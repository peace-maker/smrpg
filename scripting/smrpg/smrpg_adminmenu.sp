#pragma semicolon 1
#include <sourcemod>
#include <adminmenu>

TopMenuObject g_TopMenuCategory;
TopMenu g_hTopMenu;

int g_iCurrentMenuTarget[MAXPLAYERS+1] = {-1,...};
int g_iCurrentUpgradeTarget[MAXPLAYERS+1] = {-1,...};
int g_iCurrentPage[MAXPLAYERS+1];

enum ChangeUpgradeProperty {
	ChangeProp_None = 0,
	ChangeProp_MaxlevelBarrier,
	ChangeProp_Maxlevel,
	ChangeProp_Cost,
	ChangeProp_Icost
};

ChangeUpgradeProperty g_iClientChangesProperty[MAXPLAYERS+1];

enum UpgradeLevelChange {
	UpgradeChange_Reset,
	UpgradeChange_Remove,
	UpgradeChange_Add,
	UpgradeChange_Max
}

UpgradeLevelChange g_iClientUpgradeChangeMode[MAXPLAYERS+1];

public void OnAdminMenuCreated(Handle topmenu)
{
	TopMenu adminTopmenu = TopMenu.FromHandle(topmenu);
	if(adminTopmenu == g_hTopMenu && g_TopMenuCategory)
		return;
	
	g_TopMenuCategory = adminTopmenu.AddCategory("SM:RPG", TopMenu_AdminCategoryHandler, "smrpg_adminmenu", ADMFLAG_CONFIG);
}

public void TopMenu_AdminCategoryHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayTitle)
	{
		Format(buffer, maxlength, "SM:RPG %T:", "Commands", param);
	}
	else if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "SM:RPG %T", "Commands", param);
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	TopMenu adminMenu = TopMenu.FromHandle(topmenu);
	// Try to add the category first
	if(g_TopMenuCategory == INVALID_TOPMENUOBJECT)
		OnAdminMenuCreated(topmenu);
	// Still failed..
	if(g_TopMenuCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == adminMenu)
		return;
	
	g_hTopMenu = adminMenu;
	
	adminMenu.AddItem("Manage players", TopMenu_AdminHandlePlayers, g_TopMenuCategory, "smrpg_players_menu", ADMFLAG_CONFIG);
	adminMenu.AddItem("Manage upgrades", TopMenu_AdminHandleUpgrades, g_TopMenuCategory, "smrpg_upgrades_menu", ADMFLAG_CONFIG);
}

public void TopMenu_AdminHandlePlayers(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%T", "Manage players", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		ShowPlayerListMenu(param);
	}
}

bool ShowRPGAdminMenu(int client)
{
	if (g_hTopMenu == null || g_TopMenuCategory == INVALID_TOPMENUOBJECT)
		return false;
	
	g_hTopMenu.DisplayCategory(g_TopMenuCategory, client);
	return true;
}

void ShowPlayerListMenu(int client)
{
	Menu hMenu = new Menu(Menu_HandlePlayerList);
	hMenu.SetTitle("%T", "Select player", client);
	hMenu.ExitBackButton = true;
	
	// Add all players
	AddTargetsToMenu2(hMenu, 0, 0);
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerList(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowRPGAdminMenu(param1);
	}
	else if(action == MenuAction_Select)
	{
		char sUserId[16];
		menu.GetItem(param2, sUserId, sizeof(sUserId));
		int userid = StringToInt(sUserId);
		
		int iTarget = GetClientOfUserId(userid);
		// Player no longer available?
		if(!iTarget)
		{
			ShowPlayerListMenu(param1);
			return;
		}
		
		g_iCurrentMenuTarget[param1] = iTarget;
		ShowPlayerDetailMenu(param1);
	}
}

void ShowPlayerDetailMenu(int client)
{
	int iTarget = g_iCurrentMenuTarget[client];
	
	Menu hMenu = new Menu(Menu_HandlePlayerDetails);
	hMenu.SetTitle("SM:RPG %T > %N", "Player Details", client, iTarget);
	hMenu.ExitBackButton = true;
	
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "%T", "Manage stats", client);
	hMenu.AddItem("stats", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%T", "Manage upgrades", client);
	hMenu.AddItem("upgrades", sBuffer);
	if(CheckCommandAccess(client, "smrpg_resetstats", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Reset player", client);
		hMenu.AddItem("reset", sBuffer);
	}
	hMenu.AddItem("", "", ITEMDRAW_DISABLED|ITEMDRAW_SPACER);
	Format(sBuffer, sizeof(sBuffer), "%T", "Level", client, GetClientLevel(iTarget));
	hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	Format(sBuffer, sizeof(sBuffer), "%T", "Experience short", client, GetClientExperience(iTarget), Stats_LvlToExp(GetClientLevel(iTarget)));
	hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	Format(sBuffer, sizeof(sBuffer), "%T", "Credits", client, GetClientCredits(iTarget));
	hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	Format(sBuffer, sizeof(sBuffer), "%T", "Rank", client, GetClientRank(iTarget), GetRankCount());
	hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	FormatTime(sBuffer, sizeof(sBuffer), "%c", GetPlayerLastReset(iTarget));
	Format(sBuffer, sizeof(sBuffer), "%T", "Last reset", client, sBuffer);
	hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerDetails(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iCurrentMenuTarget[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerListMenu(param1);
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "stats"))
		{
			ShowPlayerStatsManageMenu(param1);
		}
		else if(StrEqual(sInfo, "upgrades"))
		{
			ShowPlayerUpgradeManageMenu(param1);
		}
		else if(StrEqual(sInfo, "reset"))
		{
			Menu hMenu = new Menu(Menu_HandlePlayerResetConfirm, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
			hMenu.ExitBackButton = true;
			hMenu.SetTitle("%T", "Confirm reset player", param1, g_iCurrentMenuTarget[param1]);
			hMenu.AddItem("yes", "Yes");
			hMenu.AddItem("no", "No");
			hMenu.Display(param1, MENU_TIME_FOREVER);
		}
	}
}

public int Menu_HandlePlayerResetConfirm(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerDetailMenu(param1);
		else
			g_iCurrentMenuTarget[param1] = -1;
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no") || !CheckCommandAccess(param1, "smrpg_resetstats", ADMFLAG_ROOT))
		{
			ShowPlayerDetailMenu(param1);
			return 0;
		}
		
		ResetStats(g_iCurrentMenuTarget[param1]);
		SetPlayerLastReset(g_iCurrentMenuTarget[param1], GetTime());
		LogAction(param1, g_iCurrentMenuTarget[param1], "%L permanently reset all stats of player %L.", param1, g_iCurrentMenuTarget[param1]);
		Client_PrintToChat(param1, false, "SM:RPG resetstats: %T", "Inform player reset", param1, g_iCurrentMenuTarget[param1]);
		ShowPlayerDetailMenu(param1);
	}
	else if(action == MenuAction_DisplayItem)
	{
		/* Get the display string, we'll use it as a translation phrase */
		char sDisplay[64];
		menu.GetItem(param2, "", 0, _, sDisplay, sizeof(sDisplay));

		/* Translate the string to the client's language */
		char sBuffer[255];
		Format(sBuffer, sizeof(sBuffer), "%T", sDisplay, param1);

		/* Override the text */
		return RedrawMenuItem(sBuffer);
	}
	return 0;
}

void ShowPlayerStatsManageMenu(int client)
{
	Menu hMenu = new Menu(Menu_HandlePlayerStats);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("%T > %N", "Manage stats", client, g_iCurrentMenuTarget[client]);
	
	char sBuffer[256];
	if(CheckCommandAccess(client, "smrpg_setcredits", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Change credits", client);
		hMenu.AddItem("credits", sBuffer);
	}
	if(CheckCommandAccess(client, "smrpg_setexp", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Change experience", client);
		hMenu.AddItem("experience", sBuffer);
	}
	if(CheckCommandAccess(client, "smrpg_setlvl", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Change level", client);
		hMenu.AddItem("level", sBuffer);
	}
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerStats(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerDetailMenu(param1);
		else
			g_iCurrentMenuTarget[param1] = -1;
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "credits"))
		{
			ShowPlayerCreditsManageMenu(param1);
		}
		else if(StrEqual(sInfo, "experience"))
		{
			ShowPlayerExperienceManageMenu(param1);
		}
		else if(StrEqual(sInfo, "level"))
		{
			ShowPlayerLevelManageMenu(param1);
		}
	}
}

void ShowPlayerCreditsManageMenu(int client)
{
	Menu hMenu = new Menu(Menu_HandlePlayerChangeCredits);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("%T > %N\n%T", "Change credits", client, g_iCurrentMenuTarget[client], "Credits", client, GetClientCredits(g_iCurrentMenuTarget[client]));
	
	hMenu.AddItem("100", "+100");
	hMenu.AddItem("10", "+10");
	hMenu.AddItem("1", "+1");
	hMenu.AddItem("-1", "-1");
	hMenu.AddItem("-10", "-10");
	hMenu.AddItem("-100", "-100");
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerChangeCredits(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerStatsManageMenu(param1);
		else
			g_iCurrentMenuTarget[param1] = -1;
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		int iAmount = StringToInt(sInfo);
		
		int iOldCredits = GetClientCredits(g_iCurrentMenuTarget[param1]);
		
		SetClientCredits(g_iCurrentMenuTarget[param1], iOldCredits + iAmount);
		
		LogAction(param1, g_iCurrentMenuTarget[param1], "%L changed credits of %L by %d from %d to %d.", param1, g_iCurrentMenuTarget[param1], iAmount, iOldCredits, GetClientCredits(g_iCurrentMenuTarget[param1]));
		ShowPlayerCreditsManageMenu(param1);
	}
}

void ShowPlayerExperienceManageMenu(int client)
{
	Menu hMenu = new Menu(Menu_HandlePlayerChangeExperience);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("%T > %N\n%T", "Change experience", client, g_iCurrentMenuTarget[client], "Experience short", client, GetClientExperience(g_iCurrentMenuTarget[client]), Stats_LvlToExp(GetClientLevel(g_iCurrentMenuTarget[client])+1));
	
	hMenu.AddItem("1000", "+1000");
	hMenu.AddItem("100", "+100");
	hMenu.AddItem("10", "+10");
	hMenu.AddItem("-10", "-10");
	hMenu.AddItem("-100", "-100");
	hMenu.AddItem("-1000", "-1000");
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerChangeExperience(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerStatsManageMenu(param1);
		else
			g_iCurrentMenuTarget[param1] = -1;
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		int iAmount = StringToInt(sInfo);
	
		int iOldLevel = GetClientLevel(g_iCurrentMenuTarget[param1]);
		int iOldExperience = GetClientExperience(g_iCurrentMenuTarget[param1]);
		
		bool bSuccess;
		// If we're adding experience, add it properly and level up if necassary.
		if(iAmount > 0)
			bSuccess = Stats_AddExperience(g_iCurrentMenuTarget[param1], iAmount, ExperienceReason_Admin, false, -1, true);
		else
			bSuccess = SetClientExperience(g_iCurrentMenuTarget[param1], GetClientExperience(g_iCurrentMenuTarget[param1])+iAmount);
		
		if (!bSuccess)
			LogAction(param1, g_iCurrentMenuTarget[param1], "%L tried to change experience of %L by %d, but the command failed.", param1, g_iCurrentMenuTarget[param1], iAmount);
		else
			LogAction(param1, g_iCurrentMenuTarget[param1], "%L changed experience of %L by %d. He is now Level %d and has %d/%d Experience (previously Level %d with %d/%d Experience)", param1, g_iCurrentMenuTarget[param1], iAmount, GetClientLevel(g_iCurrentMenuTarget[param1]), GetClientExperience(g_iCurrentMenuTarget[param1]), Stats_LvlToExp(GetClientLevel(g_iCurrentMenuTarget[param1])), iOldLevel, iOldExperience, Stats_LvlToExp(iOldLevel));
		ShowPlayerExperienceManageMenu(param1);
	}
}

void ShowPlayerLevelManageMenu(int client)
{
	Menu hMenu = new Menu(Menu_HandlePlayerChangeLevel);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("%T > %N\n%T", "Change level", client, g_iCurrentMenuTarget[client], "Level", client, GetClientLevel(g_iCurrentMenuTarget[client]));
	
	hMenu.AddItem("10", "+10");
	hMenu.AddItem("5", "+5");
	hMenu.AddItem("1", "+1");
	hMenu.AddItem("-1", "-1");
	hMenu.AddItem("-5", "-5");
	hMenu.AddItem("-10", "-10");
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerChangeLevel(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerStatsManageMenu(param1);
		else
			g_iCurrentMenuTarget[param1] = -1;
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		int iAmount = StringToInt(sInfo);
		int iOldLevel = GetClientLevel(g_iCurrentMenuTarget[param1]);
	
		// Do a proper level up
		if(iAmount > 0)
		{
			Stats_PlayerNewLevel(g_iCurrentMenuTarget[param1], iAmount);
		}
		// Decrease level manually, don't touch the credits/items
		else
		{
			SetClientLevel(g_iCurrentMenuTarget[param1], GetClientLevel(g_iCurrentMenuTarget[param1])+iAmount);
			SetClientExperience(g_iCurrentMenuTarget[param1], 0);
			
			if(g_hCVAnnounceNewLvl.BoolValue)
				PrintToChatAll("%t", "Client level changed", g_iCurrentMenuTarget[param1], GetClientLevel(g_iCurrentMenuTarget[param1]));
		}
		
		LogAction(param1, g_iCurrentMenuTarget[param1], "%L changed level of %L by %d from %d to %d.", param1, g_iCurrentMenuTarget[param1], iAmount, iOldLevel, GetClientLevel(g_iCurrentMenuTarget[param1]));
		ShowPlayerLevelManageMenu(param1);
	}
}

void ShowPlayerUpgradeManageMenu(int client)
{
	Menu hMenu = new Menu(Menu_HandlePlayerUpgradeSelect);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("%T > %N", "Manage player upgrades", client, g_iCurrentMenuTarget[client]);
	
	int iTarget = g_iCurrentMenuTarget[client];
	
	if(CheckCommandAccess(client, "smrpg_giveall", ADMFLAG_ROOT))
	{
		char sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T", "Give all upgrades free", client);
		hMenu.AddItem("give_all", sBuffer);
		hMenu.AddItem("", "", ITEMDRAW_SPACER);
	}
	
	int iSize = GetUpgradeCount();
	InternalUpgradeInfo upgrade;
	int iCurrentLevel;
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH], sLine[128], sIndex[8], sPermissions[30], sTeamlock[32];
	for(int i=0;i<iSize;i++)
	{
		iCurrentLevel = GetClientPurchasedUpgradeLevel(iTarget, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
			continue;
		
		GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
		
		sPermissions[0] = 0;
		sTeamlock[0] = 0;
		
		// Print the required adminflags in a readable way
		if(upgrade.adminFlag > 0)
		{
			GetAdminFlagStringFromBits(upgrade.adminFlag, sPermissions, sizeof(sPermissions));
			Format(sPermissions, sizeof(sPermissions), "%T", "Adminflags hint", client, sPermissions);
		}
		
		// Warn the admin, that this player won't be able to use this upgrade.
		if(!HasAccessToUpgrade(g_iCurrentMenuTarget[client], upgrade))
			Format(sPermissions, sizeof(sPermissions), "%s %T", sPermissions, "Adminflags Admin Denied Warning", client);
		// Or if there are some permission restrictions specified, show the player is able to use it.
		else if(upgrade.adminFlag > 0)
			Format(sPermissions, sizeof(sPermissions), "%s %T", sPermissions, "Adminflags Admin Inform OK", client);
		
		// Print the required team
		if(upgrade.teamlock > 1 && upgrade.teamlock < GetTeamCount())
		{
			GetTeamName(upgrade.teamlock, sTeamlock, sizeof(sTeamlock));
			Format(sTeamlock, sizeof(sTeamlock), "%T", "Teamlock hint", client, sTeamlock);
		}
		
		IntToString(i, sIndex, sizeof(sIndex));
		if(iCurrentLevel >= upgrade.maxLevel)
		{
			Format(sLine, sizeof(sLine), "%T", "Admin player upgrades list item maxed", client, sTranslatedName, iCurrentLevel, upgrade.maxLevel, sPermissions, sTeamlock);
		}
		else
		{
			Format(sLine, sizeof(sLine), "%T", "Admin player upgrades list item", client, sTranslatedName, iCurrentLevel, upgrade.maxLevel, sPermissions, sTeamlock);
		}
		
		hMenu.AddItem(sIndex, sLine);
	}
	
	if(g_iCurrentPage[client] > 0)
		hMenu.DisplayAt(client, g_iCurrentPage[client], MENU_TIME_FOREVER);
	else
		hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerUpgradeSelect(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iCurrentPage[param1] = 0;
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerDetailMenu(param1);
		else
			g_iCurrentMenuTarget[param1] = -1;
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		g_iCurrentPage[param1] = GetMenuSelectionPosition();
		if(StrEqual(sInfo, "give_all") && CheckCommandAccess(param1, "smrpg_giveall", ADMFLAG_ROOT))
		{
			Menu hMenu = new Menu(Menu_HandlePlayerGiveAllConfirm, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
			hMenu.ExitBackButton = true;
			hMenu.SetTitle("%T", "Confirm max all player upgrades", param1, g_iCurrentMenuTarget[param1]);
			hMenu.AddItem("yes", "Yes");
			hMenu.AddItem("no", "No");
			hMenu.Display(param1, MENU_TIME_FOREVER);
			return;
		}
		
		int iItemIndex = StringToInt(sInfo);
		
		g_iCurrentUpgradeTarget[param1] = iItemIndex;
		ShowPlayerUpgradeLevelMenu(param1);
	}
}

public int Menu_HandlePlayerGiveAllConfirm(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerUpgradeManageMenu(param1);
		else
		{
			g_iCurrentMenuTarget[param1] = -1;
			g_iCurrentPage[param1] = 0;
		}
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no") || !CheckCommandAccess(param1, "smrpg_giveall", ADMFLAG_ROOT))
		{
			ShowPlayerUpgradeManageMenu(param1);
			return 0;
		}
		
		int iSize = GetUpgradeCount();
		InternalUpgradeInfo upgrade;
		for(int i=0;i<iSize;i++)
		{
			GetUpgradeByIndex(i, upgrade);
			if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
				continue;
			
			SetClientPurchasedUpgradeLevel(g_iCurrentMenuTarget[param1], i, upgrade.maxLevel);
			SetClientSelectedUpgradeLevel(g_iCurrentMenuTarget[param1], i, upgrade.maxLevel);
		}
		
		LogAction(param1, g_iCurrentMenuTarget[param1], "%L set all upgrades of %L to the maximal level at no charge.", param1, g_iCurrentMenuTarget[param1]);
		
		Client_PrintToChat(param1, false, "SM:RPG giveall: %T", "Inform player upgrades maxed", param1, g_iCurrentMenuTarget[param1]);
		ShowPlayerUpgradeManageMenu(param1);
	}
	else if(action == MenuAction_DisplayItem)
	{
		/* Get the display string, we'll use it as a translation phrase */
		char sDisplay[64];
		menu.GetItem(param2, "", 0, _, sDisplay, sizeof(sDisplay));

		/* Translate the string to the client's language */
		char sBuffer[255];
		Format(sBuffer, sizeof(sBuffer), "%T", sDisplay, param1);

		/* Override the text */
		return RedrawMenuItem(sBuffer);
	}
	return 0;
}

void ShowPlayerUpgradeLevelMenu(int client)
{
	int iItemIndex = g_iCurrentUpgradeTarget[client];
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
	{
		g_iCurrentUpgradeTarget[client] = -1;
		ShowPlayerUpgradeManageMenu(client);
		return;
	}
	
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
	
	Menu hMenu = new Menu(Menu_HandlePlayerUpgradeLevelChange);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("%T\n%T", "Change player upgrade level", client, g_iCurrentMenuTarget[client], "Current player upgrade level", client, sTranslatedName, GetClientPurchasedUpgradeLevel(g_iCurrentMenuTarget[client], iItemIndex), upgrade.maxLevel);
	
	char sBuffer[256];
	if (CheckCommandAccess(client, "smrpg_takeupgrade", ADMFLAG_ROOT)
	 || CheckCommandAccess(client, "smrpg_sellupgrade", ADMFLAG_ROOT)
	 || CheckCommandAccess(client, "smrpg_setupgradelvl", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Reset player upgrade level 0", client);
		hMenu.AddItem("reset", sBuffer);

		Format(sBuffer, sizeof(sBuffer), "%T", "Remove player upgrade level", client);
		hMenu.AddItem("remove", sBuffer);
	}

	if (CheckCommandAccess(client, "smrpg_giveupgrade", ADMFLAG_ROOT)
	 || CheckCommandAccess(client, "smrpg_buyupgrade", ADMFLAG_ROOT)
	 || CheckCommandAccess(client, "smrpg_setupgradelvl", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Add player upgrade level", client);
		hMenu.AddItem("add", sBuffer);

		Format(sBuffer, sizeof(sBuffer), "%T", "Set player upgrade level to max", client);
		hMenu.AddItem("max", sBuffer);
	}
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerUpgradeLevelChange(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iCurrentUpgradeTarget[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerUpgradeManageMenu(param1);
		else
		{
			g_iCurrentPage[param1] = 0;
			g_iCurrentMenuTarget[param1] = -1;
		}
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		InternalUpgradeInfo upgrade;
		int iItemIndex = g_iCurrentUpgradeTarget[param1];
		GetUpgradeByIndex(iItemIndex, upgrade);
		
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			ShowPlayerUpgradeManageMenu(param1);
			return;
		}

		if(StrEqual(sInfo, "reset"))
		{
			g_iClientUpgradeChangeMode[param1] = UpgradeChange_Reset;
			ShowPlayerUpgradeLevelRemoveMenu(param1);
		}
		else if(StrEqual(sInfo, "remove"))
		{
			g_iClientUpgradeChangeMode[param1] = UpgradeChange_Remove;
			ShowPlayerUpgradeLevelRemoveMenu(param1);
		}
		else if(StrEqual(sInfo, "add"))
		{
			g_iClientUpgradeChangeMode[param1] = UpgradeChange_Add;
			ShowPlayerUpgradeLevelAddMenu(param1);
		}
		else if(StrEqual(sInfo, "max"))
		{
			g_iClientUpgradeChangeMode[param1] = UpgradeChange_Max;
			ShowPlayerUpgradeLevelAddMenu(param1);
		}
	}
}

void ShowPlayerUpgradeLevelRemoveMenu(int client)
{
	int iItemIndex = g_iCurrentUpgradeTarget[client];
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
	{
		g_iCurrentUpgradeTarget[client] = -1;
		ShowPlayerUpgradeManageMenu(client);
		return;
	}
	
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
	
	Menu hMenu = new Menu(Menu_HandlePlayerUpgradeLevelRemove);
	hMenu.ExitBackButton = true;

	char sBuffer[256];
	if (g_iClientUpgradeChangeMode[client] == UpgradeChange_Reset)
		Format(sBuffer, sizeof(sBuffer), "%T", "Reset player upgrade level 0", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T", "Remove player upgrade level", client);
	hMenu.SetTitle("%T\n%s\n%T", "Change player upgrade level", client, g_iCurrentMenuTarget[client], sBuffer, "Current player upgrade level", client, sTranslatedName, GetClientPurchasedUpgradeLevel(g_iCurrentMenuTarget[client], iItemIndex), upgrade.maxLevel);
	
	
	if (CheckCommandAccess(client, "smrpg_setupgradelvl", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Take player upgrade level full refund", client);
		hMenu.AddItem("fullrefund", sBuffer);
	}

	if (CheckCommandAccess(client, "smrpg_sellupgrade", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Force player sell upgrade level", client);
		hMenu.AddItem("forcesell", sBuffer);
	}

	if (CheckCommandAccess(client, "smrpg_takeupgrade", ADMFLAG_ROOT) || CheckCommandAccess(client, "smrpg_setupgradelvl", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Take player upgrade level no refund", client);
		hMenu.AddItem("norefund", sBuffer);
	}
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerUpgradeLevelRemove(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerUpgradeLevelMenu(param1);
		else
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			g_iCurrentPage[param1] = 0;
			g_iCurrentMenuTarget[param1] = -1;
		}
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		InternalUpgradeInfo upgrade;
		int iUpgradeIndex = g_iCurrentUpgradeTarget[param1];
		GetUpgradeByIndex(iUpgradeIndex, upgrade);
		
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			ShowPlayerUpgradeManageMenu(param1);
			return;
		}
		
		int iTarget = g_iCurrentMenuTarget[param1];
		int iOldLevel = GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex);
		int iCreditsReturned;

		// Want to take all the levels of this upgrade and set to to level 0.
		if(g_iClientUpgradeChangeMode[param1] == UpgradeChange_Reset)
		{
			if(StrEqual(sInfo, "fullrefund"))
			{
				while(TakeClientUpgrade(iTarget, iUpgradeIndex))
				{
					// Full refund
					iCreditsReturned += GetUpgradeCost(iUpgradeIndex, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex)+1);
					SetClientCredits(iTarget, GetClientCredits(iTarget) + GetUpgradeCost(iUpgradeIndex, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex)+1));
				}
				LogAction(param1, iTarget, "%L reset upgrade %s of %L with full refund of all upgrade costs. Upgrade level changed from %d to %d and player earned %d credits.", param1, upgrade.name, iTarget, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex), iCreditsReturned);
			}
			else if(StrEqual(sInfo, "forcesell"))
			{
				while(SellClientUpgrade(iTarget, iUpgradeIndex))
				{
					iCreditsReturned += GetUpgradeSale(iUpgradeIndex, iOldLevel);
					iOldLevel--;
				}
				LogAction(param1, iTarget, "%L forced %L to sell all levels of upgrade %s. Upgrade level changed from %d to %d and player earned %d credits.", param1, iTarget, upgrade.name, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex), iCreditsReturned);
			}
			else if(StrEqual(sInfo, "norefund"))
			{
				while(TakeClientUpgrade(iTarget, iUpgradeIndex))
				{
				}
				LogAction(param1, iTarget, "%L reset upgrade %s of %L with no refund. Upgrade level changed from %d to %d.", param1, upgrade.name, iTarget, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex));
			}

			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param1, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
			Client_PrintToChat(param1, false, "{OG}SM:RPG{N} > {G}%T", "Admin reset player upgrades notification", param1, iTarget, sTranslatedName, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex), iCreditsReturned);
		}
		else if (g_iClientUpgradeChangeMode[param1] == UpgradeChange_Remove)
		{
			if(StrEqual(sInfo, "fullrefund"))
			{
				if(TakeClientUpgrade(iTarget, iUpgradeIndex))
				{
					// Full refund
					int iCosts = GetUpgradeCost(iUpgradeIndex, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex)+1);
					SetClientCredits(iTarget, GetClientCredits(iTarget) + iCosts);
					LogAction(param1, iTarget, "%L took one level of upgrade %s from %L with full refund of the costs. Upgrade level changed from %d to %d and player got %d credits.", param1, upgrade.name, iTarget, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex), iCosts);
				}
			}
			else if(StrEqual(sInfo, "forcesell"))
			{
				if(SellClientUpgrade(iTarget, iUpgradeIndex))
				{
					LogAction(param1, iTarget, "%L forced %L to sell one level of upgrade %s. Upgrade level changed from %d to %d and player got %d credits..", param1, iTarget, upgrade.name, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex), GetUpgradeSale(iUpgradeIndex, iOldLevel));
				}
			}
			else if(StrEqual(sInfo, "norefund"))
			{
				if(TakeClientUpgrade(iTarget, iUpgradeIndex))
				{
					// Full refund
					int iCosts = GetUpgradeCost(iUpgradeIndex, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex)+1);
					SetClientCredits(iTarget, GetClientCredits(iTarget) + iCosts);
					LogAction(param1, iTarget, "%L took one level of upgrade %s from %L with full refund of the costs. Upgrade level changed from %d to %d and player got %d credits.", param1, upgrade.name, iTarget, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex), iCosts);
				}
			}
		}
		
		ShowPlayerUpgradeLevelRemoveMenu(param1);
	}
}

void ShowPlayerUpgradeLevelAddMenu(int client)
{
	int iItemIndex = g_iCurrentUpgradeTarget[client];
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
	{
		g_iCurrentUpgradeTarget[client] = -1;
		ShowPlayerUpgradeManageMenu(client);
		return;
	}
	
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
	
	Menu hMenu = new Menu(Menu_HandlePlayerUpgradeLevelAdd);
	hMenu.ExitBackButton = true;

	char sBuffer[256];
	if (g_iClientUpgradeChangeMode[client] == UpgradeChange_Add)
		Format(sBuffer, sizeof(sBuffer), "%T", "Add player upgrade level", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T", "Set player upgrade level to max", client);
	hMenu.SetTitle("%T\n%s\n%T", "Change player upgrade level", client, g_iCurrentMenuTarget[client], sBuffer, "Current player upgrade level", client, sTranslatedName, GetClientPurchasedUpgradeLevel(g_iCurrentMenuTarget[client], iItemIndex), upgrade.maxLevel);
	
	
	if (CheckCommandAccess(client, "smrpg_giveupgrade", ADMFLAG_ROOT) || CheckCommandAccess(client, "smrpg_setupgradelvl", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Give player upgrade level for free", client);
		hMenu.AddItem("givefree", sBuffer);
	}


	if (CheckCommandAccess(client, "smrpg_buyupgrade", ADMFLAG_ROOT))
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Force player buy upgrade level", client);
		hMenu.AddItem("forcebuy", sBuffer);
	}
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerUpgradeLevelAdd(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerUpgradeLevelMenu(param1);
		else
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			g_iCurrentPage[param1] = 0;
			g_iCurrentMenuTarget[param1] = -1;
		}
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		InternalUpgradeInfo upgrade;
		int iUpgradeIndex = g_iCurrentUpgradeTarget[param1];
		GetUpgradeByIndex(iUpgradeIndex, upgrade);
		
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			ShowPlayerUpgradeManageMenu(param1);
			return;
		}
		
		int iTarget = g_iCurrentMenuTarget[param1];
		int iOldLevel = GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex);

		// Want to take all the levels of this upgrade and set to to level 0.
		if(g_iClientUpgradeChangeMode[param1] == UpgradeChange_Max)
		{
			if(StrEqual(sInfo, "givefree"))
			{
				while(GiveClientUpgrade(iTarget, iUpgradeIndex))
				{
				}
				LogAction(param1, iTarget, "%L gave %L the maximal level of upgrade %s at no charge. Upgrade level changed from %d to %d.", param1, iTarget, upgrade.name, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex));
			}
			else if(StrEqual(sInfo, "forcebuy"))
			{
				while(BuyClientUpgrade(iTarget, iUpgradeIndex))
				{
				}
				LogAction(param1, iTarget, "%L forced %L to buy as many levels of upgrade %s he can afford. Upgrade level changed from %d to %d and player earned %d credits.", param1, iTarget, upgrade.name, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex));
			}
		}
		else if (g_iClientUpgradeChangeMode[param1] == UpgradeChange_Add)
		{
			if(StrEqual(sInfo, "givefree"))
			{
				GiveClientUpgrade(iTarget, iUpgradeIndex);
				LogAction(param1, iTarget, "%L gave %L one level of upgrade %s at no charge. Upgrade level changed from %d to %d.", param1, iTarget, upgrade.name, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex));
			}
			else if(StrEqual(sInfo, "forcebuy"))
			{
				int iCost = GetUpgradeCost(iUpgradeIndex, iOldLevel+1);
				if(iCost > GetClientCredits(iTarget))
				{
					char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
					GetUpgradeTranslatedName(param1, upgrade.index, sTranslatedName, sizeof(sTranslatedName));

					Client_PrintToChat(param1, false, "{OG}SM:RPG{N} > {G}%T", "Admin force buy insufficient funds", param1, iTarget, sTranslatedName, GetClientCredits(iTarget), iCost);
				}
				else
				{
					BuyClientUpgrade(iTarget, iUpgradeIndex);
					LogAction(param1, iTarget, "%L forced %L to buy one level of upgrade %s. Upgrade level changed from %d to %d.", param1, iTarget, upgrade.name, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iUpgradeIndex));
				}
			}
		}
		
		ShowPlayerUpgradeLevelAddMenu(param1);
	}
}

// client disconnected. Reset all open admin menus so we don't try to change stuff on a different user out of a sudden.
void ResetAdminMenu(int client)
{
	for(int i=1;i<=MaxClients;i++)
	{
		if(g_iCurrentMenuTarget[i] == client && client != i)
		{
			g_iCurrentMenuTarget[i] = -1;
			ShowPlayerListMenu(i);
		}
	}
}


public void TopMenu_AdminHandleUpgrades(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%T", "Manage upgrades", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		ShowUpgradeListMenu(param);
	}
}

void ShowUpgradeListMenu(int client)
{
	Menu hMenu = new Menu(Menu_HandleSelectUpgrade);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("SM:RPG > %T", "Manage upgrades", client);
	
	int iSize = GetUpgradeCount();
	InternalUpgradeInfo upgrade;
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH], sIndex[8];
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade))
			continue;
		
		GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
		
		IntToString(i, sIndex, sizeof(sIndex));
		hMenu.AddItem(sIndex, sTranslatedName);
	}
	
	if(g_iCurrentPage[client] > 0)
		hMenu.DisplayAt(client, g_iCurrentPage[client], MENU_TIME_FOREVER);
	else
		hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleSelectUpgrade(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			ShowRPGAdminMenu(param1);
		else
			g_iCurrentPage[param1] = 0;
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		int iItemIndex = StringToInt(sInfo);
		
		g_iCurrentPage[param1] = GetMenuSelectionPosition();
		g_iCurrentUpgradeTarget[param1] = iItemIndex;
		ShowUpgradeManageMenu(param1);
	}
}

void ShowUpgradeManageMenu(int client)
{
	InternalUpgradeInfo upgrade;
	int iItemIndex = g_iCurrentUpgradeTarget[client];
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade))
	{
		g_iCurrentUpgradeTarget[client] = -1;
		RedisplayAdminMenu(g_hTopMenu, client);
		return;
	}
	
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
	
	Menu hMenu = new Menu(Menu_HandleUpgradeDetails);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("%T > %s\n%T", "Manage upgrades", client, sTranslatedName, "Upgrade short name", client, upgrade.shortName);
	
	char sBuffer[256];
	if(upgrade.enabled)
		Format(sBuffer, sizeof(sBuffer), "%T", "Admin disable upgrade", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T", "Admin enable upgrade", client);
	hMenu.AddItem("enable", sBuffer);
	
	if(!g_hCVIgnoreLevelBarrier.BoolValue)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Admin upgrade info maxlevel barrier", client, upgrade.maxLevelBarrier);
		hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	}
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Admin upgrade info maxlevel", client, upgrade.maxLevel);
	hMenu.AddItem("maxlevel", sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Admin upgrade info cost", client, upgrade.startCost);
	hMenu.AddItem("cost", sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Admin upgrade info increase cost", client, upgrade.incCost);
	hMenu.AddItem("icost", sBuffer);
	
	char sTeamlock[128] = "None";
	if(upgrade.teamlock >= 1 && upgrade.teamlock < GetTeamCount())
	{
		GetTeamName(upgrade.teamlock, sTeamlock, sizeof(sTeamlock));
	}
	Format(sBuffer, sizeof(sBuffer), "%T", "Admin upgrade info teamlock", client, sTeamlock);
	hMenu.AddItem("teamlock", sBuffer);
	
	if(upgrade.visualsConvar != null)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Admin upgrade info visual effects", client, upgrade.enableVisuals?"On":"Off");
		hMenu.AddItem("visuals", sBuffer);
	}
	
	if(upgrade.soundsConvar != null)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Admin upgrade info sound effects", client, upgrade.enableSounds?"On":"Off");
		hMenu.AddItem("sounds", sBuffer);
	}
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleUpgradeDetails(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iCurrentUpgradeTarget[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
			ShowUpgradeListMenu(param1);
		else
			g_iCurrentPage[param1] = 0;
	}
	else if(action == MenuAction_Select)
	{
		InternalUpgradeInfo upgrade;
		GetUpgradeByIndex(g_iCurrentUpgradeTarget[param1], upgrade);
	
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade))
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			ShowUpgradeListMenu(param1);
			return;
		}
		
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "enable"))
		{
			if(upgrade.enabled)
			{
				upgrade.enableConvar.SetBool(false);
				LogAction(param1, -1, "%L disabled upgrade %s temporarily.", param1, upgrade.name);
			}
			else
			{
				upgrade.enableConvar.SetBool(true);
				LogAction(param1, -1, "%L enabled upgrade %s temporarily.", param1, upgrade.name);
			}
			ShowUpgradeManageMenu(param1);
		}
		else if(StrEqual(sInfo, "maxlevel"))
		{
			ShowUpgradePropertyChangeMenu(param1, ChangeProp_Maxlevel);
		}
		else if(StrEqual(sInfo, "cost"))
		{
			ShowUpgradePropertyChangeMenu(param1, ChangeProp_Cost);
		}
		else if(StrEqual(sInfo, "icost"))
		{
			ShowUpgradePropertyChangeMenu(param1, ChangeProp_Icost);
		}
		else if(StrEqual(sInfo, "teamlock"))
		{
			int iTeamlock = upgrade.teamlock;
			iTeamlock++;
			if(iTeamlock <= 1)
				iTeamlock = 2; // Skip the spectator team..
			else if(iTeamlock >= GetTeamCount())
				iTeamlock = 0; // Toggle in a ring.
			
			// Get the correct name for the log.
			char sTeam[128] = "None";
			if(iTeamlock > 1)
				GetTeamName(iTeamlock, sTeam, sizeof(sTeam));
			
			upgrade.teamlockConvar.SetInt(iTeamlock);
			LogAction(param1, -1, "%L toggled the teamlock on upgrade %s temporarily to restrict to team \"%s\".", param1, upgrade.name, sTeam);
			ShowUpgradeManageMenu(param1);
		}
		else if(StrEqual(sInfo, "visuals"))
		{
			if(upgrade.enableVisuals)
			{
				upgrade.visualsConvar.SetBool(false);
				LogAction(param1, -1, "%L disabled upgrade %s's visual effects temporarily.", param1, upgrade.name);
			}
			else
			{
				upgrade.visualsConvar.SetBool(true);
				LogAction(param1, -1, "%L enabled upgrade %s's visual effects temporarily.", param1, upgrade.name);
			}
			ShowUpgradeManageMenu(param1);
		}
		else if(StrEqual(sInfo, "sounds"))
		{
			if(upgrade.enableSounds)
			{
				upgrade.soundsConvar.SetBool(false);
				LogAction(param1, -1, "%L disabled upgrade %s's sound effects temporarily.", param1, upgrade.name);
			}
			else
			{
				upgrade.soundsConvar.SetBool(true);
				LogAction(param1, -1, "%L enabled upgrade %s's sound effects temporarily.", param1, upgrade.name);
			}
			ShowUpgradeManageMenu(param1);
		}
	}
}

void ShowUpgradePropertyChangeMenu(int client, ChangeUpgradeProperty prop)
{
	InternalUpgradeInfo upgrade;
	int iItemIndex = g_iCurrentUpgradeTarget[client];
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade))
	{
		g_iClientChangesProperty[client] = ChangeProp_None;
		g_iCurrentUpgradeTarget[client] = -1;
		RedisplayAdminMenu(g_hTopMenu, client);
		return;
	}
	
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
	
	Menu hMenu = new Menu(Menu_HandlePropertyChange);
	hMenu.ExitBackButton = true;
	
	char sBuffer[512];
	Format(sBuffer, sizeof(sBuffer), "%T > %s\n%T\n", "Manage upgrades", client, sTranslatedName, "Upgrade short name", client, upgrade.shortName);
	switch(prop)
	{
		case ChangeProp_Maxlevel:
		{
			Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Admin upgrades change maxlevel", client, upgrade.maxLevel);
		}
		case ChangeProp_Cost:
		{
			Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Admin upgrades change start cost", client, upgrade.startCost);
		}
		case ChangeProp_Icost:
		{
			Format(sBuffer, sizeof(sBuffer), "%s%T", sBuffer, "Admin upgrades change increasing cost", client, upgrade.incCost);
		}
	}
	
	hMenu.SetTitle(sBuffer);
	
	hMenu.AddItem("10", "+10");
	hMenu.AddItem("5", "+5");
	hMenu.AddItem("1", "+1");
	hMenu.AddItem("-1", "-1");
	hMenu.AddItem("-5", "-5");
	hMenu.AddItem("-10", "-10");
	
	hMenu.Display(client, MENU_TIME_FOREVER);
	
	g_iClientChangesProperty[client] = prop;
}

public int Menu_HandlePropertyChange(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iClientChangesProperty[param1] = ChangeProp_None;
		if(param2 == MenuCancel_ExitBack)
			ShowUpgradeManageMenu(param1);
		else
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			g_iCurrentPage[param1] = 0;
		}
	}
	else if(action == MenuAction_Select)
	{
		InternalUpgradeInfo upgrade;
		GetUpgradeByIndex(g_iCurrentUpgradeTarget[param1], upgrade);
	
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade))
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			g_iClientChangesProperty[param1] = ChangeProp_None;
			ShowUpgradeListMenu(param1);
			return;
		}
		
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		int iChange = StringToInt(sInfo);
		switch(g_iClientChangesProperty[param1])
		{
			case ChangeProp_Maxlevel:
			{
				int iValue = upgrade.maxLevel + iChange;
				int iMaxLevelBarrier = upgrade.maxLevelBarrier;
				if(iValue > 0 && (iMaxLevelBarrier <= 0 || iValue <= iMaxLevelBarrier || g_hCVIgnoreLevelBarrier.BoolValue))
				{
					upgrade.maxLevelConvar.SetInt(iValue);
					LogAction(param1, -1, "%L changed maxlevel of upgrade %s temporarily from %d to %d.", param1, upgrade.name, upgrade.maxLevel, iValue);
				}
			}
			case ChangeProp_Cost:
			{
				int iValue = upgrade.startCost + iChange;
				if(iValue >= 0)
				{
					upgrade.startCostConvar.SetInt(iValue);
					LogAction(param1, -1, "%L changed start costs of upgrade %s temporarily from %d to %d.", param1, upgrade.name, upgrade.startCost, iValue);
				}
			}
			case ChangeProp_Icost:
			{
				int iValue = upgrade.incCost + iChange;
				if(iValue > 0)
				{
					upgrade.incCostConvar.SetInt(iValue);
					LogAction(param1, -1, "%L changed increasing costs of upgrade %s temporarily from %d to %d.", param1, upgrade.name, upgrade.incCost, iValue);
				}
			}
		}
		
		ShowUpgradePropertyChangeMenu(param1, g_iClientChangesProperty[param1]);
	}
}