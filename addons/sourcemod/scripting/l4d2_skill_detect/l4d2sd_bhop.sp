#if defined _L4D2SD_BHOP_INCLUDED_
	#endinput
#endif
#define _L4D2SD_BHOP_INCLUDED_

#define HOP_CHECK_TIME			0.1
#define HOPEND_CHECK_TIME		0.1			// after streak end (potentially) detected, to check for realz?
#define HOP_ACCEL_THRESH		0.01		// bhop speed increase must be higher than this for it to count as part of a hop streak

static bool
	g_bIsHopping[MAXPLAYERS + 1],			// currently in a hop streak
	g_bHopCheck[MAXPLAYERS + 1];			// flag to check whether a hopstreak has ended (if on ground for too long.. ends)

static int
	g_iHops[MAXPLAYERS + 1];				// amount of hops in streak

static float
	g_fLastHop[MAXPLAYERS + 1][3],			// velocity vector of last jump
	g_fHopTopVelocity[MAXPLAYERS + 1];		// maximum velocity in hopping streak

static Handle
	g_hForwardBHopStreak = null;

static ConVar
	g_hCvarBHopMinStreak = null,			// cvar this many hops in a row+ = streak
	g_hCvarBHopMinInitSpeed = null,			// cvar lower than this and the first jump won't be seen as the start of a streak
	g_hCvarBHopContSpeed = null;			// cvar

void Bhop_AskPluginLoad2()
{
	g_hForwardBHopStreak = CreateGlobalForward("OnBunnyHopStreak", ET_Event, Param_Cell, Param_Cell, Param_Float);
}

void Bhop_OnPluginStart()
{
	g_hCvarBHopMinStreak = CreateConVar("sm_skill_bhopstreak", "3", "The lowest bunnyhop streak that will be reported.", _, true, 0.0, false);
	g_hCvarBHopMinInitSpeed = CreateConVar("sm_skill_bhopinitspeed", "150", "The minimal speed of the first jump of a bunnyhopstreak (0 to allow 'hops' from standstill).", _, true, 0.0, false);
	g_hCvarBHopContSpeed = CreateConVar("sm_skill_bhopkeepspeed", "300", "The minimal speed at which hops are considered succesful even if not speed increase is made.", _, true, 0.0, false);

	HookEvent("round_start", Bhop_Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_jump_apex", Bhop_Event_PlayerJumpApex, EventHookMode_Post);
	HookEvent("player_jump", Bhop_Event_PlayerJumped, EventHookMode_Post);
}

public void Bhop_Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++) {
		g_bIsHopping[i] = false;
	}
}

public void Bhop_Event_PlayerJumpApex(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if (g_bIsHopping[iClient]) {
		float fVel[3];
		GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fVel);
		fVel[2] = 0.0;
		float fLength = GetVectorLength(fVel);

		if (fLength > g_fHopTopVelocity[iClient]) {
			g_fHopTopVelocity[iClient] = fLength;
		}
	}
}

public void Bhop_Event_PlayerJumped(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || GetClientTeam(iClient) != L4D2Team_Survivor) {
		return;
	}

	// could be the start or part of a hopping streak
	float fPos[3], fVel[3];
	GetClientAbsOrigin(iClient, fPos);
	GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fVel);
	fVel[2] = 0.0; // safeguard

	float fLengthNew, fLengthOld;
	fLengthNew = GetVectorLength(fVel);

	g_bHopCheck[iClient] = false;

	if (!g_bIsHopping[iClient]) {
		if (fLengthNew >= GetConVarFloat(g_hCvarBHopMinInitSpeed)) {
			// starting potential hop streak
			g_fHopTopVelocity[iClient] = fLengthNew;
			g_bIsHopping[iClient] = true;
			g_iHops[iClient] = 0;
		}
	} else {
		// check for hopping streak
		fLengthOld = GetVectorLength(g_fLastHop[iClient]);

		// if they picked up speed, count it as a hop, otherwise, we're done hopping
		if (fLengthNew - fLengthOld > HOP_ACCEL_THRESH || fLengthNew >= GetConVarFloat(g_hCvarBHopContSpeed)) {
			g_iHops[iClient]++;

			// this should always be the case...
			if (fLengthNew > g_fHopTopVelocity[iClient]) {
				g_fHopTopVelocity[iClient] = fLengthNew;
			}

			//PrintToChat(iClient, "bunnyhop %i: speed: %.1f / increase: %.1f", g_iHops[iClient], fLengthNew, fLengthNew - fLengthOld);
		} else {
			g_bIsHopping[iClient] = false;

			if (g_iHops[iClient]) {
				HandleBHopStreak(iClient, g_iHops[iClient], g_fHopTopVelocity[iClient]);
				g_iHops[iClient] = 0;
			}
		}
	}

	g_fLastHop[iClient][0] = fVel[0];
	g_fLastHop[iClient][1] = fVel[1];
	g_fLastHop[iClient][2] = fVel[2];

	if (g_iHops[iClient] != 0) {
		// check when the player returns to the ground
		CreateTimer(HOP_CHECK_TIME, Timer_CheckHop, iClient, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_CheckHop(Handle hTimer, any client)
{
	// player back to ground = end of hop (streak)?
	if (!IS_VALID_INGAME(client) || !IsPlayerAlive(client)) {
		// streak stopped by dying / teamswitch / disconnect?
		return Plugin_Stop;
	} else if (GetEntityFlags(client) & FL_ONGROUND) {
		float fVel[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);
		fVel[2] = 0.0; // safeguard

		//PrintToChatAll("grounded %i: vel length: %.1f", client, GetVectorLength(fVel));

		g_bHopCheck[client] = true;
		CreateTimer(HOPEND_CHECK_TIME, Timer_CheckHopStreak, client, TIMER_FLAG_NO_MAPCHANGE);

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Timer_CheckHopStreak(Handle hTimer, any client)
{
	if (!IS_VALID_INGAME(client) || !IsPlayerAlive(client)) {
		return Plugin_Continue; 
	}

	// check if we have any sort of hop streak, and report
	if (g_bHopCheck[client] && g_iHops[client]) {
		HandleBHopStreak(client, g_iHops[client], g_fHopTopVelocity[client]);
		g_bIsHopping[client] = false;
		g_iHops[client] = 0;
		g_fHopTopVelocity[client] = 0.0;
	}

	g_bHopCheck[client] = false;
	return Plugin_Continue;
}

// bhaps
static void HandleBHopStreak(int survivor, int streak, float maxVelocity)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardBHopStreak);
	Call_PushCell(survivor);
	Call_PushCell(streak);
	Call_PushFloat(maxVelocity);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_BHOPSTREAK 
		&& IS_VALID_INGAME(survivor) && !IsFakeClient(survivor) && streak >= GetConVarInt(g_hCvarBHopMinStreak)
	) {
		CPrintToChat(survivor, "{green}★ {olive}You {default}got {blue}%i bunnyhop%s {default}in a row ({blue}top speed: {olive}%.1f{default})", \
										streak, (streak > 1) ? "s" : "", maxVelocity);
	}
}
