#pragma semicolon 1
#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <adminmenu>

new TopMenuObject:g_TopMenuCategory;
new Handle:g_hTopMenu;

new g_iCurrentMenuTarget[MAXPLAYERS+1] = {-1,...};
new g_iCurrentUpgradeTarget[MAXPLAYERS+1] = {-1,...};

public OnAdminMenuCreated(Handle:topmenu)
{
	if(topmenu == g_hTopMenu && g_TopMenuCategory)
		return;
	
	g_TopMenuCategory = AddToTopMenu(topmenu, "SM:RPG", TopMenuObject_Category, TopMenu_CategoryHandler, INVALID_TOPMENUOBJECT, "smrpg_menu", ADMFLAG_CONFIG);
}

public TopMenu_CategoryHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
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
	
	AddToTopMenu(topmenu, "Manage players", TopMenuObject_Item, TopMenu_HandlePlayers, g_TopMenuCategory, "smrpg_players_menu", ADMFLAG_CONFIG);
	AddToTopMenu(topmenu, "Manage upgrades", TopMenuObject_Item, TopMenu_HandleUpgrades, g_TopMenuCategory, "smrpg_upgrades_menu", ADMFLAG_CONFIG);
}

public TopMenu_HandlePlayers(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
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
	}
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
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH], String:sLine[128], String:sIndex[8];
	for(new i=0;i<iSize;i++)
	{
		iCurrentLevel = GetClientUpgradeLevel(iTarget, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		IntToString(i, sIndex, sizeof(sIndex));
		if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		{
			Format(sLine, sizeof(sLine), "%s Lvl MAX %d/%d", sTranslatedName, iCurrentLevel, upgrade[UPGR_maxLevel]);
		}
		else
		{
			Format(sLine, sizeof(sLine), "%s Lvl %d/%d", sTranslatedName, iCurrentLevel, upgrade[UPGR_maxLevel]);
		}
		
		AddMenuItem(hMenu, sIndex, sLine);
	}
	
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
	SetMenuTitle(hMenu, "Change %N's upgrade level\n%s: %d", g_iCurrentMenuTarget[client], sTranslatedName, GetClientUpgradeLevel(g_iCurrentMenuTarget[client], iItemIndex));
	
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
			g_iCurrentMenuTarget[param1] = -1;
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
		
		if(StrEqual(sInfo, "reset"))
		{
			new iOldLevel = GetClientUpgradeLevel(iTarget, iItemIndex);
			new iCreditsReturned;
			while(GetClientUpgradeLevel(iTarget, iItemIndex) > 0)
			{
				if(!TakeClientUpgrade(iTarget, iItemIndex))
					break;
				// Full refund
				iCreditsReturned += GetUpgradeCost(iItemIndex, GetClientUpgradeLevel(iTarget, iItemIndex)+1);
				SetClientCredits(iTarget, GetClientCredits(iTarget) + GetUpgradeCost(iItemIndex, GetClientUpgradeLevel(iTarget, iItemIndex)+1));
			}
			LogAction(param1, iTarget, "Reset %N's upgrade %s with full refund of all upgrade costs. Upgrade level changed from %d to %d and player earned %d credits.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientUpgradeLevel(iTarget, iItemIndex), iCreditsReturned);
			Client_PrintToChat(param1, false, "SM:RPG > Reset %N's upgrade %s with full refund of all upgrade costs. Upgrade level changed from %d to %d and player earned %d credits.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientUpgradeLevel(iTarget, iItemIndex), iCreditsReturned);
		}
		else if(StrEqual(sInfo, "give"))
		{
			new iOldLevel = GetClientUpgradeLevel(iTarget, iItemIndex);
			if(iOldLevel < upgrade[UPGR_maxLevel])
			{
				GiveClientUpgrade(iTarget, iItemIndex);
				LogAction(param1, iTarget, "Gave %N one level of upgrade %s at no charge. Upgrade level changed from %d to %d.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientUpgradeLevel(iTarget, iItemIndex));
			}
		}
		else if(StrEqual(sInfo, "buy"))
		{
			new iOldLevel = GetClientUpgradeLevel(iTarget, iItemIndex);
			if(iOldLevel < upgrade[UPGR_maxLevel])
			{
				new iCost = GetUpgradeCost(iItemIndex, iOldLevel+1);
				if(iCost > GetClientCredits(iTarget))
				{
					Client_PrintToChat(param1, false, "SM:RPG > %N doesn't have enough credits to purchase %s (%d/%d)", iTarget, upgrade[UPGR_name], GetClientCredits(iTarget), iCost);
				}
				else
				{
					BuyClientUpgrade(iTarget, iItemIndex);
					LogAction(param1, iTarget, "Forced %N to buy one level of upgrade %s. Upgrade level changed from %d to %d.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientUpgradeLevel(iTarget, iItemIndex));
				}
			}
		}
		else if(StrEqual(sInfo, "take"))
		{
			new iOldLevel = GetClientUpgradeLevel(iTarget, iItemIndex);
			if(iOldLevel > 0)
			{
				if(TakeClientUpgrade(iTarget, iItemIndex))
				{
					// Full refund
					new iCosts = GetUpgradeCost(iItemIndex, GetClientUpgradeLevel(iTarget, iItemIndex)+1);
					SetClientCredits(iTarget, GetClientCredits(iTarget) + iCosts);
					LogAction(param1, iTarget, "Took one level of upgrade %s from %N with full refund of the costs. Upgrade level changed from %d to %d and player got %d credits.", upgrade[UPGR_name], iTarget, iOldLevel, GetClientUpgradeLevel(iTarget, iItemIndex), iCosts);
				}
			}
		}
		else if(StrEqual(sInfo, "sell"))
		{
			new iOldLevel = GetClientUpgradeLevel(iTarget, iItemIndex);
			if(iOldLevel > 0)
			{
				SellClientUpgrade(iTarget, iItemIndex);
				LogAction(param1, iTarget, "Forced %N to sell one level of upgrade %s. Upgrade level changed from %d to %d.", iTarget, upgrade[UPGR_name], iOldLevel, GetClientUpgradeLevel(iTarget, iItemIndex));
			}
		}
		
		ShowPlayerUpgradeLevelMenu(param1);
	}
}




public TopMenu_HandleUpgrades(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
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
	}
	else if(action == MenuAction_Select)
	{
		decl String:sInfo[32];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iItemIndex = StringToInt(sInfo);
		
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
	AddMenuItem(hMenu, "maxlevel", sBuffer, ITEMDRAW_DISABLED);
	
	Format(sBuffer, sizeof(sBuffer), "Cost: %d", upgrade[UPGR_startCost]);
	AddMenuItem(hMenu, "cost", sBuffer, ITEMDRAW_DISABLED);
	
	Format(sBuffer, sizeof(sBuffer), "Increase Cost: %d", upgrade[UPGR_incCost]);
	AddMenuItem(hMenu, "icost", sBuffer, ITEMDRAW_DISABLED);
	
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
		}
		else if(StrEqual(sInfo, "maxlevel"))
		{
			
		}
		else if(StrEqual(sInfo, "cost"))
		{
			
		}
		else if(StrEqual(sInfo, "icost"))
		{
			
		}
		ShowUpgradeManageMenu(param1);
	}
}