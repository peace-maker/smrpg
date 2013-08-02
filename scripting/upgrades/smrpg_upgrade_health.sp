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
	CreateNative("SMRPG_Health_GetMaxHealth", Native_GetMaxHealth);
}

public OnPluginStart()
{
	g_hCVMaxIncrease = CreateConVar("smrpg_upgr_health_inc", "25", "Health max increase for each level", 0, true, 1.0);
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
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
		SMRPG_RegisterUpgradeType("Health+", UPGRADE_SHORTNAME, 16, true, 16, 10, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_OnTranslateUpgrade);
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
	
	SetEntityHealth(client, GetClientMaxHealth(client));
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
				SetEntityHealth(client, iMaxHealth);
		}
		case UpgradeQueryType_Sell:
		{
			// Client had more health than his new maxhealth?
			// Decrease it.
			if(GetClientHealth(client) > iMaxHealth)
				SetEntityHealth(client, iMaxHealth);
		}
	}
}

public bool:SMRPG_ActiveQuery(client)
{
	return false;
}

public SMRPG_OnTranslateUpgrade(client, String:translation[], maxlen)
{
	strcopy(translation, maxlen, "Gesundheit+");
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