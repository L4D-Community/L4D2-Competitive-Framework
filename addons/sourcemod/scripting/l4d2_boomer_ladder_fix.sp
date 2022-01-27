#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define DEBUG				0

#define ADDRESS_KEY			"CheckForLaddersAddress"
#define OFFSET_KEY			"CheckForLaddersPatchOffset"
#define GAMEDATA			"l4d2_boomer_ladder_fix"

enum
{
	eLinux = 0,
	eWindows
};

int
	g_iPlatform = eLinux;

bool
	g_bIsPatched = false;

Address
	g_pPatchAddress = Address_Null;

/* Windows:
 * 74 3B					jz	short loc_102CF09C
 * Change to:
 * EB 3B					jmp	short loc_102CF09C
*/
static const int
	g_iWinPatchBytes[] = {
		0xEB								// Windows
	},
	g_iWinOriginalBytes[] = {
		0x74								// Windows
	};

/* Linux:
 * 0F 84 C9 FE FF FF		jz	loc_4E9764
 * Change to NOP:
 * 90 90 90 90 90 90		NOP
*/
static const int
	g_iLinPatchBytes[] = {
		0x90, 0x90, 0x90, 0x90, 0x90, 0x90	// Linux
	},
	g_iLinOriginalBytes[] = {
		0x0F, 0x84, 0xC9, 0xFE, 0xFF, 0xFF	// Linux
	};

public Plugin myinfo =
{
	name = "[L4D2] Boomer Ladder Fix",
	author = "BHaType",
	description = "",
	version = "1.0",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_Left4Dead2) {
		SetFailState("This plugin is only for L4D2!");
	}

	Handle hGameData = LoadGameConfigFile(GAMEDATA);
	if (!hGameData) {
		SetFailState("Gamedata '%s.txt' missing or corrupt.", GAMEDATA);
	}

	g_pPatchAddress = GameConfGetAddress(hGameData, ADDRESS_KEY);
	if (g_pPatchAddress == Address_Null) {
		SetFailState("Failed to get address of '%s'", ADDRESS_KEY);
	}

	int iOffset = GameConfGetOffset(hGameData, OFFSET_KEY);
	if (iOffset == -1) {
		SetFailState("Failed to get offset from '%s'", OFFSET_KEY);
	}

	g_iPlatform = GameConfGetOffset(hGameData, "Platform");
	if (g_iPlatform != eWindows && g_iPlatform != eLinux) {
		SetFailState("Section not specified 'Platform'.");
	}

	g_pPatchAddress += view_as<Address>(iOffset);

	CheckPatch(true);

	delete hGameData;

#if DEBUG
	RegAdminCmd("sm_boomer_ladder_fix_toggle", Cmd_BoomerLadderFixToggle, ADMFLAG_ROOT);
#endif
}

public Action Cmd_BoomerLadderFixToggle(int iClient, int iArgs)
{
	if (g_bIsPatched) {
		ReplyToCommand(iClient, "[%s] Patch has been removed!", GAMEDATA);
		CheckPatch(false);
	} else {
		CheckPatch(true);
		ReplyToCommand(iClient, "[%s] Patch has been installed!", GAMEDATA);
	}

	return Plugin_Handled;
}

public void OnPluginEnd()
{
	CheckPatch(false);
}

void CheckPatch(bool bIsPatch)
{
	if (bIsPatch) {
		if (g_bIsPatched) {
			PrintToServer("[%s] Plugin already enabled", GAMEDATA);
			return;
		}

		if (g_iPlatform == eLinux) {
			CheckAndPatchBytes(g_pPatchAddress, g_iLinOriginalBytes, g_iLinPatchBytes, sizeof(g_iLinOriginalBytes));
		} else {
			CheckAndPatchBytes(g_pPatchAddress, g_iWinOriginalBytes, g_iWinPatchBytes, sizeof(g_iWinOriginalBytes));
		}

		g_bIsPatched = true;
	} else {
		if (!g_bIsPatched) {
			PrintToServer("[%s] Plugin already disabled", GAMEDATA);
			return;
		}

		if (g_iPlatform == eLinux) {
			PatchBytes(g_pPatchAddress, g_iLinOriginalBytes, sizeof(g_iLinPatchBytes));
		} else {
			PatchBytes(g_pPatchAddress, g_iWinOriginalBytes, sizeof(g_iWinOriginalBytes));
		}

		g_bIsPatched = false;
	}
}

void CheckAndPatchBytes(const Address pAddress, const int[] iCheckBytes, const int[] iPatchBytes, const int iPatchSize)
{
	int iReadByte = -1, iByteCount = 0;

	for (int i = 0; i < iPatchSize; i++) {
		iReadByte = LoadFromAddress(pAddress + view_as<Address>(i), NumberType_Int8);

		if (iCheckBytes[i] < 0 || iReadByte != iCheckBytes[i]) {
			if (iReadByte == iPatchBytes[i]) {
				iByteCount++;
				continue;
			}

			PrintToServer("Check bytes failed. Invalid byte (read: %x@%i, expected byte: %x@%i). Check offset '%s'.", iReadByte, i, iCheckBytes[i], i, OFFSET_KEY);
			SetFailState("Check bytes failed. Invalid byte (read: %x@%i, expected byte: %x@%i). Check offset '%s'.", iReadByte, i, iCheckBytes[i], i, OFFSET_KEY);
		}
	}

	if (iByteCount == iPatchSize) {
		PrintToServer("[%s] The patch is already installed.", GAMEDATA);
		return;
	}

	PatchBytes(pAddress, iPatchBytes, iPatchSize);
}

void PatchBytes(const Address pAddress, const int[] iPatchBytes, const int iPatchSize)
{
	for (int i = 0; i < iPatchSize; i++) {
		if (iPatchBytes[i] < 0) {
			PrintToServer("Patch bytes failed. Invalid write byte: %x@%i. Check offset '%s'.", iPatchBytes[i], i, OFFSET_KEY);
			SetFailState("Patch bytes failed. Invalid write byte: %x@%i. Check offset '%s'.", iPatchBytes[i], i, OFFSET_KEY);
		}

		StoreToAddress(pAddress + view_as<Address>(i), iPatchBytes[i], NumberType_Int8);
		PrintToServer("[%s] Write byte %x@%i", GAMEDATA, iPatchBytes[i], i);
	}
}
