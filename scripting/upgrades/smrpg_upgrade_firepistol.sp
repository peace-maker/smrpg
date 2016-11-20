#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "firepistol"
#define PLUGIN_VERSION "1.0"

ConVar g_hCVTimeIncrease;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Fire Pistol",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Fire Pistol upgrade for SM:RPG. Ignites players hit with a pistol.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

	// Account for late loading
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
		SMRPG_RegisterUpgradeType("Fire Pistol", UPGRADE_SHORTNAME, "Ignites players hit with a pistol.", 10, true, 10, 20, 15, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVTimeIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_firepistol_inc", "0.2", "How many seconds are players left burning multiplied by level?", 0, true, 0.0);
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
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients || !IsPlayerAlive(victim))
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// This player is already burning. Don't stack the effect and wait until he stopped to be able to burn him again.
	if(SMRPG_IsClientBurning(victim))
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
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return;
	
	// Only care for secondary weapons
	// TODO: Make more generic?
	if(iWeapon != GetPlayerWeaponSlot(attacker, 1))
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return; // Some other plugin doesn't want this effect to run
	
	float fTime = float(iLevel)*g_hCVTimeIncrease.FloatValue;
	SMRPG_IgniteClient(victim, fTime, UPGRADE_SHORTNAME, true, attacker);
}