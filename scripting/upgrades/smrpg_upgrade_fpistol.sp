#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "fpistol"
#define PLUGIN_VERSION "1.0"

#define FPISTOL_INC 0.1 /* FrostPistol speed time increase for each level */

#define PISTOL_SLOT 1

new Float:g_fFPistolLastSpeed[MAXPLAYERS+1];
new Handle:g_hFPistolResetSpeed[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Frost Pistol",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Frost Pistol upgrade for SM:RPG. Slow down players hit with a pistol.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	HookEvent("player_spawn", Event_OnResetEffect);
	HookEvent("player_death", Event_OnResetEffect);

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
		SMRPG_RegisterUpgradeType("Frost Pistol", UPGRADE_SHORTNAME, 10, true, 10, 20, 15, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnMapStart()
{
	PrecacheSound("physics/surfaces/tile_impact_bullet1.wav", true);
	PrecacheSound("physics/surfaces/tile_impact_bullet2.wav", true);
	PrecacheSound("physics/surfaces/tile_impact_bullet3.wav", true);
	PrecacheSound("physics/surfaces/tile_impact_bullet4.wav", true);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	SMRPG_ResetEffect(client);
}

/**
 * Event callbacks
 */
public Event_OnResetEffect(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	SMRPG_ResetEffect(client);
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
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0 && g_hFPistolResetSpeed[client] != INVALID_HANDLE;
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	if(g_hFPistolResetSpeed[client] != INVALID_HANDLE && IsClientInGame(client))
		TriggerTimer(g_hFPistolResetSpeed[client]);
	ClearHandle(g_hFPistolResetSpeed[client]);
}

public SMRPG_TranslateUpgrade(client, String:translation[], maxlen)
{
	Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
}

/**
 * SM:RPG public callbacks
 */
public Action:SMRPG_OnUpgradeEffect(client, const String:shortname[])
{
	// We only care for the impulse effect
	if(!StrEqual(shortname, "impulse"))
		return Plugin_Continue;
	
	// This client isn't slowed down by the frostpistol. Allow impulse to apply its effect.
	if(g_hFPistolResetSpeed[client] == INVALID_HANDLE)
		return Plugin_Continue;
	
	// Frostpistol is active. Block impulse.
	return Plugin_Handled;
}

/**
 * Hook callbacks
 */
public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
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
	
	// This effect only applies to pistols.
	if(GetPlayerWeaponSlot(attacker, PISTOL_SLOT) != weapon)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Don't have impulse going wonky
	SMRPG_ResetUpgradeEffectOnClient(victim, "impulse");
	
	new Float:fOldLaggedMovementValue = GetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue");
	
	// The more damage done, the slower the player gets.
	// TODO: Add config option to set this slowdown rate per weapon.
	new Float:fSpeed = damage / 100.0;
	if(fSpeed > 0.9)
		fSpeed = 0.9;
	
	if(g_hFPistolResetSpeed[victim] == INVALID_HANDLE)
	{
		g_fFPistolLastSpeed[victim] = fSpeed;
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", fSpeed);
	}
	else
	{
		// Player got shot by a different player with higher damage before?
		if(g_fFPistolLastSpeed[victim] > fSpeed)
		{
			g_fFPistolLastSpeed[victim] = fSpeed;
			SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", fSpeed);
		}
	}
	
	// Emit some icy sound
	// TODO: Make this game independant
	decl String:sSound[PLATFORM_MAX_PATH];
	Format(sSound, sizeof(sSound), "physics/surfaces/tile_impact_bullet%d.wav", GetRandomInt(1, 4));
	EmitSoundToAll(sSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8, SNDPITCH_NORMAL, victim);
	
	ClearHandle(g_hFPistolResetSpeed[victim]);
	
	new Handle:hData;
	g_hFPistolResetSpeed[victim] = CreateDataTimer(float(iLevel)*FPISTOL_INC, Timer_ResetSpeed, hData, TIMER_FLAG_NO_MAPCHANGE);
	WritePackCell(hData, GetClientUserId(victim));
	WritePackFloat(hData, fOldLaggedMovementValue);
	ResetPack(hData);
}

public Action:Timer_ResetSpeed(Handle:timer, any:data)
{
	new userid = ReadPackCell(data);
	new Float:fOldLaggedMovementValue = ReadPackFloat(data);
	
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hFPistolResetSpeed[client] = INVALID_HANDLE;
	
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", fOldLaggedMovementValue);
	
	return Plugin_Stop;
}