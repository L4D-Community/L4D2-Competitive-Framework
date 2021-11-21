#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <collisionhook>

#define DEBUG 0

#define Z_JOCKEY 5
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define MAX_ENTITY_NAME_SIZE 64

#if DEBUG
ConVar
	g_hCvarLedgeLaggerFix = null;
#endif

int
	g_iJockeyAttackerOffset = -1,
	g_iZombieClassOffset = -1;

public Plugin myinfo =
{
	name = "L4D2 Jockeyed Survivor Ladder Fix",
	author = "Visor, A1m`",
	description = "Fixes jockeyed Survivors slowly sliding down the ladders",
	version = "1.3",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
#if DEBUG
	g_hCvarLedgeLaggerFix = CreateConVar("l4d2_legde_lagger_fix", "1.0", "Enable fix jockeyed Survivors slowly sliding down the ladders?", _, true, 0.0, true, 1.0);
#endif

	g_iJockeyAttackerOffset = FindSendPropInfo("CTerrorPlayer", "m_jockeyAttacker");
	if (g_iJockeyAttackerOffset == -1) {
		SetFailState("Could not find 'CTerrorPlayer::m_jockeyAttacker' offset");
	}

	g_iZombieClassOffset = FindSendPropInfo("CTerrorPlayer", "m_zombieClass");
	if (g_iZombieClassOffset == -1) {
		SetFailState("Could not find 'CTerrorPlayer::m_zombieClass' offset");
	}
}

public Action CH_PassFilter(int iEntity1, int iEntity2, bool &bResult)
{
	if ((IsLadder(iEntity1) && IsJockeyedSurvivor(iEntity2)) || (IsLadder(iEntity2) && IsJockeyedSurvivor(iEntity1))) {
#if DEBUG
		char sClassName1[MAX_ENTITY_NAME_SIZE], sClassName2[MAX_ENTITY_NAME_SIZE];
		GetEdictClassname(iEntity1, sClassName1, sizeof(sClassName1));
		GetEdictClassname(iEntity2, sClassName2, sizeof(sClassName2));
		PrintToChatAll("iEntity1: %d (%s), iEntity2: %d (%s), fix: %s", iEntity1, sClassName1, iEntity2, sClassName2, (g_hCvarLedgeLaggerFix.BoolValue) ? "enabled" : "disabled");

		if (!g_hCvarLedgeLaggerFix.BoolValue) {
			return Plugin_Continue;
		}
#endif
		bResult = false;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

bool IsLadder(int iEntity)
{
	static char sClassName[MAX_ENTITY_NAME_SIZE];

	if (iEntity <= MaxClients || !IsValidEdict(iEntity)) {
		return false;
	}

	GetEdictClassname(iEntity, sClassName, sizeof(sClassName));
	return (StrContains(sClassName, "ladder") > 0);
}

bool IsJockeyedSurvivor(int iClient)
{
	return (iClient > 0
		&& iClient <= MaxClients
		&& IsClientInGame(iClient)
		&& GetClientTeam(iClient) == TEAM_SURVIVOR
		&& IsJockeyed(iClient));
}

bool IsJockeyed(int iSurvivor)
{
	return IsJockey(GetEntDataEnt2(iSurvivor, g_iJockeyAttackerOffset)); // GetEntDataEnt2 works faster than GetEntPropEnt
}

bool IsJockey(int iClient)
{
	return (iClient != -1
		&& IsClientInGame(iClient)
		&& GetClientTeam(iClient) == TEAM_INFECTED
		&& GetEntData(iClient, g_iZombieClassOffset) == Z_JOCKEY); // GetEntDataEnt2 works faster than GetEntPropEnt
}
