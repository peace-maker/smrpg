#pragma semicolon 1
#include <sourcemod>
#include <topmenus>
#include <smrpg>
#include <smlib/clients>
#include <smrpg/smrpg_clients>
#include <smrpg/smrpg_topmenu>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#define PLUGIN_VERSION "1.0"

#define SECONDS_EXP_AVG_CALC 60.0
#define EXP_MEMORY_SIZE 10

// RPG Topmenu
new Handle:g_hRPGMenu;

// Clientprefs
new bool:g_bClientHidePanel[MAXPLAYERS+1];
new Handle:g_hCookieHidePanel;

// Last experience memory
new g_iLastExperience[MAXPLAYERS+1];
new Handle:g_hExperienceMemory[MAXPLAYERS+1];
new g_iExperienceThisMinute[MAXPLAYERS+1];
new Float:g_fExperienceAverage[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG > Key Hint Infopanel",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Shows some RPG stats in a panel on the screen",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	LoadTranslations("smrpg_keyhint_info.phrases");
	
	new Handle:hTopMenu;
	if((hTopMenu = SMRPG_GetTopMenu()) != INVALID_HANDLE)
		SMRPG_OnRPGMenuReady(hTopMenu);
	
	if(LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public OnLibraryAdded(const String:name[])
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookieHidePanel = RegClientCookie("smrpg_keyhint_hide", "Hide the info panel on the right side of the screen showing RPG stats.", CookieAccess_Protected);
	}
}

public OnLibraryRemoved(const String:name[])
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookieHidePanel = INVALID_HANDLE;
	}
}

public OnClientCookiesCached(client)
{
	decl String:sBuffer[4];
	GetClientCookie(client, g_hCookieHidePanel, sBuffer, sizeof(sBuffer));
	g_bClientHidePanel[client] = StringToInt(sBuffer)==1;
}

public OnClientPutInServer(client)
{
	g_hExperienceMemory[client] = CreateArray();
}

public OnClientDisconnect(client)
{
	g_bClientHidePanel[client] = false;
	g_iLastExperience[client] = 0;
	ClearHandle(g_hExperienceMemory[client]);
	g_iExperienceThisMinute[client] = 0;
	g_fExperienceAverage[client] = 0.0;
}

public OnMapStart()
{
	CreateTimer(1.0, Timer_ShowInfoPanel, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	CreateTimer(SECONDS_EXP_AVG_CALC, Timer_CalculateEstimatedLevelupTime, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action:Timer_ShowInfoPanel(Handle:timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new iTarget, Obs_Mode:iMode, String:sBuffer[512];
	new iLevel, iExp, iExpForLevel, iExpNeeded, String:sTime[32];
	
	new iRankCount = SMRPG_GetRankCount();
	for(new i=1;i<=MaxClients;i++)
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
			if(iTarget <= 0)
				continue;
		}
		
		strcopy(sBuffer, sizeof(sBuffer), "RPG Stats\n");
		// Show the name of the player he's spectating
		if(iTarget != i)
			Format(sBuffer, sizeof(sBuffer), "%s%N\n", sBuffer, iTarget);
		
		iLevel = SMRPG_GetClientLevel(iTarget);
		iExp = SMRPG_GetClientExperience(iTarget),
		iExpForLevel = SMRPG_LevelToExperience(iLevel);
		Format(sBuffer, sizeof(sBuffer), "%s\n%T\n", sBuffer, "Level", i, iLevel);
		Format(sBuffer, sizeof(sBuffer), "%s%T\n", sBuffer, "Experience short", i, iExp, iExpForLevel);
		Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
		
		new iRank = SMRPG_GetClientRank(iTarget);
		if(iRank > 0)
			Format(sBuffer, sizeof(sBuffer), "%s\n%T", sBuffer, "Rank", i, iRank, iRankCount);
		
		if(g_fExperienceAverage[iTarget] > 0.0)
		{
			iExpNeeded = iExpForLevel - iExp;
			SecondsToString(sTime, sizeof(sTime), RoundToCeil(float(iExpNeeded)/g_fExperienceAverage[iTarget]*SECONDS_EXP_AVG_CALC));
			Format(sBuffer, sizeof(sBuffer), "%s\n%T: %s", sBuffer, "Estimated time until levelup", i, sTime);
		}
		
		if(g_iLastExperience[iTarget] > 0)
			Format(sBuffer, sizeof(sBuffer), "%s\n%T: +%d", sBuffer, "Last Experience Short", i, g_iLastExperience[iTarget]);
		
		if(SMRPG_IsClientAFK(iTarget))
			Format(sBuffer, sizeof(sBuffer), "%s\n\n%T", sBuffer, "Player is AFK", i);
		
		Client_PrintKeyHintText(i, sBuffer);
	}
	
	return Plugin_Continue;
}

public Action:Timer_CalculateEstimatedLevelupTime(Handle:timer)
{
	new iCount, iTotalExp;
	for(new client=1;client<=MaxClients;client++)
	{
		if(!IsClientInGame(client))
			continue;
		
		iCount = GetArraySize(g_hExperienceMemory[client]);
		if(iCount < EXP_MEMORY_SIZE)
		{
			PushArrayCell(g_hExperienceMemory[client], g_iExperienceThisMinute[client]);
		}
		// Keep the array at EXP_MEMORY_SIZE size
		else
		{
			ShiftArrayUp(g_hExperienceMemory[client], 0);
			SetArrayCell(g_hExperienceMemory[client], 0, g_iExperienceThisMinute[client]);
			RemoveFromArray(g_hExperienceMemory[client], EXP_MEMORY_SIZE);
		}
		
		// Start counting experience for the next minute.
		g_iExperienceThisMinute[client] = 0;
		
		// Get the average over the past few minutes
		iCount = GetArraySize(g_hExperienceMemory[client]);
		iTotalExp = 0;
		for(new i=0;i<iCount;i++)
		{
			iTotalExp += GetArrayCell(g_hExperienceMemory[client], i);
		}
		
		g_fExperienceAverage[client] = float(iTotalExp)/float(iCount);
	}
}

public SMRPG_OnAddExperiencePost(client, const String:reason[], iExperience, other)
{
	g_iLastExperience[client] = iExperience;
	g_iExperienceThisMinute[client] += iExperience;
}

/**
 * RPG Topmenu stuff
 */

public SMRPG_OnRPGMenuReady(Handle:topmenu)
{
	// Block us from being called twice!
	if(g_hRPGMenu == topmenu)
		return;
	
	g_hRPGMenu = topmenu;
	
	new TopMenuObject:iTopMenuSettings = FindTopMenuCategory(g_hRPGMenu, RPGMENU_SETTINGS);
	if(iTopMenuSettings != INVALID_TOPMENUOBJECT)
	{
		AddToTopMenu(g_hRPGMenu, "rpgkeyhint_showinfo", TopMenuObject_Item, TopMenu_SettingsItemHandler, iTopMenuSettings);
	}
}

public TopMenu_SettingsItemHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
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
			
			if(g_hCookieHidePanel != INVALID_HANDLE && AreClientCookiesCached(param))
			{
				decl String:sBuffer[4];
				IntToString(g_bClientHidePanel[param], sBuffer, sizeof(sBuffer));
				SetClientCookie(param, g_hCookieHidePanel, sBuffer);
			}
			
			DisplayTopMenu(g_hRPGMenu, param, TopMenuPosition_LastCategory);
			
			// Hide the panel right away to be responsive!
			if(g_bClientHidePanel[param])
				Client_PrintKeyHintText(param, "");
		}
	}
}

// Taken from SourceBans 2's sb_bans :)
SecondsToString(String:sBuffer[], iLength, iSecs, bool:bTextual = true)
{
	if(bTextual)
	{
		decl String:sDesc[6][8] = {"mo",              "wk",             "d",          "hr",    "min", "sec"};
		new  iCount, iDiv[6]    = {60 * 60 * 24 * 30, 60 * 60 * 24 * 7, 60 * 60 * 24, 60 * 60, 60,    1};
		sBuffer[0]              = '\0';
		
		for(new i = 0; i < sizeof(iDiv); i++)
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
		new iHours = iSecs  / 60 / 60;
		iSecs     -= iHours * 60 * 60;
		new iMins  = iSecs  / 60;
		iSecs     %= 60;
		Format(sBuffer, iLength, "%02i:%02i:%02i", iHours, iMins, iSecs);
	}
}