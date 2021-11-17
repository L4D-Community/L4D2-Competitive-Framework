#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <l4d2util_constants>

public Plugin myinfo =
{
	name = "L4D2 Tank & Charger M2 Fix",
	description = "Stops Shoves slowing the Tank and Charger Down",
	author = "Sir, Visor",
	version = "1.1",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public Action L4D_OnShovedBySurvivor(int iShover, int iShovee, const float fVector[3])
{
	if (!IsSurvivor(iShover) || !IsInfected(iShovee)) {
		return Plugin_Continue;
	}

	if (IsTankOrCharger(iShovee)) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action L4D2_OnEntityShoved(int iShover, int iShoveeEnt, int iWeapon, float fVector[3], bool bIsHunterDeadstop)
{
	if (!IsSurvivor(iShover) || !IsInfected(iShoveeEnt)) {
		return Plugin_Continue;
	}

	if (IsTankOrCharger(iShoveeEnt)) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

bool IsTankOrCharger(int iClient)
{
	int iZClass = GetEntProp(iClient, Prop_Send, "m_zombieClass");
	return ((iZClass == L4D2Infected_Charger || iZClass == L4D2Infected_Tank) && IsPlayerAlive(iClient));
}

bool IsSurvivor(int iClient)
{
	return (iClient > 0
		&& iClient <= MaxClients
		&& IsClientInGame(iClient)
		&& GetClientTeam(iClient) == L4D2Team_Survivor);
}

bool IsInfected(int iClient)
{
	return (iClient > 0
		&& iClient <= MaxClients
		&& IsClientInGame(iClient)
		&& GetClientTeam(iClient) == L4D2Team_Infected);
}
