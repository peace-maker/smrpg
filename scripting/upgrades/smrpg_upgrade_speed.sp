#pragma semicolon 1
#include <sourcemod>
#include <dhooks>
#include <smrpg>

#define UPGRADE_SHORTNAME "speed"
#define PLUGIN_VERSION "1.0"

new Handle:g_hGetSpeed;
new Handle:g_hCVPercent;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Speed+",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Speed+ upgrade for SM:RPG. Increase your default moving speed.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

	new Handle:hGameConf = LoadGameConfigFile("smrpg_speed.games");
	if(hGameConf == INVALID_HANDLE)
		SetFailState("Gamedata file smrpg_speed.games.txt is missing.");
	
	new iOffset = GameConfGetOffset(hGameConf, "GetPlayerMaxSpeed");
	CloseHandle(hGameConf);
	
	if(iOffset == -1)
		SetFailState("Gamedata is missing the \"GetPlayerMaxSpeed\" offset.");
	
	g_hGetSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, Hook_GetPlayerMaxSpeedPost);
	if(g_hGetSpeed == INVALID_HANDLE)
		SetFailState("Failed to create hook on \"GetPlayerMaxSpeed\".");
	
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
		SMRPG_RegisterUpgradeType("Speed+", UPGRADE_SHORTNAME, "Increase your average movement speed.", 10, true, 6, 10, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_speed_percent", "0.05", "Percentage of speed added to player (multiplied by level)", _, true, 0.0, true, 1.0);
	}
}

public OnClientPutInServer(client)
{
	DHookEntity(g_hGetSpeed, true, client);
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

public SMRPG_TranslateUpgrade(client, TranslationType:type, String:translation[], maxlen)
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
public MRESReturn:Hook_GetPlayerMaxSpeedPost(client, Handle:hReturn)
{
	if(!SMRPG_IsEnabled())
		return MRES_Ignored;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return MRES_Ignored;
	
	// Upgrade enabled?
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return MRES_Ignored;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return MRES_Ignored;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return MRES_Ignored; // Some other plugin doesn't want this effect to run
	
	new Float:fCurrentMaxSpeed = DHookGetReturn(hReturn);
	// Increase maxspeed depending on level
	new Float:fMaxSpeedIncrease = fCurrentMaxSpeed * float(iLevel) * GetConVarFloat(g_hCVPercent);
	
	DHookSetReturn(hReturn, fCurrentMaxSpeed+fMaxSpeedIncrease);
	return MRES_Override;
}