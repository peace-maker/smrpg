/**
 * SM:RPG Shrinking Upgrade
 * Make player models smaller
 */
#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "shrinking"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVIncrease;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Shrinking",
	author = "Peace-Maker",
	description = "Shrinking upgrade for SM:RPG. Make player models smaller.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	if(GetEngineVersion() == Engine_CSGO)
	{
		Format(error, err_max, "CS:GO models don't support scaling properly :(");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	HookEvent("player_spawn", Event_OnPlayerSpawn);
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
		SMRPG_RegisterUpgradeType("Shrinking", UPGRADE_SHORTNAME, "Make player models smaller.", 6, true, 3, 25, 15, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_shrinking_increase", "0.1", "How many percent smaller should the player get each level?", _, true, 0.01, true, 0.5);
	}
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	if(IsClientInGame(client))
		Resize_ApplyUpgrade(client, true);
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
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	Resize_ApplyUpgrade(client, false);
}

/**
 * Helpers
 */
Resize_ApplyUpgrade(client, bool:bIgnoreNullLevel = false)
{
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0 && !bIgnoreNullLevel)
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Float:fScale = 1.0 - GetConVarFloat(g_hCVIncrease) * float(iLevel);
	ResizePlayer(client, fScale);
}

// Thanks to 11530
// https://forums.alliedmods.net/showthread.php?t=193255
stock ResizePlayer(client, Float:fScale)
{
	SetEntPropFloat(client, Prop_Send, "m_flModelScale", fScale);
	SetEntPropFloat(client, Prop_Send, "m_flStepSize", 18.0 * fScale);
	
	// Have children resized too! (like the hats ;) )
	// TODO: Somehow keep the attachement offset ratio intact?
	//       Hats stay (sometimes?) further away if they are smaller.
	decl String:sBuffer[64];
	LOOP_CHILDREN(client, child)
	{
		if(GetEntityClassname(child, sBuffer, sizeof(sBuffer))
		&& StrContains(sBuffer, "prop_", false) == 0)
		{
			SetEntPropFloat(child, Prop_Send, "m_flModelScale", fScale);
		}
	}
}