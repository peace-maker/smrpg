#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>
#include <smlib>

#define UPGRADE_SHORTNAME "icestab"
#define PLUGIN_VERSION "1.0"

#define KNIFE_SLOT 2

#define ICESTAB_CLRFADE 1 /* Blue color fade amount for each frame */

new Handle:g_hCVIceStabLimitDmg;
new Handle:g_hCVTimeIncrease;
new Handle:g_hCVWeapon;
new Handle:g_hCVMinDamage;

new Handle:g_hIceStabUnfreeze[MAXPLAYERS+1] = {INVALID_HANDLE,...};
new g_iIceStabFade[MAXPLAYERS+1] = {255,...};

new g_iFreezeSoundCount;
new g_iLimitDmgSoundCount;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Ice Stab",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Ice Stab upgrade for SM:RPG. Freeze a player in place when knifing him.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	HookEvent("player_spawn", Event_OnResetEffect);
	HookEvent("player_death", Event_OnResetEffect);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	SMRPG_GC_CheckSharedMaterialsAndSounds();
	
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
		SMRPG_RegisterUpgradeType("Ice Stab", UPGRADE_SHORTNAME, "Freeze a player in place when knifing him.", 10, true, 20, 30, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Sounds, true);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVIceStabLimitDmg = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icestab_limit_dmg", "10", "Maximum damage that can be done upon icestabbed victims (0 = disable)", 0, true, 0.0);
		g_hCVTimeIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icestab_inc", "1.0", "IceStab freeze duration increase for each level", 0, true, 0.1);
		g_hCVWeapon = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icestab_weapon", "knife", "Entity name of the weapon which should trigger the effect. (e.g. knife)");
		g_hCVMinDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icestab_min_dmg", "50.0", "Minimum damage with the weapon to trigger the effect. (Secondary knife attack is 50+ damage in CS:S)", 0, true, 0.0);
	}
}

public OnMapStart()
{
	g_iFreezeSoundCount = 0;
	decl String:sKey[64];
	for(;;g_iFreezeSoundCount++)
	{
		Format(sKey, sizeof(sKey), "SoundIceStabFreeze%d", g_iFreezeSoundCount+1);
		if(!SMRPG_GC_PrecacheSound(sKey))
			break;
	}
	
	g_iLimitDmgSoundCount = 0;
	for(;;g_iLimitDmgSoundCount++)
	{
		Format(sKey, sizeof(sKey), "SoundIceStabLimitDmg%d", g_iLimitDmgSoundCount+1);
		if(!SMRPG_GC_PrecacheSound(sKey))
			break;
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	SMRPG_ResetEffect(client);
}

// Fade players from blue linearly back to default color when they got hit by icestab.
public OnGameFrame()
{
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(g_iIceStabFade[i] < 255)
		{
			g_iIceStabFade[i] += ICESTAB_CLRFADE;
			if(g_iIceStabFade[i] > 255)
				g_iIceStabFade[i] = 255;
			
			SetEntityRenderMode(i, RENDER_TRANSCOLOR);
			Entity_SetRenderColor(i, g_iIceStabFade[i], g_iIceStabFade[i], 255, -1);
		}
	}
}

/**
 * Event callbacks
 */
public Event_OnResetEffect(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;

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
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0 && g_hIceStabUnfreeze[client] != INVALID_HANDLE;
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	if(g_hIceStabUnfreeze[client] != INVALID_HANDLE && IsClientInGame(client))
		TriggerTimer(g_hIceStabUnfreeze[client]);
	ClearHandle(g_hIceStabUnfreeze[client]);
	g_iIceStabFade[client] = 254;
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
 * Hook callbacks
 */
// Reduce the damage when a player is frozen.
public Action:Hook_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon,	Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	// This player isn't frozen. Ignore.
	if(g_hIceStabUnfreeze[victim] == INVALID_HANDLE)
		return Plugin_Continue;
	
	// Limit disabled?
	new Float:fLimitDmg = GetConVarFloat(g_hCVIceStabLimitDmg);
	if(fLimitDmg <= 0.0)
		return Plugin_Continue;
	
	new iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	// All weapons except for the knife do less damage.
	// TODO: Add support for more games
	if(attacker <= 0 || attacker > MaxClients || GetPlayerWeaponSlot(attacker, KNIFE_SLOT) == iWeapon)
		return Plugin_Continue;
	
	// This was less than the limit. It's ok.
	if(damage <= fLimitDmg)
		return Plugin_Continue;
	
	// Limit the damage!
	damage = fLimitDmg;
	
	if(g_iLimitDmgSoundCount > 0)
	{
		new String:sKey[64];
		Format(sKey, sizeof(sKey), "SoundIceStabLimitDmg%d", Math_GetRandomInt(1, g_iLimitDmgSoundCount));
		SMRPG_EmitSoundToAllEnabled(UPGRADE_SHORTNAME, SMRPG_GC_GetKeyValue(sKey), victim, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, victim);
	}
	
	return Plugin_Changed;
}

public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
		return;
	
	if(damage < GetConVarFloat(g_hCVMinDamage))
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
	
	if(g_hIceStabUnfreeze[attacker] != INVALID_HANDLE)
		return; /* don't allow frozen attacker to icestab */
	
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	new iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return;
	
	decl String:sWeapon[256], String:sTargetWeapon[128];
	GetConVarString(g_hCVWeapon, sTargetWeapon, sizeof(sTargetWeapon));
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	ReplaceString(sWeapon, sizeof(sWeapon), "weapon_", "", false);
	
	// This effect only applies to the specified weapon.
	if(StrContains(sWeapon, sTargetWeapon) == -1)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Freeze the player.
	// Note: This won't reset his velocity. Useful for surf maps.
	SetEntityMoveType(victim, MOVETYPE_NONE);
	
	if(g_iFreezeSoundCount > 0)
	{
		new String:sKey[64];
		Format(sKey, sizeof(sKey), "SoundIceStabFreeze%d", Math_GetRandomInt(1, g_iFreezeSoundCount));
		SMRPG_EmitSoundToAllEnabled(UPGRADE_SHORTNAME, SMRPG_GC_GetKeyValue(sKey), victim, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, victim);
	}

	if(SMRPG_ClientWantsCosmetics(victim, UPGRADE_SHORTNAME, SMRPG_FX_Visuals))
	{
		SetEntityRenderMode(victim, RENDER_TRANSCOLOR);
		Entity_SetRenderColor(victim, 0, 0, 255, -1);
		g_iIceStabFade[victim] = 0;
	}
	
	ClearHandle(g_hIceStabUnfreeze[victim]);
	g_hIceStabUnfreeze[victim] = CreateTimer(GetConVarFloat(g_hCVTimeIncrease)*float(iLevel), Timer_Unfreeze, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_Unfreeze(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hIceStabUnfreeze[client] = INVALID_HANDLE;
	if(GetEntityMoveType(client) == MOVETYPE_NONE)
		SetEntityMoveType(client, MOVETYPE_WALK);
	g_iIceStabFade[client] = 254;
	return Plugin_Stop;
}