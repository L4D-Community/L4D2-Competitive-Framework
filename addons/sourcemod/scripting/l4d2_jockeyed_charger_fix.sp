#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

#define Z_JOCKEY 5
#define Z_CHARGER 6
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define GAMEDATA "l4d2_si_ability"

int m_queuedPummelAttacker = -1;

Handle hCLeap_OnTouch;

public Plugin myinfo =
{
	name = "L4D2 Jockeyed Charger Fix",
	author = "Visor, A1m`",
	description = "Prevent jockeys and chargers from capping the same target simultaneously",
	version = "1.5",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	Handle hGamedata = LoadGameConfigFile(GAMEDATA);

	if (!hGamedata) {
		SetFailState("Gamedata '%s.txt' missing or corrupt.", GAMEDATA);
	}

	m_queuedPummelAttacker = GameConfGetOffset(hGamedata, "CTerrorPlayer->m_queuedPummelAttacker");
	if (m_queuedPummelAttacker == -1) {
		SetFailState("Failed to get offset 'CTerrorPlayer->m_queuedPummelAttacker'.");
	}

	int iCleapOnTouch = GameConfGetOffset(hGamedata, "CBaseAbility::OnTouch");
	if (iCleapOnTouch == -1) {
		SetFailState("Failed to get offset 'CBaseAbility::OnTouch'.");
	}

	hCLeap_OnTouch = DHookCreate(iCleapOnTouch, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, CLeap_OnTouch);
	DHookAddParam(hCLeap_OnTouch, HookParamType_CBaseEntity);

	delete hGamedata;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (strcmp(classname, "ability_leap") == 0) {
		DHookEntity(hCLeap_OnTouch, false, entity);
	}
}

public MRESReturn CLeap_OnTouch(int pThis, Handle hParams)
{
	int jockey = GetEntPropEnt(pThis, Prop_Send, "m_owner");
	int survivor = DHookGetParam(hParams, 1);
	if (IsValidJockey(jockey)/* probably redundant */ && IsSurvivor(survivor))
	{
		if (IsValidCharger(GetCarrier(survivor))
		|| IsValidCharger(GetPummelQueueAttacker(survivor))
		|| IsValidCharger(GetPummelAttacker(survivor))
		) {
			return MRES_Supercede;
		}
	}
	return MRES_Ignored;
}

bool IsSurvivor(int client)
{
	return (client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR);
}

bool IsValidJockey(int client)
{
	return (client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_INFECTED
		&& GetEntProp(client, Prop_Send, "m_zombieClass") == Z_JOCKEY);
}

bool IsValidCharger(int client)
{
	return (client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_INFECTED
		&& GetEntProp(client, Prop_Send, "m_zombieClass") == Z_CHARGER);
}

int GetCarrier(int survivor)
{
	return GetEntPropEnt(survivor, Prop_Send, "m_carryAttacker");
}

int GetPummelQueueAttacker(int survivor)
{
	return GetEntDataEnt2(survivor, m_queuedPummelAttacker);
}

int GetPummelAttacker(int survivor)
{
	return GetEntPropEnt(survivor, Prop_Send, "m_pummelAttacker");
}
