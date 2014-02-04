/**
 * SM:RPG Example Upgrade
 * Adds a random effect
 */
#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

// Change the upgrade's shortname to a descriptive abbrevation
// No spaces allowed here. This is going to be used as a sql table column field name!
#define UPGRADE_SHORTNAME "example"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVMyConvar;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Example",
	author = "You",
	description = "Example upgrade for SM:RPG. Does something.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("smrpg_example_upgrade.phrases");
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
		SMRPG_RegisterUpgradeType("Example", UPGRADE_SHORTNAME, "Does something.", 10, true, 5, 15, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		
		// If this is an active effect which is only affecting players for a short time on some event, register this callback to enable other plugins to stop your effect anytime.
		// This can help to prevent compatability issues between similar upgrades.
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVMyConvar = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_example_myvar", "1", "Does something.");
	}
}

public OnClientDisconnect(client)
{
	// Don't forget to reset your effect when the client leaves ;)
	SMRPG_ResetEffect(client);
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

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	// Stop your temporary effects here.
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

// This holds the basic checks you should run before applying your effect.
ApplyMyUpgradeEffect(client)
{
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
	
	// Do my upgrade effect
	// ...
}