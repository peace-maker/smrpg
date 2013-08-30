#pragma semicolon 1
#include <sourcemod>

#define SMRPG_DB "smrpg"
#define TBL_PLAYERS "players"
#define TBL_UPGRADES "upgrades"

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
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (player_id INTEGER PRIMARY KEY %s, name VARCHAR(64) NOT NULL DEFAULT ' ', steamid VARCHAR(64) NOT NULL DEFAULT '0' UNIQUE, level INTEGER DEFAULT '1', experience INTEGER DEFAULT '0', credits INTEGER DEFAULT '0', lastseen INTEGER DEFAULT '0', upgrades_id INTEGER DEFAULT '-1')", TBL_PLAYERS, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"));
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_PLAYERS, sError);
		return;
	}
	
	// Create the upgrades table.
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS %s (upgrades_id INTEGER PRIMARY KEY %s)", TBL_UPGRADES, (g_DriverType == Driver_MySQL ? "AUTO_INCREMENT" : "AUTOINCREMENT"));
	if(!SQL_LockedFastQuery(g_hDatabase, sQuery))
	{
		decl String:sError[256];
		SQL_GetError(g_hDatabase, sError, sizeof(sError));
		SetFailState("Error creating %s table: %s", TBL_UPGRADES, sError);
		return;
	}

	// This is probably empty since no upgrades could have registered yet, but well..
	// Add all columns for currently loaded upgrades.
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		if(!IsValidUpgrade(upgrade))
			continue;
		CheckUpgradeDatabaseField(upgrade[UPGR_shortName]);
	}
	
	// Cleanup or database.
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

CheckUpgradeDatabaseField(const String:sShortName[])
{
	if(!g_hDatabase)
		return;
	
	decl String:sQuery[512];
	// If that's a completely new upgrade, add a column to the upgrades table
	Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ADD COLUMN %s INTEGER DEFAULT '0'", TBL_UPGRADES, sShortName);
	SQL_LockedFastQuery(g_hDatabase, sQuery);
	
	
	// Load the data for all connected players
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i) && GetClientDatabaseUpgradesId(i) != -1)
		{
			Format(sQuery, sizeof(sQuery), "SELECT %s FROM %s WHERE upgrades_id = %d", sShortName, TBL_UPGRADES, GetClientDatabaseUpgradesId(i));
			SQL_TQuery(g_hDatabase, SQL_GetPlayerItems, sQuery, GetClientUserId(i));
		}
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
	Format(sQuery, sizeof(sQuery), "SELECT player_id, upgrades_id FROM %s WHERE (level <= '1' AND lastseen <= '%d') %s", TBL_PLAYERS, GetTime()-259200, sQuery);
	SQL_LockDatabase(g_hDatabase);
	new Handle:hResult = SQL_Query(g_hDatabase, sQuery);
	SQL_UnlockDatabase(g_hDatabase);
	if(hResult != INVALID_HANDLE)
	{
		
		new iPlayerId, iUpgradeId;
		while(SQL_MoreRows(hResult))
		{
			if(!SQL_FetchRow(hResult))
				continue;
			
			iPlayerId = SQL_FetchInt(hResult, 0);
			iUpgradeId = SQL_FetchInt(hResult, 1);
			
			Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = '%d'", TBL_PLAYERS, iPlayerId);
			SQL_LockedFastQuery(g_hDatabase, sQuery);
			
			if(iUpgradeId != -1)
			{
				Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE upgrades_id = '%d'", TBL_UPGRADES, iUpgradeId);
				SQL_LockedFastQuery(g_hDatabase, sQuery);
			}
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