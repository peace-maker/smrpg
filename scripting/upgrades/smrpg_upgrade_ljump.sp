#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <sdktools>

#define PLUGIN_VERSION "1.0"
#define UPGRADE_SHORTNAME "ljump"

new Handle:g_hCVIncrease;
new Handle:g_hCVIncreaseStart;

new Float:g_fLJumpPreviousVelocity[MAXPLAYERS+1][3];
new Float:g_fLJumpPlayerJumped[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Long Jump",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Long Jump upgrade for SM:RPG. Boosts players jump speed.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	HookEventEx("player_footstep", Event_OnResetJump);
	HookEvent("player_spawn", Event_OnResetJump);
	HookEvent("player_death", Event_OnResetJump);
	
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
		SMRPG_RegisterUpgradeType("Long Jump", UPGRADE_SHORTNAME, "Boosts your jump speed.", 10, true, 5, 20, 15, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_ljump_inc", "0.10", "Percent of player's jump distance to increase per level.", 0, true, 0.01);
		g_hCVIncreaseStart = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_ljump_incstart", "0.20", "Percent of player's initial jump distance to increase per level.", 0, true, 0.01);
	}
}


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

public OnClientDisconnect(client)
{
	g_fLJumpPlayerJumped[client] = -1.0;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2])
{
	static s_iLastButtons[MAXPLAYERS+1] = {0,...};
	if(!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;
	
	// Make sure to reset the time when the player stops. Maybe he didn't took a step so player_footstep wasn't fired yet.
	decl Float:vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
	if(vVelocity[0] == 0.0 && vVelocity[1] == 0.0 && vVelocity[2] == 0.0)
		g_fLJumpPlayerJumped[client] = -1.0;
	
	new bool:bFirstJump = g_fLJumpPlayerJumped[client] < 0.0;
	
	// Player started to press space - or what ever is bound to jump..
	if(buttons & IN_JUMP && !(s_iLastButtons[client] & IN_JUMP))
	{
		// Make sure the player is on the ground and not on a ladder.
		if(GetEntityFlags(client) & FL_ONGROUND && GetEntityMoveType(client) != MOVETYPE_LADDER)
		{
			g_fLJumpPreviousVelocity[client] = vVelocity;
			g_fLJumpPlayerJumped[client] = GetEngineTime();
		}
	}
	
	if(g_fLJumpPlayerJumped[client] > 0.0)
	{
		if(vVelocity[2] > g_fLJumpPreviousVelocity[client][2])
		{
			LJump_HasJumped(client, vVelocity, bFirstJump);
			g_fLJumpPlayerJumped[client] = -1.0;
		}
	}
	
	s_iLastButtons[client] = buttons;
	return Plugin_Continue;
}

public Event_OnResetJump(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	// Don't reset the jumping right after the player jumped.
	// In CSGO the player_footstep event is fired right before the player takes off. Ignore that one event.
	if(g_fLJumpPlayerJumped[client] > 0.0 && (GetEngineTime() - g_fLJumpPlayerJumped[client]) > 0.003)
		g_fLJumpPlayerJumped[client] = -1.0;
}

LJump_HasJumped(client, Float:vVelocity[3], bool:bFirstJump)
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
	if(iLevel <= 0)
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new Float:fMultiplicator;
	// The first jump receives a bigger boost to get away from dangerous places quickly.
	if(bFirstJump)
		fMultiplicator = GetConVarFloat(g_hCVIncreaseStart);
	else
		fMultiplicator = GetConVarFloat(g_hCVIncrease);
	
	new Float:fIncrease = fMultiplicator * float(iLevel) + 1.0;
	vVelocity[0] *= fIncrease;
	vVelocity[1] *= fIncrease;
	
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vVelocity);
}
