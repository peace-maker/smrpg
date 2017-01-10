#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <smrpg>
#include <smrpg_health>

#define UPGRADE_SHORTNAME "health"

ConVar g_hCVMaxIncrease;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Health+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Health+ upgrade for SM:RPG. Increases player's health.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("smrpg_health");
	CreateNative("SMRPG_Health_GetClientMaxHealthEx", Native_GetMaxHealth);
}

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Health+", UPGRADE_SHORTNAME, "Increases your health.", 16, true, 16, 10, 10);
		SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVMaxIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_health_inc", "25", "Health max increase for each level", 0, true, 1.0);
	}
}

/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	SetClientHealth(client, GetClientMaxHealth(client));
}

/**
 * SM:RPG Upgrade callbacks
 */
public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
	if(!IsClientInGame(client))
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	
	int iHealth = GetClientHealth(client);
	int iMaxHealth = GetClientMaxHealth(client);
	
	switch(type)
	{
		case UpgradeQueryType_Buy:
		{
			// Client currently had his old maxhealth or more?
			// Set him to his new higher maxhealth immediately.
			// Don't touch his health, if he were already damaged.
			if(iHealth >= (iMaxHealth - g_hCVMaxIncrease.IntValue))
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

public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

int GetClientMaxHealth(int client)
{
	// Get the default maxhealth for this player/class
	int iDefaultMaxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	
	if(!SMRPG_IsEnabled())
		return iDefaultMaxHealth;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return iDefaultMaxHealth;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return iDefaultMaxHealth;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return iDefaultMaxHealth;
	
	return iDefaultMaxHealth + g_hCVMaxIncrease.IntValue * iLevel;
}

// Check if the other plugins are ok with setting the health before doing it.
void SetClientHealth(int client, int health)
{
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	SetEntityHealth(client, health);
}

/**
 * Native callbacks
 */
public int Native_GetMaxHealth(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetClientMaxHealth(client);
}