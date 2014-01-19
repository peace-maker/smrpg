#pragma semicolon 1
#include <sourcemod>

new g_iCachedRank[MAXPLAYERS+1] = {-1,...};
new g_iCachedRankCount = 0;

new Handle:g_hfwdOnAddExperience;

RegisterStatsNatives()
{
	// forward Action:SMRPG_OnAddExperience(client, ExperienceReason:reason, &iExperience);
	g_hfwdOnAddExperience = CreateGlobalForward("SMRPG_OnAddExperience", ET_Hook, Param_Cell, Param_Cell, Param_CellByRef);
	// native bool:SMRPG_AddClientExperience(client, exp, bool:bHideNotice);
	CreateNative("SMRPG_AddClientExperience", Native_AddClientExperience);
	// native SMRPG_LevelToExperience(iLevel);
	CreateNative("SMRPG_LevelToExperience", Native_LevelToExperience);
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
	if(IsFakeClient(client) && GetConVarBool(g_hCVBotMaxlevel))
	{
		if((GetClientLevel(client) + iLevelIncrease) > GetConVarInt(g_hCVBotMaxlevel))
		{
			DebugMsg("Bot %N has surpassed the maximum level of %d, resetting its stats", client, GetConVarInt(g_hCVBotMaxlevel));
			ResetStats(client);
			return;
		}
	}
	
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
	
	if(GetConVarBool(g_hCVAnnounceNewLvl))
		Client_PrintToChatAll(false, "%t", "Client level changed", client, GetClientLevel(client));
	
	if(!IsFakeClient(client))
	{
		EmitSoundToClient(client, "buttons/blip2.wav");
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

Stats_AddExperience(client, iExperience, bool:bHideNotice)
{
	IF_IGNORE_BOTS(client)
		return;
	
	SetClientExperience(client, GetClientExperience(client) + iExperience);
	
	new iExpRequired = Stats_LvlToExp(GetClientLevel(client));
	
	if(GetClientExperience(client) >= iExpRequired)
		Stats_PlayerNewLevel(client, Stats_CalcLvlInc(GetClientLevel(client), GetClientExperience(client)));
	
	if(!bHideNotice && GetConVarBool(g_hCVExpNotice))
		PrintHintText(client, "%t", "Experience Gained Hintbox", iExperience, GetClientExperience(client), Stats_LvlToExp(GetClientLevel(client)));
}

Stats_PlayerDamage(attacker, victim, Float:fDamage)
{
	if(!GetConVarBool(g_hCVEnable))
		return;
	
	// Ignore teamattack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iExp = RoundToCeil(fDamage * GetConVarFloat(g_hCVExpDamage));
	
	if(Stats_CallOnExperienceForward(attacker, ER_PlayerHurt, iExp) <= Plugin_Changed)
		Stats_AddExperience(attacker, iExp, true);
}

Stats_PlayerKill(attacker, victim)
{
	if(!GetConVarBool(g_hCVEnable))
		return;
	
	// Ignore teamattack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iExp = RoundToCeil(GetClientLevel(victim) * GetConVarFloat(g_hCVExpKill));
	new iExpMax = GetConVarInt(g_hCVExpKillMax);
	// Limit the possible experience to this.
	if(iExpMax > 0 && iExp > iExpMax)
		iExp = iExpMax;
	
	if(Stats_CallOnExperienceForward(attacker, ER_PlayerKill, iExp) <= Plugin_Changed)
		Stats_AddExperience(attacker, iExp, false);
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
			if(Stats_CallOnExperienceForward(i, ER_RoundEnd, iExperience) <= Plugin_Changed)
				Stats_AddExperience(i, iExperience, false);
		}
	}
}

Action:Stats_CallOnExperienceForward(client, ExperienceReason:reason, iExperience)
{
	new Action:result;
	Call_StartForward(g_hfwdOnAddExperience);
	Call_PushCell(client);
	Call_PushCell(reason);
	Call_PushCellRef(iExperience);
	Call_Finish(result);
	return result;
}

// native SMRPG_AddClientExperience(client, exp, bool:bHideNotice);
public Native_AddClientExperience(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
		return;
	}
	
	new iExperience = GetNativeCell(2);
	new bool:bHideNotice = bool:GetNativeCell(3);
	Stats_AddExperience(client, iExperience, bHideNotice);
}

public Native_LevelToExperience(Handle:plugin, numParams)
{
	new iLevel = GetNativeCell(1);
	return Stats_LvlToExp(iLevel);
}

/*	//////////////////////////////////////
	CRPG_RankManager
	////////////////////////////////////// */

UpdateClientRank(client)
{
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM %s WHERE level > '%d' OR (level = '%d' AND experience > '%d')", TBL_PLAYERS, GetClientLevel(client), GetClientLevel(client), GetClientExperience(client));
	SQL_TQuery(g_hDatabase, SQL_GetClientRank, sQuery, GetClientUserId(client));
}

GetClientRank(client)
{
	if(IsFakeClient(client))
		return -1;
	
	UpdateClientRank(client);
	return g_iCachedRank[client];
}

ClearClientRankCache(client)
{
	g_iCachedRank[client] = -1;
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
	
	SQL_FetchRow(hndl);
	
	g_iCachedRank[client] = SQL_FetchInt(hndl, 0) + 1; // +1 since the query returns the count, not the rank
}

UpdateRankCount()
{
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM %s", TBL_PLAYERS);
	SQL_TQuery(g_hDatabase, SQL_GetRankCount, sQuery);
}

GetRankCount()
{
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
	
	SQL_FetchRow(hndl);
	
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
	
	SendPanelToClient(hPanel, client, Panel_HandleTop10, MENU_TIME_FOREVER);
	CloseHandle(hPanel);
}

public Panel_HandleTop10(Handle:menu, MenuAction:action, param1, param2)
{
}