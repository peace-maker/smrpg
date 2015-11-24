#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#define PLUGIN_VERSION "1.0"

new Handle:g_hCVLastAttackSince;
new Handle:g_hCVExpPunish;

enum HitInfo {
	HI_attacker,
	Float:HI_damage,
	HI_lastattack
};

new Handle:g_hHitInfo[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG > Anti-Selfkill",
	author = "Peace-Maker",
	description = "Punishes players for suiciding.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	new Handle:hVersion = CreateConVar("smrpg_antiselfkill_version", PLUGIN_VERSION, "", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != INVALID_HANDLE)
	{
		SetConVarString(hVersion, PLUGIN_VERSION);
		HookConVarChange(hVersion, ConVar_VersionChanged);
	}
	
	g_hCVLastAttackSince = CreateConVar("smrpg_antiselfkill_lastattack", "10", "Only take experience, if the selfkiller got attacked by someone in the last x seconds.", _, true, 0.0);
	g_hCVExpPunish = CreateConVar("smrpg_antiselfkill_exppunish", "0.1", "Take x% of the experience required for the next level.", _, true, 0.0, true, 1.0);
	
	AutoExecConfig();
	
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
}

public ConVar_VersionChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	SetConVarString(convar, PLUGIN_VERSION);
}

/**
 * Public global forwards
 */
public OnClientPutInServer(client)
{
	g_hHitInfo[client] = CreateArray(_:HitInfo);
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	if(g_hHitInfo[client] != INVALID_HANDLE)
		CloseHandle(g_hHitInfo[client]);
	g_hHitInfo[client] = INVALID_HANDLE;
}


/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	// Forget every previous damage
	ClearArray(g_hHitInfo[client]);
}


public Event_OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!victim)
		return;
	
	new iSize = GetArraySize(g_hHitInfo[victim]);
	// Make sure he got attacked before
	if(!iSize)
		return;
	
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	// Don't care for regular frags.
	if(!attacker || victim != attacker)
	{
		ClearArray(g_hHitInfo[victim]);
		return;
	}
	
	// The player suicided!
	// Find the attacker, who did the most damage
	SortADTArrayCustom(g_hHitInfo[victim], ADT_SortHitInfoByDamage);
	
	new eHitInfo[HitInfo];
	GetArrayArray(g_hHitInfo[victim], 0, eHitInfo[0], _:HitInfo);
	
	// TODO: Give regular kill experience to last attacker.
	
	// Take some exp from the selfkiller
	SortADTArrayCustom(g_hHitInfo[victim], ADT_SortHitInfoByAttacktime);
	GetArrayArray(g_hHitInfo[victim], 0, eHitInfo[0], _:HitInfo);
	
	// Make sure he got attacked not long ago and might prevented that attacker from earning experience for a kill.
	new iLastAttackSince = GetConVarInt(g_hCVLastAttackSince);
	if(iLastAttackSince == 0 || (GetTime() - eHitInfo[HI_lastattack]) < iLastAttackSince)
	{
		new iNeededExp = SMRPG_LevelToExperience(SMRPG_GetClientLevel(victim));
		new iReducedExp = RoundToCeil(iNeededExp * GetConVarFloat(g_hCVExpPunish));
		new iExp = SMRPG_GetClientExperience(victim);
		if(iReducedExp > iExp)
			iReducedExp = iExp;
		SMRPG_SetClientExperience(victim, iExp - iReducedExp);
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > %N{G} lost {RB}%d experience{G} for suiciding during battle.", victim, iReducedExp);
		LogMessage("%L lost %d experience for suiciding. (now %d/%d)", victim, iReducedExp, SMRPG_GetClientExperience(victim), iNeededExp);
	}
	
	ClearArray(g_hHitInfo[victim]);
}

/**
 * SDK Hooks callbacks
 */
public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(victim <= 0 || victim > MaxClients || attacker <= 0 || attacker > MaxClients)
		return;
	
	new eHitInfo[HitInfo], iIndex = -1;
	new iSize = GetArraySize(g_hHitInfo[victim]);
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(g_hHitInfo[victim], i, eHitInfo[0], _:HitInfo);
		// Search the old hitinfo of this attacker
		if(eHitInfo[HI_attacker] != attacker)
			continue;
		
		iIndex = i;
		break;
	}
	
	eHitInfo[HI_attacker] = attacker;
	eHitInfo[HI_lastattack] = GetTime();
	
	// First time the attacker attacked this player?
	if(iIndex == -1)
	{
		eHitInfo[HI_damage] = damage;
		PushArrayArray(g_hHitInfo[victim], eHitInfo[0], _:HitInfo);
	}
	// Already damaged him before.
	else
	{
		eHitInfo[HI_damage] += damage;
		SetArrayArray(g_hHitInfo[victim], iIndex, eHitInfo[0], _:HitInfo);
	}
}

/**
 * Misc ADT array sorting
 */
public ADT_SortHitInfoByDamage(index1, index2, Handle:array, Handle:hndl)
{
	new eHitInfo1[HitInfo], eHitInfo2[HitInfo];
	GetArrayArray(array, index1, eHitInfo1[0], _:HitInfo);
	GetArrayArray(array, index2, eHitInfo2[0], _:HitInfo);
	
	return RoundToCeil(eHitInfo2[HI_damage] - eHitInfo1[HI_damage]);
}

public ADT_SortHitInfoByAttacktime(index1, index2, Handle:array, Handle:hndl)
{
	new eHitInfo1[HitInfo], eHitInfo2[HitInfo];
	GetArrayArray(array, index1, eHitInfo1[0], _:HitInfo);
	GetArrayArray(array, index2, eHitInfo2[0], _:HitInfo);
	
	return eHitInfo2[HI_lastattack] - eHitInfo1[HI_lastattack];
}