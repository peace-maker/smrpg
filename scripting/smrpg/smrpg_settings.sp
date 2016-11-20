#pragma semicolon 1
#include <sourcemod>

StringMap g_hSettings;
Handle g_hfwdOnSettingsLoaded;

void RegisterSettingsNatives()
{
	CreateNative("SMRPG_GetSetting", Native_GetSetting);
	CreateNative("SMRPG_SetSetting", Native_SetSetting);
}

void RegisterSettingsForwards()
{
	g_hfwdOnSettingsLoaded = CreateGlobalForward("SMRPG_OnSettingsLoaded", ET_Ignore);
}

void InitSettings()
{
	g_hSettings = new StringMap();
}

void LoadSettingsTable()
{
	char sQuery[64];
	Format(sQuery, sizeof(sQuery), "SELECT setting, value FROM %s", TBL_SETTINGS);
	g_hDatabase.Query(SQL_ReadSettings, sQuery);
}

public void SQL_ReadSettings(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Error reading settings: %s", error);
		return;
	}
	
	// Remove any old settings.
	g_hSettings.Clear();
	
	char sKey[64], sValue[256];
	while(results.MoreRows)
	{
		if(!results.FetchRow())
			continue;
		
		results.FetchString(0, sKey, sizeof(sKey));
		results.FetchString(1, sValue, sizeof(sValue));
		g_hSettings.SetString(sKey, sValue);
	}
	
	// Make sure there is a last reset time in the database.
	if(!GetSetting("last_reset", sValue, sizeof(sValue)))
	{
		IntToString(GetTime(), sValue, sizeof(sValue));
		SetSetting("last_reset", sValue);
	}
	
	CheckDatabaseVersion();
	
	Call_StartForward(g_hfwdOnSettingsLoaded);
	Call_Finish();
}

bool GetSetting(const char[] sKey, char[] sValue, int maxlen)
{
	return g_hSettings.GetString(sKey, sValue, maxlen);
}

void SetSetting(const char[] sKey, char[] sValue)
{
	g_hSettings.SetString(sKey, sValue);
	char sQuery[512];
	char[] sKeyEscaped = new char[strlen(sKey)*2+1];
	char[] sValueEscaped = new char[strlen(sValue)*2+1];
	g_hDatabase.Escape(sKey, sKeyEscaped, strlen(sKey)*2+1);
	g_hDatabase.Escape(sValue, sValueEscaped, strlen(sValue)*2+1);
	Format(sQuery, sizeof(sQuery), "REPLACE INTO %s (setting, value) VALUES (\"%s\", \"%s\");", TBL_SETTINGS, sKeyEscaped, sValueEscaped);
	g_hDatabase.Query(SQL_DoNothing, sQuery);
}

public int Native_GetSetting(Handle plugin, int numParams)
{
	char sKey[64];
	GetNativeString(1, sKey, sizeof(sKey));
	char sBuffer[256];
	if(!GetSetting(sKey, sBuffer, sizeof(sBuffer)))
		return 0;
	int iLength = GetNativeCell(3);
	SetNativeString(2, sBuffer, iLength);
	return 1;
}

public int Native_SetSetting(Handle plugin, int numParams)
{
	char sKey[64], sValue[256];
	GetNativeString(1, sKey, sizeof(sKey));
	GetNativeString(2, sValue, sizeof(sValue));
	SetSetting(sKey, sValue);
}