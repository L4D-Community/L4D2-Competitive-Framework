#if defined __confogl_debug_included
	#endinput
#endif
#define __confogl_debug_included

#if DEBUG_ALL
	#define DEBUG_DEFAULT "1"
#else
	#define DEBUG_DEFAULT "0"
#endif

static bool
	g_bConfoglDebug = false;

static ConVar
	g_hDebugConVar = null;

void Debug_OnModuleStart()
{
	g_hDebugConVar = CreateConVarEx("debug", DEBUG_DEFAULT, "Turn on Debug Logging in all Confogl Modules", _, true, 0.0, true, 1.0);

	g_bConfoglDebug = g_hDebugConVar.BoolValue;
	g_hDebugConVar.AddChangeHook(Debug_ConVarChange);
}

public void Debug_ConVarChange(ConVar hConvar, const char[] sOldValue, const char[] sNewValue)
{
	g_bConfoglDebug = hConvar.BoolValue;
}

stock bool IsDebugEnabled()
{
	return (g_bConfoglDebug || DEBUG_ALL);
}
