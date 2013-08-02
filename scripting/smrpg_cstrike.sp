#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smrpg>

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

public Plugin:myinfo = 
{
	name = "SM:RPG > CSS Experience Module",
	author = "Jannik \"Peace-Maker\" Hartung, SeLfkiLL",
	description = "CSS specific calculations for SM:RPG",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
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
	
	HookEvent("player_hurt", Event_OnPlayerHurt);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("bomb_planted", Event_OnBombPlanted);
	HookEvent("bomb_defused", Event_OnBombDefused);
	HookEvent("bomb_exploded", Event_OnBombExploded);
	HookEvent("hostage_rescued", Event_OnHostageRescued);
	HookEvent("vip_escaped", Event_OnVIPEscaped);
}

public OnAllPluginsLoaded()
{
	g_hCVExpKill = FindConVar("smrpg_exp_kill");
	g_hCVExpDamage = FindConVar("smrpg_exp_damage");
	g_hCVExpTeamwin = FindConVar("smrpg_exp_teamwin");
}

public Action:SMRPG_OnAddExperience(client, ExperienceReason:reason, &iExperience)
{
	// Don't let the normal experience calculation hit. We're doing some cstrike specific stuff here.
	return Plugin_Handled;
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
	
	new iExp = SMRPG_GetClientLevel(victim) * GetConVarInt(g_hCVExpKill);
	if(GetEventBool(event, "headshot"))
		iExp += GetConVarInt(g_hCVExpHeadshot);
	
	SMRPG_AddClientExperience(attacker, iExp, false);
}

/* Experience given to the team for one of these reasons:
	1   Target Successfully Bombed!
	2   The VIP has escaped!
	3   VIP has been assassinated!
	7   The bomb has been defused!
	11   All Hostages have been rescued!
	12   Target has been saved!
	13   Hostages have not been rescued!
*/
public Event_OnRoundEnd(Handle:event, const String:error[], bool:dontBroadcast)
{
	new iTeam = GetEventInt(event, "winner");
	new iReason = GetEventInt(event, "reason");
	
	if(!SMRPG_IsEnabled())
		return;
	
	switch(iReason)
	{
		case 1, 2, 3, 7, 11, 12, 13:
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
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarInt(g_hCVExpBombPlanted) * fTeamRatio), false);
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
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarInt(g_hCVExpBombDefused) * fTeamRatio), false);
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
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarInt(g_hCVExpBombExploded) * fTeamRatio), false);
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
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarInt(g_hCVExpHostage) * fTeamRatio), false);
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
	SMRPG_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarInt(g_hCVExpVIPEscaped) * fTeamRatio), false);
}