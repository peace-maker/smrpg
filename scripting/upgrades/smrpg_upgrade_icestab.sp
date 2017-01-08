#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>

#define UPGRADE_SHORTNAME "icestab"
#define PLUGIN_VERSION "1.0"

ConVar g_hCVIceStabLimitDmg;
ConVar g_hCVTimeIncrease;
ConVar g_hCVWeapon;
ConVar g_hCVMinDamage;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Ice Stab",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Ice Stab upgrade for SM:RPG. Freeze a player in place when knifing him.",
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
		SMRPG_RegisterUpgradeType("Ice Stab", UPGRADE_SHORTNAME, "Freeze a player in place when knifing him.", 10, true, 10, 30, 10);
		SMRPG_SetUpgradeActiveQueryCallback(UPGRADE_SHORTNAME, SMRPG_ActiveQuery);
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

public void OnMapStart()
{
	SMRPG_GC_PrecacheModel("SpriteBeam");
	SMRPG_GC_PrecacheModel("SpriteHalo");
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

/**
 * SM:RPG Upgrade callbacks
 */
public bool SMRPG_ActiveQuery(int client)
{
	// TODO: Differenciate if we froze the client ourself
	return SMRPG_IsClientFrozen(client);
}

// Some plugin wants this effect to end?
public void SMRPG_ResetEffect(int client)
{
	if(SMRPG_IsClientFrozen(client))
		SMRPG_UnfreezeClient(client);
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
 * Hook callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
		return;
	
	if(damage < g_hCVMinDamage.FloatValue)
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
	
	if(SMRPG_IsClientFrozen(attacker))
		return; /* don't allow frozen attacker to icestab */
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return;
	
	char sWeapon[256], sTargetWeapon[128];
	g_hCVWeapon.GetString(sTargetWeapon, sizeof(sTargetWeapon));
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	ReplaceString(sWeapon, sizeof(sWeapon), "weapon_", "", false);
	
	// This effect only applies to the specified weapon.
	if(StrContains(sWeapon, sTargetWeapon) == -1)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return; // Some other plugin doesn't want this effect to run
	
	// Freeze the player.
	float fFreezeTime = g_hCVTimeIncrease.FloatValue*float(iLevel);
	if(!SMRPG_FreezeClient(victim, fFreezeTime, g_hCVIceStabLimitDmg.FloatValue, UPGRADE_SHORTNAME, true, true, false))
		return;
	
	float fOrigin[3];
	GetClientAbsOrigin(victim, fOrigin);
	fOrigin[2] -= 30.0;
	
	int iBeamSprite = SMRPG_GC_GetPrecachedIndex("SpriteBeam");
	int iHaloSprite = SMRPG_GC_GetPrecachedIndex("SpriteHalo");
	// Just use the beamsprite as halo, if no halo sprite available
	if(iHaloSprite == -1)
		iHaloSprite = iBeamSprite;
	
	if(iBeamSprite != -1)
	{
		// Create a "cage" around frozen player.
		TE_SendFourBeamEffectToEnabled(fOrigin, 10.0, 10.0, 120.0, iBeamSprite, iHaloSprite, 0, 66, fFreezeTime/3.0, 10.0, 10.0, 0, 0.0, {0,0,255,255}, 0);
	}
}

// Thanks to SumGuy14 (Aka SoccerDude)
// RPGx effects.inc FourBeamEffect
stock void TE_SendFourBeamEffectToEnabled(float origin[3], float Width, float EndWidth, float Height, int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, 
                float BeamWidth, float BeamEndWidth, int FadeLength, float Amplitude, const int Color[4], int Speed, float delay=0.0)
{
	float fPoints[8][3];
	for(int point=0;point<8;point++)
	{
		fPoints[point] = origin;
	}
	
	fPoints[0][0] += Width;
	fPoints[1][0] -= Width;
	fPoints[2][1] += Width;
	fPoints[3][1] -= Width;
	fPoints[4][0] += EndWidth;
	fPoints[4][2] += Height;
	fPoints[5][0] -= EndWidth;
	fPoints[5][2] += Height;
	fPoints[6][1] += EndWidth;
	fPoints[6][2] += Height;
	fPoints[7][1] -= EndWidth;
	fPoints[7][2] += Height;
	
	for(int i=0;i<4;i++)
	{
		TE_SetupBeamPoints(fPoints[i], fPoints[i+4], ModelIndex, HaloIndex, StartFrame, FrameRate, Life, BeamWidth, BeamEndWidth, FadeLength, Amplitude, Color, Speed);
		SMRPG_TE_SendToAllEnabled(UPGRADE_SHORTNAME, delay);
	}
}