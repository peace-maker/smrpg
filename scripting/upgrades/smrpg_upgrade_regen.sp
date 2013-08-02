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
	// This is a passive effect, so it's always active, if the player got at least level 1
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
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
		new iMaxHealth = SMRPG_Health_GetClientMaxHealth(i);
		// Limit the regeneration to the maxhealth.
		if(iNewHealth > iMaxHealth)
			SetEntityHealth(i, iMaxHealth);
		else
			SetEntityHealth(i, iNewHealth);
	}
	
	return Plugin_Continue;
}