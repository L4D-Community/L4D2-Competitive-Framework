#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#define LEFT4FRAMEWORK_INCLUDE 1
#include <left4framework>

#define Z_BOOMER 2

public Plugin myinfo =
{
	name = "L4D2 Boomer Shenanigans",
	author = "Sir",
	description = "Make sure Boomers are unable to bile Survivors during a stumble (basically reinforce shoves)",
	version = "1.1",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public Action L4D_OnShovedBySurvivor(int iClient, int iVictim, const float fVecDirection[3])
{
	// Make sure we've got a Boomer on our hands.
	// (L4D2 only uses this on Special Infected so we don't need to check Client Team for the victim)
	// We're only checking Valid Client because it's Valve. ;D
	if (!IsValidClient(iVictim) || GetEntProp(iVictim, Prop_Send, "m_zombieClass") != Z_BOOMER) {
		return Plugin_Continue;
	}

	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}
	
	// Get the Ability
	int iAbility = GetEntPropEnt(iVictim, Prop_Send, "m_customAbility");

	// Make sure it's a valid Ability.
	if (iAbility == -1 || !IsValidEdict(iAbility)) {
		return Plugin_Continue;
	}

	// timestamp is when the Boomer can boom again.
	float fTimestamp = GetEntPropFloat(iAbility, Prop_Send, "m_timestamp");
	float fNow = GetGameTime();
	int bUsed = (GetEntProp(iAbility, Prop_Send, "m_hasBeenUsed", 1) > 0);

	// - 2 Scenarios where we'll have to "reinforce" the shove.
	// If bUsed is false the Boomer hasn't boomed yet in this lifetime (Respawning will reset this to false)
	// If bUsed is true but the Boomer is able to bile (If boomer kept his spawn and is going for another attack)
	if (!bUsed || fNow >= fTimestamp) {
		SetEntPropFloat(iAbility, Prop_Send, "m_timestamp", fNow + 1.0);
	}

	return Plugin_Continue;
}

bool IsValidClient(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient));
}
