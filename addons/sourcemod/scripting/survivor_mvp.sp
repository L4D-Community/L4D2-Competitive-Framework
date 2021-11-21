/**
	Issues:
	---------
		- Add damage received from common

	Changelog
	---------
	0.2c
		- added console output table for more stats, fixed it's display
		- fixed console display to always display each player on the survivor team

	0.1
		- fixed common MVP ranks being messed up.
		- finally worked in PluginEnabled cvar
		- made FF tracking switch to enabled automatically if brevity flag 4 is unset
		- fixed a bug that caused FF to always report as "no friendly fire" when tracking was disabled
		- adjusted formatting a bit
		- made FF stat hidden by default
		- made convars actually get tracked (doh)
		- added friendly fire tracking (sm_survivor_mvp_trackff 1/0)
		- added brevity-flags cvar for changing verbosity of MVP report (sm_survivor_mvp_brevity bitwise, as shown)
		- discount FF damage before match is live if RUP is active.
		- fixed problem with clients disconnecting before mvp report
		- improved consistency after client reconnect (name-based)
		- fixed mvp stats double showing in scavenge (round starts)
		- now shows if MVP is a bot
		- cleaned up code
		- fixed for scavenge, now shows stats for every scavenge round
		- fixed damage/kills getting recorded for infected players, skewing MVP stats
		- added rank display for non-MVP clients

	Brevity flags:
	---------
		1       leave out SI stats
		2       leave out CI stats
		4       leave out FF stats
		8       leave out rank notification
		16   (reserved)
		32      leave out percentages
		64      leave out absolutes
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <colors>
#undef REQUIRE_PLUGIN
#include <readyup>

#define MAX_ENTITY_NAME_SIZE	64

#define TEAM_SPECTATOR			1
#define TEAM_SURVIVOR			2
#define TEAM_INFECTED			3
#define FLAG_SPECTATOR			(1 << TEAM_SPECTATOR)
#define FLAG_SURVIVOR			(1 << TEAM_SURVIVOR)
#define FLAG_INFECTED			(1 << TEAM_INFECTED)

#define ZC_SMOKER				1
#define ZC_BOOMER				2
#define ZC_HUNTER				3
#define ZC_SPITTER				4
#define ZC_JOCKEY				5
#define ZC_CHARGER				6
#define ZC_WITCH				7
#define ZC_TANK					8

#define BREV_SI					1
#define BREV_CI					2
#define BREV_FF					4
#define BREV_RANK				8
//#define BREV_???				16
#define BREV_PERCENT			32
#define BREV_ABSOLUTE			64

#define CONBUFSIZE				1024
#define CONBUFSIZELARGE			4096

#define CHARTHRESHOLD			160					// detecting unicode stuff

ConVar
	hPluginEnabled = null,
	hCountTankDamage = null,						// whether we're tracking tank damage for MVP-selection
	hCountWitchDamage = null,						// whether we're tracking witch damage for MVP-selection
	hTrackFF = null,								// whether we're tracking friendly-fire damage (separate stat)
	hBrevityFlags = null,							// how verbose/brief the output should be:
	g_hGameMode = null;

bool
	bCountTankDamage,
	bCountWitchDamage,
	bTrackFF;

int
	iBrevityFlags;

char
	//sTmpString[MAX_NAME_LENGTH],					// just used because I'm not going to break my head over why string assignment parameter passing doesn't work
	sClientName[MAXPLAYERS + 1][64];				// which name is connected to the clientId?

// Basic statistics
int
	iGotKills[MAXPLAYERS + 1],						// SI kills             track for each client
	iGotCommon[MAXPLAYERS + 1],						// CI kills
	iDidDamage[MAXPLAYERS + 1],						// SI only              these are a bit redundant, but will keep anyway for now
	iDidDamageAll[MAXPLAYERS + 1],					// SI + tank + witch
	iDidDamageTank[MAXPLAYERS + 1],					// tank only
	iDidDamageWitch[MAXPLAYERS + 1],				// witch only
	iDidFF[MAXPLAYERS + 1];							// friendly fire damage

// Detailed statistics
int
	iDidDamageClass[MAXPLAYERS + 1][ZC_TANK + 1],	// si classes
	timesPinned[MAXPLAYERS + 1][ZC_TANK + 1],		// times pinned
	totalPinned[MAXPLAYERS + 1],					// total times pinned
	pillsUsed[MAXPLAYERS + 1],						// total pills eaten
	boomerPops[MAXPLAYERS + 1],						// total boomer pops
	damageReceived[MAXPLAYERS + 1];					// Damage received

// Tank stats
bool
	tankSpawned = false;							// When tank is spawned

int
	commonKilledDuringTank[MAXPLAYERS + 1],			// Common killed during the tank
	ttlCommonKilledDuringTank = 0,					// Common killed during the tank
	siDmgDuringTank[MAXPLAYERS + 1],				// SI killed during the tank
	ttlSiDmgDuringTank = 0,							// Total SI killed during the tank
	rocksEaten[MAXPLAYERS + 1],						// The amount of rocks a player 'ate'.
	ttlPinnedDuringTank[MAXPLAYERS + 1];			// The total times we were pinned when the tank was up

// Other
int
	iTotalKills,									// prolly more efficient to store than to recalculate
	iTotalCommon,
	//iTotalDamage,
	//iTotalDamageTank,
	//iTotalDamageWitch,
	iTotalDamageAll,
	iTotalFF,
	iRoundNumber,
	bInRound,
	bPlayerLeftStartArea;							// used for tracking FF when RUP enabled

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	CreateNative("SURVMVP_GetMVP", Native_GetMVP);
	CreateNative("SURVMVP_GetMVPDmgCount", Native_GetMVPDmgCount);
	CreateNative("SURVMVP_GetMVPKills", Native_GetMVPKills);
	CreateNative("SURVMVP_GetMVPDmgPercent", Native_GetMVPDmgPercent);
	CreateNative("SURVMVP_GetMVPCI", Native_GetMVPCI);
	CreateNative("SURVMVP_GetMVPCIKills", Native_GetMVPCIKills);
	CreateNative("SURVMVP_GetMVPCIPercent", Native_GetMVPCIPercent);

	RegPluginLibrary("survivor_mvp");
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "Survivor MVP notification",
	author = "Tabun, Artifacial",
	description = "Shows MVP for survivor team at end of round",
	version = "0.5",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	// Round triggers
	//HookEvent("door_close", DoorClose_Event);
	//HookEvent("finale_vehicle_leaving", FinaleVehicleLeaving_Event, EventHookMode_PostNoCopy);
	HookEvent("round_start", RoundStart_Event, EventHookMode_PostNoCopy);
	HookEvent("round_end", RoundEnd_Event, EventHookMode_PostNoCopy);
	HookEvent("map_transition", RoundEnd_Event, EventHookMode_PostNoCopy);
	HookEvent("scavenge_round_start", ScavRoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", PlayerLeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("pills_used", pillsUsedEvent);
	HookEvent("boomer_exploded", boomerExploded);
	HookEvent("charger_carry_end", chargerCarryEnd);
	HookEvent("jockey_ride", jockeyRide);
	HookEvent("lunge_pounce", hunterLunged);
	HookEvent("choke_start", smokerChoke);
	HookEvent("tank_killed", tankKilled, EventHookMode_PostNoCopy);
	HookEvent("tank_spawn", tankSpawn, EventHookMode_PostNoCopy);
	//HookEvent("tank_frustrated", tankFrustrated);

	// Catching data
	HookEvent("player_hurt", PlayerHurt_Event, EventHookMode_Post);
	HookEvent("player_death", PlayerDeath_Event, EventHookMode_Post);
	HookEvent("infected_hurt" ,InfectedHurt_Event, EventHookMode_Post);
	HookEvent("infected_death", InfectedDeath_Event, EventHookMode_Post);

	// check gamemode (for scavenge fix)
	g_hGameMode = FindConVar("mp_gamemode");

	// Cvars
	hPluginEnabled = CreateConVar("sm_survivor_mvp_enabled", "1", "Enable display of MVP at end of round");
	hCountTankDamage = CreateConVar("sm_survivor_mvp_counttank", "0", "Damage on tank counts towards MVP-selection if enabled.");
	hCountWitchDamage = CreateConVar("sm_survivor_mvp_countwitch", "0", "Damage on witch counts towards MVP-selection if enabled.");
	hTrackFF = CreateConVar("sm_survivor_mvp_showff", "1", "Track Friendly-fire stat.");
	hBrevityFlags = CreateConVar("sm_survivor_mvp_brevity", "0", "Flags for setting brevity of MVP report (hide 1:SI, 2:CI, 4:FF, 8:rank, 32:perc, 64:abs).");

	bCountTankDamage = hCountTankDamage.BoolValue;
	bCountWitchDamage = hCountWitchDamage.BoolValue;
	bTrackFF = hTrackFF.BoolValue;
	iBrevityFlags = hBrevityFlags.IntValue;

	// for now, force FF tracking on:
	bTrackFF = true;

	hCountTankDamage.AddChangeHook(ConVarChange_CountTankDamage);
	hCountWitchDamage.AddChangeHook(ConVarChange_CountWitchDamage);
	hTrackFF.AddChangeHook(ConVarChange_TrackFF);
	hBrevityFlags.AddChangeHook(ConVarChange_BrevityFlags);

	if (!(iBrevityFlags & BREV_FF)) {
		bTrackFF = true; // force tracking on if we're showing FF
	}

	// Commands
	RegConsoleCmd("sm_mvp", SurvivorMVP_Cmd, "Prints the current MVP for the survivor team");
	RegConsoleCmd("sm_mvpme", ShowMVPStats_Cmd, "Prints the client's own MVP-related stats");
}

public void OnClientPutInServer(int client)
{
	char tmpBuffer[64];
	GetClientName(client, tmpBuffer, sizeof(tmpBuffer));

	// if previously stored name for same client is not the same, delete stats & overwrite name
	if (strcmp(tmpBuffer, sClientName[client], true) != 0) {
		iGotKills[client] = 0;
		iGotCommon[client] = 0;
		iDidDamage[client] = 0;
		iDidDamageAll[client] = 0;
		iDidDamageWitch[client] = 0;
		iDidDamageTank[client] = 0;
		iDidFF[client] = 0;

		//@todo detailed statistics - set to 0
		for (int siClass = ZC_SMOKER; siClass <= ZC_TANK; siClass++) {
			iDidDamageClass[client][siClass] = 0;
			timesPinned[client][siClass] = 0;
		}

		pillsUsed[client] = 0;
		boomerPops[client] = 0;
		damageReceived[client] = 0;
		totalPinned[client] = 0;
		commonKilledDuringTank[client] = 0;
		siDmgDuringTank[client] = 0;
		rocksEaten[client] = 0;
		ttlPinnedDuringTank[client] = 0;

		// store name for later reference
		strcopy(sClientName[client], 64, tmpBuffer);
	}
}

public void ConVarChange_CountTankDamage(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	bCountTankDamage = StringToInt(sNewValue) != 0;
}

public void ConVarChange_CountWitchDamage(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	bCountWitchDamage = StringToInt(sNewValue) != 0;
}

public void ConVarChange_TrackFF(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	//if (StringToInt(sNewValue) == 0) { bTrackFF = false; } else { bTrackFF = true; }
	// for now, disable FF tracking toggle (always on)
}

public void ConVarChange_BrevityFlags(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	iBrevityFlags = StringToInt(sNewValue);
	if (!(iBrevityFlags & BREV_FF)) {
		bTrackFF = true;
	} // force tracking on if we're showing FF
}

public void OnRoundIsLive()
{
	bPlayerLeftStartArea = true;
}

public void PlayerLeftStartArea(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// if RUP active, now we can start tracking FF
	bPlayerLeftStartArea = true;
}

public void OnMapStart()
{
	bPlayerLeftStartArea = false;
}

public void OnMapEnd()
{
	bPlayerLeftStartArea = false;
	iRoundNumber = 0;
	bInRound = false;
}

public void ScavRoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	ClearStatsArrays();

	bInRound = true;
	tankSpawned = false;
}

public void RoundStart_Event(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	bPlayerLeftStartArea = false;

	if (!bInRound) {
		bInRound = true;
		iRoundNumber++;
	}

	ClearStatsArrays();
}

void ClearStatsArrays()
{
	// clear mvp stats
	for (int i = 1; i <= MaxClients; i++) {
		iGotKills[i] = 0;
		iGotCommon[i] = 0;
		iDidDamage[i] = 0;
		iDidDamageAll[i] = 0;
		iDidDamageWitch[i] = 0;
		iDidDamageTank[i] = 0;
		iDidFF[i] = 0;

		//@todo detailed statistics - set to 0
		for (int siClass = ZC_SMOKER; siClass <= ZC_TANK; siClass++) {
			iDidDamageClass[i][siClass] = 0;
			timesPinned[i][siClass] = 0;
		}

		pillsUsed[i] = 0;
		boomerPops[i] = 0;
		damageReceived[i] = 0;
		totalPinned[i] = 0;
		commonKilledDuringTank[i] = 0;
		siDmgDuringTank[i] = 0;
		rocksEaten[i] = 0;
		ttlPinnedDuringTank[i] = 0;
	}

	iTotalKills = 0;
	iTotalCommon = 0;
	//iTotalDamage = 0;
	//iTotalDamageTank = 0;
	//iTotalDamageWitch = 0;
	iTotalDamageAll = 0;
	iTotalFF = 0;
	ttlSiDmgDuringTank = 0;
	ttlCommonKilledDuringTank = 0;
}

public void RoundEnd_Event(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	char sGameMode[24];
	// get gamemode string for scavenge fix
	g_hGameMode.GetString(sGameMode, sizeof(sGameMode));

	if (strcmp(sGameMode, "coop", false) == 0) {
		if (bInRound) {
			if (hPluginEnabled.BoolValue) {
				CreateTimer(0.01, delayedMVPPrint); // shorter delay for scavenge.
			}

			bInRound = false;
		}
	} else {
		// versus or other
		if (bInRound && strcmp(sEventName, "map_transition", false) != 0) {
			// only show / log stuff when the round is done "the first time"
			if (hPluginEnabled.BoolValue) {
				CreateTimer(2.0, delayedMVPPrint);
			}

			bInRound = false;
		}
	}

	tankSpawned = false;
}

public Action SurvivorMVP_Cmd(int client, int args)
{
	char printBuffer[4096], strLines[8][192];

	GetMVPString(printBuffer, sizeof(printBuffer));

	// PrintToChat has a max length. Split it in to individual lines to output separately
	int intPieces = ExplodeString(printBuffer, "\n", strLines, sizeof(strLines), sizeof(strLines[]));

	if (client && IsClientConnected(client)) {
		for (int i = 0; i < intPieces; i++) {
			CPrintToChat(client, "%s", strLines[i]);
		}
	}

	PrintLoserz(true, client);
	return Plugin_Handled;
}

public Action ShowMVPStats_Cmd(int client, int args)
{
	PrintLoserz(true, client);
	return Plugin_Handled;
}

public Action delayedMVPPrint(Handle hTimer)
{
	char printBuffer[4096], strLines[8][192];
	GetMVPString(printBuffer, sizeof(printBuffer));

	// PrintToChatAll has a max length. Split it in to individual lines to output separately
	int intPieces = ExplodeString(printBuffer, "\n", strLines, sizeof(strLines), sizeof(strLines[]));
	for (int i = 0; i < intPieces; i++) {
		for (int client = 1; client <= MaxClients; client++) {
			if (IsClientInGame(client)) {
				CPrintToChat(client, "{default}%s", strLines[i]);
			}
		}
	}

	CreateTimer(0.1, Timer_PrintLosers);
	return Plugin_Stop;
}

public Action Timer_PrintLosers(Handle hTimer)
{
	PrintLoserz(false, -1);
	return Plugin_Stop;
}

void PrintLoserz(bool bSolo, int client)
{
	char tmpBuffer[512];
	// also find the three non-mvp survivors and tell them they sucked
	// tell them they sucked with SI
	if (iTotalDamageAll > 0) {
		int mvp_SI = findMVPSI();
		int mvp_SI_losers[3];
		mvp_SI_losers[0] = findMVPSI(mvp_SI);                                                   // second place
		mvp_SI_losers[1] = findMVPSI(mvp_SI, mvp_SI_losers[0]);                             // third
		mvp_SI_losers[2] = findMVPSI(mvp_SI, mvp_SI_losers[0], mvp_SI_losers[1]);       // fourth

		for (int i = 0; i <= 2; i++) {
			if (IsClientAndInGame(mvp_SI_losers[i]) && !IsFakeClient(mvp_SI_losers[i])) {
				if (bSolo) {
					if (mvp_SI_losers[i] == client) {
						Format(tmpBuffer, sizeof(tmpBuffer), "{blue}Your Rank {green}SI: {olive}#%d - {blue}({default}%d {green}dmg {blue}[{default}%.0f%%{blue}]{olive}, {default}%d {green}kills {blue}[{default}%.0f%%{blue}])", (i + 2), iDidDamageAll[mvp_SI_losers[i]], (float(iDidDamageAll[mvp_SI_losers[i]]) / float(iTotalDamageAll)) * 100, iGotKills[mvp_SI_losers[i]], (float(iGotKills[mvp_SI_losers[i]]) / float(iTotalKills)) * 100);
						CPrintToChat(mvp_SI_losers[i], "%s", tmpBuffer);
					}
				} else {
					Format(tmpBuffer, sizeof(tmpBuffer), "{blue}Your Rank {green}SI: {olive}#%d - {blue}({default}%d {green}dmg {blue}[{default}%.0f%%{blue}]{olive}, {default}%d {green}kills {blue}[{default}%.0f%%{blue}])", (i + 2), iDidDamageAll[mvp_SI_losers[i]], (float(iDidDamageAll[mvp_SI_losers[i]]) / float(iTotalDamageAll)) * 100, iGotKills[mvp_SI_losers[i]], (float(iGotKills[mvp_SI_losers[i]]) / float(iTotalKills)) * 100);
					CPrintToChat(mvp_SI_losers[i], "%s", tmpBuffer);
				}
			}
		}
	}

	// tell them they sucked with Common
	if (iTotalCommon > 0) {
		int mvp_CI = findMVPCommon();
		int mvp_CI_losers[3];
		mvp_CI_losers[0] = findMVPCommon(mvp_CI);                                                   // second place
		mvp_CI_losers[1] = findMVPCommon(mvp_CI, mvp_CI_losers[0]);                             // third
		mvp_CI_losers[2] = findMVPCommon(mvp_CI, mvp_CI_losers[0], mvp_CI_losers[1]);       // fourth

		for (int i = 0; i <= 2; i++) {
			if (IsClientAndInGame(mvp_CI_losers[i]) && !IsFakeClient(mvp_CI_losers[i])) {
				if (bSolo) {
					if (mvp_CI_losers[i] == client) {
						Format(tmpBuffer, sizeof(tmpBuffer), "{blue}Your Rank {green}CI{default}: {olive}#%d {blue}({default}%d {green}common {blue}[{default}%.0f%%{blue}])", (i + 2), iGotCommon[mvp_CI_losers[i]], (float(iGotCommon[mvp_CI_losers[i]]) / float(iTotalCommon)) * 100);
						CPrintToChat(mvp_CI_losers[i], "%s", tmpBuffer);
					}
				} else {
					Format(tmpBuffer, sizeof(tmpBuffer), "{blue}Your Rank {green}CI{default}: {olive}#%d {blue}({default}%d {green}common {blue}[{default}%.0f%%{blue}])", (i + 2), iGotCommon[mvp_CI_losers[i]], (float(iGotCommon[mvp_CI_losers[i]]) / float(iTotalCommon)) * 100);
					CPrintToChat(mvp_CI_losers[i], "%s", tmpBuffer);
				}
			}
		}
	}

	// tell them they were better with FF (I know, I know, losers = winners)
	if (iTotalFF > 0) {
		int mvp_FF = findLVPFF();
		int mvp_FF_losers[3];
		mvp_FF_losers[0] = findLVPFF(mvp_FF);                                                   // second place
		mvp_FF_losers[1] = findLVPFF(mvp_FF, mvp_FF_losers[0]);                             // third
		mvp_FF_losers[2] = findLVPFF(mvp_FF, mvp_FF_losers[0], mvp_FF_losers[1]);       // fourth

		for (int i = 0; i <= 2; i++) {
			if (IsClientAndInGame(mvp_FF_losers[i]) &&  !IsFakeClient(mvp_FF_losers[i])) {
				if (bSolo) {
					if (mvp_FF_losers[i] == client) {
						Format(tmpBuffer, sizeof(tmpBuffer), "{blue}Your Rank {green}FF{default}: {olive}#%d {blue}({default}%d {green}friendly fire {blue}[{default}%.0f%%{blue}])", (i + 2), iDidFF[mvp_FF_losers[i]], (float(iDidFF[mvp_FF_losers[i]]) / float(iTotalFF)) * 100);
						CPrintToChat(mvp_FF_losers[i], "%s", tmpBuffer);
					}
				} else {
					Format(tmpBuffer, sizeof(tmpBuffer), "{blue}Your Rank {green}FF{default}: {olive}#%d {blue}({default}%d {green}friendly fire {blue}[{default}%.0f%%{blue}])", (i + 2), iDidFF[mvp_FF_losers[i]], (float(iDidFF[mvp_FF_losers[i]]) / float(iTotalFF)) * 100);
					CPrintToChat(mvp_FF_losers[i], "%s", tmpBuffer);
				}
			}
		}
	}
}

/**
* Track pill usage
*/
public void pillsUsedEvent(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	if (client < 1 || !IsClientInGame(client)) {
		return;
	}

	pillsUsed[client]++;
}

/**
* Track boomer pops
*/
public void boomerExploded(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// We only want to track pops where the boomer didn't bile anyone
	if (hEvent.GetBool("splashedbile")) {
		return;
	}

	int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
	if (attacker < 1 || ! IsClientInGame(attacker)) {
		return;
	}

	boomerPops[attacker]++;
}

/**
* Track when someone gets charged (end of charge for level, or if someone shoots you off etc.)
*/
public void chargerCarryEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("victim"));
	if (client < 1 || ! IsClientInGame(client)) {
		return;
	}

	timesPinned[client][ZC_CHARGER]++;
	totalPinned[client]++;

	if (tankSpawned) {
		ttlPinnedDuringTank[client]++;
	}
}

/**
* Track when someone gets jockeyed.
*/
public void jockeyRide(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("victim"));
	if (client < 1 || !IsClientInGame(client)) {
		return;
	}

	timesPinned[client][ZC_JOCKEY]++;
	totalPinned[client]++;

	if (tankSpawned) {
		ttlPinnedDuringTank[client]++;
	}
}

/**
* Track when someone gets huntered.
*/
public void hunterLunged(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("victim"));
	if (client < 1 || !IsClientInGame(client)) {
		return;
	}

	timesPinned[client][ZC_HUNTER]++;
	totalPinned[client]++;

	if (tankSpawned) {
		ttlPinnedDuringTank[client]++;
	}
}

/**
* Track when someone gets smoked (we track when they start getting smoked, because anyone can get smoked)
*/
public void smokerChoke(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("victim"));
	if (client < 1 || !IsClientInGame(client)) {
		return;
	}

	timesPinned[client][ZC_SMOKER]++;
	totalPinned[client]++;

	if (tankSpawned) {
		ttlPinnedDuringTank[client]++;
	}
}

/**
* When the tank spawns
*/
public void tankSpawn(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	tankSpawned = true;
}

/**
* When the tank is killed
*/
public void tankKilled(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	tankSpawned = false;
}

/*
*      track damage/kills
*      ==================
*/
public void PlayerHurt_Event(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// Victim details
	int victimId = hEvent.GetInt("userid");
	int victim = GetClientOfUserId(victimId);

	// Attacker details
	int attackerId = hEvent.GetInt("attacker");
	int attacker = GetClientOfUserId(attackerId);

	// Misc details
	int damageDone = hEvent.GetInt("dmg_health");

	// no world damage or flukes or whatevs, no bot attackers, no infected-to-infected damage
	if (victimId && attackerId && IsClientAndInGame(victim) && IsClientAndInGame(attacker)) {
		// If a survivor is attacking infected
		if (GetClientTeam(attacker) == TEAM_SURVIVOR && GetClientTeam(victim) == TEAM_INFECTED) {
			int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");

			// Increment the damage for that class to the total
			iDidDamageClass[attacker][zombieClass] += damageDone;
			//PrintToConsole(attacker, "Attacked: %d - Dmg: %d", zombieClass, damageDone);
			//PrintToConsole(attacker, "Total damage for %d: %d", zombieClass, iDidDamageClass[attacker][zombieClass]);

			// separately store SI and tank damage
			if (zombieClass >= ZC_SMOKER && zombieClass < ZC_WITCH) {
				// If the tank is up, let's store separately
				if (tankSpawned) {
					siDmgDuringTank[attacker] += damageDone;
					ttlSiDmgDuringTank += damageDone;
				}

				iDidDamage[attacker] += damageDone;
				iDidDamageAll[attacker] += damageDone;
				//iTotalDamage += damageDone;
				iTotalDamageAll += damageDone;
			} else if (zombieClass == ZC_TANK && damageDone != 5000) { // For some reason the last attacker does 5k damage?
				// We want to track tank damage even if we're not factoring it in to our mvp result
				iDidDamageTank[attacker] += damageDone;
				//iTotalDamageTank += damageDone;

				// If we're factoring it in, include it in our overall damage
				if (bCountTankDamage) {
					iDidDamageAll[attacker] += damageDone;
					iTotalDamageAll += damageDone;
				}
			}
		}
		// Otherwise if friendly fire
		else if (GetClientTeam(attacker) == TEAM_SURVIVOR && GetClientTeam(victim) == TEAM_SURVIVOR) {                // survivor on survivor action == FF
			if (bTrackFF && bPlayerLeftStartArea) {
				// but don't record while frozen in readyup / before leaving saferoom
				iDidFF[attacker] += damageDone;
				iTotalFF += damageDone;
			}
		} else if (GetClientTeam(attacker) == TEAM_INFECTED && GetClientTeam(victim) == TEAM_SURVIVOR) { // Otherwise if infected are inflicting damage on a survivor
			// If we got hit by a tank, let's see what type of damage it was
			// If it was from a rock throw
			if (GetEntProp(attacker, Prop_Send, "m_zombieClass") == ZC_TANK) {
				char sWeaponName[MAX_ENTITY_NAME_SIZE];
				hEvent.GetString("weapon", sWeaponName, sizeof(sWeaponName));

				if (strcmp(sWeaponName, "tank_rock") == 0) {
					rocksEaten[victim]++;
				}
			}

			damageReceived[victim] += damageDone;
		}
	}
}

/**
* When the infected are hurt (i.e. when a survivor hurts an SI)
* We want to use this to track damage done to the witch.
*/
public void InfectedHurt_Event(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// catch damage done to witch
	int victimEntId = hEvent.GetInt("entityid");

	if (IsWitch(victimEntId)) {
		int attackerId = hEvent.GetInt("attacker");
		int attacker = GetClientOfUserId(attackerId);
		int damageDone = hEvent.GetInt("amount");

		// no world damage or flukes or whatevs, no bot attackers
		if (attackerId && IsClientAndInGame(attacker) && GetClientTeam(attacker) == TEAM_SURVIVOR) {
			// We want to track the witch damage regardless of whether we're counting it in our mvp stat
			iDidDamageWitch[attacker] += damageDone;
			//iTotalDamageWitch += damageDone;

			// If we're counting witch damage in our mvp stat, lets add the amount of damage done to the witch
			if (bCountWitchDamage) {
				iDidDamageAll[attacker] += damageDone;
				iTotalDamageAll += damageDone;
			}
		}
	}
}

public void PlayerDeath_Event(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// Get the victim details
	int victimId = hEvent.GetInt("userid");
	int victim = GetClientOfUserId(victimId);

	// Get the attacker details
	int attackerId = hEvent.GetInt("attacker");
	int attacker = GetClientOfUserId(attackerId);

	// no world kills or flukes or whatevs, no bot attackers
	if (victimId && attackerId && IsClientAndInGame(victim) && IsClientAndInGame(attacker) && GetClientTeam(attacker) == TEAM_SURVIVOR) {
		int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");

		// only SI, not the tank && only player-attackers
		if (zombieClass >= ZC_SMOKER && zombieClass < ZC_WITCH) {
			// store kill to count for attacker id
			iGotKills[attacker]++;
			iTotalKills++;
		}
	}

	/**
	* Are we tracking the tank?
	* This is a secondary measure. For some reason when I test locally in PM, the
	* tank_killed event is triggered, but when I test in a custom config, it's not.
	* Hopefully this should fix it.
	*/
	if (victimId && IsClientAndInGame(victim)) {
		int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
		if (zombieClass == ZC_TANK) {
			tankSpawned = false;
		}
	}
}

public void InfectedDeath_Event(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));

	if (IsClientAndInGame(attacker) && GetClientTeam(attacker) == TEAM_SURVIVOR) {
		// If the tank is up, let's store separately
		if (tankSpawned) {
			commonKilledDuringTank[attacker]++;
			ttlCommonKilledDuringTank++;
		}

		iGotCommon[attacker]++;
		iTotalCommon++;
		// if victimType > 2, it's an "uncommon" (of some type or other) -- do nothing with this ftpresent.
	}
}

/*
*      MVP string & 'sorting'
*      ======================
*/
void GetMVPString(char[] printBuffer, const int iSize)
{
	printBuffer[0] = '\0';

	char tmpBuffer[1024], tmpName[64];
	char mvp_SI_name[64], mvp_Common_name[64], mvp_FF_name[64];
	int mvp_SI = 0, mvp_Common = 0, mvp_FF = 0;

	// calculate MVP per category:
	//  1. SI damage & SI kills + damage to tank/witch
	//  2. common kills

	// SI MVP
	if (!(iBrevityFlags & BREV_SI)) {
		mvp_SI = findMVPSI();
		if (mvp_SI > 0) {
			// get name from client if connected -- if not, use sClientName array
			if (IsClientConnected(mvp_SI)) {
				GetClientName(mvp_SI, tmpName, sizeof(tmpName));
				if (IsFakeClient(mvp_SI)) {
					StrCat(tmpName, sizeof(tmpName), " \x01[BOT]");
				}
			} else {
				strcopy(tmpName, sizeof(tmpName), sClientName[mvp_SI]);
			}
			mvp_SI_name = tmpName;
		} else {
			mvp_SI_name = "(nobody)";
		}
	}

	// Common MVP
	if (!(iBrevityFlags & BREV_CI)) {
		mvp_Common = findMVPCommon();
		if (mvp_Common > 0) {
			// get name from client if connected -- if not, use sClientName array
			if (IsClientConnected(mvp_Common)) {
				GetClientName(mvp_Common, tmpName, sizeof(tmpName));
				if (IsFakeClient(mvp_Common)) {
					StrCat(tmpName, sizeof(tmpName), " \x01[BOT]");
				}
			} else {
				strcopy(tmpName, sizeof(tmpName), sClientName[mvp_Common]);
			}
			mvp_Common_name = tmpName;
		} else {
			mvp_Common_name = "(nobody)";
		}
	}

	// FF LVP
	if (!(iBrevityFlags & BREV_FF) && bTrackFF) {
		mvp_FF = findLVPFF();
		if (mvp_FF > 0) {
			// get name from client if connected -- if not, use sClientName array
			if (IsClientConnected(mvp_FF)) {
				GetClientName(mvp_FF, tmpName, sizeof(tmpName));
				if (IsFakeClient(mvp_FF)) {
					StrCat(tmpName, sizeof(tmpName), " \x01[BOT]");
				}
			} else {
				strcopy(tmpName, sizeof(tmpName), sClientName[mvp_FF]);
			}
			mvp_FF_name = tmpName;
		} else {
			mvp_FF_name = "(nobody)";
		}
	}

	// report
	if (mvp_SI == 0 && mvp_Common == 0 && !(iBrevityFlags & BREV_SI && iBrevityFlags & BREV_CI)) {
		Format(tmpBuffer, sizeof(tmpBuffer), "{blue}[{default}MVP{blue}]{default} {blue}({default}not enough action yet{blue}){default}\n");
		StrCat(printBuffer, iSize, tmpBuffer);
	} else {
		if (!(iBrevityFlags & BREV_SI)) {
			if (mvp_SI > 0) {
				if (iBrevityFlags & BREV_PERCENT) {
					Format(tmpBuffer, sizeof(tmpBuffer), "[MVP] SI:\x03 %s \x01(\x05%d \x01dmg,\x05 %d \x01kills)\n", mvp_SI_name, iDidDamageAll[mvp_SI], iGotKills[mvp_SI]);
				} else if (iBrevityFlags & BREV_ABSOLUTE) {
					Format(tmpBuffer, sizeof(tmpBuffer), "[MVP] SI:\x03 %s \x01(dmg \x04%2.0f%%\x01, kills \x04%.0f%%\x01)\n", mvp_SI_name, (float(iDidDamageAll[mvp_SI]) / float(iTotalDamageAll)) * 100, (float(iGotKills[mvp_SI]) / float(iTotalKills)) * 100);
				} else {
					Format(tmpBuffer, sizeof(tmpBuffer), "{blue}[{default}MVP{blue}] SI: {olive}%s {blue}({default}%d {green}dmg {blue}[{default}%.0f%%{blue}]{olive}, {default}%d {green}kills {blue}[{default}%.0f%%{blue}])\n", mvp_SI_name, iDidDamageAll[mvp_SI], (float(iDidDamageAll[mvp_SI]) / float(iTotalDamageAll)) * 100, iGotKills[mvp_SI], (float(iGotKills[mvp_SI]) / float(iTotalKills)) * 100);
				}
				StrCat(printBuffer, iSize, tmpBuffer);
			} else {
				StrCat(printBuffer, iSize, "{blue}[{default}MVP{blue}] SI: {blue}({default}nobody{blue}){default}\n");
			}
		}

		if (!(iBrevityFlags & BREV_CI)) {
			if (mvp_Common > 0) {
				if (iBrevityFlags & BREV_PERCENT) {
					Format(tmpBuffer, sizeof(tmpBuffer), "[MVP] CI:\x03 %s \x01(\x05%d \x01common)\n", mvp_Common_name, iGotCommon[mvp_Common]);
				} else if (iBrevityFlags & BREV_ABSOLUTE) {
					Format(tmpBuffer, sizeof(tmpBuffer), "[MVP] CI:\x03 %s \x01(\x04%.0f%%\x01)\n", mvp_Common_name, (float(iGotCommon[mvp_Common]) / float(iTotalCommon)) * 100);
				} else {
					Format(tmpBuffer, sizeof(tmpBuffer), "{blue}[{default}MVP{blue}] CI: {olive}%s {blue}({default}%d {green}common {blue}[{default}%.0f%%{blue}])\n", mvp_Common_name, iGotCommon[mvp_Common], (float(iGotCommon[mvp_Common]) / float(iTotalCommon)) * 100);
				}
				StrCat(printBuffer, iSize, tmpBuffer);
			}
		}
	}

	// FF
	if (!(iBrevityFlags & BREV_FF) && bTrackFF) {
		if (mvp_FF == 0) {
			Format(tmpBuffer, sizeof(tmpBuffer), "{blue}[{default}LVP{blue}] FF{default}: {green}no friendly fire at all!{default}\n");
			StrCat(printBuffer, iSize, tmpBuffer);
		} else {
			if (iBrevityFlags & BREV_PERCENT) {
				Format(tmpBuffer, sizeof(tmpBuffer), "[LVP] FF:\x03 %s \x01(\x05%d \x01dmg)\n", mvp_FF_name, iDidFF[mvp_FF]);
			} else if (iBrevityFlags & BREV_ABSOLUTE) {
				Format(tmpBuffer, sizeof(tmpBuffer), "[LVP] FF:\x03 %s \x01(\x04%.0f%%\x01)\n", mvp_FF_name, (float(iDidFF[mvp_FF]) / float(iTotalFF)) * 100);
			} else {
				Format(tmpBuffer, sizeof(tmpBuffer), "{blue}[{default}LVP{blue}] FF{default}: {olive}%s {blue}({default}%d {green}friendly fire {blue}[{default}%.0f%%{blue}]){default}\n", mvp_FF_name, iDidFF[mvp_FF], (float(iDidFF[mvp_FF]) / float(iTotalFF)) * 100);
			}
			StrCat(printBuffer, iSize, tmpBuffer);
		}
	}
}

int findMVPSI(int excludeMeA = 0, int excludeMeB = 0, int excludeMeC = 0)
{
	int maxIndex = 0;
	for (int i = 1; i < sizeof(iDidDamageAll); i++) {
		if (iDidDamageAll[i] > iDidDamageAll[maxIndex] && i != excludeMeA && i != excludeMeB && i != excludeMeC) {
			maxIndex = i;
		}
	}

	return maxIndex;
}

int findMVPCommon(int excludeMeA = 0, int excludeMeB = 0, int excludeMeC = 0)
{
	int maxIndex = 0;
	for (int i = 1; i < sizeof(iGotCommon); i++) {
		if (iGotCommon[i] > iGotCommon[maxIndex] && i != excludeMeA && i != excludeMeB && i != excludeMeC) {
			maxIndex = i;
		}
	}

	return maxIndex;
}

int findLVPFF(int excludeMeA = 0, int excludeMeB = 0, int excludeMeC = 0)
{
	int maxIndex = 0;
	for (int i = 1; i < sizeof(iDidFF); i++) {
		if (iDidFF[i] > iDidFF[maxIndex] && i != excludeMeA && i != excludeMeB && i != excludeMeC) {
			maxIndex = i;
		}
	}

	return maxIndex;
}

/*
*      general functions
*      =================
*/
bool IsWitch(int iEntity)
{
	if (iEntity <= MaxClients || !IsValidEdict(iEntity)) {
		return false;
	}

	char sClassName[MAX_ENTITY_NAME_SIZE];
	GetEdictClassname(iEntity, sClassName, sizeof(sClassName));
	return (strncmp(sClassName, "witch", 5) == 0); //witch and witch_bride
}

bool IsClientAndInGame(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient));
}

/*bool IsSurvivor(int iClient)
{
	return IsClientAndInGame(iClient) && GetClientTeam(iClient) == TEAM_SURVIVOR);
}

void stripUnicode(char testString[MAX_NAME_LENGTH])
{
	const int maxlength = MAX_NAME_LENGTH;
	//strcopy(testString, maxlength, sTmpString);
	sTmpString = testString;

	int uni = 0, tmpCharLength = 0;
	char currentChar;
	//int iReplace[MAX_NAME_LENGTH];      // replace these chars
	int i = 0;

	for (i = 0; i < maxlength - 3 && sTmpString[i] != 0; i++) {
		// estimate current character value
		if ((sTmpString[i] & 0x80) == 0) { // single byte character?
			currentChar=sTmpString[i];
			tmpCharLength = 0;
		} else if (((sTmpString[i] & 0xE0) == 0xC0) && ((sTmpString[i + 1] & 0xC0) == 0x80)) { // two byte character?
			currentChar=(sTmpString[i++] & 0x1f);
			currentChar=currentChar << 6;
			currentChar+=(sTmpString[i] & 0x3f);
			tmpCharLength = 1;
		} else if (((sTmpString[i] & 0xF0) == 0xE0) && ((sTmpString[i + 1] & 0xC0) == 0x80) && ((sTmpString[i + 2] & 0xC0) == 0x80)) { // three byte character?
			currentChar=(sTmpString[i++] & 0x0f);
			currentChar=currentChar << 6;
			currentChar+=(sTmpString[i++] & 0x3f);
			currentChar=currentChar << 6;
			currentChar+=(sTmpString[i] & 0x3f);
			tmpCharLength = 2;
		} else if (((sTmpString[i] & 0xF8) == 0xF0) && ((sTmpString[i + 1] & 0xC0) == 0x80) && ((sTmpString[i + 2] & 0xC0) == 0x80) && ((sTmpString[i + 3] & 0xC0) == 0x80)) { // four byte character?
			currentChar=(sTmpString[i++] & 0x07);
			currentChar=currentChar << 6;
			currentChar+=(sTmpString[i++] & 0x3f);
			currentChar=currentChar << 6;
			currentChar+=(sTmpString[i++] & 0x3f);
			currentChar=currentChar << 6;
			currentChar+=(sTmpString[i] & 0x3f);
			tmpCharLength = 3;
		} else {
			currentChar=CHARTHRESHOLD + 1; // reaching this may be caused by bug in sourcemod or some kind of bug using by the user - for unicode users I do assume last ...
			tmpCharLength = 0;
		}

		// decide if character is allowed
		if (currentChar > CHARTHRESHOLD) {
			uni++;
			// replace this character // 95 = _, 32 = space
			for (int j = tmpCharLength; j >= 0; j--) {
				sTmpString[i - j] = 95;
			}
		}
	}
}

int getSurvivor(int exclude[4])
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsSurvivor(i)) {
			bool tagged = false;
			// exclude already tagged survs
			for (int j = 0; j < 4; j++) {
				if (exclude[j] == i) {
					tagged = true;
				}
			}

			if (!tagged) {
				return i;
			}
		}
	}

	return 0;
}

bool IsCommonInfected(int iEntity)
{
	if (iEntity <= MaxClients || !IsValidEdict(iEntity)) {
		return false;
	}

	char sClassName[MAX_ENTITY_NAME_SIZE];
	GetEdictClassname(iEntity, sClassName, sizeof(sClassName));
	return (strcmp(sClassName, "infected") == 0);
}
*/

// simply return current round MVP client
public int Native_GetMVP(Handle hPlugin, int iNumParams)
{
	return findMVPSI();
}

// return damage percent of client
#if SOURCEMOD_V_MINOR > 9
public any Native_GetMVPDmgPercent(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	float fDmgprc = (iClient && iTotalDamageAll > 0) ? (float(iDidDamageAll[iClient]) / float(iTotalDamageAll)) * 100 : 0.0;
	return fDmgprc;
}

// return CI percent of client
public any Native_GetMVPCIPercent(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	float fDmgprc = (iClient && iTotalCommon > 0) ? (float(iGotCommon[iClient]) / float(iTotalCommon)) * 100 : 0.0;
	return fDmgprc;
}
#else
public int Native_GetMVPDmgPercent(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	float fDmgprc = (iClient && iTotalDamageAll > 0) ? (float(iDidDamageAll[iClient]) / float(iTotalDamageAll)) * 100 : 0.0;
	return view_as<int>(fDmgprc);
}

// return CI percent of client
public int Native_GetMVPCIPercent(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	float fDmgprc = (iClient && iTotalCommon > 0) ? (float(iGotCommon[iClient]) / float(iTotalCommon)) * 100 : 0.0;
	return view_as<int>(fDmgprc);
}
#endif

// return damage of client
public int Native_GetMVPDmgCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iDmg = (iClient && iTotalDamageAll > 0) ? iDidDamageAll[iClient] : 0;
	return iDmg;
}

// return SI kills of client
public int Native_GetMVPKills(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iDmg = (iClient && iTotalKills > 0) ? iGotKills[iClient] : 0;
	return iDmg;
}

// simply return current round MVP client (Common)
public int Native_GetMVPCI(Handle hPlugin, int iNumParams)
{
	return findMVPCommon();
}

// return common kills for client
public int Native_GetMVPCIKills(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iDmg = (iClient && iTotalCommon > 0) ? iGotCommon[iClient] : 0;
	return iDmg;
}
