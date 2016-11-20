#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "fnade"
#define PLUGIN_VERSION "1.0"

ConVar g_hCVDurationIncrease;
ConVar g_hCVMinDamage;
ConVar g_hCVWeapon;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Fire Grenade",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Fire Grenade upgrade for SM:RPG. Ignites players damaged by your grenade.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
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
		SMRPG_RegisterUpgradeType("Fire Grenade", UPGRADE_SHORTNAME, "Ignites players damaged by your grenade.", 10, true, 5, 15, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVDurationIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fnade_inc", "2", "Ignite duration increase in seconds for every level", _, true, 0.1);
		g_hCVMinDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fnade_mindmg", "5.0", "Minimum damage done with the grenade to trigger the effect", _, true, 0.0);
		g_hCVWeapon = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fnade_weapon", "hegrenade", "Entity name of the weapon which should trigger the effect. (e.g. hegrenade flashbang)");
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

/**
 * SM:RPG Upgrade callbacks
 */
public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
	// Nothing to apply here immediately after someone buys this upgrade.
}

public bool SMRPG_ActiveQuery(int client)
{
	return SMRPG_IsClientBurning(client);
}

// Some plugin wants this effect to end?
public void SMRPG_ResetEffect(int client)
{
	if(SMRPG_IsClientBurning(client))
		SMRPG_ExtinguishClient(client);
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

/**
 * Hook callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;
	
	// Enough damage?
	if(damage < g_hCVMinDamage.FloatValue)
		return;
	
	char sWeapon[256], sTargetWeapon[128];
	g_hCVWeapon.GetString(sTargetWeapon, sizeof(sTargetWeapon));
	
	// Only counts for hegrenades
	if(inflictor > 0 
	&& IsValidEdict(inflictor) 
	&& GetEntityClassname(inflictor, sWeapon, sizeof(sWeapon))
	&& StrContains(sWeapon, sTargetWeapon) == -1)
		return;
	
	// This player is already burning.
	if(SMRPG_IsClientBurning(victim))
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return; // Some other plugin doesn't want this effect to run
	
	float fDuration = float(iLevel)*g_hCVDurationIncrease.FloatValue;
	SMRPG_IgniteClient(victim, fDuration, UPGRADE_SHORTNAME, true, attacker);
}