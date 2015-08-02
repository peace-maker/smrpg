#pragma semicolon 1
#include <sourcemod>
#include <regex>

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = 
{
	name = "SM:RPG > Import THC RPG database",
	author = "Peace-Maker",
	description = "Import players from THC RPG database.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	RegAdminCmd("sm_importrpgdb", Cmd_ImportDatabase, ADMFLAG_ROOT, "Import player level and experience from THC RPG.");
}

public Action:Cmd_ImportDatabase(client, args)
{
	new Handle:hCreditsStart = FindConVar("smrpg_credits_start");
	if (!hCreditsStart)
	{
		ReplyToCommand(client, "Error finding smrpg_credits_start convar. SM:RPG loaded?");
		return Plugin_Handled;
	}
	new iCreditsStart = GetConVarInt(hCreditsStart);
	
	new Handle:hCreditsInc = FindConVar("smrpg_credits_inc");
	if (!hCreditsInc)
	{
		ReplyToCommand(client, "Error finding smrpg_credits_inc convar. SM:RPG loaded?");
		return Plugin_Handled;
	}
	new iCreditsInc = GetConVarInt(hCreditsInc);
	
	// First connect to the smrpg database.
	new String:sError[256];
	new Handle:hNewDb = SQL_Connect("smrpg", true, sError, sizeof(sError));
	if (!hNewDb)
	{
		ReplyToCommand(client, "Error connecting to SM:RPG database: %s", sError);
		return Plugin_Handled;
	}
	
	// Make sure it's empty for now.
	new Handle:hResult = SQL_Query(hNewDb, "SELECT COUNT(*) FROM players");
	if (!hResult)
	{
		SQL_GetError(hNewDb, sError, sizeof(sError));
		ReplyToCommand(client, "Error checking state of SM:RPG database: %s", sError);
		CloseHandle(hNewDb);
		return Plugin_Handled;
	}
	
	if (SQL_FetchRow(hResult))
	{
		// smrpg database not empty!
		new iCount = SQL_FetchInt(hResult, 0);
		if (iCount > 0)
		{
			ReplyToCommand(client, "There are already %d player entries in your SM:RPG database. You have to import the levels into an empty database. Please clean the SM:RPG database first and start the server with smrpg_save_data 0.", iCount);
			CloseHandle(hResult);
			CloseHandle(hNewDb);
			return Plugin_Handled;
		}
	}
	CloseHandle(hResult);
	
	// Connect to the thc_rpg database now.
	new Handle:hOldDb = SQL_Connect("thc_rpg", true, sError, sizeof(sError));
	if (!hOldDb)
	{
		ReplyToCommand(client, "Error connecting to thc_rpg database: %s", sError);
		CloseHandle(hNewDb);
		return Plugin_Handled;
	}
	
	// Fetch all players.
	// Don't care for credits. we reset them so players can choose from the new upgrades.
	hResult = SQL_Query(hOldDb, "SELECT ID, name, xp, level FROM thc_rpg");
	if (!hResult)
	{
		SQL_GetError(hOldDb, sError, sizeof(sError));
		ReplyToCommand(client, "Error fetching player list from thc_rpg database: %s", sError);
		CloseHandle(hNewDb);
		CloseHandle(hOldDb);
		return Plugin_Handled;
	}
	
	ReplyToCommand(client, "Going to import %d players...", SQL_GetRowCount(hResult));
	
	// Run through all players and add them to the smrpg database.
	new String:sAuthId[64], String:sName[128], iXP, iLevel, iCredits;
	new iAccountId, String:sEscapedName[257];
	new String:sQuery[1024];
	while(SQL_MoreRows(hResult))
	{
		if (!SQL_FetchRow(hResult))
			continue;
		
		SQL_FetchString(hResult, 0, sAuthId, sizeof(sAuthId));
		SQL_FetchString(hResult, 1, sName, sizeof(sName));
		iXP = SQL_FetchInt(hResult, 2);
		iLevel = SQL_FetchInt(hResult, 3);
		
		// Some sanity checks.
		if (iXP < 0)
		{
			ReplyToCommand(client, "%s has a negative experience of %d. Resetting to 0.", sName, iXP);
			iXP = 0;
		}
		if (iLevel < 0)
		{
			ReplyToCommand(client, "%s has a negative level of %d. Resetting to 1.", sName, iLevel);
			iLevel = 1;
		}
		
		iAccountId = -1;
		// Bots were saved as if they'd have a steamid like "BOT_Name".
		if (StrContains(sAuthId, "BOT_", false) == -1)
		{
			// smrpg stores the steamid as accountid. Convert it.
			iAccountId = GetAccountIdFromSteamId(sAuthId);
			if (iAccountId == -1)
			{
				ReplyToCommand(client, "Can't import %s. \"%s\" is not a valid steamid.", sName, sAuthId);
				continue;
			}
		}
		
		SQL_EscapeString(hNewDb, sName, sEscapedName, sizeof(sEscapedName));
		
		// Give the player the amount of credits he'd have at this level.
		iCredits = iCreditsStart + iCreditsInc * (iLevel - 1);
		
		if (iAccountId != -1)
		{
			// Player
			Format(sQuery, sizeof(sQuery), "INSERT INTO players (name, steamid, level, experience, credits) VALUES (\"%s\", %d, %d, %d, %d)", sEscapedName, iAccountId, iLevel, iXP, iCredits);
		}
		else
		{
			// Bot
			Format(sQuery, sizeof(sQuery), "INSERT INTO players (name, steamid, level, experience, credits) VALUES (\"%s\", NULL, %d, %d, %d)", sEscapedName, iLevel, iXP, iCredits);
		}
		SQL_TQuery(hNewDb, SQL_PrintError, sQuery, GetClientUserId(client));
	}
	
	ReplyToCommand(client, "Imported %d players from thc_rpg database.", SQL_GetRowCount(hResult));
	LogAction(client, -1, "%L imported %d players from thc_rpg database.", client, SQL_GetRowCount(hResult));
	
	CloseHandle(hResult);
	CloseHandle(hOldDb);
	CloseHandle(hNewDb);
	
	return Plugin_Handled;
}

public SQL_PrintError(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if (!hndl)
	{
		ReplyToCommand(client, "Error importing player: %s", error);
	}
}

/**
 * Converts a steamid to the accountid.
 */
stock GetAccountIdFromSteamId(String:sSteamID[])
{
	static Handle:hSteam2 = INVALID_HANDLE;
	static Handle:hSteam3 = INVALID_HANDLE;
	
	if (hSteam2 == INVALID_HANDLE)
		hSteam2 = CompileRegex("^STEAM_[0-9]:([0-9]):([0-9]+)$");
	if (hSteam3 == INVALID_HANDLE)
		hSteam3 = CompileRegex("^\\[U:[0-9]:([0-9]+)\\]$");
	
	new String:sBuffer[64];
	
	// Steam2 format?
	if (hSteam2 != INVALID_HANDLE && MatchRegex(hSteam2, sSteamID) == 3)
	{
		if(!GetRegexSubString(hSteam2, 1, sBuffer, sizeof(sBuffer)))
			return -1;
		
		new Y = StringToInt(sBuffer);
		if(!GetRegexSubString(hSteam2, 2, sBuffer, sizeof(sBuffer)))
			return -1;
		
		new Z = StringToInt(sBuffer);
		return Z*2 + Y;
	}
	
	// Steam3 format?
	if (hSteam3 != INVALID_HANDLE && MatchRegex(hSteam3, sSteamID) == 2)
	{
		if(!GetRegexSubString(hSteam3, 1, sBuffer, sizeof(sBuffer)))
			return -1;
		
		return StringToInt(sBuffer);
	}
	
	return -1;
}