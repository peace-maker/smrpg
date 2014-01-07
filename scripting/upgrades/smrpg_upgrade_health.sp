#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <smrpg_health>

#define PLUGIN_VERSION "1.0"
#define UPGRADE_SHORTNAME "health"

new Handle:g_hCVMaxIncrease;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Health+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Health+ upgrade for SM:RPG. Increases player's health.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("smrpg_health");
	CreateNative("SMRPG_Health_GetClientMaxHealthEx", Native_GetMaxHealth);
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
		SMRPG_RegisterUpgradeType("Health+", UPGRADE_SHORTNAME, "Increases your health.", 16, true, 16, 10, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVMaxIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_health_inc", "25", "Health max increase for each level", 0, true, 1.0);
	}
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	SetClientHealth(client, GetClientMaxHealth(client));
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
	
	new iHealth = GetClientHealth(client);
	new iMaxHealth = GetClientMaxHealth(client);
	
	switch(type)
	{
		case UpgradeQueryType_Buy:
		{
			// Client currently had his old maxhealth or more?
			// Set him to his new higher maxhealth immediately.
			// Don't touch his health, if he were already damaged.
			if(iHealth >= (iMaxHealth - GetConVarInt(g_hCVMaxIncrease)))
				SetClientHealth(client, iMaxHealth);
		}
		case UpgradeQueryType_Sell:
		{
			// Client had more health than his new maxhealth?
			// Decrease it.
			if(GetClientHealth(client) > iMaxHealth)
				SetClientHealth(client, iMaxHealth);
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

public SMRPG_TranslateUpgrade(client, TranslationType:type, String:translation[], maxlen)
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

GetClientMaxHealth(client)
{
	// Get the default maxhealth for this player/class
	new iDefaultMaxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	
	if(!SMRPG_IsEnabled())
		return iDefaultMaxHealth;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return iDefaultMaxHealth;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return iDefaultMaxHealth;
	
	return iDefaultMaxHealth + GetConVarInt(g_hCVMaxIncrease) * iLevel;
}

// Check if the other plugins are ok with setting the health before doing it.
SetClientHealth(client, health)
{
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	SetEntityHealth(client, health);
}

/**
 * Native callbacks
 */
public Native_GetMaxHealth(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	return GetClientMaxHealth(client);
}