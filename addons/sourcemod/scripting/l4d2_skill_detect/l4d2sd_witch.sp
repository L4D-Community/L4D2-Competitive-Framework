#if defined _L4D2SD_WITCH_INCLUDED_
	#endinput
#endif
#define _L4D2SD_WITCH_INCLUDED_

#define WITCH_CHECK_TIME	0.1			// time to wait before checking for witch crown after shoots fired
#define WITCH_DELETE_TIME	0.15		// time to wait before deleting entry from witch trie after entity is destroyed
#define DMGARRAYEXT			7			// MAXPLAYERS+# -- extra indices in witch_dmg_array + 1

// witch array entries (maxplayers+index)
enum
{
	WTCH_NONE,
	WTCH_HEALTH,
	WTCH_GOTSLASH,
	WTCH_STARTLED,
	WTCH_CROWNER,
	WTCH_CROWNSHOT,
	WTCH_CROWNTYPE,
	strWitchArray
};

static Handle
	g_hForwardCrown = null,
	g_hForwardDrawCrown = null;

static ConVar
	g_hCvarWitchHealth = null,			// z_witch_health
	g_hCvarDrawCrownThresh = null;		// cvar damage in final shot for drawcrown-req.

static StringMap
	g_hWitchTrie = null;				// witch tracking (Crox)

static float
	g_fWitchShotStart[MAXPLAYERS + 1];	// when the last shotgun blast from a survivor started (on any witch)

void Witch_AskPluginLoad2()
{
	g_hForwardCrown = CreateGlobalForward("OnWitchCrown", ET_Event, Param_Cell, Param_Cell);
	g_hForwardDrawCrown = CreateGlobalForward("OnWitchDrawCrown", ET_Event, Param_Cell, Param_Cell, Param_Cell);
}

void Witch_OnPluginStart()
{
	g_hCvarDrawCrownThresh = CreateConVar("sm_skill_drawcrown_damage", \
		"500",
		"How much damage a survivor must at least do in the final shot for it to count as a drawcrown.", \
		_, true, 0.0, false \
	);

	HookEvent("witch_spawn", Event_WitchSpawned, EventHookMode_Post);
	HookEvent("witch_harasser_set", Event_WitchHarasserSet, EventHookMode_Post);
	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);

	g_hCvarWitchHealth = FindConVar("z_witch_health");

	g_hWitchTrie = new StringMap();

	if (g_bLateLoad) {
		for (int iIter = 1; iIter <= MaxClients; iIter++) {
			if (IsClientInGame(iIter)) {
				SDKHook(iIter, SDKHook_OnTakeDamage, OnTakeDamageByWitch);
			}
		}
	}
}

void Witch_OnClientPostAdminCheck(int iClient)
{
	SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamageByWitch);
}

void Witch_OnEntityDestroyed(int iEntity)
{
	char witch_key[10];
	FormatEx(witch_key, sizeof(witch_key), "%x", iEntity);

	int witch_array[MAXPLAYERS + DMGARRAYEXT];
	if (GetTrieArray(g_hWitchTrie, witch_key, witch_array, sizeof(witch_array))) {
		// witch
		//  delayed deletion, to avoid potential problems with crowns not detecting
		CreateTimer(WITCH_DELETE_TIME, Timer_WitchKeyDelete, iEntity);
		SDKUnhook(iEntity, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Witch);
	}
}

public Action Timer_WitchKeyDelete(Handle hTimer, any witch)
{
	char witch_key[10];
	FormatEx(witch_key, sizeof(witch_key), "%x", witch);
	RemoveFromTrie(g_hWitchTrie, witch_key);
}

// crown tracking
public void Event_WitchSpawned(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int witch = hEvent.GetInt("witchid");

	SDKHook(witch, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Witch);

	int witch_dmg_array[MAXPLAYERS + DMGARRAYEXT];
	
	char witch_key[10];
	FormatEx(witch_key, sizeof(witch_key), "%x", witch);
	witch_dmg_array[MAXPLAYERS + WTCH_HEALTH] = GetConVarInt(g_hCvarWitchHealth);
	
	SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, false);
}

public Action Event_WitchHarasserSet(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int witch = hEvent.GetInt("witchid");

	char witch_key[10];
	FormatEx(witch_key, sizeof(witch_key), "%x", witch);
	int witch_dmg_array[MAXPLAYERS + DMGARRAYEXT];

	if (!GetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT)) {
		for (int i = 0; i <= MAXPLAYERS; i++) {
			witch_dmg_array[i] = 0;
		}
		
		witch_dmg_array[MAXPLAYERS+WTCH_HEALTH] = GetConVarInt(g_hCvarWitchHealth);
		witch_dmg_array[MAXPLAYERS+WTCH_STARTLED] = 1;  // harasser set
		SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, false);
	} else {
		witch_dmg_array[MAXPLAYERS+WTCH_STARTLED] = 1;  // harasser set
		SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, true);
	}
}

public void Event_WitchKilled(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int witch = hEvent.GetInt("witchid");
	int attacker = GetClientOfUserId(hEvent.GetInt("userid"));
	SDKUnhook(witch, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Witch);

	if (!IS_VALID_SURVIVOR(attacker)) {
		return; 
	}

	bool bOneShot = hEvent.GetBool("oneshot");

	// is it a crown / drawcrown?
	Handle pack = CreateDataPack();
	WritePackCell(pack, attacker);
	WritePackCell(pack, witch);
	WritePackCell(pack, (bOneShot) ? 1 : 0);
	CreateTimer(WITCH_CHECK_TIME, Timer_CheckWitchCrown, pack);
}

public Action OnTakeDamageByWitch(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	// if a survivor is hit by a witch, note it in the witch damage array (maxplayers+2 = 1)
	if (IS_VALID_SURVIVOR(victim) && damage > 0.0) {
		// not a crown if witch hit anyone for > 0 damage
		if (IsWitch(attacker)) {
			char witch_key[10];
			FormatEx(witch_key, sizeof(witch_key), "%x", attacker);
			int witch_dmg_array[MAXPLAYERS + DMGARRAYEXT];

			if (!GetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT)) {
				for (int i = 0; i <= MAXPLAYERS; i++) {
					witch_dmg_array[i] = 0;
				}
				
				witch_dmg_array[MAXPLAYERS+WTCH_HEALTH] = GetConVarInt(g_hCvarWitchHealth);
				witch_dmg_array[MAXPLAYERS + WTCH_GOTSLASH] = 1;  // failed
				SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, false);
			} else {
				witch_dmg_array[MAXPLAYERS + WTCH_GOTSLASH] = 1;  // failed
				SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, true);
			}
		}
	}
}

public void OnTakeDamagePost_Witch(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	// only called for witches, so no check required
	char witch_key[10];
	FormatEx(witch_key, sizeof(witch_key), "%x", victim);
	int witch_dmg_array[MAXPLAYERS + DMGARRAYEXT];

	if (!GetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT)) {
		for (int i = 0; i <= MAXPLAYERS; i++) {
			witch_dmg_array[i] = 0;
		}
		
		witch_dmg_array[MAXPLAYERS+WTCH_HEALTH] = GetConVarInt(g_hCvarWitchHealth);
		SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, false);
	}

	// store damage done to witch
	if (IS_VALID_SURVIVOR(attacker)) {
		witch_dmg_array[attacker] += RoundToFloor(damage);
		witch_dmg_array[MAXPLAYERS+WTCH_HEALTH] -= RoundToFloor(damage);

		// remember last shot
		if (g_fWitchShotStart[attacker] == 0.0 || (GetGameTime(), g_fWitchShotStart[attacker]) > SHOTGUN_BLAST_TIME) {
			// reset last shot damage count and attacker
			g_fWitchShotStart[attacker] = GetGameTime();
			witch_dmg_array[MAXPLAYERS+WTCH_CROWNER] = attacker;
			witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] = 0;
			witch_dmg_array[MAXPLAYERS + WTCH_CROWNTYPE] = (damagetype & DMG_BUCKSHOT) ? 1 : 0; // only allow shotguns
		}

		// continued blast, add up
		witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] += RoundToFloor(damage);

		SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, true);
	} else {
		// store all chip from other sources than survivor in [0]
		witch_dmg_array[0] += RoundToFloor(damage);
		//witch_dmg_array[MAXPLAYERS+1] -= RoundToFloor(damage);
		SetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT, true);
	}
}

public Action Timer_CheckWitchCrown(Handle hTimer, Handle pack)
{
	ResetPack(pack);
	int attacker = ReadPackCell(pack);
	int witch = ReadPackCell(pack);
	bool bOneShot = view_as<bool>(ReadPackCell(pack));
	CloseHandle(pack);

	CheckWitchCrown(witch, attacker, bOneShot);
}

static void CheckWitchCrown(int witch, int attacker, bool bOneShot = false)
{
	char witch_key[10];
	FormatEx(witch_key, sizeof(witch_key), "%x", witch);
	int witch_dmg_array[MAXPLAYERS + DMGARRAYEXT];
	if (!GetTrieArray(g_hWitchTrie, witch_key, witch_dmg_array, MAXPLAYERS + DMGARRAYEXT)) {
		PrintDebug("Witch Crown Check: Error: Trie entry missing (entity: %i, oneshot: %i)", witch, bOneShot);
		return;
	}

	int chipDamage = 0;
	int iWitchHealth = GetConVarInt(g_hCvarWitchHealth);

	/*
		the attacker is the last one that did damage to witch
			if their damage is full damage on an unharrassed witch, it's a full crown
			if their damage is full or > drawcrown_threshhold, it's a drawcrown
	*/

	// not a crown at all if anyone was hit, or if the killing damage wasn't a shotgun blast

	// safeguard: if it was a 'oneshot' witch kill, must've been a shotgun
	//      this is not enough: sometimes a shotgun crown happens that is not even reported as a oneshot...
	//      seems like the cause is that the witch post ontakedamage is not called in time?
	if (bOneShot) {
		witch_dmg_array[MAXPLAYERS + WTCH_CROWNTYPE] = 1;
	}

	if (witch_dmg_array[MAXPLAYERS + WTCH_GOTSLASH] || !witch_dmg_array[MAXPLAYERS + WTCH_CROWNTYPE]) {
		PrintDebug("Witch Crown Check: Failed: bungled: %i / crowntype: %i (entity: %i)", \
						witch_dmg_array[MAXPLAYERS + WTCH_GOTSLASH], witch_dmg_array[MAXPLAYERS + WTCH_CROWNTYPE], witch
		);
		PrintDebug("Witch Crown Check: Further details: attacker: %N, attacker dmg: %i, teamless dmg: %i", \
						attacker, witch_dmg_array[attacker], witch_dmg_array[0]
		);
		return;
	}

	PrintDebug("Witch Crown Check: crown shot: %i, harrassed: %i (full health: %i / drawthresh: %i / oneshot %i)", \
						witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT], witch_dmg_array[MAXPLAYERS + WTCH_STARTLED], \
						iWitchHealth, GetConVarInt(g_hCvarDrawCrownThresh), bOneShot
	);

	// full crown? unharrassed
	if (!witch_dmg_array[MAXPLAYERS + WTCH_STARTLED] && (bOneShot || witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] >= iWitchHealth)) {
		// make sure that we don't count any type of chip
		if (GetConVarBool(g_hCvarHideFakeDamage)) {
			chipDamage = 0;
			for (int i = 0; i <= MAXPLAYERS; i++) {
				if (i == attacker) { 
					continue; 
				}
				
				chipDamage += witch_dmg_array[i];
			}
			
			witch_dmg_array[attacker] = iWitchHealth - chipDamage;
		}
		HandleCrown(attacker, witch_dmg_array[attacker]);
	} else if (witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] >= GetConVarInt(g_hCvarDrawCrownThresh)) {
		// draw crown: harassed + over X damage done by one survivor -- in ONE shot

		for (int i = 0; i <= MAXPLAYERS; i++) {
			if (i == attacker) {
				// count any damage done before final shot as chip
				chipDamage += witch_dmg_array[i] - witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT];
			} else {
				chipDamage += witch_dmg_array[i];
			}
		}

		// make sure that we don't count any type of chip
		if (GetConVarBool(g_hCvarHideFakeDamage)) {
			// unlikely to happen, but if the chip was A LOT
			if (chipDamage >= iWitchHealth) {
				chipDamage = iWitchHealth - 1;
				witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] = 1;
			} else {
				witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] = iWitchHealth - chipDamage;
			}
			
			// re-check whether it qualifies as a drawcrown:
			if (witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] < GetConVarInt(g_hCvarDrawCrownThresh)) { 
				return;
			}
		}

		// plus, set final shot as 'damage', and the rest as chip
		HandleDrawCrown(attacker, witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT], chipDamage);
	}

	// remove trie
}

// drawcrown
static void HandleDrawCrown(int attacker, int damage, int chipdamage)
{
	Action aResult = Plugin_Continue;
	
	// call forward
	Call_StartForward(g_hForwardDrawCrown);
	Call_PushCell(attacker);
	Call_PushCell(damage);
	Call_PushCell(chipdamage);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_DRAWCROWN) {
		if (IS_VALID_INGAME(attacker)) {
			PrintToChatAll("\x04%N\x01 draw-crowned a witch (\x03%i\x01 damage, \x05%i\x01 chip).", attacker, damage, chipdamage);
		} else {
			PrintToChatAll("A witch was draw-crowned (\x03%i\x01 damage, \x05%i\x01 chip).", damage, chipdamage);
		}
	}
}

// crown
static void HandleCrown(int attacker, int damage)
{
	Action aResult = Plugin_Continue;
	// call forward
	Call_StartForward(g_hForwardCrown);
	Call_PushCell(attacker);
	Call_PushCell(damage);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_CROWN) {
		if (IS_VALID_INGAME(attacker)) {
			PrintToChatAll("\x04%N\x01 crowned a witch (\x03%i\x01 damage).", attacker, damage);
		} else {
			PrintToChatAll("A witch was crowned.");
		}
	}
}

static bool IsWitch(int iEntity)
{
	if (!IsValidEdict(iEntity)) {
		return false;
	}

	char sClassName[64];
	GetEdictClassname(iEntity, sClassName, sizeof(sClassName));
	return (strncmp(sClassName, "witch", 5) == 0); //witch and witch_bride
}
