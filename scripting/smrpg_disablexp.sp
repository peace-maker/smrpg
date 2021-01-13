#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma newdecls required

TopMenu g_hTopMenu;
bool g_bDisableExperience[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG > Disable experience",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Lets admins disable any experience gainings for players.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	RegAdminCmd("sm_togglexp", Cmd_ToggleExp, ADMFLAG_CHEATS, "Toggle experience gaining for a player. Usage sm_toggleexp <name|steamid|#userid>", "smrpg");
	RegAdminCmd("sm_listdisabledexp", Cmd_ListDisabledExp, ADMFLAG_CHEATS, "Lists all players and whether they have experience disabled or not.", "smrpg");
	
	LoadTranslations("common.phrases");
	
	HookEvent("player_disconnect", Event_OnPlayerDisconnect);
	
	// See if the menu plugin is already ready
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}
}

// Only reset on real disconnects. Don't care for mapchanges.
public void Event_OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	// TODO: Remember setting over disconnects? (clientpref)
	g_bDisableExperience[client] = false;
}

public Action Cmd_ToggleExp(int client, int args)
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
	
	char sTarget[256];
	GetCmdArgString(sTarget, sizeof(sTarget));
	StripQuotes(sTarget);
	TrimString(sTarget);
	
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	int iCountEnabled, iCountDisabled;
	
	for(int i=0;i<iTargetCount;i++)
	{
		g_bDisableExperience[iTargetList[i]] = !g_bDisableExperience[iTargetList[i]];
		
		if(g_bDisableExperience[iTargetList[i]])
		{
			iCountDisabled++;
			LogAction(client, iTargetList[i], "%L disabled experience gaining for %L.", client, iTargetList[i]);
		}
		else
		{
			iCountEnabled++;
			LogAction(client, iTargetList[i], "%L enabled experience gaining for %L.", client, iTargetList[i]);
		}
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L toggled experience gaining on %T (%d players).", client, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG > Experience gaining has been toggled on %t (%d players).", sTargetName, iTargetCount);
	}
	else
	{
		if(g_bDisableExperience[iTargetList[0]])
			ReplyToCommand(client, "SM:RPG > Disabled experience for %N. No more experience for that one.", iTargetList[0]);
		else
			ReplyToCommand(client, "SM:RPG > Enabled experience for %N again.", iTargetList[0]);
	}
	
	return Plugin_Handled;
}

public Action Cmd_ListDisabledExp(int client, int args)
{
	char sAuth[64];
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(!GetClientAuthId(i, AuthId_Engine, sAuth, sizeof(sAuth)))
			sAuth[0] = 0;
		
		ReplyToCommand(client, "SM:RPG > %N <%s>: %s", i, sAuth, (g_bDisableExperience[i]?"Disabled":"Enabled"));
	}
}

public Action SMRPG_OnAddExperience(int client, const char[] reason, int &iExperience, int other)
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
public void OnAdminMenuReady(Handle topmenu)
{
	// Get the rpg category
	TopMenuObject iRPGCategory = FindTopMenuCategory(topmenu, "SM:RPG");
	
	if(iRPGCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == view_as<TopMenu>(topmenu))
		return;
	
	g_hTopMenu = view_as<TopMenu>(topmenu);
	
	g_hTopMenu.AddItem("Toggle experience", TopMenu_AdminHandleToggleExp, iRPGCategory, "sm_togglexp", ADMFLAG_CHEATS);
}

public void TopMenu_AdminHandleToggleExp(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
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

void DisplayPlayerList(int client, int iPosition=0)
{
	Menu hMenu = new Menu(Menu_HandlePlayerlist);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("Toggle experience on..");
	
	bool bIgnoreBots = SMRPG_IgnoreBots();
	
	char sBuffer[128], sUserId[16], sAuth[64];
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i) || (bIgnoreBots && IsFakeClient(i)) || IsClientSourceTV(i) || IsClientReplay(i))
			continue;

		// Player is immune?
		if (!CanUserTarget(client, i))
			continue;
		
		if(!GetClientAuthId(i, AuthId_Engine, sAuth, sizeof(sAuth)))
			sAuth[0] = 0;
		
		Format(sBuffer, sizeof(sBuffer), "%N <%s>: %T", i, sAuth, (g_bDisableExperience[i]?"Off":"On"), client);
		IntToString(GetClientUserId(i), sUserId, sizeof(sUserId));
		hMenu.AddItem(sUserId, sBuffer);
	}
	
	hMenu.DisplayAt(client, iPosition, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerlist(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack && g_hTopMenu != null)
			RedisplayAdminMenu(g_hTopMenu, param1);
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		int iUserId = StringToInt(sInfo);
		
		int iTarget = GetClientOfUserId(iUserId);
		if(iTarget > 0)
		{
			g_bDisableExperience[iTarget] = !g_bDisableExperience[iTarget];
			LogAction(param1, iTarget, "%L %s experience gaining for %L.", param1, (g_bDisableExperience[iTarget]?"disabled":"enabled"), iTarget);
		}
		
		DisplayPlayerList(param1, GetMenuSelectionPosition());
	}
}