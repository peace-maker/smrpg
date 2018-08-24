#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smlib/clients>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "damage"

ConVar g_hCVDefaultPercent;
ConVar g_hCVDefaultMaxDamage;

enum WeaponConfig {
	Float:Weapon_DamageInc,
	Float:Weapon_MaxIncrease
};

StringMap g_hWeaponDamage;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Damage+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Damage+ upgrade for SM:RPG. Deal additional damage on enemies.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	g_hWeaponDamage = new StringMap();

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
		SMRPG_RegisterUpgradeType("Damage+", UPGRADE_SHORTNAME, "Deal additional damage on enemies.", 0, true, 5, 5, 10);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVDefaultPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_damage_percent", "0.05", "Percentage of damage done the victim loses additionally (multiplied by level)", _, true, 0.0);
		g_hCVDefaultMaxDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_damage_max", "25", "Maximum damage a player could deal additionally ignoring higher percentual values. (0 = disable)", _, true, 0.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnMapStart()
{
	if(!LoadWeaponConfig())
		SetFailState("Can't read config file in configs/smrpg/damage_weapons.cfg!");
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
 * Hook callbacks
 */
public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return Plugin_Continue;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return Plugin_Continue;
	
	char sWeapon[256];
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	
	float fDmgIncreasePercent = GetWeaponDamageIncreasePercent(sWeapon);
	if (fDmgIncreasePercent <= 0.0)
		return Plugin_Continue;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	// Increase the damage
	float fDmgInc = damage * fDmgIncreasePercent * float(iLevel);
	
	// Cap it at the upper limit
	float fMaxDmg = GetWeaponMaxAdditionalDamage(sWeapon);
	if(fMaxDmg > 0.0 && fDmgInc > fMaxDmg)
		fDmgInc = fMaxDmg;
	
	damage += fDmgInc;
	return Plugin_Changed;
}

/**
 * Helpers
 */
bool LoadWeaponConfig()
{
	g_hWeaponDamage.Clear();
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/damage_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	KeyValues hKV = new KeyValues("DamageWeapons");
	if(!hKV.ImportFromFile(sPath))
	{
		delete hKV;
		return false;
	}
	
	char sWeapon[64];
	if(hKV.GotoFirstSubKey(false))
	{
		int eInfo[WeaponConfig];
		do
		{
			hKV.GetSectionName(sWeapon, sizeof(sWeapon));
			
			eInfo[Weapon_DamageInc] = hKV.GetFloat("dmg_increase", -1.0);
			eInfo[Weapon_MaxIncrease] = hKV.GetFloat("max_additional_dmg", -1.0);
			
			g_hWeaponDamage.SetArray(sWeapon, eInfo[0], view_as<int>(WeaponConfig));
			
		} while (hKV.GotoNextKey());
	}
	
	delete hKV;
	return true;
}

float GetWeaponDamageIncreasePercent(const char[] sWeapon)
{
	int eInfo[WeaponConfig];
	if (g_hWeaponDamage.GetArray(sWeapon, eInfo[0], view_as<int>(WeaponConfig)))
	{
		if (eInfo[Weapon_DamageInc] >= 0.0)
			return eInfo[Weapon_DamageInc];
	}
	
	// Just use the default value
	return g_hCVDefaultPercent.FloatValue;
}

float GetWeaponMaxAdditionalDamage(const char[] sWeapon)
{
	int eInfo[WeaponConfig];
	if (g_hWeaponDamage.GetArray(sWeapon, eInfo[0], view_as<int>(WeaponConfig)))
	{
		if (eInfo[Weapon_MaxIncrease] >= 0.0)
			return eInfo[Weapon_MaxIncrease];
	}
	
	// Just use the default value
	return g_hCVDefaultMaxDamage.FloatValue;
}