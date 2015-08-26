/**
 * SM:RPG Bouncy Bullets Upgrade
 * Push enemies away by shooting them.
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smrpg_effects>

// Change the upgrade's shortname to a descriptive abbrevation
#define UPGRADE_SHORTNAME "bouncybullets"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVForce;
new Handle:g_hCVIgnoreWeapons;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Bouncy Bullets",
	author = "Peace-Maker",
	description = "Bouncy bullets upgrade for SM:RPG. Push enemies away by shooting them.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Bouncy Bullets", UPGRADE_SHORTNAME, "Push enemies away by shooting them.", 0, true, 5, 15, 20, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		
		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVForce = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bouncybullets_force", "100.0", "Velocity multiplied by level to push victim away from attacker position.");
		g_hCVIgnoreWeapons = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bouncybullets_ignore_weapons", "knife", "Comma seperated list of weapons. Don't push the victim when hit by one of these weapons.");
	}
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
	// Here you can apply your effect directly when the client's upgrade level changes.
	// E.g. adjust the maximal health of the player immediately when he bought the upgrade.
	// The client doesn't have to be ingame here!
}

public bool:SMRPG_ActiveQuery(client)
{
	// If this is a passive effect, it's always active, if the player got at least level 1.
	// If it's an active effect (like a short speed boost) add a check for the effect as well.
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}

// The core wants to display your upgrade somewhere. Translate it into the clients language!
public SMRPG_TranslateUpgrade(client, const String:shortname[], TranslationType:type, String:translation[], maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if(type == TranslationType_Description)
	{
		new String:sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

/**
 * Event callbacks
 */
public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;

	// Check whether this weapon shouldn't push the victim.
	new String:sIgnoreWeapons[512];
	GetConVarString(g_hCVIgnoreWeapons, sIgnoreWeapons, sizeof(sIgnoreWeapons));
	
	new iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = GetEntPropEnt(inflictor, Prop_Send, "m_hActiveWeapon");
	
	if (iWeapon > 0 && IsValidEntity(iWeapon))
	{
		new String:sWeapon[64];
		GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
		// Skip "weapon_" prefix.
		new iPos = StrContains(sWeapon, "weapon_", false);
		if (iPos != -1)
			iPos += 7;
		else
			iPos = 0;
		
		// This weapon should be ignored.
		if (StrContains(sIgnoreWeapons, sWeapon[iPos], false) != -1)
			return;
	}
		
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return;
	
	// The upgrade is disabled completely?
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack if not FFA.
	if (!SMRPG_IsFFAEnabled() && GetClientTeam(victim) == GetClientTeam(attacker))
		return;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(attacker, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run

	// Don't push frozen people around.
	if(SMRPG_IsClientFrozen(victim))
		return;
	
	// Push victim away from attacker's position.
	new Float:fVictimOrigin[3], Float:fAttackerOrigin[3], Float:fDirection[3];
	GetClientEyePosition(victim, fVictimOrigin);
	GetClientEyePosition(attacker, fAttackerOrigin);
	MakeVectorFromPoints(fAttackerOrigin, fVictimOrigin, fDirection);
	NormalizeVector(fDirection, fDirection);
	
	new Float:fForce = GetConVarFloat(g_hCVForce) * iLevel;
	ScaleVector(fDirection, fForce);
	TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, fDirection);
}
