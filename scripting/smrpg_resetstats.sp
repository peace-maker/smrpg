#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <smrpg>
#include <autoexecconfig>

#pragma newdecls required

int g_iDaysInMonth[] = {0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
ConVar g_hCVFirstReset;
ConVar g_hCVMonths;
ConVar g_hCVTop10MaxLevel;

ConVar g_hCVAutoReset;

public Plugin myinfo = 
{
	name = "SM:RPG > Reset interval",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Resets the stats every x months",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	ConVar hVersion = CreateConVar("smrpg_resetstats_version", SMRPG_VERSION, "", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != null)
	{
		hVersion.SetString(SMRPG_VERSION);
		hVersion.AddChangeHook(ConVar_VersionChanged);
	}
	
	LoadTranslations("smrpg_resetstats.phrases");
	
	AutoExecConfig_SetFile("plugin.smrpg_resetstats");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(null);
	
	g_hCVFirstReset = AutoExecConfig_CreateConVar("smrpg_resetstats_firstreset", "2014-02-01", "The date of the first reset which is used as a base to get the coming reset dates. Format yyyy-mm-dd.");
	g_hCVMonths = AutoExecConfig_CreateConVar("smrpg_resetstats_months", "2", "After how many months shall we reset the stats again?", _, true, 0.0);
	g_hCVTop10MaxLevel = AutoExecConfig_CreateConVar("smrpg_resetstats_top10_maxlevel", "0", "When the top 10 players total levels add together to this maxlevel, the server is reset. (0 to disable)", _, true, 0.0);
	
	g_hCVAutoReset = AutoExecConfig_CreateConVar("smrpg_resetstats_autoreset", "0", "Reset the database automatically when one of the reset conditions is true?", _, true, 0.0, true, 1.0);
	
	AutoExecConfig_ExecuteFile();
	//AutoExecConfig_CleanFile();
	
	RegConsoleCmd("sm_nextreset", Cmd_NextReset, "Displays when the next rpg reset will be.");
	RegConsoleCmd("sm_lastreset", Cmd_LastReset, "Displays when the rpg stats were last reset.");
	
	RegAdminCmd("smrpg_db_resetdatabase", Cmd_ResetDatabase, ADMFLAG_ROOT, "Resets all players in the database back to level 1. CANNOT BE UNDONE!", "smrpg");
}

public void ConVar_VersionChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	convar.SetString(SMRPG_VERSION);
}

public void OnMapStart()
{
	CreateTimer(1200.0, Timer_InformAboutReset, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public void SMRPG_OnClientLoaded(int client)
{
	// This player's stats were reset while he wasn't on the server. Inform him about the reset.
	if(SMRPG_GetClientLastSeenTime(client) < SMRPG_GetClientLastResetTime(client))
	{
		// Wait until he joined completely.
		CreateTimer(10.0, Timer_InformPlayerReset, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Cmd_ResetDatabase(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "SM:RPG > Usage: smrpg_db_resetdatabase <reason>");
		return Plugin_Handled;
	}
	
	char sReason[256];
	GetCmdArgString(sReason, sizeof(sReason));
	StripQuotes(sReason);
	TrimString(sReason);
	
	// Reset the database.
	SMRPG_ResetAllPlayers(sReason);
	
	// Inform all ingame players in chat.
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
			CreateTimer(1.0, Timer_InformPlayerReset, GetClientSerial(i), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	ReplyToCommand(client, "SM:RPG > %t", "Admin command resetdatabase");
	LogAction(client, -1, "%L reset the SM:RPG database. The reason given was \"%s\".", client, sReason);
	
	return Plugin_Handled;
}

public Action Cmd_NextReset(int client, int args)
{
	if(g_hCVMonths.IntValue > 0)
		PrintDaysUntilReset(client);
	
	if(g_hCVTop10MaxLevel.IntValue > 0)
		PrintLevelUntilReset(client);
	
	return Plugin_Handled;
}

public Action Cmd_LastReset(int client, int args)
{
	char sLastReset[32];
	int iLastReset[3];
	if(SMRPG_GetSetting("last_reset", sLastReset, sizeof(sLastReset)))
	{
		int iLastGlobalResetStamp = StringToInt(sLastReset);
		GetCurrentDate(iLastReset[0], iLastReset[1], iLastReset[2], iLastGlobalResetStamp);
		Client_Reply(client, "{OG}SM:RPG{N} > {G}%t", "Last server reset", iLastReset[2], iLastReset[1], iLastReset[0]);
		
		char sReason[256];
		if(SMRPG_GetSetting("reset_reason", sReason, sizeof(sReason)))
			Client_Reply(client, "{OG}SM:RPG{N} > {G}%t", "Display global reset reason", sReason);
	}
	
	if(client > 0)
	{
		int iLastResetStamp = SMRPG_GetClientLastResetTime(client);
		GetCurrentDate(iLastReset[0], iLastReset[1], iLastReset[2], iLastResetStamp);
		Client_Reply(client, "{OG}SM:RPG{N} > {G}%t", "Last player reset", iLastReset[2], iLastReset[1], iLastReset[0]);
	}
	return Plugin_Continue;
}

void PrintLevelUntilReset(int client)
{
	SMRPG_GetTop10Players(SQL_GetTop10, client?GetClientUserId(client):client);
}

public void SQL_GetTop10(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if(!results)
	{
		LogError("Error fetching top10 players: %s", error);
		return;
	}
	
	int iTotalLevels;
	// SELECT name, level, experience, credits FROM ..
	while(results.MoreRows)
	{
		if(!results.FetchRow())
			continue;
		
		iTotalLevels += results.FetchInt(1);
	}
	
	int iResetMaxLevel = g_hCVTop10MaxLevel.IntValue;
	int iLevelsLeft = iResetMaxLevel - iTotalLevels;
	if(iLevelsLeft < 0)
		iLevelsLeft = 0;
	
	// Actually reset the database now.
	if(iLevelsLeft == 0)
	{
		char sReason[256];
		Format(sReason, sizeof(sReason), "Levels of top 10 players summed up to %d.", iResetMaxLevel);
		DoReset(sReason);
	}
	
	if(!client)
		PrintToServer("SM:RPG > %T", "Stats reset when levels sum up to", LANG_SERVER, iResetMaxLevel, iLevelsLeft);
	else
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {G}%t", "Stats reset when levels sum up to", iResetMaxLevel, iLevelsLeft);
}

/*
 * Date interval related resetting
 */
void PrintDaysUntilReset(int client)
{
	int iNextReset[3];
	int iDays = GetDaysUntilNextReset(iNextReset);
	int iCurrentYear, iCurrentMonth, iCurrentDay;
	GetCurrentDate(iCurrentYear, iCurrentMonth, iCurrentDay);
	
	int iYears, iMonths;
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
	
	// Try to reset automatically now
	if(iDays == 0)
	{
		char sReason[256] = "Regular reset every ";
		int iMonthInterval = g_hCVMonths.IntValue;
		if(iMonthInterval > 1)
			Format(sReason, sizeof(sReason), "%s%d months.", sReason, iMonthInterval);
		else
			Format(sReason, sizeof(sReason), "%s month.", sReason);
		DoReset(sReason);
	}
	
	// Today is a special case and has it's own phrase.
	if(iDays == 0)
	{
		if(!client)
			PrintToServer("SM:RPG > %T", "Timed reset today", LANG_SERVER);
		else
			Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {G}%t", "Timed reset today");
	}
	else
	{
		char sYears[32], sMonths[32], sDays[32];
		
		if(!client)
		{
			TranslateTimespan(LANG_SERVER, sYears, sizeof(sYears), iYears, sMonths, sizeof(sMonths), iMonths, sDays, sizeof(sDays), iDays);
			PrintToServer("SM:RPG > %T", "Timed reset in future", LANG_SERVER, sDays, sMonths, sYears, iNextReset[2], iNextReset[1], iNextReset[0]);
		}
		else
		{
			for (int i=1;i<=MaxClients;i++)
			{
				if (!IsClientInGame(i) || IsFakeClient(i))
					continue;
				
				TranslateTimespan(i, sYears, sizeof(sYears), iYears, sMonths, sizeof(sMonths), iMonths, sDays, sizeof(sDays), iDays);
				Client_PrintToChat(i, false, "{OG}SM:RPG{N} > {G}%t", "Timed reset in future", sDays, sMonths, sYears, iNextReset[2], iNextReset[1], iNextReset[0]);
			}
		}
	}
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	ReplySource oldSource = SetCmdReplySource(SM_REPLY_TO_CHAT);
	if (StrEqual(sArgs, "nextreset", false))
		Cmd_NextReset(client, 0);
	else if(StrEqual(sArgs, "lastreset", false))
		Cmd_LastReset(client, 0);
	SetCmdReplySource(oldSource);
}

public Action Timer_InformAboutReset(Handle timer)
{
	Cmd_NextReset(1, 0);
	
	return Plugin_Continue;
}

public Action Timer_InformPlayerReset(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	if(!client)
		return Plugin_Stop;
	
	int iLastReset[3];
	int iLastResetStamp = SMRPG_GetClientLastResetTime(client);
	GetCurrentDate(iLastReset[2], iLastReset[1], iLastReset[0], iLastResetStamp);
	
	// Print some chat message multiple times so he really reads it.
	for(int i=0;i<3;i++)
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > %t", "Warning, your stats were reset on", iLastReset[0], iLastReset[1], iLastReset[2]);
	
	// Might be interesting to know that all other players were reset too.
	char sLastReset[32];
	if(SMRPG_GetSetting("last_reset", sLastReset, sizeof(sLastReset)))
	{
		int iLastGlobalResetStamp = StringToInt(sLastReset);
		if(iLastGlobalResetStamp == iLastResetStamp)
		{
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "The whole server got reset, so you're not the only one.");
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "This is done automatically regularly.");
			
			char sReason[256];
			if(SMRPG_GetSetting("reset_reason", sReason, sizeof(sReason)))
				Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Display global reset reason", sReason);
		}
	}
	
	return Plugin_Stop;
}

/**
 * Reset the database iff it wasn't reset already today.
 */
void DoReset(const char[] sReason)
{
	// Don't take any action automatically.
	if(!g_hCVAutoReset.BoolValue)
		return;
	
	char sLastReset[32];
	if(SMRPG_GetSetting("last_reset", sLastReset, sizeof(sLastReset)))
	{
		int iLastResetStamp = StringToInt(sLastReset);
		int iLastReset[3];
		GetCurrentDate(iLastReset[2], iLastReset[1], iLastReset[0], iLastResetStamp);
		
		int iCurrentDate[3];
		GetCurrentDate(iCurrentDate[2], iCurrentDate[1], iCurrentDate[0]);
		
		// Already reset today..
		if(iCurrentDate[0] == iLastReset[0] && iCurrentDate[1] == iLastReset[1] && iCurrentDate[2] == iLastReset[2])
			return;
	}
	
	LogMessage("Resetting SM:RPG stats automatically.");
	
	// Reset the database.
	SMRPG_ResetAllPlayers(sReason);
	
	// Inform all ingame players in chat.
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
			CreateTimer(1.0, Timer_InformPlayerReset, GetClientSerial(i), TIMER_FLAG_NO_MAPCHANGE);
	}
}

void TranslateTimespan(int client, char[] sYears, int iLenYears, int iYears, char[] sMonths, int iLenMonths, int iMonths, char[] sDays, int iLenDays, int iDays)
{
	if(iYears > 0)
	{
		if (iYears > 1)
			Format(sYears, iLenYears, "%T", "Years", client, iYears);
		else
			Format(sYears, iLenYears, "%T", "One Year", client);
	}
	
	if(iMonths > 0)
	{
		if (iMonths > 1)
			Format(sMonths, iLenMonths, "%T", "Months", client, iMonths);
		else
			Format(sMonths, iLenMonths, "%T", "One Month", client);
	}
	
	if(iDays > 0)
	{
		if (iDays > 1)
			Format(sDays, iLenDays, "%T", "Days", client, iDays);
		else
			Format(sDays, iLenDays, "%T", "One Day", client);
	}
}

stock int GetDaysUntilNextReset(int iNextReset[3])
{
	// Get the current date
	int iCurrentYear, iCurrentMonth, iCurrentDay;
	GetCurrentDate(iCurrentYear, iCurrentMonth, iCurrentDay);
	
	// Parse the start date
	char sFirstDate[15];
	g_hCVFirstReset.GetString(sFirstDate, sizeof(sFirstDate));
	TrimString(sFirstDate);
	if(strlen(sFirstDate) != 10)
		return 0;
	
	char sBuffer[15];
	strcopy(sBuffer, 5, sFirstDate);
	sBuffer[4] = '\0';
	int iFirstYear = StringToInt(sBuffer);
	strcopy(sBuffer, 3, sFirstDate[5]);
	sBuffer[2] = '\0';
	int iFirstMonth = StringToInt(sBuffer);
	strcopy(sBuffer, 3, sFirstDate[8]);
	sBuffer[2] = '\0';
	int iFirstDay = StringToInt(sBuffer);
	
	// Generate the next reset date.
	int iResetInterval = g_hCVMonths.IntValue;
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
	
	int iDays;
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

stock bool IsLeapYear(int year)
{
	if(year % 4)
		return false;
	
	if(year % 100)
		return true;
	
	if(year % 400)
		return false;
	
	return true;
}

stock void GetCurrentDate(int &iYear, int &iMonth, int &iDay, int stamp=-1)
{
	char sBuffer[15];
	FormatTime(sBuffer, sizeof(sBuffer), "%Y", stamp);
	iYear = StringToInt(sBuffer);
	FormatTime(sBuffer, sizeof(sBuffer), "%m", stamp);
	iMonth = StringToInt(sBuffer);
	FormatTime(sBuffer, sizeof(sBuffer), "%d", stamp);
	iDay = StringToInt(sBuffer);
}