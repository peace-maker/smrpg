#pragma semicolon 1
#include <sourcemod>

#define SMRPG_DB "smrpg"
#define TBL_PLAYERS "players"
#define TBL_PLAYERUPGRADES "player_upgrades"
#define TBL_UPGRADES "upgrades"
#define TBL_SETTINGS "settings"

#define DBVER_INIT 100       // Initial database version
#define DBVER_UPDATE_1 101   // Update 01.09.2014. Store steamids in accountid form instead of STEAM_X:Y:Z (steamid column varchar -> int)
#define DBVER_UPDATE_2 102   // Update 16.01.2018. Change table character set to utf8mb4 to allow new characters. Requires MySQL 5.5.3+.
#define DBVER_UPDATE_3 103   // Update 28.02.2018. Add foreign keys to avoid data pollution.

// Newest database version
#define DATABASE_VERSION DBVER_UPDATE_3

// How long to wait for a reconnect after a failed connection attempt to the database?
#define RECONNECT_INTERVAL 360.0

Database g_hDatabase;
Handle g_hReconnectTimer;

enum DatabaseDriver {
	Driver_None,
	Driver_MySQL,
	Driver_SQLite
};

DatabaseDriver g_DriverType;

Handle g_hfwdOnDatabaseConnected;

void RegisterDatabaseNatives()
{
	// native bool SMRPG_ResetAllPlayers(const char[] sReason, bool bHardReset=false);
	CreateNative("SMRPG_ResetAllPlayers", Native_ResetAllPlayers);
	// native void SMRPG_FlushDatabase();
	CreateNative("SMRPG_FlushDatabase", Native_FlushDatabase);
	// native void SMRPG_CheckDatabaseConnection();
	CreateNative("SMRPG_CheckDatabaseConnection", Native_CheckDatabaseConnection);
}

void RegisterDatabaseForwards()
{
	// forward void SMRPG_OnDatabaseConnected(Database database);
	g_hfwdOnDatabaseConnected = CreateGlobalForward("SMRPG_OnDatabaseConnected", ET_Ignore, Param_Cell);
}

void InitDatabase()
{
	ClearHandle(g_hReconnectTimer);
	
	if(SQL_CheckConfig(SMRPG_DB))
		Database.Connect(SQL_OnConnect, SMRPG_DB);
	else
		Database.Connect(SQL_OnConnect, "default"); // Default to 'default' section in the databases.cfg.
}

public void SQL_OnConnect(Database db, const char[] error, any data)
{
	if(db == null)
	{
		LogError("Error connecting to database (reconnecting in %.0f seconds): %s", RECONNECT_INTERVAL, error);
		ClearHandle(g_hReconnectTimer);
		g_hReconnectTimer = CreateTimer(RECONNECT_INTERVAL, Timer_ReconnectDatabase);
		return;
	}
	
	// We're good now. Don't reconnect again. Just to be sure.
	ClearHandle(g_hReconnectTimer);
	
	g_hDatabase = db;
	
	DBDriver driver = db.Driver;
	char sDriverIdent[16];
	driver.GetIdentifier(sDriverIdent, sizeof(sDriverIdent));
	
	// Set the right character set in mysql
	if(StrEqual(sDriverIdent, "mysql", false))
	{
		g_DriverType = Driver_MySQL;
		// Fallback to just utf8 until SourceMod's client libraries are updated.
		if (!g_hDatabase.SetCharset("utf8mb4"))
			g_hDatabase.SetCharset("utf8");
	}
	else if(StrEqual(sDriverIdent, "sqlite", false))
	{
		g_DriverType = Driver_SQLite;
		// Enable support for foreign keys in sqlite3.
		SQL_LockedFastQuery(g_hDatabase, "PRAGMA foreign_keys = ON");
	}
	else
	{
		SetFailState("Unknown SQL driver: %s. Aborting..", sDriverIdent);
	}
	
	// Make sure the tables are created using the correct charset, if the database was created with something else than utf8 as default.
	char sExtraOptions[64];
	if(g_DriverType == Driver_MySQL)
	{
		sExtraOptions = " ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
	}
	
	// Create the player table
	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (player_id INTEGER PRIMARY KEY %s, name VARCHAR(64) NOT NULL DEFAULT ' ', steamid INTEGER DEFAULT NULL UNIQUE, level INTEGER DEFAULT 1, experience INTEGER DEFAULT 0, credits INTEGER DEFAULT 0, showmenu INTEGER DEFAULT 1, fadescreen INTEGER DEFAULT 1, lastseen INTEGER DEFAULT 0, lastreset INTEGER DEFAULT 0)%s", TBL_PLAYERS, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"), sExtraOptions);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		char sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_PLAYERS, sError);
		return;
	}
	
	// Create the upgrades table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (upgrade_id INTEGER PRIMARY KEY %s, shortname VARCHAR(32) UNIQUE NOT NULL, date_added INTEGER)%s", TBL_UPGRADES, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"), sExtraOptions);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		char sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_UPGRADES, sError);
		return;
	}

	// Create the player -> upgrades table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (player_id INTEGER, upgrade_id INTEGER, purchasedlevel INTEGER NOT NULL, selectedlevel INTEGER NOT NULL, enabled INTEGER DEFAULT 1, visuals INTEGER DEFAULT 1, sounds INTEGER DEFAULT 1, PRIMARY KEY(player_id, upgrade_id), FOREIGN KEY (player_id) REFERENCES %s(player_id) ON DELETE CASCADE, FOREIGN KEY (upgrade_id) REFERENCES %s(upgrade_id) ON DELETE CASCADE)%s", TBL_PLAYERUPGRADES, TBL_PLAYERS, TBL_UPGRADES, sExtraOptions);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		char sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_PLAYERUPGRADES, sError);
		return;
	}
	
	// Create the settings table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (setting VARCHAR(64) PRIMARY KEY NOT NULL, value VARCHAR(256) NOT NULL)%s", TBL_SETTINGS, sExtraOptions);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		char sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_SETTINGS, sError);
		return;
	}
	
	LoadSettingsTable();

	// This is probably empty since no upgrades could have registered yet, but well..
	// Add all columns for currently loaded upgrades.
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo];
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		if(!IsValidUpgrade(upgrade) || upgrade[UPGR_databaseId] != -1 || upgrade[UPGR_databaseLoading])
			continue;
		CheckUpgradeDatabaseEntry(upgrade);
	}
	
	// Cleanup our database.
	DatabaseMaid();
	
	// Add all already connected players now
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && IsClientAuthorized(i))
		{
			AddPlayer(i);
		}
	}

	// Share the handle with other plugins.
	Call_StartForward(g_hfwdOnDatabaseConnected);
	Call_PushCell(g_hDatabase);
	Call_Finish();
}

public Action Timer_ReconnectDatabase(Handle timer)
{
	// Try to connect again after it first failed on plugin load.
	g_hReconnectTimer = null;
	InitDatabase();
	return Plugin_Stop;
}

void CheckUpgradeDatabaseEntry(int upgrade[InternalUpgradeInfo])
{
	if(!g_hDatabase)
		return;
	
	upgrade[UPGR_databaseLoading] = true;
	SaveUpgradeConfig(upgrade);
	
	char sQuery[512];
	// Check if that's a completely new upgrade
	char sShortNameEscaped[MAX_UPGRADE_SHORTNAME_LENGTH*2+1];
	g_hDatabase.Escape(upgrade[UPGR_shortName], sShortNameEscaped, sizeof(sShortNameEscaped));
	Format(sQuery, sizeof(sQuery), "SELECT upgrade_id FROM %s WHERE shortname = \"%s\";", TBL_UPGRADES, sShortNameEscaped);
	g_hDatabase.Query(SQL_GetUpgradeInfo, sQuery, upgrade[UPGR_index]);
}

void CheckDatabaseVersion()
{
	char sValue[8];
	if(!GetSetting("version", sValue, sizeof(sValue)))
	{
		// There is no version field yet? Just create one, we don't know if we'd need to update something..
		IntToString(DATABASE_VERSION, sValue, sizeof(sValue));
		SetSetting("version", sValue);
		return;
	}
	
	int iVersion = StringToInt(sValue);
	if(iVersion < DATABASE_VERSION)
	{
		// Perform database updates here..
		if(iVersion < DBVER_UPDATE_1)
		{
			if(g_DriverType == Driver_MySQL)
			{
				// Save steamids as accountid integers instead of STEAM_X:Y:Z
				char sQuery[512];
				// Allow NULL as steamid value
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s CHANGE steamid steamid VARCHAR(64) CHARACTER SET utf8 COLLATE utf8_general_ci NULL", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
				
				// Set bot's steamid to NULL
				Format(sQuery, sizeof(sQuery), "UPDATE %s SET steamid = NULL WHERE steamid NOT LIKE 'STEAM_%%'", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
				
				// Convert STEAM_X:Y:Z steamids to account ids
				Format(sQuery, sizeof(sQuery), "UPDATE %s SET steamid = CAST(SUBSTRING(steamid, 9, 1) AS UNSIGNED) + CAST(SUBSTRING(steamid, 11) * 2 AS UNSIGNED) WHERE steamid LIKE 'STEAM_%%'", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
				
				// Save the steamids as integers now.
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s CHANGE steamid steamid INTEGER NULL", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
			}
			else if(g_DriverType == Driver_SQLite)
			{
				// Save steamids as accountid integers instead of STEAM_X:Y:Z
				char sQuery[512];
				// Create a new table with the changed steamid field.
				// SQLite doesn't support altering column types of existing tables.
				Format(sQuery, sizeof(sQuery), "CREATE TABLE %s_X (player_id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR(64) NOT NULL DEFAULT ' ', steamid INTEGER DEFAULT NULL UNIQUE, level INTEGER DEFAULT 1, experience INTEGER DEFAULT 0, credits INTEGER DEFAULT 0, showmenu INTEGER DEFAULT 1, fadescreen INTEGER DEFAULT 1, lastseen INTEGER DEFAULT 0, lastreset INTEGER DEFAULT 0);", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
				
				// Insert all bots with NULL steamid.
				Format(sQuery, sizeof(sQuery), "INSERT INTO %s_X SELECT player_id, name, NULL, level, experience, credits, showmenu, fadescreen, lastseen, lastreset FROM %s WHERE steamid NOT LIKE 'STEAM_%%';", TBL_PLAYERS, TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
				
				// Insert all players and convert the steamid to accountid.
				Format(sQuery, sizeof(sQuery), "INSERT INTO %s_X SELECT player_id, name, CAST(SUBSTR(steamid, 9, 1) AS INTEGER) + CAST(SUBSTR(steamid, 11) * 2 AS INTEGER), level, experience, credits, showmenu, fadescreen, lastseen, lastreset FROM %s WHERE steamid LIKE 'STEAM_%%';", TBL_PLAYERS, TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
				
				// Drop the old player table.
				Format(sQuery, sizeof(sQuery), "DROP TABLE %s;", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
				
				// Rename the copied new one to match the correct table name of the old table.
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s_X RENAME TO %s;", TBL_PLAYERS, TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_1, sQuery);
					return;
				}
			}
		}
		
		// Allow all characters in player names.
		if(iVersion < DBVER_UPDATE_2)
		{
			// MySQL only. Can't change the character set of a SQLite database after it was created. SQLite is always UTF-8 in SourceMod.
			if(g_DriverType == Driver_MySQL)
			{
				// Update the character sets of the tables.
				char sQuery[512];
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s CONVERT TO CHARACTER SET utf8mb4", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_2, sQuery);
					return;
				}
				
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s CONVERT TO CHARACTER SET utf8mb4", TBL_UPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_2, sQuery);
					return;
				}
				
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s CONVERT TO CHARACTER SET utf8mb4", TBL_PLAYERUPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_2, sQuery);
					return;
				}
				
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s CONVERT TO CHARACTER SET utf8mb4", TBL_SETTINGS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_2, sQuery);
					return;
				}
			}
		}

		if(iVersion < DBVER_UPDATE_3)
		{
			char sQuery[512];

			// Delete lines that should not exist
			Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id NOT IN (SELECT player_id FROM %s) OR upgrade_id NOT IN (SELECT upgrade_id FROM %s)", TBL_PLAYERUPGRADES, TBL_PLAYERS, TBL_UPGRADES);
			if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
			{
				FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
				return;
			}

			// Make sure the tables use an engine that supports foreign keys.
			if(g_DriverType == Driver_MySQL)
			{
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ENGINE=InnoDB", TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}
				
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ENGINE=InnoDB", TBL_UPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}
				
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ENGINE=InnoDB", TBL_PLAYERUPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}
				
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ENGINE=InnoDB", TBL_SETTINGS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}

				// Add foreign key constraint on player_id.
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ADD FOREIGN KEY (player_id) REFERENCES %s(player_id) ON DELETE CASCADE", TBL_PLAYERUPGRADES, TBL_PLAYERS);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}

				// Add foreign key constraint on upgrade_id.
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ADD FOREIGN KEY (upgrade_id) REFERENCES %s(upgrade_id) ON DELETE CASCADE", TBL_PLAYERUPGRADES, TBL_UPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}
			}
			else
			{
				// Turn off foreign keys while we change the schema.
				Format(sQuery, sizeof(sQuery), "PRAGMA foreign_keys=OFF");
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}

				// Rename table to keep old data.
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s RENAME TO %s_old", TBL_PLAYERUPGRADES, TBL_PLAYERUPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}

				// Recreate table with foreign key constraints to avoid data pollution.
				Format(sQuery, sizeof(sQuery), "CREATE TABLE %s (player_id INTEGER, upgrade_id INTEGER, purchasedlevel INTEGER NOT NULL, selectedlevel INTEGER NOT NULL, enabled INTEGER DEFAULT 1, visuals INTEGER DEFAULT 1, sounds INTEGER DEFAULT 1, PRIMARY KEY(player_id, upgrade_id), FOREIGN KEY (player_id) REFERENCES %s(player_id) ON DELETE CASCADE, FOREIGN KEY (upgrade_id) REFERENCES %s(upgrade_id) ON DELETE CASCADE)", TBL_PLAYERUPGRADES, TBL_PLAYERS, TBL_UPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}

				// Restore old data.
				Format(sQuery, sizeof(sQuery), "INSERT INTO %s SELECT * FROM %s_old", TBL_PLAYERUPGRADES, TBL_PLAYERUPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}

				// Get rid of the old table.
				Format(sQuery, sizeof(sQuery), "DROP TABLE %s_old", TBL_PLAYERUPGRADES);
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}

				// Enable foreign key constraints now.
				Format(sQuery, sizeof(sQuery), "PRAGMA foreign_keys=ON");
				if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
				{
					FailDatabaseUpdateError(DBVER_UPDATE_3, sQuery);
					return;
				}
			}
			
			LogMessage("Updated database schema to version %d", DATABASE_VERSION);
		}
		
		// We're on a higher version now.
		IntToString(DATABASE_VERSION, sValue, sizeof(sValue));
		SetSetting("version", sValue);
	}
	else if(iVersion > DATABASE_VERSION)
	{
		LogError("Database version %d is newer than supported by this plugin (%d). There might be problems with incompatible database structures!", iVersion, DATABASE_VERSION);
	}
}

void FailDatabaseUpdateError(int iVersion, const char[] sQuery)
{
	char sError[256];
	SQL_GetError(g_hDatabase, sError, sizeof(sError));
	SetFailState("Failed to update the database to version %d. The plugin might not run correctly. Query: %s    Error: %s", iVersion, sQuery, sError);
}

void DatabaseMaid()
{
	if(!g_hDatabase)
		return;
	
	// Don't touch the database, if we don't want to save any data.
	if(!g_hCVSaveData.BoolValue)
		return;
	
	char sQuery[256];
	// Have players expire after x days and delete them from the database?
	if(g_hCVPlayerExpire.IntValue > 0)
	{
		Format(sQuery, sizeof(sQuery), "OR lastseen <= %d", GetTime()-(86400*g_hCVPlayerExpire.IntValue));
	}
	
	// Delete players who are Level 1 and haven't played for 3 days
	Format(sQuery, sizeof(sQuery), "SELECT player_id FROM %s WHERE (level <= 1 AND lastseen <= %d) %s", TBL_PLAYERS, GetTime()-259200, sQuery);
	g_hDatabase.Query(SQL_DeleteExpiredPlayers, sQuery);
	
	// Reduce sqlite database file size.
	if(g_DriverType == Driver_SQLite)
	{
		Format(sQuery, sizeof(sQuery), "VACUUM");
		SQL_LockedFastQuery(g_hDatabase, sQuery);
	}
}

// Natives
public int Native_ResetAllPlayers(Handle plugin, int numParams)
{
	if(!g_hDatabase)
		return false;
	
	// Don't touch the database, if we don't want to save any data.
	if(!g_hCVSaveData.BoolValue)
		return false;
	
	char sReason[256];
	GetNativeString(1, sReason, sizeof(sReason));
	
	bool bHardReset = view_as<bool>(GetNativeCell(2));
	char sQuery[512];

	// Delete all player information?
	if(bHardReset)
	{
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s", TBL_PLAYERS);
		g_hDatabase.Query(SQL_DoNothing, sQuery);
		
		// Reset all ingame players and readd them into the database.
		for(int i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				// Keep the original bot names intact, to avoid saving renamed bots.
				RemovePlayer(i, true);
				InitPlayer(i, false);
				if (IsClientAuthorized(i))
					InsertPlayer(i);
			}
		}
	}
	// Keep the player settings
	else
	{
		Transaction hTransaction = new Transaction();
		Format(sQuery, sizeof(sQuery), "UPDATE %s SET level = 1, experience = 0, credits = %d, lastreset = %d", TBL_PLAYERS, g_hCVCreditsStart.IntValue, GetTime());
		hTransaction.AddQuery(sQuery);
		Format(sQuery, sizeof(sQuery), "UPDATE %s SET purchasedlevel = 0, selectedlevel = 0, enabled = 1", TBL_PLAYERUPGRADES);
		hTransaction.AddQuery(sQuery);
		g_hDatabase.Execute(hTransaction, _, SQLTxn_LogFailure);
		
		// Just reset all ingame players too
		for(int i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				ResetStats(i);
				SetPlayerLastReset(i, GetTime());
			}
		}
	}
	
	// Remember when we last reset the database.
	IntToString(GetTime(), sQuery, sizeof(sQuery));
	SetSetting("last_reset", sQuery);
	
	// Save the passed reason.
	SetSetting("reset_reason", sReason);
	
	return true;
}

public int Native_FlushDatabase(Handle plugin, int numParams)
{
	// Flush all info into the database. This handles smrpg_save_data and smrpg_enable
	SaveAllPlayers();
}

public int Native_CheckDatabaseConnection(Handle plugin, int numParams)
{
	if(!g_hDatabase)
		return;

	// Call the global forward callback ONLY in the calling plugin.
	Function funOnDatabaseConnected = GetFunctionByName(plugin, "SMRPG_OnDatabaseConnected");
	if(funOnDatabaseConnected == INVALID_FUNCTION)
		return;

	Call_StartFunction(plugin, funOnDatabaseConnected);
	Call_PushCell(g_hDatabase);
	Call_Finish();
}

public void SQL_DoNothing(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Error executing query: %s", error);
	}
}

public void SQLTxn_LogFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Error executing query %d of %d queries: %s", failIndex, numQueries, error);
}

public void SQL_GetUpgradeInfo(Database db, DBResultSet results, const char[] error, any index)
{
	if(results == null)
	{
		LogError("Error checking for upgrade info: %s", error);
		return;
	}
	
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(index, upgrade);
	
	char sQuery[256];
	// This is a new upgrade!
	if(!results.RowCount || !results.FetchRow())
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO %s (shortname, date_added) VALUES (\"%s\", %d);", TBL_UPGRADES, upgrade[UPGR_shortName], GetTime());
		g_hDatabase.Query(SQL_InsertNewUpgrade, sQuery, index);
		return;
	}
	
	upgrade[UPGR_databaseLoading] = false;
	upgrade[UPGR_databaseId] = results.FetchInt(0);
	SaveUpgradeConfig(upgrade);
	
	// Load the data for all connected players
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i) && GetClientDatabaseId(i) != -1)
		{
			Format(sQuery, sizeof(sQuery), "SELECT upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds FROM %s WHERE player_id = %d AND upgrade_id = %d", TBL_PLAYERUPGRADES, GetClientDatabaseId(i), upgrade[UPGR_databaseId]);
			g_hDatabase.Query(SQL_GetPlayerUpgrades, sQuery, GetClientUserId(i));
		}
	}
}

public void SQL_InsertNewUpgrade(Database db, DBResultSet results, const char[] error, any index)
{
	if(results == null)
	{
		LogError("Error inserting new upgrade info: %s", error);
		return;
	}
	
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(index, upgrade);
	
	upgrade[UPGR_databaseLoading] = false;
	upgrade[UPGR_databaseId] = results.InsertId;
	SaveUpgradeConfig(upgrade);
}

// Delete all players which weren't seen on the server for too a long time.
public void SQL_DeleteExpiredPlayers(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("DatabaseMaid: player expire query failed: %s", error);
		return;
	}
	
	// Delete them at once.
	Transaction hTransaction = new Transaction();
	
	int iPlayerId;
	char sQuery[128];
	while(results.MoreRows)
	{
		if(!results.FetchRow())
			continue;
		
		iPlayerId = results.FetchInt(0);
		
		// Don't delete players who are connected right now.
		if (GetClientByPlayerID(iPlayerId) != -1)
			continue;
		
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = %d", TBL_PLAYERS, iPlayerId);
		hTransaction.AddQuery(sQuery);
	}
	
	g_hDatabase.Execute(hTransaction, _, SQLTxn_LogFailure);
}

/**
 * Executes a query and ignores the result set.
 * Locks the database connection to avoid problems with threaded queries ran at the same time.
 *
 * @param database		A database Handle.
 * @param query			Query string.
 * @param len			Optional parameter to specify the query length, in 
 *						bytes.  This can be used to send binary queries that 
 * 						have a premature terminator.
 * @return				True if query succeeded, false otherwise.  Use
 *						SQL_GetError to find the last error.
 * @error				Invalid database Handle.
 */
stock bool SQL_LockedFastQuery(Database database, const char[] query, int len=-1)
{
	SQL_LockDatabase(database);
	bool bSuccess = SQL_FastQuery(database, query, len);
	SQL_UnlockDatabase(database);
	return bSuccess;
}