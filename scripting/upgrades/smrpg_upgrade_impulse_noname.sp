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
ConVar g_hCVDefaultWait;

StringMap g_hWeaponConfig;

enum WeaponConfig
{
	Float:Config_SpeedIncrease,
	Float:Config_Duration,
	Float:Config_Wait
};

int g_iImpulseTrailSprites[MAXPLAYERS+1] = {-1,...};
bool g_bImpulse[MAXPLAYERS+1] = {false,...};
Handle g_hImpulseTimer[MAXPLAYERS+1] = {null,...};

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > THC like Impulse",
	author = "Nobody-x",
	description = "Impulse upgrade for SM:RPG. Gain speed shortly when you shoot.",
	version = SMRPG_VERSION,
	url = "https://www.noname.team/"
}

public void OnPluginStart()
{
	HookEvent("round_start", Event_OnRoundStart);
	HookEvent("weapon_fire", Event_OnWeaponFire);
	
	LoadTranslations("smrpg_impulse_upgrades.phrases");
	
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
		SMRPG_RegisterUpgradeType("Impulse", UPGRADE_SHORTNAME, "Gain speed for a short time when being shot.", 10, true, 5, 20, 20, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVDefaultSpeedIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_speed_inc", "0.2", "Speed increase for each level when player is damaged.", 0, true, 0.1);
		g_hCVDefaultDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_duration", "0.4", "Duration of Impulse's effect in seconds.", 0, true, 0.1);
		g_hCVDefaultWait = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_impulse_wait", "0.5", "Wait before next impulse in seconds.", 0, true, 0.1);
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
	g_bImpulse[client] = false;
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

public void Event_OnWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!g_bImpulse[client])
		SetPlayerImpulse(client);
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

void SetPlayerImpulse(int client) {
	if(client <= 0 || client > MaxClients)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	if (g_bImpulse[client])
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(SMRPG_IsClientLaggedMovementChanged(client, LMT_Faster, true))
		return; //Player is already faster

	int iWeapon = Client_GetActiveWeapon(client);
	
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
	
	float fWait = GetWeaponWait(sWeapon);
	if (fWait < 0.0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	/* Set player speed */
	float fSpeed = 1.0 + float(iLevel) * fSpeedIncreasePercent;
	SMRPG_ChangeClientLaggedMovement(client, fSpeed, fSpeedDuration);
	
	// No effect for this game:(
	int iRedTrailSprite = SMRPG_GC_GetPrecachedIndex("SpriteRedTrail");
	if(iRedTrailSprite == -1)
		return;
	
	float vOrigin[3];
	GetClientEyePosition(client, vOrigin);
	vOrigin[2] -= 40.0;
	
	int iSprite = g_iImpulseTrailSprites[client];
	if(iSprite == -1 || !IsValidEntity(iSprite))
	{
		iSprite = CreateEntityByName("env_sprite");
		if(iSprite == -1)
			return;
		
		SetEntityRenderMode(iSprite, RENDER_NONE);
		TeleportEntity(iSprite, vOrigin, view_as<float>({0.0,0.0,0.0}), NULL_VECTOR);
		DispatchSpawn(iSprite);
		
		g_iImpulseTrailSprites[client] = iSprite;
	}
	
	TeleportEntity(iSprite, vOrigin, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(iSprite, "SetParent", client);
	
	TE_SetupBeamFollow(iSprite, iRedTrailSprite, iRedTrailSprite, fSpeedDuration, 10.0, 4.0, 2, {255,0,0,255});
	SMRPG_TE_SendToAllEnabled(UPGRADE_SHORTNAME);
	
	if (fWait > 0.0) {
		g_bImpulse[client] = true;
		g_hImpulseTimer[client] = CreateTimer(fWait, Timer_EndWaitImpulse, GetClientSerial(client));
	}
}

public Action Timer_EndWaitImpulse(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	if (!client)
		return Plugin_Stop;

	g_bImpulse[client] = false;
	g_hImpulseTimer[client] = null;
	return Plugin_Handled;
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
			config[Config_Wait] = hKV.GetFloat("wait", -1.0);
			
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

float GetWeaponWait(const char[] sWeapon)
{
	// See if there is a value for this weapon in the config.
	int config[WeaponConfig];
	if (g_hWeaponConfig.GetArray(sWeapon, config[0], view_as<int>(WeaponConfig)))
	{
		if (config[Config_Wait] >= 0.0)
			return config[Config_Wait];
	}
	
	// Just use the default value
	return g_hCVDefaultWait.FloatValue;
}
