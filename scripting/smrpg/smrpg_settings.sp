#pragma semicolon 1
#include <sourcemod>

new Handle:g_hSettings;
new Handle:g_hfwdOnSettingsLoaded;

RegisterSettingsNatives()
{
	CreateNative("SMRPG_GetSetting", Native_GetSetting);
	CreateNative("SMRPG_SetSetting", Native_SetSetting);
}

RegisterSettingsForwards()
{
	g_hfwdOnSettingsLoaded = CreateGlobalForward("SMRPG_OnSettingsLoaded", ET_Ignore);
}

InitSettings()
{
	g_hSettings = CreateTrie();
}

LoadSettingsTable()
{
	decl String:sQuery[64];
	Format(sQuery, sizeof(sQuery), "SELECT setting, value FROM %s", TBL_SETTINGS);
	SQL_TQuery(g_hDatabase, SQL_ReadSettings, sQuery);
}

public SQL_ReadSettings(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogError("Error reading settings: %s", error);
		return;
	}
	
	// Remove any old settings.
	ClearTrie(g_hSettings);
	
	decl String:sKey[64], String:sValue[256];
	while(SQL_MoreRows(hndl))
	{
		if(!SQL_FetchRow(hndl))
			continue;
		
		SQL_FetchString(hndl, 0, sKey, sizeof(sKey));
		SQL_FetchString(hndl, 1, sValue, sizeof(sValue));
		SetTrieString(g_hSettings, sKey, sValue);
	}
	
	CheckDatabaseVersion();
	
	Call_StartForward(g_hfwdOnSettingsLoaded);
	Call_Finish();
}

bool:GetSetting(const String:sKey[], String:sValue[], maxlen)
{
	return GetTrieString(g_hSettings, sKey, sValue, maxlen);
}

SetSetting(const String:sKey[], String:sValue[])
{
	SetTrieString(g_hSettings, sKey, sValue);
	decl String:sQuery[512], String:sKeyEscaped[strlen(sKey)*2+1], String:sValueEscaped[strlen(sValue)*2+1];
	SQL_EscapeString(g_hDatabase, sKey, sKeyEscaped, strlen(sKey)*2+1);
	SQL_EscapeString(g_hDatabase, sValue, sValueEscaped, strlen(sValue)*2+1);
	Format(sQuery, sizeof(sQuery), "REPLACE INTO %s (setting, value) VALUES (\"%s\", \"%s\");", TBL_SETTINGS, sKeyEscaped, sValueEscaped);
	SQL_TQuery(g_hDatabase, SQL_DoNothing, sQuery);
}

public Native_GetSetting(Handle:plugin, numParams)
{
	decl String:sKey[64];
	GetNativeString(1, sKey, sizeof(sKey));
	new String:sBuffer[256];
	if(!GetSetting(sKey, sBuffer, sizeof(sBuffer)))
		return false;
	new iLength = GetNativeCell(3);
	SetNativeString(2, sBuffer, iLength);
	return true;
}

public Native_SetSetting(Handle:plugin, numParams)
{
	decl String:sKey[64], String:sValue[256];
	GetNativeString(1, sKey, sizeof(sKey));
	GetNativeString(2, sValue, sizeof(sValue));
	SetSetting(sKey, sValue);
}