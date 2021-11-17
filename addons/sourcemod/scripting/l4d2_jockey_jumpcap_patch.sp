#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

#define Z_JOCKEY 5
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define GAMEDATA "l4d2_si_ability"

int g_iCleapOnTouchOffset = -1;

Handle g_hCLeap_OnTouch = null;

bool g_bBlockJumpCap[MAXPLAYERS + 1] = {false, ...};

public Plugin myinfo =
{
	name = "L4D2 Jockey Jump-Cap Patch",
	author = "Visor, A1m`",
	description = "Prevent Jockeys from being able to land caps with non-ability jumps in unfair situations",
	version = "1.5",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	InitGameData();

	g_hCLeap_OnTouch = DHookCreate(g_iCleapOnTouchOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, CLeap_OnTouch);
	DHookAddParam(g_hCLeap_OnTouch, HookParamType_CBaseEntity);

	HookEvent("round_start", Event_Reset, EventHookMode_PostNoCopy);
	//HookEvent("round_end", Event_Reset, EventHookMode_PostNoCopy);
	HookEvent("player_shoved", Event_PlayerShoved);
}

void InitGameData()
{
	Handle hGamedata = LoadGameConfigFile(GAMEDATA);

	if (!hGamedata) {
		SetFailState("Gamedata '%s.txt' missing or corrupt.", GAMEDATA);
	}

	g_iCleapOnTouchOffset = GameConfGetOffset(hGamedata, "CBaseAbility::OnTouch");
	if (g_iCleapOnTouchOffset == -1) {
		SetFailState("Failed to get offset 'CBaseAbility::OnTouch'.");
	}

	delete hGamedata;
}

public void Event_Reset(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) {
		g_bBlockJumpCap[i] = false;
	}
}

public void OnEntityCreated(int iEntity, const char[] sClassName)
{
	if (strcmp(sClassName, "ability_leap") == 0) {
		DHookEntity(g_hCLeap_OnTouch, false, iEntity);
	}
}

public void Event_PlayerShoved(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iShovee = GetClientOfUserId(hEvent.GetInt("userid"));
	int iShover = GetClientOfUserId(hEvent.GetInt("attacker"));

	if (IsSurvivor(iShover) && IsJockey(iShovee)) {
		g_bBlockJumpCap[iShovee] = true;
		CreateTimer(3.0, Timer_ResetJumpcapState, iShovee, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_ResetJumpcapState(Handle hTimer, int iJockey)
{
	g_bBlockJumpCap[iJockey] = false;
	return Plugin_Stop;
}

public MRESReturn CLeap_OnTouch(int iAbility, Handle hParams)
{
	int iJockey = GetEntPropEnt(iAbility, Prop_Send, "m_owner");
	if (IsJockey(iJockey) && !IsFakeClient(iJockey)) {
		int iSurvivor = DHookGetParam(hParams, 1);
		if (IsSurvivor(iSurvivor)) {
			if (!IsAbilityActive(iAbility) && g_bBlockJumpCap[iJockey]) {
				return MRES_Supercede;
			}
		}
	}

	return MRES_Ignored;
}

bool IsAbilityActive(int iAbility)
{
	return (GetEntProp(iAbility, Prop_Send, "m_isLeaping", 1) > 0);
}

bool IsJockey(int iClient)
{
	return (iClient > 0
		/*&& iClient <= MaxClients*/
		&& IsClientInGame(iClient)
		&& GetClientTeam(iClient) == TEAM_INFECTED
		&& GetEntProp(iClient, Prop_Send, "m_zombieClass") == Z_JOCKEY);
}

bool IsSurvivor(int iClient)
{
	return (iClient > 0
		&& iClient <= MaxClients
		&& IsClientInGame(iClient)
		&& GetClientTeam(iClient) == TEAM_SURVIVOR);
}
