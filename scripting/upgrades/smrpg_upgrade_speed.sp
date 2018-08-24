#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <dhooks>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "speed"

Handle g_hGetSpeed;
ConVar g_hCVPercent;

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
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_speed_percent", "0.05", "Percentage of speed added to player (multiplied by level)", _, true, 0.0, true, 1.0);
	}
}

public void OnClientPutInServer(int client)
{
	DHookEntity(g_hGetSpeed, true, client);
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
public MRESReturn Hook_GetPlayerMaxSpeedPost(int client, Handle hReturn)
{
	if(!SMRPG_IsEnabled())
		return MRES_Ignored;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return MRES_Ignored;
	
	// Upgrade enabled?
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return MRES_Ignored;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return MRES_Ignored;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return MRES_Ignored; // Some other plugin doesn't want this effect to run
	
	float fCurrentMaxSpeed = DHookGetReturn(hReturn);
	// Increase maxspeed depending on level
	float fMaxSpeedIncrease = fCurrentMaxSpeed * float(iLevel) * g_hCVPercent.FloatValue;
	
	DHookSetReturn(hReturn, fCurrentMaxSpeed+fMaxSpeedIncrease);
	return MRES_Override;
}