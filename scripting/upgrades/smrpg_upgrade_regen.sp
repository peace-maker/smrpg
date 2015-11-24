#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <smrpg_health>

#define UPGRADE_SHORTNAME "regen"

#define PLUGIN_VERSION "1.0"

new Handle:g_hAmount;
new Handle:g_hAmountIncrease;
new Handle:g_hInterval;
new Handle:g_hIntervalDecrease;

new Handle:g_hRegenerationTimer[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Health regeneration",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Regeneration upgrade for SM:RPG. Regenerates HP every second.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
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
		SMRPG_RegisterUpgradeType("HP Regeneration", UPGRADE_SHORTNAME, "Regenerates HP regularly.", 15, true, 5, 5, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hAmount = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_amount", "1", "Specify the base amount of HP which is regenerated at the first level.", 0, true, 0.1);
		g_hAmountIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_amount_inc", "1", "Additional HP to regenerate each interval multiplied by level. (base + inc * (level-1))", 0, true, 0.0);
		g_hInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_interval", "1.0", "Specify the base interval rate at which HP is regenerated in seconds at the first level.", 0, true, 0.1);
		g_hIntervalDecrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_regen_interval_dec", "0.0", "How much is the base interval reduced for each level?", 0, true, 0.0);
	}
}

public OnClientDisconnect(client)
{
	ClearHandle(g_hRegenerationTimer[client]);
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	// Change timer interval to correct interval for new level.
	ClearHandle(g_hRegenerationTimer[client]);
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	new Float:fInterval = GetConVarFloat(g_hInterval) - GetConVarFloat(g_hIntervalDecrease) * (iLevel - 1);
	g_hRegenerationTimer[client] = CreateTimer(fInterval, Timer_IncreaseHealth, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

public Action:Timer_IncreaseHealth(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;

	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(SMRPG_IgnoreBots() && IsFakeClient(client))
		return Plugin_Continue;
		
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
		
	new iOldHealth = GetClientHealth(client);
	new iMaxHealth = SMRPG_Health_GetClientMaxHealth(client);
	// Don't reset the health, if the player gained more by other means.
	if(iOldHealth >= iMaxHealth)
		return Plugin_Continue;
		
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	new iIncrease = GetConVarInt(g_hAmount) + GetConVarInt(g_hAmountIncrease) * (iLevel - 1);
	new iNewHealth = iOldHealth + iIncrease;
	// Limit the regeneration to the maxhealth.
	if(iNewHealth > iMaxHealth)
		iNewHealth = iMaxHealth;
		
	SetEntityHealth(client, iNewHealth);
	
	return Plugin_Continue;
}