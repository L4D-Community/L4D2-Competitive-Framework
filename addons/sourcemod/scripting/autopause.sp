/*
	SourcePawn is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2015 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#define L4D2_DIRECT_INCLUDE 1
#include <left4framework>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>

#define MAX_STEAMID_LENGTH	64
#define TEAM_INFECTED		3
#define TEAM_SPECTATORS		1

bool
	g_bReadyUpIsAvailable = false,
	g_bRoundEnd = false;

ConVar
	g_hCvarEnabled = null,
	g_hCvarForce = null,
	g_hCvarApdebug = null;

StringMap
	g_hCrashedPlayersTrie = null;

ArrayList
	g_hInfectedPlayersArray = null;

public Plugin myinfo =
{
	name = "L4D2 Auto-pause",
	author = "Darkid, Griffin, A1m`",
	description = "When a player disconnects due to crash, automatically pause the game. When they rejoin, give them a correct spawn timer.",
	version = "2.2",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
}

public void OnPluginStart()
{
	// Suggestion by Nati: Disable for any 1v1
	g_hCvarEnabled = CreateConVar("autopause_enable", "1", "Whether or not to automatically pause when a player crashes.", _, true, 0.0, true, 1.0);
	g_hCvarForce = CreateConVar("autopause_force", "0", "Whether or not to force pause when a player crashes.", _, true, 0.0, true, 1.0);
	g_hCvarApdebug = CreateConVar("autopause_apdebug", "0", "Whether or not to debug information.", _, true, 0.0, true, 1.0);

	g_hCrashedPlayersTrie = new StringMap();
	g_hInfectedPlayersArray = new ArrayList(ByteCountToCells(MAX_STEAMID_LENGTH));

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	g_bReadyUpIsAvailable = LibraryExists("readyup");
}

public void OnLibraryRemoved(const char[] sPluginName)
{
	if (strcmp(sPluginName, "readyup") == 0) {
		g_bReadyUpIsAvailable = false;
	}
}

public void OnLibraryAdded(const char[] sPluginName)
{
	if (strcmp(sPluginName, "readyup") == 0) {
		g_bReadyUpIsAvailable = true;
	}
}

public void Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	g_hCrashedPlayersTrie.Clear();
	g_hInfectedPlayersArray.Clear();

	g_bRoundEnd = false;
}

public void Event_RoundEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	g_bRoundEnd = true;
}

// Handles players leaving and joining the infected team.
public void Event_PlayerTeam(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1) {
		return;
	}

	char sSteamId[MAX_STEAMID_LENGTH];
	GetClientAuthId(iClient, AuthId_Steam2, sSteamId, sizeof(sSteamId));
	if (strcmp(sSteamId, "BOT") == 0) {
		return;
	}

	int iIndex = g_hInfectedPlayersArray.FindString(sSteamId);
	if (hEvent.GetInt("oldteam") == TEAM_INFECTED) {
		if (iIndex != -1) {
			g_hInfectedPlayersArray.Erase(iIndex);
		}

		if (g_hCvarApdebug.BoolValue) {
			LogMessage("[AutoPause] Removed player %s from infected team.", sSteamId);
		}
	}

	if (hEvent.GetInt("team") == TEAM_INFECTED) {
		float fSpawnTime = 0.0;

		if (g_hCrashedPlayersTrie.GetValue(sSteamId, fSpawnTime)) {
			CountdownTimer cSpawnTimer = L4D2Direct_GetSpawnTimer(iClient);
			CTimer_Start(cSpawnTimer, fSpawnTime);
			g_hCrashedPlayersTrie.Remove(sSteamId);

			LogMessage("[AutoPause] Player %s rejoined, set spawn timer to %f.", sSteamId, fSpawnTime);
		} else if (iIndex == -1) {
			g_hInfectedPlayersArray.PushString(sSteamId);

			if (g_hCvarApdebug.BoolValue) {
				LogMessage("[AutoPause] Added player %s to infected team.", sSteamId);
			}
		}
	}
}

public Action Event_PlayerDisconnect(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	char sSteamId[MAX_STEAMID_LENGTH];
	hEvent.GetString("networkid", sSteamId, sizeof(sSteamId));
	if (strcmp(sSteamId, "BOT") == 0) {
		return Plugin_Continue;
	}

	// If the client has not loaded yet or does not have a team or is from the spectator team
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || !IsClientInGame(iClient) || GetClientTeam(iClient) <= TEAM_SPECTATORS) {
		return Plugin_Continue;
	}

	char sReason[128], sPlayerName[128], sTimedOut[256];
	hEvent.GetString("reason", sReason, sizeof(sReason));
	hEvent.GetString("name", sPlayerName, sizeof(sPlayerName));
	Format(sTimedOut, sizeof(sTimedOut), "%s timed out", sPlayerName);

	if (g_hCvarApdebug.BoolValue) {
		LogMessage("[AutoPause] Player %s (%s) left the game: %s", sPlayerName, sSteamId, sReason);
	}

	// If the leaving player crashed, pause.
	if (strcmp(sReason, sTimedOut) == 0 || strcmp(sReason, "No Steam logon") == 0) {
		if ((!g_bReadyUpIsAvailable || !IsInReady()) && !g_bRoundEnd && g_hCvarEnabled.BoolValue) {
			if (g_hCvarForce.BoolValue) {
				ServerCommand("sm_forcepause");
			} else {
				FakeClientCommand(iClient, "sm_pause");
			}

			CPrintToChatAll("{blue}[{default}AutoPause{blue}] {olive}%s {default}crashed.", sPlayerName);
		}
	}

	// If the leaving player was on infected, save their spawn timer.
	if (g_hInfectedPlayersArray.FindString(sSteamId) != -1) {
		CountdownTimer cSpawnTimer = L4D2Direct_GetSpawnTimer(iClient);

		if (cSpawnTimer != CTimer_Null) {
			float fTimeLeft = CTimer_GetRemainingTime(cSpawnTimer);
			g_hCrashedPlayersTrie.SetValue(sSteamId, fTimeLeft);

			LogMessage("[AutoPause] Player %s left the game with %f time until spawn.", sSteamId, fTimeLeft);
		}
	}

	return Plugin_Continue;
}
