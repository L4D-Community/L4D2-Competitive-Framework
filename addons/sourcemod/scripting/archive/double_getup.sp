/*
	SourcePawn is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2015 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
// Possible getups:
// Charger clear which still incaps
// Smoker pull on a Hunter getup
// Insta-clear hunter during any getup
// Tank rock on a charger getup
// Tank punch on a charger getup
// Tank rock on a multi-charger getup
// Tank punch on a multi-charge getup

// Missing getups:
// Tank punch on rock getup
// Tank punch on jockeyed player

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util> // Needed for IdentifySurvivor calls. I use survivor indices rather than client indices in case someone leaves while incapped (with a pending getup).
#define L4D2_DIRECT_INCLUDE
#include <left4framework> // Needed for forcing players to have a getup animation.

#define DEBUG 0

enum
{
	eUPRIGHT = 0,
	eINCAPPED,
	eSMOKED,
	eJOCKEYED,
	eHUNTER_GETUP,
	eINSTACHARGED, // 5
	eCHARGED,
	eCHARGER_GETUP,
	eMULTI_CHARGED,
	eTANK_ROCK_GETUP,
	eTANK_PUNCH_FLY, // 10
	eTANK_PUNCH_GETUP,
	eTANK_PUNCH_FIX,
	eTANK_PUNCH_JOCKEY_FIX
};

ConVar
	g_hCvarRockPunchFix = null,
	g_hCvarLongerTankPunchGetup = null;

bool
	g_bLateLoad = false;

int
	g_iPendingGetups[SurvivorCharacter_Size] = {0, ...}, // This is used to track the number of pending getups. The collective opinion is that you should have at most 1.
	g_iCurrentSequence[SurvivorCharacter_Size] = {0, ...}, // Kept to track when a player changes sequences, i.e. changes animations.
	g_iPlayerState[SurvivorCharacter_Size] = {eUPRIGHT, ...}; // Since there are multiple sequences for each animation, this acts as a simpler way to track a player's state.

bool
	g_bInterrupt[SurvivorCharacter_Size] = {false, ...}; // If the player was getting up, and that getup is interrupted. This alows us to break out of the GetupTimer loop.

public const int
	// Nick, Rochelle, Coach, Ellis, Bill, Zoey, Louis, Francis //correct order
	g_iTankFlyAnim[SurvivorCharacter_Size] = {628, 636, 628, 633, 536, 545, 536, 539}; //correct order

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	g_bLateLoad = bLate;

	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "L4D2 Get-Up Fix",
	author = "Darkid, Jacob",
	description = "Fixes the problem when, after completing a getup animation, you have another one.",
	version = "3.8",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	g_hCvarRockPunchFix = CreateConVar("rock_punch_fix", "1", "When a tank punches someone who is getting up from a rock, cause them to have an extra getup.", _, true, 0.0, true, 1.0);
	g_hCvarLongerTankPunchGetup = CreateConVar("longer_tank_punch_getup", "0", "When a tank punches someone give them a slightly longer getup.", _, true, 0.0, true, 1.0);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("tongue_grab", Event_TongueGrab);
	HookEvent("jockey_ride", Event_JockeyRide);
	HookEvent("jockey_ride_end", Event_JockeyRideEnd);
	HookEvent("tongue_release", Event_TongueRelease);
	HookEvent("pounce_stopped", Event_PounceStopped);
	HookEvent("charger_impact", Event_ChangerImpact);
	HookEvent("charger_carry_end", Event_ChargerCarryEnd);
	HookEvent("charger_pummel_start", Event_ChargerPummelStart);
	HookEvent("charger_pummel_end", Event_ChargerPummelEnd);
	HookEvent("player_incapacitated", Event_PlayerIncap);
	HookEvent("revive_success", Event_PlayerRevive);

	InitSurvivorModelTrie(); // Not necessary, but speeds up IdentifySurvivor() calls.

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				OnClientPostAdminCheck(i);
			}
		}
	}
}

// Used to check for tank rocks and tank punches.
public void OnClientPostAdminCheck(int iClient)
{
	SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	for (int iSurvivor = 0; iSurvivor < SurvivorCharacter_Size; iSurvivor++) {
		g_iPlayerState[iSurvivor] = eUPRIGHT;
	}
}

// If a player is smoked while getting up from a hunter, the getup is interrupted.
public void Event_TongueGrab(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("victim"));
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	if (g_iPlayerState[iSurvivor] == eHUNTER_GETUP) {
		g_bInterrupt[iSurvivor] = true;
	}
}

public void Event_JockeyRide(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("victim"));
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	g_iPlayerState[iSurvivor] = eJOCKEYED;
}

public void Event_JockeyRideEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("victim"));
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	if (g_iPlayerState[iSurvivor] == eJOCKEYED) {
		g_iPlayerState[iSurvivor] = eUPRIGHT;
	}
}

// If a player is cleared from a smoker, they should not have a getup.
public void Event_TongueRelease(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("victim"));
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	if (g_iPlayerState[iSurvivor] == eINCAPPED) {
		return;
	}

	g_iPlayerState[iSurvivor] = eUPRIGHT;
	_CancelGetup(iClient);
}

// If a player is cleared from a hunter, they should have 1 getup.
public void Event_PounceStopped(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("victim"));
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	if (g_iPlayerState[iSurvivor] == eINCAPPED) {
		return;
	}

	// If someone gets cleared WHILE they are otherwise getting up, they double-getup.
	if (IsGettingUp(iSurvivor)) {
		g_iPendingGetups[iSurvivor]++;
		return;
	}

	g_iPlayerState[iSurvivor] = eHUNTER_GETUP;
	_GetupTimer(iClient);
}

// If a player is impacted during a charged, they should have 1 getup.
public void Event_ChangerImpact(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iSurvivor = IdentifySurvivor(GetClientOfUserId(hEvent.GetInt("victim")));
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	if (g_iPlayerState[iSurvivor] == eINCAPPED) {
		return;
	}

	g_iPlayerState[iSurvivor] = eMULTI_CHARGED;
}

// If a player is cleared from a charger, they should have 1 getup.
public void Event_ChargerCarryEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iSurvivor = IdentifySurvivor(GetClientOfUserId(hEvent.GetInt("victim")));
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	// If the player is incapped when the charger lands, they will getup after being revived.
	if (g_iPlayerState[iSurvivor] == eINCAPPED) {
		g_iPendingGetups[iSurvivor]++;
	}

	g_iPlayerState[iSurvivor] = eINSTACHARGED;
}

// This event defines when a player transitions from being insta-charged to being pummeled.
public void Event_ChargerPummelStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iSurvivor = IdentifySurvivor(GetClientOfUserId(hEvent.GetInt("victim")));
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	if (g_iPlayerState[iSurvivor] == eINCAPPED) {
		return;
	}

	g_iPlayerState[iSurvivor] = eCHARGED;
}

// If a player is cleared from a charger, they should have 1 getup.
public void Event_ChargerPummelEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("victim"));
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	if (g_iPlayerState[iSurvivor] == eINCAPPED) {
		return;
	}

	g_iPlayerState[iSurvivor] = eCHARGER_GETUP;
	_GetupTimer(iClient);
}

// If a player is incapped, mark that down. This will interrupt their animations, if they have any.
public void Event_PlayerIncap(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iSurvivor = IdentifySurvivor(GetClientOfUserId(hEvent.GetInt("userid")));
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	// If the player is incapped when the charger lands, they will getup after being revived.
	if (g_iPlayerState[iSurvivor] == eINSTACHARGED) {
		g_iPendingGetups[iSurvivor]++;
	}

	g_iPlayerState[iSurvivor] = eINCAPPED;
}

// When a player is picked up, they should have 0 getups.
public void Event_PlayerRevive(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("subject"));
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return;
	}

	g_iPlayerState[iSurvivor] = eUPRIGHT;
	_CancelGetup(iClient);
}

// A catch-all to handle damage that is not associated with an event. I use this instead of player_hurt because it ignores godframes.
public Action OnTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &fDamageType)
{
	int iSurvivor = IdentifySurvivor(iVictim);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return Plugin_Continue;
	}

	char sWeapon[32];
	GetEdictClassname(iInflictor, sWeapon, sizeof(sWeapon));
	if (strcmp(sWeapon, "weapon_tank_claw") == 0) {
		if (g_iPlayerState[iSurvivor] == eCHARGER_GETUP) {
			g_bInterrupt[iSurvivor] = true;
		} else if (g_iPlayerState[iSurvivor] == eMULTI_CHARGED) {
			g_iPendingGetups[iSurvivor]++;
		}

		if (g_iPlayerState[iSurvivor] == eTANK_ROCK_GETUP && g_hCvarRockPunchFix.BoolValue) {
			g_iPlayerState[iSurvivor] = eTANK_PUNCH_FIX;
		} else if (g_iPlayerState[iSurvivor] == eJOCKEYED) {
			g_iPlayerState[iSurvivor] = eTANK_PUNCH_JOCKEY_FIX;
			_TankLandTimer(iVictim);
		} else {
			g_iPlayerState[iSurvivor] = eTANK_PUNCH_FLY;
			// Watches and waits for the survivor to enter their getup animation. It is possible to skip the fly animation, so this can't be tracked by state-based logic.
			_TankLandTimer(iVictim);
		}
	} else if (strcmp(sWeapon, "tank_rock") == 0) {
		if (g_iPlayerState[iSurvivor] == eCHARGER_GETUP) {
			g_bInterrupt[iSurvivor] = true;
		} else if (g_iPlayerState[iSurvivor] == eMULTI_CHARGED) {
			g_iPendingGetups[iSurvivor]++;
		}

		g_iPlayerState[iSurvivor] = eTANK_ROCK_GETUP;

		_GetupTimer(iVictim);
	}

	return Plugin_Continue;
}

// Detects when a player lands from a tank punch.
void _TankLandTimer(int iClient)
{
	CreateTimer(0.04, TankLandTimer, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action TankLandTimer(Handle hTimer, any iClient)
{
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return Plugin_Stop;
	}

	// I consider players to have "landed" only once they stop being in the fly anim or the landing anim (fly + 1).
	if (GetEntProp(iClient, Prop_Send, "m_nSequence") == g_iTankFlyAnim[iSurvivor]
		|| GetEntProp(iClient, Prop_Send, "m_nSequence") == (g_iTankFlyAnim[iSurvivor] + 1)
	) {
		return Plugin_Continue;
	}

	int iAnimation = (g_hCvarLongerTankPunchGetup.BoolValue) ? ANIM_SHOVED_BY_TEAMMATE : ANIM_TANK_PUNCH_GETUP; // 96 is the tank punch getup.

	if (g_iPlayerState[iSurvivor] == eTANK_PUNCH_JOCKEY_FIX) {
		// When punched out of a jockey, the player goes into land (fly+1) for an arbitrary number of frames, then enters land (fly+2) for an arbitrary number of frames. Once they're done "landing" we give them the getup they deserve.
		if (GetEntProp(iClient, Prop_Send, "m_nSequence") == (g_iTankFlyAnim[iSurvivor] + 2)) {
			return Plugin_Continue;
		}

		#if DEBUG
			PrintToChatAll("[Getup] Giving %N an extra getup...", iClient);
		#endif

		L4D2Direct_DoAnimationEvent(iClient, iAnimation);
	}

	if (g_iPlayerState[iSurvivor] == eTANK_PUNCH_FLY) {
		g_iPlayerState[iSurvivor] = eTANK_PUNCH_GETUP;
	}

	L4D2Direct_DoAnimationEvent(iClient, iAnimation);

	_GetupTimer(iClient);
	return Plugin_Stop;
}

// Detects when a player finishes getting up, i.e. their sequence changes.
void _GetupTimer(int iClient)
{
	CreateTimer(0.04, GetupTimer, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action GetupTimer(Handle hTimer, int iClient)
{
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return Plugin_Stop;
	}

	if (g_iCurrentSequence[iSurvivor] == 0) {
		#if DEBUG
			PrintToChatAll("[Getup] %N is getting up...", iClient);
		#endif

		g_iCurrentSequence[iSurvivor] = GetEntProp(iClient, Prop_Send, "m_nSequence");
		g_iPendingGetups[iSurvivor]++;
		return Plugin_Continue;
	} else if (g_bInterrupt[iSurvivor]) {
		#if DEBUG
			PrintToChatAll("[Getup] %N's getup was interrupted!", iClient);
		#endif

		g_bInterrupt[iSurvivor] = false;
		// g_iCurrentSequence[iSurvivor] = 0;

		return Plugin_Stop;
	}

	if (g_iCurrentSequence[iSurvivor] == GetEntProp(iClient, Prop_Send, "m_nSequence")) {
		return Plugin_Continue;
	} else if (g_iPlayerState[iSurvivor] == eTANK_PUNCH_FIX) {
		#if DEBUG
			PrintToChatAll("[Getup] Giving %N an extra getup...", iClient);
		#endif

		if (g_hCvarLongerTankPunchGetup.BoolValue) {
			L4D2Direct_DoAnimationEvent(iClient, ANIM_SHOVED_BY_TEAMMATE);
			g_iPlayerState[iSurvivor] = eCHARGER_GETUP;
		} else {
			L4D2Direct_DoAnimationEvent(iClient, ANIM_TANK_PUNCH_GETUP); // 96 is the tank punch getup.
			g_iPlayerState[iSurvivor] = eTANK_PUNCH_GETUP;
		}

		g_iCurrentSequence[iSurvivor] = 0;
		_TankLandTimer(iClient);

		return Plugin_Stop;
	} else {
		#if DEBUG
			PrintToChatAll("[Getup] %N finished getting up.", iClient);
		#endif

		g_iPlayerState[iSurvivor] = eUPRIGHT;
		g_iPendingGetups[iSurvivor]--;
		// After a player finishes getting up, cancel any remaining getups.
		_CancelGetup(iClient);
	}

	return Plugin_Stop;
}

// Gets players out of pending animations, i.e. sets their current frame in the animation to 1000.
void _CancelGetup(int iClient)
{
	CreateTimer(0.04, CancelGetup, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action CancelGetup(Handle hTimer, int iClient)
{
	int iSurvivor = IdentifySurvivor(iClient);
	if (iSurvivor == SurvivorCharacter_Invalid) {
		return Plugin_Stop;
	}

	if (g_iPendingGetups[iSurvivor] <= 0) {
		g_iPendingGetups[iSurvivor] = 0;
		g_iCurrentSequence[iSurvivor] = 0;

		return Plugin_Stop;
	}

#if DEBUG
	LogMessage("[Getup] Canceled extra getup for player %d.", iSurvivor);
#endif

	g_iPendingGetups[iSurvivor]--;
	SetEntPropFloat(iClient, Prop_Send, "m_flCycle", 1000.0); // Jumps to frame 1000 in the animation, effectively skipping it.

	return Plugin_Continue;
}

// If the player is in any of the getup states.
bool IsGettingUp(int iSurvivor)
{
	switch (g_iPlayerState[iSurvivor]) {
		case (eHUNTER_GETUP): {
			return true;
		}
		case (eCHARGER_GETUP): {
			return true;
		}
		case (eMULTI_CHARGED): {
			return true;
		}
		case (eTANK_PUNCH_GETUP): {
			return true;
		}
		case (eTANK_ROCK_GETUP): {
			return true;
		}
	}

	return false;
}
