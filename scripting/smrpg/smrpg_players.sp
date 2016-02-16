#pragma semicolon 1
#include <sourcemod>
#include <smlib>

// Forwards
new Handle:g_hfwdOnBuyUpgrade;
new Handle:g_hfwdOnBuyUpgradePost;
new Handle:g_hfwdOnSellUpgrade;
new Handle:g_hfwdOnSellUpgradePost;
new Handle:g_hfwdOnClientLevel;
new Handle:g_hfwdOnClientLevelPost;
new Handle:g_hfwdOnClientExperience;
new Handle:g_hfwdOnClientExperiencePost;
new Handle:g_hfwdOnClientCredits;
new Handle:g_hfwdOnClientCreditsPost;

new Handle:g_hfwdOnClientLoaded;

enum PlayerUpgradeInfo {
	PUI_purchasedlevel,
	PUI_selectedlevel,
	bool:PUI_enabled,
	bool:PUI_visuals,
	bool:PUI_sounds
};

enum PlayerInfo
{
	PLR_level,
	PLR_experience,
	PLR_credits,
	PLR_dbId,
	bool:PLR_showMenuOnLevelup,
	bool:PLR_fadeOnLevelup,
	bool:PLR_dataLoadedFromDB,
	Handle:PLR_upgrades,
	PLR_lastReset,
	PLR_lastSeen
};

new g_iPlayerInfo[MAXPLAYERS+1][PlayerInfo];
new bool:g_bFirstLoaded[MAXPLAYERS+1];
// Bot stats are saved per name, because they don't have a steamid.
// Remember the name the bot joined with, so we use the same name everytime - even if some other plugin changes the name later.
new String:g_sOriginalBotName[MAXPLAYERS+1][MAX_NAME_LENGTH];

RegisterPlayerNatives()
{
	CreateNative("SMRPG_GetClientUpgradeLevel", Native_GetClientUpgradeLevel);
	CreateNative("SMRPG_GetClientPurchasedUpgradeLevel", Native_GetClientPurchasedUpgradeLevel);
	CreateNative("SMRPG_SetClientSelectedUpgradeLevel", Native_SetClientSelectedUpgradeLevel);
	CreateNative("SMRPG_ClientBuyUpgrade", Native_ClientBuyUpgrade);
	CreateNative("SMRPG_ClientSellUpgrade", Native_ClientSellUpgrade);
	CreateNative("SMRPG_IsUpgradeActiveOnClient", Native_IsUpgradeActiveOnClient);
	
	CreateNative("SMRPG_GetClientLevel", Native_GetClientLevel);
	CreateNative("SMRPG_SetClientLevel", Native_SetClientLevel);
	CreateNative("SMRPG_GetClientCredits", Native_GetClientCredits);
	CreateNative("SMRPG_SetClientCredits", Native_SetClientCredits);
	CreateNative("SMRPG_GetClientExperience", Native_GetClientExperience);
	CreateNative("SMRPG_SetClientExperience", Native_SetClientExperience);
	CreateNative("SMRPG_ResetClientStats", Native_ResetClientStats);
	CreateNative("SMRPG_GetClientLastResetTime", Native_GetClientLastResetTime);
	CreateNative("SMRPG_GetClientLastSeenTime", Native_GetClientLastSeenTime);
	
	CreateNative("SMRPG_ClientWantsCosmetics", Native_ClientWantsCosmetics);
}

RegisterPlayerForwards()
{
	// forward Action:SMRPG_OnBuyUpgrade(client, const String:shortname[], newlevel);
	g_hfwdOnBuyUpgrade = CreateGlobalForward("SMRPG_OnBuyUpgrade", ET_Hook, Param_Cell, Param_String, Param_Cell);
	// forward SMRPG_OnBuyUpgradePost(client, const String:shortname[], newlevel);
	g_hfwdOnBuyUpgradePost = CreateGlobalForward("SMRPG_OnBuyUpgradePost", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	// forward Action:SMRPG_OnSellUpgrade(client, const String:shortname[], newlevel);
	g_hfwdOnSellUpgrade = CreateGlobalForward("SMRPG_OnSellUpgrade", ET_Hook, Param_Cell, Param_String, Param_Cell);
	// forward SMRPG_OnSellUpgradePost(client, const String:shortname[], newlevel);
	g_hfwdOnSellUpgradePost = CreateGlobalForward("SMRPG_OnSellUpgradePost", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	
	// forward Action:SMRPG_OnClientLevel(client, oldlevel, newlevel);
	g_hfwdOnClientLevel = CreateGlobalForward("SMRPG_OnClientLevel", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward SMRPG_OnClientLevelPost(client, oldlevel, newlevel);
	g_hfwdOnClientLevelPost = CreateGlobalForward("SMRPG_OnClientLevelPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	// forward Action:SMRPG_OnClientExperience(client, oldexp, newexp);
	g_hfwdOnClientExperience = CreateGlobalForward("SMRPG_OnClientExperience", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward SMRPG_OnClientExperiencePost(client, oldexp, newexp);
	g_hfwdOnClientExperiencePost = CreateGlobalForward("SMRPG_OnClientExperiencePost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	// forward Action:SMRPG_OnClientCredits(client, oldcredits, newcredits);
	g_hfwdOnClientCredits = CreateGlobalForward("SMRPG_OnClientCredits", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward SMRPG_OnClientCreditsPost(client, oldcredits, newcredits);
	g_hfwdOnClientCreditsPost = CreateGlobalForward("SMRPG_OnClientCreditsPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	
	// forward SMRPG_OnClientLoaded(client);
	g_hfwdOnClientLoaded = CreateGlobalForward("SMRPG_OnClientLoaded", ET_Ignore, Param_Cell);
}

/**
 * Player stats management
 */
InitPlayer(client, bool:bGetBotName = true)
{
	g_bFirstLoaded[client] = true;
	
	g_iPlayerInfo[client][PLR_level] = 1;
	g_iPlayerInfo[client][PLR_experience] = 0;
	g_iPlayerInfo[client][PLR_credits] = GetConVarInt(g_hCVCreditsStart);
	g_iPlayerInfo[client][PLR_dbId] = -1;
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = false;
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = GetConVarBool(g_hCVShowMenuOnLevelDefault);
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = GetConVarBool(g_hCVFadeOnLevelDefault);
	g_iPlayerInfo[client][PLR_lastReset] = GetTime();
	g_iPlayerInfo[client][PLR_lastSeen] = GetTime();
	
	g_iPlayerInfo[client][PLR_upgrades] = CreateArray(_:PlayerUpgradeInfo);
	new iNumUpgrades = GetUpgradeCount();
	
	for(new i=0;i<iNumUpgrades;i++)
	{
		// level 0 for all upgrades
		InitPlayerNewUpgrade(client);
	}
	
	// Save the name the bot joined with, so we fetch the right info, even if some plugin changes the name of the bot afterwards.
	if(bGetBotName && IsFakeClient(client))
	{
		GetClientName(client, g_sOriginalBotName[client], sizeof(g_sOriginalBotName[]));
	}
}

AddPlayer(client)
{
	if(!g_hDatabase)
		return;
	
	if(!GetConVarBool(g_hCVEnable))
		return;
	

	decl String:sQuery[256];
	if(IsFakeClient(client))
	{
		if(!GetConVarBool(g_hCVBotSaveStats))
			return;
		
		// Lookup bot levels depending on their names.
		decl String:sNameEscaped[MAX_NAME_LENGTH*2+1];
		SQL_EscapeString(g_hDatabase, g_sOriginalBotName[client], sNameEscaped, sizeof(sNameEscaped));
		Format(sQuery, sizeof(sQuery), "SELECT player_id, level, experience, credits, lastreset, lastseen, showmenu, fadescreen FROM %s WHERE steamid IS NULL AND name = '%s' ORDER BY level DESC LIMIT 1", TBL_PLAYERS, sNameEscaped);
	}
	else
	{
		new iAccountId = GetSteamAccountID(client);
		if(!iAccountId)
			return;
		
		Format(sQuery, sizeof(sQuery), "SELECT player_id, level, experience, credits, lastreset, lastseen, showmenu, fadescreen FROM %s WHERE steamid = %d ORDER BY level DESC LIMIT 1", TBL_PLAYERS, iAccountId);
	}
	
	SQL_TQuery(g_hDatabase, SQL_GetPlayerInfo, sQuery, GetClientUserId(client));
}

InsertPlayer(client)
{
	if(!GetConVarBool(g_hCVEnable) || !GetConVarBool(g_hCVSaveData))
		return;
	
	if(IsFakeClient(client) && !GetConVarBool(g_hCVBotSaveStats))
		return;
	
	decl String:sQuery[512];
	decl String:sName[MAX_NAME_LENGTH], String:sNameEscaped[MAX_NAME_LENGTH*2+1];
	GetClientName(client, sName, sizeof(sName));
	// Make sure to keep the original bot name.
	if(IsFakeClient(client))
	{
		sName = g_sOriginalBotName[client];
	}
	SQL_EscapeString(g_hDatabase, sName, sNameEscaped, sizeof(sNameEscaped));
	
	// Store the steamid of the player
	if(!IsFakeClient(client))
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO %s (name, steamid, level, experience, credits, showmenu, fadescreen, lastseen, lastreset) VALUES ('%s', %d, %d, %d, %d, %d, %d, %d, %d)",
			TBL_PLAYERS, sNameEscaped, GetSteamAccountID(client), GetClientLevel(client), GetClientExperience(client), GetClientCredits(client), ShowMenuOnLevelUp(client), FadeScreenOnLevelUp(client), GetTime(), GetTime());
	}
	// Bots are identified by their name!
	else
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO %s (name, steamid, level, experience, credits, showmenu, fadescreen, lastseen, lastreset) VALUES ('%s', NULL, %d, %d, %d, %d, %d, %d, %d)",
			TBL_PLAYERS, sNameEscaped, GetClientLevel(client), GetClientExperience(client), GetClientCredits(client), ShowMenuOnLevelUp(client), FadeScreenOnLevelUp(client), GetTime(), GetTime());
	}
	
	SQL_TQuery(g_hDatabase, SQL_InsertPlayer, sQuery, GetClientUserId(client));
}

SaveData(client, Transaction:hTransaction=Transaction:INVALID_HANDLE)
{
	if(g_hDatabase == INVALID_HANDLE)
		return;
	
	if(!GetConVarBool(g_hCVEnable) || !GetConVarBool(g_hCVSaveData))
		return;
	
	if(IsFakeClient(client) && !GetConVarBool(g_hCVBotSaveStats))
		return;
	
	// We're still in the process of loading this client's info from the db. Wait for it..
	if(!IsPlayerDataLoaded(client))
		return;
	
	if(g_iPlayerInfo[client][PLR_dbId] < 0)
	{
		InsertPlayer(client);
		return;
	}
	
	decl String:sName[MAX_NAME_LENGTH], String:sNameEscaped[MAX_NAME_LENGTH*2+1];
	GetClientName(client, sName, sizeof(sName));
	// Make sure to keep the original bot name.
	if(IsFakeClient(client))
	{
		sName = g_sOriginalBotName[client];
	}
	SQL_EscapeString(g_hDatabase, sName, sNameEscaped, sizeof(sNameEscaped));
	
	decl String:sQuery[8192];
	Format(sQuery, sizeof(sQuery), "UPDATE %s SET name = '%s', level = %d, experience = %d, credits = %d, showmenu = %d, fadescreen = %d, lastseen = %d, lastreset = %d WHERE player_id = %d", TBL_PLAYERS, sNameEscaped, GetClientLevel(client), GetClientExperience(client), GetClientCredits(client), ShowMenuOnLevelUp(client), FadeScreenOnLevelUp(client), GetTime(), g_iPlayerInfo[client][PLR_lastReset], g_iPlayerInfo[client][PLR_dbId]);
	// Add the query to the transaction instead of running it right away.
	if(hTransaction != INVALID_HANDLE)
		SQL_AddQuery(hTransaction, sQuery);
	else
		SQL_TQuery(g_hDatabase, SQL_DoNothing, sQuery);
	
	// Remember when we last saved his stats
	g_iPlayerInfo[client][PLR_lastSeen] = GetTime();
	
	// Save upgrade levels
	SavePlayerUpgradeLevels(client, hTransaction);
}

SavePlayerUpgradeLevels(client, Transaction:hTransaction=Transaction:INVALID_HANDLE)
{
	// Save upgrade levels
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo], playerupgrade[PlayerUpgradeInfo];
	new iAdded;
	decl String:sQuery[8192];
	Format(sQuery, sizeof(sQuery), "REPLACE INTO %s (player_id, upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds) VALUES ", TBL_PLAYERUPGRADES);
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(!IsValidUpgrade(upgrade))
			continue;
		
		if(iAdded > 0)
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		
		GetPlayerUpgradeInfoByIndex(client, i, playerupgrade);
		
		Format(sQuery, sizeof(sQuery), "%s(%d, %d, %d, %d, %d, %d, %d)", sQuery, g_iPlayerInfo[client][PLR_dbId], upgrade[UPGR_databaseId], GetClientPurchasedUpgradeLevel(client, i), GetClientSelectedUpgradeLevel(client, i), playerupgrade[PUI_enabled], playerupgrade[PUI_visuals], playerupgrade[PUI_sounds]);
		
		iAdded++;
	}
	if(iAdded > 0)
	{
		// Add the query to the transaction instead of running it right away.
		if(hTransaction != INVALID_HANDLE)
			SQL_AddQuery(hTransaction, sQuery);
		else
			SQL_TQuery(g_hDatabase, SQL_DoNothing, sQuery);
	}
}

SaveAllPlayers()
{
	if(g_hDatabase == INVALID_HANDLE)
		return;
	
	if(!GetConVarBool(g_hCVEnable) || !GetConVarBool(g_hCVSaveData))
		return;
	
	// Save all players at once instead of firing seperate queries for every player.
	// This is to optimize sqlite usage.
	new Transaction:hTransaction = SQL_CreateTransaction();
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i))
			SaveData(i, hTransaction);
	}
	
	SQL_ExecuteTransaction(g_hDatabase, hTransaction, _, SQLTxn_LogFailure);
}

ResetStats(client)
{
	DebugMsg("Stats have been reset for player: %N", client);
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo], playerupgrade[PlayerUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetPlayerUpgradeInfoByIndex(client, i, playerupgrade);
		// Reset upgrade to level 0
		playerupgrade[PUI_purchasedlevel] = 0;
		playerupgrade[PUI_selectedlevel] = 0;
		SavePlayerUpgradeInfo(client, i, playerupgrade);
		
		GetUpgradeByIndex(i, upgrade);
		
		if(!IsValidUpgrade(upgrade))
			continue;
		
		Call_StartFunction(upgrade[UPGR_plugin], Function:upgrade[UPGR_queryCallback]);
		Call_PushCell(client);
		Call_PushCell(UpgradeQueryType_Sell);
		Call_Finish();
	}
	
	g_iPlayerInfo[client][PLR_level] = 1;
	g_iPlayerInfo[client][PLR_experience] = 0;
	g_iPlayerInfo[client][PLR_credits] = GetConVarInt(g_hCVCreditsStart);
}

RemovePlayer(client, bool:bKeepBotName = false)
{
	ResetStats(client);
	ClearHandle(g_iPlayerInfo[client][PLR_upgrades]);
	g_iPlayerInfo[client][PLR_dbId] = -1;
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = false;
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = GetConVarBool(g_hCVShowMenuOnLevelDefault);
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = GetConVarBool(g_hCVFadeOnLevelDefault);
	g_iPlayerInfo[client][PLR_lastReset] = 0;
	g_iPlayerInfo[client][PLR_lastSeen] = 0;
	
	if(!bKeepBotName)
		g_sOriginalBotName[client][0] = '\0';
}

NotifyUpgradePluginsOfLevel(client)
{
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(!IsValidUpgrade(upgrade))
			continue;
		
		if(GetClientSelectedUpgradeLevel(client, i) <= 0)
			continue;
		
		Call_StartFunction(upgrade[UPGR_plugin], Function:upgrade[UPGR_queryCallback]);
		Call_PushCell(client);
		Call_PushCell(UpgradeQueryType_Buy);
		Call_Finish();
	}
}

IsPlayerDataLoaded(client)
{
	return g_iPlayerInfo[client][PLR_dataLoadedFromDB];
}

GetPlayerLastReset(client)
{
	return g_iPlayerInfo[client][PLR_lastReset];
}

SetPlayerLastReset(client, time)
{
	g_iPlayerInfo[client][PLR_lastReset] = time;
}

GetPlayerLastSeen(client)
{
	return g_iPlayerInfo[client][PLR_lastSeen];
}

GetPlayerUpgradeInfoByIndex(client, index, playerupgrade[PlayerUpgradeInfo])
{
	GetArrayArray(g_iPlayerInfo[client][PLR_upgrades], index, playerupgrade[0], _:PlayerUpgradeInfo);
}

SavePlayerUpgradeInfo(client, index, playerupgrade[PlayerUpgradeInfo])
{
	SetArrayArray(g_iPlayerInfo[client][PLR_upgrades], index, playerupgrade[0], _:PlayerUpgradeInfo);
}

/**
 * Player upgrade info getter
 */
stock GetClientRPGInfo(client, info[PlayerInfo])
{
	Array_Copy(g_iPlayerInfo[client][0], info[0], _:PlayerInfo);
}

stock Handle:GetClientUpgrades(client)
{
	return g_iPlayerInfo[client][PLR_upgrades];
}

GetClientDatabaseId(client)
{
	return g_iPlayerInfo[client][PLR_dbId];
}

GetClientByPlayerID(iPlayerId)
{
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && g_iPlayerInfo[i][PLR_dbId] == iPlayerId)
			return i;
	}
	return -1;
}

GetClientSelectedUpgradeLevel(client, iUpgradeIndex)
{
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	return playerupgrade[PUI_selectedlevel];
}

GetClientPurchasedUpgradeLevel(client, iUpgradeIndex)
{
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	return playerupgrade[PUI_purchasedlevel];
}

bool:IsClientUpgradeEnabled(client, iUpgradeIndex)
{
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	return playerupgrade[PUI_enabled];
}

InitPlayerNewUpgrade(client)
{
	new playerupgrade[PlayerUpgradeInfo];
	playerupgrade[PUI_purchasedlevel] = 0;
	playerupgrade[PUI_selectedlevel] = 0;
	playerupgrade[PUI_enabled] = true;
	playerupgrade[PUI_visuals] = true;
	playerupgrade[PUI_sounds] = true;
	PushArrayArray(GetClientUpgrades(client), playerupgrade[0], _:PlayerUpgradeInfo);
}

ShowMenuOnLevelUp(client)
{
	return g_iPlayerInfo[client][PLR_showMenuOnLevelup];
}

SetShowMenuOnLevelUp(client, bool:show)
{
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = show;
}

FadeScreenOnLevelUp(client)
{
	return g_iPlayerInfo[client][PLR_fadeOnLevelup];
}

SetFadeScreenOnLevelUp(client, bool:fade)
{
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = fade;
}

SetClientUpgradeEnabledStatus(client, iUpgradeIndex, bool:bEnabled)
{
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	
	// Change the enabled state.
	playerupgrade[PUI_enabled] = bEnabled;
	SavePlayerUpgradeInfo(client, iUpgradeIndex, playerupgrade);
	
	// Notify plugin about it.
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return;
	
	if(IsClientInGame(client))
	{
		new iLevel = GetClientSelectedUpgradeLevel(client, iUpgradeIndex);
		
		// Let the upgrade apply the state.
		Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_queryCallback]);
		Call_PushCell(client);
		Call_PushCell(bEnabled && iLevel > 0 ? UpgradeQueryType_Buy : UpgradeQueryType_Sell);
		Call_Finish();
	}
}

/**
 * Player upgrade buying/selling
 */

SetClientSelectedUpgradeLevel(client, iUpgradeIndex, iLevel)
{
	new iPurchased = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	// Can't select a level he doesn't own yet.
	if(iPurchased < iLevel)
		return;
	
	new iOldLevel = GetClientSelectedUpgradeLevel(client, iUpgradeIndex);
	
	if(iLevel == iOldLevel)
		return;
	
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	// Differ for selected and purchased level!
	playerupgrade[PUI_selectedlevel] = iLevel;
	SavePlayerUpgradeInfo(client, iUpgradeIndex, playerupgrade);
	
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return;
	
	if(IsClientInGame(client))
	{
		// Notify plugin about it.
		Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_queryCallback]);
		Call_PushCell(client);
		Call_PushCell(iOldLevel < iLevel ? UpgradeQueryType_Buy : UpgradeQueryType_Sell);
		Call_Finish();
	}
}

SetClientPurchasedUpgradeLevel(client, iUpgradeIndex, iLevel)
{
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	// Differ for selected and purchased level!
	playerupgrade[PUI_purchasedlevel] = iLevel;
	SavePlayerUpgradeInfo(client, iUpgradeIndex, playerupgrade);
	
	// Only update the selected level, if it's higher than the new limit
	new iSelectedLevel = GetClientSelectedUpgradeLevel(client, iUpgradeIndex);
	if(iSelectedLevel > iLevel)
		SetClientSelectedUpgradeLevel(client, iUpgradeIndex, iLevel);
}

bool:GiveClientUpgrade(client, iUpgradeIndex)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return false;
	
	new iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
	if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		return false;
	
	// Upgrade level +1!
	iCurrentLevel++;
	
	// See if some plugin doesn't want this player to level up this upgrade
	new Action:result;
	Call_StartForward(g_hfwdOnBuyUpgrade);
	Call_PushCell(client);
	Call_PushString(upgrade[UPGR_shortName]);
	Call_PushCell(iCurrentLevel);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	// Actually update the upgrade level.
	SetClientPurchasedUpgradeLevel(client, iUpgradeIndex, iCurrentLevel);
	// Also have it select the new higher upgrade level.
	SetClientSelectedUpgradeLevel(client, iUpgradeIndex, iCurrentLevel);
	
	Call_StartForward(g_hfwdOnBuyUpgradePost);
	Call_PushCell(client);
	Call_PushString(upgrade[UPGR_shortName]);
	Call_PushCell(iCurrentLevel);
	Call_Finish();
	
	return true;
}

bool:BuyClientUpgrade(client, iUpgradeIndex)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	new iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
	// can't get higher than this.
	if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		return false;
	
	new iCost = GetUpgradeCost(iUpgradeIndex, iCurrentLevel+1);
	
	// Not enough credits?
	if(iCost > g_iPlayerInfo[client][PLR_credits])
		return false;
	
	if(!GiveClientUpgrade(client, iUpgradeIndex))
		return false;
	
	DebugMsg("%N bought item %s Lvl %d", client, upgrade[UPGR_shortName], iCurrentLevel+1);
	
	g_iPlayerInfo[client][PLR_credits] -= iCost;
	
	return true;
}

bool:TakeClientUpgrade(client, iUpgradeIndex)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return false;
	
	new iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
	// Can't get negative levels
	if(iCurrentLevel <= 0)
		return false;
	
	// Upgrade level -1!
	iCurrentLevel--;
	
	// See if some plugin doesn't want this player to level down this upgrade
	new Action:result;
	Call_StartForward(g_hfwdOnSellUpgrade);
	Call_PushCell(client);
	Call_PushString(upgrade[UPGR_shortName]);
	Call_PushCell(iCurrentLevel);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	// Actually update the upgrade level.
	SetClientPurchasedUpgradeLevel(client, iUpgradeIndex, iCurrentLevel);
	
	Call_StartForward(g_hfwdOnSellUpgradePost);
	Call_PushCell(client);
	Call_PushString(upgrade[UPGR_shortName]);
	Call_PushCell(iCurrentLevel);
	Call_Finish();
	
	return true;
}

bool:SellClientUpgrade(client, iUpgradeIndex)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	new iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
	// can't get negative
	if(iCurrentLevel <= 0)
		return false;
	
	if(!TakeClientUpgrade(client, iUpgradeIndex))
		return false;
	
	DebugMsg("%N sold item %s Lvl %d", client, upgrade[UPGR_shortName], iCurrentLevel);
	
	g_iPlayerInfo[client][PLR_credits] += GetUpgradeSale(iUpgradeIndex, iCurrentLevel);
	
	return true;
}

// Have bots buy upgrades too :)
BotPickUpgrade(client)
{
	new bool:bUpgradeBought, iCurrentIndex;
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	
	new Handle:hRandomBuying = CreateArray();
	for(new i=0;i<iSize;i++)
		PushArrayCell(hRandomBuying, i);
	
	while(GetClientCredits(client) > 0)
	{
		// Shuffle the order of upgrades randomly. That way the bot won't upgrade one upgrade as much as he can before trying another one.
		Array_Shuffle(hRandomBuying);
		
		bUpgradeBought = false;
		for(new i=0;i<iSize;i++)
		{
			iCurrentIndex = GetArrayCell(hRandomBuying, i);
			GetUpgradeByIndex(iCurrentIndex, upgrade);
			
			// Valid upgrade the bot can use?
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				continue;
			
			// Don't buy it, if bots aren't allowed to use it at all..
			if(!upgrade[UPGR_allowBots])
				continue;
			
			// Don't let him buy upgrades, which are restricted to the other team.
			if(!IsClientInLockedTeam(client, upgrade))
				continue;
			
			if(BuyClientUpgrade(client, iCurrentIndex))
				bUpgradeBought = true;
		}
		if(!bUpgradeBought)
			break; /* Couldn't afford anything */
	}
	
	CloseHandle(hRandomBuying);
}

/**
 * Player info accessing functions (getter/setter)
 */
CheckItemMaxLevels(client)
{
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo], iMaxLevel, iCurrentLevel;
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		iMaxLevel = upgrade[UPGR_maxLevel];
		iCurrentLevel = GetClientPurchasedUpgradeLevel(client, i);
		while(iCurrentLevel > iMaxLevel)
		{
			/* Give player their credits back */
			SetClientCredits(client, GetClientCredits(client) + GetUpgradeCost(i, iCurrentLevel--));
		}
		if(GetClientPurchasedUpgradeLevel(client, i) != iCurrentLevel)
			SetClientPurchasedUpgradeLevel(client, i, iCurrentLevel);
	}
}

GetClientCredits(client)
{
	return g_iPlayerInfo[client][PLR_credits];
}

bool:SetClientCredits(client, iCredits)
{
	if(iCredits < 0)
		iCredits = 0;
	
	// See if some plugin doesn't want this player to get some credits
	new Action:result;
	Call_StartForward(g_hfwdOnClientCredits);
	Call_PushCell(client);
	Call_PushCell(g_iPlayerInfo[client][PLR_credits]);
	Call_PushCell(iCredits);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	new iOldCredits = g_iPlayerInfo[client][PLR_credits];
	g_iPlayerInfo[client][PLR_credits] = iCredits;
	
	Call_StartForward(g_hfwdOnClientCreditsPost);
	Call_PushCell(client);
	Call_PushCell(iOldCredits);
	Call_PushCell(iCredits);
	Call_Finish();
	
	return true;
}

GetClientLevel(client)
{
	return g_iPlayerInfo[client][PLR_level];
}

bool:SetClientLevel(client, iLevel)
{
	if(iLevel < 1)
		iLevel = 1;
	
	// See if some plugin doesn't want this player to get some credits
	new Action:result;
	Call_StartForward(g_hfwdOnClientLevel);
	Call_PushCell(client);
	Call_PushCell(g_iPlayerInfo[client][PLR_level]);
	Call_PushCell(iLevel);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	new iOldLevel = g_iPlayerInfo[client][PLR_level];
	g_iPlayerInfo[client][PLR_level] = iLevel;
	
	Call_StartForward(g_hfwdOnClientLevelPost);
	Call_PushCell(client);
	Call_PushCell(iOldLevel);
	Call_PushCell(iLevel);
	Call_Finish();
	
	return true;
}

GetClientExperience(client)
{
	return g_iPlayerInfo[client][PLR_experience];
}

bool:SetClientExperience(client, iExperience)
{
	if(iExperience < 0)
		iExperience = 0;
	
	// See if some plugin doesn't want this player to get some credits
	new Action:result;
	Call_StartForward(g_hfwdOnClientExperience);
	Call_PushCell(client);
	Call_PushCell(g_iPlayerInfo[client][PLR_experience]);
	Call_PushCell(iExperience);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	new iOldExperience = g_iPlayerInfo[client][PLR_experience];
	g_iPlayerInfo[client][PLR_experience] = iExperience;
	
	Call_StartForward(g_hfwdOnClientExperiencePost);
	Call_PushCell(client);
	Call_PushCell(iOldExperience);
	Call_PushCell(iExperience);
	Call_Finish();
	
	return true;
}

/**
 * SQL Callbacks
 */
public SQL_GetPlayerInfo(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		// TODO: Retry later?
		LogError("Unable to load player data (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	// First time this player connects?
	if(SQL_GetRowCount(hndl) == 0 || !SQL_FetchRow(hndl))
	{
		InsertPlayer(client);
		return;
	}
	
	g_iPlayerInfo[client][PLR_dbId] = SQL_FetchInt(hndl, 0);
	g_iPlayerInfo[client][PLR_level] = SQL_FetchInt(hndl, 1);
	g_iPlayerInfo[client][PLR_experience] = SQL_FetchInt(hndl, 2);
	g_iPlayerInfo[client][PLR_credits] = SQL_FetchInt(hndl, 3);
	g_iPlayerInfo[client][PLR_lastReset] = SQL_FetchInt(hndl, 4);
	g_iPlayerInfo[client][PLR_lastSeen] = SQL_FetchInt(hndl, 5);
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = SQL_FetchInt(hndl, 6) == 1;
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = SQL_FetchInt(hndl, 7) == 1;
	
	UpdateClientRank(client);
	UpdateRankCount();
	
	/* Player Upgrades */
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds FROM %s WHERE player_id = %d", TBL_PLAYERUPGRADES, g_iPlayerInfo[client][PLR_dbId]);
	SQL_TQuery(g_hDatabase, SQL_GetPlayerUpgrades, sQuery, userid);
}

public SQL_GetPlayerUpgrades(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	// player_id, upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to load item data (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	new upgrade[InternalUpgradeInfo], playerupgrade[PlayerUpgradeInfo], iSelectedLevel;
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		// If that upgrade isn't loaded yet, we'll fetch the right level when it's loaded.
		if(!GetUpgradeByDatabaseId(SQL_FetchInt(hndl, 0), upgrade))
			continue;
		
		// Load |enabled| bool first, then set the upgrade level.
		// Otherwise the upgrade is still disabled for the client, 
		// when calling the buy function in the upgrade plugin,
		// because the playerupgrade array is nulled by default..
		GetPlayerUpgradeInfoByIndex(client, upgrade[UPGR_index], playerupgrade);
		playerupgrade[PUI_enabled] = SQL_FetchInt(hndl, 3)==1;
		playerupgrade[PUI_visuals] = SQL_FetchInt(hndl, 4)==1;
		playerupgrade[PUI_sounds] = SQL_FetchInt(hndl, 5)==1;
		SavePlayerUpgradeInfo(client, upgrade[UPGR_index], playerupgrade);
		
		SetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index], SQL_FetchInt(hndl, 1));
		
		// Make sure the database is sane.. People WILL temper with it manually.
		iSelectedLevel = SQL_FetchInt(hndl, 2);
		if(iSelectedLevel > GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]))
			iSelectedLevel = GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]);
		SetClientSelectedUpgradeLevel(client, upgrade[UPGR_index], iSelectedLevel);
	}
	
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = true;
	
	CheckItemMaxLevels(client);
	
	CallOnClientLoaded(client);
}

public SQL_InsertPlayer(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to insert player info (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	g_iPlayerInfo[client][PLR_dbId] = SQL_GetInsertId(owner);
	
	UpdateClientRank(client);
	UpdateRankCount();
	
	// Insert upgrade level info
	SavePlayerUpgradeLevels(client);
	
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = true;
	CallOnClientLoaded(client);
}

/**
 * Natives
 */

// native SMRPG_GetClientUpgradeLevel(client, const String:shortname[]);
public Native_GetClientUpgradeLevel(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return 0;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return 0;
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return 0;
	}
	
	// Return 0, if the client has it disabled.
	if(!IsClientUpgradeEnabled(client, upgrade[UPGR_index]))
		return 0;
	
	return GetClientSelectedUpgradeLevel(client, upgrade[UPGR_index]);
}

// native SMRPG_GetClientPurchasedUpgradeLevel(client, const String:shortname[]);
public Native_GetClientPurchasedUpgradeLevel(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return 0;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return 0;
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return 0;
	}
	
	return GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]);
}

// native bool:SMRPG_SetClientSelectedUpgradeLevel(client, const String:shortname[], iLevel);
public Native_SetClientSelectedUpgradeLevel(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	// Check if such an upgrade is registered
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return false;
	}
	
	new iLevel = GetNativeCell(3);
	if(iLevel < 0)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid level %d.", iLevel);
		return false;
	}
	
	new iPurchased = GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]);
	// Can't select a level he doesn't own yet.
	if(iPurchased < iLevel)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Can't select level %d of upgrade \"%s\", which is higher than the purchased level %d.", iLevel, sShortName, iPurchased);
		return false;
	}
	
	SetClientSelectedUpgradeLevel(client, upgrade[UPGR_index], iLevel);
	
	return true;
}

// native bool:SMRPG_ClientBuyUpgrade(client, const String:shortname[]);
public Native_ClientBuyUpgrade(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	// Check if such an upgrade is registered
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return false;
	}
	
	return BuyClientUpgrade(client, upgrade[UPGR_index]);
}

// native bool:SMRPG_ClientSellUpgrade(client, const String:shortname[]);
public Native_ClientSellUpgrade(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return false;
	}
	
	return SellClientUpgrade(client, upgrade[UPGR_index]);
}

// native bool:SMRPG_IsUpgradeActiveOnClient(client const String:shortname[]);
public Native_IsUpgradeActiveOnClient(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return false;
	}
	
	// Ask the plugin owning that upgrade, if the effect is currently active on that player
	new bool:bResult;
	Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_activeCallback]);
	Call_PushCell(client);
	Call_Finish(bResult);
	
	return bResult;
}

// native SMRPG_GetClientLevel(client);
public Native_GetClientLevel(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return -1;
	}
	
	return GetClientLevel(client);
}

// native bool:SMRPG_SetClientLevel(client, level);
public Native_SetClientLevel(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new iLevel = GetNativeCell(2);
	
	return SetClientLevel(client, iLevel);
}

// native SMRPG_GetClientCredits(client);
public Native_GetClientCredits(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	return GetClientCredits(client);
}

// native bool:SMRPG_SetClientCredits(client, credits);
public Native_SetClientCredits(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new iCredits = GetNativeCell(2);
	
	return SetClientCredits(client, iCredits);
}

// native SMRPG_GetClientExperience(client);
public Native_GetClientExperience(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	return GetClientExperience(client);
}

// native bool:SMRPG_SetClientExperience(client, exp);
public Native_SetClientExperience(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new iExperience = GetNativeCell(2);
	
	return SetClientExperience(client, iExperience);
}

// native SMRPG_ResetClientStats(client);
public Native_ResetClientStats(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return;
	
	ResetStats(client);
	SetPlayerLastReset(client, GetTime());
}

// native SMRPG_GetClientLastResetTime(client);
public Native_GetClientLastResetTime(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return 0;
	}
	
	return GetPlayerLastReset(client);
}

// native SMRPG_GetClientLastSeenTime(client);
public Native_GetClientLastSeenTime(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return 0;
	}
	
	return GetPlayerLastSeen(client);
}

// native bool:SMRPG_ClientWantsCosmetics(client, const String:shortname[], SMRPG_FX:effect);
public Native_ClientWantsCosmetics(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return false;
	}
	
	new SMRPG_FX:iFX = SMRPG_FX:GetNativeCell(3);
	
	new playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, upgrade[UPGR_index], playerupgrade);
	
	// If the visuals on the upgrade are disabled globally, ignore the clients individual setting.
	switch(iFX)
	{
		case SMRPG_FX_Visuals:
		{
			return upgrade[UPGR_enableVisuals] && playerupgrade[PUI_visuals];
		}
		case SMRPG_FX_Sounds:
		{
			return upgrade[UPGR_enableSounds] && playerupgrade[PUI_sounds];
		}
	}
	
	return false;
}

/**
 * Helpers
 */
CallOnClientLoaded(client)
{
	// Only call that forward once per player
	if(!g_bFirstLoaded[client])
		return;
	
	g_bFirstLoaded[client] = false;
	
	Call_StartForward(g_hfwdOnClientLoaded);
	Call_PushCell(client);
	Call_Finish();
}

// Fisher and Yates shuffling
stock Array_Shuffle(Handle:array)
{
	new iSize = GetArraySize(array);
	for(new i=iSize-1;i>=1;i--)
	{
		SwapArrayItems(array, GetRandomInt(0, i), i);
	}
}