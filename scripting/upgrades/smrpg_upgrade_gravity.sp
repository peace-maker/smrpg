/**
 * SM:RPG Reduced Gravity Upgrade
 * Reduces a player's gravity and lets them jump higher.
 * 
 * Thanks to ArsiRC for config default values in THC RPG.
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>

// Change the upgrade's shortname to a descriptive abbrevation
#define UPGRADE_SHORTNAME "gravity"

ConVar g_hCVPercent;

MoveType g_iOldClientMoveType[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Reduced Gravity",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Reduced Gravity upgrade for SM:RPG. Reduces a player's gravity and lets them jump higher.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	// Late loading
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
	{
		// Reset all players now that we're gone :'(
		CheckGravity(true);
		
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
	}
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
		SMRPG_RegisterUpgradeType("Reduced Gravity", UPGRADE_SHORTNAME, "Reduces your gravity and lets you jump higher.", 0, true, 10, 10, 15);
		SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_gravity.cfg!
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_gravity_percent", "0.05", "How much should the gravity be reduced per level? Default gravity is 1.0.", _, true, 0.0, true, 0.9);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PostThinkPost, Hook_OnClientPostThinkPost);
}

public void OnClientDisconnect(int client)
{
	g_iOldClientMoveType[client] = MOVETYPE_NONE;
}

/**
 * SDK Hooks callbacks
 */
public void Hook_OnClientPostThinkPost(int client)
{
	MoveType iMoveType = GetEntityMoveType(client);
	
	if(IsClientInGame(client) && IsPlayerAlive(client))
	{	
		// Ladders set the gravity to 0.0 and back to 1.0 when leaving the ladder. Reapply our own value when a player leaves a ladder.
		// Thanks to DorCoMaNdO! https://forums.alliedmods.net/showthread.php?t=240092
		if(iMoveType != MOVETYPE_LADDER && g_iOldClientMoveType[client] == MOVETYPE_LADDER)
		{
			ApplyGravity(client);
		}
	}
	
	g_iOldClientMoveType[client] = iMoveType;
}

/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] error, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	// Set the gravity one frame after the player spawned, 
	// so we make sure other plugins, which randomly reset 
	// the gravity to 1.0 at spawn don't overwrite our effect.
	RequestFrame(Frame_OnPlayerSpawnPost, userid);
}

/**
 * RequestFrame callbacks to run one frame later.
 */
public void Frame_OnPlayerSpawnPost(any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;

	if(!IsPlayerAlive(client) || GetClientTeam(client) < 2)
		return;
	
	ApplyGravity(client, true);
}

/**
 * SM:RPG Upgrade callbacks
 */

public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
	if(IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) > 1)
		ApplyGravity(client, true);
}

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

/**
 * SM:RPG callbacks
 */
public void SMRPG_OnEnableStatusChanged(bool bEnabled)
{
	CheckGravity(false);
}

public void SMRPG_OnUpgradeSettingsChanged(const char[] shortname)
{
	if(StrEqual(shortname, UPGRADE_SHORTNAME))
	{
		if(SMRPG_IsEnabled())
		{
			CheckGravity(false);
		}
	}
}

// Set the gravity correctly
void ApplyGravity(int client, bool bIgnoreNullLevel = false)
{
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
	if(!bIgnoreNullLevel && iLevel <= 0)
		return;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Reduce the gravity
	float fGravity = 1.0 - float(iLevel) * g_hCVPercent.FloatValue;
	if(fGravity < 0.1)
		fGravity = 0.1;
	
	SetEntityGravity(client, fGravity);
}

// Make sure the gravity is set correctly for all players
// Also make sure it's reset, when the upgrade is disabled.
stock void CheckGravity(bool bForceDisable)
{
	bool bEnabled = SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME);
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		// We got disabled? :(
		if(bForceDisable || !bEnabled)
		{
			// Are bots allowed to use this upgrade?
			if(IsFakeClient(i) && SMRPG_IgnoreBots())
				continue;
			
			// Player didn't buy this upgrade yet.
			int iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
			if(iLevel <= 0)
				continue;
			
			if(!SMRPG_RunUpgradeEffect(i, UPGRADE_SHORTNAME))
				continue; // Some other plugin doesn't want this effect to run
			
			// Reset player gravity to default value again.
			SetEntityGravity(i, 1.0);
		}
		// Upgrade is enabled?
		else
		{
			ApplyGravity(i);
		}
	}
}