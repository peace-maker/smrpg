#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <sdkhooks>


#pragma newdecls required
#include <smrpg>

#undef REQUIRE_PLUGIN

#define UPGRADE_SHORTNAME "pickpocket"


ConVar g_hCVAmount;
ConVar g_hCVAmountIncrease;
ConVar g_hCVWeapon;


int	  g_MoneyOffset;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Pickpocket",
	author = "DeewaTT",
	description = "Pickpocket upgrade for SM:RPG. Steals money with every hit from your knife.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

	// We define this variable to check for the players money later.
	g_MoneyOffset = FindSendPropInfo("CCSPlayer", "m_iAccount");
	if (g_MoneyOffset == -1)
	{
		SetFailState("Can not find m_iAccount.");
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
		SMRPG_RegisterUpgradeType("Pickpocket", UPGRADE_SHORTNAME, "Steals money when knifing.", 0, true, 5, 5, 10);
		SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVAmount = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_steal_amount", "1", "Specify the base amount of money stolen at the first level.", 0, true, 0.1);
		g_hCVAmountIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_steal_amount_inc", "1", "Additional money to steal multiplied by level. (base + inc * (level-1))", 0, true, 0.0);
		g_hCVWeapon = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_steal_weapon", "knife", "Entity name of the weapon which should trigger the effect. (e.g. knife)");
	}
}

public void OnClientPutInServer(int client)
{
	// Declare the hook we will use.
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
}

/**
 * SM:RPG Upgrade callbacks
 */

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

public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients)
		return;

	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;	
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return;

	char sWeapon[256], sTargetWeapon[128];
	g_hCVWeapon.GetString(sTargetWeapon, sizeof(sTargetWeapon));
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	ReplaceString(sWeapon, sizeof(sWeapon), "weapon_", "", false);
	
	// This effect only applies to the specified weapon.
	if(StrContains(sWeapon, sTargetWeapon) == -1)
		return;
	
	Takemoney(attacker, victim);
}

public void Takemoney(int attacker, int victim)
{

	if (!attacker)
		return;

	// Are bots allowed to use this upgrade?
	if(SMRPG_IgnoreBots() && IsFakeClient(attacker))
		return;
			
	// Some other plugin doesn't want this effect to run
	if(!SMRPG_RunUpgradeEffect(attacker, UPGRADE_SHORTNAME))
		return; 

	// SM:RPG is disabled?
	if (!SMRPG_IsEnabled())
		return;

	// This upgrade is disabled?
	if (!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;

	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if (iLevel <= 0)
		return;

	// Determine how much money will be taken.
	int amountToSteal = RoundToNearest(g_hCVAmount.FloatValue + g_hCVAmountIncrease.FloatValue*(iLevel-1));

	// Check the victims money. If it's less than the attacker wants to take, set it to 0.	
	int currentVictimMoney = GetEntData(victim, g_MoneyOffset);
	int newVictimMoney = currentVictimMoney - amountToSteal;
	if (currentVictimMoney <= amountToSteal)
	{	
		amountToSteal = currentVictimMoney;
		newVictimMoney = 0;
	}
	SetEntData(victim, g_MoneyOffset, newVictimMoney);

	// Check attackers money and add the stolen amount to it.
	int currentAttackerMoney = GetEntData(attacker, g_MoneyOffset);
	int newAttackerMoney = currentAttackerMoney + amountToSteal;
	SetEntData(attacker, g_MoneyOffset, newAttackerMoney);

	return;
}