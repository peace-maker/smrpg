#pragma semicolon 1
#include <sourcemod>
#include <topmenus>

new Handle:g_hRPGTopMenu;

new TopMenuObject:g_TopMenuUpgrades;
new TopMenuObject:g_TopMenuSell;
new TopMenuObject:g_TopMenuStats;
new TopMenuObject:g_TopMenuCommands;
new TopMenuObject:g_TopMenuSettings;
new TopMenuObject:g_TopMenuHelp;

new Handle:g_hConfirmResetStatsMenu;

new Handle:g_hfwdOnRPGMenuCreated;
new Handle:g_hfwdOnRPGMenuReady;

/**
 * Setup functions to create the topmenu and API.
 */
RegisterTopMenu()
{
	g_hRPGTopMenu = CreateTopMenu(TopMenu_DefaultCategoryHandler);
	
	g_TopMenuUpgrades = AddToTopMenu(g_hRPGTopMenu, RPGMENU_UPGRADES, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuSell = AddToTopMenu(g_hRPGTopMenu, RPGMENU_SELL, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuStats = AddToTopMenu(g_hRPGTopMenu, RPGMENU_STATS, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuCommands = AddToTopMenu(g_hRPGTopMenu, RPGMENU_COMMANDS, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuSettings = AddToTopMenu(g_hRPGTopMenu, RPGMENU_SETTINGS, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuHelp = AddToTopMenu(g_hRPGTopMenu, RPGMENU_HELP, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
}

RegisterTopMenuForwards()
{
	g_hfwdOnRPGMenuCreated = CreateGlobalForward("SMRPG_OnRPGMenuCreated", ET_Ignore, Param_Cell);
	g_hfwdOnRPGMenuReady = CreateGlobalForward("SMRPG_OnRPGMenuReady", ET_Ignore, Param_Cell);
}

RegisterTopMenuNatives()
{
	CreateNative("SMRPG_GetTopMenu", Native_GetTopMenu);
}

InitMenu()
{
	// Add any already loaded upgrades to the menus
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	decl String:sBuffer[MAX_UPGRADE_SHORTNAME_LENGTH+20];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade[UPGR_topmenuUpgrades] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgupgrade_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuUpgrades] = AddToTopMenu(g_hRPGTopMenu, sBuffer, TopMenuObject_Item, TopMenu_HandleUpgrades, g_TopMenuUpgrades);
		}
		if(upgrade[UPGR_topmenuSell] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgsell_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuSell] = AddToTopMenu(g_hRPGTopMenu, sBuffer, TopMenuObject_Item, TopMenu_HandleSell, g_TopMenuSell);
		}
		if(upgrade[UPGR_topmenuHelp] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpghelp_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuHelp] = AddToTopMenu(g_hRPGTopMenu, sBuffer, TopMenuObject_Item, TopMenu_HandleHelp, g_TopMenuHelp);
		}
		SaveUpgradeConfig(upgrade);
	}
	
	// Stats Menu
	AddToTopMenu(g_hRPGTopMenu, "level", TopMenuObject_Item, TopMenu_HandleStats, g_TopMenuStats);
	AddToTopMenu(g_hRPGTopMenu, "exp", TopMenuObject_Item, TopMenu_HandleStats, g_TopMenuStats);
	AddToTopMenu(g_hRPGTopMenu, "credits", TopMenuObject_Item, TopMenu_HandleStats, g_TopMenuStats);
	AddToTopMenu(g_hRPGTopMenu, "rank", TopMenuObject_Item, TopMenu_HandleStats, g_TopMenuStats);
	
	// Settings Menu
	AddToTopMenu(g_hRPGTopMenu, "resetstats", TopMenuObject_Item, TopMenu_HandleSettings, g_TopMenuSettings);
	
	// Reset Stats Confirmation
	g_hConfirmResetStatsMenu = CreateMenu(Menu_ConfirmResetStats, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	SetMenuExitBackButton(g_hConfirmResetStatsMenu, true);

	SetMenuTitle(g_hConfirmResetStatsMenu, "credits_display");
	
	AddMenuItem(g_hConfirmResetStatsMenu, "yes", "Yes");
	AddMenuItem(g_hConfirmResetStatsMenu, "no", "No");
	
	Call_StartForward(g_hfwdOnRPGMenuCreated);
	Call_PushCell(g_hRPGTopMenu);
	Call_Finish();
	
	Call_StartForward(g_hfwdOnRPGMenuReady);
	Call_PushCell(g_hRPGTopMenu);
	Call_Finish();
}

/**
 * Native callbacks
 */
public Native_GetTopMenu(Handle:plugin, numParams)
{
	return _:g_hRPGTopMenu;
}

DisplayMainMenu(client)
{
	DisplayTopMenu(g_hRPGTopMenu, client, TopMenuPosition_Start);
}

DisplayUpgradesMenu(client)
{
	if(GetFeatureStatus(FeatureType_Native, "DisplayTopMenuCategory") == FeatureStatus_Available)
		DisplayTopMenuCategory(g_hRPGTopMenu, g_TopMenuUpgrades, client);
	else
		DisplayTopMenu(g_hRPGTopMenu, client, TopMenuPosition_Start); // Fallback to just displaying the rpgmenu if running "old" sourcemod version.
}

/**
 * TopMenu callback handlers
 */
// Print the default categories correctly.
public TopMenu_DefaultCategoryHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
		{
			// Always display the current credits in the title
			Format(buffer, maxlength, "%T\n-----\n", "Credits", param, GetClientCredits(param));
		}
		case TopMenuAction_DisplayOption:
		{
			if(object_id == g_TopMenuUpgrades)
				Format(buffer, maxlength, "%T", "Upgrades", param);
			else if(object_id == g_TopMenuSell)
				Format(buffer, maxlength, "%T", "Sell", param);
			else if(object_id == g_TopMenuStats)
				Format(buffer, maxlength, "%T", "Stats", param);
			else if(object_id == g_TopMenuCommands)
				Format(buffer, maxlength, "%T", "Commands", param);
			else if(object_id == g_TopMenuSettings)
				Format(buffer, maxlength, "%T", "Settings", param);
			else if(object_id == g_TopMenuHelp)
				Format(buffer, maxlength, "%T", "Help", param);
		}
	}
}

public TopMenu_HandleUpgrades(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[11], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				return;
			
			decl String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			new iCurrentLevel = GetClientUpgradeLevel(param, upgrade[UPGR_index]);
			
			if(iCurrentLevel >= upgrade[UPGR_maxLevel])
			{
				Format(buffer, maxlength, "%s Lvl MAX [%T: MAX]", sTranslatedName, "Cost", param);
			}
			else
			{
				Format(buffer, maxlength, "%s Lvl %d [%T: %d]", sTranslatedName, iCurrentLevel+1, "Cost", param, GetUpgradeCost(upgrade[UPGR_index], iCurrentLevel+1));
			}
		}
		case TopMenuAction_DrawOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[11], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled] || !HasAccessToUpgrade(param, upgrade))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// Don't let players buy upgrades they already maxed out.
			if(GetClientUpgradeLevel(param, upgrade[UPGR_index]) >= upgrade[UPGR_maxLevel])
				buffer[0] = ITEMDRAW_DISABLED;
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[11], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled] || !HasAccessToUpgrade(param, upgrade))
			{
				DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
				return;
			}
			
			new iItemIndex = upgrade[UPGR_index];
			new iItemLevel = GetClientUpgradeLevel(param, iItemIndex);
			new iCost = GetUpgradeCost(iItemIndex, iItemLevel+1);
			
			new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			if(iItemLevel >= upgrade[UPGR_maxLevel])
				Client_PrintToChat(param, false, "%t", "Maximum level reached");
			else if(GetClientCredits(param) < iCost)
				Client_PrintToChat(param, false, "%t", "Not enough credits", sTranslatedName, iItemLevel+1, iCost);
			else
			{
				if(BuyClientUpgrade(param, iItemIndex))
				{
					Client_PrintToChat(param, false, "%t", "Upgrade bought", sTranslatedName, iItemLevel+1);
					if(GetConVarBool(g_hCVShowUpgradePurchase))
					{
						for(new i=1;i<=MaxClients;i++)
						{
							if(i != param && IsClientInGame(i) && !IsFakeClient(i))
								Client_PrintToChat(i, false, "Upgrade purchase notification", param, sTranslatedName, iItemLevel+1);
						}
					}
				}
			}
			
			DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
		}
	}
}

public TopMenu_HandleSell(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[8], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				return;
			
			decl String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			Format(buffer, maxlength, "%s Lvl %d [%T: %d]", sTranslatedName, GetClientUpgradeLevel(param, upgrade[UPGR_index]), "Sale", param, GetUpgradeSale(upgrade[UPGR_index], GetClientUpgradeLevel(param, upgrade[UPGR_index])));
		}
		case TopMenuAction_DrawOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			new iCurrentLevel = GetClientUpgradeLevel(param, upgrade[UPGR_index]);
			
			// Allow clients to sell upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// There is nothing to sell..
			if(iCurrentLevel <= 0)
				buffer[0] = ITEMDRAW_DISABLED;
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
				return;
			}
			
			new Handle:hMenu = CreateMenu(Menu_ConfirmSell, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
			SetMenuExitBackButton(hMenu, true);
		
			SetMenuTitle(hMenu, "credits_display");
			
			decl String:sIndex[10];
			IntToString(upgrade[UPGR_index], sIndex, sizeof(sIndex));
			AddMenuItem(hMenu, sIndex, "Yes");
			AddMenuItem(hMenu, "no", "No");
			
			DisplayMenu(hMenu, param, MENU_TIME_FOREVER);
		}
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
		Client_PrintToChat(param1, false, "%t", "Upgrade sold", sTranslatedName, GetClientUpgradeLevel(param1, iItemIndex)+1);
		
		DisplayTopMenu(g_hRPGTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T\n-----\n%T\n", "Credits", param1, GetClientCredits(param1), "Are you sure?", param1);
		
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
			DisplayTopMenu(g_hRPGTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	return 0;
}

public TopMenu_HandleStats(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			decl String:sName[64];
			GetTopMenuObjName(topmenu, object_id, sName, sizeof(sName));
			
			if(StrEqual(sName, "level"))
			{
				Format(buffer, maxlength, "%T", "Level", param, GetClientLevel(param));
			}
			else if(StrEqual(sName, "exp"))
			{
				Format(buffer, maxlength, "%T", "Experience short", param, GetClientExperience(param), Stats_LvlToExp(GetClientLevel(param)));
			}
			else if(StrEqual(sName, "credits"))
			{
				Format(buffer, maxlength, "%T", "Credits", param, GetClientCredits(param));
			}
			else if(StrEqual(sName, "rank"))
			{
				Format(buffer, maxlength, "%T", "Rank", param, GetClientRank(param), GetRankCount());
			}
		}
		case TopMenuAction_DrawOption:
		{
			// This is an informational panel only. Draw all items as disabled.
			buffer[0] = ITEMDRAW_DISABLED;
		}
	}	
}

DisplayCommandsMenu(client, position)
{
	new Handle:hMenu = CreateMenu(Menu_HandleCommands, MENU_ACTIONS_DEFAULT|MenuAction_Display);
	SetMenuExitBackButton(hMenu, true);
	SetMenuTitle(hMenu, "credits_display");
	
	decl String:sLine[64];
	new Handle:hCommandlist = GetCommandList();
	new iSize = GetArraySize(hCommandlist);
	new iCommand[RPGCommand];
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(hCommandlist, i, iCommand[0], _:RPGCommand);
		
		if(!GetCommandTranslation(client, iCommand[c_command], CommandTranslationType_ShortDescription, sLine, sizeof(sLine)))
			continue;
		
		Format(sLine, sizeof(sLine), "%s: %s", iCommand[c_command], sLine);
		
		AddMenuItem(hMenu, iCommand[c_command], sLine);
	}
	
	if(position > 0)
		DisplayMenuAtItem(hMenu, client, position, MENU_TIME_FOREVER);
	else
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleCommands(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		decl String:sDescription[256];
		if(GetCommandTranslation(param1, sInfo, CommandTranslationType_Description, sDescription, sizeof(sDescription)))
			Client_PrintToChat(param1, false, "{OG}SM:RPG{N} > {G}%s{N}: %s", sInfo, sDescription);
		
		DisplayCommandsMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T\n-----\n", "Credits", param1, GetClientCredits(param1));
		
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

DisplaySettingsMenu(client)
{
	if(GetFeatureStatus(FeatureType_Native, "DisplayTopMenuCategory") == FeatureStatus_Available)
		DisplayTopMenuCategory(g_hRPGTopMenu, g_TopMenuSettings, client);
	else
		DisplayTopMenu(g_hRPGTopMenu, client, TopMenuPosition_Start); // Fallback to just displaying the rpgmenu if running "old" sourcemod version.
}

public TopMenu_HandleSettings(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxlength, "%T", "Reset Stats", param);
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sName[64];
			GetTopMenuObjName(topmenu, object_id, sName, sizeof(sName));
			
			if(StrEqual(sName, "resetstats"))
			{
				DisplayMenu(g_hConfirmResetStatsMenu, param, MENU_TIME_FOREVER);
			}
		}
	}	
}

public Menu_ConfirmResetStats(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
		{
			DisplayTopMenu(g_hRPGTopMenu, param1, TopMenuPosition_LastCategory);
			return 0;
		}
		
		ResetStats(param1);
		
		Client_PrintToChat(param1, false, "%t", "Stats have been reset");
		LogMessage("%L reset his own rpg stats on purpose.", param1);
		
		DisplaySettingsMenu(param1);
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		new Handle:hPanel = Handle:param2;
		
		// Display the current credits in the title
		decl String:sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T\n-----\n%T\n", "Credits", param1, GetClientCredits(param1), "Confirm stats reset", param1);
		
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
			DisplayTopMenu(g_hRPGTopMenu, param1, TopMenuPosition_LastCategory);
	}
	return 0;
}

DisplayHelpMenu(client)
{
	if(GetFeatureStatus(FeatureType_Native, "DisplayTopMenuCategory") == FeatureStatus_Available)
		DisplayTopMenuCategory(g_hRPGTopMenu, g_TopMenuHelp, client);
	else
		DisplayTopMenu(g_hRPGTopMenu, client, TopMenuPosition_Start); // Fallback to just displaying the rpgmenu if running "old" sourcemod version.
}

public TopMenu_HandleHelp(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[8], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				return;
			
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], buffer, maxlength);
		}
		case TopMenuAction_DrawOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			new iCurrentLevel = GetClientUpgradeLevel(param, upgrade[UPGR_index]);
			
			// Allow clients to read help about upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
				return;
			}
			
			new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH], String:sTranslatedDescription[MAX_UPGRADE_DESCRIPTION_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			GetUpgradeTranslatedDescription(param, upgrade[UPGR_index], sTranslatedDescription, sizeof(sTranslatedDescription));
			
			Client_PrintToChat(param, false, "{OG}SM:RPG{N} > {G}%s{N}: %s", sTranslatedName, sTranslatedDescription);
			
			DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
		}
	}
}

DisplayOtherUpgradesMenu(client, targetClient)
{
	new Handle:hMenu = CreateMenu(Menu_HandleOtherUpgrades);
	SetMenuExitButton(hMenu, true);
	
	SetMenuTitle(hMenu, "%N\n%T\n-----\n", targetClient, "Credits", client, GetClientCredits(targetClient));
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo], iCurrentLevel;
	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH], String:sLine[128], String:sIndex[8];
	for(new i=0;i<iSize;i++)
	{
		iCurrentLevel = GetClientUpgradeLevel(targetClient, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled] || !HasAccessToUpgrade(targetClient, upgrade))
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		IntToString(i, sIndex, sizeof(sIndex));
		if(iCurrentLevel >= upgrade[UPGR_maxLevel])
			Format(sLine, sizeof(sLine), "%s Lvl MAX", sTranslatedName);
		else
			Format(sLine, sizeof(sLine), "%s Lvl %d", sTranslatedName, iCurrentLevel);
		AddMenuItem(hMenu, sIndex, sLine, ITEMDRAW_DISABLED);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleOtherUpgrades(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

// Helper functions to access those pubvars before they are declared..
Handle:GetRPGTopMenu()
{
	return g_hRPGTopMenu;
}

TopMenuObject:GetUpgradesCategory()
{
	return g_TopMenuUpgrades;
}

TopMenuObject:GetSellCategory()
{
	return g_TopMenuSell;
}

TopMenuObject:GetHelpCategory()
{
	return g_TopMenuHelp;
}