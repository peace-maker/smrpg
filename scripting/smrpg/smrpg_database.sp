#pragma semicolon 1
#include <sourcemod>

#define CSSRPG_DB "cssrpg"
#define TBL_PLAYERS "players"
#define TBL_UPGRADES "upgrades"

// CSSRPG Database stuff
new Handle:g_hDatabase;

new String:player_cols[][] = {
	"player_id INTEGER PRIMARY KEY AUTOINCREMENT",
	"name TEXT DEFAULT ' '",
	"steamid TEXT DEFAULT '0' UNIQUE",
	"level INTEGER DEFAULT '1'",
	"experience INTEGER DEFAULT '0'",
	"credits INTEGER DEFAULT '0'",
	"lastseen INTEGER DEFAULT '0'",
	"upgrades_id INTEGER DEFAULT '-1'"
};

new String:player_col_types[][] = {"player_id", "name", "steamid", "level", "experience", "credits", "lastseen", "upgrades_id"};

InitDatabase()
{
	decl String:sError[256];
	g_hDatabase = SQLite_UseDatabase(CSSRPG_DB, sError, sizeof(sError));
	if(g_hDatabase == INVALID_HANDLE)
		SetFailState("Error initializing database: %s", sError);
	
	new result = SQLiteTableExists(TBL_PLAYERS);
	if(!result)
	{
		decl String:sQuery[1024];
		for(new i=0;i<sizeof(player_cols);i++)
		{
			if(i)
				Format(sQuery, sizeof(sQuery), "%s, %s", sQuery, player_cols[i]);
			else
				Format(sQuery, sizeof(sQuery), "%s", player_cols[i]);
		}
		
		Format(sQuery, sizeof(sQuery), "CREATE TABLE %s (%s)", TBL_PLAYERS, sQuery);
		SQL_LockedFastQuery(g_hDatabase, sQuery);
	}
	else if(result == 1)
	{
		decl String:sQuery[256];
		for(new i=0;i<sizeof(player_cols);i++)
		{
			if(!SQLiteColumnExists(player_col_types[i], TBL_PLAYERS))
			{
				Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ADD COLUMN %s", TBL_PLAYERS, player_cols[i]);
				SQL_LockedFastQuery(g_hDatabase, sQuery);
			}
		}
	}
	
	result = SQLiteTableExists(TBL_UPGRADES);
	if(!result)
	{
		decl String:sQuery[1024];
		Format(sQuery, sizeof(sQuery), "upgrades_id INTEGER PRIMARY KEY AUTOINCREMENT");
		new iSize = GetUpgradeCount();
		new upgrade[InternalUpgradeInfo];
		for(new i=0;i<iSize;i++)
		{
			GetUpgradeByIndex(i, upgrade);
			Format(sQuery, sizeof(sQuery), "%s, %s INTEGER DEFAULT '0'", sQuery, upgrade[UPGR_shortName]);
		}
		
		Format(sQuery, sizeof(sQuery), "CREATE TABLE %s (%s)", TBL_UPGRADES, sQuery);
		SQL_LockedFastQuery(g_hDatabase, sQuery);
	}
	else if(result == 1)
	{
		
		new iSize = GetUpgradeCount();
		new upgrade[InternalUpgradeInfo];
		for(new i=0;i<iSize;i++)
		{
			GetUpgradeByIndex(i, upgrade);
			CheckUpgradeDatabaseField(upgrade[UPGR_shortName]);
		}
	}
}

CheckUpgradeDatabaseField(String:sShortName[])
{
	new result = SQLiteColumnExists(sShortName, TBL_UPGRADES);
	decl String:sQuery[512];
	// That's a completely new upgrade! Add a column to the upgrade table
	if(!result)
	{
		Format(sQuery, sizeof(sQuery), "ALTER TABLE %s ADD COLUMN %s INTEGER DEFAULT '0'", TBL_UPGRADES, sShortName);
		SQL_LockedFastQuery(g_hDatabase, sQuery);
	}
	// This one is already there. Load the data for all connected players
	else if(result == 1)
	{
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i) && IsClientAuthorized(i) && GetClientDatabaseUpgradesId(i) != -1)
			{
				Format(sQuery, sizeof(sQuery), "SELECT %s FROM %s WHERE upgrades_id = %d", sShortName, TBL_UPGRADES, GetClientDatabaseUpgradesId(i));
				SQL_TQuery(g_hDatabase, SQL_GetPlayerItems, sQuery, GetClientUserId(i));
			}
		}
	}
}

DatabaseMaid()
{
	if(!GetConVarBool(g_hCVSaveData))
		return;
	
	decl String:sQuery[256];
	
	/* Delete players who are Level 1 and haven't played for 3 days */
	Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE level <= '1' AND lastseen <= '%d'", TBL_PLAYERS, GetTime()-259200);
	SQL_LockedFastQuery(g_hDatabase, sQuery);
	
	if(GetConVarInt(g_hCVPlayerExpire) > 0)
	{
		Format(sQuery, sizeof(sQuery), "SELECT upgrades_id FROM %s WHERE lastseen <= '%d'", TBL_PLAYERS, GetTime()-(86400*GetConVarInt(g_hCVPlayerExpire)));
		SQL_LockDatabase(g_hDatabase);
		new Handle:hResult = SQL_Query(g_hDatabase, sQuery);
		SQL_UnlockDatabase(g_hDatabase);
		if(hResult != INVALID_HANDLE)
		{
			while(SQL_MoreRows(hResult))
			{
				SQL_FetchRow(hResult);
				Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE upgrades_id = '%d'", TBL_UPGRADES, SQL_FetchInt(hResult, 0));
				SQL_LockedFastQuery(g_hDatabase, sQuery);
				Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE upgrades_id = '%d'", TBL_PLAYERS, SQL_FetchInt(hResult, 0));
				SQL_LockedFastQuery(g_hDatabase, sQuery);
			}
			CloseHandle(hResult);
		}
		else
		{
			LogError("DatabaseMaid: player expire query failed");
		}
	}
	
	Format(sQuery, sizeof(sQuery), "VACUUM %s", TBL_PLAYERS);
	SQL_LockedFastQuery(g_hDatabase, sQuery);
	Format(sQuery, sizeof(sQuery), "VACUUM %s", TBL_UPGRADES);
	SQL_LockedFastQuery(g_hDatabase, sQuery);
}

/* A very cheap way of doing things but there is no other alternative */
#define NO_SUCH_TBL "no such table"
SQLiteTableExists(String:table[])
{
	decl String:sQuery[64];
	Format(sQuery, sizeof(sQuery), "SELECT * FROM %s", table);
	if(SQL_LockedFastQuery(g_hDatabase, sQuery))
		return 1;
	
	decl String:sError[256];
	SQL_GetError(g_hDatabase, sError, sizeof(sError));
	if(StrContains(sError, NO_SUCH_TBL, false) != -1)
		return 0;
	
	LogError("Error checking if table \"%s\" exists: %s", table, sError);
	return -1;
}

#define NO_SUCH_COL "no such column"
SQLiteColumnExists(String:col[], String:table[])
{
	decl String:sQuery[64];
	Format(sQuery, sizeof(sQuery), "SELECT %s FROM %s", col, table);
	if(SQL_LockedFastQuery(g_hDatabase, sQuery))
		return 1;
	
	decl String:sError[256];
	SQL_GetError(g_hDatabase, sError, sizeof(sError));
	if(StrContains(sError, NO_SUCH_COL, false) != -1)
		return 0;
	
	LogError("Error checking if column \"%s\".\"%s\" exists: %s", table, col, sError);
	return -1;
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