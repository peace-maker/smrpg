#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#define PLUGIN_VERSION "1.0"

new Handle:g_hTopMenu;
new bool:g_bDisableExperience[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG > Disable experience",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Lets admins disable any experience gainings for players.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	RegAdminCmd("sm_togglexp", Cmd_ToggleExp, ADMFLAG_CHEATS, "Toggle experience gaining for a player. Usage sm_toggleexp <name|steamid|#userid>", "smrpg");
	RegAdminCmd("sm_listdisabledexp", Cmd_ListDisabledExp, ADMFLAG_CHEATS, "Lists all players and whether they have experience disabled or not.", "smrpg");
	
	LoadTranslations("common.phrases");
	
	HookEvent("player_disconnect", Event_OnPlayerDisconnect);
	
	// See if the menu plugin is already ready
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}
}

// Only reset on real disconnects. Don't care for mapchanges.
public Event_OnPlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	// TODO: Remember setting over disconnects? (clientpref)
	g_bDisableExperience[client] = false;
}

public Action:Cmd_ToggleExp(client, args)
{
	if(args < 1)
	{
		// Open the menu if no target specified.
		if(!client)
			ReplyToCommand(client, "SM:RPG > Toggle experience gaining for a player. Usage sm_toggleexp <name|steamid|#userid>");
		else
			DisplayPlayerList(client);
		return Plugin_Handled;
	}
	
	decl String:sTarget[MAX_NAME_LENGTH];
	GetCmdArgString(sTarget, sizeof(sTarget));
	StripQuotes(sTarget);
	TrimString(sTarget);
	
	new iTarget = FindTarget(client, sTarget);
	if(iTarget == -1)
		return Plugin_Handled;
	
	g_bDisableExperience[iTarget] = !g_bDisableExperience[iTarget];
	
	if(g_bDisableExperience[iTarget])
		ReplyToCommand(client, "{OG}SM:RPG{N} > {G}Disabled experience for %N. No more experience for that one.", iTarget);
	else
		ReplyToCommand(client, "{OG}SM:RPG{N} > {G}Enabled experience for %N again.", iTarget);
	
	LogAction(client, iTarget, "%L %s experience gaining for %L.", client, (g_bDisableExperience[iTarget]?"disabled":"enabled"), iTarget);
	
	return Plugin_Handled;
}

public Action:Cmd_ListDisabledExp(client, args)
{
	decl String:sAuth[64];
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(!GetClientAuthId(i, AuthId_Engine, sAuth, sizeof(sAuth)))
			sAuth[0] = 0;
		
		ReplyToCommand(client, "SM:RPG > %N <%s>: %s", i, sAuth, (g_bDisableExperience[i]?"Disabled":"Enabled"));
	}
}

public Action:SMRPG_OnAddExperience(client, const String:reason[], &iExperience, other)
{
	// Don't give him any regular experience.
	if(g_bDisableExperience[client] && !StrEqual(reason, ExperienceReason_Admin))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

/**
 * Admin menu integration.
 */
public OnAdminMenuReady(Handle:topmenu)
{
	// Get the rpg category
	new TopMenuObject:iRPGCategory = FindTopMenuCategory(topmenu, "SM:RPG");
	
	if(iRPGCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == topmenu)
		return;
	
	g_hTopMenu = topmenu;
	
	AddToTopMenu(topmenu, "Toggle experience", TopMenuObject_Item, TopMenu_AdminHandleToggleExp, iRPGCategory, "sm_togglexp", ADMFLAG_CHEATS);
}

public TopMenu_AdminHandleToggleExp(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Toggle experience");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayPlayerList(param);
	}
}

DisplayPlayerList(client, iPosition=0)
{
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerlist);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Toggle experience on..");
	
	new bool:bIgnoreBots = SMRPG_IgnoreBots();
	
	decl String:sBuffer[128], String:sUserId[16], String:sAuth[64];
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i) || (bIgnoreBots && IsFakeClient(i)) || IsClientSourceTV(i) || IsClientReplay(i))
			continue;
		
		if(!GetClientAuthId(i, AuthId_Engine, sAuth, sizeof(sAuth)))
			sAuth[0] = 0;
		
		Format(sBuffer, sizeof(sBuffer), "%N <%s>: %T", i, sAuth, (g_bDisableExperience[i]?"Off":"On"), client);
		IntToString(GetClientUserId(i), sUserId, sizeof(sUserId));
		AddMenuItem(hMenu, sUserId, sBuffer);
	}
	
	DisplayMenuAtItem(hMenu, client, iPosition, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerlist(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			RedisplayAdminMenu(g_hTopMenu, param1);
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		new iUserId = StringToInt(sInfo);
		
		new iTarget = GetClientOfUserId(iUserId);
		if(iTarget > 0)
		{
			g_bDisableExperience[iTarget] = !g_bDisableExperience[iTarget];
			LogAction(param1, iTarget, "%L %s experience gaining for %L.", param1, (g_bDisableExperience[iTarget]?"disabled":"enabled"), iTarget);
		}
		
		DisplayPlayerList(param1, GetMenuSelectionPosition());
	}
}