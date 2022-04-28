#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sourcescramble>

MemoryPatch gLadderPatch;

public Plugin myinfo =
{
	name = "[L4D2] Boomer Ladder Fix",
	author = "BHaType",
	description = "Fixes boomer teleport whenever hes close enough to ladder",
	version = "1.1",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	Handle hConf = LoadGameConfigFile("l4d2_boomer_ladder_fix");

	gLadderPatch = MemoryPatch.CreateFromConf(hConf, "CTerrorGameMovement::CheckForLadders");

	delete hConf;

	Patch(true);

	RegAdminCmd("sm_boomer_ladder_fix_toggle", Cmd_BoomerPatchToggle, ADMFLAG_ROOT);
}

public Action Cmd_BoomerPatchToggle(int iClient, int iArgs)
{
	Patch(3);
	return Plugin_Handled;
}

void Patch(int iState)
{
	static bool bSet;

	if (iState == 3) {
		iState = !bSet;
	}

	if (bSet && !iState) {
		gLadderPatch.Disable();
		bSet = false;
	} else if (!bSet && iState) {
		gLadderPatch.Enable();
		bSet = true;
	}
}
