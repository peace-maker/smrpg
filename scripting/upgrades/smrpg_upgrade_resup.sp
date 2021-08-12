#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smlib>

//#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "resup"


Handle g_hResupplyTimer;

ConVar g_hCVInterval;

// CS:GO specific
EngineVersion g_Engine;
Handle g_hGiveReserveAmmo;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Resupply",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Resupply upgrade for SM:RPG. Regenerates ammo every x seconds.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	g_Engine = GetEngineVersion();
	
	// CS:GO stores reserved ammo on weapons now instead of on the players.
	if (g_Engine == Engine_CSGO)
	{
		Handle hGConf = LoadGameConfigFile("smrpg_resup.games");
		if (hGConf == null)
		{
			SetFailState("Can't find smrpg_resup.games.txt gamedata file.");
		}
		
		StartPrepSDKCall(SDKCall_Entity);
		if (!PrepSDKCall_SetFromConf(hGConf, SDKConf_Signature, "CBaseCombatWeapon::GiveReserveAmmo"))
		{
			delete hGConf;
			SetFailState("Can't find CBaseCombatWeapon::GiveReserveAmmo signature.");
		}
		// CBaseCombatWeapon::GiveReserveAmmo(AmmoPosition_t, int, bool, CBaseCombatCharacter *)
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // ammo position 1 = primary, 2 = secondary
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // amount of ammo to give
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain); // suppress ammo pickup sound
		PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL); // optional owner. tries weapon owner if null.
		// if owner has ammo of that weapon's ammotype in his m_iAmmo, add to this array like before.
		// if the owner doesn't have ammo in m_iAmmo, use the new m_iPrimaryReserveAmmoCount props.
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); // return amount of bullets missing until the max is reached including what we're about to add with this call..
		g_hGiveReserveAmmo = EndPrepSDKCall();
		
		delete hGConf;
		if (g_hGiveReserveAmmo == null)
		{
			SetFailState("Failed to prepare CBaseCombatWeapon::GiveReserveAmmo SDK call.");
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
		SMRPG_RegisterUpgradeType("Resupply", UPGRADE_SHORTNAME, "Regenerates ammo every x seconds.", 0, true, 5, 5, 15);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_resup_interval", "3", "Set the interval in which the ammo is given in seconds.", 0, true, 0.5);
		g_hCVInterval.AddChangeHook(ConVar_OnIntervalChanged);
		
		// Start the timer with the correct interval.
		StartResupplyTimer();
	}
}

public void OnMapStart()
{
	// OnMapStart might be called before the smrpg library was registered.
	if(g_hCVInterval == null)
		return;
	
	StartResupplyTimer();
}

public void OnMapEnd()
{
	g_hResupplyTimer = null;
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
 * Timer callbacks
 */
public Action Timer_Resupply(Handle timer)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return Plugin_Continue;
	
	bool bIgnoreBots = SMRPG_IgnoreBots();
	
	int iLevel, iPrimaryAmmoType;
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		// Are bots allowed to use this upgrade?
		if(bIgnoreBots && IsFakeClient(i))
			continue;
		
		// Only change alive players.
		if(!IsPlayerAlive(i) || IsClientObserver(i))
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
			
			if (g_Engine == Engine_CSGO)
			{
				if (g_hGiveReserveAmmo != null)
				{
					SDKCall(g_hGiveReserveAmmo, iWeapon, 1, iLevel, true, -1);
				}
			}
			else
			{
				GivePlayerAmmo(i, iLevel, iPrimaryAmmoType, true);
			}
		}
	}
	
	return Plugin_Continue;
}

/**
 * Convar hook callbacks
 */
public void ConVar_OnIntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(oldValue, newValue, false))
		return;
	
	StartResupplyTimer();
}

/**
 * Helpers
 */
void StartResupplyTimer()
{
	ClearHandle(g_hResupplyTimer);
	g_hResupplyTimer = CreateTimer(g_hCVInterval.FloatValue, Timer_Resupply, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}