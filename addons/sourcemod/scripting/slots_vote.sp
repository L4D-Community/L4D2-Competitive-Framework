#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <colors>

#define TEAM_SPECTATOR		1
#define COLOR_PLUGIN_PREFIX	"{blue}[{default}Slots{blue}]{default}"
#define PLUGIN_PREFIX		"[Slots]"

char g_sSlots[32];

Handle g_hVote = null;

ConVar
	g_hSurvivorLimit = null,
	g_hZMaxPlayerZombies = null,
	g_hMaxSlots = null,
	g_hSvMaxPlayers = null;

public Plugin myinfo =
{
	name = "Slots?! Voter",
	description = "Slots Voter",
	author = "Sir",
	version = "1.2",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	g_hMaxSlots = CreateConVar("slots_max_slots", "30", "Maximum amount of slots you wish players to be able to vote for? (DON'T GO HIGHER THAN 30)", _, true, 1.0, true, 32.0);

	g_hSvMaxPlayers = FindConVar("sv_maxplayers");
	g_hSurvivorLimit = FindConVar("survivor_limit");
	g_hZMaxPlayerZombies = FindConVar("z_max_player_zombies");

	RegConsoleCmd("sm_slots", SlotsRequest);
}

public Action SlotsRequest(int client, int args)
{
	if (args != 1) {
		if (client == 0) {
			PrintToServer("%s Usage: sm_slots <number> | Example: sm_slots 8", PLUGIN_PREFIX);
		} else {
			CPrintToChat(client, "%s Usage: {olive}!slots {default}<{olive}number{default}> {blue}| {default}Example: {olive}!slots 8", COLOR_PLUGIN_PREFIX);
		}
		return Plugin_Handled;
	}

	char sSlots[64];
	GetCmdArg(1, sSlots, sizeof(sSlots));
	int iSlots = StringToInt(sSlots);
	
	int iMaxSlots = g_hMaxSlots.IntValue;
	if (iSlots > iMaxSlots) {
		if (client == 0) {
			PrintToServer("%s You can't limit slots above %i", PLUGIN_PREFIX, iMaxSlots);
		} else {
			CPrintToChat(client, "%s You can't limit slots above {olive}%i {default}on this Server", COLOR_PLUGIN_PREFIX, iMaxSlots);
		}
		return Plugin_Handled;
	}

	if (client == 0 || GetUserAdmin(client) != INVALID_ADMIN_ID) {
		g_hSvMaxPlayers.SetInt(iSlots);

		PrintToServer("%s Limited slots on the server to %i", PLUGIN_PREFIX, iSlots);
		CPrintToChatAll("%s {olive}Admin {default}has limited Slots to {blue}%i", COLOR_PLUGIN_PREFIX, iSlots);
		return Plugin_Handled;
	}

	if (iSlots < (g_hSurvivorLimit.IntValue + g_hZMaxPlayerZombies.IntValue)) {
		CPrintToChat(client, "%s You can't limit Slots lower than required Players.", COLOR_PLUGIN_PREFIX);
		return Plugin_Handled;
	}

	if (StartSlotVote(client, sSlots)) {
		strcopy(g_sSlots, sizeof(g_sSlots), sSlots);
		FakeClientCommand(client, "Vote Yes");
	}

	return Plugin_Handled;
}

bool StartSlotVote(int client, const char[] sSlots)
{
	if (GetClientTeam(client) == TEAM_SPECTATOR) {
		CPrintToChat(client, "%s Voting isn't allowed for spectators.", COLOR_PLUGIN_PREFIX);
		return false;
	}

	if (IsNewBuiltinVoteAllowed()) {
		int iNumPlayers = 0;
		int[] iPlayers = new int[MaxClients];

		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || IsFakeClient(i) || (GetClientTeam(i) == TEAM_SPECTATOR)) {
				continue;
			}

			iPlayers[iNumPlayers++] = i;
		}

		char sBuffer[64];
		FormatEx(sBuffer, sizeof(sBuffer), "Limit Slots to '%s'?", sSlots);

		g_hVote = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		SetBuiltinVoteArgument(g_hVote, sBuffer);
		SetBuiltinVoteInitiator(g_hVote, client);
		SetBuiltinVoteResultCallback(g_hVote, SlotVoteResultHandler);
		DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, 20);
		return true;
	}

	CPrintToChat(client, "%s Vote cannot be started now.", COLOR_PLUGIN_PREFIX);
	return false;
}

public void SlotVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				int iSlots = StringToInt(g_sSlots, 10);
				g_hSvMaxPlayers.SetInt(iSlots);

				DisplayBuiltinVotePass(vote, "Limiting Slots...");
				return;
			}
		}
	}

	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void VoteActionHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action) {
		case BuiltinVoteAction_End: {
			delete vote;
			g_hVote = null;
		}
		case BuiltinVoteAction_Cancel: {
			DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
		}
	}
}
