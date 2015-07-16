/**
 * SM:RPG Antidote Upgrade
 * Reduces length of bad effects on a player.
 */

#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <smrpg_effects>

// Change the upgrade's shortname to a descriptive abbrevation
#define UPGRADE_SHORTNAME "antidote"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVPercent;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Antidote",
	author = "Peace-Maker",
	description = "Antidote upgrade for SM:RPG. Reduces length of bad effects on a player.",
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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Antidote", UPGRADE_SHORTNAME, "Reduces length of bad effects on you.", 10, true, 5, 20, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);

		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);

		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_antidote.cfg!
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_antidote_percent", "0.05", "How much shorter should bad effects like freeze, burn or slowdown last? Multiplied by upgrade level.", _, true, 0.0, true, 1.0);
	}
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

/**
 * SM:RPG Effect Hub callbacks
 */
public Action:SMRPG_OnClientFreeze(client, &Float:fTime)
{
	new Float:fReduce = GetClientEffectReduction(client);
	if(fReduce <= 0.0)
		return Plugin_Continue;
	
	// Shorten the time by x%.
	fTime -= fTime * fReduce;
	if (fTime <= 0.0)
		return Plugin_Handled;
	
	return Plugin_Changed;
}

public Action:SMRPG_OnClientIgnite(client, &Float:fTime)
{
	new Float:fReduce = GetClientEffectReduction(client);
	if(fReduce <= 0.0)
		return Plugin_Continue;
	
	// Shorten the time by x%.
	fTime -= fTime * fReduce;
	if (fTime <= 0.0)
		return Plugin_Handled;
	
	return Plugin_Changed;
}

public Action:SMRPG_OnClientLaggedMovementChange(client, LaggedMovementType:type, &Float:fTime)
{
	// Getting faster is good! Don't shorten the time.
	if(type == LMT_Faster)
		return Plugin_Continue;

	new Float:fReduce = GetClientEffectReduction(client);
	if(fReduce <= 0.0)
		return Plugin_Continue;
	
	// Shorten the time by x%.
	fTime -= fTime * fReduce;
	if (fTime <= 0.0)
		return Plugin_Handled;
	
	return Plugin_Changed;
}
 
// Get percent of which we want to reduce the effect's duration.
Float:GetClientEffectReduction(client)
{
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return 0.0;
	
	// The upgrade is disabled completely?
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return 0.0;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return 0.0;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return 0.0;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return 0.0; // Some other plugin doesn't want this effect to run
	
	// See how much that player's debuffs are reduced.
	return GetConVarFloat(g_hCVPercent) * float(iLevel);
}