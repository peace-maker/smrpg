#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "impulse"
#define PLUGIN_VERSION "1.0"

/**
 * @brief Speed increase for each level when player is damaged.
 */
#define IMPULSE_INC 0.2

/**
 * @brief Duration of Impulse's effect.
 */
#define IMPULSE_DURATION 0.8

new Handle:g_hImpulseResetSpeed[MAXPLAYERS+1] = {INVALID_HANDLE,...};
new g_iImpulseTrailSprites[MAXPLAYERS+1] = {-1,...};

new g_iRedTrailSprite = -1;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Impulse",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Impulse upgrade for SM:RPG. Gain speed shortly when being shot.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	HookEvent("round_start", Event_OnRoundStart);
	HookEvent("player_spawn", Event_OnEffectReset);
	HookEvent("player_death", Event_OnEffectReset);
	
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
		SMRPG_RegisterUpgradeType("Impulse", UPGRADE_SHORTNAME, "Gain speed for a short time when being shot.", 10, true, 5, 20, 20, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnMapStart()
{
	g_iRedTrailSprite = PrecacheModel("sprites/combineball_trail_red_1.vmt", true);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	SMRPG_ResetEffect(client);
	if(g_iImpulseTrailSprites[client] != -1 && IsValidEntity(g_iImpulseTrailSprites[client]))
		AcceptEntityInput(g_iImpulseTrailSprites[client], "Kill");
	g_iImpulseTrailSprites[client] = -1;
}

/**
 * Event callbacks
 */
public Event_OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Reset all invisible entity indexes since the previous round's entities were all deleted on round start.
	for(new i=1;i<=MaxClients;i++)
		g_iImpulseTrailSprites[i] = -1;
}

public Event_OnEffectReset(Handle:event, const String:name[], bool:dontBroadcast)
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
	// This is a passive effect, so it's always active, if the player got at least level 1
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0 && g_hImpulseResetSpeed[client] != INVALID_HANDLE;
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	if(g_hImpulseResetSpeed[client] != INVALID_HANDLE && IsClientInGame(client))
		TriggerTimer(g_hImpulseResetSpeed[client]);
	ClearHandle(g_hImpulseResetSpeed[client]);
}

public SMRPG_TranslateUpgrade(client, TranslationType:type, String:translation[], maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
		return;
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
	if(IsFakeClient(victim) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!(GetEntityFlags(victim) & FL_ONGROUND))
		return; //Player is in midair
	
	if(g_hImpulseResetSpeed[victim] != INVALID_HANDLE)
		return; //Player is already faster
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Float:fOldLaggedMovementValue = GetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue");
	
	/* Set player speed */
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", fOldLaggedMovementValue + float(iLevel) * IMPULSE_INC);
	
	new Handle:hData;
	g_hImpulseResetSpeed[victim] = CreateDataTimer(IMPULSE_DURATION, Timer_ResetSpeed, hData, TIMER_FLAG_NO_MAPCHANGE);
	WritePackCell(hData, GetClientUserId(victim));
	WritePackFloat(hData, fOldLaggedMovementValue);
	ResetPack(hData);
	
	decl Float:vOrigin[3];
	GetClientEyePosition(victim, vOrigin);
	vOrigin[2] -= 40.0;
	
	new iSprite = g_iImpulseTrailSprites[victim];
	if(iSprite == -1)
	{
		iSprite = CreateEntityByName("env_sprite");
		if(iSprite == -1)
			return;
		
		SetEntityRenderMode(iSprite, RENDER_NONE);
		TeleportEntity(iSprite, vOrigin, Float:{0.0,0.0,0.0}, NULL_VECTOR);
		DispatchSpawn(iSprite);
		
		g_iImpulseTrailSprites[victim] = iSprite;
	}
	
	TeleportEntity(iSprite, vOrigin, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(iSprite, "SetParent", victim);
	
	TE_SetupBeamFollow(iSprite, g_iRedTrailSprite, g_iRedTrailSprite, IMPULSE_DURATION, 10.0, 4.0, 2, {255,0,0,255});
	TE_SendToAll();
}

public Action:Timer_ResetSpeed(Handle:timer, any:data)
{
	new userid = ReadPackCell(data);
	new Float:fOldLaggedMovementValue = ReadPackFloat(data);
	
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hImpulseResetSpeed[client] = INVALID_HANDLE;
	
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", fOldLaggedMovementValue);
	
	if(g_iImpulseTrailSprites[client] != -1 && IsValidEntity(g_iImpulseTrailSprites[client]))
	{
		SetVariantString("");
		AcceptEntityInput(g_iImpulseTrailSprites[client], "SetParent"); //unset parent
	}
	
	return Plugin_Stop;
}