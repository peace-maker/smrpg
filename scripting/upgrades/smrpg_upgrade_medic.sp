#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smrpg>
#include <smrpg_helper>
#include <smrpg_sharedmaterials>

#undef REQUIRE_PLUGIN
#include <smrpg_health>
#include <smrpg_armorplus>

#define UPGRADE_SHORTNAME "medic"
#define PLUGIN_VERSION "1.0"

#define MEDIC_HEALTH_BEAM_COLOR {5, 45, 255, 50}
#define MEDIC_ARMOR_BEAM_COLOR {5, 255, 10, 50}

new Handle:g_hCVIncrease;
new Handle:g_hCVInterval;
new Handle:g_hCVRadius;

new bool:g_bIsCstrike;

new Handle:g_hMedicTimer;

public Plugin:myinfo = 
{
	name = "SM:RPG Upgrade > Medic",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Medic upgrade for SM:RPG. Heals teammates around you.",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
}

public OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	g_bIsCstrike = GetEngineVersion() == Engine_CSS || GetEngineVersion() == Engine_CSGO;
	SMRPG_GC_CheckSharedMaterialsAndSounds();
}

public OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public OnLibraryAdded(const String:name[])
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Medic", UPGRADE_SHORTNAME, "Heals team mates around you.", 20, true, 15, 15, 20, _, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Sounds, true);
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		g_hCVIncrease = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_medic_increase", "5", "Heal increment for each level.", _, true, 1.0);
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_medic_interval", "2.0", "Delay between each heal wave in seconds.", _, true, 1.0);
		g_hCVRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_medic_radius", "250.0", "Radius around player in which other players are healed.", _, true, 1.0);
		
		HookConVarChange(g_hCVInterval, ConVar_IntervalChanged);
	}
}

public OnMapStart()
{
	if(g_hMedicTimer != INVALID_HANDLE)
		CloseHandle(g_hMedicTimer);
	
	g_hMedicTimer = CreateTimer(GetConVarFloat(g_hCVInterval), Timer_ApplyMedic, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	SMRPG_GC_PrecacheSound("SoundMedicCharge");
	
	SMRPG_GC_PrecacheModel("SpriteBeam");
	SMRPG_GC_PrecacheModel("SpriteHalo");
}

public OnMapEnd()
{
	g_hMedicTimer = INVALID_HANDLE;
}

/**
 * SM:RPG Upgrade callbacks
 */
public SMRPG_BuySell(client, UpgradeQueryType:type)
{
	// Nothing to apply here immediately after someone buys this upgrade.
}

public bool:SMRPG_ActiveQuery(client)
{
	// This is a passive effect, so it's always active, if the player got at least level 1
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	return SMRPG_IsEnabled() && upgrade[UI_enabled] && SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME) > 0;
}

public SMRPG_TranslateUpgrade(client, const String:shortname[], TranslationType:type, String:translation[], maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		new String:sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

/**
 * Checks the distance of each player from a medic and assigns health to them accordingly.
 */
public Action:Timer_ApplyMedic(Handle:timer, any:data)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	// There are no teammates in Free-For-All mode.
	if(SMRPG_IsFFAEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	new bool:bIgnoreBots = SMRPG_IgnoreBots();
	
	// Build origin cache and team targets for beam rings
	decl Float:vCacheOrigin[MaxClients+1][3];
	decl iFirstTeam[MaxClients], iSecondTeam[MaxClients];
	new iFirstCount, iSecondCount;
	for(new i=1;i<=MaxClients;i++)
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
		
		if(!IsPlayerAlive(i))
			continue;
		
		GetClientEyePosition(i, vCacheOrigin[i]);
	}
	
	new Float:fMedicRadius = GetConVarFloat(g_hCVRadius);
	new iMedicIncrease = GetConVarInt(g_hCVIncrease);
	
	new bool:bMedicDidHisJob, iBeamRingColor[4];
	
	new iBeamSprite = SMRPG_GC_GetPrecachedIndex("SpriteBeam");
	new iHaloSprite = SMRPG_GC_GetPrecachedIndex("SpriteHalo");
	// Just use the beamsprite as halo, if no halo sprite available
	if(iHaloSprite == -1)
		iHaloSprite = iBeamSprite;
	
	decl iLevel, iNewHP, iMaxHealth, iNewArmor, iMaxArmor, Float:vRingOrigin[3];
	for(new i=1;i<=MaxClients;i++)
	{
		/* If player is a medic and player is not dead */
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		
		if(bIgnoreBots && IsFakeClient(i))
			continue;
		
		iLevel = SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME);
		if(iLevel <= 0)
			continue;
		
		if(!SMRPG_RunUpgradeEffect(i, UPGRADE_SHORTNAME))
			continue; // Some other plugin doesn't want this effect to run
		
		/* Medic found, now search for teammates */
		for(new m=1;m<=MaxClients;m++)
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

public ConVar_IntervalChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(g_hMedicTimer != INVALID_HANDLE)
		CloseHandle(g_hMedicTimer);
	g_hMedicTimer = CreateTimer(GetConVarFloat(g_hCVInterval), Timer_ApplyMedic, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}