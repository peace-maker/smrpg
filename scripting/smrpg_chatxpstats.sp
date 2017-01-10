#pragma semicolon 1
#include <sourcemod>
#include <topmenus>
#include <smrpg>
#include <smlib/clients>

#pragma newdecls required
#undef REQUIRE_EXTENSIONS
#include <clientprefs>

// RPG Topmenu
TopMenu g_hRPGMenu;

// Clientprefs
bool g_bClientPrintKillXP[MAXPLAYERS+1];
Handle g_hCookiePrintKillXP;
bool g_bClientPrintLifeXP[MAXPLAYERS+1];
Handle g_hCookiePrintLifeXP;

// Convars
ConVar g_hCVPrintKillXP;
ConVar g_hCVPrintLifeXP;

// Last experience memory
int g_iExpSinceSpawn[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG > Chat Experience Stats",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Shows some RPG stats on events in chat",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
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
	for(int i=1;i<=MaxClients;i++)
		OnClientDisconnect(i);
	
	TopMenu hTopMenu;
	if((hTopMenu = SMRPG_GetTopMenu()) != null)
		SMRPG_OnRPGMenuReady(hTopMenu);
}

public void OnClientDisconnect(int client)
{
	g_iExpSinceSpawn[client] = 0;
	g_bClientPrintKillXP[client] = g_hCVPrintKillXP.BoolValue;
	g_bClientPrintLifeXP[client] = g_hCVPrintLifeXP.BoolValue;
}

/**
 * Client preferences handling
 */
public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookiePrintKillXP = RegClientCookie("smrpg_chatxpstats_killxp", "Show earned experience for kill when killing someone?", CookieAccess_Protected);
		g_hCookiePrintLifeXP = RegClientCookie("smrpg_chatxpstats_lifexp", "Print total experience earned during your last life?", CookieAccess_Protected);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookiePrintKillXP = null;
		g_hCookiePrintLifeXP = null;
	}
}

public void OnClientCookiesCached(int client)
{
	char sBuffer[4];
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
public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
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
public void SMRPG_OnAddExperiencePost(int client, const char[] reason, int iExperience, int other)
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
		g_hRPGMenu.AddItem("rpgchatxpstats_xpforkill", TopMenu_SettingsItemHandler, iTopMenuSettings);
		g_hRPGMenu.AddItem("rpgchatxpstats_xplastlife", TopMenu_SettingsItemHandler, iTopMenuSettings);
	}
}

public void TopMenu_SettingsItemHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sBuffer[32];
			topmenu.GetObjName(object_id, sBuffer, sizeof(sBuffer));
			
			if(StrEqual(sBuffer, "rpgchatxpstats_xpforkill", false))
				Format(buffer, maxlength, "%T: %T", "Print xp for last kill in chat", param, (g_bClientPrintKillXP[param]?"Yes":"No"), param);
			else if(StrEqual(sBuffer, "rpgchatxpstats_xplastlife", false))
				Format(buffer, maxlength, "%T: %T", "Print total xp last life in chat", param, (g_bClientPrintLifeXP[param]?"Yes":"No"), param);
		}
		case TopMenuAction_SelectOption:
		{
			char sBuffer[32];
			topmenu.GetObjName(object_id, sBuffer, sizeof(sBuffer));
			
			if(StrEqual(sBuffer, "rpgchatxpstats_xpforkill", false))
			{
				g_bClientPrintKillXP[param] = !g_bClientPrintKillXP[param];
			
				if(g_hCookiePrintKillXP != null && AreClientCookiesCached(param))
				{
					IntToString(g_bClientPrintKillXP[param], sBuffer, sizeof(sBuffer));
					SetClientCookie(param, g_hCookiePrintKillXP, sBuffer);
				}
			}
			else if(StrEqual(sBuffer, "rpgchatxpstats_xplastlife", false))
			{
				g_bClientPrintLifeXP[param] = !g_bClientPrintLifeXP[param];
			
				if(g_hCookiePrintLifeXP != null && AreClientCookiesCached(param))
				{
					IntToString(g_bClientPrintLifeXP[param], sBuffer, sizeof(sBuffer));
					SetClientCookie(param, g_hCookiePrintLifeXP, sBuffer);
				}
			}
			
			g_hRPGMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}