#pragma semicolon 1
#include <sourcemod>
#include <cstrike>

#pragma newdecls required
#include <smrpg>
#include <smrpg_armorplus>

#define PLUGIN_VERSION "1.0"
#define UPGRADE_SHORTNAME "armorplus"

ConVar g_hCVMaxIncrease;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Armor+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Armor+ upgrade for SM:RPG. Increases player's armor.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	
	RegPluginLibrary("smrpg_armorplus");
	CreateNative("SMRPG_Armor_GetClientMaxArmorEx", Native_GetMaxArmor);
	return APLRes_Success;
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
		SMRPG_RegisterUpgradeType("Armor+", UPGRADE_SHORTNAME, "Increases your armor.", 5, true, 5, 10, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVMaxIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armor_inc", "5", "Armor max increase for each level", 0, true, 1.0);
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
	
	int iMaxArmor = GetClientMaxArmor(client);
	int iArmor = GetClientArmor(client);
	if(iArmor == DEFAULT_MAX_ARMOR && iMaxArmor > iArmor)
		SetClientArmor(client, iMaxArmor);
}

public Action CS_OnBuyCommand(int client, const char[] weapon)
{
	// If the client bought a vest, set it to the new maxlimit
	if(StrContains(weapon, "vest") != 0)
		return Plugin_Continue;
	
	int iMaxArmor = GetClientMaxArmor(client);
	int iArmor = GetClientArmor(client);
	if(iArmor < iMaxArmor)
		SetClientArmor(client, iMaxArmor);
	return Plugin_Continue;
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
	
	int iArmor = GetClientArmor(client);
	int iMaxArmor = GetClientMaxArmor(client);
	
	switch(type)
	{
		case UpgradeQueryType_Buy:
		{
			// Client currently had his old maxarmor or more?
			// Set him to his new higher maxarmor immediately.
			// Don't touch his armor, if he were already damaged.
			if(iArmor >= (iMaxArmor - g_hCVMaxIncrease.IntValue))
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

public bool SMRPG_ActiveQuery(int client)
{
	// This is a passive effect, so it's always active, if the player got at least level 1
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
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

int GetClientMaxArmor(int client)
{
	int iDefaultMaxArmor = DEFAULT_MAX_ARMOR;
	
	if(!SMRPG_IsEnabled())
		return iDefaultMaxArmor;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return iDefaultMaxArmor;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return iDefaultMaxArmor;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return iDefaultMaxArmor;
	
	int iNewMaxArmor = iDefaultMaxArmor + g_hCVMaxIncrease.IntValue * iLevel;
	if(iNewMaxArmor > CS_MAX_ARMOR)
		iNewMaxArmor = CS_MAX_ARMOR;
	
	return iNewMaxArmor;
}

// Check if the other plugins are ok with setting the armor before doing it.
void SetClientArmor(int client, int armor)
{
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	SetEntProp(client, Prop_Send, "m_ArmorValue", armor);
}

/**
 * Native callbacks
 */
public int Native_GetMaxArmor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetClientMaxArmor(client);
}