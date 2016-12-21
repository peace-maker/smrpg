#if defined _smrpg_included
  #endinput
#endif
#define _smrpg_included

/**
 * Check if SM:RPG is enabled.
 *
 * @return True, if enabled, false otherwise.
 */
native bool SMRPG_IsEnabled();

/**
 * Check if bots should not get any effects from the rpg plugin.
 *
 * @return True, if bots should be ignored, false otherwise.
 */
native bool SMRPG_IgnoreBots();

/**
 * Is the server in Free-For-All mode?
 * Ignore teamchecks.
 *
 * @return True, if teammates are enemies, false otherwise.
 */
native bool SMRPG_IsFFAEnabled();

/**
 * Called when SM:RPG is enabled or disabled. (smrpg_enable)
 *
 * @param bEnabled True, if SM:RPG is now enabled, false if it's now disabled.
 */
forward void SMRPG_OnEnableStatusChanged(bool bEnabled);

#include <smrpg/smrpg_clients>
#include <smrpg/smrpg_upgrades>
#include <smrpg/smrpg_topmenu>
#include <smrpg/smrpg_settings>
#include <smrpg/smrpg_database>

public SharedPlugin __pl_smrpg = 
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
public void __pl_smrpg_SetNTVOptional()
{
	MarkNativeAsOptional("SMRPG_IsEnabled");
	MarkNativeAsOptional("SMRPG_IgnoreBots");
	MarkNativeAsOptional("SMRPG_IsFFAEnabled");
	MarkNativeAsOptional("SMRPG_GetClientLevel");
	MarkNativeAsOptional("SMRPG_SetClientLevel");
	MarkNativeAsOptional("SMRPG_GetClientCredits");
	MarkNativeAsOptional("SMRPG_SetClientCredits");
	MarkNativeAsOptional("SMRPG_GetClientExperience");
	MarkNativeAsOptional("SMRPG_SetClientExperience");
	MarkNativeAsOptional("SMRPG_ResetClientStats");
	MarkNativeAsOptional("SMRPG_IsClientAFK");
	MarkNativeAsOptional("SMRPG_AddClientExperience");
	MarkNativeAsOptional("SMRPG_LevelToExperience");
	MarkNativeAsOptional("SMRPG_ResetAllPlayers");
	MarkNativeAsOptional("SMRPG_FlushDatabase");
	MarkNativeAsOptional("SMRPG_GetClientRank");
	MarkNativeAsOptional("SMRPG_GetRankCount");
	MarkNativeAsOptional("SMRPG_GetTop10Players");
	MarkNativeAsOptional("SMRPG_GetWeaponExperience");
	MarkNativeAsOptional("SMRPG_GetClientLastResetTime");
	MarkNativeAsOptional("SMRPG_GetClientLastSeenTime");
	MarkNativeAsOptional("SMRPG_RegisterUpgradeType");
	MarkNativeAsOptional("SMRPG_UnregisterUpgradeType");
	MarkNativeAsOptional("SMRPG_CreateUpgradeConVar");
	MarkNativeAsOptional("SMRPG_SetUpgradeTranslationCallback");
	MarkNativeAsOptional("SMRPG_SetUpgradeResetCallback");
	MarkNativeAsOptional("SMRPG_SetUpgradeDefaultCosmeticEffect");
	MarkNativeAsOptional("SMRPG_ClientWantsCosmetics");
	MarkNativeAsOptional("SMRPG_UpgradeExists");
	MarkNativeAsOptional("SMRPG_ResetUpgradeEffectOnClient");
	MarkNativeAsOptional("SMRPG_GetUpgradeInfo");
	MarkNativeAsOptional("SMRPG_RunUpgradeEffect");
	MarkNativeAsOptional("SMRPG_GetClientUpgradeLevel");
	MarkNativeAsOptional("SMRPG_GetClientPurchasedUpgradeLevel");
	MarkNativeAsOptional("SMRPG_SetClientSelectedUpgradeLevel");
	MarkNativeAsOptional("SMRPG_ClientBuyUpgrade");
	MarkNativeAsOptional("SMRPG_ClientSellUpgrade");
	MarkNativeAsOptional("SMRPG_IsUpgradeActiveOnClient");
	MarkNativeAsOptional("SMRPG_CheckUpgradeAccess");
	MarkNativeAsOptional("SMRPG_GetTopMenu");
	MarkNativeAsOptional("SMRPG_GetSetting");
	MarkNativeAsOptional("SMRPG_SetSetting");
}
#endif