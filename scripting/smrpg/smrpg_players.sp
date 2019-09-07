#pragma semicolon 1
#include <sourcemod>
#include <smlib>

// Forwards
Handle g_hfwdOnBuyUpgrade;
Handle g_hfwdOnBuyUpgradePost;
Handle g_hfwdOnSellUpgrade;
Handle g_hfwdOnSellUpgradePost;
Handle g_hfwdOnClientLevel;
Handle g_hfwdOnClientLevelPost;
Handle g_hfwdOnClientExperience;
Handle g_hfwdOnClientExperiencePost;
Handle g_hfwdOnClientCredits;
Handle g_hfwdOnClientCreditsPost;

Handle g_hfwdOnClientLoaded;

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
	ArrayList:PLR_upgrades,
	PLR_lastReset,
	PLR_lastSeen
};

int g_iPlayerInfo[MAXPLAYERS+1][PlayerInfo];
bool g_bFirstLoaded[MAXPLAYERS+1];
// Bot stats are saved per name, because they don't have a steamid.
// Remember the name the bot joined with, so we use the same name everytime - even if some other plugin changes the name later.
char g_sOriginalBotName[MAXPLAYERS+1][MAX_NAME_LENGTH];

void RegisterPlayerNatives()
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

void RegisterPlayerForwards()
{
	// forward Action SMRPG_OnBuyUpgrade(int client, const char[] shortname, int newlevel);
	g_hfwdOnBuyUpgrade = CreateGlobalForward("SMRPG_OnBuyUpgrade", ET_Hook, Param_Cell, Param_String, Param_Cell);
	// forward void SMRPG_OnBuyUpgradePost(int client, const char[] shortname, int newlevel);
	g_hfwdOnBuyUpgradePost = CreateGlobalForward("SMRPG_OnBuyUpgradePost", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	// forward Action SMRPG_OnSellUpgrade(int client, const char[] shortname, int newlevel);
	g_hfwdOnSellUpgrade = CreateGlobalForward("SMRPG_OnSellUpgrade", ET_Hook, Param_Cell, Param_String, Param_Cell);
	// forward void SMRPG_OnSellUpgradePost(int client, const char[] shortname, int newlevel);
	g_hfwdOnSellUpgradePost = CreateGlobalForward("SMRPG_OnSellUpgradePost", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	
	// forward Action SMRPG_OnClientLevel(int client, int oldlevel, int newlevel);
	g_hfwdOnClientLevel = CreateGlobalForward("SMRPG_OnClientLevel", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward void SMRPG_OnClientLevelPost(int client, int oldlevel, int newlevel);
	g_hfwdOnClientLevelPost = CreateGlobalForward("SMRPG_OnClientLevelPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	// forward Action SMRPG_OnClientExperience(int client, int oldexp, int newexp);
	g_hfwdOnClientExperience = CreateGlobalForward("SMRPG_OnClientExperience", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward void SMRPG_OnClientExperiencePost(int client, int oldexp, int newexp);
	g_hfwdOnClientExperiencePost = CreateGlobalForward("SMRPG_OnClientExperiencePost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	// forward Action SMRPG_OnClientCredits(int client, int oldcredits, int newcredits);
	g_hfwdOnClientCredits = CreateGlobalForward("SMRPG_OnClientCredits", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward void SMRPG_OnClientCreditsPost(int client, int oldcredits, int newcredits);
	g_hfwdOnClientCreditsPost = CreateGlobalForward("SMRPG_OnClientCreditsPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	
	// forward void SMRPG_OnClientLoaded(int client);
	g_hfwdOnClientLoaded = CreateGlobalForward("SMRPG_OnClientLoaded", ET_Ignore, Param_Cell);
}

/**
 * Player stats management
 */
void InitPlayer(int client, bool bGetBotName = true)
{
	g_bFirstLoaded[client] = true;
	
	// See if the player should start at a higher level than 1?
	int iStartLevel, iStartCredits;
	GetStartLevelAndExperience(iStartLevel, iStartCredits);
	
	g_iPlayerInfo[client][PLR_level] = iStartLevel;
	g_iPlayerInfo[client][PLR_experience] = 0;
	g_iPlayerInfo[client][PLR_credits] = iStartCredits;
	g_iPlayerInfo[client][PLR_dbId] = -1;
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = false;
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = g_hCVShowMenuOnLevelDefault.BoolValue;
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = g_hCVFadeOnLevelDefault.BoolValue;
	g_iPlayerInfo[client][PLR_lastReset] = GetTime();
	g_iPlayerInfo[client][PLR_lastSeen] = GetTime();
	
	g_iPlayerInfo[client][PLR_upgrades] = new ArrayList(view_as<int>(PlayerUpgradeInfo));
	int iNumUpgrades = GetUpgradeCount();
	
	for(int i=0;i<iNumUpgrades;i++)
	{
		// start level (default 0) for all upgrades
		InitPlayerNewUpgrade(client);
	}
	
	// Save the name the bot joined with, so we fetch the right info, even if some plugin changes the name of the bot afterwards.
	if(bGetBotName && IsFakeClient(client))
	{
		GetClientName(client, g_sOriginalBotName[client], sizeof(g_sOriginalBotName[]));
	}
}

void AddPlayer(int client)
{
	if(!g_hDatabase)
		return;
	
	if(!g_hCVEnable.BoolValue)
		return;

	char sQuery[256];
	if(IsFakeClient(client))
	{
		if(!g_hCVBotSaveStats.BoolValue)
			return;

		// Don't save stats for SourceTV.
		if(IsClientSourceTV(client) || IsClientReplay(client))
			return;
		
		// Lookup bot levels depending on their names.
		char sNameEscaped[MAX_NAME_LENGTH*2+1];
		g_hDatabase.Escape(g_sOriginalBotName[client], sNameEscaped, sizeof(sNameEscaped));
		Format(sQuery, sizeof(sQuery), "SELECT player_id, level, experience, credits, lastreset, lastseen, showmenu, fadescreen FROM %s WHERE steamid IS NULL AND name = '%s' ORDER BY level DESC LIMIT 1", TBL_PLAYERS, sNameEscaped);
	}
	else
	{
		int iAccountId = GetSteamAccountID(client);
		if(!iAccountId)
			return;
		
		Format(sQuery, sizeof(sQuery), "SELECT player_id, level, experience, credits, lastreset, lastseen, showmenu, fadescreen FROM %s WHERE steamid = %d ORDER BY level DESC LIMIT 1", TBL_PLAYERS, iAccountId);
	}
	
	g_hDatabase.Query(SQL_GetPlayerInfo, sQuery, GetClientUserId(client));
}

void InsertPlayer(int client)
{
	if(!g_hCVEnable.BoolValue || !g_hCVSaveData.BoolValue)
		return;
	
	if(IsFakeClient(client) && !g_hCVBotSaveStats.BoolValue)
		return;
	
	char sQuery[512];
	char sName[MAX_NAME_LENGTH], sNameEscaped[MAX_NAME_LENGTH*2+1];
	GetClientName(client, sName, sizeof(sName));
	// Make sure to keep the original bot name.
	if(IsFakeClient(client))
	{
		sName = g_sOriginalBotName[client];
	}
	g_hDatabase.Escape(sName, sNameEscaped, sizeof(sNameEscaped));
	
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
	
	g_hDatabase.Query(SQL_InsertPlayer, sQuery, GetClientUserId(client));
}

bool SaveData(int client, Transaction hTransaction=null)
{
	if(g_hDatabase == null)
		return false;
	
	if(!g_hCVEnable.BoolValue || !g_hCVSaveData.BoolValue)
		return false;
	
	if(IsFakeClient(client) && !g_hCVBotSaveStats.BoolValue)
		return false;

	if(IsClientSourceTV(client) || IsClientReplay(client))
		return false;
	
	// We're still in the process of loading this client's info from the db. Wait for it..
	if(!IsPlayerDataLoaded(client))
		return false;
	
	if(g_iPlayerInfo[client][PLR_dbId] < 0)
	{
		InsertPlayer(client);
		return false;
	}
	
	char sName[MAX_NAME_LENGTH], sNameEscaped[MAX_NAME_LENGTH*2+1];
	GetClientName(client, sName, sizeof(sName));
	// Make sure to keep the original bot name.
	if(IsFakeClient(client))
	{
		sName = g_sOriginalBotName[client];
	}
	g_hDatabase.Escape(sName, sNameEscaped, sizeof(sNameEscaped));
	
	char sQuery[8192];
	Format(sQuery, sizeof(sQuery), "UPDATE %s SET name = '%s', level = %d, experience = %d, credits = %d, showmenu = %d, fadescreen = %d, lastseen = %d, lastreset = %d WHERE player_id = %d", TBL_PLAYERS, sNameEscaped, GetClientLevel(client), GetClientExperience(client), GetClientCredits(client), ShowMenuOnLevelUp(client), FadeScreenOnLevelUp(client), GetTime(), g_iPlayerInfo[client][PLR_lastReset], g_iPlayerInfo[client][PLR_dbId]);
	// Add the query to the transaction instead of running it right away.
	if(hTransaction != null)
		hTransaction.AddQuery(sQuery);
	else
		g_hDatabase.Query(SQL_DoNothing, sQuery);
	
	// Remember when we last saved his stats
	g_iPlayerInfo[client][PLR_lastSeen] = GetTime();
	
	// Save upgrade levels
	SavePlayerUpgradeLevels(client, hTransaction);
	
	return true;
}

void SavePlayerUpgradeLevels(int client, Transaction hTransaction=null)
{
	// Save upgrade levels
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo], playerupgrade[PlayerUpgradeInfo];
	int iAdded;
	char sQuery[8192];
	Format(sQuery, sizeof(sQuery), "REPLACE INTO %s (player_id, upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds) VALUES ", TBL_PLAYERUPGRADES);
	for(int i=0;i<iSize;i++)
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
		if(hTransaction != null)
			hTransaction.AddQuery(sQuery);
		else
			g_hDatabase.Query(SQL_DoNothing, sQuery);
	}
}

void SaveAllPlayers()
{
	if(g_hDatabase == null)
		return;
	
	if(!g_hCVEnable.BoolValue || !g_hCVSaveData.BoolValue)
		return;
	
	// Save all players at once instead of firing seperate queries for every player.
	// This is to optimize sqlite usage.
	Transaction hTransaction = new Transaction();
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i))
			SaveData(i, hTransaction);
	}
	
	g_hDatabase.Execute(hTransaction, _, SQLTxn_LogFailure);
}

void ResetStats(int client)
{
	DebugMsg("Stats have been reset for player: %N", client);
	
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo], playerupgrade[PlayerUpgradeInfo];
	bool bWasEnabled;
	for(int i=0;i<iSize;i++)
	{
		GetPlayerUpgradeInfoByIndex(client, i, playerupgrade);
		// See if this upgrade has been enabled and should be notified to stop the effect.
		bWasEnabled = playerupgrade[PUI_enabled] && playerupgrade[PUI_selectedlevel] > 0;
		
		// Reset upgrade to level 0
		playerupgrade[PUI_purchasedlevel] = 0;
		playerupgrade[PUI_selectedlevel] = 0;
		SavePlayerUpgradeInfo(client, i, playerupgrade);
		
		// No need to inform the upgrade plugin, that this player was reset,
		// if it wasn't active before at all.
		if (!bWasEnabled)
			continue;
		
		GetUpgradeByIndex(i, upgrade);
		
		if(!IsValidUpgrade(upgrade))
			continue;
		
		// Plugin doesn't care? OK :(
		if(upgrade[UPGR_queryCallback] == INVALID_FUNCTION)
			continue;
		
		Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_queryCallback]);
		Call_PushCell(client);
		Call_PushCell(UpgradeQueryType_Sell);
		Call_Finish();
	}
	
	g_iPlayerInfo[client][PLR_level] = 1;
	g_iPlayerInfo[client][PLR_experience] = 0;
	g_iPlayerInfo[client][PLR_credits] = g_hCVCreditsStart.IntValue;
}

void RemovePlayer(int client, bool bKeepBotName = false)
{
	ResetStats(client);
	ClearHandle(g_iPlayerInfo[client][PLR_upgrades]);
	g_iPlayerInfo[client][PLR_dbId] = -1;
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = false;
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = g_hCVShowMenuOnLevelDefault.BoolValue;
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = g_hCVFadeOnLevelDefault.BoolValue;
	g_iPlayerInfo[client][PLR_lastReset] = 0;
	g_iPlayerInfo[client][PLR_lastSeen] = 0;
	
	if(!bKeepBotName)
		g_sOriginalBotName[client][0] = '\0';
}

void NotifyUpgradePluginsOfLevel(int client)
{
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo];
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(!IsValidUpgrade(upgrade))
			continue;
		
		if(GetClientSelectedUpgradeLevel(client, i) <= 0)
			continue;
		
		// Plugin doesn't care? OK :(
		if(upgrade[UPGR_queryCallback] == INVALID_FUNCTION)
			continue;
		
		Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_queryCallback]);
		Call_PushCell(client);
		Call_PushCell(UpgradeQueryType_Buy);
		Call_Finish();
	}
}

bool IsPlayerDataLoaded(int client)
{
	return g_iPlayerInfo[client][PLR_dataLoadedFromDB];
}

int GetPlayerLastReset(int client)
{
	return g_iPlayerInfo[client][PLR_lastReset];
}

void SetPlayerLastReset(int client, int time)
{
	g_iPlayerInfo[client][PLR_lastReset] = time;
}

int GetPlayerLastSeen(int client)
{
	return g_iPlayerInfo[client][PLR_lastSeen];
}

void GetPlayerUpgradeInfoByIndex(int client, int index, int playerupgrade[PlayerUpgradeInfo])
{
	g_iPlayerInfo[client][PLR_upgrades].GetArray(index, playerupgrade[0], view_as<int>(PlayerUpgradeInfo));
}

void SavePlayerUpgradeInfo(int client, int index, int playerupgrade[PlayerUpgradeInfo])
{
	g_iPlayerInfo[client][PLR_upgrades].SetArray(index, playerupgrade[0], view_as<int>(PlayerUpgradeInfo));
}

// See if this player is a bot and we shouldn't process any info for him.
bool IgnoreBotPlayer(int client)
{
	// Just checking for bots.
	if(!IsFakeClient(client))
		return false;
	
	// Bot features disabled as a whole.
	if(!g_hCVBotEnable.BoolValue)
		return true;

	// Ignore SourceTV.
	if(IsClientSourceTV(client) || IsClientReplay(client))
		return true;
	
	// No human players on the server.
	if(g_hCVBotNeedHuman.BoolValue && Client_GetCount(true, false) == 0)
		return true;
	
	return false;
}

/**
 * Player upgrade info getter
 */
stock void GetClientRPGInfo(int client, int info[PlayerInfo])
{
	Array_Copy(g_iPlayerInfo[client][0], info[0], view_as<int>(PlayerInfo));
}

stock ArrayList GetClientUpgrades(int client)
{
	return g_iPlayerInfo[client][PLR_upgrades];
}

int GetClientDatabaseId(int client)
{
	return g_iPlayerInfo[client][PLR_dbId];
}

int GetClientByPlayerID(int iPlayerId)
{
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && g_iPlayerInfo[i][PLR_dbId] == iPlayerId)
			return i;
	}
	return -1;
}

int GetClientSelectedUpgradeLevel(int client, int iUpgradeIndex)
{
	int playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	return playerupgrade[PUI_selectedlevel];
}

int GetClientPurchasedUpgradeLevel(int client, int iUpgradeIndex)
{
	int playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	return playerupgrade[PUI_purchasedlevel];
}

bool IsClientUpgradeEnabled(int client, int iUpgradeIndex)
{
	int playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	return playerupgrade[PUI_enabled];
}

void InitPlayerNewUpgrade(int client)
{
	// Let the player start this upgrade on its set start level by default.
	ArrayList clienUpgrades = GetClientUpgrades(client);
	int iIndex = clienUpgrades.Length;
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iIndex, upgrade);
	
	int playerupgrade[PlayerUpgradeInfo];
	playerupgrade[PUI_purchasedlevel] = 0;
	playerupgrade[PUI_selectedlevel] = 0;
	playerupgrade[PUI_enabled] = true;
	playerupgrade[PUI_visuals] = true;
	playerupgrade[PUI_sounds] = true;
	clienUpgrades.PushArray(playerupgrade[0], view_as<int>(PlayerUpgradeInfo));
	
	// Get the money for the start level?
	// TODO: Make sure to document the OnBuyUpgrade forward being called on clients not ingame yet + test.
	// (This is can be called OnClientConnected.)
	bool bFree = g_hCVUpgradeStartLevelsFree.BoolValue;
	for(int i=0; i<upgrade[UPGR_startLevel]; i++)
	{
		if (bFree)
		{
			if (!GiveClientUpgrade(client, iIndex))
				break;
		}
		else
		{
			if (!BuyClientUpgrade(client, iIndex))
				break; // TODO: Log if there are not enough credits for the start level?
		}
	}
}

bool ShowMenuOnLevelUp(int client)
{
	return g_iPlayerInfo[client][PLR_showMenuOnLevelup];
}

void SetShowMenuOnLevelUp(int client, bool show)
{
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = show;
}

bool FadeScreenOnLevelUp(int client)
{
	return g_iPlayerInfo[client][PLR_fadeOnLevelup];
}

void SetFadeScreenOnLevelUp(int client, bool fade)
{
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = fade;
}

void SetClientUpgradeEnabledStatus(int client, int iUpgradeIndex, bool bEnabled)
{
	int playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	
	// Change the enabled state.
	playerupgrade[PUI_enabled] = bEnabled;
	SavePlayerUpgradeInfo(client, iUpgradeIndex, playerupgrade);
	
	// Notify plugin about it.
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return;
	
	// Plugin doesn't care? OK :(
	if(upgrade[UPGR_queryCallback] == INVALID_FUNCTION)
		return;
	
	if(IsClientInGame(client))
	{
		int iLevel = GetClientSelectedUpgradeLevel(client, iUpgradeIndex);
		if (iLevel <= 0)
			return;
		
		// Let the upgrade apply the state.
		Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_queryCallback]);
		Call_PushCell(client);
		Call_PushCell(bEnabled ? UpgradeQueryType_Buy : UpgradeQueryType_Sell);
		Call_Finish();
	}
}

/**
 * Player upgrade buying/selling
 */

void SetClientSelectedUpgradeLevel(int client, int iUpgradeIndex, int iLevel)
{
	int iPurchased = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	// Can't select a level he doesn't own yet.
	if(iPurchased < iLevel)
		return;
	
	int iOldLevel = GetClientSelectedUpgradeLevel(client, iUpgradeIndex);
	
	if(iLevel == iOldLevel)
		return;
	
	int playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	// Differ for selected and purchased level!
	playerupgrade[PUI_selectedlevel] = iLevel;
	SavePlayerUpgradeInfo(client, iUpgradeIndex, playerupgrade);
	
	// Don't call the callback, if the player disabled the upgrade.
	if (!playerupgrade[PUI_enabled])
		return;
	
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return;
	
	// Plugin doesn't care? OK :(
	if(upgrade[UPGR_queryCallback] == INVALID_FUNCTION)
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

void SetClientPurchasedUpgradeLevel(int client, int iUpgradeIndex, int iLevel)
{
	int playerupgrade[PlayerUpgradeInfo];
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	// Differ for selected and purchased level!
	playerupgrade[PUI_purchasedlevel] = iLevel;
	SavePlayerUpgradeInfo(client, iUpgradeIndex, playerupgrade);
	
	// Only update the selected level, if it's higher than the new limit
	int iSelectedLevel = GetClientSelectedUpgradeLevel(client, iUpgradeIndex);
	if(iSelectedLevel > iLevel)
		SetClientSelectedUpgradeLevel(client, iUpgradeIndex, iLevel);
}

bool GiveClientUpgrade(int client, int iUpgradeIndex)
{
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return false;
	
	int iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
	if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		return false;
	
	// Upgrade level +1!
	iCurrentLevel++;
	
	// See if some plugin doesn't want this player to level up this upgrade
	Action result;
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

bool BuyClientUpgrade(int client, int iUpgradeIndex)
{
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	int iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
	// can't get higher than this.
	if(iCurrentLevel >= upgrade[UPGR_maxLevel])
		return false;
	
	int iCost = GetUpgradeCost(iUpgradeIndex, iCurrentLevel+1);
	
	// Not enough credits?
	if(iCost > g_iPlayerInfo[client][PLR_credits])
		return false;
	
	if(!GiveClientUpgrade(client, iUpgradeIndex))
		return false;
	
	DebugMsg("%N bought item %s Lvl %d", client, upgrade[UPGR_shortName], iCurrentLevel+1);
	
	g_iPlayerInfo[client][PLR_credits] -= iCost;
	
	return true;
}

bool TakeClientUpgrade(int client, int iUpgradeIndex)
{
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return false;
	
	int iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
	// Can't get negative levels
	if(iCurrentLevel <= 0)
		return false;
	
	// Upgrade level -1!
	iCurrentLevel--;
	
	// See if some plugin doesn't want this player to level down this upgrade
	Action result;
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

bool SellClientUpgrade(int client, int iUpgradeIndex)
{
	int upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	int iCurrentLevel = GetClientPurchasedUpgradeLevel(client, iUpgradeIndex);
	
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
void BotPickUpgrade(int client)
{
	bool bUpgradeBought;
	int iCurrentIndex;
	
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo];
	
	ArrayList hRandomBuying = new ArrayList();
	for(int i=0;i<iSize;i++)
		hRandomBuying.Push(i);
	
	while(GetClientCredits(client) > 0)
	{
		// Shuffle the order of upgrades randomly. That way the bot won't upgrade one upgrade as much as he can before trying another one.
		Array_Shuffle(hRandomBuying);
		
		bUpgradeBought = false;
		for(int i=0;i<iSize;i++)
		{
			iCurrentIndex = hRandomBuying.Get(i);
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
	
	delete hRandomBuying;
}

/**
 * Player info accessing functions (getter/setter)
 */
void CheckItemMaxLevels(int client)
{
	int iSize = GetUpgradeCount();
	int upgrade[InternalUpgradeInfo], iMaxLevel, iCurrentLevel;
	for(int i=0;i<iSize;i++)
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

int GetClientCredits(int client)
{
	return g_iPlayerInfo[client][PLR_credits];
}

bool SetClientCredits(int client, int iCredits)
{
	if(iCredits < 0)
		iCredits = 0;
	
	// See if some plugin doesn't want this player to get some credits
	Action result;
	Call_StartForward(g_hfwdOnClientCredits);
	Call_PushCell(client);
	Call_PushCell(g_iPlayerInfo[client][PLR_credits]);
	Call_PushCell(iCredits);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	int iOldCredits = g_iPlayerInfo[client][PLR_credits];
	g_iPlayerInfo[client][PLR_credits] = iCredits;
	
	Call_StartForward(g_hfwdOnClientCreditsPost);
	Call_PushCell(client);
	Call_PushCell(iOldCredits);
	Call_PushCell(iCredits);
	Call_Finish();
	
	return true;
}

int GetClientLevel(int client)
{
	return g_iPlayerInfo[client][PLR_level];
}

bool SetClientLevel(int client, int iLevel)
{
	if(iLevel < 1)
		iLevel = 1;
	
	// See if some plugin doesn't want this player to get some credits
	Action result;
	Call_StartForward(g_hfwdOnClientLevel);
	Call_PushCell(client);
	Call_PushCell(g_iPlayerInfo[client][PLR_level]);
	Call_PushCell(iLevel);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	int iOldLevel = g_iPlayerInfo[client][PLR_level];
	g_iPlayerInfo[client][PLR_level] = iLevel;
	
	Call_StartForward(g_hfwdOnClientLevelPost);
	Call_PushCell(client);
	Call_PushCell(iOldLevel);
	Call_PushCell(iLevel);
	Call_Finish();
	
	return true;
}

int GetClientExperience(int client)
{
	return g_iPlayerInfo[client][PLR_experience];
}

bool SetClientExperience(int client, int iExperience)
{
	if(iExperience < 0)
		iExperience = 0;
	
	// See if some plugin doesn't want this player to get some credits
	Action result;
	Call_StartForward(g_hfwdOnClientExperience);
	Call_PushCell(client);
	Call_PushCell(g_iPlayerInfo[client][PLR_experience]);
	Call_PushCell(iExperience);
	Call_Finish(result);
	
	// Some plugin doesn't want this to happen :(
	if(result > Plugin_Continue)
		return false;
	
	int iOldExperience = g_iPlayerInfo[client][PLR_experience];
	g_iPlayerInfo[client][PLR_experience] = iExperience;
	
	Call_StartForward(g_hfwdOnClientExperiencePost);
	Call_PushCell(client);
	Call_PushCell(iOldExperience);
	Call_PushCell(iExperience);
	Call_Finish();
	
	return true;
}

void GetStartLevelAndExperience(int &iStartLevel, int &iStartCredits)
{
	// See if the player should start at a higher level than 1?
	iStartLevel = g_hCVLevelStart.IntValue;
	if (iStartLevel < 1)
		iStartLevel = 1;
	
	// If the start level is at a higher level than 1, he might get more credits for his level.
	iStartCredits = g_hCVCreditsStart.IntValue;
	if (g_hCVLevelStartGiveCredits.BoolValue)
		iStartCredits += g_hCVCreditsInc.IntValue * (iStartLevel - 1);
}

/**
 * SQL Callbacks
 */
public void SQL_GetPlayerInfo(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(results == null)
	{
		// TODO: Retry later?
		LogError("Unable to load player data (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	// First time this player connects?
	if(results.RowCount == 0 || !results.FetchRow())
	{
		InsertPlayer(client);
		return;
	}
	
	g_iPlayerInfo[client][PLR_dbId] = results.FetchInt(0);
	g_iPlayerInfo[client][PLR_level] = results.FetchInt(1);
	g_iPlayerInfo[client][PLR_experience] = results.FetchInt(2);
	g_iPlayerInfo[client][PLR_credits] = results.FetchInt(3);
	g_iPlayerInfo[client][PLR_lastReset] = results.FetchInt(4);
	g_iPlayerInfo[client][PLR_lastSeen] = results.FetchInt(5);
	g_iPlayerInfo[client][PLR_showMenuOnLevelup] = results.FetchInt(6) != 0;
	g_iPlayerInfo[client][PLR_fadeOnLevelup] = results.FetchInt(7) != 0;
	
	UpdateClientRank(client);
	UpdateRankCount();
	
	/* Player Upgrades */
	char sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds FROM %s WHERE player_id = %d", TBL_PLAYERUPGRADES, g_iPlayerInfo[client][PLR_dbId]);
	g_hDatabase.Query(SQL_GetPlayerUpgrades, sQuery, userid);
}

public void SQL_GetPlayerUpgrades(Database db, DBResultSet results, const char[] error, any userid)
{
	// player_id, upgrade_id, purchasedlevel, selectedlevel, enabled, visuals, sounds
	int client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(results == null)
	{
		LogError("Unable to load item data (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	// We're as good as loaded..
	// Set this now, so calls to e.g. SMRPG_GetClientUpgradeLevel in one of the upgrade's BuySell callbacks
	// get the upgrade's level correctly instead of returning 0.
	// This could be inconsistent when the just-loaded upgrade tries to get the level of another upgrade
	// which isn't loaded yet for this player. We can't just do NotifyUpgradePluginsOfLevel, because this
	// callback is reused, when an upgrade is reloaded/lateloaded to fetch the levels of already connected players (see SQL_GetUpgradeInfo)
	// and we don't want to trigger the BuySell callback twice if the level didn't change for all the other upgrades.
	// TODO: Collect upgrade ids of loaded upgrades and inform them after all levels are loaded in a second loop.
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = true;
	
	int upgrade[InternalUpgradeInfo], playerupgrade[PlayerUpgradeInfo], iSelectedLevel;
	while(results.MoreRows)
	{
		if(!results.FetchRow())
			continue;
		
		// If that upgrade isn't loaded yet, we'll fetch the right level when it's loaded.
		if(!GetUpgradeByDatabaseId(results.FetchInt(0), upgrade))
			continue;
		
		// Load |enabled| bool first, then set the upgrade level.
		// Otherwise the upgrade plugin might be informed,
		// even if the player has the upgrade disabled.
		GetPlayerUpgradeInfoByIndex(client, upgrade[UPGR_index], playerupgrade);
		playerupgrade[PUI_enabled] = results.FetchInt(3)!=0;
		playerupgrade[PUI_visuals] = results.FetchInt(4)!=0;
		playerupgrade[PUI_sounds] = results.FetchInt(5)!=0;
		SavePlayerUpgradeInfo(client, upgrade[UPGR_index], playerupgrade);
		
		SetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index], results.FetchInt(1));
		
		// Make sure the database is sane.. People WILL temper with it manually.
		iSelectedLevel = results.FetchInt(2);
		if(iSelectedLevel > GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]))
			iSelectedLevel = GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]);
		SetClientSelectedUpgradeLevel(client, upgrade[UPGR_index], iSelectedLevel);
	}
	
	CheckItemMaxLevels(client);
	
	CallOnClientLoaded(client);
}

public void SQL_InsertPlayer(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(results == null)
	{
		LogError("Unable to insert player info (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	g_iPlayerInfo[client][PLR_dbId] = results.InsertId;
	
	UpdateClientRank(client);
	UpdateRankCount();
	
	// Insert upgrade level info
	SavePlayerUpgradeLevels(client);
	
	g_iPlayerInfo[client][PLR_dataLoadedFromDB] = true;
	
	// Notify the upgrade plugins of the possible start level of the new player.
	if (IsClientInGame(client))
		NotifyUpgradePluginsOfLevel(client);
	CallOnClientLoaded(client);
}

/**
 * Natives
 */

// native int SMRPG_GetClientUpgradeLevel(int client, const char[] shortname);
public int Native_GetClientUpgradeLevel(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return 0;
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	int upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	// Return 0, if the client has it disabled.
	if(!IsClientUpgradeEnabled(client, upgrade[UPGR_index]))
		return 0;
	
	return GetClientSelectedUpgradeLevel(client, upgrade[UPGR_index]);
}

// native int SMRPG_GetClientPurchasedUpgradeLevel(int client, const char[] shortname);
public int Native_GetClientPurchasedUpgradeLevel(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return 0;
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	int upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	return GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]);
}

// native bool SMRPG_SetClientSelectedUpgradeLevel(int client, const char[] shortname, int iLevel);
public int Native_SetClientSelectedUpgradeLevel(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	// Check if such an upgrade is registered
	int upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	int iLevel = GetNativeCell(3);
	if(iLevel < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid level %d.", iLevel);
	
	int iPurchased = GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index]);
	// Can't select a level he doesn't own yet.
	if(iPurchased < iLevel)
		return ThrowNativeError(SP_ERROR_NATIVE, "Can't select level %d of upgrade \"%s\", which is higher than the purchased level %d.", iLevel, sShortName, iPurchased);
	
	SetClientSelectedUpgradeLevel(client, upgrade[UPGR_index], iLevel);
	
	return 1;
}

// native bool SMRPG_ClientBuyUpgrade(int client, const char[] shortname);
public int Native_ClientBuyUpgrade(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	// Check if such an upgrade is registered
	int upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	return BuyClientUpgrade(client, upgrade[UPGR_index]);
}

// native bool SMRPG_ClientSellUpgrade(int client, const char[] shortname);
public int Native_ClientSellUpgrade(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	int upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	return SellClientUpgrade(client, upgrade[UPGR_index]);
}

// native bool SMRPG_IsUpgradeActiveOnClient(int client const char[] shortname);
public int Native_IsUpgradeActiveOnClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	int upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	// Ask the plugin owning that upgrade, if the effect is currently active on that player
	return IsUpgradeEffectActive(client, upgrade);
}

// native int SMRPG_GetClientLevel(int client);
public int Native_GetClientLevel(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetClientLevel(client);
}

// native bool SMRPG_SetClientLevel(int client, int level);
public int Native_SetClientLevel(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int iLevel = GetNativeCell(2);
	
	return SetClientLevel(client, iLevel);
}

// native int SMRPG_GetClientCredits(int client);
public int Native_GetClientCredits(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetClientCredits(client);
}

// native bool SMRPG_SetClientCredits(int client, int credits);
public int Native_SetClientCredits(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int iCredits = GetNativeCell(2);
	
	return SetClientCredits(client, iCredits);
}

// native int SMRPG_GetClientExperience(int client);
public int Native_GetClientExperience(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetClientExperience(client);
}

// native bool SMRPG_SetClientExperience(int client, int exp);
public int Native_SetClientExperience(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int iExperience = GetNativeCell(2);
	
	return SetClientExperience(client, iExperience);
}

// native void SMRPG_ResetClientStats(int client);
public int Native_ResetClientStats(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return 0;
	
	ResetStats(client);
	SetPlayerLastReset(client, GetTime());
	return 0;
}

// native int SMRPG_GetClientLastResetTime(int client);
public int Native_GetClientLastResetTime(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetPlayerLastReset(client);
}

// native int SMRPG_GetClientLastSeenTime(int client);
public int Native_GetClientLastSeenTime(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetPlayerLastSeen(client);
}

// native bool SMRPG_ClientWantsCosmetics(int client, const char[] shortname, SMRPG_FX effect);
public int Native_ClientWantsCosmetics(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	// Don't try to lookup anything, if we haven't loaded the client completely yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	int upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	SMRPG_FX iFX = view_as<SMRPG_FX>(GetNativeCell(3));
	
	int playerupgrade[PlayerUpgradeInfo];
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
void CallOnClientLoaded(int client)
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
stock void Array_Shuffle(ArrayList array)
{
	int iSize = array.Length;
	for(int i=iSize-1;i>=1;i--)
	{
		array.SwapAt(GetRandomInt(0, i), i);
	}
}