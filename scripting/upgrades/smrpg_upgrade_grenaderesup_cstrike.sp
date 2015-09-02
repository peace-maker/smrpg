#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <smrpg>

#define UPGRADE_SHORTNAME "grenaderesup"

#define PLUGIN_VERSION "1.0"

#define GRENADE_CLASSNAME_LENGTH 64

enum GrenadeEntry {
	GE_index,
	Float:GE_baseDelay,
	Float:GE_decrease,
	Float:GE_minDelay,
	GE_ammoType,
	String:GE_classname[GRENADE_CLASSNAME_LENGTH]
}

enum PlayerGrenade {
	Handle:PG_timer,
	PG_ammo
}

new bool:g_bLateLoaded;
new Handle:g_hGrenadeConfig;

new Float:g_fDefaultDelay = 40.0;
new Float:g_fDefaultDecrease = 4.0;

new Handle:g_PlayerGrenades[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Grenade Resupply",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Grenade resupply upgrade for SM:RPG. Regenerates grenades x seconds after you threw them.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	new EngineVersion:engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	g_bLateLoaded = late;
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	g_hGrenadeConfig = CreateArray(_:GrenadeEntry);
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("weapon_fire", Event_OnWeaponFire);
	
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
		SMRPG_RegisterUpgradeType("Grenade Resupply", UPGRADE_SHORTNAME, "Regenerates grenades x seconds after you threw them.", 20, true, 5, 5, 15, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnMapStart()
{
	if(!LoadResupplyDelayConfig())
		SetFailState("Can't find or parse the config file in configs/smrpg/grenade_resupply_delay.cfg");
	
	// Handle lateloading and setup our data structures to include grenades players might already own.
	if(g_bLateLoaded)
	{
		new String:sClassname[GRENADE_CLASSNAME_LENGTH], grenadeEntry[GrenadeEntry];
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				// See if players already hold some of the grenades we want to resupply.
				LOOP_CLIENTWEAPONS(i, iWeapon, iIndex)
				{
					GetEntityClassname(iWeapon, sClassname, sizeof(sClassname));
					if(!GetGrenadeEntryByName(sClassname, grenadeEntry))
						continue;
					
					Hook_OnWeaponEquipPost(i, iWeapon);
				}
			}
		}
		g_bLateLoaded = false;
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_OnWeaponEquipPost);
}

public OnClientDisconnect(client)
{
	ResetResupplyTimers(client, true);
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	ResetResupplyTimers(client, true);
	// TODO: Apply default amount or start resupplying right away.
	// Maybe put this into the denial upgrade?
}

public Event_OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	ResetResupplyTimers(client, true);
}

public Event_OnWeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	new String:sWeapon[64];
	GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
	
	new grenadeEntry[GrenadeEntry];
	if(!GetGrenadeEntryByName(sWeapon, grenadeEntry))
		return;
	
	StartGrenadeResupplyTimer(client, grenadeEntry);
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
 * SDK Hooks callbacks
 */
public Hook_OnWeaponEquipPost(client, weapon)
{
	if(client <= 0 || client > MaxClients || !IsClientInGame(client))
		return;

	if(weapon <= 0 || !IsValidEntity(weapon))
		return;
	
	decl String:sClassname[64];
	GetEntityClassname(weapon, sClassname, sizeof(sClassname));
	
	new grenadeEntry[GrenadeEntry];
	if(!GetGrenadeEntryByName(sClassname, grenadeEntry))
		return;
	
	// See if we got the ammo type yet.
	CheckGrenadeAmmoType(weapon, grenadeEntry);
	
	new playerGrenade[PlayerGrenade];
	GetPlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	
	new iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry[GE_ammoType]);
	
	// Remember the maximum amount of grenades of this type the player ever owned.
	// So we can keep regenerating nades until we are at that maximum again.
	if(playerGrenade[PG_ammo] < iPrimaryAmmo)
	{
		playerGrenade[PG_ammo] = iPrimaryAmmo;
		SavePlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	}
	
	// The player got enough grenades on his own now.
	// No need to keep the timer running.
	if(iPrimaryAmmo == playerGrenade[PG_ammo])
	{
		ClearHandle(playerGrenade[PG_timer]);
		SavePlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	}
	
	// TODO: Maybe reset resupply timer of a grenade type when a player picks one of up.
}

/**
 * Timer callbacks
 */
public Action:Timer_ResupplyPlayer(Handle:timer, Handle:data)
{
	ResetPack(data);
	new userid = ReadPackCell(data);
	new iEntryIndex = ReadPackCell(data);
	
	new grenadeEntry[GrenadeEntry];
	GetGrenadeEntryByIndex(iEntryIndex, grenadeEntry);
	
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Handled;
	
	new playerGrenade[PlayerGrenade];
	GetPlayerGrenadeByIndex(client, iEntryIndex, playerGrenade);
	playerGrenade[PG_timer] = INVALID_HANDLE;
	SavePlayerGrenadeByIndex(client, iEntryIndex, playerGrenade);
	
	if(!IsPlayerAlive(client))
		return Plugin_Handled;
	
	// The player already picked up enough grenades by himself?
	// Don't give more!
	new iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry[GE_ammoType]);
	if(iPrimaryAmmo >= playerGrenade[PG_ammo])
		return Plugin_Handled;
	
	// Give the grenade!
	GivePlayerItem(client, grenadeEntry[GE_classname]);
	
	iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry[GE_ammoType]);
	// Did he have more grenades at once one time ago?
	if(iPrimaryAmmo < playerGrenade[PG_ammo])
	{
		// Start next resupply timer right away.
		StartGrenadeResupplyTimer(client, grenadeEntry);
	}
	return Plugin_Handled;
}

/**
 * Helpers
 */

StartGrenadeResupplyTimer(client, grenadeEntry[GrenadeEntry])
{
	// SMRPG and upgrade enabled?
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(SMRPG_IgnoreBots() && IsFakeClient(client))
		return;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Calculate the time until we give back the grenade.
	new Float:fTime = GetGrenadeBaseDelay(grenadeEntry) - GetGrenadeDelayDecrease(grenadeEntry) * (iLevel-1);
	if(fTime <= 0.0)
		fTime = 0.1;
	
	// Don't go below this delay. That way other grenades might decrease further, but this grenade stops at some level.
	if(fTime < grenadeEntry[GE_minDelay])
		fTime = grenadeEntry[GE_minDelay];
	
	new playerGrenade[PlayerGrenade];
	GetPlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	
	// This player didn't throw a grenade of this type previously.
	if(playerGrenade[PG_timer] == INVALID_HANDLE)
	{
		// Handle case of lateloading or not catching the equip of this grenade.
		if(playerGrenade[PG_ammo] < 1)
			playerGrenade[PG_ammo] = 1;
		new Handle:hPack;
		playerGrenade[PG_timer] = CreateDataTimer(fTime, Timer_ResupplyPlayer, hPack, TIMER_FLAG_NO_MAPCHANGE);
		WritePackCell(hPack, GetClientUserId(client));
		WritePackCell(hPack, grenadeEntry[GE_index]);
		
		SavePlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	}
}

// Load the config file and clear the cache.
bool:LoadResupplyDelayConfig()
{
	ClearArray(g_hGrenadeConfig);
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(!g_PlayerGrenades[i])
			g_PlayerGrenades[i] = CreateArray(_:PlayerGrenade);
		else
			ClearArray(g_PlayerGrenades[i]);
	}
	
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/grenade_resupply_delay.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	new Handle:hKV = CreateKeyValues("GrenadeResupply");
	if(!hKV)
		return false;
	
	if(!FileToKeyValues(hKV, sPath))
	{
		CloseHandle(hKV);
		return false;
	}
	
	if(!KvGotoFirstSubKey(hKV))
	{
		CloseHandle(hKV);
		return false;
	}
	
	new playerGrenade[PlayerGrenade];
	
	decl String:sBuffer[GRENADE_CLASSNAME_LENGTH];
	do
	{
		KvGetSectionName(hKV, sBuffer, sizeof(sBuffer));
		
		if(StrEqual(sBuffer, "#default", false))
		{
			g_fDefaultDelay = KvGetFloat(hKV, "resupply_base_delay", 40.0);
			g_fDefaultDecrease = KvGetFloat(hKV, "resupply_delay_decrease", 4.0);
			continue;
		}
		
		new grenadeEntry[GrenadeEntry];
		strcopy(grenadeEntry[GE_classname], GRENADE_CLASSNAME_LENGTH, sBuffer);
		grenadeEntry[GE_ammoType] = -1;
		grenadeEntry[GE_baseDelay] = KvGetFloat(hKV, "resupply_base_delay", -1.0);
		grenadeEntry[GE_minDelay] = KvGetFloat(hKV, "resupply_minimum_delay", 0.0);
		grenadeEntry[GE_decrease] = KvGetFloat(hKV, "resupply_delay_decrease", -1.0);
		
		grenadeEntry[GE_index] = GetArraySize(g_hGrenadeConfig);
		PushArrayArray(g_hGrenadeConfig, grenadeEntry[0], _:GrenadeEntry);
		
		for(new i=1;i<=MaxClients;i++)
		{
			PushArrayArray(g_PlayerGrenades[i], playerGrenade[0], _:PlayerGrenade);
		}
	} while(KvGotoNextKey(hKV));
	
	CloseHandle(hKV);
	return true;
}

/**
 * Datastructure accessor helpers
 */
GetGrenadeEntryByIndex(iIndex, grenadeEntry[GrenadeEntry])
{
	GetArrayArray(g_hGrenadeConfig, iIndex, grenadeEntry[0], _:GrenadeEntry);
}

bool:GetGrenadeEntryByName(const String:sClassname[], grenadeEntry[GrenadeEntry])
{
	new iSize = GetArraySize(g_hGrenadeConfig);
	for(new i=0;i<iSize;i++)
	{
		GetGrenadeEntryByIndex(i, grenadeEntry);
		if(StrContains(grenadeEntry[GE_classname], sClassname, false) != -1)
			return true;
	}
	return false;
}

GetPlayerGrenadeByIndex(client, iEntryIndex, playerGrenade[PlayerGrenade])
{
	GetArrayArray(g_PlayerGrenades[client], iEntryIndex, playerGrenade[0], _:PlayerGrenade);
}

SavePlayerGrenadeByIndex(client, iEntryIndex, playerGrenade[PlayerGrenade])
{
	SetArrayArray(g_PlayerGrenades[client], iEntryIndex, playerGrenade[0], _:PlayerGrenade);
}

Float:GetGrenadeBaseDelay(grenadeEntry[GrenadeEntry])
{
	if(grenadeEntry[GE_baseDelay] < 0.0)
		return g_fDefaultDelay;
	return grenadeEntry[GE_baseDelay];
}

Float:GetGrenadeDelayDecrease(grenadeEntry[GrenadeEntry])
{
	if(grenadeEntry[GE_decrease] < 0.0)
		return g_fDefaultDecrease;
	return grenadeEntry[GE_decrease];
}

// Cache the ammo type of the grenade.
CheckGrenadeAmmoType(entity, grenadeEntry[GrenadeEntry])
{
	if(grenadeEntry[GE_ammoType] >= 0)
		return;
	
	grenadeEntry[GE_ammoType] = Weapon_GetPrimaryAmmoType(entity);
	SetArrayArray(g_hGrenadeConfig, grenadeEntry[GE_index], grenadeEntry[0], _:GrenadeEntry);
}

GetClientAmmoOfType(client, iAmmoType)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", 4, iAmmoType);
}

ResetResupplyTimers(client, bool:bResetAmmo)
{
	new iSize = GetArraySize(g_PlayerGrenades[client]);
	new playerGrenade[PlayerGrenade];
	for(new i=0;i<iSize;i++)
	{
		GetPlayerGrenadeByIndex(client, i, playerGrenade);
		ClearHandle(playerGrenade[PG_timer]);
		if(bResetAmmo)
			playerGrenade[PG_ammo] = 0;
		SavePlayerGrenadeByIndex(client, i, playerGrenade);
	}
}