#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <dhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "speed"

Handle g_hGetSpeed;
ConVar g_hCVPercent;
ConVar g_hCVSpeedMethod;

enum SpeedMethod {
	SM_LaggedMovementValue,
	SM_MaxSpeed
}

SpeedMethod g_SpeedMethod;
int g_iClientHookId[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Speed+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Speed+ upgrade for SM:RPG. Increase your default moving speed.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

	Handle hGameConf = LoadGameConfigFile("smrpg_speed.games");
	if(hGameConf == null)
		SetFailState("Gamedata file smrpg_speed.games.txt is missing.");
	
	int iOffset = GameConfGetOffset(hGameConf, "GetPlayerMaxSpeed");
	delete hGameConf;
	
	if(iOffset == -1)
		SetFailState("Gamedata is missing the \"GetPlayerMaxSpeed\" offset.");
	
	g_hGetSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, Hook_GetPlayerMaxSpeedPost);
	if(g_hGetSpeed == null)
		SetFailState("Failed to create hook on \"GetPlayerMaxSpeed\".");
	
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
		SMRPG_RegisterUpgradeType("Speed+", UPGRADE_SHORTNAME, "Increase your average movement speed.", 0, true, 6, 10, 10);
		SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_speed_percent", "0.05", "Percentage of speed added to player (multiplied by level)", _, true, 0.0, true, 1.0);
		g_hCVSpeedMethod = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_speed_method", "1", "Which method for default movement speed improvement should be applied? 0: LaggedMovementValue, speeds up jumping and falling too (old way); 1: MaxSpeed, only increases the maximum walking speed on the ground (new way)", _, true, 0.0, true, 1.0);
		g_SpeedMethod = view_as<SpeedMethod>(g_hCVSpeedMethod.IntValue);
		g_hCVSpeedMethod.AddChangeHook(ConVar_OnSpeedMethodChanged);
	}
}

public void OnClientPutInServer(int client)
{
	if (g_SpeedMethod == SM_MaxSpeed)
		g_iClientHookId[client] = DHookEntity(g_hGetSpeed, true, client);
}

public void OnClientDisconnect_Post(int client)
{
	g_iClientHookId[client] = 0;
}

/**
 * ConVar change callbacks
 */
public void ConVar_OnSpeedMethodChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	SpeedMethod oldSpeedMethod = g_SpeedMethod;
	g_SpeedMethod = view_as<SpeedMethod>(g_hCVSpeedMethod.IntValue);
	if(oldSpeedMethod == g_SpeedMethod)
		return;

	// Apply the selected method to all connected players.
	for(int i=1;i<=MaxClients;i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (g_SpeedMethod == SM_LaggedMovementValue)
		{
			// Disable MaxSpeed method.
			DHookRemoveHookID(g_iClientHookId[i]);
			g_iClientHookId[i] = 0;

			ApplyLaggedMovementSpeedChange(i);
		}
		else
		{
			// Disable LaggedMovementValue method.
			SMRPG_ResetClientLaggedMovement(i, LMT_Default);

			g_iClientHookId[i] = DHookEntity(g_hGetSpeed, true, i);
		}
	}
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

public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
	if(!IsClientInGame(client))
		return;
	
	if (g_SpeedMethod == SM_LaggedMovementValue)
		ApplyLaggedMovementSpeedChange(client);
}

float GetClientSpeedIncrease(int client)
{
	if(!SMRPG_IsEnabled())
		return 0.0;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return 0.0;
	
	// Upgrade enabled?
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return 0.0;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return 0.0;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return 0.0; // Some other plugin doesn't want this effect to run
	
	// Increase maxspeed depending on level
	return float(iLevel) * g_hCVPercent.FloatValue;
}

void ApplyLaggedMovementSpeedChange(int client)
{
	float fMaxSpeedIncrease = GetClientSpeedIncrease(client);
	if (fMaxSpeedIncrease <= 0.0)
	{
		SMRPG_ResetClientLaggedMovement(client, LMT_Default);
		return;
	}
	SMRPG_SetClientDefaultLaggedMovement(client, 1.0 + fMaxSpeedIncrease);
}

/**
 * Hook callbacks
 */
public MRESReturn Hook_GetPlayerMaxSpeedPost(int client, Handle hReturn)
{
	float fMaxSpeedIncrease = GetClientSpeedIncrease(client);
	if (fMaxSpeedIncrease <= 0.0)
		return MRES_Ignored;

	float fCurrentMaxSpeed = DHookGetReturn(hReturn);
	// Increase maxspeed depending on level
	fMaxSpeedIncrease *= fCurrentMaxSpeed;
	
	DHookSetReturn(hReturn, fCurrentMaxSpeed+fMaxSpeedIncrease);
	return MRES_Override;
}
