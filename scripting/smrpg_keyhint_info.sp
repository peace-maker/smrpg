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

// RPG Topmenu
new Handle:g_hRPGMenu;

// Clientprefs
new bool:g_bClientHidePanel[MAXPLAYERS+1];
new Handle:g_hCookieHidePanel;

// Last experience memory
new g_iLastExperience[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SMRPG > Key Hint Infopanel",
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

public OnClientDisconnect(client)
{
	g_bClientHidePanel[client] = false;
	g_iLastExperience[client] = 0;
}

public OnMapStart()
{
	CreateTimer(1.0, Timer_ShowInfoPanel, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action:Timer_ShowInfoPanel(Handle:timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new iTarget, Obs_Mode:iMode, String:sBuffer[512];
	new iLevel;
	
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
		Format(sBuffer, sizeof(sBuffer), "%s\n%T\n", sBuffer, "Level", i, iLevel);
		Format(sBuffer, sizeof(sBuffer), "%s%T\n", sBuffer, "Experience short", i, SMRPG_GetClientExperience(iTarget), SMRPG_LevelToExperience(iLevel));
		Format(sBuffer, sizeof(sBuffer), "%s%T\n", sBuffer, "Credits", i, SMRPG_GetClientCredits(iTarget));
		Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Rank", i, SMRPG_GetClientRank(iTarget), iRankCount);
		
		if(g_iLastExperience[iTarget] > 0)
			Format(sBuffer, sizeof(sBuffer), "%s\n%T: +%d", sBuffer, "Last Experience Short", i, g_iLastExperience[iTarget]);
		
		if(SMRPG_IsClientAFK(iTarget))
			Format(sBuffer, sizeof(sBuffer), "%s\n\n%T", sBuffer, "Player is AFK", i);
		
		Client_PrintKeyHintText(i, sBuffer);
	}
	
	return Plugin_Continue;
}

public Action:SMRPG_OnAddExperience(client, const String:reason[], &iExperience, other)
{
	g_iLastExperience[client] = iExperience;
	return Plugin_Continue;
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