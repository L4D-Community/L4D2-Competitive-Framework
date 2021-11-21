#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#define L4D2_DIRECT_INCLUDE 1
#define LEFT4FRAMEWORK_INCLUDE 1
#include <left4framework>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util>
#include <colors>
#undef REQUIRE_PLUGIN
#include <caster_system>

#define MAX_STEAMID_LENGTH 32

ArrayList
	g_hWhosHadTank = null;

char
	g_sQueuedTankSteamId[MAX_STEAMID_LENGTH] = "";

ConVar
	g_hCvarTankPrint = null,
	g_hCvarTankDebug = null;

bool
	g_bCasterSystemAvailable = false;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	CreateNative("GetTankSelection", Native_GetTankSelection);

	RegPluginLibrary("l4d_tank_control_eq");
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "L4D2 Tank Control",
	author = "arti",
	description = "Distributes the role of the tank evenly throughout the team",
	version = "1.0",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	// Load translations (for targeting player)
	LoadTranslations("common.phrases");

	// Event hooks
	HookEvent("player_left_start_area", Event_PlayerLeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("tank_killed", Event_TankKilled, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

	// Initialise the tank arrays/data values
	g_hWhosHadTank = new ArrayList(ByteCountToCells(MAX_STEAMID_LENGTH));

	// Admin commands
	RegAdminCmd("sm_tankshuffle", TankShuffle_Cmd, ADMFLAG_SLAY, "Re-picks at random someone to become tank.");
	RegAdminCmd("sm_givetank", GiveTank_Cmd, ADMFLAG_SLAY, "Gives the tank to a selected player");

	// Register the boss commands
	RegConsoleCmd("sm_tank", Tank_Cmd, "Shows who is becoming the tank.");
	RegConsoleCmd("sm_boss", Tank_Cmd, "Shows who is becoming the tank.");
	RegConsoleCmd("sm_witch", Tank_Cmd, "Shows who is becoming the tank.");

	// Cvars
	g_hCvarTankPrint = CreateConVar("tankcontrol_print_all", "0", "Who gets to see who will become the tank? (0 = Infected, 1 = Everyone)", _, true, 0.0, true, 1.0);
	g_hCvarTankDebug = CreateConVar("tankcontrol_debug", "0", "Whether or not to debug to console", _, true, 0.0, true, 1.0);
}

public void OnAllPluginsLoaded()
{
	g_bCasterSystemAvailable = LibraryExists("caster_system");
}

public void OnLibraryAdded(const char[] sPluginName)
{
	if (strcmp(sPluginName, "caster_system") == 0) {
		g_bCasterSystemAvailable = true;
	}
}

public void OnLibraryRemoved(const char[] sPluginName)
{
	if (strcmp(sPluginName, "caster_system") == 0) {
		g_bCasterSystemAvailable = false;
	}
}

public void OnClientDisconnect(int iClient)
{
	char sTmpSteamId[MAX_STEAMID_LENGTH];
	GetClientAuthId(iClient, AuthId_Steam2, sTmpSteamId, sizeof(sTmpSteamId));

	if (strcmp(g_sQueuedTankSteamId, sTmpSteamId) == 0) {
		Frame_ChooseTank(0);
		Frame_OutputTankToAll(0);
	}
}

/**
 * When a new game starts, reset the tank pool.
 */
public void Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	CreateTimer(10.0, Timer_NewGame, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_NewGame(Handle hTimer)
{
	// If it's a new game, reset the tank pool
	if (L4D2Direct_GetVSCampaignScore(0) == 0 && L4D2Direct_GetVSCampaignScore(1) == 0) {
		g_hWhosHadTank.Clear();
		g_sQueuedTankSteamId = "";
	}

	return Plugin_Stop;
}

/**
 * When the round ends, reset the active tank.
 */
public void Event_RoundEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	g_sQueuedTankSteamId = "";
}

/**
 * When a player leaves the start area, choose a tank and output to all.
 */
public void Event_PlayerLeftStartArea(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	Frame_ChooseTank(0);
	Frame_OutputTankToAll(0);
}

/**
 * When the queued tank switches teams, choose a new one
 */
public void Event_PlayerTeam(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (hEvent.GetBool("disconnect")) {
		return;
	}

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1) {
		return;
	}

	if (hEvent.GetInt("oldteam") != L4D2Team_Infected) {
		return;
	}

	char sTmpSteamId[MAX_STEAMID_LENGTH];
	GetClientAuthId(iClient, AuthId_Steam2, sTmpSteamId, sizeof(sTmpSteamId));

	if (strcmp(g_sQueuedTankSteamId, sTmpSteamId) == 0) {
		RequestFrame(Frame_ChooseTank, 0);
		RequestFrame(Frame_OutputTankToAll, 0);
	}
}

/**
 * When the tank dies, requeue a player to become tank (for finales)
 */
public void Event_PlayerDeath(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iVictim = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iVictim < 1/* || !IsClientInGame(victim)*/) {
		return;
	}

	int iZombieClass = GetEntProp(iVictim, Prop_Send, "m_zombieClass");
	if (iZombieClass != L4D2Infected_Tank) {
		return;
	}

	if (g_hCvarTankDebug.BoolValue) {
		PrintToConsoleAll("[TC] Tank died(1), choosing a new tank");
	}

	Frame_ChooseTank(0);
}

public void Event_TankKilled(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (g_hCvarTankDebug.BoolValue) {
		PrintToConsoleAll("[TC] Tank died(2), choosing a new tank");
	}

	Frame_ChooseTank(0);
}

/**
 * When a player wants to find out whos becoming tank,
 * output to them.
 */
public Action Tank_Cmd(int iClient, int iArgs)
{
	if (iClient == 0) {
		PrintToServer("[SM] This command is not available for the server!");
		return Plugin_Handled;
	}

	// Only output if we have a queued tank
	if (!strcmp(g_sQueuedTankSteamId, "")) {
		return Plugin_Handled;
	}

	int iTankClientId = getInfectedPlayerBySteamId(g_sQueuedTankSteamId);
	if (iTankClientId != -1) {
		// If on infected, print to entire team
		if (GetClientTeam(iClient) == L4D2Team_Infected || IsPlayerCaster(iClient)) {
			if (iClient == iTankClientId) {
				CPrintToChat(iClient, "{red}<{default}Tank Selection{red}> {green}You {default}will become the {red}Tank{default}!");
			} else {
				CPrintToChat(iClient, "{red}<{default}Tank Selection{red}> {olive}%N {default}will become the {red}Tank!", iTankClientId);
			}
		}
	}

	return Plugin_Handled;
}

/**
 * Shuffle the tank (randomly give to another player in
 * the pool.
 */
public Action TankShuffle_Cmd(int iClient, int iArgs)
{
	Frame_ChooseTank(0);
	Frame_OutputTankToAll(0);

	return Plugin_Handled;
}

/**
 * Give the tank to a specific player.
 */
public Action GiveTank_Cmd(int iClient, int iArgs)
{
	if (iArgs != 1) {
		ReplyToCommand(iClient, "[SM] Usage: sm_givetank <#userid|name>");
		return Plugin_Handled;
	}

	char sArg[MAX_NAME_LENGTH];
	GetCmdArg(1, sArg, sizeof(sArg));

	int iTarget = FindTarget(iClient, sArg);
	if (iTarget == -1) {
		return Plugin_Handled;
	}

	if (IsFakeClient(iTarget) || GetClientTeam(iTarget) != L4D2Team_Infected) {
		ReplyToCommand(iClient, "[SM] %s not on infected. Unable to give tank.", iTarget);
		return Plugin_Handled;
	}

	char sSteamId[MAX_STEAMID_LENGTH];
	GetClientAuthId(iTarget, AuthId_Steam2, sSteamId, sizeof(sSteamId));

	strcopy(g_sQueuedTankSteamId, sizeof(g_sQueuedTankSteamId), sSteamId);
	Frame_OutputTankToAll(0);

	return Plugin_Handled;
}

/**
 * Selects a player on the infected team from random who hasn't been
 * tank and gives it to them.
 */
public void Frame_ChooseTank(any iData)
{
	// Create our pool of players to choose from
	ArrayList hInfectedPool = new ArrayList(ByteCountToCells(MAX_STEAMID_LENGTH));
	addTeamSteamIdsToArray(hInfectedPool, L4D2Team_Infected);

	// If there is nobody on the infected team, return (otherwise we'd be stuck trying to select forever)
	if (hInfectedPool.Length == 0) {
		delete hInfectedPool;
		return;
	}

	// Remove players who've already had tank from the pool.
	removeTanksFromPool(hInfectedPool, g_hWhosHadTank);

	// If the infected pool is empty, remove infected players from pool
	if (hInfectedPool.Length == 0) { // (when nobody on infected ,error)
		ArrayList hInfectedTeam = new ArrayList(ByteCountToCells(MAX_STEAMID_LENGTH));
		addTeamSteamIdsToArray(hInfectedTeam, L4D2Team_Infected);
		if (hInfectedTeam.Length > 1) {
			removeTanksFromPool(g_hWhosHadTank, hInfectedTeam);
			Frame_ChooseTank(0);
		} else {
			g_sQueuedTankSteamId = "";
		}

		delete hInfectedTeam;
		delete hInfectedPool;
		return;
	}

	// Select a random person to become tank
	int iRndIndex = GetRandomInt(0, (hInfectedPool.Length - 1));
	hInfectedPool.GetString(iRndIndex, g_sQueuedTankSteamId, sizeof(g_sQueuedTankSteamId));
	delete hInfectedPool;
}

/**
 * Make sure we give the tank to our queued player.
 */
public Action L4D_OnTryOfferingTankBot(int iTankIndex, bool &bEnterStatis)
{
	// Reset the tank's frustration if need be
	if (!IsFakeClient(iTankIndex)) {
		PrintHintText(iTankIndex, "Rage Meter Refilled");

		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && GetClientTeam(i) == L4D2Team_Infected) {
				if (iTankIndex == i) {
					CPrintToChat(i, "{red}<{default}Tank Rage{red}> {olive}Rage Meter {red}Refilled");
				} else {
					CPrintToChat(i, "{red}<{default}Tank Rage{red}> {default}({green}%N{default}'s) {olive}Rage Meter {red}Refilled", iTankIndex);
				}
			}
		}

		SetTankFrustration(iTankIndex, 100);
		L4D2Direct_SetTankPassedCount(L4D2Direct_GetTankPassedCount() + 1);
		return Plugin_Handled;
	}

	// If we don't have a queued tank, choose one
	if (!strcmp(g_sQueuedTankSteamId, "")) {
		Frame_ChooseTank(0);
	}

	// Mark the player as having had tank
	if (strcmp(g_sQueuedTankSteamId, "") != 0) {
		setTankTickets(g_sQueuedTankSteamId, 20000);
		g_hWhosHadTank.PushString(g_sQueuedTankSteamId);
	}

	return Plugin_Continue;
}

/**
 * Sets the amount of tickets for a particular player, essentially giving them tank.
 */
void setTankTickets(const char[] sSteamId, int iTickets)
{
	int iTankClientId = getInfectedPlayerBySteamId(sSteamId);

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == L4D2Team_Infected) {
			L4D2Direct_SetTankTickets(i, (i == iTankClientId) ? iTickets : 0);
		}
	}
}

/**
 * Output who will become tank
 */
public void Frame_OutputTankToAll(any iData)
{
	int iTankClientId = getInfectedPlayerBySteamId(g_sQueuedTankSteamId);

	if (iTankClientId == -1) {
		return;
	}

	if (g_hCvarTankPrint.BoolValue) {
		CPrintToChatAll("{red}<{default}Tank Selection{red}> {olive}%N {default}will become the {red}Tank!", iTankClientId);
		return;
	}

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && (GetClientTeam(i) == L4D2Team_Infected || IsPlayerCaster(i))) {
			if (iTankClientId == i) {
				CPrintToChat(i, "{red}<{default}Tank Selection{red}> {green}You {default}will become the {red}Tank{default}!");
			} else {
				CPrintToChat(i, "{red}<{default}Tank Selection{red}> {olive}%N {default}will become the {red}Tank!", iTankClientId);
			}
		}
	}
}

/**
 * Adds steam ids for a particular team to an array.
 *
 * @ param Handle steamIds
 *		The array steam ids will be added to.
 * @param int team
 *		The team to get steam ids for.
 */
void addTeamSteamIdsToArray(ArrayList hSteamIds, int iTeam)
{
	char sSteamId[MAX_STEAMID_LENGTH];

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == iTeam) {
			GetClientAuthId(i, AuthId_Steam2, sSteamId, sizeof(sSteamId));
			hSteamIds.PushString(sSteamId);
		}
	}
}

/**
 * Removes steam ids from the tank pool if they've already had tank.
 *
 * @param Handle steamIdTankPool
 *		The pool of potential steam ids to become tank.
 * @ param Handle tanks
 *		The steam ids of players who've already had tank.
 *
 * @return
 *		The pool of steam ids who haven't had tank.
 */
void removeTanksFromPool(ArrayList hSteamIdTankPool, ArrayList hTanks)
{
	int iIndex;
	char sSteamId[MAX_STEAMID_LENGTH];

	int ArraySize = hTanks.Length;
	for (int i = 0; i < ArraySize; i++) {
		hTanks.GetString(i, sSteamId, sizeof(sSteamId));
		iIndex = hSteamIdTankPool.FindString(sSteamId);

		if (iIndex != -1) {
			hSteamIdTankPool.Erase(iIndex);
		}
	}
}

/**
 * Retrieves a player's client index by their steam id.
 *
 * @param const String:steamId[]
 *		The steam id to look for.
 *
 * @return
 *		The player's client index.
 */
int getInfectedPlayerBySteamId(const char[] sSteamId)
{
	char sTmpSteamId[MAX_STEAMID_LENGTH];

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == L4D2Team_Infected) {
			GetClientAuthId(i, AuthId_Steam2, sTmpSteamId, sizeof(sTmpSteamId));

			if (strcmp(sSteamId, sTmpSteamId) == 0) {
				return i;
			}
		}
	}

	return -1;
}

bool IsPlayerCaster(int iClient)
{
	return (g_bCasterSystemAvailable && IsClientCaster(iClient));
}

/*stock void PrintToInfected(const char[] Message, any ...)
{
	char sPrint[256];
	VFormat(sPrint, sizeof(sPrint), Message, 2);

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && (GetClientTeam(i) == L4D2Team_Infected || IsPlayerCaster(i))) {
			CPrintToChat(i, "{default}%s", sPrint);
		}
	}
}*/

public int Native_GetTankSelection(Handle hPlugin, int iNumParams)
{
	return getInfectedPlayerBySteamId(g_sQueuedTankSteamId);
}
