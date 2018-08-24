#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

//#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "grenaderesup"


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

bool g_bLateLoaded;
ArrayList g_hGrenadeConfig;

float g_fDefaultDelay = 40.0;
float g_fDefaultDecrease = 4.0;

ArrayList g_PlayerGrenades[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Grenade Resupply",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Grenade resupply upgrade for SM:RPG. Regenerates grenades x seconds after you threw them.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	g_bLateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	g_hGrenadeConfig = new ArrayList(view_as<int>(GrenadeEntry));
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("weapon_fire", Event_OnWeaponFire);
	
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
		SMRPG_RegisterUpgradeType("Grenade Resupply", UPGRADE_SHORTNAME, "Regenerates grenades x seconds after you threw them.", 0, true, 5, 5, 15);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public void OnMapStart()
{
	if(!LoadResupplyDelayConfig())
		SetFailState("Can't find or parse the config file in configs/smrpg/grenade_resupply_delay.cfg");
	
	// Handle lateloading and setup our data structures to include grenades players might already own.
	if(g_bLateLoaded)
	{
		char sClassname[GRENADE_CLASSNAME_LENGTH];
		int grenadeEntry[GrenadeEntry];
		for(int i=1;i<=MaxClients;i++)
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

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_OnWeaponEquipPost);
}

public void OnClientDisconnect(int client)
{
	ResetResupplyTimers(client, true);
}

/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	ResetResupplyTimers(client, true);
	// TODO: Apply default amount or start resupplying right away.
	// Maybe put this into the denial upgrade?
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	ResetResupplyTimers(client, true);
}

public void Event_OnWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	char sWeapon[64];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	
	int grenadeEntry[GrenadeEntry];
	if(!GetGrenadeEntryByName(sWeapon, grenadeEntry))
		return;
	
	StartGrenadeResupplyTimer(client, grenadeEntry);
}

/**
 * SM:RPG Upgrade callbacks
 */

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
 * SDK Hooks callbacks
 */
public void Hook_OnWeaponEquipPost(int client, int weapon)
{
	if(client <= 0 || client > MaxClients || !IsClientInGame(client))
		return;

	if(weapon <= 0 || !IsValidEntity(weapon))
		return;
	
	char sClassname[64];
	GetEntityClassname(weapon, sClassname, sizeof(sClassname));
	
	int grenadeEntry[GrenadeEntry];
	if(!GetGrenadeEntryByName(sClassname, grenadeEntry))
		return;
	
	// See if we got the ammo type yet.
	CheckGrenadeAmmoType(weapon, grenadeEntry);
	
	int playerGrenade[PlayerGrenade];
	GetPlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	
	int iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry[GE_ammoType]);
	
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
public Action Timer_ResupplyPlayer(Handle timer, DataPack data)
{
	data.Reset();
	int userid = data.ReadCell();
	int iEntryIndex = data.ReadCell();
	
	int grenadeEntry[GrenadeEntry];
	GetGrenadeEntryByIndex(iEntryIndex, grenadeEntry);
	
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Handled;
	
	int playerGrenade[PlayerGrenade];
	GetPlayerGrenadeByIndex(client, iEntryIndex, playerGrenade);
	playerGrenade[PG_timer] = null;
	SavePlayerGrenadeByIndex(client, iEntryIndex, playerGrenade);
	
	if(!IsPlayerAlive(client) || IsClientObserver(client))
		return Plugin_Handled;
	
	// The player already picked up enough grenades by himself?
	// Don't give more!
	int iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry[GE_ammoType]);
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

void StartGrenadeResupplyTimer(int client, int grenadeEntry[GrenadeEntry])
{
	// SMRPG and upgrade enabled?
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(SMRPG_IgnoreBots() && IsFakeClient(client))
		return;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Calculate the time until we give back the grenade.
	float fTime = GetGrenadeBaseDelay(grenadeEntry) - GetGrenadeDelayDecrease(grenadeEntry) * (iLevel-1);
	if(fTime <= 0.0)
		fTime = 0.1;
	
	// Don't go below this delay. That way other grenades might decrease further, but this grenade stops at some level.
	if(fTime < grenadeEntry[GE_minDelay])
		fTime = grenadeEntry[GE_minDelay];
	
	int playerGrenade[PlayerGrenade];
	GetPlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	
	// This player didn't throw a grenade of this type previously.
	if(playerGrenade[PG_timer] == null)
	{
		// Handle case of lateloading or not catching the equip of this grenade.
		if(playerGrenade[PG_ammo] < 1)
			playerGrenade[PG_ammo] = 1;
		DataPack hPack;
		playerGrenade[PG_timer] = CreateDataTimer(fTime, Timer_ResupplyPlayer, hPack, TIMER_FLAG_NO_MAPCHANGE);
		hPack.WriteCell(GetClientUserId(client));
		hPack.WriteCell(grenadeEntry[GE_index]);
		
		SavePlayerGrenadeByIndex(client, grenadeEntry[GE_index], playerGrenade);
	}
}

// Load the config file and clear the cache.
bool LoadResupplyDelayConfig()
{
	g_hGrenadeConfig.Clear();
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(!g_PlayerGrenades[i])
			g_PlayerGrenades[i] = new ArrayList(view_as<int>(PlayerGrenade));
		else
			g_PlayerGrenades[i].Clear();
	}
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/grenade_resupply_delay.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	KeyValues hKV = new KeyValues("GrenadeResupply");
	if(!hKV)
		return false;
	
	if(!hKV.ImportFromFile(sPath))
	{
		delete hKV;
		return false;
	}
	
	if(!hKV.GotoFirstSubKey())
	{
		delete hKV;
		return false;
	}
	
	int playerGrenade[PlayerGrenade];
	
	char sBuffer[GRENADE_CLASSNAME_LENGTH];
	do
	{
		hKV.GetSectionName(sBuffer, sizeof(sBuffer));
		
		if(StrEqual(sBuffer, "#default", false))
		{
			g_fDefaultDelay = hKV.GetFloat("resupply_base_delay", 40.0);
			g_fDefaultDecrease = hKV.GetFloat("resupply_delay_decrease", 4.0);
			continue;
		}
		
		int grenadeEntry[GrenadeEntry];
		strcopy(grenadeEntry[GE_classname], GRENADE_CLASSNAME_LENGTH, sBuffer);
		grenadeEntry[GE_ammoType] = -1;
		grenadeEntry[GE_baseDelay] = hKV.GetFloat("resupply_base_delay", -1.0);
		grenadeEntry[GE_minDelay] = hKV.GetFloat("resupply_minimum_delay", 0.0);
		grenadeEntry[GE_decrease] = hKV.GetFloat("resupply_delay_decrease", -1.0);
		
		grenadeEntry[GE_index] = GetArraySize(g_hGrenadeConfig);
		g_hGrenadeConfig.PushArray(grenadeEntry[0], view_as<int>(GrenadeEntry));
		
		for(int i=1;i<=MaxClients;i++)
		{
			g_PlayerGrenades[i].PushArray(playerGrenade[0], view_as<int>(PlayerGrenade));
		}
	} while(hKV.GotoNextKey());
	
	delete hKV;
	return true;
}

/**
 * Datastructure accessor helpers
 */
void GetGrenadeEntryByIndex(int iIndex, int grenadeEntry[GrenadeEntry])
{
	g_hGrenadeConfig.GetArray(iIndex, grenadeEntry[0], view_as<int>(GrenadeEntry));
}

bool GetGrenadeEntryByName(const char[] sClassname, int grenadeEntry[GrenadeEntry])
{
	int iSize = GetArraySize(g_hGrenadeConfig);
	for(int i=0;i<iSize;i++)
	{
		GetGrenadeEntryByIndex(i, grenadeEntry);
		if(StrContains(grenadeEntry[GE_classname], sClassname, false) != -1)
			return true;
	}
	return false;
}

void GetPlayerGrenadeByIndex(int client, int iEntryIndex, int playerGrenade[PlayerGrenade])
{
	g_PlayerGrenades[client].GetArray(iEntryIndex, playerGrenade[0], view_as<int>(PlayerGrenade));
}

void SavePlayerGrenadeByIndex(int client, int iEntryIndex, int playerGrenade[PlayerGrenade])
{
	g_PlayerGrenades[client].SetArray(iEntryIndex, playerGrenade[0], view_as<int>(PlayerGrenade));
}

float GetGrenadeBaseDelay(int grenadeEntry[GrenadeEntry])
{
	if(grenadeEntry[GE_baseDelay] < 0.0)
		return g_fDefaultDelay;
	return grenadeEntry[GE_baseDelay];
}

float GetGrenadeDelayDecrease(int grenadeEntry[GrenadeEntry])
{
	if(grenadeEntry[GE_decrease] < 0.0)
		return g_fDefaultDecrease;
	return grenadeEntry[GE_decrease];
}

// Cache the ammo type of the grenade.
void CheckGrenadeAmmoType(int entity, int grenadeEntry[GrenadeEntry])
{
	if(grenadeEntry[GE_ammoType] >= 0)
		return;
	
	grenadeEntry[GE_ammoType] = Weapon_GetPrimaryAmmoType(entity);
	g_hGrenadeConfig.SetArray(grenadeEntry[GE_index], grenadeEntry[0], view_as<int>(GrenadeEntry));
}

int GetClientAmmoOfType(int client, int iAmmoType)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", 4, iAmmoType);
}

void ResetResupplyTimers(int client, bool bResetAmmo)
{
	int iSize = GetArraySize(g_PlayerGrenades[client]);
	int playerGrenade[PlayerGrenade];
	for(int i=0;i<iSize;i++)
	{
		GetPlayerGrenadeByIndex(client, i, playerGrenade);
		ClearHandle(playerGrenade[PG_timer]);
		if(bResetAmmo)
			playerGrenade[PG_ammo] = 0;
		SavePlayerGrenadeByIndex(client, i, playerGrenade);
	}
}