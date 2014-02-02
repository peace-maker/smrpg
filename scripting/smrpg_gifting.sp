#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <smrpg>

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = 
{
	name = "SM:RPG > Credit Gifting",
	author = "Peace-Maker",
	description = "Players are able to gift credits to other players",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	new Handle:hVersion = CreateConVar("smrpg_gifting_version", PLUGIN_VERSION, "SM:RPG Credit Gifting version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	if(hVersion != INVALID_HANDLE)
	{
		SetConVarString(hVersion, PLUGIN_VERSION);
		HookConVarChange(hVersion, ConVar_VersionChanged);
	}
	
	LoadTranslations("common.phrases");
	LoadTranslations("smrpg_gifting.phrases");
	
	AddCommandListener(CmdLstnr_Say, "say");
	AddCommandListener(CmdLstnr_Say, "say_team");
	
	RegConsoleCmd("sm_rpggift", Cmd_RPGGift, "Give your credits to some other player. Usage: sm_rpggift <#userid|authid|name> <credits>");
}

public ConVar_VersionChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	SetConVarString(convar, PLUGIN_VERSION);
}

public Action:Cmd_RPGGift(client, args)
{
	if(!client)
	{
		ReplyToCommand(client, "SM:RPG > This command is ingame only.");
		return Plugin_Handled;
	}
	
	if(args < 2)
	{
		ReplyToCommand(client, "SM:RPG > Usage: sm_rpggift <#userid|authid|name> <credits>");
		return Plugin_Handled;
	}
	
	decl String:sTarget[MAX_NAME_LENGTH];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	decl String:sCredits[10];
	GetCmdArg(2, sCredits, sizeof(sCredits));
	
	HandleGifting(client, sTarget, sCredits);
	return Plugin_Handled;
}

public Action:CmdLstnr_Say(client, const String:command[], argc)
{
	if(!client)
		return Plugin_Continue;
	
	decl String:sText[512];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	
	if(StrContains(sText, "rpggift", false) != 0)
		return Plugin_Continue;
	
	new iIndex, iRet;
	decl String:sArg[MAX_NAME_LENGTH];
	decl String:sTarget[MAX_NAME_LENGTH], String:sCredits[10];
	new iArgCount;
	while(iRet != -1)
	{
		iRet = BreakString(sText[iIndex], sArg, sizeof(sArg));
		iIndex += iRet;
		
		switch(iArgCount)
		{
			case 1:
				strcopy(sTarget, sizeof(sTarget), sArg);
			case 2:
				strcopy(sCredits, sizeof(sCredits), sArg);
		}
		iArgCount++;
	}
	
	if(iArgCount != 3)
	{
		Client_PrintToChat(client, false, "SM:RPG > Usage: sm_rpggift <#userid|authid|name> <credits>");
		return Plugin_Handled;
	}
	
	HandleGifting(client, sTarget, sCredits);
	return Plugin_Continue;
}

HandleGifting(client, String:sTarget[], String:sCredits[])
{
	new iTarget = FindTarget(client, sTarget, true, false);
	if(iTarget == -1)
		return;

	if(iTarget == client)
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Don't give yourself a gift");
		return;
	}
	
	new iCredits = StringToInt(sCredits);
	if(iCredits <= 0)
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Need at least 1 credit");
		return;
	}
	
	new iPlayerCredits = SMRPG_GetClientCredits(client);
	if(iPlayerCredits < iCredits)
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "You don't have enough credits");
		return;
	}
	
	if(!SMRPG_SetClientCredits(client, iPlayerCredits-iCredits))
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Failed to give credits", iCredits, iTarget);
		return;
	}
	
	if(!SMRPG_SetClientCredits(iTarget, SMRPG_GetClientCredits(iTarget)+iCredits))
	{
		// Reset the credits
		if(!SMRPG_SetClientCredits(client, iPlayerCredits))
		{
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Fatal Error giving credits. Credits lost.", iCredits, iTarget);
			LogMessage("%L tried to give %L %d credits. That failed and we weren't able to give %N his credits back.", client, iTarget, iCredits, client);
		}
		else
			Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%t", "Failed to give credits", iCredits, iTarget);
		return;
	}
	
	LogAction(client, iTarget, "Gave %d credits as a gift.", iCredits);
	Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {G}%t", "Gave credits as a gift", client, iCredits, iTarget);
}