#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <smrpg>

#define PLUGIN_VERSION "1.0"

new bool:g_bLateLoaded;
new Handle:g_hPlayerAutoSave;

// Convars
new Handle:g_hCVEnable;
new Handle:g_hCVBotEnable;
new Handle:g_hCVDebug;
new Handle:g_hCVSaveData;
new Handle:g_hCVSteamIDSave;
new Handle:g_hCVSaveInterval;
new Handle:g_hCVPlayerExpire;
new Handle:g_hCVBotMaxlevel;
new Handle:g_hCVAnnounceNewLvl;

new Handle:g_hCVExpNotice;
new Handle:g_hCVExpMax;
new Handle:g_hCVExpStart;
new Handle:g_hCVExpInc;

new Handle:g_hCVExpDamage;
new Handle:g_hCVExpKill;

new Handle:g_hCVExpTeamwin;

new Handle:g_hCVCreditsInc;
new Handle:g_hCVCreditsStart;
new Handle:g_hCVSalePercent;
new Handle:g_hCVIgnoreLevelBarrier;

#define IF_IGNORE_BOTS(%1) if(!GetConVarBool(g_hCVBotEnable) && IsFakeClient(%1))

#include "smrpg/smrpg_upgrades.sp"
#include "smrpg/smrpg_database.sp"
#include "smrpg/smrpg_players.sp"
#include "smrpg/smrpg_stats.sp"
#include "smrpg/smrpg_menu.sp"
#include "smrpg/smrpg_admincommands.sp"

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
	
	CreateNative("SMRPG_IsEnabled", Native_IsEnabled);
	CreateNative("SMRPG_IgnoreBots", Native_IgnoreBots);
	RegisterUpgradeNatives();
	RegisterPlayerNatives();
	InitStatsNatives();
}

public OnPluginStart()
{
	new Handle:hVersion = CreateConVar("smrpg_version", PLUGIN_VERSION, "SM:RPG version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != INVALID_HANDLE)
	{
		SetConVarString(hVersion, PLUGIN_VERSION);
		HookConVarChange(hVersion, ConVar_VersionChanged);
	}
	
	g_hCVEnable = CreateConVar("smrpg_enable", "1", "If set to 1, SM:RPG is enabled, if 0, SM:RPG is disabled", 0, true, 0.0, true, 1.0);
	g_hCVBotEnable = CreateConVar("smrpg_bot_enable", "1", "If set to 1, bots will be able to use the SM:RPG plugin", 0, true, 0.0, true, 1.0);
	g_hCVDebug = CreateConVar("smrpg_debug", "0", "Turns on debug mode for this plugin", 0, true, 0.0, true, 1.0);
	g_hCVSaveData = CreateConVar("smrpg_save_data", "1", "If disabled, the database won't be updated (this means player data won't be saved!)", 0, true, 0.0, true, 1.0);
	g_hCVSteamIDSave = CreateConVar("smrpg_steamid_save", "1", "Save by SteamID instead of by SteamID and name", 0, true, 0.0, true, 1.0);
	g_hCVSaveInterval = CreateConVar("smrpg_save_interval", "150", "Interval (in seconds) that player data is auto saved (0 = off)", 0, true, 0.0);
	g_hCVPlayerExpire = CreateConVar("smrpg_player_expire", "30", "Sets how many days until an unused player account is deleted (0 = never)", 0, true, 0.0);
	g_hCVBotMaxlevel = CreateConVar("smrpg_bot_maxlevel", "250", "The maximum level a bot can reach until its stats are reset (0 = infinite)", 0, true, 0.0);
	g_hCVAnnounceNewLvl = CreateConVar("smrpg_announce_newlvl", "1", "Global announcement when a player reaches a new level (1 = enable, 0 = disable)", 0, true, 0.0, true, 1.0);
	
	g_hCVExpNotice = CreateConVar("smrpg_exp_notice", "1", "Sets notifications to players when they gain Experience", 0, true, 0.0, true, 1.0);
	g_hCVExpMax = CreateConVar("smrpg_exp_max", "50000", "Maximum experience that will ever be required", 0, true, 0.0);
	g_hCVExpStart = CreateConVar("smrpg_exp_start", "250", "Experience required for Level 1", 0, true, 0.0);
	g_hCVExpInc = CreateConVar("smrpg_exp_inc", "50", "Incriment experience requied for each level (until smrpg_exp_max)", 0, true, 0.0);
	
	g_hCVExpDamage = CreateConVar("smrpg_exp_damage", "1.0", "Experience for hurting an enemy multiplied by the damage done", 0, true, 0.0);
	g_hCVExpKill = CreateConVar("smrpg_exp_kill", "15.0", "Experience for a kill multiplied by the victim's level", 0, true, 0.0);
	
	g_hCVExpTeamwin = CreateConVar("smrpg_exp_teamwin", "0.15", "Experience multipled by the experience required and the team ratio given to a team for completing the objective", 0, true, 0.0);
	
	g_hCVCreditsInc = CreateConVar("smrpg_credits_inc", "5", "Credits given to each new level", 0, true, 0.0);
	g_hCVCreditsStart = CreateConVar("smrpg_credits_start", "0", "Starting credits for Level 1", 0, true, 0.0);
	g_hCVSalePercent = CreateConVar("smrpg_sale_percent", "0.75", "Percentage of credits a player gets for selling an item", 0, true, 0.0);
	g_hCVIgnoreLevelBarrier = CreateConVar("smrpg_ignore_level_barrier", "0", "Ignore the hardcoded maxlevels for the items and allow to set the maxlevel as high as you want.", 0, true, 0.0, true, 1.0);
	
	HookConVarChange(g_hCVEnable, ConVar_EnableChanged);
	HookConVarChange(g_hCVSaveInterval, ConVar_SaveIntervalChanged);
	
	RegConsoleCmd("rpgmenu", Cmd_RPGMenu, "Opens the rpg main menu");
	RegConsoleCmd("rpg", Cmd_RPGMenu, "Opens the rpg main menu");
	RegConsoleCmd("rpgrank", Cmd_RPGRank, "Shows your rank or the rank of the target person. rpgrank [name|steamid|#userid]");
	RegConsoleCmd("rpgtop10", Cmd_RPGTop10, "Show the SM:RPG top 10");
	
	RegisterAdminCommands();
	
	InitUpgrades();
	InitDatabase();
	InitMenu();
	
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("player_say", Event_OnPlayerSay);
	
	if(g_bLateLoaded)
	{
		decl String:sAuth[40];
		for(new i=1;i<=MaxClients;i++)
		{
			if(!IsClientConnected(i))
				continue;
			
			OnClientConnected(i);
			
			if(!IsClientInGame(i))
				continue;
			
			OnClientPutInServer(i);
			
			if(IsClientAuthorized(i) && GetClientAuthString(i, sAuth, sizeof(sAuth)))
			{
				OnClientAuthorized(i, sAuth);
			}
		}
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
public OnConfigsExecuted()
{
	ClearHandle(g_hPlayerAutoSave);
	g_hPlayerAutoSave = CreateTimer(GetConVarFloat(g_hCVSaveInterval), Timer_SavePlayers, _, TIMER_REPEAT);
}

public OnMapStart()
{
	PrecacheSound("buttons/blip2.wav", true);
	
	// Clean up our database..
	DatabaseMaid();
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
	
	PrintToChat(client, "\x01This server is running SM:RPG v%s.", PLUGIN_VERSION);
	PrintToChat(client, "%t", "greeting");
}

public OnClientAuthorized(client, const String:auth[])
{
	AddPlayer(client, auth);
}

public OnClientDisconnect(client)
{
	SaveData(client);
	ClearClientRankCache(client);
	RemovePlayer(client);
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

public Event_OnPlayerDeath(Handle:event, const String:error[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(attacker <= 0 || victim <= 0)
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
	
	if(StrEqual(sText, "rpgmenu") || StrEqual(sText, "rpg"))
		DisplayMainMenu(client);
	else if(StrContains(sText, "rpgrank") == 0)
	{
		TrimString(sText);
		if(!sText[7])
		{
			PrintRankToChat(client, -1);
		}
		else
		{
			new iTarget = FindTarget(client, sText[7], true, false);
			if(iTarget == -1)
				return;
			PrintRankToChat(iTarget, -1);
		}
	}
	else if(StrEqual(sText, "rpgtop10"))
		DisplayTop10Menu(client);
	else if(StrEqual(sText, "rpghelp"))
		DisplayHelpMenu(client, 0);
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
		new iTarget = FindTarget(client, sText, true, false);
		if(iTarget == -1)
			return Plugin_Handled;
		PrintRankToChat(iTarget, -1);
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
	return GetConVarBool(g_hCVBotEnable);
}

/**
 * Helpers
 */
// IsValidHandle() is deprecated, let's do a real check then...
// By Thraaawn
stock bool:IsValidPlugin(Handle:hPlugin) {
	if(hPlugin == INVALID_HANDLE)return false;

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