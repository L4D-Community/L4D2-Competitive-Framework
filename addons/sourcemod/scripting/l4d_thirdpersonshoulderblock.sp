#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define TEAM_SPECTATORS 1
#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrorMax)
{
	/* Only load the plugin if the server is running Left 4 Dead or Left 4 Dead 2.
	 * Loading the plugin on Counter-Strike: Source or Team Fortress 2 would cause all clients to get kicked,
	 * because the thirdpersonshoulder mode and the corresponding ConVar that we check do not exist there.
	*/

	char sGameFolder[12];
	GetGameFolderName(sGameFolder, sizeof(sGameFolder));
	if (strcmp(sGameFolder, "left4dead") == 0 || strcmp(sGameFolder, "left4dead2") == 0) {
		return APLRes_Success;
	}

	strcopy(sError, iErrorMax, "Plugin only supports L4D1/2");
	return APLRes_Failure;
}

public Plugin myinfo =
{
	name = "Thirdpersonshoulder Block",
	author = "Don",
	description = "Kicks clients who enable the thirdpersonshoulder mode on L4D1/2 to prevent them from looking around corners, through walls etc.",
	version = "1.5",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	float fRand = GetRandomFloat(2.5, 3.5);
	CreateTimer(fRand, CheckClients, _, TIMER_REPEAT);
}

public Action CheckClients(Handle hTimer)
{
	int iTeam = TEAM_SPECTATORS;

	for (int iClientIndex = 1; iClientIndex <= MaxClients; iClientIndex++) {
		if (IsClientInGame(iClientIndex) && !IsFakeClient(iClientIndex)) {
			iTeam = GetClientTeam(iClientIndex);
			if (iTeam == TEAM_SURVIVORS || iTeam == TEAM_INFECTED) { // Only query clients on survivor or infected team, ignore spectators.
				QueryClientConVar(iClientIndex, "c_thirdpersonshoulder", QueryClientConVarCallback);
			}
		}
	}
}

public void QueryClientConVarCallback(QueryCookie iCookie, int iClient, ConVarQueryResult iResult, const char[] sCvarName, const char[] sCvarValue)
{
	/* If the ConVar was somehow not found on the client, is not valid or is protected, kick the client.
	 * The ConVar should always be readable unless the client is trying to prevent it from being read out.
	*/
	if (IsClientInGame(iClient) && !IsClientInKickQueue(iClient)) {
		if (iResult != ConVarQuery_Okay) {
			ChangeClientTeam(iClient, TEAM_SPECTATORS);
			PrintToChatAll("\x01\x03%N\x01 spectated due to \x04c_thirdpersonshoulder\x01 not valid or protected!", iClient);
		}
		/* If the ConVar was found on the client, but is not set to either "false" or "0",
		 * kick the client as well, as he might be using thirdpersonshoulder.
		*/
		else if (strcmp(sCvarValue, "false") != 0 && strcmp(sCvarValue, "0") != 0) {
			ChangeClientTeam(iClient, TEAM_SPECTATORS);
			PrintToChatAll("\x01\x03%N\x01 spectated due to \x04c_thirdpersonshoulder\x01, set at\x05 0\x01 to play!", iClient);
		}
	}
}
