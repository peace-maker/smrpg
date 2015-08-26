#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smrpg>
#include <smrpg_effects>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>
#include <smlib>

#define UPGRADE_SHORTNAME "icestab"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVIceStabLimitDmg;
new Handle:g_hCVTimeIncrease;
new Handle:g_hCVWeapon;
new Handle:g_hCVMinDamage;

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
		SMRPG_RegisterUpgradeType("Ice Stab", UPGRADE_SHORTNAME, "Freeze a player in place when knifing him.", 10, true, 10, 30, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
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
	SMRPG_GC_PrecacheModel("SpriteBeam");
	SMRPG_GC_PrecacheModel("SpriteHalo");
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
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
	// TODO: Differenciate if we froze the client ourself
	return SMRPG_IsClientFrozen(client);
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	if(SMRPG_IsClientFrozen(client))
		SMRPG_UnfreezeClient(client);
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
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	if(SMRPG_IsClientFrozen(attacker))
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
	new Float:fFreezeTime = GetConVarFloat(g_hCVTimeIncrease)*float(iLevel);
	if(!SMRPG_FreezeClient(victim, fFreezeTime, GetConVarFloat(g_hCVIceStabLimitDmg), UPGRADE_SHORTNAME, true, true, false))
		return;
	
	new Float:fOrigin[3];
	GetClientAbsOrigin(victim, fOrigin);
	fOrigin[2] -= 30.0;
	
	new iBeamSprite = SMRPG_GC_GetPrecachedIndex("SpriteBeam");
	new iHaloSprite = SMRPG_GC_GetPrecachedIndex("SpriteHalo");
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
stock TE_SendFourBeamEffectToEnabled(Float:origin[3], Float:Width, Float:EndWidth, Float:Height, ModelIndex, HaloIndex, StartFrame, FrameRate, Float:Life, 
                Float:BeamWidth, Float:BeamEndWidth, FadeLength, Float:Amplitude, const Color[4], Speed, Float:delay=0.0)
{
	new Float:fPoints[8][3];
	for(new point=0;point<8;point++)
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
	
	for(new i=0;i<4;i++)
	{
		TE_SetupBeamPoints(fPoints[i], fPoints[i+4], ModelIndex, HaloIndex, StartFrame, FrameRate, Life, BeamWidth, BeamEndWidth, FadeLength, Amplitude, Color, Speed);
		SMRPG_TE_SendToAllEnabled(UPGRADE_SHORTNAME, delay);
	}
}