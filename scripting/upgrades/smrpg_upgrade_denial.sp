#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "denial"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVDenialRestrict;

new bool:g_bDenialPlayerWasDead[MAXPLAYERS+1];
new Handle:g_hDenialStripTimer[MAXPLAYERS+1] = {INVALID_HANDLE,...};

new String:g_sDenialPrimary[MAXPLAYERS+1][64];
new String:g_sDenialSecondary[MAXPLAYERS+1][64];

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Denial",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Denial upgrade for SM:RPG. Keep your weapons after you die.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("player_team", Event_OnPlayerTeam);
	
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
		SMRPG_RegisterUpgradeType("Denial", UPGRADE_SHORTNAME, "Keep your weapons the next time you spawn after you've died.", 2, true, 2, 75, 50, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVDenialRestrict = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_denial_restrict", "", "Space delimited list of restricted weapons (e.g. awp g3sg1 m249)");
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_WeaponEquipPost);
}

public OnClientDisconnect(client)
{
	Denial_ResetClient(client);
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	
	/* Reset player Denial data while Denial is disabled */
	if(!SMRPG_IsEnabled() || !upgrade[UI_enabled])
	{
		Denial_ResetClient(client);
		return;
	}
	
	// Only change weapons, if he was dead.
	if(!g_bDenialPlayerWasDead[client])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	g_bDenialPlayerWasDead[client] = false;
	
	// Strip weapons
	ClearHandle(g_hDenialStripTimer[client]);
	g_hDenialStripTimer[client] = CreateTimer(0.1, Timer_StripPlayer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Event_OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	
	/* Reset player Denial data while Denial is disabled */
	if(!SMRPG_IsEnabled() || !upgrade[UI_enabled])
	{
		Denial_ResetClient(client);
		return;
	}
	
	g_bDenialPlayerWasDead[client] = true;
}

public Event_OnPlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	SMRPG_ResetEffect(client);
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	
}

public bool:SMRPG_ActiveQuery(client)
{
	// This is a passive effect, so it's always active, if the player got at least level 1
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	g_sDenialPrimary[client][0] = '\0';
	g_sDenialSecondary[client][0] = '\0';
	ClearHandle(g_hDenialStripTimer[client]);
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
 * SDKHook callbacks
 */
public Action:Hook_WeaponEquipPost(client, weapon)
{
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	
	/* Reset player Denial data while Denial is disabled */
	if(!SMRPG_IsEnabled() || !upgrade[UI_enabled])
	{
		Denial_ResetClient(client);
		return Plugin_Continue;
	}
	
	if(weapon <= MaxClients)
		return Plugin_Continue;
	
	// Ignore pickup of weapons before spawn
	if(g_bDenialPlayerWasDead[client])
		return Plugin_Continue;
	
	if(weapon == GetPlayerWeaponSlot(client, 0))
		GetEntityClassname(weapon, g_sDenialPrimary[client], sizeof(g_sDenialPrimary[]));
	else if(weapon == GetPlayerWeaponSlot(client, 1))
		GetEntityClassname(weapon, g_sDenialSecondary[client], sizeof(g_sDenialSecondary[]));
	
	return Plugin_Continue;
}

/**
 * Timer callbacks
 */
public Action:Timer_StripPlayer(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hDenialStripTimer[client] = INVALID_HANDLE;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Stop;
	
	// Level 1: Secondary Weapon
	if(iLevel >= 1)
	{
		if(StrContains(g_sDenialSecondary[client],"weapon_") != -1 && !Denial_IsWeaponRestricted(g_sDenialSecondary[client]))
		{
			decl String:sOldWeapon[64];
			new iCurrentWeapon = GetPlayerWeaponSlot(client, 1);
			// Remove his current weapon
			if(iCurrentWeapon != INVALID_ENT_REFERENCE)
			{
				GetEdictClassname(iCurrentWeapon, sOldWeapon, sizeof(sOldWeapon));
				Client_RemoveWeapon(client, sOldWeapon);
			}
			iCurrentWeapon = GivePlayerItem(client, g_sDenialSecondary[client]);
			if(iCurrentWeapon != INVALID_ENT_REFERENCE)
			{
				EquipPlayerWeapon(client, iCurrentWeapon);
				GivePlayerAmmo(client, 1000, Weapon_GetPrimaryAmmoType(iCurrentWeapon), false);
			}
		}
	}
	
	// Level 2: Primary Weapon
	if(iLevel >= 2)
	{
		if(StrContains(g_sDenialPrimary[client],"weapon_") != -1 && !Denial_IsWeaponRestricted(g_sDenialPrimary[client]))
		{
			decl String:sOldWeapon[64];
			new iCurrentWeapon = GetPlayerWeaponSlot(client, 0);
			// Remove his current weapon
			if(iCurrentWeapon != INVALID_ENT_REFERENCE)
			{
				GetEdictClassname(iCurrentWeapon, sOldWeapon, sizeof(sOldWeapon));
				Client_RemoveWeapon(client, sOldWeapon);
			}
			iCurrentWeapon = GivePlayerItem(client, g_sDenialPrimary[client]);
			if(iCurrentWeapon != INVALID_ENT_REFERENCE)
			{
				EquipPlayerWeapon(client, iCurrentWeapon);
				GivePlayerAmmo(client, 1000, Weapon_GetPrimaryAmmoType(iCurrentWeapon), false);
				
				// Have the player use the new primary weapon by default.
				Client_SetActiveWeapon(client, iCurrentWeapon);
			}
		}
	}
	
	return Plugin_Stop;
}

/**
 * Helper functions
 */
Denial_ResetClient(client)
{
	g_bDenialPlayerWasDead[client] = false;
	SMRPG_ResetEffect(client);
}

bool:Denial_IsWeaponRestricted(String:sWeapon[])
{
	decl String:sRestrictedWeapons[1024];
	GetConVarString(g_hCVDenialRestrict, sRestrictedWeapons, sizeof(sRestrictedWeapons));
	
	new iPos = StrContains(sWeapon, "weapon_");
	if(iPos != -1)
		iPos += 7; // skip "weapon_" too.
	else
		iPos = 0;
	
	if(StrContains(sRestrictedWeapons, sWeapon[iPos], false) != -1)
		return true;
	return false;
}