#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#define DEBUG 0

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

int g_iIsGhostOffset = -1;

public Plugin myinfo =
{
	name = "L4D2 Ghost-Cheat Preventer",
	author = "Sir",
	description = "Don't broadcast Infected entities to Survivors while in ghost mode, disabling them from hooking onto the entities with 3rd party programs.",
	version = "1.2.1",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	g_iIsGhostOffset = FindSendPropInfo("CTerrorPlayer", "m_isGhost");
	if (g_iIsGhostOffset == -1) {
		SetFailState("Could not find 'CTerrorPlayer::m_isGhost' offset");
	}

	for (int iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient)) {
			OnClientPutInServer(iClient);
		}
	}
}

public void OnClientPutInServer(int iClient)
{
	SDKHook(iClient, SDKHook_SetTransmit, Hook_SetTransmit);
}

public Action Hook_SetTransmit(int iEntity, int iClient)
{
	/**
	 * By default Valve still transmits the entities to Survivors, even when not in sight or in ghost mode.
	 * Detecting if a player is actually in someone's sight is likely impossible to implement without issues,
	 * but blocking ghosts from being transmitted has no downsides.
	 *
	 * This code will prevent 3rd party programs from hooking onto unspawned Infected.
	**/

	if (GetClientTeam(iClient) != TEAM_SURVIVOR) {
		return Plugin_Continue;
	}

	if (GetClientTeam(iEntity) != TEAM_INFECTED || GetEntData(iEntity, g_iIsGhostOffset, 1) < 1) { // GetEntData works faster than GetEntProp
		return Plugin_Continue;
	}

#if DEBUG
	PrintToChatAll("Hook_SetTransmit. entity: %N (%d), team: %d, isGhost: %d; client: %N (%d), team: %d", \
						iEntity, iEntity, GetClientTeam(iEntity), GetEntData(iEntity, g_iIsGhostOffset, 1), iClient, iClient, GetClientTeam(iClient));
#endif

	return Plugin_Handled; // Block info from being transmitted to client if true.
}
