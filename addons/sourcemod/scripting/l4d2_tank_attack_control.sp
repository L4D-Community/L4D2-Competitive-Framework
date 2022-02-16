#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#define LEFT4FRAMEWORK_INCLUDE 1
#include <left4framework>
#include <colors>

#define TEAM_INFECTED 3
#define Z_TANK 8

//throw sequences:
//48 - (not used unless tank_rock_overhead_percent is changed)

//49 - 1handed overhand (+attack2),
//50 - underhand (+use),
//51 - 2handed overhand (+reload)

int
	g_iZombieClassOffset = -1,
	g_iQueuedThrow[MAXPLAYERS + 1];

float
	throwQueuedAt[MAXPLAYERS + 1];

ConVar
	g_hBlockPunchRock = null,
	g_hBlockJumpRock = null,
	g_hOverhandOnly = null;

public Plugin myinfo =
{
	name = "Tank Attack Control",
	author = "vintik, CanadaRox, Jacob, Visor",
	description = "",
	version = "0.7.3",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	if (GetEngineVersion() != Engine_Left4Dead2) {
		strcopy(sError, iErrMax, "Plugin supports Left 4 dead 2 only!");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_iZombieClassOffset = FindSendPropInfo("CTerrorPlayer", "m_zombieClass");
	if (g_iZombieClassOffset == -1) {
		SetFailState("Failed to get offset from \"CTerrorPlayer::m_zombieClass\"");
	}

	//future-proof remake of the confogl feature (could be used with lgofnoc)
	g_hBlockPunchRock = CreateConVar("l4d2_block_punch_rock", "1", "Block tanks from punching and throwing a rock at the same time", _, true, 0.0, true, 1.0);
	g_hBlockJumpRock = CreateConVar("l4d2_block_jump_rock", "0", "Block tanks from jumping and throwing a rock at the same time", _, true, 0.0, true, 1.0);
	g_hOverhandOnly = CreateConVar("tank_overhand_only", "0", "Force tank to only throw overhand rocks.", _, true, 0.0, true, 1.0);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("tank_spawn", Event_TankSpawn);
}

public void Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) {
		g_iQueuedThrow[i] = 3;
		throwQueuedAt[i] = 0.0;
	}
}

public void Event_TankSpawn(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iTank = GetClientOfUserId(hEvent.GetInt("userid"));

	if (IsFakeClient(iTank)) {
		return;
	}

	bool bHidemessage = false;

	char sBuffer[3];
	if (GetClientInfo(iTank, "rs_hidemessage", sBuffer, sizeof(sBuffer))) {
		bHidemessage = view_as<bool>(StringToInt(sBuffer));
	}

	if (!bHidemessage && !g_hOverhandOnly.BoolValue) {
		CPrintToChat(iTank, "{blue}[{default}Tank Rock Selector{blue}]");
		CPrintToChat(iTank, "{olive}Reload {default}= {blue}2 Handed Overhand");
		CPrintToChat(iTank, "{olive}Use {default}= {blue}Underhand");
		CPrintToChat(iTank, "{olive}M2 {default}= {blue}1 Handed Overhand");
	}
}

public Action OnPlayerRunCmd(int iClient, int& iButtons, int& iImpulse, float fVel[3], float fAngles[3], int& iWeapon)
{
	if (GetClientTeam(iClient) != TEAM_INFECTED
		|| GetEntData(iClient, g_iZombieClassOffset, 4) != Z_TANK
		|| IsFakeClient(iClient)
		|| !IsPlayerAlive(iClient)
	) {
		return Plugin_Continue;
	}

	//if tank
	if ((iButtons & IN_JUMP) && ShouldCancelJump(iClient)) {
		iButtons &= ~IN_JUMP;
	}

	if (g_hOverhandOnly.BoolValue) {
		g_iQueuedThrow[iClient] = 3; // two hand overhand
	} else {
		if (iButtons & IN_RELOAD) {
			g_iQueuedThrow[iClient] = 3; //two hand overhand
			iButtons |= IN_ATTACK2;
		} else if (iButtons & IN_USE) {
			g_iQueuedThrow[iClient] = 2; //underhand
			iButtons |= IN_ATTACK2;
		} else {
			g_iQueuedThrow[iClient] = 1; //one hand overhand
		}
	}

	return Plugin_Continue;
}

public Action L4D_OnCThrowActivate(int iAbility)
{
	int iOwner = GetEntPropEnt(iAbility, Prop_Data, "m_hOwnerEntity");
	if (iOwner == -1) {
		return Plugin_Continue;
	}

	if (g_hBlockPunchRock.BoolValue && (GetClientButtons(iOwner) & IN_ATTACK)) {
		return Plugin_Handled;
	}

	throwQueuedAt[iOwner] = GetGameTime();

	return Plugin_Continue;
}

public Action L4D2_OnSelectTankAttack(int iClient, int &iSequence)
{
	if (iSequence > 48 && g_iQueuedThrow[iClient]) {
		//rock throw
		iSequence = g_iQueuedThrow[iClient] + 48;
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

bool ShouldCancelJump(int iClient)
{
	if (!g_hBlockJumpRock.BoolValue) {
		return false;
	}

	return (1.5 > GetGameTime() - throwQueuedAt[iClient]);
}
