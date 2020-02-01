#pragma semicolon 1
#include <sourcemod>
// https://github.com/peace-maker/mapzonelib
#include <mapzonelib>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma newdecls required
#include <smrpg>

#define MAPZONE_GROUP "smrpg_noxp"

TopMenu g_hTopMenu;

// Count in how many no-exp zones a player is. Could be in multiple zones at once.
int g_iNumInNoXPZone[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG > No Experience Zones",
	author = "Peace-Maker",
	description = "Disable earning of experience in set zones on maps.",
	version = SMRPG_VERSION,
	url = "https://www.wcfan.de/"
}

public void OnPluginStart()
{
	RegAdminCmd("sm_noxpzones", Cmd_ShowZoneMenu, ADMFLAG_CONFIG, "Manage zones in which players get no XP.", "smrpg");
	
	RegAdminCmd("sm_listnoxp", Cmd_ListNoXP, ADMFLAG_CONFIG, "List players currently affected by this plugin.", "smrpg");
	
	// See if the menu plugin is already ready
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}
}

public void OnLibraryAdded(const char[] library)
{
	if(StrEqual(library, "mapzonelib"))
	{
		MapZone_RegisterZoneGroup(MAPZONE_GROUP);
		MapZone_SetMenuCancelAction(MAPZONE_GROUP, MapZone_OnMenuCancelAction);
		int iColor[] = {255,0,0,255};
		MapZone_SetZoneDefaultColor(MAPZONE_GROUP, iColor);
	}
}

public void OnClientDisconnect(int client)
{
	g_iNumInNoXPZone[client] = 0;
}

/**
 * Command callbacks
 */
public Action Cmd_ShowZoneMenu(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG > This command is ingame only.");
		return Plugin_Handled;
	}
	
	MapZone_ShowMenu(client, MAPZONE_GROUP);
	return Plugin_Handled;
}

public Action Cmd_ListNoXP(int client, int args)
{
	ReplyToCommand(client, "Listing players that are in a restricted zone:");
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(g_iNumInNoXPZone[client] > 0)
			ReplyToCommand(client, "SM:RPG > %N is in %d zones.", i, g_iNumInNoXPZone[client]);
	}
	
	return Plugin_Handled;
}

/**
 * Map zone callbacks
 */
public void MapZone_OnClientEnterZone(int client, const char[] sZoneGroup, const char[] sZoneName)
{
	// Only care for zones created by us.
	if(!StrEqual(sZoneGroup, MAPZONE_GROUP, false))
		return;
	
	g_iNumInNoXPZone[client]++;
}

public void MapZone_OnClientLeaveZone(int client, const char[] sZoneGroup, const char[] sZoneName)
{
	// Only care for zones created by us.
	if(!StrEqual(sZoneGroup, MAPZONE_GROUP, false))
		return;
	
	g_iNumInNoXPZone[client]--;
	if(g_iNumInNoXPZone[client] < 0)
		g_iNumInNoXPZone[client] = 0;
}

public void MapZone_OnMenuCancelAction(int client, int reason, const char[] group)
{
	if(!g_hTopMenu)
		return;
	
	RedisplayAdminMenu(g_hTopMenu, client);
}

/**
 * SM:RPG callbacks
 */
public Action SMRPG_OnAddExperience(int client, const char[] reason, int &iExperience, int other)
{
	// Allow admins to change the players even though they're in a noxp zone.
	if (StrEqual(reason, ExperienceReason_Admin))
		return Plugin_Continue;

	// Don't give him any regular experience, if he's in a noxp zone.
	if(g_iNumInNoXPZone[client] > 0
	// or the target is in one.
	|| (other > 0 && g_iNumInNoXPZone[other] > 0))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

/**
 * Admin menu integration.
 */
public void OnAdminMenuReady(Handle topmenu)
{
	// Get the rpg category
	TopMenu adminmenu = TopMenu.FromHandle(topmenu);
	TopMenuObject iRPGCategory = adminmenu.FindCategory("SM:RPG");
	
	if(iRPGCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == adminmenu)
		return;
	
	g_hTopMenu = adminmenu;
	
	adminmenu.AddItem("Manage no XP zones", TopMenu_AdminHandleZones, iRPGCategory, "sm_noxpzones", ADMFLAG_CONFIG);
}

public void TopMenu_AdminHandleZones(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Manage no XP zones");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		MapZone_ShowMenu(param, MAPZONE_GROUP);
	}
}
