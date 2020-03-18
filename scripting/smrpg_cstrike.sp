#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <smrpg>
#include <smlib>
#include <autoexecconfig>

#pragma newdecls required

//#define _DEBUG

bool g_bIsCSGO;

ConVar g_hCVExpKillMax;
ConVar g_hCVExpTeamwin;

ConVar g_hCVExpKillAssist;

ConVar g_hCVExpHeadshot;

ConVar g_hCVExpBombPlanted;
ConVar g_hCVExpBombDefused;
ConVar g_hCVExpBombExploded;
ConVar g_hCVExpHostage;
ConVar g_hCVExpVIPEscaped;

ConVar g_hCVExpDominating;
ConVar g_hCVExpRevenge;

ConVar g_hCVExpDZPlace[3];

ConVar g_hCVBotEarnExpObjective;

ConVar g_hCVShowMVPLevel;
ConVar g_hCVEnableAntiKnifeleveling;

ConVar g_hCVDisableXPDuringWarmup;

enum KnifeLeveling {
	KL_Hits,
	KL_LastAttack,
	KL_FirstAttack
};

int g_iKnifeDamage[MAXPLAYERS+1][MAXPLAYERS+1][KnifeLeveling];
bool g_bKnifeLeveled[MAXPLAYERS+1];
Handle g_hKnifeLevelCooldown[MAXPLAYERS+1];
int g_iKnifeLevelDetections[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG > Counter-Strike Experience Module",
	author = "Jannik \"Peace-Maker\" Hartung, SeLfkiLL",
	description = "Counter-Strike specific calculations for SM:RPG",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	
	g_bIsCSGO = engine == Engine_CSGO;
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	AutoExecConfig_SetFile("plugin.smrpg_cstrike");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(null);
	
	g_hCVExpKillAssist = AutoExecConfig_CreateConVar("smrpg_exp_kill_assist", "10.0", "Experience for assisting in killing a player multiplied by the victim's level", 0, true, 0.0);
	
	g_hCVExpHeadshot = AutoExecConfig_CreateConVar("smrpg_exp_headshot", "50.0", "Experience extra for a headshot", 0, true, 0.0);
	
	g_hCVExpBombPlanted = AutoExecConfig_CreateConVar("smrpg_exp_bombplanted", "0.15", "Experience multipled by the experience required for the player's next level and the team ratio given for planting the bomb", 0, true, 0.0);
	g_hCVExpBombDefused = AutoExecConfig_CreateConVar("smrpg_exp_bombdefused", "0.30", "Experience multipled by the experience required for the player's next level and the team ratio given for defusing the bomb", 0, true, 0.0);
	g_hCVExpBombExploded = AutoExecConfig_CreateConVar("smrpg_exp_bombexploded", "0.20", "Experience multipled by the experience required for the player's next level and the team ratio given to the bomb planter when it explodes", 0, true, 0.0);
	g_hCVExpHostage = AutoExecConfig_CreateConVar("smrpg_exp_hostage", "0.10", "Experience multipled by the experience required for the player's next level and the team ratio for rescuing a hostage", 0, true, 0.0);
	g_hCVExpVIPEscaped = AutoExecConfig_CreateConVar("smrpg_exp_vipescaped", "0.35", "Experience multipled by the experience required for the player's next level and the team ratio given to the vip when the vip escapes", 0, true, 0.0);
	
	g_hCVExpDominating = AutoExecConfig_CreateConVar("smrpg_exp_dominating", "5.0", "Experience for dominating an enemy multiplied by the victim's level.", 0, true, 0.0);
	g_hCVExpRevenge = AutoExecConfig_CreateConVar("smrpg_exp_revenge", "8.0", "Experience for killing a dominating enemy in revenge multiplied by the attackers's level.", 0, true, 0.0);

	g_hCVExpDZPlace[0] = AutoExecConfig_CreateConVar("smrpg_exp_dz_place_1", "10000", "Experience for first place in a Danger Zone match.", 0, true, 0.0);
	g_hCVExpDZPlace[1] = AutoExecConfig_CreateConVar("smrpg_exp_dz_place_2", "7500", "Experience for second place in a Danger Zone match.", 0, true, 0.0);
	g_hCVExpDZPlace[2] = AutoExecConfig_CreateConVar("smrpg_exp_dz_place_3", "5000", "Experience for third place in a Danger Zone match.", 0, true, 0.0);
	
	g_hCVBotEarnExpObjective = AutoExecConfig_CreateConVar("smrpg_bot_exp_objectives", "1", "Should bots earn experience for completing objectives (bomb, hostage, ..)?", 0, true, 0.0, true, 1.0);
	
	g_hCVShowMVPLevel = AutoExecConfig_CreateConVar("smrpg_mvp_level", "1", "Show player level as MVP stars on the scoreboard?", 0, true, 0.0, true, 1.0);
	g_hCVEnableAntiKnifeleveling = AutoExecConfig_CreateConVar("smrpg_anti_knifelevel", "1", "Stop giving exp to players who knife each other too often in a time frame?", 0, true, 0.0, true, 1.0);

	g_hCVDisableXPDuringWarmup = AutoExecConfig_CreateConVar("smrpg_disable_experience_warmup", "0", "Stop players from getting any experience during the warmup period? (CS:GO only)", 0, true, 0.0, true, 1.0);
	
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

	UserMsg msgSurvivalStats = GetUserMessageId("SurvivalStats");
	// SurvivalStats only available in CS:GO and "Protobuf.ReadInt64" was added in SourceMod 1.10.
	if(msgSurvivalStats != INVALID_MESSAGE_ID && GetFeatureStatus(FeatureType_Native, "Protobuf.ReadInt64") == FeatureStatus_Available)
		HookUserMessage(msgSurvivalStats, UsrMsgHook_OnSurvivalStats);
}

public void OnAllPluginsLoaded()
{
	g_hCVExpKillMax = FindConVar("smrpg_exp_kill_max");
	g_hCVExpTeamwin = FindConVar("smrpg_exp_teamwin");
}

// Reset anti knifeleveling stuff
public void OnClientDisconnect(int client)
{
	g_bKnifeLeveled[client] = false;
	ClearHandle(g_hKnifeLevelCooldown[client]);
	g_iKnifeLevelDetections[client] = 0;
	
	for(int i=1;i<=MaxClients;i++)
	{
		g_iKnifeDamage[client][i][KL_Hits] = 0;
		g_iKnifeDamage[client][i][KL_LastAttack] = 0;
		g_iKnifeDamage[client][i][KL_FirstAttack] = 0;
		
		g_iKnifeDamage[i][client][KL_Hits] = 0;
		g_iKnifeDamage[i][client][KL_LastAttack] = 0;
		g_iKnifeDamage[i][client][KL_FirstAttack] = 0;
	}
}

public Action SMRPG_OnAddExperience(int client, const char[] reason, int &iExperience, int other)
{
	// Don't let the normal experience calculation hit. We're doing some cstrike specific stuff here.
	if(StrEqual(reason, ExperienceReason_PlayerHurt) || StrEqual(reason, ExperienceReason_PlayerKill) || StrEqual(reason, ExperienceReason_RoundEnd))
		return Plugin_Handled;

	// Disable any experience during warmup if smrpg_disable_experience_warmup is set.
	if(g_bIsCSGO && g_hCVDisableXPDuringWarmup.BoolValue && !StrEqual(reason, ExperienceReason_Admin) && GameRules_GetProp("m_bWarmupPeriod"))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action SMRPG_OnClientLevel(int client, int oldlevel, int newlevel)
{
	if(IsClientInGame(client))
		UpdateMVPLevel(client);
	
	return Plugin_Continue;
}

public void SMRPG_TranslateExperienceReason(int client, const char[] reason, int iExperience, int other, char[] buffer, int maxlen)
{
	// Just use the reason string directly as translation phrase.
	if(other > 0)
		Format(buffer, maxlen, "%T", reason, client, iExperience, other);
	else
		Format(buffer, maxlen, "%T", reason, client, iExperience);
}

public void Event_OnPlayerSpawn(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	UpdateMVPLevel(client);
}

public void Event_OnRoundMVP(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	UpdateMVPLevel(client);
}

public void Event_OnPlayerHurt(Event event, const char[] error, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	int iDmgHealth = event.GetInt("dmg_health");
	int iDmgArmor = event.GetInt("dmg_armor");
	char sWeapon[64];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	
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
	
	int iExp;
	int iTotalDmg = iDmgHealth+iDmgArmor;
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
			if(g_hCVEnableAntiKnifeleveling.BoolValue && !g_bKnifeLeveled[attacker])
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
		if(g_hCVEnableAntiKnifeleveling.BoolValue && g_bKnifeLeveled[attacker])
			return;

	}
	
	iExp = RoundToCeil(float(iTotalDmg) * SMRPG_GetWeaponExperience(sWeapon, WeaponExperience_Damage));
	
	if(StrContains(sWeapon, "knife") != -1)
		Debug_AddClientExperience(attacker, iExp, true, "cs_playerknife", victim);
	else
		Debug_AddClientExperience(attacker, iExp, true, "cs_playerhurt", victim);
}

public void Event_OnPlayerDeath(Event event, const char[] error, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int assister;
	
	if(attacker == 0 || victim == 0)
		return;
	
	if(g_bIsCSGO)
	{
		assister = GetClientOfUserId(event.GetInt("assister"));
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
		int iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * g_hCVExpKillAssist.FloatValue);
		Debug_AddClientExperience(assister, iExp, false, "cs_playerkillassist", victim);
	}
	
	// Ignore suicide
	if(attacker == victim)
		return;
	
	// Ignore teamattack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	char sWeapon[64];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	
	int iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * SMRPG_GetWeaponExperience(sWeapon, WeaponExperience_Kill) + SMRPG_GetWeaponExperience(sWeapon, WeaponExperience_Bonus));
	if(event.GetBool("headshot"))
		iExp += g_hCVExpHeadshot.IntValue;
	
	int iExpMax = g_hCVExpKillMax.IntValue;
	// Limit the possible experience to this.
	if(iExpMax > 0 && iExp > iExpMax)
		iExp = iExpMax;
	
	Debug_AddClientExperience(attacker, iExp, false, "cs_playerkill", victim);
	
	// Player started dominating this player?
	if(event.GetBool("dominated"))
	{
		iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * g_hCVExpDominating.FloatValue);
		Debug_AddClientExperience(attacker, iExp, false, "cs_dominating", victim);
	}
	
	// Player broke the domination and killed him in revenge?
	if(event.GetBool("revenge"))
	{
		iExp = RoundToCeil(SMRPG_GetClientLevel(victim) * g_hCVExpRevenge.FloatValue);
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
public void Event_OnRoundEnd(Event event, const char[] error, bool dontBroadcast)
{
	int iTeam = event.GetInt("winner");
	CSRoundEndReason iReason = view_as<CSRoundEndReason>(event.GetInt("reason"));
	
	// The reasons in CS:GO are shifted in the CSRoundEndReason enum..
	if (g_bIsCSGO)
		iReason--;
	
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
	
	float fTeamRatio;
	if(iTeam == 2)
		fTeamRatio = SMRPG_TeamRatio(3);
	else if(iTeam == 3)
		fTeamRatio = SMRPG_TeamRatio(2);
	else
		return;
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == iTeam)
			Debug_AddClientExperience(i, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(i))) * g_hCVExpTeamwin.FloatValue * fTeamRatio), false, "cs_winround");
	}
}

public void Event_OnBombPlanted(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	if(IsFakeClient(client) && !g_hCVBotEarnExpObjective.BoolValue)
		return;
	
	float fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * g_hCVExpBombPlanted.FloatValue * fTeamRatio), false, "cs_bombplanted");
}

public void Event_OnBombDefused(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	if(IsFakeClient(client) && !g_hCVBotEarnExpObjective.BoolValue)
		return;
	
	float fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * g_hCVExpBombDefused.FloatValue * fTeamRatio), false, "cs_bombdefused");
}

public void Event_OnBombExploded(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	if(IsFakeClient(client) && !g_hCVBotEarnExpObjective.BoolValue)
		return;
	
	float fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * g_hCVExpBombExploded.FloatValue * fTeamRatio), false, "cs_bombexploded");
}

public void Event_OnHostageRescued(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	if(IsFakeClient(client) && !g_hCVBotEarnExpObjective.BoolValue)
		return;
	
	float fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * g_hCVExpHostage.FloatValue * fTeamRatio), false, "cs_hostagerescued");
}

public void Event_OnVIPEscaped(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int iTeam = GetClientTeam(client);
	if(iTeam <= 1)
		return;
	
	if(IsFakeClient(client) && !g_hCVBotEarnExpObjective.BoolValue)
		return;
	
	float fTeamRatio = SMRPG_TeamRatio(iTeam == 2 ? 3 : 2);
	Debug_AddClientExperience(client, RoundToCeil(float(SMRPG_LevelToExperience(SMRPG_GetClientLevel(client))) * g_hCVExpVIPEscaped.FloatValue * fTeamRatio), false, "cs_vipescaped");
}

// CS:GO Danger Zone winners.
public Action UsrMsgHook_OnSurvivalStats(UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init)
{
#if SOURCEMOD_V_MINOR > 9
	if(!SMRPG_IsEnabled())
		return;

	int xuid[2];
	int userCount = msg.GetRepeatedFieldCount("users");
	for(int i = 0; i < userCount; i++)
	{
		Protobuf placement = msg.ReadRepeatedMessage("users", i);
		placement.ReadInt64("xuid", xuid);
		int client = GetClientByAccountID(xuid[0]);
		if(client == -1)
			continue;

		int place = placement.ReadInt("placement");
		if(place > 3)
			continue;

		// TODO: Dynamically scale based on RPG level of competitors?
		// Consider other players in their squad?
		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientUserId(client));
		hPack.WriteCell(place);
		hPack.Reset();

		// Give experience on the next frame to avoid problems with
		// sending new usermessages during a usermessage hook.
		RequestFrame(AddDangerZoneExperienceNextFrame, hPack);
	}
#endif
}

void AddDangerZoneExperienceNextFrame(DataPack hPack)
{
	hPack.Reset();
	int client = GetClientOfUserId(hPack.ReadCell());
	int place = hPack.ReadCell();
	delete hPack;

	if(!client)
		return;

	char sExperienceReason[32];
	Format(sExperienceReason, sizeof(sExperienceReason), "cs_dangerzone_place%d", place);
	Debug_AddClientExperience(client, g_hCVExpDZPlace[place - 1].IntValue, false, sExperienceReason);
}

public Action Timer_ResetKnifeLeveling(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	//PrintToServer("%N knifeleveling status was reset.", client);
	g_hKnifeLevelCooldown[client] = null;
	g_bKnifeLeveled[client] = false;
	return Plugin_Stop;
}

void UpdateMVPLevel(int client)
{
	if(!g_hCVShowMVPLevel.BoolValue)
		return;
	
	if (IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	CS_SetMVPCount(client, SMRPG_GetClientLevel(client));
}

stock int GetClientByAccountID(int iTargetAccountID)
{
	for(int i=1;i<=MaxClients;i++)
	{
		if (!IsClientConnected(i))
			continue;

		int iAccountID = GetSteamAccountID(i);
		if(!iAccountID)
			continue;

		if(iTargetAccountID == iAccountID)
			return i;
	}
	return -1;
}

// This stuff is leftover from balancing the experience on a deathmatch server.
// Maybe someone finds it useful too when playing with the experience settings, so i'll leave it here.
void Debug_AddClientExperience(int client, int exp, bool bHideNotice, const char[] sReason, int victim=-1)
{
#if !defined _DEBUG
	// This is all that's really needed
	SMRPG_AddClientExperience(client, exp, sReason, bHideNotice, victim, SMRPG_TranslateExperienceReason);
#else
	int iOldLevel = SMRPG_GetClientLevel(client);
	int iOldExperience = SMRPG_GetClientExperience(client);
	int iOldNeeded = SMRPG_LevelToExperience(iOldLevel);
	
	int iOriginalExperience = exp;
	bool bAdded = SMRPG_AddClientExperience(client, exp, sReason, bHideNotice, victim, SMRPG_TranslateExperienceReason);
	
	int iNewLevel = SMRPG_GetClientLevel(client);
	char sAttackerAuth[40], sVictimString[256], sLevelInc[32], sChangedExperience[32];
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
stock void DebugLog(const char[] format, any ...)
{
	static char sLog[8192] = "";
	static File hFile = null;
	static int iOpenTime = 0;
	char sBuffer[256];
	SetGlobalTransTarget(LANG_SERVER);
	VFormat(sBuffer, sizeof(sBuffer), format, 2);
	
	char sOldDate[9], sCurrentDate[9];
	FormatTime(sOldDate, sizeof(sOldDate), "%Y%m%d", iOpenTime);
	FormatTime(sCurrentDate, sizeof(sCurrentDate), "%Y%m%d");
	
	if(hFile == null || !StrEqual(sOldDate, sCurrentDate))
	{
		char sPath[PLATFORM_MAX_PATH];
		FormatTime(sPath, sizeof(sPath), "%Y_%m_%d");
		BuildPath(Path_SM, sPath, sizeof(sPath), "data/smrpg_experience_%s.log", sPath);
		
		// Basic log rotation
		if(!StrEqual(sOldDate, sCurrentDate) && hFile != null)
			delete hFile;
		
		hFile = OpenFile(sPath, "a");
		iOpenTime = GetTime();
	}

	// Flush the buffer.
	if((strlen(sLog) + strlen(sBuffer) + 24) >= sizeof(sLog)-1)
	{
		if(hFile != null)
			hFile.WriteString(sLog, false);
		sLog[0] = 0;
	}

	char sDate[32];
	FormatTime(sDate, sizeof(sDate), "%m/%d/%Y - %H:%M:%S: ");
	StrCat(sLog, sizeof(sLog), sDate);
	StrCat(sLog, sizeof(sLog), sBuffer);
	StrCat(sLog, sizeof(sLog), "\n");
}
#endif