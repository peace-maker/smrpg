/**
 * SM:RPG Position Swap Upgrade
 * Gives you the chance to swap positions with your attacker.
 *
 * Based on the upgrade in THC:RPG by arsirc, thanks!
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "positionswap"

ConVar g_hCVChance;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Position Swap",
	author = "Peace-Maker",
	description = "Position Swap upgrade for SM:RPG. Gives you the chance to swap positions with your attacker.",
	version = SMRPG_VERSION,
	url = "https://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Position Swap", UPGRADE_SHORTNAME, "Gives you the chance to swap positions with your attacker.", 0, true, 5, 20, 15);

		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVChance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_positionswap_chance", "0.05", "The chance that the position of the attacker and the victim are swapped (multiplied by level).", _, true, 0.0, true, 1.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

/**
 * SM:RPG Upgrade callbacks
 */

// The core wants to display your upgrade somewhere. Translate it into the clients language!
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom)
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients)
		return;

	if(!IsPlayerAlive(attacker))
		return;

	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return;
	
	// The upgrade is disabled completely?
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(victim) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;

	// Check if this attack allows the victim to swap places with the attacker.
	if(Math_GetRandomFloat(0.0, 1.0) > g_hCVChance.FloatValue * iLevel)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return; // Some other plugin doesn't want this effect to run

	// Swap positions, but keep view angles and velocity at their original values.
	float fVictimPosition[3], fAttackerPosition[3];
	GetClientAbsOrigin(victim, fVictimPosition);
	GetClientAbsOrigin(attacker, fAttackerPosition);
	TeleportEntity(victim, fAttackerPosition, NULL_VECTOR, NULL_VECTOR);
	TeleportEntity(attacker, fVictimPosition, NULL_VECTOR, NULL_VECTOR);
}
