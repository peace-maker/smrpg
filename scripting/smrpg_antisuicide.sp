#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#pragma newdecls required

ConVar g_hCVLastAttackSince;
ConVar g_hCVExpPunish;

enum struct HitInfo {
	int attacker;
	float damage;
	int lastattack;
}

ArrayList g_hHitInfo[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG > Anti-Selfkill",
	author = "Peace-Maker",
	description = "Punishes players for suiciding.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	ConVar hVersion = CreateConVar("smrpg_antiselfkill_version", SMRPG_VERSION, "", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != null)
	{
		hVersion.SetString(SMRPG_VERSION);
		hVersion.AddChangeHook(ConVar_VersionChanged);
	}
	
	g_hCVLastAttackSince = CreateConVar("smrpg_antiselfkill_lastattack", "10", "Only take experience, if the selfkiller got attacked by someone in the last x seconds.", _, true, 0.0);
	g_hCVExpPunish = CreateConVar("smrpg_antiselfkill_exppunish", "0.1", "Take x% of the experience required for the next level.", _, true, 0.0, true, 1.0);
	
	LoadTranslations("smrpg_antisuicide.phrases");
	AutoExecConfig();
	
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
}

public void ConVar_VersionChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	convar.SetString(SMRPG_VERSION);
}

/**
 * Public global forwards
 */
public void OnClientPutInServer(int client)
{
	g_hHitInfo[client] = new ArrayList(sizeof(HitInfo));
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public void OnClientDisconnect_Post(int client)
{
	delete g_hHitInfo[client];
}


/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	// Forget every previous damage
	g_hHitInfo[client].Clear();
}


public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if(!victim)
		return;
	
	int iSize = g_hHitInfo[victim].Length;
	// Make sure he got attacked before
	if(!iSize)
		return;
	
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	// Don't care for regular frags.
	if(!attacker || victim != attacker)
	{
		g_hHitInfo[victim].Clear();
		return;
	}
	
	// The player suicided!
	// Find the attacker, who did the most damage
	SortADTArrayCustom(g_hHitInfo[victim], ADT_SortHitInfoByDamage);
	
	HitInfo hitInfo;
	g_hHitInfo[victim].GetArray(0, hitInfo, sizeof(HitInfo));
	
	// TODO: Give regular kill experience to last attacker.
	
	// Take some exp from the selfkiller
	SortADTArrayCustom(g_hHitInfo[victim], ADT_SortHitInfoByAttacktime);
	g_hHitInfo[victim].GetArray(0, hitInfo, sizeof(HitInfo));
	
	// Make sure he got attacked not long ago and might prevented that attacker from earning experience for a kill.
	int iLastAttackSince = g_hCVLastAttackSince.IntValue;
	if(iLastAttackSince == 0 || (GetTime() - hitInfo.lastattack) < iLastAttackSince)
	{
		int iNeededExp = SMRPG_LevelToExperience(SMRPG_GetClientLevel(victim));
		int iReducedExp = RoundToCeil(iNeededExp * g_hCVExpPunish.FloatValue);
		int iExp = SMRPG_GetClientExperience(victim);
		if(iReducedExp > iExp)
			iReducedExp = iExp;
		SMRPG_SetClientExperience(victim, iExp - iReducedExp);
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > %t", "Player lost experience for suicide", victim, iReducedExp);
		LogMessage("%L lost %d experience for suiciding. (now %d/%d)", victim, iReducedExp, SMRPG_GetClientExperience(victim), iNeededExp);
	}
	
	g_hHitInfo[victim].Clear();
}

/**
 * SDK Hooks callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(victim <= 0 || victim > MaxClients || attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
		return;
	
	HitInfo hitInfo;
	int iIndex = -1;
	int iSize = g_hHitInfo[victim].Length;
	for(int i=0;i<iSize;i++)
	{
		g_hHitInfo[victim].GetArray(i, hitInfo, sizeof(HitInfo));
		// Search the old hitinfo of this attacker
		if(hitInfo.attacker != attacker)
			continue;
		
		iIndex = i;
		break;
	}
	
	hitInfo.attacker = attacker;
	hitInfo.lastattack = GetTime();
	
	// First time the attacker attacked this player?
	if(iIndex == -1)
	{
		hitInfo.damage = damage;
		g_hHitInfo[victim].PushArray(hitInfo, sizeof(HitInfo));
	}
	// Already damaged him before.
	else
	{
		hitInfo.damage += damage;
		g_hHitInfo[victim].SetArray(iIndex, hitInfo, sizeof(HitInfo));
	}
}

/**
 * Misc ADT array sorting
 */
public int ADT_SortHitInfoByDamage(int index1, int index2, Handle array, Handle hndl)
{
	HitInfo hitInfo1, hitInfo2;
	ArrayList arrayList = view_as<ArrayList>(array);
	arrayList.GetArray(index1, hitInfo1, sizeof(HitInfo));
	arrayList.GetArray(index2, hitInfo2, sizeof(HitInfo));
	
	return RoundToCeil(hitInfo2.damage - hitInfo1.damage);
}

public int ADT_SortHitInfoByAttacktime(int index1, int index2, Handle array, Handle hndl)
{
	HitInfo hitInfo1, hitInfo2;
	ArrayList arrayList = view_as<ArrayList>(array);
	arrayList.GetArray(index1, hitInfo1, sizeof(HitInfo));
	arrayList.GetArray(index2, hitInfo2, sizeof(HitInfo));
	
	return hitInfo2.lastattack - hitInfo1.lastattack;
}
