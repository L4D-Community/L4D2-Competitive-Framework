/*
	Changelog
	---------
		1.0.9
			- used CanadaRox's SDK method for detecting staggers (since it's less likely to have false positives).

		1.0.8
			- fixed bug where clients with maxclient index would be ignored

		1.0.7
			- reset original way of dealing extra skeet damage to reward killer.

		1.0.6
			- (dcx2) Removed ground-tracking timer for hunter skeet, switched to m_isAttemptingToPounce
			- (dcx2) Removed handles from global variables, since they are unused after OnPluginStart
			- (dcx2) Switched hunter skeeting to SetEntityHealth() for increased compatibility with damage tracking plugins (ie l4d2_assist)

		1.0.5
			- (dcx2) Added enable cvar
			- (dcx2) cached pounce interrupt cvar
			- (dcx2) fixed charger debuff calculation

		1.0.4
			- Used dcx2's much better IN_ATTACK2 method of blocking stumble-scratching.

		1.0.3
			- Added stumble-negation inflictor check so only SI scratches are affected.

		1.0.2
			- Fixed incorrect bracketing that caused error spam. (Re-fixed because drunk)

		1.0.0
			- Blocked AI scratches-while-stumbling from doing any damage.
			- Replaced clunky charger tracking with simple netprop check.

		0.0.5 and older
			- Small fix for chargers getting 1 damage for 0-damage events.
			- simulates human-charger damage behavior while charging for AI chargers.
			- simulates human-hunter skeet behavior for AI hunters.

	-----------------------------------------------------------------------------------------------------------------------------------------------------
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <l4d2util_constants>

#define GAMEDATA_FILE			"staggersolver"

// Bit flags to enable individual features of the plugin
#define SKEET_POUNCING_AI		(0x01)
#define DEBUFF_CHARGING_AI		(0x02)
#define BLOCK_STUMBLE_SCRATCH	(0x04)
#define ALL_FEATURES			(SKEET_POUNCING_AI | DEBUFF_CHARGING_AI | BLOCK_STUMBLE_SCRATCH)

// Globals
Handle
	g_hIsStaggering = null;

bool
	g_bLateLoad = false;

int
	g_iEnabledFlags = ALL_FEATURES,							// Enables individual features of the plugin
	g_iPounceInterrupt = 150,								// Caches pounce interrupt cvar's value
	g_iHunterSkeetDamage[MAXPLAYERS + 1] = {0, ...};		// How much damage done in a single hunter leap so far

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	g_bLateLoad = bLate;

	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "Bot SI skeet/level damage fix",
	author = "Tabun, dcx2, A1m`",
	description = "Makes AI SI take (and do) damage like human SI.",
	version = "1.1",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	InitGameData();

	// find/create cvars, hook changes, cache current values
	ConVar hCvarEnabled = CreateConVar(
		"sm_aidmgfix_enable", \
		"7", \
		"Bit flag: Enables plugin features (add together): 1=Skeet pouncing AI, 2=Debuff charging AI, 4=Block stumble scratches, 7=all, 0=off", \
		_, true, 0.0, true, 7.0 \
	);

	ConVar hCvarPounceInterrupt = FindConVar("z_pounce_damage_interrupt");

	hCvarEnabled.AddChangeHook(OnAIDamageFixEnableChanged);
	hCvarPounceInterrupt.AddChangeHook(OnPounceInterruptChanged);

	g_iEnabledFlags = hCvarEnabled.IntValue;
	g_iPounceInterrupt = hCvarPounceInterrupt.IntValue;

	// events
	HookEvent("ability_use", Event_AbilityUse, EventHookMode_Post);

	// hook when loading late
	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				OnClientPutInServer(i);
			}
		}
	}
}

void InitGameData()
{
	// sdkhook
	Handle hGameConf = LoadGameConfigFile(GAMEDATA_FILE);
	if (hGameConf == null) {
		SetFailState("[aidmgfix] Could not load game config file (staggersolver.txt).");
	}

	StartPrepSDKCall(SDKCall_Player);

	if (!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "IsStaggering")) {
		SetFailState("[aidmgfix] Could not find signature IsStaggering.");
	}

	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hIsStaggering = EndPrepSDKCall();

	if (g_hIsStaggering == null) {
		SetFailState("[aidmgfix] Failed to load signature IsStaggering");
	}

	delete hGameConf;
}

public void OnAIDamageFixEnableChanged(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	g_iEnabledFlags = StringToInt(sNewValue);
}

public void OnPounceInterruptChanged(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	g_iPounceInterrupt = StringToInt(sNewValue);
}

public void OnClientPutInServer(int iClient)
{
	// hook bots spawning
	SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);

	g_iHunterSkeetDamage[iClient] = 0;
}

public Action OnTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType)
{
	// Must be enabled, victim and attacker must be ingame, damage must be greater than 0, victim must be AI infected
	if (!g_iEnabledFlags || fDamage <= 0.0) {
		return Plugin_Continue;
	}

	if (!IsClientAndInGame(iVictim) || GetClientTeam(iVictim) != L4D2Team_Infected || !IsFakeClient(iVictim)) {
		return Plugin_Continue;
	}

	if (!IsClientAndInGame(iAttacker)) {
		return Plugin_Continue;
	}

	switch (GetEntProp(iVictim, Prop_Send, "m_zombieClass")) {
		case L4D2Infected_Hunter: {
			// Is this AI hunter attempting to pounce?
			if (g_iEnabledFlags & SKEET_POUNCING_AI) {
				if (GetEntProp(iVictim, Prop_Send, "m_isAttemptingToPounce", 1) < 1) {
					return Plugin_Continue;
				}
				g_iHunterSkeetDamage[iVictim] += RoundToFloor(fDamage);

				// have we skeeted it?
				if (g_iHunterSkeetDamage[iVictim] >= g_iPounceInterrupt) {
					// Skeet the hunter
					g_iHunterSkeetDamage[iVictim] = 0;
					fDamage = float(GetClientHealth(iVictim));
					return Plugin_Changed;
				}
			}
		}
		case L4D2Infected_Charger: {
			// Is this AI charger charging?
			if (g_iEnabledFlags & DEBUFF_CHARGING_AI) {
				// Is this AI charger charging?
				int iAbilityEnt = GetEntPropEnt(iVictim, Prop_Send, "m_customAbility");
				if (iAbilityEnt == -1 || !IsValidEdict(iAbilityEnt)) {
					return Plugin_Continue;
				}

				if (GetEntProp(iAbilityEnt, Prop_Send, "m_isCharging", 1) > 0) {
					// Game does Floor(Floor(fDamage) / 3 - 1) to charging AI chargers, so multiply Floor(fDamage)+1 by 3
					fDamage = (fDamage - FloatFraction(fDamage) + 1.0) * 3.0;
					return Plugin_Changed;
				}
			}
		}
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int iClient, int &iButtons)
{
	// If the AI Infected is staggering, block melee so they can't scratch
	if ((g_iEnabledFlags & BLOCK_STUMBLE_SCRATCH)
		/*&& IsClientAndInGame(iClient)*/
		&& GetClientTeam(iClient) == L4D2Team_Infected
		&& IsFakeClient(iClient)
		&& SDKCall(g_hIsStaggering, iClient)
	) {
		iButtons &= ~IN_ATTACK2;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

// hunters pouncing / tracking
public void Event_AbilityUse(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// track hunters pouncing
	char sAbilityName[64];
	hEvent.GetString("ability", sAbilityName, sizeof(sAbilityName));

	if (strcmp(sAbilityName, "ability_lunge", false) != 0) {
		return;
	}

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || GetClientTeam(iClient) != L4D2Team_Infected) {
		return;
	}

	// Clear skeet tracking damage each time the hunter starts a pounce
	g_iHunterSkeetDamage[iClient] = 0;
}

bool IsClientAndInGame(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient));
}
