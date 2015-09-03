#pragma semicolon 1
#include <sourcemod>
#include <topmenus>
#include <smlib>
#include <smrpg>
#include <smrpg_commandlist>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#define PLUGIN_VERSION "1.0"

#define MAX_COMMAND_NAME_LENGTH 32

new Handle:g_hCVCommandAdvertInterval;

enum RPGCommand {
	Handle:c_plugin,
	String:c_command[MAX_COMMAND_NAME_LENGTH],
	Function:c_callback,
	TopMenuObject:c_topmenuobject
}

new Handle:g_hCommandList;

// Command advertising
new Handle:g_hCommandAdvertTimer;
new g_iLastAdvertizedCommand = -1;

// RPG top menu
new Handle:g_hRPGMenu;
new TopMenuObject:g_TopMenuCommands;
new TopMenuObject:g_TopMenuSettings;

// Clientprefs
new bool:g_bClientHideAdvert[MAXPLAYERS+1];
new Handle:g_hCookieHideAdvert;

public Plugin:myinfo = 
{
	name = "SM:RPG > Command List",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Teaches players about available rpg commands",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("smrpg_commandlist");
	
	CreateNative("SMRPG_RegisterCommand", Native_RegisterCommand);
	CreateNative("SMRPG_UnregisterCommand", Native_UnregisterCommand);
	
	return APLRes_Success;
}

public OnPluginStart()
{
	new Handle:hVersion = CreateConVar("smrpg_commandlist_version", PLUGIN_VERSION, "", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != INVALID_HANDLE)
	{
		SetConVarString(hVersion, PLUGIN_VERSION);
		HookConVarChange(hVersion, ConVar_VersionChanged);
	}
	
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg.phrases");
	LoadTranslations("smrpg_commandlist.phrases");
	
	g_hCommandList = CreateArray(_:RPGCommand);
	
	g_hCVCommandAdvertInterval = CreateConVar("smrpg_commandadvert_interval", "300", "Show the description of an available commmand in chat every x seconds. (0 = disabled)", 0, true, 0.0);
	HookConVarChange(g_hCVCommandAdvertInterval, ConVar_AdvertIntervalChanged);
	
	new Handle:hTopMenu = SMRPG_GetTopMenu();
	if(hTopMenu != INVALID_HANDLE)
	{
		SMRPG_OnRPGMenuCreated(hTopMenu);
		SMRPG_OnRPGMenuReady(hTopMenu);
	}
	
	if(LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
}

public ConVar_VersionChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	SetConVarString(convar, PLUGIN_VERSION);
}

public OnLibraryAdded(const String:name[])
{
	if(StrEqual(name, "clientprefs"))
	{
		g_hCookieHideAdvert = RegClientCookie("smrpg_commandlist_hidead", "Hide the messages which teach the players about available commands in SM:RPG.", CookieAccess_Protected);
	}
}

public OnLibraryRemoved(const String:name[])
{
	if(StrEqual(name, "smrpg"))
	{
		g_hRPGMenu = INVALID_HANDLE;
		g_TopMenuCommands = INVALID_TOPMENUOBJECT;
	}
}

public OnMapStart()
{
	new Float:fInterval = GetConVarFloat(g_hCVCommandAdvertInterval);
	if(fInterval > 0.0)
		g_hCommandAdvertTimer = CreateTimer(fInterval, Timer_ShowCommandAdvert, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public OnClientDisconnect(client)
{
	g_bClientHideAdvert[client] = true;
}

public OnClientCookiesCached(client)
{
	decl String:sBuffer[4];
	GetClientCookie(client, g_hCookieHideAdvert, sBuffer, sizeof(sBuffer));
	g_bClientHideAdvert[client] = StringToInt(sBuffer)==1;
}

public SMRPG_OnRPGMenuCreated(Handle:topmenu)
{
	// Block us from being called twice!
	if(g_hRPGMenu == topmenu)
		return;
	
	g_hRPGMenu = topmenu;
	
	g_TopMenuCommands = AddToTopMenu(g_hRPGMenu, RPGMENU_COMMANDS, TopMenuObject_Category, TopMenu_CommandCategoryHandler, INVALID_TOPMENUOBJECT);
}

public SMRPG_OnRPGMenuReady(Handle:topmenu)
{
	g_TopMenuSettings = FindTopMenuCategory(g_hRPGMenu, RPGMENU_SETTINGS);
	if(g_TopMenuSettings != INVALID_TOPMENUOBJECT)
	{
		AddToTopMenu(g_hRPGMenu, "rpgcmdlist_hidead", TopMenuObject_Item, TopMenu_SettingsItemHandler, g_TopMenuSettings);
	}
	
	new iSize = GetArraySize(g_hCommandList);
	new iCommand[RPGCommand];
	decl String:sCommandName[MAX_COMMAND_NAME_LENGTH+10];
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(g_hCommandList, i, iCommand[0], _:RPGCommand);
		
		Format(sCommandName, sizeof(sCommandName), "rpgcmd_%s", iCommand[c_command]);
		iCommand[c_topmenuobject] = AddToTopMenu(g_hRPGMenu, sCommandName, TopMenuObject_Item, TopMenu_CommandItemHandler, g_TopMenuCommands);
	}
}

public TopMenu_CommandCategoryHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
		{
			// Always display the current credits in the title
			if(GetFeatureStatus(FeatureType_Native, "SetTopMenuTitleCaching") == FeatureStatus_Available)
				Format(buffer, maxlength, "%T\n-----\n", "Credits", param, SMRPG_GetClientCredits(param));
			// If this version of sourcemod doesn't support changing the topmenu title dynamically, don't print the credits..
			else
				Format(buffer, maxlength, "%T\n-----\n", "Commands", param);
		}
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxlength, "%T", "Commands", param);
		}
	}
}

public TopMenu_CommandItemHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			decl String:sCommandName[MAX_COMMAND_NAME_LENGTH+10];
			GetTopMenuObjName(topmenu, object_id, sCommandName, sizeof(sCommandName));
			
			new iCommand[RPGCommand];
			if(!GetCommandByName(sCommandName[7], iCommand))
				return;
		
			decl String:sShortDescription[64];
			if(!GetCommandTranslation(param, iCommand[c_command], CommandTranslationType_ShortDescription, sShortDescription, sizeof(sShortDescription)))
				return;
			
			Format(buffer, maxlength, "%s: %s", iCommand[c_command], sShortDescription);
		}
		case TopMenuAction_SelectOption:
		{
			decl String:sCommandName[MAX_COMMAND_NAME_LENGTH+10];
			GetTopMenuObjName(topmenu, object_id, sCommandName, sizeof(sCommandName));
			
			new iCommand[RPGCommand];
			if(!GetCommandByName(sCommandName[7], iCommand))
			{
				DisplayTopMenu(g_hRPGMenu, param, TopMenuPosition_LastCategory);
				return;
			}
			
			decl String:sDescription[256];
			if(GetCommandTranslation(param, iCommand[c_command], CommandTranslationType_Description, sDescription, sizeof(sDescription)))
				Client_PrintToChat(param, false, "{OG}SM:RPG{N} > {G}%s{N}: %s", iCommand[c_command], sDescription);
			
			DisplayTopMenu(g_hRPGMenu, param, TopMenuPosition_LastCategory);
		}
		case TopMenuAction_DrawOption:
		{
			decl String:sCommandName[MAX_COMMAND_NAME_LENGTH+10];
			GetTopMenuObjName(topmenu, object_id, sCommandName, sizeof(sCommandName));
			
			new iCommand[RPGCommand];
			if(!GetCommandByName(sCommandName[7], iCommand) || !IsValidPlugin(iCommand[c_plugin]))
			{
				buffer[0] = ITEMDRAW_IGNORE;
			}
		}
	}
}

public TopMenu_SettingsItemHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
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
				decl String:sBuffer[4];
				IntToString(g_bClientHideAdvert[param], sBuffer, sizeof(sBuffer));
				SetClientCookie(param, g_hCookieHideAdvert, sBuffer);
			}
			
			DisplayTopMenu(g_hRPGMenu, param, TopMenuPosition_LastCategory);
		}
	}
}

// native SMRPG_RegisterCommand(const String:command[], SMRPG_TranslateUpgradeCB:callback);
public Native_RegisterCommand(Handle:plugin, numParams)
{
	new String:sCommand[MAX_COMMAND_NAME_LENGTH];
	GetNativeString(1, sCommand, sizeof(sCommand));
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
	new Function:iCallback = GetNativeFunction(2);
#else
	new Function:iCallback = Function:GetNativeCell(2);
#endif
	
	new iCommand[RPGCommand];
	new iSize = GetArraySize(g_hCommandList);
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(g_hCommandList, i, iCommand[0], _:RPGCommand);
		if(StrEqual(sCommand, iCommand[c_command], false))
		{
			// This command was registered by a different plugin..
			if(plugin != iCommand[c_plugin])
			{
				ThrowNativeError(SP_ERROR_NATIVE, "RPG command \"%s\" is already registered by a different plugin!", sCommand);
			}
			// This plugin already registered this command. maybe it wants to update the callback function?
			else
			{
				iCommand[c_callback] = iCallback;
				SetArrayArray(g_hCommandList, i, iCommand[0], _:RPGCommand);
			}
			// We're done here already.
			return;
		}
	}
	
	// Fill the struct with the passed info.
	iCommand[c_plugin] = plugin;
	strcopy(iCommand[c_command], MAX_COMMAND_NAME_LENGTH, sCommand);
	iCommand[c_callback] = iCallback;
	
	decl String:sCommandName[MAX_COMMAND_NAME_LENGTH+10];
	Format(sCommandName, sizeof(sCommandName), "rpgcmd_%s", iCommand[c_command]);
	if(g_hRPGMenu != INVALID_HANDLE && g_TopMenuCommands != INVALID_TOPMENUOBJECT)
		iCommand[c_topmenuobject] = AddToTopMenu(g_hRPGMenu, sCommandName, TopMenuObject_Item, TopMenu_CommandItemHandler, g_TopMenuCommands);
	PushArrayArray(g_hCommandList, iCommand[0], _:RPGCommand);
}

// native SMRPG_UnregisterCommand(const String:command[]);
public Native_UnregisterCommand(Handle:plugin, numParams)
{
	new String:sCommand[MAX_COMMAND_NAME_LENGTH];
	GetNativeString(1, sCommand, sizeof(sCommand));
	
	new iCommand[RPGCommand];
	new iSize = GetArraySize(g_hCommandList);
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(g_hCommandList, i, iCommand[0], _:RPGCommand);
		// Found the command and it was registered by this plugin?
		if(StrEqual(sCommand, iCommand[c_command], false) && plugin == iCommand[c_plugin])
		{
			if(iCommand[c_topmenuobject] != INVALID_TOPMENUOBJECT && g_hRPGMenu != INVALID_HANDLE && g_TopMenuCommands != INVALID_TOPMENUOBJECT)
				RemoveFromTopMenu(g_hRPGMenu, iCommand[c_topmenuobject]);
			RemoveFromArray(g_hCommandList, i);
			return;
		}
	}
	
	//ThrowNativeError(SP_ERROR_NATIVE, "There is no command \"%s\" registered by this plugin.", sCommand);
}

/**
 * Timer callbacks
 */
public Action:Timer_ShowCommandAdvert(Handle:timer)
{
	// No commands to advertise?!
	new iNumCommands = GetArraySize(g_hCommandList);
	if(iNumCommands == 0)
		return Plugin_Continue;
	
	// No players to show stuff to, don't do anything.
	new iPlayerCount = Client_GetCount(true, false);
	if(iPlayerCount == 0)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new iCommand[RPGCommand];
	decl String:sText[512];
	new iSentMessages, iTriedCommands;
	do
	{
		// Show the next command
		g_iLastAdvertizedCommand++;
		iTriedCommands++;
		
		// Start with the first command again.
		if(g_iLastAdvertizedCommand >= iNumCommands)
			g_iLastAdvertizedCommand = 0;
		
		GetArrayArray(g_hCommandList, g_iLastAdvertizedCommand, iCommand[0], _:RPGCommand);
		
		for(new client=1;client<=MaxClients;client++)
		{
			// That client has adverts disabled in his !settings.
			if(g_bClientHideAdvert[client])
				continue;
			
			if(!IsClientInGame(client) || IsFakeClient(client))
				continue;
			
			// That command doesn't have an advert text?
			if(!GetCommandTranslation(client, iCommand[c_command], CommandTranslationType_Advert, sText, sizeof(sText)))
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
public ConVar_AdvertIntervalChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(StrEqual(oldValue, newValue, false))
		return;
	
	ClearHandle(g_hCommandAdvertTimer);
	
	new Float:fInterval = GetConVarFloat(g_hCVCommandAdvertInterval);
	if(fInterval > 0.0)
		g_hCommandAdvertTimer = CreateTimer(fInterval, Timer_ShowCommandAdvert, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

/**
 * Helpers
 */
bool:GetCommandByName(const String:sCommand[], iCommand[RPGCommand])
{
	new iSize = GetArraySize(g_hCommandList);
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(g_hCommandList, i, iCommand[0], _:RPGCommand);
		if(StrEqual(sCommand, iCommand[c_command], false))
			return true;
	}
	iCommand[c_plugin] = INVALID_HANDLE;
	iCommand[c_command][0] = '\0';
	iCommand[c_callback] = INVALID_FUNCTION;
	return false;
}

bool:GetCommandTranslation(client, const String:sCommand[], CommandTranslationType:type, String:buffer[], maxlen)
{
	buffer[0] = '\0';
	
	new iCommand[RPGCommand];
	if(!GetCommandByName(sCommand, iCommand))
		return false;
	
	if(!IsValidPlugin(iCommand[c_plugin]))
		return false;
	
	new Action:iRet;
	Call_StartFunction(iCommand[c_plugin], iCommand[c_callback]);
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