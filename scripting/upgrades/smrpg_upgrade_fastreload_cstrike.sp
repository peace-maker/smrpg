/**
 * SM:RPG Fast Reload Upgrade
 * Increases the reload speed of guns
 * 
 * Credits to tPoncho and his Perkmod https://forums.alliedmods.net/showthread.php?t=99305
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>

// Change the upgrade's shortname to a descriptive abbrevation
// No spaces allowed here. This is going to be used as a sql table column field name!
#define UPGRADE_SHORTNAME "fastreload"

bool g_bLateLoaded;

ConVar g_hCVSpeedInc;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Fast Reload",
	author = "Peace-Maker",
	description = "Fast Reload upgrade for SM:RPG. Increases the reload speed of guns.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoaded = late;
	
	EngineVersion engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	if(g_bLateLoaded)
	{
		int iEntities = GetMaxEntities();
		for(int i=MaxClients+1;i<=iEntities;i++)
		{
			// Hook shotguns.
			if(IsValidEntity(i) && HasEntProp(i, Prop_Send, "m_reloadState"))
			{
				SDKHook(i, SDKHook_ReloadPost, Hook_OnReloadPost);
			}
		}
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
		SMRPG_RegisterUpgradeType("Fast Reload", UPGRADE_SHORTNAME, "Increases the reload speed of your guns.", 10, true, 5, 20, 10);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVSpeedInc = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fastreload_speedmult", "0.05", "Speed up reloading of guns by this amount each level.");
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Hook shotguns - they reload differently.
	if(HasEntProp(entity, Prop_Send, "m_reloadState"))
		SDKHook(entity, SDKHook_ReloadPost, Hook_OnReloadPost);
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

// This holds the basic checks you should run before applying your effect.
void IncreaseReloadSpeed(int client)
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
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	
	char sWeapon[64];
	int iWeapon = Client_GetActiveWeaponName(client, sWeapon, sizeof(sWeapon));
	
	//PrintToChatAll("%N is reloading his weapon %d %s.", client, iWeapon, sWeapon);
	
	if(iWeapon == INVALID_ENT_REFERENCE)
		return;
	
	// No shotgun?
	bool bIsShotgun = HasEntProp(iWeapon, Prop_Send, "m_reloadState");
	if(bIsShotgun)
	{
		int iReloadState = GetEntProp(iWeapon, Prop_Send, "m_reloadState");
		// The shotgun isn't really reloading. (full or no ammo left)
		if(iReloadState == 0)
			return;
	}
	
	float fNextAttack = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
	float fGameTime = GetGameTime();
	
	//PrintToChatAll("gametime %f, weapon nextattack %f, player nextattack %f, weapon idletime %f", fGameTime, fNextAttack, GetEntPropFloat(client, Prop_Send, "m_flNextAttack"), GetEntPropFloat(iWeapon, Prop_Send, "m_flTimeWeaponIdle"));
	
	float fReloadIncrease = 1.0 / (1.0 + float(iLevel) * g_hCVSpeedInc.FloatValue);
	
	// Change the playback rate of the weapon to see it reload faster visually
	SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0 / fReloadIncrease);
	
	int iViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	if(iViewModel != INVALID_ENT_REFERENCE)
		SetEntPropFloat(iViewModel, Prop_Send, "m_flPlaybackRate", 1.0 / fReloadIncrease);
	
	float fNextAttackNew = (fNextAttack - fGameTime) * fReloadIncrease;
	
	if(bIsShotgun)
	{
		DataPack hData;
		CreateDataTimer(0.01, Timer_CheckShotgunEnd, hData, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		hData.WriteCell(EntIndexToEntRef(iWeapon));
		hData.WriteCell(GetClientUserId(client));
	}
	else
	{
		// Reset the playback rate after the gun reloaded.
		DataPack hData;
		CreateDataTimer(fNextAttackNew, Timer_ResetPlaybackRate, hData, TIMER_FLAG_NO_MAPCHANGE);
		hData.WriteCell(EntIndexToEntRef(iWeapon));
		hData.WriteCell(GetClientUserId(client));
	}
	
	// Tell the gun it can fire ammo faster again after reload
	// This acutally decreases the reload time
	fNextAttackNew += fGameTime;
	SetEntPropFloat(iWeapon, Prop_Send, "m_flTimeWeaponIdle", fNextAttackNew);
	SetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack", fNextAttackNew);
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", fNextAttackNew);
	
	//PrintToChatAll("new nextattack %f, client nextattack %f, weapon idletime %f", fNextAttackNew, GetEntPropFloat(client, Prop_Send, "m_flNextAttack"), GetEntPropFloat(iWeapon, Prop_Send, "m_flTimeWeaponIdle"));
}

public Action Timer_ResetPlaybackRate(Handle timer, DataPack data)
{
	data.Reset();
	
	int iWeapon = EntRefToEntIndex(data.ReadCell());
	int client = GetClientOfUserId(data.ReadCell());
	
	if(iWeapon != INVALID_ENT_REFERENCE)	
		SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0);
	
	if(client > 0)
		ResetClientViewModel(client);
	
	//PrintToChatAll("Reset playback rate of %d and client %d", iWeapon, client);
	
	return Plugin_Stop;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	static bool s_ClientIsReloading[MAXPLAYERS+1];
	if(!IsClientInGame(client))
		return Plugin_Continue;

	char sWeapon[64];
	int iWeapon = Client_GetActiveWeaponName(client, sWeapon, sizeof(sWeapon));
	if(iWeapon == INVALID_ENT_REFERENCE)
		return Plugin_Continue;
	
	bool bIsReloading = Weapon_IsReloading(iWeapon);
	// Shotguns don't use m_bInReload but have their own m_reloadState
	if(!bIsReloading && HasEntProp(iWeapon, Prop_Send, "m_reloadState") && GetEntProp(iWeapon, Prop_Send, "m_reloadState") > 0)
		bIsReloading = true;
	
	if(bIsReloading && !s_ClientIsReloading[client])
	{
		IncreaseReloadSpeed(client);
	}
	
	s_ClientIsReloading[client] = bIsReloading;
	
	return Plugin_Continue;
}

public Action Timer_CheckShotgunEnd(Handle timer, DataPack data)
{
	data.Reset();
	
	int iWeapon = EntRefToEntIndex(data.ReadCell());
	int client = GetClientOfUserId(data.ReadCell());
	
	// Weapon is gone?!
	if(iWeapon == INVALID_ENT_REFERENCE)
	{
		if(client > 0)
			ResetClientViewModel(client);
		return Plugin_Stop;
	}
	
	int iOwner = Weapon_GetOwner(iWeapon);
	// Weapon dropped?
	if(iOwner <= 0)
	{
		// Reset the old client
		if(client > 0)
			ResetClientViewModel(client);
		
		// Reset weapon.
		SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0);
		
		return Plugin_Stop;
	}

	int iReloadState = GetEntProp(iWeapon, Prop_Send, "m_reloadState");
	
	// Still reloading
	if(iReloadState > 0)
		return Plugin_Continue;
	
	// Done reloading.
	SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0);
	
	
	if(client > 0)
		ResetClientViewModel(client);
	
	//PrintToChatAll("%N reloaded shotgun %d", client, iWeapon);
	
	return Plugin_Stop;
}

// Increase shotgun reload
public void Hook_OnReloadPost(int weapon, bool bSuccessful)
{
	int client = Weapon_GetOwner(weapon);
	if(client <= 0)
		return;
	
	if(GetEntProp(weapon, Prop_Send, "m_reloadState") != 2)
		return;
	
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
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Fasten reload!
	float fReloadIncrease = 1.0 / (1.0 + float(iLevel) * g_hCVSpeedInc.FloatValue);
	
	float fIdleTime = GetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle");
	float fGameTime = GetGameTime();
	float fIdleTimeNew = (fIdleTime - fGameTime) * fReloadIncrease + fGameTime;
	// This is the next time Reload is called for shotguns
	SetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle", fIdleTimeNew);
	
	//PrintToChatAll("%d reloadpost, success %d, reloadstate %d, gametime %f, wep nextattack %f, orig idle: %f, idle %f, clip1 %d, nextthink %d", weapon, bSuccessful, GetEntProp(weapon, Prop_Send, "m_reloadState"), GetGameTime(), GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack"), fIdleTime, GetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle"), Weapon_GetPrimaryClip(weapon), GetEntProp(weapon, Prop_Send, "m_nNextThinkTick"));
}

stock void ResetClientViewModel(int client)
{
	int iViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	if(iViewModel != INVALID_ENT_REFERENCE)
		SetEntPropFloat(iViewModel, Prop_Send, "m_flPlaybackRate", 1.0);
}