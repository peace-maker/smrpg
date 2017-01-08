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

#define UPGRADE_SHORTNAME "fpistol"
#define PLUGIN_VERSION "1.0"

ConVar g_hCVTimeIncrease;

StringMap g_hWeaponSpeeds;

// See how many freeze sounds we have in the gamedata file.
int g_iFreezeSoundCount;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Frost Pistol",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Frost Pistol upgrade for SM:RPG. Slow down players hit with a pistol.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_hWeaponSpeeds = new StringMap();
	
	if(!LoadWeaponConfig())
	{
		Format(error, err_max, "Can't read config file in configs/smrpg/frostpistol_weapons.cfg!");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	SMRPG_GC_CheckSharedMaterialsAndSounds();

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
		SMRPG_RegisterUpgradeType("Frost Pistol", UPGRADE_SHORTNAME, "Slow down players hit with a pistol.", 10, true, 10, 20, 15);
		SMRPG_SetUpgradeActiveQueryCallback(UPGRADE_SHORTNAME, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Sounds, true);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVTimeIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fpistol_inc", "0.1", "How many seconds are players slowed down multiplied by level?", 0, true, 0.1);
	}
}

public void OnMapStart()
{
	g_iFreezeSoundCount = 0;
	char sBuffer[64];
	for(;;g_iFreezeSoundCount++)
	{
		Format(sBuffer, sizeof(sBuffer), "SoundFPistolFreeze%d", g_iFreezeSoundCount+1);
		if(!SMRPG_GC_PrecacheSound(sBuffer))
			break;
	}
}

public void OnMapEnd()
{
	if(!LoadWeaponConfig())
		SetFailState("Can't read config file in configs/smrpg/frostpistol_weapons.cfg!");
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public void OnClientDisconnect(int client)
{
	SMRPG_ResetEffect(client);
}

/**
 * SM:RPG Upgrade callbacks
 */

public bool SMRPG_ActiveQuery(int client)
{
	return SMRPG_IsClientLaggedMovementChanged(client, LMT_Slower, true);
}

// Some plugin wants this effect to end?
public void SMRPG_ResetEffect(int client)
{
	SMRPG_ResetClientLaggedMovement(client, LMT_Slower);
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
	if(type == LMT_Slower)
	{
		// Reset the blue color, if we set it before.
		SMRPG_ResetClientToDefaultColor(client, true, true, true, false);
	}
}

/**
 * Hook callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return;
	
	char sWeapon[256];
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	ReplaceString(sWeapon, sizeof(sWeapon), "weapon_", "", false);
	
	float fSpeed;
	// Don't process weapons, which aren't in the config file.
	if(!g_hWeaponSpeeds.GetValue(sWeapon, fSpeed))
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return; // Some other plugin doesn't want this effect to run
	
	float fTime = float(iLevel) * g_hCVTimeIncrease.FloatValue;
	if(fTime <= 0.0)
		return; // Silly convar settings?

	if(SMRPG_ChangeClientLaggedMovement(victim, fSpeed, fTime))
	{
		// Emit some icy sound
		if(g_iFreezeSoundCount > 0)
		{
			char sKey[64];
			Format(sKey, sizeof(sKey), "SoundFPistolFreeze%d", GetRandomInt(1, g_iFreezeSoundCount));
			// Only play it to players who enabled sounds for this upgrade
			SMRPG_EmitSoundToAllEnabled(UPGRADE_SHORTNAME, SMRPG_GC_GetKeyValue(sKey), victim, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8, SNDPITCH_NORMAL, victim);
		}
		
		// TODO: Move to laggedmovement effect hub slowdown
		// If the victim doesn't want any effect, don't show it to anyone..................
		if(SMRPG_ClientWantsCosmetics(victim, UPGRADE_SHORTNAME, SMRPG_FX_Visuals))
		{
			SMRPG_SetClientRenderColor(victim, 0, 0, 255, -1);
		}
	}
}

/**
 * Helpers
 */
bool LoadWeaponConfig()
{
	g_hWeaponSpeeds.Clear();
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/frostpistol_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	KeyValues hKV = new KeyValues("FrostPistolWeapons");
	if(!hKV.ImportFromFile(sPath))
	{
		delete hKV;
		return false;
	}
	
	char sWeapon[64];
	float fSpeed;
	if(hKV.GotoFirstSubKey(false))
	{
		do
		{
			hKV.GetSectionName(sWeapon, sizeof(sWeapon));
			fSpeed = hKV.GetFloat(NULL_STRING, 1.0);
			
			g_hWeaponSpeeds.SetValue(sWeapon, fSpeed);
			
		} while (hKV.GotoNextKey(false));
	}
	delete hKV;
	return true;
}
