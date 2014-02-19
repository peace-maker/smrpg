#pragma semicolon 1
#include <sourcemod>

#define SMRPG_DB "smrpg"
#define TBL_PLAYERS "players"
#define TBL_PLAYERUPGRADES "player_upgrades"
#define TBL_UPGRADES "upgrades"
#define TBL_SETTINGS "settings"

#define DATABASE_VERSION 100

new Handle:g_hDatabase;
new g_iSequence = -1;

enum DatabaseDriver {
	Driver_None,
	Driver_MySQL,
	Driver_SQLite
};

new DatabaseDriver:g_DriverType;

InitDatabase()
{
	if(SQL_CheckConfig(SMRPG_DB))
		SQL_TConnect(SQL_OnConnect, SMRPG_DB, ++g_iSequence);
	else
		SQL_TConnect(SQL_OnConnect, "default", ++g_iSequence); // Default to 'default' section in the databases.cfg.
}

public SQL_OnConnect(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		SetFailState("Error initializing database: %s", error);
		return;
	}
	
	// Ignore old connection attempts.
	if(g_iSequence != data)
	{
		CloseHandle(hndl);
		return;
	}
	
	g_hDatabase = hndl;
	
	new String:sDriverIdent[16];
	SQL_GetDriverIdent(owner, sDriverIdent, sizeof(sDriverIdent));
	
	// Set the right character set in mysql
	if(StrEqual(sDriverIdent, "mysql", false))
	{
		g_DriverType = Driver_MySQL;
		if(GetFeatureStatus(FeatureType_Native, "SQL_SetCharset") == FeatureStatus_Available)
			SQL_SetCharset(g_hDatabase, "utf8");
		else
			SQL_LockedFastQuery(g_hDatabase, "SET NAMES 'UTF8'");
	}
	else
		g_DriverType = Driver_SQLite;
	
	// Create the player table
	decl String:sQuery[1024];
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (player_id INTEGER PRIMARY KEY %s, name VARCHAR(64) NOT NULL DEFAULT ' ', steamid VARCHAR(64) NOT NULL DEFAULT '0' UNIQUE, level INTEGER DEFAULT '1', experience INTEGER DEFAULT '0', credits INTEGER DEFAULT '0', lastseen INTEGER DEFAULT '0', lastreset INTEGER DEFAULT '0')", TBL_PLAYERS, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"));
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_PLAYERS, sError);
		return;
	}
	
	// Create the player -> upgrades table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (player_id INTEGER, upgrade_id INTEGER, level INTEGER NOT NULL, currentlevel INTEGER NOT NULL, enabled INTEGER DEFAULT '1', visuals INTEGER DEFAULT '1', sounds INTEGER DEFAULT '1', PRIMARY KEY(player_id, upgrade_id))", TBL_PLAYERUPGRADES);
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_PLAYERUPGRADES, sError);
		return;
	}
	
	// Create the upgrades table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (upgrade_id INTEGER PRIMARY KEY %s, shortname VARCHAR(32) UNIQUE NOT NULL, date_added INTEGER)", TBL_UPGRADES, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"));
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_UPGRADES, sError);
		return;
	}
	
	// Create the settings table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (setting VARCHAR(64) PRIMARY KEY NOT NULL, value VARCHAR(256) NOT NULL)", TBL_SETTINGS);
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
	decl String:sAuthId[32];
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && IsClientAuthorized(i) && GetClientAuthString(i, sAuthId, sizeof(sAuthId)))
		{
			AddPlayer(i, sAuthId);
		}
	}
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
		IntToString(DATABASE_VERSION, sValue, sizeof(sValue));
		SetSetting("version", sValue);
	}
	else if(iVersion > DATABASE_VERSION)
	{
		LogError("Database version %d is newer than supported by this plugin (%d). There might be problems with incompatible database structures!", iVersion, DATABASE_VERSION);
	}
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
		Format(sQuery, sizeof(sQuery), "OR lastseen <= '%d'", GetTime()-(86400*GetConVarInt(g_hCVPlayerExpire)));
	}
	
	// Delete players who are Level 1 and haven't played for 3 days
	Format(sQuery, sizeof(sQuery), "SELECT player_id FROM %s WHERE (level <= '1' AND lastseen <= '%d') %s", TBL_PLAYERS, GetTime()-259200, sQuery);
	SQL_LockDatabase(g_hDatabase);
	new Handle:hResult = SQL_Query(g_hDatabase, sQuery);
	SQL_UnlockDatabase(g_hDatabase);
	if(hResult != INVALID_HANDLE)
	{
		new iPlayerId;
		while(SQL_MoreRows(hResult))
		{
			if(!SQL_FetchRow(hResult))
				continue;
			
			iPlayerId = SQL_FetchInt(hResult, 0);
			
			Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = '%d'", TBL_PLAYERUPGRADES, iPlayerId);
			SQL_LockedFastQuery(g_hDatabase, sQuery);
			
			Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = '%d'", TBL_PLAYERS, iPlayerId);
			SQL_LockedFastQuery(g_hDatabase, sQuery);
		}
		CloseHandle(hResult);
	}
	else
	{
		LogError("DatabaseMaid: player expire query failed");
	}
	
	// Reduce sqlite database file size.
	if(g_DriverType == Driver_SQLite)
	{
		Format(sQuery, sizeof(sQuery), "VACUUM");
		SQL_LockedFastQuery(g_hDatabase, sQuery);
	}
}

public SQL_DoNothing(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error executing query: %s", error);
	}
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
			Format(sQuery, sizeof(sQuery), "SELECT * FROM %s WHERE player_id = %d AND upgrade_id = %d", TBL_PLAYERUPGRADES, GetClientDatabaseId(i), upgrade[UPGR_databaseId]);
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