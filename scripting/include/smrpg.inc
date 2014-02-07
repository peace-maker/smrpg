#if defined _smrpg_included
  #endinput
#endif
#define _smrpg_included

/**
 * Check if SM:RPG is enabled.
 *
 * @return True, if enabled, false otherwise.
 */
native bool:SMRPG_IsEnabled();

/**
 * Check if bots should not get any effects from the rpg plugin.
 *
 * @return True, if bots should be ignored, false otherwise.
 */
native bool:SMRPG_IgnoreBots();

#include <smrpg/smrpg_clients>
#include <smrpg/smrpg_upgrades>
#include <smrpg/smrpg_topmenu>

/**
 * Wrapper to emit sound to all clients that have the sound effects activated for this upgrade.
 *
 * @param shortname     Shortname of the upgrade.
 * @param sample        Sound file name relative to the "sounds" folder.
 * @param entity        Entity to emit from.
 * @param channel       Channel to emit with.
 * @param level         Sound level.
 * @param flags         Sound flags.
 * @param volume        Sound volume.
 * @param pitch         Sound pitch.
 * @param speakerentity Unknown.
 * @param origin        Sound origin.
 * @param dir           Sound direction.
 * @param updatePos     Unknown (updates positions?)
 * @param soundtime     Alternate time to play sound for.
 * @noreturn
 * @error Invalid client index.
 */
stock SMRPG_EmitSoundToAllEnabled(const String:shortname[], 
				 const String:sample[],
				 entity = SOUND_FROM_PLAYER,
				 channel = SNDCHAN_AUTO,
				 level = SNDLEVEL_NORMAL,
				 flags = SND_NOFLAGS,
				 Float:volume = SNDVOL_NORMAL,
				 pitch = SNDPITCH_NORMAL,
				 speakerentity = -1,
				 const Float:origin[3] = NULL_VECTOR,
				 const Float:dir[3] = NULL_VECTOR,
				 bool:updatePos = true,
				 Float:soundtime = 0.0)
{
	new iClients[MaxClients], iNumClients;
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && SMRPG_ClientWantsCosmetics(i, shortname, SMRPG_FX_Sounds))
			iClients[iNumClients++] = i;
	}

	if(!iNumClients)
		return;

	EmitSound(iClients, iNumClients, sample, entity, channel, level, flags, volume, pitch, speakerentity, origin, dir, updatePos, soundtime);
}

/**
 * Broadcasts the current temp entity to all clients that have the visual effects activated for this upgrade.
 * @note See TE_Start().
 *
 * @param shortname Shortname of the upgrade.
 * @param delay     Delay in seconds to send the TE.
 * @noreturn
 */
stock SMRPG_TE_SendToAllEnabled(const String:shortname[], Float:delay=0.0)
{
	new iClients[MaxClients], iNumClients;
	for (new i=1; i<=MaxClients; i++)
	{
		if (IsClientInGame(i) && SMRPG_ClientWantsCosmetics(i, shortname, SMRPG_FX_Visuals))
		{
			iClients[iNumClients++] = i;
		}
	}
	return TE_Send(iClients, iNumClients, delay);
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
	MarkNativeAsOptional("SMRPG_CreateUpgradeConVar");
	MarkNativeAsOptional("SMRPG_UpgradeExists");
	MarkNativeAsOptional("SMRPG_ResetUpgradeEffectOnClient");
	MarkNativeAsOptional("SMRPG_GetUpgradeInfo");
	MarkNativeAsOptional("SMRPG_RunUpgradeEffect");
	MarkNativeAsOptional("SMRPG_GetClientUpgradeLevel");
	MarkNativeAsOptional("SMRPG_ClientBuyUpgrade");
	MarkNativeAsOptional("SMRPG_ClientSellUpgrade");
	MarkNativeAsOptional("SMRPG_IsUpgradeActiveOnClient");
	MarkNativeAsOptional("SMRPG_CheckUpgradeAccess");
	MarkNativeAsOptional("SMRPG_GetTopMenu");
}
#endif