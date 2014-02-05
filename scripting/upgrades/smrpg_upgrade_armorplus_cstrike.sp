#pragma semicolon 1
#include <sourcemod>
#include <cstrike>
#include <smrpg>
#include <smrpg_armorplus>

#define PLUGIN_VERSION "1.0"
#define UPGRADE_SHORTNAME "armorplus"

new Handle:g_hCVMaxIncrease;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Armor+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Armor+ upgrade for SM:RPG. Increases player's armor.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	new EngineVersion:engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	
	RegPluginLibrary("smrpg_armorplus");
	CreateNative("SMRPG_Armor_GetClientMaxArmorEx", Native_GetMaxArmor);
	return APLRes_Success;
}

public OnPluginStart()
{
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
}

public OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public OnLibraryAdded(const String:name[])
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Armor+", UPGRADE_SHORTNAME, "Increases your armor.", 16, true, 10, 10, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVMaxIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armor_inc", "25", "Armor max increase for each level", 0, true, 1.0);
	}
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	new iMaxArmor = GetClientMaxArmor(client);
	new iArmor = GetClientArmor(client);
	if(iArmor == DEFAULT_MAX_ARMOR && iMaxArmor > iArmor)
		SetClientArmor(client, iMaxArmor);
}

public Action:CS_OnBuyCommand(client, const String:weapon[])
{
	// If the client bought a vest, set it to the new maxlimit
	if(StrContains(weapon, "vest") != 0)
		return Plugin_Continue;
	
	new iMaxArmor = GetClientMaxArmor(client);
	new iArmor = GetClientArmor(client);
	if(iArmor < iMaxArmor)
		SetClientArmor(client, iMaxArmor);
	return Plugin_Continue;
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	if(!IsClientInGame(client))
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	
	new iArmor = GetClientArmor(client);
	new iMaxArmor = GetClientMaxArmor(client);
	
	switch(type)
	{
		case UpgradeQueryType_Buy:
		{
			// Client currently had his old maxarmor or more?
			// Set him to his new higher maxarmor immediately.
			// Don't touch his armor, if he were already damaged.
			if(iArmor >= (iMaxArmor - GetConVarInt(g_hCVMaxIncrease)))
				SetClientArmor(client, iMaxArmor);
		}
		case UpgradeQueryType_Sell:
		{
			// Client had more armor than his new maxarmor?
			// Decrease it.
			if(iArmor > iMaxArmor)
				SetClientArmor(client, iMaxArmor);
		}
	}
}

public bool:SMRPG_ActiveQuery(client)
{
	// This is a passive effect, so it's always active, if the player got at least level 1
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}

public SMRPG_TranslateUpgrade(client, const String:shortname[], TranslationType:type, String:translation[], maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		new String:sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

GetClientMaxArmor(client)
{
	new iDefaultMaxArmor = DEFAULT_MAX_ARMOR;
	
	if(!SMRPG_IsEnabled())
		return iDefaultMaxArmor;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return iDefaultMaxArmor;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return iDefaultMaxArmor;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return iDefaultMaxArmor;
	
	return iDefaultMaxArmor + GetConVarInt(g_hCVMaxIncrease) * iLevel;
}

// Check if the other plugins are ok with setting the armor before doing it.
SetClientArmor(client, armor)
{
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	SetEntProp(client, Prop_Send, "m_ArmorValue", armor);
}

/**
 * Native callbacks
 */
public Native_GetMaxArmor(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	return GetClientMaxArmor(client);
}