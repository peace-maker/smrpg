#if defined _smrpg_included
  #endinput
#endif
#define _smrpg_included

native bool:SMRPG_IsEnabled();
native bool:SMRPG_IgnoreBots();

native SMRPG_GetClientLevel(client);
native bool:SMRPG_SetClientLevel(client, level);

native SMRPG_GetClientCredits(client);
native bool:SMRPG_SetClientCredits(client, credits);

native SMRPG_GetClientExperience(client);
native bool:SMRPG_SetClientExperience(client, exp);

native bool:SMRPG_AddClientExperience(client, exp, bool:bHideNotice);
native SMRPG_LevelToExperience(iLevel);

enum UpgradeQueryType
{
	UpgradeQueryType_Buy,
	UpgradeQueryType_Sell
};

functag public SMRPG_UpgradeQuery(client, UpgradeQueryType:type);
functag public bool:SMRPG_ActiveQuery(client);
functag public SMRPG_TranslateUpgrade(client, String:translation[], maxlen);

native SMRPG_RegisterUpgradeType(const String:name[], const String:shortname[], maxlevelbarrier, bool:bDefaultEnable, iDefaultMaxLevel, iDefaultStartCost, iDefaultCostInc, SMRPG_UpgradeQuery:querycb, SMRPG_ActiveQuery:activecb);
native SMRPG_UnregisterUpgradeType(const String:shortname[]);
native SMRPG_SetUpgradeTranslationCallback(const String:shortname[], SMRPG_TranslateUpgrade:cb);

native bool:SMRPG_UpgradeExists(const String:shortname[]);

#define MAX_UPGRADE_NAME_LENGTH 64
#define MAX_UPGRADE_SHORTNAME_LENGTH 32

enum UpgradeInfo
{
	bool:UI_enabled, // upgrade enabled?
	UI_maxLevelBarrier, // upper limit of maxlevel setting. Can't set maxlevel higher than that.
	UI_maxLevel, // Maximal level a player can get for this upgrade
	UI_startCost, // The amount of credits the first level costs
	UI_incCost, // The amount of credits each level costs more
	String:UI_name[MAX_UPGRADE_NAME_LENGTH],
	String:UI_shortName[MAX_UPGRADE_SHORTNAME_LENGTH] // shortname used as unique identifier in all commands and database
};
native SMRPG_GetUpgradeInfo(const String:shortname[], upgrade[UpgradeInfo]);

native SMRPG_GetClientUpgradeLevel(client, const String:shortname[]);
native bool:SMRPG_ClientBuyUpgrade(client, const String:shortname[]);
native bool:SMRPG_ClientSellUpgrade(client, const String:shortname[]);

native bool:SMRPG_IsUpgradeActiveOnClient(client, const String:shortname[]);

forward SMRPG_OnClientLoaded(client);

forward Action:SMRPG_OnClientLevel(client, oldlevel, newlevel);
forward Action:SMRPG_OnClientExperience(client, oldexp, newexp);
forward Action:SMRPG_OnClientCredits(client, oldcredits, newcredits);

forward Action:SMRPG_OnBuyUpgrade(client, const String:shortname[], newlevel);
forward Action:SMRPG_OnSellUpgrade(client, const String:shortname[], newlevel);

enum ExperienceReason
{
	ER_PlayerHurt,
	ER_PlayerKill,
	ER_RoundEnd
};

forward Action:SMRPG_OnAddExperience(client, ExperienceReason:reason, &iExperience);

stock Float:SMRPG_TeamRatio(iTeam)
{
	if(iTeam <= 1)
		return 0.0;
	
	new Float:fTeamRatio;
	
	if(iTeam == 2)
		fTeamRatio = float(GetTeamClientCount(2)) / float(GetTeamClientCount(3));
	else
		fTeamRatio = float(GetTeamClientCount(3)) / float(GetTeamClientCount(2));
	return fTeamRatio;
}

public SharedPlugin:__pl_smrpg = 
{
	name = "smrpg",
	file = "smrpg.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_smrpg_SetNTVOptional()
{
	MarkNativeAsOptional("SMRPG_IsEnabled");
	MarkNativeAsOptional("SMRPG_IgnoreBots");
	MarkNativeAsOptional("SMRPG_GetClientLevel");
	MarkNativeAsOptional("SMRPG_SetClientLevel");
	MarkNativeAsOptional("SMRPG_GetClientCredits");
	MarkNativeAsOptional("SMRPG_SetClientCredits");
	MarkNativeAsOptional("SMRPG_GetClientExperience");
	MarkNativeAsOptional("SMRPG_SetClientExperience");
	MarkNativeAsOptional("SMRPG_AddClientExperience");
	MarkNativeAsOptional("SMRPG_LevelToExperience");
	MarkNativeAsOptional("SMRPG_RegisterUpgradeType");
	MarkNativeAsOptional("SMRPG_UnregisterUpgradeType");
	MarkNativeAsOptional("SMRPG_UpgradeExists");
	MarkNativeAsOptional("SMRPG_GetUpgradeInfo");
	MarkNativeAsOptional("SMRPG_GetClientUpgradeLevel");
	MarkNativeAsOptional("SMRPG_ClientBuyUpgrade");
	MarkNativeAsOptional("SMRPG_ClientSellUpgrade");
	MarkNativeAsOptional("SMRPG_IsUpgradeActiveOnClient");
}
#endif