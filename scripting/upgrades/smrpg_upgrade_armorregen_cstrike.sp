#pragma semicolon 1
#include <sourcemod>
#include <smlib>

#pragma newdecls required
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <smrpg_armorplus>

#define UPGRADE_SHORTNAME "armorregen"

#define PLUGIN_VERSION "1.0"

ConVar g_hCVAmount;
ConVar g_hCVAmountIncrease;
ConVar g_hCVInterval;
ConVar g_hCVIntervalDecrease;
ConVar g_hCVGiveHelmet;

Handle g_hRegenerationTimer[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Armor regeneration",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Armor regeneration upgrade for SM:RPG. Regenerates armor regularly.",
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
	return APLRes_Success;
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
		SMRPG_RegisterUpgradeType("Armor regeneration", UPGRADE_SHORTNAME, "Regenerates armor regularly.", 15, true, 5, 5, 10);
		SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVAmount = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_amount", "1", "Specify the base amount of armor which is regenerated at the first level.", 0, true, 0.1);
		g_hCVAmountIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_amount_inc", "1", "Additional armor to regenerate each interval multiplied by level. (base + inc * (level-1))", 0, true, 0.0);
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_interval", "1.0", "Specify the base interval rate at which armor is regenerated in seconds at the first level.", 0, true, 0.1);
		g_hCVIntervalDecrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_interval_dec", "0.0", "How much is the base interval reduced for each level?", 0, true, 0.0);
		g_hCVGiveHelmet = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_give_helmet", "1", "Give players helmet after they regenerated to 100% of their armor?", 0, true, 0.0, true, 1.0);
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
	g_hRegenerationTimer[client] = CreateTimer(fInterval, Timer_IncreaseArmor, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

public Action Timer_IncreaseArmor(Handle timer, any userid)
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
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	int iMaxArmor = SMRPG_Armor_GetClientMaxArmor(client);
	int iCurrentArmor = GetClientArmor(client);
	
	// He already is regenerated completely.
	if(iCurrentArmor >= iMaxArmor)
	{
		// Give him an helmet now.
		if (g_hCVGiveHelmet.BoolValue && !GetEntProp(client, Prop_Send, "m_bHasHelmet"))
			SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
		return Plugin_Continue;
	}
	
	int iIncrease = g_hCVAmount.IntValue + g_hCVAmountIncrease.IntValue * (iLevel - 1);
	int iNewArmor = iCurrentArmor + iIncrease;
	if(iNewArmor > iMaxArmor)
		iNewArmor = iMaxArmor;
	SetEntProp(client, Prop_Send, "m_ArmorValue", iNewArmor);
	
	return Plugin_Continue;
}