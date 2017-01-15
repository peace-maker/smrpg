/**
 * This file is part of the SM:RPG Effect Hub.
 * Handles freezing of players.
 */

Handle g_hfwdOnClientFreeze;
Handle g_hfwdOnClientFrozen;
Handle g_hfwdOnClientUnfrozen;

int g_iFreezeSoundCount;
int g_iLimitDmgSoundCount;
Handle g_hUnfreeze[MAXPLAYERS+1];
Handle g_hFreezePlugin[MAXPLAYERS+1];
float g_fLimitDamage[MAXPLAYERS+1];
char g_sUpgradeName[MAXPLAYERS+1][MAX_UPGRADE_SHORTNAME_LENGTH];

enum DamageReductionConfig
{
	DRC_MaxDamage,
	Float:DRC_DmgReduction
};

StringMap g_hDamageReductionConfig;

/**
 * Setup helpers
 */
void RegisterFreezeNatives()
{
	CreateNative("SMRPG_FreezeClient", Native_FreezeClient);
	CreateNative("SMRPG_UnfreezeClient", Native_UnfreezeClient);
	CreateNative("SMRPG_IsClientFrozen", Native_IsClientFrozen);
}

void RegisterFreezeForwards()
{
	// forward Action SMRPG_OnClientFreeze(int client, float &fTime);
	g_hfwdOnClientFreeze = CreateGlobalForward("SMRPG_OnClientFreeze", ET_Hook, Param_Cell, Param_FloatByRef);
	// forward void SMRPG_OnClientFrozen(client, float fTime);
	g_hfwdOnClientFrozen = CreateGlobalForward("SMRPG_OnClientFrozen", ET_Ignore, Param_Cell, Param_Float);
	// forward void SMRPG_OnClientUnfrozen(client);
	g_hfwdOnClientUnfrozen = CreateGlobalForward("SMRPG_OnClientUnfrozen", ET_Ignore, Param_Cell);
}

void SetupFreezeData()
{
	g_hDamageReductionConfig = new StringMap();
}

void PrecacheFreezeSounds()
{
	g_iFreezeSoundCount = 0;
	char sKey[64];
	for(;;g_iFreezeSoundCount++)
	{
		Format(sKey, sizeof(sKey), "SoundIceStabFreeze%d", g_iFreezeSoundCount+1);
		if(!SMRPG_GC_PrecacheSound(sKey))
			break;
	}
	
	g_iLimitDmgSoundCount = 0;
	for(;;g_iLimitDmgSoundCount++)
	{
		Format(sKey, sizeof(sKey), "SoundIceStabLimitDmg%d", g_iLimitDmgSoundCount+1);
		if(!SMRPG_GC_PrecacheSound(sKey))
			break;
	}
}

void ResetFreezeClient(int client)
{
	if(g_hFreezePlugin[client] != null && IsClientInGame(client))
		UnfreezeClient(client);
	ResetClientFreezeState(client);
	ClearHandle(g_hUnfreeze[client]);
}

/**
 * Timer callbacks
 */
public Action Timer_Unfreeze(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hUnfreeze[client] = null;
	UnfreezeClient(client);
	
	return Plugin_Stop;
}

/**
 * Hook callbacks
 */
// Reduce the damage when a player is frozen.
Action Freeze_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage)
{
	// This player isn't frozen. Ignore.
	if(g_hUnfreeze[victim] == null)
		return Plugin_Continue;
	
	// Limit disabled?
	if(g_fLimitDamage[victim] <= 0.0)
		return Plugin_Continue;
		
	float fLimitDamage = g_fLimitDamage[victim];
	
	// See if there is special configuration for this weapon.
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	char sWeapon[64];
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	RemovePrefixFromString("weapon_", sWeapon, sWeapon, sizeof(sWeapon));
	
	// Get the invidiual setting for this weapon
	// or the default values for this upgrade, if there is no special setting for the weapon.
	Action ret = Plugin_Continue;
	int iDamageReduction[DamageReductionConfig];
	if(GetDamageReductionConfigForWeapon(sWeapon, g_sUpgradeName[victim], iDamageReduction)
	|| GetDamageReductionConfigForWeapon("#default", g_sUpgradeName[victim], iDamageReduction))
	{
		//PrintToServer("Weapon config for weapon %s in %s: max_damage: %d, dmg_reduction: %f", sWeapon, g_sUpgradeName[victim], iDamageReduction[DRC_MaxDamage], iDamageReduction[DRC_DmgReduction]);
		// Only use this value, if it was set in the config.
		if(iDamageReduction[DRC_MaxDamage] >= 0)
			fLimitDamage = float(iDamageReduction[DRC_MaxDamage]);
		
		// Reduce the damage by x percent.
		if(iDamageReduction[DRC_DmgReduction] > 0.0)
		{
			float fReduction = damage * iDamageReduction[DRC_DmgReduction];
			damage -= fReduction;
			ret = Plugin_Changed;
			
			// Just block the damage, if there is none. Don't just return now, so we still play the sound.
			if(damage <= 0.0)
				ret = Plugin_Handled;
		}
	}
	
	// This was less than the limit. It's ok.
	if(fLimitDamage > 0.0 && damage > 0.0 && damage <= fLimitDamage)
		return ret;
	
	// Limit the damage if it wasn't reduced to 0. So we still play the sound.
	if(damage > 0.0)
	{
		damage = g_fLimitDamage[victim];
		ret = Plugin_Changed;
	}
	
	if(g_iLimitDmgSoundCount > 0)
	{
		char sKey[64];
		Format(sKey, sizeof(sKey), "SoundIceStabLimitDmg%d", Math_GetRandomInt(1, g_iLimitDmgSoundCount));
		SMRPG_EmitSoundToAllEnabled(g_sUpgradeName[victim], SMRPG_GC_GetKeyValue(sKey), victim, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, victim);
	}
	
	return ret;
}

/**
 * Native handlers
 */
// native bool SMRPG_FreezeClient(int client, float fTime, float fDamageLimit, const char[] sUpgradeName, bool bPlaySound=true, bool bFadeColor=true, bool bResetVelocity=false);
public int Native_FreezeClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	float fFreezeTime = view_as<float>(GetNativeCell(2));
	float fLimitDamage = view_as<float>(GetNativeCell(3));
	int iLen;
	GetNativeStringLength(4, iLen);
	char[] sUpgradeName = new char[iLen+1];
	GetNativeString(4, sUpgradeName, iLen+1);
	bool bPlaySound = GetNativeCell(5);
	bool bFadeColor = GetNativeCell(6);
	bool bResetVelocity = GetNativeCell(7);
	
	Action ret;
	Call_StartForward(g_hfwdOnClientFreeze);
	Call_PushCell(client);
	Call_PushFloatRef(fFreezeTime);
	Call_Finish(ret);
	
	if(ret >= Plugin_Handled)
		return 0;
	
	// Are you insane?
	if(fFreezeTime < 0.0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid freeze time %f.", fFreezeTime);
	
	// Save the upgrade shortname for damage limiting later.
	strcopy(g_sUpgradeName[client], MAX_UPGRADE_SHORTNAME_LENGTH, sUpgradeName);
	
	// Don't allow more damage than this if victim is frozen.
	// !!! This is deprecated and overwritten by anything in the freeze_limit_damage config!
	g_fLimitDamage[client] = fLimitDamage;
	
	// Freeze the player.
	// Note: This won't reset his velocity. Useful for surf maps.
	SetEntityMoveType(client, MOVETYPE_NONE);
	
	// Reset the velocity, if we are told to.
	if(bResetVelocity)
	{
		float fStop[3];
		Entity_SetAbsVelocity(client, fStop);
	}
	
	if(bPlaySound && g_iFreezeSoundCount > 0)
	{
		char sKey[64];
		Format(sKey, sizeof(sKey), "SoundIceStabFreeze%d", Math_GetRandomInt(1, g_iFreezeSoundCount));
		SMRPG_EmitSoundToAllEnabled(sUpgradeName, SMRPG_GC_GetKeyValue(sKey), client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, client);
	}

	if(bFadeColor && SMRPG_ClientWantsCosmetics(client, sUpgradeName, SMRPG_FX_Visuals))
	{
		Help_SetClientRenderColorFadeTarget(plugin, client, 255, 255, 255, -1);
		// Fade as long as the player is frozen.
		float fTickrate = 1.0 / GetTickInterval();
		float fStepsize = 255.0 / (fTickrate * fFreezeTime);
		SMRPG_SetClientRenderColorFadeStepsize(client, fStepsize, fStepsize);
		Help_SetClientRenderColor(plugin, client, 0, 0, 255, -1);
	}
	
	ClearHandle(g_hUnfreeze[client]);
	g_hUnfreeze[client] = CreateTimer(fFreezeTime, Timer_Unfreeze, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	g_hFreezePlugin[client] = plugin;
	
	Call_StartForward(g_hfwdOnClientFrozen);
	Call_PushCell(client);
	Call_PushFloat(fFreezeTime);
	Call_Finish();
	
	return true;
}

// native void SMRPG_UnfreezeClient(int client);
public int Native_UnfreezeClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	if(!g_hUnfreeze[client])
		return ThrowNativeError(SP_ERROR_NATIVE, "Client is not frozen.");
	
	ResetFreezeClient(client);
	return 0;
}

// native bool SMRPG_IsClientFrozen(int client);
public int Native_IsClientFrozen(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	return g_hUnfreeze[client] != null;
}

/**
 * Helpers
 */
void UnfreezeClient(int client)
{
	if(GetEntityMoveType(client) == MOVETYPE_NONE)
		SetEntityMoveType(client, MOVETYPE_WALK);
	Help_ResetClientToDefaultColor(g_hFreezePlugin[client], client, true, true, true, false);
	ResetClientFreezeState(client);
	
	Call_StartForward(g_hfwdOnClientUnfrozen);
	Call_PushCell(client);
	Call_Finish();
}

// Client doesn't have to be ingame for this one.
void ResetClientFreezeState(int client)
{
	g_hFreezePlugin[client] = null;
	g_fLimitDamage[client] = 0.0;
	g_sUpgradeName[client][0] = 0;
}

bool ReadLimitDamageConfig()
{
	// Remove old config first.
	StringMapSnapshot hSnapshot = g_hDamageReductionConfig.Snapshot();
	int iSize = hSnapshot.Length;
	char sBuffer[64];
	Handle hSubmap;
	for(int i=0; i<iSize; i++)
	{
		hSnapshot.GetKey(i, sBuffer, sizeof(sBuffer));
		g_hDamageReductionConfig.GetValue(sBuffer, hSubmap);
		delete hSubmap;
	}
	g_hDamageReductionConfig.Clear();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/freeze_limit_damage.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	KeyValues hKV = new KeyValues("SMRPGFreezeLimitDamage");
	if(!hKV.ImportFromFile(sPath))
	{
		delete hKV;
		return false;
	}
	
	if(!hKV.GotoFirstSubKey())
	{
		delete hKV;
		return true;
	}
	
	int iDamageReduction[DamageReductionConfig];
	char sWeapon[64], sUpgradeShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
	StringMap hSubUpgradeMap;
	int iDefaultSetting[DamageReductionConfig], iBaseUpgradeDefault[DamageReductionConfig], iWeaponDefault[DamageReductionConfig];
	do
	{
		hKV.GetSectionName(sWeapon, sizeof(sWeapon));
		RemovePrefixFromString("weapon_", sWeapon, sWeapon, sizeof(sWeapon));
		
		if(!hKV.GotoFirstSubKey())
			continue;
		
		if(!g_hDamageReductionConfig.GetValue(sWeapon, hSubUpgradeMap))
		{
			hSubUpgradeMap = new StringMap();
		}
		
		// Check the global #default
		if(!GetDamageReductionConfigForWeapon("#default", "#default", iDefaultSetting))
		{
			iDefaultSetting[DRC_MaxDamage] = -1;
			iDefaultSetting[DRC_DmgReduction] = -1.0;
		}
		
		// Load this current weapon's default section
		if(!hSubUpgradeMap.GetArray("#default", iWeaponDefault[0], view_as<int>(DamageReductionConfig)))
		{
			iWeaponDefault[DRC_MaxDamage] = -1;
			iWeaponDefault[DRC_DmgReduction] = -1.0;
		}
		
		do
		{
			hKV.GetSectionName(sUpgradeShortname, sizeof(sUpgradeShortname));
			// Load the global default section for this upgrade.
			if(StrEqual(sUpgradeShortname, "#default", false)
			|| !GetDamageReductionConfigForWeapon("#default", sUpgradeShortname, iBaseUpgradeDefault))
			{
				iBaseUpgradeDefault[DRC_MaxDamage] = -1;
				iBaseUpgradeDefault[DRC_DmgReduction] = -1.0;
			}
			// Use the global default, if there is some value unset in this global upgrade setting.
			MergeDamageReductionValues(iBaseUpgradeDefault, iDefaultSetting);
			
			// Always prefer the #default section of the current weapon.
			if(iWeaponDefault[DRC_MaxDamage] >= 0)
				iBaseUpgradeDefault[DRC_MaxDamage] = iWeaponDefault[DRC_MaxDamage];
			if(iWeaponDefault[DRC_DmgReduction] >= 0.0)
				iBaseUpgradeDefault[DRC_DmgReduction] = iWeaponDefault[DRC_DmgReduction];
			
			iDamageReduction[DRC_MaxDamage] = hKV.GetNum("max_damage", -1);
			iDamageReduction[DRC_DmgReduction] = hKV.GetFloat("dmg_reduction", -1.0);
			// Can't reduce 100%!
			if(iDamageReduction[DRC_DmgReduction] > 1.0)
			{
				LogError("Invalid \"dmg_reduction\" setting (%f) in upgrade \"%s\" section of weapon \"%s\" in freeze_limit_damage.cfg. Can't be higher than 1.0. Ignoring.", iDamageReduction[DRC_DmgReduction], sUpgradeShortname, sWeapon);
				iDamageReduction[DRC_DmgReduction] = -1.0;
			}
			
			// Use default, if a value is not set in this upgrade's section.
			if (!StrEqual(sUpgradeShortname, "#default", false))
				MergeDamageReductionValues(iDamageReduction, iBaseUpgradeDefault);
			else
				iWeaponDefault = iDamageReduction;
			
			//PrintToServer("Parsed weapon \"%s\" for upgrade \"%s\": max_damage: %d, dmg_reduction: %f (base defaults: max_damage: %d, dmg_reduction: %f)", sWeapon, sUpgradeShortname, iDamageReduction[DRC_MaxDamage], iDamageReduction[DRC_DmgReduction], iBaseUpgradeDefault[DRC_MaxDamage], iBaseUpgradeDefault[DRC_DmgReduction]);
			
			hSubUpgradeMap.SetArray(sUpgradeShortname, iDamageReduction[0], view_as<int>(DamageReductionConfig), true);
			
		} while(hKV.GotoNextKey());
		
		g_hDamageReductionConfig.SetValue(sWeapon, hSubUpgradeMap, true);
		
		hKV.GoBack();
		
	} while(hKV.GotoNextKey());
	delete hKV;
	
	return true;
}

// Use the value of the baseconfig if there is no value set in the current config.
void MergeDamageReductionValues(int iCurrentConfig[DamageReductionConfig], const int iBaseConfig[DamageReductionConfig])
{
	if(iCurrentConfig[DRC_MaxDamage] < 0)
		iCurrentConfig[DRC_MaxDamage] = iBaseConfig[DRC_MaxDamage];
	if(iCurrentConfig[DRC_DmgReduction] < 0.0)
		iCurrentConfig[DRC_DmgReduction] = iBaseConfig[DRC_DmgReduction];
}

// Find the DamageReductionConfig of the weapon for an upgrade.
// Use the #default section of the weapon if there is no extra config for the upgrade.
bool GetDamageReductionConfigForWeapon(const char[] sWeapon, const char[] sShortname, int iDamageReduction[DamageReductionConfig])
{
	// No section for this weapon?
	StringMap hSubUpgradeMap;
	if(!g_hDamageReductionConfig.GetValue(sWeapon, hSubUpgradeMap))
		return false;
	
	// Special settings for this upgrade?
	if(hSubUpgradeMap.GetArray(sShortname, iDamageReduction[0], view_as<int>(DamageReductionConfig)))
		return true;
	
	// Get at least the default values for this weapon.
	return hSubUpgradeMap.GetArray("#default", iDamageReduction[0], view_as<int>(DamageReductionConfig));
}
