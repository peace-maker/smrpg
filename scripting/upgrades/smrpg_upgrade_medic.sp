#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

//#pragma newdecls required
#include <smrpg>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>

#undef REQUIRE_PLUGIN
#include <smrpg_health>
#include <smrpg_armorplus>

#define UPGRADE_SHORTNAME "medic"

#define MEDIC_HEALTH_BEAM_COLOR {5, 45, 255, 50}
#define MEDIC_ARMOR_BEAM_COLOR {5, 255, 10, 50}

ConVar g_hCVIncrease;
ConVar g_hCVInterval;
ConVar g_hCVRadius;
ConVar g_hCVRadiusIncrease;

bool g_bIsCstrike;

Handle g_hMedicTimer;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Medic",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Medic upgrade for SM:RPG. Heals teammates around you.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	g_bIsCstrike = GetEngineVersion() == Engine_CSS || GetEngineVersion() == Engine_CSGO;
	SMRPG_GC_CheckSharedMaterialsAndSounds();
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Medic", UPGRADE_SHORTNAME, "Heals team mates around you.", 20, true, 15, 15, 20);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Sounds, true);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_medic_increase", "5", "Heal increment for each level.", _, true, 1.0);
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_medic_interval", "2.0", "Delay between each heal wave in seconds.", _, true, 1.0);
		g_hCVRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_medic_radius", "250.0", "Base radius around player in which other players are healed.", _, true, 1.0);
		g_hCVRadiusIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_medic_radius_increase", "0.0", "Radius increase for each level.", _, true, 0.0);
		
		g_hCVInterval.AddChangeHook(ConVar_IntervalChanged);
	}
}

public void OnMapStart()
{
	if(g_hMedicTimer != null)
		delete g_hMedicTimer;
	
	g_hMedicTimer = CreateTimer(g_hCVInterval.FloatValue, Timer_ApplyMedic, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	SMRPG_GC_PrecacheSound("SoundMedicCharge");
	
	SMRPG_GC_PrecacheModel("SpriteBeam");
	SMRPG_GC_PrecacheModel("SpriteHalo");
}

public void OnMapEnd()
{
	g_hMedicTimer = null;
}

/**
 * SM:RPG Upgrade callbacks
 */
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

/**
 * Checks the distance of each player from a medic and assigns health to them accordingly.
 */
public Action Timer_ApplyMedic(Handle timer, any data)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	// There are no teammates in Free-For-All mode.
	if(SMRPG_IsFFAEnabled())
		return Plugin_Continue;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	bool bIgnoreBots = SMRPG_IgnoreBots();
	
	// Build origin cache and team targets for beam rings
	new Float:vCacheOrigin[MaxClients+1][3];
	int[] iFirstTeam = new int[MaxClients];
	int[] iSecondTeam = new int[MaxClients];
	int iFirstCount, iSecondCount;
	for(int i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(bIgnoreBots && IsFakeClient(i))
			continue;
		
		// Only show the effect to people who want to see it!
		if(SMRPG_ClientWantsCosmetics(i, UPGRADE_SHORTNAME, SMRPG_FX_Visuals))
		{
			if(GetClientTeam(i) == 2)
				iFirstTeam[iFirstCount++] = i;
			else if(GetClientTeam(i) == 3)
				iSecondTeam[iSecondCount++] = i;
		}
		
		if(!IsPlayerAlive(i) || IsClientObserver(i))
			continue;
		
		GetClientEyePosition(i, vCacheOrigin[i]);
	}
	
	float fMedicRadiusBase = g_hCVRadius.FloatValue;
	float fMedicRadiusIncrease = g_hCVRadiusIncrease.FloatValue;
	int iMedicIncrease = g_hCVIncrease.IntValue;
	
	bool bMedicDidHisJob;
	int	iBeamRingColor[4];
	
	int iBeamSprite = SMRPG_GC_GetPrecachedIndex("SpriteBeam");
	int iHaloSprite = SMRPG_GC_GetPrecachedIndex("SpriteHalo");
	// Just use the beamsprite as halo, if no halo sprite available
	if(iHaloSprite == -1)
		iHaloSprite = iBeamSprite;
	
	int iLevel, iNewHP, iMaxHealth, iNewArmor, iMaxArmor;
	float fMedicRadius, vRingOrigin[3];
	for(int i=1;i<=MaxClients;i++)
	{
		/* If player is a medic and player is not dead */
		if(!IsClientInGame(i) || !IsPlayerAlive(i) || IsClientObserver(i))
			continue;
		
		if(bIgnoreBots && IsFakeClient(i))
			continue;
		
		iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			continue;
		
		if(!SMRPG_RunUpgradeEffect(i, UPGRADE_SHORTNAME))
			continue; // Some other plugin doesn't want this effect to run
		
		fMedicRadius = fMedicRadiusBase + fMedicRadiusIncrease * float(iLevel-1);
		
		/* Medic found, now search for teammates */
		for(int m=1;m<=MaxClients;m++)
		{
			/* If player is on the same team as medic, player is not dead,
				   and player is not the medic */
			if(m == i || !IsClientInGame(m) || !IsPlayerAlive(m) || GetClientTeam(m) != GetClientTeam(i))
				continue;
			
			if(bIgnoreBots && IsFakeClient(m))
				continue;
			
			/* A suitable player has been found */
			/* Check if player is in the medic's radius */
			if(GetVectorDistance(vCacheOrigin[i], vCacheOrigin[m]) > fMedicRadius)
				continue;
			
			iNewHP = GetClientHealth(m);
			if(g_bIsCstrike)
			{
				iNewArmor = GetClientArmor(m);
				iMaxArmor = SMRPG_Armor_GetClientMaxArmor(m);
			}
			
			bMedicDidHisJob = false;
			
			iMaxHealth = SMRPG_Health_GetClientMaxHealth(m);
			/* If player is not at maximum health, heal him */
			if(iNewHP < iMaxHealth)
			{
				iNewHP += iLevel * iMedicIncrease;
				
				if(iNewHP > iMaxHealth)
					iNewHP = iMaxHealth;
				
				SetEntityHealth(m, iNewHP);
				
				iBeamRingColor = MEDIC_HEALTH_BEAM_COLOR;
				
				bMedicDidHisJob = true;
			}
			/* Else if player is not at maximum armor, repair him */
			else if(g_bIsCstrike && iNewArmor < iMaxArmor)
			{
				if(iLevel*iMedicIncrease > 25)
					iNewArmor += 25;
				else
					iNewArmor += iLevel*iMedicIncrease;
				
				if(iNewArmor > iMaxArmor)
					iNewArmor = iMaxArmor;
				
				// TODO: Move out of medic upgrade into own one?
				SetEntProp(m, Prop_Send, "m_ArmorValue", iNewArmor);
				
				iBeamRingColor = MEDIC_ARMOR_BEAM_COLOR;
				
				bMedicDidHisJob = true;
			}
			
			// Only run the effects, if something happended
			if(!bMedicDidHisJob)
				continue;
			
			vRingOrigin = vCacheOrigin[i];
			vRingOrigin[2] -= 25.0;
			
			if(iBeamSprite != -1)
			{
				TE_SetupBeamRingPoint(vRingOrigin, 8.0, fMedicRadius+300.0, iBeamSprite, iHaloSprite, 0, 1, 1.5, 10.0, 0.0, iBeamRingColor, 0, FBEAM_FADEOUT);
				
				if(GetClientTeam(i) == 2)
					TE_Send(iFirstTeam, iFirstCount);
				else
					TE_Send(iSecondTeam, iSecondCount);
			}
			
			SMRPG_EmitSoundToAllEnabled(UPGRADE_SHORTNAME, SMRPG_GC_GetKeyValue("SoundMedicCharge"), i, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.2, SNDPITCH_NORMAL, i);
		}
	}
	
	return Plugin_Continue;
}

public void ConVar_IntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(g_hMedicTimer != null)
		delete g_hMedicTimer;
	g_hMedicTimer = CreateTimer(g_hCVInterval.FloatValue, Timer_ApplyMedic, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}