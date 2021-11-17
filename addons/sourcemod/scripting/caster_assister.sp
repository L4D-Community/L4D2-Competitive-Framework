#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <caster_system>

#define CASTER_SYSTEM_NAME "caster_system"
#define MAX_SPEED 2.0
#define TEAM_SPECTATORS 1

bool
	g_bCasterSystemAvailable = false;

float
	g_fCurrentMulti[MAXPLAYERS + 1] = {1.0, ...},
	g_fCurrentIncrement[MAXPLAYERS + 1] = {0.1, ...},
	g_fVerticalIncrement[MAXPLAYERS + 1] = {10.0, ...};

public Plugin myinfo =
{
	name = "Caster Assister",
	author = "CanadaRox, Sir",
	description = "Allows spectators to control their own specspeed and move vertically",
	version = "2.4",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_set_specspeed_multi", SetSpecspeed_Cmd);
	RegConsoleCmd("sm_set_specspeed_increment", SetSpecspeedIncrement_Cmd);
	RegConsoleCmd("sm_increase_specspeed", IncreaseSpecspeed_Cmd);
	RegConsoleCmd("sm_decrease_specspeed", DecreaseSpecspeed_Cmd);
	RegConsoleCmd("sm_set_vertical_increment", SetVerticalIncrement_Cmd);

	HookEvent("player_team", PlayerTeam_Event);
}

public void OnAllPluginsLoaded()
{
	g_bCasterSystemAvailable = LibraryExists(CASTER_SYSTEM_NAME);
}

public void OnLibraryRemoved(const char[] sPluginName)
{
	if (StrEqual(sPluginName, CASTER_SYSTEM_NAME)) {
		g_bCasterSystemAvailable = false;
	}
}

public void OnLibraryAdded(const char[] sPluginName)
{
	if (StrEqual(sPluginName, CASTER_SYSTEM_NAME)) {
		g_bCasterSystemAvailable = true;
	}
}

public void OnClientPutInServer(int iClient)
{
	if (g_bCasterSystemAvailable && IsClientCaster(iClient)) {
		FakeClientCommand(iClient, "sm_spechud");
	}
}

public void PlayerTeam_Event(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	if (hEvent.GetBool("disconnect")) {
		return;
	}

	if (hEvent.GetInt("team") != TEAM_SPECTATORS) {
		return;
	}

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || IsFakeClient(iClient)) {
		return;
	}

	SetEntPropFloat(iClient, Prop_Send, "m_flLaggedMovementValue", g_fCurrentMulti[iClient]);
}

public Action SetSpecspeed_Cmd(int iClient, int iArgs)
{
	if (GetClientTeam(iClient) != TEAM_SPECTATORS) {
		return Plugin_Handled;
	}

	if (iArgs != 1) {
		ReplyToCommand(iClient, "Usage: sm_set_specspeed_multi # (default: 1.0)");
		return Plugin_Handled;
	}

	char sBuffer[10];
	GetCmdArg(1, sBuffer, sizeof(sBuffer));
	float fNewVal = StringToFloat(sBuffer);

	if (IsSpeedValid(fNewVal)) {
		SetEntPropFloat(iClient, Prop_Send, "m_flLaggedMovementValue", fNewVal);
		g_fCurrentMulti[iClient] = fNewVal;
	}

	return Plugin_Handled;
}

public Action SetSpecspeedIncrement_Cmd(int iClient, int iArgs)
{
	if (GetClientTeam(iClient) != TEAM_SPECTATORS) {
		return Plugin_Handled;
	}

	if (iArgs != 1) {
		ReplyToCommand(iClient, "Usage: sm_set_specspeed_increment # (default: 0.1)");
		return Plugin_Handled;
	}

	char sBuffer[10];
	GetCmdArg(1, sBuffer, sizeof(sBuffer));
	g_fCurrentIncrement[iClient] = StringToFloat(sBuffer);
	return Plugin_Handled;
}

public Action IncreaseSpecspeed_Cmd(int iClient, int iArgs)
{
	if (GetClientTeam(iClient) != TEAM_SPECTATORS) {
		return Plugin_Handled;
	}

	IncreaseSpecspeed(iClient, g_fCurrentIncrement[iClient]);
	return Plugin_Handled;
}

public Action DecreaseSpecspeed_Cmd(int iClient, int iArgs)
{
	if (GetClientTeam(iClient) != TEAM_SPECTATORS) {
		return Plugin_Handled;
	}

	IncreaseSpecspeed(iClient, -g_fCurrentIncrement[iClient]);
	return Plugin_Handled;
}

public Action SetVerticalIncrement_Cmd(int iClient, int iArgs)
{
	if (GetClientTeam(iClient) != TEAM_SPECTATORS) {
		return Plugin_Handled;
	}

	if (iArgs != 1) {
		ReplyToCommand(iClient, "Usage: sm_set_vertical_increment # (default: 10.0)");
		return Plugin_Handled;
	}

	char sBuffer[10];
	GetCmdArg(1, sBuffer, sizeof(sBuffer));
	g_fVerticalIncrement[iClient] = StringToFloat(sBuffer);
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int iClient, int &iButtons)
{
	if (GetClientTeam(iClient) != TEAM_SPECTATORS || IsFakeClient(iClient)) {
		return Plugin_Continue;
	}

	if (iButtons & IN_USE) {
		MoveUp(iClient, g_fVerticalIncrement[iClient]);
	} else if (iButtons & IN_RELOAD) {
		MoveUp(iClient, -g_fVerticalIncrement[iClient]);
	}

	return Plugin_Continue;
}

void IncreaseSpecspeed(int iClient, float fDifference)
{
	float fCalculate = GetEntPropFloat(iClient, Prop_Send, "m_flLaggedMovementValue") + fDifference;

	if (IsSpeedValid(fCalculate)) {
		SetEntPropFloat(iClient, Prop_Send, "m_flLaggedMovementValue", fCalculate);
		g_fCurrentMulti[iClient] = fCalculate;
	}
}

void MoveUp(int iClient, float fDistance)
{
	float fOrigin[3];
	GetClientAbsOrigin(iClient, fOrigin);
	fOrigin[2] += fDistance;

	TeleportEntity(iClient, fOrigin, NULL_VECTOR, NULL_VECTOR);
}

bool IsSpeedValid(float fSpeed)
{
	return (fSpeed >= 0.0 && fSpeed <= MAX_SPEED);
}
