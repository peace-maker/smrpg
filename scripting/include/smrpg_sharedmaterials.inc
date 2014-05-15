#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

/**
 * Loads the smrpg_sharedmaterials.games gamedata file and errors if it fails.
 * 
 * @noreturn
 */
stock SMRPG_GC_CheckSharedMaterialsAndSounds(const String:sGameDataFile[] = "smrpg_sharedmaterials.games")
{
	if(SMRPG_GC_GetSMRPGGameData(sGameDataFile) == INVALID_HANDLE)
		SetFailState("Missing required gamedata %s!", sGameDataFile);
}

/**
 * Gets a keyvalue from the smrpg_sharedmaterials.games gameconfig file.
 * 
 * @param key	The key to search for in the gamedata file.
 * @return		The value of the key in the gamedata file.
 */
stock String:SMRPG_GC_GetKeyValue(const String:key[])
{
	new String:sBuffer[PLATFORM_MAX_PATH];
	GameConfGetKeyValue(SMRPG_GC_GetSMRPGGameData(), key, sBuffer, sizeof(sBuffer));
	return sBuffer;
}

/**
 * Precaches the model and caches the model index.
 * 
 * @param key	The key of the modelpath in the gamedata file.
 * @return		Modelindex of the precached model.
 */
stock SMRPG_GC_PrecacheModel(const String:key[])
{
	new String:sBuffer[PLATFORM_MAX_PATH];
	sBuffer = SMRPG_GC_GetKeyValue(key);
	new iIndex = -1;
	if(sBuffer[0] != '\0')
	{
		iIndex = PrecacheModel(sBuffer);
		SetTrieValue(SMRPG_GC_GetGameDataCache(), key, iIndex);
	}
	return iIndex;
}

/**
 * Precaches a sound from the gamedata file.
 * 
 * @param key	The key of the soundpath in the gamedata file.
 * @return		True if precached successfully, false otherwise.
 */
stock bool:SMRPG_GC_PrecacheSound(const String:key[])
{
	new String:sBuffer[PLATFORM_MAX_PATH];
	sBuffer = SMRPG_GC_GetKeyValue(key);
	new bool:bSuccess;
	if(sBuffer[0] != '\0')
	{
		bSuccess = PrecacheSound(sBuffer, true);
	}
	return bSuccess;
}

/**
 * Gets the model index of a precached model in the gamedata file.
 * 
 * @param key	The key of the model in the gamedata file.
 * @return		The precached model index if it was precached, -1 if not precached or failed.
 */
stock SMRPG_GC_GetPrecachedIndex(const String:key[])
{
	new iValue = -1;
	GetTrieValue(SMRPG_GC_GetGameDataCache(), key, iValue);
	return iValue;
}


/***********************************
 * INTERNAL
 ***********************************/

/**
 * Gets the Handle to the smrpg_sharedmaterials.games gameconfig.
 * 
 * @return Handle to the smrpg_sharedmaterials.games gameconfig or INVALID_HANDLE if not found.
 */
stock Handle:SMRPG_GC_GetSMRPGGameData(const String:sGameDataFile[] = "")
{
	static Handle:hGameData = INVALID_HANDLE;
	if(!hGameData && sGameDataFile[0] != '\0')
	{
		hGameData = LoadGameConfigFile(sGameDataFile);
	}
	
	return hGameData;
}

/**
 * Gets the Handle to the precached models indices trie.
 * 
 * @return Handle to the precached models indices trie.
 */
stock Handle:SMRPG_GC_GetGameDataCache()
{
	static Handle:hCache = INVALID_HANDLE;
	if(!hCache)
	{
		hCache = CreateTrie();
	}
	return hCache;
}