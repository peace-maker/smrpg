#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>

#undef REQUIRE_PLUGIN
#include <smrpg_health>

#define UPGRADE_SHORTNAME "vamp"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVPercent;
new Handle:g_hCVMax;

new g_iBeamColor[] = {0,255,0,255}; // green

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Vampire",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Vampire upgrade for SM:RPG. Steal HP from players when damaging them.",
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
		SMRPG_RegisterUpgradeType("Vampire", UPGRADE_SHORTNAME, "Steal HP from players when damaging them.", 15, true, 10, 15, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vamp_percent", "0.075", "Percent of damage to convert to attacker's health for each level.", 0, true, 0.001);
		g_hCVMax = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vamp_maxhp", "70", "Maximum HP the attacker can get at a time. (0 = unlimited)", 0, true, 0.0);
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public OnMapStart()
{
	SMRPG_GC_PrecacheModel("SpriteBeam");
	SMRPG_GC_PrecacheModel("SpriteHalo");
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
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
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
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
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
	
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(attacker, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Float:fIncrease = float(iLevel) * GetConVarFloat(g_hCVPercent);
	fIncrease *= damage;
	fIncrease += 0.5;
	
	// Don't let the attacker steal more hp than the set max 
	new iMaxIncrease = GetConVarInt(g_hCVMax);
	new iIncrease = RoundToFloor(fIncrease);
	if(iMaxIncrease > 0 && iIncrease > iMaxIncrease)
		iIncrease = iMaxIncrease;
	
	new iOldHealth = GetClientHealth(attacker);
	new iNewHealth = iOldHealth + iIncrease;
	new iMaxHealth = SMRPG_Health_GetClientMaxHealth(attacker);
	// Limit health gain to maxhealth
	if(iNewHealth > iMaxHealth)
		iNewHealth = iMaxHealth;
	
	// Only change anything and display the effect, if we actually gave some health.
	if(iOldHealth != iMaxHealth)
	{
		SetEntityHealth(attacker, iNewHealth);
		
		new Float:fAttackerOrigin[3], Float:fVictimOrigin[3];
		GetClientEyePosition(attacker, fAttackerOrigin);
		GetClientEyePosition(victim, fVictimOrigin);
		fAttackerOrigin[2] -= 10.0;
		fVictimOrigin[2] -= 10.0;
		
		new iBeamSprite = SMRPG_GC_GetPrecachedIndex("SpriteBeam");
		new iHaloSprite = SMRPG_GC_GetPrecachedIndex("SpriteHalo");
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