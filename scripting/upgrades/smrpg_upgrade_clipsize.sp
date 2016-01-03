/**
 * SM:RPG Increase Clipsize
 * Increases the clipsize of weapons.
 * 
 * Could be done nicer with hooks on CBaseCombatWeapon::GetMaxClip1 and CBaseCombatWeapon::GetDefaultClip1, but gamedata..
 * Still needs the "reload when clip1 == original maxclip1" fix as well as the onbuy/sell stuff.
 * Need to cache the current maxclip1 for the weapon. GetMaxClip1 and GetDefaultClip1 get called quite often.
 * The current implementation without gamedata subtracts the additional ammo in clip1 from the backpack ammo too. If that's wanted, it needs to be reimplemented in the gamedata version too..
 */
#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <sdkhooks>
#include <smlib>

#define UPGRADE_SHORTNAME "clipsize"
#define PLUGIN_VERSION "1.0"

new g_iGameMaxClip1[2048];
new bool:g_bWeaponReloadOnFull[2048];
new Handle:g_hWeaponTrie;

new bool:g_bLateLoaded;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Increase Clipsize",
	author = "Peace-Maker",
	description = "Increase Clipsize upgrade for SM:RPG. Increases the clipsize of weapons.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	g_hWeaponTrie = CreateTrie();
	g_bLateLoaded = late;
	
	if(!LoadWeaponAmmoConfig())
	{
		Format(error, err_max, "Can't read config file in configs/smrpg/clipsize_weapons.cfg!");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	if(g_bLateLoaded)
	{
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i))
				OnClientPutInServer(i);
		}
		
		new iEntities = GetMaxEntities();
		decl String:sClassname[64], iClipIncrease;
		for(new i=MaxClients+1;i<=iEntities;i++)
		{
			if(IsValidEntity(i) && GetEntityClassname(i, sClassname, sizeof(sClassname)) && GetTrieValue(g_hWeaponTrie, sClassname, iClipIncrease))
			{
				SDKHook(i, SDKHook_Reload, Hook_OnReload);
				SDKHook(i, SDKHook_ReloadPost, Hook_OnReloadPost);
				// TODO: Apply new maxclips directly for weapons being held by players.
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
		SMRPG_RegisterUpgradeType("Increase Clipsize", UPGRADE_SHORTNAME, "Increases the size of a weapon's clip.", 0, true, 2, 30, 30, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnEntityCreated(entity, const String:classname[])
{
	if(entity >= 2048)
		return;
	
	new iClipIncrease;
	if(GetTrieValue(g_hWeaponTrie, classname, iClipIncrease))
		SDKHook(entity, SDKHook_SpawnPost, Hook_OnSpawnPost);
}

public OnEntityDestroyed(entity)
{
	if(entity > 0 && entity < 2048)
	{
		g_bWeaponReloadOnFull[entity] = false;
		g_iGameMaxClip1[entity] = 0;
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_OnWeaponEquipPost);
	SDKHook(client, SDKHook_WeaponDropPost, Hook_OnWeaponDropPost);
}

public OnMapEnd()
{
	if(!LoadWeaponAmmoConfig())
		SetFailState("Can't read config file in configs/smrpg/clipsize_weapons.cfg!");
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	if(!client || !IsClientInGame(client))
		return;
	
	new iClipIncrease, iNewMaxClip, iClip1, iAmmoCount;
	decl String:sWeapon[64];
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	LOOP_CLIENTWEAPONS(client, iWeapon, i)
	{
		if(g_iGameMaxClip1[iWeapon] <= 0)
			continue;
		
		GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
		if(!GetTrieValue(g_hWeaponTrie, sWeapon, iClipIncrease))
			continue;
		
		iNewMaxClip = g_iGameMaxClip1[iWeapon]+iClipIncrease*iLevel;
		iClip1 = Weapon_GetPrimaryClip(iWeapon);
		
		iAmmoCount = 0;
		Client_GetWeaponPlayerAmmoEx(client, iWeapon, iAmmoCount);
		
		switch(type)
		{
			case UpgradeQueryType_Buy:
			{
				new iIncrease = iNewMaxClip - iClip1;
				
				// Make sure we set the clip to the new size right away as a visual effect, if the player currently has a full clip.
				if(iClip1 == (iNewMaxClip-iClipIncrease))
				{
					// Player doesn't have enough ammo for a whole reload, see how much we can add
					if(iAmmoCount < iIncrease)
						iIncrease = iAmmoCount;
					
					Weapon_SetPrimaryClip(iWeapon, iClip1+iIncrease);
					Client_SetWeaponPlayerAmmoEx(client, iWeapon, iAmmoCount-iIncrease);
				}
			}
			case UpgradeQueryType_Sell:
			{
				// If he still got more ammo in the current clip, set it to the new limit and give him his ammo back.
				if(iClip1 > iNewMaxClip)
				{
					Weapon_SetPrimaryClip(iWeapon, iNewMaxClip);
					Client_SetWeaponPlayerAmmoEx(client, iWeapon, iAmmoCount+(iClip1-iNewMaxClip));
				}
			}
		}
	}
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
 * SDKHook callbacks
 */

public Hook_OnSpawnPost(entity)
{
	RequestFrame(Frame_GetGameMaxClip1, EntIndexToEntRef(entity));
	SDKHook(entity, SDKHook_Reload, Hook_OnReload);
	SDKHook(entity, SDKHook_ReloadPost, Hook_OnReloadPost);
}

public Hook_OnWeaponDropPost(client, weapon)
{
	if(client <= 0 || weapon < 0)
		return;
	
	if(g_iGameMaxClip1[weapon] <= 0)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Restore the original game's default maxclip1, if the weapon currently has more ammo loaded.
	// So other players don't get the same upgrade as the previous owner of the weapon.
	// TODO: DO WE WANT THAT? CONFIG OPTION?
	new iClip1 = Weapon_GetPrimaryClip(weapon);
	if(iClip1 > g_iGameMaxClip1[weapon])
	{
		Weapon_SetPrimaryClip(weapon, g_iGameMaxClip1[weapon]);
		// Also give the player the extra ammo back, so he doesn't lose ammo when dropping the gun and picking it up again.
		new iPrimaryAmmo;
		Client_GetWeaponPlayerAmmoEx(client, weapon, iPrimaryAmmo);
		Client_SetWeaponPlayerAmmoEx(client, weapon, iPrimaryAmmo + (iClip1 - g_iGameMaxClip1[weapon]));
	}
	
	return;
}

public Hook_OnWeaponEquipPost(client, weapon)
{
	if(!client || !IsClientInGame(client) || weapon < 0)
		return;
	
	// Weapon wasn't spawned completely yet. Can happen when buying a weapon. It's already equipped before it's spawned.
	if(g_iGameMaxClip1[weapon] <= 0)
		return;
	
	if(!IsUpgradeActive(client))
		return;
	
	new iClip1 = Weapon_GetPrimaryClip(weapon);
	if(iClip1 == g_iGameMaxClip1[weapon])
		CreateTimer(0.1, Timer_SetEquipAmmo, EntIndexToEntRef(weapon), TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Hook_OnReload(weapon)
{
	new client = Weapon_GetOwner(weapon);
	if(client <= 0)
		return Plugin_Continue;
	
	new iClipIncrease;
	decl String:sWeapon[64];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));
	if(!GetTrieValue(g_hWeaponTrie, sWeapon, iClipIncrease))
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	iClipIncrease *= iLevel;
	
	new iNewMaxClip = g_iGameMaxClip1[weapon]+iClipIncrease;
	
	// Don't reload if we're at the new virtual max clipsize!
	new iClip1 = Weapon_GetPrimaryClip(weapon);
	if(iClip1 == iNewMaxClip)
		return Plugin_Handled;
	
	// The game doesn't reload the weapon, if it is on maxclip already.
	// Modifiy the clip right before it tries to reload, so it actually does :S
	if(iClip1 == g_iGameMaxClip1[weapon])
	{
		Weapon_SetPrimaryClip(weapon, g_iGameMaxClip1[weapon]-1);
		g_bWeaponReloadOnFull[weapon] = true;
	}
	
	return Plugin_Continue;
}

public Hook_OnReloadPost(weapon, bool:bSuccessful)
{
	// Readd the bullet we removed previously, so we trick the game into reloading a full weapon ;)
	if(g_bWeaponReloadOnFull[weapon])
	{
		Weapon_SetPrimaryClip(weapon, g_iGameMaxClip1[weapon]);
		g_bWeaponReloadOnFull[weapon] = false;
	}
	
	if(!bSuccessful)
		return;
	
	new client = Weapon_GetOwner(weapon);
	if(client <= 0)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, EntIndexToEntRef(weapon));
	WritePackCell(hPack, Weapon_GetPrimaryClip(weapon));
	CreateTimer(0.1, Timer_CheckReloadFinish, hPack, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT|TIMER_DATA_HNDL_CLOSE);
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(!IsUpgradeActive(client))
		return;
	
	CreateTimer(0.5, Timer_SetWeaponsClips, userid, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * RequestFrame callbacks
 */
public Frame_GetGameMaxClip1(any:entity)
{
	entity = EntRefToEntIndex(entity);
	if(entity == INVALID_ENT_REFERENCE)
		return;
	
	g_iGameMaxClip1[entity] = Weapon_GetPrimaryClip(entity);
	
	// If this weapon already has an owner right after it spawned it was probably bought.
	// Weapons are equipped before spawning them when buying them.
	new client = Weapon_GetOwner(entity);
	if(client > 0)
		Hook_OnWeaponEquipPost(client, entity);
}

/**
 * Timer callbacks
 */
public Action:Timer_SetEquipAmmo(Handle:timer, any:weapon)
{
	weapon = EntRefToEntIndex(weapon);
	if(weapon == INVALID_ENT_REFERENCE)
		return Plugin_Stop;
	
	new client = Weapon_GetOwner(weapon);
	if(client <= 0)
		return Plugin_Stop;
	
	new iClipIncrease;
	decl String:sWeapon[64];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));
	if(!GetTrieValue(g_hWeaponTrie, sWeapon, iClipIncrease))
		return Plugin_Stop;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Stop;
	
	iClipIncrease *= iLevel;
	
	new iAmmoCount;
	Client_GetWeaponPlayerAmmoEx(client, weapon, iAmmoCount);
	if(iAmmoCount < iClipIncrease)
		iClipIncrease = iAmmoCount;
	
	Weapon_SetPrimaryClip(weapon, Weapon_GetPrimaryClip(weapon)+iClipIncrease);
	Client_SetWeaponPlayerAmmoEx(client, weapon, iAmmoCount-iClipIncrease);
	return Plugin_Stop;
}

public Action:Timer_CheckReloadFinish(Handle:timer, any:data)
{
	ResetPack(data);
	new weapon = EntRefToEntIndex(ReadPackCell(data));
	new iPreReloadClip1 = ReadPackCell(data);
	
	if(!IsValidEntity(weapon))
		return Plugin_Stop;
	
	// Wait until it's finished..
	if(Weapon_IsReloading(weapon))
		return Plugin_Continue;
	
	new client = Weapon_GetOwner(weapon);
	if(client <= 0)
		return Plugin_Stop;
	
	// Player changed weapons after starting to reload? :(
	if(Client_GetActiveWeapon(client) != weapon)
		return Plugin_Stop;
	
	new iClip1 = Weapon_GetPrimaryClip(weapon);
	// Support for learning new maxclip value for late-loading.
	if(g_iGameMaxClip1[weapon] == 0)
		g_iGameMaxClip1[weapon] = iClip1;
	
	// Weapon still had more ammo than the default max.
	if(iClip1 < iPreReloadClip1)
		iClip1 = iPreReloadClip1;
	
	// There is less ammo in the clip than after an usual full reload. The player doesn't have enough ammo for the default clipsize already.. Don't try to add even more!
	if(iClip1 < g_iGameMaxClip1[weapon])
		return Plugin_Stop;
	
	// Get the weapon's clip increase from the config file
	new iClipIncrease;
	decl String:sWeapon[64];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));
	if(!GetTrieValue(g_hWeaponTrie, sWeapon, iClipIncrease))
		return Plugin_Continue;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	iClipIncrease *= iLevel;
	
	new iNewMaxClip = g_iGameMaxClip1[weapon]+iClipIncrease;
	
	// How many bullets do we need to add to match the new virtual max clipsize?
	new iIncrease = iNewMaxClip - iClip1;
	
	new iAmmoCount;
	Client_GetWeaponPlayerAmmoEx(client, weapon, iAmmoCount);
	// Player doesn't have enough ammo for a whole reload, see how much we can add
	if(iAmmoCount < iIncrease)
		iIncrease = iAmmoCount;
	
	// No ammo left for us :(
	if(iIncrease == 0)
		return Plugin_Stop;
	
	Weapon_SetPrimaryClip(weapon, iClip1+iIncrease);
	Client_SetWeaponPlayerAmmoEx(client, weapon, iAmmoCount-iIncrease);
	return Plugin_Stop;
}

// Make sure the correct ammo is set after the player respawned
public Action:Timer_SetWeaponsClips(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	new iClipIncrease, iNewMaxClip, iClip1, iAmmoCount;
	decl String:sWeapon[64];
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	LOOP_CLIENTWEAPONS(client, iWeapon, i)
	{
		if(g_iGameMaxClip1[iWeapon] <= 0)
			continue;
		
		GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
		if(!GetTrieValue(g_hWeaponTrie, sWeapon, iClipIncrease))
			continue;
		
		iClipIncrease *= iLevel;
		
		iNewMaxClip = g_iGameMaxClip1[iWeapon]+iClipIncrease;
		iClip1 = Weapon_GetPrimaryClip(iWeapon);
		
		if(iClip1 == g_iGameMaxClip1[iWeapon])
		{
			iAmmoCount = 0;
			Client_GetWeaponPlayerAmmoEx(client, iWeapon, iAmmoCount);
			
			new iIncrease = iNewMaxClip - iClip1;
			// Player doesn't have enough ammo for a whole reload, see how much we can add
			if(iAmmoCount < iIncrease)
				iIncrease = iAmmoCount;
			
			Weapon_SetPrimaryClip(iWeapon, iClip1+iIncrease);
			Client_SetWeaponPlayerAmmoEx(client, iWeapon, iAmmoCount-iIncrease);
		}
	}
	
	return Plugin_Continue;
}

/**
 * Helpers
 */
bool:LoadWeaponAmmoConfig()
{
	ClearTrie(g_hWeaponTrie);
	
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/clipsize_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	new Handle:hKV = CreateKeyValues("ClipsizeWeapons");
	if(!FileToKeyValues(hKV, sPath))
	{
		CloseHandle(hKV);
		return false;
	}
	
	decl String:sWeapon[64], iClipIncrease;
	if(KvGotoFirstSubKey(hKV, false))
	{
		do
		{
			KvGetSectionName(hKV, sWeapon, sizeof(sWeapon));
			iClipIncrease = KvGetNum(hKV, NULL_STRING, 0);
			
			SetTrieValue(g_hWeaponTrie, sWeapon, iClipIncrease);
			
		} while (KvGotoNextKey(hKV, false));
	}
	CloseHandle(hKV);
	return true;
}

bool:IsUpgradeActive(client)
{
	if(!SMRPG_IsEnabled())
		return false;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return false;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return false;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return false;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return false; // Some other plugin doesn't want this effect to run
	
	return true;
}