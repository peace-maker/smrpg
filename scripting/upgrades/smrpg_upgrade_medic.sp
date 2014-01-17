#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smrpg>

#undef REQUIRE_PLUGIN
#include <smrpg_health>

#define UPGRADE_SHORTNAME "medic"
#define PLUGIN_VERSION "1.0"

/**
 * @brief Heal increment for each level.
 */
#define MEDIC_INC 5

/**
 * @brief Delay between each heal.
 */
#define MEDIC_DELAY 2.0

/**
 * @brief Medic healing radius.
 */
#define MEDIC_RADIUS 250.0

#define MEDIC_HEALTH_BEAM_COLOR {5, 45, 255, 50}
#define MEDIC_ARMOR_BEAM_COLOR {5, 255, 10, 50}

new g_iBeamRingSprite = -1;

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
		SMRPG_RegisterUpgradeType("Medic", UPGRADE_SHORTNAME, "Heals team mates around you.", 20, true, 15, 15, 20, SMRPG_BuySell, SMRPG_ActiveQuery);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
	}
}

public OnMapStart()
{
	CreateTimer(MEDIC_DELAY, Timer_ApplyMedic, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	// TODO: Make game independant
	PrecacheSound("weapons/physcannon/physcannon_charge.wav", true);
	
	g_iBeamRingSprite = PrecacheModel("sprites/lgtning.vmt", true);
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

public SMRPG_TranslateUpgrade(client, TranslationType:type, String:translation[], maxlen)
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
 * @brief Checks the distance of each player from a medic and assigns health
 *        to them accordingly.
 */
public Action:Timer_ApplyMedic(Handle:timer, any:data)
{
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	new upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	new bool:bBotEnable = SMRPG_IgnoreBots();
	
	// Build origin cache and team targets for beam rings
	decl Float:vCacheOrigin[MaxClients+1][3];
	decl iFirstTeam[MaxClients+1], iSecondTeam[MaxClients+1];
	new iFirstCount, iSecondCount;
	for(new i=1;i<=MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(!bBotEnable && IsFakeClient(i))
			continue;
		
		if(GetClientTeam(i) == 2)
			iFirstTeam[iFirstCount++] = i;
		else if(GetClientTeam(i) == 3)
			iSecondTeam[iSecondCount++] = i;
		
		if(!IsPlayerAlive(i))
			continue;
		
		GetClientEyePosition(i, vCacheOrigin[i]);
	}
	
	new bool:bMedicDidHisJob, iBeamRingColor[4];
	
	decl iLevel, iNewHP, iMaxHealth, iNewArmor, Float:vRingOrigin[3];
	for(new i=1;i<=MaxClients;i++)
	{
		/* If player is a medic and player is not dead */
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		
		if(!bBotEnable && IsFakeClient(i))
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
			
			if(!bBotEnable && IsFakeClient(m))
				continue;
			
			/* A suitable player has been found */
			/* Check if player is in the medic's radius */
			if(GetVectorDistance(vCacheOrigin[i], vCacheOrigin[m]) > MEDIC_RADIUS)
				continue;
			
			iNewHP = GetClientHealth(m);
			iNewArmor = GetClientArmor(m);
			
			bMedicDidHisJob = false;
			
			iMaxHealth = SMRPG_Health_GetClientMaxHealth(m);
			/* If player is not at maximum health, heal him */
			if(iNewHP < iMaxHealth)
			{
				iNewHP += iLevel * MEDIC_INC;
				
				if(iNewHP > iMaxHealth)
					iNewHP = iMaxHealth;
				
				SetEntityHealth(m, iNewHP);
				
				iBeamRingColor = MEDIC_HEALTH_BEAM_COLOR;
				
				bMedicDidHisJob = true;
			}
			/* Else if player is not at maximum armor, repair him */
			else if(iNewArmor < 100)
			{
				if(iLevel*MEDIC_INC > 25)
					iNewArmor += 25;
				else
					iNewArmor += iLevel*MEDIC_INC;
				
				if(iNewArmor > 100)
					iNewArmor = 100;
				
				// TODO: Make game independant
				SetEntProp(m, Prop_Send, "m_ArmorValue", iNewArmor);
				
				iBeamRingColor = MEDIC_ARMOR_BEAM_COLOR;
				
				bMedicDidHisJob = true;
			}
			
			// Only run the effects, if something happended
			if(!bMedicDidHisJob)
				continue;
			
			vRingOrigin = vCacheOrigin[i];
			vRingOrigin[2] -= 25.0;
			
			TE_SetupBeamRingPoint(vRingOrigin, 8.0, MEDIC_RADIUS+300.0, g_iBeamRingSprite, g_iBeamRingSprite, 0, 1, 1.5, 10.0, 0.0, iBeamRingColor, 0, FBEAM_FADEOUT);
			
			if(GetClientTeam(i) == 2)
				TE_Send(iFirstTeam, iFirstCount);
			else
				TE_Send(iSecondTeam, iSecondCount);
			
			EmitSoundToAll("weapons/physcannon/physcannon_charge.wav", i, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.2, SNDPITCH_NORMAL, i);
		}
	}
	
	return Plugin_Continue;
}