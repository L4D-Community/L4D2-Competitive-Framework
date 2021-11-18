#if defined _L4D2SD_CARALARM_INCLUDED_
	#endinput
#endif
#define _L4D2SD_CARALARM_INCLUDED_

#define CARALARM_MIN_TIME		0.11			// maximum time after touch/shot => alarm to connect the two events (test this for LAG)

enum
{
	CALARM_UNKNOWN,
	CALARM_HIT,
	CALARM_TOUCHED,
	CALARM_EXPLOSION,
	CALARM_BOOMER,
	enAlarmReasons
};

static Handle
	g_hForwardAlarmTriggered = null;

static StringMap
	g_hCarTrie = null;							// car alarm tracking

static float
	g_fLastCarAlarm = 0.0;						// time when last car alarm went off

static int
	g_iLastCarAlarmReason[MAXPLAYERS + 1],		// what this survivor did to set the last alarm off
	g_iLastCarAlarmBoomer;						// if a boomer triggered an alarm, remember it

void CarAlarm_AskPluginLoad2()
{
	g_hForwardAlarmTriggered =  CreateGlobalForward("OnCarAlarmTriggered", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
}

void CarAlarm_OnPluginStart()
{
	HookEvent("triggered_car_alarm", CarAlarm_Event_CarAlarmGoesOff, EventHookMode_Post);
	HookEvent("round_end", CarAlarm_Event_RoundEnd, EventHookMode_PostNoCopy);

	g_hCarTrie = new StringMap();
}

public void CarAlarm_Event_RoundEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// clean trie, new cars will be created
	ClearTrie(g_hCarTrie);
}

public void CarAlarm_Event_CarAlarmGoesOff(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	g_fLastCarAlarm = GetGameTime();
}

bool CarAlarm_OnEntityCreated(int iEntity, const char[] sClassName)
{
	if (sClassName[0] != 'p') {
		return false;
	}

	if (strcmp(sClassName, "prop_car_alarm") == 0) {
		//char car_key[10];
		//FormatEx(car_key, sizeof(car_key), "%x", iEntity);

		SDKHook(iEntity, SDKHook_OnTakeDamage, OnTakeDamage_Car);
		SDKHook(iEntity, SDKHook_Touch, OnTouch_Car);

		SDKHook(iEntity, SDKHook_Spawn, OnEntitySpawned_CarAlarm);
		return true;
	} else if (strcmp(sClassName, "prop_car_glass") == 0) {
		SDKHook(iEntity, SDKHook_OnTakeDamage, OnTakeDamage_CarGlass);
		SDKHook(iEntity, SDKHook_Touch, OnTouch_CarGlass);

		//SetTrieValue(g_hCarTrie, car_key,);
		SDKHook(iEntity, SDKHook_Spawn, OnEntitySpawned_CarAlarmGlass);
		return true;
	}

	return false;
}

public void OnEntitySpawned_CarAlarm(int entity)
{
	if (!IsValidEntity(entity)) {
		return; 
	}

	char car_key[10];
	FormatEx(car_key, sizeof(car_key), "%x", entity);

	char target[48];
	GetEntPropString(entity, Prop_Data, "m_iName", target, sizeof(target));

	SetTrieValue(g_hCarTrie, target, entity);
	SetTrieValue(g_hCarTrie, car_key, 0);         // who shot the car?

	HookSingleEntityOutput(entity, "OnCarAlarmStart", Hook_CarAlarmStart);
}

public void OnEntitySpawned_CarAlarmGlass(int entity)
{
	if (!IsValidEntity(entity)) {
		return;
	}

	// glass is parented to a car, link the two through the trie
	// find parent and save both
	char car_key[10];
	FormatEx(car_key, sizeof(car_key), "%x", entity);

	char parent[48];
	GetEntPropString(entity, Prop_Data, "m_iParent", parent, sizeof(parent));
	int parentEntity;

	// find targetname in trie
	if (GetTrieValue(g_hCarTrie, parent, parentEntity)) {
		// if valid entity, save the parent entity
		if (IsValidEntity(parentEntity)) {
			SetTrieValue(g_hCarTrie, car_key, parentEntity);

			char car_key_p[10];
			FormatEx(car_key_p, sizeof(car_key_p), "%x_A", parentEntity);
			int testEntity;

			if (GetTrieValue(g_hCarTrie, car_key_p, testEntity)) {
				// second glass
				FormatEx(car_key_p, sizeof(car_key_p), "%x_B", parentEntity);
			}

			SetTrieValue(g_hCarTrie, car_key_p, entity);
		}
	}
}

public Action OnTakeDamage_Car(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!IS_VALID_SURVIVOR(attacker)) { 
		return Plugin_Continue; 
	}

	/*
		boomer popped on alarmed car =
			DMG_BLAST_SURFACE| DMG_BLAST
		and inflictor is the boomer

		melee slash/club =
			DMG_SLOWBURN|DMG_PREVENT_PHYSICS_FORCE + DMG_CLUB or DMG_SLASH
		shove is without DMG_SLOWBURN
	*/

	CreateTimer(0.01, Timer_CheckAlarm, victim, TIMER_FLAG_NO_MAPCHANGE);

	char car_key[10];
	FormatEx(car_key, sizeof(car_key), "%x", victim);
	SetTrieValue(g_hCarTrie, car_key, attacker);

	if (damagetype & DMG_BLAST) {
		if (IS_VALID_INFECTED(inflictor) && GetEntProp(inflictor, Prop_Send, "m_zombieClass") == L4D2Infected_Boomer) {
			g_iLastCarAlarmReason[attacker] = CALARM_BOOMER;
			g_iLastCarAlarmBoomer = inflictor;
		} else {
			g_iLastCarAlarmReason[attacker] = CALARM_EXPLOSION;
		}
	} else if (damage == 0.0 && (damagetype & DMG_CLUB || damagetype & DMG_SLASH) && !(damagetype & DMG_SLOWBURN)) {
		g_iLastCarAlarmReason[attacker] = CALARM_TOUCHED;
	} else {
		g_iLastCarAlarmReason[attacker] = CALARM_HIT;
	}

	return Plugin_Continue;
}

public void OnTouch_Car(int entity, int client)
{
	if (!IS_VALID_SURVIVOR(client)) { 
		return; 
	}

	CreateTimer(0.01, Timer_CheckAlarm, entity, TIMER_FLAG_NO_MAPCHANGE);

	char car_key[10];
	FormatEx(car_key, sizeof(car_key), "%x", entity);
	SetTrieValue(g_hCarTrie, car_key, client);

	g_iLastCarAlarmReason[client] = CALARM_TOUCHED;
}

public Action OnTakeDamage_CarGlass(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamagetype)
{
	// check for either: boomer pop or survivor
	if (!IS_VALID_SURVIVOR(iAttacker)) {
		return Plugin_Continue;
	}

	char car_key[10];
	FormatEx(car_key, sizeof(car_key), "%x", iVictim);
	int parentEntity;

	if (GetTrieValue(g_hCarTrie, car_key, parentEntity)) {
		CreateTimer(0.01, Timer_CheckAlarm, parentEntity, TIMER_FLAG_NO_MAPCHANGE);

		FormatEx(car_key, sizeof(car_key), "%x", parentEntity);
		SetTrieValue(g_hCarTrie, car_key, iAttacker);

		if (iDamagetype & DMG_BLAST) {
			if (IS_VALID_INFECTED(iInflictor) && GetEntProp(iInflictor, Prop_Send, "m_zombieClass") == L4D2Infected_Boomer) {
				g_iLastCarAlarmReason[iAttacker] = CALARM_BOOMER;
				g_iLastCarAlarmBoomer = iInflictor;
			} else {
				g_iLastCarAlarmReason[iAttacker] = CALARM_EXPLOSION;
			}
		} else if (fDamage == 0.0 && (iDamagetype & DMG_CLUB || iDamagetype & DMG_SLASH) && !(iDamagetype & DMG_SLOWBURN)) {
			g_iLastCarAlarmReason[iAttacker] = CALARM_TOUCHED;
		} else {
			g_iLastCarAlarmReason[iAttacker] = CALARM_HIT;
		}
	}

	return Plugin_Continue;
}

public void OnTouch_CarGlass(int entity, int client)
{
	if (!IS_VALID_SURVIVOR(client)) { 
		return; 
	}

	char car_key[10];
	FormatEx(car_key, sizeof(car_key), "%x", entity);
	int parentEntity;

	if (GetTrieValue(g_hCarTrie, car_key, parentEntity)) {
		CreateTimer(0.01, Timer_CheckAlarm, parentEntity, TIMER_FLAG_NO_MAPCHANGE);

		FormatEx(car_key, sizeof(car_key), "%x", parentEntity);
		SetTrieValue(g_hCarTrie, car_key, client);

		g_iLastCarAlarmReason[client] = CALARM_TOUCHED;
	}
}

public Action Timer_CheckAlarm(Handle hTimer, any entity)
{
	//PrintToChatAll("checking alarm: time: %.3f", GetGameTime() - g_fLastCarAlarm);

	if ((GetGameTime() - g_fLastCarAlarm) < CARALARM_MIN_TIME) {
		// got a match, drop stuff from trie and handle triggering
		char car_key[10];
		int testEntity;
		int survivor = -1;

		// remove car glass
		FormatEx(car_key, sizeof(car_key), "%x_A", entity);
		if (GetTrieValue(g_hCarTrie, car_key, testEntity)) {
			RemoveFromTrie(g_hCarTrie, car_key);
			SDKUnhook(testEntity, SDKHook_OnTakeDamage, OnTakeDamage_CarGlass);
			SDKUnhook(testEntity, SDKHook_Touch, OnTouch_CarGlass);
		}
		
		FormatEx(car_key, sizeof(car_key), "%x_B", entity);
		
		if (GetTrieValue(g_hCarTrie, car_key, testEntity)) {
			RemoveFromTrie(g_hCarTrie, car_key);
			SDKUnhook(testEntity, SDKHook_OnTakeDamage, OnTakeDamage_CarGlass);
			SDKUnhook(testEntity, SDKHook_Touch, OnTouch_CarGlass);
		}

		// remove car
		FormatEx(car_key, sizeof(car_key), "%x", entity);
		if (GetTrieValue(g_hCarTrie, car_key, survivor)) {
			RemoveFromTrie(g_hCarTrie, car_key);
			SDKUnhook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Car);
			SDKUnhook(entity, SDKHook_Touch, OnTouch_Car);
		}

		// check for infected assistance
		int infected = 0;
		if (IS_VALID_SURVIVOR(survivor)) {
			if (g_iLastCarAlarmReason[survivor] == CALARM_BOOMER) {
				infected = g_iLastCarAlarmBoomer;
			} else if (IS_VALID_INFECTED(GetEntPropEnt(survivor, Prop_Send, "m_carryAttacker"))) {
				infected = GetEntPropEnt(survivor, Prop_Send, "m_carryAttacker");
			} else if (IS_VALID_INFECTED(GetEntPropEnt(survivor, Prop_Send, "m_jockeyAttacker"))) {
				infected = GetEntPropEnt(survivor, Prop_Send, "m_jockeyAttacker");
			} else if (IS_VALID_INFECTED(GetEntPropEnt(survivor, Prop_Send, "m_tongueOwner"))) {
				infected = GetEntPropEnt(survivor, Prop_Send, "m_tongueOwner");
			}
		}

		HandleCarAlarmTriggered(survivor, infected, (IS_VALID_INGAME(survivor)) ? g_iLastCarAlarmReason[survivor] : CALARM_UNKNOWN);
	}

	return Plugin_Stop;
}

// car alarm handling
public void Hook_CarAlarmStart(const char[] output, int caller, int activator, float delay)
{
	//decl String:car_key[10];
	//FormatEx(car_key, sizeof(car_key), "%x", entity);

	PrintDebug("calarm trigger: caller %i / activator %i / delay: %.2f", caller, activator, delay);
}

// car alarms
static void HandleCarAlarmTriggered(int survivor, int infected, int reason)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardAlarmTriggered);
	Call_PushCell(survivor);
	Call_PushCell(infected);
	Call_PushCell(reason);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_CARALARM 
		&& IS_VALID_INGAME(survivor) && !IsFakeClient(survivor)
	) {
		if (reason == CALARM_HIT) {
			PrintToChatAll("\x05%N\x01 triggered an alarm with a hit.", survivor);
		} else if (reason == CALARM_TOUCHED) {
			// if a survivor touches an alarmed car, it might be due to a special infected...
			if (IS_VALID_INFECTED(infected)) {
				if (!IsFakeClient(infected)) {
					PrintToChatAll("\x04%N\x01 made \x05%N\x01 trigger an alarm.", infected, survivor);
				} else {
					switch (GetEntProp(infected, Prop_Send, "m_zombieClass")) {
						case L4D2Infected_Smoker: { 
							PrintToChatAll("\x01A hunter made \x05%N\x01 trigger an alarm.", survivor); 
						}
						case L4D2Infected_Jockey: { 
							PrintToChatAll("\x01A jockey made \x05%N\x01 trigger an alarm.", survivor); 
						}
						case L4D2Infected_Charger: { 
							PrintToChatAll("\x01A charger made \x05%N\x01 trigger an alarm.", survivor); 
						}
						default: { 
							PrintToChatAll("\x01A bot infected made \x05%N\x01 trigger an alarm.", survivor); 
						}
					}
				}
			} else {
				PrintToChatAll("\x05%N\x01 touched an alarmed car.", survivor);
			}
		} else if (reason == CALARM_EXPLOSION) {
			PrintToChatAll("\x05%N\x01 triggered an alarm with an explosion.", survivor);
		} else if (reason == CALARM_BOOMER) {
			if (IS_VALID_INFECTED(infected) && !IsFakeClient(infected)) {
				PrintToChatAll("\x05%N\x01 triggered an alarm by killing a boomer \x04%N\x01.", survivor, infected);
			} else {
				PrintToChatAll("\x05%N\x01 triggered an alarm by shooting a boomer.", survivor);
			}
		} else {
			PrintToChatAll("\x05%N\x01 triggered an alarm.", survivor);
		}
	}
}
