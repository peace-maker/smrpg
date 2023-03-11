/**
 * SM:RPG Reduced Fall Damage Upgrade
 * Reduces the damage you take from falling from great heights.
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "turtle"

ConVar g_hCVPercent;
ConVar g_hCVDuration;

Handle g_turtleTimers[65];
bool g_turtleMode[65];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Turtle",
	author = "DeewaTT",
	description = "Let's you take decreased damage after taking a headshot for a limit amount of time.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Turtle", UPGRADE_SHORTNAME, "Reduces the damage you receive after taking a headshot.", 0, true, 5, 10, 10);
		
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_turtle_percent", "0.01", "How much percent of the damage should be removed (multiplied by level)?", _, true, 0.01, true, 1.0);
		g_hCVDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_turtle_duration", "0.01", "How long should the damage reduction last (multiplied by level)?", _, true, 0.01, true, 10.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	SDKHook(client, SDKHook_TraceAttackPost, Hook_TraceAttackPost);
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

/**
 * SDK Hooks callbacks
 */


public void Hook_TraceAttackPost(int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup)
{
	// Check if the victim is a player and if the last hit was a headshot.
    	if (IsClientInGame(victim) && hitgroup == 1 && hitbox == 12) 
	{
    // Check if the victim has the "turtle" skill.
    	int iLevel = SMRPG_GetClientUpgradeLevel(victim, "turtle");
        if (iLevel > 0) 
		{
        // Activate "turtlemode" for the player
		SetTurtlemode(victim, true); 
		// Find out how long the player will be protected
		float turtleDuration = float(iLevel) * g_hCVDuration.FloatValue;
		if (g_turtleTimers[victim] != INVALID_HANDLE)
			return;
        // Schedule a timer to deactivate "turtlemode" after x seconds 
		g_turtleTimers[victim] = CreateTimer(turtleDuration, RemoveTurtleMode, victim, TIMER_FLAG_NO_MAPCHANGE);
		}
    }
    	return; 
}		
public Action RemoveTurtleMode(Handle timer, int victim)
{
    // Deactivate "turtlemode" for the player
    	SetTurtlemode(victim, false);
	g_turtleTimers[victim] = INVALID_HANDLE;
    	return Plugin_Handled;
}


public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, 
									float damageForce[3], float damagePosition[3], int damagecustom)
{
	// We need to check if we are in damage reduction mode.
	if(g_turtleMode[victim] == false)
		return Plugin_Continue;

	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	// The upgrade is disabled completely?
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(victim) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
	// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run
	

	float fReducePercent = g_hCVPercent.FloatValue * float(iLevel);
	// Never block the whole damage.
	if (fReducePercent >= 1.0)
		fReducePercent = 0.99;
	
	// Reduce the damage taken.
	damage -= damage * fReducePercent;
	return Plugin_Changed;
}


// Turns the Turtlemode on or off.
public void SetTurtlemode(int victim, bool bool)
{
	g_turtleMode[victim] = bool;
	
	if(g_turtleMode[victim] == true)
	{
		PrintToConsole(victim, "You are now in turtlemode, taking %d%% reduced damage.", RoundToNearest(100*g_hCVPercent.FloatValue * float(SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME))));
	}
	else
	{
		PrintToConsole(victim, "You are no longer in turtlemode, taking normal damage.");
	}
	return;
}