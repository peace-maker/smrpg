/**
 * SM:RPG Armor Helmet Upgrade
 * Gives players a chance to receive a helmet on spawn.
 */

#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "armorhelmet"

ConVar g_hCVChance;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Armor Helmet",
	author = "Peace-Maker",
	description = "Armor Helmet upgrade for SM:RPG. Chance to get a helmet on spawn.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	HookEvent("player_spawn", Event_OnPlayerSpawn);
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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Armor Helmet", UPGRADE_SHORTNAME, "Gives you a chance to get a helmet on spawn.", 0, true, 5, 5, 5);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVChance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_armorhelmet_chance", "0.1", "Chance percentage of a client spawning with a helmet (multiplied by level).", _, true, 0.01, true, 1.0);
	}
}

/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;
	
	// This guy already has a helmet. No need to do anything.
	if (GetEntProp(client, Prop_Send, "m_bHasHelmet"))
		return;
	
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return;
	
	// The upgrade is disabled completely?
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	// Only change alive players.
	if(!IsPlayerAlive(client) || IsClientObserver(client))
		return;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	float fChance = float(iLevel) * g_hCVChance.FloatValue;
	if (GetURandomFloat() < fChance)
	{
		// Give the player at least one armor to be able to wear the helmet
		int iArmor = GetEntProp(client, Prop_Send, "m_ArmorValue");
		if (iArmor == 0)
			SetEntProp(client, Prop_Send, "m_ArmorValue", 1);
		SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
	}
}
 
/**
 * SM:RPG Upgrade callbacks
 */

// The core wants to display your upgrade somewhere. Translate it into the clients language!
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}