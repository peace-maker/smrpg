#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "denial"
#define PLUGIN_VERSION "1.0"

ConVar g_hCVDenialRestrict;

bool g_bDenialPlayerWasDead[MAXPLAYERS+1];
Handle g_hDenialStripTimer[MAXPLAYERS+1] = {null,...};

char g_sDenialPrimary[MAXPLAYERS+1][64];
char g_sDenialSecondary[MAXPLAYERS+1][64];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Denial",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Denial upgrade for SM:RPG. Keep your weapons after you die.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("player_team", Event_OnPlayerTeam);
	
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
		SMRPG_RegisterUpgradeType("Denial", UPGRADE_SHORTNAME, "Keep your weapons the next time you spawn after you've died.", 2, true, 2, 75, 50, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVDenialRestrict = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_denial_restrict", "", "Space delimited list of restricted weapons (e.g. awp g3sg1 m249)");
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_WeaponEquipPost);
}

public void OnClientDisconnect(int client)
{
	Denial_ResetClient(client);
}

/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	int upgrade[UpgradeInfo];
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

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	
	/* Reset player Denial data while Denial is disabled */
	if(!SMRPG_IsEnabled() || !upgrade[UI_enabled])
	{
		Denial_ResetClient(client);
		return;
	}
	
	g_bDenialPlayerWasDead[client] = true;
}

public void Event_OnPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	SMRPG_ResetEffect(client);
}

/**
 * SM:RPG Upgrade callbacks
 */
public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
	
}

public bool SMRPG_ActiveQuery(int client)
{
	// This is a passive effect, so it's always active, if the player got at least level 1
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}

// Some plugin wants this effect to end?
public void SMRPG_ResetEffect(int client)
{
	g_sDenialPrimary[client][0] = '\0';
	g_sDenialSecondary[client][0] = '\0';
	ClearHandle(g_hDenialStripTimer[client]);
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
 * SDKHook callbacks
 */
public Action Hook_WeaponEquipPost(int client, int weapon)
{
	int upgrade[UpgradeInfo];
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
		GetRealWeaponClassname(weapon, g_sDenialPrimary[client], sizeof(g_sDenialPrimary[]));
	else if(weapon == GetPlayerWeaponSlot(client, 1))
		GetRealWeaponClassname(weapon, g_sDenialSecondary[client], sizeof(g_sDenialSecondary[]));
	
	return Plugin_Continue;
}

/**
 * Timer callbacks
 */
public Action Timer_StripPlayer(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hDenialStripTimer[client] = null;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Stop;
	
	// Level 1: Secondary Weapon
	if(iLevel >= 1)
	{
		if(StrContains(g_sDenialSecondary[client],"weapon_") != -1 && !Denial_IsWeaponRestricted(g_sDenialSecondary[client]))
		{
			char sOldWeapon[64];
			int iCurrentWeapon = GetPlayerWeaponSlot(client, 1);
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
			char sOldWeapon[64];
			int iCurrentWeapon = GetPlayerWeaponSlot(client, 0);
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
void Denial_ResetClient(int client)
{
	g_bDenialPlayerWasDead[client] = false;
	SMRPG_ResetEffect(client);
}

bool Denial_IsWeaponRestricted(const char[] sWeapon)
{
	char sRestrictedWeapons[1024];
	g_hCVDenialRestrict.GetString(sRestrictedWeapons, sizeof(sRestrictedWeapons));
	
	int iPos = StrContains(sWeapon, "weapon_");
	if(iPos != -1)
		iPos += 7; // skip "weapon_" too.
	else
		iPos = 0;
	
	if(StrContains(sRestrictedWeapons, sWeapon[iPos], false) != -1)
		return true;
	return false;
}

bool GetRealWeaponClassname(int entity, char[] sClassname, int maxlen)
{
	// Replace the weapon classname with the correct one for special weapons in CS:GO.
	if (GetEngineVersion() == Engine_CSGO)
	{
		int iItemDefinitionIndex = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
		char sWeapon[32];
		switch(iItemDefinitionIndex)
		{
			case 60:
				sWeapon = "weapon_m4a1_silencer";
			case 61:
				sWeapon = "weapon_usp_silencer";
			case 63:
				sWeapon = "weapon_cz75a";
			case 64:
				sWeapon = "weapon_revolver";
		}
		if (sWeapon[0])
		{
			strcopy(sClassname, maxlen, sWeapon);
			return true;
		}
	}
	
	return GetEntityClassname(entity, sClassname, maxlen);
}