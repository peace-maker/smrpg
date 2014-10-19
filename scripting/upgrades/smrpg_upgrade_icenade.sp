#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "icenade"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVLimitDmg;
new Handle:g_hCVDurationIncrease;
new Handle:g_hCVMinDamage;
new Handle:g_hCVWeapon;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Ice Grenade",
	author = "Peace-Maker",
	description = "Ice Grenade upgrade for SM:RPG. Freeze a player in place when damaged by your grenade.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
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
		SMRPG_RegisterUpgradeType("Ice Grenade", UPGRADE_SHORTNAME, "Freeze a player in place when damaged by your grenade.", 10, true, 5, 15, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Sounds, true);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVLimitDmg = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icenade_limit_dmg", "10", "Maximum damage that can be done upon frozen victims (0 = disable)", 0, true, 0.0);
		g_hCVDurationIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icenade_inc", "1.0", "Freeze duration increase in seconds for every level", _, true, 0.1);
		g_hCVMinDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icenade_mindmg", "10.0", "Minimum damage done with the grenade to trigger the effect", _, true, 0.0);
		g_hCVWeapon = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icenade_weapon", "hegrenade", "Entity name of the weapon which should trigger the effect. (e.g. hegrenade)");
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
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
	// TODO: Differenciate if we froze the client ourself
	return SMRPG_IsClientFrozen(client);
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	if(SMRPG_IsClientFrozen(client))
		SMRPG_UnfreezeClient(client);
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

/**
 * Event callbacks
 */
public Event_OnEffectReset(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	SMRPG_ResetEffect(client);
}

/**
 * Hook callbacks
 */
public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;
	
	// Enough damage?
	if(damage < GetConVarFloat(g_hCVMinDamage))
		return;
	
	decl String:sWeapon[256], String:sTargetWeapon[128];
	GetConVarString(g_hCVWeapon, sTargetWeapon, sizeof(sTargetWeapon));
	
	// Only counts for the weapons in the cvar
	if(inflictor > 0 
	&& IsValidEdict(inflictor) 
	&& GetEntityClassname(inflictor, sWeapon, sizeof(sWeapon))
	&& StrContains(sWeapon, sTargetWeapon) == -1)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	if(SMRPG_IsClientFrozen(attacker))
		return; /* don't allow frozen attacker to freeze others */
	
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Float:fDuration = float(iLevel)*GetConVarFloat(g_hCVDurationIncrease);
	SMRPG_FreezeClient(victim, fDuration, GetConVarFloat(g_hCVLimitDmg), UPGRADE_SHORTNAME);
}