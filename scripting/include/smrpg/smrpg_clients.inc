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
 * Gets the rpg rank of a player.
 * The returned rank is a cached value and the current rank is fetched afterwards.
 *
 * @param client        The client
 * @return The client's rpg rank or -1 if the rank wasn't fetched yet or for bots.
 * @error Invalid client index
 */
native SMRPG_GetClientRank(client);

/**
 * Get the total number of ranked players in the database.
 * The returned value is from the cache and the cache is updated afterwards.
 *
 * @return Total number of ranked players.
 */
native SMRPG_GetRankCount();

/**
 * Get the top 10 players.
 * The owner handle in the callback is always INVALID_HANDLE just to not leak the database handle :)
 * The query returned is
 *    SELECT name, level, experience, credits FROM ..
 *
 * @param callback    The default threaded sql callback. The query Handle will be in "hndl".
 * @param data        Optional custom data passed to the callback.
 * @noreturn
 */
native SMRPG_GetTop10Players(SQLTCallback:callback, any:data=0);

/**
 * Resets a clients complete rpg stats including all bought upgrades.
 * CANNOT BE UNDONE!
 *
 * @param client				The client index
 * @noreturn
 * @error Invalid client index
 */
native SMRPG_ResetClientStats(client);

/**
 * Get the time when a client's rpg stats were last reset. Returns the time the player first joined, if his stats were never reset in between.
 *
 * @param client				The client index
 * @return						The unix timestamp when the client was last reset.
 * @error Invalid client index
 */
native SMRPG_GetClientLastResetTime(client);

/**
 * Get the time when the client was last active on the server.
 *
 * @param client				The client index
 * @return						The unix timestamp when the client was last saved on the server.
 * @error Invalid client index
 */
native SMRPG_GetClientLastSeenTime(client);

/**
 * Check if a client is away from keyboard.
 * This is done by saving the player's last position regularly and see if it is still the same later.
 * Shooting resets the timer.
 *
 * @param client				The client index
 * @return	True if player afk, false otherwise.
 * @error Invalid client index
 */
native bool:SMRPG_IsClientAFK(client);

/**
 * Called when the core wants a reason string to be translated so it's displayed in the recent added experience panel.
 * Should look like
 *   15 exp. for killing (name of [other])
 *   100 exp. for winning the round
 *
 * @param client        The client who got experience and in which language the reason should be translated.
 * @param reason        The reason string passed in SMRPG_AddClientExperience
 * @param iExperience   The amount of experience added.
 * @param other         Optionally the index of the other client involved in the reason for this experience. -1 if no other entity involved.
 * @param buffer        The buffer to store the translated reason string in.
 * @param maxlen        The maximal length of the translation buffer.
 * @noreturn
 */
functag public SMRPG_ExpTranslationCb(client, const String:reason[], iExperience, other, String:buffer[], maxlen);

/**
 * Adds experience to a client.
 * If he gets enough experience to level up, he levels up.
 *
 * @param client         The client
 * @param level          The experience to add
 * @param reason         The reason this experience was added.
 * @param bHideNotice    Set to true, if you want a notification displayed in the HintText area on the client's screen, telling him the amount of experience he just earned, or to false if not.
 * @param other          Optional index of other client involved in the reason for this experience. e.g. the victim which was hurt. Set to -1 if no other particular entity was involved.
 * @param callback       Optional translation callback to translate the reason into a human readable format. (See SMRPG_ExpTranslationCb)
 * @return               True if the experience was added, false otherwise.
 * @error Invalid client index
 */
native bool:SMRPG_AddClientExperience(client, exp, const String:reason[], bool:bHideNotice, other=-1, SMRPG_ExpTranslationCb:callback=SMRPG_ExpTranslationCb:INVALID_FUNCTION);

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
#define ExperienceReason_PlayerHurt "def_playerhurt" // Give experience to the attacker when he hurt an enemy
#define ExperienceReason_PlayerKill "def_playerkill" // Give experience to the attacker when he killed an enemy
#define ExperienceReason_RoundEnd "def_roundend" // Give experience to the winning team
#define ExperienceReason_Admin "def_admin" // An admin gave experience through commands or admin menu

/**
 * Called when we are about to give a client some experience.
 * You can modify the experience or block it all together.
 * The core calls this with the above defined reasons. This is useful, if you want to add more game specific experience handling which override the default ones.
 *
 * @param client         The client, which is about to get some experience.
 * @param reason         The reason why this client gets experience.
 * @param iExperience    By reference. The experience to give to the player. You can change it to whatever you like.
 * @param other          The other entity which was involved in adding this experience. e.g. the victim which was hurt. -1 if no other particular entity was involved.
 * @return >= Plugin_Handled to block it, Plugin_Continue to pass, Plugin_Changed if you modified iExperience.
 */
forward Action:SMRPG_OnAddExperience(client, const String:reason[], &iExperience, other);

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