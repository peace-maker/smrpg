#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <smrpg_armorplus>

#define UPGRADE_SHORTNAME "armorregen"

#define PLUGIN_VERSION "1.0"

new Handle:g_hCVGiveHelmet;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Armor regeneration",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Armor regeneration upgrade for SM:RPG. Regenerates armor every second.",
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
		SMRPG_RegisterUpgradeType("Armor regeneration", UPGRADE_SHORTNAME, "Regenerates armor every second.", 15, true, 5, 5, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVGiveHelmet = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorregen_give_helmet", "1", "Give players helmet after they regenerated to 100% of their armor?", 0, true, 0.0, true, 1.0);
	}
}

public OnMapStart()
{
	CreateTimer(1.0, Timer_IncreaseArmor, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	// Nothing to apply here immediately after someone buys this upgrade.
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

public Action:Timer_IncreaseArmor(Handle:timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	new bool:bIgnoreBots = SMRPG_IgnoreBots();
	
	new iLevel, iMaxArmor, iCurrentArmor, iNewArmor;
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		// Are bots allowed to use this upgrade?
		if(bIgnoreBots && IsFakeClient(i))
			continue;
		
		// Player didn't buy this upgrade yet.
		iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			continue;
		
		if(!SMRPG_RunUpgradeEffect(i, UPGRADE_SHORTNAME))
			continue; // Some other plugin doesn't want this effect to run
		
		iMaxArmor = SMRPG_Armor_GetClientMaxArmor(i);
		iCurrentArmor = GetClientArmor(i);
		
		// He already is regenerated completely.
		if(iCurrentArmor >= iMaxArmor)
		{
			// Give him an helmet now.
			if (GetConVarBool(g_hCVGiveHelmet) && !GetEntProp(i, Prop_Send, "m_bHasHelmet"))
				SetEntProp(i, Prop_Send, "m_bHasHelmet", 1);
			continue;
		}
		
		iNewArmor = iCurrentArmor+iLevel;
		if(iNewArmor > iMaxArmor)
			iNewArmor = iMaxArmor;
		SetEntProp(i, Prop_Send, "m_ArmorValue", iNewArmor);
	}
	
	return Plugin_Continue;
}