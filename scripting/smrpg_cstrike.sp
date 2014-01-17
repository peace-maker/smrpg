#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <smrpg>
#include <smlib>

#define PLUGIN_VERSION "1.0"

new Handle:g_hCVExpKill;
new Handle:g_hCVExpDamage;
new Handle:g_hCVExpTeamwin;

new Handle:g_hCVExpKnifeDmg;
new Handle:g_hCVExpHeadshot;

new Handle:g_hCVExpBombPlanted;
new Handle:g_hCVExpBombDefused;
new Handle:g_hCVExpBombExploded;
new Handle:g_hCVExpHostage;
new Handle:g_hCVExpVIPEscaped;

new Handle:g_hCVShowMVPLevel;
new Handle:g_hCVEnableAntiKnifeleveling;

enum KnifeLeveling {
	KL_Hits,
	KL_LastAttack,
	KL_FirstAttack
};

new g_iKnifeDamage[MAXPLAYERS+1][MAXPLAYERS+1][KnifeLeveling];
new bool:g_bKnifeLeveled[MAXPLAYERS+1];
new Handle:g_hKnifeLevelCooldown[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG > CSS Experience Module",
	author = "Jannik \"Peace-Maker\" Hartung, SeLfkiLL",
	description = "CSS specific calculations for SM:RPG",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	new EngineVersion:engine = GetEngineVersion();
	if(engine != Engine_CSS)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike:Source only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public OnPluginStart()
{
	g_hCVExpKnifeDmg = CreateConVar("smrpg_exp_knifedmg", "8.0", "Experience for knifing an enemy multiplied by the damage done (must be higher than smrpg_exp_damage)", 0, true, 0.0);
	g_hCVExpHeadshot = CreateConVar("smrpg_exp_headshot", "50.0", "Experience extra for a headshot", 0, true, 0.0);
	
	g_hCVExpBombPlanted = CreateConVar("smrpg_exp_bombplanted", "0.15", "Experience multipled by the experience required and the team ratio given for planting the bomb", 0, true, 0.0);
	g_hCVExpBombDefused = CreateConVar("smrpg_exp_bombdefused", "0.30", "Experience multipled by the experience required and the team ratio given for defusing the bomb", 0, true, 0.0);
	g_hCVExpBombExploded = CreateConVar("smrpg_exp_bombexploded", "0.20", "Experience multipled by the experience required and the team ratio given to the bomb planter when it explodes", 0, true, 0.0);
	g_hCVExpHostage = CreateConVar("smrpg_exp_hostage", "0.10", "Experience multipled by the experience required and the team ratio for rescuing a hostage", 0, true, 0.0);
	g_hCVExpVIPEscaped = CreateConVar("smrpg_exp_vipescaped", "0.35", "Experience multipled by the experience required and the team ratio given to the vip when the vip escapes", 0, true, 0.0);
	
	g_hCVShowMVPLevel = CreateConVar("smrpg_mvp_level", "1", "Show player level as MVP stars on the scoreboard?", 0, true, 0.0, true, 1.0);
	g_hCVEnableAntiKnifeleveling = CreateConVar("smrpg_anti_knifelevel", "1", "Stop giving exp to players who knife each other too often in a time frame?", 0, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "plugin.smrpg_cstrike");
	
	LoadTranslations("smrpg_cstrike.phrases");
	
	HookEvent("player_hurt", Event_OnPlayerHurt);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("bomb_planted", Event_OnBombPlanted);
	HookEvent("bomb_defused", Event_OnBombDefused);
	HookEvent("bomb_exploded", Event_OnBombExploded);
	HookEvent("hostage_rescued", Event_OnHostageRescued);
	HookEvent("vip_escaped", Event_OnVIPEscaped);
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("round_mvp", Event_OnRoundMVP);
}

public OnAllPluginsLoaded()
{
	g_hCVExpKill = FindConVar("smrpg_exp_kill");
	g_hCVExpDamage = FindConVar("smrpg_exp_damage");
	g_hCVExpTeamwin = FindConVar("smrpg_exp_teamwin");
}

// Reset anti knifeleveling stuff
public OnClientDisconnect(client)
{
	g_bKnifeLeveled[client] = false;
	ClearHandle(g_hKnifeLevelCooldown[client]);
	
	for(new i=1;i<=MaxClients;i++)
	{
		g_iKnifeDamage[client][i][KL_Hits] = 0;
		g_iKnifeDamage[client][i][KL_LastAttack] = 0;
		g_iKnifeDamage[client][i][KL_FirstAttack] = 0;
		
		g_iKnifeDamage[i][client][KL_Hits] = 0;
		g_iKnifeDamage[i][client][KL_LastAttack] = 0;
		g_iKnifeDamage[i][client][KL_FirstAttack] = 0;
	}
}

public Action:SMRPG_OnAddExperience(client, ExperienceReason:reason, &iExperience)
{
	// Don't let the normal experience calculation hit. We're doing some cstrike specific stuff here.
	return Plugin_Handled;
}

public Action:SMRPG_OnClientLevel(client, oldlevel, newlevel)
{
	if(!GetConVarBool(g_hCVShowMVPLevel))
		return Plugin_Continue;
	
	if(IsClientInGame(client))
		CS_SetMVPCount(client, newlevel);
	
	return Plugin_Continue;
}

public Event_OnPlayerSpawn(Handle:event, const String:error[], bool:dontBroadcast)
{
	if(!GetConVarBool(g_hCVShowMVPLevel))
		return;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	CS_SetMVPCount(client, SMRPG_GetClientLevel(client));
}

public Event_OnRoundMVP(Handle:event, const String:error[], bool:dontBroadcast)
{
	if(!GetConVarBool(g_hCVShowMVPLevel))
		return;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	CS_SetMVPCount(client, SMRPG_GetClientLevel(client));
}

public Event_OnPlayerHurt(Handle:event, const String:error[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	new iDmgHealth = GetEventInt(event, "dmg_health");
	new iDmgArmor = GetEventInt(event, "dmg_armor");
	decl String:sWeapon[32];
	GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
	
	if(attacker == 0 || victim == 0)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	// Ignore teamattack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iExp;
	new iTotalDmg = iDmgHealth+iDmgArmor;
	if(StrContains(sWeapon, "knife") != -1)
	{
		// If this guy didn't attack the other player for 30 seconds, reset his hit count.
		if((GetTime() - g_iKnifeDamage[attacker][victim][KL_LastAttack]) > 30)
		{
			//PrintToServer("%N didn't knife %N for at least 30 seconds. Resetting hit count.", attacker, victim);
			g_iKnifeDamage[attacker][victim][KL_Hits] = 0;
		}
		
		// Remember this great moment of first strike!
		if(g_iKnifeDamage[attacker][victim][KL_Hits] == 0)
			g_iKnifeDamage[attacker][victim][KL_FirstAttack] = GetTime();
		
		g_iKnifeDamage[attacker][victim][KL_Hits]++;
		g_iKnifeDamage[attacker][victim][KL_LastAttack] = GetTime();
		
		// Player attacked victim at least 5 times at least 10 seconds after the first attack
		if(g_iKnifeDamage[attacker][victim][KL_Hits] > 5 && (g_iKnifeDamage[attacker][victim][KL_LastAttack] - g_iKnifeDamage[attacker][victim][KL_FirstAttack]) > 10)
		{
			//PrintToServer("%N is knifeleveling on %N. hits %d, time since first attack: %d", attacker, victim, g_iKnifeDamage[attacker][victim][KL_Hits], (g_iKnifeDamage[attacker][victim][KL_LastAttack] - g_iKnifeDamage[attacker][victim][KL_FirstAttack]));
			if(GetConVarBool(g_hCVEnableAntiKnifeleveling) && !g_bKnifeLeveled[attacker])
			{
				LogMessage("%L is knifeleveling with %L.", attacker, victim);
				Client_PrintToChatAll(false, "%t", "Player is knifeleveling", attacker, victim);
			}
				
			g_bKnifeLeveled[attacker] = true;
			ClearHandle(g_hKnifeLevelCooldown[attacker]);
			g_hKnifeLevelCooldown[attacker] = CreateTimer(60.0, Timer_ResetKnifeLeveling, GetClientUserId(attacker), TIMER_FLAG_NO_MAPCHANGE);
		}
		
		// Don't give any experience at all for knife leveling.
		if(GetConVarBool(g_hCVEnableAntiKnifeleveling) && g_bKnifeLeveled[attacker])
			return;
		
		if(GetConVarFloat(g_hCVExpKnifeDmg) > GetConVarFloat(g_hCVExpDamage))
			iExp = RoundToCeil(float(iTotalDmg) * GetConVarFloat(g_hCVExpKnifeDmg));
		else
			iExp = RoundToCeil(float(iTotalDmg) * GetConVarFloat(g_hCVExpDamage));
	}
	else
	{
		iExp = RoundToCeil(float(iTotalDmg) * GetConVarFloat(g_hCVExpDamage));
	}
	
	SMRPG_AddClientExperience(attacker, iExp, true);
}

public Event_OnPlayerDeath(Handle:event, const String:error[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(attacker == 0 || victim == 0)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	// Ignore teamattack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * GetConVarFloat(g_hCVExpKill));
	if(GetEventBool(event, "headshot"))
		iExp += GetConVarInt(g_hCVExpHeadshot);
	
	SMRPG_AddClientExperience(attacker, iExp, false);
}

/* Experience given to the team for one of these reasons:
	0   Target Successfully Bombed!
	1   The VIP has escaped!
	2   VIP has been assassinated!
	6   The bomb has been defused!
	10   All Hostages have been rescued!
	11   Target has been saved!
	12   Hostages have not been rescued!
*/
public Event_OnRoundEnd(Handle:event, const String:error[], bool:dontBroadcast)
{
	new iTeam = GetEventInt(event, "winner");
	new CSRoundEndReason:iReason = CSRoundEndReason:GetEventInt(event, "reason");
	
	if(!SMRPG_IsEnabled())
		return;
	
	switch(iReason)
	{
		case CSRoundEnd_TargetBombed, CSRoundEnd_VIPEscaped, CSRoundEnd_VIPKilled, CSRoundEnd_BombDefused, CSRoundEnd_HostagesRescued, CSRoundEnd_TargetSaved, CSRoundEnd_HostagesNotRescued:
		{
		}
		default:
			return;
	}
	
	new Float:fTeamRatio;
	if(iTeam == 2)
		fTeamRatio = SMRPG_TeamRatio(3);
	else if(iTeam == 3)
		fTeamRatio = SMRPG_TeamRatio(2);
	else
		return;
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == iTeam)
			SMRPG_AddClientExperience(i, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(i))) * GetConVarFloat(g_hCVExpTeamwin) * fTeamRatio), false);
	}
}

public Event_OnBombPlanted(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpBombPlanted) * fTeamRatio), false);
}

public Event_OnBombDefused(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpBombDefused) * fTeamRatio), false);
}

public Event_OnBombExploded(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpBombExploded) * fTeamRatio), false);
}

public Event_OnHostageRescued(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpHostage) * fTeamRatio), false);
}

public Event_OnVIPEscaped(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpVIPEscaped) * fTeamRatio), false);
}

public Action:Timer_ResetKnifeLeveling(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	//PrintToServer("%N knifeleveling status was reset.", client);
	g_hKnifeLevelCooldown[client] = INVALID_HANDLE;
	g_bKnifeLeveled[client] = false;
	return Plugin_Stop;
}