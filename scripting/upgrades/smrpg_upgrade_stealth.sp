#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smlib>

//#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "stealth"


ConVar g_hCVMinimumAlpha;

// CS:GO only convar to enable alpha changes on players.
ConVar g_hCVIgnoreImmunity;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Stealth",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Stealth upgrade for SM:RPG. Renders players opaque.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	// CS:GO ignored the alpha setting on players up until Operation: Bloodhound.
	// We force the new convar to true, to make sure we're allowed to change the alpha.
	if(GetEngineVersion() == Engine_CSGO)
	{
		g_hCVIgnoreImmunity = FindConVar("sv_disable_immunity_alpha");
		if(g_hCVIgnoreImmunity != null)
		{
			SetConVarBool(g_hCVIgnoreImmunity, true);
			g_hCVIgnoreImmunity.AddChangeHook(ConVar_OnDisableImmunityAlphaChanged);
		}
	}

	// Late loading
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Stealth", UPGRADE_SHORTNAME, "Renders yourself more and more invisible.", 5, true, 5, 15, 10);
		SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVMinimumAlpha = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_stealth_min_alpha", "120", "Player visibility at the maximum upgrade level. 0 = completely invisible", 0, true, 0.0, true, 255.0);
	}
}

public void OnMapStart()
{
	// Just to make sure there's nothing else messing with this effect.
	CreateTimer(5.0, Timer_SetVisibilities, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, Hook_OnWeaponDropPost);
}

/**
 * ConVar change hook callbacks (CS:GO only)
 */
public void ConVar_OnDisableImmunityAlphaChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(!convar.BoolValue)
	{
		// Ignore this convar, if this upgrade is disabled.
		if(!SMRPG_IsEnabled())
			return;
	
		int upgrade[UpgradeInfo];
		SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
		if(!upgrade[UI_enabled])
			return;
		
		convar.SetBool(true);
		PrintToServer("SM:RPG Stealth Upgrade > Forcing sv_disable_immunity_alpha to 1.");
	}
}

// CS:GO only: force sv_disable_immunity_alpha to 1 when enabling smrpg.
public void SMRPG_OnEnableStatusChanged(bool bEnabled)
{
	if(!bEnabled)
		return;
	
	// CS:GO only
	if(g_hCVIgnoreImmunity == null)
		return;

	// Upgrade enabled too?
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// alpha change was ignored. OBEY!
	if(!g_hCVIgnoreImmunity.BoolValue)
	{
		g_hCVIgnoreImmunity.SetBool(true);
		PrintToServer("SM:RPG Stealth Upgrade > Forcing sv_disable_immunity_alpha to 1.");
	}
}

// CS:GO only: force sv_disable_immunity_alpha to 1 when enabling this upgrade.
public void SMRPG_OnUpgradeSettingsChanged(const char[] shortname)
{
	// CS:GO only
	if(g_hCVIgnoreImmunity == null)
		return;

	// Settings of some other upgrade changed? Boring..
	if(!StrEqual(shortname, UPGRADE_SHORTNAME))
		return;

	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;

	if(!g_hCVIgnoreImmunity.BoolValue)
	{
		g_hCVIgnoreImmunity.SetBool(true);
	}
}

/**
 * Event callbacks
 */
public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	SetClientVisibility(client);
}

/**
 * SDK Hooks callbacks
 */
public void Hook_OnWeaponDropPost(int client, int weapon)
{
	if(weapon == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Render dropped weapons visible again!
	SetEntityRenderMode(weapon, RENDER_TRANSCOLOR);
	Entity_SetRenderColor(weapon, -1, -1, -1, 255);
}

/**
 * SM:RPG Upgrade callbacks
 */
public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
	if(!IsClientInGame(client))
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	SetClientVisibility(client);
}

public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

/**
 * Timer callbacks
 */
public Action Timer_SetVisibilities(Handle timer, any data)
{
	SetVisibilities();
	
	return Plugin_Continue;
}

/**
 * Helper functions
 */
void SetVisibilities()
{
	if(!SMRPG_IsEnabled())
		return;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	bool bIgnoreBots = SMRPG_IgnoreBots();
	
	int iLevel;
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		// Are bots allowed to use this upgrade?
		if(bIgnoreBots && IsFakeClient(i))
			continue;
		
		// Player didn't buy this upgrade yet.
		iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			continue;
		
		SetClientVisibility(i);
	}
}

void SetClientVisibility(int client)
{
	// Only change alive players.
	if(!IsPlayerAlive(client) || IsClientObserver(client))
		return;
	
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	
	// Keep the minimum alpha in byte range
	int iMinimumAlpha = g_hCVMinimumAlpha.IntValue;
	if (iMinimumAlpha < 0 || iMinimumAlpha > 255)
		iMinimumAlpha = 120;
	
	// Each step brings the player's visibility more towards the minimum alpha.
	int iStepSize = (255 - iMinimumAlpha) / upgrade[UI_maxLevel];
	
	// Render the player more invisible each level
	int iAlpha = 255 - iLevel * iStepSize;
	// Avoid rounding problems with the stepsize.
	if (iAlpha < 0)
		iAlpha = 0; // TODO: RENDER_NONE?
	
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	Entity_SetRenderColor(client, -1, -1, -1, iAlpha);
	
	// Render his weapons opaque too.
	int iWeapon = -1, iIndex;
	while((iWeapon = Client_GetNextWeapon(client, iIndex)) != -1)
	{
		SetEntityRenderMode(iWeapon, RENDER_TRANSCOLOR);
		Entity_SetRenderColor(iWeapon, -1, -1, -1, iAlpha);
	}
	
	// Take care of any props attachted to him like hats.
	char sBuffer[64];
	LOOP_CHILDREN(client, child)
	{
		if(GetEntityClassname(child, sBuffer, sizeof(sBuffer))
		&& StrContains(sBuffer, "prop_", false) == 0)
		{
			SetEntityRenderMode(child, RENDER_TRANSCOLOR);
			Entity_SetRenderColor(child, -1, -1, -1, iAlpha);
		}
	}
}
