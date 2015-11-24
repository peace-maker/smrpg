#pragma semicolon 1
#include <sourcemod>
#include <topmenus>
#include <smrpg>
#include <smlib/clients>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#define PLUGIN_VERSION "1.0"

// RPG Topmenu
new Handle:g_hRPGMenu;

// Clientprefs
new bool:g_bClientPrintKillXP[MAXPLAYERS+1];
new Handle:g_hCookiePrintKillXP;
new bool:g_bClientPrintLifeXP[MAXPLAYERS+1];
new Handle:g_hCookiePrintLifeXP;

// Convars
new Handle:g_hCVPrintKillXP;
new Handle:g_hCVPrintLifeXP;

// Last experience memory
new g_iExpSinceSpawn[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG > Chat Experience Stats",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Shows some RPG stats on events in chat",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg_chatxpstats.phrases");
	
	HookEvent("player_death", Event_OnPlayerDeath);
	
	g_hCVPrintKillXP = CreateConVar("smrpg_chatxpstats_printkillxp", "0", "Show experience earned for last kill in chat by default?", _, true, 0.0, true, 1.0);
	g_hCVPrintLifeXP = CreateConVar("smrpg_chatxpstats_printlifexp", "0", "Show total experience earned during last life in chat by default?", _, true, 0.0, true, 1.0);
	
	AutoExecConfig();
	
	if(LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
	
	// Initialize default values.
	for(new i=1;i<=MaxClients;i++)
		OnClientDisconnect(i);
	
	new Handle:hTopMenu;
	if((hTopMenu = SMRPG_GetTopMenu()) != INVALID_HANDLE)
		SMRPG_OnRPGMenuReady(hTopMenu);
}

public OnClientDisconnect(client)
{
	g_iExpSinceSpawn[client] = 0;
	g_bClientPrintKillXP[client] = GetConVarBool(g_hCVPrintKillXP);
	g_bClientPrintLifeXP[client] = GetConVarBool(g_hCVPrintLifeXP);
}

/**
 * Client preferences handling
 */
public OnLibraryAdded(const String:name[])
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookiePrintKillXP = RegClientCookie("smrpg_chatxpstats_killxp", "Show earned experience for kill when killing someone?", CookieAccess_Protected);
		g_hCookiePrintLifeXP = RegClientCookie("smrpg_chatxpstats_lifexp", "Print total experience earned during your last life?", CookieAccess_Protected);
	}
}

public OnLibraryRemoved(const String:name[])
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookiePrintKillXP = INVALID_HANDLE;
		g_hCookiePrintLifeXP = INVALID_HANDLE;
	}
}

public OnClientCookiesCached(client)
{
	new String:sBuffer[4];
	GetClientCookie(client, g_hCookiePrintKillXP, sBuffer, sizeof(sBuffer));
	if(strlen(sBuffer) > 0)
		g_bClientPrintKillXP[client] = StringToInt(sBuffer)==1;
	GetClientCookie(client, g_hCookiePrintLifeXP, sBuffer, sizeof(sBuffer));
	if(strlen(sBuffer) > 0)
		g_bClientPrintLifeXP[client] = StringToInt(sBuffer)==1;
}

/**
 * Event callbacks
 */
public Event_OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	// No xp earned? No need to say that..
	if(!g_iExpSinceSpawn[client])
		return;
	
	if(g_bClientPrintLifeXP[client])
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Total earned experience during past life", g_iExpSinceSpawn[client]);
	Client_PrintToConsole(client, "{OG}SM:RPG{N} > {G}%t", "Total earned experience during past life", g_iExpSinceSpawn[client]);
	
	g_iExpSinceSpawn[client] = 0;
}

/**
 * SM:RPG callbacks
 */
public SMRPG_OnAddExperiencePost(client, const String:reason[], iExperience, other)
{
	g_iExpSinceSpawn[client] += iExperience;
	
	if(other > 0
	&& (StrEqual(reason, ExperienceReason_PlayerKill)
	|| StrEqual(reason, "cs_playerkill")))
	{
		if(g_bClientPrintKillXP[client])
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Earned experience for kill", iExperience, other);
		Client_PrintToConsole(client, "{OG}SM:RPG{N} > {G}%t", "Earned experience for kill", iExperience, other);
	}
	
	return;
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
		AddToTopMenu(g_hRPGMenu, "rpgchatxpstats_xpforkill", TopMenuObject_Item, TopMenu_SettingsItemHandler, iTopMenuSettings);
		AddToTopMenu(g_hRPGMenu, "rpgchatxpstats_xplastlife", TopMenuObject_Item, TopMenu_SettingsItemHandler, iTopMenuSettings);
	}
}

public TopMenu_SettingsItemHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			decl String:sBuffer[32];
			GetTopMenuObjName(topmenu, object_id, sBuffer, sizeof(sBuffer));
			
			if(StrEqual(sBuffer, "rpgchatxpstats_xpforkill", false))
				Format(buffer, maxlength, "%T: %T", "Print xp for last kill in chat", param, (g_bClientPrintKillXP[param]?"Yes":"No"), param);
			else if(StrEqual(sBuffer, "rpgchatxpstats_xplastlife", false))
				Format(buffer, maxlength, "%T: %T", "Print total xp last life in chat", param, (g_bClientPrintLifeXP[param]?"Yes":"No"), param);
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sBuffer[32];
			GetTopMenuObjName(topmenu, object_id, sBuffer, sizeof(sBuffer));
			
			if(StrEqual(sBuffer, "rpgchatxpstats_xpforkill", false))
			{
				g_bClientPrintKillXP[param] = !g_bClientPrintKillXP[param];
			
				if(g_hCookiePrintKillXP != INVALID_HANDLE && AreClientCookiesCached(param))
				{
					IntToString(g_bClientPrintKillXP[param], sBuffer, sizeof(sBuffer));
					SetClientCookie(param, g_hCookiePrintKillXP, sBuffer);
				}
			}
			else if(StrEqual(sBuffer, "rpgchatxpstats_xplastlife", false))
			{
				g_bClientPrintLifeXP[param] = !g_bClientPrintLifeXP[param];
			
				if(g_hCookiePrintLifeXP != INVALID_HANDLE && AreClientCookiesCached(param))
				{
					IntToString(g_bClientPrintLifeXP[param], sBuffer, sizeof(sBuffer));
					SetClientCookie(param, g_hCookiePrintLifeXP, sBuffer);
				}
			}
			
			DisplayTopMenu(g_hRPGMenu, param, TopMenuPosition_LastCategory);
		}
	}
}