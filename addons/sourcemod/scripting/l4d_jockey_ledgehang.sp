#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define ARRAY_INDEX_DURATION 0
#define ARRAY_INDEX_TIMESTAMP 1

ConVar g_hCvarJockeyLedgeHang = null;

public Plugin myinfo =
{
	name = "L4D2 Jockey Ledge Hang Recharge",
	author = "Jahze, A1m`",
	version = "1.4",
	description = "Adds a cvar to adjust the recharge timer of a jockey after he ledge hangs a survivor.",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	g_hCvarJockeyLedgeHang = CreateConVar("z_leap_interval_post_ledge_hang", "10", "How long before a jockey can leap again after a ledge hang");

	HookEvent("jockey_ride_end", JockeyRideEnd, EventHookMode_Post);
}

public void JockeyRideEnd(Event hEvent, const char[] name, bool dontBroadcast)
{
	int iJockeyVictim = GetClientOfUserId(hEvent.GetInt("victim"));

	if (iJockeyVictim < 1 || !IsHangingFromLedge(iJockeyVictim)) {
		return;
	}

	int iJockeyAttacker = GetClientOfUserId(hEvent.GetInt("userid"));
	int iAbility = GetEntPropEnt(iJockeyAttacker, Prop_Send, "m_customAbility");
	if (iAbility == -1) {
		return;
	}

	char sAbilityName[32];
	GetEdictClassname(iAbility, sAbilityName, sizeof(sAbilityName));
	if (strcmp(sAbilityName, "ability_leap") != 0) {
		return;
	}

	/*
	 * Table: m_nextActivationTimer (offset 1104) (type DT_CountdownTimer)
	 *	Member: m_duration (offset 4) (type float) (bits 0) (NoScale)
	 *	Member: m_timestamp (offset 8) (type float) (bits 0) (NoScale)
	*/
	float fLedgeHangInterval = g_hCvarJockeyLedgeHang.FloatValue;
	SetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", fLedgeHangInterval, ARRAY_INDEX_DURATION);
	SetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", GetGameTime() + fLedgeHangInterval, ARRAY_INDEX_TIMESTAMP);
}

bool IsHangingFromLedge(int iClient)
{
	return (GetEntProp(iClient, Prop_Send, "m_isHangingFromLedge", 1) > 0
		|| GetEntProp(iClient, Prop_Send, "m_isFallingFromLedge", 1) > 0);
}
