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
 * The reason for the call of the SMRPG_UpgradeQueryCB callback.
 * This helps to determine, if the upgrade's level increased or decreased.
 */
enum UpgradeQueryType
{
	UpgradeQueryType_Buy, // The upgrade was bought by the client. I.e. the upgrade's level just increased.
	UpgradeQueryType_Sell // The upgrade was sold by the client. I.e. the upgrade's level just decreased.
};

/**
 * This callback is called by the core plugin, when the client buys or sells this upgrade.
 * It's also called, when an admin changes the upgrade level of the client, or the client disconnects.
 * The client does not have to be ingame!
 *
 * @param client         The client, whos upgrade level changed.
 * @param type           The type of the change. (buy or sell)
 * @noreturn
 */
functag public SMRPG_UpgradeQueryCB(client, UpgradeQueryType:type);

/**
 * Called to check, if an upgrade's effect is currently active on a client.
 * This gets called by the SMRPG_IsUpgradeActiveOnClient native, to ask the plugin, which registered the upgrade, if it's currently doing something.
 *
 * This is mostly interesting for active upgrades. Passive upgrades can just check, if the client's upgrade level is > 0.
 *
 * @param client         The client, which should be checked, if the upgrade is currently active on him.
 * @return True, if the upgrade's effect is currently active on the client, false otherwise.
 */
functag public bool:SMRPG_ActiveQueryCB(client);

/**
 * Registers a new upgrade to the rpg core.
 * This will show up in the rpgmenu.
 * The shortname is like an unique identifier for this upgrade. It is also used to create a database column, so no whitespace allowed!
 * Other plugins might use the shortname to check for information of the upgrade.
 *
 * This native registers 4 default convars for the plugin and saves them in a seperate config file for the upgrade in cfg/sourcemod/smrpg/smrpg_upgrade_<shortname>.cfg
 *  - smrpg_<shortname>_enable   ~ Enable or disable the upgrade. The upgrade needs to check this value and should obey it..
 *  - smrpg_<shortname>_maxlevel ~ The maximal level a player can buy the upgrade.
 *  - smrpg_<shortname>_cost     ~ The start cost of this item when purchasing level 1
 *  - smrpg_<shortname>_icost    ~ The amount to increase the cost for each level: cost for level x = startcost + icost * (level-1)
 *
 * You can add more convars to that file using the SMRPG_CreateUpgradeConVar native.
 *
 * @param name              The full name of the upgrade. This is displayed in the rpgmenu. Set a translation callback to dynamically change it.
 * @param shortname         A short abbreviative name for this upgrade. It's the primary unique identifier used in all other upgrade-specific natives. Must not contain whitespace.
 * @param description       A verbose description of the upgrade. Shown in the rpghelp menu.
 * @param maxlevelbarrier   Hardcoded limit you don't want the maxlevel to exceed. You can't set the maxlevel higher than this. This value can't be changed during runtime.
 * @param bDefaultEnable    Do you want this upgrade to be enabled by default? Default value of the _enable convar.
 * @param iDefaultMaxLevel  The default maxlevel of this plugin. Players won't be able to buy more levels of this upgrade than this. Default value of the _maxlevel convar.
 * @param iDefaultStartCost The default start costs to buy level 1 of this upgrade. Default of the _cost convar.
 * @param iDefaultCostInc   The default incremential cost to buy higher levels of this upgrade. See _icost comment above. Default of the _icost convar.
 * @param querycb           The callback which is called when a client buys / sells this upgrade. Can be used to apply some effects immediately on purchase.
 * @param activecb          The callback which is called to check whether the upgrade currently has some active effect on the client.
 * @noreturn
 * @error Whitespace in shortname, upgrade shortname already exists.
 */
native SMRPG_RegisterUpgradeType(const String:name[], const String:shortname[], const String:description[], maxlevelbarrier, bool:bDefaultEnable, iDefaultMaxLevel, iDefaultStartCost, iDefaultCostInc, SMRPG_UpgradeQueryCB:querycb, SMRPG_ActiveQueryCB:activecb);

/**
 * Unregisters a given upgrade from the core.
 * It will be hidden from the rpgmenu and all queries regarding this upgrade will fail.
 *
 * Call this in OnPluginEnd()!
 *
 * @param shortname      The shortname of the upgrade you want to unregister.
 * @noreturn
 * @error Unknown upgrade shortname.
 */
native SMRPG_UnregisterUpgradeType(const String:shortname[]);

/**
 * Create a convar for the upgrade.
 * The convar is added to the upgrade's specific autogenerated config file in cfg/sourcemod/smrpg/smrpg_upgrade_<shortname>.cfg next to the default convars.
 * This helps to keep all upgrade configuration in one centralized uniform place.
 *
 * @param shortname      The shortname of the upgrade you want to register this convar for.
 * @param name           Name of new convar.
 * @param defaultValue   String containing the default value of new convar.
 * @param description    Optional description of the convar.
 * @param flags          Optional bitstring of flags determining how the convar should be handled. See FCVAR_* constants for more details.
 * @param hasMin         Optional boolean that determines if the convar has a minimum value.
 * @param min            Minimum floating point value that the convar can have if hasMin is true.
 * @param hasMax         Optional boolean that determines if the convar has a maximum value.
 * @param max            Maximum floating point value that the convar can have if hasMax is true.
 * @return A handle to the newly created convar. If the convar already exists, a handle to it will still be returned.
 * @error Convar name is blank or is the same as an existing console command.
 */
native Handle:SMRPG_CreateUpgradeConVar(const String:shortname[], const String:name[], const String:defaultValue[], const String:description[]="", flags=0, bool:hasMin=false, Float:min=0.0, bool:hasMax=false, Float:max=0.0);

/**
 * Types of translatable information of the upgrade.
 */
enum TranslationType
{
  TranslationType_Name, // Full name of the upgrade
  TranslationType_Description // Verbose description of the upgrade
};

/**
 * Called, when the core plugin wants to print information about this upgrade. (e.g. in the rpgmenu upgrades list)
 * The translation defaults to the strings that were passed when registering the upgrade.
 *
 * @param client         The client, to which language you should translate to.
 * @param type           The requested TranslationType (name or description).
 * @param translation    The translation buffer.
 * @param maxlen         The maximal length of the buffer.
 * @noreturn
 */
functag public SMRPG_TranslateUpgradeCB(client, TranslationType:type, String:translation[], maxlen);

/**
 * Set a translation callback for the named upgrade.
 * This is used to translate the name and description of the upgrade into different languages when needed.
 * This has to be called from the same plugin, which registered the upgrade, therefore AFTER SMRPG_RegisterUpgradeType!
 *
 * @param shortname      The shortname of the upgrade you want to add the translation callback to.
 * @param cb             The callback function to register.
 * @noreturn
 * @error Unknown upgrade shortname.
 */
native SMRPG_SetUpgradeTranslationCallback(const String:shortname[], SMRPG_TranslateUpgradeCB:cb);

/**
 * Called, when another plugin wants to stop the effect of this upgrade via SMRPG_ResetUpgradeEffectOnClient.
 * You should stop all changes on the client, that your upgrade currently does.
 *
 * Passive upgrades (like regeneration) don't need to register this callback.
 *
 * @param client         Stop all effects on this client.
 * @noreturn
 */
functag public SMRPG_ResetEffectCB(client);

/**
 * Set a effect reset callback for the named upgrade.
 * This is used to give other plugins the possiblity to stop interfering effects using SMRPG_ResetUpgradeEffectOnClient.
 * This has to be called from the same plugin, which registered the upgrade, therefore AFTER SMRPG_RegisterUpgradeType!
 *
 * Register this callback, if you do some active effects (like freezing)
 *
 * @param shortname      The shortname of the upgrade you want to add the translation callback to.
 * @param cb             The callback function to register.
 * @noreturn
 * @error Unknown upgrade shortname.
 */
native SMRPG_SetUpgradeResetCallback(const String:shortname[], SMRPG_ResetEffectCB:cb);

/**
 * Signal other plugins that this upgrade is about to do its effects on a client.
 * This calls the SMRPG_OnUpgradeEffect forward, which allows other plugins to block the effect of this upgrade.
 *
 * The should be checked before applying any effects on a client, to see, if some other plugin doesn't want the effects to happen.
 * That way you can e.g. avoid interferences between upgrades that change the same prop.
 *
 * @param client         The client which is about to get some effect applied.
 * @param shortname      The shortname of the upgrade that is about to apply its effect on the client.
 * @return True, if it's ok to run the effect, false if some other plugin doesn't want you to apply the effects.
 * @error Invalid client index, unknown upgrade shortname.
 */
native bool:SMRPG_RunUpgradeEffect(client, const String:shortname[]);

/**
 * Check if an upgrade with that shortname exists.
 *
 * @param shortname      The shortname of the upgrade.
 * @return True, if there is an upgrade with that shortname registered, false otherwise.
 */
native bool:SMRPG_UpgradeExists(const String:shortname[]);

/**
 * The maximal length of the full name of an upgrade
 */
#define MAX_UPGRADE_NAME_LENGTH 64
/**
 * The maximal length of the short name of an upgrade
 */
#define MAX_UPGRADE_SHORTNAME_LENGTH 32
/**
 * The maximal length of the description of an upgrade
 */
#define MAX_UPGRADE_DESCRIPTION_LENGTH 128

/**
 * Detailed upgrade info of some upgrade.
 */
enum UpgradeInfo
{
	bool:UI_enabled, // upgrade enabled?
	UI_maxLevelBarrier, // upper limit of maxlevel setting. Can't set maxlevel higher than that.
	UI_maxLevel, // Maximal level a player can get for this upgrade
	UI_startCost, // The amount of credits the first level costs
	UI_incCost, // The amount of credits each level costs more
	String:UI_name[MAX_UPGRADE_NAME_LENGTH],
	String:UI_shortName[MAX_UPGRADE_SHORTNAME_LENGTH], // shortname used as unique identifier in all commands and database
	String:UI_description[MAX_UPGRADE_DESCRIPTION_LENGTH]
};

/**
 * Get the UpgradeInfo of an upgrade.
 *
 * @param shortname      The shortname of the upgrade you want to know more about.
 * @param upgrade        An buffer array to hold all the upgrade information.
 * @noreturn
 * @error Unkown upgrade shortname.
 */
native SMRPG_GetUpgradeInfo(const String:shortname[], upgrade[UpgradeInfo]);

/**
 * Ask the plugin controlling an upgrade to remove all active effects from a client.
 * This only works, if the plugin, which registered the shortname named upgrade, has a reset callback set correctly.
 * If the other plugin did not set such a reset callback with SMRPG_SetUpgradeResetCallback, this won't have any effect :(
 *
 * @param client         The client to stop all effects on.
 * @param shortname      The upgrade shortname, which effects should be stopped on the client.
 * @noreturn
 * @error Invalid client index, unknown upgrade shortname.
 */
native SMRPG_ResetUpgradeEffectOnClient(client, const String:shortname[]);

/**
 * Checks if an upgrade's effect is currently active on a client.
 * This calls the SMRPG_ActiveQueryCB callback of the upgrade.
 *
 * @param client         The client to check for the effect of an upgrade.
 * @param shortname      The upgrade shortname, which should be checked, if it has some effects active on a client.
 * @return True, if the plugin handling the upgrade said, there is some effect active, false otherwise.
 * @error Invalid client index, unknown upgrade shortname.
 */
native bool:SMRPG_IsUpgradeActiveOnClient(client, const String:shortname[]);



/**
 * Get the level of an upgrade of a client.
 *
 * @param client         The client which upgrade level you want to know.
 * @param shortname      The upgrade shortname
 * @return The level of the upgrade the client has purchased. 0 if he didn't buy it yet.
 * @error Invalid client index, unknown upgrade shortname.
 */
native SMRPG_GetClientUpgradeLevel(client, const String:shortname[]);

/**
 * Lets a client buy an upgrade and increases his upgrade level by 1.
 * Silently caps the level at the maxlevel.
 * This calls the SMRPG_OnBuyUpgrade forward to let other plugins know about the change. They can override that forward to block the buying.
 *
 * @param client         The client, which should buy a level of this upgrade.
 * @param shortname      The upgrade shortname which the client should buy.
 * @return True, if the client bought the upgrade, false if some other plugin stopped the buying in SMRPG_OnBuyUpgrade.
 * @error Invalid client index, unknown upgrade shortname.
 */
native bool:SMRPG_ClientBuyUpgrade(client, const String:shortname[]);

/**
 * Lets a client sell an upgrade and decreases his upgrade level by 1.
 * Silently caps the level at 0.
 * This calls the SMRPG_OnSellUpgrade forward to let other plugins know about the change. They can override that forward to block the selling.
 *
 * @param client         The client, which should sell a level of this upgrade.
 * @param shortname      The upgrade shortname which the client should sell.
 * @return True, if the client sold the upgrade, false if some other plugin stopped the selling in SMRPG_OnSellUpgrade.
 * @error Invalid client index, unknown upgrade shortname.
 */
native bool:SMRPG_ClientSellUpgrade(client, const String:shortname[]);

/**
 * Called when a client's upgrade levels were loaded from the database.
 * 
 * @param client         The client who's levels were just loaded.
 * @noreturn
 */
forward SMRPG_OnClientLoaded(client);

/**
 * Called when the level of a client changes.
 * You can stop that from happening by returning Plugin_Handled.
 *
 * @param client         The client, who's level is going to be changed.
 * @param oldlevel       The old, current level of the client.
 * @param newlevel       The new level the client is going to be set to.
 * @return >= Plugin_Handled to block, Plugin_Continue to let it pass.
 */
forward Action:SMRPG_OnClientLevel(client, oldlevel, newlevel);

/**
 * Called when the experience of a client changes.
 * You can stop that from happening by returning Plugin_Handled.
 *
 * @param client         The client, who's experience is going to be changed.
 * @param oldexp         The old, current experience of the client.
 * @param newexp         The new experience the client is going to be set to.
 * @return >= Plugin_Handled to block, Plugin_Continue to let it pass.
 */
forward Action:SMRPG_OnClientExperience(client, oldexp, newexp);

/**
 * Called when the credits of a client changes.
 * You can stop that from happening by returning Plugin_Handled.
 *
 * @param client         The client, who's credits is going to be changed.
 * @param oldcredits     The old, current credits of the client.
 * @param newcredits     The new credits the client is going to be set to.
 * @return >= Plugin_Handled to block, Plugin_Continue to let it pass.
 */
forward Action:SMRPG_OnClientCredits(client, oldcredits, newcredits);

/**
 * Called when a client buys an upgrade or in general, when a client's upgrade level increases.
 * You can stop that from happening by returning Plugin_Handled.
 *
 * @param client         The client who is about to buy an upgrade.
 * @param shortname      The upgrade shortname of the upgrade being bought.
 * @param newlevel       The new level, the client's upgrade will be set to.
 * @return >= Plugin_Handled to block the client from buying that upgrade, Plugin_Continue to let it pass.
 */
forward Action:SMRPG_OnBuyUpgrade(client, const String:shortname[], newlevel);

/**
 * Called when a client sells an upgrade or in general, when a client's upgrade level decreases.
 * You can stop that from happening by returning Plugin_Handled.
 *
 * @param client         The client who is about to sell an upgrade.
 * @param shortname      The upgrade shortname of the upgrade being sold.
 * @param newlevel       The new level, the client's upgrade will be set to.
 * @return >= Plugin_Handled to block the client from selling that upgrade, Plugin_Continue to let it pass.
 */
forward Action:SMRPG_OnSellUpgrade(client, const String:shortname[], newlevel);

/**
 * Called when an upgrade is about to start his effect on a client.
 * The upgrades have to call SMRPG_RunUpgradeEffect for this to work.
 *
 * @param client         The client which is about to get some effect applied by the upgrade.
 * @param shortname      The shortname of the upgrade that is about to apply an effect.
 * @return >= Plugin_Handled to tell the upgrade to NOT run the effect, Plugin_Continue to let it pass.
 */
forward Action:SMRPG_OnUpgradeEffect(client, const String:shortname[]);

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
}
#endif