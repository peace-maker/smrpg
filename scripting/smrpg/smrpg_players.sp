#pragma semicolon 1
#include <sourcemod>
#include <smlib>

// Forwards
new Handle:g_hfwdOnBuyUpgrade;
new Handle:g_hfwdOnSellUpgrade;
new Handle:g_hfwdOnClientLevel;
new Handle:g_hfwdOnClientExperience;
new Handle:g_hfwdOnClientCredits;

new Handle:g_hfwdOnClientLoaded;

enum PlayerInfo
{
	PLR_level,
	PLR_experience,
	PLR_credits,
	PLR_dbId,
	PLR_dbUpgradeId,
	bool:PLR_triedToLoadData,
	Handle:PLR_upgradesLevel
}

new g_iPlayerInfo[MAXPLAYERS+1][PlayerInfo];
new bool:g_bFirstLoaded[MAXPLAYERS+1];

RegisterPlayerNatives()
{
	CreateNative("SMRPG_GetClientUpgradeLevel", Native_GetClientUpgradeLevel);
	CreateNative("SMRPG_ClientBuyUpgrade", Native_ClientBuyUpgrade);
	CreateNative("SMRPG_ClientSellUpgrade", Native_ClientSellUpgrade);
	CreateNative("SMRPG_IsUpgradeActiveOnClient", Native_IsUpgradeActiveOnClient);
	
	CreateNative("SMRPG_GetClientLevel", Native_GetClientLevel);
	CreateNative("SMRPG_SetClientLevel", Native_SetClientLevel);
	CreateNative("SMRPG_GetClientCredits", Native_GetClientCredits);
	CreateNative("SMRPG_SetClientCredits", Native_SetClientCredits);
	CreateNative("SMRPG_GetClientExperience", Native_GetClientExperience);
	CreateNative("SMRPG_SetClientExperience", Native_SetClientExperience);
	
	// forward Action:SMRPG_OnBuyUpgrade(client, const String:shortname[], newlevel);
	g_hfwdOnBuyUpgrade = CreateGlobalForward("SMRPG_OnBuyUpgrade", ET_Hook, Param_Cell, Param_String, Param_Cell);
	// forward Action:SMRPG_OnSellUpgrade(client, const String:shortname[], newlevel);
	g_hfwdOnSellUpgrade = CreateGlobalForward("SMRPG_OnSellUpgrade", ET_Hook, Param_Cell, Param_String, Param_Cell);
	
	// forward Action:SMRPG_OnClientLevel(client, oldlevel, newlevel);
	g_hfwdOnClientLevel = CreateGlobalForward("SMRPG_OnClientLevel", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward Action:SMRPG_OnClientExperience(client, oldexp, newexp);
	g_hfwdOnClientExperience = CreateGlobalForward("SMRPG_OnClientExperience", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	// forward Action:SMRPG_OnClientCredits(client, oldcredits, newcredits);
	g_hfwdOnClientCredits = CreateGlobalForward("SMRPG_OnClientCredits", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	
	// forward SMRPG_OnClientLoaded(client);
	g_hfwdOnClientLoaded = CreateGlobalForward("SMRPG_OnClientLoaded", ET_Ignore, Param_Cell);
}

/**
 * Player stats management
 */
InitPlayer(client)
{
	g_bFirstLoaded[client] = true;
	
	g_iPlayerInfo[client][PLR_level] = 1;
	g_iPlayerInfo[client][PLR_experience] = 0;
	g_iPlayerInfo[client][PLR_credits] = GetConVarInt(g_hCVCreditsStart);
	g_iPlayerInfo[client][PLR_dbId] = -1;
	g_iPlayerInfo[client][PLR_dbUpgradeId] = -1;
	g_iPlayerInfo[client][PLR_triedToLoadData] = false;
	
	g_iPlayerInfo[client][PLR_upgradesLevel] = CreateArray();
	new iNumUpgrades = GetUpgradeCount();
	for(new i=0;i<iNumUpgrades;i++)
	{
		PushArrayCell(g_iPlayerInfo[client][PLR_upgradesLevel], 0); // level 0 for all upgrades
	}
}

AddPlayer(client, const String:auth[])
{
	if(!GetConVarBool(g_hCVEnable))
		return;
	
	if(IsFakeClient(client))
		return;
	
	decl String:sQuery[256];
	
	if(GetConVarBool(g_hCVSteamIDSave))
	{
		Format(sQuery, sizeof(sQuery), "SELECT player_id, upgrades_id, level, experience, credits FROM %s WHERE steamid = '%s' ORDER BY level DESC LIMIT 1", TBL_PLAYERS, auth);
	}
	else
	{
		decl String:sName[MAX_NAME_LENGTH], String:sNameEscaped[MAX_NAME_LENGTH*2+1];
		GetClientName(client, sName, sizeof(sName));
		SQL_EscapeString(g_hDatabase, sName, sNameEscaped, sizeof(sNameEscaped));
		Format(sQuery, sizeof(sQuery), "SELECT player_id, upgrades_id, level, experience, credits FROM %s WHERE name = '%s' AND steamid = '%s' ORDER BY level DESC LIMIT 1", TBL_PLAYERS, sNameEscaped, auth);
	}
	
	SQL_TQuery(g_hDatabase, SQL_GetPlayerInfo, sQuery, GetClientUserId(client));
}

InsertPlayer(client)
{
	if(!GetConVarBool(g_hCVEnable) || !GetConVarBool(g_hCVSaveData))
		return;
	
	decl String:sQuery[512];
	decl String:sName[MAX_NAME_LENGTH], String:sNameEscaped[MAX_NAME_LENGTH*2+1];
	GetClientName(client, sName, sizeof(sName));
	SQL_EscapeString(g_hDatabase, sName, sNameEscaped, sizeof(sNameEscaped));
	
	decl String:sSteamID[32], String:sSteamIDEscaped[65];
	GetClientAuthString(client, sSteamID, sizeof(sSteamID));
	SQL_EscapeString(g_hDatabase, sSteamID, sSteamIDEscaped, sizeof(sSteamIDEscaped));
	
	Format(sQuery, sizeof(sQuery), "INSERT INTO %s (name, steamid, level, experience, credits, lastseen) VALUES ('%s', '%s', '%d', '%d', '%d', '%d')",
		TBL_PLAYERS, sNameEscaped, sSteamIDEscaped, GetClientLevel(client), GetClientExperience(client), GetClientCredits(client), GetTime());
	
	SQL_TQuery(g_hDatabase, SQL_InsertPlayer, sQuery, GetClientUserId(client));
}

SaveData(client)
{
	if(!GetConVarBool(g_hCVEnable) || !GetConVarBool(g_hCVSaveData))
		return;
	
	if(IsFakeClient(client))
		return;
	
	// We're still in the process of loading this client's info from the db. Wait for it..
	if(!g_iPlayerInfo[client][PLR_triedToLoadData])
		return;
	
	if(g_iPlayerInfo[client][PLR_dbId] < 0 || g_iPlayerInfo[client][PLR_dbUpgradeId] < 0)
	{
		InsertPlayer(client);
		return;
	}
	
	decl String:sQuery[1024];
	Format(sQuery, sizeof(sQuery), "UPDATE %s SET level = '%d', experience = '%d', credits = '%d', lastseen = '%d' WHERE player_id = '%d'", TBL_PLAYERS, GetClientLevel(client), GetClientExperience(client), GetClientCredits(client), GetTime(), g_iPlayerInfo[client][PLR_dbId]);
	SQL_TQuery(g_hDatabase, SQL_DoNothing, sQuery);
	
	// Save item levels
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(i)
			Format(sQuery, sizeof(sQuery), "%s, %s = '%d'", sQuery, upgrade[UPGR_shortName], GetClientUpgradeLevel(client, i));
		else
			Format(sQuery, sizeof(sQuery), "%s = '%d'", upgrade[UPGR_shortName], GetClientUpgradeLevel(client, i));
	}
	Format(sQuery, sizeof(sQuery), "UPDATE %s SET %s WHERE upgrades_id = '%d'", TBL_UPGRADES, sQuery, g_iPlayerInfo[client][PLR_dbUpgradeId]);
	SQL_TQuery(g_hDatabase, SQL_DoNothing, sQuery);
}

SaveAllPlayers()
{
	if(!GetConVarBool(g_hCVEnable) || !GetConVarBool(g_hCVSaveData))
		return;
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i))
			SaveData(i);
	}
}

ResetStats(client)
{
	DebugMsg("Stats have been reset for player: %N", client);
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		// Reset upgrade to level 0
		SetArrayCell(GetClientUpgradeLevels(i), i, 0);
		
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

RemovePlayer(client)
{
	ResetStats(client);
	g_iPlayerInfo[client][PLR_dbUpgradeId] = -1;
	g_iPlayerInfo[client][PLR_dbId] = -1;
	g_iPlayerInfo[client][PLR_triedToLoadData] = false;
}

/**
 * Player upgrade info getter
 */
stock GetClientRPGInfo(client, info[PlayerInfo])
{
	Array_Copy(g_iPlayerInfo[client][0], info[0], _:PlayerInfo);
}

stock Handle:GetClientUpgradeLevels(client)
{
	return g_iPlayerInfo[client][PLR_upgradesLevel];
}

GetClientDatabaseUpgradesId(client)
{
	return g_iPlayerInfo[client][PLR_dbUpgradeId];
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

GetClientUpgradeLevel(client, iUpgradeIndex)
{
	return GetArrayCell(GetClientUpgradeLevels(client), iUpgradeIndex);
}

/**
 * Player upgrade buying/selling
 */

SetClientUpgradeLevel(client, iUpgradeIndex, iLevel)
{
	new iOldLevel = GetClientUpgradeLevel(client, iUpgradeIndex);
	
	if(iLevel == iOldLevel)
		return;
	
	SetArrayCell(GetClientUpgradeLevels(client), iUpgradeIndex, iLevel);
	
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return;
	
	// Notify plugin about it.
	Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_queryCallback]);
	Call_PushCell(client);
	Call_PushCell(iOldLevel < iLevel ? UpgradeQueryType_Buy : UpgradeQueryType_Sell);
	Call_Finish();
}

bool:GiveClientUpgrade(client, iUpgradeIndex)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	if(!IsValidUpgrade(upgrade))
		return false;
	
	new iCurrentLevel = GetClientUpgradeLevel(client, iUpgradeIndex);
	
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
	SetClientUpgradeLevel(client, iUpgradeIndex, iCurrentLevel);
	
	return true;
}

bool:BuyClientUpgrade(client, iUpgradeIndex)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	new iCurrentLevel = GetClientUpgradeLevel(client, iUpgradeIndex);
	
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
	
	new iCurrentLevel = GetClientUpgradeLevel(client, iUpgradeIndex);
	
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
	SetClientUpgradeLevel(client, iUpgradeIndex, iCurrentLevel);
	
	return true;
}

bool:SellClientUpgrade(client, iUpgradeIndex)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	new iCurrentLevel = GetClientUpgradeLevel(client, iUpgradeIndex);
	
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
	new bool:bUpgradeBought, iCost, iCurrentIndex;
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	
	new Handle:hRandomBuying = CreateArray();
	for(new i=0;i<iSize;i++)
		PushArrayCell(hRandomBuying, i);
	
	while(GetClientCredits(client))
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
			
			iCost = GetUpgradeCost(iCurrentIndex, GetClientUpgradeLevel(client, iCurrentIndex)+1);
			if(GetClientCredits(client) >= iCost)
			{
				BuyClientUpgrade(client, iCurrentIndex);
				bUpgradeBought = true;
			}
		}
		if(!bUpgradeBought)
			break; /* Couldn't afford anything */
	}
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
		iCurrentLevel = GetClientUpgradeLevel(client, i);
		while(iCurrentLevel > iMaxLevel)
		{
			/* Give player their credits back */
			/* TakeItem isn't necessary since the player hasn't even been completely added yet */
			SetClientCredits(client, GetClientCredits(client) + GetUpgradeCost(i, iCurrentLevel--));
		}
		if(GetClientUpgradeLevel(client, i) != iCurrentLevel)
			SetClientUpgradeLevel(client, i, iCurrentLevel);
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
	
	g_iPlayerInfo[client][PLR_credits] = iCredits;
	
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
	
	g_iPlayerInfo[client][PLR_level] = iLevel;
	
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
	
	g_iPlayerInfo[client][PLR_experience] = iExperience;
	
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
	g_iPlayerInfo[client][PLR_dbUpgradeId] = SQL_FetchInt(hndl, 1);
	g_iPlayerInfo[client][PLR_level] = SQL_FetchInt(hndl, 2);
	g_iPlayerInfo[client][PLR_experience] = SQL_FetchInt(hndl, 3);
	g_iPlayerInfo[client][PLR_credits] = SQL_FetchInt(hndl, 4);
	
	UpdateClientRank(client);
	UpdateRankCount();
	
	/* Player Items */
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT * FROM %s WHERE upgrades_id = '%d'", TBL_UPGRADES, g_iPlayerInfo[client][PLR_dbUpgradeId]);
	SQL_TQuery(g_hDatabase, SQL_GetPlayerItems, sQuery, userid);
}

public SQL_GetPlayerItems(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to load item data (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	// Player isn't fully registred?!
	if(SQL_GetRowCount(hndl) == 0 || !SQL_FetchRow(hndl))
	{
		LogError("Player %N is registred, but doesn't have an items table entry?", client);
		CallOnClientLoaded(client);
		return;
	}
	
	new iNumFields = SQL_GetFieldCount(hndl);
	decl String:sFieldName[MAX_UPGRADE_SHORTNAME_LENGTH];
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iNumFields;i++)
	{
		SQL_FieldNumToName(hndl, i, sFieldName, sizeof(sFieldName));
		
		// If that upgrade isn't loaded yet, we'll fetch the right level when it's loaded.
		if(!GetUpgradeByShortname(sFieldName, upgrade))
			continue;
		
		SetClientUpgradeLevel(client, upgrade[UPGR_index], SQL_FetchInt(hndl, i));
	}
	
	g_iPlayerInfo[client][PLR_triedToLoadData] = true;
	
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
	new String:sFields[1024], String:sValues[1024];
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		Format(sFields, sizeof(sFields), "%s, %s", sFields, upgrade[UPGR_shortName]);
		Format(sValues, sizeof(sValues), "%s, '%d'", sValues, GetClientUpgradeLevel(client, i));
	}
	
	decl String:sQuery[2048];
	Format(sQuery, sizeof(sQuery), "INSERT INTO %s (upgrades_id%s) VALUES (NULL%s)", TBL_UPGRADES, sFields, sValues);
	SQL_TQuery(g_hDatabase, SQL_InsertPlayerUpgrades, sQuery, userid);
}

public SQL_InsertPlayerUpgrades(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to insert player upgrades info (%s)", error);
		CallOnClientLoaded(client);
		return;
	}
	
	g_iPlayerInfo[client][PLR_dbUpgradeId] = SQL_GetInsertId(owner);
	
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "UPDATE %s SET upgrades_id = '%d' WHERE player_id = '%d'", TBL_PLAYERS, g_iPlayerInfo[client][PLR_dbUpgradeId], g_iPlayerInfo[client][PLR_dbId]);
	SQL_TQuery(g_hDatabase, SQL_DoNothing, sQuery);
	
	g_iPlayerInfo[client][PLR_triedToLoadData] = true;
	
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
	
	return GetArrayCell(GetClientUpgradeLevels(client), upgrade[UPGR_index]);
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
		return false;
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
	
	new iExperience = GetNativeCell(2);
	
	return SetClientExperience(client, iExperience);
}

/**
 * Helpers
 */
CallOnClientLoaded(client)
{
	g_iPlayerInfo[client][PLR_triedToLoadData] = true;
	
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