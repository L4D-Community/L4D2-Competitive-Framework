#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

ConVar g_hCvarMaxZombies = null;

public Plugin myinfo =
{
	name = "Character Fix",
	author = "someone",
	version = "0.2",
	description = "Fixes character change exploit in 1v1, 2v2, 3v3",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	g_hCvarMaxZombies = FindConVar("z_max_player_zombies");

	AddCommandListener(TeamCmd, "jointeam");
}

public Action TeamCmd(int iClient, const char[] sCommand, int iArgc)
{
	if (iClient == 0 || iArgc < 1) {
		return Plugin_Continue;
	}

	char sBuffer[32];
	GetCmdArg(1, sBuffer, sizeof(sBuffer));
	int iNewTeam = StringToInt(sBuffer);

	if (GetClientTeam(iClient) == TEAM_SURVIVOR
		&& (strcmp("Infected", sBuffer, false) == 0
		|| iNewTeam == TEAM_INFECTED)
	) {
		if (GetInfectedCount() >= g_hCvarMaxZombies.IntValue) {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

int GetInfectedCount()
{
	int iZombies = 0;

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_INFECTED) {
			iZombies++;
		}
	}

	return iZombies;
}
