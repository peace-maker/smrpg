#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "fpistol"
#define PLUGIN_VERSION "1.0"

new Handle:g_hCVTimeIncrease;

new Float:g_fFPistolLastSpeed[MAXPLAYERS+1];
new Handle:g_hFPistolResetSpeed[MAXPLAYERS+1];

new Handle:g_hWeaponSpeeds;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Frost Pistol",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Frost Pistol upgrade for SM:RPG. Slow down players hit with a pistol.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	g_hWeaponSpeeds = CreateTrie();
	
	if(!LoadWeaponConfig())
	{
		Format(error, err_max, "Can't read config file in configs/smrpg/frostpistol_weapons.cfg!");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public OnPluginStart()
{
	HookEvent("player_spawn", Event_OnResetEffect);
	HookEvent("player_death", Event_OnResetEffect);

	LoadTranslations("smrpg_stock_upgrades.phrases");

	// Account for late loading
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public OnLibraryAdded(const String:name[])
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Frost Pistol", UPGRADE_SHORTNAME, "Slow down players hit with a pistol.", 10, true, 10, 20, 15, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeResetCallback(UPGRADE_SHORTNAME, SMRPG_ResetEffect);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVTimeIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_upgrade_fpistol_inc", "0.1", "How many seconds are players slowed down multiplied by level?", 0, true, 0.0);
	}
}

public OnMapStart()
{
	PrecacheSound("physics/surfaces/tile_impact_bullet1.wav", true);
	PrecacheSound("physics/surfaces/tile_impact_bullet2.wav", true);
	PrecacheSound("physics/surfaces/tile_impact_bullet3.wav", true);
	PrecacheSound("physics/surfaces/tile_impact_bullet4.wav", true);
}

public OnMapEnd()
{
	if(!LoadWeaponConfig())
		SetFailState("Can't read config file in configs/smrpg/frostpistol_weapons.cfg!");
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

public OnClientDisconnect(client)
{
	SMRPG_ResetEffect(client);
}

/**
 * Event callbacks
 */
public Event_OnResetEffect(Handle:event, const String:error[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;

	SMRPG_ResetEffect(client);
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	// Nothing to apply here immediately after someone buys this upgrade.
}

public bool:SMRPG_ActiveQuery(client)
{
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0 && g_hFPistolResetSpeed[client] != INVALID_HANDLE;
}

// Some plugin wants this effect to end?
public SMRPG_ResetEffect(client)
{
	if(g_hFPistolResetSpeed[client] != INVALID_HANDLE && IsClientInGame(client))
		TriggerTimer(g_hFPistolResetSpeed[client]);
	ClearHandle(g_hFPistolResetSpeed[client]);
	g_fFPistolLastSpeed[client] = 0.0;
}

public SMRPG_TranslateUpgrade(client, TranslationType:type, String:translation[], maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		new String:sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

/**
 * SM:RPG public callbacks
 */
public Action:SMRPG_OnUpgradeEffect(client, const String:shortname[])
{
	// We only care for the impulse effect
	if(!StrEqual(shortname, "impulse"))
		return Plugin_Continue;
	
	// This client isn't slowed down by the frostpistol. Allow impulse to apply its effect.
	if(g_hFPistolResetSpeed[client] == INVALID_HANDLE)
		return Plugin_Continue;
	
	// Frostpistol is active. Block impulse.
	return Plugin_Handled;
}

/**
 * Hook callbacks
 */
public Hook_OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	// Ignore team attack
	if(GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	new iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return;
	
	decl String:sWeapon[256];
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	ReplaceString(sWeapon, sizeof(sWeapon), "weapon_", "", false);
	
	new Float:fSpeed;
	// Don't process weapons, which aren't in the config file.
	if(!GetTrieValue(g_hWeaponSpeeds, sWeapon, fSpeed))
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	// Don't have impulse going wonky
	SMRPG_ResetUpgradeEffectOnClient(victim, "impulse");
	
	//new Float:fOldLaggedMovementValue = GetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue");
	new Float:fOldLaggedMovementValue = 1.0;
	
	if(g_hFPistolResetSpeed[victim] == INVALID_HANDLE)
	{
		g_fFPistolLastSpeed[victim] = fSpeed;
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", fSpeed);
	}
	else
	{
		// Player got shot by a different player with higher damage before?
		if(g_fFPistolLastSpeed[victim] > fSpeed)
		{
			g_fFPistolLastSpeed[victim] = fSpeed;
			SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", fSpeed);
		}
		// Don't extend the timer, if the player is already slowed down for that speed.
		else
		{
			return;
		}
	}
	
	// Emit some icy sound
	// TODO: Make this game independant
	decl String:sSound[PLATFORM_MAX_PATH];
	Format(sSound, sizeof(sSound), "physics/surfaces/tile_impact_bullet%d.wav", GetRandomInt(1, 4));
	EmitSoundToAll(sSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8, SNDPITCH_NORMAL, victim);
	SetEntityRenderMode(victim, RENDER_TRANSCOLOR);
	Entity_SetRenderColor(victim, 0, 0, 255, -1);
	
	ClearHandle(g_hFPistolResetSpeed[victim]);
	
	new Handle:hData;
	g_hFPistolResetSpeed[victim] = CreateDataTimer(float(iLevel)*GetConVarFloat(g_hCVTimeIncrease), Timer_ResetSpeed, hData, TIMER_FLAG_NO_MAPCHANGE);
	WritePackCell(hData, GetClientUserId(victim));
	WritePackFloat(hData, fOldLaggedMovementValue);
	ResetPack(hData);
}

/**
 * Timer callbacks
 */
public Action:Timer_ResetSpeed(Handle:timer, any:data)
{
	new userid = ReadPackCell(data);
	new Float:fOldLaggedMovementValue = ReadPackFloat(data);
	
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hFPistolResetSpeed[client] = INVALID_HANDLE;
	
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", fOldLaggedMovementValue);
	Entity_SetRenderColor(client, 255, 255, 255, -1);
	
	return Plugin_Stop;
}

/**
 * Helpers
 */
bool:LoadWeaponConfig()
{
	ClearTrie(g_hWeaponSpeeds);
	
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/frostpistol_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	new Handle:hKV = CreateKeyValues("FrostPistolWeapons");
	if(!FileToKeyValues(hKV, sPath))
	{
		CloseHandle(hKV);
		return false;
	}
	
	decl String:sWeapon[64], Float:fSpeed;
	if(KvGotoFirstSubKey(hKV, false))
	{
		do
		{
			KvGetSectionName(hKV, sWeapon, sizeof(sWeapon));
			fSpeed = KvGetFloat(hKV, NULL_STRING, 1.0);
			
			SetTrieValue(g_hWeaponSpeeds, sWeapon, fSpeed);
			
		} while (KvGotoNextKey(hKV, false));
	}
	CloseHandle(hKV);
	return true;
}