#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <smlib>

#define UPGRADE_SHORTNAME "stealth"
#define STEALTH_INC 27

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Stealth",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Stealth upgrade for SM:RPG. Renders players opaque.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
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
		SMRPG_RegisterUpgradeType("Stealth", UPGRADE_SHORTNAME, "Renders yourself more and more invisible.", 5, true, 5, 15, 10, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnMapStart()
{
	// Just to make sure there's nothing else messing with this effect.
	CreateTimer(5.0, Timer_SetVisibilities, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Event callbacks
 */
public Event_OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return;
	
	SetClientVisibility(client);
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	if(!IsClientInGame(client))
		return;
	
	SetClientVisibility(client);
}

public bool:SMRPG_ActiveQuery(client)
{
	// This is a passive effect, so it's always active, if the player got at least level 1
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
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
 * Timer callbacks
 */
public Action:Timer_SetVisibilities(Handle:timer, any:data)
{
	SetVisibilities();
	
	return Plugin_Continue;
}

/**
 * Helper functions
 */
SetVisibilities()
{
	if(!SMRPG_IsEnabled())
		return;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return;
	
	new bool:bBotEnable = SMRPG_IgnoreBots();
	
	new iLevel;
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		// Are bots allowed to use this upgrade?
		if(!bBotEnable && IsFakeClient(i))
			continue;
		
		// Player didn't buy this upgrade yet.
		iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			continue;
		
		SetClientVisibility(i);
	}
}

SetClientVisibility(client)
{
	if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
		return; // Some other plugin doesn't want this effect to run
	
	new iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	new iAlpha = 255 - iLevel * STEALTH_INC;
	// Keep the player visible enough, even if we break the maxlevel barrier.
	if(iAlpha < 120)
		iAlpha = 120;
	Entity_SetRenderColor(client, -1, -1, -1, iAlpha);
	
	// Render his weapons opaque too.
	new iWeapon = -1, iIndex;
	while((iWeapon = Client_GetNextWeapon(client, iIndex)) != -1)
	{
		SetEntityRenderMode(iWeapon, RENDER_TRANSCOLOR);
		Entity_SetRenderColor(iWeapon, -1, -1, -1, iAlpha);
	}
	
	// Take care of any props attachted to him like hats.
	decl String:sBuffer[64];
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