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
#include <smrpg>
#include <smlib>

// Change the upgrade's shortname to a descriptive abbrevation
// No spaces allowed here. This is going to be used as a sql table column field name!
#define UPGRADE_SHORTNAME "fastreload"
#define PLUGIN_VERSION "1.0"

new bool:g_bLateLoaded;

new Handle:g_hCVSpeedInc;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Fast Reload",
	author = "Peace-Maker",
	description = "Fast Reload upgrade for SM:RPG. Increases the reload speed of guns.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	g_bLateLoaded = late;
	
	if(GetEngineVersion() != Engine_CSS)
	{
		Format(error, err_max, "This plugin is for CS:S only.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	if(g_bLateLoaded)
	{
		new iEntities = GetMaxEntities();
		decl String:sClassname[64];
		for(new i=MaxClients+1;i<=iEntities;i++)
		{
			if(IsValidEntity(i) && GetEntityClassname(i, sClassname, sizeof(sClassname)) && (StrEqual(sClassname, "weapon_m3") || StrEqual(sClassname, "weapon_xm1014")))
			{
				SDKHook(i, SDKHook_ReloadPost, Hook_OnReloadPost);
			}
		}
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
		SMRPG_RegisterUpgradeType("Fast Reload", UPGRADE_SHORTNAME, "Increases the reload speed of your guns.", 10, true, 5, 20, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVSpeedInc = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_fastreload_speedmult", "0.05", "Speed up reloading of guns by this amount each level.");
	}
}

public OnEntityCreated(entity, const String:classname[])
{
	if(StrEqual(classname, "weapon_m3") || StrEqual(classname, "weapon_xm1014"))
		SDKHook(entity, SDKHook_ReloadPost, Hook_OnReloadPost);
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

// This holds the basic checks you should run before applying your effect.
IncreaseReloadSpeed(client)
{
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return;
	
	// The upgrade is disabled completely?
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	
	new String:sWeapon[64];
	new iWeapon = Client_GetActiveWeaponName(client, sWeapon, sizeof(sWeapon));
	
	//PrintToChatAll("%N is reloading his weapon %d %s.", client, iWeapon, sWeapon);
	
	if(iWeapon == INVALID_ENT_REFERENCE)
		return;
	
	// No shotgun?
	new bool:bIsShotgun;
	if(StrEqual(sWeapon, "weapon_m3") || StrEqual(sWeapon, "weapon_xm1014"))
	{
		new iReloadState = GetEntProp(iWeapon, Prop_Send, "m_reloadState");
		// The shotgun isn't really reloading. (full or no ammo left)
		if(iReloadState == 0)
			return;
		
		bIsShotgun = true;
	}
	
	new Float:fNextAttack = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
	new Float:fGameTime = GetGameTime();
	
	//PrintToChatAll("gametime %f, weapon nextattack %f, player nextattack %f, weapon idletime %f", fGameTime, fNextAttack, GetEntPropFloat(client, Prop_Send, "m_flNextAttack"), GetEntPropFloat(iWeapon, Prop_Send, "m_flTimeWeaponIdle"));
	
	new Float:fReloadIncrease = 1.0 / (1.0 + float(iLevel) * GetConVarFloat(g_hCVSpeedInc));
	
	// Change the playback rate of the weapon to see it reload faster visually
	SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0 / fReloadIncrease);
	
	new iViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	if(iViewModel != INVALID_ENT_REFERENCE)
		SetEntPropFloat(iViewModel, Prop_Send, "m_flPlaybackRate", 1.0 / fReloadIncrease);
	
	new Float:fNextAttackNew = (fNextAttack - fGameTime) * fReloadIncrease;
	
	if(bIsShotgun)
	{
		new Handle:hData;
		CreateDataTimer(0.01, Timer_CheckShotgunEnd, hData, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		WritePackCell(hData, EntIndexToEntRef(iWeapon));
		WritePackCell(hData, GetClientUserId(client));
	}
	else
	{
		// Reset the playback rate after the gun reloaded.
		new Handle:hData;
		CreateDataTimer(fNextAttackNew, Timer_ResetPlaybackRate, hData, TIMER_FLAG_NO_MAPCHANGE);
		WritePackCell(hData, EntIndexToEntRef(iWeapon));
		WritePackCell(hData, GetClientUserId(client));
	}
	
	// Tell the gun it can fire ammo faster again after reload
	// This acutally decreases the reload time
	fNextAttackNew += fGameTime;
	SetEntPropFloat(iWeapon, Prop_Send, "m_flTimeWeaponIdle", fNextAttackNew);
	SetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack", fNextAttackNew);
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", fNextAttackNew);
	
	//PrintToChatAll("new nextattack %f, client nextattack %f, weapon idletime %f", fNextAttackNew, GetEntPropFloat(client, Prop_Send, "m_flNextAttack"), GetEntPropFloat(iWeapon, Prop_Send, "m_flTimeWeaponIdle"));
}

public Action:Timer_ResetPlaybackRate(Handle:timer, any:data)
{
	ResetPack(data);
	
	new iWeapon = EntRefToEntIndex(ReadPackCell(data));
	new client = GetClientOfUserId(ReadPackCell(data));
	
	if(iWeapon != INVALID_ENT_REFERENCE)	
		SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0);
	
	if(client > 0)
		ResetClientViewModel(client);
	
	//PrintToChatAll("Reset playback rate of %d and client %d", iWeapon, client);
	
	return Plugin_Stop;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2])
{
	static bool:s_ClientIsReloading[MAXPLAYERS+1];
	if(!IsClientInGame(client))
		return Plugin_Continue;

	new String:sWeapon[64];
	new iWeapon = Client_GetActiveWeaponName(client, sWeapon, sizeof(sWeapon));
	if(iWeapon == INVALID_ENT_REFERENCE)
		return Plugin_Continue;
	
	new bool:bIsReloading = Weapon_IsReloading(iWeapon);
	// Shotguns don't use m_bInReload but have their own m_reloadState
	if(!bIsReloading && (StrEqual(sWeapon, "weapon_m3") || StrEqual(sWeapon, "weapon_xm1014")) && GetEntProp(iWeapon, Prop_Send, "m_reloadState") > 0)
		bIsReloading = true;
	
	if(bIsReloading && !s_ClientIsReloading[client])
	{
		IncreaseReloadSpeed(client);
	}
	
	s_ClientIsReloading[client] = bIsReloading;
	
	return Plugin_Continue;
}

public Action:Timer_CheckShotgunEnd(Handle:timer, any:data)
{
	ResetPack(data);
	
	new iWeapon = EntRefToEntIndex(ReadPackCell(data));
	new client = GetClientOfUserId(ReadPackCell(data));
	
	// Weapon is gone?!
	if(iWeapon == INVALID_ENT_REFERENCE)
	{
		if(client > 0)
			ResetClientViewModel(client);
		return Plugin_Stop;
	}
	
	new iOwner = Weapon_GetOwner(iWeapon);
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

	new iReloadState = GetEntProp(iWeapon, Prop_Send, "m_reloadState");
	
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
public Hook_OnReloadPost(weapon, bool:bSuccessful)
{
	new client = Weapon_GetOwner(weapon);
	if(client <= 0)
		return;
	
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return;
	
	// The upgrade is disabled completely?
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Fasten reload!
	new Float:fReloadIncrease = 1.0 / (1.0 + float(iLevel) * GetConVarFloat(g_hCVSpeedInc));
	
	new Float:fIdleTime = GetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle");
	new Float:fGameTime = GetGameTime();
	new Float:fIdleTimeNew = (fIdleTime - fGameTime) * fReloadIncrease + fGameTime;
	// This is the next time Reload is called for shotguns
	SetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle", fIdleTimeNew);
	
	//PrintToChatAll("%d reloadpost, success %d, reloadstate %d, gametime %f, wep nextattack %f, idle %f, clip1 %d, nextthink %d", weapon, bSuccessful, GetEntProp(weapon, Prop_Send, "m_reloadState"), GetGameTime(), GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack"), GetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle"), Weapon_GetPrimaryClip(weapon), GetEntProp(weapon, Prop_Send, "m_nNextThinkTick"));
}

stock ResetClientViewModel(client)
{
	new iViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	if(iViewModel != INVALID_ENT_REFERENCE)
		SetEntPropFloat(iViewModel, Prop_Send, "m_flPlaybackRate", 1.0);
}