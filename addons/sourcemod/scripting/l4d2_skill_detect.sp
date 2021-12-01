/**
 *  L4D2_skill_detect
 *
 *  Plugin to detect and forward reports about 'skill'-actions,
 *  such as skeets, crowns, levels, dp's.
 *  Works in campaign and versus modes.
 *
 *  m_isAttemptingToPounce  can only be trusted for
 *  AI hunters -- for human hunters this gets cleared
 *  instantly on taking killing damage
 *
 *  Shotgun skeets and teamskeets are only counted if the
 *  added up damage to pounce_interrupt is done by shotguns
 *  only. 'Skeeting' chipped hunters shouldn't count, IMO.
 *
 *  This performs global forward calls to:
 *      OnSkeet(survivor, hunter)
 *      OnSkeetMelee(survivor, hunter)
 *      OnSkeetGL(survivor, hunter)
 *      OnSkeetSniper(survivor, hunter)
 *      OnSkeetHurt(survivor, hunter, damage, isOverkill)
 *      OnSkeetMeleeHurt(survivor, hunter, damage, isOverkill)
 *      OnSkeetSniperHurt(survivor, hunter, damage, isOverkill)
 *      OnHunterDeadstop(survivor, hunter)
 *      OnBoomerPop(survivor, boomer, shoveCount, Float:timeAlive)
 *      OnChargerLevel(survivor, charger)
 *      OnChargerLevelHurt(survivor, charger, damage)
 *      OnWitchCrown(survivor, damage)
 *      OnWitchCrownHurt(survivor, damage, chipdamage)
 *      OnTongueCut(survivor, smoker)
 *      OnSmokerSelfClear(survivor, smoker, withShove)
 *      OnTankRockSkeeted(survivor, tank)
 *      OnTankRockEaten(tank, survivor)
 *      OnHunterHighPounce(hunter, victim, actualDamage, Float:calculatedDamage, Float:height, bool:bReportedHigh, bool:bPlayerIncapped)
 *      OnJockeyHighPounce(jockey, victim, Float:height, bool:bReportedHigh)
 *      OnDeathCharge(charger, victim, Float: height, Float: distance, wasCarried)
 *      OnSpecialShoved(survivor, infected, zombieClass)
 *      OnSpecialClear(clearer, pinner, pinvictim, zombieClass, Float:timeA, Float:timeB, withShove)
 *      OnBoomerVomitLanded(boomer, amount)
 *      OnBunnyHopStreak(survivor, streak, Float:maxVelocity)
 *      OnCarAlarmTriggered(survivor, infected, reason)
 *
 *      OnDeathChargeAssist(assister, charger, victim)    [ not done yet ]
 *      OnBHop(player, isInfected, speed, streak)         [ not done yet ]
 *
 *  Where survivor == -2 if it was a team effort, -1 or 0 if unknown or invalid client.
 *  damage is the amount of damage done (that didn't add up to skeeting damage),
 *  and isOverkill indicates whether the shot would've been a skeet if the hunter
 *  had not been chipped.
 *
 *  @author         Tabun
 *  @libraryname    skill_detect
 */

/*
    Reports:
    --------
    Damage shown is damage done in the last shot/slash. So for crowns, this means
    that the 'damage' value is one shotgun blast


    Quirks:
    -------
    Does not report people cutting smoker tongues that target players other
    than themselves. Could be done, but would require (too much) tracking.

    Actual damage done, on Hunter DPs, is low when the survivor gets incapped
    by (a fraction of) the total pounce damage.


    Fake Damage
    -----------
    Hiding of fake damage has the following consequences:
        - Drawcrowns are less likely to be registered: if a witch takes too
          much chip before the crowning shot, the final shot will be considered
          as doing too little damage for a crown (even if it would have been a crown
          had the witch had more health).
        - Charger levels are harder to get on chipped chargers. Any charger that
          has taken (600 - 390 =) 210 damage or more cannot be leveled (even if
          the melee swing would've killed the charger (1559 damage) if it'd have
          had full health).
    I strongly recommend leaving fakedamage visible: it will offer more feedback on
    the survivor's action and reward survivors doing (what would be) full crowns and
    levels on chipped targets.


    To Do
    -----

    - fix:  tank rock owner is not reliable for the RockEaten forward

    - fix:  apparently some HR4 cars generate car alarm messages when shot, even when no alarm goes off
            (combination with car equalize plugin?)
            - see below: the single hook might also fix this.. -- if not, hook for sound
            - do a hookoutput on prop_car_alarm's and use that to track the actual alarm
                going off (might help in the case 2 alarms go off exactly at the same time?)
    - fix:  double prints on car alarms (sometimes? epi + m60)

    - fix:  sometimes instaclear reports double for single clear (0.16s / 0.19s) epi saw this, was for hunter
    - fix:  deadstops and m2s don't always register .. no idea why..
    - fix:  sometimes a (first?) round doesn't work for skeet detection.. no hurt/full skeets are reported or counted

    - make forwards fire for every potential action,
        - include the relevant values, so other plugins can decide for themselves what to consider it

    - test chargers getting dislodged with boomer pops?

    - add commonhop check
    - add deathcharge assist check
        - smoker
        - jockey

    - add deathcharge coordinates for some areas
        - DT4 next to saferoom
        - DA1 near the lower roof, on sidewalk next to fence (no hurttrigger there)
        - DA2 next to crane roof to the right of window
            DA2 charge down into start area, after everyone's jumped the fence

    - count rock hits even if they do no damage [epi request]
    - sir
        - make separate teamskeet forward, with (for now, up to) 4 skeeters + the damage each did
    - xan
        - add detection/display of unsuccesful witch crowns (witch death + info)

    detect...
        - ? add jockey deadstops (and change forward to reflect type)
        - ? speedcrown detection?
        - ? spit-on-cap detection

    ---
    done:
        - applied sanity bounds to calculated damage for hunter dps
        - removed tank's name from rock skeet print
        - 300+ speed hops are considered hops even if no increase
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <colors>
#include <l4d2_direct> //#include <left4dhooks>
#include <l4d2util_constants>

#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == 2)
#define IS_INFECTED(%1)         (GetClientTeam(%1) == 3)
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define IS_VALID_SURVIVOR(%1)   (IS_VALID_INGAME(%1) && IS_SURVIVOR(%1))
#define IS_VALID_INFECTED(%1)   (IS_VALID_INGAME(%1) && IS_INFECTED(%1))

#define SHOTGUN_BLAST_TIME      0.1
#define POUNCE_CHECK_TIME       0.1
#define SHOVE_TIME              0.05
#define MAX_CHARGE_TIME         12.0    // maximum time to pass before charge checking ends
#define CHARGE_CHECK_TIME       0.25    // check interval for survivors flying from impacts
#define CHARGE_END_CHECK        2.5     // after client hits ground after getting impact-charged: when to check whether it was a death
#define CHARGE_END_RECHECK      3.0     // safeguard wait to recheck on someone getting incapped out of bounds
#define VOMIT_DURATION_TIME     2.25    // how long the boomer vomit stream lasts -- when to check for boom count
#define ROCK_CHECK_TIME         0.34    // how long to wait after rock entity is destroyed before checking for skeet/eat (high to avoid lag issues)

#define MIN_DC_TRIGGER_DMG      300     // minimum amount a 'trigger' / drown must do before counted as a death action
#define MIN_DC_FALL_DMG         175     // minimum amount of fall damage counts as death-falling for a deathcharge
#define WEIRD_FLOW_THRESH       900.0   // -9999 seems to be break flow.. but meh
#define MIN_FLOWDROPHEIGHT      350.0   // minimum height a survivor has to have dropped before a WEIRD_FLOW value is treated as a DC spot
#define MIN_DC_RECHECK_DMG      100     // minimum damage from map to have taken on first check, to warrant recheck

#define CUT_SHOVED      1                       // smoker got shoved
#define CUT_SHOVEDSURV  2                       // survivor got shoved
#define CUT_KILL        3                       // reason for tongue break (release_type)
#define CUT_SLASH       4                       // this is used for others shoving a survivor free too, don't trust .. it involves tongue damage?

#define VICFLG_CARRIED          (1 << 0)        // was the one that the charger carried (not impacted)
#define VICFLG_FALL             (1 << 1)        // flags stored per charge victim, to check for deathchargeroony -- fallen
#define VICFLG_DROWN            (1 << 2)        // drowned
#define VICFLG_HURTLOTS         (1 << 3)        // whether the victim was hurt by 400 dmg+ at once
#define VICFLG_TRIGGER          (1 << 4)        // killed by trigger_hurt
#define VICFLG_AIRDEATH         (1 << 5)        // died before they hit the ground (impact check)
#define VICFLG_KILLEDBYOTHER    (1 << 6)        // if the survivor was killed by an SI other than the charger
#define VICFLG_WEIRDFLOW        (1 << 7)        // when survivors get out of the map and such
#define VICFLG_WEIRDFLOWDONE    (1 << 8)        //      checked, don't recheck for this

#define REP_SKEET				(1 << 0)  // 1 (HandleSkeet)
#define REP_HURTSKEET			(1 << 1)  // 2 (HandleNonSkeet)
#define REP_LEVEL				(1 << 2)  // 4 (HandleLevel)
#define REP_HURTLEVEL			(1 << 3)  // 8 (HandleLevelHurt)
#define REP_CROWN				(1 << 4)  // 16 (HandleCrown)
#define REP_DRAWCROWN			(1 << 5)  // 32 (HandleDrawCrown)
#define REP_TONGUECUT			(1 << 6)  // 64 (HandleTongueCut)
#define REP_SELFCLEAR			(1 << 7)  // 128 (HandleSmokerSelfClear)
#define REP_SELFCLEARSHOVE		(1 << 8)  // 256 (HandleSmokerSelfClear)
#define REP_ROCKSKEET			(1 << 9)  // 512 (HandleRockSkeeted)
#define REP_DEADSTOP			(1 << 10) // 1024 (HandleDeadstop)
#define REP_POP					(1 << 11) // 2048 (HandlePop)
#define REP_SHOVE				(1 << 12) // 4096 (HandleShove)
#define REP_HUNTERDP			(1 << 13) // 8192 (HandleHunterDP)
#define REP_JOCKEYDP			(1 << 14) // 16384 (HandleJockeyDP)
#define REP_DEATHCHARGE			(1 << 15) // 32768 (HandleDeathCharge)
#define REP_DC_ASSIST			(1 << 16) // 65536 (not used)
#define REP_INSTACLEAR			(1 << 17) // 131072 (HandleClear)
#define REP_BHOPSTREAK			(1 << 18) // 262144 (HandleBHopStreak)
#define REP_CARALARM			(1 << 19) // 524288 (HandleCarAlarmTriggered)

#define REP_FULLFLAG			1048575

// REP_SKEET | REP_LEVEL | REP_CROWN | REP_DRAWCROWN | REP_HUNTERDP | REP_JOCKEYDP | REP_DEATHCHARGE | REP_CARALARM
//
// HandleSkeet HandleLevel HandleCrown HandleDrawCrown HandleHunterDP HandleJockeyDP HandleDeathCharge HandleCarAlarmTriggered
//
// 1 4 16 32 8192 16384 32768 65536 (122933 with ASSIST, 57397 without); 131072 for instaclears + 524288 for car alarm
// Old Value - 581685

// REP_CARALARM | REP_BHOPSTREAK | REP_INSTACLEAR | REP_DEATHCHARGE | REP_HUNTERDP | REP_SHOVE | REP_POP | REP_DEADSTOP | REP_ROCKSKEET |
// | REP_SELFCLEAR | REP_SELFCLEARSHOVE | REP_TONGUECUT | REP_HURTLEVEL | REP_LEVEL | REP_HURTSKEET | REP_SKEET
//
// HandleCarAlarmTriggered | HandleBHopStreak | HandleClear | HandleDeathCharge | HandleHunterDP | HandleShove | HandlePop | HandleDeadstop | HandleRockSkeeted |
// | HandleSmokerSelfClear | HandleSmokerSelfClear2 | HandleTongueCut | HandleLevelHurt | HandleLevel | HandleNonSkeet | HandleSkeet
//
// 524288 + 262144 + 131072 + 32768 + 8192 + 4096 + 2048 + 1024 + 512 +
// + 256 + 128 + 64 + 8 + 4 + 2 + 1
// New Value - 966607
#define REP_DEFAULT "966607"

/*
// l4d2 rework flag 451532
// REP_LEVEL (4) + REP_HURTLEVEL (8) + REP_TONGUECUT (64) + REP_SELFCLEAR (128) + REP_SELFCLEARSHOVE (256) + REP_ROCKSKEET (512) +
// + REP_HUNTERDP (8192) + REP_JOCKEYDP (16384) + REP_DEATHCHARGE (32768) + REP_INSTACLEAR (131072) + REP_BHOPSTREAK (262144)
// 4 + 8 + 64 + 128 + 256 + 512 + 8192 + 16384 + 32768 + 131072 + 262144 = 451532
*/

// trie values: weapon type
enum
{
	WPTYPE_SNIPER,
	WPTYPE_MAGNUM,
	WPTYPE_GL
};

// trie values: OnEntityCreated classname
enum strOEC
{
	OEC_WITCH,
	OEC_TANKROCK,
	OEC_TRIGGER,
	OEC_CARALARM,
	OEC_CARGLASS
};

enum
{
	rckDamage,
	rckTank,
	rckSkeeter,
	strRockData
};

static const char g_csSIClassName[][] =
{
	"",
	"smoker",
	"boomer",
	"hunter",
	"spitter",
	"jockey",
	"charger",
	"witch",
	"tank"
};

bool g_bLateLoad = false;

Handle g_hForwardSkeet = null;
Handle g_hForwardSkeetHurt = null;
Handle g_hForwardSkeetMelee = null;
Handle g_hForwardSkeetMeleeHurt = null;
Handle g_hForwardSkeetSniper = null;
Handle g_hForwardSkeetSniperHurt = null;
Handle g_hForwardSkeetGL = null;
Handle g_hForwardHunterDeadstop = null;
Handle g_hForwardSIShove = null;
Handle g_hForwardBoomerPop = null;
Handle g_hForwardLevel = null;
Handle g_hForwardLevelHurt = null;
Handle g_hForwardTongueCut = null;
Handle g_hForwardSmokerSelfClear = null;
Handle g_hForwardRockSkeeted = null;
Handle g_hForwardRockEaten = null;
Handle g_hForwardHunterDP = null;
Handle g_hForwardJockeyDP = null;
Handle g_hForwardDeathCharge = null;
Handle g_hForwardClear = null;
Handle g_hForwardVomitLanded = null;

Handle g_hTrieWeapons = null;   // weapon check
Handle g_hTrieEntityCreated = null;   // getting classname of entity created
Handle g_hRockTrie = null;   // tank rock tracking

// all SI / pinners
float g_fSpawnTime[MAXPLAYERS + 1];                               // time the SI spawned up
float g_fPinTime[MAXPLAYERS + 1][2];                            // time the SI pinned a target: 0 = start of pin (tongue pull, charger carry); 1 = carry end / tongue reigned in
int g_iSpecialVictim[MAXPLAYERS + 1];                               // current victim (set in traceattack, so we can check on death)

// hunters: skeets/pounces
int g_iHunterShotDmgTeam[MAXPLAYERS + 1];                               // counting shotgun blast damage for hunter, counting entire survivor team's damage
int g_iHunterShotDmg[MAXPLAYERS + 1][MAXPLAYERS + 1];               // counting shotgun blast damage for hunter / skeeter combo
float g_fHunterShotStart[MAXPLAYERS + 1][MAXPLAYERS + 1];               // when the last shotgun blast on hunter started (if at any time) by an attacker
float g_fHunterTracePouncing[MAXPLAYERS + 1];                               // time when the hunter was still pouncing (in traceattack) -- used to detect pouncing status
float g_fHunterLastShot[MAXPLAYERS + 1];                               // when the last shotgun damage was done (by anyone) on a hunter
int g_iHunterLastHealth[MAXPLAYERS + 1];                               // last time hunter took any damage, how much health did it have left?
int g_iHunterOverkill[MAXPLAYERS + 1];                               // how much more damage a hunter would've taken if it wasn't already dead
bool g_bHunterKilledPouncing[MAXPLAYERS + 1];                               // whether the hunter was killed when actually pouncing
int g_iPounceDamage[MAXPLAYERS + 1];                               // how much damage on last 'highpounce' done
float g_fPouncePosition[MAXPLAYERS + 1][3];                            // position that a hunter (jockey?) pounced from (or charger started his carry)

// deadstops
float g_fVictimLastShove[MAXPLAYERS + 1][MAXPLAYERS + 1];               // when was the player shoved last by attacker? (to prevent doubles)

// levels / charges
int g_iChargerHealth[MAXPLAYERS + 1];                               // how much health the charger had the last time it was seen taking damage
float g_fChargeTime[MAXPLAYERS + 1];                               // time the charger's charge last started, or if victim, when impact started
int g_iChargeVictim[MAXPLAYERS + 1];                               // who got charged
float g_fChargeVictimPos[MAXPLAYERS + 1][3];                            // location of each survivor when it got hit by the charger
int g_iVictimCharger[MAXPLAYERS + 1];                               // for a victim, by whom they got charge(impacted)
int g_iVictimFlags[MAXPLAYERS + 1];                               // flags stored per charge victim: VICFLAGS_
int g_iVictimMapDmg[MAXPLAYERS + 1];                               // for a victim, how much the cumulative map damage is so far (trigger hurt / drowning)

// pops
bool g_bBoomerHitSomebody[MAXPLAYERS + 1];                               // false if boomer didn't puke/exploded on anybody
int g_iBoomerGotShoved[MAXPLAYERS + 1];                               // count boomer was shoved at any point
int g_iBoomerVomitHits[MAXPLAYERS + 1];                               // how many booms in one vomit so far

// smoker clears
bool g_bSmokerClearCheck[MAXPLAYERS + 1];                               // [smoker] smoker dies and this is set, it's a self-clear if g_iSmokerVictim is the killer
int g_iSmokerVictim[MAXPLAYERS + 1];                               // [smoker] the one that's being pulled
int g_iSmokerVictimDamage[MAXPLAYERS + 1];                               // [smoker] amount of damage done to a smoker by the one he pulled
bool g_bSmokerShoved[MAXPLAYERS + 1];                               // [smoker] set if the victim of a pull manages to shove the smoker

// rocks
int g_iTankRock[MAXPLAYERS + 1];                               // rock entity per tank
int g_iRocksBeingThrown[10];                                           // 10 tanks max simultanously throwing rocks should be ok (this stores the tank client)
int g_iRocksBeingThrownCount = 0;                // so we can do a push/pop type check for who is throwing a created rock

// cvars
Handle g_hCvarReport = null;   // cvar whether to report at all
Handle g_hCvarReportFlags = null;   // cvar what to report

Handle g_hCvarAllowMelee = null;   // cvar whether to count melee skeets
Handle g_hCvarAllowSniper = null;   // cvar whether to count sniper headshot skeets
Handle g_hCvarAllowGLSkeet = null;   // cvar whether to count direct hit GL skeets
Handle g_hCvarSelfClearThresh = null;   // cvar damage while self-clearing from smokers
Handle g_hCvarHunterDPThresh = null;   // cvar damage for hunter highpounce
Handle g_hCvarJockeyDPThresh = null;   // cvar distance for jockey highpounce
Handle g_hCvarHideFakeDamage = null;   // cvar damage while self-clearing from smokers
Handle g_hCvarDeathChargeHeight = null;   // cvar how high a charger must have come in order for a DC to count
Handle g_hCvarInstaTime = null;   // cvar clear within this time or lower for instaclear

Handle g_hCvarPounceInterrupt = null;   // z_pounce_damage_interrupt
int g_iPounceInterrupt = 150;
Handle g_hCvarChargerHealth = null;   // z_charger_health
Handle g_hCvarMaxPounceDistance = null;   // z_pounce_damage_range_max
Handle g_hCvarMinPounceDistance = null;   // z_pounce_damage_range_min
Handle g_hCvarMaxPounceDamage = null;   // z_hunter_max_pounce_bonus_damage;

// modules
#include "l4d2_skill_detect/l4d2sd_car_alarm.sp"
#include "l4d2_skill_detect/l4d2sd_witch.sp"
#include "l4d2_skill_detect/l4d2sd_bhop.sp"

public Plugin myinfo =
{
	name = "Skill Detection (skeets, crowns, levels)",
	author = "Tabun, A1m`",
	description = "Detects and reports skeets, crowns, levels, highpounces, etc.",
	version = "1.2",
	url = "https://github.com/L4D-Community/L4D2-Competitive-Framework"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax)
{
	Witch_AskPluginLoad2();
	CarAlarm_AskPluginLoad2();
	Bhop_AskPluginLoad2();

	g_hForwardSkeet = CreateGlobalForward("OnSkeet", ET_Event, Param_Cell, Param_Cell);
	g_hForwardSkeetHurt = CreateGlobalForward("OnSkeetHurt", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	g_hForwardSkeetMelee = CreateGlobalForward("OnSkeetMelee", ET_Event, Param_Cell, Param_Cell);
	g_hForwardSkeetMeleeHurt = CreateGlobalForward("OnSkeetMeleeHurt", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	g_hForwardSkeetSniper = CreateGlobalForward("OnSkeetSniper", ET_Event, Param_Cell, Param_Cell);
	g_hForwardSkeetSniperHurt = CreateGlobalForward("OnSkeetSniperHurt", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	g_hForwardSkeetGL = CreateGlobalForward("OnSkeetGL", ET_Event, Param_Cell, Param_Cell);
	g_hForwardSIShove = CreateGlobalForward("OnSpecialShoved", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_hForwardHunterDeadstop = CreateGlobalForward("OnHunterDeadstop", ET_Event, Param_Cell, Param_Cell);
	g_hForwardBoomerPop = CreateGlobalForward("OnBoomerPop", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Float);
	g_hForwardLevel = CreateGlobalForward("OnChargerLevel", ET_Event, Param_Cell, Param_Cell);
	g_hForwardLevelHurt = CreateGlobalForward("OnChargerLevelHurt", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_hForwardTongueCut = CreateGlobalForward("OnTongueCut", ET_Event, Param_Cell, Param_Cell);
	g_hForwardSmokerSelfClear = CreateGlobalForward("OnSmokerSelfClear", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_hForwardRockSkeeted = CreateGlobalForward("OnTankRockSkeeted", ET_Event, Param_Cell, Param_Cell);
	g_hForwardRockEaten = CreateGlobalForward("OnTankRockEaten", ET_Event, Param_Cell, Param_Cell);
	g_hForwardHunterDP = CreateGlobalForward("OnHunterHighPounce", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Float, Param_Cell, Param_Cell);
	g_hForwardJockeyDP = CreateGlobalForward("OnJockeyHighPounce", ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Cell);
	g_hForwardDeathCharge = CreateGlobalForward("OnDeathCharge", ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float, Param_Cell);
	g_hForwardClear = CreateGlobalForward("OnSpecialClear", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Float, Param_Cell);
	g_hForwardVomitLanded = CreateGlobalForward("OnBoomerVomitLanded", ET_Event, Param_Cell, Param_Cell);

	g_bLateLoad = bLate;
	RegPluginLibrary("skill_detect");
	return APLRes_Success;
}

public void OnPluginStart()
{
	Witch_OnPluginStart();
	CarAlarm_OnPluginStart();
	Bhop_OnPluginStart();

	// hooks
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("scavenge_round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("ability_use", Event_AbilityUse, EventHookMode_Post);
	HookEvent("lunge_pounce", Event_LungePounce, EventHookMode_Post);
	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
	HookEvent("player_jump", Event_PlayerJumped, EventHookMode_Post);

	HookEvent("player_now_it", Event_PlayerBoomed, EventHookMode_Post);
	HookEvent("boomer_exploded", Event_BoomerExploded, EventHookMode_Post);

	//HookEvent("infected_hurt", Event_InfectedHurt, EventHookMode_Post);
	HookEvent("tongue_grab", Event_TongueGrab, EventHookMode_Post);
	HookEvent("tongue_pull_stopped", Event_TonguePullStopped, EventHookMode_Post);
	HookEvent("choke_start", Event_ChokeStart, EventHookMode_Post);
	HookEvent("choke_stopped", Event_ChokeStop, EventHookMode_Post);
	HookEvent("jockey_ride", Event_JockeyRide, EventHookMode_Post);
	HookEvent("charger_carry_start", Event_ChargeCarryStart, EventHookMode_Post);
	HookEvent("charger_carry_end", Event_ChargeCarryEnd, EventHookMode_Post);
	HookEvent("charger_impact", Event_ChargeImpact, EventHookMode_Post);
	HookEvent("charger_pummel_start", Event_ChargePummelStart, EventHookMode_Post);

	HookEvent("player_incapacitated_start", Event_IncapStart, EventHookMode_Post);

	g_hCvarReport = CreateConVar("sm_skill_report_enable" , "0", "Whether to report in chat (see sm_skill_report_flags).", _, true, 0.0, true, 1.0);
	g_hCvarReportFlags = CreateConVar("sm_skill_report_flags", REP_DEFAULT, "What to report skeets in chat (bitflags: 1,2:skeets/hurt; 4,8:level/chip; 16,32:crown/draw; 64,128:cut/selfclear, ... ).", _, true, 0.0, false, 0.0);

	g_hCvarAllowMelee = CreateConVar("sm_skill_skeet_allowmelee", "1", "Whether to count/forward melee skeets.", _, true, 0.0, true, 1.0);
	g_hCvarAllowSniper = CreateConVar("sm_skill_skeet_allowsniper", "1", "Whether to count/forward sniper/magnum headshots as skeets.", _, true, 0.0, true, 1.0);
	g_hCvarAllowGLSkeet = CreateConVar("sm_skill_skeet_allowgl", "1", "Whether to count/forward direct GL hits as skeets.", _, true, 0.0, true, 1.0);
	g_hCvarSelfClearThresh = CreateConVar("sm_skill_selfclear_damage", "200", "How much damage a survivor must at least do to a smoker for him to count as self-clearing.", _, true, 0.0, false);
	g_hCvarHunterDPThresh = CreateConVar("sm_skill_hunterdp_height", "400", "Minimum height of hunter pounce for it to count as a DP.", _, true, 0.0, false);
	g_hCvarJockeyDPThresh = CreateConVar("sm_skill_jockeydp_height", "300", "How much height distance a jockey must make for his 'DP' to count as a reportable highpounce.", _, true, 0.0, false);
	g_hCvarHideFakeDamage = CreateConVar("sm_skill_hidefakedamage", "0", "If set, any damage done that exceeds the health of a victim is hidden in reports.", _, true, 0.0, true, 1.0);
	g_hCvarDeathChargeHeight = CreateConVar("sm_skill_deathcharge_height","400", "How much height distance a charger must take its victim for a deathcharge to be reported.", _, true, 0.0, false);
	g_hCvarInstaTime = CreateConVar("sm_skill_instaclear_time", "0.75", "A clear within this time (in seconds) counts as an insta-clear.", _, true, 0.0, false);

	// cvars: built in
	g_hCvarPounceInterrupt = FindConVar("z_pounce_damage_interrupt");
	HookConVarChange(g_hCvarPounceInterrupt, CvarChange_PounceInterrupt);
	g_iPounceInterrupt = GetConVarInt(g_hCvarPounceInterrupt);

	g_hCvarChargerHealth = FindConVar("z_charger_health");

	g_hCvarMaxPounceDistance = FindConVar("z_pounce_damage_range_max");
	g_hCvarMinPounceDistance = FindConVar("z_pounce_damage_range_min");
	g_hCvarMaxPounceDamage = FindConVar("z_hunter_max_pounce_bonus_damage");
	
	if (g_hCvarMaxPounceDistance == null) {
		g_hCvarMaxPounceDistance = CreateConVar("z_pounce_damage_range_max", "1000.0", "Not available on this server, added by l4d2_skill_detect.", _, true, 0.0, false, 0.0); 
	}
	
	if (g_hCvarMinPounceDistance == null) {
		g_hCvarMinPounceDistance = CreateConVar("z_pounce_damage_range_min",  "300.0", "Not available on this server, added by l4d2_skill_detect.", FCVAR_NONE, true, 0.0, false, 0.0);
	}
	
	if (g_hCvarMaxPounceDamage == null) {
		g_hCvarMaxPounceDamage = CreateConVar("z_hunter_max_pounce_bonus_damage",  "49", "Not available on this server, added by l4d2_skill_detect.", FCVAR_NONE, true, 0.0, false, 0.0);
	}

	// tries
	g_hTrieWeapons = CreateTrie();
	SetTrieValue(g_hTrieWeapons, "hunting_rifle", WPTYPE_SNIPER);
	SetTrieValue(g_hTrieWeapons, "sniper_military", WPTYPE_SNIPER);
	SetTrieValue(g_hTrieWeapons, "sniper_awp", WPTYPE_SNIPER);
	SetTrieValue(g_hTrieWeapons, "sniper_scout", WPTYPE_SNIPER);
	SetTrieValue(g_hTrieWeapons, "pistol_magnum", WPTYPE_MAGNUM);
	SetTrieValue(g_hTrieWeapons, "grenade_launcher_projectile", WPTYPE_GL);

	g_hTrieEntityCreated = CreateTrie();
	SetTrieValue(g_hTrieEntityCreated, "tank_rock",             OEC_TANKROCK);
	SetTrieValue(g_hTrieEntityCreated, "witch",                 OEC_WITCH);
	SetTrieValue(g_hTrieEntityCreated, "trigger_hurt",          OEC_TRIGGER);
	SetTrieValue(g_hTrieEntityCreated, "prop_car_alarm",        OEC_CARALARM);
	SetTrieValue(g_hTrieEntityCreated, "prop_car_glass",        OEC_CARGLASS);

	g_hRockTrie = CreateTrie();
}

public void CvarChange_PounceInterrupt(ConVar hConVar, const char[] oldValue, const char[] sNewValue)
{
	g_iPounceInterrupt = hConVar.IntValue;
}

public void OnClientPostAdminCheck(int iClient)
{
	Witch_OnClientPostAdminCheck(iClient);
}

public void Event_RoundStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	g_iRocksBeingThrownCount = 0;

	for (int i = 1; i <= MaxClients; i++) {
		for (int j = 1; j <= MaxClients; j++) {
			g_fVictimLastShove[i][j] = 0.0;
		}
	}
}

public Action Event_PlayerHurt(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int victim = GetClientOfUserId(hEvent.GetInt("userid"));
	int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
	int zClass;

	int damage = hEvent.GetInt("dmg_health");
	int damagetype = hEvent.GetInt("type");

	if (IS_VALID_INFECTED(victim)) {
		zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
		int health = hEvent.GetInt("health");
		int hitgroup = hEvent.GetInt("hitgroup");

		if (damage < 1) {
			return Plugin_Continue; 
		}

		switch (zClass) {
			case L4D2Infected_Hunter: {
				// if it's not a survivor doing the work, only get the remaining health
				if (!IS_VALID_SURVIVOR(attacker)) {
					g_iHunterLastHealth[victim] = health;
					return Plugin_Continue;
				}

				// if the damage done is greater than the health we know the hunter to have remaining, reduce the damage done
				if (g_iHunterLastHealth[victim] > 0 && damage > g_iHunterLastHealth[victim]) {
					damage = g_iHunterLastHealth[victim];
					g_iHunterOverkill[victim] = g_iHunterLastHealth[victim] - damage;
					g_iHunterLastHealth[victim] = 0;
				}

				/*
					handle old shotgun blast: too long ago? not the same blast
				*/
				if (g_iHunterShotDmg[victim][attacker] > 0 && (GetGameTime() - g_fHunterShotStart[victim][attacker]) > SHOTGUN_BLAST_TIME) {
					g_fHunterShotStart[victim][attacker] = 0.0;
				}

				/*
					m_isAttemptingToPounce is set to 0 here if the hunter is actually skeeted
					so the g_fHunterTracePouncing[victim] value indicates when the hunter was last seen pouncing in traceattack
					(should be DIRECTLY before this event for every shot).
				*/
				bool bIsAttemptingToPounce = (GetEntProp(victim, Prop_Send, "m_isAttemptingToPounce", 1) > 0);
				bool bIsPouncing = (bIsAttemptingToPounce || (g_fHunterTracePouncing[victim] != 0.0 && (GetGameTime() - g_fHunterTracePouncing[victim]) < 0.001));

				if (bIsPouncing) {
					if (damagetype & DMG_BUCKSHOT) {
						// first pellet hit?
						if (g_fHunterShotStart[victim][attacker] == 0.0) {
							// new shotgun blast
							g_fHunterShotStart[victim][attacker] = GetGameTime();
							g_fHunterLastShot[victim] = g_fHunterShotStart[victim][attacker];
						}
						
						g_iHunterShotDmg[victim][attacker] += damage;
						g_iHunterShotDmgTeam[victim] += damage;

						if (health == 0) {
							g_bHunterKilledPouncing[victim] = true;
						}
					} else if (damagetype & (DMG_BLAST | DMG_PLASMA) && health == 0) {
						// direct GL hit?
						/*
							direct hit is DMG_BLAST | DMG_PLASMA
							indirect hit is DMG_AIRBOAT
						*/

						char weaponB[32];
						int weaponTypeB;
						hEvent.GetString("weapon", weaponB, sizeof(weaponB));

						if (GetTrieValue(g_hTrieWeapons, weaponB, weaponTypeB) && weaponTypeB == WPTYPE_GL) {
							if (GetConVarBool(g_hCvarAllowGLSkeet)) {
								HandleSkeet(attacker, victim, false, false, true);
							}
						}
					} else if (damagetype & DMG_BULLET && health == 0 && hitgroup == HITGROUP_HEAD) {
						// headshot with bullet based weapon (only single shots) -- only snipers
						char weaponA[32];
						int weaponTypeA;
						hEvent.GetString("weapon", weaponA, sizeof(weaponA));

						if (GetTrieValue(g_hTrieWeapons, weaponA, weaponTypeA) 
							&& (weaponTypeA == WPTYPE_SNIPER || weaponTypeA == WPTYPE_MAGNUM)
						) {
							if (damage >= g_iPounceInterrupt) {
								g_iHunterShotDmgTeam[victim] = 0;
								
								if (GetConVarBool(g_hCvarAllowSniper)) {
									HandleSkeet(attacker, victim, false, true);
								}
								
								ResetHunter(victim);
							} else {
								// hurt skeet
								if (GetConVarBool(g_hCvarAllowSniper)) {
									HandleNonSkeet(attacker, victim, damage, (g_iHunterOverkill[victim] + g_iHunterShotDmgTeam[victim] > g_iPounceInterrupt), false, true);
								}
								
								ResetHunter(victim);
							}
						}

						// already handled hurt skeet above
						//g_bHunterKilledPouncing[victim] = true;
					} else if (damagetype & DMG_SLASH || damagetype & DMG_CLUB) {
						// melee skeet
						if (damage >= g_iPounceInterrupt) {
							g_iHunterShotDmgTeam[victim] = 0;
							if (GetConVarBool(g_hCvarAllowMelee)) {
								HandleSkeet(attacker, victim, true);
							}
							ResetHunter(victim);
							//g_bHunterKilledPouncing[victim] = true;
						} else if (health == 0) {
							// hurt skeet (always overkill)
							if (GetConVarBool(g_hCvarAllowMelee)) {
								HandleNonSkeet(attacker, victim, damage, true, true, false);
							}
							
							ResetHunter(victim);
						}
					}
				} else if (health == 0) {
					// make sure we don't mistake non-pouncing hunters as 'not skeeted'-warnable
					g_bHunterKilledPouncing[victim] = false;
				}

				// store last health seen for next damage event
				g_iHunterLastHealth[victim] = health;
			}
			case L4D2Infected_Charger: {
				if (IS_VALID_SURVIVOR(attacker)) {
					// check for levels
					if (health == 0 && (damagetype & DMG_CLUB || damagetype & DMG_SLASH)) {
						int iChargeHealth = GetConVarInt(g_hCvarChargerHealth);
						int abilityEnt = GetEntPropEnt(victim, Prop_Send, "m_customAbility");
						
						if (abilityEnt != -1 && IsValidEdict(abilityEnt) && GetEntProp(abilityEnt, Prop_Send, "m_isCharging", 1) > 0) {
							// fix fake damage?
							if (GetConVarBool(g_hCvarHideFakeDamage)) {
								damage = iChargeHealth - g_iChargerHealth[victim];
							}

							// charger was killed, was it a full level?
							if (damage > (iChargeHealth * 0.65)) {
								HandleLevel(attacker, victim);
							} else {
								HandleLevelHurt(attacker, victim, damage);
							}
						}
					}
				}

				// store health for next damage it takes
				if (health > 0) {
					g_iChargerHealth[victim] = health;
				}
			}
			case L4D2Infected_Smoker: {
				if (!IS_VALID_SURVIVOR(attacker)) {
					return Plugin_Continue;
				}

				g_iSmokerVictimDamage[victim] += damage;
			}
		}
	} else if (IS_VALID_INFECTED(attacker)) {
		zClass = GetEntProp(attacker, Prop_Send, "m_zombieClass");

		switch (zClass) {
			case L4D2Infected_Hunter: {
				// a hunter pounce landing is DMG_CRUSH
				if (damagetype & DMG_CRUSH) {
					g_iPounceDamage[attacker] = damage;
				}
			}
			case L4D2Infected_Tank: {
				char weapon[10];
				hEvent.GetString("weapon", weapon, sizeof(weapon));

				if (strcmp(weapon, "tank_rock") == 0) {
					// find rock entity through tank
					if (g_iTankRock[attacker]) {
						// remember that the rock wasn't shot
						char rock_key[10];
						FormatEx(rock_key, sizeof(rock_key), "%x", g_iTankRock[attacker]);
						
						int rock_array[3];
						rock_array[rckDamage] = -1;
						SetTrieArray(g_hRockTrie, rock_key, rock_array, sizeof(rock_array), true);
					}

					if (IS_VALID_SURVIVOR(victim)) {
						HandleRockEaten(attacker, victim);
					}
				}

				return Plugin_Continue;
			}
		}
	}

	// check for deathcharge flags
	if (IS_VALID_SURVIVOR(victim)) {
		// debug
		if (damagetype & DMG_DROWN || damagetype & DMG_FALL) {
			g_iVictimMapDmg[victim] += damage;
		}

		if (damagetype & DMG_DROWN && damage >= MIN_DC_TRIGGER_DMG) {
			g_iVictimFlags[victim] = g_iVictimFlags[victim] | VICFLG_HURTLOTS;
		} else if (damagetype & DMG_FALL && damage >= MIN_DC_FALL_DMG) {
			g_iVictimFlags[victim] = g_iVictimFlags[victim] | VICFLG_HURTLOTS;
		}
	}

	return Plugin_Continue;
}

public void Event_PlayerSpawn(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || GetClientTeam(iClient) != L4D2Team_Infected) {
		return;
	}

	int zClass = GetEntProp(iClient, Prop_Send, "m_zombieClass");

	g_fSpawnTime[iClient] = GetGameTime();
	g_fPinTime[iClient][0] = 0.0;
	g_fPinTime[iClient][1] = 0.0;

	switch (zClass) {
		case L4D2Infected_Boomer: {
			g_bBoomerHitSomebody[iClient] = false;
			g_iBoomerGotShoved[iClient] = 0;
		}
		case L4D2Infected_Smoker: {
			g_bSmokerClearCheck[iClient] = false;
			g_iSmokerVictim[iClient] = 0;
			g_iSmokerVictimDamage[iClient] = 0;
		}
		case L4D2Infected_Hunter: {
			SDKHook(iClient, SDKHook_TraceAttack, TraceAttack_Hunter);

			g_fPouncePosition[iClient][0] = 0.0;
			g_fPouncePosition[iClient][1] = 0.0;
			g_fPouncePosition[iClient][2] = 0.0;
		}
		case L4D2Infected_Jockey: {
			SDKHook(iClient, SDKHook_TraceAttack, TraceAttack_Jockey);

			g_fPouncePosition[iClient][0] = 0.0;
			g_fPouncePosition[iClient][1] = 0.0;
			g_fPouncePosition[iClient][2] = 0.0;
		}
		case L4D2Infected_Charger: {
			SDKHook(iClient, SDKHook_TraceAttack, TraceAttack_Charger);

			g_iChargerHealth[iClient] = GetConVarInt(g_hCvarChargerHealth);
		}
	}
}

// player about to get incapped
public Action Event_IncapStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	// test for deathcharges
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	
	//int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
	int attackent = hEvent.GetInt("attackerentid");
	int dmgtype = hEvent.GetInt("type");

	char classname[24];
	int classnameOEC;
	
	if (attackent > 0 && IsValidEdict(attackent)) {
		GetEdictClassname(attackent, classname, sizeof(classname));
		if (GetTrieValue(g_hTrieEntityCreated, classname, classnameOEC)) {
			g_iVictimFlags[client] = g_iVictimFlags[client] | VICFLG_TRIGGER;
		}
	}

	float flow = L4D2Direct_GetFlowDistance(client);

	//PrintDebug("Incap Pre on [%N]: attk: %i / %i (%s) - dmgtype: %i - flow: %.1f", client, attacker, attackent, classname, dmgtype, flow);

	// drown is damage type
	if (dmgtype & DMG_DROWN) {
		g_iVictimFlags[client] = g_iVictimFlags[client] | VICFLG_DROWN;
	}
	
	if (flow < WEIRD_FLOW_THRESH) {
		g_iVictimFlags[client] = g_iVictimFlags[client] | VICFLG_WEIRDFLOW;
	}
}

// trace attacks on hunters
public Action TraceAttack_Hunter(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	// track pinning
	g_iSpecialVictim[victim] = GetEntPropEnt(victim, Prop_Send, "m_pounceVictim");

	if (!IS_VALID_SURVIVOR(attacker) || !IsValidEdict(inflictor)) {
		return;
	}

	// track flight
	if (GetEntProp(victim, Prop_Send, "m_isAttemptingToPounce", 1)) {
		g_fHunterTracePouncing[victim] = GetGameTime();
	} else {
		g_fHunterTracePouncing[victim] = 0.0;
	}
}

public Action TraceAttack_Charger(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	// track pinning
	int victimA = GetEntPropEnt(victim, Prop_Send, "m_carryVictim");

	if (victimA != -1) {
		g_iSpecialVictim[victim] = victimA;
	} else {
		g_iSpecialVictim[victim] = GetEntPropEnt(victim, Prop_Send, "m_pummelVictim");
	}
}

public Action TraceAttack_Jockey(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	// track pinning
	g_iSpecialVictim[victim] = GetEntPropEnt(victim, Prop_Send, "m_jockeyVictim");
}

public Action Event_PlayerDeath(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int victim = GetClientOfUserId(hEvent.GetInt("userid"));
	int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));

	if (IS_VALID_INFECTED(victim)) {
		int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");

		switch (zClass) {
			case L4D2Infected_Hunter: {
				if (!IS_VALID_SURVIVOR(attacker)) {
					return Plugin_Continue; 
				}

				if (g_iHunterShotDmgTeam[victim] > 0 && g_bHunterKilledPouncing[victim]) {
					// skeet?
					if (g_iHunterShotDmgTeam[victim] > g_iHunterShotDmg[victim][attacker] &&
						g_iHunterShotDmgTeam[victim] >= g_iPounceInterrupt
					) {
						// team skeet
						HandleSkeet(-2, victim);
					} else if (g_iHunterShotDmg[victim][attacker] >= g_iPounceInterrupt) {
						// single player skeet
						HandleSkeet(attacker, victim);
					} else if (g_iHunterOverkill[victim] > 0) {
						// overkill? might've been a skeet, if it wasn't on a hurt hunter (only for shotguns)
						HandleNonSkeet(attacker, victim, g_iHunterShotDmgTeam[victim], (g_iHunterOverkill[victim] + g_iHunterShotDmgTeam[victim] > g_iPounceInterrupt));
					} else {
						// not a skeet at all
						HandleNonSkeet(attacker, victim, g_iHunterShotDmg[victim][attacker]);
					}
				} else {
					// check whether it was a clear
					if (g_iSpecialVictim[victim] > 0) {
						HandleClear(attacker, victim, g_iSpecialVictim[victim], L4D2Infected_Hunter, GetGameTime() - g_fPinTime[victim][0], -1.0);
					}
				}

				ResetHunter(victim);
			}
			case L4D2Infected_Smoker: {
				if (!IS_VALID_SURVIVOR(attacker)) { 
					return Plugin_Continue; 
				}

				if (g_bSmokerClearCheck[victim] &&
					g_iSmokerVictim[victim] == attacker &&
					g_iSmokerVictimDamage[victim] >= GetConVarInt(g_hCvarSelfClearThresh)
				) {
					HandleSmokerSelfClear(attacker, victim);
				} else {
					g_bSmokerClearCheck[victim] = false;
					g_iSmokerVictim[victim] = 0;
				}
			}
			case L4D2Infected_Jockey: {
				// check whether it was a clear
				if (g_iSpecialVictim[victim] > 0) {
					HandleClear(attacker, victim, g_iSpecialVictim[victim], L4D2Infected_Jockey, GetGameTime() - g_fPinTime[victim][0], -1.0);
				}
			}
			case L4D2Infected_Charger: {
				// is it someone carrying a survivor (that might be DC'd)?
				// switch charge victim to 'impact' check (reset checktime)
				if (IS_VALID_INGAME(g_iChargeVictim[victim])) {
					g_fChargeTime[ g_iChargeVictim[victim] ] = GetGameTime();
				}

				// check whether it was a clear
				if (g_iSpecialVictim[victim] > 0) {
					HandleClear(attacker, victim, g_iSpecialVictim[victim], L4D2Infected_Charger, (g_fPinTime[victim][1] > 0.0) ? (GetGameTime() - g_fPinTime[victim][1]) : -1.0, GetGameTime() - g_fPinTime[victim][0]);
				}
			}
		}
	} else if (IS_VALID_SURVIVOR(victim)) {
		// check for deathcharges
		//int atkent = hEvent.GetInt("attackerentid");
		int dmgtype = hEvent.GetInt("type");

		//PrintDebug("Died [%N]: attk: %i / %i - dmgtype: %i", victim, attacker, atkent, dmgtype);

		if (dmgtype & DMG_FALL) {
			g_iVictimFlags[victim] = g_iVictimFlags[victim] | VICFLG_FALL;
		} else if (IS_VALID_INFECTED(attacker) && attacker != g_iVictimCharger[victim]) {
			// if something other than the charger killed them, remember (not a DC)
			g_iVictimFlags[victim] = g_iVictimFlags[victim] | VICFLG_KILLEDBYOTHER;
		}
	}

	return Plugin_Continue;
}

public void Event_PlayerShoved(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int victim = GetClientOfUserId(hEvent.GetInt("userid"));
	int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));

	//PrintDebug("Shove from %i on %i", attacker, victim);

	if (!IS_VALID_SURVIVOR(attacker) || !IS_VALID_INFECTED(victim)) {
		return;
	}

	int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");

	//PrintDebug(" --> Shove from %N on %N (class: %i) -- (last shove time: %.2f / %.2f)", attacker, victim, zClass, g_fVictimLastShove[victim][attacker], GetGameTime() - g_fVictimLastShove[victim][attacker]);

	// track on boomers
	if (zClass == L4D2Infected_Boomer) {
		g_iBoomerGotShoved[victim]++;
	} else {
		// check for clears
		switch (zClass) {
			case L4D2Infected_Hunter: {
				if (GetEntPropEnt(victim, Prop_Send, "m_pounceVictim") > 0) {
					float fTime = GetGameTime() - g_fPinTime[victim][0];
					HandleClear(attacker, victim, GetEntPropEnt(victim, Prop_Send, "m_pounceVictim"), L4D2Infected_Hunter, fTime, -1.0, true);
				}
			}
			case L4D2Infected_Jockey: {
				if (GetEntPropEnt(victim, Prop_Send, "m_jockeyVictim") > 0) {
					float fTime = GetGameTime() - g_fPinTime[victim][0];
					HandleClear(attacker, victim, GetEntPropEnt(victim, Prop_Send, "m_jockeyVictim"), L4D2Infected_Jockey, fTime, -1.0, true);
				}
			}
		}
	}

	if (g_fVictimLastShove[victim][attacker] == 0.0 || (GetGameTime() - g_fVictimLastShove[victim][attacker]) >= SHOVE_TIME) {
		if (GetEntProp(victim, Prop_Send, "m_isAttemptingToPounce", 1)) {
			HandleDeadstop(attacker, victim);
		}

		HandleShove(attacker, victim, zClass);

		g_fVictimLastShove[victim][attacker] = GetGameTime();
	}

	// check for shove on smoker by pull victim
	if (g_iSmokerVictim[victim] == attacker) {
		g_bSmokerShoved[victim] = true;
	}

	//PrintDebug("shove by %i on %i", attacker, victim);
}

public void Event_LungePounce(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	int victim = GetClientOfUserId(hEvent.GetInt("victim"));

	g_fPinTime[client][0] = GetGameTime();

	// clear hunter-hit stats (not skeeted)
	ResetHunter(client);

	// check if it was a DP
	// ignore if no real pounce start pos
	if (g_fPouncePosition[client][0] == 0.0
		&& g_fPouncePosition[client][1] == 0.0
		&& g_fPouncePosition[client][2] == 0.0
	) {
		return;
	}

	float endPos[3];
	GetClientAbsOrigin(client, endPos);
	float fHeight = g_fPouncePosition[client][2] - endPos[2];

	// from pounceannounce:
	// distance supplied isn't the actual 2d vector distance needed for damage calculation. See more about it at
	// http://forums.alliedmods.net/showthread.php?t=93207

	float fMin = GetConVarFloat(g_hCvarMinPounceDistance);
	float fMax = GetConVarFloat(g_hCvarMaxPounceDistance);
	float fMaxDmg = GetConVarFloat(g_hCvarMaxPounceDamage);

	// calculate 2d distance between previous position and pounce position
	int distance = RoundToNearest(GetVectorDistance(g_fPouncePosition[client], endPos));

	// get damage using hunter damage formula
	// check if this is accurate, seems to differ from actual damage done!
	float fDamage = (((float(distance) - fMin) / (fMax - fMin)) * fMaxDmg) + 1.0;

	// apply bounds
	if (fDamage < 0.0) {
		fDamage = 0.0;
	} else if (fDamage > fMaxDmg + 1.0) {
		fDamage = fMaxDmg + 1.0;
	}

	Handle pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackCell(pack, victim);
	WritePackFloat(pack, fDamage);
	WritePackFloat(pack, fHeight);
	CreateTimer(0.05, Timer_HunterDP, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public Action Timer_HunterDP(Handle hTimer, any pack)
{
	ResetPack(pack);
	
	int client = ReadPackCell(pack);
	int victim = ReadPackCell(pack);
	float fDamage = ReadPackFloat(pack);
	float fHeight = ReadPackFloat(pack);

	HandleHunterDP(client, victim, g_iPounceDamage[client], fDamage, fHeight);
	return Plugin_Stop;
}

public void Event_PlayerJumped(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || GetClientTeam(iClient) != L4D2Team_Infected) {
		return;
	}

	int zClass = GetEntProp(iClient, Prop_Send, "m_zombieClass");
	if (zClass != L4D2Infected_Jockey) {
		return;
	}

	// where did jockey jump from?
	GetClientAbsOrigin(iClient, g_fPouncePosition[iClient]);
}

public void Event_JockeyRide(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	int victim = GetClientOfUserId(hEvent.GetInt("victim"));

	if (!IS_VALID_INFECTED(client) || !IS_VALID_SURVIVOR(victim)) { 
		return; 
	}

	g_fPinTime[client][0] = GetGameTime();

	// minimum distance travelled?
	// ignore if no real pounce start pos
	if (g_fPouncePosition[client][0] == 0.0 && g_fPouncePosition[client][1] == 0.0 && g_fPouncePosition[client][2] == 0.0) { 
		return;
	}

	float endPos[3];
	GetClientAbsOrigin(client, endPos);
	float fHeight = g_fPouncePosition[client][2] - endPos[2];

	//PrintToChatAll("jockey height: %.3f", fHeight);

	// (high) pounce
	HandleJockeyDP(client, victim, fHeight);
}

public void Event_AbilityUse(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient < 1 || GetClientTeam(iClient) != L4D2Team_Infected) {
		return;
	}

	char sAbilityName[64];
	hEvent.GetString("ability", sAbilityName, sizeof(sAbilityName));
	if (strcmp(sAbilityName, "ability_lunge") == 0) {
		// hunter started a pounce
		ResetHunter(iClient);
		GetClientAbsOrigin(iClient, g_fPouncePosition[iClient]);
	} else if(strcmp(sAbilityName, "ability_throw") == 0) {
		// tank throws rock
		g_iRocksBeingThrown[g_iRocksBeingThrownCount] = iClient;

		// safeguard
		if (g_iRocksBeingThrownCount < 9) {
			g_iRocksBeingThrownCount++; 
		}
	}
}

// charger carrying
public void Event_ChargeCarryStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!IS_VALID_INFECTED(client)) { 
		return; 
	}
	
	int victim = GetClientOfUserId(hEvent.GetInt("victim"));
	PrintDebug("Charge carry start: %i - %i -- time: %.2f", client, victim, GetGameTime());

	g_fChargeTime[client] = GetGameTime();
	g_fPinTime[client][0] = g_fChargeTime[client];
	g_fPinTime[client][1] = 0.0;

	if (!IS_VALID_SURVIVOR(victim)) { 
		return; 
	}

	g_iChargeVictim[client] = victim;           // store who we're carrying (as long as this is set, it's not considered an impact charge flight)
	g_iVictimCharger[victim] = client;          // store who's charging whom
	g_iVictimFlags[victim] = VICFLG_CARRIED;    // reset flags for checking later - we know only this now
	g_fChargeTime[victim] = g_fChargeTime[client];
	g_iVictimMapDmg[victim] = 0;

	GetClientAbsOrigin(victim, g_fChargeVictimPos[victim]);

	//CreateTimer(CHARGE_CHECK_TIME, Timer_ChargeCheck, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(CHARGE_CHECK_TIME, Timer_ChargeCheck, victim, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_ChargeImpact(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	int victim = GetClientOfUserId(hEvent.GetInt("victim"));
	if (!IS_VALID_INFECTED(client) || !IS_VALID_SURVIVOR(victim)) { 
		return; 
	}

	// remember how many people the charger bumped into, and who, and where they were
	GetClientAbsOrigin(victim, g_fChargeVictimPos[victim]);

	g_iVictimCharger[victim] = client;      // store who we've bumped up
	g_iVictimFlags[victim] = 0;             // reset flags for checking later
	g_fChargeTime[victim] = GetGameTime();  // store time per victim, for impacts
	g_iVictimMapDmg[victim] = 0;

	CreateTimer(CHARGE_CHECK_TIME, Timer_ChargeCheck, victim, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_ChargePummelStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));

	if (!IS_VALID_INFECTED(client)) {
		return; 
	}

	g_fPinTime[client][1] = GetGameTime();
}

public void Event_ChargeCarryEnd(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	if (client < 1 || client > MaxClients) { 
		return; 
	}

	g_fPinTime[client][1] = GetGameTime();

	// delay so we can check whether charger died 'mid carry'
	CreateTimer(0.1, Timer_ChargeCarryEnd, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ChargeCarryEnd(Handle hTimer, any client)
{
	// set charge time to 0 to avoid deathcharge timer continuing
	g_iChargeVictim[client] = 0;        // unset this so the repeated timer knows to stop for an ongroundcheck
}

public Action Timer_ChargeCheck(Handle hTimer, any client)
{
	// if something went wrong with the survivor or it was too long ago, forget about it
	if (!IS_VALID_SURVIVOR(client) || !g_iVictimCharger[client] 
		|| g_fChargeTime[client] == 0.0 || (GetGameTime() - g_fChargeTime[client]) > MAX_CHARGE_TIME
	) {
		return Plugin_Stop;
	}

	// we're done checking if either the victim reached the ground, or died
	if (!IsPlayerAlive(client)) {
		// player died (this was .. probably.. a death charge)
		g_iVictimFlags[client] = g_iVictimFlags[client] | VICFLG_AIRDEATH;

		// check conditions now
		CreateTimer(0.0, Timer_DeathChargeCheck, client, TIMER_FLAG_NO_MAPCHANGE);

		return Plugin_Stop;
	} else if (GetEntityFlags(client) & FL_ONGROUND && g_iChargeVictim[ g_iVictimCharger[client] ] != client) {
		// survivor reached the ground and didn't die (yet)
		// the client-check condition checks whether the survivor is still being carried by the charger
		//      (in which case it doesn't matter that they're on the ground)

		// check conditions with small delay (to see if they still die soon)
		CreateTimer(CHARGE_END_CHECK, Timer_DeathChargeCheck, client, TIMER_FLAG_NO_MAPCHANGE);

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Timer_DeathChargeCheck(Handle hTimer, any client)
{
	if (!IS_VALID_INGAME(client)) {
		return Plugin_Stop;
	}

	// check conditions.. if flags match up, it's a DC
	PrintDebug("Checking charge victim: %i - %i - flags: %i (alive? %i)", g_iVictimCharger[client], client, g_iVictimFlags[client], IsPlayerAlive(client));

	int flags = g_iVictimFlags[client];

	if (!IsPlayerAlive(client)) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		float fHeight = g_fChargeVictimPos[client][2] - pos[2];

		/*
			it's a deathcharge when:
				the survivor is dead AND
					they drowned/fell AND took enough damage or died in mid-air
					AND not killed by someone else
					OR is in an unreachable spot AND dropped at least X height
					OR took plenty of map damage

			old.. need?
				fHeight > GetConVarFloat(g_hCvarDeathChargeHeight)
		*/
		if (((flags & VICFLG_DROWN || flags & VICFLG_FALL) &&
			(flags & VICFLG_HURTLOTS || flags & VICFLG_AIRDEATH) ||
			(flags & VICFLG_WEIRDFLOW && fHeight >= MIN_FLOWDROPHEIGHT) ||
			g_iVictimMapDmg[client] >= MIN_DC_TRIGGER_DMG)
			&& !(flags & VICFLG_KILLEDBYOTHER)
		) {
			HandleDeathCharge(g_iVictimCharger[client], client, fHeight, GetVectorDistance(g_fChargeVictimPos[client], pos, false), view_as<bool>(flags & VICFLG_CARRIED));
		}
	}
	else if ((flags & VICFLG_WEIRDFLOW || g_iVictimMapDmg[client] >= MIN_DC_RECHECK_DMG) && !(flags & VICFLG_WEIRDFLOWDONE)) {
		// could be incapped and dying more slowly
		// flag only gets set on preincap, so don't need to check for incap
		g_iVictimFlags[client] = g_iVictimFlags[client] | VICFLG_WEIRDFLOWDONE;

		CreateTimer(CHARGE_END_RECHECK, Timer_DeathChargeCheck, client, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Stop;
}

void ResetHunter(int client)
{
	g_iHunterShotDmgTeam[client] = 0;

	for (int i = 1; i <= MaxClients; i++) {
		g_iHunterShotDmg[client][i] = 0;
		g_fHunterShotStart[client][i] = 0.0;
	}
	
	g_iHunterOverkill[client] = 0;
}

// entity creation
public void OnEntityCreated(int iEntity, const char[] sClassName)
{
	CarAlarm_OnEntityCreated(iEntity, sClassName);

	if (strcmp("tank_rock", sClassName) == 0) {
		char rock_key[10];
		FormatEx(rock_key, sizeof(rock_key), "%x", iEntity);
		int rock_array[3];

		// store which tank is throwing what rock
		int tank = ShiftTankThrower();

		if (IS_VALID_INGAME(tank)) {
			g_iTankRock[tank] = iEntity;
			rock_array[rckTank] = tank;
		}

		SetTrieArray(g_hRockTrie, rock_key, rock_array, sizeof(rock_array), true);

		SDKHook(iEntity, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost_Rock);
		SDKHook(iEntity, SDKHook_Touch, OnTouch_Rock);
	}
}

// entity destruction
public void OnEntityDestroyed(int iEntity)
{
	Witch_OnEntityDestroyed(iEntity);
}

public Action Timer_CheckRockSkeet(Handle hTimer, any rock)
{
	int rock_array[3];
	char rock_key[10];
	FormatEx(rock_key, sizeof(rock_key), "%x", rock);
	if (!GetTrieArray(g_hRockTrie, rock_key, rock_array, sizeof(rock_array))) { 
		return Plugin_Continue; 
	}

	RemoveFromTrie(g_hRockTrie, rock_key);

	// if rock didn't hit anyone / didn't touch anything, it was shot
	if (rock_array[rckDamage] > 0) {
		HandleRockSkeeted(rock_array[rckSkeeter], rock_array[rckTank]);
	}

	return Plugin_Continue;
}

// boomer got somebody
public void Event_PlayerBoomed(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
	bool byBoom = hEvent.GetBool("by_boomer");

	if (byBoom && IS_VALID_INFECTED(attacker)) {
		g_bBoomerHitSomebody[attacker] = true;

		// check if it was vomit spray
		bool byExplosion = hEvent.GetBool("exploded");
		if (!byExplosion) {
			// count amount of booms
			if (!g_iBoomerVomitHits[attacker]) {
				// check for boom count later
				CreateTimer(VOMIT_DURATION_TIME, Timer_BoomVomitCheck, attacker, TIMER_FLAG_NO_MAPCHANGE);
			}
			
			g_iBoomerVomitHits[attacker]++;
		}
	}
}

// check how many booms landed
public Action Timer_BoomVomitCheck(Handle hTimer, any client)
{
	HandleVomitLanded(client, g_iBoomerVomitHits[client]);
	g_iBoomerVomitHits[client] = 0;
}

// boomers that didn't bile anyone
public void Event_BoomerExploded(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	bool biled = hEvent.GetBool("splashedbile");
	
	if (!biled && !g_bBoomerHitSomebody[client]) {
		int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
		
		if (IS_VALID_SURVIVOR(attacker)) {
			HandlePop(attacker, client, g_iBoomerGotShoved[client], GetGameTime() - g_fSpawnTime[client]);
		}
	}
}

// tank rock
// Credit to 'Marttt'
// Original plugin -> https://forums.alliedmods.net/showthread.php?p=2648989
public void OnTakeDamageAlivePost_Rock(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if (!IS_VALID_SURVIVOR(attacker)) {
		return;
	}
	
	char rock_key[10];
	int rock_array[3];
	
	FormatEx(rock_key, sizeof(rock_key), "%x", victim);
	GetTrieArray(g_hRockTrie, rock_key, rock_array, sizeof(rock_array));

	/*
		can't really use this for precise detection, though it does
		report the last shot -- the damage report is without distance falloff

		NOTE: Was using TraceAttack hook.
	*/
	rock_array[rckDamage] += RoundToFloor(damage);
	rock_array[rckSkeeter] = attacker;
	SetTrieArray(g_hRockTrie, rock_key, rock_array, sizeof(rock_array), true);

	if (GetEntProp(victim, Prop_Data, "m_iHealth") > 0) {
		return;
	}

	// tank rock
	CreateTimer(ROCK_CHECK_TIME, Timer_CheckRockSkeet, victim, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnTouch_Rock(int entity)
{
	// remember that the rock wasn't shot
	char rock_key[10];
	FormatEx(rock_key, sizeof(rock_key), "%x", entity);
	
	int rock_array[3];
	rock_array[rckDamage] = -1;
	SetTrieArray(g_hRockTrie, rock_key, rock_array, sizeof(rock_array), true);

	SDKUnhook(entity, SDKHook_Touch, OnTouch_Rock);
}

// smoker tongue cutting & self clears
public void Event_TonguePullStopped(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int attacker = GetClientOfUserId(hEvent.GetInt("userid"));
	int victim = GetClientOfUserId(hEvent.GetInt("victim"));
	int smoker = GetClientOfUserId(hEvent.GetInt("smoker"));
	int reason = hEvent.GetInt("release_type");

	if (!IS_VALID_SURVIVOR(attacker) || !IS_VALID_INFECTED(smoker)) { 
		return; 
	}

	// clear check -  if the smoker itself was not shoved, handle the clear
	HandleClear(attacker, smoker, victim, \
			L4D2Infected_Smoker, (g_fPinTime[smoker][1] > 0.0) ? (GetGameTime() - g_fPinTime[smoker][1]) : -1.0, \
			GetGameTime() - g_fPinTime[smoker][0], view_as<bool>(reason != CUT_SLASH && reason != CUT_KILL)
	);

	if (attacker != victim) { 
		return; 
	}

	if (reason == CUT_KILL) {
		g_bSmokerClearCheck[smoker] = true;
	} else if (g_bSmokerShoved[smoker]) {
		HandleSmokerSelfClear(attacker, smoker, true);
	} else if (reason == CUT_SLASH) { // note: can't trust this to actually BE a slash..
		// check weapon
		char weapon[32];
		GetClientWeapon(attacker, weapon, sizeof(weapon));

		// this doesn't count the chainsaw, but that's no-skill anyway
		if (strcmp(weapon, "weapon_melee", false) == 0) {
			HandleTongueCut(attacker, smoker);
		}
	}
}

public Action Event_TongueGrab(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int attacker = GetClientOfUserId(hEvent.GetInt("userid"));
	int victim = GetClientOfUserId(hEvent.GetInt("victim"));

	if (IS_VALID_INFECTED(attacker) && IS_VALID_SURVIVOR(victim)) {
		// new pull, clean damage
		g_bSmokerClearCheck[attacker] = false;
		g_bSmokerShoved[attacker] = false;
		g_iSmokerVictim[attacker] = victim;
		g_iSmokerVictimDamage[attacker] = 0;
		g_fPinTime[attacker][0] = GetGameTime();
		g_fPinTime[attacker][1] = 0.0;
	}
}

public Action Event_ChokeStart(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int attacker = GetClientOfUserId(hEvent.GetInt("userid"));

	if (g_fPinTime[attacker][0] == 0.0) {
		g_fPinTime[attacker][0] = GetGameTime(); 
	}
	
	g_fPinTime[attacker][1] = GetGameTime();
}

public Action Event_ChokeStop(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int attacker = GetClientOfUserId(hEvent.GetInt("userid"));
	int victim = GetClientOfUserId(hEvent.GetInt("victim"));
	int smoker = GetClientOfUserId(hEvent.GetInt("smoker"));
	int reason = hEvent.GetInt("release_type");

	if (!IS_VALID_SURVIVOR(attacker) || !IS_VALID_INFECTED(smoker)) {
		return;
	}

	// if the smoker itself was not shoved, handle the clear
	HandleClear(attacker, smoker, victim, \
			L4D2Infected_Smoker, (g_fPinTime[smoker][1] > 0.0) ? (GetGameTime() - g_fPinTime[smoker][1]) : -1.0, \
			GetGameTime() - g_fPinTime[smoker][0], view_as<bool>(reason != CUT_SLASH && reason != CUT_KILL) \
	);
}

/*
    Reporting and forwards
    ----------------------
*/
// boomer pop
void HandlePop(int attacker, int victim, int shoveCount, float timeAlive)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardBoomerPop);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(shoveCount);
	Call_PushFloat(timeAlive);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_POP) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			PrintToChatAll("\x04%N\x01 popped \x05%N\x01.", attacker, victim);
		} else if (IS_VALID_INGAME(attacker)) {
			PrintToChatAll("\x04%N\x01 popped a boomer.", attacker);
		}
	}
}

// charger level
void HandleLevel(int attacker, int victim)
{
	Action aResult = Plugin_Continue;
	// call forward
	Call_StartForward(g_hForwardLevel);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_LEVEL) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			CPrintToChatAll("{green}★★★ {olive}%N {blue}fully {default}leveled {olive}%N", attacker, victim);
		} else if (IS_VALID_INGAME(attacker)) {
			CPrintToChatAll("{green}★★★ {olive}%N {blue}fully {default}leveled {olive}a charger", attacker);
		}
	}
}

// charger level hurt
void HandleLevelHurt(int attacker, int victim, int damage)
{
	Action aResult = Plugin_Continue;
	// call forward
	Call_StartForward(g_hForwardLevelHurt);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(damage);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_HURTLEVEL) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			CPrintToChatAll("{green}★ {olive}%N {blue}chip-leveled {olive}%N {default}({blue}%i dmg{default})", attacker, victim, damage);
		} else if (IS_VALID_INGAME(attacker)) {
			CPrintToChatAll("{green}★ {olive}%N {blue}chip-leveled {default}a charger ({blue}%i dmg{default})", attacker, damage);
		}
	}
}

// deadstops
void HandleDeadstop(int attacker, int victim)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardHunterDeadstop);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_DEADSTOP) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			CPrintToChatAll("{green}★ {olive}%N {blue}deadstopped {olive}%N", attacker, victim);
		} else if (IS_VALID_INGAME(attacker)) {
			CPrintToChatAll("{green}★ {olive}%N {blue}deadstopped {olive}a hunter", attacker);
		}
	}
}

void HandleShove(int attacker, int victim, int zombieClass)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardSIShove);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(zombieClass);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_SHOVE) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			PrintToChatAll("\x04%N\x01 shoved \x05%N\x01.", attacker, victim);
		} else if (IS_VALID_INGAME(attacker)) {
			PrintToChatAll("\x04%N\x01 shoved an SI.", attacker);
		}
	}
}

// real skeet
void HandleSkeet(int attacker, int victim, bool bMelee = false, bool bSniper = false, bool bGL = false)
{
	Action aResult = Plugin_Continue;
	// call forward
	if (bSniper) {
		Call_StartForward(g_hForwardSkeetSniper);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_Finish(aResult);
	} else if (bGL) {
		Call_StartForward(g_hForwardSkeetGL);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_Finish(aResult);
	} else if (bMelee) {
		Call_StartForward(g_hForwardSkeetMelee);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_Finish(aResult);
	} else {
		Call_StartForward(g_hForwardSkeet);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_Finish(aResult);
	}
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_SKEET) {
		if (attacker == -2) {
			// team skeet sets to -2
			if (IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
				PrintToChatAll("\x05%N\x01 was team-skeeted.", victim);
			} else {
				PrintToChatAll("\x01A hunter was team-skeeted.");
			}
		} else if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			PrintToChatAll("\x04%N\x01 %sskeeted \x05%N\x01.", \
						attacker, (bMelee) ? "melee-": ((bSniper) ? "headshot-" : ((bGL) ? "grenade-" : "")), victim);
		} else if (IS_VALID_INGAME(attacker)) {
			PrintToChatAll("\x04%N\x01 %sskeeted a hunter.", \
						attacker, (bMelee) ? "melee-": ((bSniper) ? "headshot-" : ((bGL) ? "grenade-" : "")));
		}
	}
}

// hurt skeet / non-skeet
//  NOTE: bSniper not set yet, do this
void HandleNonSkeet(int attacker, int victim, int damage, bool bOverKill = false, bool bMelee = false, bool bSniper = false)
{
	Action aResult = Plugin_Continue;
	// call forward
	if (bSniper) {
		Call_StartForward(g_hForwardSkeetSniperHurt);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_PushCell(damage);
		Call_PushCell(bOverKill);
		Call_Finish(aResult);
	} else if (bMelee) {
		Call_StartForward(g_hForwardSkeetMeleeHurt);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_PushCell(damage);
		Call_PushCell(bOverKill);
		Call_Finish(aResult);
	} else {
		Call_StartForward(g_hForwardSkeetHurt);
		Call_PushCell(attacker);
		Call_PushCell(victim);
		Call_PushCell(damage);
		Call_PushCell(bOverKill);
		Call_Finish(aResult);
	}
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_HURTSKEET) {
		if (IS_VALID_INGAME(victim)) {
			PrintToChatAll("\x05%N\x01 was \x04not\x01 skeeted (\x03%i\x01 damage).%s", \
								victim, damage, (bOverKill) ? "(Would've skeeted if hunter were unchipped!)" : "");
		} else {
			PrintToChatAll("\x01Hunter was \x04not\x01 skeeted (\x03%i\x01 damage).%s", \
								damage, (bOverKill) ? "(Would've skeeted if hunter were unchipped!)" : "");
		}
	}
}

// smoker clears
void HandleTongueCut(int attacker, int victim)
{
	Action aResult = Plugin_Continue;
	// call forward
	Call_StartForward(g_hForwardTongueCut);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_TONGUECUT) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			CPrintToChatAll("{green}★★★ {olive}%N {blue}cut {olive}%N{default}'s tongue", attacker, victim);
		} else if (IS_VALID_INGAME(attacker)) {
			CPrintToChatAll("{green}★★ {olive}%N {blue}cut {default}smoker tongue", attacker);
		}
	}
}

void HandleSmokerSelfClear(int attacker, int victim, bool withShove = false)
{
	Action aResult = Plugin_Continue;
	
	// call forward
	Call_StartForward(g_hForwardSmokerSelfClear);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(withShove);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_SELFCLEAR 
		&& (!withShove || GetConVarInt(g_hCvarReport) & REP_SELFCLEARSHOVE)
	) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			CPrintToChatAll("{green}★★ {olive}%N {blue}self-cleared {default}from {olive}%N{default}'s tongue{blue}%s", \
									attacker, victim, (withShove) ? " by shoving" : "");
		} else if (IS_VALID_INGAME(attacker)) {
			CPrintToChatAll("{green}★★ {olive}%N {blue}self-cleared {default}from a smoker tongue{blue}%s", \
									attacker, (withShove) ? " by shoving" : "");
		}
	}
}

// rocks
void HandleRockEaten(int attacker, int victim)
{
	Action aResult = Plugin_Continue;
	
	Call_StartForward(g_hForwardRockEaten);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish(aResult);
	
	/*if (aResult == Plugin_Handled) {
		return;
	}*/
	
	// report ?!
}

void HandleRockSkeeted(int attacker, int victim)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardRockSkeeted);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_ROCKSKEET) {
		/*
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
			PrintToChatAll("\x04%N\x01 skeeted \x05%N\x01's rock.", attacker, victim);
		} else if (IS_VALID_INGAME(attacker)) {
		}*/
		
		CPrintToChatAll("{green}★ {olive}%N {blue}skeeted {default}a tank rock", attacker);
	}
}

// highpounces
void HandleHunterDP(int attacker, int victim, int actualDamage, float calculatedDamage, float height, bool playerIncapped = false)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardHunterDP);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(actualDamage);
	Call_PushFloat(calculatedDamage);
	Call_PushFloat(height);
	Call_PushCell((height >= GetConVarFloat(g_hCvarHunterDPThresh)) ? 1 : 0);
	Call_PushCell((playerIncapped) ? 1 : 0);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_HUNTERDP 
		&& height >= GetConVarFloat(g_hCvarHunterDPThresh) && !playerIncapped
	) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(attacker)) {
			CPrintToChatAll("{green}★★ {olive}%N {red}high-pounced {olive}%N {default}({red}%i {default}dmg, height: {red}%i{default})", \
								attacker,  victim, RoundFloat(calculatedDamage), RoundFloat(height));
		} else if (IS_VALID_INGAME(victim)) {
			CPrintToChatAll("{green}★★ {olive}A hunter {red}high-pounced {olive}%N {default}({red}%i {default}dmg, height: {red}%i{default})", \
								victim, RoundFloat(calculatedDamage), RoundFloat(height));
		}
	}
}

void HandleJockeyDP(int attacker, int victim, float height)
{
	Action aResult = Plugin_Continue;
	
	Call_StartForward(g_hForwardJockeyDP);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushFloat(height);
	Call_PushCell((height >= GetConVarFloat(g_hCvarJockeyDPThresh)) ? 1 : 0);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_JOCKEYDP 
		&& height >= GetConVarFloat(g_hCvarJockeyDPThresh)
	) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(attacker)) {
			CPrintToChatAll("{green}★★★ {olive}%N {red}high-pounced {olive}%N {default}({red}height{default}: {red}%i{default})", \
								attacker, victim, RoundFloat(height));
		} else if (IS_VALID_INGAME(victim)) {
			CPrintToChatAll("{green}★★★ {olive}A jockey {red}high-pounced {olive}%N {default}({red}height{default}: {red}%i{default})", \
								victim, RoundFloat(height));
		}
	}
}

// deathcharges
void HandleDeathCharge(int attacker, int victim, float height, float distance, bool bCarried = true)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardDeathCharge);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushFloat(height);
	Call_PushFloat(distance);
	Call_PushCell((bCarried) ? 1 : 0);
	Call_Finish(aResult);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	// report?
	if (GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_DEATHCHARGE
		&& height >= GetConVarFloat(g_hCvarDeathChargeHeight)
	) {
		if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(attacker)) {
			CPrintToChatAll("{green}★★★★ {olive}%N {red}death-charged {olive}%N{default} %s({red}height{default}: {red}%i{default})", \
								attacker, victim, (bCarried) ? "" : "by bowling ", RoundFloat(height));
		} else if (IS_VALID_INGAME(victim)) {
			CPrintToChatAll("{green}★★★★ {olive}A charger {red}death-charged {olive}%N{default} %s({red}height{default}: {red}%i{default})",
								victim, (bCarried) ? "" : "by bowling ", RoundFloat(height) );
		}
	}
}

// SI clears    (cleartimeA = pummel/pounce/ride/choke, cleartimeB = tongue drag, charger carry)
void HandleClear(int attacker, int victim, int pinVictim, int zombieClass, float clearTimeA, float clearTimeB, bool bWithShove = false)
{
	// sanity check:
	if (clearTimeA < 0 && clearTimeA != -1.0) { 
		clearTimeA = 0.0; 
	}
	
	if (clearTimeB < 0 && clearTimeB != -1.0) { 
		clearTimeB = 0.0; 
	}
	
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardClear);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(pinVictim);
	Call_PushCell(zombieClass);
	Call_PushFloat(clearTimeA);
	Call_PushFloat(clearTimeB);
	Call_PushCell((bWithShove) ? 1 : 0);
	Call_Finish(aResult);
	
	PrintDebug("Clear: %i freed %i from %i: time: %.2f / %.2f -- class: %s (with shove? %i)", \
						attacker, pinVictim, victim, clearTimeA, clearTimeB, g_csSIClassName[zombieClass], bWithShove);
	
	if (aResult == Plugin_Handled) {
		return;
	}
	
	if (attacker != pinVictim && 
		GetConVarBool(g_hCvarReport) && GetConVarInt(g_hCvarReportFlags) & REP_INSTACLEAR
	) {
		float fMinTime = GetConVarFloat(g_hCvarInstaTime);
		float fClearTime = clearTimeA;
	
		if (zombieClass == L4D2Infected_Charger || zombieClass == L4D2Infected_Smoker) {
			fClearTime = clearTimeB; 
		}

		if (fClearTime != -1.0 && fClearTime <= fMinTime) {
			if (IS_VALID_INGAME(attacker) && IS_VALID_INGAME(victim) && !IsFakeClient(victim)) {
				if (IS_VALID_INGAME(pinVictim)) {
					CPrintToChatAll("{green}★ {olive}%N {blue}insta-cleared {olive}%N {default}from {olive}%N{default}'s %s ({blue}%.2f {default}seconds)", \
											attacker, pinVictim, victim, g_csSIClassName[zombieClass],fClearTime
					);
				} else {
					CPrintToChatAll("{green}★ {olive}%N {blue}insta-cleared {olive}a teammate {default}from {olive}%N{default}'s %s ({blue}%.2f {default}seconds)", \
											attacker, victim, g_csSIClassName[zombieClass], fClearTime);
				}
			} else if (IS_VALID_INGAME(attacker)) {
				if (IS_VALID_INGAME(pinVictim)) {
					CPrintToChatAll("{green}★ {olive}%N {blue}insta-cleared {olive}%N {default}from a %s ({blue}%.2f {default}seconds)", \
											attacker, pinVictim, g_csSIClassName[zombieClass], fClearTime);
				} else {
					CPrintToChatAll("{green}★ {olive}%N {blue}insta-cleared {olive}a teammate {default}from a %s ({blue}%.2f {default}seconds)", \
											attacker, g_csSIClassName[zombieClass], fClearTime);
				}
			}
		}
	}
}

// booms
void HandleVomitLanded(int attacker, int boomCount)
{
	Action aResult = Plugin_Continue;
	Call_StartForward(g_hForwardVomitLanded);
	Call_PushCell(attacker);
	Call_PushCell(boomCount);
	Call_Finish(aResult);
	
	/*if (aResult == Plugin_Handled) {
		return;
	}*/
	// report ?!
}

int ShiftTankThrower()
{
	int tank = -1;

	if (!g_iRocksBeingThrownCount) {
		return -1; 
	}

	tank = g_iRocksBeingThrown[0];

	// shift the tank array downwards, if there are more than 1 throwers
	if (g_iRocksBeingThrownCount > 1) {
		for (int x = 1; x <= g_iRocksBeingThrownCount; x++) {
			g_iRocksBeingThrown[x-1] = g_iRocksBeingThrown[x];
		}
	}

	g_iRocksBeingThrownCount--;

	return tank;
}

/*  Height check..
    not required now
    maybe for some other 'skill'?
static float GetHeightAboveGround(float pos[3])
{
	// execute Trace straight down
	Handle trace = TR_TraceRayFilterEx(pos, ANGLE_STRAIGHT_DOWN, MASK_SHOT, RayType_Infinite, ChargeTraceFilter);

	if (!TR_DidHit(trace)) {
		LogError("Tracer Bug: Trace did not hit anything...");
	}

	float vEnd[3];
	TR_GetEndPosition(vEnd, trace); // retrieve our trace endpoint
	CloseHandle(trace);

	return GetVectorDistance(pos, vEnd, false);
}

public bool ChargeTraceFilter( int entity, int contentsMask)
{
	if (!entity || !IsValidEntity(entity)) { // dont let WORLD, or invalid entities be hit
		return false;
	}
	return true;
}
*/

stock void PrintDebug(const char[] Message, any ...)
{
	char DebugBuff[256];
	VFormat(DebugBuff, sizeof(DebugBuff), Message, 2);
	LogMessage(DebugBuff);
}
