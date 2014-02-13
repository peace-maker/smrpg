#if defined _smrpg_settings_included
  #endinput
#endif
#define _smrpg_settings_included

#include <smrpg>

/**
 * Get the value of some setting from the settings table.
 *
 * @param sKey		The name of the setting.
 * @param sValue	The buffer to store the setting's value in.
 * @param maxlen	The maximum length of the buffer.
 * @return True if the setting existed and was retrieved, false otherwise.
 */
native bool:SMRPG_GetSetting(const String:sKey[], String:sValue[], maxlen);

/**
 * Set a setting variable in the smrpg "settings" table.
 *
 * @param sKey		The name of the setting.
 * @param sValue	The new value of the setting.
 * @noreturn
 */
native SMRPG_SetSetting(const String:sKey[], String:sValue[]);

/**
 * Called when the settings were loaded from the database.
 *
 * @noreturn
 */
forward SMRPG_OnSettingsLoaded();