#pragma semicolon 1
#include <sourcemod>

#define MAX_COMMAND_NAME_LENGTH 32

enum RPGCommand {
	Handle:c_plugin,
	String:c_command[MAX_COMMAND_NAME_LENGTH],
	Function:c_callback
}

new Handle:g_hCommandList;

RegisterCommandlistNatives()
{
	CreateNative("SMRPG_RegisterCommand", Native_RegisterCommand);
	CreateNative("SMRPG_UnregisterCommand", Native_UnregisterCommand);
}

InitCommandList()
{
	g_hCommandList = CreateArray(_:RPGCommand);
}

Handle:GetCommandList()
{
	return g_hCommandList;
}

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

// native SMRPG_RegisterCommand(const String:command[], SMRPG_TranslateUpgradeCB:callback);
public Native_RegisterCommand(Handle:plugin, numParams)
{
	new String:sCommand[MAX_COMMAND_NAME_LENGTH];
	GetNativeString(1, sCommand, sizeof(sCommand));
	new Function:iCallback = Function:GetNativeCell(2);
	
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
			RemoveFromArray(g_hCommandList, i);
			return;
		}
	}
	
	//ThrowNativeError(SP_ERROR_NATIVE, "There is no command \"%s\" registered by this plugin.", sCommand);
}

public Action:CommandList_DefaultTranslations(client, const String:command[], CommandTranslationType:type, String:translation[], maxlen)
{
	if(type == CommandTranslationType_ShortDescription)
	{
		if(StrEqual(command, "rpgmenu"))
			Format(translation, maxlen, "Opens the rpg main menu");
		else if(StrEqual(command, "rpgrank"))
			Format(translation, maxlen, "Shows your rank or the rank of the target person");
		else if(StrEqual(command, "rpginfo"))
			Format(translation, maxlen, "Shows the purchased upgrades of the target person");
		else if(StrEqual(command, "rpgtop10"))
			Format(translation, maxlen, "Show the SM:RPG top 10");
		else if(StrEqual(command, "rpghelp"))
			Format(translation, maxlen, "Show the SM:RPG help menu");
		return Plugin_Continue;
	}
	else if(type == CommandTranslationType_Description)
	{
		if(StrEqual(command, "rpgmenu"))
			Format(translation, maxlen, "Opens the rpg main menu. You can buy or sell upgrades, view your stats, view this command list and change other settings.");
		else if(StrEqual(command, "rpgrank"))
			Format(translation, maxlen, "Shows your rank or the rank of the target person. Usage rpgrank [name|steamid|#userid]");
		else if(StrEqual(command, "rpginfo"))
			Format(translation, maxlen, "Shows the purchased upgrades of the target person. Usage rpginfo <name|steamid|#userid>");
		else if(StrEqual(command, "rpgtop10"))
			Format(translation, maxlen, "Show the top 10 ranked RPG players on this server.");
		else if(StrEqual(command, "rpghelp"))
			Format(translation, maxlen, "Show the SM:RPG help menu where you get detailed descriptions of the different available upgrades.");
		return Plugin_Continue;
	}
	
	return Plugin_Handled;
}