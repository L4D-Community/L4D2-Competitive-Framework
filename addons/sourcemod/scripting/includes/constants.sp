#pragma semicolon 1

const	START_SAFEROOM			= 1 << 0;
const	END_SAFEROOM			= 1 << 1;


enum WeaponIDs
{
	WEPID_PISTOL			 = 1,
	WEPID_SMG,				// 2
	WEPID_PUMPSHOTGUN,		// 3
	WEPID_AUTOSHOTGUN,		// 4
	WEPID_RIFLE,			// 5
	WEPID_HUNTING_RIFLE,	// 6
	WEPID_SMG_SILENCED,		// 7
	WEPID_SHOTGUN_CHROME, 	// 8
	WEPID_RIFLE_DESERT,		// 9
	WEPID_SNIPER_MILITARY,	// 10
	WEPID_SHOTGUN_SPAS, 	// 11
	WEPID_FIRST_AID_KIT, 	// 12
	WEPID_MOLOTOV, 			// 13
	WEPID_PIPE_BOMB, 		// 14
	WEPID_PAIN_PILLS, 		// 15
	WEPID_GASCAN,			// 16
	WEPID_PROPANE_TANK,		// 17
	WEPID_AIR_CANISTER,		// 18
	WEPID_CHAINSAW 			 = 20,
	WEPID_GRENADE_LAUNCHER,	// 21
	WEPID_ADRENALINE 		 = 23,
	WEPID_DEFIBRILLATOR,	// 24
	WEPID_VOMITJAR,			// 25
	WEPID_RIFLE_AK47, 		// 26
	WEPID_GNOME_CHOMPSKI,	// 27
	WEPID_COLA_BOTTLES,		// 28
	WEPID_FIREWORKS_BOX,	// 29
	WEPID_INCENDIARY_AMMO,	// 30
	WEPID_FRAG_AMMO,		// 31
	WEPID_PISTOL_MAGNUM,	// 32
	WEPID_SMG_MP5, 			// 33
	WEPID_RIFLE_SG552, 		// 34
	WEPID_SNIPER_AWP, 		// 35
	WEPID_SNIPER_SCOUT, 	// 36
	WEPID_RIFLE_M60			// 37
};

new String:	g_sTeamName[8][]					= { "Spectator", "" , "Survivor", "Infected", "", "Infected", "Survivors", "Infected" };
const 	NUM_OF_SURVIVORS 	= 4;
const 	TEAM_SURVIVOR		= 2;
const 	TEAM_INFECTED 		= 3;