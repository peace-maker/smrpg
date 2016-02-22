/**
 * SM:RPG Armor Helmet Upgrade
 * Gives players a chance to receive a helmet on spawn.
 */

#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

#define UPGRADE_SHORTNAME "armorhelmet"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVChance;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Armor Helmet",
	author = "Peace-Maker",
	description = "Armor Helmet upgrade for SM:RPG. Chance to get a helmet on spawn.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	new EngineVersion:engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Armor Helmet", UPGRADE_SHORTNAME, "Gives you a chance to get a helmet on spawn.", 0, true, 5, 5, 5, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVChance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorhelmet_chance", "0.1", "Chance percentage of a client spawning with a helmet (multiplied by level).", _, true, 0.01, true, 1.0);
	}
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client)
		return;
	
	// This guy already has a helmet. No need to do anything.
	if (GetEntProp(client, Prop_Send, "m_bHasHelmet"))
		return;
	
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return;
	
	// The upgrade is disabled completely?
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Float:fChance = float(iLevel) * GetConVarFloat(g_hCVChance);
	if (GetURandomFloat() < fChance)
		SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
}
 
/**
 * SM:RPG Upgrade callbacks
 */

public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	// Here you can apply your effect directly when the client's upgrade level changes.
	// E.g. adjust the maximal health of the player immediately when he bought the upgrade.
	// The client doesn't have to be ingame here!
}

public bool:SMRPG_ActiveQuery(client)
{
	// If this is a passive effect, it's always active, if the player got at least level 1.
	// If it's an active effect (like a short speed boost) add a check for the effect as well.
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}

// The core wants to display your upgrade somewhere. Translate it into the clients language!
public SMRPG_TranslateUpgrade(client, const String:shortname[], TranslationType:type, String:translation[], maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if(type == TranslationType_Description)
	{
		new String:sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}