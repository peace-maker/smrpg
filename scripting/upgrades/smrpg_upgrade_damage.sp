#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smrpg>
#include <smlib/clients>

#define UPGRADE_SHORTNAME "damage"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVDefaultPercent;
new Handle:g_hCVDefaultMaxDamage;

enum WeaponConfig {
	Float:Weapon_DamageInc,
	Float:Weapon_MaxIncrease
};

new Handle:g_hWeaponDamage;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Damage+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Damage+ upgrade for SM:RPG. Deal additional damage on enemies.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	g_hWeaponDamage = CreateTrie();

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
		SMRPG_RegisterUpgradeType("Damage+", UPGRADE_SHORTNAME, "Deal additional damage on enemies.", 10, true, 5, 5, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVDefaultPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_damage_percent", "0.05", "Percentage of damage done the victim loses additionally (multiplied by level)", _, true, 0.0);
		g_hCVDefaultMaxDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_damage_max", "25", "Maximum damage a player could deal additionally ignoring higher percentual values. (0 = disable)", _, true, 0.0);
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public OnMapStart()
{
	if(!LoadWeaponConfig())
		SetFailState("Can't read config file in configs/smrpg/damage_weapons.cfg!");
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
 * Hook callbacks
 */
public Action:Hook_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return Plugin_Continue;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	new iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return Plugin_Continue;
	
	decl String:sWeapon[256];
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	
	new Float:fDmgIncreasePercent = GetWeaponDamageIncreasePercent(sWeapon);
	if (fDmgIncreasePercent <= 0.0)
		return Plugin_Continue;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	
	// Increase the damage
	new Float:fDmgInc = damage * fDmgIncreasePercent * float(iLevel);
	
	// Cap it at the upper limit
	new Float:fMaxDmg = GetWeaponMaxAdditionalDamage(sWeapon);
	if(fMaxDmg > 0.0 && fDmgInc > fMaxDmg)
		fDmgInc = fMaxDmg;
	
	damage += fDmgInc;
	return Plugin_Changed;
}

/**
 * Helpers
 */
bool:LoadWeaponConfig()
{
	ClearTrie(g_hWeaponDamage);
	
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/damage_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	new Handle:hKV = CreateKeyValues("DamageWeapons");
	if(!FileToKeyValues(hKV, sPath))
	{
		CloseHandle(hKV);
		return false;
	}
	
	decl String:sWeapon[64];
	if(!KvGotoFirstSubKey(hKV, false))
	{
		CloseHandle(hKV);
		return false;
	}
	
	new eInfo[WeaponConfig];
	do
	{
		KvGetSectionName(hKV, sWeapon, sizeof(sWeapon));
		
		eInfo[Weapon_DamageInc] = KvGetFloat(hKV, "dmg_increase", -1.0);
		eInfo[Weapon_MaxIncrease] = KvGetFloat(hKV, "max_additional_dmg", -1.0);
		
		SetTrieArray(g_hWeaponDamage, sWeapon, eInfo[0], _:WeaponConfig);
		
	} while (KvGotoNextKey(hKV));
	
	CloseHandle(hKV);
	return true;
}

Float:GetWeaponDamageIncreasePercent(const String:sWeapon[])
{
	new eInfo[WeaponConfig];
	if (GetTrieArray(g_hWeaponDamage, sWeapon, eInfo[0], _:WeaponConfig))
	{
		if (eInfo[Weapon_DamageInc] >= 0.0)
			return eInfo[Weapon_DamageInc];
	}
	
	// Just use the default value
	return GetConVarFloat(g_hCVDefaultPercent);
}

Float:GetWeaponMaxAdditionalDamage(const String:sWeapon[])
{
	new eInfo[WeaponConfig];
	if (GetTrieArray(g_hWeaponDamage, sWeapon, eInfo[0], _:WeaponConfig))
	{
		if (eInfo[Weapon_MaxIncrease] >= 0.0)
			return eInfo[Weapon_MaxIncrease];
	}
	
	// Just use the default value
	return GetConVarFloat(g_hCVDefaultMaxDamage);
}