#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#define LEFT4FRAMEWORK_INCLUDE 1
#include <left4framework>

int iCommonLimit;

ConVar hCommonLimit;

public Plugin myinfo =
{
	name = "Director-scripted common limit blocker",
	author = "Tabun",
	description = "Prevents director scripted overrides of z_common_limit. Only affects scripted common limits higher than the cvar.",
	version = "0.2",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	hCommonLimit = FindConVar("z_common_limit");

	iCommonLimit = hCommonLimit.IntValue;

	HookConVarChange(hCommonLimit, Cvar_CommonLimitChange);
}

public void Cvar_CommonLimitChange(ConVar hCvar, const char[] oldValue, const char[] newValue)
{
	iCommonLimit = hCommonLimit.IntValue;
}

public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
	if (strcmp(key, "CommonLimit") == 0) {
		if (retVal != iCommonLimit) {
			retVal = iCommonLimit;
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
