#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <smrpg>
#include <autoexecconfig>

#define PLUGIN_VERSION "1.0"

new g_iDaysInMonth[] = {0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
new Handle:g_hCVFirstReset;
new Handle:g_hCVMonths;
new Handle:g_hCVTop10MaxLevel;

new Handle:g_hCVAutoReset;

public Plugin:myinfo = 
{
	name = "SM:RPG > Reset interval",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Resets the stats every x months",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	new Handle:hVersion = CreateConVar("smrpg_resetstats_version", PLUGIN_VERSION, "", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != INVALID_HANDLE)
	{
		SetConVarString(hVersion, PLUGIN_VERSION);
		HookConVarChange(hVersion, ConVar_VersionChanged);
	}
	
	AutoExecConfig_SetFile("plugin.smrpg_resetstats");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(INVALID_HANDLE);
	
	g_hCVFirstReset = AutoExecConfig_CreateConVar("smrpg_resetstats_firstreset", "2014-02-01", "The date of the first reset which is used as a base to get the coming reset dates. Format yyyy-mm-dd.");
	g_hCVMonths = AutoExecConfig_CreateConVar("smrpg_resetstats_months", "2", "After how many months shall we reset the stats again?", _, true, 0.0);
	g_hCVTop10MaxLevel = AutoExecConfig_CreateConVar("smrpg_resetstats_top10_maxlevel", "0", "When the top 10 players total levels add together to this maxlevel, the server is reset. (0 to disable)", _, true, 0.0);
	
	g_hCVAutoReset = AutoExecConfig_CreateConVar("smrpg_resetstats_autoreset", "0", "Reset the database automatically when one of the reset conditions is true?", _, true, 0.0, true, 1.0);
	
	AutoExecConfig_ExecuteFile();
	//AutoExecConfig_CleanFile();
	
	RegConsoleCmd("sm_nextreset", Cmd_NextReset, "Displays when the next rpg reset will be.");
	RegConsoleCmd("sm_lastreset", Cmd_LastReset, "Displays when the rpg stats were last reset.");
	
	RegAdminCmd("smrpg_db_resetdatabase", Cmd_ResetDatabase, ADMFLAG_ROOT, "Resets all players in the database back to level 1. CANNOT BE UNDON!", "smrpg");
	
	AddCommandListener(CmdLstnr_Say, "say");
	AddCommandListener(CmdLstnr_Say, "say_team");
}

public ConVar_VersionChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	SetConVarString(convar, PLUGIN_VERSION);
}

public OnMapStart()
{
	CreateTimer(1200.0, Timer_InformAboutReset, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public SMRPG_OnClientLoaded(client)
{
	// This player's stats were reset while he wasn't on the server. Inform him about the reset.
	if(SMRPG_GetClientLastSeenTime(client) < SMRPG_GetClientLastResetTime(client))
	{
		// Wait until he joined completely.
		CreateTimer(10.0, Timer_InformPlayerReset, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:Cmd_ResetDatabase(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "SM:RPG > Usage: smrpg_db_resetdatabase <reason>");
		return Plugin_Handled;
	}
	
	decl String:sReason[256];
	GetCmdArgString(sReason, sizeof(sReason));
	StripQuotes(sReason);
	TrimString(sReason);
	
	// Reset the database.
	SMRPG_ResetAllPlayers(sReason);
	
	// Inform all ingame players in chat.
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
			CreateTimer(1.0, Timer_InformPlayerReset, GetClientSerial(i), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	ReplyToCommand(client, "SM:RPG > The database was wiped. All players are on level 1 again.");
	LogAction(client, -1, "%L reset the SM:RPG database. The reason given was \"%s\".", client, sReason);
	
	return Plugin_Handled;
}

public Action:Cmd_NextReset(client, args)
{
	if(GetConVarInt(g_hCVMonths) > 0)
		PrintDaysUntilReset(client);
	
	if(GetConVarInt(g_hCVTop10MaxLevel) > 0)
		PrintLevelUntilReset(client);
	
	return Plugin_Handled;
}

public Action:Cmd_LastReset(client, args)
{
	new String:sLastReset[32], iLastReset[3];
	if(SMRPG_GetSetting("last_reset", sLastReset, sizeof(sLastReset)))
	{
		new iLastGlobalResetStamp = StringToInt(sLastReset);
		GetCurrentDate(iLastReset[2], iLastReset[1], iLastReset[0], iLastGlobalResetStamp);
		Client_Reply(client, "{OG}SM:RPG{N} > {G}The server stats were reset on {N}%d-%d-%d{G}.", iLastReset[2], iLastReset[1], iLastReset[0]);
		
		new String:sReason[256];
		if(SMRPG_GetSetting("reset_reason", sReason, sizeof(sReason)))
			Client_Reply(client, "{OG}SM:RPG{N} > {G}Reason: {N}%s", sReason);
	}
	
	if(client > 0)
	{
		new iLastResetStamp = SMRPG_GetClientLastResetTime(client);
		GetCurrentDate(iLastReset[2], iLastReset[1], iLastReset[0], iLastResetStamp);
		Client_Reply(client, "{OG}SM:RPG{N} > {G}Your stats were {RB}reset on {N}%d-%d-%d{G}.", iLastReset[2], iLastReset[1], iLastReset[0]);
	}
	return Plugin_Continue;
}

PrintLevelUntilReset(client)
{
	SMRPG_GetTop10Players(SQL_GetTop10, client?GetClientUserId(client):client);
}

public SQL_GetTop10(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	
	if(!hndl)
	{
		LogError("Error fetching top10 players: %s", error);
		return;
	}
	
	new iTotalLevels;
	// SELECT name, level, experience, credits FROM ..
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		iTotalLevels += SQL_FetchInt(hndl, 1);
	}
	
	new iResetMaxLevel = GetConVarInt(g_hCVTop10MaxLevel);
	new iLevelsLeft = iResetMaxLevel - iTotalLevels;
	if(iLevelsLeft < 0)
		iLevelsLeft = 0;
	
	// Actually reset the database now.
	if(iLevelsLeft == 0)
	{
		decl String:sReason[256];
		Format(sReason, sizeof(sReason), "Levels of top 10 players summed up to %d.", iResetMaxLevel);
		DoReset(sReason);
	}
	
	if(!client)
		PrintToServer("SM:RPG > The stats are reset when the levels of the top 10 players sum up to %d. Still %d levels left.", iResetMaxLevel, iLevelsLeft);
	else
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {G}The stats are reset when the levels of the top 10 players sum up to %d. Still %d levels left.", iResetMaxLevel, iLevelsLeft);
}

/*
 * Date interval related resetting
 */
PrintDaysUntilReset(client)
{
	new iNextReset[3];
	new iDays = GetDaysUntilNextReset(iNextReset);
	new iCurrentYear, iCurrentMonth, iCurrentDay;
	GetCurrentDate(iCurrentYear, iCurrentMonth, iCurrentDay);
	
	new iYears, iMonths;
	while((iDays - g_iDaysInMonth[iCurrentMonth]) > 0)
	{
		iDays -= g_iDaysInMonth[iCurrentMonth];
		iCurrentMonth++;
		if(iCurrentMonth > 12)
		{
			iCurrentMonth -= 12;
			iCurrentYear++;
		}
		
		iMonths++;
		if(iMonths > 12)
		{
			iMonths -= 12;
			iYears++;
		}
	}
	
	new String:sTimeString[64];
	if(iDays == 0)
	{
		strcopy(sTimeString, sizeof(sTimeString), "today");
		new String:sReason[256] = "Regular reset every ";
		new iMonthInterval = GetConVarInt(g_hCVMonths);
		if(iMonthInterval > 1)
			Format(sReason, sizeof(sReason), "%s%d months.", sReason, iMonthInterval);
		else
			Format(sReason, sizeof(sReason), "%s month.", sReason);
		DoReset(sReason);
	}
	else
		strcopy(sTimeString, sizeof(sTimeString), "in");
	
	if(iYears > 0)
		Format(sTimeString, sizeof(sTimeString), "%s %d year%s", sTimeString, iYears, (iYears > 1?"s":""));
	if(iMonths > 0)
		Format(sTimeString, sizeof(sTimeString), "%s %d month%s", sTimeString, iMonths, (iMonths > 1?"s":""));
	if(iDays > 0)
		Format(sTimeString, sizeof(sTimeString), "%s %d day%s", sTimeString, iDays, (iDays > 1?"s":""));
	
	if(iDays > 0)
		Format(sTimeString, sizeof(sTimeString), "%s on %02d.%02d.%04d", sTimeString, iNextReset[2], iNextReset[1], iNextReset[0]);
	
	if(!client)
		PrintToServer("SM:RPG > The stats are going to be reset %s.", sTimeString);
	else
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {G}The stats are going to be reset %s.", sTimeString);
}

public Action:CmdLstnr_Say(client, const String:command[], argc)
{
	decl String:sText[16];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	TrimString(sText);
	if(StrEqual(sText, "nextreset", false))
		Cmd_NextReset(client, 0);
	return Plugin_Continue;
}

public Action:Timer_InformAboutReset(Handle:timer)
{
	Cmd_NextReset(1, 0);
	
	return Plugin_Continue;
}

public Action:Timer_InformPlayerReset(Handle:timer, any:serial)
{
	new client = GetClientFromSerial(serial);
	if(!client)
		return Plugin_Stop;
	
	new iLastReset[3];
	new iLastResetStamp = SMRPG_GetClientLastResetTime(client);
	GetCurrentDate(iLastReset[2], iLastReset[1], iLastReset[0], iLastResetStamp);
	
	// Print some chat message multiple times so he really reads it.
	for(new i=0;i<3;i++)
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {RB}WARNING!{G} Your stats were {RB}reset on {N}%d-%d-%d{G}.", iLastReset[2], iLastReset[1], iLastReset[0]);
	
	// Might be interesting to know that all other players were reset too.
	new String:sLastReset[32];
	if(SMRPG_GetSetting("last_reset", sLastReset, sizeof(sLastReset)))
	{
		new iLastGlobalResetStamp = StringToInt(sLastReset);
		if(iLastGlobalResetStamp == iLastResetStamp)
		{
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}The whole server got reset, so you're not the only one.");
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}This is done automatically regularly. Type {N}nextreset{G} to see when it's time again.");
			
			new String:sReason[256];
			if(SMRPG_GetSetting("reset_reason", sReason, sizeof(sReason)))
				Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}Reason: {N}%s", sReason);
		}
	}
	
	return Plugin_Stop;
}

/**
 * Reset the database iff it wasn't reset already today.
 */
DoReset(const String:sReason[])
{
	// Don't take any action automatically.
	if(!GetConVarBool(g_hCVAutoReset))
		return;
	
	decl String:sLastReset[32];
	if(SMRPG_GetSetting("last_reset", sLastReset, sizeof(sLastReset)))
	{
		new iLastResetStamp = StringToInt(sLastReset);
		new iLastReset[3];
		GetCurrentDate(iLastReset[2], iLastReset[1], iLastReset[0], iLastResetStamp);
		
		new iCurrentDate[3];
		GetCurrentDate(iCurrentDate[2], iCurrentDate[1], iCurrentDate[0]);
		
		// Already reset today..
		if(iCurrentDate[0] == iLastReset[0] && iCurrentDate[1] == iLastReset[1] && iCurrentDate[2] == iLastReset[2])
			return;
	}
	
	LogMessage("Resetting SM:RPG stats automatically.");
	
	// Reset the database.
	SMRPG_ResetAllPlayers(sReason);
	
	// Inform all ingame players in chat.
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
			CreateTimer(1.0, Timer_InformPlayerReset, GetClientSerial(i), TIMER_FLAG_NO_MAPCHANGE);
	}
}

stock GetDaysUntilNextReset(iNextReset[3])
{
	// Get the current date
	new iCurrentYear, iCurrentMonth, iCurrentDay;
	GetCurrentDate(iCurrentYear, iCurrentMonth, iCurrentDay);
	
	// Parse the start date
	decl String:sFirstDate[15];
	GetConVarString(g_hCVFirstReset, sFirstDate, sizeof(sFirstDate));
	TrimString(sFirstDate);
	if(strlen(sFirstDate) != 10)
		return 0;
	
	decl String:sBuffer[15];
	strcopy(sBuffer, 5, sFirstDate);
	sBuffer[4] = '\0';
	new iFirstYear = StringToInt(sBuffer);
	strcopy(sBuffer, 3, sFirstDate[5]);
	sBuffer[2] = '\0';
	new iFirstMonth = StringToInt(sBuffer);
	strcopy(sBuffer, 3, sFirstDate[8]);
	sBuffer[2] = '\0';
	new iFirstDay = StringToInt(sBuffer);
	
	// Generate the next reset date.
	new iResetInterval = GetConVarInt(g_hCVMonths);
	while(iFirstYear < iCurrentYear || iFirstYear == iCurrentYear && (iFirstMonth < iCurrentMonth || (iFirstMonth == iCurrentMonth && iFirstDay < iCurrentDay)))
	{
		iFirstMonth += iResetInterval;
		while(iFirstMonth > 12)
		{
			iFirstYear++;
			iFirstMonth -= 12;
		}
	}
	
	iNextReset[0] = iFirstYear;
	iNextReset[1] = iFirstMonth;
	iNextReset[2] = iFirstDay;
	
	//PrintToServer("Next reset on %d-%d-%d", iFirstYear, iFirstMonth, iFirstDay);
	
	new iDays;
	while(iCurrentYear < iFirstYear || (iCurrentMonth < iFirstMonth && iCurrentYear == iFirstYear))
	{
		iDays += g_iDaysInMonth[iCurrentMonth];
		
		// Leap years..
		if(iCurrentMonth == 2)
		{
			if(IsLeapYear(iCurrentYear))
				iDays++; // feburary got 29 days this year.
		}
		
		iCurrentMonth++;
		if(iCurrentMonth > 12)
		{
			iCurrentMonth -= 12;
			iCurrentYear++;
		}
	}
	iDays += (iFirstDay - iCurrentDay);
	return iDays;
}

stock bool:IsLeapYear(year)
{
	if(year % 4)
		return false;
	
	if(year % 100)
		return true;
	
	if(year % 400)
		return false;
	
	return true;
}

stock GetCurrentDate(&iYear, &iMonth, &iDay, stamp=-1)
{
	decl String:sBuffer[15];
	FormatTime(sBuffer, sizeof(sBuffer), "%Y", stamp);
	iYear = StringToInt(sBuffer);
	FormatTime(sBuffer, sizeof(sBuffer), "%m", stamp);
	iMonth = StringToInt(sBuffer);
	FormatTime(sBuffer, sizeof(sBuffer), "%d", stamp);
	iDay = StringToInt(sBuffer);
}