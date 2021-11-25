#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define MAX_SCRIPT_NAME_LENGTH 32
#define TEAM_SURVIVORS 2

enum
{
	eWeaponName,
	eWeaponWorldModel,
	eWeaponViewModel,
	eWeaponScriptName,

	eWeaponSize
};

enum
{
	Melee_None				= 0,
	Melee_Knife				= 1,
	Melee_FireAxe			= 2,
	Melee_CricketBat		= 3,
	Melee_Katana			= 4,
	Melee_Riotshield		= 5,
	Melee_Machete			= 6,
	Melee_Guitar			= 7,
	Melee_Pan				= 8,
	Melee_BaseBallBat		= 9,
	Melee_Crowbar			= 10,
	Melee_GolfClub			= 11,
	Melee_Tonfa				= 12,
	Melee_Pitchfork			= 13,
	Melee_Shovel			= 14,
	//Melee_Didgeridoo		= 15,

	Melee_Size
};

public const char g_sMeleeWeapons[][][] =
{
	{
		"",
		"",
		"",
		""
	},
	{
		"knife",
		"models/w_models/weapons/w_knife_t.mdl",
		"models/v_models/v_knife_t.mdl",
		"scripts/melee/knife.txt"
	},
	{
		"fireaxe",
		"models/weapons/melee/w_fireaxe.mdl",
		"models/weapons/melee/v_fireaxe.mdl",
		"scripts/melee/fireaxe.txt",
	},
	{
		"cricket_bat",
		"models/weapons/melee/w_cricket_bat.mdl",
		"models/weapons/melee/v_cricket_bat.mdl",
		"scripts/melee/cricket_bat.txt"
	},
	{
		"katana",
		"models/weapons/melee/w_katana.mdl",
		"models/weapons/melee/v_katana.mdl",
		"scripts/melee/katana.txt"
	},
	{
		"riotshield",
		"models/weapons/melee/w_riotshield.mdl",
		"models/weapons/melee/v_riotshield.mdl",
		"scripts/melee/riotshield.txt"
	},
	{
		"machete",
		"models/weapons/melee/w_machete.mdl",
		"models/weapons/melee/v_machete.mdl",
		"scripts/melee/machete.txt"
	},
	{
		"electric_guitar",
		"models/weapons/melee/w_electric_guitar.mdl",
		"models/weapons/melee/v_electric_guitar.mdl",
		"scripts/melee/electric_guitar.txt"
	},
	{
		"frying_pan",
		"models/weapons/melee/w_frying_pan.mdl",
		"models/weapons/melee/v_frying_pan.mdl",
		"scripts/melee/frying_pan.txt"
	},
	{
		"baseball_bat",
		"models/weapons/melee/w_bat.mdl",
		"models/weapons/melee/v_bat.mdl",
		"scripts/melee/baseball_bat.txt"
	},
	{
		"crowbar",
		"models/weapons/melee/w_crowbar.mdl",
		"models/weapons/melee/v_crowbar.mdl",
		"scripts/melee/crowbar.txt"
	},
	{
		"golfclub",
		"models/weapons/melee/w_golfclub.mdl",
		"models/weapons/melee/v_golfclub.mdl",
		"scripts/melee/golfclub.txt"
	},
	{
		"tonfa",
		"models/weapons/melee/w_tonfa.mdl",
		"models/weapons/melee/v_tonfa.mdl",
		"scripts/melee/tonfa.txt"
	},
	{
		"pitchfork",
		"models/weapons/melee/w_pitchfork.mdl",
		"models/weapons/melee/v_pitchfork.mdl",
		"scripts/melee/pitchfork.txt"
	},
	{
		"shovel",
		"models/weapons/melee/w_shovel.mdl",
		"models/weapons/melee/v_shovel.mdl",
		"scripts/melee/shovel.txt"
	}/*,
	{
		"didgeridoo",
		"models/weapons/melee/w_didgeridoo.mdl",
		"",
		""
	}*/
};

ConVar
	g_hEnabled = null,
	g_hWeaponRandom = null,
	g_hWeaponRandomAmount = null,
	g_hMeleeWeapons[Melee_Size] = {null, ...};

Handle
	g_hSpawnTimer = null;

ArrayList
	g_hFirstHalfMelees = null;

int
	g_iMeleeClassCount = 0;

char
	g_sMeleeClass[Melee_Size][MAX_SCRIPT_NAME_LENGTH];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	if (GetEngineVersion() != Engine_Left4Dead2) {
		strcopy(sError, iErrMax, "Melee in the Saferoom only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "Melee In The Saferoom",
	author = "N3wton, A1m`",
	description = "Spawns a selection of melee weapons in the saferoom, at the start of each round.",
	version = "2.5",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};

public void OnPluginStart()
{
	g_hEnabled = CreateConVar("l4d2_MITSR_Enabled", "1", "Should the plugin be enabled", _, true, 0.0, true, 1.0);
	g_hWeaponRandom = CreateConVar("l4d2_MITSR_Random", "1", "Spawn Random Weapons (1) or custom list (0)", _, true, 0.0, true, 1.0);
	g_hWeaponRandomAmount = CreateConVar("l4d2_MITSR_Amount", "8", "Number of weapons to spawn if l4d2_MITSR_Random is 1", _, true, 0.0);

	g_hMeleeWeapons[Melee_Knife] = CreateConVar("l4d2_MITSR_Knife", "1", "Number of knifes to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_FireAxe] = CreateConVar("l4d2_MITSR_FireAxe", "1", "Number of fireaxes to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_CricketBat] = CreateConVar("l4d2_MITSR_CricketBat", "1", "Number of cricket bats to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Katana] = CreateConVar("l4d2_MITSR_Katana", "1", "Number of katanas to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Riotshield] = CreateConVar("l4d2_MITSR_RiotShield", "0", "Number of riot shields to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Machete] = CreateConVar("l4d2_MITSR_Machete", "1", "Number of machetes to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Guitar] = CreateConVar("l4d2_MITSR_ElecGuitar", "1", "Number of electric guitars to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Pan] = CreateConVar("l4d2_MITSR_FryingPan", "1", "Number of frying pans to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_BaseBallBat] = CreateConVar("l4d2_MITSR_BaseballBat", "1", "Number of baseball bats to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Crowbar] = CreateConVar("l4d2_MITSR_Crowbar", "1", "Number of crowbars to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_GolfClub] = CreateConVar("l4d2_MITSR_GolfClub", "1", "Number of golf clubs to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Tonfa] = CreateConVar("l4d2_MITSR_Tonfa", "1", "Number of tonfas to spawn (l4d2_MITSR_Random must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Pitchfork] = CreateConVar("l4d2_MITSR_PitchFork", "1", "Number of pitchforks to spawn (l4d2_MITSR_Spawn_Type must be 0)", _, true, 0.0, true, 10.0);
	g_hMeleeWeapons[Melee_Shovel] = CreateConVar("l4d2_MITSR_Shovel", "1", "Number of shovels to spawn (l4d2_MITSR_Spawn_Type must be 0)", _, true, 0.0, true, 10.0);
	//g_hMeleeWeapons[Melee_Didgeridoo] = CreateConVar("l4d2_MITSR_Didgeridoo", "1", "Number of shovels to spawn (l4d2_MITSR_Spawn_Type must be 0)", _, true, 0.0, true, 10.0);

	g_hFirstHalfMelees = new ArrayList();

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	RegAdminCmd("sm_melee_list", Cmd_MeleeList, ADMFLAG_KICK, "Lists all melee weapons spawnable in current campaign");
}

public Action Cmd_MeleeList(int iClient, int iArgs)
{
	for (int i = 0; i < g_iMeleeClassCount; i++) {
		PrintToChat(iClient, "%d : %s", i, g_sMeleeClass[i]);
	}

	return Plugin_Handled;
}

public void OnMapStart()
{
	for (int i = 1; i < Melee_Size; i++) {
		for (int j = eWeaponWorldModel; j <= eWeaponViewModel; j++) {
			if (!IsModelPrecached(g_sMeleeWeapons[i][j])) {
				PrecacheModel(g_sMeleeWeapons[i][j], true);
			}
		}

		if (!IsGenericPrecached(g_sMeleeWeapons[i][eWeaponScriptName])) {
			PrecacheGeneric(g_sMeleeWeapons[i][eWeaponScriptName], true);
		}
	}
}

public void OnMapEnd()
{
	g_hFirstHalfMelees.Clear();
	g_hSpawnTimer = null;
}

public void Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (!g_hEnabled.BoolValue) {
		return;
	}

	GetMeleeClasses();

	if (g_hSpawnTimer != null) {
		delete g_hSpawnTimer;
		g_hSpawnTimer = null;
	}

	g_hSpawnTimer = CreateTimer(2.0, Timer_SpawnMelee, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public Action Timer_SpawnMelee(Handle hTimer)
{
	int iClient = GetInGameClient();

	if (iClient < 1) {
		return Plugin_Continue;
	}

	float fSpawnPosition[3], fSpawnAngle[3];
	GetClientAbsOrigin(iClient, fSpawnPosition);
	fSpawnPosition[2] += 20;
	fSpawnAngle[0] = 90.0;

	if (!g_hWeaponRandom.BoolValue) {
		SpawnCustomList(fSpawnPosition, fSpawnAngle);

		g_hSpawnTimer = null;
		return Plugin_Stop;
	}

	int iRandomMelee = 0;
	if (IsVersus() && !IsGameInFirstHalf() && g_hFirstHalfMelees.Length > 0) {
		int iLength = g_hFirstHalfMelees.Length;
		for (int i = 0; i < iLength; i++) {
			iRandomMelee = g_hFirstHalfMelees.Get(i);

			SpawnMelee(g_sMeleeClass[iRandomMelee], fSpawnPosition, fSpawnAngle);
		}
	} else {
		int iRandomAmount = g_hWeaponRandomAmount.IntValue;
		g_hFirstHalfMelees.Clear();

		for (int i = 0 ; i < iRandomAmount; i++) {
			iRandomMelee = GetRandomInt(0, (g_iMeleeClassCount - 1));
			g_hFirstHalfMelees.Push(iRandomMelee);

			SpawnMelee(g_sMeleeClass[iRandomMelee], fSpawnPosition, fSpawnAngle);
		}
	}

	g_hSpawnTimer = null;
	return Plugin_Stop;
}

void SpawnCustomList(const float fPosition[3], const float fAngle[3])
{
	char sScriptName[MAX_SCRIPT_NAME_LENGTH];
	int iCvarValue = 0;

	for (int j = 1; j < Melee_Size; j++) {
		iCvarValue = g_hMeleeWeapons[j].IntValue;
		if (iCvarValue > 0) {
			for (int i = 0; i < iCvarValue; i++) {
				GetScriptName(g_sMeleeWeapons[j][eWeaponName], sScriptName);
				SpawnMelee(sScriptName, fPosition, fAngle);
			}
		}
	}
}

void SpawnMelee(const char[] sClass, const float fPosition[3], const float fAngle[3])
{
	float fSpawnPosition[3], fSpawnAngle[3];
	VectorCopy(fPosition, fSpawnPosition);
	VectorCopy(fAngle, fSpawnAngle);

	fSpawnPosition[0] += (-10 + GetRandomInt(0, 20));
	fSpawnPosition[1] += (-10 + GetRandomInt(0, 20));
	fSpawnPosition[2] += GetRandomInt(0, 10);
	fSpawnAngle[1] = GetRandomFloat(0.0, 360.0);

	int iMeleeSpawn = CreateEntityByName("weapon_melee");
	if (iMeleeSpawn == -1) {
		return;
	}

	DispatchKeyValue(iMeleeSpawn, "melee_script_name", sClass);
	DispatchSpawn(iMeleeSpawn);
	TeleportEntity(iMeleeSpawn, fSpawnPosition, fSpawnAngle, NULL_VECTOR);
}

void GetMeleeClasses()
{
	int iMeleeStringTable = FindStringTable("MeleeWeapons");
	g_iMeleeClassCount = GetStringTableNumStrings(iMeleeStringTable);

	for (int i = 0; i < g_iMeleeClassCount; i++) {
		ReadStringTable(iMeleeStringTable, i, g_sMeleeClass[i], MAX_SCRIPT_NAME_LENGTH);
	}
}

void GetScriptName(const char[] sClass, char[] sScriptName, const int iMaxLen = MAX_SCRIPT_NAME_LENGTH)
{
	for (int i = 0; i < g_iMeleeClassCount; i++) {
		if (StrContains(g_sMeleeClass[i], sClass, false) == 0) {
			Format(sScriptName, iMaxLen, "%s", g_sMeleeClass[i]);
			return;
		}
	}

	Format(sScriptName, iMaxLen, "%s", g_sMeleeClass[0]);
}

int GetInGameClient()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVORS && IsPlayerAlive(i)) {
			return i;
		}
	}

	return -1;
}

bool IsVersus()
{
	char sGameMode[32];
	GetConVarString(FindConVar("mp_gamemode"), sGameMode, sizeof(sGameMode));
	if (StrContains(sGameMode, "versus", false) != -1 || StrContains(sGameMode, "mutation12", false) != -1) {
		return true;
	}

	return false;
}

bool IsGameInFirstHalf()
{
	return (GameRules_GetProp("m_bInSecondHalfOfRound")) ? false : true;
}

void VectorCopy(const float fFrom[3], float fTo[3])
{
	fTo[0] = fFrom[0];
	fTo[1] = fFrom[1];
	fTo[2] = fFrom[2];
}
