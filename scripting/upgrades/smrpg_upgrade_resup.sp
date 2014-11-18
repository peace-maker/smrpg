#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smlib>
#include <smrpg>

#define UPGRADE_SHORTNAME "resup"

#define PLUGIN_VERSION "1.0"

new Handle:g_hResupplyTimer;

new Handle:g_hCVInterval;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Resupply",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Resupply upgrade for SM:RPG. Regenerates ammo every x seconds.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
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
		SMRPG_RegisterUpgradeType("Resupply", UPGRADE_SHORTNAME, "Regenerates ammo every x seconds.", 20, true, 5, 5, 15, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_resup_interval", "3", "Set the interval in which the ammo is given in seconds.", 0, true, 0.5);
		HookConVarChange(g_hCVInterval, ConVar_OnIntervalChanged);
		
		// Start the timer with the correct interval.
		StartResupplyTimer();
	}
}

public OnMapStart()
{
	// OnMapStart might be called before the smrpg library was registered.
	if(g_hCVInterval == INVALID_HANDLE)
		return;
	
	StartResupplyTimer();
}

public OnMapEnd()
{
	g_hResupplyTimer = INVALID_HANDLE;
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
 * Timer callbacks
 */
public Action:Timer_Resupply(Handle:timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	new bool:bIgnoreBots = SMRPG_IgnoreBots();
	
	new iLevel, iPrimaryAmmoType;
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
			iPrimaryAmmoType = Weapon_GetPrimaryAmmoType(iWeapon);
			// Grenades and knives have m_iClip1 = -1 or m_iPrimaryAmmoType = -1 respectively.
			// Don't try to refill those.
			if(iPrimaryAmmoType < 0 || Weapon_GetPrimaryClip(iWeapon) < 0)
				continue;
			
			GivePlayerAmmo(i, iLevel, iPrimaryAmmoType, true);
		}
	}
	
	return Plugin_Continue;
}

/**
 * Convar hook callbacks
 */
public ConVar_OnIntervalChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(StrEqual(oldValue, newValue, false))
		return;
	
	StartResupplyTimer();
}

/**
 * Helpers
 */
StartResupplyTimer()
{
	ClearHandle(g_hResupplyTimer);
	g_hResupplyTimer = CreateTimer(GetConVarFloat(g_hCVInterval), Timer_Resupply, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}