#pragma semicolon 1
#pragma newdecls required

#define DEBUG								0

#include <sourcemod>
#include <sdkhooks>
#if DEBUG
#include <l4d2util_constants>
#include <l4d2util_survivors>
#endif

#define TEAM_SURVIVORS						2
#define SEQUENCE_POUNCED_TO_STAND_ELLIS		625
#define FRAMES_ELLIS						79.0 //79 frames(Currently: 1.1.2022) for ellis
#define FRAMES_OTHERS						64.0 //64 frames for other survivors

#if DEBUG
static const int g_iGetUpAnimations[8][4] =
{
	{620, 667, 671, 672}, //Nick 0
	{629, 674, 678, 679}, //Rochelle 1
	{621, 656, 660, 661}, //Coach 2
	{625, 671, 675, 676}, //Ellis 3
	{528, 759, 763, 764}, //Bill 4
	{537, 819, 823, 824}, //Zoey 5
	{528, 759, 763, 764}, //Louis 6
	{531, 762, 766, 767} //Francis 7
	//Hunter 0, Charger 1, Charger wall 2, Charger ground 3
};

float g_fFirstAnim[MAXPLAYERS + 1] = {0.0, ...};
#endif

public Plugin myinfo =
{
	name = "Ellis Hunter Getup Duration Adjustment",
	author = "Rena, A1m`",
	description = "Make the getup animation duration of ellis equal to that of the other survivors",
	version = "1.5",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	if (GetEngineVersion() != Engine_Left4Dead2) {
		strcopy(sError, iErrMax, "Plugin only supports Left 4 Dead 2");

		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent("pounce_end", Event_OnPounceEnd, EventHookMode_Post);
}

public void Event_OnPounceEnd(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(event, "victim"));
	if (iClient < 1 || GetClientTeam(iClient) != TEAM_SURVIVORS) {
		return;
	}

#if DEBUG
	g_fFirstAnim[iClient] = GetGameTime();

	PrintToChatAll("pounce_end: %N, time: %f", iClient, g_fFirstAnim[iClient]);
#else
	//MODEL_ELLIS
	//models/survivors/survivor_mechanic.mdl
	char sModelName[36];
	GetClientModel(iClient, sModelName, sizeof(sModelName));

	if (strncmp(sModelName[26], "mechanic", 8, true) != 0) {
		return;
	}
#endif

	SDKHook(iClient, SDKHook_PostThinkPost, Hook_OnEntityPostThinkPost);
}

public void Hook_OnEntityPostThinkPost(int iClient)
{
#if DEBUG
	if (GetClientTeam(iClient) != TEAM_SURVIVORS) {
		SDKUnhook(iClient, SDKHook_PostThinkPost, Hook_OnEntityPostThinkPost);

		PrintTime(iClient);
		return;
	}

	int iCharIndex = IdentifySurvivor(iClient);
	if (GetEntProp(iClient, Prop_Send, "m_nSequence") != g_iGetUpAnimations[iCharIndex][0]) {
		SDKUnhook(iClient, SDKHook_PostThinkPost, Hook_OnEntityPostThinkPost);

		PrintTime(iClient);
		return;
	}

	if (iCharIndex == SurvivorCharacter_Ellis) {
		PrintToChatAll("iClient: %N , m_flPlaybackRate: %f", iClient, FRAMES_ELLIS/FRAMES_OTHERS);

		SetEntPropFloat(iClient, Prop_Send, "m_flPlaybackRate", FRAMES_ELLIS/FRAMES_OTHERS);
	}
#else
	if (GetClientTeam(iClient) != TEAM_SURVIVORS
		|| GetEntProp(iClient, Prop_Send, "m_nSequence") != SEQUENCE_POUNCED_TO_STAND_ELLIS
	) {
		SDKUnhook(iClient, SDKHook_PostThinkPost, Hook_OnEntityPostThinkPost);
		return;
	}

	SetEntPropFloat(iClient, Prop_Send, "m_flPlaybackRate", FRAMES_ELLIS/FRAMES_OTHERS);
#endif
}

#if DEBUG
void PrintTime(int iClient)
{
	float fLastAnim = GetGameTime() - g_fFirstAnim[iClient];

	int iCharIndex = IdentifySurvivor(iClient);

	char sCharacterName[16];
	GetSurvivorName(iCharIndex, sCharacterName, sizeof(sCharacterName));

	PrintToChatAll("Player: %N (%d), character name: %s (%d), getup animation time: %f ", iClient, iClient, sCharacterName, iCharIndex, fLastAnim);
}
#endif
