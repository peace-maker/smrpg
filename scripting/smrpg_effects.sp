#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg_effects>
#include <smrpg_sharedmaterials>

#undef REQUIRE_PLUGIN
#include <smrpg_helper>

ConVar g_hCVCreditFireAttacker;

#include "smrpg_effects/rendercolor.sp"
#include "smrpg_effects/freeze.sp"
#include "smrpg_effects/ignite.sp"
#include "smrpg_effects/laggedmovement.sp"

public Plugin myinfo = 
{
	name = "SM:RPG > Effect Hub",
	author = "Peace-Maker",
	description = "Central place for effects.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("smrpg_effects");
	RegisterFreezeNatives();
	RegisterRenderColorNatives();
	RegisterIgniteNatives();
	RegisterLaggedMovementNatives();
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	SMRPG_GC_CheckSharedMaterialsAndSounds();
	
	RegisterFreezeForwards();
	RegisterIgniteForwards();
	RegisterLaggedMovementForwards();
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);

	g_hCVCreditFireAttacker = CreateConVar("smrpg_credit_ignite_attacker", "1", "Credit fire damage to the attacker which ignited the victim?", _, true, 0.0, true, 1.0);
	AutoExecConfig(true, "plugin.smrpg_effects");
	
	SetupFreezeData();

	// Account for late loading
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnMapStart()
{
	PrecacheFreezeSounds();
	ReadLimitDamageConfig();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	ResetRenderColorClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetRenderColorClient(client);
	ResetFreezeClient(client);
	ResetIgniteClient(client, true);
	ResetLaggedMovementClient(client);
}

/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;

	ResetFreezeClient(client);
	ResetIgniteClient(client, false);
	ApplyDefaultRenderColor(client);
	ResetLaggedMovementClient(client);
}

public void Event_OnPlayerDeath(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;

	ResetFreezeClient(client);
	ResetIgniteClient(client, false);
	ResetLaggedMovementClient(client);
}

/**
 * Hook callbacks
 */
public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	Action iRetFreeze = Freeze_OnTakeDamage(victim, attacker, inflictor, damage);
	Action iRetIgnite = Ignite_OnTakeDamage(victim, attacker, inflictor, damage, damagetype);
	return iRetFreeze > iRetIgnite ? iRetFreeze : iRetIgnite;
}

/**
 * Helpers
 */
// IsValidHandle() is deprecated, let's do a real check then...
// By Thraaawn
stock bool IsValidPlugin(Handle hPlugin) {
	if(hPlugin == null)
		return false;

	Handle hIterator = GetPluginIterator();

	bool bPluginValid = false;
	while(MorePlugins(hIterator)) {
		Handle hLoadedPlugin = ReadPlugin(hIterator);
		if(hLoadedPlugin == hPlugin) {
			bPluginValid = GetPluginStatus(hLoadedPlugin) == Plugin_Running;
			break;
		}
	}

	delete hIterator;

	return bPluginValid;
}

// This removes a prefix from a string including anything before the prefix.
// This is useful for TF2's tfweapon_ prefix vs. default weapon_ prefix in other sourcegames.
stock void RemovePrefixFromString(const char[] sPrefix, const char[] sInput, char[] sOutput, int maxlen)
{
	int iPos = StrContains(sInput, sPrefix, false);
	// The prefix isn't in the string, just copy the whole string.
	if(iPos == -1)
		iPos = 0;
	// Skip the prefix and all other stuff before it.
	else
		iPos += strlen(sPrefix);
	
	// Support for inputstring == outputstring?
	char[] sBuffer = new char[maxlen+1];
	strcopy(sBuffer, maxlen, sInput[iPos]);
	
	strcopy(sOutput, maxlen, sBuffer);
}
