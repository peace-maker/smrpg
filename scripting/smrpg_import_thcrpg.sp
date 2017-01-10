#pragma semicolon 1
#include <sourcemod>
#include <regex>
#include <smrpg>

#pragma newdecls required

// How many players to fetch and import at once.
#define IMPORT_STEP 100

public Plugin myinfo = 
{
	name = "SM:RPG > Import THC RPG database",
	author = "Peace-Maker",
	description = "Import players from THC RPG database.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	RegAdminCmd("sm_importrpgdb", Cmd_ImportDatabase, ADMFLAG_ROOT, "Import player level and experience from THC RPG. Usage: sm_importrpgdb [minlevel]");
}

public Action Cmd_ImportDatabase(int client, int args)
{
	// Parse the optional argument for minimum level to import.
	int iMinimumLevel = 1;
	if (args >= 1)
	{
		char sArgs[32];
		GetCmdArgString(sArgs, sizeof(sArgs));
		StripQuotes(sArgs);
		
		iMinimumLevel = StringToInt(sArgs);
	}
	if (iMinimumLevel < 1)
	{
		ReplyToCommand(client, "Minimum level has to be greater than 0.");
		return Plugin_Handled;
	}
	
	ConVar hCreditsStart = FindConVar("smrpg_credits_start");
	if (!hCreditsStart)
	{
		ReplyToCommand(client, "Error finding smrpg_credits_start convar. SM:RPG loaded?");
		return Plugin_Handled;
	}
	int iCreditsStart = hCreditsStart.IntValue;
	
	ConVar hCreditsInc = FindConVar("smrpg_credits_inc");
	if (!hCreditsInc)
	{
		ReplyToCommand(client, "Error finding smrpg_credits_inc convar. SM:RPG loaded?");
		return Plugin_Handled;
	}
	int iCreditsInc = hCreditsInc.IntValue;
	
	// First connect to the smrpg database.
	char sError[256];
	Database hNewDb = SQL_Connect("smrpg", true, sError, sizeof(sError));
	if (!hNewDb)
	{
		ReplyToCommand(client, "Error connecting to SM:RPG database: %s", sError);
		return Plugin_Handled;
	}
	
	hNewDb.SetCharset("utf8");
	
	// Make sure it's empty for now.
	DBResultSet hResult = SQL_Query(hNewDb, "SELECT COUNT(*) FROM players");
	if (!hResult)
	{
		SQL_GetError(hNewDb, sError, sizeof(sError));
		ReplyToCommand(client, "Error checking state of SM:RPG database: %s", sError);
		delete hNewDb;
		return Plugin_Handled;
	}
	
	if (hResult.FetchRow())
	{
		// smrpg database not empty!
		int iCount = hResult.FetchInt(0);
		if (iCount > 0)
		{
			ReplyToCommand(client, "There are already %d player entries in your SM:RPG database. You have to import the levels into an empty database. Please clean the SM:RPG database first and start the server with smrpg_save_data 0.", iCount);
			delete hResult;
			delete hNewDb;
			return Plugin_Handled;
		}
	}
	delete hResult;
	
	// Connect to the thc_rpg database now.
	Database hOldDb = SQL_Connect("thc_rpg", true, sError, sizeof(sError));
	if (!hOldDb)
	{
		ReplyToCommand(client, "Error connecting to thc_rpg database: %s", sError);
		delete hNewDb;
		return Plugin_Handled;
	}
	
	hOldDb.SetCharset("utf8");
	
	// Get player count.
	hResult = SQL_Query(hOldDb, "SELECT COUNT(*) FROM thc_rpg WHERE level >= %d", iMinimumLevel);
	if (!hResult)
	{
		SQL_GetError(hOldDb, sError, sizeof(sError));
		ReplyToCommand(client, "Error fetching player count from thc_rpg database: %s", sError);
		delete hNewDb;
		delete hOldDb;
		return Plugin_Handled;
	}
	
	int iCount;
	if (hResult.FetchRow())
		iCount = hResult.FetchInt(0);
	delete hResult;
	
	ReplyToCommand(client, "Going to import %d players with at least level %d ...", iCount, iMinimumLevel);
	
	int iUserId = client;
	if (client > 0)
		iUserId = GetClientUserId(client);
	
	char sAuthId[64], sName[128];
	int iXP, iLevel, iCredits, iAccountId;
	char sEscapedName[257], sQuery[1024];
	
	int iCurrentTime = GetTime();
	
	// Load old players in chunks, so we don't try to load the whole database into memory.
	for (int i=0; i<iCount; i+=IMPORT_STEP)
	{
		// Fetch a chunk of players.
		// Don't care for credits. we reset them so players can choose from the new upgrades.
		Format(sQuery, sizeof(sQuery), "SELECT ID, name, xp, level FROM thc_rpg WHERE level >= %d LIMIT %d, %d", iMinimumLevel, i, IMPORT_STEP);
		hResult = SQL_Query(hOldDb, sQuery);
		if (!hResult)
		{
			SQL_GetError(hOldDb, sError, sizeof(sError));
			ReplyToCommand(client, "Error fetching player list chunk %d from thc_rpg database: %s", i, sError);
			delete hNewDb;
			delete hOldDb;
			return Plugin_Handled;
		}
		
		// Run through all players and add them to the smrpg database.
		while(hResult.MoreRows)
		{
			if (!hResult.FetchRow())
				continue;
			
			hResult.FetchString(0, sAuthId, sizeof(sAuthId));
			hResult.FetchString(1, sName, sizeof(sName));
			iXP = hResult.FetchInt(2);
			iLevel = hResult.FetchInt(3);
			
			// Some sanity checks.
			if (iXP < 0)
			{
				ReplyToCommand(client, "%s has a negative experience of %d. Resetting to 0.", sName, iXP);
				iXP = 0;
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
			
			hNewDb.Escape(sName, sEscapedName, sizeof(sEscapedName));
			
			// Give the player the amount of credits he'd have at this level.
			iCredits = iCreditsStart + iCreditsInc * (iLevel - 1);
			
			if (iAccountId != -1)
			{
				// Player
				Format(sQuery, sizeof(sQuery), "INSERT INTO players (name, steamid, level, experience, credits, lastseen) VALUES (\"%s\", %d, %d, %d, %d, %d)", sEscapedName, iAccountId, iLevel, iXP, iCredits, iCurrentTime);
			}
			else
			{
				// Bot
				Format(sQuery, sizeof(sQuery), "INSERT INTO players (name, steamid, level, experience, credits, lastseen) VALUES (\"%s\", NULL, %d, %d, %d, %d)", sEscapedName, iLevel, iXP, iCredits, iCurrentTime);
			}
			hNewDb.Query(SQL_PrintError, sQuery, iUserId);
		}
		
		ReplyToCommand(client, "Imported %d/%d players from thc_rpg database.", i + hResult.RowCount, iCount);
		delete hResult;
	}
	
	LogAction(client, -1, "%L imported %d players from thc_rpg database.", client, iCount);
	
	delete hOldDb;
	delete hNewDb;
	
	return Plugin_Handled;
}

public void SQL_PrintError(Database owner, DBResultSet results, const char[] error, any userid)
{
	int client = userid;
	if(userid > 0)
	{
		client = GetClientOfUserId(userid);
		if(!client)
			return;
	}
	
	if (!results)
	{
		ReplyToCommand(client, "Error importing player: %s", error);
	}
}

/**
 * Converts a steamid to the accountid.
 */
stock int GetAccountIdFromSteamId(char[] sSteamID)
{
	static Regex hSteam2 = null;
	static Regex hSteam3 = null;
	
	if (hSteam2 == null)
		hSteam2 = new Regex("^STEAM_[0-9]:([0-9]):([0-9]+)$");
	if (hSteam3 == null)
		hSteam3 = new Regex("^\\[U:[0-9]:([0-9]+)\\]$");
	
	char sBuffer[64];
	
	// Steam2 format?
	if (hSteam2 != null && hSteam2.Match(sSteamID) == 3)
	{
		if(!hSteam2.GetSubString(1, sBuffer, sizeof(sBuffer)))
			return -1;
		
		int Y = StringToInt(sBuffer);
		if(!hSteam2.GetSubString(2, sBuffer, sizeof(sBuffer)))
			return -1;
		
		int Z = StringToInt(sBuffer);
		return Z*2 + Y;
	}
	
	// Steam3 format?
	if (hSteam3 != null && hSteam3.Match(sSteamID) == 2)
	{
		if(!hSteam3.GetSubString(1, sBuffer, sizeof(sBuffer)))
			return -1;
		
		return StringToInt(sBuffer);
	}
	
	return -1;
}