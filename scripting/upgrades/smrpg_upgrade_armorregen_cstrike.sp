#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <smrpg_armorplus>

#define UPGRADE_SHORTNAME "armorregen"

#define PLUGIN_VERSION "1.0"

new Handle:g_hAmount;
new Handle:g_hAmountIncrease;
new Handle:g_hInterval;
new Handle:g_hIntervalDecrease;
new Handle:g_hCVGiveHelmet;

new Handle:g_hRegenerationTimer[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Armor regeneration",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Armor regeneration upgrade for SM:RPG. Regenerates armor regularly.",
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
	return APLRes_Success;
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
		SMRPG_RegisterUpgradeType("Armor regeneration", UPGRADE_SHORTNAME, "Regenerates armor regularly.", 15, true, 5, 5, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hAmount = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_amount", "1", "Specify the base amount of armor which is regenerated at the first level.", 0, true, 0.1);
		g_hAmountIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_amount_inc", "1", "Additional armor to regenerate each interval multiplied by level. (base + inc * (level-1))", 0, true, 0.0);
		g_hInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_interval", "1.0", "Specify the base interval rate at which armor is regenerated in seconds at the first level.", 0, true, 0.1);
		g_hIntervalDecrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_interval_dec", "0.0", "How much is the base interval reduced for each level?", 0, true, 0.0);
		g_hCVGiveHelmet = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_give_helmet", "1", "Give players helmet after they regenerated to 100% of their armor?", 0, true, 0.0, true, 1.0);
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
	g_hRegenerationTimer[client] = CreateTimer(fInterval, Timer_IncreaseArmor, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

public Action:Timer_IncreaseArmor(Handle:timer, any:userid)
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
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	new iMaxArmor = SMRPG_Armor_GetClientMaxArmor(client);
	new iCurrentArmor = GetClientArmor(client);
	
	// He already is regenerated completely.
	if(iCurrentArmor >= iMaxArmor)
	{
		// Give him an helmet now.
		if (GetConVarBool(g_hCVGiveHelmet) && !GetEntProp(client, Prop_Send, "m_bHasHelmet"))
			SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
		return Plugin_Continue;
	}
	
	new iIncrease = GetConVarInt(g_hAmount) + GetConVarInt(g_hAmountIncrease) * (iLevel - 1);
	new iNewArmor = iCurrentArmor + iIncrease;
	if(iNewArmor > iMaxArmor)
		iNewArmor = iMaxArmor;
	SetEntProp(client, Prop_Send, "m_ArmorValue", iNewArmor);
	
	return Plugin_Continue;
}