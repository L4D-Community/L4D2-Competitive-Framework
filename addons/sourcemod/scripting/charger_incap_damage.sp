#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#define DEBUG					0
#define TEAM_SURVIVOR			2
#define TEAM_INFECTED			3
#define ZC_CHARGER				6

bool
	g_bLateLoad = false;

ConVar
	g_hCvarZChargerPoundDmg = null,
	g_hCvarDmgIncappedPound = null;

public Plugin myinfo =
{
	name = "Incapped Charger Damage",
	author = "Sir, A1m`",
	description = "Modify Charger pummel damage done to Survivors",
	version = "2.0",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	g_bLateLoad = bLate;
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hCvarDmgIncappedPound = CreateConVar("charger_dmg_incapped", "-1.0", "Pound Damage dealt to incapped Survivors.");

	g_hCvarZChargerPoundDmg = FindConVar("z_charger_pound_dmg");

	// hook already existing clients if loading late
	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnClientPutInServer(int iClient)
{
	SDKHook(iClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

// [Hook_OnTakeDamage] Victim: (Nick) 5, attacker: (Noname`) 2, inflictor: 2, damage: 15.000000, damagetype: 128 
// [Hook_OnTakeDamage] Weapon: -1, damageforce: 0.000000 0.000000 0.000000, damageposition: 0.000000 0.000000 0.000000
public Action Hook_OnTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamagetype, \
								int &iWeapon, float fDamageForce[3], float fDamagePosition[3])
{
	if (iDamagetype != DMG_CLUB 
		|| fDamage != g_hCvarZChargerPoundDmg.FloatValue
		|| g_hCvarDmgIncappedPound.FloatValue <= 0.0
	) {
		return Plugin_Continue;
	}

	if (/*!IsClientAndInGame(iVictim)
		|| */GetClientTeam(iVictim) != TEAM_SURVIVOR
		|| GetEntProp(iVictim, Prop_Send, "m_isIncapacitated", 1) < 1
	) {
		return Plugin_Continue;
	}

	if (!IsClientAndInGame(iAttacker)
		|| GetClientTeam(iAttacker) != TEAM_INFECTED
		|| GetEntProp(iAttacker, Prop_Send, "m_zombieClass") != ZC_CHARGER
	) {
		return Plugin_Continue;
	}

	int iPummelVictim = GetEntPropEnt(iAttacker, Prop_Send, "m_pummelVictim");
	if (iPummelVictim != iVictim) {
		return Plugin_Continue;
	}

#if DEBUG
	PrintToChatAll("[Hook_OnTakeDamage] Victim: (%N) %d, attacker: (%N) %d, inflictor: %d, damage: %f, damagetype: %d ", \
										iVictim, iVictim, iAttacker, iAttacker, iInflictor, fDamage, iDamagetype);
	PrintToChatAll("[Hook_OnTakeDamage] Weapon: %d, damageforce: %f %f %f, damageposition: %f %f %f", \
										iWeapon, fDamageForce[0], fDamageForce[1], fDamageForce[2], fDamagePosition[0], fDamagePosition[1], fDamagePosition[2]);
#endif

	fDamage = g_hCvarDmgIncappedPound.FloatValue;
	return Plugin_Changed;
}

bool IsClientAndInGame(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient));
}
