#pragma semicolon 1
#include <sourcemod>
#include <smlib>

// Allow to refetch the rank every 20 seconds.
#define RANK_CACHE_UPDATE_INTERVAL 20

new g_iCachedRank[MAXPLAYERS+1] = {-1,...};
new g_iNextCacheUpdate[MAXPLAYERS+1];
new g_iCachedRankCount = 0;
new g_iNextCacheCountUpdate;

enum SessionStats {
	SS_JoinTime,
	SS_JoinLevel,
	SS_JoinExperience,
	SS_JoinCredits,
	SS_JoinRank,
	bool:SS_WantsAutoUpdate,
	bool:SS_WantsMenuOpen,
	bool:SS_OKToClose,
	Handle:SS_LastExperience
};

new g_iPlayerSessionStartStats[MAXPLAYERS+1][SessionStats];
new bool:g_bBackToStatsMenu[MAXPLAYERS+1];

new Handle:g_hfwdOnAddExperience;
new Handle:g_hfwdOnAddExperiencePost;

// AFK Handling
enum AFKInfo {
	Float:AFK_lastPosition[3],
	AFK_startTime,
	AFK_spawnTime,
	AFK_deathTime
}
new g_PlayerAFKInfo[MAXPLAYERS+1][AFKInfo];
new bool:g_bPlayerSpawnProtected[MAXPLAYERS+1];

// Individual weapon experience settings
new Handle:g_hWeaponExperience;

enum WeaponExperienceContainer {
	Float:WXP_Damage,
	Float:WXP_Kill,
	Float:WXP_Bonus
};

RegisterStatsNatives()
{
	// native bool:SMRPG_AddClientExperience(client, exp, const String:reason[], bool:bHideNotice, other=-1, SMRPG_ExpTranslationCb:callback=SMRPG_ExpTranslationCb:INVALID_FUNCTION);
	CreateNative("SMRPG_AddClientExperience", Native_AddClientExperience);
	// native SMRPG_LevelToExperience(iLevel);
	CreateNative("SMRPG_LevelToExperience", Native_LevelToExperience);
	// native SMRPG_GetClientRank(client);
	CreateNative("SMRPG_GetClientRank", Native_GetClientRank);
	// native SMRPG_GetRankCount();
	CreateNative("SMRPG_GetRankCount", Native_GetRankCount);
	
	// native SMRPG_GetTop10Players(SQLTCallback:callback, any:data=0);
	CreateNative("SMRPG_GetTop10Players", Native_GetTop10Players);
	
	// native bool:SMRPG_IsClientAFK(client);
	CreateNative("SMRPG_IsClientAFK", Native_IsClientAFK);
	// native bool:SMRPG_IsClientSpawnProtected(client);
	CreateNative("SMRPG_IsClientSpawnProtected", Native_IsClientSpawnProtected);
	
	// native Float:SMRPG_GetWeaponExperience(const String:sWeapon[], WeaponExperienceType:type);
	CreateNative("SMRPG_GetWeaponExperience", Native_GetWeaponExperience);
}

RegisterStatsForwards()
{
	// forward Action:SMRPG_OnAddExperience(client, const String:reason[], &iExperience, other);
	g_hfwdOnAddExperience = CreateGlobalForward("SMRPG_OnAddExperience", ET_Hook, Param_Cell, Param_String, Param_CellByRef, Param_Cell);
	// forward SMRPG_OnAddExperiencePost(client, const String:reason[], iExperience, other);
	g_hfwdOnAddExperiencePost = CreateGlobalForward("SMRPG_OnAddExperiencePost", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_Cell);
}

/* Calculate the experience needed for this level */
Stats_LvlToExp(iLevel)
{
	new iExp;
	
	if(iLevel <= 1)
		iExp = GetConVarInt(g_hCVExpStart);
	else
		iExp = iLevel * GetConVarInt(g_hCVExpInc) + GetConVarInt(g_hCVExpStart);
	
	return iExp > GetConVarInt(g_hCVExpMax) ? GetConVarInt(g_hCVExpMax) : iExp;
}

/* Calculate how many levels to increase by current level and experience */
Stats_CalcLvlInc(iLevel, iExp)
{
	new iLevelIncrease;
	
	new iExpRequired = Stats_LvlToExp(iLevel);
	while(iExp >= iExpRequired)
	{
		iLevelIncrease++;
		iExp -= iExpRequired;
		iExpRequired = Stats_LvlToExp(iLevel+iLevelIncrease);
	}
	
	return iLevelIncrease;
}

Stats_PlayerNewLevel(client, iLevelIncrease)
{
	new iMaxLevel, bool:bMaxLevelReset;
	if(IsFakeClient(client))
	{
		iMaxLevel = GetConVarInt(g_hCVBotMaxlevel);
		bMaxLevelReset = GetConVarBool(g_hCVBotMaxlevelReset);
	}
	else
	{
		iMaxLevel = GetConVarInt(g_hCVPlayerMaxlevel);
		bMaxLevelReset = GetConVarBool(g_hCVPlayerMaxlevelReset);
	}
	
	// Check if the player reached the maxlevel
	if(iMaxLevel > 0)
	{
		new iNewLevel = GetClientLevel(client) + iLevelIncrease;
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
	new iExperience = GetClientExperience(client);
	for(new i=0;i<iLevelIncrease;i++)
	{
		iExperience -= Stats_LvlToExp(GetClientLevel(client)+i);
	}
	
	// Some admin gave him a level even though he didn't have enough exp? well well..
	if(iExperience < 0)
		iExperience = 0;
	
	SetClientExperience(client, iExperience);
	
	SetClientLevel(client, GetClientLevel(client)+iLevelIncrease);
	SetClientCredits(client, GetClientCredits(client) + iLevelIncrease * GetConVarInt(g_hCVCreditsInc));
	
	DebugMsg("%N is now level %d (%d level increase(s))", client, GetClientLevel(client), iLevelIncrease);
	
	// Player wants to get prompted with the rpgmenu automatically when he levels up?
	// Make sure he isn't viewing another menu at the moment.
	if(ShowMenuOnLevelUp(client) && GetClientMenu(client) == MenuSource_None)
	{
		DisplayUpgradesMenu(client);
	}
	
	if(FadeScreenOnLevelUp(client))
	{
		new String:sColor[16], String:sBuffers[4][4];
		// Keep the default color if there is invalid input in the convar.
		new iColor[] = {255, 215, 0, 40};
		// Parse the "r g b a" convar string of the screen fading color.
		GetConVarString(g_hCVFadeOnLevelColor, sColor, sizeof(sColor));
		new iNum = ExplodeString(sColor, " ", sBuffers, 4, 4);
		for(new i=0;i<iNum;i++)
			iColor[i] = StringToInt(sBuffers[i]);
		Client_ScreenFade(client, 255, FFADE_OUT|FFADE_PURGE, 255, iColor[0], iColor[1], iColor[2], iColor[3]);
	}
	
	if(GetConVarBool(g_hCVAnnounceNewLvl))
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
	else if(GetConVarBool(g_hCVBotEnable))
	{
		BotPickUpgrade(client);
	}
}

bool:Stats_AddExperience(client, &iExperience, const String:sReason[], bool:bHideNotice, other)
{
	// Nothing to add?
	if(iExperience <= 0)
		return false;
	
	IF_IGNORE_BOTS(client)
		return false;
	
	new bool:bBotEnable = GetConVarBool(g_hCVBotEnable);
	if(GetConVarBool(g_hCVNeedEnemies))
	{
		// No enemies in the opposite team?
		if(!Team_HaveAllPlayers(bBotEnable))
			return false;
	}
	
	// All players in the opposite team are AFK?
	if(GetConVarBool(g_hCVEnemiesNotAFK))
	{
		new iMyTeam = GetClientTeam(client);
		if(iMyTeam > 1)
		{
			new bool:bAllAFK, iTeam;
			for(new i=1;i<=MaxClients;i++)
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
	
	// Don't give the players any more exp when they already reached the maxlevel.
	new iMaxlevel;
	if(IsFakeClient(client))
		iMaxlevel = GetConVarInt(g_hCVBotMaxlevel);
	else
		iMaxlevel = GetConVarInt(g_hCVPlayerMaxlevel);
	
	if(iMaxlevel > 0 && GetClientLevel(client) >= iMaxlevel)
		return false;
	
	// Handle experience with bots
	if(other > 0 && other <= MaxClients && IsClientInGame(other))
	{
		new bool:bClientBot = IsFakeClient(client);
		new bool:bOtherBot = IsFakeClient(other);
		if(bClientBot && bOtherBot)
		{
			if(!GetConVarBool(g_hCVBotKillBot))
				return false;
		}
		else if(bClientBot && !bOtherBot)
		{
			if(!GetConVarBool(g_hCVBotKillPlayer))
				return false;
		}
		else if(!bClientBot && bOtherBot)
		{
			if(!GetConVarBool(g_hCVPlayerKillBot))
				return false;
		}
	}
	
	// See if some other plugin doesn't like this.
	if(Stats_CallOnExperienceForward(client, sReason, iExperience, other) > Plugin_Changed)
		return false;
	
	SetClientExperience(client, GetClientExperience(client) + iExperience);
	
	new iExpRequired = Stats_LvlToExp(GetClientLevel(client));
	
	if(GetClientExperience(client) >= iExpRequired)
		Stats_PlayerNewLevel(client, Stats_CalcLvlInc(GetClientLevel(client), GetClientExperience(client)));
	
	Stats_CallOnExperiencePostForward(client, sReason, iExperience, other);
	
	if(!bHideNotice && GetConVarBool(g_hCVExpNotice))
		PrintHintText(client, "%t", "Experience Gained Hintbox", iExperience, GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)));
	
	return true;
}

Stats_PlayerDamage(attacker, victim, Float:fDamage, const String:sWeapon[])
{
	if(!GetConVarBool(g_hCVEnable))
		return;
	
	// Don't give the attacker any exp when his victim was afk.
	if(IsClientAFK(victim))
		return;
	
	// Don't give the attacker any exp when his victim just spawned and didn't do anything at all yet.
	if(IsClientSpawnProtected(victim))
		return;
	
	// Ignore teamattack if not FFA
	if(!GetConVarBool(g_hCVFFA) && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iExp = RoundToCeil(fDamage * GetWeaponExperience(sWeapon, WeaponExperience_Damage));
	
	SMRPG_AddClientExperience(attacker, iExp, ExperienceReason_PlayerHurt, true, victim);
}

Stats_PlayerKill(attacker, victim, const String:sWeapon[])
{
	if(!GetConVarBool(g_hCVEnable))
		return;
	
	// Don't give the attacker any exp when his victim was afk.
	if(IsClientAFK(victim))
		return;
	
	// Don't give the attacker any exp when his victim just spawned and didn't do anything at all yet.
	if(IsClientSpawnProtected(victim))
		return;
	
	// Ignore teamattack if not FFA
	if(!GetConVarBool(g_hCVFFA) && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iExp = RoundToCeil(GetClientLevel(victim) * GetWeaponExperience(sWeapon, WeaponExperience_Kill) + GetWeaponExperience(sWeapon, WeaponExperience_Bonus));
	new iExpMax = GetConVarInt(g_hCVExpKillMax);
	// Limit the possible experience to this.
	if(iExpMax > 0 && iExp > iExpMax)
		iExp = iExpMax;
	
	SMRPG_AddClientExperience(attacker, iExp, ExperienceReason_PlayerKill, false, victim);
}

Stats_WinningTeam(iTeam)
{
	if(!GetConVarBool(g_hCVEnable))
		return;
	
	new Float:fTeamRatio;
	if(iTeam == 2)
		fTeamRatio = SMRPG_TeamRatio(3);
	else if(iTeam == 3)
		fTeamRatio = SMRPG_TeamRatio(2);
	else
		return;
	
	new iExperience;
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == iTeam)
		{
			iExperience = RoundToCeil(float(Stats_LvlToExp(GetClientLevel(i))) * GetConVarFloat(g_hCVExpTeamwin) * fTeamRatio);
			SMRPG_AddClientExperience(i, iExperience, ExperienceReason_RoundEnd, false, -1);
		}
	}
}

// forward Action:SMRPG_OnAddExperience(client, const String:reason[], &iExperience, other);
Action:Stats_CallOnExperienceForward(client, const String:sReason[], &iExperience, other)
{
	new Action:result;
	Call_StartForward(g_hfwdOnAddExperience);
	Call_PushCell(client);
	Call_PushString(sReason);
	Call_PushCellRef(iExperience);
	Call_PushCell(other);
	Call_Finish(result);
	return result;
}

// forward SMRPG_OnAddExperiencePost(client, const String:reason[], iExperience, other);
Stats_CallOnExperiencePostForward(client, const String:sReason[], iExperience, other)
{
	Call_StartForward(g_hfwdOnAddExperiencePost);
	Call_PushCell(client);
	Call_PushString(sReason);
	Call_PushCell(iExperience);
	Call_PushCell(other);
	Call_Finish();
}

// AFK Handling
StartAFKChecker()
{
	CreateTimer(0.5, Timer_CheckAFKPlayers, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action:Timer_CheckAFKPlayers(Handle:timer)
{
	new Float:fOrigin[3], Float:fLastPosition[3];
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) > 1)
		{
			GetClientAbsOrigin(i, fOrigin);
			
			// See if the player just spawned..
			if(g_PlayerAFKInfo[i][AFK_spawnTime] > 0)
			{
				new iDifference = GetTime() - g_PlayerAFKInfo[i][AFK_spawnTime];
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

bool:IsClientAFK(client)
{
	if(g_PlayerAFKInfo[client][AFK_startTime] == 0)
		return false;
	
	new iAFKTime = GetConVarInt(g_hCVAFKTime);
	if(iAFKTime <= 0)
		return false;
	
	if((GetTime() - g_PlayerAFKInfo[client][AFK_startTime]) > iAFKTime)
		return true;
	return false;
}

ResetAFKPlayer(client)
{
	g_PlayerAFKInfo[client][AFK_startTime] = 0;
	g_PlayerAFKInfo[client][AFK_spawnTime] = 0;
	g_PlayerAFKInfo[client][AFK_deathTime] = 0;
	Array_Copy(g_PlayerAFKInfo[client][AFK_lastPosition], Float:{0.0,0.0,0.0}, 3);
}

// Spawn Protection handling
bool:IsClientSpawnProtected(client)
{
	if(!GetConVarBool(g_hCVSpawnProtect))
		return false;
	return g_bPlayerSpawnProtected[client];
}

ResetSpawnProtection(client)
{
	g_bPlayerSpawnProtected[client] = false;
}

/**
 * Native Callbacks
 */
// native bool:SMRPG_AddClientExperience(client, &exp, const String:reason[], bool:bHideNotice, other=-1, SMRPG_ExpTranslationCb:callback=SMRPG_ExpTranslationCb:INVALID_FUNCTION);
public Native_AddClientExperience(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	new iExperience = GetNativeCellRef(2);
	new iLen;
	GetNativeStringLength(3, iLen);
	new String:sReason[iLen+1];
	GetNativeString(3, sReason, iLen+1);
	
	new bool:bHideNotice = bool:GetNativeCell(4);
	new other = GetNativeCell(5);
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
	new Function:translationCallback = GetNativeFunction(6);
#else
	new Function:translationCallback = Function:GetNativeCell(6);
#endif
	
	new iOriginalExperience = iExperience;
	new bool:bAdded = Stats_AddExperience(client, iExperience, sReason, bHideNotice, other);
	if(iOriginalExperience != iExperience)
		SetNativeCellRef(2, iExperience);
	
	if(bAdded && !IsFakeClient(client))
	{
		new String:sTranslatedReason[256];
		strcopy(sTranslatedReason, sizeof(sTranslatedReason), sReason);
		if(translationCallback != INVALID_FUNCTION)
		{
			// functag SMRPG_ExpTranslationCb(client, const String:reason[], iExperience, other, String:buffer[], maxlen);
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

public Native_LevelToExperience(Handle:plugin, numParams)
{
	new iLevel = GetNativeCell(1);
	return Stats_LvlToExp(iLevel);
}

public Native_GetClientRank(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	return GetClientRank(client);
}

public Native_GetRankCount(Handle:plugin, numParams)
{
	return GetRankCount();
}

public Native_IsClientAFK(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	return IsClientAFK(client);
}

public Native_IsClientSpawnProtected(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return false;
	}
	
	return IsClientSpawnProtected(client);
}

public Native_GetTop10Players(Handle:plugin, numParams)
{
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
	new Function:callback = GetNativeFunction(1);
#else
	new Function:callback = Function:GetNativeCell(1);
#endif
	new data = GetNativeCell(2);
	
	new Handle:hData = CreateDataPack();
	WritePackCell(hData, _:plugin);
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
	WritePackFunction(hData, callback);
#else
	WritePackCell(hData, _:callback);
#endif
	WritePackCell(hData, data);
	
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT name, level, experience, credits FROM %s ORDER BY level DESC, experience DESC LIMIT 10", TBL_PLAYERS);
	SQL_TQuery(g_hDatabase, SQL_GetTop10Native, sQuery, hData);
}

public SQL_GetTop10Native(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new Handle:hPlugin = Handle:ReadPackCell(data);
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
	new Function:callback = ReadPackFunction(data);
#else
	new Function:callback = Function:ReadPackCell(data);
#endif
	new extraData = ReadPackCell(data);
	CloseHandle(data);
	
	// Don't care if the calling plugin is gone.
	if(!IsValidPlugin(hPlugin))
		return;
	
	Call_StartFunction(hPlugin, callback);
	Call_PushCell(INVALID_HANDLE);
	Call_PushCell(hndl);
	Call_PushString(error);
	Call_PushCell(extraData);
	Call_Finish();
}

// native Float:SMRPG_GetWeaponExperience(const String:sWeapon[], WeaponExperienceType:type);
public Native_GetWeaponExperience(Handle:plugin, numParams)
{
	new String:sWeapon[64], WeaponExperienceType:type;
	GetNativeString(1, sWeapon, sizeof(sWeapon));
	type = WeaponExperienceType:GetNativeCell(2);
	
	return _:GetWeaponExperience(sWeapon, type);
}

// rpgsession handling
InitPlayerSessionStartStats(client)
{
	g_iPlayerSessionStartStats[client][SS_JoinTime] = GetTime();
	g_iPlayerSessionStartStats[client][SS_JoinLevel] = GetClientLevel(client);
	g_iPlayerSessionStartStats[client][SS_JoinExperience] = GetClientExperience(client);
	g_iPlayerSessionStartStats[client][SS_JoinCredits] = GetClientCredits(client);
	g_iPlayerSessionStartStats[client][SS_JoinRank] = -1;
	g_iPlayerSessionStartStats[client][SS_WantsAutoUpdate] = false;
	g_iPlayerSessionStartStats[client][SS_WantsMenuOpen] = false;
	g_iPlayerSessionStartStats[client][SS_OKToClose] = false;
	
	new Handle:hLastExperience = CreateArray(ByteCountToCells(256));
	ResizeArray(hLastExperience, GetConVarInt(g_hCVLastExperienceCount));
	SetArrayString(hLastExperience, 0, "");
	g_iPlayerSessionStartStats[client][SS_LastExperience] = hLastExperience;
}

ResetPlayerSessionStats(client)
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
public SMRPG_OnClientLoaded(client)
{
	// Only set it once and leave it that way until he really disconnects.
	if(g_iPlayerSessionStartStats[client][SS_JoinTime] == 0)
		InitPlayerSessionStartStats(client);
}

InsertSessionExperienceString(client, const String:sExperience[])
{
	new Handle:hLastExperience = g_iPlayerSessionStartStats[client][SS_LastExperience];
	// Not loaded yet..
	if(hLastExperience == INVALID_HANDLE)
		return;
	
	// Insert the string at the start of the array!
	ShiftArrayUp(hLastExperience, 0);
	SetArrayString(hLastExperience, 0, sExperience);
}

public ConVar_LastExperienceCountChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// Apply the new size immediately.
	for(new i=1;i<=MaxClients;i++)
	{
		if(g_iPlayerSessionStartStats[i][SS_JoinTime] > 0)
			ResizeArray(g_iPlayerSessionStartStats[i][SS_LastExperience], GetConVarInt(convar));
	}
}

StartSessionMenuUpdater()
{
	CreateTimer(1.0, Timer_UpdateSessionMenus, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action:Timer_UpdateSessionMenus(Handle:timer)
{
	for(new i=1;i<=MaxClients;i++)
	{
		// Refresh the contents of the menu here.
		if(IsClientInGame(i) && !IsFakeClient(i) && g_iPlayerSessionStartStats[i][SS_WantsMenuOpen] && g_iPlayerSessionStartStats[i][SS_WantsAutoUpdate])
			DisplaySessionStatsMenu(i);
	}
	
	return Plugin_Continue;
}

DisplaySessionStatsMenu(client)
{
	new Handle:hPanel = CreatePanel();
	
	decl String:sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "%T", "Stats", client);
	DrawPanelItem(hPanel, sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "  %T", "Level", client, GetClientLevel(client));
	DrawPanelText(hPanel, sBuffer);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Experience short", client, GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)));
	DrawPanelText(hPanel, sBuffer);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Credits", client, GetClientCredits(client));
	DrawPanelText(hPanel, sBuffer);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Rank", client, GetClientRank(client), GetRankCount());
	DrawPanelText(hPanel, sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Session", client);
	DrawPanelItem(hPanel, sBuffer);
	
	SecondsToString(sBuffer, sizeof(sBuffer), GetTime()-g_iPlayerSessionStartStats[client][SS_JoinTime], false);
	Format(sBuffer, sizeof(sBuffer), "  %T", "Playtime", client, sBuffer);
	DrawPanelText(hPanel, sBuffer);
	
	new iChangedLevels = GetClientLevel(client) - g_iPlayerSessionStartStats[client][SS_JoinLevel];
	Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed level", client, iChangedLevels>0?"+":"", iChangedLevels);
	DrawPanelText(hPanel, sBuffer);
	
	// Need to calculate the total earned experience.
	new iEarnedExperience = GetClientExperience(client) - g_iPlayerSessionStartStats[client][SS_JoinExperience];
	for(new i=0;i<iChangedLevels;i++)
	{
		iEarnedExperience += Stats_LvlToExp(g_iPlayerSessionStartStats[client][SS_JoinLevel]+i);
	}
	
	Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed experience", client, iEarnedExperience>0?"+":"", iEarnedExperience);
	DrawPanelText(hPanel, sBuffer);
	
	new iBuffer = GetClientCredits(client) - g_iPlayerSessionStartStats[client][SS_JoinCredits];
	Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed credits", client, iBuffer>0?"+":"", iBuffer);
	DrawPanelText(hPanel, sBuffer);
	
	if(g_iPlayerSessionStartStats[client][SS_JoinRank] != -1)
	{
		iBuffer = g_iPlayerSessionStartStats[client][SS_JoinRank] - GetClientRank(client);
		Format(sBuffer, sizeof(sBuffer), "  %T: %s%d", "Changed rank", client, iBuffer>0?"+":"", iBuffer);
		DrawPanelText(hPanel, sBuffer);
	}
	
	DrawPanelItem(hPanel, "", ITEMDRAW_SPACER);
	
	Format(sBuffer, sizeof(sBuffer), "%T: %T", "Auto refresh panel", client, (g_iPlayerSessionStartStats[client][SS_WantsAutoUpdate]?"Yes":"No"), client);
	DrawPanelItem(hPanel, sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%T", "Last Experience", client);
	DrawPanelItem(hPanel, sBuffer);
	
	// The old menu is closed when we open the new one.
	// The logic here is like this:
	// We want to stop redisplaying the session menu, if the menu was closed gracefully or was interrupted by a different menu.
	// If the old menu is currently displaying (callback was not called yet) we don't want it to stay closed when we display it again.
	// So we set OKToClose to true, so it doesn't set WantsMenuOpen to false as if the menu was closed by an interrupting menu.
	// That way the menu stays open and is refreshed every second while staying closed if the player closes it or some other menu is displayed over it.
	if(g_iPlayerSessionStartStats[client][SS_WantsMenuOpen])
		g_iPlayerSessionStartStats[client][SS_OKToClose] = true;
	g_iPlayerSessionStartStats[client][SS_WantsMenuOpen] = true;
	
	SendPanelToClient(hPanel, client, Panel_HandleSessionMenu, MENU_TIME_FOREVER);
	CloseHandle(hPanel);
}

public Panel_HandleSessionMenu(Handle:menu, MenuAction:action, param1, param2)
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

DisplaySessionLastExperienceMenu(client, bool:bBackToStatsMenu)
{
	new Handle:hLastExperience = g_iPlayerSessionStartStats[client][SS_LastExperience];
	// Player not loaded yet.
	if(hLastExperience == INVALID_HANDLE)
		return;

	// Remember what the back button in the menu should do.
	g_bBackToStatsMenu[client] = bBackToStatsMenu;
	
	new Handle:hMenu = CreateMenu(Menu_HandleLastExperience);
	SetMenuTitle(hMenu, "%t: %N", "Last Experience", client);
	SetMenuExitBackButton(hMenu, true);
	
	new iSize = GetArraySize(hLastExperience);
	decl String:sBuffer[256];
	for(new i=0;i<iSize;i++)
	{
		if(GetArrayString(hLastExperience, i, sBuffer, sizeof(sBuffer)) <= 0)
			break;
		
		AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	}
	
	if(GetMenuItemCount(hMenu) == 0)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Nothing to display", client);
		AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Menu_HandleLastExperience(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
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

UpdateClientRank(client)
{
	if(!g_hDatabase)
		return;
	
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM %s WHERE level > %d OR (level = %d AND experience > %d)", TBL_PLAYERS, GetClientLevel(client), GetClientLevel(client), GetClientExperience(client));
	SQL_TQuery(g_hDatabase, SQL_GetClientRank, sQuery, GetClientUserId(client));
	g_iNextCacheUpdate[client] = GetTime() + RANK_CACHE_UPDATE_INTERVAL;
}

GetClientRank(client)
{
	if(IsFakeClient(client))
		return -1;
	
	// Only update the cache, if we actually used it for a while.
	if(g_iNextCacheUpdate[client] < GetTime())
		UpdateClientRank(client);
	return g_iCachedRank[client];
}

ClearClientRankCache(client)
{
	g_iCachedRank[client] = -1;
	g_iNextCacheUpdate[client] = 0;
}

public SQL_GetClientRank(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to get player rank (%s)", error);
		return;
	}
	
	if(!SQL_FetchRow(hndl))
		return;
	
	g_iCachedRank[client] = SQL_FetchInt(hndl, 0) + 1; // +1 since the query returns the count, not the rank
	
	// Save the first time we fetch the rank for him.
	if(g_iPlayerSessionStartStats[client][SS_JoinRank] == -1)
		g_iPlayerSessionStartStats[client][SS_JoinRank] = g_iCachedRank[client];
}

UpdateRankCount()
{
	if(!g_hDatabase)
		return;
	
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM %s", TBL_PLAYERS);
	SQL_TQuery(g_hDatabase, SQL_GetRankCount, sQuery);
	g_iNextCacheCountUpdate = GetTime() + RANK_CACHE_UPDATE_INTERVAL;
}

GetRankCount()
{
	// Only update the cache, if we actually used it for a while.
	if(g_iNextCacheCountUpdate < GetTime())
		UpdateRankCount();
	
	if(g_iCachedRankCount > 0)
		return g_iCachedRankCount;
	
	return 0;
}

public SQL_GetRankCount(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to get player rank count (%s)", error);
		return;
	}
	
	if(!SQL_FetchRow(hndl))
		return;
	
	g_iCachedRankCount = SQL_FetchInt(hndl, 0);
	
	new info[PlayerInfo];
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			GetClientRPGInfo(i, info);
			if(info[PLR_dbId] < 0)
				g_iCachedRankCount++; /* accounts for players not saved in the db */
		}
	}
}

PrintRankToChat(client, sendto)
{
	if(sendto == -1)
		Client_PrintToChatAll(false, "%t", "rpgrank", client, GetClientLevel(client), GetClientRank(client), GetRankCount(), GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)), GetClientCredits(client));
	else
		Client_PrintToChat(sendto, false, "%t", "rpgrank", client, GetClientLevel(client), GetClientRank(client), GetRankCount(), GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)), GetClientCredits(client));
}

stock DisplayTop10Menu(client)
{
	if(!g_hDatabase)
		return; // TODO: Print message about database problems.

	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT name, level, experience, credits FROM %s ORDER BY level DESC, experience DESC LIMIT 10", TBL_PLAYERS);
	SQL_TQuery(g_hDatabase, SQL_GetTop10, sQuery, GetClientUserId(client));
}

public SQL_GetTop10(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to get player top10 (%s)", error);
		return;
	}
	
	decl String:sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "%T\n-----\n", "Top 10 Players", client);
	
	new Handle:hPanel = CreatePanel();
	SetPanelTitle(hPanel, sBuffer);
	
	new iIndex = 1;
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		SQL_FetchString(hndl, 0, sBuffer, sizeof(sBuffer));
		Format(sBuffer, sizeof(sBuffer), "%d. %s Lvl: %d Exp: %d Cr: %d", iIndex++, sBuffer, SQL_FetchInt(hndl, 1), SQL_FetchInt(hndl, 2), SQL_FetchInt(hndl, 3));
		DrawPanelText(hPanel, sBuffer);
	}
	
	// Let the panel close on any number
	SetPanelKeys(hPanel, 255);
	
	SendPanelToClient(hPanel, client, Panel_DoNothing, MENU_TIME_FOREVER);
	CloseHandle(hPanel);
}

public Panel_DoNothing(Handle:menu, MenuAction:action, param1, param2)
{
}

DisplayNextPlayersInRanking(client)
{
	if(!g_hDatabase)
		return; // TODO: Print message about database problems.
	
	decl String:sQuery[512];
	Format(sQuery, sizeof(sQuery), "SELECT player_id, name, level, experience, credits, (SELECT COUNT(*) FROM %s ps WHERE p.level < ps.level OR (p.level = ps.level AND p.experience < ps.experience))+1 AS rank FROM %s p WHERE level > %d OR (level = %d AND experience >= %d) ORDER BY level ASC, experience ASC LIMIT 20", TBL_PLAYERS, TBL_PLAYERS, GetClientLevel(client), GetClientLevel(client), GetClientExperience(client));
	SQL_TQuery(g_hDatabase, SQL_GetNext10, sQuery, GetClientUserId(client));
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

public SQL_GetNext10(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Unable to get the next 20 players in front of the current rank of a player (%s)", error);
		return;
	}
	
	decl String:sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "%T\n-----\n", "Next ranked players", client);
	
	new iNextCache[20][ENUM_STRUCTS_SUCK_SIZE], iCount;
	
	new Handle:hPanel = CreatePanel();
	SetPanelTitle(hPanel, sBuffer);
	
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		SQL_FetchString(hndl, 1, iNextCache[iCount][NP_name], MAX_NAME_LENGTH);
		iNextCache[iCount][NP_DBID] = SQL_FetchInt(hndl, 0);
		iNextCache[iCount][NP_level] = SQL_FetchInt(hndl, 2);
		iNextCache[iCount][NP_exp] = SQL_FetchInt(hndl, 3);
		iNextCache[iCount][NP_credits] = SQL_FetchInt(hndl, 4);
		iNextCache[iCount][NP_rank] = SQL_FetchInt(hndl, 5);
		iCount++;
	}
	
	// TODO: Account for currently ingame players that got above us in the ranking and aren't in the db yet, so they aren't in the result set of the query.
	
	// See if some players are currently connected and possibly have newer stats in the cache than stored in the db
	new iLocalPlayer;
	for(new i=0;i<iCount;i++)
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
	new iLastRank = iNextCache[0][NP_rank];
	// Fix rank if ordering changed!
	for(new i=0;i<iCount;i++)
	{
		iNextCache[i][NP_rank] = iLastRank--;
	}
	
	new iNeeded = iCount > 10 ? 10 : iCount;
	for(new i=0;i<iCount&&iNeeded>0;i++)
	{
		if(iNextCache[i][NP_level] < GetClientLevel(client) || (iNextCache[i][NP_level] == GetClientLevel(client) && iNextCache[i][NP_exp] < GetClientExperience(client)))
			continue;
		
		Format(sBuffer, sizeof(sBuffer), "%d. %s Lvl: %d Exp: %d Cr: %d", iNextCache[i][NP_rank], iNextCache[i][NP_name], iNextCache[i][NP_level], iNextCache[i][NP_exp], iNextCache[i][NP_credits]);
		DrawPanelText(hPanel, sBuffer);
		iNeeded--;
	}
	
	// Let the panel close on any number
	SetPanelKeys(hPanel, 255);
	
	SendPanelToClient(hPanel, client, Panel_DoNothing, MENU_TIME_FOREVER);
	CloseHandle(hPanel);
}

// Sort players ascending by level and experience
public Sort2D_NextPlayers(elem1[], elem2[], const array[][], Handle:hndl)
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
InitWeaponExperienceConfig()
{
	g_hWeaponExperience = CreateTrie();
}

bool:ReadWeaponExperienceConfig()
{
	// Clear all the previous configs first.
	ClearTrie(g_hWeaponExperience);
	
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/weapon_experience.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	new Handle:hKV = CreateKeyValues("SMRPGWeaponExperience");
	if(!FileToKeyValues(hKV, sPath))
		return false;
	
	if(!KvGotoFirstSubKey(hKV))
		return false;
	
	
	new String:sWeapon[64], iWeaponExperience[WeaponExperienceContainer];
	do {
		KvGetSectionName(hKV, sWeapon, sizeof(sWeapon));
		RemovePrefixFromString("weapon_", sWeapon, sWeapon, sizeof(sWeapon));
	
		iWeaponExperience[WXP_Damage] = KvGetFloat(hKV, "exp_damage", -1.0);
		iWeaponExperience[WXP_Kill] = KvGetFloat(hKV, "exp_kill", -1.0);
		iWeaponExperience[WXP_Bonus] = KvGetFloat(hKV, "exp_bonus", -1.0);
		
		SetTrieArray(g_hWeaponExperience, sWeapon, iWeaponExperience[0], _:WeaponExperienceContainer);
		
	} while(KvGotoNextKey(hKV));
	
	CloseHandle(hKV);
	return true;
}

Float:GetWeaponExperience(const String:sWeapon[], WeaponExperienceType:type)
{
	new iWeaponExperience[WeaponExperienceContainer];
	iWeaponExperience[WXP_Damage] = -1.0;
	iWeaponExperience[WXP_Kill] = -1.0;
	iWeaponExperience[WXP_Bonus] = -1.0;
	
	new String:sBuffer[64];
	RemovePrefixFromString("weapon_", sWeapon, sBuffer, sizeof(sBuffer));
	// We default back to the convar values, if this fails.
	GetTrieArray(g_hWeaponExperience, sBuffer, iWeaponExperience[0], _:WeaponExperienceContainer);
	
	// Fall back to default convar values, if unset or invalid.
	if(iWeaponExperience[WXP_Damage] < 0.0)
		iWeaponExperience[WXP_Damage] = GetConVarFloat(g_hCVExpDamage);
	if(iWeaponExperience[WXP_Kill] < 0.0)
		iWeaponExperience[WXP_Kill] = GetConVarFloat(g_hCVExpKill);
	if(iWeaponExperience[WXP_Bonus] < 0.0)
		iWeaponExperience[WXP_Bonus] = GetConVarFloat(g_hCVExpKillBonus);
	
	return Float:iWeaponExperience[type];
}

/**
 * Helper functions
 */
// Taken from SourceBans 2's sb_bans :)
SecondsToString(String:sBuffer[], iLength, iSecs, bool:bTextual = true)
{
	if(bTextual)
	{
		decl String:sDesc[6][8] = {"mo",              "wk",             "d",          "hr",    "min", "sec"};
		new  iCount, iDiv[6]    = {60 * 60 * 24 * 30, 60 * 60 * 24 * 7, 60 * 60 * 24, 60 * 60, 60,    1};
		sBuffer[0]              = '\0';
		
		for(new i = 0; i < sizeof(iDiv); i++)
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
		new iHours = iSecs  / 60 / 60;
		iSecs     -= iHours * 60 * 60;
		new iMins  = iSecs  / 60;
		iSecs     %= 60;
		Format(sBuffer, iLength, "%02i:%02i:%02i", iHours, iMins, iSecs);
	}
}

// This removes a prefix from a string including anything before the prefix.
// This is useful for TF2's tfweapon_ prefix vs. default weapon_ prefix in other sourcegames.
stock RemovePrefixFromString(const String:sPrefix[], const String:sInput[], String:sOutput[], maxlen)
{
	new iPos = StrContains(sInput, sPrefix, false);
	// The prefix isn't in the string, just copy the whole string.
	if(iPos == -1)
		iPos = 0;
	// Skip the prefix and all other stuff before it.
	else
		iPos += strlen(sPrefix);
	
	// Support for inputstring == outputstring?
	new String:sBuffer[maxlen+1];
	strcopy(sBuffer, maxlen, sInput[iPos]);
	
	strcopy(sOutput, maxlen, sBuffer);
}