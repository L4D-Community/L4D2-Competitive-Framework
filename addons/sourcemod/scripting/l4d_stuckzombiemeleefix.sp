#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define DEBUG					0
#define PLUGIN_VERSION			"1.2"
#define LIFE_ALIVE				0
#define ENTITY_NAME_MAX_LENGTH	64

bool g_bMeleeDelay[MAXPLAYERS + 1] = {false, ...};

public Plugin myinfo =
{
	name = "Stuck Zombie Melee Fix",
	author = "AtomicStryker",
	description = "Smash nonstaggering Zombies",
	version = PLUGIN_VERSION,
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public void OnPluginStart()
{
	HookEvent("entity_shoved", Event_EntShoved, EventHookMode_Post);

	AddNormalSoundHook(HookSound_Callback); //my melee hook since they didnt include an event for it
}

public Action HookSound_Callback(int iClients[MAXPLAYERS], int &iNumClients, char sSample[PLATFORM_MAX_PATH], int &iEntity, int &iChannel, \
				float &fVolume, int &iLevel, int &iPitch, int &iFlags, char sSoundEntry[PLATFORM_MAX_PATH], int &iSeed)
{
	//to work only on melee sounds, its 'swish' or 'weaponswing'
	if (StrContains(sSample, "Swish", false) == -1) {
		return Plugin_Continue;
	}
	//so the client has the melee sound playing. OMG HES MELEEING!

	if (iEntity > MaxClients) {
		return Plugin_Continue; // bugfix for some people on L4D2
	}

	//add in a 1 second delay so this doesnt fire every frame
	if (g_bMeleeDelay[iEntity]) {
		return Plugin_Continue; //note 'Entity' means 'client' here
	}

	g_bMeleeDelay[iEntity] = true;
	CreateTimer(1.0, Timer_ResetMeleeDelay, iEntity);

#if DEBUG
	PrintToChatAll("Melee detected via soundhook.");
#endif

	int iEntityTarget = GetClientAimTarget(iEntity, false);
	if (iEntityTarget <= MaxClients) {
		return Plugin_Continue;
	}

	if (!IsCommonInfected(iEntityTarget)) {
		return Plugin_Continue;
	}

	float fClientpos[3], fEntpos[3];
	GetEntityAbsOrigin(iEntityTarget, fEntpos);
	GetClientEyePosition(iEntity, fClientpos);
	if (GetVectorDistance(fClientpos, fEntpos) < 50.0) {
		return Plugin_Continue; //else you could 'jedi melee' Zombies from a distance
	}

#if DEBUG
	PrintToChatAll("Youre meleeing and looking at Zombie id #%i", iEntityTarget);
#endif

	//now to make this Zombie fire a event to be caught by the actual 'fix'

	Event hEvent = CreateEvent("entity_shoved", true);
	if (hEvent != null) {
		hEvent.SetInt("attacker", iEntity); //the client being called Entity is a bit unfortunate
		hEvent.SetInt("entityid", iEntityTarget);
		hEvent.Fire(true);
	}

	return Plugin_Continue;
}

public Action Timer_ResetMeleeDelay(Handle hTimer, int iClient)
{
	g_bMeleeDelay[iClient] = false;

	return Plugin_Stop;
}

public void Event_EntShoved(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iEntity = hEvent.GetInt("entityid"); //get the events shoved entity id
	
	if (!IsCommonInfected(iEntity)) {
		return; //make sure it IS a zombie.
	}

	float fPos[3];
	GetEntityAbsOrigin(iEntity, fPos); //get the Zombies position

	DataPack hPack; //a data pack because i need multiple values saved
	CreateDataTimer(0.5, Timer_CheckForMovement, hPack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE); //0.5 seemed both long enough for a normal zombie to stumble away and for a stuck one to DIEEEEE

	hPack.WriteCell(EntIndexToEntRef(iEntity)); //save the Zombie id
	hPack.WriteFloat(fPos[0]); //save the Zombies position
	hPack.WriteFloat(fPos[1]);
	hPack.WriteFloat(fPos[2]);

#if DEBUG
	PrintToChatAll("Meleed Zombie detected.");
#endif
}

public Action Timer_CheckForMovement(Handle hTimer, DataPack hPack)
{
	hPack.Reset(); //this resets our 'reading' position in the data pack, to start from the beginning

	int iZombie = EntRefToEntIndex(hPack.ReadCell()); //get the Zombie id
	if (iZombie == INVALID_ENT_REFERENCE || !IsValidEdict(iZombie)) {
		return Plugin_Stop; //did the zombie get disappear somehow?
	}

	if (!IsCommonInfected(iZombie) || !IsAlive(iZombie)) {
		return Plugin_Stop; //make sure it STILL IS a zombie.
	}

	float fOldpos[3], fNewpos[3];
	fOldpos[0] = hPack.ReadFloat(); //get the old Zombie position (half a sec ago)
	fOldpos[1] = hPack.ReadFloat();
	fOldpos[2] = hPack.ReadFloat();
	GetEntityAbsOrigin(iZombie, fNewpos); //get the Zombies current position

	if (GetVectorDistance(fOldpos, fNewpos) > 5.0) {
		return Plugin_Stop; //if the positions differ, the zombie was correctly shoved and is now staggering. Plugin End
	}

#if DEBUG
	PrintToChatAll("Stuck meleed Zombie detected.");
#endif

	//now i could simply slay the stuck zombie. but this would also instantkill any zombie you meleed into a corner or against a wall
	//so instead i coded a two-punts-it-doesnt-move-so-slay-it command

	int iZombieHealth = GetEntProp(iZombie, Prop_Data, "m_iHealth");
	int iZombieHealthMax = GetEntProp(iZombie, Prop_Data, "m_iMaxHealth"); //FindConVar("z_health").IntValue;

	if (iZombieHealth - (iZombieHealthMax / 2) <= 0) { // if the zombies health is less than half
		//SetEntProp(iZombie, Prop_Data, "m_iHealth", 0); //CRUSH HIM!!!!!! - ragdoll bug, unused
		AcceptEntityInput(iZombie, "BecomeRagdoll"); //Damizean pointed this one out, Cheers to him.

		#if DEBUG
			PrintToChatAll("Slayed Stuck Zombie.");
		#endif
	} else {
		SetEntProp(iZombie, Prop_Data, "m_iHealth", iZombieHealth - (iZombieHealthMax / 2)); //else remove half of its health, so the zombie dies from the next melee blow
	}

	return Plugin_Stop;
}

//entity abs origin code from here
//http://forums.alliedmods.net/showpost.php?s=e5dce96f11b8e938274902a8ad8e75e9&p=885168&postcount=3
void GetEntityAbsOrigin(int iEntity, float fOrigin[3])
{
	float fMins[3], fMaxs[3];
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
	GetEntPropVector(iEntity, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", fMaxs);

	fOrigin[0] += (fMins[0] + fMaxs[0]) * 0.5;
	fOrigin[1] += (fMins[1] + fMaxs[1]) * 0.5;
	fOrigin[2] += (fMins[2] + fMaxs[2]) * 0.5;
}

bool IsCommonInfected(int iEntity)
{
	char sEntityName[ENTITY_NAME_MAX_LENGTH];
	GetEdictClassname(iEntity, sEntityName, sizeof(sEntityName));
	return (strcmp(sEntityName, "infected", false) == 0);
}

bool IsAlive(int iEntity)
{
	return (GetEntProp(iEntity, Prop_Data, "m_lifeState") == LIFE_ALIVE);
}
