/*
    to do:
        - make it work with confogl (lgofnoc?)

    0.1b
        - works properly with config dir changes on the fly
        - unloads properly now (resets values)

*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
//#include <confogl>

#define KV_MAPCVAR			"/mapcvars.txt"
#define MAX_CONFIG_LEN		128
#define MAX_VARLENGTH		64
#define MAX_VALUELENGTH		128
#define MAX_SETVARS			64

#define DEBUG				0

char g_sUseConfigDir[MAX_CONFIG_LEN]; // which directory in cfgogl are we using? none = cfg/

ConVar g_hUseConfigDir = null;

KeyValues g_hKvOrig = null; // kv to store original values in

public Plugin myinfo =
{
	name = "L4D(2) map-based convar loader.",
	author = "Tabun",
	version = "0.2",
	description = "Loads convars on map-load, based on currently active map and confogl config.",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	g_hUseConfigDir = CreateConVar("l4d_mapcvars_configdir", "", "Which cfgogl config are we using?");

	GetConVarString(g_hUseConfigDir, g_sUseConfigDir, MAX_CONFIG_LEN);
	HookConVarChange(g_hUseConfigDir, CvarConfigChange);

	// prepare KV for saving old states
	g_hKvOrig = CreateKeyValues("MapCvars_Orig");     // store original values
}

public void OnPluginEnd()
{
	ResetMapPrefs();

	if (g_hKvOrig != null) {
		CloseHandle(g_hKvOrig);
		g_hKvOrig = null;
	}
}

public void CvarConfigChange(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	strcopy(g_sUseConfigDir, MAX_CONFIG_LEN, sNewValue);

#if DEBUG
	PrintToServer("[mcv] config directory changed [%s], reloading values.", sNewValue);
#endif

	ResetMapPrefs(); // reset old
	GetThisMapPrefs(); // apply new
}

public void OnMapStart()
{
	GetThisMapPrefs();
}

public void OnMapEnd()
{
	ResetMapPrefs();
}

int GetThisMapPrefs()
{
	int iNumChanged = 0; // how many cvars were changed for this map

	// reopen original keyvalues for clean slate:
	if (g_hKvOrig != null) {
		CloseHandle(g_hKvOrig);
		g_hKvOrig = null;
	}

	g_hKvOrig = CreateKeyValues("MapCvars_Orig"); // store original values for this map

	// build path to current config's keyvalues file
	char usePath[PLATFORM_MAX_PATH];
	if (strlen(g_sUseConfigDir) > 0) {
		usePath = "../../cfg/cfgogl/";
		StrCat(usePath, PLATFORM_MAX_PATH, g_sUseConfigDir);
		StrCat(usePath, PLATFORM_MAX_PATH, KV_MAPCVAR);
	} else {
		usePath = "../../cfg";
		StrCat(usePath, PLATFORM_MAX_PATH, KV_MAPCVAR);
	}

	BuildPath(Path_SM, usePath, sizeof(usePath), usePath);

	if (!FileExists(usePath)) {
		#if DEBUG
			PrintToServer("[mcv] file does not exist! (%s)", usePath);
		#endif

		return 0;
	}

#if DEBUG
	PrintToServer("[mcv] trying keyvalue read (from [%s])...", usePath);
#endif

	KeyValues hKv = CreateKeyValues("MapCvars");
	FileToKeyValues(hKv, usePath);

	if (hKv == null) {
		#if DEBUG
			PrintToServer("[mcv] couldn't read file.");
		#endif

		return 0;
	}

	// read keyvalues for current map
	char sMapName[64];
	GetCurrentMap(sMapName, sizeof(sMapName));

	if (!KvJumpToKey(hKv, sMapName)) {
		// no special settings for this map
		CloseHandle(hKv);
		#if DEBUG
			PrintToServer("[mcv] couldn't find map (%s)", sMapName);
		#endif

		return 0;
	}

	// find all cvar keys and save the original values
	// then execute the change
	char tmpKey[MAX_VARLENGTH], tmpValueNew[MAX_VALUELENGTH], tmpValueOld[MAX_VALUELENGTH];
	ConVar hConVar = null;
	//new iConVarFlags = 0;

	if (KvGotoFirstSubKey(hKv, false)) { // false to get values
		do {
			// read key stuff
			KvGetSectionName(hKv, tmpKey, sizeof(tmpKey)); // the subkey is a key-value pair, so get this to get the 'convar'

			#if DEBUG
				PrintToServer("[mcv] kv key found: [%s], reading value...", tmpKey);
			#endif

			// is it a convar?
			hConVar = FindConVar(tmpKey);
			/*
				// what to do with non-existant cvars?
				// don't add, for now
			if (hConVar == null) {
				hConVar = CreateConVar(tmpKey, "", "[mcv] added because it didn't exist yet...", FCVAR_NONE);
			}
			*/

			if (hConVar != null) {
				// get type..
				//iConVarFlags = GetConVarFlags(hConVar);

				// types?
				//      FCVAR_CHEAT

				KvGetString(hKv, NULL_STRING, tmpValueNew, sizeof(tmpValueNew), "[:none:]");
				#if DEBUG
					PrintToServer("[mcv] kv value read: [%s] => [%s])", tmpKey, tmpValueNew);
				#endif

				// read, save and set value
				if (!StrEqual(tmpValueNew,"[:none:]")) {
					GetConVarString(hConVar, tmpValueOld, sizeof(tmpValueOld));
					PrintToServer("[mcv] cvar value changed: [%s] => [%s] (saved old: [%s]))", tmpKey, tmpValueNew, tmpValueOld);

					if (!StrEqual(tmpValueNew,tmpValueOld)) {
						// different, save the old
						iNumChanged++;
						KvSetString(g_hKvOrig, tmpKey, tmpValueOld);

						// apply the new
						SetConVarString(hConVar, tmpValueNew);
						//if (iConVarFlags & FCVAR_CHEAT) {

						//}
					}
				}
			} else {
				#if DEBUG
					PrintToServer("[mcv] convar doesn't exist: [%s], not changing it.", tmpKey);
				#endif
			}
		} while (KvGotoNextKey(hKv, false));
	}

	KvSetString(g_hKvOrig, "__EOF__", "1");             // a test-safeguard

	CloseHandle(hKv);
	return iNumChanged;
}

void ResetMapPrefs()
{
	KvRewind(g_hKvOrig);

#if DEBUG
	PrintToServer("[mcv] attempting to reset values, if any...");
#endif

	// find all cvar keys and reset to original values
	char tmpKey[64], tmpValueOld[512];
	ConVar hConVar = null;

	if (KvGotoFirstSubKey(g_hKvOrig, false)) { // false to get values
		do {
			// read key stuff
			KvGetSectionName(g_hKvOrig, tmpKey, sizeof(tmpKey));      // the subkey is a key-value pair, so get this to get the 'convar'

			if (StrEqual(tmpKey, "__EOF__")) {
				#if DEBUG
					PrintToServer("[mcv] kv original settings, all read. (EOF).");
				#endif

				break;
			} else {
				#if DEBUG
					PrintToServer("[mcv] kv original saved setting found: [%s], reading value...", tmpKey);
				#endif

				// is it a convar?
				hConVar = FindConVar(tmpKey);

				if (hConVar != null) {
					KvGetString(g_hKvOrig, NULL_STRING, tmpValueOld, sizeof(tmpValueOld), "[:none:]");
					#if DEBUG
						PrintToServer("[mcv] kv saved value read: [%s] => [%s])", tmpKey, tmpValueOld);
					#endif

					// read, save and set value
					if (!StrEqual(tmpValueOld, "[:none:]")) {
						// reset the old
						SetConVarString(hConVar, tmpValueOld);
						PrintToServer("[mcv] cvar value reset to original: [%s] => [%s])", tmpKey, tmpValueOld);
					}
				} else {
					#if DEBUG
						PrintToServer("[mcv] convar doesn't exist: [%s], not resetting it.", tmpKey);
					#endif
				}
			}
		} while (KvGotoNextKey(g_hKvOrig, false));
	}
}
