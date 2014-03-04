#pragma semicolon 1
#include <sourcemod>
#include <adminmenu>

new TopMenuObject:g_TopMenuCategory;
new Handle:g_hTopMenu;

new g_iCurrentMenuTarget[MAXPLAYERS+1] = {-1,...};
new g_iCurrentUpgradeTarget[MAXPLAYERS+1] = {-1,...};
new g_iCurrentPage[MAXPLAYERS+1];

enum ChangeUpgradeProperty {
	ChangeProp_None = 0,
	ChangeProp_MaxlevelBarrier,
	ChangeProp_Maxlevel,
	ChangeProp_Cost,
	ChangeProp_Icost
};

new ChangeUpgradeProperty:g_iClientChangesProperty[MAXPLAYERS+1];

public OnAdminMenuCreated(Handle:topmenu)
{
	if(topmenu == g_hTopMenu && g_TopMenuCategory)
		return;
	
	g_TopMenuCategory = AddToTopMenu(topmenu, "SM:RPG", TopMenuObject_Category, TopMenu_AdminCategoryHandler, INVALID_TOPMENUOBJECT, "smrpg_adminmenu", ADMFLAG_CONFIG);
}

public TopMenu_AdminCategoryHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayTitle)
	{
		Format(buffer, maxlength, "SM:RPG Commands:");
	}
	else if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "SM:RPG Commands");
	}
}

public OnAdminMenuReady(Handle:topmenu)
{
	// Try to add the category first
	if(g_TopMenuCategory == INVALID_TOPMENUOBJECT)
		OnAdminMenuCreated(topmenu);
	// Still failed..
	if(g_TopMenuCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == topmenu)
		return;
	
	g_hTopMenu = topmenu;
	
	AddToTopMenu(topmenu, "Manage players", TopMenuObject_Item, TopMenu_AdminHandlePlayers, g_TopMenuCategory, "smrpg_players_menu", ADMFLAG_CONFIG);
	AddToTopMenu(topmenu, "Manage upgrades", TopMenuObject_Item, TopMenu_AdminHandleUpgrades, g_TopMenuCategory, "smrpg_upgrades_menu", ADMFLAG_CONFIG);
}

public TopMenu_AdminHandlePlayers(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Manage players");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		ShowPlayerListMenu(param);
	}
}

ShowPlayerListMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerList);
	SetMenuTitle(hMenu, "Select player:");
	SetMenuExitBackButton(hMenu, true);
	
	// Add all players
	AddTargetsToMenu2(hMenu, 0, 0);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerList(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		RedisplayAdminMenu(g_hTopMenu, param1);
	}
	else if(action == MenuAction_Select)
	{
		decl String:sUserId[16];
		GetMenuItem(menu, param2, sUserId, sizeof(sUserId));
		new userid = StringToInt(sUserId);
		
		new iTarget = GetClientOfUserId(userid);
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

ShowPlayerDetailMenu(client)
{
	new iTarget = g_iCurrentMenuTarget[client];
	
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerDetails);
	SetMenuTitle(hMenu, "SM:RPG Player Details > %N", iTarget);
	SetMenuExitBackButton(hMenu, true);
	
	AddMenuItem(hMenu, "stats", "Manage RPG stats");
	AddMenuItem(hMenu, "upgrades", "Manage upgrades");
	AddMenuItem(hMenu, "reset", "Reset player");
	AddMenuItem(hMenu, "", "", ITEMDRAW_DISABLED|ITEMDRAW_SPACER);
	decl String:sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "%T", "Level", client, GetClientLevel(iTarget));
	AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	Format(sBuffer, sizeof(sBuffer), "%T", "Experience short", client, GetClientExperience(iTarget), Stats_LvlToExp(GetClientLevel(iTarget)));
	AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	Format(sBuffer, sizeof(sBuffer), "%T", "Credits", client, GetClientCredits(iTarget));
	AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	Format(sBuffer, sizeof(sBuffer), "%T", "Rank", client, GetClientRank(iTarget), GetRankCount());
	AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	FormatTime(sBuffer, sizeof(sBuffer), "%c", GetPlayerLastReset(iTarget));
	Format(sBuffer, sizeof(sBuffer), "%T", "Last reset", client, sBuffer);
	AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerDetails(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		g_iCurrentMenuTarget[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
			ShowPlayerListMenu(param1);
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
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
			new Handle:hMenu = CreateMenu(Menu_HandlePlayerResetConfirm, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
			SetMenuExitBackButton(hMenu, true);
			SetMenuTitle(hMenu, "Do you really want to reset the stats and upgrades of %N?", g_iCurrentMenuTarget[param1]);
			AddMenuItem(hMenu, "yes", "Yes");
			AddMenuItem(hMenu, "no", "No");
			DisplayMenu(hMenu, param1, MENU_TIME_FOREVER);
		}
	}
}

public Menu_HandlePlayerResetConfirm(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
		{
			ShowPlayerDetailMenu(param1);
			return 0;
		}
		
		ResetStats(g_iCurrentMenuTarget[param1]);
		SetPlayerLastReset(g_iCurrentMenuTarget[param1], GetTime());
		LogAction(param1, g_iCurrentMenuTarget[param1], "Permanently reset all stats of player %N.", g_iCurrentMenuTarget[param1]);
		Client_PrintToChat(param1, false, "SM:RPG resetstats: %N's stats have been permanently reset", g_iCurrentMenuTarget[param1]);
		ShowPlayerDetailMenu(param1);
	}
	else if(action == MenuAction_DisplayItem)
	{
		/* Get the display string, we'll use it as a translation phrase */
		decl String:sDisplay[64];
		GetMenuItem(menu, param2, "", 0, _, sDisplay, sizeof(sDisplay));

		/* Translate the string to the client's language */
		decl String:sBuffer[255];
		Format(sBuffer, sizeof(sBuffer), "%T", sDisplay, param1);

		/* Override the text */
		return RedrawMenuItem(sBuffer);
	}
	return 0;
}

ShowPlayerStatsManageMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerStats);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Manage RPG stats > %N", g_iCurrentMenuTarget[client]);
	
	if(CheckCommandAccess(client, "smrpg_setcredits", ADMFLAG_ROOT))
		AddMenuItem(hMenu, "credits", "Change credits");
	if(CheckCommandAccess(client, "smrpg_setexp", ADMFLAG_ROOT))
		AddMenuItem(hMenu, "experience", "Change experience");
	if(CheckCommandAccess(client, "smrpg_setlvl", ADMFLAG_ROOT))
		AddMenuItem(hMenu, "level", "Change level");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerStats(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
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

ShowPlayerCreditsManageMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerChangeCredits);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Change Credits > %N\nCredits: %d", g_iCurrentMenuTarget[client], GetClientCredits(g_iCurrentMenuTarget[client]));
	
	AddMenuItem(hMenu, "100", "+100");
	AddMenuItem(hMenu, "10", "+10");
	AddMenuItem(hMenu, "1", "+1");
	AddMenuItem(hMenu, "-1", "-1");
	AddMenuItem(hMenu, "-10", "-10");
	AddMenuItem(hMenu, "-100", "-100");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerChangeCredits(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iAmount = StringToInt(sInfo);
		
		new iOldCredits = GetClientCredits(g_iCurrentMenuTarget[param1]);
		
		SetClientCredits(g_iCurrentMenuTarget[param1], iOldCredits + iAmount);
		
		LogAction(param1, g_iCurrentMenuTarget[param1], "Changed %N's credits by %d from %d to %d.", g_iCurrentMenuTarget[param1], iAmount, iOldCredits, GetClientCredits(g_iCurrentMenuTarget[param1]));
		ShowPlayerCreditsManageMenu(param1);
	}
}

ShowPlayerExperienceManageMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerChangeExperience);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Change Experience > %N\nExperience: %d", g_iCurrentMenuTarget[client], GetClientExperience(g_iCurrentMenuTarget[client]));
	
	AddMenuItem(hMenu, "1000", "+1000");
	AddMenuItem(hMenu, "100", "+100");
	AddMenuItem(hMenu, "10", "+10");
	AddMenuItem(hMenu, "-10", "-10");
	AddMenuItem(hMenu, "-100", "-100");
	AddMenuItem(hMenu, "-1000", "-1000");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerChangeExperience(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iAmount = StringToInt(sInfo);
	
		new iOldLevel = GetClientLevel(g_iCurrentMenuTarget[param1]);
		new iOldExperience = GetClientExperience(g_iCurrentMenuTarget[param1]);
		
		// If we're adding experience, add it properly and level up if necassary.
		if(iAmount > 0)
			Stats_AddExperience(g_iCurrentMenuTarget[param1], iAmount, false);
		else
			SetClientExperience(g_iCurrentMenuTarget[param1], GetClientExperience(g_iCurrentMenuTarget[param1])+iAmount);
		
		LogAction(param1, g_iCurrentMenuTarget[param1], "Changed experience of %N by %d. He is now Level %d and has %d/%d Experience (previously Level %d with %d/%d Experience)", g_iCurrentMenuTarget[param1], iAmount, GetClientLevel(g_iCurrentMenuTarget[param1]), GetClientExperience(g_iCurrentMenuTarget[param1]), Stats_LvlToExp(GetClientLevel(g_iCurrentMenuTarget[param1])), iOldLevel, iOldExperience, Stats_LvlToExp(iOldLevel));
		ShowPlayerExperienceManageMenu(param1);
	}
}

ShowPlayerLevelManageMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerChangeLevel);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Change Level > %N\nLevel: %d", g_iCurrentMenuTarget[client], GetClientLevel(g_iCurrentMenuTarget[client]));
	
	AddMenuItem(hMenu, "10", "+10");
	AddMenuItem(hMenu, "5", "+5");
	AddMenuItem(hMenu, "1", "+1");
	AddMenuItem(hMenu, "-1", "-1");
	AddMenuItem(hMenu, "-5", "-5");
	AddMenuItem(hMenu, "-10", "-10");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerChangeLevel(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iAmount = StringToInt(sInfo);
		new iOldLevel = GetClientLevel(g_iCurrentMenuTarget[param1]);
	
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
			
			if(GetConVarBool(g_hCVAnnounceNewLvl))
				PrintToChatAll("%t", "new_lvl1", g_iCurrentMenuTarget[param1], GetClientLevel(g_iCurrentMenuTarget[param1]));
		}
		
		LogAction(param1, g_iCurrentMenuTarget[param1], "Changed level of %N by %d from %d to %d.", g_iCurrentMenuTarget[param1], iAmount, iOldLevel, GetClientLevel(g_iCurrentMenuTarget[param1]));
		ShowPlayerLevelManageMenu(param1);
	}
}

ShowPlayerUpgradeManageMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerUpgradeSelect);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Manage player upgrades > %N", g_iCurrentMenuTarget[client]);
	
	new iTarget = g_iCurrentMenuTarget[client];
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo], iCurrentLevel;
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH], String:sLine[128], String:sIndex[8], String:sPermissions[30];
	for(new i=0;i<iSize;i++)
	{
		iCurrentLevel = GetClientPurchasedUpgradeLevel(iTarget, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		sPermissions[0] = 0;
		
		// Print the required adminflags in a readable way
		if(upgrade[UPGR_adminFlag] > 0)
		{
			GetAdminFlagStringFromBits(upgrade[UPGR_adminFlag], sPermissions, sizeof(sPermissions));
			Format(sPermissions, sizeof(sPermissions), " (adminflags: %s)", sPermissions);
		}
		
		// Warn the admin, that this player won't be able to use this upgrade.
		if(!HasAccessToUpgrade(g_iCurrentMenuTarget[client], upgrade))
			Format(sPermissions, sizeof(sPermissions), "%s NO ACCESS", sPermissions);
		// Or if there are some permission restrictions specified, show the player is able to use it.
		else if(upgrade[UPGR_adminFlag] > 0)
			Format(sPermissions, sizeof(sPermissions), "%s OK", sPermissions);
		
		IntToString(i, sIndex, sizeof(sIndex));
		if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		{
			Format(sLine, sizeof(sLine), "%s Lvl MAX %d/%d%s", sTranslatedName, iCurrentLevel, upgrade[UPGR_maxLevel], sPermissions);
		}
		else
		{
			Format(sLine, sizeof(sLine), "%s Lvl %d/%d%s", sTranslatedName, iCurrentLevel, upgrade[UPGR_maxLevel], sPermissions);
		}
		
		AddMenuItem(hMenu, sIndex, sLine);
	}
	
	if(g_iCurrentPage[client] > 0)
		DisplayMenuAtItem(hMenu, client, g_iCurrentPage[client], MENU_TIME_FOREVER);
	else
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerUpgradeSelect(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iItemIndex = StringToInt(sInfo);
		
		g_iCurrentPage[param1] = GetMenuSelectionPosition();
		g_iCurrentUpgradeTarget[param1] = iItemIndex;
		ShowPlayerUpgradeLevelMenu(param1);
	}
}

ShowPlayerUpgradeLevelMenu(client)
{
	new iItemIndex = g_iCurrentUpgradeTarget[client];
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
	{
		g_iCurrentUpgradeTarget[client] = -1;
		ShowPlayerUpgradeManageMenu(client);
		return;
	}
	
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
	
	new Handle:hMenu = CreateMenu(Menu_HandlePlayerUpgradeLevelChange);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Change %N's upgrade level\n%s: %d/%d", g_iCurrentMenuTarget[client], sTranslatedName, GetClientPurchasedUpgradeLevel(g_iCurrentMenuTarget[client], iItemIndex), upgrade[UPGR_maxLevel]);
	
	AddMenuItem(hMenu, "reset", "Reset upgrade to 0 with full refund\n");
	AddMenuItem(hMenu, "give", "Give level at no costs");
	AddMenuItem(hMenu, "buy", "Force to buy level\n");
	AddMenuItem(hMenu, "take", "Take level with full refund");
	AddMenuItem(hMenu, "sell", "Force to sell level");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandlePlayerUpgradeLevelChange(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new upgrade[InternalUpgradeInfo];
		new iItemIndex = g_iCurrentUpgradeTarget[param1];
		GetUpgradeByIndex(iItemIndex, upgrade);
		
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			ShowPlayerUpgradeManageMenu(param1);
			return;
		}
		
		new iTarget = g_iCurrentMenuTarget[param1];
		new iOldLevel = GetClientPurchasedUpgradeLevel(iTarget, iItemIndex);
		
		if(StrEqual(sInfo, "reset"))
		{
			new iCreditsReturned;
			while(GetClientPurchasedUpgradeLevel(iTarget, iItemIndex) > 0)
			{
				if(!TakeClientUpgrade(iTarget, iItemIndex))
					break;
				// Full refund
				iCreditsReturned += GetUpgradeCost(iItemIndex, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex)+1);
				SetClientCredits(iTarget, GetClientCredits(iTarget) + GetUpgradeCost(iItemIndex, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex)+1));
			}
			LogAction(param1, iTarget, "Reset %N's upgrade %s with full refund of all upgrade costs. Upgrade level changed from %d to %d and player earned %d credits.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex), iCreditsReturned);
			Client_PrintToChat(param1, false, "{OG}SM:RPG{N} > {G}Reset %N's upgrade %s with full refund of all upgrade costs. Upgrade level changed from %d to %d and player earned %d credits.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex), iCreditsReturned);
		}
		else if(StrEqual(sInfo, "give"))
		{
			if(iOldLevel < upgrade[UPGR_maxLevel])
			{
				GiveClientUpgrade(iTarget, iItemIndex);
				LogAction(param1, iTarget, "Gave %N one level of upgrade %s at no charge. Upgrade level changed from %d to %d.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex));
			}
		}
		else if(StrEqual(sInfo, "buy"))
		{
			if(iOldLevel < upgrade[UPGR_maxLevel])
			{
				new iCost = GetUpgradeCost(iItemIndex, iOldLevel+1);
				if(iCost > GetClientCredits(iTarget))
				{
					Client_PrintToChat(param1, false, "{OG}SM:RPG{N} > {G}%N doesn't have enough credits to purchase %s (%d/%d)", iTarget, upgrade[UPGR_name], GetClientCredits(iTarget), iCost);
				}
				else
				{
					BuyClientUpgrade(iTarget, iItemIndex);
					LogAction(param1, iTarget, "Forced %N to buy one level of upgrade %s. Upgrade level changed from %d to %d.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex));
				}
			}
		}
		else if(StrEqual(sInfo, "take"))
		{
			if(iOldLevel > 0)
			{
				if(TakeClientUpgrade(iTarget, iItemIndex))
				{
					// Full refund
					new iCosts = GetUpgradeCost(iItemIndex, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex)+1);
					SetClientCredits(iTarget, GetClientCredits(iTarget) + iCosts);
					LogAction(param1, iTarget, "Took one level of upgrade %s from %N with full refund of the costs. Upgrade level changed from %d to %d and player got %d credits.", upgrade[UPGR_name], iTarget, iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex), iCosts);
				}
			}
		}
		else if(StrEqual(sInfo, "sell"))
		{
			if(iOldLevel > 0)
			{
				SellClientUpgrade(iTarget, iItemIndex);
				LogAction(param1, iTarget, "Forced %N to sell one level of upgrade %s. Upgrade level changed from %d to %d.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientPurchasedUpgradeLevel(iTarget, iItemIndex));
			}
		}
		
		ShowPlayerUpgradeLevelMenu(param1);
	}
}

// client disconnected. Reset all open admin menus so we don't try to change stuff on a different user out of a sudden.
ResetAdminMenu(client)
{
	for(new i=1;i<=MaxClients;i++)
	{
		if(g_iCurrentMenuTarget[i] == client && client != i)
		{
			g_iCurrentMenuTarget[i] = -1;
			ShowPlayerListMenu(i);
		}
	}
}


public TopMenu_AdminHandleUpgrades(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Manage upgrades");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		ShowUpgradeListMenu(param);
	}
}

ShowUpgradeListMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandleSelectUpgrade);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "SM:RPG > Manage upgrades");
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH], String:sIndex[8];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade))
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		IntToString(i, sIndex, sizeof(sIndex));
		AddMenuItem(hMenu, sIndex, sTranslatedName);
	}
	
	if(g_iCurrentPage[client] > 0)
		DisplayMenuAtItem(hMenu, client, g_iCurrentPage[client], MENU_TIME_FOREVER);
	else
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleSelectUpgrade(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			RedisplayAdminMenu(g_hTopMenu, param1);
		else
			g_iCurrentPage[param1] = 0;
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iItemIndex = StringToInt(sInfo);
		
		g_iCurrentPage[param1] = GetMenuSelectionPosition();
		g_iCurrentUpgradeTarget[param1] = iItemIndex;
		ShowUpgradeManageMenu(param1);
	}
}

ShowUpgradeManageMenu(client)
{
	new upgrade[InternalUpgradeInfo];
	new iItemIndex = g_iCurrentUpgradeTarget[client];
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade))
	{
		g_iCurrentUpgradeTarget[client] = -1;
		RedisplayAdminMenu(g_hTopMenu, client);
		return;
	}
	
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
	
	new Handle:hMenu = CreateMenu(Menu_HandleUpgradeDetails);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "Manage upgrade > %s\nShort name: %s", sTranslatedName, upgrade[UPGR_shortName]);
	
	decl String:sBuffer[256];
	if(upgrade[UPGR_enabled])
		Format(sBuffer, sizeof(sBuffer), "Disable upgrade");
	else
		Format(sBuffer, sizeof(sBuffer), "Enable upgrade");
	AddMenuItem(hMenu, "enable", sBuffer);
	
	if(!GetConVarBool(g_hCVIgnoreLevelBarrier))
	{
		Format(sBuffer, sizeof(sBuffer), "Maxlevel barrier: %d", upgrade[UPGR_maxLevelBarrier]);
		AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	}
	
	Format(sBuffer, sizeof(sBuffer), "Maxlevel: %d", upgrade[UPGR_maxLevel]);
	AddMenuItem(hMenu, "maxlevel", sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "Cost: %d", upgrade[UPGR_startCost]);
	AddMenuItem(hMenu, "cost", sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "Increase Cost: %d", upgrade[UPGR_incCost]);
	AddMenuItem(hMenu, "icost", sBuffer);
	
	if(upgrade[UPGR_visualsConvar] != INVALID_HANDLE)
	{
		Format(sBuffer, sizeof(sBuffer), "Visual effects: %T", upgrade[UPGR_enableVisuals]?"On":"Off", client);
		AddMenuItem(hMenu, "visuals", sBuffer);
	}
	
	if(upgrade[UPGR_soundsConvar] != INVALID_HANDLE)
	{
		Format(sBuffer, sizeof(sBuffer), "Sound effects: %T", upgrade[UPGR_enableSounds]?"On":"Off", client);
		AddMenuItem(hMenu, "sounds", sBuffer);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleUpgradeDetails(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		new upgrade[InternalUpgradeInfo];
		GetUpgradeByIndex(g_iCurrentUpgradeTarget[param1], upgrade);
	
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade))
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			ShowUpgradeListMenu(param1);
			return;
		}
		
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "enable"))
		{
			if(upgrade[UPGR_enabled])
			{
				SetConVarBool(upgrade[UPGR_enableConvar], false);
				LogAction(param1, -1, "Disabled upgrade %s temporarily.", upgrade[UPGR_name]);
			}
			else
			{
				SetConVarBool(upgrade[UPGR_enableConvar], true);
				LogAction(param1, -1, "Enabled upgrade %s temporarily.", upgrade[UPGR_name]);
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
		else if(StrEqual(sInfo, "visuals"))
		{
			if(upgrade[UPGR_enableVisuals])
			{
				SetConVarBool(upgrade[UPGR_visualsConvar], false);
				LogAction(param1, -1, "Disabled upgrade %s's visual effects temporarily.", upgrade[UPGR_name]);
			}
			else
			{
				SetConVarBool(upgrade[UPGR_visualsConvar], true);
				LogAction(param1, -1, "Enabled upgrade %s's visual effects temporarily.", upgrade[UPGR_name]);
			}
			ShowUpgradeManageMenu(param1);
		}
		else if(StrEqual(sInfo, "sounds"))
		{
			if(upgrade[UPGR_enableSounds])
			{
				SetConVarBool(upgrade[UPGR_soundsConvar], false);
				LogAction(param1, -1, "Disabled upgrade %s's sound effects temporarily.", upgrade[UPGR_name]);
			}
			else
			{
				SetConVarBool(upgrade[UPGR_soundsConvar], true);
				LogAction(param1, -1, "Enabled upgrade %s's sound effects temporarily.", upgrade[UPGR_name]);
			}
			ShowUpgradeManageMenu(param1);
		}
	}
}

ShowUpgradePropertyChangeMenu(client, ChangeUpgradeProperty:property)
{
	new upgrade[InternalUpgradeInfo];
	new iItemIndex = g_iCurrentUpgradeTarget[client];
	GetUpgradeByIndex(iItemIndex, upgrade);
	
	// Bad upgrade?
	if(!IsValidUpgrade(upgrade))
	{
		g_iClientChangesProperty[client] = ChangeProp_None;
		g_iCurrentUpgradeTarget[client] = -1;
		RedisplayAdminMenu(g_hTopMenu, client);
		return;
	}
	
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
	
	new Handle:hMenu = CreateMenu(Menu_HandlePropertyChange);
	SetMenuExitBackButton(hMenu, true);
	
	decl String:sBuffer[512];
	Format(sBuffer, sizeof(sBuffer), "Manage upgrade > %s\nShort name: %s\n", sTranslatedName, upgrade[UPGR_shortName]);
	switch(property)
	{
		case ChangeProp_Maxlevel:
		{
			Format(sBuffer, sizeof(sBuffer), "%sChange maxlevel temporarily: %d", sBuffer, upgrade[UPGR_maxLevel]);
		}
		case ChangeProp_Cost:
		{
			Format(sBuffer, sizeof(sBuffer), "%sChange start cost temporarily: %d", sBuffer, upgrade[UPGR_startCost]);
		}
		case ChangeProp_Icost:
		{
			Format(sBuffer, sizeof(sBuffer), "%sChange increasing cost temporarily: %d", sBuffer, upgrade[UPGR_incCost]);
		}
	}
	
	SetMenuTitle(hMenu, sBuffer);
	
	AddMenuItem(hMenu, "10", "+10");
	AddMenuItem(hMenu, "5", "+5");
	AddMenuItem(hMenu, "1", "+1");
	AddMenuItem(hMenu, "-1", "-1");
	AddMenuItem(hMenu, "-5", "-5");
	AddMenuItem(hMenu, "-10", "-10");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	
	g_iClientChangesProperty[client] = property;
}

public Menu_HandlePropertyChange(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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
		new upgrade[InternalUpgradeInfo];
		GetUpgradeByIndex(g_iCurrentUpgradeTarget[param1], upgrade);
	
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade))
		{
			g_iCurrentUpgradeTarget[param1] = -1;
			g_iClientChangesProperty[param1] = ChangeProp_None;
			ShowUpgradeListMenu(param1);
			return;
		}
		
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iChange = StringToInt(sInfo);
		switch(g_iClientChangesProperty[param1])
		{
			case ChangeProp_Maxlevel:
			{
				new iValue = upgrade[UPGR_maxLevel] + iChange;
				if(iValue > 0 && iValue <= upgrade[UPGR_maxLevelBarrier])
				{
					SetConVarInt(upgrade[UPGR_maxLevelConvar], iValue);
					LogAction(param1, -1, "Changed maxlevel of upgrade %s temporarily from %d to %d.", upgrade[UPGR_name], upgrade[UPGR_maxLevel], iValue);
				}
			}
			case ChangeProp_Cost:
			{
				new iValue = upgrade[UPGR_startCost] + iChange;
				if(iValue >= 0)
				{
					SetConVarInt(upgrade[UPGR_startCostConvar], iValue);
					LogAction(param1, -1, "Changed start costs of upgrade %s temporarily from %d to %d.", upgrade[UPGR_name], upgrade[UPGR_startCost], iValue);
				}
			}
			case ChangeProp_Icost:
			{
				new iValue = upgrade[UPGR_incCost] + iChange;
				if(iValue > 0)
				{
					SetConVarInt(upgrade[UPGR_incCostConvar], iValue);
					LogAction(param1, -1, "Changed increasing costs of upgrade %s temporarily from %d to %d.", upgrade[UPGR_name], upgrade[UPGR_incCost], iValue);
				}
			}
		}
		
		ShowUpgradePropertyChangeMenu(param1, g_iClientChangesProperty[param1]);
	}
}