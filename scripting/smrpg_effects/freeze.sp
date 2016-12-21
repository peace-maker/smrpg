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
	
	// TODO: Add config option to exclude weapons from limitation.
	/*int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	// All weapons except for the knife do less damage.
	// TODO: Add support for more games
	if(attacker <= 0 || attacker > MaxClients || GetPlayerWeaponSlot(attacker, KNIFE_SLOT) == iWeapon)
		return Plugin_Continue;*/
	
	// This was less than the limit. It's ok.
	if(damage <= g_fLimitDamage[victim])
		return Plugin_Continue;
	
	// Limit the damage!
	damage = g_fLimitDamage[victim];
	
	if(g_iLimitDmgSoundCount > 0)
	{
		char sKey[64];
		Format(sKey, sizeof(sKey), "SoundIceStabLimitDmg%d", Math_GetRandomInt(1, g_iLimitDmgSoundCount));
		SMRPG_EmitSoundToAllEnabled(g_sUpgradeName[victim], SMRPG_GC_GetKeyValue(sKey), victim, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, victim);
	}
	
	return Plugin_Changed;
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