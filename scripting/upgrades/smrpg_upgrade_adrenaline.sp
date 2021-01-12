/**
 * SM:RPG Adrenaline Upgrade
 * Increase your speed shortly when shooting.
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "adrenaline"

ConVar g_hCVSpeedIncrease;
ConVar g_hCVEffectDuration;
ConVar g_hCVOnHitEnemy;
ConVar g_hCVRequireGround;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Adrenaline",
	author = "Peace-Maker",
	description = "Adrenaline upgrade for SM:RPG. Increase your speed shortly when shooting.",
	version = SMRPG_VERSION,
	url = "https://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

	if (!HookEventEx("weapon_fire", Event_OnWeaponFire))
		SetFailState("This game doesn't have the \"weapon_fire\" event. Upgrade disabled.");

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
		SMRPG_RegisterUpgradeType("Adrenaline", UPGRADE_SHORTNAME, "Increase your speed shortly when shooting.", 0, true, 6, 10, 10);
		
		// If this is an active effect which is only affecting players for a short time on some event,
		// register this callback so other plugins can ask, if your effect is currently active on a player
		// using SMRPG_IsUpgradeActiveOnClient.
		SMRPG_SetUpgradeActiveQueryCallback(UPGRADE_SHORTNAME, SMRPG_ActiveQuery);
		
		// If this is an active effect which is only affecting players for a short time on some event, register this callback to enable other plugins to stop your effect anytime.
		// This can help to prevent compatibility issues between similar upgrades.
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVSpeedIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_adrenaline_speed_inc", "0.05", "Speed increase for each level when a weapon is fired.", _, true, 0.1);
		g_hCVEffectDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_adrenaline_duration", "0.5", "Duration of the speed up in seconds.", 0, true, 0.1);
		g_hCVOnHitEnemy = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_adrenaline_hit_enemy", "1", "Increase the speed (0) everytime the player shoots his weapon or (1) if the player hits an enemy?", 0, true, 0.0, true, 1.0);
		g_hCVRequireGround = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_adrenaline_require_ground", "1", "Only apply the effect when the player stands on the ground while shooting?", 0, true, 0.0, true, 1.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public void OnClientDisconnect(int client)
{
	// Don't forget to reset your effect when the client leaves ;)
	SMRPG_ResetEffect(client);
}

/**
 * Event callbacks
 */
public void Event_OnWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;

	// We require to hit an enemy with this attack.
	if (g_hCVOnHitEnemy.BoolValue)
		return;

	ApplyAdrenalineEffect(client);
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

/**
 * Hook callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients)
		return;
	
	// We're increasing the speed on every shot not only when we hit an enemy.
	if (!g_hCVOnHitEnemy.BoolValue)
		return;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;

	ApplyAdrenalineEffect(attacker);
}

/**
 * Helpers
 */
void ApplyAdrenalineEffect(int client)
{
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return;
	
	// The upgrade is disabled completely?
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;

	// Player is in midair.
	if(g_hCVRequireGround.BoolValue && !(GetEntityFlags(client) & FL_ONGROUND))
		return; 

	// Player is already faster
	if(SMRPG_IsClientLaggedMovementChanged(client, LMT_Faster, true))
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run

	float fSpeed = 1.0 + float(iLevel) * g_hCVSpeedIncrease.FloatValue;
	SMRPG_ChangeClientLaggedMovement(client, fSpeed, g_hCVEffectDuration.FloatValue);
}
