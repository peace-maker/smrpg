#if defined _smrpg_health_included
  #endinput
#endif
#define _smrpg_health_included

/**
 * Get the maximal health for a client.
 * Returns the default maxhealth value, if client doesn't have the health upgrade or SM:RPG is disabled.
 *
 * @param client  The client whos maxhealth you want to know.
 * @return        The client's maxhealth depending on his SM:RPG maxhealth level.
 */
native SMRPG_Health_GetMaxHealth(client);

public SharedPlugin:__pl_smrpg_health = 
{
	name = "smrpg_health",
	file = "smrpg_upgrade_health.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_smrpg_health_SetNTVOptional()
{
	MarkNativeAsOptional("SMRPG_Health_GetMaxHealth");
}
#endif