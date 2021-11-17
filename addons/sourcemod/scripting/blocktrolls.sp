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
#include <l4d2util_constants>

bool
	g_bBlockCallvote = false;

int
	g_iLoadedPlayers = 0;

public Plugin myinfo =
{
	name = "Block Trolls",
	description = "Prevents calling votes while others are loading",
	author = "ProdigySim, CanadaRox, darkid",
	version = "2.2",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	AddCommandListener(Vote_Listener, "callvote");
	AddCommandListener(Vote_Listener, "vote");

	HookEvent("player_team", OnPlayerJoin);
}

public void OnMapStart()
{
	g_bBlockCallvote = true;
	g_iLoadedPlayers = 0;

	CreateTimer(40.0, Timer_EnableCallvote, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnPlayerJoin(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (hEvent.GetInt("oldteam") == 0) {
		g_iLoadedPlayers++;

		if (g_iLoadedPlayers == 6) {
			g_bBlockCallvote = false;
		}
	}
}

public Action Vote_Listener(int iClient, const char[] sCommand, int iArgc)
{
	if (g_bBlockCallvote) {
		ReplyToCommand(iClient, "[SM] Voting is not enabled until 60s into the round");
		return Plugin_Handled;
	}

	int iTeam = GetClientTeam(iClient);
	if (iClient && IsClientInGame(iClient) && (iTeam == L4D2Team_Survivor || iTeam == L4D2Team_Infected)) {
		return Plugin_Continue;
	}

	ReplyToCommand(iClient, "[SM] You must be ingame and not a spectator to vote");
	return Plugin_Handled;
}

public Action Timer_EnableCallvote(Handle hTimer)
{
	g_bBlockCallvote = false;

	return Plugin_Stop;
}
