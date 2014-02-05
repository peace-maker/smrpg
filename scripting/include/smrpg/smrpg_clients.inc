#if defined _smrpg_clients_included
  #endinput
#endif
#define _smrpg_clients_included

#include <smrpg>

/**
 * Gets a client's current RPG level.
 *
 * @param client         The client
 * @return The client's rpg level (level start at 1)
 * @error Invalid client index
 */
native SMRPG_GetClientLevel(client);

/**
 * Sets a client's RPG level to another level.
 *
 * @param client         The client
 * @param level          The new level of the client
 * @return True, if the level was set successfully, false if some plugin blocked it in the SMRPG_OnClientLevel forward.
 * @error Invalid client index
 */
native bool:SMRPG_SetClientLevel(client, level);

/**
 * Gets a client's current RPG credits.
 *
 * @param client         The client
 * @return The client's rpg credits.
 * @error Invalid client index
 */
native SMRPG_GetClientCredits(client);

/**
 * Sets a client's RPG credits.
 *
 * @param client         The client
 * @param level          The new credits of the client
 * @return True, if the credits were set successfully, false if some plugin blocked it in the SMRPG_OnClientCredits forward.
 * @error Invalid client index
 */
native bool:SMRPG_SetClientCredits(client, credits);

/**
 * Gets a client's current RPG experience.
 *
 * @param client         The client
 * @return The client's rpg experience
 * @error Invalid client index
 */
native SMRPG_GetClientExperience(client);

/**
 * Sets a client's RPG experience.
 * Doesn't level up the client, if he gets more experience than he'd need for a next level.
 * Use SMRPG_AddClientExperience for that.
 *
 * @param client         The client
 * @param level          The new experience of the client
 * @return True, if the experience were set successfully, false if some plugin blocked it in the SMRPG_OnClientExperience forward.
 * @error Invalid client index
 */
native bool:SMRPG_SetClientExperience(client, exp);

/**
 * Adds experience to a client.
 * If he gets enough experience to level up, he levels up.
 *
 * @param client         The client
 * @param level          The experience to add
 * @param bHideNotice    Set to true, if you want a notification displayed in the HintText area on the client's screen, telling him the amount of experience he just earned, or to false if not.
 * @noreturn
 * @error Invalid client index
 */
native SMRPG_AddClientExperience(client, exp, bool:bHideNotice);

/**
 * Calculate the amount of experience needed to reach the next level.
 * Level start at 1.
 * 
 * @return The amount of experience needed to reach iLevel+1.
 */
native SMRPG_LevelToExperience(iLevel);

/**
 * List of default reasons the core plugin adds experience to clients for.
 */
enum ExperienceReason
{
	ER_PlayerHurt, // Give experience to the attacker when he hurt an enemy
	ER_PlayerKill, // Give experience to the attacker when he killed an enemy
	ER_RoundEnd // Give experience to the winning team
};

/**
 * Called when the core is about to give a client some experience for above reasons.
 * You can modify the experience or block it all together.
 * This is useful, if you want to add more game specific experience handling which override the default ones.
 *
 * This is not called for any other added experience in other ways. Only the default events in the core.
 *
 * @param client         The client, which is about to get some experience.
 * @param reason         The reason why this client gets experience.
 * @param iExperience    By reference. The experience to give to the player. You can change it to whatever you like.
 * @return >= Plugin_Handled to block it, Plugin_Continue to pass, Plugin_Changed if you modified iExperience.
 */
forward Action:SMRPG_OnAddExperience(client, ExperienceReason:reason, &iExperience);

/**
 * Calculate the ratio of team1:team2.
 * This is e.g. used to lower the amount of experience earned, when a winning team has more players than the other.
 * 
 * @param iTeam          The team index of the player which is about to get experience.
 * @return The teammember amount ratio of iTeam : otherTeam.
 */
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