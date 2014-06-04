/**
 * Idea by freddukes' SourceRPG eventscript.
 * 
 * Increase experience earnings and credit reward for one map.
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smrpg>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#define PLUGIN_VERSION "1.0"

new Handle:g_hCVRPGSaveData;
new bool:g_bRPGSaveDataOld;

new Handle:g_hCVTurboMode;
new Handle:g_hCVTurboModeAnnounce;
new Handle:g_hCVExperienceMultiplier;
new Handle:g_hCVCreditsMultiplier;

new bool:g_bMapEnded;

new bool:g_bClientLeveledUp[MAXPLAYERS+1];

new Handle:g_hTopMenu;

public Plugin:myinfo = 
{
	name = "SM:RPG > Turbo Mode",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Highers levelup rates for the current map. Stats are not saved.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	g_hCVTurboMode = CreateConVar("smrpg_turbomode_enabled", "0", "Enable SM:RPG turbo mode with higher experience and credits rates.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCVTurboModeAnnounce = CreateConVar("smrpg_turbomode_announce", "1", "Announce turbomode to all players in chat when it's enabled.", 0, true, 0.0, true, 1.0);
	g_hCVExperienceMultiplier = CreateConVar("smrpg_turbomode_expmultiplier", "3", "Multiply all earned experience by this value.", 0, true, 1.0);
	g_hCVCreditsMultiplier = CreateConVar("smrpg_turbomode_creditsmultiplier", "2", "Multiply all earned credits by this value.", 0, true, 1.0);
	
	HookConVarChange(g_hCVTurboMode, ConVar_TurboModeChanged);
	
	AutoExecConfig();
	
	RegAdminCmd("sm_turbomode", Cmd_TurboMode, ADMFLAG_CONFIG, "Enables SM:RPG turbo mode. Higher experience rates for everyone until mapchange. Stats are not saved.", "smrpg");
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	LoadTranslations("common.phrases");
	
	// See if the menu plugin is already ready
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}
}

/**
 * Public forwards
 */
public OnAllPluginsLoaded()
{
	// Disable saving stuff to the database during turbo mode.
	g_hCVRPGSaveData = FindConVar("smrpg_save_data");
	if(g_hCVRPGSaveData != INVALID_HANDLE)
		HookConVarChange(g_hCVRPGSaveData, ConVar_SaveDataChanged);
}

public OnConfigsExecuted()
{
	// Trigger the config, if it's set already.
	g_bRPGSaveDataOld = GetConVarBool(g_hCVRPGSaveData);
	if(GetConVarBool(g_hCVTurboMode))
		ConVar_TurboModeChanged(g_hCVTurboMode, "0", "1");
}

public OnMapStart()
{
	g_bMapEnded = false;
}

public OnMapEnd()
{
	g_bMapEnded = true;
	
	// Disable turbo mode.
	SetConVarBool(g_hCVTurboMode, false);
}

/**
 * ConVar change callbacks
 */
public ConVar_SaveDataChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// DON'T SAVE ANYTHING DURING TURBO MODE!
	if(GetConVarBool(g_hCVTurboMode) && GetConVarBool(convar))
		SetConVarBool(convar, false);
	else
		g_bRPGSaveDataOld = GetConVarBool(convar);
}

public ConVar_TurboModeChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(StrEqual(oldValue, newValue))
		return;
	
	if(GetConVarBool(g_hCVTurboMode))
	{
		// Remember the old value before enabling turbo mode.
		g_bRPGSaveDataOld = GetConVarBool(g_hCVRPGSaveData);
		
		// Save all current progress to the database!
		SMRPG_FlushDatabase();
		
		// Disable saving.
		SetConVarBool(g_hCVRPGSaveData, false);
		
		// Reset all ingame players.
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i))
				SMRPG_ResetClientStats(i);
		}
		
		// Restart the round.
		//ServerCommand("mp_restartgame 2");
		
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {RB}Turbo mode enabled!{G} Experience earned increase {N}%.2fx{G} and credits {N}%.2fx{G} faster! Stats are not permanent.", GetConVarFloat(g_hCVExperienceMultiplier), GetConVarFloat(g_hCVCreditsMultiplier));
		
		// Start showing a constant message on the screen.
		if(Timer_DisplayTurboModeHud(INVALID_HANDLE) == Plugin_Continue)
			CreateTimer(1.0, Timer_DisplayTurboModeHud, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	}
	else
	{
		// Reset saving
		SetConVarBool(g_hCVRPGSaveData, g_bRPGSaveDataOld);
		
		if(!g_bMapEnded)
		{
			// Reconnect all clients so their old level is loaded.
			for(new i=1;i<=MaxClients;i++)
			{
				if(IsClientInGame(i))
				{
					if(IsFakeClient(i))
						SMRPG_ResetClientStats(i);
					else
						ReconnectClient(i);
					
				}
			}
		}
		
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {RB}Turbo mode disabled!{G} Experience and credit rates are back to normal.");
	}
}

/**
 * Event handlers
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	if(IsPlayerAlive(client) && GetConVarBool(g_hCVTurboMode) && GetConVarBool(g_hCVTurboModeAnnounce))
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {RB}Turbo mode enabled!{G} Experience increase {N}%.2fx{G} and credits {N}%.2fx{G} faster! Stats are not permanent.", GetConVarFloat(g_hCVExperienceMultiplier), GetConVarFloat(g_hCVCreditsMultiplier));
}

/**
 * Command handlers
 */
public Action:Cmd_TurboMode(client, args)
{
	if(!GetConVarBool(g_hCVTurboMode))
	{
		ReplyToCommand(client, "SM:RPG > Turbo mode is now enabled. All players have been reset and experience is speed up.");
		SetConVarBool(g_hCVTurboMode, true);
	}
	else
	{
		ReplyToCommand(client, "SM:RPG > Turbo mode is now disabled. All players will be reconnected.");
		SetConVarBool(g_hCVTurboMode, false);
	}
	
	return Plugin_Handled;
}

/**
 * Timer callbacks
 */
public Action:Timer_DisplayTurboModeHud(Handle:timer)
{
	if(!GetConVarBool(g_hCVTurboMode))
		return Plugin_Stop;
	
	SetHudTextParams(0.8, 0.2, 2.0, 255, 0, 0, 200);
	
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			if(ShowHudText(i, -1, "Turbo mode") == -1)
			{
				PrintToServer("HudMsg not supported?");
				return Plugin_Stop;
			}
		}
	}
	
	return Plugin_Continue;
}

/**
 * SMRPG callbacks
 */
public SMRPG_OnClientLoaded(client)
{
	// Reset client to 0 during turbo mode.
	if(GetConVarBool(g_hCVTurboMode))
		SMRPG_ResetClientStats(client);
}

public Action:SMRPG_OnAddExperience(client, const String:reason[], &iExperience, other)
{
	if(!GetConVarBool(g_hCVTurboMode))
		return Plugin_Continue;
	
	if(!StrEqual(reason, ExperienceReason_Admin))
	{
		// Higher experience rate
		iExperience = RoundToCeil(float(iExperience) * GetConVarFloat(g_hCVExperienceMultiplier));
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action:SMRPG_OnClientLevel(client, oldlevel, newlevel)
{
	// The next credits change should be multiplied!
	g_bClientLeveledUp[client] = true;
	return Plugin_Continue;
}

public Action:SMRPG_OnClientCredits(client, oldcredits, newcredits)
{
	if(g_bClientLeveledUp[client])
	{
		g_bClientLeveledUp[client] = false;
		
		// Credits were actually given not taken
		if(GetConVarBool(g_hCVTurboMode) && oldcredits < newcredits)
		{
			new iInc = newcredits - oldcredits;
			iInc = RoundToCeil(float(iInc) * GetConVarFloat(g_hCVCreditsMultiplier));
			
			// Give him more credits.
			SMRPG_SetClientCredits(client, oldcredits + iInc);
			
			// Don't give him the regular credits for this levelup.
			return Plugin_Handled;
		}
		// what?..
	}
	
	return Plugin_Continue;
}

/**
 * Admin menu integration.
 */
public OnAdminMenuReady(Handle:topmenu)
{
	// Get the rpg category
	new TopMenuObject:iRPGCategory = FindTopMenuCategory(topmenu, "SM:RPG");
	
	if(iRPGCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == topmenu)
		return;
	
	g_hTopMenu = topmenu;
	
	AddToTopMenu(topmenu, "Toggle Turbo Mode", TopMenuObject_Item, TopMenu_AdminHandleTurboMode, iRPGCategory, "sm_turbomode", ADMFLAG_CONFIG);
}

public TopMenu_AdminHandleTurboMode(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Turbo Mode: %T", (GetConVarBool(g_hCVTurboMode)?"On":"Off"), param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		Cmd_TurboMode(param, 0);
		RedisplayAdminMenu(topmenu, param);
	}
}