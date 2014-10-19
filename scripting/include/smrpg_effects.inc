#if defined _smrpg_effects_included
  #endinput
#endif
#define _smrpg_effects_included

/**
 * Freezes a client in place. Can play optional effects on him.
 *
 * @param client             The client index.
 * @param fTime              The time to freeze the player for.
 * @param fDamageLimit       Don't allow more damage than this if victim is frozen. Set to 0, if you don't want to limit the damage.
 * @param sUpgradeName       Upgrade shortname which issues the freeze. Used to see if clients want to see the visual/sound effects.
 * @param bPlaySound         Play a random icy sound?
 * @param bFadeColor         Fade the player's model from blue to normal?
 * @param bResetVelocity     Reset the velocity of the client as well? You can just freeze him temporarily and keep the velocity. Useful for surfing.
 * @return                   True if client was frozen, false otherwise.
 * @error                    Invalid client index.
 */
native bool:SMRPG_FreezeClient(client, Float:fTime, Float:fDamageLimit, const String:sUpgradeName[], bool:bPlaySound=true, bool:bFadeColor=true, bool:bResetVelocity=false);

/**
 * Unfreeze a client, if he was frozen by SMRPG_FreezeClient previously.
 *
 * @param client             The client index.
 * @noreturn
 * @error                    Invalid client index or client not frozen.
 */
native SMRPG_UnfreezeClient(client);

/**
 * Checks whether a client is frozen by this plugin.
 *
 * @param client             The client index.
 * @return                   True if frozen, false otherwise.
 * @error                    Invalid client index.
 */
native bool:SMRPG_IsClientFrozen(client);

/**
 * Ignites a client. Can play optional effects on him.
 *
 * @param client             The client index.
 * @param fTime              The time to let the player burn.
 * @param sUpgradeName       Upgrade shortname which issues the ignition. Used to see if clients want to see the visual/sound effects.
 * @param bFadeColor         Fade the player's model from red to normal?
 * @return                   True if client was ignited, false otherwise.
 * @error                    Invalid client index.
 */
native bool:SMRPG_IgniteClient(client, Float:fTime, const String:sUpgradeName[], bool:bFadeColor=true);

/**
 * Extinguish a client, if he was ignited by SMRPG_IgniteClient previously.
 *
 * @param client             The client index.
 * @noreturn
 * @error                    Invalid client index or client not burning.
 */
native SMRPG_ExtinguishClient(client);

/**
 * Checks whether a client is ignited by this plugin.
 *
 * @param client             The client index.
 * @return                   True if burning, false otherwise.
 * @error                    Invalid client index.
 */
native bool:SMRPG_IsClientBurning(client);

/**
 * Set the default color of the player to reset to after some effects are run.
 * Color is not touched, if set to -1.
 *
 * @param client             The client index.
 * @param r                  The red channel (0-255) or -1 to leave unchanged.
 * @param g                  The green channel (0-255) or -1 to leave unchanged.
 * @param b                  The blue channel (0-255) or -1 to leave unchanged.
 * @param a                  The alpha channel (0-255) or -1 to leave unchanged.
 * @noreturn
 * @error                    Invalid client index.
 */
native SMRPG_SetClientDefaultColor(client, r=-1, g=-1, b=-1, a=-1);

/**
 * Set the render color of the player.
 * Color is not touched, if set to -1.
 *
 * @param client             The client index.
 * @param r                  The red channel (0-255) or -1 to leave unchanged.
 * @param g                  The green channel (0-255) or -1 to leave unchanged.
 * @param b                  The blue channel (0-255) or -1 to leave unchanged.
 * @param a                  The alpha channel (0-255) or -1 to leave unchanged.
 * @noreturn
 * @error                    Invalid client index.
 */
native SMRPG_SetClientRenderColor(client, r=-1, g=-1, b=-1, a=-1);

/**
 * Start fading the render color from the current value to this target color.
 * Uses the stepsize set with SMRPG_SetClientRenderColorFadeStepsize.
 * Color is not touched, if set to -1.
 *
 * @param client             The client index.
 * @param r                  The red channel (0-255) or -1 to leave unchanged.
 * @param g                  The green channel (0-255) or -1 to leave unchanged.
 * @param b                  The blue channel (0-255) or -1 to leave unchanged.
 * @param a                  The alpha channel (0-255) or -1 to leave unchanged.
 * @noreturn
 * @error                    Invalid client index.
 */
native SMRPG_SetClientRenderColorFadeTarget(client, r=-1, g=-1, b=-1, a=-1);

/**
 * Set the fade stepsize for each channel. Every frame the channel moves by that stepsize towards the fade target.
 * Stepsize is not touched, if set to -1.
 *
 * @param client             The client index.
 * @param r                  The step size for the red channel or -1 to leave unchanged.
 * @param g                  The step size for the green channel or -1 to leave unchanged.
 * @param b                  The step size for the blue channel or -1 to leave unchanged.
 * @param a                  The step size for the alpha channel or -1 to leave unchanged.
 * @noreturn
 * @error                    Invalid client index.
 */
native SMRPG_SetClientRenderColorFadeStepsize(client, Float:r=-1.0, Float:g=-1.0, Float:b=-1.0, Float:a=-1.0);

/**
 * Reset the render color of the client back to the set default color.
 * @see SMRPG_SetClientDefaultColor
 *
 * Only sets the color back, if it was last set by the same plugin.
 * This is to prevent prematurely resetting the effect of some other plugin, if that had our effect overwritten.
 *
 * @param client             The client index.
 * @param bResetRed          Should we reset the red channel back to default?
 * @param bResetGreen        Should we reset the green channel back to default?
 * @param bResetBlue         Should we reset the blue channel back to default?
 * @param bResetAlpha        Should we reset the alpha channel back to default?
 * @param bForceReset        Ignore which plugin last changed the channels and force a reset?
 * @noreturn
 * @error                    Invalid client index.
 */
native SMRPG_ResetClientToDefaultColor(client, bool:bResetRed, bool:bResetGreen, bool:bResetBlue, bool:bResetAlpha, bool:bForceReset=false);

/**
 * Called when a client is about to be frozen for fTime seconds.
 *
 * @param client     The client index.
 * @param &fTime     The time to freeze for. You can change it and return Plugin_Changed.
 * @return           >= Plugin_Handled to block, Plugin_Continue to allow freezing.
 */
forward Action:SMRPG_OnClientFreeze(client, &Float:fTime);

/**
 * Called when a client was frozen for fTime seconds.
 *
 * @param client     The client index.
 * @param fTime      The time to freeze for.
 * @noreturn
 */
forward SMRPG_OnClientFrozen(client, Float:fTime);

/**
 * Called when a client was unfrozen.
 *
 * @param client     The client index.
 * @noreturn
 */
forward SMRPG_OnClientUnfrozen(client);

/**
 * Called when a client is about to be ignited for fTime seconds.
 *
 * @param client     The client index.
 * @param &fTime     The time to burn for. You can change it and return Plugin_Changed.
 * @return           >= Plugin_Handled to block, Plugin_Continue to allow burning.
 */
forward Action:SMRPG_OnClientIgnite(client, &Float:fTime);

/**
 * Called when a client was ignited for fTime seconds.
 *
 * @param client     The client index.
 * @param fTime      The time to freeze for.
 * @noreturn
 */
forward SMRPG_OnClientIgnited(client, Float:fTime);

/**
 * Called when a client was extinguished.
 *
 * @param client     The client index.
 * @noreturn
 */
forward SMRPG_OnClientExtinguished(client);

public SharedPlugin:__pl_smrpg_effects = 
{
	name = "smrpg_effects",
	file = "smrpg_effects.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_smrpg_effects_SetNTVOptional()
{
	MarkNativeAsOptional("SMRPG_FreezeClient");
	MarkNativeAsOptional("SMRPG_UnfreezeClient");
	MarkNativeAsOptional("SMRPG_IsClientFrozen");
	
	MarkNativeAsOptional("SMRPG_IgniteClient");
	MarkNativeAsOptional("SMRPG_ExtinguishClient");
	MarkNativeAsOptional("SMRPG_IsClientBurning");
	
	MarkNativeAsOptional("SMRPG_SetClientDefaultColor");
	MarkNativeAsOptional("SMRPG_SetClientRenderColor");
	MarkNativeAsOptional("SMRPG_SetClientRenderColorFadeTarget");
	MarkNativeAsOptional("SMRPG_SetClientRenderColorFadeStepsize");
	MarkNativeAsOptional("SMRPG_ResetClientToDefaultColor");
}
#endif