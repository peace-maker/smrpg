#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smrpg_effects>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>
#include <smlib>

#define UPGRADE_SHORTNAME "impulse"
#define PLUGIN_VERSION "1.0"

// Config
new Handle:g_hCVDefaultSpeedIncrease;
new Handle:g_hCVDefaultDuration;

new Handle:g_hWeaponConfig;

enum WeaponConfig
{
	Float:Config_SpeedIncrease,
	Float:Config_Duration
};

new g_iImpulseTrailSprites[MAXPLAYERS+1] = {-1,...};

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
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	SMRPG_GC_CheckSharedMaterialsAndSounds();
	
	g_hWeaponConfig = CreateTrie();
	
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
		SMRPG_RegisterUpgradeType("Impulse", UPGRADE_SHORTNAME, "Gain speed for a short time when being shot.", 10, true, 5, 20, 20, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVDefaultSpeedIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_speed_inc", "0.2", "Speed increase for each level when player is damaged.", 0, true, 0.1);
		g_hCVDefaultDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_duration", "0.8", "Duration of Impulse's effect in seconds.", 0, true, 0.1);
	}
}

public OnMapStart()
{
	SMRPG_GC_PrecacheModel("SpriteRedTrail");
	
	if(!LoadWeaponConfig())
		LogError("Can't read config file in configs/smrpg/impulse_weapons.cfg!");
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

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	// Nothing to apply here immediately after someone buys this upgrade.
}

public bool:SMRPG_ActiveQuery(client)
{
	return SMRPG_IsClientLaggedMovementChanged(client, LMT_Faster, true);
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	SMRPG_ResetClientLaggedMovement(client, LMT_Faster);
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
 * SM:RPG Effect Hub callbacks
 */
public SMRPG_OnClientLaggedMovementReset(client, LaggedMovementType:type)
{
	if(type == LMT_Faster)
	{
		if(g_iImpulseTrailSprites[client] != -1 && IsValidEntity(g_iImpulseTrailSprites[client]))
		{
			SetVariantString("");
			AcceptEntityInput(g_iImpulseTrailSprites[client], "SetParent"); //unset parent
		}
	}
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
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!(GetEntityFlags(victim) & FL_ONGROUND))
		return; //Player is in midair
	
	if(SMRPG_IsClientLaggedMovementChanged(victim, LMT_Faster, true))
		return; //Player is already faster
	
	new iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	new String:sWeapon[256];
	if(iWeapon != -1)
		GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	
	// Upgrade disabled for this weapon?
	new Float:fSpeedIncreasePercent = GetWeaponSpeedIncrease(sWeapon);
	if (fSpeedIncreasePercent <= 0.0)
		return;
	
	new Float:fSpeedDuration = GetWeaponEffectDuration(sWeapon);
	if (fSpeedDuration <= 0.0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	/* Set player speed */
	new Float:fSpeed = 1.0 + float(iLevel) * fSpeedIncreasePercent;
	SMRPG_ChangeClientLaggedMovement(victim, fSpeed, fSpeedDuration);
	
	// No effect for this game:(
	new iRedTrailSprite = SMRPG_GC_GetPrecachedIndex("SpriteRedTrail");
	if(iRedTrailSprite == -1)
		return;
	
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
	
	TE_SetupBeamFollow(iSprite, iRedTrailSprite, iRedTrailSprite, fSpeedDuration, 10.0, 4.0, 2, {255,0,0,255});
	SMRPG_TE_SendToAllEnabled(UPGRADE_SHORTNAME);
}

/**
 * Helpers
 */
bool:LoadWeaponConfig()
{
	ClearTrie(g_hWeaponConfig);
	
	new String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/impulse_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	new Handle:hKV = CreateKeyValues("ImpulseWeapons");
	if(!FileToKeyValues(hKV, sPath))
	{
		CloseHandle(hKV);
		return false;
	}
	
	new String:sWeapon[64], config[WeaponConfig];
	if(KvGotoFirstSubKey(hKV, false))
	{
		do
		{
			KvGetSectionName(hKV, sWeapon, sizeof(sWeapon));
			config[Config_SpeedIncrease] = KvGetFloat(hKV, "speed_increase", -1.0);
			config[Config_Duration] = KvGetFloat(hKV, "duration", -1.0);
			
			SetTrieArray(g_hWeaponConfig, sWeapon, config[0], _:WeaponConfig);
			
		} while (KvGotoNextKey(hKV));
	}
	CloseHandle(hKV);
	return true;
}

Float:GetWeaponSpeedIncrease(const String:sWeapon[])
{
	// See if there is a value for this weapon in the config.
	new config[WeaponConfig];
	if (GetTrieArray(g_hWeaponConfig, sWeapon, config[0], _:WeaponConfig))
	{
		if (config[Config_SpeedIncrease] >= 0.0)
			return config[Config_SpeedIncrease];
	}
	
	// Just use the default value
	return GetConVarFloat(g_hCVDefaultSpeedIncrease);
}

Float:GetWeaponEffectDuration(const String:sWeapon[])
{
	// See if there is a value for this weapon in the config.
	new config[WeaponConfig];
	if (GetTrieArray(g_hWeaponConfig, sWeapon, config[0], _:WeaponConfig))
	{
		if (config[Config_Duration] >= 0.0)
			return config[Config_Duration];
	}
	
	// Just use the default value
	return GetConVarFloat(g_hCVDefaultDuration);
}
