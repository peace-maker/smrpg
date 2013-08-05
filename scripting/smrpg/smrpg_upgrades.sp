#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <autoexecconfig> // https://github.com/Impact123/AutoExecConfig

enum InternalUpgradeInfo
{
	UPGR_index, // index in g_hUpgrades array
	bool:UPGR_enabled, // upgrade enabled?
	bool:UPGR_unavailable, // plugin providing this upgrade gone?
	UPGR_maxLevelBarrier, // upper limit of maxlevel setting. Can't set maxlevel higher than that.
	UPGR_maxLevel, // Maximal level a player can get for this upgrade
	UPGR_startCost, // The amount of credits the first level costs
	UPGR_incCost, // The amount of credits each level costs more
	Function:UPGR_queryCallback, // callback called, when a player bought/sold the upgrade
	Function:UPGR_activeCallback, // callback called, to see, if a player is currently under the effect of that upgrade
	Function:UPGR_translationCallback, // callback called, when the upgrade's name is about to get displayed.
	Function:UPGR_resetCallback, // callback called, when the upgrade's effect should be removed.
	Handle:UPGR_plugin, // The plugin which registered the upgrade
	// Convar handles to track changes and upgrade the right value in the cache
	Handle:UPGR_enableConvar,
	Handle:UPGR_maxLevelConvar,
	Handle:UPGR_startCostConvar,
	Handle:UPGR_incCostConvar,
	
	String:UPGR_name[MAX_UPGRADE_NAME_LENGTH],
	String:UPGR_shortName[MAX_UPGRADE_SHORTNAME_LENGTH],
	String:UPGR_description[MAX_UPGRADE_DESCRIPTION_LENGTH]
};

new Handle:g_hUpgrades;
new Handle:g_hfwdOnUpgradeEffect;

RegisterUpgradeNatives()
{
	g_hfwdOnUpgradeEffect = CreateGlobalForward("SMRPG_OnUpgradeEffect", ET_Hook, Param_Cell, Param_String);
	
	CreateNative("SMRPG_RegisterUpgradeType", Native_RegisterUpgradeType);
	CreateNative("SMRPG_UnregisterUpgradeType", Native_UnregisterUpgradeType);
	CreateNative("SMRPG_CreateUpgradeConVar", Native_CreateUpgradeConVar);
	
	CreateNative("SMRPG_SetUpgradeTranslationCallback", Native_SetUpgradeTranslationCallback);
	CreateNative("SMRPG_SetUpgradeResetCallback", Native_SetUpgradeResetCallback);
	CreateNative("SMRPG_UpgradeExists", Native_UpgradeExists);
	CreateNative("SMRPG_GetUpgradeInfo", Native_GetUpgradeInfo);
	CreateNative("SMRPG_ResetUpgradeEffectOnClient", Native_ResetUpgradeEffectOnClient);
	CreateNative("SMRPG_RunUpgradeEffect", Native_RunUpgradeEffect);
}

InitUpgrades()
{
	g_hUpgrades = CreateArray(_:InternalUpgradeInfo);
}

// native SMRPG_RegisterUpgradeType(const String:name[], const String:shortname[], maxlevelbarrier, bool:bDefaultEnable, iDefaultMaxLevel, iDefaultStartCost, iDefaultCostInc, SMRPG_UpgradeQuery:buycb, SMRPG_UpgradeQuery:sellcb, SMRPG_UpgradeQuery:activecb);
public Native_RegisterUpgradeType(Handle:plugin, numParams)
{
	new len;
	GetNativeStringLength(1, len);
	new String:sName[len+1];
	GetNativeString(1, sName, len+1);
	
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	if(StrContains(sShortName, " ") != -1)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Whitespace is not allowed in the shortname of an upgrade.");
		return;
	}

	// There already is an upgrade with that name loaded. Don't load it twice. shortnames have to be unique.
	new upgrade[InternalUpgradeInfo], bool:bAlreadyLoaded;
	if(GetUpgradeByShortname(sShortName, upgrade))
	{
		if(IsValidUpgrade(upgrade) && upgrade[UPGR_plugin] != plugin)
		{
			new String:sPluginName[32] = "Unloaded";
			GetPluginInfo(upgrade[UPGR_plugin], PlInfo_Name, sPluginName, sizeof(sPluginName));
			ThrowNativeError(SP_ERROR_NATIVE, "An upgrade with name \"%s\" is already registered by plugin \"%s\".", sShortName, sPluginName);
			return;
		}
		
		bAlreadyLoaded = true;
	}
	
	GetNativeStringLength(3, len);
	new String:sDescription[len+1];
	GetNativeString(3, sDescription, len+1);
	
	new iMaxLevelBarrier = GetNativeCell(4);
	new bool:bDefaultEnable = bool:GetNativeCell(5);
	new iDefaultMaxLevel = GetNativeCell(6);
	new iDefaultStartCost = GetNativeCell(7);
	new iDefaultCostInc = GetNativeCell(8);
	new Function:queryCallback = Function:GetNativeCell(9);
	new Function:activeCallback = Function:GetNativeCell(10);
	
	if(!bAlreadyLoaded)
		upgrade[UPGR_index] = GetArraySize(g_hUpgrades);
	upgrade[UPGR_enabled] = bDefaultEnable;
	upgrade[UPGR_unavailable] = false;
	upgrade[UPGR_maxLevelBarrier] = iMaxLevelBarrier;
	upgrade[UPGR_maxLevel] = iDefaultMaxLevel;
	upgrade[UPGR_startCost] = iDefaultStartCost;
	upgrade[UPGR_incCost] = iDefaultCostInc;
	upgrade[UPGR_queryCallback] = queryCallback;
	upgrade[UPGR_activeCallback] = activeCallback;
	upgrade[UPGR_translationCallback] = INVALID_FUNCTION;
	upgrade[UPGR_resetCallback] = INVALID_FUNCTION;
	upgrade[UPGR_plugin] = plugin;
	strcopy(upgrade[UPGR_name], MAX_UPGRADE_NAME_LENGTH, sName);
	strcopy(upgrade[UPGR_shortName], MAX_UPGRADE_SHORTNAME_LENGTH, sShortName);
	strcopy(upgrade[UPGR_description], MAX_UPGRADE_DESCRIPTION_LENGTH, sDescription);
	
	decl String:sCvarName[64], String:sCvarDescription[256], String:sValue[16];
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_upgrade_%s", sShortName);
	AutoExecConfig_SetFile(sCvarName, "sourcemod/smrpg");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(plugin);
	
	// Register convars
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_enable", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "Sets the %s item to enabled (1) or disabled (0)", sName);
	IntToString(_:bDefaultEnable, sValue, sizeof(sValue));
	new Handle:hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 0.0, true, 1.0);
	HookConVarChange(hCvar, ConVar_UpgradeChanged);
	upgrade[UPGR_enableConvar] = hCvar;
	
	// TODO: Handle maxlevel > maxlevelbarrier etc. rpgi.cpp CVARItemMaxLvl!
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_maxlevel", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "%s item maximum level", sName);
	IntToString(iDefaultMaxLevel, sValue, sizeof(sValue));
	hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 1.0);
	HookConVarChange(hCvar, ConVar_UpgradeMaxLevelChanged);
	upgrade[UPGR_maxLevelConvar] = hCvar;
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_cost", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "%s item start cost", sName);
	IntToString(iDefaultStartCost, sValue, sizeof(sValue));
	hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 0.0);
	HookConVarChange(hCvar, ConVar_UpgradeChanged);
	upgrade[UPGR_startCostConvar] = hCvar;
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_icost", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "%s item cost increment for each level", sName);
	IntToString(iDefaultCostInc, sValue, sizeof(sValue));
	hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 0.0);
	HookConVarChange(hCvar, ConVar_UpgradeChanged);
	upgrade[UPGR_incCostConvar] = hCvar;
	
	AutoExecConfig_ExecuteFile();
	
	//AutoExecConfig_CleanFile();
	
	// We already got info about this. Don't insert it a second time.
	if(bAlreadyLoaded)
	{
		SaveUpgradeConfig(upgrade);
	}
	// It's a new upgrade. Insert it.
	else
	{
		PushArrayArray(g_hUpgrades, upgrade[0], _:InternalUpgradeInfo);
		
		// New upgrade! Add it to each connected player's list
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientConnected(i))
			{
				PushArrayCell(GetClientUpgradeLevels(i), 0);
			}
		}
	}
	
	CheckUpgradeDatabaseField(sShortName);
}

// native SMRPG_UnregisterUpgradeType(const String:shortname[]);
public Native_UnregisterUpgradeType(Handle:plugin, numParams)
{
	new len;
	GetNativeStringLength(1, len);
	new String:sShortName[len+1];
	GetNativeString(1, sShortName, len+1);
	
	new iSize = GetArraySize(g_hUpgrades);
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(!IsValidUpgrade(upgrade))
			continue;
		
		if(StrEqual(upgrade[UPGR_shortName], sShortName, false))
		{
			// Set this upgrade as unavailable! Don't process anything in the future.
			upgrade[UPGR_unavailable] = true;
			SaveUpgradeConfig(upgrade);
			return;
		}
	}
	
	ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
}

// native Handle:SMRPG_CreateUpgradeConVar(const String:shortname[], const String:name[], const String:defaultValue[], const String:description[]="", flags=0, bool:hasMin=false, Float:min=0.0, bool:hasMax=false, Float:max=0.0);
public Native_CreateUpgradeConVar(Handle:plugin, numParams)
{
	new len;
	GetNativeStringLength(1, len);
	new String:sShortName[len+1];
	GetNativeString(1, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return _:INVALID_HANDLE;
	}
	
	GetNativeStringLength(2, len);
	new String:name[len+1];
	GetNativeString(2, name, len+1);
	
	GetNativeStringLength(3, len);
	new String:defaultValue[len+1];
	GetNativeString(3, defaultValue, len+1);
	
	GetNativeStringLength(4, len);
	new String:description[len+1];
	GetNativeString(4, description, len+1);
	
	new flags = GetNativeCell(5);
	new bool:hasMin = bool:GetNativeCell(6);
	new Float:min = Float:GetNativeCell(7);
	new bool:hasMax = bool:GetNativeCell(8);
	new Float:max = Float:GetNativeCell(9);
	
	decl String:sFileName[PLATFORM_MAX_PATH];
	Format(sFileName, sizeof(sFileName), "smrpg_upgrade_%s", sShortName);
	AutoExecConfig_SetFile(sFileName, "sourcemod/smrpg");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(plugin);
	
	new Handle:hCvar = AutoExecConfig_CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
	
	// AutoExecConfig_ExecuteFile(); // No need to call AutoExecConfig again. The file is already in the list.
	// Just execute the config again, to get the values?
	ServerCommand("exec sourcemod/smrpg/smrpg_upgrade_%s.cfg", sShortName);
	
	//AutoExecConfig_CleanFile();
	
	return _:hCvar;
}

// native bool:SMRPG_UpgradeExists(const String:shortname[]);
public Native_UpgradeExists(Handle:plugin, numParams)
{
	new len;
	GetNativeStringLength(1, len);
	new String:sShortName[len+1];
	GetNativeString(1, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade))
		return false;
	
	return IsValidUpgrade(upgrade);
}

// native SMRPG_GetUpgradeInfo(const String:shortname[], upgrade[UpgradeInfo]);
public Native_GetUpgradeInfo(Handle:plugin, numParams)
{
	new len;
	GetNativeStringLength(1, len);
	new String:sShortName[len+1];
	GetNativeString(1, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return;
	}
	
	new publicUpgrade[UpgradeInfo];
	publicUpgrade[UI_enabled] = upgrade[UPGR_enabled];
	publicUpgrade[UI_maxLevelBarrier] = upgrade[UPGR_maxLevelBarrier];
	publicUpgrade[UI_maxLevel] = upgrade[UPGR_maxLevel];
	publicUpgrade[UI_startCost] = upgrade[UPGR_startCost];
	publicUpgrade[UI_incCost] = upgrade[UPGR_incCost];
	strcopy(publicUpgrade[UI_name], MAX_UPGRADE_NAME_LENGTH, upgrade[UPGR_name]);
	strcopy(publicUpgrade[UI_shortName], MAX_UPGRADE_SHORTNAME_LENGTH, upgrade[UPGR_shortName]);
	
	SetNativeArray(2, publicUpgrade[0], _:UpgradeInfo);
}

// native SMRPG_SetUpgradeTranslationCallback(const String:shortname[], SMRPG_TranslateUpgrade:cb);
public Native_SetUpgradeTranslationCallback(Handle:plugin, numParams)
{
	new len;
	GetNativeStringLength(1, len);
	new String:sShortName[len+1];
	GetNativeString(1, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return;
	}
	
	if(upgrade[UPGR_plugin] != plugin)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "ResetEffect callback has to be from the same plugin the upgrade was registered in.");
		return;
	}
	
	upgrade[UPGR_translationCallback] = Function:GetNativeCell(2);
	SaveUpgradeConfig(upgrade);
}

// native SMRPG_SetUpgradeResetCallback(const String:shortname[], SMRPG_ResetEffectCB:cb);
public Native_SetUpgradeResetCallback(Handle:plugin, numParams)
{
	new len;
	GetNativeStringLength(1, len);
	new String:sShortName[len+1];
	GetNativeString(1, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return;
	}
	
	if(upgrade[UPGR_plugin] != plugin)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Translation callback has to be from the same plugin the upgrade was registered in.");
		return;
	}
	
	upgrade[UPGR_resetCallback] = Function:GetNativeCell(2);
	SaveUpgradeConfig(upgrade);
}

public Native_ResetUpgradeEffectOnClient(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return;
	}
	
	new len;
	GetNativeStringLength(2, len);
	new String:sShortName[len+1];
	GetNativeString(2, sShortName, len+1);
	
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
		return;
	}
	
	// If there is no reset callback registered, we can't do anything here.
	if(upgrade[UPGR_resetCallback] == INVALID_FUNCTION)
		return;
	
	Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_resetCallback]);
	Call_PushCell(client);
	Call_Finish();
}

public Native_RunUpgradeEffect(Handle:plugin, numParams)
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

	new Action:result;
	Call_StartForward(g_hfwdOnUpgradeEffect);
	Call_PushCell(client);
	Call_PushString(sShortName);
	Call_Finish(result);
	
	return result < Plugin_Handled;
}

/**
 * Helpers
 */
stock Handle:GetUpgradeList()
{
	return g_hUpgrades;
}

GetUpgradeCount()
{
	return GetArraySize(g_hUpgrades);
}

GetUpgradeByIndex(iIndex, upgrade[InternalUpgradeInfo])
{
	GetArrayArray(g_hUpgrades, iIndex, upgrade[0], _:InternalUpgradeInfo);
}

bool:GetUpgradeByShortname(const String:sShortName[], upgrade[InternalUpgradeInfo])
{
	new iSize = GetArraySize(g_hUpgrades);
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(StrEqual(upgrade[UPGR_shortName], sShortName, false))
		{
			return true;
		}
	}
	return false;
}

stock GetUpgradeCost(iItemIndex, iLevel)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iItemIndex, upgrade);
	if(iLevel <= 1)
		return upgrade[UPGR_startCost];
	else
		return upgrade[UPGR_startCost] + upgrade[UPGR_incCost] * (iLevel-1);
}

stock GetUpgradeSale(iItemIndex, iLevel)
{
	new iCost = GetUpgradeCost(iItemIndex, iLevel);
	
	new Float:fSalePercent = GetConVarFloat(g_hCVSalePercent);
	if(fSalePercent == 1.0)
		return iCost;
	
	if(iLevel <= 1)
		return iCost;
	
	new iSale = RoundToFloor(float(iCost) * (fSalePercent > 1.0 ? (fSalePercent/100.0) : fSalePercent) + 0.5);
	new iCreditsInc = GetConVarInt(g_hCVCreditsInc);
	if(iCreditsInc <= 1)
		return iSale;
	else
		iSale = (iSale + RoundToFloor(float(iCreditsInc)/2.0)) / iCreditsInc * iCreditsInc;
	
	if(iSale > iCost)
		return iCost;
	
	return iSale;
}

stock bool:IsValidUpgrade(upgrade[InternalUpgradeInfo])
{
	if(upgrade[UPGR_unavailable])
		return false;
	
	if(IsValidPlugin(upgrade[UPGR_plugin]))
		return true;
	
	upgrade[UPGR_unavailable] = true;
	upgrade[UPGR_plugin] = INVALID_HANDLE;
	SaveUpgradeConfig(upgrade);
	return false;
}

stock SaveUpgradeConfig(upgrade[InternalUpgradeInfo])
{
	SetArrayArray(g_hUpgrades, upgrade[UPGR_index], upgrade[0], _:InternalUpgradeInfo);
}

stock bool:IsUpgradeEffectActive(client, upgrade[InternalUpgradeInfo])
{
	if(!IsValidUpgrade(upgrade))
		return false;
	
	new bool:bActive;
	Call_StartFunction(upgrade[UPRG_plugin], upgrade[UPGR_activeCallback]);
	Call_PushCell(client);
	Call_Finish(bActive);
	
	return bActive;
}

GetUpgradeTranslatedName(client, iUpgradeIndex, String:name[], maxlen)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	strcopy(name, maxlen, upgrade[UPGR_name]);
	
	// No translation callback registered? Fall back to the name set when registering the upgrade.
	if(upgrade[UPGR_translationCallback] == INVALID_FUNCTION)
		return;
	
	Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_translationCallback]);
	Call_PushCell(client);
	Call_PushCell(TranslationType_Name);
	Call_PushStringEx(name, maxlen, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(maxlen);
	Call_Finish();
}

GetUpgradeTranslatedDescription(client, iUpgradeIndex, String:description[], maxlen)
{
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	strcopy(description, maxlen, upgrade[UPGR_description]);
	
	// No translation callback registered? Fall back to the name set when registering the upgrade.
	if(upgrade[UPGR_translationCallback] == INVALID_FUNCTION)
		return;
	
	Call_StartFunction(upgrade[UPGR_plugin], upgrade[UPGR_translationCallback]);
	Call_PushCell(client);
	Call_PushCell(TranslationType_Description);
	Call_PushStringEx(description, maxlen, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(maxlen);
	Call_Finish();
}

/**
 * Convar change callbacks
 */
// Cache the new config value
public ConVar_UpgradeChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	new iSize = GetArraySize(g_hUpgrades);
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade[UPGR_enableConvar] == convar)
		{
			upgrade[UPGR_enabled] = GetConVarBool(convar);
			SaveUpgradeConfig(upgrade);
			break;
		}
		else if(upgrade[UPGR_startCostConvar] == convar)
		{
			upgrade[UPGR_startCost] = GetConVarInt(convar);
			SaveUpgradeConfig(upgrade);
			break;
		}
		else if(upgrade[UPGR_incCostConvar] == convar)
		{
			upgrade[UPGR_incCost] = GetConVarInt(convar);
			SaveUpgradeConfig(upgrade);
			break;
		}
	}
}

public ConVar_UpgradeMaxLevelChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	new iSize = GetArraySize(g_hUpgrades);
	new upgrade[InternalUpgradeInfo];
	for(new i;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade[UPGR_maxLevelConvar] == convar)
			break;
	}
	
	new iNewMaxLevel = GetConVarInt(convar);
	new iMaxLevelBarrier = upgrade[UPGR_maxLevelBarrier];
	
	if(!GetConVarBool(g_hCVIgnoreLevelBarrier) && iNewMaxLevel > iMaxLevelBarrier)
		iNewMaxLevel = iMaxLevelBarrier;
	
	upgrade[UPGR_maxLevel] = iNewMaxLevel;
	SaveUpgradeConfig(upgrade);
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		while(GetClientUpgradeLevel(i, upgrade[UPGR_index]) > iNewMaxLevel)
		{
			SetClientCredits(i, GetClientCredits(i) + GetUpgradeCost(upgrade[UPGR_index], GetClientUpgradeLevel(i, upgrade[UPGR_index])));
			TakeClientUpgrade(i, upgrade[UPGR_index]);
		}
	}
}