#pragma semicolon 1
#include <sourcemod>
#include <topmenus>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_commandlist>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#define MAX_COMMAND_NAME_LENGTH 32

ConVar g_hCVCommandAdvertInterval;

enum struct RPGCommand {
	Handle plugin;
	char command[MAX_COMMAND_NAME_LENGTH];
	Function callback;
	TopMenuObject topmenuobject;
}

ArrayList g_hCommandList;

// Command advertising
Handle g_hCommandAdvertTimer;
int g_iLastAdvertizedCommand = -1;

// RPG top menu
TopMenu g_hRPGMenu;
TopMenuObject g_TopMenuCommands;
TopMenuObject g_TopMenuSettings;

// Clientprefs
bool g_bClientHideAdvert[MAXPLAYERS+1];
Handle g_hCookieHideAdvert;

public Plugin myinfo = 
{
	name = "SM:RPG > Command List",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Teaches players about available rpg commands",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("smrpg_commandlist");
	
	CreateNative("SMRPG_RegisterCommand", Native_RegisterCommand);
	CreateNative("SMRPG_UnregisterCommand", Native_UnregisterCommand);
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	ConVar hVersion = CreateConVar("smrpg_commandlist_version", SMRPG_VERSION, "", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != null)
	{
		hVersion.SetString(SMRPG_VERSION);
		hVersion.AddChangeHook(ConVar_VersionChanged);
	}
	
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	LoadTranslations("smrpg_commandlist.phrases");
	
	g_hCommandList = new ArrayList(sizeof(RPGCommand));
	
	g_hCVCommandAdvertInterval = CreateConVar("smrpg_commandadvert_interval", "300", "Show the description of an available commmand in chat every x seconds. (0 = disabled)", 0, true, 0.0);
	g_hCVCommandAdvertInterval.AddChangeHook(ConVar_AdvertIntervalChanged);
	
	TopMenu hTopMenu = SMRPG_GetTopMenu();
	if(hTopMenu != null)
	{
		SMRPG_OnRPGMenuCreated(hTopMenu);
		SMRPG_OnRPGMenuReady(hTopMenu);
	}
	
	if(LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
}

public void ConVar_VersionChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	convar.SetString(SMRPG_VERSION);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookieHideAdvert = RegClientCookie("smrpg_commandlist_hidead", "Hide the messages which teach the players about available commands in SM:RPG.", CookieAccess_Protected);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "smrpg"))
	{
		g_hRPGMenu = null;
		g_TopMenuCommands = INVALID_TOPMENUOBJECT;
	}
}

public void OnMapStart()
{
	float fInterval = g_hCVCommandAdvertInterval.FloatValue;
	if(fInterval > 0.0)
		g_hCommandAdvertTimer = CreateTimer(fInterval, Timer_ShowCommandAdvert, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public void OnClientDisconnect(int client)
{
	g_bClientHideAdvert[client] = true;
}

public void OnClientCookiesCached(int client)
{
	char sBuffer[4];
	GetClientCookie(client, g_hCookieHideAdvert, sBuffer, sizeof(sBuffer));
	g_bClientHideAdvert[client] = StringToInt(sBuffer)==1;
}

public void SMRPG_OnRPGMenuCreated(TopMenu topmenu)
{
	// Block us from being called twice!
	if(g_hRPGMenu == topmenu)
		return;
	
	g_hRPGMenu = topmenu;
	
	g_TopMenuCommands = topmenu.AddCategory(RPGMENU_COMMANDS, TopMenu_CommandCategoryHandler);
}

public void SMRPG_OnRPGMenuReady(TopMenu topmenu)
{
	g_TopMenuSettings = g_hRPGMenu.FindCategory(RPGMENU_SETTINGS);
	if(g_TopMenuSettings != INVALID_TOPMENUOBJECT)
	{
		g_hRPGMenu.AddItem("rpgcmdlist_hidead", TopMenu_SettingsItemHandler, g_TopMenuSettings);
	}
	
	int iSize = g_hCommandList.Length;
	RPGCommand command;
	char sCommandName[MAX_COMMAND_NAME_LENGTH+10];
	for(int i=0;i<iSize;i++)
	{
		g_hCommandList.GetArray(i, command, sizeof(RPGCommand));
		
		Format(sCommandName, sizeof(sCommandName), "rpgcmd_%s", command.command);
		command.topmenuobject = g_hRPGMenu.AddItem(sCommandName, TopMenu_CommandItemHandler, g_TopMenuCommands);
	}
}

public void TopMenu_CommandCategoryHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
		{
			// Always display the current credits in the title
			Format(buffer, maxlength, "SM:RPG %T\n%T\n-----\n", "Commands", param, "Credits", param, SMRPG_GetClientCredits(param));
		}
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxlength, "%T", "Commands", param);
		}
	}
}

public void TopMenu_CommandItemHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sCommandName[MAX_COMMAND_NAME_LENGTH+10];
			topmenu.GetObjName(object_id, sCommandName, sizeof(sCommandName));
			
			RPGCommand command;
			if(!GetCommandByName(sCommandName[7], command))
				return;
		
			char sShortDescription[64];
			if(!GetCommandTranslation(param, command.command, CommandTranslationType_ShortDescription, sShortDescription, sizeof(sShortDescription)))
				return;
			
			Format(buffer, maxlength, "%s: %s", command.command, sShortDescription);
		}
		case TopMenuAction_SelectOption:
		{
			char sCommandName[MAX_COMMAND_NAME_LENGTH+10];
			topmenu.GetObjName(object_id, sCommandName, sizeof(sCommandName));
			
			RPGCommand command;
			if(!GetCommandByName(sCommandName[7], command))
			{
				g_hRPGMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}
			
			char sDescription[256];
			if(GetCommandTranslation(param, command.command, CommandTranslationType_Description, sDescription, sizeof(sDescription)))
				Client_PrintToChat(param, false, "{OG}SM:RPG{N} > {G}%s{N}: %s", command.command, sDescription);
			
			g_hRPGMenu.Display(param, TopMenuPosition_LastCategory);
		}
		case TopMenuAction_DrawOption:
		{
			char sCommandName[MAX_COMMAND_NAME_LENGTH+10];
			topmenu.GetObjName(object_id, sCommandName, sizeof(sCommandName));
			
			RPGCommand command;
			if(!GetCommandByName(sCommandName[7], command) || !IsValidPlugin(command.plugin))
			{
				buffer[0] = ITEMDRAW_IGNORE;
			}
		}
	}
}

public void TopMenu_SettingsItemHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxlength, "%T: %T", "Hide chat adverts", param, (g_bClientHideAdvert[param]?"Yes":"No"), param);
		}
		case TopMenuAction_SelectOption:
		{
			g_bClientHideAdvert[param] = !g_bClientHideAdvert[param];
			if(AreClientCookiesCached(param))
			{
				char sBuffer[4];
				IntToString(g_bClientHideAdvert[param], sBuffer, sizeof(sBuffer));
				SetClientCookie(param, g_hCookieHideAdvert, sBuffer);
			}
			
			g_hRPGMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

// native void SMRPG_RegisterCommand(const char[] command, SMRPG_TranslateUpgradeCB callback);
public int Native_RegisterCommand(Handle plugin, int numParams)
{
	char sCommand[MAX_COMMAND_NAME_LENGTH];
	GetNativeString(1, sCommand, sizeof(sCommand));
	Function iCallback = GetNativeFunction(2);
	
	RPGCommand command;
	int iSize = g_hCommandList.Length;
	for(int i=0;i<iSize;i++)
	{
		g_hCommandList.GetArray(i, command, sizeof(RPGCommand));
		if(StrEqual(sCommand, command.command, false))
		{
			// This command was registered by a different plugin..
			if(plugin != command.plugin)
			{
				ThrowNativeError(SP_ERROR_NATIVE, "RPG command \"%s\" is already registered by a different plugin!", sCommand);
			}
			// This plugin already registered this command. maybe it wants to update the callback function?
			else
			{
				command.callback = iCallback;
				g_hCommandList.SetArray(i, command, sizeof(RPGCommand));
			}
			// We're done here already.
			return;
		}
	}
	
	// Fill the struct with the passed info.
	command.plugin = plugin;
	command.command = sCommand;
	command.callback = iCallback;
	
	char sCommandName[MAX_COMMAND_NAME_LENGTH+10];
	Format(sCommandName, sizeof(sCommandName), "rpgcmd_%s", command.command);
	if(g_hRPGMenu != null && g_TopMenuCommands != INVALID_TOPMENUOBJECT)
		command.topmenuobject = g_hRPGMenu.AddItem(sCommandName, TopMenu_CommandItemHandler, g_TopMenuCommands);
	g_hCommandList.PushArray(command, sizeof(RPGCommand));
}

// native void SMRPG_UnregisterCommand(const char[] command);
public int Native_UnregisterCommand(Handle plugin, int numParams)
{
	char sCommand[MAX_COMMAND_NAME_LENGTH];
	GetNativeString(1, sCommand, sizeof(sCommand));
	
	RPGCommand command;
	int iSize = g_hCommandList.Length;
	for(int i=0;i<iSize;i++)
	{
		g_hCommandList.GetArray(i, command, sizeof(RPGCommand));
		// Found the command and it was registered by this plugin?
		if(StrEqual(sCommand, command.command, false) && plugin == command.plugin)
		{
			if(command.topmenuobject != INVALID_TOPMENUOBJECT && g_hRPGMenu != null && g_TopMenuCommands != INVALID_TOPMENUOBJECT)
				g_hRPGMenu.Remove(command.topmenuobject);
			g_hCommandList.Erase(i);
			return;
		}
	}
	
	//ThrowNativeError(SP_ERROR_NATIVE, "There is no command \"%s\" registered by this plugin.", sCommand);
}

/**
 * Timer callbacks
 */
public Action Timer_ShowCommandAdvert(Handle timer)
{
	// No commands to advertise?!
	int iNumCommands = g_hCommandList.Length;
	if(iNumCommands == 0)
		return Plugin_Continue;
	
	// No players to show stuff to, don't do anything.
	int iPlayerCount = Client_GetCount(true, false);
	if(iPlayerCount == 0)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	RPGCommand command;
	char sText[512];
	int iSentMessages, iTriedCommands;
	do
	{
		// Show the next command
		g_iLastAdvertizedCommand++;
		iTriedCommands++;
		
		// Start with the first command again.
		if(g_iLastAdvertizedCommand >= iNumCommands)
			g_iLastAdvertizedCommand = 0;
		
		g_hCommandList.GetArray(g_iLastAdvertizedCommand, command, sizeof(RPGCommand));
		
		for(int client=1;client<=MaxClients;client++)
		{
			// That client has adverts disabled in his !settings.
			if(g_bClientHideAdvert[client])
				continue;
			
			if(!IsClientInGame(client) || IsFakeClient(client))
				continue;
			
			// That command doesn't have an advert text?
			if(!GetCommandTranslation(client, command.command, CommandTranslationType_Advert, sText, sizeof(sText)))
				continue;
			
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%s", sText);
			iSentMessages++;
		}
		
	}
	// Loop until we finally sent a message or we're at the beginning again.
	// Plugins can return Plugin_Handled when being asked for the advert text, so we skip them and try to display the advert for the next command.
	while(!iSentMessages  && iTriedCommands < iNumCommands);
	
	return Plugin_Continue;
}

/**
 * Convar change handlers
 */
public void ConVar_AdvertIntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(oldValue, newValue, false))
		return;
	
	ClearHandle(g_hCommandAdvertTimer);
	
	float fInterval = g_hCVCommandAdvertInterval.FloatValue;
	if(fInterval > 0.0)
		g_hCommandAdvertTimer = CreateTimer(fInterval, Timer_ShowCommandAdvert, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

/**
 * Helpers
 */
bool GetCommandByName(const char[] sCommand, RPGCommand command)
{
	int iSize = g_hCommandList.Length;
	for(int i=0;i<iSize;i++)
	{
		g_hCommandList.GetArray(i, command, sizeof(RPGCommand));
		if(StrEqual(sCommand, command.command, false))
			return true;
	}
	command.plugin = null;
	command.command[0] = '\0';
	command.callback = INVALID_FUNCTION;
	return false;
}

bool GetCommandTranslation(int client, const char[] sCommand, CommandTranslationType type, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	
	RPGCommand command;
	if(!GetCommandByName(sCommand, command))
		return false;
	
	if(!IsValidPlugin(command.plugin))
		return false;
	
	Action iRet;
	Call_StartFunction(command.plugin, command.callback);
	Call_PushCell(client);
	Call_PushString(sCommand);
	Call_PushCell(type);
	Call_PushStringEx(buffer, maxlen, SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
	Call_PushCell(maxlen);
	Call_Finish(iRet);
	
	return iRet < Plugin_Handled;
}
 
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