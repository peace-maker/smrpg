#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <autoexecconfig> // https://github.com/Impact123/AutoExecConfig

enum struct InternalUpgradeInfo
{
	int index; // index in g_hUpgrades array
	int databaseId; // the upgrade_id in the upgrades table
	bool databaseLoading; // are we currently loading the databaseid of this upgrade?
	bool enabled; // upgrade enabled?
	bool unavailable; // plugin providing this upgrade gone?
	int maxLevelBarrier; // upper limit of maxlevel setting. Can't set maxlevel higher than that.
	int maxLevel; // Maximal level a player can get for this upgrade
	int startLevel; // The level players start with, when they first join the server.
	int startCost; // The amount of credits the first level costs
	int incCost; // The amount of credits each level costs more
	int adminFlag; // Admin flag(s) this upgrade is restricted to
	bool enableVisuals; // Enable the visual effects of this upgrade by default?
	bool enableSounds; // Enable the audio effects of this upgrade by default?
	bool allowBots; // Are bots allowed to use this upgrade?
	int teamlock; // Can only players of a certain team use this upgrade?
	Function queryCallback; // callback called, when a player bought/sold the upgrade
	Function activeCallback; // callback called, to see, if a player is currently under the effect of that upgrade
	Function translationCallback; // callback called, when the upgrade's name is about to get displayed.
	Function resetCallback; // callback called, when the upgrade's effect should be removed.
	Handle plugin; // The plugin which registered the upgrade
	// Convar handles to track changes and upgrade the right value in the cache
	ConVar enableConvar;
	ConVar maxLevelConvar;
	ConVar startLevelConvar;
	ConVar startCostConvar;
	ConVar incCostConvar;
	ConVar adminFlagConvar;
	ConVar visualsConvar;
	ConVar soundsConvar;
	ConVar botsConvar;
	ConVar teamlockConvar;
	
	// Topmenu object ids
	TopMenuObject topmenuUpgrades;
	TopMenuObject topmenuSell;
	TopMenuObject topmenuUpgradeSettings;
	TopMenuObject topmenuHelp;
	
	char name[MAX_UPGRADE_NAME_LENGTH];
	char shortName[MAX_UPGRADE_SHORTNAME_LENGTH];
	char description[MAX_UPGRADE_DESCRIPTION_LENGTH];
}

ArrayList g_hUpgrades;
Handle g_hfwdOnUpgradeEffect;
Handle g_hfwdOnUpgradeSettingsChanged;
Handle g_hfwdOnUpgradeRegistered;
Handle g_hfwdOnUpgradeUnregistered;

void RegisterUpgradeNatives()
{
	CreateNative("SMRPG_RegisterUpgradeType", Native_RegisterUpgradeType);
	CreateNative("SMRPG_UnregisterUpgradeType", Native_UnregisterUpgradeType);
	CreateNative("SMRPG_CreateUpgradeConVar", Native_CreateUpgradeConVar);
	
	// native void SMRPG_SetUpgradeBuySellCallback(const char[] shortname, SMRPG_UpgradeQueryCB cb);
	CreateNative("SMRPG_SetUpgradeBuySellCallback", Native_SetUpgradeBuySellCallback);
	// native void SMRPG_SetUpgradeActiveQueryCallback(const char[] shortname, SMRPG_ActiveQueryCB cb);
	CreateNative("SMRPG_SetUpgradeActiveQueryCallback", Native_SetUpgradeActiveQueryCallback);
	CreateNative("SMRPG_SetUpgradeTranslationCallback", Native_SetUpgradeTranslationCallback);
	CreateNative("SMRPG_SetUpgradeResetCallback", Native_SetUpgradeResetCallback);
	CreateNative("SMRPG_SetUpgradeDefaultCosmeticEffect", Native_SetUpgradeDefaultCosmeticEffect);
	CreateNative("SMRPG_UpgradeExists", Native_UpgradeExists);
	CreateNative("SMRPG_GetUpgradeInfo", Native_GetUpgradeInfo);
	CreateNative("SMRPG_ResetUpgradeEffectOnClient", Native_ResetUpgradeEffectOnClient);
	CreateNative("SMRPG_RunUpgradeEffect", Native_RunUpgradeEffect);
	
	CreateNative("SMRPG_CheckUpgradeAccess", Native_CheckUpgradeAccess);
}

void RegisterUpgradeForwards()
{
	g_hfwdOnUpgradeEffect = CreateGlobalForward("SMRPG_OnUpgradeEffect", ET_Hook, Param_Cell, Param_String, Param_Cell);
	g_hfwdOnUpgradeSettingsChanged = CreateGlobalForward("SMRPG_OnUpgradeSettingsChanged", ET_Ignore, Param_String);
	g_hfwdOnUpgradeRegistered = CreateGlobalForward("SMRPG_OnUpgradeRegistered", ET_Ignore, Param_String);
	g_hfwdOnUpgradeUnregistered = CreateGlobalForward("SMRPG_OnUpgradeUnregistered", ET_Ignore, Param_String);
}

void InitUpgrades()
{
	g_hUpgrades = new ArrayList(sizeof(InternalUpgradeInfo));
}

// native void SMRPG_RegisterUpgradeType(const char[] name, const char[] shortname, const char[] description, int maxlevelbarrier, bool bDefaultEnable, int iDefaultMaxLevel, int iDefaultStartCost, int iDefaultCostInc, int iAdminFlags=0, SMRPG_UpgradeQueryCB querycb, SMRPG_ActiveQueryCB activecb);
public int Native_RegisterUpgradeType(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sName = new char[len+1];
	GetNativeString(1, sName, len+1);
	
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);

	// There already is an upgrade with that name loaded. Don't load it twice. shortnames have to be unique.
	InternalUpgradeInfo upgrade;
	bool bAlreadyLoaded;
	if(GetUpgradeByShortname(sShortName, upgrade))
	{
		if(IsValidUpgrade(upgrade) && upgrade.plugin != plugin)
		{
			char sPluginName[32] = "Unloaded";
			GetPluginInfo(upgrade.plugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
			return ThrowNativeError(SP_ERROR_NATIVE, "An upgrade with name \"%s\" is already registered by plugin \"%s\".", sShortName, sPluginName);
		}
		
		bAlreadyLoaded = true;
	}
	
	bool bWasUnavailable = upgrade.unavailable;
	
	GetNativeStringLength(3, len);
	char[] sDescription = new char[len+1];
	GetNativeString(3, sDescription, len+1);
	
	int iMaxLevelBarrier = GetNativeCell(4);
	bool bDefaultEnable = view_as<bool>(GetNativeCell(5));
	int iDefaultMaxLevel = GetNativeCell(6);
	int iDefaultStartCost = GetNativeCell(7);
	int iDefaultCostInc = GetNativeCell(8);
	int iDefaultAdminFlags = GetNativeCell(9);
	Function queryCallback = GetNativeFunction(10);
	Function activeCallback = GetNativeFunction(11);
	
	if(!bAlreadyLoaded)
	{
		upgrade.index = g_hUpgrades.Length;
		upgrade.databaseId = -1;
		upgrade.databaseLoading = false;
		TopMenu hTopMenu = GetRPGTopMenu();
		if(hTopMenu != null)
		{
			char sBuffer[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			if(GetUpgradesCategory() != INVALID_TOPMENUOBJECT)
			{
				Format(sBuffer, sizeof(sBuffer), "rpgupgrade_%s", sShortName);
				upgrade.topmenuUpgrades = hTopMenu.AddItem(sBuffer, TopMenu_HandleUpgrades, GetUpgradesCategory());
			}
			if(GetSellCategory() != INVALID_TOPMENUOBJECT)
			{
				Format(sBuffer, sizeof(sBuffer), "rpgsell_%s", sShortName);
				upgrade.topmenuSell = hTopMenu.AddItem(sBuffer, TopMenu_HandleSell, GetSellCategory());
			}
			if(GetUpgradeSettingsCategory() != INVALID_TOPMENUOBJECT)
			{
				Format(sBuffer, sizeof(sBuffer), "rpgupgrsettings_%s", sShortName);
				upgrade.topmenuUpgradeSettings = hTopMenu.AddItem(sBuffer, TopMenu_HandleUpgradeSettings, GetUpgradeSettingsCategory());
			}
			if(GetHelpCategory() != INVALID_TOPMENUOBJECT)
			{
				Format(sBuffer, sizeof(sBuffer), "rpghelp_%s", sShortName);
				upgrade.topmenuHelp = hTopMenu.AddItem(sBuffer, TopMenu_HandleHelp, GetHelpCategory());
			}
		}
	}
	upgrade.enabled = bDefaultEnable;
	upgrade.unavailable = false;
	upgrade.maxLevelBarrier = iMaxLevelBarrier;
	upgrade.maxLevel = iDefaultMaxLevel;
	upgrade.startLevel = 0;
	upgrade.startCost = iDefaultStartCost;
	upgrade.incCost = iDefaultCostInc;
	upgrade.enableVisuals = true;
	upgrade.enableSounds = true;
	upgrade.queryCallback = queryCallback;
	upgrade.activeCallback = activeCallback;
	upgrade.translationCallback = INVALID_FUNCTION;
	upgrade.resetCallback = INVALID_FUNCTION;
	upgrade.plugin = plugin;
	upgrade.visualsConvar = null;
	upgrade.soundsConvar = null;
	strcopy(upgrade.name, sizeof(upgrade.name), sName);
	strcopy(upgrade.shortName, sizeof(upgrade.shortName), sShortName);
	strcopy(upgrade.description, sizeof(upgrade.description), sDescription);
	
	char sCvarName[64], sCvarDescription[256], sValue[16];
	
	// Make sure the subfolder exists.
	if(!DirExists("cfg/sourcemod/smrpg"))
		CreateDirectory("cfg/sourcemod/smrpg", FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC|FPERM_G_READ|FPERM_G_WRITE|FPERM_G_EXEC|FPERM_O_READ|FPERM_O_EXEC);
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_upgrade_%s", sShortName);
	AutoExecConfig_SetFile(sCvarName, "sourcemod/smrpg");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(plugin);
	
	// Register convars
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_enable", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "Enables (1) or disables (0) the %s upgrade.", sName);
	IntToString(view_as<int>(bDefaultEnable), sValue, sizeof(sValue));
	ConVar hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 0.0, true, 1.0);
	hCvar.AddChangeHook(ConVar_UpgradeChanged);
	upgrade.enableConvar = hCvar;
	upgrade.enabled = hCvar.BoolValue;
	
	// TODO: Handle maxlevel > maxlevelbarrier etc. rpgi.cpp CVARItemMaxLvl!
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_maxlevel", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "%s upgrade maximum level. This is the maximum level players can reach for this upgrade.\nWhen changed, all players who bought a higher level before are refunded with the full upgrade costs and set down to the new maxlevel.", sName);
	IntToString(iDefaultMaxLevel, sValue, sizeof(sValue));
	hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 1.0);
	hCvar.AddChangeHook(ConVar_UpgradeMaxLevelChanged);
	upgrade.maxLevelConvar = hCvar;
	upgrade.maxLevel = hCvar.IntValue;
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_startlevel", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "%s upgrade start level. The initial levels players get of this upgrade when they first join the server.", sName);
	hCvar = AutoExecConfig_CreateConVar(sCvarName, "0", sCvarDescription, 0, true, 0.0);
	hCvar.AddChangeHook(ConVar_UpgradeChanged);
	upgrade.startLevelConvar = hCvar;
	upgrade.startLevel = hCvar.IntValue;
	if (upgrade.startLevel > upgrade.maxLevel)
	{
		LogError("Upgrade %s smrpg_%s_startlevel convar (%d) is set higher than the maxlevel (%d). Clamping.", sName, sShortName, upgrade.startLevel, upgrade.maxLevel);
		upgrade.startLevel = upgrade.maxLevel;
		hCvar.SetInt(upgrade.startLevel);
	}
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_cost", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "%s upgrade start cost. The initial amount of credits the first level of this upgrade costs.", sName);
	IntToString(iDefaultStartCost, sValue, sizeof(sValue));
	hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 0.0);
	hCvar.AddChangeHook(ConVar_UpgradeChanged);
	upgrade.startCostConvar = hCvar;
	upgrade.startCost = hCvar.IntValue;
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_icost", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "%s upgrade cost increment for each level. The amount of credits added to the costs for each level: Buy upgrade level x -> startcost + x * incrementcost.", sName);
	IntToString(iDefaultCostInc, sValue, sizeof(sValue));
	hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 0.0);
	hCvar.AddChangeHook(ConVar_UpgradeChanged);
	upgrade.incCostConvar = hCvar;
	upgrade.incCost = hCvar.IntValue;
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_adminflag", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "Required admin flag to use this upgrade. Leave blank to allow everyone to use this upgrade. This also checks for a \"smrpg_upgrade_%s\" admin override for permissions.", sShortName);
	GetAdminFlagStringFromBits(iDefaultAdminFlags, sValue, sizeof(sValue));
	hCvar = AutoExecConfig_CreateConVar(sCvarName, sValue, sCvarDescription, 0, true, 0.0);
	hCvar.AddChangeHook(ConVar_UpgradeChanged);
	upgrade.adminFlagConvar = hCvar;
	hCvar.GetString(sValue, sizeof(sValue));
	upgrade.adminFlag = ReadFlagString(sValue);
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_allowbots", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "Allow bots to use the %s upgrade?", sName);
	hCvar = AutoExecConfig_CreateConVar(sCvarName, "1", sCvarDescription, 0, true, 0.0, true, 1.0);
	hCvar.AddChangeHook(ConVar_UpgradeChanged);
	upgrade.botsConvar = hCvar;
	upgrade.allowBots = hCvar.BoolValue;
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_%s_teamlock", sShortName);
	Format(sCvarDescription, sizeof(sCvarDescription), "Restrict access to the %s upgrade to a team?\nOptions:\n\t0: Disable restriction and allow the upgrade to be used by players in any team.\n\t2: Only allow players of the RED/Terrorist team to use this upgrade.\n\t3: Only allow players of the BLU/Counter-Terrorist team to use this upgrade.", sName);
	hCvar = AutoExecConfig_CreateConVar(sCvarName, "0", sCvarDescription, 0, true, 0.0, true, 3.0);
	hCvar.AddChangeHook(ConVar_UpgradeChanged);
	upgrade.teamlockConvar = hCvar;
	upgrade.teamlock = hCvar.IntValue;
	
	AutoExecConfig_ExecuteFile();
	
	//AutoExecConfig_CleanFile();
	
	// We already got info about this. Don't insert it a second time.
	if(bAlreadyLoaded)
	{
		SaveUpgradeConfig(upgrade);
	}
	// It's a new upgrade. Insert it.
	else
	{
		g_hUpgrades.PushArray(upgrade, sizeof(InternalUpgradeInfo));
		
		// New upgrade! Add it to each connected player's list
		for(int i=1;i<=MaxClients;i++)
		{
			if(IsClientConnected(i))
			{
				InitPlayerNewUpgrade(i);
			}
		}
	}
	
	// We're not in the process of fetching the upgrade info from the database.
	if(!upgrade.databaseLoading)
	{
		// This upgrade wasn't fetched or inserted into the database yet.
		if(upgrade.databaseId == -1)
		{
			// Inform other plugins, that this upgrade is loaded.
			CallUpgradeRegisteredForward(sShortName);
			
			CheckUpgradeDatabaseEntry(upgrade);
		}
		// This upgrade was registered already previously and we can use the cached values.
		else if(bAlreadyLoaded && bWasUnavailable)
		{
			// Inform other plugins, that this upgrade is loaded.
			CallUpgradeRegisteredForward(sShortName);
			
			RequestFrame(RequestFrame_OnFrame, upgrade.index);
		}
	}
	return 0;
}

// native void SMRPG_UnregisterUpgradeType(const char[] shortname);
public int Native_UnregisterUpgradeType(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	int iSize = g_hUpgrades.Length;
	InternalUpgradeInfo upgrade;
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(!IsValidUpgrade(upgrade))
			continue;
		
		if(StrEqual(upgrade.shortName, sShortName, false))
		{
			// Set this upgrade as unavailable! Don't process anything in the future.
			upgrade.unavailable = true;
			SaveUpgradeConfig(upgrade);
			
			// Inform other plugins, that this upgrade is unloaded.
			Call_StartForward(g_hfwdOnUpgradeUnregistered);
			Call_PushString(sShortName);
			Call_Finish();
			
			return 0;
		}
	}
	
	return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
}

// native ConVar SMRPG_CreateUpgradeConVar(const char[] shortname, const char[] name, const char[] defaultValue, const char[] description="", flags=0, bool hasMin=false, float min=0.0, bool hasMax=false, float max=0.0);
public int Native_CreateUpgradeConVar(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	GetNativeStringLength(2, len);
	char[] name = new char[len+1];
	GetNativeString(2, name, len+1);
	
	GetNativeStringLength(3, len);
	char[] defaultValue = new char[len+1];
	GetNativeString(3, defaultValue, len+1);
	
	GetNativeStringLength(4, len);
	char[] description = new char[len+1];
	GetNativeString(4, description, len+1);
	
	int flags = GetNativeCell(5);
	bool hasMin = view_as<bool>(GetNativeCell(6));
	float min = view_as<float>(GetNativeCell(7));
	bool hasMax = view_as<bool>(GetNativeCell(8));
	float max = view_as<float>(GetNativeCell(9));
	
	char sFileName[PLATFORM_MAX_PATH];
	Format(sFileName, sizeof(sFileName), "smrpg_upgrade_%s", sShortName);
	AutoExecConfig_SetFile(sFileName, "sourcemod/smrpg");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(plugin);
	
	ConVar hCvar = AutoExecConfig_CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
	
	// AutoExecConfig_ExecuteFile(); // No need to call AutoExecConfig again. The file is already in the list.
	// Just execute the config again, to get the values?
	ServerCommand("exec sourcemod/smrpg/smrpg_upgrade_%s.cfg", sShortName);
	
	//AutoExecConfig_CleanFile();
	
	return view_as<int>(hCvar);
}

// native bool SMRPG_UpgradeExists(const char[] shortname);
public int Native_UpgradeExists(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade))
		return false;
	
	return IsValidUpgrade(upgrade);
}

// native SMRPG_GetUpgradeInfo(const char[] shortname, UpgradeInfo upgrade);
public int Native_GetUpgradeInfo(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	// Keep this future proof. If the calling plugin wants more information than we got, only return as much as we know.
	// If it wants less info, only write less.
	int arraysize = GetNativeCell(3);
	if(arraysize > sizeof(UpgradeInfo))
		arraysize = sizeof(UpgradeInfo);
	
	UpgradeInfo publicUpgrade;
	publicUpgrade.enabled = upgrade.enabled;
	publicUpgrade.maxLevelBarrier = upgrade.maxLevelBarrier;
	publicUpgrade.maxLevel = upgrade.maxLevel;
	publicUpgrade.startCost = upgrade.startCost;
	publicUpgrade.incCost = upgrade.incCost;
	publicUpgrade.adminFlag = upgrade.adminFlag;
	publicUpgrade.teamlock = upgrade.teamlock;
	strcopy(publicUpgrade.name, MAX_UPGRADE_NAME_LENGTH, upgrade.name);
	strcopy(publicUpgrade.shortName, MAX_UPGRADE_SHORTNAME_LENGTH, upgrade.shortName);
	strcopy(publicUpgrade.description, MAX_UPGRADE_DESCRIPTION_LENGTH, upgrade.description);
	publicUpgrade.startLevel = upgrade.startLevel;
	
	SetNativeArray(2, publicUpgrade, arraysize);
	return 0;
}

// native void SMRPG_SetUpgradeBuySellCallback(const char[] shortname, SMRPG_UpgradeQueryCB cb);
public int Native_SetUpgradeBuySellCallback(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	if(upgrade.plugin != plugin)
		return ThrowNativeError(SP_ERROR_NATIVE, "BuySell callback has to be from the same plugin the upgrade was registered in.");
	
	upgrade.queryCallback = GetNativeFunction(2);
	
	SaveUpgradeConfig(upgrade);
	return 0;
}

// native void SMRPG_SetUpgradeActiveQueryCallback(const char[] shortname, SMRPG_ActiveQueryCB cb);
public int Native_SetUpgradeActiveQueryCallback(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	if(upgrade.plugin != plugin)
		return ThrowNativeError(SP_ERROR_NATIVE, "Active query callback has to be from the same plugin the upgrade was registered in.");
	
	upgrade.activeCallback = GetNativeFunction(2);
	
	SaveUpgradeConfig(upgrade);
	return 0;
}

// native void SMRPG_SetUpgradeTranslationCallback(const char[] shortname, SMRPG_TranslateUpgrade cb);
public int Native_SetUpgradeTranslationCallback(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	if(upgrade.plugin != plugin)
		return ThrowNativeError(SP_ERROR_NATIVE, "Translation callback has to be from the same plugin the upgrade was registered in.");
	
	upgrade.translationCallback = GetNativeFunction(2);
	
	SaveUpgradeConfig(upgrade);
	return 0;
}

// native void SMRPG_SetUpgradeResetCallback(const char[] shortname, SMRPG_ResetEffectCB cb);
public int Native_SetUpgradeResetCallback(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	if(upgrade.plugin != plugin)
		return ThrowNativeError(SP_ERROR_NATIVE, "ResetEffect callback has to be from the same plugin the upgrade was registered in.");
	
	upgrade.resetCallback = GetNativeFunction(2);
	
	SaveUpgradeConfig(upgrade);
	return 0;
}

// native void SMRPG_SetUpgradeDefaultCosmeticEffect(const char[] shortname, SMRPG_FX effect, bool bDefaultEnable);
public int Native_SetUpgradeDefaultCosmeticEffect(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] sShortName = new char[len+1];
	GetNativeString(1, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	}
	
	SMRPG_FX iFX = view_as<SMRPG_FX>(GetNativeCell(2));
	bool bDefaultEnable = view_as<bool>(GetNativeCell(3));
	
	char sCvarName[64], sCvarDescription[256];
	
	Format(sCvarName, sizeof(sCvarName), "smrpg_upgrade_%s", sShortName);
	AutoExecConfig_SetFile(sCvarName, "sourcemod/smrpg");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetPlugin(plugin);
	
	switch(iFX)
	{
		case SMRPG_FX_Visuals:
		{
			Format(sCvarName, sizeof(sCvarName), "smrpg_%s_visuals", sShortName);
			Format(sCvarDescription, sizeof(sCvarDescription), "Show the visual effects of upgrade %s by default?", upgrade.name);
			ConVar hCvar = AutoExecConfig_CreateConVar(sCvarName, (bDefaultEnable?"1":"0"), sCvarDescription, 0, true, 0.0, true, 1.0);
			hCvar.AddChangeHook(ConVar_UpgradeChanged);
			upgrade.visualsConvar = hCvar;
			upgrade.enableVisuals = hCvar.BoolValue;
		}
		case SMRPG_FX_Sounds:
		{
			Format(sCvarName, sizeof(sCvarName), "smrpg_%s_sounds", sShortName);
			Format(sCvarDescription, sizeof(sCvarDescription), "Play the sounds of upgrade %s by default?", upgrade.name);
			ConVar hCvar = AutoExecConfig_CreateConVar(sCvarName, (bDefaultEnable?"1":"0"), sCvarDescription, 0, true, 0.0, true, 1.0);
			hCvar.AddChangeHook(ConVar_UpgradeChanged);
			upgrade.soundsConvar = hCvar;
			upgrade.enableSounds = hCvar.BoolValue;
		}
	}
	
	SaveUpgradeConfig(upgrade);
	return 0;
}

// native SMRPG_ResetUpgradeEffectOnClient(int client, const char[] shortname);
public int Native_ResetUpgradeEffectOnClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	// If there is no reset callback registered, we can't do anything here.
	if(upgrade.resetCallback == INVALID_FUNCTION)
		return 0;
	
	Call_StartFunction(upgrade.plugin, upgrade.resetCallback);
	Call_PushCell(client);
	Call_Finish();
	return 0;
}

// native bool SMRPG_RunUpgradeEffect(int target, const char[] shortname, int issuer=-1);
public int Native_RunUpgradeEffect(Handle plugin, int numParams)
{
	int target = GetNativeCell(1);
	if(target < 0 || target > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid target client index %d.", target);
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	// Validate the client index of the person starting the effect
	int issuer = -1;
	if (numParams > 2)
	{
		issuer = GetNativeCell(3);
		if (issuer < -1 || issuer > MaxClients)
			return ThrowNativeError(SP_ERROR_NATIVE, "Invalid issuer client index %d.", issuer);
	}
	
	// If there is no explicit different issuer given, the upgrade effect is on the target itself.
	if (issuer == -1)
		issuer = target;
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);

	// Don't allow this client to use the upgrade, if he doesn't have the required admin flag.
	// Don't inform the other plugins at all.
	if(!HasAccessToUpgrade(issuer, upgrade))
	{
		// Might still allow them to use the effects of the upgrade, if they already got a level for it.
		int iLevel = GetClientPurchasedUpgradeLevel(issuer, upgrade.index);
		if(iLevel <= 0 || !g_hCVAllowPresentUpgradeUsage.BoolValue)
			return false;
	}
	
	// Block the effect from running, if the client is in the wrong team and there is a teamlock on the upgrade.
	if(!IsClientInLockedTeam(issuer, upgrade))
		return false;
	
	// Don't allow bots to use this upgrade at all and don't inform other plugins that this effect would be about to start.
	if(!upgrade.allowBots && IsFakeClient(issuer))
		return false;
	
	Action result;
	Call_StartForward(g_hfwdOnUpgradeEffect);
	Call_PushCell(target);
	Call_PushString(sShortName);
	Call_PushCell(issuer);
	Call_Finish(result);
	
	return result < Plugin_Handled;
}

// native bool SMRPG_CheckUpgradeAccess(int client, const char[] shortname);
public int Native_CheckUpgradeAccess(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client < 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d.", client);
	
	int len;
	GetNativeStringLength(2, len);
	char[] sShortName = new char[len+1];
	GetNativeString(2, sShortName, len+1);
	
	InternalUpgradeInfo upgrade;
	if(!GetUpgradeByShortname(sShortName, upgrade) || !IsValidUpgrade(upgrade))
		return ThrowNativeError(SP_ERROR_NATIVE, "No upgrade named \"%s\" loaded.", sShortName);
	
	return HasAccessToUpgrade(client, upgrade);
}

/**
 * Frame hook callbacks
 */
// This is called one frame after some upgrade plugin reregistered itself after reload.
// This way OnLibraryAdded was run completely in the upgrade plugin and all convars and other stuff is initialized correctly.
public void RequestFrame_OnFrame(any upgradeindex)
{
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(upgradeindex, upgrade);
	
	// Plugin doesn't care? OK :(
	if(upgrade.queryCallback == INVALID_FUNCTION)
		return;
	
	// Inform the upgrade plugin, that these players need the effect applied again.
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(GetClientSelectedUpgradeLevel(i, upgrade.index) <= 0)
			continue;
		
		// Notify plugin about it.
		Call_StartFunction(upgrade.plugin, upgrade.queryCallback);
		Call_PushCell(i);
		Call_PushCell(UpgradeQueryType_Buy);
		Call_Finish();
	}
}

/**
 * Helpers
 */
int GetUpgradeCount()
{
	return g_hUpgrades.Length;
}

void GetUpgradeByIndex(int iIndex, InternalUpgradeInfo upgrade)
{
	GetArrayArray(g_hUpgrades, iIndex, upgrade, sizeof(InternalUpgradeInfo));
}

bool GetUpgradeByShortname(const char[] sShortName, InternalUpgradeInfo upgrade)
{
	int iSize = g_hUpgrades.Length;
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(StrEqual(upgrade.shortName, sShortName, false))
		{
			return true;
		}
	}
	return false;
}

bool GetUpgradeByDatabaseId(int iDatabaseId, InternalUpgradeInfo upgrade)
{
	int iSize = g_hUpgrades.Length;
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade.databaseId == iDatabaseId)
		{
			return true;
		}
	}
	return false;
}

int GetUpgradeCost(int iItemIndex, int iLevel)
{
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(iItemIndex, upgrade);
	if(iLevel <= 1)
		return upgrade.startCost;
	else
		return upgrade.startCost + upgrade.incCost * (iLevel-1);
}

int GetUpgradeSale(int iItemIndex, int iLevel)
{
	int iCost = GetUpgradeCost(iItemIndex, iLevel);
	
	float fSalePercent = g_hCVSalePercent.FloatValue;
	if(fSalePercent == 1.0)
		return iCost;
	
	if(iLevel <= 1)
		return iCost;
	
	int iSale = RoundToFloor(float(iCost) * (fSalePercent > 1.0 ? (fSalePercent/100.0) : fSalePercent) + 0.5);
	int iCreditsInc = g_hCVCreditsInc.IntValue;
	if(iCreditsInc <= 1)
		return iSale;
	else
		iSale = (iSale + RoundToFloor(float(iCreditsInc)/2.0)) / iCreditsInc * iCreditsInc;
	
	if(iSale > iCost)
		return iCost;
	
	return iSale;
}

bool IsValidUpgrade(InternalUpgradeInfo upgrade)
{
	// This plugin is available (again)?
	bool bUnavailable = !IsValidPlugin(upgrade.plugin);
	if(upgrade.unavailable != bUnavailable)
	{
		upgrade.unavailable = bUnavailable;
		SaveUpgradeConfig(upgrade);
	}
	return !upgrade.unavailable;
}

void SaveUpgradeConfig(InternalUpgradeInfo upgrade)
{
	g_hUpgrades.SetArray(upgrade.index, upgrade, sizeof(InternalUpgradeInfo));
}

bool IsUpgradeEffectActive(int client, InternalUpgradeInfo upgrade)
{
	if(!IsValidUpgrade(upgrade))
		return false;
	
	// See if the whole plugin is active at all.
	if(!SMRPG_IsEnabled())
		return false;
	
	// See if the upgrade is disabled for all players.
	if(!upgrade.enabled)
		return false;
	
	// See if the player is a bot and RPG is disabled for bots.
	if(IgnoreBotPlayer(client))
		return false;
	
	// Won't be active, if we don't know if he has it yet.
	if (!IsPlayerDataLoaded(client))
		return false;
	
	// Client didn't buy the upgrade yet?
	if(GetClientSelectedUpgradeLevel(client, upgrade.index) <= 0)
		return false;
	
	// Not active, if the client has the upgrade disabled himself.
	if(!IsClientUpgradeEnabled(client, upgrade.index))
		return false;
	
	// Can't be active if client isn't in the team this upgrade is locked to.
	if(!IsClientInLockedTeam(client, upgrade))
		return false;
	
	// Can't be active if the client doesn't have the permissions.
	if(!HasAccessToUpgrade(client, upgrade))
		return false;
	
	// Passive upgrades are always on once the player has at least level 1.
	if(upgrade.activeCallback == INVALID_FUNCTION)
		return true;
	
	// Ask the plugin itself now.
	bool bActive;
	Call_StartFunction(upgrade.plugin, upgrade.activeCallback);
	Call_PushCell(client);
	Call_Finish(bActive);
	
	return bActive;
}

bool HasAccessToUpgrade(int client, InternalUpgradeInfo upgrade)
{
	char sFlag[MAX_UPGRADE_SHORTNAME_LENGTH+15];
	Format(sFlag, sizeof(sFlag), "smrpg_upgrade_%s", upgrade.shortName);
	
	// Don't allow this client to use the upgrade, if he doesn't have the required admin flag.
	return CheckCommandAccess(client, sFlag, upgrade.adminFlag, true);
}

// Checks whether a client is in the correct team, if the upgrade is locked to one.
bool IsClientInLockedTeam(int client, InternalUpgradeInfo upgrade)
{
	// This upgrade isn't locked at all. No restriction.
	if(upgrade.teamlock <= 1)
		return true;

	int iTeam = GetClientTeam(client);
	// Always grant access to all upgrades, if the player is in spectator mode.
	if(iTeam <= 1)
		return true;
	
	// See if the player is in the allowed team.
	return iTeam == upgrade.teamlock;
}

void GetUpgradeTranslatedName(int client, int iUpgradeIndex, char[] name, int maxlen)
{
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	strcopy(name, maxlen, upgrade.name);
	
	// No translation callback registered? Fall back to the name set when registering the upgrade.
	if(upgrade.translationCallback == INVALID_FUNCTION)
		return;
	
	Call_StartFunction(upgrade.plugin, upgrade.translationCallback);
	Call_PushCell(client);
	Call_PushString(upgrade.shortName);
	Call_PushCell(TranslationType_Name);
	Call_PushStringEx(name, maxlen, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(maxlen);
	Call_Finish();
}

void GetUpgradeTranslatedDescription(int client, int iUpgradeIndex, char[] description, int maxlen)
{
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	strcopy(description, maxlen, upgrade.description);
	
	// No translation callback registered? Fall back to the name set when registering the upgrade.
	if(upgrade.translationCallback == INVALID_FUNCTION)
		return;
	
	Call_StartFunction(upgrade.plugin, upgrade.translationCallback);
	Call_PushCell(client);
	Call_PushString(upgrade.shortName);
	Call_PushCell(TranslationType_Description);
	Call_PushStringEx(description, maxlen, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(maxlen);
	Call_Finish();
}

void CallUpgradeRegisteredForward(const char[] sShortName)
{
	// Inform other plugins, that this upgrade is loaded.
	Call_StartForward(g_hfwdOnUpgradeRegistered);
	Call_PushString(sShortName);
	Call_Finish();
}

/**
 * Convar change callbacks
 */
// Cache the new config value
public void ConVar_UpgradeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int iSize = g_hUpgrades.Length;
	InternalUpgradeInfo upgrade;
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade.enableConvar == convar)
		{
			upgrade.enabled = convar.BoolValue;
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.startLevelConvar == convar)
		{
			upgrade.startLevel = convar.IntValue;
			if (upgrade.startLevel > upgrade.maxLevel)
			{
				LogError("Upgrade %s smrpg_%s_startlevel convar (%d) is set higher than the maxlevel (%d). Clamping.", upgrade.name, upgrade.shortName, upgrade.startLevel, upgrade.maxLevel);
				upgrade.startLevel = upgrade.maxLevel;
				
				// Reflect the cap in the convar value as well.
				convar.RemoveChangeHook(ConVar_UpgradeChanged);
				convar.SetInt(upgrade.startLevel);
				convar.AddChangeHook(ConVar_UpgradeChanged);
			}
			
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.startCostConvar == convar)
		{
			upgrade.startCost = convar.IntValue;
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.incCostConvar == convar)
		{
			upgrade.incCost = convar.IntValue;
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.adminFlagConvar == convar)
		{
			char sValue[30];
			convar.GetString(sValue, sizeof(sValue));
			upgrade.adminFlag = ReadFlagString(sValue);
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.visualsConvar == convar)
		{
			upgrade.enableVisuals = convar.BoolValue;
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.soundsConvar == convar)
		{
			upgrade.enableSounds = convar.BoolValue;
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.botsConvar == convar)
		{
			upgrade.allowBots = convar.BoolValue;
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
		else if(upgrade.teamlockConvar == convar)
		{
			upgrade.teamlock = convar.IntValue;
			// Guarantee to have "0" when disabled.
			if(upgrade.teamlock == 1)
				upgrade.teamlock = 0;
			SaveUpgradeConfig(upgrade);
			Call_OnUpgradeSettingsChanged(upgrade.shortName);
			break;
		}
	}
}

public void ConVar_UpgradeMaxLevelChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int iSize = g_hUpgrades.Length;
	InternalUpgradeInfo upgrade;
	for(int i;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade.maxLevelConvar == convar)
			break;
	}
	
	int iNewMaxLevel = convar.IntValue;
	int iMaxLevelBarrier = upgrade.maxLevelBarrier;
	
	if(iMaxLevelBarrier > 0 && !g_hCVIgnoreLevelBarrier.BoolValue && iNewMaxLevel > iMaxLevelBarrier)
	{
		iNewMaxLevel = iMaxLevelBarrier;
		
		// Reflect the cap in the convar value.
		convar.RemoveChangeHook(ConVar_UpgradeMaxLevelChanged);
		convar.SetInt(iNewMaxLevel);
		convar.AddChangeHook(ConVar_UpgradeMaxLevelChanged);
	}
	
	upgrade.maxLevel = iNewMaxLevel;
	SaveUpgradeConfig(upgrade);
	
	Call_OnUpgradeSettingsChanged(upgrade.shortName);
	
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		while(GetClientPurchasedUpgradeLevel(i, upgrade.index) > iNewMaxLevel)
		{
			SetClientCredits(i, GetClientCredits(i) + GetUpgradeCost(upgrade.index, GetClientPurchasedUpgradeLevel(i, upgrade.index)));
			TakeClientUpgrade(i, upgrade.index);
		}
	}
}

void Call_OnUpgradeSettingsChanged(const char[] sShortname)
{
	Call_StartForward(g_hfwdOnUpgradeSettingsChanged);
	Call_PushString(sShortname);
	Call_Finish();
}