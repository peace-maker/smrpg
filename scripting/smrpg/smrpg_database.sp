#pragma semicolon 1
#include <sourcemod>

#define SMRPG_DB "smrpg"
#define TBL_PLAYERS "players"
#define TBL_PLAYERUPGRADES "player_upgrades"
#define TBL_UPGRADES "upgrades"
#define TBL_SETTINGS "settings"

#define DBVER_INIT 100       // Initial database version
#define DBVER_UPDATE_1 101   // Update 01.09.2014. Store steamids in accountid form instead of STEAM_X:Y:Z (steamid column varchar -> int)

// Newest database version
#define DATABASE_VERSION DBVER_UPDATE_1

// How long to wait for a reconnect after a failed connection attempt to the database?
#define RECONNECT_INTERVAL 360.0

new Handle:g_hDatabase;
new Handle:g_hReconnectTimer;

enum DatabaseDriver {
	Driver_None,
	Driver_MySQL,
	Driver_SQLite
};

new DatabaseDriver:g_DriverType;

RegisterDatabaseNatives()
{
	// native bool:SMRPG_ResetAllPlayers(const String:sReason[], bool:bHardReset=false);
	CreateNative("SMRPG_ResetAllPlayers", Native_ResetAllPlayers);
	// native SMRPG_FlushDatabase();
	CreateNative("SMRPG_FlushDatabase", Native_FlushDatabase);
}

InitDatabase()
{
	ClearHandle(g_hReconnectTimer);
	
	if(SQL_CheckConfig(SMRPG_DB))
		SQL_TConnect(SQL_OnConnect, SMRPG_DB);
	else
		SQL_TConnect(SQL_OnConnect, "default"); // Default to 'default' section in the databases.cfg.
}

public SQL_OnConnect(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("Error connecting to database (reconnecting in %.0f seconds): %s", RECONNECT_INTERVAL, error);
		ClearHandle(g_hReconnectTimer);
		g_hReconnectTimer = CreateTimer(RECONNECT_INTERVAL, Timer_ReconnectDatabase);
		return;
	}
	
	// We're good now. Don't reconnect again. Just to be sure.
	ClearHandle(g_hReconnectTimer);
	
	g_hDatabase = hndl;
	
	new String:sDriverIdent[16];
	SQL_GetDriverIdent(owner, sDriverIdent, sizeof(sDriverIdent));
	
	// Set the right character set in mysql
	if(StrEqual(sDriverIdent, "mysql", false))
	{
		g_DriverType = Driver_MySQL;
		SQL_SetCharset(g_hDatabase, "utf8");
	}
	else if(StrEqual(sDriverIdent, "sqlite", false))
	{
		g_DriverType = Driver_SQLite;
	}
	else
	{
		SetFailState("Unknown SQL driver: %s. Aborting..", sDriverIdent);
	}
	
	// Make sure the tables are created using the correct charset, if the database was created with something else than utf8 as default.
	new String:sDefaultCharset[32];
	if(g_DriverType == Driver_MySQL)
	{
		strcopy(sDefaultCharset, sizeof(sDefaultCharset), " DEFAULT CHARSET=utf8");
	}
	
	// Create the player table
	decl String:sQuery[1024];
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (player_id INTEGER PRIMARY KEY %s, name VARCHAR(64) NOT NULL DEFAULT ' ', steamid INTEGER DEFAULT NULL UNIQUE, level INTEGER DEFAULT 1, experience INTEGER DEFAULT 0, credits INTEGER DEFAULT 0, showmenu INTEGER DEFAULT 1, fadescreen INTEGER DEFAULT 1, lastseen INTEGER DEFAULT 0, lastreset INTEGER DEFAULT 0)%s", TBL_PLAYERS, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"), sDefaultCharset);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_PLAYERS, sError);
		return;
	}
	
	// Create the player -> upgrades table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (player_id INTEGER, upgrade_id INTEGER, purchasedlevel INTEGER NOT NULL, selectedlevel INTEGER NOT NULL, enabled INTEGER DEFAULT 1, visuals INTEGER DEFAULT 1, sounds INTEGER DEFAULT 1, PRIMARY KEY(player_id, upgrade_id))%s", TBL_PLAYERUPGRADES, sDefaultCharset);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_PLAYERUPGRADES, sError);
		return;
	}
	
	// Create the upgrades table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (upgrade_id INTEGER PRIMARY KEY %s, shortname VARCHAR(32) UNIQUE NOT NULL, date_added INTEGER)%s", TBL_UPGRADES, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"), sDefaultCharset);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_UPGRADES, sError);
		return;
	}
	
	// Create the settings table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (setting VARCHAR(64) PRIMARY KEY NOT NULL, value VARCHAR(256) NOT NULL)%s", TBL_SETTINGS, sDefaultCharset);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_SETTINGS, sError);
		return;
	}
	
	LoadSettingsTable();

	// This is probably empty since no upgrades could have registered yet, but well..
	// Add all columns for currently loaded upgrades.
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		if(!IsValidUpgrade(upgrade) || upgrade[UPGR_databaseId] != -1 || upgrade[UPGR_databaseLoading])
			continue;
		CheckUpgradeDatabaseEntry(upgrade);
	}
	
	// Cleanup our database.
	DatabaseMaid();
	
	// Add all already connected players now
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && IsClientAuthorized(i))
		{
			AddPlayer(i);
		}
	}
}

public Action:Timer_ReconnectDatabase(Handle:timer)
{
	// Try to connect again after it first failed on plugin load.
	g_hReconnectTimer = INVALID_HANDLE;
	InitDatabase();
	return Plugin_Stop;
}

CheckUpgradeDatabaseEntry(upgrade[InternalUpgradeInfo])
{
	if(!g_hDatabase)
		return;
	
	upgrade[UPGR_databaseLoading] = true;
	SaveUpgradeConfig(upgrade);
	
	decl String:sQuery[512];
	// Check if that's a completely new upgrade
	decl String:sShortNameEscaped[MAX_UPGRADE_SHORTNAME_LENGTH*2+1];
	SQL_EscapeString(g_hDatabase, upgrade[UPGR_shortName], sShortNameEscaped, sizeof(sShortNameEscaped));
	Format(sQuery, sizeof(sQuery), "SELECT upgrade_id FROM %s WHERE shortname = \"%s\";", TBL_UPGRADES, sShortNameEscaped);
	SQL_TQuery(g_hDatabase, SQL_GetUpgradeInfo, sQuery, upgrade[UPGR_index]);
}

CheckDatabaseVersion()
{
	decl String:sValue[8];
	if(!GetSetting("version", sValue, sizeof(sValue)))
	{
		// There is no version field yet? Just create one, we don't know if we'd need to update something..
		IntToString(DATABASE_VERSION, sValue, sizeof(sValue));
		SetSetting("version", sValue);
		return;
	}
	
	new iVersion = StringToInt(sValue);
	if(iVersion < DATABASE_VERSION)
	{
		// Perform database updates here..
		if(iVersion < DBVER_UPDATE_1)
		{
			if(g_DriverType == Driver_MySQL)
			{
				// Save steamids as accountid integers instead of STEAM_X:Y:Z
				decl String:sQuery[512];
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
				decl String:sQuery[512];
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
		
		// We're on a higher version now.
		IntToString(DATABASE_VERSION, sValue, sizeof(sValue));
		SetSetting("version", sValue);
	}
	else if(iVersion > DATABASE_VERSION)
	{
		LogError("Database version %d is newer than supported by this plugin (%d). There might be problems with incompatible database structures!", iVersion, DATABASE_VERSION);
	}
}

FailDatabaseUpdateError(iVersion, const String:sQuery[])
{
	decl String:sError[256];
	SQL_GetError(g_hDatabase, sError, sizeof(sError));
	SetFailState("Failed to update the database to version %d. The plugin might not run correctly. Query: %s    Error: %s", iVersion, sQuery, sError);
}

DatabaseMaid()
{
	if(!g_hDatabase)
		return;
	
	// Don't touch the database, if we don't want to save any data.
	if(!GetConVarBool(g_hCVSaveData))
		return;
	
	new String:sQuery[256];
	// Have players expire after x days and delete them from the database?
	if(GetConVarInt(g_hCVPlayerExpire) > 0)
	{
		Format(sQuery, sizeof(sQuery), "OR lastseen <= %d", GetTime()-(86400*GetConVarInt(g_hCVPlayerExpire)));
	}
	
	// Delete players who are Level 1 and haven't played for 3 days
	Format(sQuery, sizeof(sQuery), "SELECT player_id FROM %s WHERE (level <= 1 AND lastseen <= %d) %s", TBL_PLAYERS, GetTime()-259200, sQuery);
	SQL_TQuery(g_hDatabase, SQL_DeleteExpiredPlayers, sQuery);
	
	// Reduce sqlite database file size.
	if(g_DriverType == Driver_SQLite)
	{
		Format(sQuery, sizeof(sQuery), "VACUUM");
		SQL_LockedFastQuery(g_hDatabase, sQuery);
	}
}

// Natives
public Native_ResetAllPlayers(Handle:plugin, numParams)
{
	if(!g_hDatabase)
		return false;
	
	// Don't touch the database, if we don't want to save any data.
	if(!GetConVarBool(g_hCVSaveData))
		return false;
	
	new String:sReason[256];
	GetNativeString(1, sReason, sizeof(sReason));
	
	new bool:bHardReset = bool:GetNativeCell(2);
	decl String:sQuery[512];

	// Delete all player information?
	if(bHardReset)
	{
		new Transaction:hTransaction = SQL_CreateTransaction();
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s", TBL_PLAYERUPGRADES);
		SQL_AddQuery(hTransaction, sQuery);
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s", TBL_PLAYERS);
		SQL_AddQuery(hTransaction, sQuery);
		SQL_ExecuteTransaction(g_hDatabase, hTransaction, _, SQLTxn_LogFailure);
		
		// Reset all ingame players and readd them into the database.
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				// Keep the original bot names intact, to avoid saving renamed bots.
				RemovePlayer(i, true);
				InitPlayer(i, false);
				InsertPlayer(i);
			}
		}
	}
	// Keep the player settings
	else
	{
		new Transaction:hTransaction = SQL_CreateTransaction();
		Format(sQuery, sizeof(sQuery), "UPDATE %s SET level = 1, experience = 0, credits = %d, lastreset = %d", TBL_PLAYERS, GetConVarInt(g_hCVCreditsStart), GetTime());
		SQL_AddQuery(hTransaction, sQuery);
		Format(sQuery, sizeof(sQuery), "UPDATE %s SET purchasedlevel = 0, selectedlevel = 0, enabled = 1", TBL_PLAYERUPGRADES);
		SQL_AddQuery(hTransaction, sQuery);
		SQL_ExecuteTransaction(g_hDatabase, hTransaction, _, SQLTxn_LogFailure);
		
		// Just reset all ingame players too
		for(new i=1;i<=MaxClients;i++)
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

public Native_FlushDatabase(Handle:plugin, numParams)
{
	// Flush all info into the database. This handles smrpg_save_data and smrpg_enable
	SaveAllPlayers();
}

public SQL_DoNothing(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error executing query: %s", error);
	}
}

public SQLTxn_LogFailure(Handle:db, any:data, numQueries, const String:error[], failIndex, any:queryData[])
{
	LogError("Error executing query %d of %d queries: %s", failIndex, numQueries, error);
}

public SQL_GetUpgradeInfo(Handle:owner, Handle:hndl, const String:error[], any:index)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error checking for upgrade info: %s", error);
		return;
	}
	
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(index, upgrade);
	
	decl String:sQuery[256];
	// This is a new upgrade!
	if(!SQL_GetRowCount(hndl) || !SQL_FetchRow(hndl))
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO %s (shortname, date_added) VALUES (\"%s\", %d);", TBL_UPGRADES, upgrade[UPGR_shortName], GetTime());
		SQL_TQuery(g_hDatabase, SQL_InsertNewUpgrade, sQuery, index);
		return;
	}
	
	upgrade[UPGR_databaseLoading] = false;
	upgrade[UPGR_databaseId] = SQL_FetchInt(hndl, 0);
	SaveUpgradeConfig(upgrade);
	
	// Load the data for all connected players
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i) && GetClientDatabaseId(i) != -1)
		{
			Format(sQuery, sizeof(sQuery), "SELECT upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds FROM %s WHERE player_id = %d AND upgrade_id = %d", TBL_PLAYERUPGRADES, GetClientDatabaseId(i), upgrade[UPGR_databaseId]);
			SQL_TQuery(g_hDatabase, SQL_GetPlayerUpgrades, sQuery, GetClientUserId(i));
		}
	}
}

public SQL_InsertNewUpgrade(Handle:owner, Handle:hndl, const String:error[], any:index)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error inserting new upgrade info: %s", error);
		return;
	}
	
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(index, upgrade);
	
	upgrade[UPGR_databaseLoading] = false;
	upgrade[UPGR_databaseId] = SQL_GetInsertId(owner);
	SaveUpgradeConfig(upgrade);
}

// Delete all players which weren't seen on the server for too a long time.
public SQL_DeleteExpiredPlayers(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("DatabaseMaid: player expire query failed: %s", error);
	}
	
	// Delete them at once.
	new Transaction:hTransaction = SQL_CreateTransaction();
	
	new iPlayerId, String:sQuery[128];
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		iPlayerId = SQL_FetchInt(hndl, 0);
		
		// Don't delete players who are connected right now.
		if (GetClientByPlayerID(iPlayerId) != -1)
			continue;
		
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = %d", TBL_PLAYERUPGRADES, iPlayerId);
		SQL_AddQuery(hTransaction, sQuery);
		
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = %d", TBL_PLAYERS, iPlayerId);
		SQL_AddQuery(hTransaction, sQuery);
	}
	
	SQL_ExecuteTransaction(g_hDatabase, hTransaction, _, SQLTxn_LogFailure);
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
stock bool:SQL_LockedFastQuery(Handle:database, const String:query[], len=-1)
{
	SQL_LockDatabase(database);
	new bool:bSuccess = SQL_FastQuery(database, query, len);
	SQL_UnlockDatabase(database);
	return bSuccess;
}