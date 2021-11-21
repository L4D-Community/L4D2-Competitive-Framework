#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0"
#define MAX_ENTITY_NAME_SIZE 64

float g_fSurvivorStart[3];

ConVar g_hGameMode = null;

public Plugin myinfo =
{
	name = "No Safe Room Medkits",
	author = "Blade",
	description = "Removes Safe Room Medkits",
	version = PLUGIN_VERSION,
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	char sGameFolder[64];
	GetGameFolderName(sGameFolder, sizeof(sGameFolder));
	if (strcmp(sGameFolder, "left4dead2", false) != 0) {
		SetFailState("Plugin supports Left 4 Dead 2 only.");
	}

	//CreateConVar("nokits_version", PLUGIN_VERSION, "No Safe Room Medkits Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	g_hGameMode = FindConVar("mp_gamemode");
}

public void Event_RoundStart(Event hEvent, const char[] sEventname, bool bDontBroadcast)
{
	char sGameMode[32];
	g_hGameMode.GetString(sGameMode, sizeof(sGameMode));
	if (strcmp(sGameMode, "versus", false) != 0 && strcmp(sGameMode, "mutation12", false) != 0) {
		return;
	}

	//find where the survivors start so we know which medkits to replace,
	FindSurvivorStart();
	//and replace the medkits with pills.
	ReplaceMedkits();
}

void FindSurvivorStart()
{
	int iEntityCount = GetEntityCount();
	char sClassName[MAX_ENTITY_NAME_SIZE];
	float fLocation[3];

	//Search entities for either a locked saferoom door,
	for (int i = (MaxClients + 1); i <= iEntityCount; i++) {
		if (!IsValidEdict(i)) {
			continue;
		}

		GetEdictClassname(i, sClassName, sizeof(sClassName));

		if ((StrContains(sClassName, "prop_door_rotating_checkpoint", false) != -1)
			&& (GetEntProp(i, Prop_Send, "m_bLocked", 1) > 0)
		) {
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", fLocation);
			VectorCopy(fLocation, g_fSurvivorStart);
			return;
		}
	}

	//or a survivor start point.
	for (int i = (MaxClients + 1); i <= iEntityCount; i++) {
		if (!IsValidEdict(i)) {
			continue;
		}

		GetEdictClassname(i, sClassName, sizeof(sClassName));

		if (StrContains(sClassName, "info_survivor_position", false) != -1) {
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", fLocation);
			VectorCopy(fLocation, g_fSurvivorStart);
			return;
		}
	}
}

void ReplaceMedkits()
{
	int iEntityCount = GetEntityCount();
	char sClassName[MAX_ENTITY_NAME_SIZE];
	float fNearestMedkit[3], fLocation[3];

	//Look for the nearest medkit from where the survivors start,
	for (int i = (MaxClients + 1); i <= iEntityCount; i++) {
		if (!IsValidEdict(i)) {
			continue;
		}

		GetEdictClassname(i, sClassName, sizeof(sClassName));

		if (StrContains(sClassName, "weapon_first_aid_kit", false) != -1) {
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", fLocation);
			//If fNearestMedkit is zero, then this must be the first medkit we found.

			if ((fNearestMedkit[0] + fNearestMedkit[1] + fNearestMedkit[2]) == 0.0) {
				VectorCopy(fLocation, fNearestMedkit);
				continue;
			}

			//If this medkit is closer than the last medkit, record its location.
			if (GetVectorDistance(g_fSurvivorStart, fLocation, false) < GetVectorDistance(g_fSurvivorStart, fNearestMedkit, false)) {
				VectorCopy(fLocation, fNearestMedkit);
			}
		}
	}

	//then remove the kits
	for (int i = (MaxClients + 1); i <= iEntityCount; i++) {
		if (!IsValidEdict(i)) {
			continue;
		}

		GetEdictClassname(i, sClassName, sizeof(sClassName));

		if (StrContains(sClassName, "weapon_first_aid_kit", false) != -1) {
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", fLocation);

			if (GetVectorDistance(fNearestMedkit, fLocation, false) < 400) {
				#if SOURCEMOD_V_MINOR > 8
					RemoveEntity(i);
				#else
					AcceptEntityInput(i, "Kill");
				#endif
			}
		}
	}
}

void VectorCopy(float fFrom[3], float fTo[3])
{
	fTo[0] = fFrom[0];
	fTo[1] = fFrom[1];
	fTo[2] = fFrom[2];
}
