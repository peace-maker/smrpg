#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "fnade"
#define PLUGIN_VERSION "1.0"

/* Ignite duration increase for every level */
#define FNADE_INC 2
#define FNADE_DMG_MIN 5.0

new Handle:g_hExtinguishTimer[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Fire Grenade",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Fire Grenade upgrade for SM:RPG. Ignites players damaged by your grenade.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	HookEvent("player_spawn", Event_OnEffectReset);
	HookEvent("player_death", Event_OnEffectReset);
	
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
		SMRPG_RegisterUpgradeType("Fire Grenade", UPGRADE_SHORTNAME, "Ignites players damaged by your grenade.", 10, true, 5, 15, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	SMRPG_ResetEffect(client);
	ClearHandle(g_hExtinguishTimer[client]);
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

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	if(g_hExtinguishTimer[client] != INVALID_HANDLE && IsClientInGame(client))
		TriggerTimer(g_hExtinguishTimer[client]);
	ClearHandle(g_hExtinguishTimer[client]);
	g_hExtinguishTimer[client] = CreateTimer(0.2, Timer_Extinguish, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
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
	if(damage < FNADE_DMG_MIN)
		return;
	
	decl String:sWeapon[40];
	
	// Only counts for hegrenades
	if(inflictor > 0 
	&& IsValidEdict(inflictor) 
	&& GetEntityClassname(inflictor, sWeapon, sizeof(sWeapon))
	&& StrContains(sWeapon, "hegrenade") == -1)
		return;
	
	// This player is already burning.
	if(g_hExtinguishTimer[victim] != INVALID_HANDLE)
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
	
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Float:fDuration = float(iLevel)*FNADE_INC;
	IgniteEntity(victim, fDuration);
	g_hExtinguishTimer[victim] = CreateTimer(fDuration, Timer_Extinguish, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_Extinguish(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hExtinguishTimer[client] = INVALID_HANDLE;
	
	ExtinguishEntity(client);
	// Extinguish the ragdoll too!
	if(!IsPlayerAlive(client))
	{
		new iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if(iRagdoll > 0)
			ExtinguishEntity(iRagdoll);
	}
	
	return Plugin_Stop;
}