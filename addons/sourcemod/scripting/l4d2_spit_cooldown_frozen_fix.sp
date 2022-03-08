#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define Z_SPITTER				4

#define ARRAY_INDEX_DURATION	0
#define ARRAY_INDEX_TIMESTAMP	1

ConVar g_hCvarZSpitInterval = null;

public Plugin myinfo =
{
	name = "[L4D2] Spit Cooldown Frozen Fix",
	author = "Forgetest",
	description = "Simple fix for spit cooldown being \"frozen\".",
	version = "1.1a",
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
};

public void OnPluginStart()
{
	g_hCvarZSpitInterval = FindConVar("z_spit_interval");

	HookEvent("ability_use", Event_AbilityUse);
}

public void Event_AbilityUse(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	char sAbility[16];
	hEvent.GetString("ability", sAbility, sizeof(sAbility));
	if (strcmp(sAbility[8], "spit") != 0) {
		return;
	}

	// duration of spit animation seems to vary from [1.160003, 1.190002] on 100t sv
	CreateTimer(1.2, Timer_CheckAbilityTimer, hEvent.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CheckAbilityTimer(Handle hTimer, any iUserId)
{
	int iClient = GetClientOfUserId(iUserId);
	if (iClient < 1 || GetEntProp(iClient, Prop_Send, "m_zombieClass") != Z_SPITTER || !IsPlayerAlive(iClient)) {
		return Plugin_Stop;
	}

	int iAbility = GetEntPropEnt(iClient, Prop_Send, "m_customAbility");
	if (iAbility == -1) {
		return Plugin_Stop;
	}

	// potential freezing detected
	if (GetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", 0) == 3600.0) {
		float fInterval = g_hCvarZSpitInterval.FloatValue;
		SetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", fInterval, ARRAY_INDEX_DURATION);
		SetEntPropFloat(iAbility, Prop_Send, "m_nextActivationTimer", GetGameTime() + fInterval, ARRAY_INDEX_TIMESTAMP);

		SetEntProp(iAbility, Prop_Send, "m_bHasBeenActivated", false);
	}

	return Plugin_Stop;
}

/* @Forgetest:
	in some cases member 'm_bSequenceFinisheddoes' is not set to true

unsigned int __usercall CSpitAbility::ActivateAbility@<eax>(long double a1@<st0>, CSpitAbility *this)
{
	...
	CBaseAbility::StartActivationTimer(this, 3600.0, 0.0);
	...
}

void __usercall CSpitAbility::UpdateAbility(long double a1@<st0>, CSpitAbility *this)
{
	...

	if ( *(_BYTE *)(v2 + 1160) ) // - m_bSequenceFinished (Offset 1160) (Save)(1 Bytes)
	{
		CBaseAbility::StartActivationTimer(this, z_spit_interval.GetFloat(), 0.0); // ConVar z_spit_interval
		...
	}
}*/
