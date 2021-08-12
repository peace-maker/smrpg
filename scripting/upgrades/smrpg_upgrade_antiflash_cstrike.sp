/**
 * SM:RPG Antiflash Upgrade
 * Reduces effect of flashbangs.
 */

#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "antiflash"
#define MIN_FLASH_ALPHA 0.5

ConVar g_hCVPercent;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Antiflash",
	author = "Peace-Maker",
	description = "Antiflash upgrade for SM:RPG. Reduces effect of flashbangs.",
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
	
	HookEvent("player_blind", Event_OnPlayerBlind);
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
		SMRPG_RegisterUpgradeType("Antiflash", UPGRADE_SHORTNAME, "Reduce blinding effect of flashbangs on you.", 0, true, 4, 10, 10);
		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_antiflash.cfg!
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_antiflash_percent", "0.15", "Reduce the effect of flashbang by this percent multiplied by upgrade level.", _, true, 0.01, true, 1.0);
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

public void Event_OnPlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	// Only apply to alive players.
	if(!IsPlayerAlive(client) || IsClientObserver(client))
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
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Reduce the flash effect.
	float fFlashAlpha = GetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha");
	fFlashAlpha -= fFlashAlpha * g_hCVPercent.FloatValue * float(iLevel);
	if(fFlashAlpha < MIN_FLASH_ALPHA)
		fFlashAlpha = MIN_FLASH_ALPHA;
	SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", fFlashAlpha);
}
