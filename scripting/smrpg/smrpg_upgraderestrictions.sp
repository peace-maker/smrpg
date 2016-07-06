// Top level structure for an upgrade section.
enum UpgradeRestriction {
	UR_minimumRPGLevel, // holds the "min_rpg_level" info
	Handle:UR_upgrades // Array of UpgradeRequirementLevel's in "upgrades" section. requirements on the minimum levels of other upgrades
};

enum UpgradeRequirementLevel {
	URL_level, // upgrade level which requires the below list of minimum levels of other upgrades
	Handle:URL_requirements // array of UpgradeRequirement's
}

// Single key => value pair in "upgrades" section of an upgrade
enum UpgradeRequirement {
	UR_minLevel,
	String:UR_shortName[MAX_UPGRADE_SHORTNAME_LENGTH]
}

new Handle:g_hUpgradeRestrictions;

// Config parser
enum RestrictionConfigSection {
	RSection_None = 0,
	RSection_Root,
	RSection_Upgrade,
	RSection_UpgradeAccess,
	RSection_UpgradeDependencies,
	RSection_UpgradeRequirementLevel
};

new RestrictionConfigSection:g_iConfigSection;
new g_iIgnoreLevel;
new String:g_sCurrentUpgrade[MAX_UPGRADE_SHORTNAME_LENGTH];
new g_iRequirementLevel = -1; // For error messages
new Handle:g_hRequirementUpgradeList;

InitUpgradeRestrictions()
{
	g_hUpgradeRestrictions = CreateTrie();
}

/**
 * Helpers to get info for upgrades.
 */
 
bool:IsUpgradeRestricted(client, upgrade[InternalUpgradeInfo])
{
	// Player isn't on the right level yet.
	if (GetClientLevel(client) < GetMinimumRPGLevelForUpgrade(upgrade))
		return true;
	
	// Check for other required upgrades for this upgrade
	new Handle:hRequiredUpgrades = GetRequiredUpgradesForClient(client, upgrade, GetClientPurchasedUpgradeLevel(client, upgrade[UPGR_index])+1);
	// No other upgrades required or all requirements met.
	if (!hRequiredUpgrades)
		return false;
	
	CloseHandle(hRequiredUpgrades);
	return true;
}
 
// returns 0 if there is no minimum configured
GetMinimumRPGLevelForUpgrade(upgrade[InternalUpgradeInfo])
{
	new iRestriction[UpgradeRestriction];
	if (!GetTrieArray(g_hUpgradeRestrictions, upgrade[UPGR_shortName], iRestriction[0], _:UpgradeRestriction))
		return 0;
	
	return iRestriction[UR_minimumRPGLevel];
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
	new iRestriction[UpgradeRestriction];
	if (!GetTrieArray(g_hUpgradeRestrictions, upgrade[UPGR_shortName], iRestriction[0], _:UpgradeRestriction))
		return INVALID_HANDLE;
		
	if (!iRestriction[UR_upgrades])
		return INVALID_HANDLE;
	
	// Use a trie to merge multiple requirements for the same upgrade for the same level.
	new Handle:hRequiredUpgrades = CreateTrie();
	
	// Collect all the requirements up until iLevel
	new iSize = GetArraySize(iRestriction[UR_upgrades]);
	new iRequirementLevel[UpgradeRequirementLevel];
	new iRequirement[UpgradeRequirement], iNumRequirements;
	for (new i=0; i<iSize; i++)
	{
		GetArrayArray(iRestriction[UR_upgrades], i, iRequirementLevel[0], _:UpgradeRequirementLevel);
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

/**
 * SMC Parser for upgrade_restrictions.cfg config.
 */
bool:ResetRestrictionConfig()
{
	// Delete old config
	new Handle:hSnapshot = CreateTrieSnapshot(g_hUpgradeRestrictions);
	new iTrieSize = TrieSnapshotLength(hSnapshot), iSize;
	new String:sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
	new iRestriction[UpgradeRestriction], iRequirementLevel[UpgradeRequirementLevel];
	for (new i=0; i<iTrieSize; i++)
	{
		GetTrieSnapshotKey(hSnapshot, i, sShortname, sizeof(sShortname));
		GetTrieArray(g_hUpgradeRestrictions, sShortname, iRestriction[0], _:UpgradeRestriction);
		
		if (iRestriction[UR_upgrades] != INVALID_HANDLE)
		{
			iSize = GetArraySize(iRestriction[UR_upgrades]);
			for (new j=0; j<iSize; j++)
			{
				GetArrayArray(iRestriction[UR_upgrades], j, iRequirementLevel[0], _:UpgradeRequirementLevel);
				CloseHandle(iRequirementLevel[URL_requirements]);
			}
			CloseHandle(iRestriction[UR_upgrades]);
		}		
	}
	CloseHandle(hSnapshot);
	ClearTrie(g_hUpgradeRestrictions);
	
	// Reset reader state
	g_iConfigSection = RSection_None;
	g_iIgnoreLevel = 0;
	g_sCurrentUpgrade[0] = '\0';
	g_iRequirementLevel = -1;
	g_hRequirementUpgradeList = INVALID_HANDLE;
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
		
		new iRestriction[UpgradeRestriction];
		// Make sure there are no structures open for this upgrade yet.
		if (GetTrieArray(g_hUpgradeRestrictions, name, iRestriction[0], _:UpgradeRestriction))
		{
			LogError("Multiple sections for upgrade \"%s\". Only one per upgrade is supported.", name);
			return SMCParse_HaltFail;
		}
		
		SetTrieArray(g_hUpgradeRestrictions, name, iRestriction[0], _:UpgradeRestriction);
	}
	else if (g_iConfigSection == RSection_Upgrade)
	{
		if (StrEqual(name, "access", false))
			g_iConfigSection = RSection_UpgradeAccess;
		else if (StrEqual(name, "upgrades", false))
		{
			g_iConfigSection = RSection_UpgradeDependencies;
			
			new iRestriction[UpgradeRestriction];
			GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestriction);
			
			// Allow multiple "upgrades" sections to help readability.
			// We'll try to catch interferences later
			if (!iRestriction[UR_upgrades])
			{
				// Use an adt_array to sort it ascending after parsing.
				iRestriction[UR_upgrades] = CreateArray(_:UpgradeRequirementLevel);
				SetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestriction);
			}
		}
		else
			g_iIgnoreLevel++;
	}
	else if (g_iConfigSection == RSection_UpgradeDependencies)
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
		
		new iRestriction[UpgradeRestriction];
		GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestriction);
		
		new iRequirementLevel[UpgradeRequirementLevel];
		iRequirementLevel[URL_level] = iLevel;
		iRequirementLevel[URL_requirements] = CreateArray(_:UpgradeRequirement);
		PushArrayArray(iRestriction[UR_upgrades], iRequirementLevel[0], _:UpgradeRequirementLevel);
		
		// Remember for better error messages when parsing the other upgrade requirements
		g_iRequirementLevel = iLevel;
		
		// So we don't have to search for the correct list in the array.
		g_hRequirementUpgradeList = iRequirementLevel[URL_requirements];
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
	
	if (g_iConfigSection == RSection_Upgrade)
	{
		if (StrEqual(key, "min_rpg_level", false))
		{
			new iLevel;
			if (StringToIntEx(value, iLevel) == 0)
			{
				LogError("Upgrade \"%s\"'s min_rpg_level is not an integer.", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			if (iLevel < 0)
			{
				LogError("Upgrade \"%s\"'s min_rpg_level can't be negative.", g_sCurrentUpgrade);
				return SMCParse_HaltFail;
			}
			
			new iRestriction[UpgradeRestriction];
			GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestriction);
			iRestriction[UR_minimumRPGLevel] = iLevel;
			SetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestriction);
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
		
		// Done with the upgrade. Sort the upgrade requirements by ascending level.
		new iRestriction[UpgradeRestriction];
		GetTrieArray(g_hUpgradeRestrictions, g_sCurrentUpgrade, iRestriction[0], _:UpgradeRestriction);
		
		if (iRestriction[UR_upgrades])
		{
			SortADTArrayCustom(iRestriction[UR_upgrades], Sort_UpgradeRequirements);
			
			// Check for duplicate level sections
			new iLastLevel = -1;
			new iRequirementLevel[UpgradeRequirementLevel];
			new iSize = GetArraySize(iRestriction[UR_upgrades]);
			for (new i=0; i<iSize; i++)
			{
				GetArrayArray(iRestriction[UR_upgrades], i, iRequirementLevel[0], _:UpgradeRequirementLevel);
				if (iLastLevel != -1 && iLastLevel == iRequirementLevel[URL_level])
				{
					LogError("There are multiple sections for level %d in the \"upgrades\" sections of upgrade \"%s\". Please merge them.", iLastLevel, g_sCurrentUpgrade);
					return SMCParse_HaltFail;
				}
				
				iLastLevel = iRequirementLevel[URL_level];
			}
			
			// TODO: Check for upgrade restrictions on other upgrades being lower on higher levels than on lower ones. 
			// "upgrades" { "2" { "health" "4" } "4" { "health" "2" } }
		}
		
		g_sCurrentUpgrade[0] = '\0';
	}
	else if (g_iConfigSection == RSection_UpgradeAccess || g_iConfigSection == RSection_UpgradeDependencies)
	{
		g_iConfigSection = RSection_Upgrade;
	}
	else if (g_iConfigSection == RSection_UpgradeRequirementLevel)
	{
		g_iConfigSection = RSection_UpgradeDependencies;
		
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

