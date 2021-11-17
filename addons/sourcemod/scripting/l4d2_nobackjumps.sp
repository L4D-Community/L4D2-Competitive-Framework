#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

#define Z_HUNTER 3
#define TEAM_INFECTED 3

#define GAMEDATA "l4d2_si_ability"

int
	g_iLungeActivateAbilityOffset = -1;

Handle
	g_hCLunge_ActivateAbility = null;

float
	g_fSuspectedBackjump[MAXPLAYERS + 1] = {0.0, ...};

public Plugin myinfo =
{
	name = "L4D2 No Backjump",
	author = "Visor, A1m`",
	description = "Look at the title",
	version = "1.3",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	InitGameData();

	g_hCLunge_ActivateAbility = DHookCreate(g_iLungeActivateAbilityOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, CLunge_ActivateAbility);

	HookEvent("round_start", ResetEvent, EventHookMode_PostNoCopy);
	//HookEvent("round_end", ResetEvent, EventHookMode_PostNoCopy);

	HookEvent("player_jump", OnPlayerJump, EventHookMode_Post);
}

void InitGameData()
{
	Handle hGamedata = LoadGameConfigFile(GAMEDATA);

	if (!hGamedata) {
		SetFailState("Gamedata '%s.txt' missing or corrupt.", GAMEDATA);
	}

	g_iLungeActivateAbilityOffset = GameConfGetOffset(hGamedata, "CBaseAbility::ActivateAbility");
	if (g_iLungeActivateAbilityOffset == -1) {
		SetFailState("Failed to get offset 'CBaseAbility::ActivateAbility'.");
	}

	delete hGamedata;
}

public void OnEntityCreated(int iEntity, const char[] sClassName)
{
	if (strcmp(sClassName, "ability_lunge") == 0) {
		DHookEntity(g_hCLunge_ActivateAbility, false, iEntity);
	}
}

public void ResetEvent(Event hEvent, const char[] eEventName, bool bDontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) {
		g_fSuspectedBackjump[i] = 0.0;
	}
}

public void OnPlayerJump(Event hEvent, const char[] eEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if (IsHunter(iClient) && !IsGhost(iClient) && IsOutwardJump(iClient)) {
		g_fSuspectedBackjump[iClient] = GetGameTime();
	}
}

public MRESReturn CLunge_ActivateAbility(int ability)
{
	int iClient = GetEntPropEnt(ability, Prop_Send, "m_owner");
	if (g_fSuspectedBackjump[iClient] + 1.5 > GetGameTime()) {
		//PrintToChat(iClient, "\x01[SM] No \x03backjumps\x01, sorry");
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

bool IsOutwardJump(int iClient)
{
	bool bIsGround = ((GetEntityFlags(iClient) & FL_ONGROUND) != 0);
	bool bIsAttemptingToPounce = (GetEntProp(iClient, Prop_Send, "m_isAttemptingToPounce", 1) > 0);

	return (!bIsAttemptingToPounce && !bIsGround);
}

bool IsHunter(int iClient)
{
	return (iClient > 0
		/*&& iClient <= MaxClients*/ //GetClientOfUserId return 0, if not found
		&& IsClientInGame(iClient)
		&& GetClientTeam(iClient) == TEAM_INFECTED
		&& GetEntProp(iClient, Prop_Send, "m_zombieClass") == Z_HUNTER
		&& IsPlayerAlive(iClient));
}

bool IsGhost(int iClient)
{
	return (GetEntProp(iClient, Prop_Send, "m_isGhost", 1) > 0);
}
