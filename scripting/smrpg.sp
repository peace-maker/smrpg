#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <topmenus>
#include <regex>
#include <smlib>
#include <smrpg>
#include <autoexecconfig>
#include <smrpg_sharedmaterials>

#pragma newdecls required
#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <smrpg_commandlist>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#define PLUGIN_VERSION "1.0"

bool g_bLateLoaded;
Handle g_hPlayerAutoSave;

Handle g_hfwdOnEnableStatusChanged;

// Convars
ConVar g_hCVEnable;
ConVar g_hCVFFA;
ConVar g_hCVBotEnable;
ConVar g_hCVBotSaveStats;
ConVar g_hCVBotNeedHuman;
ConVar g_hCVNeedEnemies;
ConVar g_hCVEnemiesNotAFK;
ConVar g_hCVDebug;
ConVar g_hCVSaveData;
ConVar g_hCVSaveInterval;
ConVar g_hCVPlayerExpire;
ConVar g_hCVAllowSelfReset;

ConVar g_hCVBotMaxlevel;
ConVar g_hCVBotMaxlevelReset;
ConVar g_hCVPlayerMaxlevel;
ConVar g_hCVPlayerMaxlevelReset;

ConVar g_hCVBotKillPlayer;
ConVar g_hCVPlayerKillBot;
ConVar g_hCVBotKillBot;

ConVar g_hCVAnnounceNewLvl;
ConVar g_hCVAFKTime;
ConVar g_hCVSpawnProtect;

ConVar g_hCVExpNotice;
ConVar g_hCVExpMax;
ConVar g_hCVExpStart;
ConVar g_hCVExpInc;

ConVar g_hCVExpDamage;
ConVar g_hCVExpKill;
ConVar g_hCVExpKillBonus;
ConVar g_hCVExpKillMax;

ConVar g_hCVExpTeamwin;

ConVar g_hCVLastExperienceCount;

ConVar g_hCVLevelStart;
ConVar g_hCVLevelStartGiveCredits;
ConVar g_hCVUpgradeStartLevelsFree;
ConVar g_hCVCreditsInc;
ConVar g_hCVCreditsStart;
ConVar g_hCVSalePercent;
ConVar g_hCVIgnoreLevelBarrier;
ConVar g_hCVAllowPresentUpgradeUsage;
ConVar g_hCVDisableLevelSelection;
ConVar g_hCVShowMaxLevelInMenu;

#define SHOW_TEAMLOCK_NONE 0
#define SHOW_TEAMLOCK_BOUGHT 1
#define SHOW_TEAMLOCK_ALL 2
ConVar g_hCVShowUpgradesOfOtherTeam;
ConVar g_hCVBuyUpgradesOfOtherTeam;
ConVar g_hCVShowTeamlockNoticeOwnTeam;

ConVar g_hCVShowUpgradePurchase;
ConVar g_hCVShowMenuOnLevelDefault;
ConVar g_hCVFadeOnLevelDefault;

ConVar g_hCVFadeOnLevelColor;

// List of default core chat commands available to players, which get registered with the smrpg_commandlist plugin.
char g_sDefaultRPGCommands[] = {"rpgmenu", "rpgrank", "rpginfo", "rpgtop10", "rpgnext", "rpgsession", "rpghelp", "rpgexp"};

#define IF_IGNORE_BOTS(%1) if(IsFakeClient(%1) && (!g_hCVBotEnable.BoolValue || (g_hCVBotNeedHuman.BoolValue && Client_GetCount(true, false) == 0)))

#include "smrpg/smrpg_upgrades.sp"
#include "smrpg/smrpg_database.sp"
#include "smrpg/smrpg_settings.sp"
#include "smrpg/smrpg_players.sp"
#include "smrpg/smrpg_stats.sp"
#include "smrpg/smrpg_menu.sp"
#include "smrpg/smrpg_admincommands.sp"
#include "smrpg/smrpg_adminmenu.sp"

public Plugin myinfo = 
{
	name = "SM:RPG",
	author = "Jannik \"Peace-Maker\" Hartung, SeLfkiLL",
	description = "SM:RPG Mod",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("smrpg");
	g_bLateLoaded = late;
	
	CreateNative("SMRPG_IsEnabled", Native_IsEnabled);
	CreateNative("SMRPG_IgnoreBots", Native_IgnoreBots);
	CreateNative("SMRPG_IsFFAEnabled", Native_IsFFAEnabled);
	RegisterUpgradeNatives();
	RegisterPlayerNatives();
	RegisterStatsNatives();
	RegisterTopMenuNatives();
	RegisterSettingsNatives();
	RegisterDatabaseNatives();
}

public void OnPluginStart()
{
	ConVar hVersion = CreateConVar("smrpg_version", PLUGIN_VERSION, "SM:RPG version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != null)
	{
		hVersion.SetString(PLUGIN_VERSION);
		hVersion.AddChangeHook(ConVar_VersionChanged);
	}
	
	SMRPG_GC_CheckSharedMaterialsAndSounds();
	
	AutoExecConfig_SetFile("plugin.smrpg");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(null);
	
	g_hCVEnable = AutoExecConfig_CreateConVar("smrpg_enable", "1", "If set to 1, SM:RPG is enabled, if 0, SM:RPG is disabled", 0, true, 0.0, true, 1.0);
	g_hCVFFA = AutoExecConfig_CreateConVar("smrpg_ffa", "0", "Free-For-All mode to ignore teams and handle teammates as if they're enemies?", 0, true, 0.0, true, 1.0);
	g_hCVBotEnable = AutoExecConfig_CreateConVar("smrpg_bot_enable", "1", "If set to 1, bots will be able to use the SM:RPG plugin", 0, true, 0.0, true, 1.0);
	g_hCVBotSaveStats = AutoExecConfig_CreateConVar("smrpg_bot_save_stats", "0", "If set to 1, the stats of bots are saved per bot name and are restored when the bot is added later again.", 0, true, 0.0, true, 1.0);
	g_hCVBotNeedHuman = AutoExecConfig_CreateConVar("smrpg_bot_need_human", "1", "Don't allow bots to gain experience while no human player is on the server?", 0, true, 0.0, true, 1.0);
	g_hCVNeedEnemies = AutoExecConfig_CreateConVar("smrpg_need_enemies", "1", "Don't give any experience if there is no enemy in the opposite team?", 0, true, 0.0, true, 1.0);
	g_hCVEnemiesNotAFK = AutoExecConfig_CreateConVar("smrpg_enemies_not_afk", "1", "Don't give any experience if all enemies are currently AFK?", 0, true, 0.0, true, 1.0);
	g_hCVDebug = AutoExecConfig_CreateConVar("smrpg_debug", "0", "Turns on debug mode for this plugin", 0, true, 0.0, true, 1.0);
	g_hCVSaveData = AutoExecConfig_CreateConVar("smrpg_save_data", "1", "If disabled, the database won't be updated (this means player data won't be saved!)", 0, true, 0.0, true, 1.0);
	g_hCVSaveInterval = AutoExecConfig_CreateConVar("smrpg_save_interval", "150", "Interval (in seconds) that player data is auto saved (0 = off)", 0, true, 0.0);
	g_hCVPlayerExpire = AutoExecConfig_CreateConVar("smrpg_player_expire", "30", "Sets how many days until an unused player account is deleted (0 = never)", 0, true, 0.0);
	g_hCVAllowSelfReset = AutoExecConfig_CreateConVar("smrpg_allow_selfreset", "1", "Are players allowed to reset their own rpg stats in the settings menu?", 0, true, 0.0, true, 1.0);
	
	g_hCVBotMaxlevel = AutoExecConfig_CreateConVar("smrpg_bot_maxlevel", "250", "The maximum level a bot can reach until its stats are reset (0 = infinite)", 0, true, 0.0);
	g_hCVBotMaxlevelReset = AutoExecConfig_CreateConVar("smrpg_bot_maxlevel_reset", "1", "Reset the bot to level 1, if the bot reaches the maxlevel for bots?", 0, true, 0.0, true, 1.0);
	g_hCVPlayerMaxlevel = AutoExecConfig_CreateConVar("smrpg_player_maxlevel", "0", "The maximum level a player can reach until he stops getting more experience. (0 = infinite)", 0, true, 0.0);
	g_hCVPlayerMaxlevelReset = AutoExecConfig_CreateConVar("smrpg_player_maxlevel_reset", "0", "Reset the player to level 1, if the player reaches the player maxlevel?", 0, true, 0.0, true, 1.0);
	
	g_hCVBotKillPlayer = AutoExecConfig_CreateConVar("smrpg_bot_kill_player", "1", "Bots earn experience for interacting with real players?", 0, true, 0.0, true, 1.0);
	g_hCVPlayerKillBot = AutoExecConfig_CreateConVar("smrpg_player_kill_bot", "1", "Real players earn experience for interacting with bots?", 0, true, 0.0, true, 1.0);
	g_hCVBotKillBot = AutoExecConfig_CreateConVar("smrpg_bot_kill_bot", "1", "Bots earn experience for interacting with bots?", 0, true, 0.0, true, 1.0);
	
	g_hCVAnnounceNewLvl = AutoExecConfig_CreateConVar("smrpg_announce_newlvl", "1", "Global announcement when a player reaches a new level (1 = enable, 0 = disable)", 0, true, 0.0, true, 1.0);
	g_hCVAFKTime = AutoExecConfig_CreateConVar("smrpg_afk_time", "30", "After how many seconds of idleing is the player flagged as AFK? (0 = off)", 0, true, 0.0);
	g_hCVSpawnProtect = AutoExecConfig_CreateConVar("smrpg_spawn_protect_noxp", "1", "Don't give any experience for actions against players who just spawned and haven't pressed any buttons yet?", 0, true, 0.0, true, 1.0);
	
	g_hCVExpNotice = AutoExecConfig_CreateConVar("smrpg_exp_notice", "1", "Sends notifications to players when they gain Experience", 0, true, 0.0, true, 1.0);
	g_hCVExpMax = AutoExecConfig_CreateConVar("smrpg_exp_max", "50000", "Maximum experience that will ever be required", 0, true, 0.0);
	g_hCVExpStart = AutoExecConfig_CreateConVar("smrpg_exp_start", "250", "Experience required for Level 1", 0, true, 0.0);
	g_hCVExpInc = AutoExecConfig_CreateConVar("smrpg_exp_inc", "50", "Increment experience required for each level (until smrpg_exp_max)", 0, true, 0.0);
	
	g_hCVExpDamage = AutoExecConfig_CreateConVar("smrpg_exp_damage", "1.0", "Experience for hurting an enemy multiplied by the damage done", 0, true, 0.0);
	g_hCVExpKill = AutoExecConfig_CreateConVar("smrpg_exp_kill", "15.0", "Experience for a kill multiplied by the victim's level", 0, true, 0.0);
	g_hCVExpKillBonus = AutoExecConfig_CreateConVar("smrpg_exp_kill_bonus", "0.0", "Extra constant experience to give on top of the regular experience on a kill.", 0, true, 0.0);
	g_hCVExpKillMax = AutoExecConfig_CreateConVar("smrpg_exp_kill_max", "0.0", "Maximum experience a player can ever earn for killing someone. (0 = unlimited)", 0, true, 0.0);
	
	g_hCVExpTeamwin = AutoExecConfig_CreateConVar("smrpg_exp_teamwin", "0.15", "Experience multipled by the experience required and the team ratio given to a team for completing the objective", 0, true, 0.0);
	AutoExecConfig_CreateConVar("smrpg_exp_use_teamratio", "1", "Scale the experience for team events by the team ratio? This is e.g. used to lower the amount of experience earned, when a winning team has more players than the other.", 0, true, 0.0, true, 1.0);
	
	g_hCVLastExperienceCount = AutoExecConfig_CreateConVar("smrpg_lastexperience_count", "50", "How many times should we remember why each player got some experience in the recent past?", 0, true, 1.0);
	
	g_hCVLevelStart = AutoExecConfig_CreateConVar("smrpg_level_start", "1", "Starting level for new players.", 0, true, 1.0);
	g_hCVLevelStartGiveCredits = AutoExecConfig_CreateConVar("smrpg_level_start_give_credits", "1", "Give the players the credits for all additional start levels as if they'd leveled up themselves?", 0, true, 0.0, true, 1.0);
	g_hCVUpgradeStartLevelsFree = AutoExecConfig_CreateConVar("smrpg_upgrade_start_levels_free", "1", "Don't charge the players for the initial upgrade levels (smrpg_<upgr>_startlevel)?", 0, true, 0.0, true, 1.0);
	g_hCVCreditsInc = AutoExecConfig_CreateConVar("smrpg_credits_inc", "5", "Credits given to each new level", 0, true, 0.0);
	g_hCVCreditsStart = AutoExecConfig_CreateConVar("smrpg_credits_start", "0", "Starting credits for Level 1", 0, true, 0.0);
	g_hCVSalePercent = AutoExecConfig_CreateConVar("smrpg_sale_percent", "0.75", "Percentage of credits a player gets for selling an upgrade", 0, true, 0.0);
	g_hCVIgnoreLevelBarrier = AutoExecConfig_CreateConVar("smrpg_ignore_level_barrier", "0", "Ignore the hardcoded maxlevels for the upgrades and allow to set the maxlevel as high as you want. THIS MIGHT BE BAD!", 0, true, 0.0, true, 1.0);
	g_hCVAllowPresentUpgradeUsage = AutoExecConfig_CreateConVar("smrpg_allow_present_upgrade_usage", "0", "Allow players to use the upgrades they already have levels for, if they normally wouldn't have access to the upgrade due to the adminflags.\nThis allows admins to give upgrades to players they aren't able to buy themselves.", 0, true, 0.0, true, 1.0);
	g_hCVDisableLevelSelection = AutoExecConfig_CreateConVar("smrpg_disable_level_selection", "0", "Don't allow players to change the selected levels of their upgrades to a lower level than they already purchased?", 0, true, 0.0, true, 1.0);
	g_hCVShowMaxLevelInMenu = AutoExecConfig_CreateConVar("smrpg_show_maxlevel_in_menu", "0", "Show the maxlevel of an upgrade in the upgrade buy, sell and info menus?", 0, true, 0.0, true, 1.0);
	g_hCVShowUpgradesOfOtherTeam = AutoExecConfig_CreateConVar("smrpg_show_upgrades_teamlock", "1", "Show the upgrades if they are locked to the other team?\n\t0: Don't show teamlocked upgrades at all.\n\t1: Show upgrades if the player already bought a level while being in the other team.\n\t2: Always show all upgrades.", 0, true, 0.0, true, 2.0);
	g_hCVBuyUpgradesOfOtherTeam = AutoExecConfig_CreateConVar("smrpg_buy_upgrades_teamlock", "0", "Allow players to buy upgrades of the other team, even if they can't use them in the current team?", 0, true, 0.0, true, 1.0);
	g_hCVShowTeamlockNoticeOwnTeam = AutoExecConfig_CreateConVar("smrpg_show_teamlock_notice_own_team", "0", "Always show the team restriction of the upgrade in the menu, even if the player is in the correct team?", 0, true, 0.0, true, 1.0);
	
	g_hCVShowUpgradePurchase = AutoExecConfig_CreateConVar("smrpg_show_upgrade_purchase_in_chat", "0", "Show a message to all in chat when a player buys an upgrade.", 0, true, 0.0, true, 1.0);
	g_hCVShowMenuOnLevelDefault = AutoExecConfig_CreateConVar("smrpg_show_menu_on_levelup", "0", "Show the rpg menu when a player levels up by default? Players can change it in their settings individually afterwards.", 0, true, 0.0, true, 1.0);
	g_hCVFadeOnLevelDefault = AutoExecConfig_CreateConVar("smrpg_fade_screen_on_levelup", "1", "Fade the screen golden when a player levels up by default? Players can change it in their settings individually afterwards.", 0, true, 0.0, true, 1.0);
	
	g_hCVFadeOnLevelColor = AutoExecConfig_CreateConVar("smrpg_fade_screen_on_levelup_color", "255 215 0 40", "RGBA color to fade the screen in for a short time after levelup. Default is a golden shine.", 0);
	
	AutoExecConfig_ExecuteFile();
	//AutoExecConfig_CleanFile();
	
	// forward void SMRPG_OnEnableStatusChanged(bool bEnabled);
	g_hfwdOnEnableStatusChanged = CreateGlobalForward("SMRPG_OnEnableStatusChanged", ET_Ignore, Param_Cell);
	
	
	g_hCVEnable.AddChangeHook(ConVar_EnableChanged);
	g_hCVSaveInterval.AddChangeHook(ConVar_SaveIntervalChanged);
	g_hCVLastExperienceCount.AddChangeHook(ConVar_LastExperienceCountChanged);
	
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
	InitWeaponExperienceConfig();
	
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	
	HookEventEx("player_spawn", Event_OnPlayerSpawn);
	HookEventEx("player_death", Event_OnPlayerDeath);
	HookEventEx("round_end", Event_OnRoundEnd);
	HookEvent("player_disconnect", Event_OnPlayerDisconnect);
	
	if(g_bLateLoaded)
	{
		for(int i=1;i<=MaxClients;i++)
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
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}
}

/**
 * ConVar changes
 */
public void ConVar_VersionChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	SetConVarString(convar, PLUGIN_VERSION);
}

public void ConVar_SaveIntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ClearHandle(g_hPlayerAutoSave);
	g_hPlayerAutoSave = CreateTimer(g_hCVSaveInterval.FloatValue, Timer_SavePlayers, _, TIMER_REPEAT);
}

public void ConVar_EnableChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(oldValue, newValue, false))
		return;
	
	// Call the forward.
	Call_StartForward(g_hfwdOnEnableStatusChanged);
	Call_PushCell(convar.BoolValue);
	Call_Finish();
	
	// Don't need to do anything, if we're enabled or we don't want to save the stats to the database.
	if(convar.BoolValue || !g_hCVSaveData.BoolValue)
		return;
	
	convar.RemoveChangeHook(ConVar_EnableChanged);
	SetConVarBool(convar, true);
	SaveAllPlayers();
	SetConVarBool(convar, false);
	convar.AddChangeHook(ConVar_EnableChanged);
	PrintToServer("SM:RPG smrpg_enable: SM:RPG data has been saved");
}

/**
 * Public global forwards
 */
public void OnAllPluginsLoaded()
{
	RegisterTopMenu();
	InitMenu();
}

public void OnPluginEnd()
{
	if(LibraryExists("smrpg_commandlist"))
	{
		for(int i=0;i<sizeof(g_sDefaultRPGCommands);i++)
			SMRPG_UnregisterCommand(g_sDefaultRPGCommands[i]);
	}
	
	// Try to save the stats!
	if(g_hDatabase != null)
		SaveAllPlayers();
}

public void OnConfigsExecuted()
{
	char sPath[PLATFORM_MAX_PATH];
	char sError[256];
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/rpgmenu_sorting.txt");
	
	if (!LoadTopMenuConfig(GetRPGTopMenu(), sPath, sError, sizeof(sError)))
	{
		LogError("Could not load rpg menu config (file \"%s\": %s)", sPath, sError);
	}
	
	ClearHandle(g_hPlayerAutoSave);
	g_hPlayerAutoSave = CreateTimer(g_hCVSaveInterval.FloatValue, Timer_SavePlayers, _, TIMER_REPEAT);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "smrpg_commandlist"))
	{
		// Register the default rpg commands
		for(int i=0;i<sizeof(g_sDefaultRPGCommands);i++)
			SMRPG_RegisterCommand(g_sDefaultRPGCommands[i], CommandList_DefaultTranslations);
	}
	else if(StrEqual(name, "clientprefs"))
	{
		SetCookieMenuItem(ClientPrefsMenu_HandleItem, 0, "SM:RPG > Settings");
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "adminmenu"))
	{
		g_hTopMenu = null;
		g_TopMenuCategory = INVALID_TOPMENUOBJECT;
	}
}

public void OnMapStart()
{
	SMRPG_GC_PrecacheSound("SoundLevelup");
	
	if(!ReadWeaponExperienceConfig())
	{
		LogError("Failed to read individual weapon experience config in sourcemod/configs/smrpg/weapon_experience.cfg");
	}
	
	// Clean up our database..
	DatabaseMaid();
	
	StartAFKChecker();
	StartSessionMenuUpdater();
}

public void OnMapEnd()
{
	SaveAllPlayers();
}

public void OnClientConnected(int client)
{
	InitPlayer(client);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
	
	if(!g_hCVEnable.BoolValue)
		return;
	
	// Call the query callback in all plugins of the upgrades this client owns.
	// His upgrades were loaded before he got fully ingame.
	if (IsPlayerDataLoaded(client))
		NotifyUpgradePluginsOfLevel(client);
	
	Client_PrintToChat(client, false, "%t", "Inform about plugin", PLUGIN_VERSION);
	Client_PrintToChat(client, false, "%t", "Advertise rpgmenu command");
}

public void OnClientAuthorized(int client, const char[] auth)
{
	AddPlayer(client);
}

public void OnClientDisconnect(int client)
{
	ResetPlayerMenu(client);
	ResetAdminMenu(client);
	
	// Save stats and upgrade levels both at once or nothing at all.
	Transaction hTransaction = new Transaction();
	if (SaveData(client, hTransaction))
		g_hDatabase.Execute(hTransaction, _, SQLTxn_LogFailure);
	else
		delete hTransaction;
	
	ClearClientRankCache(client);
	RemovePlayer(client);
	ResetAFKPlayer(client);
	ResetSpawnProtection(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsClientInGame(client) && IsPlayerAlive(client))
	{
		// Reset his afk timer when he uses a weapon.
		if(buttons & (IN_ATTACK|IN_ATTACK2))
			g_PlayerAFKInfo[client][AFK_startTime] = 0;
		
		// Remove spawn protection if the player presses any buttons.
		if(buttons > 0)
			g_bPlayerSpawnProtected[client] = false;
	}
	return Plugin_Continue;
}

public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	char sWeapon[64];
	if(iWeapon > 0)
		GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	
	Stats_PlayerDamage(attacker, victim, damage, sWeapon);
}

/**
 * Event handlers
 */

public void Event_OnPlayerSpawn(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if(client <= 0)
		return;
	
	// Save the spawn time so we don't count the new spawn position as if the player moved himself
	g_PlayerAFKInfo[client][AFK_spawnTime] = GetTime();
	// Protect him and don't give any experience to actions against him until he presses some button.
	g_bPlayerSpawnProtected[client] = true;
}
 
public void Event_OnPlayerDeath(Event event, const char[] error, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	if(victim <= 0)
		return;
	
	// Save when the player died.
	g_PlayerAFKInfo[victim][AFK_deathTime] = GetTime();
	
	if(attacker <= 0)
		return;
	
	char sWeapon[64];
	// FIXME: Not all games might have this resource in the player_death event..
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	
	Stats_PlayerKill(attacker, victim, sWeapon);
}

public void Event_OnRoundEnd(Event event, const char[] error, bool dontBroadcast)
{
	Stats_WinningTeam(event.GetInt("winner"));
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sText)
{
	if(StrEqual(sText, "rpgmenu", false) || StrEqual(sText, "rpg", false))
		DisplayMainMenu(client);
	else if(StrContains(sText, "rpgrank", false) == 0)
	{
		if(!sText[7])
		{
			PrintRankToChat(client, -1);
		}
		else
		{
			int iTarget = FindTarget(client, sText[8], !g_hCVBotEnable.BoolValue, false);
			if(iTarget == -1)
				return;
			PrintRankToChat(iTarget, -1);
		}
	}
	else if(StrContains(sText, "rpginfo", false) == 0)
	{
		if(!sText[7])
		{
			// See if he's spectating someone and show the upgrades of the target.
			if(IsClientObserver(client) || !IsPlayerAlive(client))
			{
				Obs_Mode iObsMode = Client_GetObserverMode(client);
				if(iObsMode == OBS_MODE_IN_EYE || iObsMode == OBS_MODE_CHASE)
				{
					int iTarget = Client_GetObserverTarget(client);
					if(iTarget > 0 && iTarget <= MaxClients)
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
			int iTarget = FindTarget(client, sText[8], false, false);
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
public void Event_OnPlayerDisconnect(Event event, const char[] error, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	ResetPlayerSessionStats(client);
}

/**
 * Public command handlers
 */

public Action Cmd_RPGMenu(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayMainMenu(client);
	
	return Plugin_Handled;
}

public Action Cmd_RPGRank(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	char sText[256];
	GetCmdArgString(sText, sizeof(sText));
	TrimString(sText);
	
	if(!sText[0])
	{
		PrintRankToChat(client, client);
	}
	else
	{
		int iTarget = FindTarget(client, sText, !g_hCVBotEnable.BoolValue, false);
		if(iTarget == -1)
			return Plugin_Handled;
		PrintRankToChat(iTarget, client);
	}
	
	return Plugin_Handled;
}

public Action Cmd_RPGInfo(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	char sText[256];
	GetCmdArgString(sText, sizeof(sText));
	TrimString(sText);
	
	if(!sText[0])
	{
		// See if he's spectating someone and show the upgrades of the target.
		if(IsClientObserver(client) || !IsPlayerAlive(client))
		{
			Obs_Mode iObsMode = Client_GetObserverMode(client);
			if(iObsMode == OBS_MODE_IN_EYE || iObsMode == OBS_MODE_CHASE)
			{
				int iTarget = Client_GetObserverTarget(client);
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
		int iTarget = FindTarget(client, sText, false, false);
		if(iTarget == -1)
			return Plugin_Handled;
		DisplayOtherUpgradesMenu(client, iTarget);
	}
	
	return Plugin_Handled;
}

public Action Cmd_RPGTop10(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayTop10Menu(client);
	
	return Plugin_Handled;
}

public Action Cmd_RPGNext(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayNextPlayersInRanking(client);
	
	return Plugin_Handled;
}

public Action Cmd_RPGSession(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplaySessionStatsMenu(client);
	
	return Plugin_Handled;
}

public Action Cmd_RPGHelp(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG: This command is ingame only.");
		return Plugin_Handled;
	}
	
	DisplayHelpMenu(client);
	
	return Plugin_Handled;
}

public Action Cmd_RPGLatestExperience(int client, int args)
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
public Action Timer_SavePlayers(Handle timer, any data)
{
	if(!g_hCVEnable.BoolValue || !g_hCVSaveData.BoolValue || !g_hCVSaveInterval.BoolValue)
		return Plugin_Continue;
	
	SaveAllPlayers();
	
	return Plugin_Continue;
}

/**
 * Natives
 */
public int Native_IsEnabled(Handle plugin, int numParams)
{
	return g_hCVEnable.BoolValue;
}

public int Native_IgnoreBots(Handle plugin, int numParams)
{
	return !g_hCVBotEnable.BoolValue;
}

public int Native_IsFFAEnabled(Handle plugin, int numParams)
{
	return g_hCVFFA.BoolValue;
}

/**
 * Translation callback for SM:RPG Command List plugin
 */
public Action CommandList_DefaultTranslations(int client, const char[] command, CommandTranslationType type, char[] translation, int maxlen)
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
				Format(translation, maxlen, "%T", "rpgexp advert", client, g_hCVLastExperienceCount.IntValue);
		}
	}
	return Plugin_Continue;
}

/**
 * Clientprefs !settings menu item
 */
public void ClientPrefsMenu_HandleItem(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
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
stock bool IsValidPlugin(Handle hPlugin) {
	if(hPlugin == null)
		return false;

	Handle hIterator = GetPluginIterator();

	bool bPluginExists = false;
	while(MorePlugins(hIterator)) {
		Handle hLoadedPlugin = ReadPlugin(hIterator);
		if(hLoadedPlugin == hPlugin) {
			bPluginExists = true;
			break;
		}
	}

	delete hIterator;

	return bPluginExists;
}

stock void DebugMsg(char[] format, any ...)
{
	if(!g_hCVDebug.BoolValue)
		return;
	
	char sBuffer[192];
	SetGlobalTransTarget(LANG_SERVER);
	VFormat(sBuffer, sizeof(sBuffer), format, 2);
	PrintToServer(sBuffer);
}