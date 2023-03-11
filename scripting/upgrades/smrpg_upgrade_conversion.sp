#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "conversion"
#define PLUGIN_VERSION	  "1.0"

public Plugin myinfo =
{
	name		= "SM:RPG Upgrade > Conversion ",
	author		= "WanekWest",
	description = "Conversion allows the player to turn excess money into exp.",
	version		= PLUGIN_VERSION,
	url			= "https://vk.com/wanek_west"


}

ConVar g_hCvMoneyConvertType,
	   g_hCvMoneyConvertRequestAmount, g_hCvMoneyConvertIncreaserPerLevel, g_hCvMoneyConvertBaseAmount;

int	  hCvMoneyConvertType, hCvMoneyConvertRequestAmount;
float hCvMoneyConvertIncreaserPerLevel, hCvMoneyConvertBaseAmount;

int	  g_MoneyOffset;

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");

	
	HookEvent("bomb_defused", Event_OnBombDefused);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("hostage_rescued", Event_OnHostageRescue);
	HookEvent("bomb_exploded", Event_OnBombExploded);
	HookEvent("player_death", Event_OnPlayerDeath);
//	HookEvent("round_start", Event_OnRoundStart);
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("hostage_follows", Event_OnHostageFollow);

	g_MoneyOffset = FindSendPropInfo("CCSPlayer", "m_iAccount");
	if (g_MoneyOffset == -1)
	{
		SetFailState("Can not find m_iAccount.");
	}
}

public void OnPluginEnd()
{
	if (SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
	// Register this upgrade in SM:RPG
	if (StrEqual(name, "smrpg"))
	{
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Conversion", UPGRADE_SHORTNAME, "Conversion allows the player to turn excess money into credits.", 10, true, 5, 15, 10);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);

		g_hCvMoneyConvertType = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_conversion_type", "0", "Conversion type. 0 - to EXP, 1 - to Credits", _, true, 0.0);
		g_hCvMoneyConvertType.AddChangeHook(OnConverChangeType);
		hCvMoneyConvertType			   = g_hCvMoneyConvertType.IntValue;

		g_hCvMoneyConvertRequestAmount = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_conversion_request_amount", "100", "How much money to take for 1 unit of Experience/Credits.", _, true, 0.0);
		g_hCvMoneyConvertRequestAmount.AddChangeHook(OnConverChangeReqMoney);
		hCvMoneyConvertRequestAmount	   = g_hCvMoneyConvertRequestAmount.IntValue;

		g_hCvMoneyConvertIncreaserPerLevel = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_conversion_increase", "1.0", "Increase value per level.", _, true, 0.0);
		g_hCvMoneyConvertIncreaserPerLevel.AddChangeHook(OnConverChangeIncreaseValue);
		hCvMoneyConvertIncreaserPerLevel = g_hCvMoneyConvertIncreaserPerLevel.FloatValue;

		g_hCvMoneyConvertBaseAmount		 = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_conversion_base_amount", "1.0", "The base amount to start with at level 1.", _, true, 0.0);
		g_hCvMoneyConvertBaseAmount.AddChangeHook(OnConverChangeBaseAmount);
		hCvMoneyConvertBaseAmount = g_hCvMoneyConvertBaseAmount.FloatValue;
	}
}

public void OnConverChangeType(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	hCvMoneyConvertType = hCvar.IntValue;
}

public void OnConverChangeReqMoney(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	hCvMoneyConvertRequestAmount = hCvar.IntValue;
}

public void OnConverChangeIncreaseValue(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	hCvMoneyConvertIncreaserPerLevel = hCvar.FloatValue;
}

public void OnConverChangeBaseAmount(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	hCvMoneyConvertBaseAmount = hCvar.FloatValue;
}

// The core wants to display your upgrade somewhere. Translate it into the clients language!
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if (type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if (type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH + 12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

public void Event_OnRoundEnd(Event event, const char[] error, bool dontBroadcast)
{
	int maxClients = MaxClients;
	int time;
	GetMapTimeLeft(time);

	//This is the time before mapchange. After the last round it takes about 3 seconds for the map to change. Depending on server settings.
	if(time <= 4)
	{
    	for (int client = 1; client <= maxClients; client++)
    {

		Conversion(client, 0);
		if(client==maxClients)
			return;
		
    }
	return;
	}
}

public void Event_OnHostageFollow(Event event, const char[] error, bool dontBroadcast)
{	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;

	Conversion(client, 10000);
	return;
}

public void Event_OnPlayerDeath(Event event, const char[] error, bool dontBroadcast)
{

	int client = GetClientOfUserId(event.GetInt("attacker"));
	if (!client)
		return;

	Conversion(client, 9700);
	return;

}


public void Event_OnHostageRescue(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;

	Conversion(client, 10000);
	return;
}

public void Event_OnBombDefused(Event event, const char[] name, bool dontBroadcast)
{	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;

	Conversion(client, 10000);
	return;
}

public void Event_OnBombExploded(Event event, const char[] name, bool dontBroadcast)
{	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;

	Conversion(client, 10000);
	return;
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;

	Conversion(client, 10000);
	return;
}

public void Conversion(int client, int moneyThreshold)
{
	if (!client)
		return;

	// SM:RPG is disabled?
	if (!SMRPG_IsEnabled())
		return;

	// The upgrade is disabled completely?
	if (!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;

		// Are bots allowed to use this upgrade?
	//if (IsFakeClient(client) && SMRPG_IgnoreBots())
		//return;

		// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if (iLevel <= 0)
		return;
		
	int currentClientMoney = GetEntData(client, g_MoneyOffset);
	if (currentClientMoney >= moneyThreshold + hCvMoneyConvertRequestAmount)
	{

		// int clientMoney = GetEntProp(client, Prop_Send, "m_iAccount");
		int	  amountToSubstract = currentClientMoney - moneyThreshold;
		float amountToAdd		= hCvMoneyConvertBaseAmount + hCvMoneyConvertIncreaserPerLevel * (iLevel - 1);
		int	  amountToGive		= RoundToCeil(amountToSubstract / hCvMoneyConvertRequestAmount * amountToAdd);
		PrintToConsole(client, "You have earned %d experience for converting $", amountToGive);
		char reason[256];
		FormatEx(reason, sizeof(reason), "converting %d$", amountToSubstract);

		if (hCvMoneyConvertType == 0)
		{
			SMRPG_AddClientExperience(client, amountToGive, reason, false, -1);
			SetEntData(client, g_MoneyOffset, moneyThreshold);
		}
		else
		{
			SMRPG_SetClientCredits(client, SMRPG_GetClientCredits(client) + amountToGive);
			SetEntData(client, g_MoneyOffset, moneyThreshold);
		}
	}

	return;
}

