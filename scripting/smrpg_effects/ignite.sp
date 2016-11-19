/**
 * This file is part of the SM:RPG Effect Hub.
 * Handles igniting of players.
 */

Handle g_hfwdOnClientIgnite;
Handle g_hfwdOnClientIgnited;
Handle g_hfwdOnClientExtinguished;

Handle g_hExtinguish[MAXPLAYERS+1];
Handle g_hIgnitePlugin[MAXPLAYERS+1];
int g_iAttacker[MAXPLAYERS+1] = {-1, ...};

/**
 * Setup helpers
 */
void RegisterIgniteNatives()
{
	CreateNative("SMRPG_IgniteClient", Native_IgniteClient);
	CreateNative("SMRPG_ExtinguishClient", Native_ExtinguishClient);
	CreateNative("SMRPG_IsClientBurning", Native_IsClientBurning);
}

void RegisterIgniteForwards()
{
	// forward Action SMRPG_OnClientIgnite(int client, float &fTime);
	g_hfwdOnClientIgnite = CreateGlobalForward("SMRPG_OnClientIgnite", ET_Hook, Param_Cell, Param_FloatByRef);
	// forward void SMRPG_OnClientIgnited(int client, float fTime);
	g_hfwdOnClientIgnited = CreateGlobalForward("SMRPG_OnClientIgnited", ET_Ignore, Param_Cell, Param_Float);
	// forward void SMRPG_OnClientExtinguished(int client);
	g_hfwdOnClientExtinguished = CreateGlobalForward("SMRPG_OnClientExtinguished", ET_Ignore, Param_Cell);
}

void ResetIgniteClient(int client, bool bDisconnect)
{
	if(g_hIgnitePlugin[client] != null && IsClientInGame(client))
		ExtinguishClient(client);
	ResetClientIgniteState(client);
	ClearHandle(g_hExtinguish[client]);
	
	// Extinguish again a few frames later, so ragdolls don't burn.
	if(!bDisconnect)
		g_hExtinguish[client] = CreateTimer(0.2, Timer_Extinguish, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer callbacks
 */
public Action Timer_Extinguish(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hExtinguish[client] = null;
	
	ExtinguishClient(client);
	
	return Plugin_Stop;
}

/**
 * Hook callbacks
 */
// Change the attacker to the right player when a victim gets damage from fire.
Action Ignite_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	// Not ignited by this plugin.
	if (g_hExtinguish[victim] == null)
		return Plugin_Continue;
	
	// No attacker passed to SMRPG_IgniteClient.
	if (g_iAttacker[victim] == -1)
		return Plugin_Continue;
	
	// Only care for direct burn damage to the player burning himself.
	if (damagetype & (DMG_BURN | DMG_DIRECT) != (DMG_BURN | DMG_DIRECT))
		return Plugin_Continue;
	
	// Already an attacker client specified?
	if (attacker > 0 && attacker <= MaxClients)
		return Plugin_Continue;
	
	int iAttacker = GetClientFromSerial(g_iAttacker[victim]);
	// Attacker left the server?
	if (!iAttacker)
	{
		// Don't do all the above again next time.
		g_iAttacker[victim] = -1;
		return Plugin_Continue;
	}
	
	// Change the attacker to the player who ignited the victim.
	attacker = iAttacker;
	return Plugin_Changed;
}

/**
 * Native handlers
 */
// native bool SMRPG_IgniteClient(int client, float fTime, const char[] sUpgradeName, bool bFadeColor=true, int attacker=-1);
public int Native_IgniteClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	float fIgniteTime = view_as<float>(GetNativeCell(2));
	int iLen;
	GetNativeStringLength(3, iLen);
	char[] sUpgradeName = new char[iLen+1];
	GetNativeString(3, sUpgradeName, iLen+1);
	bool bFadeColor = GetNativeCell(4);
	
	int attacker = -1;
	// Attacker parameter was added later.
	if (numParams > 4)
		attacker = GetNativeCell(5);

	// Server admin doesn't want the attacker to get credit for the fire damage.
	if (!GetConVarBool(g_hCVCreditFireAttacker))
		attacker = -1;
	
	if (attacker != -1 && (attacker <= 0 || attacker > MaxClients))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid attacker client index %d", attacker);
	
	Action ret;
	Call_StartForward(g_hfwdOnClientIgnite);
	Call_PushCell(client);
	Call_PushFloatRef(fIgniteTime);
	Call_Finish(ret);
	
	if(ret >= Plugin_Handled)
		return false;
	
	// Are you insane?
	if(fIgniteTime < 0.0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid ignite time %f.", fIgniteTime);
	
	// Ignite the player.
	if (attacker != -1)
		g_iAttacker[client] = GetClientSerial(attacker);
	g_hIgnitePlugin[client] = plugin;
	// TODO: Remember the "creator" of the entityflame effects entity which does the damage 
	// to catch the "splash" fire damage as well on other players than the victim. (just DMG_BURN without the DMG_DIRECT)
	IgniteEntity(client, fIgniteTime);
	
	ClearHandle(g_hExtinguish[client]);
	g_hExtinguish[client] = CreateTimer(fIgniteTime, Timer_Extinguish, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	
	if(bFadeColor 
	// The blue fade from freezing is more important, so that you know how long the player is still frozen.
	// You see the fire anyway, if you want to know if the client is burning..
	&& !SMRPG_IsClientFrozen(client)
	&& SMRPG_ClientWantsCosmetics(client, sUpgradeName, SMRPG_FX_Visuals))
	{
		Help_SetClientRenderColorFadeTarget(plugin, client, 255, 255, 255, -1);
		// Fade as long as the player is burning.
		float fTickrate = 1.0 / GetTickInterval();
		float fStepsize = 255.0 / (fTickrate * fIgniteTime);
		SMRPG_SetClientRenderColorFadeStepsize(client, -1.0, fStepsize, fStepsize);
		Help_SetClientRenderColor(plugin, client, 255, 0, 0, -1);
	}
	
	Call_StartForward(g_hfwdOnClientIgnited);
	Call_PushCell(client);
	Call_PushFloat(fIgniteTime);
	Call_Finish();
	
	return true;
}

// native SMRPG_ExtinguishClient(int client);
public int Native_ExtinguishClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	if(!g_hExtinguish[client])
		return ThrowNativeError(SP_ERROR_NATIVE, "Client is not burning.");
	
	ResetIgniteClient(client, false);
	return 0;
}

// native bool SMRPG_IsClientBurning(int client);
public int Native_IsClientBurning(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	return g_hExtinguish[client] != null;
}

/**
 * Helpers
 */
void ExtinguishClient(int client)
{
	ExtinguishEntity(client);
	// Extinguish the ragdoll too!
	if(!IsPlayerAlive(client))
	{
		int iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if(iRagdoll > 0)
			ExtinguishEntity(iRagdoll);
	}
	
	Help_ResetClientToDefaultColor(g_hIgnitePlugin[client], client, true, true, true, false);
	ResetClientIgniteState(client);
	
	Call_StartForward(g_hfwdOnClientExtinguished);
	Call_PushCell(client);
	Call_Finish();
}

// Client doesn't have to ingame for this one.
void ResetClientIgniteState(int client)
{
	g_hIgnitePlugin[client] = null;
	g_iAttacker[client] = -1;
}