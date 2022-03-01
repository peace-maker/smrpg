/**
 * SM:RPG Firerate Upgrade
 * Increases the firerate of weapons.
 * 
 * Credits to blodia! His weapon mod (https://forums.alliedmods.net/showthread.php?t=123015)
 * showed me new ways to think about overriding entity behaviour. Thank you!
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>

// Change the upgrade's shortname to a descriptive abbrevation
#define UPGRADE_SHORTNAME "firerate"

ConVar g_hCVIncrease;

float g_fModifyNextAttack[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Firerate",
	author = "Peace-Maker",
	description = "Firerate upgrade for SM:RPG. Increases the firerate of weapons.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	for(int i=1;i<=MaxClients;i++)
		if(IsClientInGame(i))
			OnClientPutInServer(i);
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
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Increase Firerate", UPGRADE_SHORTNAME, "Increases the firerate of weapons.", 0, true, 10, 12, 15);
		
		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_firerate_increase", "0.1", "Decrease time between shots by x% per level.", _, true, 0.01);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PostThink, Hook_OnPostThink);
	SDKHook(client, SDKHook_PostThinkPost, Hook_OnPostThinkPost);
}

public void OnClientDisconnect(int client)
{
	g_fModifyNextAttack[client] = 0.0;
}

/**
 * SM:RPG Upgrade callbacks
 */

// The core wants to display your upgrade somewhere. Translate it into the clients language!
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

public void Hook_OnPostThink(int client)
{
	int iButtons = GetClientButtons(client);
	if(iButtons & IN_ATTACK)
	{
		// Dead players can't shoot.
		if(!IsPlayerAlive(client))
			return;

		// SM:RPG is disabled?
		if(!SMRPG_IsEnabled())
			return;

		// The upgrade is disabled completely?
		if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
			return;

		// Are bots allowed to use this upgrade?
		if(IsFakeClient(client) && SMRPG_IgnoreBots())
			return;

		// Player didn't buy this upgrade yet.
		int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			return;

		// Is he holding a weapon?
		int iWeaponIndex = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (iWeaponIndex == INVALID_ENT_REFERENCE)
			return;
		
		// Credits to blodia for his weapon mod
		// The weapon can't be fired yet.
		if (GetGameTime() < GetEntPropFloat(iWeaponIndex, Prop_Send, "m_flNextPrimaryAttack"))
			return;
		
		// The player can't attack yet.
		if (GetGameTime() < GetEntPropFloat(client, Prop_Send, "m_flNextAttack"))
			return;
		
		// Empty clip.. Can't attack at all.
		if (GetEntProp(iWeaponIndex, Prop_Send, "m_iClip1") <= 0)
			return;
		
		// Only care for weapons with bullets/ammo
		if (GetEntProp(iWeaponIndex, Prop_Send, "m_iPrimaryAmmoType") < 0)
			return;
		
		// This calls the SMRPG_OnUpgradeEffect global forward where other plugins can stop you from applying your effect, if it conflicts with theirs.
		// This also returns false, if the client doesn't have the required admin flags to use the upgrade, so no need to call SMRPG_CheckUpgradeAccess.
		if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
			return; // Some other plugin doesn't want this effect to run
		
		g_fModifyNextAttack[client] = 1.0 / (1.0 + float(iLevel) * g_hCVIncrease.FloatValue);
	}
}

public void Hook_OnPostThinkPost(int client)
{
	if(g_fModifyNextAttack[client] <= 0.0)
		return;
	
	if(!IsPlayerAlive(client))
	{
		g_fModifyNextAttack[client] = 0.0;
		return;
	}
	
	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon != INVALID_ENT_REFERENCE)
	{
		float flNextPrimaryAttack = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
		
		flNextPrimaryAttack -= GetGameTime();
		// Lower the time a bit, so the next bullet can be shot more quickly.
		flNextPrimaryAttack *= g_fModifyNextAttack[client];
		flNextPrimaryAttack += GetGameTime();
		
		SetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack", flNextPrimaryAttack);
	}

	g_fModifyNextAttack[client] = 0.0;
}