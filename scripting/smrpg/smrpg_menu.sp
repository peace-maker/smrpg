#pragma semicolon 1
#include <sourcemod>
#include <topmenus>

new Handle:g_hRPGTopMenu;

new TopMenuObject:g_TopMenuUpgrades;
new TopMenuObject:g_TopMenuSell;
new TopMenuObject:g_TopMenuUpgradeSettings;
new TopMenuObject:g_TopMenuStats;
new TopMenuObject:g_TopMenuSettings;
new TopMenuObject:g_TopMenuHelp;

new Handle:g_hConfirmResetStatsMenu;

new Handle:g_hfwdOnRPGMenuCreated;
new Handle:g_hfwdOnRPGMenuReady;

new g_iSelectedSettingsUpgrade[MAXPLAYERS+1] = {-1,...};

/**
 * Setup functions to create the topmenu and API.
 */
RegisterTopMenu()
{
	g_hRPGTopMenu = CreateTopMenu(TopMenu_DefaultCategoryHandler);
	SetTopMenuTitleCaching(g_hRPGTopMenu, false);
	
	g_TopMenuUpgrades = AddToTopMenu(g_hRPGTopMenu, RPGMENU_UPGRADES, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuSell = AddToTopMenu(g_hRPGTopMenu, RPGMENU_SELL, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuUpgradeSettings = AddToTopMenu(g_hRPGTopMenu, RPGMENU_UPGRADESETTINGS, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
	g_TopMenuStats = AddToTopMenu(g_hRPGTopMenu, RPGMENU_STATS, TopMenuObject_Category, TopMenu_DefaultCategoryHandler, INVALID_TOPMENUOBJECT);
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
		if(upgrade[UPGR_topmenuUpgradeSettings] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgupgrsettings_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuUpgradeSettings] = AddToTopMenu(g_hRPGTopMenu, sBuffer, TopMenuObject_Item, TopMenu_HandleUpgradeSettings, g_TopMenuUpgradeSettings);
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
	AddToTopMenu(g_hRPGTopMenu, "lastexp", TopMenuObject_Item, TopMenu_HandleStats, g_TopMenuStats);
	
	// Settings Menu
	AddToTopMenu(g_hRPGTopMenu, "resetstats", TopMenuObject_Item, TopMenu_HandleSettings, g_TopMenuSettings);
	AddToTopMenu(g_hRPGTopMenu, "toggleautoshow", TopMenuObject_Item, TopMenu_HandleSettings, g_TopMenuSettings);
	AddToTopMenu(g_hRPGTopMenu, "togglefade", TopMenuObject_Item, TopMenu_HandleSettings, g_TopMenuSettings);
	
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

ResetPlayerMenu(client)
{
	g_iSelectedSettingsUpgrade[client] = -1;
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
	DisplayTopMenuCategory(g_hRPGTopMenu, g_TopMenuUpgrades, client);
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
			else if(object_id == g_TopMenuUpgradeSettings)
				Format(buffer, maxlength, "%T", "Upgrade Settings", param);
			else if(object_id == g_TopMenuStats)
				Format(buffer, maxlength, "%T", "Stats", param);
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
			
			// Show the team this upgrade is locked to, if it is.
			new String:sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && GetConVarBool(g_hCVShowTeamlockNoticeOwnTeam)) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			decl String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			new iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			
			if(iCurrentLevel >= upgrade[UPGR_maxLevel])
			{
				Format(buffer, maxlength, "%s Lvl %d MAX [%T: MAX]%s", sTranslatedName, iCurrentLevel, "Cost", param, sTeamlock);
			}
			else
			{
				Format(buffer, maxlength, "%s Lvl %d [%T: %d]%s", sTranslatedName, iCurrentLevel+1, "Cost", param, GetUpgradeCost(upgrade[UPGR_index], iCurrentLevel+1), sTeamlock);
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
			
			new iLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			// The upgrade is teamlocked and the client is in the wrong team.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iLevel, true);
			}
			
			// Don't let players buy upgrades they already maxed out.
			if(iLevel >= upgrade[UPGR_maxLevel])
				buffer[0] |= ITEMDRAW_DISABLED;
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
			new iItemLevel = GetClientPurchasedUpgradeLevel(param, iItemIndex);
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
							{
								GetUpgradeTranslatedName(i, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
								Client_PrintToChat(i, false, "Upgrade purchase notification", param, sTranslatedName, iItemLevel+1);
							}
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
			
			// Show the team this upgrade is locked to, if it is.
			new String:sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && GetConVarBool(g_hCVShowTeamlockNoticeOwnTeam)) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			decl String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			Format(buffer, maxlength, "%s Lvl %d [%T: %d]%s", sTranslatedName, GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]), "Sale", param, GetUpgradeSale(upgrade[UPGR_index], GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index])), sTeamlock);
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
			
			new iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			
			// Allow clients to sell upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// The upgrade is teamlocked and the client is in the wrong team.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iCurrentLevel, false);
			}
			
			// There is nothing to sell..
			if(iCurrentLevel <= 0)
				buffer[0] |= ITEMDRAW_DISABLED;
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
		Client_PrintToChat(param1, false, "%t", "Upgrade sold", sTranslatedName, GetClientPurchasedUpgradeLevel(param1, iItemIndex)+1);
		
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

public TopMenu_HandleUpgradeSettings(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[16], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				return;
			
			// Show the team this upgrade is locked to, if it is.
			new String:sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && GetConVarBool(g_hCVShowTeamlockNoticeOwnTeam)) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			new iPurchasedLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			new iSelectedLevel = GetClientSelectedUpgradeLevel(param, upgrade[UPGR_index]);
			decl String:sBuffer[128];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sBuffer, sizeof(sBuffer));
			if(!GetConVarBool(g_hCVDisableLevelSelection))
				Format(sBuffer, sizeof(sBuffer), "%s Lvl %d/%d", sBuffer, iSelectedLevel, iPurchasedLevel);
			
			Format(sBuffer, sizeof(sBuffer), "%s [%T]%s", sBuffer, IsClientUpgradeEnabled(param, upgrade[UPGR_index])?"On":"Off", param, sTeamlock);
			strcopy(buffer, maxlength, sBuffer);
		}
		case TopMenuAction_DrawOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[16], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			new iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			
			// Allow clients to view upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// Don't show the upgrade, if it's teamlocked, the client is in the wrong team and didn't buy it before.
			// Make sure to show it, if we're set to show all.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iCurrentLevel, false);
				return;
			}
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			GetTopMenuObjName(topmenu, object_id, sShortname, sizeof(sShortname));
			
			new upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[16], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
				return;
			}
			
			DisplayUpgradeSettingsMenu(param, upgrade[UPGR_index]);
		}
	}
}

DisplayUpgradeSettingsMenu(client, iUpgradeIndex)
{
	new Handle:hMenu = CreateMenu(Menu_HandleUpgradeSettings, MENU_ACTIONS_DEFAULT);
	SetMenuExitBackButton(hMenu, true);

	new String:sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, iUpgradeIndex, sTranslatedName, sizeof(sTranslatedName));
	SetMenuTitle(hMenu, "%T\n-----\n%s\n", "Credits", client, GetClientCredits(client), sTranslatedName);
	
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	
	decl String:sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "%T: %T", "Enabled", client, playerupgrade[PUI_enabled]?"On":"Off", client);
	AddMenuItem(hMenu, "enable", sBuffer);
	
	if(!GetConVarBool(g_hCVDisableLevelSelection))
	{
		Format(sBuffer, sizeof(sBuffer), "%T: %d/%d", "Selected level", client, playerupgrade[PUI_selectedlevel], playerupgrade[PUI_purchasedlevel]);
		AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
		Format(sBuffer, sizeof(sBuffer), "%T", "Increase selected level", client);
		AddMenuItem(hMenu, "incselect", sBuffer, playerupgrade[PUI_selectedlevel]<playerupgrade[PUI_purchasedlevel]?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
		Format(sBuffer, sizeof(sBuffer), "%T", "Decrease selected level", client);
		AddMenuItem(hMenu, "decselect", sBuffer, playerupgrade[PUI_selectedlevel]>0?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	new bool:bHasVisuals = upgrade[UPGR_visualsConvar] != INVALID_HANDLE && upgrade[UPGR_enableVisuals];
	new bool:bHasSounds = upgrade[UPGR_soundsConvar] != INVALID_HANDLE && upgrade[UPGR_enableSounds];
	
	if(bHasVisuals || bHasSounds)
	{
		AddMenuItem(hMenu, "", "", ITEMDRAW_SPACER);
		if(bHasVisuals)
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %T", "Visual effects", client, playerupgrade[PUI_visuals]?"On":"Off", client);
			AddMenuItem(hMenu, "visuals", sBuffer);
		}
		if(bHasSounds)
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %T", "Sound effects", client, playerupgrade[PUI_sounds]?"On":"Off", client);
			AddMenuItem(hMenu, "sounds", sBuffer);
		}
	}
	
	g_iSelectedSettingsUpgrade[client] = iUpgradeIndex;
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleUpgradeSettings(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:sInfo[16];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		new playerupgrade[PlayerUpgradeInfo];
		GetPlayerUpgradeInfoByIndex(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		
		if(StrEqual(sInfo, "enable"))
		{
			playerupgrade[PUI_enabled] = playerupgrade[PUI_enabled]?false:true;
		}
		else if(StrEqual(sInfo, "incselect"))
		{
			if(playerupgrade[PUI_selectedlevel] < playerupgrade[PUI_purchasedlevel] && !GetConVarBool(g_hCVDisableLevelSelection))
				playerupgrade[PUI_selectedlevel]++;
		}
		else if(StrEqual(sInfo, "decselect"))
		{
			if(playerupgrade[PUI_selectedlevel] > 0 && !GetConVarBool(g_hCVDisableLevelSelection))
				playerupgrade[PUI_selectedlevel]--;
		}
		else if(StrEqual(sInfo, "visuals"))
		{
			playerupgrade[PUI_visuals] = playerupgrade[PUI_visuals]?false:true;
		}
		else if(StrEqual(sInfo, "sounds"))
		{
			playerupgrade[PUI_sounds] = playerupgrade[PUI_sounds]?false:true;
		}
		
		SavePlayerUpgradeInfo(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		DisplayUpgradeSettingsMenu(param1, g_iSelectedSettingsUpgrade[param1]);
	}
	else if(action == MenuAction_Cancel)
	{
		g_iSelectedSettingsUpgrade[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
			DisplayTopMenu(g_hRPGTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

DisplayStatsMenu(client)
{
	DisplayTopMenuCategory(g_hRPGTopMenu, g_TopMenuStats, client);
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
			else if(StrEqual(sName, "lastexp"))
			{
				Format(buffer, maxlength, "%T", "Last Experience", param);
			}
		}
		case TopMenuAction_DrawOption:
		{
			decl String:sName[64];
			GetTopMenuObjName(topmenu, object_id, sName, sizeof(sName));
			
			// HACKHACK: Don't disable the lastexp one
			if(!StrEqual(sName, "lastexp"))
			{
				// This is an informational panel only. Draw all items as disabled.
				buffer[0] = ITEMDRAW_DISABLED;
			}
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sName[64];
			GetTopMenuObjName(topmenu, object_id, sName, sizeof(sName));
			
			if(StrEqual(sName, "lastexp"))
			{
				DisplaySessionLastExperienceMenu(param, true);
			}
		}
	}	
}

DisplaySettingsMenu(client)
{
	DisplayTopMenuCategory(g_hRPGTopMenu, g_TopMenuSettings, client);
}

public TopMenu_HandleSettings(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	decl String:sName[64];
	GetTopMenuObjName(topmenu, object_id, sName, sizeof(sName));
	
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			if(StrEqual(sName, "resetstats"))
			{
				Format(buffer, maxlength, "%T", "Reset Stats", param);
			}
			else if(StrEqual(sName, "toggleautoshow"))
			{
				Format(buffer, maxlength, "%T: %T", "Show menu on levelup", param, ShowMenuOnLevelUp(param)?"Yes":"No", param);
			}
			else if(StrEqual(sName, "togglefade"))
			{
				Format(buffer, maxlength, "%T: %T", "Fade screen on levelup", param, FadeScreenOnLevelUp(param)?"Yes":"No", param);
			}
		}
		case TopMenuAction_DrawOption:
		{
			if(StrEqual(sName, "resetstats"))
			{
				// Don't show the reset stats option, if disabled.
				if(!GetConVarBool(g_hCVAllowSelfReset))
					buffer[0] = ITEMDRAW_IGNORE;
			}
		}
		case TopMenuAction_SelectOption:
		{
			if(StrEqual(sName, "resetstats"))
			{
				DisplayMenu(g_hConfirmResetStatsMenu, param, MENU_TIME_FOREVER);
			}
			else if(StrEqual(sName, "toggleautoshow"))
			{
				SetShowMenuOnLevelUp(param, !ShowMenuOnLevelUp(param));
				DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
			}
			else if(StrEqual(sName, "togglefade"))
			{
				SetFadeScreenOnLevelUp(param, !FadeScreenOnLevelUp(param));
				DisplayTopMenu(g_hRPGTopMenu, param, TopMenuPosition_LastCategory);
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
		
		// Are players allowed to reset themselves?
		// Player might still had the menu open while this setting changed.
		if(GetConVarBool(g_hCVAllowSelfReset))
		{
			ResetStats(param1);
			SetPlayerLastReset(param1, GetTime());
			
			Client_PrintToChat(param1, false, "%t", "Stats have been reset");
			LogMessage("%L reset his own rpg stats on purpose.", param1);
		}
		
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
	DisplayTopMenuCategory(g_hRPGTopMenu, g_TopMenuHelp, client);
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
			
			// Show the team this upgrade is locked to, if it is.
			new String:sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && GetConVarBool(g_hCVShowTeamlockNoticeOwnTeam)) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			new String:sDescription[MAX_UPGRADE_DESCRIPTION_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sDescription, sizeof(sDescription));
			
			Format(buffer, maxlength, "%s%s", sDescription, sTeamlock);
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
			
			new iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			
			// Allow clients to read help about upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// Don't show the upgrade, if it's teamlocked, the client is in the wrong team and didn't buy the upgrade before.
			// Make sure to show it, if we're set to show all.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iCurrentLevel, false);
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
		iCurrentLevel = GetClientPurchasedUpgradeLevel(targetClient, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled] || !HasAccessToUpgrade(targetClient, upgrade) || !IsClientInLockedTeam(targetClient, upgrade))
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		IntToString(i, sIndex, sizeof(sIndex));
		if(iCurrentLevel >= upgrade[UPGR_maxLevel])
			Format(sLine, sizeof(sLine), "%s Lvl %d MAX", sTranslatedName, iCurrentLevel);
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

TopMenuObject:GetUpgradeSettingsCategory()
{
	return g_TopMenuUpgradeSettings;
}

TopMenuObject:GetHelpCategory()
{
	return g_TopMenuHelp;
}

// Handle the logic of the smrpg_show_upgrades_teamlock convar.
GetItemDrawFlagsForTeamlock(iLevel, bool:bBuyMenu)
{
	new iShowTeamlock = GetConVarInt(g_hCVShowUpgradesOfOtherTeam);
	switch(iShowTeamlock)
	{
		case SHOW_TEAMLOCK_NONE:
		{
			return ITEMDRAW_IGNORE;
		}
		case SHOW_TEAMLOCK_BOUGHT:
		{
			// The client bought it while being in the other team.
			if(iLevel > 0)
			{
				// Show it, but don't let him buy it.
				if(bBuyMenu && !GetConVarBool(g_hCVBuyUpgradesOfOtherTeam))
				{
					return ITEMDRAW_DISABLED;
				}
				// else let him use it.
			}
			// The client doesn't have the upgrade. Don't show it.
			else
			{
				return ITEMDRAW_IGNORE;
			}
		}
		case SHOW_TEAMLOCK_ALL:
		{
			// Show it, but don't let him buy it.
			if(bBuyMenu && !GetConVarBool(g_hCVBuyUpgradesOfOtherTeam))
			{
				return ITEMDRAW_DISABLED;
			}
			// else let him use it.
		}
	}
	return 0;
}