#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define ENTITY_NAME_MAX_LENGTH 64

public Plugin myinfo =
{
	name = "Byebye Door",
	description = "Time to kill Saferoom Doors.",
	author = "Sir",
	version = "1.2",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void Event_RoundStart(Event hEvent, const char[] eName, bool dontBroadcast)
{
	int iEntityCount = GetEntityCount();
	char sClassName[ENTITY_NAME_MAX_LENGTH];

	for (int i = (MaxClients + 1); i <= iEntityCount; i++){
		if (!IsValidEdict(i)) {
			continue;
		}

		GetEdictClassname(i, sClassName, sizeof(sClassName));
		if (strcmp(sClassName, "prop_door_rotating_checkpoint", false) == 0) {
			if (GetEntProp(i, Prop_Send, "m_bLocked", 1) > 0) {
				#if SOURCEMOD_V_MINOR > 8
					RemoveEntity(i);
				#else
					AcceptEntityInput(i, "Kill");
				#endif

				break;
			}
		}
	}
}
