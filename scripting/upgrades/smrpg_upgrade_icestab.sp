#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "icestab"
#define PLUGIN_VERSION "1.0"

#define KNIFE_SLOT 2

#define ICESTAB_INC 1.0 /* IceStab freeze duration increase for each level */
#define ICESTAB_DMG_MIN 50.0 /* Secondary knife attack is 50+ damage */
#define ICESTAB_CLRFADE 1 /* Blue color fade amount for each frame */

new Handle:g_hCVIceStabLimitDmg;

new Handle:g_hIceStabUnfreeze[MAXPLAYERS+1] = {INVALID_HANDLE,...};
new g_iIceStabFade[MAXPLAYERS+1] = {255,...};

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Ice Stab",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Impulse upgrade for SM:RPG. Gain speed shortly when being shot.",
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
		SMRPG_RegisterUpgradeType("Ice Stab", UPGRADE_SHORTNAME, 10, true, 20, 30, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVIceStabLimitDmg = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_icestab_limit_dmg", "10", "Maximum damage that can be done upon icestabbed victims (0 = disable)", 0, true, 0.0);
	}
}

public OnMapStart()
{
	PrecacheSound("physics/glass/glass_impact_bullet1.wav", true);
	PrecacheSound("physics/glass/glass_impact_bullet2.wav", true);
	PrecacheSound("physics/glass/glass_impact_bullet3.wav", true);
	PrecacheSound("physics/glass/glass_sheet_impact_hard1.wav", true);
	PrecacheSound("physics/glass/glass_sheet_impact_hard2.wav", true);
	PrecacheSound("physics/glass/glass_sheet_impact_hard3.wav", true);
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
	g_iIceStabFade[client] = 255;
}

public SMRPG_TranslateUpgrade(client, String:translation[], maxlen)
{
	Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
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
	
	// All weapons except for the knife do less damage.
	// TODO: Add support for more games
	if(attacker <= 0 || attacker > MaxClients || GetPlayerWeaponSlot(attacker, KNIFE_SLOT) == weapon)
		return Plugin_Continue;
	
	// This was less than the limit. It's ok.
	if(damage <= fLimitDmg)
		return Plugin_Continue;
	
	// Limit the damage!
	damage = fLimitDmg;
	
	decl String:sSound[PLATFORM_MAX_PATH];
	Format(sSound, sizeof(sSound), "physics/glass/glass_sheet_impact_hard%d.wav", GetRandomInt(1, 3));
	EmitSoundToAll(sSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, victim);
	
	return Plugin_Changed;
}

public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;
	
	if(damage < ICESTAB_DMG_MIN)
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
	
	// This effect only applies to knifes.
	// TODO: Add support for more games
	if(GetPlayerWeaponSlot(attacker, KNIFE_SLOT) != weapon)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Freeze the player.
	// Note: This won't reset his velocity. Useful for surf maps.
	SetEntityMoveType(victim, MOVETYPE_NONE);
	
	decl String:sSound[PLATFORM_MAX_PATH];
	Format(sSound, sizeof(sSound), "physics/glass/glass_impact_bullet%d.wav", GetRandomInt(1, 3));
	EmitSoundToAll(sSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, victim);

	SetEntityRenderMode(victim, RENDER_TRANSCOLOR);
	Entity_SetRenderColor(victim, 0, 0, 255, -1);
	
	ClearHandle(g_hIceStabUnfreeze[victim]);
	g_iIceStabFade[victim] = 0;
	g_hIceStabUnfreeze[victim] = CreateTimer(float(iLevel), Timer_Unfreeze, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_Unfreeze(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hIceStabUnfreeze[client] = INVALID_HANDLE;
	if(GetEntityMoveType(client) == MOVETYPE_NONE)
		SetEntityMoveType(client, MOVETYPE_WALK);
	
	return Plugin_Stop;
}