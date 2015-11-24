#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <smrpg>
#include <smlib>
#include <autoexecconfig>

#define PLUGIN_VERSION "1.0"

//#define _DEBUG

new bool:g_bIsCSGO;

new Handle:g_hCVExpKillMax;
new Handle:g_hCVExpTeamwin;

new Handle:g_hCVExpKillAssist;

new Handle:g_hCVExpHeadshot;

new Handle:g_hCVExpBombPlanted;
new Handle:g_hCVExpBombDefused;
new Handle:g_hCVExpBombExploded;
new Handle:g_hCVExpHostage;
new Handle:g_hCVExpVIPEscaped;

new Handle:g_hCVExpDominating;
new Handle:g_hCVExpRevenge;

new Handle:g_hCVBotEarnExpObjective;

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
new g_iKnifeLevelDetections[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "SM:RPG > Counter-Strike Experience Module",
	author = "Jannik \"Peace-Maker\" Hartung, SeLfkiLL",
	description = "Counter-Strike specific calculations for SM:RPG",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	new EngineVersion:engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	
	g_bIsCSGO = engine == Engine_CSGO;
	
	return APLRes_Success;
}

public OnPluginStart()
{
	AutoExecConfig_SetFile("plugin.smrpg_cstrike");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(INVALID_HANDLE);
	
	g_hCVExpKillAssist = AutoExecConfig_CreateConVar("smrpg_exp_kill_assist", "10.0", "Experience for assisting in killing a player multiplied by the victim's level", 0, true, 0.0);
	
	g_hCVExpHeadshot = AutoExecConfig_CreateConVar("smrpg_exp_headshot", "50.0", "Experience extra for a headshot", 0, true, 0.0);
	
	g_hCVExpBombPlanted = AutoExecConfig_CreateConVar("smrpg_exp_bombplanted", "0.15", "Experience multipled by the experience required and the team ratio given for planting the bomb", 0, true, 0.0);
	g_hCVExpBombDefused = AutoExecConfig_CreateConVar("smrpg_exp_bombdefused", "0.30", "Experience multipled by the experience required and the team ratio given for defusing the bomb", 0, true, 0.0);
	g_hCVExpBombExploded = AutoExecConfig_CreateConVar("smrpg_exp_bombexploded", "0.20", "Experience multipled by the experience required and the team ratio given to the bomb planter when it explodes", 0, true, 0.0);
	g_hCVExpHostage = AutoExecConfig_CreateConVar("smrpg_exp_hostage", "0.10", "Experience multipled by the experience required and the team ratio for rescuing a hostage", 0, true, 0.0);
	g_hCVExpVIPEscaped = AutoExecConfig_CreateConVar("smrpg_exp_vipescaped", "0.35", "Experience multipled by the experience required and the team ratio given to the vip when the vip escapes", 0, true, 0.0);
	
	g_hCVExpDominating = AutoExecConfig_CreateConVar("smrpg_exp_dominating", "5.0", "Experience for dominating an enemy multiplied by the victim's level.", 0, true, 0.0);
	g_hCVExpRevenge = AutoExecConfig_CreateConVar("smrpg_exp_revenge", "8.0", "Experience for killing a dominating enemy in revenge multiplied by the attackers's level.", 0, true, 0.0);
	
	g_hCVBotEarnExpObjective = AutoExecConfig_CreateConVar("smrpg_bot_exp_objectives", "1", "Should bots earn experience for completing objectives (bomb, hostage, ..)?", 0, true, 0.0, true, 1.0);
	
	g_hCVShowMVPLevel = AutoExecConfig_CreateConVar("smrpg_mvp_level", "1", "Show player level as MVP stars on the scoreboard?", 0, true, 0.0, true, 1.0);
	g_hCVEnableAntiKnifeleveling = AutoExecConfig_CreateConVar("smrpg_anti_knifelevel", "1", "Stop giving exp to players who knife each other too often in a time frame?", 0, true, 0.0, true, 1.0);
	
	AutoExecConfig_ExecuteFile();
	//AutoExecConfig_CleanFile();
	
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
	g_hCVExpKillMax = FindConVar("smrpg_exp_kill_max");
	g_hCVExpTeamwin = FindConVar("smrpg_exp_teamwin");
}

// Reset anti knifeleveling stuff
public OnClientDisconnect(client)
{
	g_bKnifeLeveled[client] = false;
	ClearHandle(g_hKnifeLevelCooldown[client]);
	g_iKnifeLevelDetections[client] = 0;
	
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

public Action:SMRPG_OnAddExperience(client, const String:reason[], &iExperience, other)
{
	// Don't let the normal experience calculation hit. We're doing some cstrike specific stuff here.
	if(StrEqual(reason, ExperienceReason_PlayerHurt) || StrEqual(reason, ExperienceReason_PlayerKill) || StrEqual(reason, ExperienceReason_RoundEnd))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action:SMRPG_OnClientLevel(client, oldlevel, newlevel)
{
	if(!GetConVarBool(g_hCVShowMVPLevel))
		return Plugin_Continue;
	
	if(IsClientInGame(client))
		CS_SetMVPCount(client, newlevel);
	
	return Plugin_Continue;
}

public SMRPG_TranslateExperienceReason(client, const String:reason[], iExperience, other, String:buffer[], maxlen)
{
	// Just use the reason string directly as translation phrase.
	if(other > 0)
		Format(buffer, maxlen, "%T", reason, client, iExperience, other);
	else
		Format(buffer, maxlen, "%T", reason, client, iExperience);
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
	decl String:sWeapon[64];
	GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
	
	if(attacker == 0 || victim == 0)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	if(SMRPG_IsClientAFK(victim))
		return;
	
	// Don't give the attacker any exp when his victim just spawned and didn't do anything at all yet.
	if(SMRPG_IsClientSpawnProtected(victim))
		return;
	
	// Ignore teamattack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
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
				LogMessage("%L (lvl %d) is knifeleveling with %L (lvl %d).", attacker, SMRPG_GetClientLevel(attacker), victim, SMRPG_GetClientLevel(victim));
				Client_PrintToChatAll(false, "%t", "Player is knifeleveling", attacker, victim);
			}
			
			// Keep track on how often that player tried to powerlevel.
			if(!g_bKnifeLeveled[attacker])
				g_iKnifeLevelDetections[attacker]++;
			
			g_bKnifeLeveled[attacker] = true;
			ClearHandle(g_hKnifeLevelCooldown[attacker]);
			g_hKnifeLevelCooldown[attacker] = CreateTimer(60.0*g_iKnifeLevelDetections[attacker], Timer_ResetKnifeLeveling, GetClientUserId(attacker), TIMER_FLAG_NO_MAPCHANGE);
		}
		
		// Don't give any experience at all for knife leveling.
		if(GetConVarBool(g_hCVEnableAntiKnifeleveling) && g_bKnifeLeveled[attacker])
			return;

	}
	
	iExp = RoundToCeil(float(iTotalDmg) * SMRPG_GetWeaponExperience(sWeapon, WeaponExperience_Damage));
	
	if(StrContains(sWeapon, "knife") != -1)
		Debug_AddClientExperience(attacker, iExp, true, "cs_playerknife", victim);
	else
		Debug_AddClientExperience(attacker, iExp, true, "cs_playerhurt", victim);
}

public Event_OnPlayerDeath(Handle:event, const String:error[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new assister;
	
	if(attacker == 0 || victim == 0)
		return;
	
	if(g_bIsCSGO)
	{
		assister = GetClientOfUserId(GetEventInt(event, "assister"));
	}
	
	if(!SMRPG_IsEnabled())
		return;
	
	if(SMRPG_IsClientAFK(victim))
		return;
	
	// Don't give the attacker any exp when his victim just spawned and didn't do anything at all yet.
	if(SMRPG_IsClientSpawnProtected(victim))
		return;
	
	// Give the assisting player some exp.
	if(assister > 0
	&& (SMRPG_IsFFAEnabled() || GetClientTeam(victim) != GetClientTeam(assister)))
	{
		new iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * GetConVarFloat(g_hCVExpKillAssist));
		Debug_AddClientExperience(assister, iExp, false, "cs_playerkillassist", victim);
	}
	
	// Ignore suicide
	if(attacker == victim)
		return;
	
	// Ignore teamattack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new String:sWeapon[64];
	GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
	
	new iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * SMRPG_GetWeaponExperience(sWeapon, WeaponExperience_Kill) + SMRPG_GetWeaponExperience(sWeapon, WeaponExperience_Bonus));
	if(GetEventBool(event, "headshot"))
		iExp += GetConVarInt(g_hCVExpHeadshot);
	
	new iExpMax = GetConVarInt(g_hCVExpKillMax);
	// Limit the possible experience to this.
	if(iExpMax > 0 && iExp > iExpMax)
		iExp = iExpMax;
	
	Debug_AddClientExperience(attacker, iExp, false, "cs_playerkill", victim);
	
	// Player started dominating this player?
	if(GetEventBool(event, "dominated"))
	{
		iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * GetConVarFloat(g_hCVExpDominating));
		Debug_AddClientExperience(attacker, iExp, false, "cs_dominating", victim);
	}
	
	// Player broke the domination and killed him in revenge?
	if(GetEventBool(event, "revenge"))
	{
		iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * GetConVarFloat(g_hCVExpRevenge));
		Debug_AddClientExperience(attacker, iExp, false, "cs_revenge", victim);
	}
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
			Debug_AddClientExperience(i, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(i))) * GetConVarFloat(g_hCVExpTeamwin) * fTeamRatio), false, "cs_winround");
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
	
	if(IsFakeClient(client) && !GetConVarBool(g_hCVBotEarnExpObjective))
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpBombPlanted) * fTeamRatio), false, "cs_bombplanted");
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
	
	if(IsFakeClient(client) && !GetConVarBool(g_hCVBotEarnExpObjective))
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpBombDefused) * fTeamRatio), false, "cs_bombdefused");
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
	
	if(IsFakeClient(client) && !GetConVarBool(g_hCVBotEarnExpObjective))
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpBombExploded) * fTeamRatio), false, "cs_bombexploded");
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
	
	if(IsFakeClient(client) && !GetConVarBool(g_hCVBotEarnExpObjective))
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpHostage) * fTeamRatio), false, "cs_hostagerescued");
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
	
	if(IsFakeClient(client) && !GetConVarBool(g_hCVBotEarnExpObjective))
		return;
	
	new Float:fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * GetConVarFloat(g_hCVExpVIPEscaped) * fTeamRatio), false, "cs_vipescaped");
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

// This stuff is leftover from balancing the experience on a deathmatch server.
// Maybe someone finds it useful too when playing with the experience settings, so i'll leave it here.
Debug_AddClientExperience(client, exp, bool:bHideNotice, const String:sReason[], victim=-1)
{
#if !defined _DEBUG
	// This is all that's really needed
	SMRPG_AddClientExperience(client, exp, sReason, bHideNotice, victim, SMRPG_TranslateExperienceReason);
#else
	new iOldLevel = SMRPG_GetClientLevel(client);
	new iOldExperience = SMRPG_GetClientExperience(client);
	new iOldNeeded = SMRPG_LevelToExperience(iOldLevel);
	
	new iOriginalExperience = exp;
	new bool:bAdded = SMRPG_AddClientExperience(client, exp, sReason, bHideNotice, victim, SMRPG_TranslateExperienceReason);
	
	new iNewLevel = SMRPG_GetClientLevel(client);
	new String:sAttackerAuth[40], String:sVictimString[256], String:sLevelInc[32], String:sChangedExperience[32];
	GetClientAuthId(client, AuthId_Engine, sAttackerAuth, sizeof(sAttackerAuth));
	if(victim > 0)
		Format(sVictimString, sizeof(sVictimString), " %N (lvl %d)", victim, SMRPG_GetClientLevel(victim));
	if(iNewLevel != iOldLevel)
		Format(sLevelInc, sizeof(sLevelInc), " (now lvl %d [%d/%d])", iNewLevel, SMRPG_GetClientExperience(client), SMRPG_LevelToExperience(iNewLevel));
	
	if(iOriginalExperience != exp)
		Format(sChangedExperience, sizeof(sChangedExperience), " (intended %d)", iOriginalExperience);
	
	if(bAdded)
		DebugLog("%N <%s> (lvl %d [%d/%d]) got %d%s exp%s for %s%s.", client, sAttackerAuth, iOldLevel, iOldExperience, iOldNeeded, exp, sChangedExperience, sLevelInc, sReason, sVictimString);
	else
		DebugLog("%N <%s> (lvl %d [%d/%d]) was going to get %d%s exp%s for %s%s, but was blocked by a plugin.", client, sAttackerAuth, iOldLevel, iOldExperience, iOldNeeded, exp, sChangedExperience, sLevelInc, sReason, sVictimString);
#endif
}

#if defined _DEBUG
stock DebugLog(String:format[], any:...)
{
	static String:sLog[8192] = "";
	static Handle:hFile = INVALID_HANDLE;
	static iOpenTime = 0;
	decl String:sBuffer[256];
	SetGlobalTransTarget(LANG_SERVER);
	VFormat(sBuffer, sizeof(sBuffer), format, 2);
	
	decl String:sOldDate[9], String:sCurrentDate[9];
	FormatTime(sOldDate, sizeof(sOldDate), "%Y%m%d", iOpenTime);
	FormatTime(sCurrentDate, sizeof(sCurrentDate), "%Y%m%d");
	
	if(hFile == INVALID_HANDLE || !StrEqual(sOldDate, sCurrentDate))
	{
		decl String:sPath[PLATFORM_MAX_PATH];
		FormatTime(sPath, sizeof(sPath), "%Y_%m_%d");
		BuildPath(Path_SM, sPath, sizeof(sPath), "data/smrpg_experience_%s.log", sPath);
		
		// Basic log rotation
		if(!StrEqual(sOldDate, sCurrentDate) && hFile != INVALID_HANDLE)
			CloseHandle(hFile);
		
		hFile = OpenFile(sPath, "a");
		iOpenTime = GetTime();
	}
	
	// Flush the buffer.
	if((strlen(sLog) + strlen(sBuffer) + 24) >= sizeof(sLog)-1)
	{
		if(hFile != INVALID_HANDLE)
			WriteFileString(hFile, sLog, false);
		sLog[0] = 0;
	}
	
	decl String:sDate[32];
	FormatTime(sDate, sizeof(sDate), "%m/%d/%Y - %H:%M:%S: ");
	StrCat(sLog, sizeof(sLog), sDate);
	StrCat(sLog, sizeof(sLog), sBuffer);
	StrCat(sLog, sizeof(sLog), "\n");
}
#endif