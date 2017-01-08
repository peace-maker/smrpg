#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>

#undef REQUIRE_PLUGIN
#include <smrpg_health>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "vamp"
#define PLUGIN_VERSION "1.0"

ConVar g_hCVPercent;
ConVar g_hCVMax;
ConVar g_hCVFreezePenalty;

int g_iBeamColor[] = {0,255,0,255}; // green

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Vampire",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Vampire upgrade for SM:RPG. Steal HP from players when damaging them.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
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
		SMRPG_RegisterUpgradeType("Vampire", UPGRADE_SHORTNAME, "Steal HP from players when damaging them.", 15, true, 10, 15, 10);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vamp_percent", "0.075", "Percent of damage to convert to attacker's health for each level.", 0, true, 0.001);
		g_hCVMax = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vamp_maxhp", "70", "Maximum HP the attacker can get at a time. (0 = unlimited)", 0, true, 0.0);
		g_hCVFreezePenalty = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vamp_freeze_penalty", "0.5", "Only give x% of the HP the attacker would receive, if the victim is frozen by e.g. icestab.", 0, true, 0.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public void OnMapStart()
{
	SMRPG_GC_PrecacheModel("SpriteBeam");
	SMRPG_GC_PrecacheModel("SpriteHalo");
}

/**
 * SM:RPG Upgrade callbacks
 */
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
	
	int iOldHealth = GetClientHealth(attacker);
	int iMaxHealth = SMRPG_Health_GetClientMaxHealth(attacker);
		
	// Don't reset the health, if the player gained more by other means.
	if(iOldHealth >= iMaxHealth)
		return;
	
	if(!SMRPG_RunUpgradeEffect(attacker, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	float fIncrease = float(iLevel) * g_hCVPercent.FloatValue;
	fIncrease *= damage;
	fIncrease += 0.5;
	
	// Reduce stolen HP if the victim is frozen with icestab
	if(GetFeatureStatus(FeatureType_Native, "SMRPG_IsClientFrozen") == FeatureStatus_Available && SMRPG_IsClientFrozen(victim))
	{
		fIncrease *= g_hCVFreezePenalty.FloatValue;
	}
	
	// Don't let the attacker steal more hp than the set max 
	int iMaxIncrease = g_hCVMax.IntValue;
	int iIncrease = RoundToFloor(fIncrease);
	if(iMaxIncrease > 0 && iIncrease > iMaxIncrease)
		iIncrease = iMaxIncrease;
	
	int iNewHealth = iOldHealth + iIncrease;
	// Limit health gain to maxhealth
	if(iNewHealth > iMaxHealth)
		iNewHealth = iMaxHealth;
	
	// Only change anything and display the effect, if we actually gave some health.
	if(iOldHealth != iMaxHealth)
	{
		SetEntityHealth(attacker, iNewHealth);
		
		float fAttackerOrigin[3], fVictimOrigin[3];
		GetClientEyePosition(attacker, fAttackerOrigin);
		GetClientEyePosition(victim, fVictimOrigin);
		fAttackerOrigin[2] -= 10.0;
		fVictimOrigin[2] -= 10.0;
		
		int iBeamSprite = SMRPG_GC_GetPrecachedIndex("SpriteBeam");
		int iHaloSprite = SMRPG_GC_GetPrecachedIndex("SpriteHalo");
		// Just use the beamsprite as halo, if no halo sprite available
		if(iHaloSprite == -1)
			iHaloSprite = iBeamSprite;
		
		if(iBeamSprite != -1)
		{
			TE_SetupBeamPoints(fAttackerOrigin, fVictimOrigin, iBeamSprite, iHaloSprite, 0, 66, 0.2, 1.0, 20.0, 1, 0.0, g_iBeamColor, 5);
			SMRPG_TE_SendToAllEnabled(UPGRADE_SHORTNAME);
		}
	}
}