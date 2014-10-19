#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <smrpg_effects>
#include <smrpg_sharedmaterials>

#undef REQUIRE_PLUGIN
#include <smrpg_helper>

#define PLUGIN_VERSION "1.0"

#include "smrpg_effects/rendercolor.sp"
#include "smrpg_effects/freeze.sp"

public Plugin:myinfo = 
{
	name = "SM:RPG > Effect Hub",
	author = "Peace-Maker",
	description = "Central place for effects.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("smrpg_effects");
	RegisterFreezeNatives();
	RegisterRenderColorNatives();
	
	return APLRes_Success;
}

public OnPluginStart()
{
	SMRPG_GC_CheckSharedMaterialsAndSounds();
	
	RegisterFreezeForwards();
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	
	// Account for late loading
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public OnMapStart()
{
	PrecacheFreezeSounds();
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	ResetRenderColorClient(client);
}

public OnClientDisconnect(client)
{
	ResetFreezeClient(client);
	ResetRenderColorClient(client);
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;

	ResetFreezeClient(client);
	ApplyDefaultRenderColor(client);
}

public Event_OnPlayerDeath(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;

	ResetFreezeClient(client);
}

/**
 * Helpers
 */
// IsValidHandle() is deprecated, let's do a real check then...
// By Thraaawn
stock bool:IsValidPlugin(Handle:hPlugin) {
	if(hPlugin == INVALID_HANDLE)
		return false;

	new Handle:hIterator = GetPluginIterator();

	new bool:bPluginExists = false;
	while(MorePlugins(hIterator)) {
		new Handle:hLoadedPlugin = ReadPlugin(hIterator);
		if(hLoadedPlugin == hPlugin) {
			bPluginExists = true;
			break;
		}
	}

	CloseHandle(hIterator);

	return bPluginExists;
}