// The z_gun_swing_vs_amt_penalty cvar is the amount of cooldown time you get
// when you are on your maximum m2 penalty. However, whilst testing I found that
// a magic number of ~0.7s was always added to this.
//
// @Forgetest: nah just "z_gun_swing_interval"
//#define COOLDOWN_EXTRA_TIME 0.7

// Sometimes the ability timer doesn't get reset if the timer interval is the
// stagger time. Use an epsilon to set it slightly before the stagger is over.
//#define STAGGER_TIME_EPS 0.1

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <l4d2util_constants>
#define LEFT4FRAMEWORK_INCLUDE 1
#include <left4framework>
#include <sdkhooks>

#define DEBUG		0
#define DURATION	0
#define TIMESTAMP	1

int
	g_iQueuedStaggerTypeOffset = -1;

ConVar
	g_hCvarMpGameMode = null,
	g_hCvarMinShovePenalty = null,
	g_hCvarMaxShovePenalty = null,
	g_hCvarShoveInterval = null,
	g_hCvarShovePenaltyAmt = null,
	g_hCvarPounceCrouchDelay = null,
	g_hCvarLeapInterval = null,
	g_hCvarPenaltyIncreaseHunter = null,
	g_hCvarPenaltyIncreaseJockey = null,
	g_hCvarPenaltyIncreaseSmoker = null;

public Plugin myinfo =
{
	name		= "L4D2 M2 Control",
	author		= "Jahze, Visor, A1m`, Forgetest",
	version		= "1.16",
	description	= "Blocks instant repounces and gives m2 penalty after a shove/deadstop",
	url 		= "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	GetOffset();

	g_hCvarPenaltyIncreaseHunter = CreateConVar("l4d2_m2_hunter_penalty", "0", "How much penalty gets added when you shove a Hunter");
	g_hCvarPenaltyIncreaseJockey = CreateConVar("l4d2_m2_jockey_penalty", "0", "How much penalty gets added when you shove a Jockey");
	g_hCvarPenaltyIncreaseSmoker = CreateConVar("l4d2_m2_smoker_penalty", "0", "How much penalty gets added when you shove a Smoker");

	g_hCvarMpGameMode = FindConVar("mp_gamemode");
	g_hCvarShoveInterval = FindConVar("z_gun_swing_interval");
	g_hCvarShovePenaltyAmt = FindConVar("z_gun_swing_vs_amt_penalty");
	g_hCvarPounceCrouchDelay = FindConVar("z_pounce_crouch_delay");
	g_hCvarLeapInterval = FindConVar("z_leap_interval");

	HookEvent("player_shoved", Event_PlayerShoved);

	g_hCvarMpGameMode.AddChangeHook(MpGameMode_Changed);
}

void GetOffset()
{
	int iStaggerDistOffset = FindSendPropInfo("CTerrorPlayer", "m_staggerDist");
	if (iStaggerDistOffset == -1) {
		SetFailState("Could not find offset: CTerrorPlayer->m_staggerDist");
	}

	//Member: m_staggerDist (offset 12820) (type float) (bits 0) (NoScale|CoordMP)
	//m_iQueuedStaggerType offset 12824 type int
	//CTerrorPlayer->m_iQueuedStaggerType
	g_iQueuedStaggerTypeOffset = iStaggerDistOffset + 4;
}

public void OnMapStart()
{
	GetCvarType();
}

public void MpGameMode_Changed(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	GetCvarType();
}

/* Original game code:
if ( z_gun_swing_vs_cooldown.GetFloat != 0.0 )
{
	if ( CTerrorGameRules::IsCoopMode() )
		v20 = z_gun_swing_coop_min_penalty.GetFloat();
	else
		v20 = z_gun_swing_vs_min_penalty.GetFloat();

	if ( CTerrorGameRules::IsCoopMode() )
		v21 = z_gun_swing_coop_max_penalty.GetFloat();
	else
		v21 = z_gun_swing_vs_max_penalty.GetFloat();
	...
}
*/
void GetCvarType()
{
	char sGameMode[64];
	g_hCvarMpGameMode.GetString(sGameMode, sizeof(sGameMode));

	if (L4D_IsCoopMode()) {
		g_hCvarMinShovePenalty = FindConVar("z_gun_swing_coop_min_penalty");
		g_hCvarMaxShovePenalty = FindConVar("z_gun_swing_coop_max_penalty");
		return;
	}

	g_hCvarMinShovePenalty = FindConVar("z_gun_swing_vs_min_penalty");
	g_hCvarMaxShovePenalty = FindConVar("z_gun_swing_vs_max_penalty");
}

public void Event_PlayerShoved(Event hEvent, const char[] eEventName, bool bDontBroadcast)
{
	int iShover = GetClientOfUserId(hEvent.GetInt("attacker"));
	if (iShover < 1 || GetClientTeam(iShover) != L4D2Team_Survivor) {
		return;
	}

	if (GetEntProp(iShover, Prop_Send, "m_bAdrenalineActive", 1) > 0) {
		return;
	}

	int iShoverWeapon = GetEntPropEnt(iShover, Prop_Send, "m_hActiveWeapon");
	if (iShoverWeapon == -1) {
		return;
	}

	int iShovee = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iShovee < 1 || GetClientTeam(iShovee) != L4D2Team_Infected) {
		return;
	}

	int iPenaltyIncrease = 0;
	int iZClass = GetEntProp(iShovee, Prop_Send, "m_zombieClass");

	switch (iZClass) {
		case L4D2Infected_Hunter: {
			iPenaltyIncrease = g_hCvarPenaltyIncreaseHunter.IntValue;
		}
		case L4D2Infected_Jockey: {
			iPenaltyIncrease = g_hCvarPenaltyIncreaseJockey.IntValue;
		}
		case L4D2Infected_Smoker: {
			iPenaltyIncrease = g_hCvarPenaltyIncreaseSmoker.IntValue;
		}
		default: {
			return;
		}
	}

	int iMinPenalty = g_hCvarMinShovePenalty.IntValue;
	int iMaxPenalty = g_hCvarMaxShovePenalty.IntValue;
	int iPenalty = GetEntProp(iShover, Prop_Send, "m_iShovePenalty");

	iPenalty += iPenaltyIncrease;
	if (iPenalty > iMaxPenalty) {
		iPenalty = iMaxPenalty;
	}

	float fAttackStartTime = GetEntPropFloat(iShoverWeapon, Prop_Send, "m_attackTimer", TIMESTAMP) - GetEntPropFloat(iShoverWeapon, Prop_Send, "m_attackTimer", DURATION);
	float fEps = GetGameTime() - fAttackStartTime;

	SetEntProp(iShover, Prop_Send, "m_iShovePenalty", iPenalty);
	SetEntPropFloat(iShover, Prop_Send, "m_flNextShoveTime", CalcNextShoveTime(iPenalty, iMinPenalty, iMaxPenalty) - fEps);

	if (iZClass == L4D2Infected_Smoker) {
		return;
	}

#if DEBUG
	PrintToChatAll("[Event_PlayerShoved] iShovee: %N SDKHook_PostThinkPost", iShovee);
#endif

	//Seems to have a double hook if the player hits the infected 2 times with the butt
	SDKUnhook(iShovee, SDKHook_PostThinkPost, Hook_PostThinkPost);
	SDKHook(iShovee, SDKHook_PostThinkPost, Hook_PostThinkPost);
}

public void Hook_PostThinkPost(int iClient)
{
	if (GetClientTeam(iClient) != L4D2Team_Infected
		|| !IsPlayerAlive(iClient)
		|| GetEntProp(iClient, Prop_Send, "m_isGhost", 1) > 0
	) {
		#if DEBUG
			PrintToChatAll("[Hook_PostThinkPost] Client: %N not infected or ghost or not alive!", iClient);
		#endif

		SDKUnhook(iClient, SDKHook_PostThinkPost, Hook_PostThinkPost);
		return;
	}

	if (IsPlayerStaggering(iClient)) {
		#if DEBUG
			PrintToChatAll("[Hook_PostThinkPost] Client: %N is player staggering", iClient);
		#endif

		return; //waiting for it to end to set the ability timer 'm_nextActivationTimer'
	}

	float fDuration = -1.0;
	bool bIsValidInfected = false;

	switch (GetEntProp(iClient, Prop_Send, "m_zombieClass")) {
		case L4D2Infected_Hunter: {
			fDuration = g_hCvarPounceCrouchDelay.FloatValue;
			bIsValidInfected = (GetEntPropEnt(iClient, Prop_Send, "m_pounceVictim") == -1);

			#if DEBUG
				PrintToChatAll("[Hook_PostThinkPost] Client: %N is hunter, m_pounceVictim: %d!", iClient, GetEntPropEnt(iClient, Prop_Send, "m_pounceVictim"));
			#endif
		}
		case L4D2Infected_Jockey: {
			fDuration = g_hCvarLeapInterval.FloatValue;
			bIsValidInfected = (GetEntPropEnt(iClient, Prop_Send, "m_jockeyVictim") == -1);

			#if DEBUG
				PrintToChatAll("[Hook_PostThinkPost] Client: %N is jockey, m_jockeyVictim: %d!", iClient, GetEntPropEnt(iClient, Prop_Send, "m_jockeyVictim"));
			#endif
		}
	}

	if (!bIsValidInfected) {
		#if DEBUG
			int iZClass = GetEntProp(iClient, Prop_Send, "m_zombieClass");
			PrintToChatAll("[Hook_PostThinkPost] Client: %N attacks a survivor or invalid zclass: %d (%s)!", iClient, iZClass, L4D2_InfectedNames[iZClass]);
		#endif

		SDKUnhook(iClient, SDKHook_PostThinkPost, Hook_PostThinkPost);
		return;
	}

	SetActivationTimer(iClient, fDuration);

	SDKUnhook(iClient, SDKHook_PostThinkPost, Hook_PostThinkPost);
}

void SetActivationTimer(int iClient, float fDuration)
{
	int iAbility = GetEntPropEnt(iClient, Prop_Send, "m_customAbility");
	if (iAbility == -1) {
		#if DEBUG
			PrintToChatAll("[SetActivationTimer] Client: %N invalid ability!", iClient);
		#endif

		return;
	}

	/*
	 * Table: m_nextActivationTimer (offset 1104) (type DT_CountdownTimer)
	 *	Member: m_duration (offset 4) (type float) (bits 0) (NoScale)
	 *	Member: m_timestamp (offset 8) (type float) (bits 0) (NoScale)
	*/

	float fGetTimestamp = GetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", TIMESTAMP);
	float fSetTimestamp = GetGameTime() + fDuration;

	//If the timer has been activated and the new value is greater than the old one.
	if (fGetTimestamp > 0.0 && fSetTimestamp <= fGetTimestamp) {
		#if DEBUG
			PrintToChatAll("[SetActivationTimer] Client: %N the current ability timer is greater than the one that will be set! current: %f, set: %f!", iClient, fGetTimestamp, fSetTimestamp);
		#endif

		return;
	}

	SetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", fDuration, DURATION);
	SetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", fSetTimestamp, TIMESTAMP);

#if DEBUG
	PrintToChatAll("[SetActivationTimer] Client: %N reset ability timer! Set: m_duration - %f, m_timestamp - %f!", iClient, fDuration, GetGameTime() + fDuration);
#endif
}

bool IsPlayerStaggering(int iClient)
{
	static float fStgDist2, vStgDist[3], vOrigin[3];

	if (GetEntData(iClient, g_iQueuedStaggerTypeOffset, 4) != -1) {
		return true;
	}

	float fStaggerTimestamp = GetEntPropFloat(iClient, Prop_Send, "m_staggerTimer", TIMESTAMP);
	if (fStaggerTimestamp <= 0.0 || GetGameTime() >= fStaggerTimestamp) {
		return false;
	}

	GetEntPropVector(iClient, Prop_Send, "m_staggerStart", vStgDist);
	GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", vOrigin);
	fStgDist2 = GetEntPropFloat(iClient, Prop_Send, "m_staggerDist");

	return (GetVectorDistance(vStgDist, vOrigin) <= fStgDist2);
}

float CalcNextShoveTime(int iCurrentPenalty, int iMinPenalty, int iMaxPenalty)
{
	float fRatio = 0.0;
	if (iCurrentPenalty >= iMinPenalty) {
		fRatio = ClampFloat(float(iCurrentPenalty - iMinPenalty) / float(iMaxPenalty - iMinPenalty), 0.0, 1.0);
	}

	float fDuration = fRatio * g_hCvarShovePenaltyAmt.FloatValue;
	float fReturn = GetGameTime() + fDuration + g_hCvarShoveInterval.FloatValue;

	return fReturn;
}

float ClampFloat(float fInc, float fLow, float fHigh)
{
	return (fInc > fHigh) ? fHigh : ((fInc < fLow) ? fLow : fInc);
}
