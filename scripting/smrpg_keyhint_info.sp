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
// Choose where to show the panel in. See PanelDisplayType enum.
ConVar g_hCVPanelType;
ConVar g_hCVPanelUseHTML;
ConVar g_hCVPanelColor;
ConVar g_hCVPanelPosition;

enum PanelDisplayType {
	DisplayType_Hint,		// Show info panel in the hint are in the middle of the screen.
	DisplayType_KeyHint,	// Show info panel on the right side of the screen. (CS:S)
	DisplayType_HudMsg		// Show info panel on arbitary position on the screen.
};

// RPG Topmenu
TopMenu g_hRPGMenu;

// Clientprefs
bool g_bClientHidePanel[MAXPLAYERS+1];
Handle g_hCookieHidePanel;

// HUD synchronizer object to help keep the hud on the
// screen without interferring with other plugins.
Handle g_hHUDSync;

// Last experience memory
int g_iLastExperience[MAXPLAYERS+1];
ArrayList g_hExperienceMemory[MAXPLAYERS+1];
int g_iExperienceThisMinute[MAXPLAYERS+1];
float g_fExperienceAverage[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG > Stats Info Panel",
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

	bool bIsCSGO = GetEngineVersion() == Engine_CSGO;

	g_hCVDefaultHidePanel = AutoExecConfig_CreateConVar("smrpg_hide_infopanel_default", "0", "Hide the info panel by default for new players? They'll have to enable it themselves.", 0, true, 0.0, true, 1.0);
	g_hCVPanelType = AutoExecConfig_CreateConVar("smrpg_infopanel_type", (bIsCSGO ? "2" :"1"), "Select where to display the panel. 0 - Show info panel in hint area in the center-bottom box, 1 - Show info panel in keyhint area on the right side of the screen, 2 - Show info panel on arbitary position on the screen specified by other convars.", _, true, 0.0, true, 2.0);
	g_hCVPanelUseHTML = AutoExecConfig_CreateConVar("smrpg_infopanel_use_html", (bIsCSGO ? "1" :"0"), "Use HTML to format the hint text. Some games like CS:GO support a limited set of HTML tags in hint messages.");
	g_hCVPanelColor = AutoExecConfig_CreateConVar("smrpg_infopanel_color", "0 200 200 200", "The text color of on-screen info panel when smrpg_hud_type is set to 1 in 'r g b a'.");
	g_hCVPanelPosition = AutoExecConfig_CreateConVar("smrpg_infopanel_position", "-1 0.1", "Relative position of on-screen info panel in 'x y' format. Values can go from 0.0 to 1.0 starting at the top left corner. -1 is the center.");
	
	AutoExecConfig_ExecuteFile();

	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	LoadTranslations("smrpg_keyhint_info.phrases");
	
	TopMenu hTopMenu;
	if((hTopMenu = SMRPG_GetTopMenu()) != null)
		SMRPG_OnRPGMenuReady(hTopMenu);
	
	if(LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}

	g_hHUDSync = CreateHudSynchronizer();
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
	int iRankCount = SMRPG_GetRankCount();
	
	PanelDisplayType iPanelType = view_as<PanelDisplayType>(g_hCVPanelType.IntValue);

	// Setup HudMsg with correct color etc.
	if (iPanelType == DisplayType_HudMsg)
	{
		int iColor[4];
		float fPosition[2];
		iColor = GetHUDColor();
		fPosition = GetHUDPosition();
		SetHudTextParams(fPosition[0], fPosition[1], 5.0, iColor[0], iColor[1], iColor[2], iColor[3], 1, 1.0, 0.0, 0.0);
	}

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
			
		// Show the name of the player he's spectating
		if(iTarget != i)
		{
			switch(iPanelType)
			{
				case DisplayType_Hint, DisplayType_HudMsg:
				{
					Format(sBuffer, sizeof(sBuffer), "%T\n", "Show for other player", i, "RPG stats", iTarget);

					// Substitute the HTML heading formating in the phrase.
					if(iPanelType == DisplayType_Hint && g_hCVPanelUseHTML.BoolValue)
					{
						char sStatsHeader[64], sHTMLHeader[128];
						Format(sStatsHeader, sizeof(sStatsHeader), "%T", "RPG stats", i);
						Format(sHTMLHeader, sizeof(sHTMLHeader), "<font size=\"20\"><u>%s</u></font>", sStatsHeader);
						ReplaceString(sBuffer, sizeof(sBuffer), sStatsHeader, sHTMLHeader);
					}
				}
				case DisplayType_KeyHint:
				{
					Format(sBuffer, sizeof(sBuffer), "%T\n%N\n", "RPG stats", i, iTarget);
				}
			}
		}
		// Show plain "Stats" header
		else
		{
			if(iPanelType == DisplayType_Hint && g_hCVPanelUseHTML.BoolValue)
				Format(sBuffer, sizeof(sBuffer), "<font size=\"20\"><u>%T</u></font>\n", "RPG stats", i);
			else
				Format(sBuffer, sizeof(sBuffer), "%T\n", "RPG stats", i);
		}
		
		iLevel = SMRPG_GetClientLevel(iTarget);
		iExp = SMRPG_GetClientExperience(iTarget),
		iExpForLevel = SMRPG_LevelToExperience(iLevel);
		
		switch(iPanelType)
		{
			case DisplayType_Hint:
			{
				if(g_hCVPanelUseHTML.BoolValue)
				{
					Format(sBuffer, sizeof(sBuffer), "%s<font size=\"16\">%T\t", sBuffer, "Level", i, iLevel);
					Format(sBuffer, sizeof(sBuffer), "%s%T\t", sBuffer, "Experience short", i, iExp, iExpForLevel);
					Format(sBuffer, sizeof(sBuffer), "%s%T</font>", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
				}
				else
				{
					Format(sBuffer, sizeof(sBuffer), "%s%T    ", sBuffer, "Level", i, iLevel);
					Format(sBuffer, sizeof(sBuffer), "%s%T    ", sBuffer, "Experience short", i, iExp, iExpForLevel);
					Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
				}
			}
			case DisplayType_KeyHint:
			{
				Format(sBuffer, sizeof(sBuffer), "%s\n%T\n", sBuffer, "Level", i, iLevel);
				Format(sBuffer, sizeof(sBuffer), "%s%T\n", sBuffer, "Experience short", i, iExp, iExpForLevel);
				Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
			}
			case DisplayType_HudMsg:
			{
				Format(sBuffer, sizeof(sBuffer), "%s%T\t", sBuffer, "Level", i, iLevel);
				Format(sBuffer, sizeof(sBuffer), "%s%T\t", sBuffer, "Experience short", i, iExp, iExpForLevel);
				Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
			}
		}
		
		// No place in the hint box for that. :(
		if(iPanelType != DisplayType_Hint || !g_hCVPanelUseHTML.BoolValue)
		{
			int iRank = SMRPG_GetClientRank(iTarget);
			if(iRank > 0)
				Format(sBuffer, sizeof(sBuffer), "%s\n%T", sBuffer, "Rank", i, iRank, iRankCount);
		}
		
		if(g_fExperienceAverage[iTarget] > 0.0)
		{
			iExpNeeded = iExpForLevel - iExp;
			SecondsToString(sTime, sizeof(sTime), RoundToCeil(float(iExpNeeded)/g_fExperienceAverage[iTarget]*SECONDS_EXP_AVG_CALC));
			
			switch(iPanelType)
			{
				case DisplayType_Hint:
				{
					if(g_hCVPanelUseHTML.BoolValue)
						Format(sBuffer, sizeof(sBuffer), "%s\t<font size=\"15\" color=\"#00ff00\"><i>%T: %s</i></font>", sBuffer, "Estimated time until levelup", i, sTime);
					else
						Format(sBuffer, sizeof(sBuffer), "%s\n%T: %s", sBuffer, "Estimated time until levelup", i, sTime);
				}
				case DisplayType_KeyHint:
				{
					Format(sBuffer, sizeof(sBuffer), "%s\n%T: %s", sBuffer, "Estimated time until levelup", i, sTime);
				}
				case DisplayType_HudMsg:
				{
					Format(sBuffer, sizeof(sBuffer), "%s\n%T: %s", sBuffer, "Estimated time until levelup", i, sTime);
				}
			}
		}
		
		if(iPanelType != DisplayType_Hint || !g_hCVPanelUseHTML.BoolValue)
		{
			if(g_iLastExperience[iTarget] > 0)
				Format(sBuffer, sizeof(sBuffer), "%s\n%T: +%d", sBuffer, "Last Experience Short", i, g_iLastExperience[iTarget]);

			if(SMRPG_IsClientAFK(iTarget))
				Format(sBuffer, sizeof(sBuffer), "%s\n\n%T", sBuffer, "Player is AFK", i);
		}
		
		switch(iPanelType)
		{
			case DisplayType_Hint:
				PrintHintText(i, "%s", sBuffer);
			case DisplayType_KeyHint:
				Client_PrintKeyHintText(i, "%s", sBuffer);
			case DisplayType_HudMsg:
				ShowSyncHudText(i, g_hHUDSync, "%s", sBuffer);
		}
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
	return Plugin_Continue;
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
			Format(buffer, maxlength, "%T: %T", "Hide stats info panel", param, (g_bClientHidePanel[param]?"Yes":"No"), param);
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
			
			// The panel will be shown in the next timer iteration.
			if(!g_bClientHidePanel[param])
				return;

			// Hide the panel right away to be responsive!
			switch(view_as<PanelDisplayType>(g_hCVPanelType.IntValue))
			{
				case DisplayType_KeyHint:
					Client_PrintKeyHintText(param, "");
				case DisplayType_HudMsg:
					ClearSyncHud(param, g_hHUDSync);
			}
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

int[] GetHUDColor()
{
	int iColor[4];
	
	// Parse the color string 'r g b a' into the array.
	char sColor[32], sSplit[4][8];
	g_hCVPanelColor.GetString(sColor, sizeof(sColor));
	ExplodeString(sColor, " ", sSplit, sizeof(sSplit), sizeof(sSplit[]));
	for (int i; i < sizeof(iColor); i++)
	{
		iColor[i] = StringToInt(sSplit[i]);
	}
	return iColor;
}

float[] GetHUDPosition()
{
	float fPosition[2];
	
	// Parse the color string 'r g b a' into the array.
	char sPosition[16], sSplit[2][8];
	g_hCVPanelPosition.GetString(sPosition, sizeof(sPosition));
	ExplodeString(sPosition, " ", sSplit, sizeof(sSplit), sizeof(sSplit[]));
	for (int i; i < sizeof(fPosition); i++)
	{
		fPosition[i] = StringToFloat(sSplit[i]);
	}
	return fPosition;
}
