#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "icenade"

ConVar g_hCVLimitDmg;
ConVar g_hCVDurationIncrease;
ConVar g_hCVMinDamage;
ConVar g_hCVWeapon;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Ice Grenade",
	author = "Peace-Maker",
	description = "Ice Grenade upgrade for SM:RPG. Freeze a player in place when damaged by your grenade.",
	version = SMRPG_VERSION,
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
		SMRPG_RegisterUpgradeType("Ice Grenade", UPGRADE_SHORTNAME, "Freeze a player in place when damaged by your grenade.", 0, true, 5, 15, 10);
		SMRPG_SetUpgradeActiveQueryCallback(UPGRADE_SHORTNAME, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Sounds, true);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		// Still read this, but deprecate it for new installs. Use the freeze_limit_damage.cfg now.
		g_hCVLimitDmg = CreateConVar("smrpg_icenade_limit_dmg", "10", "Maximum damage that can be done upon frozen victims (0 = disable)", 0, true, 0.0);
		g_hCVDurationIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icenade_inc", "1.0", "Freeze duration increase in seconds for every level", _, true, 0.1);
		g_hCVMinDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icenade_mindmg", "10.0", "Minimum damage done with the grenade to trigger the effect", _, true, 0.0);
		g_hCVWeapon = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icenade_weapon", "hegrenade", "Entity name of the weapon which should trigger the effect. (e.g. hegrenade)");
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

/**
 * SM:RPG Upgrade callbacks
 */
public bool SMRPG_ActiveQuery(int client)
{
	// TODO: Differenciate if we froze the client ourself
	return SMRPG_IsClientFrozen(client);
}

// Some plugin wants this effect to end?
public void SMRPG_ResetEffect(int client)
{
	if(SMRPG_IsClientFrozen(client))
		SMRPG_UnfreezeClient(client);
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
 * Event callbacks
 */
public void Event_OnEffectReset(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	SMRPG_ResetEffect(client);
}

/**
 * Hook callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients)
		return;
	
	// Enough damage?
	if(damage < g_hCVMinDamage.FloatValue)
		return;
	
	char sWeapon[256], sTargetWeapon[128];
	g_hCVWeapon.GetString(sTargetWeapon, sizeof(sTargetWeapon));
	
	// Only counts for the weapons in the cvar
	if(inflictor > 0 
	&& IsValidEdict(inflictor) 
	&& GetEntityClassname(inflictor, sWeapon, sizeof(sWeapon))
	&& StrContains(sWeapon, sTargetWeapon) == -1)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	if(SMRPG_IsClientFrozen(attacker))
		return; /* don't allow frozen attacker to freeze others */
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return; // Some other plugin doesn't want this effect to run
	
	float fDuration = float(iLevel)*g_hCVDurationIncrease.FloatValue;
	SMRPG_FreezeClient(victim, fDuration, g_hCVLimitDmg.FloatValue, UPGRADE_SHORTNAME);
}