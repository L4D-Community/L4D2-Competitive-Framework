#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#define L4D2_DIRECT_INCLUDE 1
#define LEFT4FRAMEWORK_INCLUDE 1
#include <left4framework>
#include <l4d2util_constants>
#include <colors>
#undef REQUIRE_PLUGIN
#include <readyup>

#define DOMINATORS_DEFAULT 53

int
	g_iStoredClass[MAXPLAYERS + 1] = {0, ...},
	g_iDominators = DOMINATORS_DEFAULT,
	g_iVersusSpitterLimit = 0,
	g_iMaxSI = 0;

bool
	g_bPlayerSpawned[MAXPLAYERS + 1] = {false, ...},
	g_bRespawning[MAXPLAYERS + 1] = {false, ...},
	g_bKeepChecking[MAXPLAYERS + 1] = {false, ...};

float
	g_fTankPls[MAXPLAYERS + 1] = {0.0, ...}; // Small Timer to Fix AI Tank pass

ArrayList
	g_SpawnsArray = null;

bool
	g_bReadyUpIsAvailable = false,
	g_bLive = false;

ConVar
	g_hDominators = null,
	g_hCvarMaxSI = null,
	g_hCvarVersusSmokerLimit = null,
	g_hCvarVersusBoomerLimit = null,
	g_hCvarVersusHunterLimit = null,
	g_hCvarVersusSpitterLimit = null,
	g_hCvarVersusJockeyLimit = null,
	g_hCvarVersusChargersLimit = null;

public Plugin myinfo =
{
	name = "L4D2 Proper Sack Order",
	author = "Sir",
	description = "Finally fix that pesky spawn rotation not being reliable",
	version = "1.5",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	// Array
	g_SpawnsArray = new ArrayList(16);

	g_hCvarMaxSI = FindConVar("z_max_player_zombies");
	g_hCvarVersusSpitterLimit = FindConVar("z_versus_spitter_limit");

	g_hCvarVersusSmokerLimit = FindConVar("z_versus_smoker_limit");
	g_hCvarVersusBoomerLimit = FindConVar("z_versus_boomer_limit");
	g_hCvarVersusHunterLimit = FindConVar("z_versus_hunter_limit");
	g_hCvarVersusJockeyLimit = FindConVar("z_versus_jockey_limit");
	g_hCvarVersusChargersLimit = FindConVar("z_versus_charger_limit");

	g_iMaxSI = g_hCvarMaxSI.IntValue;
	g_iVersusSpitterLimit = g_hCvarVersusSpitterLimit.IntValue;

	g_hCvarMaxSI.AddChangeHook(cvarChanged);
	g_hCvarVersusSpitterLimit.AddChangeHook(cvarChanged);

	// Events
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", Event_RoundGoesLive, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
}

public void cvarChanged(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	g_iMaxSI = g_hCvarMaxSI.IntValue;
	g_iVersusSpitterLimit = g_hCvarVersusSpitterLimit.IntValue;
}

// Ready-up Checks
public void OnAllPluginsLoaded()
{
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

public void OnConfigsExecuted()
{
	g_hDominators = FindConVar("l4d2_dominators");

	g_iDominators = (g_hDominators != null) ? g_hDominators.IntValue : DOMINATORS_DEFAULT;
}

public void OnRoundIsLive()
{
	RoundActivated();
}

public void Event_RoundGoesLive(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (g_bReadyUpIsAvailable) {
		return;
	}

	RoundActivated();
}

void RoundActivated()
{
	if (!g_bLive) {
		// Clear Array here.
		// Fill Array with existing spawns (from lowest SI Class to Highest, ie. 2 Hunters, if available, will be spawned before a Spitter as they're SI Class 3 and a Spitter is 4)
		g_SpawnsArray.Clear();
		FillArray(g_SpawnsArray);
		g_bLive = true;
	}
}

// Events
public void Event_RoundReset(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// Clear Bool.
	g_bLive = false;

	//Clear Spawn Storage
	for (int i = 1; i <= MaxClients; i++) {
		g_bPlayerSpawned[i] = false;
		g_fTankPls[i] = 0.0;
		g_iStoredClass[i] = 0;
		g_bKeepChecking[i] = false;
		g_bRespawning[i] = false;
	}
}

public void Event_PlayerSpawn(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (!g_bLive) {
		return;
	}

	// Check if the Player is Valid and Infected.
	// Triggered when a Player actually spawns in (Players spawn out of Ghost Mode, AI Takes over existing Spawn)
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || IsFakeClient(iClient) || GetClientTeam(iClient) != L4D2Team_Infected) {
		return;
	}

	if (GetEntProp(iClient, Prop_Send, "m_zombieClass") == L4D2Infected_Tank) {
		return;
	}

	g_bPlayerSpawned[iClient] = true;
	g_bRespawning[iClient] = false;
}

public void Event_PlayerTeam(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (!g_bLive || hEvent.GetBool("disconnect") || hEvent.GetInt("oldteam") != L4D2Team_Infected) {
		return;
	}

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || GetEntProp(iClient, Prop_Send, "m_isGhost", 1) < 1) {
		return;
	}
	
	// 1.3 Notes: Investigate if I did these because they have issues, considering I didn't document this anywhere.
	//--------------------------------------------------------------------------------------------------------------
	// - Why am I checking for Tank here if we only care about Ghost Infected?
	// - Why not reset stats on players regardless (for safety) prior to the Ghost/Tank check?
	//--------------------------------------------------------------------------------------------------------------
	int iSI = GetEntProp(iClient, Prop_Send, "m_zombieClass");
	if (iSI <= L4D2Infected_Common || iSI == L4D2Infected_Tank) {
		return;
	}

	g_bPlayerSpawned[iClient] = false;
	g_bRespawning[iClient] = false;
	g_iStoredClass[iClient] = 0;

	if (g_SpawnsArray.Length > 0) {
		g_SpawnsArray.ShiftUp(0);
	}

	g_SpawnsArray.Set(0, iSI);
}

public void OnClientDisconnect(int iClient)
{
	if (IsFakeClient(iClient)) {
		return;
	}

	g_bPlayerSpawned[iClient] = false;
	g_bRespawning[iClient] = false;
}

public void Event_PlayerDeath(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (!g_bLive) {
		return;
	}

	// Check if the Player is Valid and Infected.
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || !IsClientInGame(iClient) || GetClientTeam(iClient) != L4D2Team_Infected) {
		return;
	}
	
	// Don't want Tanks in our Array.. do we?!
	// Also includes a tiny Fix.
	int iSI = GetEntProp(iClient, Prop_Send, "m_zombieClass");
	if (iSI > L4D2Infected_Common) {
		if (iSI == L4D2Infected_Tank) {
			g_iStoredClass[iClient] = 0;
		} else if (g_fTankPls[iClient] < GetGameTime()) {
			if (g_iStoredClass[iClient] == 0) {
				g_SpawnsArray.Push(iSI);
			}
		}
	}

	if (!IsFakeClient(iClient)) {
		g_bPlayerSpawned[iClient] = false;
	}
}

public void L4D_OnEnterGhostState(int iClient)
{
	// Is Game live?
	// Is Valid Client?
	// Is Infected?
	// Instant spawn after passing Tank to AI? (Gets slain) - NOTE: We don't need to reset g_fTankPls thanks to nodeathcamskip.smx
	if (!g_bLive) {
		return;
	}

	/*if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || GetClientTeam(iClient) != L4D2Team_Infected) {
		return;
	}*/

	if (g_fTankPls[iClient] > GetGameTime()) {
		return;
	}

	// Is Player Respawning?
	if (g_bPlayerSpawned[iClient]) {
		g_bRespawning[iClient] = true;
		return;
	}

	// Switch Class and Pass Client Info as he will already be counted in the total.
	// If for some reason the returned SI is invalid or if the Array isn't filled up yet: allow Director to continue.
	int iSI = ReturnNextSIInQueue(iClient);
	if (iSI > L4D2Infected_Common) {
		L4D_SetClass(iClient, iSI);
	}

	if (g_bKeepChecking[iClient]) {
		g_iStoredClass[iClient] = iSI;
		g_bKeepChecking[iClient] = false;
	}
}

public Action L4D_OnTryOfferingTankBot(int iTankIndex, bool &bEnterStasis)
{
	if (iTankIndex > 0 && IsFakeClient(iTankIndex)) {
		// Because Tank Control sets the Tank Tickets as well.
		// This method will work, but it will only work with Configs/Server setups that use L4D Tank Control
		CreateTimer(0.01, Timer_CheckTankie, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

public Action Timer_CheckTankie(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == L4D2Team_Infected) {
			if (L4D2Direct_GetTankTickets(i) == 20000) {
				if (GetEntProp(i, Prop_Send, "m_isGhost", 1) > 0) {
					g_iStoredClass[i] = GetEntProp(i, Prop_Send, "m_zombieClass");
				} else {
					g_bKeepChecking[i] = true;
				}
			}
		}
	}

	return Plugin_Stop;
}

public void L4D2_OnTankPassControl(int iOldTank, int iNewTank, int iPassCount) //l4d2lib
{
	if (!IsFakeClient(iNewTank)) {
		if (g_iStoredClass[iNewTank] > 0) {
			if (!g_bPlayerSpawned[iNewTank] || g_bRespawning[iNewTank]) {
				g_SpawnsArray.Push(g_iStoredClass[iNewTank]);
				g_bRespawning[iNewTank] = false;
			}
		}
	
		g_bKeepChecking[iNewTank] = false;
	} else {
		g_fTankPls[iOldTank] = GetGameTime() + 2.0;
		g_iStoredClass[iOldTank] = 0;
	}
}

//--------------------------------------------------------------------------------- Stocks & Such
int ReturnNextSIInQueue(int iClient)
{
	int iQueuedSI = L4D2Infected_Common;
	int iQueuedIndex = 0;

	// Do we have Spawns in our Array yet?
	if (g_SpawnsArray.Length > 0) {
		// Check if we actually need a "Support" SI at this time.
		// Requirements:
		// - No Quadcap Plugin.
		// - No Tank Alive.
		// - A Full Infected Team (4 Players)
		// - No "Support" SI Alive.
		if (g_iDominators != 0 && !IsTankInPlay() 
			&& !IsSupportSIAlive(iClient) && IsInfectedTeamFull() 
			&& IsInfectedTeamAlive() >= (g_iMaxSI - 1)
		) {
			// Look for the Boomer's position in the Array.
			iQueuedSI = L4D2Infected_Boomer;
			iQueuedIndex = g_SpawnsArray.FindValue(L4D2Infected_Boomer);

			// Look for the Spitter's position in the Array.
			int iTempIndex = g_SpawnsArray.FindValue(L4D2Infected_Spitter);

			// Check if the Spitter should be selected for Spawning (because she died before the Boomer did)
			//
			// Additional Check:
			// -----------------
			// If the Boomer position returns -1 (it shouldn't, considering we've checked for any Support SI being alive)
			// Perhaps a non-Boomer config? :D
			if (iQueuedIndex > iTempIndex || iQueuedIndex == -1) {
				iQueuedSI = L4D2Infected_Spitter;
				iQueuedIndex = iTempIndex;
			}
		} else { // We get to enforce the first available Spawn in the Array!
			// Simple, just take the Array's very first Index value.
			iQueuedSI = g_SpawnsArray.Get(0);

			// Hold up, no spitters when Tank is up!
			// Luckily all the plugin does is change the spitter limit to 0, so we can easily track it.
			if (iQueuedSI == L4D2Infected_Spitter && g_iVersusSpitterLimit == 0) {
				// Let's take the next SI in the array then.
				iQueuedSI = g_SpawnsArray.Get(1);
				iQueuedIndex = 1;
			}
		}

		// Remove SI from Array.
		if (iQueuedSI != L4D2Infected_Common) {
			g_SpawnsArray.Erase(iQueuedIndex);
		}
	}

	// return Queued SI to function caller.
	return iQueuedSI;
}

void FillArray(ArrayList &hArray)
{
	int iSmokers = g_hCvarVersusSmokerLimit.IntValue;
	int iBoomers = g_hCvarVersusBoomerLimit.IntValue;
	int iHunters = g_hCvarVersusHunterLimit.IntValue;
	int iSpitters = g_hCvarVersusSpitterLimit.IntValue;
	int iJockeys = g_hCvarVersusJockeyLimit.IntValue;
	int iChargers = g_hCvarVersusChargersLimit.IntValue;

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == L4D2Team_Infected) {
			int iSiClass = GetEntProp(i, Prop_Send, "m_zombieClass");
			switch (iSiClass) {
				case L4D2Infected_Smoker: {
					iSmokers--;
				}
				case L4D2Infected_Boomer: {
					iBoomers--;
				}
				case L4D2Infected_Hunter: {
					iHunters--;
				}
				case L4D2Infected_Spitter: {
					iSpitters--;
				}
				case L4D2Infected_Jockey: {
					iJockeys--;
				}
				case L4D2Infected_Charger: {
					iChargers--;
				}
			}
		}
	}

	while (iSmokers > 0) {
		iSmokers--;
		hArray.Push(L4D2Infected_Smoker);
	}

	while (iBoomers > 0) {
		iBoomers--;
		hArray.Push(L4D2Infected_Boomer);
	}

	while (iHunters > 0) {
		iHunters--;
		hArray.Push(L4D2Infected_Hunter);
	}

	while (iSpitters > 0) {
		iSpitters--;
		hArray.Push(L4D2Infected_Spitter);
	}

	while (iJockeys > 0) {
		iJockeys--;
		hArray.Push(L4D2Infected_Jockey);
	}

	while (iChargers > 0) {
		iChargers--;
		hArray.Push(L4D2Infected_Charger);
	}
}

bool IsTankInPlay()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == L4D2Team_Infected) {
			if (GetEntProp(i, Prop_Send, "m_zombieClass") == L4D2Infected_Tank && IsPlayerAlive(i)) {
				return true;
			}
		}
	}

	return false;
}

bool IsInfectedTeamFull()
{
	int iSICount = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == L4D2Team_Infected) {
			iSICount++;
		}
	}

	return (iSICount >= g_iMaxSI);
}

int IsInfectedTeamAlive()
{
	int iSICount = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == L4D2Team_Infected && IsPlayerAlive(i)) {
			iSICount++;
		}
	}

	return iSICount;
}

bool IsSupportSIAlive(int iClient)
{
	for (int i = 1; i <= MaxClients; i++) {
		if (i != iClient && IsClientInGame(i) && GetClientTeam(i) == L4D2Team_Infected && IsPlayerAlive(i)) {
			if (IsSupport(i)) {
				return true;
			}
		}
	}

	// No Support SI Alive, send back-up!
	return false;
}

bool IsSupport(int iClient)
{
	int iZClass = GetEntProp(iClient, Prop_Send, "m_zombieClass");
	return (iZClass == L4D2Infected_Boomer || iZClass == L4D2Infected_Spitter);
}
