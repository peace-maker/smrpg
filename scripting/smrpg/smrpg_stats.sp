#pragma semicolon 1
#include <sourcemod>
#include <smlib>

// Allow to refetch the rank every 20 seconds.
#define RANK_CACHE_UPDATE_INTERVAL 20

int g_iCachedRank[MAXPLAYERS+1] = {-1,...};
int g_iNextCacheUpdate[MAXPLAYERS+1];
int g_iCachedRankCount = 0;
int g_iNextCacheCountUpdate;

enum SessionStats {
	SS_JoinTime,
	SS_JoinLevel,
	SS_JoinExperience,
	SS_JoinCredits,
	SS_JoinRank,
	bool:SS_WantsAutoUpdate,
	bool:SS_WantsMenuOpen,
	bool:SS_OKToClose,
	ArrayList:SS_LastExperience
};

int g_iPlayerSessionStartStats[MAXPLAYERS+1][SessionStats];
bool g_bBackToStatsMenu[MAXPLAYERS+1];

Handle g_hfwdOnAddExperience;
Handle g_hfwdOnAddExperiencePost;

// AFK Handling
enum AFKInfo {
	Float:AFK_lastPosition[3],
	AFK_startTime,
	AFK_spawnTime,
	AFK_deathTime
}
int g_PlayerAFKInfo[MAXPLAYERS+1][AFKInfo];
bool g_bPlayerSpawnProtected[MAXPLAYERS+1];

// Individual weapon experience settings
StringMap g_hWeaponExperience;

enum WeaponExperienceContainer {
	Float:WXP_Damage,
	Float:WXP_Kill,
	Float:WXP_Bonus
};

void RegisterStatsNatives()
{
	// native bool SMRPG_AddClientExperience(int client, int exp, const char[] reason, bool bHideNotice, int other=-1, SMRPG_ExpTranslationCb callback=INVALID_FUNCTION);
	CreateNative("SMRPG_AddClientExperience", Native_AddClientExperience);
	// native int SMRPG_LevelToExperience(int iLevel);
	CreateNative("SMRPG_LevelToExperience", Native_LevelToExperience);
	// native int SMRPG_GetClientRank(int client);
	CreateNative("SMRPG_GetClientRank", Native_GetClientRank);
	// native int SMRPG_GetRankCount();
	CreateNative("SMRPG_GetRankCount", Native_GetRankCount);
	
	// native void SMRPG_GetTop10Players(SQLQueryCallback callback, any data=0);
	CreateNative("SMRPG_GetTop10Players", Native_GetTop10Players);
	
	// native bool SMRPG_IsClientAFK(int client);
	CreateNative("SMRPG_IsClientAFK", Native_IsClientAFK);
	// native bool SMRPG_IsClientSpawnProtected(int client);
	CreateNative("SMRPG_IsClientSpawnProtected", Native_IsClientSpawnProtected);
	
	// native float SMRPG_GetWeaponExperience(const char[] sWeapon, WeaponExperienceType type);
	CreateNative("SMRPG_GetWeaponExperience", Native_GetWeaponExperience);
}

void RegisterStatsForwards()
{
	// forward Action SMRPG_OnAddExperience(int client, const char[] reason, int &iExperience, int other);
	g_hfwdOnAddExperience = CreateGlobalForward("SMRPG_OnAddExperience", ET_Hook, Param_Cell, Param_String, Param_CellByRef, Param_Cell);
	// forward void SMRPG_OnAddExperiencePost(int client, const char[] reason, int iExperience, int other);
	g_hfwdOnAddExperiencePost = CreateGlobalForward("SMRPG_OnAddExperiencePost", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_Cell);
}

/* Calculate the experience needed for this level */
int Stats_LvlToExp(int iLevel)
{
	int iExp;
	
	if(iLevel <= 1)
		iExp = g_hCVExpStart.IntValue;
	else
		iExp = iLevel * g_hCVExpInc.IntValue + g_hCVExpStart.IntValue;
	
	return iExp > g_hCVExpMax.IntValue ? g_hCVExpMax.IntValue : iExp;
}

/* Calculate how many levels to increase by current level and experience */
int Stats_CalcLvlInc(int iLevel, int iExp)
{
	int iLevelIncrease;
	
	int iExpRequired = Stats_LvlToExp(iLevel);
	while(iExp >= iExpRequired)
	{
		iLevelIncrease++;
		iExp -= iExpRequired;
		iExpRequired = Stats_LvlToExp(iLevel+iLevelIncrease);
	}
	
	return iLevelIncrease;
}

void Stats_PlayerNewLevel(int client, int iLevelIncrease)
{
	int iMaxLevel;
	bool bMaxLevelReset;
	if(IsFakeClient(client))
	{
		iMaxLevel = g_hCVBotMaxlevel.IntValue;
		bMaxLevelReset = g_hCVBotMaxlevelReset.BoolValue;
	}
	else
	{
		iMaxLevel = g_hCVPlayerMaxlevel.IntValue;
		bMaxLevelReset = g_hCVPlayerMaxlevelReset.BoolValue;
	}
	
	// Check if the player reached the maxlevel
	if(iMaxLevel > 0)
	{
		int iNewLevel = GetClientLevel(client) + iLevelIncrease;
		// Player surpassed the maxlevel?
		if(iNewLevel > iMaxLevel)
		{
			// Reset him immediately if we want to.
			if(bMaxLevelReset)
			{
				DebugMsg("Player %N has surpassed the maximum level of %d, resetting his stats", client, iMaxLevel);
				Client_PrintToChatAll(false, "%t", "Player reached maxlevel", client, iMaxLevel);
				LogMessage("%L surpassed the maximum level of %d, resetting his stats.", client, iMaxLevel);
				ResetStats(client);
				return;
			}
			else
			{
				// Only increase so much until we reach the maxlevel.
				iLevelIncrease = iMaxLevel - GetClientLevel(client);
			}
		}
	}
	
	// Don't do anything, if we don't really have a new level.
	if(iLevelIncrease <= 0)
		return;
	
	// Make sure to keep the experience he gained in addition to the needed exp for the levels.
	int iExperience = GetClientExperience(client);
	for(int i=0;i<iLevelIncrease;i++)
	{
		iExperience -= Stats_LvlToExp(GetClientLevel(client)+i);
	}
	
	// Some admin gave him a level even though he didn't have enough exp? well well..
	if(iExperience < 0)
		iExperience = 0;
	
	SetClientExperience(client, iExperience);
	
	SetClientLevel(client, GetClientLevel(client)+iLevelIncrease);
	SetClientCredits(client, GetClientCredits(client) + iLevelIncrease * g_hCVCreditsInc.IntValue);
	
	DebugMsg("%N is now level %d (%d level increase(s))", client, GetClientLevel(client), iLevelIncrease);
	
	// Player wants to get prompted with the rpgmenu automatically when he levels up?
	// Make sure he isn't viewing another menu at the moment.
	if(ShowMenuOnLevelUp(client) && GetClientMenu(client) == MenuSource_None)
	{
		DisplayUpgradesMenu(client);
	}
	
	if(FadeScreenOnLevelUp(client))
	{
		char sColor[16], sBuffers[4][4];
		// Keep the default color if there is invalid input in the convar.
		int iColor[] = {255, 215, 0, 40};
		// Parse the "r g b a" convar string of the screen fading color.
		g_hCVFadeOnLevelColor.GetString(sColor, sizeof(sColor));
		int iNum = ExplodeString(sColor, " ", sBuffers, 4, 4);
		for(int i=0;i<iNum;i++)
			iColor[i] = StringToInt(sBuffers[i]);
		Client_ScreenFade(client, 255, FFADE_OUT|FFADE_PURGE, 255, iColor[0], iColor[1], iColor[2], iColor[3]);
	}
	
	if(g_hCVAnnounceNewLvl.BoolValue)
		Client_PrintToChatAll(false, "%t", "Client level changed", client, GetClientLevel(client));
	
	if(!IsFakeClient(client))
	{
		EmitSoundToClient(client, SMRPG_GC_GetKeyValue("SoundLevelup"));
		if((GetClientLevel(client) - iLevelIncrease) <= 1)
		{
			/* for newbies */
			Client_PrintToChat(client, false, "%t", "Newbie instructions new level");
			Client_PrintToChat(client, false, "%t", "Newbie instructions use rpgmenu");
		}
		else
		{
			Client_PrintToChat(client, false, "%t", "You have new credits", GetClientCredits(client));
		}
	}
	else if(g_hCVBotEnable.BoolValue)
	{
		BotPickUpgrade(client);
	}
}

bool Stats_AddExperience(int client, int &iExperience, const char[] sReason, bool bHideNotice, int other, bool bIgnoreChecks=false)
{
	// Nothing to add?
	if(iExperience <= 0)
		return false;
	
	IF_IGNORE_BOTS(client)
		return false;
	
	// Admin commands shouldn't worry about fairness.
	if (!bIgnoreChecks)
	{
		bool bBotEnable = g_hCVBotEnable.BoolValue;
		if(g_hCVNeedEnemies.BoolValue)
		{
			// No enemies in the opposite team?
			if(!Team_HaveAllPlayers(bBotEnable))
				return false;
		}
		
		// All players in the opposite team are AFK?
		if(g_hCVEnemiesNotAFK.BoolValue)
		{
			int iMyTeam = GetClientTeam(client);
			if(iMyTeam > 1)
			{
				bool bAllAFK;
				int iTeam;
				for(int i=1;i<=MaxClients;i++)
				{
					if(IsClientInGame(i))
					{
						if(IsFakeClient(i) && !bBotEnable)
							continue;
						
						iTeam = GetClientTeam(i);
						// This is an enemy?
						if(iTeam > 1 && iTeam != iMyTeam)
						{
							// This enemy isn't afk? Add experience then.
							if(!IsClientAFK(i))
							{
								bAllAFK = false;
								break;
							}
							else
							{
								bAllAFK = true;
							}
						}
					}
				}
				
				// Don't count any experience, if all players in the opposite team are AFK.
				if(bAllAFK)
					return false;
			}
		}
	}
	
	// Don't give the players any more exp when they already reached the maxlevel.
	int iMaxlevel;
	if(IsFakeClient(client))
		iMaxlevel = g_hCVBotMaxlevel.IntValue;
	else
		iMaxlevel = g_hCVPlayerMaxlevel.IntValue;
	
	if(iMaxlevel > 0 && GetClientLevel(client) >= iMaxlevel)
		return false;
	
	// Handle experience with bots
	if(other > 0 && other <= MaxClients && IsClientInGame(other))
	{
		bool bClientBot = IsFakeClient(client);
		bool bOtherBot = IsFakeClient(other);
		if(bClientBot && bOtherBot)
		{
			if(!g_hCVBotKillBot.BoolValue)
				return false;
		}
		else if(bClientBot && !bOtherBot)
		{
			if(!g_hCVBotKillPlayer.BoolValue)
				return false;
		}
		else if(!bClientBot && bOtherBot)
		{
			if(!g_hCVPlayerKillBot.BoolValue)
				return false;
		}
	}
	
	// See if some other plugin doesn't like this.
	if(Stats_CallOnExperienceForward(client, sReason, iExperience, other) > Plugin_Changed)
		return false;
	
	SetClientExperience(client, GetClientExperience(client) + iExperience);
	
	int iExpRequired = Stats_LvlToExp(GetClientLevel(client));
	
	if(GetClientExperience(client) >= iExpRequired)
		Stats_PlayerNewLevel(client, Stats_CalcLvlInc(GetClientLevel(client), GetClientExperience(client)));
	
	Stats_CallOnExperiencePostForward(client, sReason, iExperience, other);
	
	if(!bHideNotice && g_hCVExpNotice.BoolValue)
		PrintHintText(client, "%t", "Experience Gained Hintbox", iExperience, GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)));
	
	return true;
}

void Stats_PlayerDamage(int attacker, int victim, float fDamage, const char[] sWeapon)
{
	if(!g_hCVEnable.BoolValue)
		return;
	
	// Don't give the attacker any exp when his victim was afk.
	if(IsClientAFK(victim))
		return;
	
	// Don't give the attacker any exp when his victim just spawned and didn't do anything at all yet.
	if(IsClientSpawnProtected(victim))
		return;
	
	// Ignore teamattack if not FFA
	if(!g_hCVFFA.BoolValue && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	int iExp = RoundToCeil(fDamage * GetWeaponExperience(sWeapon, WeaponExperience_Damage));
	
	SMRPG_AddClientExperience(attacker, iExp, ExperienceReason_PlayerHurt, true, victim);
}

void Stats_PlayerKill(int attacker, int victim, const char[] sWeapon)
{
	if(!g_hCVEnable.BoolValue)
		return;
	
	// Don't give the attacker any exp when his victim was afk.
	if(IsClientAFK(victim))
		return;
	
	// Don't give the attacker any exp when his victim just spawned and didn't do anything at all yet.
	if(IsClientSpawnProtected(victim))
		return;
	
	// Ignore teamattack if not FFA
	if(!g_hCVFFA.BoolValue && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	int iExp = RoundToCeil(GetClientLevel(victim) * GetWeaponExperience(sWeapon, WeaponExperience_Kill) + GetWeaponExperience(sWeapon, WeaponExperience_Bonus));
	int iExpMax = g_hCVExpKillMax.IntValue;
	// Limit the possible experience to this.
	if(iExpMax > 0 && iExp > iExpMax)
		iExp = iExpMax;
	
	SMRPG_AddClientExperience(attacker, iExp, ExperienceReason_PlayerKill, false, victim);
}

void Stats_WinningTeam(int iTeam)
{
	if(!g_hCVEnable.BoolValue)
		return;
	
	float fTeamRatio;
	if(iTeam == 2)
		fTeamRatio = SMRPG_TeamRatio(3);
	else if(iTeam == 3)
		fTeamRatio = SMRPG_TeamRatio(2);
	else
		return;
	
	int iExperience;
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == iTeam)
		{
			iExperience = RoundToCeil(float(Stats_LvlToExp(GetClientLevel(i))) * g_hCVExpTeamwin.FloatValue * fTeamRatio);
			SMRPG_AddClientExperience(i, iExperience, ExperienceReason_RoundEnd, false, -1);
		}
	}
}

// forward Action SMRPG_OnAddExperience(int client, const char[] reason, int &iExperience, int other);
Action Stats_CallOnExperienceForward(int client, const char[] sReason, int &iExperience, int other)
{
	Action result;
	Call_StartForward(g_hfwdOnAddExperience);
	Call_PushCell(client);
	Call_PushString(sReason);
	Call_PushCellRef(iExperience);
	Call_PushCell(other);
	Call_Finish(result);
	return result;
}

// forward void SMRPG_OnAddExperiencePost(int client, const char[] reason, int iExperience, int other);
void Stats_CallOnExperiencePostForward(int client, const char[] sReason, int iExperience, int other)
{
	Call_StartForward(g_hfwdOnAddExperiencePost);
	Call_PushCell(client);
	Call_PushString(sReason);
	Call_PushCell(iExperience);
	Call_PushCell(other);
	Call_Finish();
}

// AFK Handling
void StartAFKChecker()
{
	CreateTimer(0.5, Timer_CheckAFKPlayers, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action Timer_CheckAFKPlayers(Handle timer)
{
	float fOrigin[3], fLastPosition[3];
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) > 1)
		{
			GetClientAbsOrigin(i, fOrigin);
			
			// See if the player just spawned..
			if(g_PlayerAFKInfo[i][AFK_spawnTime] > 0)
			{
				int iDifference = GetTime() - g_PlayerAFKInfo[i][AFK_spawnTime];
				// The player spawned 2 seconds ago. He's now ready to be checked for being afk again.
				if(iDifference > 2)
				{
					g_PlayerAFKInfo[i][AFK_spawnTime] = 0;
					if(g_PlayerAFKInfo[i][AFK_startTime] > 0)
						g_PlayerAFKInfo[i][AFK_startTime] += iDifference;
					Array_Copy(fOrigin, g_PlayerAFKInfo[i][AFK_lastPosition], 3);
				}
				continue;
			}
			
			// See if we need to subtract some time while he was dead.
			if(g_PlayerAFKInfo[i][AFK_deathTime] > 0)
			{
				if(g_PlayerAFKInfo[i][AFK_startTime] > 0)
					g_PlayerAFKInfo[i][AFK_startTime] += GetTime() - g_PlayerAFKInfo[i][AFK_deathTime];
				g_PlayerAFKInfo[i][AFK_deathTime] = 0;
			}
			
			Array_Copy(g_PlayerAFKInfo[i][AFK_lastPosition], fLastPosition, 3);
			if(Math_VectorsEqual(fOrigin, fLastPosition, 1.0))
			{
				if(g_PlayerAFKInfo[i][AFK_startTime] == 0)
					g_PlayerAFKInfo[i][AFK_startTime] = GetTime();
			}
			else
			{
				g_PlayerAFKInfo[i][AFK_startTime] = 0;
			}
			
			Array_Copy(fOrigin, g_PlayerAFKInfo[i][AFK_lastPosition], 3);
		}
	}
	
	return Plugin_Continue;
}

bool IsClientAFK(int client)
{
	if(g_PlayerAFKInfo[client][AFK_startTime] == 0)
		return false;
	
	int iAFKTime = g_hCVAFKTime.IntValue;
	if(iAFKTime <= 0)
		return false;
	
	if((GetTime() - g_PlayerAFKInfo[client][AFK_startTime]) > iAFKTime)
		return true;
	return false;
}

void ResetAFKPlayer(int client)
{
	g_PlayerAFKInfo[client][AFK_startTime] = 0;
	g_PlayerAFKInfo[client][AFK_spawnTime] = 0;
	g_PlayerAFKInfo[client][AFK_deathTime] = 0;
	Array_Copy(g_PlayerAFKInfo[client][AFK_lastPosition], view_as<float>({0.0,0.0,0.0}), 3);
}

// Spawn Protection handling
bool IsClientSpawnProtected(int client)
{
	if(!g_hCVSpawnProtect.BoolValue)
		return false;
	return g_bPlayerSpawnProtected[client];
}

void ResetSpawnProtection(int client)
{
	g_bPlayerSpawnProtected[client] = false;
}

/**
 * Native Callbacks
 */
// native bool SMRPG_AddClientExperience(int client, int &exp, const char[] reason, bool bHideNotice, int other=-1, SMRPG_ExpTranslationCb callback=INVALID_FUNCTION);
public int Native_AddClientExperience(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	int iExperience = GetNativeCellRef(2);
	int iLen;
	GetNativeStringLength(3, iLen);
	char[] sReason = new char[iLen+1];
	GetNativeString(3, sReason, iLen+1);
	
	bool bHideNotice = view_as<bool>(GetNativeCell(4));
	int other = GetNativeCell(5);
	Function translationCallback = GetNativeFunction(6);
	
	int iOriginalExperience = iExperience;
	// TODO: Expose bIgnoreChecks parameter.
	bool bAdded = Stats_AddExperience(client, iExperience, sReason, bHideNotice, other);
	if(iOriginalExperience != iExperience)
		SetNativeCellRef(2, iExperience);
	
	if(bAdded && !IsFakeClient(client))
	{
		char sTranslatedReason[256];
		strcopy(sTranslatedReason, sizeof(sTranslatedReason), sReason);
		if(translationCallback != INVALID_FUNCTION)
		{
			// functag SMRPG_ExpTranslationCb(client, const char[] reason, iExperience, other, char[] buffer, maxlen);
			Call_StartFunction(plugin, translationCallback);
			Call_PushCell(client);
			Call_PushString(sReason);
			Call_PushCell(iExperience);
			Call_PushCell(other);
			Call_PushStringEx(sTranslatedReason, sizeof(sTranslatedReason), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
			Call_PushCell(sizeof(sTranslatedReason));
			Call_Finish();
		}
		
		// String wasn't changed or no callback set?
		if(StrEqual(sTranslatedReason, sReason))
		{
			if(other > 0 && other <= MaxClients)
				Format(sTranslatedReason, sizeof(sTranslatedReason), "%T", "Experience Reason Other Client", client, iExperience, sReason, other);
			else
				Format(sTranslatedReason, sizeof(sTranslatedReason), "%T", "Experience Reason General", client, iExperience, sReason);
		}
		
		InsertSessionExperienceString(client, sTranslatedReason);
	}
	
	return bAdded;
}

public int Native_LevelToExperience(Handle plugin, int numParams)
{
	int iLevel = GetNativeCell(1);
	return Stats_LvlToExp(iLevel);
}

public int Native_GetClientRank(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return GetClientRank(client);
}

public int Native_GetRankCount(Handle plugin, int numParams)
{
	return GetRankCount();
}

public int Native_IsClientAFK(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return IsClientAFK(client);
}

public int Native_IsClientSpawnProtected(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	return IsClientSpawnProtected(client);
}

public int Native_GetTop10Players(Handle plugin, int numParams)
{
	Function callback = GetNativeFunction(1);
	int data = GetNativeCell(2);
	
	DataPack hData = new DataPack();
	hData.WriteCell(view_as<int>(plugin));
	hData.WriteFunction(callback);
	hData.WriteCell(data);
	
	char sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT name, level, experience, credits FROM %s ORDER BY level DESC, experience DESC LIMIT 10", TBL_PLAYERS);
	g_hDatabase.Query(SQL_GetTop10Native, sQuery, hData);
}

public void SQL_GetTop10Native(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack dp = view_as<DataPack>(data);
	dp.Reset();
	Handle hPlugin = view_as<Handle>(dp.ReadCell());
	Function callback = dp.ReadFunction();
	int extraData = dp.ReadCell();
	delete dp;
	
	// Don't care if the calling plugin is gone.
	if(!IsValidPlugin(hPlugin))
		return;
	
	Call_StartFunction(hPlugin, callback);
	Call_PushCell(INVALID_HANDLE);
	Call_PushCell(results);
	Call_PushString(error);
	Call_PushCell(extraData);
	Call_Finish();
}

// native float SMRPG_GetWeaponExperience(const char[] sWeapon, WeaponExperienceType type);
public int Native_GetWeaponExperience(Handle plugin, int numParams)
{
	char sWeapon[64];
	GetNativeString(1, sWeapon, sizeof(sWeapon));
	WeaponExperienceType type = view_as<WeaponExperienceType>(GetNativeCell(2));
	
	return view_as<int>(GetWeaponExperience(sWeapon, type));
}

// rpgsession handling
void InitPlayerSessionStartStats(int client)
{
	g_iPlayerSessionStartStats[client][SS_JoinTime] = GetTime();
	g_iPlayerSessionStartStats[client][SS_JoinLevel] = GetClientLevel(client);
	g_iPlayerSessionStartStats[client][SS_JoinExperience] = GetClientExperience(client);
	g_iPlayerSessionStartStats[client][SS_JoinCredits] = GetClientCredits(client);
	g_iPlayerSessionStartStats[client][SS_JoinRank] = -1;
	g_iPlayerSessionStartStats[client][SS_WantsAutoUpdate] = false;
	g_iPlayerSessionStartStats[client][SS_WantsMenuOpen] = false;
	g_iPlayerSessionStartStats[client][SS_OKToClose] = false;
	
	ArrayList hLastExperience = new ArrayList(ByteCountToCells(256));
	hLastExperience.Resize(g_hCVLastExperienceCount.IntValue);
	hLastExperience.SetString(0, "");
	g_iPlayerSessionStartStats[client][SS_LastExperience] = hLastExperience;
}

void ResetPlayerSessionStats(int client)
{
	g_iPlayerSessionStartStats[client][SS_JoinTime] = 0;
	g_iPlayerSessionStartStats[client][SS_JoinLevel] = 0;
	g_iPlayerSessionStartStats[client][SS_JoinExperience] = 0;
	g_iPlayerSessionStartStats[client][SS_JoinCredits] = 0;
	g_iPlayerSessionStartStats[client][SS_JoinRank] = -1;
	g_iPlayerSessionStartStats[client][SS_WantsAutoUpdate] = false;
	g_iPlayerSessionStartStats[client][SS_WantsMenuOpen] = false;
	g_iPlayerSessionStartStats[client][SS_OKToClose] = false;
	ClearHandle(g_iPlayerSessionStartStats[client][SS_LastExperience]);
}

// Use our own forward to initialize the session info :)
public void SMRPG_OnClientLoaded(int client)
{
	// Only set it once and leave it that way until he really disconnects.
	if(g_iPlayerSessionStartStats[client][SS_JoinTime] == 0)
		InitPlayerSessionStartStats(client);
}

void InsertSessionExperienceString(int client, const char[] sExperience)
{
	ArrayList hLastExperience = g_iPlayerSessionStartStats[client][SS_LastExperience];
	// Not loaded yet..
	if(hLastExperience == null)
		return;
	
	// Insert the string at the start of the array!
	hLastExperience.ShiftUp(0);
	hLastExperience.SetString(0, sExperience);
}

public void ConVar_LastExperienceCountChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// Apply the new size immediately.
	for(int i=1;i<=MaxClients;i++)
	{
		if(g_iPlayerSessionStartStats[i][SS_JoinTime] > 0)
			g_iPlayerSessionStartStats[i][SS_LastExperience].Resize(convar.IntValue);
	}
}

void StartSessionMenuUpdater()
{
	CreateTimer(1.0, Timer_UpdateSessionMenus, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action Timer_UpdateSessionMenus(Handle timer)
{
	for(int i=1;i<=MaxClients;i++)
	{
		// Refresh the contents of the menu here.
		if(IsClientInGame(i) && !IsFakeClient(i) && g_iPlayerSessionStartStats[i][SS_WantsMenuOpen] && g_iPlayerSessionStartStats[i][SS_WantsAutoUpdate])
			DisplaySessionStatsMenu(i);
	}
	
	return Plugin_Continue;
}

void DisplaySessionStatsMenu(int client)
{
	Panel hPanel = new Panel();
	
	char sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "%T", "Stats", client);
	hPanel.DrawItem(sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "  %T", "Level", client, GetClientLevel(client));
	hPanel.DrawText(sBuffer);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Experience short", client, GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)));
	hPanel.DrawText(sBuffer);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Credits", client, GetClientCredits(client));
	hPanel.DrawText(sBuffer);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Rank", client, GetClientRank(client), GetRankCount());
	hPanel.DrawText(sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Session", client);
	hPanel.DrawItem(sBuffer);
	
	SecondsToString(sBuffer, sizeof(sBuffer), GetTime()-g_iPlayerSessionStartStats[client][SS_JoinTime], false);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Playtime", client, sBuffer);
	hPanel.DrawText(sBuffer);
	
	int iChangedLevels = GetClientLevel(client) - g_iPlayerSessionStartStats[client][SS_JoinLevel];
	Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed level", client, iChangedLevels>0?"+":"", iChangedLevels);
	hPanel.DrawText(sBuffer);
	
	// Need to calculate the total earned experience.
	int iEarnedExperience = GetClientExperience(client) - g_iPlayerSessionStartStats[client][SS_JoinExperience];
	for(int i=0;i<iChangedLevels;i++)
	{
		iEarnedExperience += Stats_LvlToExp(g_iPlayerSessionStartStats[client][SS_JoinLevel]+i);
	}
	
	Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed experience", client, iEarnedExperience>0?"+":"", iEarnedExperience);
	hPanel.DrawText(sBuffer);
	
	int iBuffer = GetClientCredits(client) - g_iPlayerSessionStartStats[client][SS_JoinCredits];
	Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed credits", client, iBuffer>0?"+":"", iBuffer);
	hPanel.DrawText(sBuffer);
	
	if(g_iPlayerSessionStartStats[client][SS_JoinRank] != -1)
	{
		iBuffer = g_iPlayerSessionStartStats[client][SS_JoinRank] - GetClientRank(client);
		Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed rank", client, iBuffer>0?"+":"", iBuffer);
		hPanel.DrawText(sBuffer);
	}
	
	hPanel.DrawItem("", ITEMDRAW_SPACER);
	
	Format(sBuffer, sizeof(sBuffer), "%T: %T", "Auto refresh panel", client, (g_iPlayerSessionStartStats[client][SS_WantsAutoUpdate]?"Yes":"No"), client);
	hPanel.DrawItem(sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Last Experience", client);
	hPanel.DrawItem(sBuffer);
	
	// The old menu is closed when we open the new one.
	// The logic here is like this:
	// We want to stop redisplaying the session menu, if the menu was closed gracefully or was interrupted by a different menu.
	// If the old menu is currently displaying (callback was not called yet) we don't want it to stay closed when we display it again.
	// So we set OKToClose to true, so it doesn't set WantsMenuOpen to false as if the menu was closed by an interrupting menu.
	// That way the menu stays open and is refreshed every second while staying closed if the player closes it or some other menu is displayed over it.
	if(g_iPlayerSessionStartStats[client][SS_WantsMenuOpen])
		g_iPlayerSessionStartStats[client][SS_OKToClose] = true;
	g_iPlayerSessionStartStats[client][SS_WantsMenuOpen] = true;
	
	hPanel.Send(client, Panel_HandleSessionMenu, MENU_TIME_FOREVER);
	delete hPanel;
}

public int Panel_HandleSessionMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		g_iPlayerSessionStartStats[param1][SS_WantsMenuOpen] = false;
		g_iPlayerSessionStartStats[param1][SS_OKToClose] = false;
		
		// Toggle the auto update
		if(param2 == 4)
		{
			g_iPlayerSessionStartStats[param1][SS_WantsAutoUpdate] = !g_iPlayerSessionStartStats[param1][SS_WantsAutoUpdate];
			DisplaySessionStatsMenu(param1);
			return;
		}
		else if(param2 == 5)
		{
			DisplaySessionLastExperienceMenu(param1, false);
		}
	}
	else if(action == MenuAction_Cancel)
	{
		
		if(!g_iPlayerSessionStartStats[param1][SS_OKToClose])
			g_iPlayerSessionStartStats[param1][SS_WantsMenuOpen] = false;
		g_iPlayerSessionStartStats[param1][SS_OKToClose] = false;
	}
}

void DisplaySessionLastExperienceMenu(int client, bool bBackToStatsMenu)
{
	ArrayList hLastExperience = g_iPlayerSessionStartStats[client][SS_LastExperience];
	// Player not loaded yet.
	if(hLastExperience == null)
		return;

	// Remember what the back button in the menu should do.
	g_bBackToStatsMenu[client] = bBackToStatsMenu;
	
	Menu hMenu = new Menu(Menu_HandleLastExperience);
	hMenu.SetTitle("%t: %N", "Last Experience", client);
	hMenu.ExitBackButton = true;
	
	int iSize = hLastExperience.Length;
	char sBuffer[256];
	for(int i=0;i<iSize;i++)
	{
		if(hLastExperience.GetString(i, sBuffer, sizeof(sBuffer)) <= 0)
			break;
		
		hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	}
	
	if(GetMenuItemCount(hMenu) == 0)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Nothing to display", client);
		hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	}
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleLastExperience(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		if(g_bBackToStatsMenu[param1])
			DisplayStatsMenu(param1);
		else
			DisplaySessionStatsMenu(param1);
	}
}

/*	//////////////////////////////////////
	CRPG_RankManager
	////////////////////////////////////// */

void UpdateClientRank(int client)
{
	if(!g_hDatabase)
		return;
	
	char sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM %s WHERE level > %d OR (level = %d AND experience > %d)", TBL_PLAYERS, GetClientLevel(client), GetClientLevel(client), GetClientExperience(client));
	g_hDatabase.Query(SQL_GetClientRank, sQuery, GetClientUserId(client));
	g_iNextCacheUpdate[client] = GetTime() + RANK_CACHE_UPDATE_INTERVAL;
}

int GetClientRank(int client)
{
	if(IsFakeClient(client))
		return -1;
	
	// Only update the cache, if we actually used it for a while.
	if(g_iNextCacheUpdate[client] < GetTime())
		UpdateClientRank(client);
	return g_iCachedRank[client];
}

void ClearClientRankCache(int client)
{
	g_iCachedRank[client] = -1;
	g_iNextCacheUpdate[client] = 0;
}

public void SQL_GetClientRank(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(results == null)
	{
		LogError("Unable to get player rank (%s)", error);
		return;
	}
	
	if(!results.FetchRow())
		return;
	
	g_iCachedRank[client] = results.FetchInt(0) + 1; // +1 since the query returns the count, not the rank
	
	// Save the first time we fetch the rank for him.
	if(g_iPlayerSessionStartStats[client][SS_JoinRank] == -1)
		g_iPlayerSessionStartStats[client][SS_JoinRank] = g_iCachedRank[client];
}

void UpdateRankCount()
{
	if(!g_hDatabase)
		return;
	
	char sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM %s", TBL_PLAYERS);
	g_hDatabase.Query(SQL_GetRankCount, sQuery);
	g_iNextCacheCountUpdate = GetTime() + RANK_CACHE_UPDATE_INTERVAL;
}

int GetRankCount()
{
	// Only update the cache, if we actually used it for a while.
	if(g_iNextCacheCountUpdate < GetTime())
		UpdateRankCount();
	
	if(g_iCachedRankCount > 0)
		return g_iCachedRankCount;
	
	return 0;
}

public void SQL_GetRankCount(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Unable to get player rank count (%s)", error);
		return;
	}
	
	if(!results.FetchRow())
		return;
	
	g_iCachedRankCount = results.FetchInt(0);
	
	int info[PlayerInfo];
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			GetClientRPGInfo(i, info);
			if(info[PLR_dbId] < 0)
				g_iCachedRankCount++; /* accounts for players not saved in the db */
		}
	}
}

void PrintRankToChat(int client, int sendto)
{
	if(sendto == -1)
		Client_PrintToChatAll(false, "%t", "rpgrank", client, GetClientLevel(client), GetClientRank(client), GetRankCount(), GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)), GetClientCredits(client));
	else
		Client_PrintToChat(sendto, false, "%t", "rpgrank", client, GetClientLevel(client), GetClientRank(client), GetRankCount(), GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)), GetClientCredits(client));
}

stock void DisplayTop10Menu(int client)
{
	if(!g_hDatabase)
		return; // TODO: Print message about database problems.

	char sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT name, level, experience, credits FROM %s ORDER BY level DESC, experience DESC LIMIT 10", TBL_PLAYERS);
	g_hDatabase.Query(SQL_GetTop10, sQuery, GetClientUserId(client));
}

public void SQL_GetTop10(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(results == null)
	{
		LogError("Unable to get player top10 (%s)", error);
		return;
	}
	
	char sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "%T\n-----\n", "Top 10 Players", client);
	
	Panel hPanel = new Panel();
	hPanel.SetTitle(sBuffer);
	
	int iIndex = 1;
	while(results.MoreRows)
	{
		if(!results.FetchRow())
			continue;
		
		results.FetchString(0, sBuffer, sizeof(sBuffer));
		Format(sBuffer, sizeof(sBuffer), "%d. %s Lvl: %d Exp: %d Cr: %d", iIndex++, sBuffer, results.FetchInt(1), results.FetchInt(2), results.FetchInt(3));
		hPanel.DrawText(sBuffer);
	}
	
	// Let the panel close on any number
	hPanel.SetKeys(255);
	
	hPanel.Send(client, Panel_DoNothing, MENU_TIME_FOREVER);
	delete hPanel;
}

public int Panel_DoNothing(Menu menu, MenuAction action, int param1, int param2)
{
}

void DisplayNextPlayersInRanking(int client)
{
	if(!g_hDatabase)
		return; // TODO: Print message about database problems.
	
	char sQuery[512];
	Format(sQuery, sizeof(sQuery), "SELECT player_id, name, level, experience, credits, (SELECT COUNT(*) FROM %s ps WHERE p.level < ps.level OR (p.level = ps.level AND p.experience < ps.experience))+1 AS rank FROM %s p WHERE level > %d OR (level = %d AND experience >= %d) ORDER BY level ASC, experience ASC LIMIT 20", TBL_PLAYERS, TBL_PLAYERS, GetClientLevel(client), GetClientLevel(client), GetClientExperience(client));
	g_hDatabase.Query(SQL_GetNext10, sQuery, GetClientUserId(client));
}

#define ENUM_STRUCTS_SUCK_SIZE 5+(MAX_NAME_LENGTH+3/4)
enum NextPlayersSorting {
	NP_DBID,
	NP_rank,
	NP_level,
	NP_exp,
	NP_credits,
	String:NP_name[MAX_NAME_LENGTH]
};

public void SQL_GetNext10(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(results == null)
	{
		LogError("Unable to get the next 20 players in front of the current rank of a player (%s)", error);
		return;
	}
	
	char sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "%T\n-----\n", "Next ranked players", client);
	
	int iNextCache[20][ENUM_STRUCTS_SUCK_SIZE], iCount;
	
	Panel hPanel = new Panel();
	hPanel.SetTitle(sBuffer);
	
	while(results.MoreRows)
	{
		if(!results.FetchRow())
			continue;
		
		results.FetchString(1, iNextCache[iCount][NP_name], MAX_NAME_LENGTH);
		iNextCache[iCount][NP_DBID] = results.FetchInt(0);
		iNextCache[iCount][NP_level] = results.FetchInt(2);
		iNextCache[iCount][NP_exp] = results.FetchInt(3);
		iNextCache[iCount][NP_credits] = results.FetchInt(4);
		iNextCache[iCount][NP_rank] = results.FetchInt(5);
		iCount++;
	}
	
	// TODO: Account for currently ingame players that got above us in the ranking and aren't in the db yet, so they aren't in the result set of the query.
	
	// See if some players are currently connected and possibly have newer stats in the cache than stored in the db
	int iLocalPlayer;
	for(int i=0;i<iCount;i++)
	{
		iLocalPlayer = GetClientByPlayerID(iNextCache[i][NP_DBID]);
		if(iLocalPlayer == -1)
			continue;
		
		iNextCache[i][NP_level] = GetClientLevel(iLocalPlayer);
		iNextCache[i][NP_exp] = GetClientExperience(iLocalPlayer);
		iNextCache[i][NP_credits] = GetClientCredits(iLocalPlayer);
	}
	
	SortCustom2D(iNextCache, iCount, Sort2D_NextPlayers);
	
	// Save the next rank as reference if the list is reordered with current data below
	int iLastRank = iNextCache[0][NP_rank];
	// Fix rank if ordering changed!
	for(int i=0;i<iCount;i++)
	{
		iNextCache[i][NP_rank] = iLastRank--;
	}
	
	int iNeeded = iCount > 10 ? 10 : iCount;
	for(int i=0;i<iCount&&iNeeded>0;i++)
	{
		if(iNextCache[i][NP_level] < GetClientLevel(client) || (iNextCache[i][NP_level] == GetClientLevel(client) && iNextCache[i][NP_exp] < GetClientExperience(client)))
			continue;
		
		Format(sBuffer, sizeof(sBuffer), "%d. %s Lvl: %d Exp: %d Cr: %d", iNextCache[i][NP_rank], iNextCache[i][NP_name], iNextCache[i][NP_level], iNextCache[i][NP_exp], iNextCache[i][NP_credits]);
		hPanel.DrawText(sBuffer);
		iNeeded--;
	}
	
	// Let the panel close on any number
	hPanel.SetKeys(255);
	
	hPanel.Send(client, Panel_DoNothing, MENU_TIME_FOREVER);
	delete hPanel;
}

// Sort players ascending by level and experience
public int Sort2D_NextPlayers(int[] elem1, int[] elem2, const int[][] array, Handle hndl)
{
	if(elem1[NP_level] > elem2[NP_level])
		return 1;
	
	if(elem1[NP_level] == elem2[NP_level] && elem1[NP_exp] > elem2[NP_exp])
		return 1;
	
	return -1;
}

/**
 * Extra experience per weapon parsing
 */
void InitWeaponExperienceConfig()
{
	g_hWeaponExperience = new StringMap();
}

bool ReadWeaponExperienceConfig()
{
	// Clear all the previous configs first.
	g_hWeaponExperience.Clear();
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/weapon_experience.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	KeyValues hKV = CreateKeyValues("SMRPGWeaponExperience");
	if(!hKV.ImportFromFile(sPath))
	{
		delete hKV;
		return false;
	}
	
	if(!hKV.GotoFirstSubKey())
	{
		delete hKV;
		return false;
	}
	
	char sWeapon[64];
	int iWeaponExperience[WeaponExperienceContainer];
	do {
		hKV.GetSectionName(sWeapon, sizeof(sWeapon));
		RemovePrefixFromString("weapon_", sWeapon, sWeapon, sizeof(sWeapon));
	
		iWeaponExperience[WXP_Damage] = hKV.GetFloat("exp_damage", -1.0);
		iWeaponExperience[WXP_Kill] = hKV.GetFloat("exp_kill", -1.0);
		iWeaponExperience[WXP_Bonus] = hKV.GetFloat("exp_bonus", -1.0);
		
		g_hWeaponExperience.SetArray(sWeapon, iWeaponExperience[0], view_as<int>(WeaponExperienceContainer));
		
	} while(hKV.GotoNextKey());
	
	delete hKV;
	return true;
}

float GetWeaponExperience(const char[] sWeapon, WeaponExperienceType type)
{
	int iWeaponExperience[WeaponExperienceContainer];
	iWeaponExperience[WXP_Damage] = -1.0;
	iWeaponExperience[WXP_Kill] = -1.0;
	iWeaponExperience[WXP_Bonus] = -1.0;
	
	char sBuffer[64];
	RemovePrefixFromString("weapon_", sWeapon, sBuffer, sizeof(sBuffer));
	// We default back to the convar values, if this fails.
	g_hWeaponExperience.GetArray(sBuffer, iWeaponExperience[0], view_as<int>(WeaponExperienceContainer));
	
	// Fall back to default convar values, if unset or invalid.
	if(iWeaponExperience[WXP_Damage] < 0.0)
		iWeaponExperience[WXP_Damage] = g_hCVExpDamage.FloatValue;
	if(iWeaponExperience[WXP_Kill] < 0.0)
		iWeaponExperience[WXP_Kill] = g_hCVExpKill.FloatValue;
	if(iWeaponExperience[WXP_Bonus] < 0.0)
		iWeaponExperience[WXP_Bonus] = g_hCVExpKillBonus.FloatValue;
	
	return view_as<float>(iWeaponExperience[type]);
}

/**
 * Helper functions
 */
// Taken from SourceBans 2's sb_bans :)
void SecondsToString(char[] sBuffer, int iLength, int iSecs, bool bTextual = true)
{
	if(bTextual)
	{
		char sDesc[6][8] = {"mo",              "wk",             "d",          "hr",    "min", "sec"};
		int  iCount, iDiv[6]    = {60 * 60 * 24 * 30, 60 * 60 * 24 * 7, 60 * 60 * 24, 60 * 60, 60,    1};
		sBuffer[0]              = '\0';
		
		for(int i = 0; i < sizeof(iDiv); i++)
		{
			if((iCount = iSecs / iDiv[i]) > 0)
			{
				Format(sBuffer, iLength, "%s%i %s, ", sBuffer, iCount, sDesc[i]);
				iSecs %= iDiv[i];
			}
		}
		sBuffer[strlen(sBuffer) - 2] = '\0';
	}
	else
	{
		int iHours = iSecs  / 60 / 60;
		iSecs     -= iHours * 60 * 60;
		int iMins  = iSecs  / 60;
		iSecs     %= 60;
		Format(sBuffer, iLength, "%02i:%02i:%02i", iHours, iMins, iSecs);
	}
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