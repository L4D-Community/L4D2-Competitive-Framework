#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <caster_system>

#define MAX_NETVARS_STRING_LENGTH 8

enum
{
	eSvMinCmdRate = 0,
	eSvMaxCmdRate,
	eSvMinUpdateRate,
	eSvMaxUpdateRate,
	eSvMinRate,
	eSvMaxRate,
	eSvClientMinInterpRatio,
	eSvClientMaxInterpRatio,

	eNetVars_Size
};

enum
{
	L4D2Team_None = 0,
	L4D2Team_Spectator,
	L4D2Team_Survivor,
	L4D2Team_Infected
};

bool readyUpIsAvailable = false;

char g_sNetVarsValues[eNetVars_Size][MAX_NETVARS_STRING_LENGTH];

float fLastAdjusted[MAXPLAYERS + 1] = {0.0, ...};

ConVar
	sv_mincmdrate = null,
	sv_maxcmdrate = null,
	sv_minupdaterate = null,
	sv_maxupdaterate = null,
	sv_minrate = null,
	sv_maxrate = null,
	sv_client_min_interp_ratio = null,
	sv_client_max_interp_ratio = null;

public Plugin myinfo =
{
	name = "Lightweight Spectating",
	author = "Visor",
	description = "Forces low rates on spectators",
	version = "1.3",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	sv_mincmdrate = FindConVar("sv_mincmdrate");
	sv_maxcmdrate = FindConVar("sv_maxcmdrate");
	sv_minupdaterate = FindConVar("sv_minupdaterate");
	sv_maxupdaterate = FindConVar("sv_maxupdaterate");
	sv_minrate = FindConVar("sv_minrate");
	sv_maxrate = FindConVar("sv_maxrate");
	sv_client_min_interp_ratio = FindConVar("sv_client_min_interp_ratio");
	sv_client_max_interp_ratio = FindConVar("sv_client_max_interp_ratio");

	HookEvent("player_team", Event_OnTeamChange);
}

public void OnPluginEnd()
{
	sv_minupdaterate.SetString(g_sNetVarsValues[eSvMinUpdateRate]);
	sv_mincmdrate.SetString(g_sNetVarsValues[eSvMinCmdRate]);
}

public void OnAllPluginsLoaded()
{
	readyUpIsAvailable = LibraryExists("caster_system");
}

public void OnLibraryRemoved(const char[] sPluginName)
{
	if (strcmp(sPluginName, "caster_system", true) == 0) {
		readyUpIsAvailable = false;
	}
}

public void OnLibraryAdded(const char[] sPluginName)
{
	if (strcmp(sPluginName, "caster_system", true) == 0) {
		readyUpIsAvailable = true;
	}
}

public void OnConfigsExecuted()
{
	sv_mincmdrate.GetString(g_sNetVarsValues[eSvMinCmdRate], MAX_NETVARS_STRING_LENGTH);
	sv_maxcmdrate.GetString(g_sNetVarsValues[eSvMaxCmdRate], MAX_NETVARS_STRING_LENGTH);
	sv_minupdaterate.GetString(g_sNetVarsValues[eSvMinUpdateRate], MAX_NETVARS_STRING_LENGTH);
	sv_maxupdaterate.GetString(g_sNetVarsValues[eSvMaxUpdateRate], MAX_NETVARS_STRING_LENGTH);
	sv_minrate.GetString(g_sNetVarsValues[eSvMinRate], MAX_NETVARS_STRING_LENGTH);
	sv_maxrate.GetString(g_sNetVarsValues[eSvMaxRate], MAX_NETVARS_STRING_LENGTH);
	sv_client_min_interp_ratio.GetString(g_sNetVarsValues[eSvClientMinInterpRatio], MAX_NETVARS_STRING_LENGTH);
	sv_client_max_interp_ratio.GetString(g_sNetVarsValues[eSvClientMaxInterpRatio], MAX_NETVARS_STRING_LENGTH);

	sv_minupdaterate.SetInt(30);
	sv_mincmdrate.SetInt(30);
}

public void OnClientPutInServer(int iClient)
{
	fLastAdjusted[iClient] = 0.0;
}

public void Event_OnTeamChange(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	CreateTimer(10.0, TimerAdjustRates, iClient, TIMER_FLAG_NO_MAPCHANGE);
}

public Action TimerAdjustRates(Handle hTimer, int iClient)
{
	AdjustRates(iClient);

	return Plugin_Stop;
}

public void OnClientSettingsChanged(int iClient)
{
	AdjustRates(iClient);
}

void AdjustRates(int iClient)
{
	if (!IsValidClient(iClient)) {
		return;
	}

	float fTime = GetEngineTime();

	if (fLastAdjusted[iClient] < fTime - 1.0) {
		fLastAdjusted[iClient] = fTime;

		int iTeam = GetClientTeam(iClient);

		if (iTeam == L4D2Team_Survivor
			|| iTeam == L4D2Team_Infected
			|| (readyUpIsAvailable && IsClientCaster(iClient))
		) {
			ResetRates(iClient);
		} else if (iTeam == L4D2Team_Spectator) {
			SetSpectatorRates(iClient);
		}
	}
}

void SetSpectatorRates(int iClient)
{
	sv_mincmdrate.ReplicateToClient(iClient, "30");
	sv_maxcmdrate.ReplicateToClient(iClient, "30");
	sv_minupdaterate.ReplicateToClient(iClient, "30");
	sv_maxupdaterate.ReplicateToClient(iClient, "30");
	sv_minrate.ReplicateToClient(iClient, "10000");
	sv_maxrate.ReplicateToClient(iClient, "10000");

	SetClientInfo(iClient, "cl_updaterate", "30");
	SetClientInfo(iClient, "cl_cmdrate", "30");
}

void ResetRates(int iClient)
{
	sv_mincmdrate.ReplicateToClient(iClient, g_sNetVarsValues[eSvMinCmdRate]);
	sv_maxcmdrate.ReplicateToClient(iClient, g_sNetVarsValues[eSvMaxCmdRate]);
	sv_minupdaterate.ReplicateToClient(iClient, g_sNetVarsValues[eSvMinUpdateRate]);
	sv_maxupdaterate.ReplicateToClient(iClient, g_sNetVarsValues[eSvMaxUpdateRate]);
	sv_minrate.ReplicateToClient(iClient, g_sNetVarsValues[eSvMinRate]);
	sv_maxrate.ReplicateToClient(iClient, g_sNetVarsValues[eSvMaxRate]);

	SetClientInfo(iClient, "cl_updaterate", g_sNetVarsValues[eSvMaxUpdateRate]);
	SetClientInfo(iClient, "cl_cmdrate", g_sNetVarsValues[eSvMaxCmdRate]);
}

bool IsValidClient(int iClient)
{
	return (iClient > 0
		&& iClient <= MaxClients
		&& IsClientInGame(iClient)
		&& !IsFakeClient(iClient));
}
