#pragma semicolon 1
#include <sourcemod>
#include <topmenus>
#include <smrpg>
#include <smlib/clients>
#include <smrpg/smrpg_clients>
#include <smrpg/smrpg_topmenu>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#pragma newdecls required
#define PLUGIN_VERSION "1.0"

#define SECONDS_EXP_AVG_CALC 60.0
#define EXP_MEMORY_SIZE 10

// RPG Topmenu
TopMenu g_hRPGMenu;

// Clientprefs
bool g_bClientHidePanel[MAXPLAYERS+1];
Handle g_hCookieHidePanel;

// Last experience memory
int g_iLastExperience[MAXPLAYERS+1];
ArrayList g_hExperienceMemory[MAXPLAYERS+1];
int g_iExperienceThisMinute[MAXPLAYERS+1];
float g_fExperienceAverage[MAXPLAYERS+1];

bool g_bIsCSGO;

public Plugin myinfo = 
{
	name = "SM:RPG > Key Hint Infopanel",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Shows some RPG stats in a panel on the screen",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	LoadTranslations("smrpg_keyhint_info.phrases");
	
	TopMenu hTopMenu;
	if((hTopMenu = SMRPG_GetTopMenu()) != null)
		SMRPG_OnRPGMenuReady(hTopMenu);
	
	if(LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
	
	g_bIsCSGO = GetEngineVersion() == Engine_CSGO;
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookieHidePanel = RegClientCookie("smrpg_keyhint_hide", "Hide the rpg info panel showing RPG stats.", CookieAccess_Protected);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookieHidePanel = null;
	}
}

public void OnClientCookiesCached(int client)
{
	char sBuffer[4];
	GetClientCookie(client, g_hCookieHidePanel, sBuffer, sizeof(sBuffer));
	g_bClientHidePanel[client] = StringToInt(sBuffer)==1;
}

public void OnClientPutInServer(int client)
{
	g_hExperienceMemory[client] = new ArrayList();
}

public void OnClientDisconnect(int client)
{
	g_bClientHidePanel[client] = false;
	g_iLastExperience[client] = 0;
	ClearHandle(g_hExperienceMemory[client]);
	g_iExperienceThisMinute[client] = 0;
	g_fExperienceAverage[client] = 0.0;
}

public void OnMapStart()
{
	CreateTimer(1.0, Timer_ShowInfoPanel, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	CreateTimer(SECONDS_EXP_AVG_CALC, Timer_CalculateEstimatedLevelupTime, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action Timer_ShowInfoPanel(Handle timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	int iTarget;
	Obs_Mode iMode;
	char sBuffer[512];
	int iLevel, iExp, iExpForLevel, iExpNeeded;
	char sTime[32];
	
	int iRankCount = SMRPG_GetRankCount();
	for(int i=1;i<=MaxClients;i++)
	{
		// This player doesn't want this info.
		if(g_bClientHidePanel[i])
			continue;
		
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;
		
		iTarget = i;
		// Show info of the player he's spectating
		if(IsClientObserver(i) || !IsPlayerAlive(i))
		{
			// Only care for direct spectating of some player.
			iMode = Client_GetObserverMode(i);
			if(iMode != OBS_MODE_CHASE && iMode != OBS_MODE_IN_EYE)
				continue;
			
			// Make sure he's really observing someone.
			iTarget = Client_GetObserverTarget(i);
			if(iTarget <= 0 || iTarget > MaxClients)
				continue;
		}
		
		// CS:GO doesn't support the KeyHint usermessage.
		// Show a 3 line formatted HintText instead.
		if (g_bIsCSGO)
			strcopy(sBuffer, sizeof(sBuffer), "<font size=\"20\"><u>RPG Stats</u></font>");
		else
			strcopy(sBuffer, sizeof(sBuffer), "RPG Stats\n");
			
		// Show the name of the player he's spectating
		if(iTarget != i)
		{
			if (g_bIsCSGO)
				Format(sBuffer, sizeof(sBuffer), "%s for <font color=\"#ff0000\">%N</font>\n", sBuffer, iTarget);
			else
				Format(sBuffer, sizeof(sBuffer), "%s%N\n", sBuffer, iTarget);
		}
		else if (g_bIsCSGO)
			StrCat(sBuffer, sizeof(sBuffer), "\n");
		
		iLevel = SMRPG_GetClientLevel(iTarget);
		iExp = SMRPG_GetClientExperience(iTarget),
		iExpForLevel = SMRPG_LevelToExperience(iLevel);
		
		if (g_bIsCSGO)
		{
			Format(sBuffer, sizeof(sBuffer), "%s<font size=\"16\">%T\t", sBuffer, "Level", i, iLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T\t", sBuffer, "Experience short", i, iExp, iExpForLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T</font>", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
		}
		else
		{
			Format(sBuffer, sizeof(sBuffer), "%s\n%T\n", sBuffer, "Level", i, iLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T\n", sBuffer, "Experience short", i, iExp, iExpForLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
		}
		
		// No space for that in CS:GO :(
		if (!g_bIsCSGO)
		{
			int iRank = SMRPG_GetClientRank(iTarget);
			if(iRank > 0)
				Format(sBuffer, sizeof(sBuffer), "%s\n%T", sBuffer, "Rank", i, iRank, iRankCount);
		}
		
		if(g_fExperienceAverage[iTarget] > 0.0)
		{
			iExpNeeded = iExpForLevel - iExp;
			SecondsToString(sTime, sizeof(sTime), RoundToCeil(float(iExpNeeded)/g_fExperienceAverage[iTarget]*SECONDS_EXP_AVG_CALC));
			
			if (g_bIsCSGO)
				Format(sBuffer, sizeof(sBuffer), "%s\t<font size=\"15\" color=\"#00ff00\"><i>%T: %s</i></font>", sBuffer, "Estimated time until levelup", i, sTime);
			else
				Format(sBuffer, sizeof(sBuffer), "%s\n%T: %s", sBuffer, "Estimated time until levelup", i, sTime);
		}
		
		// Not enough space in csgo..
		if(!g_bIsCSGO)
		{
			if(g_iLastExperience[iTarget] > 0)
				Format(sBuffer, sizeof(sBuffer), "%s\n%T: +%d", sBuffer, "Last Experience Short", i, g_iLastExperience[iTarget]);
			
			if(SMRPG_IsClientAFK(iTarget))
				Format(sBuffer, sizeof(sBuffer), "%s\n\n%T", sBuffer, "Player is AFK", i);
		}
		
		if (g_bIsCSGO)
			Client_PrintHintText(i, "%s", sBuffer);
		else
			Client_PrintKeyHintText(i, "%s", sBuffer);
	}
	
	return Plugin_Continue;
}

public Action Timer_CalculateEstimatedLevelupTime(Handle timer)
{
	int iCount, iTotalExp;
	for(int client=1;client<=MaxClients;client++)
	{
		if(!IsClientInGame(client))
			continue;
		
		iCount = GetArraySize(g_hExperienceMemory[client]);
		if(iCount < EXP_MEMORY_SIZE)
		{
			g_hExperienceMemory[client].Push(g_iExperienceThisMinute[client]);
		}
		// Keep the array at EXP_MEMORY_SIZE size
		else
		{
			g_hExperienceMemory[client].ShiftUp(0);
			g_hExperienceMemory[client].Set(0, g_iExperienceThisMinute[client]);
			g_hExperienceMemory[client].Erase(EXP_MEMORY_SIZE);
		}
		
		// Start counting experience for the next minute.
		g_iExperienceThisMinute[client] = 0;
		
		// Get the average over the past few minutes
		iCount = g_hExperienceMemory[client].Length;
		iTotalExp = 0;
		for(int i=0;i<iCount;i++)
		{
			iTotalExp += g_hExperienceMemory[client].Get(i);
		}
		
		g_fExperienceAverage[client] = float(iTotalExp)/float(iCount);
	}
}

public void SMRPG_OnAddExperiencePost(int client, const char[] reason, int iExperience, int other)
{
	g_iLastExperience[client] = iExperience;
	g_iExperienceThisMinute[client] += iExperience;
}

/**
 * RPG Topmenu stuff
 */

public void SMRPG_OnRPGMenuReady(TopMenu topmenu)
{
	// Block us from being called twice!
	if(g_hRPGMenu == topmenu)
		return;
	
	g_hRPGMenu = topmenu;
	
	TopMenuObject iTopMenuSettings = g_hRPGMenu.FindCategory(RPGMENU_SETTINGS);
	if(iTopMenuSettings != INVALID_TOPMENUOBJECT)
	{
		g_hRPGMenu.AddItem("rpgkeyhint_showinfo", TopMenu_SettingsItemHandler, iTopMenuSettings);
	}
}

public void TopMenu_SettingsItemHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxlength, "%T: %T", "Hide stats info panel on the right", param, (g_bClientHidePanel[param]?"Yes":"No"), param);
		}
		case TopMenuAction_SelectOption:
		{
			g_bClientHidePanel[param] = !g_bClientHidePanel[param];
			
			if(g_hCookieHidePanel != null && AreClientCookiesCached(param))
			{
				char sBuffer[4];
				IntToString(g_bClientHidePanel[param], sBuffer, sizeof(sBuffer));
				SetClientCookie(param, g_hCookieHidePanel, sBuffer);
			}
			
			topmenu.Display(param, TopMenuPosition_LastCategory);
			
			// Hide the panel right away to be responsive!
			if(g_bClientHidePanel[param] && !g_bIsCSGO)
				Client_PrintKeyHintText(param, "");
		}
	}
}

// Taken from SourceBans 2's sb_bans :)
void SecondsToString(char[] sBuffer, int iLength, int iSecs, bool bTextual = true)
{
	if(bTextual)
	{
		char sDesc[6][8] = {"mo",              "wk",             "d",          "hr",    "min", "sec"};
		int  iCount, iDiv[6]    = {60 * 60 * 24 * 30, 60 * 60 * 24 * 7, 60 * 60 * 24, 60 * 60, 60,    1};
		sBuffer[0]              = '\0';
		
		for(int i = 0; i < sizeof(iDiv); i++)
		{
			if((iCount = iSecs / iDiv[i]) > 0)
			{
				Format(sBuffer, iLength, "%s%i %s, ", sBuffer, iCount, sDesc[i]);
				iSecs %= iDiv[i];
			}
		}
		sBuffer[strlen(sBuffer) - 2] = '\0';
	}
	else
	{
		int iHours = iSecs  / 60 / 60;
		iSecs     -= iHours * 60 * 60;
		int iMins  = iSecs  / 60;
		iSecs     %= 60;
		Format(sBuffer, iLength, "%02i:%02i:%02i", iHours, iMins, iSecs);
	}
}