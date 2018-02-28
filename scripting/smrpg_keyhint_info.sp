#pragma semicolon 1
#include <sourcemod>
#include <topmenus>
#include <smrpg>
#include <autoexecconfig>
#include <smlib/clients>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#pragma newdecls required

#define SECONDS_EXP_AVG_CALC 60.0
#define EXP_MEMORY_SIZE 10

// Convar to set whether to show the panel to new players by default.
ConVar g_hCVDefaultHidePanel;
ConVar gc_iRed;
ConVar gc_iBlue;
ConVar gc_iGreen;
ConVar gc_iAlpha;
ConVar gc_fX;
ConVar gc_fY;

// RPG Topmenu
TopMenu g_hRPGMenu;

// Clientprefs
bool g_bClientHidePanel[MAXPLAYERS+1];
Handle g_hCookieHidePanel;
Handle g_hHUD;
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
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	AutoExecConfig_SetFile("plugin.smrpg_keyhint_info");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(null);

	g_hCVDefaultHidePanel = AutoExecConfig_CreateConVar("smrpg_hide_infopanel_default", "0", "Hide the info panel by default for new players? They'll have to enable it themselves.", 0, true, 0.0, true, 1.0);
	gc_fX = AutoExecConfig_CreateConVar("sm_hud_x", "-1", "x coordinate, from 0 to 1. -1.0 is the center of sm_hud_type '1'", _, true, -1.0, true, 1.0);
	gc_fY = AutoExecConfig_CreateConVar("sm_hud_y", "0.1", "y coordinate, from 0 to 1. -1.0 is the center of sm_hud_type '1'", _, true, -1.0, true, 1.0);
	gc_iRed = AutoExecConfig_CreateConVar("sm_hud_red", "0", "Color of sm_hud_type '1' (set R, G and B values to 255 to disable) (Rgb): x - red value", _, true, 0.0, true, 255.0);
	gc_iBlue = AutoExecConfig_CreateConVar("sm_hud_green", "200", "Color of sm_hud_type '1' (set R, G and B values to 255 to disable) (rGb): x - green value", _, true, 0.0, true, 255.0);
	gc_iGreen = AutoExecConfig_CreateConVar("sm_hud_blue", "200", "Color of sm_hud_type '1' (set R, G and B values to 255 to disable) (rgB): x - blue value", _, true, 0.0, true, 255.0);
	gc_iAlpha = AutoExecConfig_CreateConVar("sm_hud_alpha", "200", "Alpha value of sm_hud_type '1' (set value to 255 to disable for transparency)", _, true, 0.0, true, 255.0);
	
	AutoExecConfig_ExecuteFile();

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
	g_hHUD = CreateHudSynchronizer();
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "clientprefs") && !g_hCookieHidePanel)
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
	// Only use the cookie value if the player already set it.
	if (sBuffer[0] != '\0')
		g_bClientHidePanel[client] = StringToInt(sBuffer)==1;
	// Fall back to the default value for new players.
	else
		g_bClientHidePanel[client] = g_hCVDefaultHidePanel.BoolValue;
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
	SetHudTextParams(gc_fX.FloatValue, gc_fY.FloatValue, 5.0, gc_iRed.IntValue, gc_iGreen.IntValue, gc_iBlue.IntValue, gc_iAlpha.IntValue, 1, 1.0, 0.0, 0.0);
	int iRankCount = SMRPG_GetRankCount();
	for(int i=1;i<=MaxClients;i++)
	{
		// This player doesn't want this info.
		if(g_bClientHidePanel[i])
			continue;
		
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;
		ClearSyncHud(i, g_hHUD);
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
			strcopy(sBuffer, sizeof(sBuffer), "RPG Stats");
		else
			strcopy(sBuffer, sizeof(sBuffer), "RPG Stats\n");
			
		// Show the name of the player he's spectating
		if(iTarget != i)
		{
			if (g_bIsCSGO)
				Format(sBuffer, sizeof(sBuffer), "%s for %N\n", sBuffer, iTarget);
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
			Format(sBuffer, sizeof(sBuffer), "%s%T\t", sBuffer, "Level", i, iLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T\t", sBuffer, "Experience short", i, iExp, iExpForLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
		}
		else
		{
			Format(sBuffer, sizeof(sBuffer), "%s\n%T\n", sBuffer, "Level", i, iLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T\n", sBuffer, "Experience short", i, iExp, iExpForLevel);
			Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
		}
		
		int iRank = SMRPG_GetClientRank(iTarget);
		if(iRank > 0)
			Format(sBuffer, sizeof(sBuffer), "%s\n%T", sBuffer, "Rank", i, iRank, iRankCount);
		
		if(g_fExperienceAverage[iTarget] > 0.0)
		{
			iExpNeeded = iExpForLevel - iExp;
			SecondsToString(sTime, sizeof(sTime), RoundToCeil(float(iExpNeeded)/g_fExperienceAverage[iTarget]*SECONDS_EXP_AVG_CALC));
			
			if (g_bIsCSGO)
				Format(sBuffer, sizeof(sBuffer), "%s\t%T: %s", sBuffer, "Estimated time until levelup", i, sTime);
			else
				Format(sBuffer, sizeof(sBuffer), "%s\n%T: %s", sBuffer, "Estimated time until levelup", i, sTime);
		}
		
		if(g_iLastExperience[iTarget] > 0)
			Format(sBuffer, sizeof(sBuffer), "%s\n%T: +%d", sBuffer, "Last Experience Short", i, g_iLastExperience[iTarget]);

		if(SMRPG_IsClientAFK(iTarget))
			Format(sBuffer, sizeof(sBuffer), "%s\n\n%T", sBuffer, "Player is AFK", i);
		
		if (g_bIsCSGO)
			ShowSyncHudText(i, g_hHUD, "%s", sBuffer);
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
