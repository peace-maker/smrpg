#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

//#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "grenaderesup"


#define GRENADE_CLASSNAME_LENGTH 64

enum struct GrenadeEntry {
	int index;
	float baseDelay;
	float decrease;
	float minDelay;
	int ammoType;
	char classname[GRENADE_CLASSNAME_LENGTH];
}

enum struct PlayerGrenade {
	Handle timer;
	int ammo;
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
	g_hGrenadeConfig = new ArrayList(sizeof(GrenadeEntry));
	
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
		GrenadeEntry grenadeEntry;
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
	
	GrenadeEntry grenadeEntry;
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
	
	GrenadeEntry grenadeEntry;
	if(!GetGrenadeEntryByName(sClassname, grenadeEntry))
		return;
	
	// See if we got the ammo type yet.
	CheckGrenadeAmmoType(weapon, grenadeEntry);
	
	PlayerGrenade playerGrenade;
	GetPlayerGrenadeByIndex(client, grenadeEntry.index, playerGrenade);
	
	int iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry.ammoType);
	
	// Remember the maximum amount of grenades of this type the player ever owned.
	// So we can keep regenerating nades until we are at that maximum again.
	if(playerGrenade.ammo < iPrimaryAmmo)
	{
		playerGrenade.ammo = iPrimaryAmmo;
		SavePlayerGrenadeByIndex(client, grenadeEntry.index, playerGrenade);
	}
	
	// The player got enough grenades on his own now.
	// No need to keep the timer running.
	if(iPrimaryAmmo == playerGrenade.ammo)
	{
		ClearHandle(playerGrenade.timer);
		SavePlayerGrenadeByIndex(client, grenadeEntry.index, playerGrenade);
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
	
	GrenadeEntry grenadeEntry;
	GetGrenadeEntryByIndex(iEntryIndex, grenadeEntry);
	
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Handled;
	
	PlayerGrenade playerGrenade;
	GetPlayerGrenadeByIndex(client, iEntryIndex, playerGrenade);
	playerGrenade.timer = null;
	SavePlayerGrenadeByIndex(client, iEntryIndex, playerGrenade);
	
	if(!IsPlayerAlive(client) || IsClientObserver(client))
		return Plugin_Handled;
	
	// The player already picked up enough grenades by himself?
	// Don't give more!
	int iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry.ammoType);
	if(iPrimaryAmmo >= playerGrenade.ammo)
		return Plugin_Handled;
	
	// Give the grenade!
	GivePlayerItem(client, grenadeEntry.classname);
	
	iPrimaryAmmo = GetClientAmmoOfType(client, grenadeEntry.ammoType);
	// Did he have more grenades at once one time ago?
	if(iPrimaryAmmo < playerGrenade.ammo)
	{
		// Start next resupply timer right away.
		StartGrenadeResupplyTimer(client, grenadeEntry);
	}
	return Plugin_Handled;
}

/**
 * Helpers
 */

void StartGrenadeResupplyTimer(int client, GrenadeEntry grenadeEntry)
{
	// SMRPG and upgrade enabled?
	if(!SMRPG_IsEnabled())
		return;
	
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
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
	if(fTime < grenadeEntry.minDelay)
		fTime = grenadeEntry.minDelay;
	
	PlayerGrenade playerGrenade;
	GetPlayerGrenadeByIndex(client, grenadeEntry.index, playerGrenade);
	
	// This player didn't throw a grenade of this type previously.
	if(playerGrenade.timer == null)
	{
		// Handle case of lateloading or not catching the equip of this grenade.
		if(playerGrenade.ammo < 1)
			playerGrenade.ammo = 1;
		DataPack hPack;
		playerGrenade.timer = CreateDataTimer(fTime, Timer_ResupplyPlayer, hPack, TIMER_FLAG_NO_MAPCHANGE);
		hPack.WriteCell(GetClientUserId(client));
		hPack.WriteCell(grenadeEntry.index);
		
		SavePlayerGrenadeByIndex(client, grenadeEntry.index, playerGrenade);
	}
}

// Load the config file and clear the cache.
bool LoadResupplyDelayConfig()
{
	g_hGrenadeConfig.Clear();
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(!g_PlayerGrenades[i])
			g_PlayerGrenades[i] = new ArrayList(sizeof(PlayerGrenade));
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
	
	PlayerGrenade playerGrenade;
	
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
		
		GrenadeEntry grenadeEntry;
		strcopy(grenadeEntry.classname, GRENADE_CLASSNAME_LENGTH, sBuffer);
		grenadeEntry.ammoType = -1;
		grenadeEntry.baseDelay = hKV.GetFloat("resupply_base_delay", -1.0);
		grenadeEntry.minDelay = hKV.GetFloat("resupply_minimum_delay", 0.0);
		grenadeEntry.decrease = hKV.GetFloat("resupply_delay_decrease", -1.0);
		
		grenadeEntry.index = GetArraySize(g_hGrenadeConfig);
		g_hGrenadeConfig.PushArray(grenadeEntry, sizeof(GrenadeEntry));
		
		for(int i=1;i<=MaxClients;i++)
		{
			g_PlayerGrenades[i].PushArray(playerGrenade, sizeof(PlayerGrenade));
		}
	} while(hKV.GotoNextKey());
	
	delete hKV;
	return true;
}

/**
 * Datastructure accessor helpers
 */
void GetGrenadeEntryByIndex(int iIndex, GrenadeEntry grenadeEntry)
{
	g_hGrenadeConfig.GetArray(iIndex, grenadeEntry, sizeof(GrenadeEntry));
}

bool GetGrenadeEntryByName(const char[] sClassname, GrenadeEntry grenadeEntry)
{
	int iSize = GetArraySize(g_hGrenadeConfig);
	for(int i=0;i<iSize;i++)
	{
		GetGrenadeEntryByIndex(i, grenadeEntry);
		if(StrContains(grenadeEntry.classname, sClassname, false) != -1)
			return true;
	}
	return false;
}

void GetPlayerGrenadeByIndex(int client, int iEntryIndex, PlayerGrenade playerGrenade)
{
	g_PlayerGrenades[client].GetArray(iEntryIndex, playerGrenade, sizeof(PlayerGrenade));
}

void SavePlayerGrenadeByIndex(int client, int iEntryIndex, PlayerGrenade playerGrenade)
{
	g_PlayerGrenades[client].SetArray(iEntryIndex, playerGrenade, sizeof(PlayerGrenade));
}

float GetGrenadeBaseDelay(GrenadeEntry grenadeEntry)
{
	if(grenadeEntry.baseDelay < 0.0)
		return g_fDefaultDelay;
	return grenadeEntry.baseDelay;
}

float GetGrenadeDelayDecrease(GrenadeEntry grenadeEntry)
{
	if(grenadeEntry.decrease < 0.0)
		return g_fDefaultDecrease;
	return grenadeEntry.decrease;
}

// Cache the ammo type of the grenade.
void CheckGrenadeAmmoType(int entity, GrenadeEntry grenadeEntry)
{
	if(grenadeEntry.ammoType >= 0)
		return;
	
	grenadeEntry.ammoType = Weapon_GetPrimaryAmmoType(entity);
	g_hGrenadeConfig.SetArray(grenadeEntry.index, grenadeEntry, sizeof(GrenadeEntry));
}

int GetClientAmmoOfType(int client, int iAmmoType)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", 4, iAmmoType);
}

void ResetResupplyTimers(int client, bool bResetAmmo)
{
	int iSize = GetArraySize(g_PlayerGrenades[client]);
	PlayerGrenade playerGrenade;
	for(int i=0;i<iSize;i++)
	{
		GetPlayerGrenadeByIndex(client, i, playerGrenade);
		ClearHandle(playerGrenade.timer);
		if(bResetAmmo)
			playerGrenade.ammo = 0;
		SavePlayerGrenadeByIndex(client, i, playerGrenade);
	}
}