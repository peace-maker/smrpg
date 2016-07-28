// Top level structure for an upgrade section.
enum UpgradeRestrictionConfig {
	Handle:URC_minimumRPGLevels, // Array of MinimumRPGLevel in "rpg_level" section. requirements on the minimum rpg level for different upgrade levels.
	Handle:URC_upgradesRequirements, // Array of UpgradeRequirementLevel's in "upgrade_requirements" section. requirements on the minimum levels of other upgrades
	Handle:URC_upgradesRestrictions, // Array of UpgradeRestrictionRule's in "upgrade_restrictions" section. conditions of maxmimal level of other upgrades/rpg level for this upgrade to appear.
}

enum MinimumRPGLevel {
	MRL_upgradeLevel, // upgrade level the rpg level is required for
	MRL_minRPGLevel   // rpg level the player needs to have to buy the upgrade level.
}

enum UpgradeRequirementLevel {
	URL_level, // upgrade level which requires the below list of minimum levels of other upgrades
	Handle:URL_requirements // array of UpgradeRequirement's
}

// Single key => value pair in "upgrades_requirements" section of an upgrade
enum UpgradeRequirement {
	UR_minLevel,
	String:UR_shortName[MAX_UPGRADE_SHORTNAME_LENGTH]
}

// Structure holding the "upgrade_restrictions" section
enum UpgradeRestrictionRule {
	URR_maxLevel, // maximal rpg level for this upgrade to be usable
	Handle:URR_upgradeRestrictions // Trie of "upgrade shortname" => "maximal level" pairs
}

new Handle:g_hUpgradeRestrictions;

// Config parser
enum RestrictionConfigSection {
	RSection_None = 0,
	RSection_Root,
	RSection_Upgrade,
	RSection_RPGLevels,
	RSection_RPGLevelRule,
	RSection_UpgradeAccess,
	RSection_UpgradeRequirements,
	RSection_UpgradeRequirementLevel,
	RSection_UpgradeRestrictions,
	RSection_UpgradeRestrictionRule
};

new RestrictionConfigSection:g_iConfigSection;
new g_iIgnoreLevel;
new String:g_sCurrentUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
new g_TempMinRPGLevel[MinimumRPGLevel];
new g_iRequirementLevel = -1; // For error messages
new Handle:g_hRequirementUpgradeList;
new g_TempRestrictionRule[UpgradeRestrictionRule];

InitUpgradeRestrictions()
{
	g_hUpgradeRestrictions = CreateTrie();
}

/**
 * Helpers to get info for upgrades.
 */
 
bool:UpgradeHasUnmetRequirements(client, upgrade[InternalUpgradeInfo])
{
	new iNewLevel = GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index])+1;
	
	// Player isn't on the right level yet.
	if (GetClientLevel(client) < GetMinimumRPGLevelForUpgrade(upgrade, iNewLevel))
		return true;
	
	// Check for other required upgrades for this upgrade
	new Handle:hRequiredUpgrades = GetRequiredUpgradesForClient(client, upgrade, iNewLevel);
	// No other upgrades required or all requirements met.
	if (!hRequiredUpgrades)
		return false;
	
	CloseHandle(hRequiredUpgrades);
	return true;
}
 
// returns 0 if there is no minimum configured
GetMinimumRPGLevelForUpgrade(upgrade[InternalUpgradeInfo], iUpgradeLevel)
{
	new iRestriction[UpgradeRestrictionConfig];
	if (!GetTrieArray(g_hUpgradeRestrictions, upgrade[UPGR_shortName], iRestriction[0], _:UpgradeRestrictionConfig))
		return 0;
	
	if (!iRestriction[URC_minimumRPGLevels])
		return 0;
	
	// Find highest setting below or equal to iUpgradeLevel.
	new iSize = GetArraySize(iRestriction[URC_minimumRPGLevels]);
	new iMinRPGLevel[MinimumRPGLevel], iRequiredRPGLevel;
	for (new i=0; i<iSize; i++)
	{
		GetArrayArray(iRestriction[URC_minimumRPGLevels], i, iMinRPGLevel[0], _:MinimumRPGLevel);
		
		// The array is sorted ascending by upgrade level. We went too far.
		if (iMinRPGLevel[MRL_upgradeLevel] > iUpgradeLevel)
			break;
		
		iRequiredRPGLevel = iMinRPGLevel[MRL_minRPGLevel];
	}
	
	return iRequiredRPGLevel;
}

Handle:GetRequiredUpgradesForClient(client, upgrade[InternalUpgradeInfo], iUpgradeLevel)
{
	new Handle:hRequiredUpgrades = GetRequiredUpgradesForLevel(upgrade, iUpgradeLevel);
	if (!hRequiredUpgrades)
		return INVALID_HANDLE;
	
	// See which upgrade requirements the client already meets.
	new Handle:hSnapshot = CreateTrieSnapshot(hRequiredUpgrades);
	new iSize = TrieSnapshotLength(hSnapshot);
	new String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH], iMinLevel;
	new otherUpgrade[InternalUpgradeInfo];
	for (new i=0; i<iSize; i++)
	{
		GetTrieSnapshotKey(hSnapshot, i, sShortname, sizeof(sShortname));
		// Only leave valid loaded and enabled upgrades in the list.
		if(!GetUpgradeByShortname(sShortname, otherUpgrade) || !IsValidUpgrade(otherUpgrade) || !otherUpgrade[UPGR_enabled])
		{
			RemoveFromTrie(hRequiredUpgrades, sShortname);
			continue;
		}
		
		// Player got the required level for that upgrade? Good.
		GetTrieValue(hRequiredUpgrades, sShortname, iMinLevel);
		if (GetClientPurchasedUpgradeLevel(client, otherUpgrade[UPGR_index]) >= iMinLevel)
			RemoveFromTrie(hRequiredUpgrades, sShortname);
	}
	
	CloseHandle(hSnapshot);
	
	// If the player meets all the requirements for the upgrade, don't pass an empty tree around.
	if (GetTrieSize(hRequiredUpgrades) == 0)
	{
		CloseHandle(hRequiredUpgrades);
		return INVALID_HANDLE;
	}
	
	return hRequiredUpgrades;
}

// Return a hashmap of "shortname" => "minlevel" required upgrades for the given level.
Handle:GetRequiredUpgradesForLevel(upgrade[InternalUpgradeInfo], iLevel)
{
	new iRestriction[UpgradeRestrictionConfig];
	if (!GetTrieArray(g_hUpgradeRestrictions, upgrade[UPGR_shortName], iRestriction[0], _:UpgradeRestrictionConfig))
		return INVALID_HANDLE;
		
	if (!iRestriction[URC_upgradesRequirements])
		return INVALID_HANDLE;
	
	// Use a trie to merge multiple requirements for the same upgrade for the same level.
	new Handle:hRequiredUpgrades = CreateTrie();
	
	// Collect all the requirements up until iLevel
	new iSize = GetArraySize(iRestriction[URC_upgradesRequirements]);
	new iRequirementLevel[UpgradeRequirementLevel];
	new iRequirement[UpgradeRequirement], iNumRequirements;
	for (new i=0; i<iSize; i++)
	{
		GetArrayArray(iRestriction[URC_upgradesRequirements], i, iRequirementLevel[0], _:UpgradeRequirementLevel);
		if (iRequirementLevel[URL_level] > iLevel)
			break; // The array is sorted. Don't need to look at the next ones.
		
		iNumRequirements = GetArraySize(iRequirementLevel[URL_requirements]);
		for (new j=0; j<iNumRequirements; j++)
		{
			GetArrayArray(iRequirementLevel[URL_requirements], j, iRequirement[0], _:UpgradeRequirement);
			SetTrieValue(hRequiredUpgrades, iRequirement[UR_shortName], iRequirement[UR_minLevel]);
		}
	}
	
	return hRequiredUpgrades;
}

// Does one of the rules in the "upgrade_restrictions" section apply to this client?
// RPG level too high and/or other upgrade levels too high?
bool:IsUpgradeRestricted(client, upgrade[InternalUpgradeInfo])
{
	new iRestriction[UpgradeRestrictionConfig];
	if (!GetTrieArray(g_hUpgradeRestrictions, upgrade[UPGR_shortName], iRestriction[0], _:UpgradeRestrictionConfig))
		return false;
		
	if (!iRestriction[URC_upgradesRestrictions])
		return false;

	new iRPGLevel = GetClientLevel(client);
	
	new iSize = GetArraySize(iRestriction[URC_upgradesRestrictions]);
	new iRestrictionRule[UpgradeRestrictionRule];
	new Handle:hSnapshot, iSnapshotLength, String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
	new otherUpgrade[InternalUpgradeInfo], iMaximalLevel;
	new bool:bRuleApplies;
	for (new i=0; i<iSize; i++)
	{
		GetArrayArray(iRestriction[URC_upgradesRestrictions], i, iRestrictionRule[0], _:UpgradeRestrictionRule);
		bRuleApplies = false;
		
		// Player is still below the maximal level?
		// This rule does not apply. Check the next one.
		if (iRPGLevel < iRestrictionRule[URR_maxLevel])
			continue;
		
		// Maximal rpg level is set and reached here. Check for the other conditions in the rule section now.
		if (iRestrictionRule[URR_maxLevel] != -1)
			bRuleApplies = true;
		
		// No upgrade restrictions?
		if (iRestrictionRule[URR_upgradeRestrictions] == INVALID_HANDLE)
		{
			// Player's rpg level is too high.
			break;
		}
		
		// Check the other upgrade restrictions.
		hSnapshot = CreateTrieSnapshot(iRestrictionRule[URR_upgradeRestrictions]);
		iSnapshotLength = TrieSnapshotLength(hSnapshot);
		for (new j=0; j<iSnapshotLength; j++)
		{
			GetTrieSnapshotKey(hSnapshot, j, sShortname, sizeof(sShortname));
			// See if that upgrade even exists
			if (!GetUpgradeByShortname(sShortname, otherUpgrade) || !IsValidUpgrade(otherUpgrade) || !otherUpgrade[UPGR_enabled])
				continue;
			
			// Player reached the max level of the other upgrade?
			GetTrieValue(iRestrictionRule[URR_upgradeRestrictions], sShortname, iMaximalLevel);
			if (GetClientPurchasedUpgradeLevel(client, otherUpgrade[UPGR_index]) >= iMaximalLevel)
				continue;
			
			// Player is still below the max level of the other upgrade. This rule doesn't apply.
			bRuleApplies = false;
			break;
		}
		CloseHandle(hSnapshot);
		
		// No need to check the other rule sections. It's enough if one applies.
		if (bRuleApplies)
			break;
	}
	
	return bRuleApplies;
}

// TODO Add function to check if the change of an upgrade's level let to a restriction of another upgrade
// And disable/refund the other upgrade's cost?


/**
 * SMC Parser for upgrade_restrictions.cfg config.
 */
bool:ResetRestrictionConfig()
{
	// Delete old config
	new Handle:hSnapshot = CreateTrieSnapshot(g_hUpgradeRestrictions);
	new iTrieSize = TrieSnapshotLength(hSnapshot), iSize;
	new String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
	new iRestriction[UpgradeRestrictionConfig], iRequirementLevel[UpgradeRequirementLevel];
	new iRestrictionRule[UpgradeRestrictionRule];
	for (new i=0; i<iTrieSize; i++)
	{
		GetTrieSnapshotKey(hSnapshot, i, sShortname, sizeof(sShortname));
		GetTrieArray(g_hUpgradeRestrictions, sShortname, iRestriction[0], _:UpgradeRestrictionConfig);
		
		// Close MinimumRPGLevel array if created
		if (iRestriction[URC_minimumRPGLevels] != INVALID_HANDLE)
		{
			CloseHandle(iRestriction[URC_minimumRPGLevels]);
		}
		
		// Close all upgrade requirement arrays
		if (iRestriction[URC_upgradesRequirements] != INVALID_HANDLE)
		{
			iSize = GetArraySize(iRestriction[URC_upgradesRequirements]);
			for (new j=0; j<iSize; j++)
			{
				GetArrayArray(iRestriction[URC_upgradesRequirements], j, iRequirementLevel[0], _:UpgradeRequirementLevel);
				CloseHandle(iRequirementLevel[URL_requirements]);
			}
			CloseHandle(iRestriction[URC_upgradesRequirements]);
		}
		
		// Close all upgrade restriction arrays
		if (iRestriction[URC_upgradesRestrictions] != INVALID_HANDLE)
		{
			iSize = GetArraySize(iRestriction[URC_upgradesRestrictions]);
			for (new j=0; j<iSize; j++)
			{
				GetArrayArray(iRestriction[URC_upgradesRestrictions], j, iRestrictionRule[0], _:UpgradeRestrictionRule);
				CloseHandle(iRestrictionRule[URR_upgradeRestrictions]);
			}
			CloseHandle(iRestriction[URC_upgradesRestrictions]);
		}
	}
	CloseHandle(hSnapshot);
	ClearTrie(g_hUpgradeRestrictions);
	
	// Reset reader state
	g_iConfigSection = RSection_None;
	g_iIgnoreLevel = 0;
	g_sCurrentUpgrade[0] = '\0';
	g_TempMinRPGLevel[MRL_minRPGLevel] = -1;
	g_TempMinRPGLevel[MRL_upgradeLevel] = -1;
	g_iRequirementLevel = -1;
	g_hRequirementUpgradeList = INVALID_HANDLE;
	g_TempRestrictionRule[URR_maxLevel] = -1;
	ClearHandle(g_TempRestrictionRule[URR_upgradeRestrictions]);
}

bool:ReadRestrictionConfig()
{
	// Forget old config
	ResetRestrictionConfig();
	
	new Handle:hSMC = SMC_CreateParser();
	SMC_SetReaders(hSMC, URConfig_NewSection, URConfig_KeyValue, URConfig_EndSection);
	
	new String:sConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/smrpg/upgrade_restrictions.cfg");
	if (!FileExists(sConfigFile))
		return false;
	
	new iLine, iCol;
	new SMCError:iErr = SMC_ParseFile(hSMC, sConfigFile, iLine, iCol);
	if (iErr != SMCError_Okay)
	{
		new String:sError[256];
		if (!SMC_GetErrorString(iErr, sError, sizeof(sError)))
			sError = "Fatal parse error";
		
		LogError("Error reading upgrade_restrictions.cfg: %s (line %d, col %d)", sError, iLine, iCol);
		ResetRestrictionConfig(); // Don't let some bad state mess us up later.
	}
	
	// TODO: Enforce new upgrade restriction rules on all connected players.
	
	return iErr == SMCError_Okay;
}

public SMCResult:URConfig_NewSection(Handle:smc, const String:name[], bool:opt_quotes)
{
	if (g_iIgnoreLevel > 0)
	{
		g_iIgnoreLevel++;
		return SMCParse_Continue;
	}
	if (g_iConfigSection == RSection_None)
	{
		g_iConfigSection = RSection_Root;
	}
	else if (g_iConfigSection == RSection_Root)
	{
		g_iConfigSection = RSection_Upgrade;
		strcopy(g_sCurrentUpgrade, sizeof(g_sCurrentUpgrade), name);
		
		new iRestriction[UpgradeRestrictionConfig];
		// Make sure there are no structures open for this upgrade yet.
		if (GetTrieArray(g_hUpgradeRestrictions, name, iRestriction[0], _:UpgradeRestrictionConfig))
		{
			LogError("Multiple sections for upgrade \"%s\". Only one per upgrade is supported.", name);
			return SMCParse_HaltFail;
		}
		
		SetTrieArray(g_hUpgradeRestrictions, name, iRestriction[0], _:UpgradeRestrictionConfig);
	}
	else if (g_iConfigSection == RSection_Upgrade)
	{
		if (StrEqual(name, "access", false))
			g_iConfigSection = RSection_UpgradeAccess;
		else if (StrEqual(name, "rpg_level", false))
		{
			g_iConfigSection = RSection_RPGLevels;
			
			new iRestriction[UpgradeRestrictionConfig];
			GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
			
			// Allow multiple "rpg_level" sections for flexibility.
			// We'll try to catch interferences later.
			if (!iRestriction[URC_minimumRPGLevels])
			{
				// Use an adt_array to sort it ascending after parsing.
				iRestriction[URC_minimumRPGLevels] = CreateArray(_:MinimumRPGLevel);
				SetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
			}
		}
		else if (StrEqual(name, "upgrade_requirements", false))
		{
			g_iConfigSection = RSection_UpgradeRequirements;
			
			new iRestriction[UpgradeRestrictionConfig];
			GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
			
			// Allow multiple "upgrades_requirements" sections to help readability.
			// We'll try to catch interferences later
			if (!iRestriction[URC_upgradesRequirements])
			{
				// Use an adt_array to sort it ascending after parsing.
				iRestriction[URC_upgradesRequirements] = CreateArray(_:UpgradeRequirementLevel);
				SetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
			}
		}
		else if (StrEqual(name, "upgrade_restrictions", false))
		{
			g_iConfigSection = RSection_UpgradeRestrictions;
			
			new iRestriction[UpgradeRestrictionConfig];
			GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
			
			// Allow multiple "upgrade_restrictions" sections to help readability.
			if (!iRestriction[URC_upgradesRestrictions])
			{
				iRestriction[URC_upgradesRestrictions] = CreateArray(_:UpgradeRestrictionRule);
				SetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionRule);
			}
		}
		else
			g_iIgnoreLevel++;
	}
	else if (g_iConfigSection == RSection_RPGLevels)
	{
		g_iConfigSection = RSection_RPGLevelRule;
	}
	else if (g_iConfigSection == RSection_UpgradeRequirements)
	{
		g_iConfigSection = RSection_UpgradeRequirementLevel;
		
		new iLevel;
		if (StringToIntEx(name, iLevel) == 0)
		{
			LogError("Upgrade \"%s\"'s dependency level section name \"%s\" is not an integer.", g_sCurrentUpgrade, name);
			return SMCParse_HaltFail;
		}
		
		if (iLevel < 1)
		{
			LogError("Upgrade \"%s\"'s dependency for level %d is invalid. Has to be for at least level 1.", g_sCurrentUpgrade, iLevel);
			return SMCParse_HaltFail;
		}
		
		new iRestriction[UpgradeRestrictionConfig];
		GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
		
		new iRequirementLevel[UpgradeRequirementLevel];
		iRequirementLevel[URL_level] = iLevel;
		iRequirementLevel[URL_requirements] = CreateArray(_:UpgradeRequirement);
		PushArrayArray(iRestriction[URC_upgradesRequirements], iRequirementLevel[0], _:UpgradeRequirementLevel);
		
		// Remember for better error messages when parsing the other upgrade requirements
		g_iRequirementLevel = iLevel;
		
		// So we don't have to search for the correct list in the array.
		g_hRequirementUpgradeList = iRequirementLevel[URL_requirements];
	}
	else if (g_iConfigSection == RSection_UpgradeRestrictions)
	{
		g_iConfigSection = RSection_UpgradeRestrictionRule;
	}
	else
	{
		// Don't know what this is about, just skip over it.
		g_iIgnoreLevel++;
	}
	
	return SMCParse_Continue;
}

public SMCResult:URConfig_KeyValue(Handle:smc, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	// Skip all this, if we don't know what to do.
	if (g_iIgnoreLevel > 0)
		return SMCParse_Continue;
	
	if (g_iConfigSection == RSection_RPGLevelRule)
	{
		// The upgrade level of the current upgrade to restrict to a minimal rpg level.
		if (StrEqual(key, "upgrade_level", false))
		{
			// We've been here before :/
			if (g_TempMinRPGLevel[MRL_upgradeLevel] != -1)
			{
				LogError("Multiple \"upgrade_level\" keys in same section for upgrade \"%s\".", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			// Some sanity checks
			new iLevel;
			if (StringToIntEx(value, iLevel) == 0)
			{
				LogError("Upgrade \"%s\"'s upgrade_level is not an integer.", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			if (iLevel < 1)
			{
				LogError("Upgrade \"%s\"'s upgrade_level has to be at least 1.", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			g_TempMinRPGLevel[MRL_upgradeLevel] = iLevel;
		}
		// The required minimum rpg level for an upgrade level.
		else if (StrEqual(key, "rpg_level", false))
		{
			// We've been here before :/
			if (g_TempMinRPGLevel[MRL_minRPGLevel] != -1)
			{
				LogError("Multiple \"rpg_level\" keys in same section for upgrade \"%s\".", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			// Some sanity checks
			new iLevel;
			if (StringToIntEx(value, iLevel) == 0)
			{
				LogError("Upgrade \"%s\"'s rpg_level is not an integer.", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			if (iLevel < 0)
			{
				LogError("Upgrade \"%s\"'s rpg_level can't be negative.", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			g_TempMinRPGLevel[MRL_minRPGLevel] = iLevel;
		}
	}
	else if (g_iConfigSection == RSection_UpgradeRequirementLevel)
	{
		new iLevel;
		if (StringToIntEx(value, iLevel) == 0)
		{
			LogError("Upgrade \"%s\"'s upgrade requirement minimum level for \"%s\" is not an integer.", g_sCurrentUpgrade, key);
			return SMCParse_HaltFail;
		}
		
		if (iLevel < 0)
		{
			LogError("Upgrade \"%s\"'s upgrade requirement minimum level for \"%s\" can't be negative.", g_sCurrentUpgrade, key);
			return SMCParse_HaltFail;
		}
		
		if (StrEqual(g_sCurrentUpgrade, key, false))
		{
			LogError("Upgrade \"%s\" can't require itself.", g_sCurrentUpgrade);
			return SMCParse_HaltFail;
		}
		
		new iRequirement[UpgradeRequirement];
		iRequirement[UR_minLevel] = iLevel;
		strcopy(iRequirement[UR_shortName], MAX_UPGRADE_SHORTNAME_LENGTH, key);
		PushArrayArray(g_hRequirementUpgradeList, iRequirement[0], _:UpgradeRequirement);
	}
	else if (g_iConfigSection == RSection_UpgradeRestrictionRule)
	{
		new iLevel;
		if (StringToIntEx(value, iLevel) == 0)
		{
			LogError("Upgrade \"%s\"'s maximal allowed level for \"%s\" is not an integer.", g_sCurrentUpgrade, key);
			return SMCParse_HaltFail;
		}
		
		if (iLevel < 0)
		{
			LogError("Upgrade \"%s\"'s maximal allowed level for \"%s\" can't be negative.", g_sCurrentUpgrade, key);
			return SMCParse_HaltFail;
		}
		
		if (StrEqual(g_sCurrentUpgrade, key, false))
		{
			LogError("Upgrade \"%s\" can't have a restriction on its own level.", g_sCurrentUpgrade);
			return SMCParse_HaltFail;
		}
		
		// max rpg level setting?
		if (StrEqual(key, "max_rpg_level", false))
		{
			if (g_TempRestrictionRule[URR_maxLevel] != -1)
			{
				LogError("Upgrade \"%s\" has multiple \"max_rpg_level\" keys in \"upgrade_restrictions\" section.", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			g_TempRestrictionRule[URR_maxLevel] = iLevel;
		}
		// This must be an upgrade
		else
		{
			if (g_TempRestrictionRule[URR_upgradeRestrictions] == INVALID_HANDLE)
				g_TempRestrictionRule[URR_upgradeRestrictions] = CreateTrie();
			
			new iTemp;
			if (GetTrieValue(g_TempRestrictionRule[URR_upgradeRestrictions], key, iTemp))
			{
				LogError("Upgrade \"%s\" has multiple \"%s\" keys in \"upgrade_restrictions\" section.", g_sCurrentUpgrade, key);
				return SMCParse_HaltFail;
			}
			
			SetTrieValue(g_TempRestrictionRule[URR_upgradeRestrictions], key, iLevel);
		}
	}
	return SMCParse_Continue;
}

public SMCResult:URConfig_EndSection(Handle:smc)
{
	if (g_iIgnoreLevel > 0)
	{
		g_iIgnoreLevel--;
		return SMCParse_Continue;
	}
	
	if (g_iConfigSection == RSection_Root)
	{
		g_iConfigSection = RSection_None;
	}
	else if (g_iConfigSection == RSection_Upgrade)
	{
		g_iConfigSection = RSection_Root;
		
		// Done with the upgrade.
		new iRestriction[UpgradeRestrictionConfig];
		GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
		
		if (iRestriction[URC_upgradesRequirements])
		{
			// Sort the upgrade requirements by ascending level.
			SortADTArrayCustom(iRestriction[URC_upgradesRequirements], Sort_UpgradeRequirements);
			
			// Check for duplicate level sections
			new iLastLevel = -1;
			new iRequirementLevel[UpgradeRequirementLevel];
			new iSize = GetArraySize(iRestriction[URC_upgradesRequirements]);
			for (new i=0; i<iSize; i++)
			{
				GetArrayArray(iRestriction[URC_upgradesRequirements], i, iRequirementLevel[0], _:UpgradeRequirementLevel);
				if (iLastLevel != -1 && iLastLevel == iRequirementLevel[URL_level])
				{
					LogError("There are multiple sections for level %d in the \"upgrade_requirements\" sections of upgrade \"%s\". Please merge them.", iLastLevel, g_sCurrentUpgrade);
					return SMCParse_HaltFail;
				}
				
				iLastLevel = iRequirementLevel[URL_level];
			}
			
			// TODO: Check for upgrade restrictions on other upgrades being lower on higher levels than on lower ones. 
			// "upgrades" { "2" { "health" "4" } "4" { "health" "2" } }
		}
		
		if (iRestriction[URC_minimumRPGLevels])
		{
			// Sort the rpg level requirements by ascending level.
			SortADTArrayCustom(iRestriction[URC_minimumRPGLevels], Sort_RPGLevelRequirements);
			
			// Check for duplicate level sections and assert the rpg level is linearly ascending.
			new iLastLevel = -1, iLastMinRPGLevel = -1;
			new iMinRPGLevel[MinimumRPGLevel];
			new iSize = GetArraySize(iRestriction[URC_minimumRPGLevels]);
			for (new i=0; i<iSize; i++)
			{
				GetArrayArray(iRestriction[URC_minimumRPGLevels], i, iMinRPGLevel[0], _:MinimumRPGLevel);
				
				// Can't have multiple sections for the same upgrade level.
				if (iLastLevel != -1 && iLastLevel == iMinRPGLevel[MRL_upgradeLevel])
				{
					LogError("There are multiple sections for upgrade level %d in the \"rpg_level\" sections of upgrade \"%s\". Please merge them.", iLastLevel, g_sCurrentUpgrade);
					return SMCParse_HaltFail;
				}
				iLastLevel = iMinRPGLevel[MRL_upgradeLevel];
				
				// Minimum rpg level for upgrade level 1 has to be smaller than minimum rpg level for upgrade level 2.
				if (iLastMinRPGLevel > iMinRPGLevel[MRL_minRPGLevel])
				{
					LogError("The required rpg level for upgrade \"%s\" level %d can't be set to %d, because the previous section already set the minimum rpg level to %d.", g_sCurrentUpgrade, iMinRPGLevel[MRL_upgradeLevel], iMinRPGLevel[MRL_minRPGLevel], iLastMinRPGLevel);
					return SMCParse_HaltFail;
				}
				iLastMinRPGLevel = iMinRPGLevel[MRL_minRPGLevel];
			}
		}
		
		g_sCurrentUpgrade[0] = '\0';
	}
	else if (g_iConfigSection == RSection_RPGLevels 
			|| g_iConfigSection == RSection_UpgradeAccess 
			|| g_iConfigSection == RSection_UpgradeRequirements
			|| g_iConfigSection == RSection_UpgradeRestrictions)
	{
		g_iConfigSection = RSection_Upgrade;
	}
	else if (g_iConfigSection == RSection_RPGLevelRule)
	{
		g_iConfigSection = RSection_RPGLevels;
		
		// Both "upgrade_level" and "rpg_level" have to be set.
		if (g_TempMinRPGLevel[MRL_upgradeLevel] == -1)
		{
			LogError("Missing \"upgrade_level\" setting in \"rpg_level\" section of upgrade \"%s\".", g_sCurrentUpgrade);
			return SMCParse_HaltFail;
		}
		
		if (g_TempMinRPGLevel[MRL_minRPGLevel] == -1)
		{
			LogError("Missing \"rpg_level\" setting in \"rpg_level\" section of upgrade \"%s\".", g_sCurrentUpgrade);
			return SMCParse_HaltFail;
		}
		
		// Save this section
		new iRestriction[UpgradeRestrictionConfig];
		GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
		PushArrayArray(iRestriction[URC_minimumRPGLevels], g_TempMinRPGLevel[0], _:MinimumRPGLevel);
		
		// Reset temp data for another section.
		g_TempMinRPGLevel[MRL_minRPGLevel] = -1;
		g_TempMinRPGLevel[MRL_upgradeLevel] = -1;
	}
	else if (g_iConfigSection == RSection_UpgradeRequirementLevel)
	{
		g_iConfigSection = RSection_UpgradeRequirements;
		
		// Make sure there are no duplicate entries for the same other upgrade.
		new iRequirement[UpgradeRequirement], iTemp;
		new iSize = GetArraySize(g_hRequirementUpgradeList);
		new Handle:hHashmap = CreateTrie();
		for (new i=0; i<iSize; i++)
		{
			GetArrayArray(g_hRequirementUpgradeList, i, iRequirement[0], _:UpgradeRequirement);
			if (GetTrieValue(hHashmap, iRequirement[UR_shortName], iTemp))
			{
				CloseHandle(hHashmap);
				LogError("There are multiple requirements for upgrade \"%s\" in \"upgrades\" section for level %d of upgrade \"%s\".", iRequirement[UR_shortName], g_iRequirementLevel, g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			SetTrieValue(hHashmap, iRequirement[UR_shortName], 0);
		}
		CloseHandle(hHashmap);
		
		g_iRequirementLevel = -1;
		g_hRequirementUpgradeList = INVALID_HANDLE;
	}
	else if (g_iConfigSection == RSection_UpgradeRestrictionRule)
	{
		g_iConfigSection = RSection_UpgradeRestrictions;
		
		// If this section wasn't empty ..
		if (g_TempRestrictionRule[URR_maxLevel] != -1 || g_TempRestrictionRule[URL_requirements] != INVALID_HANDLE)
		{
			// .. Save it
			new iRestriction[UpgradeRestrictionConfig];
			GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestrictionConfig);
			PushArrayArray(iRestriction[URC_upgradesRestrictions], g_TempRestrictionRule[0], _:UpgradeRestrictionRule);
		}
		
		// Reset the state
		g_TempRestrictionRule[URR_maxLevel] = -1;
		g_TempRestrictionRule[URL_requirements] = INVALID_HANDLE;
	}
	return SMCParse_Continue;
}

// Sort by upgrade level ascending
public Sort_UpgradeRequirements(index1, index2, Handle:array, Handle:hndl)
{
	new iRequirementLevel1[UpgradeRequirementLevel], iRequirementLevel2[UpgradeRequirementLevel];
	GetArrayArray(array, index1, iRequirementLevel1[0], _:UpgradeRequirementLevel);
	GetArrayArray(array, index2, iRequirementLevel2[0], _:UpgradeRequirementLevel);
	
	return iRequirementLevel1[URL_level] - iRequirementLevel2[URL_level];
}

// Sort by upgrade level ascending
public Sort_RPGLevelRequirements(index1, index2, Handle:array, Handle:hndl)
{
	new iMinRPGLevel1[MinimumRPGLevel], iMinRPGLevel2[MinimumRPGLevel];
	GetArrayArray(array, index1, iMinRPGLevel1[0], _:UpgradeRequirementLevel);
	GetArrayArray(array, index2, iMinRPGLevel2[0], _:UpgradeRequirementLevel);
	
	return iMinRPGLevel1[MRL_upgradeLevel] - iMinRPGLevel2[MRL_upgradeLevel];
}