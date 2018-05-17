#pragma semicolon 1
#include <smlib>
#pragma newdecls required
#include <smrpg>

#define MAX_BAN_REASON_LENGTH 256

enum BanInfo
{
	BanInfo_AccountId,
	BanInfo_Time,
	BanInfo_StartTime,
	String:BanInfo_Reason[MAX_BAN_REASON_LENGTH]
};
StringMap g_hBans;
bool g_bClientBanned[MAXPLAYERS+1];
int g_iClientBanNotificationCount[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG > Ban players",
	author = "Peace-Maker",
	description = "Ban players from RPG features.",
	version = SMRPG_VERSION,
	url = "https://www.wcfan.de/"
}

public void OnPluginStart()
{
	RegAdminCmd("sm_rpgban", Cmd_OnRPGBan, ADMFLAG_BAN, "Ban a player from RPG features. Usage sm_rpgban <name|#steamid|#userid> <length in minutes> <reason>");
	RegAdminCmd("sm_rpgunban", Cmd_OnRPGUnban, ADMFLAG_BAN, "Unban a player from RPG features. Usage sm_rpgunban <name|#steamid|#userid>");

	HookEvent("player_spawn", Event_OnPlayerSpawn);

	// TODO: Integrate RPGBan Player into admin menu.
	// TODO: Make bans persistent in database.
	// TODO: Make messages translatable.

	g_hBans = new StringMap();
	LoadTranslations("common.phrases");
}

public void OnClientAuthorized(int client, const char[] auth)
{
	int iBanInfo[BanInfo];
	if (GetClientBanInfo(client, iBanInfo))
		g_bClientBanned[client] = true;
}

public void OnClientDisconnect(int client)
{
	g_bClientBanned[client] = false;
	g_iClientBanNotificationCount[client] = 0;
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsPlayerAlive(client))
		return;

	if (!IsClientBanned(client))
		return;

	// Don't spam this every spawn.
	if (g_iClientBanNotificationCount[client] > 2)
		return;

	// TODO: Show time until ban expires.
	Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}You are banned from RPG features. You will gain no experience nor be able to use your upgrades.");
	g_iClientBanNotificationCount[client]++;
}

/**
 * SMRPG forwards.
 */
public Action SMRPG_OnAddExperience(int client, const char[] reason, int &iExperience, int other)
{
	// Don't give him any regular experience.
	if(!StrEqual(reason, ExperienceReason_Admin) && IsClientBanned(client))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// Don't let him use any of his upgrades.
public Action SMRPG_OnUpgradeEffect(int target, const char[] shortname, int issuer)
{
	if (IsClientBanned(issuer))
		return Plugin_Handled;
	return Plugin_Continue;
}

// Don't let him buy upgrades.
public Action SMRPG_OnBuyUpgrade(int client, const char[] shortname, int newlevel)
{
	if (IsClientBanned(client))
		return Plugin_Handled;
	return Plugin_Continue;
}

// Don't let him sell upgrades.
public Action SMRPG_OnSellUpgrade(int client, const char[] shortname, int newlevel)
{
	if (IsClientBanned(client))
		return Plugin_Handled;
	return Plugin_Continue;
}

/**
 * Command callbacks
 */
public Action Cmd_OnRPGBan(int client, int args)
{
	if (args < 4)
	{
		ReplyToCommand(client, "Usage sm_rpgban <name|#steamid|#userid> <length in minutes> <reason>");
		return Plugin_Handled;
	}

	char sTarget[MAX_NAME_LENGTH];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	int iTarget = FindTarget(client, sTarget, true, true);
	if (iTarget == -1)
		return Plugin_Handled;

	if (!IsClientAuthorized(iTarget))
	{
		ReplyToCommand(client, "%N isn't authorized with steam yet. Try again later.", iTarget);
		return Plugin_Handled;
	}

	// TODO: Open menu when options are missing.

	char sTime[32];
	GetCmdArg(2, sTime, sizeof(sTime));
	TrimString(sTime);
	int iTime;
	if (StringToIntEx(sTime, iTime) != strlen(sTime))
	{
		ReplyToCommand(client, "Failed to parse the length of the ban. \"%s\" is not a number.", sTime);
		return Plugin_Handled;
	}


	// Get the reason
	char sReason[MAX_BAN_REASON_LENGTH];
	GetCmdArg(3, sReason, sizeof(sReason));
	TrimString(sReason);

	BanClientFromRPG(client, iTarget, iTime, sReason);

	return Plugin_Handled;
}

public Action Cmd_OnRPGUnban(int client, int args)
{
	// Require all arguments for RCON.
	if (args < 2)
	{
		ReplyToCommand(client, "Usage sm_rpgunban <name|#steamid|#userid>");
		return Plugin_Handled;
	}

	char sTarget[MAX_NAME_LENGTH];
	GetCmdArgString(sTarget, sizeof(sTarget));
	StripQuotes(sTarget);
	int iTarget = FindTarget(client, sTarget, true, true);
	if (iTarget == -1)
		return Plugin_Handled;

	if (!IsClientBanned(iTarget))
	{
		ReplyToCommand(client, "%N is not banned from RPG.", iTarget);
		return Plugin_Handled;
	}

	UnbanClientFromRPG(iTarget);
	LogAction(client, iTarget, "%L unbanned %L from RPG features.", client, iTarget);
	return Plugin_Handled;
}

void BanClientFromRPG(int client, int iTarget, int iTime, const char[] sReason)
{
	int iBanInfo[BanInfo];
	if (IsClientBanned(iTarget))
	{
		GetClientBanInfo(iTarget, iBanInfo);
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%N was banned before. Changed the ban from %d minutes to %d minutes. (Old reason: \"%s\")", iBanInfo[BanInfo_Time], iTime, iBanInfo[BanInfo_Reason]);
	}

	iBanInfo[BanInfo_AccountId] = GetSteamAccountID(iTarget);
	iBanInfo[BanInfo_Time] = iTime;
	iBanInfo[BanInfo_StartTime] = GetTime();
	strcopy(iBanInfo[BanInfo_Reason], MAX_BAN_REASON_LENGTH, sReason);

	char sAccountId[64];
	IntToString(iBanInfo[BanInfo_AccountId], sAccountId, sizeof(sAccountId));
	g_hBans.SetArray(sAccountId, iBanInfo[0], view_as<int>(BanInfo));
	g_bClientBanned[iTarget] = true;

	LogAction(client, iTarget, "%L banned %L from RPG features (time %d) (reason \"%s\")", client, iTarget, iTime, sReason);
	ShowActivity2(client, "SM:RPG", "%N banned %N from RPG features for %d minutes. Reason: %s", client, iTarget, iTime, sReason);
}

void UnbanClientFromRPG(int client)
{
	g_bClientBanned[client] = false;

	char sAccountId[64];
	sAccountId = GetClientAccountIDString(client);
	g_hBans.Remove(sAccountId);
	Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}Your RPG ban expired. You may play normally again. Behave yourself!");
}

bool IsClientBanned(int client)
{
	if (!g_bClientBanned[client])
		return false;

	int iBanInfo[BanInfo];
	if (!GetClientBanInfo(client, iBanInfo))
		return false;

	// Permanent ban.
	if (!iBanInfo[BanInfo_Time])
		return true;

	// Make sure the ban still ends in the future.
	bool bBanStillValid = (iBanInfo[BanInfo_StartTime] + iBanInfo[BanInfo_Time]*60) > GetTime();
	if (!bBanStillValid)
		UnbanClientFromRPG(client);

	return bBanStillValid;
}

bool GetClientBanInfo(int client, int iBanInfo[BanInfo])
{
	char sAccountId[64];
	sAccountId = GetClientAccountIDString(client);
	if (!sAccountId[0])
		return false;

	return g_hBans.GetArray(sAccountId, iBanInfo[0], view_as<int>(BanInfo));
}

char GetClientAccountIDString(int client)
{
	char sAccountId[64];

	if (!IsClientAuthorized(client))
		return sAccountId;

	int iAccountId = GetSteamAccountID(client);
	IntToString(iAccountId, sAccountId, sizeof(sAccountId));
	return sAccountId;
}
