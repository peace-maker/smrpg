#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>

#define UPGRADE_SHORTNAME "impulse"

// Config
ConVar g_hCVDefaultSpeedIncrease;
ConVar g_hCVDefaultDuration;
ConVar g_hCVRequireGround;

StringMap g_hWeaponConfig;

enum WeaponConfig
{
	Float:Config_SpeedIncrease,
	Float:Config_Duration
};

int g_iImpulseTrailSprites[MAXPLAYERS+1] = {-1,...};

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Impulse",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Impulse upgrade for SM:RPG. Gain speed shortly when being shot.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	HookEvent("round_start", Event_OnRoundStart);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	SMRPG_GC_CheckSharedMaterialsAndSounds();
	
	g_hWeaponConfig = new StringMap();
	
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
		SMRPG_RegisterUpgradeType("Impulse", UPGRADE_SHORTNAME, "Gain speed for a short time when being shot.", 0, true, 5, 20, 20);
		SMRPG_SetUpgradeActiveQueryCallback(UPGRADE_SHORTNAME, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVDefaultSpeedIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_speed_inc", "0.2", "Speed increase for each level when player is damaged.", 0, true, 0.1);
		g_hCVDefaultDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_duration", "0.8", "Duration of Impulse's effect in seconds.", 0, true, 0.1);
		g_hCVRequireGround = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_require_ground", "1", "Only apply the effect when the player stands on the ground when being shot?", 0, true, 0.0, true, 1.0);
	}
}

public void OnMapStart()
{
	SMRPG_GC_PrecacheModel("SpriteRedTrail");
	
	if(!LoadWeaponConfig())
		LogError("Can't read config file in configs/smrpg/impulse_weapons.cfg!");
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public void OnClientDisconnect(int client)
{
	SMRPG_ResetEffect(client);
	if(g_iImpulseTrailSprites[client] != -1 && IsValidEntity(g_iImpulseTrailSprites[client]))
		AcceptEntityInput(g_iImpulseTrailSprites[client], "Kill");
	g_iImpulseTrailSprites[client] = -1;
}

/**
 * Event callbacks
 */
public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Reset all invisible entity indexes since the previous round's entities were all deleted on round start.
	for(int i=1;i<=MaxClients;i++)
		g_iImpulseTrailSprites[i] = -1;
}

/**
 * SM:RPG Upgrade callbacks
 */
public bool SMRPG_ActiveQuery(int client)
{
	return SMRPG_IsClientLaggedMovementChanged(client, LMT_Faster, true);
}

// Some plugin wants this effect to end?
public void SMRPG_ResetEffect(int client)
{
	SMRPG_ResetClientLaggedMovement(client, LMT_Faster);
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
 * SM:RPG Effect Hub callbacks
 */
public void SMRPG_OnClientLaggedMovementReset(int client, LaggedMovementType type)
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
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(victim) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(g_hCVRequireGround.BoolValue && !(GetEntityFlags(victim) & FL_ONGROUND))
		return; //Player is in midair
	
	if(SMRPG_IsClientLaggedMovementChanged(victim, LMT_Faster, true))
		return; //Player is already faster
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	char sWeapon[256];
	if(iWeapon != -1)
		GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	
	// Upgrade disabled for this weapon?
	float fSpeedIncreasePercent = GetWeaponSpeedIncrease(sWeapon);
	if (fSpeedIncreasePercent <= 0.0)
		return;
	
	float fSpeedDuration = GetWeaponEffectDuration(sWeapon);
	if (fSpeedDuration <= 0.0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	/* Set player speed */
	float fSpeed = 1.0 + float(iLevel) * fSpeedIncreasePercent;
	SMRPG_ChangeClientLaggedMovement(victim, fSpeed, fSpeedDuration);
	
	// No effect for this game:(
	int iRedTrailSprite = SMRPG_GC_GetPrecachedIndex("SpriteRedTrail");
	if(iRedTrailSprite == -1)
		return;
	
	float vOrigin[3];
	GetClientEyePosition(victim, vOrigin);
	vOrigin[2] -= 40.0;
	
	int iSprite = g_iImpulseTrailSprites[victim];
	if(iSprite == -1 || !IsValidEntity(iSprite))
	{
		iSprite = CreateEntityByName("env_sprite");
		if(iSprite == -1)
			return;
		
		SetEntityRenderMode(iSprite, RENDER_NONE);
		TeleportEntity(iSprite, vOrigin, view_as<float>({0.0,0.0,0.0}), NULL_VECTOR);
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
bool LoadWeaponConfig()
{
	g_hWeaponConfig.Clear();
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/impulse_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	KeyValues hKV = new KeyValues("ImpulseWeapons");
	if(!hKV.ImportFromFile(sPath))
	{
		delete hKV;
		return false;
	}
	
	char sWeapon[64];
	int config[WeaponConfig];
	if(hKV.GotoFirstSubKey(false))
	{
		do
		{
			hKV.GetSectionName(sWeapon, sizeof(sWeapon));
			config[Config_SpeedIncrease] = hKV.GetFloat("speed_increase", -1.0);
			config[Config_Duration] = hKV.GetFloat("duration", -1.0);
			
			g_hWeaponConfig.SetArray(sWeapon, config[0], view_as<int>(WeaponConfig));
			
		} while (hKV.GotoNextKey());
	}
	delete hKV;
	return true;
}

float GetWeaponSpeedIncrease(const char[] sWeapon)
{
	// See if there is a value for this weapon in the config.
	int config[WeaponConfig];
	if (g_hWeaponConfig.GetArray(sWeapon, config[0], view_as<int>(WeaponConfig)))
	{
		if (config[Config_SpeedIncrease] >= 0.0)
			return config[Config_SpeedIncrease];
	}
	
	// Just use the default value
	return g_hCVDefaultSpeedIncrease.FloatValue;
}

float GetWeaponEffectDuration(const char[] sWeapon)
{
	// See if there is a value for this weapon in the config.
	int config[WeaponConfig];
	if (g_hWeaponConfig.GetArray(sWeapon, config[0], view_as<int>(WeaponConfig)))
	{
		if (config[Config_Duration] >= 0.0)
			return config[Config_Duration];
	}
	
	// Just use the default value
	return g_hCVDefaultDuration.FloatValue;
}
