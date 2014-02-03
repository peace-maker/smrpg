#pragma semicolon 1
#include <sourcemod>
#include <smlib>

#define MAX_COMMAND_NAME_LENGTH 32

enum RPGCommand {
	Handle:c_plugin,
	String:c_command[MAX_COMMAND_NAME_LENGTH],
	Function:c_callback
}

new Handle:g_hCommandList;

// Command advertising
new Handle:g_hCommandAdvertTimer;
new g_iLastAdvertizedCommand = -1;

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
	return Plugin_Continue;
}

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

public ConVar_AdvertIntervalChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(StrEqual(oldValue, newValue, false))
		return;
	
	ClearHandle(g_hCommandAdvertTimer);
	
	new Float:fInterval = GetConVarFloat(g_hCVCommandAdvertInterval);
	if(fInterval > 0.0)
		g_hCommandAdvertTimer = CreateTimer(fInterval, Timer_ShowCommandAdvert, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}