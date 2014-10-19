/**
 * This file is part of the SM:RPG Effect Hub.
 * Handles igniting of players.
 */

new Handle:g_hfwdOnClientIgnite;
new Handle:g_hfwdOnClientIgnited;
new Handle:g_hfwdOnClientExtinguished;

new Handle:g_hExtinguish[MAXPLAYERS+1];
new Handle:g_hIgnitePlugin[MAXPLAYERS+1];

/**
 * Setup helpers
 */
RegisterIgniteNatives()
{
	CreateNative("SMRPG_IgniteClient", Native_IgniteClient);
	CreateNative("SMRPG_ExtinguishClient", Native_ExtinguishClient);
	CreateNative("SMRPG_IsClientBurning", Native_IsClientBurning);
}

RegisterIgniteForwards()
{
	// forward Action:SMRPG_OnClientIgnite(client, &Float:fTime);
	g_hfwdOnClientIgnite = CreateGlobalForward("SMRPG_OnClientIgnite", ET_Hook, Param_Cell, Param_FloatByRef);
	// forward SMRPG_OnClientIgnited(client, Float:fTime);
	g_hfwdOnClientIgnited = CreateGlobalForward("SMRPG_OnClientIgnited", ET_Ignore, Param_Cell, Param_Float);
	// forward SMRPG_OnClientExtinguished(client);
	g_hfwdOnClientExtinguished = CreateGlobalForward("SMRPG_OnClientExtinguished", ET_Ignore, Param_Cell);
}

ResetIgniteClient(client, bool:bDisconnect)
{
	if(g_hExtinguish[client] != INVALID_HANDLE && IsClientInGame(client))
		TriggerTimer(g_hExtinguish[client]);
	ClearHandle(g_hExtinguish[client]);
	
	// Extinguish again a few frames later, so ragdolls don't burn.
	if(!bDisconnect)
		g_hExtinguish[client] = CreateTimer(0.2, Timer_Extinguish, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer callbacks
 */
public Action:Timer_Extinguish(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Stop;
	
	g_hExtinguish[client] = INVALID_HANDLE;
	
	ExtinguishEntity(client);
	// Extinguish the ragdoll too!
	if(!IsPlayerAlive(client))
	{
		new iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if(iRagdoll > 0)
			ExtinguishEntity(iRagdoll);
	}
	
	Help_ResetClientToDefaultColor(g_hIgnitePlugin[client], client, true, true, true, false);
	g_hIgnitePlugin[client] = INVALID_HANDLE;
	
	Call_StartForward(g_hfwdOnClientExtinguished);
	Call_PushCell(client);
	Call_Finish();
	
	return Plugin_Stop;
}

/**
 * Native handlers
 */
// native bool:SMRPG_IgniteClient(client, Float:fTime, const String:sUpgradeName[], bool:bFadeColor=true);
public Native_IgniteClient(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
		return false;
	}
	
	new Float:fIgniteTime = Float:GetNativeCell(2);
	new iLen;
	GetNativeStringLength(3, iLen);
	new String:sUpgradeName[iLen+1];
	GetNativeString(3, sUpgradeName, iLen+1);
	new bool:bFadeColor = GetNativeCell(4);
	
	new Action:ret;
	Call_StartForward(g_hfwdOnClientIgnite);
	Call_PushCell(client);
	Call_PushFloatRef(fIgniteTime);
	Call_Finish(ret);
	
	if(ret >= Plugin_Handled)
		return false;
	
	// Are you insane?
	if(fIgniteTime < 0.0)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid ignite time %f.", fIgniteTime);
		return false;
	}
	
	// Ignite the player.
	IgniteEntity(client, fIgniteTime);
	g_hIgnitePlugin[client] = plugin;
	
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
		new Float:fTickrate = 1.0 / GetTickInterval();
		new Float:fStepsize = 255.0 / (fTickrate * fIgniteTime);
		SMRPG_SetClientRenderColorFadeStepsize(client, -1.0, fStepsize, fStepsize);
		Help_SetClientRenderColor(plugin, client, 255, 0, 0, -1);
	}
	
	Call_StartForward(g_hfwdOnClientIgnited);
	Call_PushCell(client);
	Call_PushFloat(fIgniteTime);
	Call_Finish();
	
	return true;
}

// native SMRPG_ExtinguishClient(client);
public Native_ExtinguishClient(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
		return;
	}
	
	if(!g_hExtinguish[client])
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Client is not burning.");
		return;
	}
	
	ResetIgniteClient(client, false);
}

// native bool:SMRPG_IsClientBurning(client);
public Native_IsClientBurning(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	if(client <= 0 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
		return false;
	}
	
	return g_hExtinguish[client] != INVALID_HANDLE;
}