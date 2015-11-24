/**
 * SM:RPG Poison Smoke Upgrade
 * Damages players inside the smoke of a smoke grenade.
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smrpg>

#define UPGRADE_SHORTNAME "poisonsmoke"
#define PLUGIN_VERSION "1.0"

enum GrenadeInfo {
	GR_userid,
	GR_team,
	GR_projectile,
	GR_particle,
	GR_light,
	Handle:GR_removeTimer,
	Handle:GR_damageTimer,
};

new Handle:g_hThrownGrenades;

new Handle:g_hCVFriendlyFire;
new Handle:g_hCVIgnoreFriendlyFire;
new Handle:g_hCVBaseDamage;
new Handle:g_hCVIncDamage;
new Handle:g_hCVColorT;
new Handle:g_hCVColorCT;
new Handle:g_hCVInterval;

new bool:g_bInCheckDamage;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Poison Smoke",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Poison Smoke upgrade for SM:RPG. Damages players standing inside the smoke of a smoke grenade.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	new EngineVersion:engine = GetEngineVersion();
	if(engine != Engine_CSS)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	g_hThrownGrenades = CreateArray(_:GrenadeInfo);
	
	// To change the weapon icon from some skull to a grenade!
	HookEvent("player_death", Event_OnPlayerDeath, EventHookMode_Pre);
	
	HookEvent("round_start", Event_OnResetSmokes);
	HookEvent("round_end", Event_OnResetSmokes);
	
	g_hCVFriendlyFire = FindConVar("mp_friendlyfire");
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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Poison Smoke", UPGRADE_SHORTNAME, "Damages players standing inside the smoke of a smoke grenade.", 20, true, 10, 15, 10, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		
		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVIgnoreFriendlyFire = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_ignoreff", "0", "Ignore the setting of mp_friendlyfire and don't allow team damage by poison smoke at all?", _, true, 0.0, true, 1.0);
		g_hCVBaseDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_basedamage", "3", "The minimum damage the poison smoke inflicts.", _, true, 0.0);
		g_hCVIncDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_incdamage", "2", "How much damage multiplied by the upgrade level should we add to the base damage?", _, true, 1.0);
		g_hCVColorT = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_color_t", "20 250 50", "What color should the smoke be for grenades thrown by terrorists? Format: \"red green blue\" from 0 - 255.", FCVAR_PLUGIN);
		g_hCVColorCT = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_color_ct", "20 250 50", "What color should the smoke be for grenades thrown by counter-terrorists? Format: \"red green blue\" from 0 - 255.", FCVAR_PLUGIN);
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_damage_interval", "1", "Deal damage every x seconds.", _, true, 0.1);
	}
}

public OnMapEnd()
{
	// No need to close the timers manually, because they're closed automagically on map end.
	ClearArray(g_hThrownGrenades);
}

/**
 * Event callbacks
 */
// Change the killicon to a grenade. Smokes don't have an own icon, so we'll use the flashbang!
public Action:Event_OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	decl String:sWeapon[64];
	GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
	if(StrEqual(sWeapon, "env_particlesmokegrenade"))
	{
		SetEventString(event, "weapon", "flashbang");
	}
	return Plugin_Continue;
}

public Event_OnResetSmokes(Handle:event, const String:name[], bool:dontBroadcast)
{
	new iSize = GetArraySize(g_hThrownGrenades);
	new iGrenade[GrenadeInfo], iLight;
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(g_hThrownGrenades, i, iGrenade[0], _:GrenadeInfo);
		
		if(iGrenade[GR_removeTimer] != INVALID_HANDLE)
			CloseHandle(iGrenade[GR_removeTimer]);
		if(!g_bInCheckDamage && iGrenade[GR_damageTimer] != INVALID_HANDLE)
		{
			CloseHandle(iGrenade[GR_damageTimer]);
		}
		
		// Keep the color on round end and only remove it on round start.
		if(StrEqual(name, "round_start"))
		{
			iLight = EntRefToEntIndex(iGrenade[GR_light]);
			if(iLight != INVALID_ENT_REFERENCE && IsValidEntity(iLight))
				AcceptEntityInput(iLight, "Kill");
		}
	}
	ClearArray(g_hThrownGrenades);
	
	if(g_bInCheckDamage)
		g_bInCheckDamage = false;
}

/**
 * SM:RPG Upgrade callbacks
 */

public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	// Here you can apply your effect directly when the client's upgrade level changes.
	// E.g. adjust the maximal health of the player immediately when he bought the upgrade.
	// The client doesn't have to be ingame here!
}

public bool:SMRPG_ActiveQuery(client)
{
	// If this is a passive effect, it's always active, if the player got at least level 1.
	// If it's an active effect (like a short speed boost) add a check for the effect as well.
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}


// The core wants to display your upgrade somewhere. Translate it into the clients language!
public SMRPG_TranslateUpgrade(client, const String:shortname[], TranslationType:type, String:translation[], maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if(type == TranslationType_Description)
	{
		new String:sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

public OnEntityCreated(entity, const String:classname[])
{
	if(StrEqual(classname, "smokegrenade_projectile", false))
	{
		SDKHook(entity, SDKHook_Spawn, Hook_OnSpawnProjectile);
	}
	
	// CS:S doesn't use the EffectDispatch ParticleEffect route, but creates such an entity instead.
	if(StrEqual(classname, "env_particlesmokegrenade", false))
	{
		SDKHook(entity, SDKHook_Spawn, Hook_OnSpawnParticles);
	}
}

public Hook_OnSpawnProjectile(entity)
{
	new client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	
	if(client == INVALID_ENT_REFERENCE || !IsClientInGame(client))
		return;
	
	if(!SMRPG_CanRunEffectOnClient(client))
		return;
	
	new iGrenade[GrenadeInfo];
	iGrenade[GR_userid] = GetClientUserId(client);
	iGrenade[GR_team] = GetClientTeam(client);
	iGrenade[GR_projectile] = EntIndexToEntRef(entity);
	iGrenade[GR_particle] = INVALID_ENT_REFERENCE;
	iGrenade[GR_light] = INVALID_ENT_REFERENCE;
	iGrenade[GR_removeTimer] = INVALID_HANDLE;
	iGrenade[GR_damageTimer] = INVALID_HANDLE;
	PushArrayArray(g_hThrownGrenades, iGrenade[0], _:GrenadeInfo);
}

// CS:S only!
public Hook_OnSpawnParticles(entity)
{
	new Float:fParticleOrigin[3], Float:fProjectileOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fParticleOrigin);
	
	new iSize = GetArraySize(g_hThrownGrenades);
	new iGrenade[GrenadeInfo], iProjectile;
	for(new i=0;i<iSize;i++)
	{
		GetArrayArray(g_hThrownGrenades, i, iGrenade[0], _:GrenadeInfo);
		iProjectile = EntRefToEntIndex(iGrenade[GR_projectile]); // TODO: check for valid entity and remove entry, if light wasn't spawned already.
		GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", fProjectileOrigin);
		
		// This is the grenade we're looking for.
		if(fParticleOrigin[0] == fProjectileOrigin[0] && fParticleOrigin[1] == fProjectileOrigin[1] && fParticleOrigin[2] == fProjectileOrigin[2])
		{
			new client = GetClientOfUserId(iGrenade[GR_userid]);
			if(!client || !SMRPG_CanRunEffectOnClient(client) || !SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
			{
				RemoveFromArray(g_hThrownGrenades, i);
				break; // Some other plugin doesn't want this effect to run
			}
			
			iGrenade[GR_particle] = EntIndexToEntRef(entity);
			
			new Float:fFadeStartTime = GetEntPropFloat(entity, Prop_Send, "m_FadeStartTime");
			new Float:fFadeEndTime = GetEntPropFloat(entity, Prop_Send, "m_FadeEndTime");
			
			// Create the light, which colors the smoke.
			new iEnt = CreateLightDynamic(entity, fParticleOrigin, iGrenade[GR_team], fFadeStartTime, fFadeEndTime);
			iGrenade[GR_light] = EntIndexToEntRef(iEnt);
			
			// Stop dealing damage when the smoke starts to vanish.
			iGrenade[GR_removeTimer] = CreateTimer(fFadeStartTime+(fFadeEndTime-fFadeStartTime)/2.5, Timer_StopDamage, iGrenade[GR_particle], TIMER_FLAG_NO_MAPCHANGE);
			// Deal damage to anyone walking into the smoke
			iGrenade[GR_damageTimer] = CreateTimer(GetConVarFloat(g_hCVInterval), Timer_CheckDamage, iGrenade[GR_particle], TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
			
			SetArrayArray(g_hThrownGrenades, i, iGrenade[0], _:GrenadeInfo);
			
			break;
		}
	}
}

// Hide the light if, players disabled the visual effect.
// Only works, if the light is hidden completely right after spawn and is never transmitted to the client.
// So you can't toggle the light on and of for a single client while it's already shining.
public Action:Hook_OnSetTransmitLight(entity, client)
{
	if(client < 0 || client >= MaxClients)
		return Plugin_Continue;
	
	if(IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client))
		return Plugin_Continue;
	
	if(!SMRPG_ClientWantsCosmetics(client, UPGRADE_SHORTNAME, SMRPG_FX_Visuals))
		return Plugin_Stop;
	
	return Plugin_Continue;
}

/**
 * Timer callbacks
 */
// Remove the poison effect, 2 seconds before the smoke is completely vanished
public Action:Timer_StopDamage(Handle:timer, any:entityref)
{
	// Get the grenade array with this entity index
	new iSize = GetArraySize(g_hThrownGrenades);
	new iGrenade[GrenadeInfo];
	for(new i=0; i<iSize; i++)
	{
		GetArrayArray(g_hThrownGrenades, i, iGrenade[0], _:GrenadeInfo);
		if(iGrenade[GR_light] == INVALID_ENT_REFERENCE)
			continue;
		
		// This is the right grenade
		// Remove it
		if(iGrenade[GR_particle] == entityref)
		{
			CloseHandle(iGrenade[GR_damageTimer]);
			
			RemoveFromArray(g_hThrownGrenades, i);
			break;
		}
	}
	
	return Plugin_Stop;
}

// Do damage every seconds to players in the smoke
public Action:Timer_CheckDamage(Handle:timer, any:entityref)
{
	new entity = EntRefToEntIndex(entityref);
	if(entity == INVALID_ENT_REFERENCE)
		return Plugin_Continue;
	
	// Get the grenade array with this entity index
	new iSize = GetArraySize(g_hThrownGrenades);
	new iGrenade[GrenadeInfo], bool:bFound;
	for(new i=0; i<iSize; i++)
	{
		GetArrayArray(g_hThrownGrenades, i, iGrenade[0], _:GrenadeInfo);
		if(iGrenade[GR_particle] == entityref)
		{
			bFound = true;
			break;
		}
	}
	
	// The particles were removed already.
	if(!bFound)
		return Plugin_Continue;
	
	// Don't do anything, if the client who's thrown the grenade left.
	new client = GetClientOfUserId(iGrenade[GR_userid]);
	if(!client)
		return Plugin_Continue;
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	// We're dealing damage now. If we kill the last person in the team and the round ends, this timer will be stopped while we're still in here.
	// We can't have an invalid timer handle in the timer's callback, so don't close it.
	g_bInCheckDamage = true;
	
	new Float:fDamage = GetConVarFloat(g_hCVBaseDamage) + GetConVarFloat(g_hCVIncDamage) * float(iLevel);
	
	new Float:fParticleOrigin[3], Float:fPlayerOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fParticleOrigin);
	
	new bool:bFriendlyFire = GetConVarBool(g_hCVFriendlyFire);
	new bool:bIgnoreFriendlyFire = GetConVarBool(g_hCVIgnoreFriendlyFire);
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && (SMRPG_IsFFAEnabled() || (bFriendlyFire && !bIgnoreFriendlyFire || GetClientTeam(i) != iGrenade[GR_team])))
		{
			GetClientAbsOrigin(i, fPlayerOrigin);
			if(GetVectorDistance(fParticleOrigin, fPlayerOrigin) <= 220)
				SDKHooks_TakeDamage(i, iGrenade[GR_particle], client, fDamage, DMG_POISON, -1, NULL_VECTOR, fParticleOrigin);
		}
	}
	
	// round_end was fired during timer execution. stop ourself now.
	if(!g_bInCheckDamage)
		return Plugin_Stop;
	
	g_bInCheckDamage = false;
	
	return Plugin_Continue;
}

CreateLightDynamic(entity, Float:fOrigin[3], iTeam, Float:fFadeStartTime, Float:fFadeEndTime)
{
	decl String:sBuffer[64];
	new iEnt = CreateEntityByName("light_dynamic");
	if(iEnt == INVALID_ENT_REFERENCE)
		return iEnt;
	
	Format(sBuffer, sizeof(sBuffer), "smokelight_%d", entity);
	DispatchKeyValue(iEnt,"targetname", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%f %f %f", fOrigin[0], fOrigin[1], fOrigin[2]);
	DispatchKeyValue(iEnt, "origin", sBuffer);
	DispatchKeyValue(iEnt, "angles", "-90 0 0");
	if(iTeam == 2)
		GetConVarString(g_hCVColorT, sBuffer, sizeof(sBuffer));
	// Fall back to CT color, even if the player switched to spectator after he threw the nade
	else
		GetConVarString(g_hCVColorCT, sBuffer, sizeof(sBuffer));
	DispatchKeyValue(iEnt, "_light", sBuffer);
	//DispatchKeyValue(iEnt, "_inner_cone","-89");
	//DispatchKeyValue(iEnt, "_cone","-89");
	DispatchKeyValue(iEnt, "pitch","-90");
	DispatchKeyValue(iEnt, "distance","256");
	DispatchKeyValue(iEnt, "spotlight_radius","96");
	DispatchKeyValue(iEnt, "brightness","3");
	DispatchKeyValue(iEnt, "style","6");
	DispatchKeyValue(iEnt, "spawnflags","1");
	DispatchSpawn(iEnt);
	AcceptEntityInput(iEnt, "DisableShadow");
	
	new String:sAddOutput[64];
	// Remove the light when the smoke vanishes
	Format(sAddOutput, sizeof(sAddOutput), "OnUser1 !self:kill::%f:1", fFadeStartTime+(fFadeEndTime-fFadeStartTime)/2.5);
	SetVariantString(sAddOutput);
	AcceptEntityInput(iEnt, "AddOutput");
	// Don't light any players or models, when the smoke starts to clear!
	Format(sAddOutput, sizeof(sAddOutput), "OnUser1 !self:spawnflags:3:%f:1", fFadeStartTime);
	SetVariantString(sAddOutput);
	AcceptEntityInput(iEnt, "AddOutput");
	AcceptEntityInput(iEnt, "FireUser1");
	
	// Only show it to people who want to see the visual effect.
	SDKHook(iEnt, SDKHook_SetTransmit, Hook_OnSetTransmitLight);
	
	return iEnt;
}

stock SMRPG_CanRunEffectOnClient(client)
{
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return false;
	
	// The upgrade is disabled completely?
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return false;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return false;
	
	// Player didn't buy this upgrade yet.
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return false;
	
	return true;
}