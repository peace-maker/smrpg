#pragma semicolon 1
#include <sourcemod>
#include <smrpg>

//#define USE_SIMPLE_PROCESSOR 1

// Prefer chat processor if available..
#if defined USE_SIMPLE_PROCESSOR
// https://forums.alliedmods.net/showthread.php?t=198501
#include <scp>
#include <colorvariables>
#define PROCESSOR_TYPE "(Simple Chat Processor)"
#else
// https://forums.alliedmods.net/showthread.php?t=286913
#include <chat-processor>
#define PROCESSOR_TYPE "(Chat Processor)"
#endif

#pragma newdecls required

ConVar g_hCVMaxChatRank;
ConVar g_hCVShowLevel;

public Plugin myinfo =
{
	name = "SM:RPG > Chat Tags " ... PROCESSOR_TYPE,
	author = "Peace-Maker",
	description = "Add RPG level in front of chat messages.",
	version = SMRPG_VERSION,
	url = "https://www.wcfan.de/"
};

public void OnPluginStart()
{
	LoadTranslations("smrpg_chattags.phrases");
	
	g_hCVMaxChatRank = CreateConVar("smrpg_chattags_maxrank", "10", "Show the rank of the player up until this value in front of his name in chat. -1 to disable, 0 to show for everyone.", _, true, -1.0);
	g_hCVShowLevel = CreateConVar("smrpg_chattags_showlevel", "1", "Show the level of the player in front of his name in chat?", _, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "smrpg_chattags");
}

// Add the RPG level to the name.
#if defined USE_SIMPLE_PROCESSOR
public Action OnChatMessage(int& author, Handle recipients, char[] name, char[] message)
#else
public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
#endif
{
	// Show the rank of the Top X players in front of their name.
	char sRankTag[64];
	int iMaxRank = g_hCVMaxChatRank.IntValue;
	if (iMaxRank > -1)
	{
		int iRank = SMRPG_GetClientRank(author);
		if (iRank > 0 && (iMaxRank == 0 || iRank <= iMaxRank))
			Format(sRankTag, sizeof(sRankTag), "%T", "Rank Chat Tag", author, iRank);
	}

	// Add the current RPG level to the name.
	char sLevelTag[64];
	if (g_hCVShowLevel.BoolValue)
	{
		int iLevel = SMRPG_GetClientLevel(author);
		Format(sLevelTag, sizeof(sLevelTag), "%T", "Level Chat Tag", author, iLevel);
	}
	
	Format(name, MAXLENGTH_NAME, "%s%s\x03%s", sRankTag, sLevelTag, name);
	
	// SCP doesn't process color tags on its own.
#if defined USE_SIMPLE_PROCESSOR
	CProcessVariables(name, MAXLENGTH_NAME, false);
#endif
	return Plugin_Changed;
}