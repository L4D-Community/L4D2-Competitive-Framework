#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>

#define SAYTEXT_MAX_LENGTH 192

enum
{
	L4D2Team_None = 0,
	L4D2Team_Spectator,
	L4D2Team_Survivor,
	L4D2Team_Infected
};

ConVar
	hCvarCvarChange = null,
	hCvarNameChange = null,
	hCvarSpecNameChange = null,
	hCvarSpecSeeChat = null;

public Plugin myinfo =
{
	name = "BeQuiet",
	author = "Sir",
	description = "Please be Quiet!",
	version = "1.4",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	hCvarCvarChange = CreateConVar("bq_cvar_change_suppress", "1", "Silence Server Cvars being changed, this makes for a clean chat with no disturbances.");
	hCvarNameChange = CreateConVar("bq_name_change_suppress", "1", "Silence Player name Changes.");
	hCvarSpecNameChange = CreateConVar("bq_name_change_spec_suppress", "1", "Silence Spectating Player name Changes.");
	hCvarSpecSeeChat = CreateConVar("bq_show_player_team_chat_spec", "1", "Show Spectators Survivors and Infected Team chat?");

	AddCommandListener(Say_Callback, "say");
	AddCommandListener(TeamSay_Callback, "say_team");

	HookEvent("server_cvar", Event_ServerConVar, EventHookMode_Pre);
	HookEvent("player_changename", Event_NameChange, EventHookMode_Pre);
}

public Action Say_Callback(int client, char[] command, int args)
{
	if (client == 0) {
		return Plugin_Continue;
	}

	char sayWord[SAYTEXT_MAX_LENGTH];
	GetCmdArg(1, sayWord, sizeof(sayWord));

	if (sayWord[0] == '!' || sayWord[0] == '/') {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action TeamSay_Callback(int client, char[] command, int args)
{
	// Regardless of max usermessage size,
	// TextMsg has a limit of 128 characters for the actual message on the client side and 192 for SayText and SayText2.
	// (see hud_basechat in the sdk)

	char sChat[SAYTEXT_MAX_LENGTH];
	GetCmdArg(1, sChat, sizeof(sChat));

	if (sChat[0] == '!' || sChat[0] == '/') {
		return Plugin_Handled;
	}

	if (!hCvarSpecSeeChat.BoolValue) {
		return Plugin_Continue;
	}

	int iTeam = GetClientTeam(client);
	if (iTeam < L4D2Team_Survivor) {
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == L4D2Team_Spectator) {
			if (iTeam == L4D2Team_Survivor) {
				CPrintToChat(i, "{default}(Survivor) {blue}%N {default}: %s", client, sChat);
			} else {
				CPrintToChat(i, "{default}(Infected) {red}%N {default}: %s", client, sChat);
			}
		}
	}

	return Plugin_Continue;
}

public Action Event_ServerConVar(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	return (hCvarCvarChange.BoolValue) ? Plugin_Handled : Plugin_Continue;
}

public Action Event_NameChange(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	if (client < 1 || !IsClientInGame(client)) {
		return Plugin_Continue;
	}

	if (GetClientTeam(client) == L4D2Team_Spectator && hCvarSpecNameChange.BoolValue) {
		return Plugin_Handled;
	} else if (hCvarNameChange.BoolValue) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}
