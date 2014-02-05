#if defined _smrpg_commandlist_included
  #endinput
#endif
#define _smrpg_commandlist_included

/** Category name of added topmenu category */
#define RPGMENU_COMMANDS "RPGCommandsMenu"

/**
 * Types of translatable information for rpg commands.
 */
enum CommandTranslationType {
	CommandTranslationType_ShortDescription, // Short description of the command displayed in the commandlist menu
	CommandTranslationType_Description, // Detailed description of the command displayed when the command is selected in the commandlist menu
	CommandTranslationType_Advert // Advertisement to show in chat periodically
};

/**
 * Called when the core plugin wants to print information about this command.
 *
 * @param client      The client in which language the information should be displayed.
 * @param command     The command we want information about.
 * @param type        The translation type (description or advert)
 * @param translation The translation buffer.
 * @param maxlen      The maximal length of the buffer.
 * @return            Return Plugin_Handled to stop the command from being listed in the menu or the advert printed, otherwise return Plugin_Continue.
 */
functag public Action:SMRPG_TranslateCommandCB(client, const String:command[], CommandTranslationType:type, String:translation[], maxlen);

/**
 * Register a rpg related command in the core.
 * The command will be listed in the command list in the rpgmenu and be advertised periodically.
 *
 * @param command   The command you want to register.
 * @param callback  The callback to call to get the description and advert text.
 * @noreturn
 * @error Command already registered by other plugin.
 */
native SMRPG_RegisterCommand(const String:command[], SMRPG_TranslateCommandCB:callback);

/**
 * Unregister the rpg related command from the core.
 * Call this in OnPluginEnd!
 * 
 * @param command   The command you previously registered and want to unregister now.
 * @noreturn
 */
native SMRPG_UnregisterCommand(const String:command[]);

public SharedPlugin:__pl_smrpg_commandlist = 
{
	name = "smrpg_commandlist",
	file = "smrpg_commandlist.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_smrpg_commandlist_SetNTVOptional()
{
	MarkNativeAsOptional("SMRPG_RegisterCommand");
	MarkNativeAsOptional("SMRPG_UnregisterCommand");
}
#endif