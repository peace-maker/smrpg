#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <sdktools>

#define PLUGIN_VERSION "1.0"
#define UPGRADE_SHORTNAME "ljump"

/* Percent of player's jump to increase */
#define LJUMP_INC 0.20

new Float:g_fLJumpPreviousVelocity[MAXPLAYERS+1][3];
new bool:g_bLJumpPlayerJumped[MAXPLAYERS+1];

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
	HookEvent("player_footstep", Event_OnResetJump);
	HookEvent("player_spawn", Event_OnResetJump);
	HookEvent("player_death", Event_OnResetJump);
	HookEvent("player_jump", Event_OnPlayerJump);
	
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
		SMRPG_RegisterUpgradeType("Long Jump", UPGRADE_SHORTNAME, "Boosts your jump speed.", 10, true, 5, 20, 15, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
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

public SMRPG_TranslateUpgrade(client, TranslationType:type, String:translation[], maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
		return;
}

public OnClientDisconnect(client)
{
	g_bLJumpPlayerJumped[client] = false;
}

public OnGameFrame()
{
	decl Float:vVelocity[3];
	for(new i=1;i<=MaxClients;i++)
	{
		if(!g_bLJumpPlayerJumped[i])
			continue;
		
		if(!IsClientInGame(i))
			continue;
		
		GetEntPropVector(i, Prop_Data, "m_vecVelocity", vVelocity);
		if(vVelocity[2] > g_fLJumpPreviousVelocity[i][2])
		{
			LJump_HasJumped(i, vVelocity);
			g_bLJumpPlayerJumped[i] = false;
		}
	}
}

public Event_OnPlayerJump(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", g_fLJumpPreviousVelocity[client]);
	g_bLJumpPlayerJumped[client] = true;
}

public Event_OnResetJump(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_bLJumpPlayerJumped[client] = false;
}

LJump_HasJumped(client, Float:vVelocity[3])
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
	
	new Float:fIncrease = LJUMP_INC * float(iLevel) + 1.0;
	vVelocity[0] *= fIncrease;
	vVelocity[1] *= fIncrease;
	
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vVelocity);
}
