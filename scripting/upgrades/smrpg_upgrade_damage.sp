#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smrpg>

#define UPGRADE_SHORTNAME "damage"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVPercent;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Damage+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Damage+ upgrade for SM:RPG. Deal additional damage on enemies.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

	// Account for late loading
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
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
		SMRPG_RegisterUpgradeType("Damage+", UPGRADE_SHORTNAME, "Deal additional damage on enemies.", 10, true, 5, 5, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_damage_percent", "0.25", "Percentage of damage done the victim loses additionally (multiplied by level)", _, true, 0.0, true, 1.0);
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
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
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}

public SMRPG_TranslateUpgrade(client, TranslationType:type, String:translation[], maxlen)
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

/**
 * Hook callbacks
 */
public Action:Hook_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	// Ignore team attack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return Plugin_Continue;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	// Increase the damage
	damage += RoundToNearest(damage * GetConVarFloat(g_hCVPercent) * float(iLevel));
	return Plugin_Changed;
}
