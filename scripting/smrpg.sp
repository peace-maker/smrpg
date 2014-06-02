#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <topmenus>
#include <smlib>
#include <smrpg>
#include <autoexecconfig>
#include <smrpg_sharedmaterials>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <smrpg_commandlist>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#define PLUGIN_VERSION "1.0"

new bool:g_bLateLoaded;
new Handle:g_hPlayerAutoSave;

// Convars
new Handle:g_hCVEnable;
new Handle:g_hCVBotEnable;
new Handle:g_hCVBotNeedHuman;
new Handle:g_hCVNeedEnemies;
new Handle:g_hCVEnemiesNotAFK;
new Handle:g_hCVDebug;
new Handle:g_hCVSaveData;
new Handle:g_hCVSaveInterval;
new Handle:g_hCVPlayerExpire;

new Handle:g_hCVBotMaxlevel;
new Handle:g_hCVBotMaxlevelReset;
new Handle:g_hCVPlayerMaxlevel;
new Handle:g_hCVPlayerMaxlevelReset;

new Handle:g_hCVBotKillPlayer;
new Handle:g_hCVPlayerKillBot;
new Handle:g_hCVBotKillBot;

new Handle:g_hCVAnnounceNewLvl;
new Handle:g_hCVAFKTime;

new Handle:g_hCVExpNotice;
new Handle:g_hCVExpMax;
new Handle:g_hCVExpStart;
new Handle:g_hCVExpInc;

new Handle:g_hCVExpDamage;
new Handle:g_hCVExpKill;
new Handle:g_hCVExpKillMax;

new Handle:g_hCVExpTeamwin;

new Handle:g_hCVLastExperienceCount;

new Handle:g_hCVCreditsInc;
new Handle:g_hCVCreditsStart;
new Handle:g_hCVSalePercent;
new Handle:g_hCVIgnoreLevelBarrier;
new Handle:g_hCVAllowPresentUpgradeUsage;
new Handle:g_hCVDisableLevelSelection;

new Handle:g_hCVShowUpgradePurchase;
new Handle:g_hCVShowMenuOnLevelDefault;
new Handle:g_hCVFadeOnLevelDefault;

new Handle:g_hCVFadeOnLevelColor;

#define IF_IGNORE_BOTS(%1) if(IsFakeClient(%1) && (!GetConVarBool(g_hCVBotEnable) || (GetConVarBool(g_hCVBotNeedHuman) && Client_GetCount(true, false) == 0)))

#include "smrpg/smrpg_upgrades.sp"
#include "smrpg/smrpg_database.sp"
#include "smrpg/smrpg_settings.sp"
#include "smrpg/smrpg_players.sp"
#include "smrpg/smrpg_stats.sp"
#include "smrpg/smrpg_menu.sp"
#include "smrpg/smrpg_admincommands.sp"
#include "smrpg/smrpg_adminmenu.sp"

public Plugin:myinfo = 
{
	name = "SM:RPG",
	author = "Jannik \"Peace-Maker\" Hartung, SeLfkiLL",
	description = "SM:RPG Mod",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("smrpg");
	g_bLateLoaded = late;
	
	MarkNativeAsOptional("SQL_SetCharset");
	// https://bugs.alliedmods.net/show_bug.cgi?id=6033
	MarkNativeAsOptional("DisplayTopMenuCategory");
	// https://bugs.alliedmods.net/show_bug.cgi?id=6034
	MarkNativeAsOptional("SetTopMenuTitleCaching");
	
	CreateNative("SMRPG_IsEnabled", Native_IsEnabled);
	CreateNative("SMRPG_IgnoreBots", Native_IgnoreBots);
	RegisterUpgradeNatives();
	RegisterPlayerNatives();
	RegisterStatsNatives();
	RegisterTopMenuNatives();
	RegisterSettingsNatives();
	RegisterDatabaseNatives();
}

public OnPluginStart()
{
	new Handle:hVersion = CreateConVar("smrpg_version", PLUGIN_VERSION, "SM:RPG version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != INVALID_HANDLE)
	{
		SetConVarString(hVersion, PLUGIN_VERSION);
		HookConVarChange(hVersion, ConVar_VersionChanged);
	}
	
	SMRPG_GC_CheckSharedMaterialsAndSounds();
	
	AutoExecConfig_SetFile("plugin.smrpg");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(INVALID_HANDLE);
	
	g_hCVEnable = AutoExecConfig_CreateConVar("smrpg_enable", "1", "If set to 1, SM:RPG is enabled, if 0, SM:RPG is disabled", 0, true, 0.0, true, 1.0);
	g_hCVBotEnable = AutoExecConfig_CreateConVar("smrpg_bot_enable", "1", "If set to 1, bots will be able to use the SM:RPG plugin", 0, true, 0.0, true, 1.0);
	g_hCVBotNeedHuman = AutoExecConfig_CreateConVar("smrpg_bot_need_human", "1", "Don't allow bots to gain experience while no human player is on the server?", 0, true, 0.0, true, 1.0);
	g_hCVNeedEnemies = AutoExecConfig_CreateConVar("smrpg_need_enemies", "1", "Don't give any experience if there is no enemy in the opposite team?", 0, true, 0.0, true, 1.0);
	g_hCVEnemiesNotAFK = AutoExecConfig_CreateConVar("smrpg_enemies_not_afk", "1", "Don't give any experience if all enemies are currently AFK?", 0, true, 0.0, true, 1.0);
	g_hCVDebug = AutoExecConfig_CreateConVar("smrpg_debug", "0", "Turns on debug mode for this plugin", 0, true, 0.0, true, 1.0);
	g_hCVSaveData = AutoExecConfig_CreateConVar("smrpg_save_data", "1", "If disabled, the database won't be updated (this means player data won't be saved!)", 0, true, 0.0, true, 1.0);
	g_hCVSaveInterval = AutoExecConfig_CreateConVar("smrpg_save_interval", "150", "Interval (in seconds) that player data is auto saved (0 = off)", 0, true, 0.0);
	g_hCVPlayerExpire = AutoExecConfig_CreateConVar("smrpg_player_expire", "30", "Sets how many days until an unused player account is deleted (0 = never)", 0, true, 0.0);
	
	g_hCVBotMaxlevel = AutoExecConfig_CreateConVar("smrpg_bot_maxlevel", "250", "The maximum level a bot can reach until its stats are reset (0 = infinite)", 0, true, 0.0);
	g_hCVBotMaxlevelReset = AutoExecConfig_CreateConVar("smrpg_bot_maxlevel_reset", "1", "Reset the bot to level 1, if the bot reaches the maxlevel for bots?", 0, true, 0.0, true, 1.0);
	g_hCVPlayerMaxlevel = AutoExecConfig_CreateConVar("smrpg_player_maxlevel", "0", "The maximum level a player can reach until he stops getting more experience. (0 = infinite)", 0, true, 0.0);
	g_hCVPlayerMaxlevelReset = AutoExecConfig_CreateConVar("smrpg_player_maxlevel_reset", "0", "Reset the player to level 1, if the player reaches the player maxlevel?", 0, true, 0.0, true, 1.0);
	
	g_hCVBotKillPlayer = AutoExecConfig_CreateConVar("smrpg_bot_kill_player", "1", "Bots earn experience for interacting with real players?", 0, true, 0.0, true, 1.0);
	g_hCVPlayerKillBot = AutoExecConfig_CreateConVar("smrpg_player_kill_bot", "1", "Real players earn experience for interacting with bots?", 0, true, 0.0, true, 1.0);
	g_hCVBotKillBot = AutoExecConfig_CreateConVar("smrpg_bot_kill_bot", "1", "Bots earn experience for interacting with bots?", 0, true, 0.0, true, 1.0);
	
	g_hCVAnnounceNewLvl = AutoExecConfig_CreateConVar("smrpg_announce_newlvl", "1", "Global announcement when a player reaches a new level (1 = enable, 0 = disable)", 0, true, 0.0, true, 1.0);
	g_hCVAFKTime = AutoExecConfig_CreateConVar("smrpg_afk_time", "30", "After how many seconds of idleing is the player flagged as AFK? (0 = off)", 0, true, 0.0);
	
	g_hCVExpNotice = AutoExecConfig_CreateConVar("smrpg_exp_notice", "1", "Sends notifications to players when they gain Experience", 0, true, 0.0, true, 1.0);
	g_hCVExpMax = AutoExecConfig_CreateConVar("smrpg_exp_max", "50000", "Maximum experience that will ever be required", 0, true, 0.0);
	g_hCVExpStart = AutoExecConfig_CreateConVar("smrpg_exp_start", "250", "Experience required for Level 1", 0, true, 0.0);
	g_hCVExpInc = AutoExecConfig_CreateConVar("smrpg_exp_inc", "50", "Increment experience required for each level (until smrpg_exp_max)", 0, true, 0.0);
	
	g_hCVExpDamage = AutoExecConfig_CreateConVar("smrpg_exp_damage", "1.0", "Experience for hurting an enemy multiplied by the damage done", 0, true, 0.0);
	g_hCVExpKill = AutoExecConfig_CreateConVar("smrpg_exp_kill", "15.0", "Experience for a kill multiplied by the victim's level", 0, true, 0.0);
	g_hCVExpKillMax = AutoExecConfig_CreateConVar("smrpg_exp_kill_max", "0.0", "Maximum experience a player can ever earn for killing someone. (0 = unlimited)", 0, true, 0.0);
	
	g_hCVExpTeamwin = AutoExecConfig_CreateConVar("smrpg_exp_teamwin", "0.15", "Experience multipled by the experience required and the team ratio given to a team for completing the objective", 0, true, 0.0);
	
	g_hCVLastExperienceCount = AutoExecConfig_CreateConVar("smrpg_lastexperience_count", "50", "How many times should we remember why each player got some experience in the recent past?", 0, true, 1.0);
	
	g_hCVCreditsInc = AutoExecConfig_CreateConVar("smrpg_credits_inc", "5", "Credits given to each new level", 0, true, 0.0);
	g_hCVCreditsStart = AutoExecConfig_CreateConVar("smrpg_credits_start", "0", "Starting credits for Level 1", 0, true, 0.0);
	g_hCVSalePercent = AutoExecConfig_CreateConVar("smrpg_sale_percent", "0.75", "Percentage of credits a player gets for selling an upgrade", 0, true, 0.0);
	g_hCVIgnoreLevelBarrier = AutoExecConfig_CreateConVar("smrpg_ignore_level_barrier", "0", "Ignore the hardcoded maxlevels for the upgrades and allow to set the maxlevel as high as you want. THIS MIGHT BE BAD!", 0, true, 0.0, true, 1.0);
	g_hCVAllowPresentUpgradeUsage = AutoExecConfig_CreateConVar("smrpg_allow_present_upgrade_usage", "0", "Allow players to use the upgrades they already have levels for, if they normally wouldn't have access to the upgrade due to the adminflags.\nThis allows admins to give upgrades to players they aren't able to buy themselves.", 0, true, 0.0, true, 1.0);
	g_hCVDisableLevelSelection = AutoExecConfig_CreateConVar("smrpg_disable_level_selection", "0", "Don't allow players to change the selected levels of their upgrades to a lower level than they already purchased?", 0, true, 0.0, true, 1.0);
	
	g_hCVShowUpgradePurchase = AutoExecConfig_CreateConVar("smrpg_show_upgrade_purchase_in_chat", "0", "Show a message to all in chat when a player buys an upgrade.", 0, true, 0.0, true, 1.0);
	g_hCVShowMenuOnLevelDefault = AutoExecConfig_CreateConVar("smrpg_show_menu_on_levelup", "0", "Show the rpg menu when a player levels up by default? Players can change it in their settings individually afterwards.", 0, true, 0.0, true, 1.0);
	g_hCVFadeOnLevelDefault = AutoExecConfig_CreateConVar("smrpg_fade_screen_on_levelup", "1", "Fade the screen golden when a player levels up by default? Players can change it in their settings individually afterwards.", 0, true, 0.0, true, 1.0);
	
	g_hCVFadeOnLevelColor = AutoExecConfig_CreateConVar("smrpg_fade_screen_on_levelup_color", "255 215 0 40", "RGBA color to fade the screen in for a short time after levelup. Default is a golden shine.", 0);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	HookConVarChange(g_hCVEnable, ConVar_EnableChanged);
	HookConVarChange(g_hCVSaveInterval, ConVar_SaveIntervalChanged);
	HookConVarChange(g_hCVLastExperienceCount, ConVar_LastExperienceCountChanged);
	
	RegConsoleCmd("rpgmenu", Cmd_RPGMenu, "Opens the rpg main menu");
	RegConsoleCmd("rpg", Cmd_RPGMenu, "Opens the rpg main menu");
	RegConsoleCmd("rpgrank", Cmd_RPGRank, "Shows your rank or the rank of the target person. rpgrank [name|steamid|#userid]");
	RegConsoleCmd("rpginfo", Cmd_RPGInfo, "Shows the purchased upgrades of the target person. rpginfo <name|steamid|#userid>");
	RegConsoleCmd("rpgtop10", Cmd_RPGTop10, "Show the SM:RPG top 10");
	RegConsoleCmd("rpgnext", Cmd_RPGNext, "Show the next few ranked players before you");
	RegConsoleCmd("rpgsession", Cmd_RPGSession, "Show your session stats");
	RegConsoleCmd("rpghelp", Cmd_RPGHelp, "Show the SM:RPG help menu");
	RegConsoleCmd("rpgexp", Cmd_RPGLatestExperience, "Show the latest experience you earned");
	
	RegisterAdminCommands();
	RegisterPlayerForwards();
	RegisterTopMenuForwards();
	RegisterStatsForwards();
	RegisterUpgradeForwards();
	RegisterSettingsForwards();
	
	InitSettings();
	InitUpgrades();
	InitDatabase();
	
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	
	HookEventEx("player_spawn", Event_OnPlayerSpawn);
	HookEventEx("player_death", Event_OnPlayerDeath);
	HookEventEx("round_end", Event_OnRoundEnd);
	HookEvent("player_say", Event_OnPlayerSay);
	HookEvent("player_disconnect", Event_OnPlayerDisconnect);
	
	if(g_bLateLoaded)
	{
		for(new i=1;i<=MaxClients;i++)
		{
			if(!IsClientConnected(i))
				continue;
			
			OnClientConnected(i);
			
			if(!IsClientInGame(i))
				continue;
			
			OnClientPutInServer(i);
			
			// Query info from db, when the connection is established.
		}
		
		if(LibraryExists("smrpg_commandlist"))
		{
			OnLibraryAdded("smrpg_commandlist");
		}
	}
	
	if(LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
	
	// See if the menu plugin is already ready
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}
}

/**
 * ConVar changes
 */
public ConVar_VersionChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	SetConVarString(convar, PLUGIN_VERSION);
}

public ConVar_SaveIntervalChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	ClearHandle(g_hPlayerAutoSave);
	g_hPlayerAutoSave = CreateTimer(GetConVarFloat(g_hCVSaveInterval), Timer_SavePlayers, _, TIMER_REPEAT);
}

public ConVar_EnableChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(GetConVarBool(convar) || !GetConVarBool(g_hCVSaveData))
		return;
	
	UnhookConVarChange(convar, ConVar_EnableChanged);
	SetConVarBool(convar, true);
	SaveAllPlayers();
	SetConVarBool(convar, false);
	HookConVarChange(convar, ConVar_EnableChanged);
	PrintToServer("SM:RPG smrpg_enable: SM:RPG data has been saved");
}

/**
 * Public global forwards
 */
public OnAllPluginsLoaded()
{
	RegisterTopMenu();
	InitMenu();
}

public OnPluginEnd()
{
	if(LibraryExists("smrpg_commandlist"))
	{
		SMRPG_UnregisterCommand("rpgmenu");
		SMRPG_UnregisterCommand("rpgrank");
		SMRPG_UnregisterCommand("rpginfo");
		SMRPG_UnregisterCommand("rpgtop10");
		SMRPG_UnregisterCommand("rpgnext");
		SMRPG_UnregisterCommand("rpgsession");
		SMRPG_UnregisterCommand("rpghelp");
		SMRPG_UnregisterCommand("rpgexp");
	}
}

public OnConfigsExecuted()
{
	decl String:sPath[PLATFORM_MAX_PATH];
	decl String:sError[256];
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/rpgmenu_sorting.txt");
	
	if (!LoadTopMenuConfig(GetRPGTopMenu(), sPath, sError, sizeof(sError)))
	{
		LogError("Could not load rpg menu config (file \"%s\": %s)", sPath, sError);
	}
	
	ClearHandle(g_hPlayerAutoSave);
	g_hPlayerAutoSave = CreateTimer(GetConVarFloat(g_hCVSaveInterval), Timer_SavePlayers, _, TIMER_REPEAT);
}

public OnLibraryAdded(const String:name[])
{
	if(StrEqual(name, "smrpg_commandlist"))
	{
		// Register the default rpg commands
		SMRPG_RegisterCommand("rpgmenu", CommandList_DefaultTranslations);
		SMRPG_RegisterCommand("rpgrank", CommandList_DefaultTranslations);
		SMRPG_RegisterCommand("rpginfo", CommandList_DefaultTranslations);
		SMRPG_RegisterCommand("rpgtop10", CommandList_DefaultTranslations);
		SMRPG_RegisterCommand("rpgnext", CommandList_DefaultTranslations);
		SMRPG_RegisterCommand("rpgsession", CommandList_DefaultTranslations);
		SMRPG_RegisterCommand("rpghelp", CommandList_DefaultTranslations);
	}
	else if(StrEqual(name, "clientprefs"))
	{
		SetCookieMenuItem(ClientPrefsMenu_HandleItem, 0, "SM:RPG > Settings");
	}
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "adminmenu"))
	{
		g_hTopMenu = INVALID_HANDLE;
		g_TopMenuCategory = INVALID_TOPMENUOBJECT;
	}
}

public OnMapStart()
{
	SMRPG_GC_PrecacheSound("SoundLevelup");
	
	// Clean up our database..
	DatabaseMaid();
	
	StartAFKChecker();
	StartSessionMenuUpdater();
}

public OnMapEnd()
{
	SaveAllPlayers();
}

public OnClientConnected(client)
{
	InitPlayer(client);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
	
	if(!GetConVarBool(g_hCVEnable))
		return;
	
	Client_PrintToChat(client, false, "%t", "Inform about plugin", PLUGIN_VERSION);
	Client_PrintToChat(client, false, "%t", "Advertise rpgmenu command");
}

public OnClientAuthorized(client, const String:auth[])
{
	if(IsFakeClient(client))
		return;
	
	AddPlayer(client, auth);
}

public OnClientDisconnect(client)
{
	ResetPlayerMenu(client);
	ResetAdminMenu(client);
	SaveData(client);
	ClearClientRankCache(client);
	RemovePlayer(client);
	ResetAFKPlayer(client);
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2])
{
	// Reset his afk timer when he uses a weapon.
	if(IsClientInGame(client) && IsPlayerAlive(client) && buttons & (IN_ATTACK|IN_ATTACK2))
		g_PlayerAFKInfo[client][AFK_startTime] = 0;
	return Plugin_Continue;
}

public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;
	
	Stats_PlayerDamage(attacker, victim, damage);
}

/**
 * Event handlers
 */

public Event_OnPlayerSpawn(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(client <= 0)
		return;
	
	// Save the spawn time so we don't count the new spawn position as if the player moved himself
	g_PlayerAFKInfo[client][AFK_spawnTime] = GetTime();
}
 
public Event_OnPlayerDeath(Handle:event, const String:error[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(victim <= 0)
		return;
	
	// Save when the player died.
	g_PlayerAFKInfo[victim][AFK_deathTime] = GetTime();
	
	if(attacker <= 0)
		return;
	
	Stats_PlayerKill(attacker, victim);
}

public Event_OnRoundEnd(Handle:event, const String:error[], bool:dontBroadcast)
{
	Stats_WinningTeam(GetEventInt(event, "winner"));
}

public Event_OnPlayerSay(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	decl String:sText[256];
	GetEventString(event, "text", sText, sizeof(sText));
	
	if(StrEqual(sText, "rpgmenu", false) || StrEqual(sText, "rpg", false))
		DisplayMainMenu(client);
	else if(StrContains(sText, "rpgrank", false) == 0)
	{
		TrimString(sText);
		if(!sText[7])
		{
			PrintRankToChat(client, -1);
		}
		else
		{
			new iTarget = FindTarget(client, sText[8], !GetConVarBool(g_hCVBotEnable), false);
			if(iTarget == -1)
				return;
			PrintRankToChat(iTarget, -1);
		}
	}
	else if(StrContains(sText, "rpginfo", false) == 0)
	{
		TrimString(sText);
		if(!sText[7])
		{
			// See if he's spectating someone and show the upgrades of the target.
			if(IsClientObserver(client) || !IsPlayerAlive(client))
			{
				new Obs_Mode:iObsMode = Client_GetObserverMode(client);
				if(iObsMode == OBS_MODE_IN_EYE || iObsMode == OBS_MODE_CHASE)
				{
					new iTarget = Client_GetObserverTarget(client);
					if(iTarget > 0)
					{
						DisplayOtherUpgradesMenu(client, iTarget);
						return;
					}
				}
			}
			// Just display the normal upgrades menu, if self targetting with no target specified.
			DisplayUpgradesMenu(client);
		}
		else
		{
			new iTarget = FindTarget(client, sText[8], false, false);
			if(iTarget == -1)
				return;
			DisplayOtherUpgradesMenu(client, iTarget);
		}
	}
	else if(StrEqual(sText, "rpgtop10", false))
		DisplayTop10Menu(client);
	else if(StrEqual(sText, "rpgnext", false))
		DisplayNextPlayersInRanking(client);
	else if(StrEqual(sText, "rpgsession", false))
		DisplaySessionStatsMenu(client);
	else if(StrEqual(sText, "rpghelp", false))
		DisplayHelpMenu(client);
	else if(StrEqual(sText, "rpgexp", false))
		DisplaySessionLastExperienceMenu(client, true);
}

// That player fully disconnected, not just reconnected after a mapchange.
public Event_OnPlayerDisconnect(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	ResetPlayerSessionStats(client);
}

/**
 * Public command handlers
 */

public Action:Cmd_RPGMenu(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayMainMenu(client);
	
	return Plugin_Handled;
}

public Action:Cmd_RPGRank(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	decl String:sText[256];
	GetCmdArgString(sText, sizeof(sText));
	TrimString(sText);
	
	if(!sText[0])
	{
		PrintRankToChat(client, -1);
	}
	else
	{
		new iTarget = FindTarget(client, sText, !GetConVarBool(g_hCVBotEnable), false);
		if(iTarget == -1)
			return Plugin_Handled;
		PrintRankToChat(iTarget, -1);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_RPGInfo(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	decl String:sText[256];
	GetCmdArgString(sText, sizeof(sText));
	TrimString(sText);
	
	if(!sText[0])
	{
		// See if he's spectating someone and show the upgrades of the target.
		if(IsClientObserver(client) || !IsPlayerAlive(client))
		{
			new Obs_Mode:iObsMode = Client_GetObserverMode(client);
			if(iObsMode == OBS_MODE_IN_EYE || iObsMode == OBS_MODE_CHASE)
			{
				new iTarget = Client_GetObserverTarget(client);
				if(iTarget > 0)
				{
					DisplayOtherUpgradesMenu(client, iTarget);
					return Plugin_Handled;
				}
			}
		}
		// Just display the normal upgrades menu, if self targetting with no target specified.
		DisplayUpgradesMenu(client);
	}
	else
	{
		new iTarget = FindTarget(client, sText, false, false);
		if(iTarget == -1)
			return Plugin_Handled;
		DisplayOtherUpgradesMenu(client, iTarget);
	}
	
	return Plugin_Handled;
}

public Action:Cmd_RPGTop10(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayTop10Menu(client);
	
	return Plugin_Handled;
}

public Action:Cmd_RPGNext(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayNextPlayersInRanking(client);
	
	return Plugin_Handled;
}

public Action:Cmd_RPGSession(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplaySessionStatsMenu(client);
	
	return Plugin_Handled;
}

public Action:Cmd_RPGHelp(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayHelpMenu(client);
	
	return Plugin_Handled;
}

public Action:Cmd_RPGLatestExperience(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplaySessionLastExperienceMenu(client, true);
	
	return Plugin_Handled;
}

/**
 * Timer callbacks
 */
public Action:Timer_SavePlayers(Handle:timer, any:data)
{
	if(!GetConVarBool(g_hCVEnable) || !GetConVarBool(g_hCVSaveData) || !GetConVarBool(g_hCVSaveInterval))
		return Plugin_Continue;
	
	SaveAllPlayers();
	
	return Plugin_Continue;
}

/**
 * Natives
 */
public Native_IsEnabled(Handle:plugin, numParams)
{
	return GetConVarBool(g_hCVEnable);
}

public Native_IgnoreBots(Handle:plugin, numParams)
{
	return !GetConVarBool(g_hCVBotEnable);
}

/**
 * Translation callback for SM:RPG Command List plugin
 */
public Action:CommandList_DefaultTranslations(client, const String:command[], CommandTranslationType:type, String:translation[], maxlen)
{
	if(StrEqual(command, "rpgmenu"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpgmenu short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpgmenu desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpgmenu advert", client);
		}
	}
	else if(StrEqual(command, "rpgrank"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpgrank short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpgrank desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpgrank advert", client);
		}
	}
	else if(StrEqual(command, "rpginfo"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpginfo short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpginfo desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpginfo advert", client);
		}
	}
	else if(StrEqual(command, "rpgtop10"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpgtop10 short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpgtop10 desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpgtop10 advert", client);
		}
	}
	else if(StrEqual(command, "rpgnext"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpgnext short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpgnext desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpgnext advert", client);
		}
	}
	else if(StrEqual(command, "rpgsession"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpgsession short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpgsession desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpgsession advert", client);
		}
	}
	else if(StrEqual(command, "rpghelp"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpghelp short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpghelp desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpghelp advert", client);
		}
	}
	else if(StrEqual(command, "rpgexp"))
	{
		switch(type)
		{
			case CommandTranslationType_ShortDescription:
				Format(translation, maxlen, "%T", "rpgexp short desc", client);
			case CommandTranslationType_Description:
				Format(translation, maxlen, "%T", "rpgexp desc", client);
			case CommandTranslationType_Advert:
				Format(translation, maxlen, "%T", "rpgexp advert", client, GetConVarInt(g_hCVLastExperienceCount));
		}
	}
	return Plugin_Continue;
}

/**
 * Clientprefs !settings menu item
 */
public ClientPrefsMenu_HandleItem(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
{
	switch(action)
	{
		case CookieMenuAction_DisplayOption:
		{
			Format(buffer, maxlen, "SM:RPG > %T", "Settings", client);
		}
		case CookieMenuAction_SelectOption:
		{
			DisplaySettingsMenu(client);
		}
	}
}

/**
 * Helpers
 */
// IsValidHandle() is deprecated, let's do a real check then...
// By Thraaawn
stock bool:IsValidPlugin(Handle:hPlugin) {
	if(hPlugin == INVALID_HANDLE)
		return false;

	new Handle:hIterator = GetPluginIterator();

	new bool:bPluginExists = false;
	while(MorePlugins(hIterator)) {
		new Handle:hLoadedPlugin = ReadPlugin(hIterator);
		if(hLoadedPlugin == hPlugin) {
			bPluginExists = true;
			break;
		}
	}

	CloseHandle(hIterator);

	return bPluginExists;
}

stock DebugMsg(String:format[], any:...)
{
	if(!GetConVarBool(g_hCVDebug))
		return;
	
	decl String:sBuffer[192];
	SetGlobalTransTarget(LANG_SERVER);
	VFormat(sBuffer, sizeof(sBuffer), format, 2);
	PrintToServer(sBuffer);
}