#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smlib>
#include <smrpg>

#define UPGRADE_SHORTNAME "resup"

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Resupply",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Resupply upgrade for SM:RPG. Regenerates ammo every third second.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// https://bugs.alliedmods.net/show_bug.cgi?id=6039
	MarkNativeAsOptional("GivePlayerAmmo");
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
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
		SMRPG_RegisterUpgradeType("Resupply", UPGRADE_SHORTNAME, "Regenerates ammo every third second.", 20, true, 5, 5, 15, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnMapStart()
{
	CreateTimer(3.0, Timer_Resupply, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

public Action:Timer_Resupply(Handle:timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	new bool:bIgnoreBots = SMRPG_IgnoreBots();
	new bool:bGiveClientAmmoNativeAvailable = GetFeatureStatus(FeatureType_Native, "GivePlayerAmmo") == FeatureStatus_Available;
	
	new iLevel, iPrimaryAmmo;
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		// Are bots allowed to use this upgrade?
		if(bIgnoreBots && IsFakeClient(i))
			continue;
		
		// Player didn't buy this upgrade yet.
		iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			continue;
		
		if(!SMRPG_RunUpgradeEffect(i, UPGRADE_SHORTNAME))
			continue; // Some other plugin doesn't want this effect to run
		
		LOOP_CLIENTWEAPONS(i, iWeapon, iIndex)
		{
			// Use the new SDKTools native, if available!
			if(bGiveClientAmmoNativeAvailable)
			{
				GivePlayerAmmo(i, iLevel, Weapon_GetPrimaryAmmoType(iWeapon), true);
			}
			// Try to use our own gamedata for older sourcemod versions.
			else if(GiveAmmo(i, iLevel, Weapon_GetPrimaryAmmoType(iWeapon), true) == -1)
			{
				// Fall back to non-limit alternative, if sdkcall fails.
				Client_GetWeaponPlayerAmmoEx(i, iWeapon, iPrimaryAmmo);
				Client_SetWeaponPlayerAmmoEx(i, iWeapon, iPrimaryAmmo+iLevel);
			}
		}
	}
	
	return Plugin_Continue;
}

/**
 * GiveAmmo gives ammo of a certain type to a player - duh.
 *
 * @param client        The client index.
 * @param ammo            Amount of bullets to give. Is capped at weapon's limit.
 * @param ammotype        Type of ammo to give to player.
 * @param suppressSound Don't play the ammo pickup sound.
 * 
 * @return Amount of bullets actually given. -1 on error.
 */
stock GiveAmmo(client, ammo, ammotype, bool:bSuppressSound)
{
	static Handle:hGiveAmmo = INVALID_HANDLE;
	static bool:bErroaaarrd = false;
	
	if(hGiveAmmo == INVALID_HANDLE)
	{
		new Handle:hGameConf = LoadGameConfigFile("smrpg_resup.games");
		if(hGameConf == INVALID_HANDLE)
		{
			if(!bErroaaarrd)
				LogError("Can't find smrpg_resup.games.txt gamedata. Ammo Resupply won't obey weapon ammo limits!");
			bErroaaarrd = true;
			return -1;
		}
		
		StartPrepSDKCall(SDKCall_Player);
		if(!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "GiveAmmo"))
		{
			CloseHandle(hGameConf);
			if(!bErroaaarrd)
				LogError("Can't find CBaseCombatCharacter::GiveAmmo(int, int, bool) offset. Ammo Resupply won't obey weapon ammo limits!");
			bErroaaarrd = true;
			return -1;
		}
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		hGiveAmmo = EndPrepSDKCall();

		CloseHandle(hGameConf);
		
		if(hGiveAmmo == INVALID_HANDLE)
		{
			if(!bErroaaarrd)
				LogError("Failed to finish GiveAmmo SDKCall. Ammo Resupply won't obey weapon ammo limits!");
			bErroaaarrd = true;
			return -1;
		}
	}
	
	return SDKCall(hGiveAmmo, client, ammo, ammotype, bSuppressSound);
}