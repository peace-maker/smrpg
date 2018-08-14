#pragma semicolon 1
#include <smlib>
#pragma newdecls required
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#define MAX_BAN_REASON_LENGTH 256

enum BanInfo
{
	BanInfo_DatabaseId,
	BanInfo_AccountId,
	BanInfo_Time,
	BanInfo_StartTime,
	String:BanInfo_Reason[MAX_BAN_REASON_LENGTH]
};
StringMap g_hBans;
bool g_bClientBanned[MAXPLAYERS+1];
int g_iClientBanNotificationCount[MAXPLAYERS+1];

TopMenu g_hTopMenu;
int g_iClientPlayerListSelection[MAXPLAYERS+1];
int g_iClientBanTargetUserId[MAXPLAYERS+1];
int g_iClientBanLengthMinutes[MAXPLAYERS+1];

Database g_hDatabase;
#define TBL_BANS "bans"

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

	// TODO: Make messages translatable.

	g_hBans = new StringMap();
	LoadTranslations("common.phrases");

	// See if the menu plugin is already ready
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		// If so, manually fire the callback
		OnAdminMenuReady(topmenu);
	}

	// See if we're late loaded and the database connection is already open.
	SMRPG_CheckDatabaseConnection();
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
	g_iClientPlayerListSelection[client] = 0;
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
public void SMRPG_OnDatabaseConnected(Database database)
{
	g_hDatabase = database;

	DBDriver driver = database.Driver;
	char sDriverIdent[16];
	driver.GetIdentifier(sDriverIdent, sizeof(sDriverIdent));

	char sAutoIncrement[32], sExtraOptions[64];
	if(StrEqual(sDriverIdent, "mysql", false))
	{
		sAutoIncrement = "AUTO_INCREMENT";
		sExtraOptions = " ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
	}
	else if(StrEqual(sDriverIdent, "sqlite", false))
	{
		sAutoIncrement = "AUTOINCREMENT";
	}
	else
	{
		SetFailState("Unknown SQL driver: %s. Aborting..", sDriverIdent);
	}

	char sQuery[512];
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s` (ban_id INTEGER PRIMARY KEY %s, name VARCHAR(128) NOT NULL, steamid INTEGER NOT NULL, start INTEGER NOT NULL, length INTEGER NOT NULL, reason VARCHAR(%d) NOT NULL, unban_time INTEGER DEFAULT NULL)%s", TBL_BANS, sAutoIncrement, MAX_BAN_REASON_LENGTH, sExtraOptions);
	g_hDatabase.Query(SQL_LogError, sQuery);

	// Load all active bans
	// We're prefetching here, since RPG bans are expected to be temporary and the list of banned players at the same time should be fairly short.
	Format(sQuery, sizeof(sQuery), "SELECT ban_id, steamid, start, length, reason FROM `%s` WHERE (length = 0 OR (start + length*60) > %d) AND unban_time IS NULL", TBL_BANS, GetTime());
	g_hDatabase.Query(SQL_LoadBans, sQuery);
}

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
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}You are banned from RPG features. You cannot buy upgrades right now.");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// Don't let him sell upgrades.
public Action SMRPG_OnSellUpgrade(int client, const char[] shortname, int newlevel)
{
	if (IsClientBanned(client))
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}You are banned from RPG features. You cannot sell upgrades right now.");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

/**
 * Command callbacks
 */
public Action Cmd_OnRPGBan(int client, int args)
{
	if (args < 3)
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
	if (args < 1)
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

	AdminUnbanClientFromRPG(client, iTarget);
	ReplyToCommand(client, "SM:RPG > %N was unbanned from RPG.", iTarget);
	LogAction(client, iTarget, "%L unbanned %L from RPG features.", client, iTarget);
	return Plugin_Handled;
}

/**
 * Admin menu integration.
 */
public void OnAdminMenuReady(Handle topmenu)
{
	// Get the rpg category
	TopMenuObject iRPGCategory = FindTopMenuCategory(topmenu, "SM:RPG");
	
	if(iRPGCategory == INVALID_TOPMENUOBJECT)
		return;
	
	if(g_hTopMenu == view_as<TopMenu>(topmenu))
		return;
	
	g_hTopMenu = view_as<TopMenu>(topmenu);
	
	g_hTopMenu.AddItem("RPG Ban Player", TopMenu_AdminHandleBanPlayer, iRPGCategory, "sm_rpgban", ADMFLAG_BAN);
}

public void TopMenu_AdminHandleBanPlayer(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "RPG Ban Player");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayPlayerList(param);
	}
}

void DisplayPlayerList(int client)
{
	Menu hMenu = new Menu(Menu_HandlePlayerlist);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("Select player to ban from RPG:");
	
	char sBuffer[128], sUserId[16], sAuth[64];
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;
		
		// Player is immune?
		if (!CanUserTarget(client, i))
			continue;

		// Still allow to ban players locally.
		if(!GetClientAuthId(i, AuthId_Engine, sAuth, sizeof(sAuth)))
			sAuth[0] = 0;
		
		Format(sBuffer, sizeof(sBuffer), "%N <%s>", i, sAuth);
		IntToString(GetClientUserId(i), sUserId, sizeof(sUserId));
		hMenu.AddItem(sUserId, sBuffer);
	}
	
	g_iClientBanTargetUserId[client] = 0;
	hMenu.DisplayAt(client, g_iClientPlayerListSelection[client], MENU_TIME_FOREVER);
}

public int Menu_HandlePlayerlist(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iClientPlayerListSelection[param1] = 0;
		if(param2 == MenuCancel_ExitBack && g_hTopMenu != null)
			RedisplayAdminMenu(g_hTopMenu, param1);
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		int iUserId = StringToInt(sInfo);
		g_iClientPlayerListSelection[param1] = menu.Selection;
		
		int iTarget = GetClientOfUserId(iUserId);
		if (!iTarget)
		{
			PrintToChat(param1, "%t", "Player no longer available");
			DisplayPlayerList(param1);
			return;
		}

		g_iClientBanTargetUserId[param1] = iUserId;
		
		DisplayBanTimeMenu(param1);
	}
}

void DisplayBanTimeMenu(int client)
{
	int iTarget = GetClientOfUserId(g_iClientBanTargetUserId[client]);
	if (!iTarget)
	{
		PrintToChat(client, "%t", "Player no longer available");
		DisplayPlayerList(client);
		return;
	}

	Menu hMenu = new Menu(Menu_HandleBanTimeList);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("Select length of RPG ban for %N:", iTarget);
	
	hMenu.AddItem("0", "Permanent");
	hMenu.AddItem("10", "10 Minutes");
	hMenu.AddItem("30", "30 Minutes");
	hMenu.AddItem("60", "1 Hour");
	hMenu.AddItem("240", "4 Hours");
	hMenu.AddItem("1440", "1 Day");
	hMenu.AddItem("10080", "1 Week");
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleBanTimeList(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iClientBanTargetUserId[param1] = 0;
		if(param2 == MenuCancel_ExitBack)
			DisplayPlayerList(param1);
	}
	else if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		int iMinutes = StringToInt(sInfo);
		
		int iTarget = GetClientOfUserId(g_iClientBanTargetUserId[param1]);
		if (!iTarget)
		{
			PrintToChat(param1, "%t", "Player no longer available");
			DisplayPlayerList(param1);
			return;
		}

		g_iClientBanLengthMinutes[param1] = iMinutes;
		
		DisplayBanReasonMenu(param1);
	}
}

void DisplayBanReasonMenu(int client)
{
	int iTarget = GetClientOfUserId(g_iClientBanTargetUserId[client]);
	if (!iTarget)
	{
		g_iClientBanLengthMinutes[client] = 0;
		PrintToChat(client, "%t", "Player no longer available");
		DisplayPlayerList(client);
		return;
	}

	Menu hMenu = new Menu(Menu_HandleBanReasonList);
	hMenu.ExitBackButton = true;
	hMenu.SetTitle("Select the reason for the RPG ban for %N:", iTarget);
	
	hMenu.AddItem("Abusive", "Abusive");
	hMenu.AddItem("Racism", "Racism");
	hMenu.AddItem("General cheating/exploits", "General cheating/exploits");
	hMenu.AddItem("Mic spamming", "Mic spamming");
	hMenu.AddItem("Admin disrespect", "Admin disrespect");
	hMenu.AddItem("Camping", "Camping");
	hMenu.AddItem("Team killing", "Team killing");
	hMenu.AddItem("Unacceptable Spray", "Unacceptable Spray");
	hMenu.AddItem("Breaking Server Rules", "Breaking Server Rules");
	hMenu.AddItem("Other", "Other");
	
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleBanReasonList(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iClientBanLengthMinutes[param1] = 0;
		if(param2 == MenuCancel_ExitBack)
			DisplayBanTimeMenu(param1);
	}
	else if(action == MenuAction_Select)
	{
		char sReason[MAX_BAN_REASON_LENGTH];
		menu.GetItem(param2, sReason, sizeof(sReason));
		
		int iTarget = GetClientOfUserId(g_iClientBanTargetUserId[param1]);
		if (!iTarget)
		{
			g_iClientBanLengthMinutes[param1] = 0;
			PrintToChat(param1, "%t", "Player no longer available");
			DisplayPlayerList(param1);
			return;
		}

		BanClientFromRPG(param1, iTarget, g_iClientBanLengthMinutes[param1], sReason);
		g_iClientBanTargetUserId[param1] = 0;
		g_iClientBanLengthMinutes[param1] = 0;
	}
}

/**
 * SQL callbacks
 */
public void SQL_LogError(Database db, DBResultSet results, const char[] error, any data)
{
	if(!results)
	{
		LogError("Error executing query: %s", error);
	}
}

public void SQL_LoadBans(Database db, DBResultSet results, const char[] error, any data)
{
	if(!results)
	{
		LogError("Error loading active bans: %s", error);
		return;
	}

	// Remove any bans in our cache. The database always takes higher priority.
	g_hBans.Clear();

	int iBanInfo[BanInfo];
	char sAccountId[64];
	// SELECT ban_id, steamid, start, length, reason
	while(results.FetchRow())
	{
		iBanInfo[BanInfo_DatabaseId] = results.FetchInt(0);
		iBanInfo[BanInfo_AccountId] = results.FetchInt(1);
		iBanInfo[BanInfo_StartTime] = results.FetchInt(2);
		iBanInfo[BanInfo_Time] = results.FetchInt(3);
		results.FetchString(4, iBanInfo[BanInfo_Reason], MAX_BAN_REASON_LENGTH);

		IntToString(iBanInfo[BanInfo_AccountId], sAccountId, sizeof(sAccountId));
		g_hBans.SetArray(sAccountId, iBanInfo[0], view_as<int>(BanInfo));
	}

	// Check if any connected player is banned.
	for(int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsClientAuthorized(i))
			continue;

		if (GetClientBanInfo(i, iBanInfo))
			g_bClientBanned[i] = true;
	}
}

public void SQL_InsertBan(Database db, DBResultSet results, const char[] error, any iAccountId)
{
	if(!results)
	{
		LogError("Error saving ban: %s", error);
		return;
	}

	char sAccountId[64];
	IntToString(iAccountId, sAccountId, sizeof(sAccountId));

	// See if this is a new ban and we need to save the ban_id.
	int iBanInfo[BanInfo];
	g_hBans.GetArray(sAccountId, iBanInfo[0], view_as<int>(BanInfo));
	if (iBanInfo[BanInfo_DatabaseId] != -1)
		return;

	// Remember the ban id of the ban in the database.
	iBanInfo[BanInfo_DatabaseId] = results.InsertId;
	g_hBans.SetArray(sAccountId, iBanInfo[0], view_as<int>(BanInfo));
}

/**
 * Helpers
 */
void BanClientFromRPG(int client, int iTarget, int iTime, const char[] sReason)
{
	int iBanInfo[BanInfo];
	iBanInfo[BanInfo_DatabaseId] = -1;
	// Don't touch the start time of the ban, if the player is currently banned already.
	// Only change the length of the ban.
	iBanInfo[BanInfo_StartTime] = GetTime();

	if (IsClientBanned(iTarget))
	{
		GetClientBanInfo(iTarget, iBanInfo);
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}%N was banned before. Changed the ban from %d minutes to %d minutes. (Old reason: \"%s\")", iTarget, iBanInfo[BanInfo_Time], iTime, iBanInfo[BanInfo_Reason]);
	}

	iBanInfo[BanInfo_AccountId] = GetSteamAccountID(iTarget);
	iBanInfo[BanInfo_Time] = iTime;
	strcopy(iBanInfo[BanInfo_Reason], MAX_BAN_REASON_LENGTH, sReason);

	char sAccountId[64];
	IntToString(iBanInfo[BanInfo_AccountId], sAccountId, sizeof(sAccountId));
	g_hBans.SetArray(sAccountId, iBanInfo[0], view_as<int>(BanInfo));
	g_bClientBanned[iTarget] = true;

	LogAction(client, iTarget, "%L banned %L from RPG features (time %d) (reason \"%s\")", client, iTarget, iTime, sReason);
	Client_PrintToChatAll(false, "{OG}SM:RPG{N} > {G}%N banned %N from RPG features for %d minutes. Reason: %s", client, iTarget, iTime, sReason);

	if(!g_hDatabase)
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}No database connection available. The ban will only last until the server restarts!");
	}
	else
	{
		char sQuery[1024];
		// New ban
		if (iBanInfo[BanInfo_DatabaseId] == -1)
			g_hDatabase.Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (name, steamid, start, length, reason) VALUES ('%N', %d, %d, %d, '%s')", TBL_BANS, iTarget, iBanInfo[BanInfo_AccountId], iBanInfo[BanInfo_StartTime], iBanInfo[BanInfo_Time], iBanInfo[BanInfo_Reason]);
		else
			g_hDatabase.Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (ban_id, name, steamid, start, length, reason) VALUES (%d, '%N', %d, %d, %d, '%s') ON DUPLICATE KEY UPDATE name=VALUES(name), steamid=VALUES(steamid), start=VALUES(start), length=VALUES(length), reason=VALUES(reason)", TBL_BANS, iBanInfo[BanInfo_DatabaseId], iTarget, iBanInfo[BanInfo_AccountId], iBanInfo[BanInfo_StartTime], iBanInfo[BanInfo_Time], iBanInfo[BanInfo_Reason]);
		g_hDatabase.Query(SQL_InsertBan, sQuery, iBanInfo[BanInfo_AccountId]);
	}
}

void AdminUnbanClientFromRPG(int client, int target)
{
	int iBanInfo[BanInfo];
	GetClientBanInfo(target, iBanInfo);

	UnbanClientFromRPG(target);

	if(!g_hDatabase)
	{
		Client_PrintToChat(client, false, "{OG}SM:RPG{N} > {G}No database connection available. The player might still be banned when the database comes back.");
	}
	else if (iBanInfo[BanInfo_DatabaseId] > 0)
	{
		char sQuery[512];
		Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET unban_time = %d WHERE ban_id = %d", TBL_BANS, GetTime(), iBanInfo[BanInfo_DatabaseId]);
		g_hDatabase.Query(SQL_LogError, sQuery);
	}
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
