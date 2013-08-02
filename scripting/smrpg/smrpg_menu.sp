#pragma semicolon 1
#include <sourcemod>

new Handle:g_hMainMenu;
new Handle:g_hStatsMenu;
new Handle:g_hSettingsMenu;
new Handle:g_hConfirmResetStatsMenu;

new g_iSellMenuPage[MAXPLAYERS+1];

InitMenu()
{
	// Main Menu
	g_hMainMenu = CreateMenu(Menu_HandleMainMenu, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_Display);
	SetMenuExitButton(g_hMainMenu, true);
	
	SetMenuTitle(g_hMainMenu, "credits_display");
	
	AddMenuItem(g_hMainMenu, "upgrades", "menu_opt.upgrades");
	AddMenuItem(g_hMainMenu, "sell", "menu_opt.sell");
	AddMenuItem(g_hMainMenu, "stats", "menu_opt.stats");
	AddMenuItem(g_hMainMenu, "settings", "menu_opt.settings");
	AddMenuItem(g_hMainMenu, "help", "menu_opt.help");
	
	// Stats Menu
	g_hStatsMenu = CreateMenu(Menu_HandleStats, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_Display);
	SetMenuExitBackButton(g_hStatsMenu, true);
	
	SetMenuTitle(g_hStatsMenu, "credits_display");
	
	AddMenuItem(g_hStatsMenu, "", "level", ITEMDRAW_DISABLED);
	AddMenuItem(g_hStatsMenu, "", "exp", ITEMDRAW_DISABLED);
	AddMenuItem(g_hStatsMenu, "", "credits", ITEMDRAW_DISABLED);
	AddMenuItem(g_hStatsMenu, "", "rank", ITEMDRAW_DISABLED);
	
	// Settings Menu
	g_hSettingsMenu = CreateMenu(Menu_HandleSettings, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_Display);
	SetMenuExitBackButton(g_hSettingsMenu, true);
	
	SetMenuTitle(g_hSettingsMenu, "credits_display");
	
	AddMenuItem(g_hSettingsMenu, "resetstats", "menu_opt.reset_stats");
	
	// Reset Stats Confirmation
	g_hConfirmResetStatsMenu = CreateMenu(Menu_ConfirmResetStats, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	SetMenuExitBackButton(g_hConfirmResetStatsMenu, true);

	SetMenuTitle(g_hConfirmResetStatsMenu, "credits_display");
	
	AddMenuItem(g_hConfirmResetStatsMenu, "yes", "Yes");
	AddMenuItem(g_hConfirmResetStatsMenu, "no", "No");
}

DisplayMainMenu(client)
{
	DisplayMenu(g_hMainMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleMainMenu(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "upgrades"))
		{
			DisplayUpgradesMenu(param1, 0);
		}
		else if(StrEqual(sInfo, "sell"))
		{
			DisplaySellMenu(param1);
		}
		else if(StrEqual(sInfo, "stats"))
		{
			DisplayStatsMenu(param1);
		}
		else if(StrEqual(sInfo, "settings"))
		{
			DisplaySettingsMenu(param1);
		}
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T %d\n-----\n", "menu_txt.credits", param1, GetClientCredits(param1));
		
		SetPanelTitle(hPanel, sBuffer);
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

DisplayUpgradesMenu(client, position)
{
	new Handle:hMenu = CreateMenu(Menu_HandleUpgrades, MENU_ACTIONS_DEFAULT|MenuAction_Display);
	SetMenuExitBackButton(hMenu, true);
	
	SetMenuTitle(hMenu, "credits_display");
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo], iCurrentLevel;
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH], String:sLine[128], String:sIndex[8];
	for(new i=0;i<iSize;i++)
	{
		iCurrentLevel = GetClientUpgradeLevel(client, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		IntToString(i, sIndex, sizeof(sIndex));
		if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		{
			Format(sLine, sizeof(sLine), "%s Lvl MAX [%T: MAX]", sTranslatedName, "menu_txt.cost", client);
			AddMenuItem(hMenu, sIndex, sLine, ITEMDRAW_DISABLED);
		}
		else
		{
			Format(sLine, sizeof(sLine), "%s Lvl %d [%T: %d]", sTranslatedName, iCurrentLevel+1, "menu_txt.cost", client, GetUpgradeCost(i, iCurrentLevel+1));
			AddMenuItem(hMenu, sIndex, sLine);
		}
	}
	
	if(position > 0)
		DisplayMenuAtItem(hMenu, client, position, MENU_TIME_FOREVER);
	else
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleUpgrades(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new iItemIndex = StringToInt(sInfo);
		new upgrade[InternalUpgradeInfo];
		GetUpgradeByIndex(iItemIndex, upgrade);
		
		// Bad upgrade?
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
		{
			DisplayUpgradesMenu(param1, GetMenuSelectionPosition());
			return;
		}
		
		new iItemLevel = GetClientUpgradeLevel(param1, iItemIndex);
		new iCost = GetUpgradeCost(iItemIndex, iItemLevel+1);
		
		new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
		GetUpgradeTranslatedName(param1, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		if(iItemLevel >= upgrade[UPGR_maxLevel])
			PrintToChat(param1, "%t", "menu_result.max_lvl");
		else if(GetClientCredits(param1) < iCost)
			PrintToChat(param1, "%t", "menu_result.not_enough_credits", sTranslatedName, iItemLevel+1, iCost);
		else
		{
			if(BuyClientUpgrade(param1, iItemIndex))
				PrintToChat(param1, "%t", "menu_result.item_bought", sTranslatedName, iItemLevel+1);
		}
		
		
		DisplayUpgradesMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T %d\n-----\n", "menu_txt.credits", param1, GetClientCredits(param1));
		
		SetPanelTitle(hPanel, sBuffer);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			DisplayMainMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

DisplaySellMenu(client)
{
	new Handle:hMenu = CreateMenu(Menu_HandleSell, MENU_ACTIONS_DEFAULT|MenuAction_Display);
	SetMenuExitBackButton(hMenu, true);
	
	SetMenuTitle(hMenu, "credits_display");
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo], iCurrentLevel;
	decl String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH], String:sLine[128], String:sIndex[8];
	for(new i=0;i<iSize;i++)
	{
		iCurrentLevel = GetClientUpgradeLevel(client, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		IntToString(i, sIndex, sizeof(sIndex));

		Format(sLine, sizeof(sLine), "%s Lvl %d [%T: %d]", sTranslatedName, iCurrentLevel, "menu_txt.sale", client, GetUpgradeSale(i, iCurrentLevel));
		AddMenuItem(hMenu, sIndex, sLine, (iCurrentLevel > 0?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED));
	}
	
	if(g_iSellMenuPage[client] > 0)
		DisplayMenuAtItem(hMenu, client, g_iSellMenuPage[client], MENU_TIME_FOREVER);
	else
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleSell(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new Handle:hMenu = CreateMenu(Menu_ConfirmSell, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
		SetMenuExitBackButton(hMenu, true);
	
		SetMenuTitle(hMenu, "credits_display");
		
		AddMenuItem(hMenu, sInfo, "Yes");
		AddMenuItem(hMenu, "no", "No");
		
		DisplayMenu(hMenu, param1, MENU_TIME_FOREVER);
		g_iSellMenuPage[param1] = GetMenuSelectionPosition();
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T %d\n-----\n", "menu_txt.credits", param1, GetClientCredits(param1));
		
		SetPanelTitle(hPanel, sBuffer);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			DisplayMainMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public Menu_ConfirmSell(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
			return 0;
		
		new iItemIndex = StringToInt(sInfo);
		new upgrade[InternalUpgradeInfo];
		GetUpgradeByIndex(iItemIndex, upgrade);
		SellClientUpgrade(param1, iItemIndex);
		
		new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
		GetUpgradeTranslatedName(param1, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		PrintToChat(param1, "%t", "menu_result.item_sold", sTranslatedName, GetClientUpgradeLevel(param1, iItemIndex)+1);
		
		DisplaySellMenu(param1);
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T %d\n-----\n%T\n", "menu_txt.credits", param1, GetClientCredits(param1), "menu_confirm.sell_confirm", param1);
		
		SetPanelTitle(hPanel, sBuffer);
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
	else if(action == MenuAction_Cancel)
	{
		g_iSellMenuPage[param1] = 0;
		if(param2 == MenuCancel_ExitBack)
			DisplaySellMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	return 0;
}

DisplayStatsMenu(client)
{
	DisplayMenu(g_hStatsMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleStats(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T %d\n-----\n", "menu_txt.credits", param1, GetClientCredits(param1));
		
		SetPanelTitle(hPanel, sBuffer);
	}
	else if(action == MenuAction_DisplayItem)
	{
		decl String:sDisplay[64];
		GetMenuItem(menu, param2, "", 0, _, sDisplay, sizeof(sDisplay));

		decl String:sBuffer[255];
		if(StrEqual(sDisplay, "level"))
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %d", "menu_txt.level", param1, GetClientLevel(param1));
		}
		else if(StrEqual(sDisplay, "exp"))
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %d/%d", "menu_txt.exp_short", param1, GetClientExperience(param1), Stats_LvlToExp(GetClientLevel(param1)));
		}
		else if(StrEqual(sDisplay, "credits"))
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %d", "menu_txt.credits", param1, GetClientCredits(param1));
		}
		else if(StrEqual(sDisplay, "rank"))
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %d/%d", "menu_txt.rank", param1, GetClientRank(param1), GetRankCount());
		}

		/* Override the text */
		return RedrawMenuItem(sBuffer);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			DisplayMainMenu(param1);
	}
	return 0;
}

DisplaySettingsMenu(client)
{
	DisplayMenu(g_hSettingsMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleSettings(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "resetstats"))
		{
			DisplayMenu(g_hConfirmResetStatsMenu, param1, MENU_TIME_FOREVER);
		}
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T %d\n-----\n", "menu_txt.credits", param1, GetClientCredits(param1));
		
		SetPanelTitle(hPanel, sBuffer);
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
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			DisplayMainMenu(param1);
	}
	return 0;
}

public Menu_ConfirmResetStats(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
			return 0;
		
		ResetStats(param1);
		
		PrintToChat(param1, "%t", "menu_result.stats_reset");
		
		DisplaySettingsMenu(param1);
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T %d\n-----\n%T\n", "menu_txt.credits", param1, GetClientCredits(param1), "menu_confirm.reset_confirm", param1);
		
		SetPanelTitle(hPanel, sBuffer);
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
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			DisplaySettingsMenu(param1);
	}
	return 0;
}