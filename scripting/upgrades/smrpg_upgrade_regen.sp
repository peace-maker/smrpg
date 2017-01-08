#pragma semicolon 1
#include <sourcemod>
#include <smlib>

#pragma newdecls required
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <smrpg_health>

#define UPGRADE_SHORTNAME "regen"

#define PLUGIN_VERSION "1.0"

ConVar g_hCVAmount;
ConVar g_hCVAmountIncrease;
ConVar g_hCVInterval;
ConVar g_hCVIntervalDecrease;

Handle g_hRegenerationTimer[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Health regeneration",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Regeneration upgrade for SM:RPG. Regenerates HP every second.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
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
		SMRPG_RegisterUpgradeType("HP Regeneration", UPGRADE_SHORTNAME, "Regenerates HP regularly.", 15, true, 5, 5, 10);
		SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVAmount = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_amount", "1", "Specify the base amount of HP which is regenerated at the first level.", 0, true, 0.1);
		g_hCVAmountIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_amount_inc", "1", "Additional HP to regenerate each interval multiplied by level. (base + inc * (level-1))", 0, true, 0.0);
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_interval", "1.0", "Specify the base interval rate at which HP is regenerated in seconds at the first level.", 0, true, 0.1);
		g_hCVIntervalDecrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_interval_dec", "0.0", "How much is the base interval reduced for each level?", 0, true, 0.0);
	}
}

public void OnClientDisconnect(int client)
{
	ClearHandle(g_hRegenerationTimer[client]);
}

/**
 * SM:RPG Upgrade callbacks
 */
public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
	// Change timer interval to correct interval for new level.
	ClearHandle(g_hRegenerationTimer[client]);
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	float fInterval = g_hCVInterval.FloatValue - g_hCVIntervalDecrease.FloatValue * (iLevel - 1);
	g_hRegenerationTimer[client] = CreateTimer(fInterval, Timer_IncreaseHealth, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

public Action Timer_IncreaseHealth(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;

	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(SMRPG_IgnoreBots() && IsFakeClient(client))
		return Plugin_Continue;
		
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
		
	int iOldHealth = GetClientHealth(client);
	int iMaxHealth = SMRPG_Health_GetClientMaxHealth(client);
	// Don't reset the health, if the player gained more by other means.
	if(iOldHealth >= iMaxHealth)
		return Plugin_Continue;
		
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	int iIncrease = g_hCVAmount.IntValue + g_hCVAmountIncrease.IntValue * (iLevel - 1);
	int iNewHealth = iOldHealth + iIncrease;
	// Limit the regeneration to the maxhealth.
	if(iNewHealth > iMaxHealth)
		iNewHealth = iMaxHealth;
		
	SetEntityHealth(client, iNewHealth);
	
	return Plugin_Continue;
}