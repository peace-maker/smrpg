#pragma semicolon 1
#include <sourcemod>
#include <topmenus>

TopMenu g_hRPGTopMenu;

TopMenuObject g_TopMenuUpgrades;
TopMenuObject g_TopMenuSell;
TopMenuObject g_TopMenuUpgradeSettings;
TopMenuObject g_TopMenuStats;
TopMenuObject g_TopMenuSettings;
TopMenuObject g_TopMenuHelp;

Menu g_hConfirmResetStatsMenu;

Handle g_hfwdOnRPGMenuCreated;
Handle g_hfwdOnRPGMenuReady;

int g_iSelectedSettingsUpgrade[MAXPLAYERS+1] = {-1,...};

/**
 * Setup functions to create the topmenu and API.
 */
void RegisterTopMenu()
{
	g_hRPGTopMenu = new TopMenu(TopMenu_DefaultCategoryHandler);
	g_hRPGTopMenu.CacheTitles = false;
	
	g_TopMenuUpgrades = g_hRPGTopMenu.AddCategory(RPGMENU_UPGRADES, TopMenu_DefaultCategoryHandler);
	g_TopMenuSell = g_hRPGTopMenu.AddCategory(RPGMENU_SELL, TopMenu_DefaultCategoryHandler);
	g_TopMenuUpgradeSettings = g_hRPGTopMenu.AddCategory(RPGMENU_UPGRADESETTINGS, TopMenu_DefaultCategoryHandler);
	g_TopMenuStats = g_hRPGTopMenu.AddCategory(RPGMENU_STATS, TopMenu_DefaultCategoryHandler);
	g_TopMenuSettings = g_hRPGTopMenu.AddCategory(RPGMENU_SETTINGS, TopMenu_DefaultCategoryHandler);
	g_TopMenuHelp = g_hRPGTopMenu.AddCategory(RPGMENU_HELP, TopMenu_DefaultCategoryHandler);
}

void RegisterTopMenuForwards()
{
	g_hfwdOnRPGMenuCreated = CreateGlobalForward("SMRPG_OnRPGMenuCreated", ET_Ignore, Param_Cell);
	g_hfwdOnRPGMenuReady = CreateGlobalForward("SMRPG_OnRPGMenuReady", ET_Ignore, Param_Cell);
}

void RegisterTopMenuNatives()
{
	CreateNative("SMRPG_GetTopMenu", Native_GetTopMenu);
}

void InitMenu()
{
	// Add any already loaded upgrades to the menus
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo];
	char sBuffer[MAX_UPGRADE_SHORTNAME_LENGTH+20];
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade[UPGR_topmenuUpgrades] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgupgrade_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuUpgrades] = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleUpgrades, g_TopMenuUpgrades);
		}
		if(upgrade[UPGR_topmenuSell] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgsell_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuSell] = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleSell, g_TopMenuSell);
		}
		if(upgrade[UPGR_topmenuUpgradeSettings] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgupgrsettings_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuUpgradeSettings] = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleUpgradeSettings, g_TopMenuUpgradeSettings);
		}
		if(upgrade[UPGR_topmenuHelp] == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpghelp_%s", upgrade[UPGR_shortName]);
			upgrade[UPGR_topmenuHelp] = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleHelp, g_TopMenuHelp);
		}
		SaveUpgradeConfig(upgrade);
	}
	
	// Stats Menu
	g_hRPGTopMenu.AddItem("level", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("exp", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("credits", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("rank", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("lastexp", TopMenu_HandleStats, g_TopMenuStats);
	
	// Settings Menu
	g_hRPGTopMenu.AddItem("resetstats", TopMenu_HandleSettings, g_TopMenuSettings);
	g_hRPGTopMenu.AddItem("toggleautoshow", TopMenu_HandleSettings, g_TopMenuSettings);
	g_hRPGTopMenu.AddItem("togglefade", TopMenu_HandleSettings, g_TopMenuSettings);
	
	// Reset Stats Confirmation
	g_hConfirmResetStatsMenu = new Menu(Menu_ConfirmResetStats, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	g_hConfirmResetStatsMenu.ExitBackButton = true;

	g_hConfirmResetStatsMenu.SetTitle("credits_display");
	
	g_hConfirmResetStatsMenu.AddItem("yes", "Yes");
	g_hConfirmResetStatsMenu.AddItem("no", "No");
	
	Call_StartForward(g_hfwdOnRPGMenuCreated);
	Call_PushCell(g_hRPGTopMenu);
	Call_Finish();
	
	Call_StartForward(g_hfwdOnRPGMenuReady);
	Call_PushCell(g_hRPGTopMenu);
	Call_Finish();
}

void ResetPlayerMenu(int client)
{
	g_iSelectedSettingsUpgrade[client] = -1;
}

/**
 * Native callbacks
 */
public int Native_GetTopMenu(Handle plugin, int numParams)
{
	return view_as<int>(g_hRPGTopMenu);
}

void DisplayMainMenu(int client)
{
	g_hRPGTopMenu.Display(client, TopMenuPosition_Start);
}

void DisplayUpgradesMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuUpgrades, client);
}

/**
 * TopMenu callback handlers
 */
// Print the default categories correctly.
public void TopMenu_DefaultCategoryHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
		{
			if(object_id == g_TopMenuUpgrades)
				Format(buffer, maxlength, "SM:RPG %T", "Upgrades", param);
			else if(object_id == g_TopMenuSell)
				Format(buffer, maxlength, "SM:RPG %T", "Sell", param);
			else if(object_id == g_TopMenuUpgradeSettings)
				Format(buffer, maxlength, "SM:RPG %T", "Upgrade Settings", param);
			else if(object_id == g_TopMenuStats)
				Format(buffer, maxlength, "SM:RPG %T", "Stats", param);
			else if(object_id == g_TopMenuSettings)
				Format(buffer, maxlength, "SM:RPG %T", "Settings", param);
			else if(object_id == g_TopMenuHelp)
				Format(buffer, maxlength, "SM:RPG %T", "Help", param);
			else
				Format(buffer, maxlength, "SM:RPG %T", "Menu", param);
			
			// Always display the current credits in the title
			Format(buffer, maxlength, "%s\n%T\n-----\n", buffer, "Credits", param, GetClientCredits(param));
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

public void TopMenu_HandleUpgrades(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[11], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			
			if(iCurrentLevel >= upgrade[UPGR_maxLevel])
			{
				Format(buffer, maxlength, "%T", "RPG menu buy upgrade entry max level", param, sTranslatedName, iCurrentLevel, "Cost", sTeamlock);
			}
			// Optionally show the maxlevel of the upgrade
			else if (g_hCVShowMaxLevelInMenu.BoolValue)
			{
				Format(buffer, maxlength, "%T", "RPG menu buy upgrade entry show max", param, sTranslatedName, iCurrentLevel+1, upgrade[UPGR_maxLevel], "Cost", GetUpgradeCost(upgrade[UPGR_index], iCurrentLevel+1), sTeamlock);
			}
			else
			{
				Format(buffer, maxlength, "%T", "RPG menu buy upgrade entry", param, sTranslatedName, iCurrentLevel+1, "Cost", GetUpgradeCost(upgrade[UPGR_index], iCurrentLevel+1), sTeamlock);
			}
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[11], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled] || !HasAccessToUpgrade(param, upgrade))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			int iLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
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
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[11], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled] || !HasAccessToUpgrade(param, upgrade))
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}
			
			int iItemIndex = upgrade[UPGR_index];
			int iItemLevel = GetClientPurchasedUpgradeLevel(param, iItemIndex);
			int iCost = GetUpgradeCost(iItemIndex, iItemLevel+1);
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
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
					if(g_hCVShowUpgradePurchase.BoolValue)
					{
						for(int i=1;i<=MaxClients;i++)
						{
							if(i != param && IsClientInGame(i) && !IsFakeClient(i))
							{
								GetUpgradeTranslatedName(i, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
								Client_PrintToChat(i, false, "%t", "Upgrade purchase notification", param, sTranslatedName, iItemLevel+1);
							}
						}
					}
				}
			}
			
			g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

public void TopMenu_HandleSell(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[8], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade))
				return;

			// Don't show the upgrade if it is disabled and players are not allowed to sell disabled upgrades.
			// TODO: Show if upgrade is disabled?
			if(!upgrade[UPGR_enabled] && (!g_hCVAllowSellDisabled.BoolValue || GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]) <= 0))
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			// Optionally show the maxlevel of the upgrade
			if (g_hCVShowMaxLevelInMenu.BoolValue)
			{
				Format(buffer, maxlength, "%T", "RPG menu sell upgrade entry show max", param, sTranslatedName, GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]), upgrade[UPGR_maxLevel], "Sale", GetUpgradeSale(upgrade[UPGR_index], GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index])), sTeamlock);
			}
			else
			{
				Format(buffer, maxlength, "%T", "RPG menu sell upgrade entry", param, sTranslatedName, GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]), "Sale", GetUpgradeSale(upgrade[UPGR_index], GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index])), sTeamlock);
			}
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}

			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			// Don't show the upgrade if it is disabled and players are not allowed to sell disabled upgrades.
			if(!upgrade[UPGR_enabled] && (!g_hCVAllowSellDisabled.BoolValue || iCurrentLevel <= 0))
				return;
			
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
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade))
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}

			// Don't allow selling the upgrade if it is disabled and players are not allowed to sell disabled upgrades.
			if(!upgrade[UPGR_enabled] && (!g_hCVAllowSellDisabled.BoolValue || GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]) <= 0))
				return;
			
			Menu hMenu = new Menu(Menu_ConfirmSell, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
			hMenu.ExitBackButton = true;
		
			hMenu.SetTitle("credits_display");
			
			char sIndex[10];
			IntToString(upgrade[UPGR_index], sIndex, sizeof(sIndex));
			hMenu.AddItem(sIndex, "Yes");
			hMenu.AddItem("no", "No");
			
			hMenu.Display(param, MENU_TIME_FOREVER);
		}
	}
}

public int Menu_ConfirmSell(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
			return 0;
		
		int iItemIndex = StringToInt(sInfo);
		int upgrade[InternalUpgradeInfo];
		GetUpgradeByIndex(iItemIndex, upgrade);
		char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
		GetUpgradeTranslatedName(param1, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		if (SellClientUpgrade(param1, iItemIndex))
			Client_PrintToChat(param1, false, "%t", "Upgrade sold", sTranslatedName, GetClientPurchasedUpgradeLevel(param1, iItemIndex));
		
		g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		Panel hPanel = view_as<Panel>(param2);
		
		// Display the current credits in the title
		char sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T\n-----\n%T\n", "Credits", param1, GetClientCredits(param1), "Are you sure?", param1);
		
		hPanel.SetTitle(sBuffer);
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
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public void TopMenu_HandleUpgradeSettings(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[16], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			int iPurchasedLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			int iSelectedLevel = GetClientSelectedUpgradeLevel(param, upgrade[UPGR_index]);
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			
			char sBuffer[128];
			if(!g_hCVDisableLevelSelection.BoolValue)
				Format(sBuffer, sizeof(sBuffer), "%T", "RPG menu upgrade settings entry level selection", param, sTranslatedName, iSelectedLevel, iPurchasedLevel, IsClientUpgradeEnabled(param, upgrade[UPGR_index])?"On":"Off", sTeamlock);
			else
				Format(sBuffer, sizeof(sBuffer), "%T", "RPG menu upgrade settings entry", param, sTranslatedName, iSelectedLevel, IsClientUpgradeEnabled(param, upgrade[UPGR_index])?"On":"Off", sTeamlock);
			strcopy(buffer, maxlength, sBuffer);
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[16], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			
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
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[16], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}
			
			DisplayUpgradeSettingsMenu(param, upgrade[UPGR_index]);
		}
	}
}

void DisplayUpgradeSettingsMenu(int client, int iUpgradeIndex)
{
	Menu hMenu = new Menu(Menu_HandleUpgradeSettings);
	hMenu.ExitBackButton = true;

	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, iUpgradeIndex, sTranslatedName, sizeof(sTranslatedName));
	hMenu.SetTitle("%T\n-----\n%s\n", "Credits", client, GetClientCredits(client), sTranslatedName);
	
	int playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	
	char sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "%T: %T", "Enabled", client, playerupgrade[PUI_enabled]?"On":"Off", client);
	hMenu.AddItem("enable", sBuffer);
	
	if(!g_hCVDisableLevelSelection.BoolValue)
	{
		Format(sBuffer, sizeof(sBuffer), "%T: %d/%d", "Selected level", client, playerupgrade[PUI_selectedlevel], playerupgrade[PUI_purchasedlevel]);
		hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
		Format(sBuffer, sizeof(sBuffer), "%T", "Increase selected level", client);
		hMenu.AddItem("incselect", sBuffer, playerupgrade[PUI_selectedlevel]<playerupgrade[PUI_purchasedlevel]?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
		Format(sBuffer, sizeof(sBuffer), "%T", "Decrease selected level", client);
		hMenu.AddItem("decselect", sBuffer, playerupgrade[PUI_selectedlevel]>0?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	bool bHasVisuals = upgrade[UPGR_visualsConvar] != null && upgrade[UPGR_enableVisuals];
	bool bHasSounds = upgrade[UPGR_soundsConvar] != null && upgrade[UPGR_enableSounds];
	
	if(bHasVisuals || bHasSounds)
	{
		hMenu.AddItem("", "", ITEMDRAW_SPACER);
		if(bHasVisuals)
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %T", "Visual effects", client, playerupgrade[PUI_visuals]?"On":"Off", client);
			hMenu.AddItem("visuals", sBuffer);
		}
		if(bHasSounds)
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %T", "Sound effects", client, playerupgrade[PUI_sounds]?"On":"Off", client);
			hMenu.AddItem("sounds", sBuffer);
		}
	}
	
	g_iSelectedSettingsUpgrade[client] = iUpgradeIndex;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleUpgradeSettings(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		int playerupgrade[PlayerUpgradeInfo];
		GetPlayerUpgradeInfoByIndex(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		
		if(StrEqual(sInfo, "enable"))
		{
			SetClientUpgradeEnabledStatus(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade[PUI_enabled]?false:true);
		}
		else if(StrEqual(sInfo, "incselect"))
		{
			if(!g_hCVDisableLevelSelection.BoolValue)
				SetClientSelectedUpgradeLevel(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade[PUI_selectedlevel]+1);
		}
		else if(StrEqual(sInfo, "decselect"))
		{
			if(playerupgrade[PUI_selectedlevel] > 0 && !g_hCVDisableLevelSelection.BoolValue)
				SetClientSelectedUpgradeLevel(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade[PUI_selectedlevel]-1);
		}
		else if(StrEqual(sInfo, "visuals"))
		{
			playerupgrade[PUI_visuals] = playerupgrade[PUI_visuals]?false:true;
			SavePlayerUpgradeInfo(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		}
		else if(StrEqual(sInfo, "sounds"))
		{
			playerupgrade[PUI_sounds] = playerupgrade[PUI_sounds]?false:true;
			SavePlayerUpgradeInfo(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		}
		
		DisplayUpgradeSettingsMenu(param1, g_iSelectedSettingsUpgrade[param1]);
	}
	else if(action == MenuAction_Cancel)
	{
		g_iSelectedSettingsUpgrade[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

void DisplayStatsMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuStats, client);
}

public void TopMenu_HandleStats(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sName[64];
			topmenu.GetObjName(object_id, sName, sizeof(sName));
			
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
			char sName[64];
			topmenu.GetObjName(object_id, sName, sizeof(sName));
			
			// HACKHACK: Don't disable the lastexp one
			if(!StrEqual(sName, "lastexp"))
			{
				// This is an informational panel only. Draw all items as disabled.
				buffer[0] = ITEMDRAW_DISABLED;
			}
		}
		case TopMenuAction_SelectOption:
		{
			char sName[64];
			topmenu.GetObjName(object_id, sName, sizeof(sName));
			
			if(StrEqual(sName, "lastexp"))
			{
				DisplaySessionLastExperienceMenu(param, true);
			}
		}
	}	
}

void DisplaySettingsMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuSettings, client);
}

public void TopMenu_HandleSettings(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	char sName[64];
	topmenu.GetObjName(object_id, sName, sizeof(sName));
	
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
				if(!g_hCVAllowSelfReset.BoolValue)
					buffer[0] = ITEMDRAW_IGNORE;
			}
		}
		case TopMenuAction_SelectOption:
		{
			if(StrEqual(sName, "resetstats"))
			{
				g_hConfirmResetStatsMenu.Display(param, MENU_TIME_FOREVER);
			}
			else if(StrEqual(sName, "toggleautoshow"))
			{
				SetShowMenuOnLevelUp(param, !ShowMenuOnLevelUp(param));
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
			}
			else if(StrEqual(sName, "togglefade"))
			{
				SetFadeScreenOnLevelUp(param, !FadeScreenOnLevelUp(param));
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
			}
		}
	}	
}

public int Menu_ConfirmResetStats(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
		{
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
			return 0;
		}
		
		// Are players allowed to reset themselves?
		// Player might still had the menu open while this setting changed.
		if(g_hCVAllowSelfReset.BoolValue)
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
		Panel hPanel = view_as<Panel>(param2);
		
		// Display the current credits in the title
		char sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T\n-----\n%T\n", "Credits", param1, GetClientCredits(param1), "Confirm stats reset", param1);
		
		hPanel.SetTitle(sBuffer);
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
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	return 0;
}

void DisplayHelpMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuHelp, client);
}

public void TopMenu_HandleHelp(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			if(!GetUpgradeByShortname(sShortname[8], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade[UPGR_teamlock] > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade[UPGR_teamlock] < GetTeamCount())
			{
				GetTeamName(upgrade[UPGR_teamlock], sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			char sDescription[MAX_UPGRADE_DESCRIPTION_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sDescription, sizeof(sDescription));
			
			Format(buffer, maxlength, "%s%s", sDescription, sTeamlock);
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade[UPGR_index]);
			
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
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			int upgrade[InternalUpgradeInfo];
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH], sTranslatedDescription[MAX_UPGRADE_DESCRIPTION_LENGTH];
			GetUpgradeTranslatedName(param, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
			GetUpgradeTranslatedDescription(param, upgrade[UPGR_index], sTranslatedDescription, sizeof(sTranslatedDescription));
			
			Client_PrintToChat(param, false, "{OG}SM:RPG{N} > {G}%s{N}: %s", sTranslatedName, sTranslatedDescription);
			
			g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

void DisplayOtherUpgradesMenu(int client, int targetClient)
{
	Menu hMenu = new Menu(Menu_HandleOtherUpgrades);
	hMenu.ExitBackButton = true;
	
	hMenu.SetTitle("%N\n%T\n-----\n", targetClient, "Credits", client, GetClientCredits(targetClient));
	
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo], iCurrentLevel;
	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH], sLine[128], sIndex[8];
	for(int i=0;i<iSize;i++)
	{
		iCurrentLevel = GetClientPurchasedUpgradeLevel(targetClient, i);
		GetUpgradeByIndex(i, upgrade);
		
		// Don't show disabled items in the menu.
		if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled] || !HasAccessToUpgrade(targetClient, upgrade) || !IsClientInLockedTeam(targetClient, upgrade))
			continue;
		
		GetUpgradeTranslatedName(client, upgrade[UPGR_index], sTranslatedName, sizeof(sTranslatedName));
		
		if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		{
			Format(sLine, sizeof(sLine), "%T", "RPG menu other players upgrades entry max level", client, sTranslatedName, iCurrentLevel);
		}
		// Optionally show the maxlevel of the upgrade
		else if (g_hCVShowMaxLevelInMenu.BoolValue)
		{
			Format(sLine, sizeof(sLine), "%T", "RPG menu other players upgrades entry show max", client, sTranslatedName, iCurrentLevel, upgrade[UPGR_maxLevel]);
		}
		else
		{
			Format(sLine, sizeof(sLine), "%T", "RPG menu other players upgrades entry", client, sTranslatedName, iCurrentLevel);
		}

		IntToString(i, sIndex, sizeof(sIndex));
		hMenu.AddItem(sIndex, sLine, ITEMDRAW_DISABLED);
	}
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleOtherUpgrades(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
}

// Helper functions to access those pubvars before they are declared..
TopMenu GetRPGTopMenu()
{
	return g_hRPGTopMenu;
}

TopMenuObject GetUpgradesCategory()
{
	return g_TopMenuUpgrades;
}

TopMenuObject GetSellCategory()
{
	return g_TopMenuSell;
}

TopMenuObject GetUpgradeSettingsCategory()
{
	return g_TopMenuUpgradeSettings;
}

TopMenuObject GetHelpCategory()
{
	return g_TopMenuHelp;
}

// Handle the logic of the smrpg_show_upgrades_teamlock convar.
int GetItemDrawFlagsForTeamlock(int iLevel, bool bBuyMenu)
{
	int iShowTeamlock = g_hCVShowUpgradesOfOtherTeam.IntValue;
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
				if(bBuyMenu && !g_hCVBuyUpgradesOfOtherTeam.BoolValue)
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
			if(bBuyMenu && !g_hCVBuyUpgradesOfOtherTeam.BoolValue)
			{
				return ITEMDRAW_DISABLED;
			}
			// else let him use it.
		}
	}
	return 0;
}