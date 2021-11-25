#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools_sound>
#include <colors>
#include <l4d2util_constants>
#define LEFT4FRAMEWORK_INCLUDE 1
#include <left4framework>
#undef REQUIRE_PLUGIN
#include <l4d_tank_control_eq>

#define DANG "ui/pickup_secret01.wav"

public Plugin myinfo =
{
	name = "L4D2 Tank Announcer",
	author = "Visor, Forgetest, xoxo",
	description = "Announce in chat and via a sound when a Tank has spawned",
	version = "1.5",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnMapStart()
{
	PrecacheSound(DANG);
}

// This forward is always fired only for bots.
public void L4D_OnSpawnTank_Post(int iClient, const float fVecPos[3], const float fVecAng[3])
{
	char nameBuf[MAX_NAME_LENGTH];

	if (IsTankSelection()) {
		iClient = GetTankSelection();
		if (iClient > 0 && IsClientInGame(iClient)) {
			FormatEx(nameBuf, sizeof(nameBuf), "%N", iClient);
		} else {
			FormatEx(nameBuf, sizeof(nameBuf), "AI");
		}
	} else {
		HookEvent("player_spawn", Event_PlayerSpawn);
		return;
	}

	CPrintToChatAll("{red}[{default}!{red}] {olive}Tank {default}({red}Control: %s{default}) has spawned!", nameBuf);
	EmitSoundToAll(DANG);
}

public void Event_PlayerSpawn(Event hEvent, char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	// Tanky Client?
	if (IsTank(iClient) && !IsFakeClient(iClient)) {
		CPrintToChatAll("{red}[{default}!{red}] {olive}Tank {default}({red}Control: %N{default}) has spawned!", iClient);
		EmitSoundToAll(DANG);
		UnhookEvent("player_spawn", Event_PlayerSpawn);
	}
}

/**
 * Is the player the tank?
 *
 * @param client client ID
 * @return bool
 */
bool IsTank(int iClient)
{
	return (IsClientInGame(iClient)
		&& GetClientTeam(iClient) == L4D2Team_Infected
		&& GetEntProp(iClient, Prop_Send, "m_zombieClass") == L4D2Infected_Tank);
}

/*
 * @return			true if GetTankSelection exist false otherwise.
 */
bool IsTankSelection()
{
	return (GetFeatureStatus(FeatureType_Native, "GetTankSelection") != FeatureStatus_Unknown);
}
