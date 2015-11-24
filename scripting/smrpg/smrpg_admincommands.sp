#pragma semicolon 1
#include <sourcemod>

RegisterAdminCommands()
{
	RegAdminCmd("smrpg_player", Cmd_PlayerInfo, ADMFLAG_ROOT, "Get info about a certain player. Usage smrpg_player <player name | userid | steamid>", "smrpg");
	RegAdminCmd("smrpg_resetstats", Cmd_ResetStats, ADMFLAG_ROOT, "Reset a player's Level, Credits, Experience, and Upgrades (this cannot be undone!). Usage smrpg_resetstats <player name | userid | steamid>", "smrpg");
	RegAdminCmd("smrpg_resetexp", Cmd_ResetExp, ADMFLAG_ROOT, "Reset a player's Experience. Usage smrpg_resetexp <player name | userid | steamid>", "smrpg");
	RegAdminCmd("smrpg_setlvl", Cmd_SetLvl, ADMFLAG_ROOT, "Set a player's Level. Usage smrpg_setlvl <player name | userid | steamid> <new level>", "smrpg");
	RegAdminCmd("smrpg_addlvl", Cmd_AddLvl, ADMFLAG_ROOT, "Add Level(s) to a player's current Level. Usage smrpg_addlvl <player name | userid | steamid> <levels>", "smrpg");
	RegAdminCmd("smrpg_setexp", Cmd_SetExp, ADMFLAG_ROOT, "Set a player's Experience. Usage smrpg_setexp <player name | userid | steamid> <new exp>", "smrpg");
	RegAdminCmd("smrpg_addexp", Cmd_AddExp, ADMFLAG_ROOT, "Give a player Experience. Usage smrpg_addexp <player name | userid | steamid> <exp>", "smrpg");
	RegAdminCmd("smrpg_setcredits", Cmd_SetCredits, ADMFLAG_ROOT, "Set a player's Credits. Usage smrpg_setcredits <player name | userid | steamid> <new credits>", "smrpg");
	RegAdminCmd("smrpg_addcredits", Cmd_AddCredits, ADMFLAG_ROOT, "Add to player's Credits. Usage smrpg_addcredits <player name | userid | steamid> <credits>", "smrpg");
	RegAdminCmd("smrpg_listupgrades", Cmd_ListUpgrades, ADMFLAG_ROOT, "List all available upgrades.", "smrpg");
	RegAdminCmd("smrpg_setupgradelvl", Cmd_SetUpgradeLvl, ADMFLAG_ROOT, "Set a player's Upgrade Level. Usage smrpg_setupgradelvl <player name | userid | steamid> <upgrade> <level|max>", "smrpg");
	RegAdminCmd("smrpg_giveupgrade", Cmd_GiveUpgrade, ADMFLAG_ROOT, "Give a player an Upgrade (increment). Usage smrpg_giveupgrade <player name | userid | steamid> <upgrade>", "smrpg");
	RegAdminCmd("smrpg_giveall", Cmd_GiveAll, ADMFLAG_ROOT, "Give a player all the Upgrades available. Usage smrpg_giveall <player name | userid | steamid>", "smrpg");
	RegAdminCmd("smrpg_takeupgrade", Cmd_TakeUpgrade, ADMFLAG_ROOT, "Take an Upgrade from a player (decrement). Usage smrpg_takeupgrade <player name | userid | steamid> <upgrade>", "smrpg");
	RegAdminCmd("smrpg_buyupgrade", Cmd_BuyUpgrade, ADMFLAG_ROOT, "Force a player to buy an Upgrade. Usage smrpg_buyupgrade <player name | userid | steamid> <upgrade>", "smrpg");
	RegAdminCmd("smrpg_sellupgrade", Cmd_SellUpgrade, ADMFLAG_ROOT, "Force a player to sell an Upgrade (full refund). Usage smrpg_sellupgrade <player name | userid | steamid> <upgrade>", "smrpg");
	RegAdminCmd("smrpg_sellall", Cmd_SellAll, ADMFLAG_ROOT, "Force a player to sell all their Upgrades (full refund). Usage smrpg_sellall <player name | userid | steamid>", "smrpg");
	
	RegAdminCmd("smrpg_reload_weaponexperience", Cmd_ReloadWeaponExperience, ADMFLAG_CONFIG, "Reload the weapon_experience.cfg config for individual experience rates per weapon.", "smrpg");
	
	RegAdminCmd("smrpg_db_delplayer", Cmd_DBDelPlayer, ADMFLAG_ROOT, "Delete a player entry from the database (this cannot be undone!). Usage: smrpg_db_delplayer <full name | player db id | steamid>", "smrpg");
	RegAdminCmd("smrpg_db_mass_sell", Cmd_DBMassSell, ADMFLAG_ROOT, "Force everyone in the database (and playing) to sell a specific upgrade. Usage: smrpg_db_mass_sell <upgrade>", "smrpg");
	RegAdminCmd("smrpg_db_write", Cmd_DBWrite, ADMFLAG_ROOT, "Write current player data to the database", "smrpg");
	RegAdminCmd("smrpg_db_stats", Cmd_DBStats, ADMFLAG_ROOT, "Show general stats about player base and upgrade usage.", "smrpg");
	
	RegAdminCmd("smrpg_debug_playerlist", Cmd_DebugPlayerlist, ADMFLAG_ROOT, "List all RPG players", "smrpg");
}

public Action:Cmd_PlayerInfo(client, args)
{
	decl String:sText[256];
	GetCmdArgString(sText, sizeof(sText));
	TrimString(sText);
	new iTarget = FindTarget(client, sText, false, false);
	if(iTarget == -1)
		return Plugin_Handled;
	
	ReplyToCommand(client, "SM:RPG: ----------");
	ReplyToCommand(client, "SM:RPG %N: ", iTarget);
	
	new playerInfo[PlayerInfo];
	GetClientRPGInfo(iTarget, playerInfo);
	
	new String:sSteamID[64];
	GetClientAuthId(iTarget, AuthId_Engine, sSteamID, sizeof(sSteamID));
	ReplyToCommand(client, "SM:RPG Info: Index: %d, UserID: %d, SteamID: %s, Database ID: %d, AFK: %d", iTarget, GetClientUserId(iTarget), sSteamID, playerInfo[PLR_dbId], IsClientAFK(iTarget));
	
	ReplyToCommand(client, "SM:RPG Stats: Level: %d, Experience: %d/%d, Credits: %d, Rank: %d/%d", GetClientLevel(iTarget), GetClientExperience(iTarget), Stats_LvlToExp(GetClientLevel(iTarget)), GetClientCredits(iTarget), GetClientRank(iTarget), GetRankCount());
	
	ReplyToCommand(client, "SM:RPG Upgrades: ");
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	decl String:sPermission[30];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		if(!IsValidUpgrade(upgrade))
			continue;
		
		sPermission[0] = 0;
		if(upgrade[UPGR_adminFlag] > 0)
		{
			GetAdminFlagStringFromBits(upgrade[UPGR_adminFlag], sPermission, sizeof(sPermission));
			Format(sPermission, sizeof(sPermission), " (admflag: %s)", sPermission);
		}
		
		if(!HasAccessToUpgrade(iTarget, upgrade))
			Format(sPermission, sizeof(sPermission), " NO ACCESS:");
		else if(upgrade[UPGR_adminFlag] > 0)
			Format(sPermission, sizeof(sPermission), " OK:");
		ReplyToCommand(client, "SM:RPG - %s%s Level %d (Selected %d)", upgrade[UPGR_name], sPermission, GetClientPurchasedUpgradeLevel(iTarget, i), GetClientSelectedUpgradeLevel(iTarget, i));
	}
	ReplyToCommand(client, "SM:RPG: ----------");
	
	return Plugin_Handled;
}

public Action:Cmd_ResetStats(client, args)
{
	decl String:sTarget[256];
	GetCmdArgString(sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	for(new i=0;i<iTargetCount;i++)
	{
		ResetStats(iTargetList[i]);
		SetPlayerLastReset(iTargetList[i], GetTime());
		
		LogAction(client, iTargetList[i], "%L permanently reset all stats of player %L.", client, iTargetList[i]);
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L permanently reset all stats for %T (%d players).", client, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG resetstats: Stats have been permanently reset for %t (%d players).", sTargetName, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG resetstats: %N's stats have been permanently reset.", iTargetList[0]);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_ResetExp(client, args)
{
	decl String:sTarget[256];
	GetCmdArgString(sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iFailedTargets[MAXPLAYERS];
	new iFailedCount;
	for(new i=0;i<iTargetCount;i++)
	{
		if(SetClientExperience(iTargetList[i], 0))
		{
			LogAction(client, iTargetList[i], "%L reset experience of player %L.", client, iTargetList[i]);
		}
		else
		{
			iFailedTargets[iFailedCount++] = iTargetList[i];
		}
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L reset experience for %T (%d players).", client, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG resetexp: Experience has been reset for %t (%d players).", sTargetName, iTargetCount);
		if(iFailedCount > 0)
		{
			decl String:sFailedList[1024];
			Format(sFailedList, sizeof(sFailedList), "SM:RPG resetexp: Can't reset experience for %d client(s) (blocked by other plugin): ", iFailedCount);
			for(new i=0;i<iFailedCount;i++)
			{
				Format(sFailedList, sizeof(sFailedList), "%s%s %N", sFailedList, (i>0?",":""), iFailedTargets[i]);
			}
			ReplyToCommand(client, "%s.", sFailedList);
		}
	}
	else
	{
		if(iFailedCount == 0)
			ReplyToCommand(client, "SM:RPG resetexp: %N's experience has been reset.", iTargetList[0]);
		else
			ReplyToCommand(client, "SM:RPG resetexp: Can't reset %N's experience. Some other plugin doesn't want this to happen.", iTargetList[0]);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_SetLvl(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_setlvl <player name | #userid | steamid> <new level>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sLevel[16];
	GetCmdArg(2, sLevel, sizeof(sLevel));
	new iLevel = StringToInt(sLevel);
	
	if(iLevel < 1)
	{
		ReplyToCommand(client, "SM:RPG setlvl: Minimum level is 1!");
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldLevel;
	new iFailedTargets[MAXPLAYERS], iFailedOldLevels[MAXPLAYERS];
	new iFailedCount;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldLevel = GetClientLevel(iTargetList[i]);
		// Don't touch players who already are on the desired level.
		if(iLastOldLevel == iLevel)
			continue;
		
		// Do a proper level up
		if(iLevel > iLastOldLevel)
		{
			Stats_PlayerNewLevel(iTargetList[i], iLevel-iLastOldLevel);
		}
		// Decrease level manually, don't touch the credits/items
		else
		{
			SetClientLevel(iTargetList[i], iLevel);
			SetClientExperience(iTargetList[i], 0);
			
			if(GetConVarBool(g_hCVAnnounceNewLvl))
				Client_PrintToChatAll(false, "%t", "Client level changed", iTargetList[i], GetClientLevel(iTargetList[i]));
		}
		
		LogAction(client, iTargetList[i], "%L set level of %L from %d to %d.", client, iTargetList[i], iLastOldLevel, GetClientLevel(iTargetList[i]));
		
		// Didn't change to the desired new level completely?
		if(GetClientLevel(iTargetList[i]) != iLevel)
		{
			iFailedOldLevels[iFailedCount] = iLastOldLevel;
			iFailedTargets[iFailedCount++] = iTargetList[i];
		}
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L set level of %T (%d players) to %d.", client, sTargetName, LANG_SERVER, iTargetCount, iLevel);
		ReplyToCommand(client, "SM:RPG setlvl: Level has been set to %d for %t (%d players).", iLevel, sTargetName, iTargetCount);
		if(iFailedCount > 0)
		{
			decl String:sFailedList[1024];
			Format(sFailedList, sizeof(sFailedList), "SM:RPG setlvl: %d clients failed: ", iFailedCount);
			for(new i=0;i<iFailedCount;i++)
			{
				Format(sFailedList, sizeof(sFailedList), "%s%s%N (level: %d, old: %d)", sFailedList, (i>0?", ":""), iFailedTargets[i], GetClientLevel(iFailedTargets[0]), iFailedOldLevels[0]);
			}
			ReplyToCommand(client, "%s.", sFailedList);
		}
	}
	else
	{
		ReplyToCommand(client, "SM:RPG setlvl: %N has been set to level %d (previously level %d)", iTargetList[0], GetClientLevel(iTargetList[0]), iLastOldLevel);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_AddLvl(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_addlvl <player name | #userid | steamid> <levels>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sLevel[16];
	GetCmdArg(2, sLevel, sizeof(sLevel));
	new iLevelIncrease = StringToInt(sLevel);
	
	if(iLevelIncrease < 1)
	{
		ReplyToCommand(client, "SM:RPG addlvl: You have to add at least 1 level!");
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldLevel;
	new iFailedTargets[MAXPLAYERS], iFailedOldLevels[MAXPLAYERS];
	new iFailedCount;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldLevel = GetClientLevel(iTargetList[i]);
		
		// Do a proper level up
		Stats_PlayerNewLevel(iTargetList[i], iLevelIncrease);

		LogAction(client, iTargetList[i], "%L added max. %d levels to %L. He leveled up from level %d to %d.", client, iLevelIncrease, iTargetList[i], iLastOldLevel, GetClientLevel(iTargetList[i]));
		
		// Didn't change to the desired new level completely?
		if(GetClientLevel(iTargetList[i]) != iLastOldLevel+iLevelIncrease)
		{
			iFailedOldLevels[iFailedCount] = iLastOldLevel;
			iFailedTargets[iFailedCount++] = iTargetList[i];
		}
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L added %d levels to %T (%d players).", client, iLevelIncrease, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG addlvl: Added %d levels to %t (%d players).", iLevelIncrease, sTargetName, iTargetCount);
		if(iFailedCount > 0)
		{
			decl String:sFailedList[1024];
			Format(sFailedList, sizeof(sFailedList), "SM:RPG addlvl: %d clients failed: ", iFailedCount);
			for(new i=0;i<iFailedCount;i++)
			{
				Format(sFailedList, sizeof(sFailedList), "%s%s%N (level: %d, old: %d)", sFailedList, (i>0?", ":""), iFailedTargets[i], GetClientLevel(iFailedTargets[0]), iFailedOldLevels[0]);
			}
			ReplyToCommand(client, "%s.", sFailedList);
		}
	}
	else
	{
		ReplyToCommand(client, "SM:RPG addlvl: %N has been set to level %d (previously level %d)", iTargetList[0], GetClientLevel(iTargetList[0]), iLastOldLevel);
	}

	return Plugin_Handled;
}

public Action:Cmd_SetExp(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_setexp <player name | #userid | steamid> <new exp>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sExperience[16];
	GetCmdArg(2, sExperience, sizeof(sExperience));
	new iExperience = StringToInt(sExperience);
	
	if(iExperience < 0)
	{
		ReplyToCommand(client, "SM:RPG setexp: Experience must be >= 0!");
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldLevel, iLastOldExperience;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldLevel = GetClientLevel(iTargetList[i]);
		iLastOldExperience = GetClientExperience(iTargetList[i]);
		
		// Do a proper level up if enough experience.
		if(iExperience > iLastOldExperience)
		{
			new iNewExperience = iExperience-iLastOldExperience;
			Stats_AddExperience(iTargetList[i], iNewExperience, ExperienceReason_Admin, false, -1);
		}
		else
			SetClientExperience(iTargetList[i], iExperience);
		
		LogAction(client, iTargetList[i], "%L set experience of %L to %d. He is now level %d and has %d/%d experience (previously level %d with %d/%d experience)", client, iTargetList[i], iExperience, GetClientLevel(iTargetList[i]), GetClientExperience(iTargetList[i]), Stats_LvlToExp(GetClientLevel(iTargetList[i])), iLastOldLevel, iLastOldExperience, Stats_LvlToExp(iLastOldLevel));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L set experience of %T (%d players) to %d.", client, sTargetName, LANG_SERVER, iTargetCount, iExperience);
		ReplyToCommand(client, "SM:RPG setexp: Experience has been set to %d for %t (%d players).", iExperience, sTargetName, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG setexp: %N is now level %d and has %d/%d experience (previously level %d with %d/%d experience)", iTargetList[0], GetClientLevel(iTargetList[0]), GetClientExperience(iTargetList[0]), Stats_LvlToExp(GetClientLevel(iTargetList[0])), iLastOldLevel, iLastOldExperience, Stats_LvlToExp(iLastOldLevel));
	}

	return Plugin_Handled;
}

public Action:Cmd_AddExp(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_addexp <player name | #userid | steamid> <exp>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sExperienceIncrease[16];
	GetCmdArg(2, sExperienceIncrease, sizeof(sExperienceIncrease));
	new iExperienceIncrease = StringToInt(sExperienceIncrease);
	
	if(iExperienceIncrease < 1)
	{
		ReplyToCommand(client, "SM:RPG addexp: You have to add at least 1 experience!");
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldLevel, iLastOldExperience;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldLevel = GetClientLevel(iTargetList[i]);
		iLastOldExperience = GetClientExperience(iTargetList[i]);
		
		// Do a proper level up if enough experience.
		Stats_AddExperience(iTargetList[i], iExperienceIncrease, ExperienceReason_Admin, false, -1);
		
		LogAction(client, iTargetList[i], "%L added %d experience to %L. He is now level %d and has %d/%d experience (previously level %d with %d/%d experience)", client, iExperienceIncrease, iTargetList[i], GetClientLevel(iTargetList[i]), GetClientExperience(iTargetList[i]), Stats_LvlToExp(GetClientLevel(iTargetList[i])), iLastOldLevel, iLastOldExperience, Stats_LvlToExp(iLastOldLevel));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L added %d experience to %T (%d players).", client, iExperienceIncrease, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG addexp: %d experience has been added for %t (%d players).", iExperienceIncrease, sTargetName, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG addexp: %N is now level %d and has %d/%d experience (previously level %d with %d/%d experience)", iTargetList[0], GetClientLevel(iTargetList[0]), GetClientExperience(iTargetList[0]), Stats_LvlToExp(GetClientLevel(iTargetList[0])), iLastOldLevel, iLastOldExperience, Stats_LvlToExp(iLastOldLevel));
	}
	
	return Plugin_Handled;
}

public Action:Cmd_SetCredits(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_setcredits <player name | #userid | steamid> <new credits>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sCredits[16];
	GetCmdArg(2, sCredits, sizeof(sCredits));
	new iCredits = StringToInt(sCredits);
	
	if(iCredits < 0)
	{
		ReplyToCommand(client, "SM:RPG setcredits: Credits have to be >= 0!");
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldCredits;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldCredits = GetClientCredits(iTargetList[i]);
		
		SetClientCredits(iTargetList[i], iCredits);
		
		LogAction(client, iTargetList[i], "%L set credits of %L from %d to %d.", client, iTargetList[i], iLastOldCredits, GetClientCredits(iTargetList[i]));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L set credits of %T to %d (%d players).", client, sTargetName, LANG_SERVER, iCredits, iTargetCount);
		ReplyToCommand(client, "SM:RPG setcredits: Set credits of %t to %d (%d players).", sTargetName, iCredits, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG setcredits: %N now has %d credits (previously had %d credits)", iTargetList[0], GetClientCredits(iTargetList[0]), iLastOldCredits);
	}

	return Plugin_Handled;
}

public Action:Cmd_AddCredits(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_addcredits <player name | #userid | steamid> <credits>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sCredits[16];
	GetCmdArg(2, sCredits, sizeof(sCredits));
	new iCredits = StringToInt(sCredits);
	
	if(iCredits < 1)
	{
		ReplyToCommand(client, "SM:RPG addcredits: You have to add at least 1 credit!");
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldCredits;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldCredits = GetClientCredits(iTargetList[i]);
		
		SetClientCredits(iTargetList[i], iLastOldCredits+iCredits);
		
		LogAction(client, iTargetList[i], "%L added %d credits to %L. The credits changed from %d to %d.", client, iCredits, iTargetList[i], iLastOldCredits, GetClientCredits(iTargetList[i]));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L added %d credits to %T (%d players).", client, iCredits, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG addcredits: Added %d credits to %t (%d players).", iCredits, sTargetName, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG addcredits: %N got %d credits and now has %d credits (previously had %d credits)", iTargetList[0], iCredits, GetClientCredits(iTargetList[0]), iLastOldCredits);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_ListUpgrades(client, args)
{
	new iSize = GetUpgradeCount();
	ReplyToCommand(client, "There are %d upgrades registered.", iSize);
	new upgrade[InternalUpgradeInfo];
	new iUnavailableCount, String:sPluginFile[64], String:sPermissions[30];
	for(new i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		if(!IsValidUpgrade(upgrade))
		{
			iUnavailableCount++;
			continue;
		}
		
		GetPluginFilename(upgrade[UPGR_plugin], sPluginFile, sizeof(sPluginFile));
		GetAdminFlagStringFromBits(upgrade[UPGR_adminFlag], sPermissions, sizeof(sPermissions));
		
		ReplyToCommand(client, "%d. [%s] %s (%s). Maxlevel: %d, maxlevel barrier: %d, start cost: %d, increasing cost: %d, adminflag: %s, plugin: %s", i-iUnavailableCount, (upgrade[UPGR_enabled] ? "ON" : "OFF"), upgrade[UPGR_name], upgrade[UPGR_shortName], upgrade[UPGR_maxLevel], upgrade[UPGR_maxLevelBarrier], upgrade[UPGR_startCost], upgrade[UPGR_incCost], sPermissions, sPluginFile);
	}
	if(iUnavailableCount > 0)
	{
		ReplyToCommand(client, "----------------");
		ReplyToCommand(client, "%d upgrades are unavailable. The plugin providing that upgrade might have been unloaded.", iUnavailableCount);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_SetUpgradeLvl(client, args)
{
	if(args < 3)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_setupgradelvl <player name | #userid | steamid> <upgrade shortname> <level|max>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
	GetCmdArg(2, sUpgrade, sizeof(sUpgrade));
	TrimString(sUpgrade);
	StripQuotes(sUpgrade);
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sUpgrade, upgrade) || !IsValidUpgrade(upgrade))
	{
		ReplyToCommand(client, "SM:RPG: There is no upgrade with name \"%s\".", sUpgrade);
		return Plugin_Handled;
	}
	
	decl String:sLevel[16];
	GetCmdArg(3, sLevel, sizeof(sLevel));
	StripQuotes(sLevel);
	
	// Make sure we're not over the maxlevel
	new iLevel = StringToInt(sLevel);
	if(StrEqual(sLevel, "max", false) || iLevel > upgrade[UPGR_maxLevel])
		iLevel = upgrade[UPGR_maxLevel];
	
	if(iLevel < 0)
	{
		ReplyToCommand(client, "SM:RPG setupgradelvl: Upgrade levels start at 0!");
		return Plugin_Handled;
	}
	
	new iIndex = upgrade[UPGR_index];
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldUpgradeLevel;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldUpgradeLevel = GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex);
		
		// Item level increased
		if(iLastOldUpgradeLevel < iLevel)
		{
			while(GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex) < iLevel)
			{
				// If some plugin doesn't want any more upgrade levels, stop trying.
				if(!GiveClientUpgrade(iTargetList[i], iIndex))
					break;
			}
		}
		// Item level decreased..
		else
		{
			while(GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex) > iLevel)
			{
				// If some plugin doesn't want any less upgrade levels, stop trying.
				if(!TakeClientUpgrade(iTargetList[i], iIndex))
					break;
			}
		}
		
		LogAction(client, iTargetList[i], "%L set %L level of upgrade %s from %d to %d at no charge.", client, iTargetList[i], upgrade[UPGR_name], iLastOldUpgradeLevel, GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L set level of upgrade %s to %d for %T (%d players).", client, upgrade[UPGR_name], iLevel, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG setupgradelvl: Set level upgrade %s to %d for %t (%d players).", upgrade[UPGR_name], iLevel, sTargetName, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG setupgradelvl: %N now has %s level %d (previously level %d)", iTargetList[0], upgrade[UPGR_name], GetClientPurchasedUpgradeLevel(iTargetList[0], iIndex), iLastOldUpgradeLevel);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_GiveUpgrade(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_giveupgrade <player name | #userid | steamid> <upgrade shortname>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
	GetCmdArg(2, sUpgrade, sizeof(sUpgrade));
	TrimString(sUpgrade);
	StripQuotes(sUpgrade);
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sUpgrade, upgrade) || !IsValidUpgrade(upgrade))
	{
		ReplyToCommand(client, "SM:RPG giveupgrade: There is no upgrade with name \"%s\".", sUpgrade);
		return Plugin_Handled;
	}
	
	new iIndex = upgrade[UPGR_index];
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iLastOldUpgradeLevel;
	new iCountAlreadyMaxed;
	new iFailedTargets[MAXPLAYERS], iFailedCount;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldUpgradeLevel = GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex);
		
		if(iLastOldUpgradeLevel >= upgrade[UPGR_maxLevel])
		{
			iCountAlreadyMaxed++;
			continue;
		}
		
		if(!GiveClientUpgrade(iTargetList[i], iIndex))
		{
			iFailedTargets[iFailedCount++] = iTargetList[i];
			continue;
		}
		
		LogAction(client, iTargetList[i], "%L gave %L a level of upgrade %s at no charge. It changed from level %d to %d.", client, iTargetList[i], upgrade[UPGR_name], iLastOldUpgradeLevel, GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L gave a level of upgrade %s to %T (%d players).", client, upgrade[UPGR_name], sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG giveupgrade: Gave a level of upgrade %s to %t (%d players).", upgrade[UPGR_name], sTargetName, iTargetCount);
		if(iCountAlreadyMaxed > 0)
			ReplyToCommand(client, "SM:RPG giveupgrade: %d players already had it on max.", iCountAlreadyMaxed);
		if(iFailedCount > 0)
		{
			decl String:sFailedList[1024];
			Format(sFailedList, sizeof(sFailedList), "SM:RPG giveupgrade: %d clients failed: ", iFailedCount);
			for(new i=0;i<iFailedCount;i++)
			{
				Format(sFailedList, sizeof(sFailedList), "%s%s%N ", sFailedList, (i>0?", ":""), iFailedTargets[i]);
			}
			ReplyToCommand(client, "%s.", sFailedList);
		}
	}
	else
	{
		if(iCountAlreadyMaxed > 0)
			ReplyToCommand(client, "SM:RPG giveupgrade: %N has the maximum level for %s (level %d)", iTargetList[0], upgrade[UPGR_name], iLastOldUpgradeLevel);
		else if(iFailedCount > 0)
			ReplyToCommand(client, "SM:RPG giveupgrade: Tried to give %N a level for upgrade %s, but it refused to level up.", iTargetList[0], upgrade[UPGR_name]);
		else
			ReplyToCommand(client, "SM:RPG giveupgrade: %N now has %s level %d (previously level %d)", iTargetList[0], upgrade[UPGR_name], GetClientPurchasedUpgradeLevel(iTargetList[0], iIndex), iLastOldUpgradeLevel);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_GiveAll(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_giveall <player name | #userid | steamid>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	for(new i=0;i<iTargetCount;i++)
	{
		// Run through all upgrades
		for(new u=0;u<iSize;u++)
		{
			GetUpgradeByIndex(u, upgrade);
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				continue;
			
			// TODO: Obey adminflags and bot restrictions!
			SetClientPurchasedUpgradeLevel(iTargetList[i], u, upgrade[UPGR_maxLevel]);
			SetClientSelectedUpgradeLevel(iTargetList[i], u, upgrade[UPGR_maxLevel]);
		}
		
		LogAction(client, iTargetList[i], "%L set all upgrades of %L to the maximal level at no charge.", client, iTargetList[i]);
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L gave all upgrades to %T (%d players) at no charge.", client, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG giveall: Gave all upgrades to %t (%d players) at no charge.", sTargetName, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG giveall: %N now has all Upgrades on max.", iTargetList[0]);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_TakeUpgrade(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_takeupgrade <player name | #userid | steamid> <upgrade shortname>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
	GetCmdArg(2, sUpgrade, sizeof(sUpgrade));
	TrimString(sUpgrade);
	StripQuotes(sUpgrade);
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sUpgrade, upgrade) || !IsValidUpgrade(upgrade))
	{
		ReplyToCommand(client, "SM:RPG takeupgrade: There is no upgrade with shortname \"%s\".", sUpgrade);
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iIndex = upgrade[UPGR_index];
	
	new iLastOldUpgradeLevel;
	new iCountDontOwn;
	new iFailedTargets[MAXPLAYERS], iFailedCount;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldUpgradeLevel = GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex);
		
		// Client doesn't have that upgrade. Can't take it away.
		if(iLastOldUpgradeLevel <= 0)
		{
			iCountDontOwn++;
			continue;
		}
		
		if(!TakeClientUpgrade(iTargetList[i], iIndex))
		{
			iFailedTargets[iFailedCount++] = iTargetList[i];
			continue;
		}
		
		LogAction(client, iTargetList[i], "%L took a level of upgrade %s from %L with no refund. Changed upgrade level from %d to %d.", client, upgrade[UPGR_name], iTargetList[i], iLastOldUpgradeLevel, GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L took a level of upgrade %s from %T (%d players).", client, upgrade[UPGR_name], sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG takeupgrade: Took a level of upgrade %s from %t (%d players).", upgrade[UPGR_name], sTargetName, iTargetCount);
		if(iCountDontOwn > 0)
			ReplyToCommand(client, "SM:RPG takeupgrade: %d players didn't own the upgrade at all.", iCountDontOwn);
		if(iFailedCount > 0)
		{
			decl String:sFailedList[1024];
			Format(sFailedList, sizeof(sFailedList), "SM:RPG takeupgrade: %d clients failed: ", iFailedCount);
			for(new i=0;i<iFailedCount;i++)
			{
				Format(sFailedList, sizeof(sFailedList), "%s%s%N ", sFailedList, (i>0?", ":""), iFailedTargets[i]);
			}
			ReplyToCommand(client, "%s.", sFailedList);
		}
	}
	else
	{
		if(iCountDontOwn > 0)
			ReplyToCommand(client, "SM:RPG takeupgrade: %N doesn't have upgrade %s.", iTargetList[0], upgrade[UPGR_name]);
		else if(iFailedCount > 0)
			ReplyToCommand(client, "SM:RPG takeupgrade: Tried to take a level of upgrade %s from %N, but it refused to level down.", upgrade[UPGR_name], iTargetList[0]);
		else
			ReplyToCommand(client, "SM:RPG takeupgrade: %N now has %s level %d (previously level %d)", iTargetList[0], upgrade[UPGR_name], GetClientPurchasedUpgradeLevel(iTargetList[0], iIndex), iLastOldUpgradeLevel);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_BuyUpgrade(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_buyupgrade <player name | #userid | steamid> <upgrade shortname>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
	GetCmdArg(2, sUpgrade, sizeof(sUpgrade));
	TrimString(sUpgrade);
	StripQuotes(sUpgrade);
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sUpgrade, upgrade) || !IsValidUpgrade(upgrade))
	{
		ReplyToCommand(client, "SM:RPG buyupgrade: There is no upgrade with shortname \"%s\".", sUpgrade);
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iIndex = upgrade[UPGR_index];
	
	new iLastOldUpgradeLevel;
	new iCountAlreadyMaxed;
	new iPoorTargets[MAXPLAYERS], iPoorCount;
	new iFailedTargets[MAXPLAYERS], iFailedCount;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldUpgradeLevel = GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex);
		
		// Already has the maximum level, don't need to buy another one.
		if(iLastOldUpgradeLevel >= upgrade[UPGR_maxLevel])
		{
			iCountAlreadyMaxed++;
			continue;
		}
		
		// Doesn't have enough credits.
		new iCost = GetUpgradeCost(iIndex, iLastOldUpgradeLevel);
		if(iCost > GetClientCredits(iTargetList[i]))
		{
			iPoorTargets[iPoorCount++] = iTargetList[i];
			continue;
		}
		
		// Try to buy the upgrade.
		if(!BuyClientUpgrade(iTargetList[i], iIndex))
		{
			iFailedTargets[iFailedCount++] = iTargetList[i];
			continue;
		}
		
		LogAction(client, iTargetList[i], "%L forced %L to buy a level of upgrade %s. The upgrade level changed from %d to %d", client, iTargetList[i], upgrade[UPGR_name], iLastOldUpgradeLevel, GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L forced %T (%d players) to buy a level of upgrade %s.", client, sTargetName, LANG_SERVER, iTargetCount, upgrade[UPGR_name]);
		ReplyToCommand(client, "SM:RPG buyupgrade: Made %t (%d players) buy a level of upgrade %s.", sTargetName, iTargetCount, upgrade[UPGR_name]);
		if(iCountAlreadyMaxed > 0)
			ReplyToCommand(client, "SM:RPG buyupgrade: %d players already had the upgrade at the maximal level.", iCountAlreadyMaxed);
		if(iPoorCount > 0)
		{
			decl String:sPoorList[1024];
			Format(sPoorList, sizeof(sPoorList), "SM:RPG buyupgrade: %d clients don't have enough credits: ", iPoorCount);
			for(new i=0;i<iPoorCount;i++)
			{
				Format(sPoorList, sizeof(sPoorList), "%s%s%N ", sPoorList, (i>0?", ":""), iPoorTargets[i]);
			}
			ReplyToCommand(client, "%s.", sPoorList);
		}
		if(iFailedCount > 0)
		{
			decl String:sFailedList[1024];
			Format(sFailedList, sizeof(sFailedList), "SM:RPG buyupgrade: %d clients failed: ", iFailedCount);
			for(new i=0;i<iFailedCount;i++)
			{
				Format(sFailedList, sizeof(sFailedList), "%s%s%N ", sFailedList, (i>0?", ":""), iFailedTargets[i]);
			}
			ReplyToCommand(client, "%s.", sFailedList);
		}
	}
	else
	{
		if(iCountAlreadyMaxed > 0)
			ReplyToCommand(client, "SM:RPG buyupgrade: %N has the maximum level for %s (level %d).", iTargetList[0], upgrade[UPGR_name], iLastOldUpgradeLevel);
		else if(iPoorCount > 0)
			ReplyToCommand(client, "SM:RPG buyupgrade: %N doesn't have enough credits to purchase %s (%d/%d).", iTargetList[0], upgrade[UPGR_name], GetClientCredits(iTargetList[0]), GetUpgradeCost(iIndex, iLastOldUpgradeLevel));
		else if(iFailedCount > 0)
			ReplyToCommand(client, "SM:RPG buyupgrade: Tried to make %N buy a level of upgrade %s, but it refused to level up.", iTargetList[0], upgrade[UPGR_name]);
		else
			ReplyToCommand(client, "SM:RPG buyupgrade: %N now has %s level %d (previously level %d).", iTargetList[0], upgrade[UPGR_name], GetClientPurchasedUpgradeLevel(iTargetList[0], iIndex), iLastOldUpgradeLevel);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_SellUpgrade(client, args)
{
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_sellupgrade <player name | #userid | steamid> <upgrade shortname>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
	GetCmdArg(2, sUpgrade, sizeof(sUpgrade));
	TrimString(sUpgrade);
	StripQuotes(sUpgrade);
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sUpgrade, upgrade) || !IsValidUpgrade(upgrade))
	{
		ReplyToCommand(client, "SM:RPG sellupgrade: There is no upgrade with name \"%s\".", sUpgrade);
		return Plugin_Handled;
	}
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iIndex = upgrade[UPGR_index];
	
	new iLastOldUpgradeLevel;
	new iCountDontOwn;
	new iFailedTargets[MAXPLAYERS], iFailedCount;
	for(new i=0;i<iTargetCount;i++)
	{
		iLastOldUpgradeLevel = GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex);
		
		// Client doesn't have that upgrade. Can't take it away.
		if(iLastOldUpgradeLevel <= 0)
		{
			iCountDontOwn++;
			continue;
		}
		
		if(!TakeClientUpgrade(iTargetList[i], iIndex))
		{
			iFailedTargets[iFailedCount++] = iTargetList[i];
			continue;
		}
		
		// Full refund!
		new iUpgradeCosts = GetUpgradeCost(iIndex, iLastOldUpgradeLevel);
		SetClientCredits(iTargetList[i], GetClientCredits(iTargetList[i]) + iUpgradeCosts);
		
		LogAction(client, iTargetList[i], "%L forced %L to sell a level of upgrade %s with full refund of the costs. The upgrade level changed from %d to %d and he received %d credits.", client, iTargetList[i], upgrade[UPGR_name], iLastOldUpgradeLevel, GetClientPurchasedUpgradeLevel(iTargetList[i], iIndex), iUpgradeCosts);
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L forced %T (%d players) to sell a level of upgrade %s with full refund.", client, sTargetName, LANG_SERVER, iTargetCount, upgrade[UPGR_name]);
		ReplyToCommand(client, "SM:RPG sellupgrade: Forced %t (%d players) to sell a level of upgrade %s with full refund.", sTargetName, iTargetCount, upgrade[UPGR_name]);
		if(iCountDontOwn > 0)
			ReplyToCommand(client, "SM:RPG sellupgrade: %d players didn't own the upgrade at all.", iCountDontOwn);
		if(iFailedCount > 0)
		{
			decl String:sFailedList[1024];
			Format(sFailedList, sizeof(sFailedList), "SM:RPG sellupgrade: %d clients failed: ", iFailedCount);
			for(new i=0;i<iFailedCount;i++)
			{
				Format(sFailedList, sizeof(sFailedList), "%s%s%N ", sFailedList, (i>0?", ":""), iFailedTargets[i]);
			}
			ReplyToCommand(client, "%s.", sFailedList);
		}
	}
	else
	{
		if(iCountDontOwn > 0)
			ReplyToCommand(client, "SM:RPG sellupgrade: %N doesn't have upgrade %s.", iTargetList[0], upgrade[UPGR_name]);
		else if(iFailedCount > 0)
			ReplyToCommand(client, "SM:RPG sellupgrade: Tried to force %N to sell a level of upgrade %s with full refund, but it refused to level down.", iTargetList[0], upgrade[UPGR_name]);
		else
			ReplyToCommand(client, "SM:RPG sellupgrade: %N sold one level of upgrade %s with full refund, is now on level %d (previously level %d) and received %d credits.", iTargetList[0], upgrade[UPGR_name], GetClientPurchasedUpgradeLevel(iTargetList[0], iIndex), iLastOldUpgradeLevel, GetUpgradeCost(iIndex, iLastOldUpgradeLevel));
	}
	
	return Plugin_Handled;
}

public Action:Cmd_SellAll(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_sellall <player name | #userid | steamid>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[256];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	TrimString(sTarget);
	
	decl String:sTargetName[MAX_TARGET_LENGTH];
	new iTargetList[MAXPLAYERS], iTargetCount;
	new bool:tn_is_ml;
	if((iTargetCount = ProcessTargetString(sTarget,
							client, 
							iTargetList,
							sizeof(iTargetList),
							0,
							sTargetName,
							sizeof(sTargetName),
							tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	new iSize = GetUpgradeCount();
	new upgrade[InternalUpgradeInfo];
	new iLastCreditsReturned;
	for(new i=0;i<iTargetCount;i++)
	{
		// Run through all upgrades
		for(new u=0;u<iSize;u++)
		{
			GetUpgradeByIndex(u, upgrade);
			if(!IsValidUpgrade(upgrade) || !upgrade[UPGR_enabled])
				continue;
			
			while(GetClientPurchasedUpgradeLevel(iTargetList[i], u) > 0)
			{
				if(!TakeClientUpgrade(iTargetList[i], u))
					break;
				// Full refund.
				iLastCreditsReturned += GetUpgradeCost(u, GetClientPurchasedUpgradeLevel(iTargetList[i], u)+1);
				SetClientCredits(iTargetList[i], GetClientCredits(iTargetList[i]) + GetUpgradeCost(u, GetClientPurchasedUpgradeLevel(iTargetList[i], u)+1));
			}
		}
		
		LogAction(client, iTargetList[i], "%L forced %L to sell all enabled upgrades with full refund of the costs for each level. He got %d credits and now has %d.", client, iTargetList[i], iLastCreditsReturned, GetClientCredits(iTargetList[i]));
	}
	
	if(tn_is_ml)
	{
		LogAction(client, -1, "%L sold all enabled upgrades of %T (%d players) with full refund for each level.", client, sTargetName, LANG_SERVER, iTargetCount);
		ReplyToCommand(client, "SM:RPG sellall: Forced %t (%d players) to sell all enabled upgrades with full refund for each level.", sTargetName, iTargetCount);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG sellall: %N has sold all enabled upgrades with full refund for each level, got %d credits and now has %d credits.", iTargetList[0], iLastCreditsReturned, GetClientCredits(iTargetList[0]));
	}
	
	return Plugin_Handled;
}

public Action:Cmd_DBDelPlayer(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_db_delplayer <full name | player db id | steamid>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[64];
	GetCmdArgString(sTarget, sizeof(sTarget));
	TrimString(sTarget);
	StripQuotes(sTarget);
	
	decl String:sQuery[128], iPlayerID;
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, client);
	WritePackString(hPack, sTarget);
	
	// Match as steamid
	new iAccountId = GetAccountIdFromSteamId(sTarget);
	if(iAccountId != -1)
	{
		new iTarget = FindClientBySteamID(sTarget);
		if(iTarget != -1)
			RemovePlayer(iTarget);
		
		WritePackCell(hPack, iTarget);
		Format(sQuery, sizeof(sQuery), "SELECT player_id, name FROM %s WHERE steamid = %d", TBL_PLAYERS, iAccountId);
		SQL_TQuery(g_hDatabase, SQL_CheckDeletePlayer, sQuery, hPack);
	}
	// Match as playerid
	else if(StringToIntEx(sTarget, iPlayerID) && iPlayerID > 0)
	{
		new iTarget = GetClientByPlayerID(iPlayerID);
		if(iTarget != -1)
			RemovePlayer(iTarget);
		
		WritePackCell(hPack, iTarget);
		Format(sQuery, sizeof(sQuery), "SELECT player_id, name FROM %s WHERE player_id = %d", TBL_PLAYERS, iPlayerID);
		SQL_TQuery(g_hDatabase, SQL_CheckDeletePlayer, sQuery, hPack);
	}
	// Match as name
	else
	{
		new iTarget = FindClientByExactName(sTarget);
		if(iTarget != -1)
			RemovePlayer(iTarget);
		
		WritePackCell(hPack, iTarget);
		Format(sQuery, sizeof(sQuery), "SELECT player_id, name FROM %s WHERE name = '%s'", TBL_PLAYERS, sTarget);
		SQL_TQuery(g_hDatabase, SQL_CheckDeletePlayer, sQuery, hPack);
	}
	return Plugin_Handled;
}

public Action:Cmd_DBMassSell(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "SM:RPG: Usage: smrpg_db_mass_sell <upgrade shortname>");
		return Plugin_Handled;
	}
	
	// TODO: check database for column instead of only currently loaded upgrades?
	decl String:sUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
	GetCmdArg(1, sUpgrade, sizeof(sUpgrade));
	TrimString(sUpgrade);
	StripQuotes(sUpgrade);
	new upgrade[InternalUpgradeInfo];
	if(!GetUpgradeByShortname(sUpgrade, upgrade) || !IsValidUpgrade(upgrade))
	{
		ReplyToCommand(client, "SM:RPG: There is no upgrade with name \"%s\" loaded.", sUpgrade);
		return Plugin_Handled;
	}
	
	new iIndex = upgrade[UPGR_index];
	
	// Handle players ingame
	new iOldLevel;
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i) || !IsClientAuthorized(i))
			continue;
		
		iOldLevel = GetClientPurchasedUpgradeLevel(i, iIndex);
		if(iOldLevel <= 0)
			continue;
		
		while(iOldLevel > 0)
		{
			if(!TakeClientUpgrade(i, iIndex))
				break;
			SetClientCredits(i, GetClientCredits(i) + GetUpgradeCost(iIndex, iOldLevel--));
		}
	}
	
	// Update all other players in the database
	new Handle:hData = CreateDataPack();
	WritePackCell(hData, client);
	WritePackCell(hData, iIndex);
	
	decl String:sQuery[128];
	Format(sQuery, sizeof(sQuery), "SELECT player_id, purchasedlevel FROM %s WHERE upgrade_id = %d AND purchasedlevel > 0", TBL_PLAYERUPGRADES, upgrade[UPGR_databaseId]);
	SQL_TQuery(g_hDatabase, SQL_MassDeleteItem, sQuery, hData);
	
	return Plugin_Handled;
}

public Action:Cmd_ReloadWeaponExperience(client, args)
{
	if(ReadWeaponExperienceConfig())
		ReplyToCommand(client, "SM:RPG > The weapon experience config has been reloaded.");
	else
		ReplyToCommand(client, "SM:RPG > Failure reading weapon experience config file in sourcemod/configs/smrpg/weapon_experience.cfg.");
	
	return Plugin_Handled;
}

public Action:Cmd_DebugPlayerlist(client, args)
{
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		ReplyToCommand(client, "Player: %N, UserID: %d, Level: %d, Experience: %d/%d, AFK: %d", i, GetClientUserId(i), GetClientLevel(i), GetClientExperience(i), Stats_LvlToExp(GetClientLevel(i)), IsClientAFK(i));
	}
	return Plugin_Handled;
}

public Action:Cmd_DBWrite(client, args)
{
	SaveAllPlayers();
	LogAction(client, -1, "%L saved all player data to the database.", client);
	ReplyToCommand(client, "SM:RPG db_write: All player data has been saved to the database.");
	return Plugin_Handled;
}

public Action:Cmd_DBStats(client, args)
{
	decl String:sQuery[512];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) AS total, (SELECT COUNT(*) FROM %s WHERE lastseen > %d) AS recent, AVG(level) FROM %s", TBL_PLAYERS, GetTime()-432000, TBL_PLAYERS);
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, client?GetClientSerial(client):0);
	WritePackCell(hPack, _:GetCmdReplySource());
	SQL_TQuery(g_hDatabase, SQL_PrintPlayerStats, sQuery, hPack);
	return Plugin_Handled;
}

/**
 * SQL callbacks
 */
public SQL_CheckDeletePlayer(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new client = ReadPackCell(data);
	new String:sTarget[64];
	ReadPackString(data, sTarget, sizeof(sTarget));
	new iTarget = ReadPackCell(data);
	CloseHandle(data);
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error while trying to find player for deletion (%s)", error);
		if(iTarget != -1)
			LogAction(client, iTarget, "%L tried to delete player %L from the database using search phrase \"%s\", but the select query failed. The stats were reset ingame though.", client, iTarget, sTarget);
		return;
	}
	
	if(!SQL_GetRowCount(hndl) || !SQL_FetchRow(hndl))
	{
		if(client == 0 || IsClientInGame(client))
		{
			if(iTarget != -1)
				LogAction(client, iTarget, "%L tried to delete player %L from the database using search phrase \"%s\", but there was no matching entry. The stats were reset ingame though.", client, iTarget, sTarget);
			ReplyToCommand(client, "SM:RPG db_delplayer: Unable to find the specified player in the database.");
		}
		return;
	}
	
	new iPlayerId = SQL_FetchInt(hndl, 0);
	if(GetConVarBool(g_hCVSaveData))
	{
		decl String:sQuery[128];
		new Transaction:hTransaction = SQL_CreateTransaction();
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = %d", TBL_PLAYERUPGRADES, iPlayerId);
		SQL_AddQuery(hTransaction, sQuery);
		Format(sQuery, sizeof(sQuery), "DELETE FROM %s WHERE player_id = %d", TBL_PLAYERS, iPlayerId);
		SQL_AddQuery(hTransaction, sQuery);
		SQL_ExecuteTransaction(g_hDatabase, hTransaction, _, SQLTxn_LogFailure);
		
		if(iTarget != -1)
			g_iPlayerInfo[iTarget][PLR_dbId] = -1;
		
		decl String:sName[64];
		SQL_FetchString(hndl, 1, sName, sizeof(sName));
		if(client == 0 || IsClientInGame(client))
		{
			if(iTarget != -1)
				LogAction(client, iTarget, "%L triggered deletion of %L. Player \"%s\" has been deleted from the database and his current ingame stats were reset. (search phrase: %s)", client, iTarget, sName, sTarget);
			else
				LogAction(client, -1, "%L triggered deletion of player \"%s\" from the database. (search phrase: %s)", client, sName, sTarget);
			ReplyToCommand(client, "SM:RPG db_delplayer: Player '%s' has been deleted from the database.", sName);
		}
	}
	else
	{
		if(client == 0 || IsClientInGame(client))
		{
			if(iTarget != -1)
				LogAction(client, iTarget, "%L tried to delete player %L from the database using search phrase \"%s\", but data saving is disabled (smrpg_save_data 0). The stats were reset ingame though.", client, iTarget, sTarget);
			ReplyToCommand(client, "SM:RPG db_delplayer: Notice: smrpg_save_data is set to '0', command had no effect.");
		}
	}
	
	
}

public SQL_MassDeleteItem(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new client = ReadPackCell(data);
	new iIndex = ReadPackCell(data);
	CloseHandle(data);
	
	new upgrade[InternalUpgradeInfo];
	GetUpgradeByIndex(iIndex, upgrade);
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogAction(client, -1, "%L tried to mass sell upgrade \"%s\", but the select query failed. It might have been reset on some players ingame though!", client, upgrade[UPGR_name]);
		LogError("Error during mass deletion of item (%s)", error);
		return;
	}
	
	if(SQL_GetRowCount(hndl) == 0)
	{
		if(client == 0 || IsClientInGame(client))
		{
			LogAction(client, -1, "%L tried to mass sell upgrade \"%s\", but nobody has the upgrade purchased at any level.", client, upgrade[UPGR_name]);
			ReplyToCommand(client, "SM:RPG db_mass_sell: Nobody has the Upgrade '%s' purchased at any level.", upgrade[UPGR_name]);
		}
		return;
	}
	
	if(GetConVarBool(g_hCVSaveData))
	{
		// Give players full refund for their upgrades.
		new iOldLevel, iAddCredits, iPlayerID;
		decl String:sQuery[128];
		
		// Update all players at once instead of firing lots of single update queries.
		new Transaction:hTransaction = SQL_CreateTransaction();
		
		while(SQL_MoreRows(hndl))
		{
			if(!SQL_FetchRow(hndl))
				continue;
			
			iPlayerID = SQL_FetchInt(hndl, 0);
			
			// This player is currently ingame and we already handled him. Don't add credits twice.
			if(GetClientByPlayerID(iPlayerID) != -1)
				continue;
			
			iOldLevel = SQL_FetchInt(hndl, 1);
			if(iOldLevel < 0)
			{
				DebugMsg("Negative level for upgrade %s in database for player %d!", upgrade[UPGR_name], iPlayerID);
				iOldLevel = 0;
			}
			if(iOldLevel > upgrade[UPGR_maxLevel])
			{
				DebugMsg("Upgrade level higher than max level of upgrade %s for player %d!", upgrade[UPGR_name], iPlayerID);
				iOldLevel = upgrade[UPGR_maxLevel];
			}
			
			iAddCredits = 0;
			while(iOldLevel > 0)
				iAddCredits += GetUpgradeCost(iIndex, iOldLevel--);
			
			Format(sQuery, sizeof(sQuery), "UPDATE %s SET credits = (credits + %d) WHERE player_id = %d", TBL_PLAYERS, iAddCredits, iPlayerID);
			SQL_AddQuery(hTransaction, sQuery);
		}
		
		SQL_ExecuteTransaction(g_hDatabase, hTransaction, _, SQLTxn_LogFailure);
		
		// Reset all players to upgrade level 0
		Format(sQuery, sizeof(sQuery), "UPDATE %s SET purchasedlevel = 0, selectedlevel = 0 WHERE upgrade_id = %d", TBL_PLAYERUPGRADES, upgrade[UPGR_databaseId]);
		SQL_TQuery(g_hDatabase, SQL_DoNothing, sQuery);
		
		if(client == 0 || IsClientInGame(client))
		{
			LogAction(client, -1, "%L mass sold upgrade \"%s\" on all players with full costs refunded. %d players in the database have been refunded their credits.", client, upgrade[UPGR_name], SQL_GetRowCount(hndl));
			ReplyToCommand(client, "SM:RPG db_mass_sell: All (%d) players in the database with Upgrade '%s' have been refunded their credits", SQL_GetRowCount(hndl), upgrade[UPGR_name]);
		}
	}
	else
	{
		if(client == 0 || IsClientInGame(client))
		{
			LogAction(client, -1, "%L tried to mass sell upgrade \"%s\", but data saving is disabled (smrpg_save_data 0). It might have been reset on some players ingame though!", client, upgrade[UPGR_name]);
			ReplyToCommand(client, "SM:RPG db_mass_sell: Notice: smrpg_save_data is set to '0', command had no effect");
		}
	}
}

public SQL_PrintPlayerStats(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new client = GetClientFromSerial(ReadPackCell(data));
	new ReplySource:source = ReplySource:ReadPackCell(data);
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error getting player stats in smrpg_db_stats: %s", error);
		CloseHandle(data);
		return;
	}

	if(SQL_FetchRow(hndl))
	{
		new ReplySource:oldSource = SetCmdReplySource(source);
		new iPlayerCount = SQL_FetchInt(hndl, 0);
		new iRecentPlayers = SQL_FetchInt(hndl, 1);
		ReplyToCommand(client, "There are %d players in the database with an average level of %.2f. %d (%.2f%%) connected in the last 5 days.", iPlayerCount, SQL_FetchFloat(hndl, 2), iRecentPlayers, float(iRecentPlayers)/float(iPlayerCount)*100.0);
		SetCmdReplySource(oldSource);
	}
	
	decl String:sQuery[64];
	Format(sQuery, sizeof(sQuery), "SELECT upgrade_id, shortname FROM %s", TBL_UPGRADES);
	SQL_TQuery(g_hDatabase, SQL_PrintUpgradeStats, sQuery, data);
}

public SQL_PrintUpgradeStats(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new serial = ReadPackCell(data);
	new client = GetClientFromSerial(serial);
	new ReplySource:source = ReplySource:ReadPackCell(data);
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error getting upgrade names in smrpg_db_stats: %s", error);
		CloseHandle(data);
		return;
	}
	
	new ReplySource:oldSource = SetCmdReplySource(source);
	ReplyToCommand(client, "Listing %d registered upgrades:", SQL_GetRowCount(hndl)-1);
	ReplyToCommand(client, "%-15s%-8s%-10s%-8s", "Upgrade", "#bought", "AVG LVL", "Loaded");
	SetCmdReplySource(oldSource);

	decl String:sUpgradeName[MAX_UPGRADE_SHORTNAME_LENGTH];
	decl String:sQuery[512];
	new Handle:hPack;
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		SQL_FetchString(hndl, 1, sUpgradeName, sizeof(sUpgradeName));
		
		hPack = CreateDataPack();
		WritePackCell(hPack, serial);
		WritePackCell(hPack, _:source);
		WritePackString(hPack, sUpgradeName);
		
		Format(sQuery, sizeof(sQuery), "SELECT COUNT(*), AVG(purchasedlevel) FROM %s WHERE upgrade_id = %d AND purchasedlevel > 0", TBL_PLAYERUPGRADES, SQL_FetchInt(hndl, 0));
		SQL_TQuery(g_hDatabase, SQL_PrintUpgradeUsage, sQuery, hPack);
	}
	CloseHandle(data);
}

public SQL_PrintUpgradeUsage(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new client = GetClientFromSerial(ReadPackCell(data));
	new ReplySource:source = ReplySource:ReadPackCell(data);
	decl String:sUpgradeName[MAX_UPGRADE_SHORTNAME_LENGTH];
	ReadPackString(data, sUpgradeName, sizeof(sUpgradeName));
	CloseHandle(data);
	
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error getting upgrade stats in smrpg_db_stats: %s", error);
		return;
	}

	new upgrade[InternalUpgradeInfo];
	new ReplySource:oldSource = SetCmdReplySource(source);
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		ReplyToCommand(client, "%-15s%-8d%-10.2f%-8s", sUpgradeName, SQL_FetchInt(hndl, 0), SQL_FetchFloat(hndl, 1), (GetUpgradeByShortname(sUpgradeName, upgrade)?"Yes":"No"));
	}
	SetCmdReplySource(oldSource);
}

/**
 * Helpers
 */
/**
 * Converts a steamid to the accountid.
 */
stock GetAccountIdFromSteamId(String:sSteamID[])
{
	static Handle:hSteam2 = INVALID_HANDLE;
	static Handle:hSteam3 = INVALID_HANDLE;
	
	if (hSteam2 == INVALID_HANDLE)
		hSteam2 = CompileRegex("^STEAM_[0-9]:([0-9]):([0-9]+)$");
	if (hSteam3 == INVALID_HANDLE)
		hSteam3 = CompileRegex("^\\[U:[0-9]:([0-9]+)\\]$");
	
	new String:sBuffer[64];
	
	// Steam2 format?
	if (hSteam2 != INVALID_HANDLE && MatchRegex(hSteam2, sSteamID) == 3)
	{
		if(!GetRegexSubString(hSteam2, 1, sBuffer, sizeof(sBuffer)))
			return -1;
		
		new Y = StringToInt(sBuffer);
		if(!GetRegexSubString(hSteam2, 2, sBuffer, sizeof(sBuffer)))
			return -1;
		
		new Z = StringToInt(sBuffer);
		return Z*2 + Y;
	}
	
	// Steam3 format?
	if (hSteam3 != INVALID_HANDLE && MatchRegex(hSteam3, sSteamID) == 2)
	{
		if(!GetRegexSubString(hSteam3, 1, sBuffer, sizeof(sBuffer)))
			return -1;
		
		return StringToInt(sBuffer);
	}
	
	return -1;
}

stock FindClientBySteamID(const String:sSteamID[])
{
	decl String:sTemp[64];
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i))
		{
			// Check Steam2 format.
			if(GetClientAuthId(i, AuthId_Steam2, sTemp, sizeof(sTemp)) && StrEqual(sSteamID, sTemp))
				return i;
			
			// And Steam3 format.
			if(GetClientAuthId(i, AuthId_Steam3, sTemp, sizeof(sTemp)) && StrEqual(sSteamID, sTemp))
				return i;
		}
	}
	return -1;
}

stock FindClientByExactName(const String:sName[])
{
	decl String:sTemp[MAX_NAME_LENGTH];
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
		{
			GetClientName(i, sTemp, sizeof(sTemp));
			if(StrEqual(sName, sTemp))
				return i;
		}
	}
	return -1;
}

stock GetAdminFlagStringFromBits(flags, String:flagstring[], maxlen)
{
	new AdminFlag:iAdmFlags[AdminFlags_TOTAL];
	new iNumFlags = FlagBitsToArray(flags, iAdmFlags, AdminFlags_TOTAL);
	new iChar;
	flagstring[0] = 0;
	for(new f=0;f<iNumFlags;f++)
	{
		if(FindFlagChar(iAdmFlags[f], iChar))
			Format(flagstring, maxlen, "%s%c", flagstring, iChar);
	}
}