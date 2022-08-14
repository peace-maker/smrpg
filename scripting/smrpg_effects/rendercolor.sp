/**
 * This file is part of the SM:RPG Effect Hub.
 * Handles the render color of players
 */

// Default render color to reset to when the fade finished.
int g_iDefaultColor[MAXPLAYERS+1][4];

float g_fColor[MAXPLAYERS+1][4];

int g_iColorFadeTarget[MAXPLAYERS+1][4];
float g_fColorFadeStep[MAXPLAYERS+1][4];

// Save which plugin last changed the color, so only that plugin may reset the color to default.
Handle g_hLastAccessedPlugin[MAXPLAYERS+1][4];

/**
 * Setup helpers
 */
void RegisterRenderColorNatives()
{
	CreateNative("SMRPG_SetClientDefaultColor", Native_SetClientDefaultColor);
	CreateNative("SMRPG_SetClientRenderColor", Native_SetClientRenderColor);
	CreateNative("SMRPG_SetClientRenderColorFadeTarget", Native_SetClientRenderColorFadeTarget);
	CreateNative("SMRPG_SetClientRenderColorFadeStepsize", Native_SetClientRenderColorFadeStepsize);
	
	CreateNative("SMRPG_ResetClientToDefaultColor", Native_ResetClientToDefaultColor);
}

void ResetRenderColorClient(int client)
{
	for(int i=0;i<4;i++)
	{
		g_iDefaultColor[client][i] = 255;
		g_iColorFadeTarget[client][i] = -1;
		g_fColorFadeStep[client][i] = 1.0;
		g_fColor[client][i] = 255.0;
		g_hLastAccessedPlugin[client][i] = null;
	}
}

void ApplyDefaultRenderColor(int client)
{
	for(int i=0;i<4;i++)
	{
		g_iColorFadeTarget[client][i] = -1;
		g_fColor[client][i] = 255.0;
	}
	Help_ResetClientToDefaultColor(null, client, true, true, true, true, true);
}

// Fade players from current color linearly to the fade target.
public void OnGameFrame()
{
	bool bFade;
	for(int client=1;client<=MaxClients;client++)
	{
		if(!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;
		
		bFade = false;
		int iColor[4];
		for(int c=0;c<4;c++)
		{
			// Don't change this channel by default.
			iColor[c] = -1;
			
			// We don't want to fade this channel.
			if(g_iColorFadeTarget[client][c] < 0)
				continue;
			
			// We need to fade up in that direction
			if(g_fColor[client][c] < g_iColorFadeTarget[client][c])
			{
				g_fColor[client][c] += g_fColorFadeStep[client][c];
				if(g_fColor[client][c] > 255)
					g_fColor[client][c] = 255.0;
				iColor[c] = RoundToFloor(g_fColor[client][c]);
				bFade = true;
				
				// Did we finish fading to that color?
				if(g_fColor[client][c] >= g_iColorFadeTarget[client][c])
					g_iColorFadeTarget[client][c] = -1;
			}
			// or fade down
			else if(g_fColor[client][c] > g_iColorFadeTarget[client][c])
			{
				g_fColor[client][c] -= g_fColorFadeStep[client][c];
				if(g_fColor[client][c] < 0)
					g_fColor[client][c] = 0.0;
				iColor[c] = RoundToFloor(g_fColor[client][c]);
				bFade = true;
				
				// Did we finish fading to that color?
				if(g_fColor[client][c] <= g_iColorFadeTarget[client][c])
					g_iColorFadeTarget[client][c] = -1;
			}
			// no need to fade anymore.
			else
			{
				g_iColorFadeTarget[client][c] = -1;
				iColor[c] = RoundToFloor(g_fColor[client][c]);
				bFade = true;
			}
		}
		
		if(bFade)
		{
			SetEntityRenderMode(client, RENDER_TRANSCOLOR);
			Entity_SetRenderColor(client, iColor[0], iColor[1], iColor[2], iColor[3]);
		}
	}
}

/**
 * Native handlers
 */
// native void SMRPG_SetClientDefaultColor(int client, int r=-1, int g=-1, int b=-1, int a=-1);
public int Native_SetClientDefaultColor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	int iColor[4];
	for(int i=0;i<4;i++)
	{
		iColor[i] = GetNativeCell(i+2);
		if(iColor[i] >= 0)
		{
			// colors are bytes..
			if(iColor[i] > 255)
				iColor[i] = 255;
			
			g_iDefaultColor[client][i] = iColor[i];
		}
	}
	return 0;
}

// native void SMRPG_SetClientRenderColor(intclient, int r=-1, int g=-1, int b=-1, int a=-1);
public int Native_SetClientRenderColor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	Help_SetClientRenderColor(plugin, client, GetNativeCell(2), GetNativeCell(3), GetNativeCell(4), GetNativeCell(5));
	return 0;
}

stock void Help_SetClientRenderColor(Handle hPlugin, int client, int r=-1, int g=-1, int b=-1, int a=-1)
{
	int iColor[4];
	iColor[0] = r;
	iColor[1] = g;
	iColor[2] = b;
	iColor[3] = a;
	
	for(int i=0;i<4;i++)
	{
		// Entity_SetRenderColor checks explicitly for -1
		if(iColor[i] < 0)
			iColor[i] = -1;
		
		// Only set the color, if we want to change it.
		if(iColor[i] >= 0)
		{
			// colors are bytes..
			if(iColor[i] > 255)
				iColor[i] = 255;
			
			g_fColor[client][i] = float(iColor[i]);
			g_hLastAccessedPlugin[client][i] = hPlugin;
		}
	}
	
	// Actually change the color.
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	Entity_SetRenderColor(client, iColor[0], iColor[1], iColor[2], iColor[3]);
}

// native void SMRPG_SetClientRenderColorFadeTarget(int client, int r=-1, int g=-1, int b=-1, int a=-1);
public int Native_SetClientRenderColorFadeTarget(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	Help_SetClientRenderColorFadeTarget(plugin, client, GetNativeCell(2), GetNativeCell(3), GetNativeCell(4), GetNativeCell(5));
	return 0;
}

stock void Help_SetClientRenderColorFadeTarget(Handle hPlugin, int client, int r=-1, int g=-1, int b=-1, int a=-1)
{
	int iColor[4];
	iColor[0] = r;
	iColor[1] = g;
	iColor[2] = b;
	iColor[3] = a;
	
	for(int i=0;i<4;i++)
	{
		if(iColor[i] < 0)
			iColor[i] = -1;
		
		// Start to fade to that color
		if(iColor[i] >= 0)
		{
			// colors are bytes..
			if(iColor[i] > 255)
				iColor[i] = 255;
			
			g_iColorFadeTarget[client][i] = iColor[i];
			g_hLastAccessedPlugin[client][i] = hPlugin;
		}
	}
}

// native void SMRPG_SetClientRenderColorFadeStepsize(int client, int r=-1, int g=-1, int b=-1, int a=-1);
public int Native_SetClientRenderColorFadeStepsize(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	float fStepsize[4];
	for(int i=0;i<4;i++)
	{
		fStepsize[i] = view_as<float>(GetNativeCell(i+2));
		
		if(fStepsize[i] <= 0.0)
			continue;
		
		g_fColorFadeStep[client][i] = fStepsize[i];
	}
	return 0;
}

// native void SMRPG_ResetClientToDefaultColor(int client, bool bResetRed, bool bResetGreen, bool bResetBlue, bool bResetAlpha, bool bForceReset=false);
public int Native_ResetClientToDefaultColor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if(client <= 0 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	Help_ResetClientToDefaultColor(plugin, client, GetNativeCell(2), GetNativeCell(3), GetNativeCell(4), GetNativeCell(5), GetNativeCell(6));
	return 0;
}

stock void Help_ResetClientToDefaultColor(Handle hPlugin, int client, bool bResetRed, bool bResetGreen, bool bResetBlue, bool bResetAlpha, bool bForceReset=false)
{
	bool bResetChannel[4];
	bResetChannel[0] = bResetRed;
	bResetChannel[1] = bResetGreen;
	bResetChannel[2] = bResetBlue;
	bResetChannel[3] = bResetAlpha;
	
	int iColor[4];
	for(int i=0;i<4;i++)
	{
		// Ignore it by default.
		iColor[i] = -1;
		
		// Don't touch this channel?
		if(!bResetChannel[i])
			continue;
		
		// That channel was last set by this plugin. That's fine. Reset it.
		if(bForceReset || !g_hLastAccessedPlugin[client][i] || g_hLastAccessedPlugin[client][i] == hPlugin || !IsValidPlugin(g_hLastAccessedPlugin[client][i]))
		{
			iColor[i] = g_iDefaultColor[client][i];
			g_fColor[client][i] = float(g_iDefaultColor[client][i]);
			g_hLastAccessedPlugin[client][i] = null;
		}
	}
	
	// Actually change the color.
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	Entity_SetRenderColor(client, iColor[0], iColor[1], iColor[2], iColor[3]);
}