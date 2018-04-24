/**
 * Idea by freddukes' SourceRPG eventscript.
 * 
 * Increase experience earnings and credit reward for one map.
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <smrpg>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma newdecls required

ConVar g_hCVRPGSaveData;
bool g_bRPGSaveDataOld;

ConVar g_hCVTurboMode;
ConVar g_hCVTurboModeAnnounce;
ConVar g_hCVPersistChanges;
ConVar g_hCVExperienceMultiplier;
ConVar g_hCVCreditsMultiplier;

bool g_bPersistChanges;
bool g_bMapEnded;

bool g_bClientLeveledUp[MAXPLAYERS+1];

TopMenu g_hTopMenu;

public Plugin myinfo = 
{
	name = "SM:RPG > Turbo Mode",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Highers levelup rates for the current map. Stats are not saved.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	AutoExecConfig_SetFile("plugin.smrpg_turbomode");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(null);

	g_hCVTurboMode = AutoExecConfig_CreateConVar("smrpg_turbomode_enabled", "0", "Enable SM:RPG turbo mode with higher experience and credits rates.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCVTurboModeAnnounce = AutoExecConfig_CreateConVar("smrpg_turbomode_announce", "1", "Announce turbomode to all players in chat when it's enabled.", 0, true, 0.0, true, 1.0);
	g_hCVPersistChanges = AutoExecConfig_CreateConVar("smrpg_turbomode_persist_changes", "0", "Keep the player's stat changes while turbo mode is active and don't set them to level 1 beforehand?", 0, true, 0.0, true, 1.0);
	g_hCVExperienceMultiplier = AutoExecConfig_CreateConVar("smrpg_turbomode_expmultiplier", "3", "Multiply all earned experience by this value.", 0, true, 1.0);
	g_hCVCreditsMultiplier = AutoExecConfig_CreateConVar("smrpg_turbomode_creditsmultiplier", "2", "Multiply all earned credits by this value.", 0, true, 1.0);
	
	g_hCVTurboMode.AddChangeHook(ConVar_TurboModeChanged);

	AutoExecConfig_ExecuteFile();
	
	RegAdminCmd("sm_turbomode", Cmd_TurboMode, ADMFLAG_CONFIG, "Enables SM:RPG turbo mode. Higher experience rates for everyone until mapchange. Stats are not saved.", "smrpg");
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg_turbomode.phrases");
	
	// See if the menu plugin is already ready
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}
}

/**
 * Public forwards
 */
public void OnAllPluginsLoaded()
{
	// Disable saving stuff to the database during turbo mode.
	g_hCVRPGSaveData = FindConVar("smrpg_save_data");
	if(g_hCVRPGSaveData != null)
		g_hCVRPGSaveData.AddChangeHook(ConVar_SaveDataChanged);
}

public void OnConfigsExecuted()
{
	// Trigger the config, if it's set already.
	g_bRPGSaveDataOld = g_hCVRPGSaveData.BoolValue;
	if(g_hCVTurboMode.BoolValue)
		ConVar_TurboModeChanged(g_hCVTurboMode, "0", "1");
}

public void OnMapStart()
{
	g_bMapEnded = false;
}

public void OnMapEnd()
{
	g_bMapEnded = true;
	
	// Disable turbo mode.
	g_hCVTurboMode.SetBool(false);
}

/**
 * ConVar change callbacks
 */
public void ConVar_SaveDataChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// DON'T SAVE ANYTHING DURING TURBO MODE!
	if(g_hCVTurboMode.BoolValue && !g_bPersistChanges && convar.BoolValue)
		convar.SetBool(false);
	else
		g_bRPGSaveDataOld = convar.BoolValue;
}

public void ConVar_TurboModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(oldValue, newValue))
		return;
	
	// Enable turbo mode now.
	if(g_hCVTurboMode.BoolValue)
	{
		g_bPersistChanges = g_hCVPersistChanges.BoolValue;
		// We don't want any changes happening now to be saved to the database.
		if(!g_bPersistChanges)
		{
			// Remember the old value before enabling turbo mode.
			g_bRPGSaveDataOld = g_hCVRPGSaveData.BoolValue;
			
			// Save all current progress to the database!
			SMRPG_FlushDatabase();
			
			// Disable saving.
			g_hCVRPGSaveData.SetBool(false);
			
			// Reset all ingame players.
			for(int i=1;i<=MaxClients;i++)
			{
				if(IsClientInGame(i))
					SMRPG_ResetClientStats(i);
			}
		}
		
		// Restart the round.
		//ServerCommand("mp_restartgame 2");
		
		if(g_bPersistChanges)
			Client_PrintToChatAll(false, "{OG}SM:RPG{N} > %t", "Turbo mode enabled save stats", g_hCVExperienceMultiplier.FloatValue, g_hCVCreditsMultiplier.FloatValue);
		else
			Client_PrintToChatAll(false, "{OG}SM:RPG{N} > %t", "Turbo mode enabled discard stats", g_hCVExperienceMultiplier.FloatValue, g_hCVCreditsMultiplier.FloatValue);
		
		// Start showing a constant message on the screen.
		if(Timer_DisplayTurboModeHud(null) == Plugin_Continue)
			CreateTimer(1.0, Timer_DisplayTurboModeHud, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	}
	else
	{
		// We don't want any changes happening now to be saved to the database.
		if (!g_bPersistChanges)
		{
			// Reset saving
			g_hCVRPGSaveData.SetBool(g_bRPGSaveDataOld);
			
			if(!g_bMapEnded)
			{
				// Reconnect all clients so their old level is loaded.
				for(int i=1;i<=MaxClients;i++)
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
		}
		
		Client_PrintToChatAll(false, "{OG}SM:RPG{N} > %t", "Turbo mode disabled");
	}
}

/**
 * Event handlers
 */
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(IsPlayerAlive(client) && g_hCVTurboMode.BoolValue && g_hCVTurboModeAnnounce.BoolValue)
	{
		if(g_bPersistChanges)
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > %t", "Turbo mode enabled save stats", g_hCVExperienceMultiplier.FloatValue, g_hCVCreditsMultiplier.FloatValue);
		else
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > %t", "Turbo mode enabled discard stats", g_hCVExperienceMultiplier.FloatValue, g_hCVCreditsMultiplier.FloatValue);
	}
}

/**
 * Command handlers
 */
public Action Cmd_TurboMode(int client, int args)
{
	if(!g_hCVTurboMode.BoolValue)
	{
		LogAction(client, -1, "%L enabled SM:RPG turbo mode.", client);
		ReplyToCommand(client, "SM:RPG > %t", "Command Turbo mode enabled");
		g_hCVTurboMode.SetBool(true);
	}
	else
	{
		LogAction(client, -1, "%L disabled SM:RPG turbo mode.", client);
		ReplyToCommand(client, "SM:RPG > %t", "Command Turbo mode disabled");
		g_hCVTurboMode.SetBool(false);
	}
	
	return Plugin_Handled;
}

/**
 * Timer callbacks
 */
public Action Timer_DisplayTurboModeHud(Handle timer)
{
	if(!g_hCVTurboMode.BoolValue)
		return Plugin_Stop;
	
	SetHudTextParams(0.8, 0.2, 2.0, 255, 0, 0, 200);
	
	char sBuffer[64];
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			Format(sBuffer, sizeof(sBuffer), "%T", "Turbo mode", i);
			if(ShowHudText(i, -1, sBuffer) == -1)
			{
				//PrintToServer("HudMsg not supported?");
				return Plugin_Stop;
			}
		}
	}
	
	return Plugin_Continue;
}

/**
 * SMRPG callbacks
 */
public void SMRPG_OnClientLoaded(int client)
{
	// Reset client to 0 during turbo mode if we don't want to save the changes.
	if(!g_bPersistChanges && g_hCVTurboMode.BoolValue)
		SMRPG_ResetClientStats(client);
}

public Action SMRPG_OnAddExperience(int client, const char[] reason, int &iExperience, int other)
{
	if(!g_hCVTurboMode.BoolValue)
		return Plugin_Continue;
	
	if(!StrEqual(reason, ExperienceReason_Admin))
	{
		// Higher experience rate
		iExperience = RoundToCeil(float(iExperience) * g_hCVExperienceMultiplier.FloatValue);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action SMRPG_OnClientLevel(int client, int oldlevel, int newlevel)
{
	// The next credits change should be multiplied!
	g_bClientLeveledUp[client] = true;
	return Plugin_Continue;
}

public Action SMRPG_OnClientCredits(int client, int oldcredits, int newcredits)
{
	if(g_bClientLeveledUp[client])
	{
		g_bClientLeveledUp[client] = false;
		
		// Credits were actually given not taken
		if(g_hCVTurboMode.BoolValue && oldcredits < newcredits)
		{
			int iInc = newcredits - oldcredits;
			iInc = RoundToCeil(float(iInc) * g_hCVCreditsMultiplier.FloatValue);
			
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
public void OnAdminMenuReady(Handle hndl)
{
	TopMenu topmenu = TopMenu.FromHandle(hndl);
	// Get the rpg category
	TopMenuObject iRPGCategory = topmenu.FindCategory("SM:RPG");
	
	if(iRPGCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == topmenu)
		return;
	
	g_hTopMenu = topmenu;
	
	topmenu.AddItem("Toggle Turbo Mode", TopMenu_AdminHandleTurboMode, iRPGCategory, "sm_turbomode", ADMFLAG_CONFIG);
}

public void TopMenu_AdminHandleTurboMode(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%T: %T", "Turbo mode", param, (g_hCVTurboMode.BoolValue?"On":"Off"), param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		// Make sure to toggle turbo mode after the menu closed.
		// SM doesn't like clients to disconnect during a menu callback.
		RequestFrame(Frame_AfterMenuHandle, GetClientUserId(param));
	}
}

public void Frame_AfterMenuHandle(any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;
	
	// Toggle turbo mode
	Cmd_TurboMode(client, 0);
	if(IsClientInGame(client))
	{
		RedisplayAdminMenu(g_hTopMenu, client);
	}
}