#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <smrpg_health>

#define UPGRADE_SHORTNAME "regen"

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Health regeneration",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Regeneration upgrade for SM:RPG. Regenerates HP every second.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
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
		SMRPG_RegisterUpgradeType("Regeneration", UPGRADE_SHORTNAME, 15, true, 5, 5, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
}

public OnMapStart()
{
	CreateTimer(1.0, Timer_IncreaseHealth, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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
	return false;
}

public Action:Timer_IncreaseHealth(Handle:timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	new bool:bBotEnable = SMRPG_IgnoreBots();
	
	new iLevel;
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		// Are bots allowed to use this upgrade?
		if(!bBotEnable && IsFakeClient(i))
			continue;
		
		// Player didn't buy this upgrade yet.
		iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			continue;
		
		new iNewHealth = GetClientHealth(i)+iLevel;
		new iMaxHealth = GetClientMaxHealth(i);
		// Limit the regeneration to the maxhealth.
		if(iNewHealth > iMaxHealth)
			SetEntityHealth(i, iMaxHealth);
		else
			SetEntityHealth(i, iNewHealth);
	}
	
	return Plugin_Continue;
}

GetClientMaxHealth(client)
{
	// Use Health+ maxlevel, if available.
	if(GetFeatureStatus(FeatureType_Native, "SMRPG_Health_GetMaxHealth") == FeatureStatus_Available)
		return SMRPG_Health_GetMaxHealth(client);
	
	return GetEntProp(client, Prop_Data, "m_iMaxHealth");
}