#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <fun>
#include <hamsandwich>
#include <xs>
//=====================================
//  VERSION CHECK
//=====================================
#if AMXX_VERSION_NUM < 190
	#assert "AMX Mod X v1.9.0 or greater library required!"
#endif

#pragma semicolon 1

#define MAX_PLAYERS 	32

#define TASKID_REVIVE 	1337
#define TASKID_RESPAWN 	1338
#define TASKID_CHECKRE 	1339
#define TASKID_CHECKST 	13310
#define TASKID_ORIGIN 	13311
#define TASKID_SETUSER 	13312

#define pev_zorigin		pev_fuser4
#define seconds(%1) 	((1<<12) * (%1))

new MODEL_RKIT		[] 	= "models/w_medkit.mdl";

new SOUND_START		[] 	= "items/medshot4.wav";
new SOUND_FINISHED	[] 	= "items/smallmedkit2.wav";
new SOUND_FAILED	[] 	= "items/medshotno1.wav";
new SOUND_EQUIP		[]	= "items/ammopickup2.wav";
new ENTITY_KIT		[]	= "revival_kit";

enum
{
	ICON_HIDE = 0,
	ICON_SHOW,
	ICON_FLASH
};

enum _:CVAR_LIST
{
	REVIVAL_TIME,
	REVIVAL_HEALTH,
	REVIVAL_DISTANCE,
	REVIVAL_COST,
	REVIVAL_SC_FADE,
	REVIVAL_FADE_TIME,
};

enum _:CVAR_VALUE
{
	V_REVIVAL_TIME,
	V_REVIVAL_HEALTH,
	Float:V_REVIVAL_DISTANCE,
	V_REVIVAL_COST,
	V_REVIVAL_SC_FADE,
	V_REVIVAL_FADE_TIME,
};

enum _:PLAYER_DATA
{
	bool:HAS_KIT,
	bool:WAS_DUCKING,
	Float:REVIVE_DELAY,
	Float:BODY_ORIGIN	[3],
};

enum _:MSG_DATA
{
	MSG_BAR_TIME,
	MSG_SCREEN_FADE,
	MSG_STATUS_ICON,
	MSG_CLCORPSE,
}
new g_player_data			[MAX_PLAYERS + 1][PLAYER_DATA];
new g_msg_data				[MSG_DATA];

new g_cvars					[CVAR_LIST];
new g_values				[CVAR_VALUE];

static const PLUGIN_NAME	[] 	= "Revival Kit";
static const PLUGIN_AUTHOR	[] 	= "Cheap_Suit / +ARUKARI-";
static const PLUGIN_VERSION	[]	= "2.0";

public plugin_init()
{
	register_plugin	(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar	(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SPONLY|FCVAR_SERVER);
	
	register_clcmd("say /buyrkit", 	"cmd_buyrkit");
	register_clcmd("buyrkit", 		"cmd_buyrkit");

	g_cvars		[REVIVAL_TIME]		= create_cvar("amx_revkit_time",			"6");
	g_cvars		[REVIVAL_HEALTH]	= create_cvar("amx_revkit_health",			"75");
	g_cvars		[REVIVAL_DISTANCE]	= create_cvar("amx_revkit_distance",		"70.0");
	g_cvars		[REVIVAL_COST]		= create_cvar("amx_revkit_cost", 			"1200");
	g_cvars		[REVIVAL_SC_FADE]	= create_cvar("amx_revkit_screen_fade", 	"1");
	g_cvars		[REVIVAL_FADE_TIME]	= create_cvar("amx_revkit_screen_fade_time","2");

	bind_pcvar_num(g_cvars[REVIVAL_TIME],		g_values[V_REVIVAL_TIME]);
	bind_pcvar_num(g_cvars[REVIVAL_HEALTH], 	g_values[V_REVIVAL_HEALTH]);
	bind_pcvar_num(g_cvars[REVIVAL_COST], 		g_values[V_REVIVAL_COST]);
	bind_pcvar_float(g_cvars[REVIVAL_DISTANCE], g_values[V_REVIVAL_DISTANCE]);
	bind_pcvar_num(g_cvars[REVIVAL_SC_FADE], 	g_values[V_REVIVAL_SC_FADE]);
	bind_pcvar_num(g_cvars[REVIVAL_FADE_TIME], 	g_values[V_REVIVAL_FADE_TIME]);

	g_msg_data	[MSG_BAR_TIME]		= get_user_msgid("BarTime");
	g_msg_data	[MSG_CLCORPSE]		= get_user_msgid("ClCorpse");
	g_msg_data	[MSG_SCREEN_FADE]	= get_user_msgid("ScreenFade");
	g_msg_data	[MSG_STATUS_ICON]	= get_user_msgid("StatusIcon");

	register_message(g_msg_data	[MSG_CLCORPSE], "message_clcorpse");
	
	register_event	("HLTV", 		"event_hltv",	"a", "1=0", "2=0");
	
	RegisterHam		(Ham_Killed,			"player",	"event_death");
	RegisterHam		(Ham_Player_PostThink,	"player",	"fwd_playerpostthink");
	RegisterHam		(Ham_Touch,				ENTITY_KIT,	"fwd_touch");

	register_forward(FM_EmitSound,			"fwd_emitsound");
}

public plugin_precache()
{
	precache_model("models/player/arctic/arctic.mdl");
	precache_model("models/player/terror/terror.mdl");
	precache_model("models/player/leet/leet.mdl");
	precache_model("models/player/guerilla/guerilla.mdl");
	precache_model("models/player/gign/gign.mdl");
	precache_model("models/player/sas/sas.mdl");
	precache_model("models/player/gsg9/gsg9.mdl");
	precache_model("models/player/urban/urban.mdl");
	precache_model("models/player/vip/vip.mdl");
	
	precache_model(MODEL_RKIT);
	
	precache_sound(SOUND_START);
	precache_sound(SOUND_FINISHED);
	precache_sound(SOUND_FAILED);
	precache_sound(SOUND_EQUIP);
}

public cmd_buyrkit(id)
{
	if(!is_user_alive(id))
		client_print(id, print_chat, "You need to be alive.");
	else if(g_player_data[id][HAS_KIT])
		client_print(id, print_chat, "You already have a revival kit.");
	else if(!cs_get_user_buyzone(id))
		client_print(id, print_chat, "You need to be in the buyzone.");
	else if(cs_get_user_money(id) < g_values[V_REVIVAL_COST])
		client_print(id, print_chat, "You dont have enough money (Cost:$%d)", g_values[V_REVIVAL_COST]);
	else
	{
		g_player_data[id][HAS_KIT] = true;
		cs_set_user_money(id, cs_get_user_money(id) - g_values[V_REVIVAL_COST]);
		client_print(id, print_chat, "You bought a revival kit. Hold your +use key (E) to revive a teammate.");
		client_cmd(id, "spk %s", SOUND_EQUIP);
		
	}
	return PLUGIN_HANDLED;
}

public message_clcorpse()	
	return PLUGIN_HANDLED;
	
public client_connect(id)
{
	g_player_data[id][HAS_KIT] = false;
	reset_player(id);
}

public event_hltv()
{
	remove_all_entity("fake_corpse");
	remove_all_entity(ENTITY_KIT);
	set_task(1.0, "task_botbuy");
	
	static players[32], num;
	get_players(players, num, "a");
	for(new i = 0; i < num; ++i)
		reset_player(players[i]);
}
	
public task_botbuy()
{
	static players[32], num;
	get_players(players, num, "ad");
	for(new i = 0; i < num; ++i) if(!g_player_data[players[i]][HAS_KIT])
		cmd_buyrkit(players[i]);
}

public reset_player(id)
{
	remove_task(TASKID_REVIVE + id);
	remove_task(TASKID_RESPAWN + id);
	remove_task(TASKID_CHECKRE + id);
	remove_task(TASKID_CHECKST + id);
	remove_task(TASKID_ORIGIN + id);
	remove_task(TASKID_SETUSER + id);
	
	msg_bartime(id, 0);
	g_player_data[id][REVIVE_DELAY] = 0.0;
	g_player_data[id][WAS_DUCKING]	= false;
	g_player_data[id][BODY_ORIGIN]	= Float:{0.0, 0.0, 0.0};
}

public client_disconnected(id)
{
	new ent;
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "fake_corpse")))
	{
		if (pev(ent, pev_owner) == id)
			engfunc(EngFunc_RemoveEntity, ent);
	}
}

public fwd_touch(kit, id)
{
	if(!pev_valid(kit))
		return FMRES_IGNORED;
	
	if(!is_user_alive(id) || g_player_data[id][HAS_KIT])
		return FMRES_IGNORED;
	
	new classname[32];
	pev(kit, pev_classname, classname, 31);
	
	if(equal(classname, ENTITY_KIT))
	{
		engfunc(EngFunc_RemoveEntity, kit);
		g_player_data[id][HAS_KIT] = true;
		client_cmd(id, "spk %s", SOUND_EQUIP);
	}
	return FMRES_IGNORED;
}

public fwd_playerpostthink(id)
{
	if(!is_user_connected(id) || !g_player_data[id][HAS_KIT])
		return FMRES_IGNORED;
	
	if(!is_user_alive(id))
	{
		msg_statusicon(id, ICON_HIDE);
		return FMRES_IGNORED;
	}
	
	new body = find_dead_body(id);
	if(pev_valid(body))
	{
		new lucky_bastard = pev(body, pev_owner);
	
		if(!is_user_connected(lucky_bastard))
			return FMRES_IGNORED;

		new lb_team = get_user_team(lucky_bastard);
		new rev_team = get_user_team(id);
		if(lb_team == 1 || lb_team == 2 && lb_team == rev_team)
			msg_statusicon(id, ICON_FLASH);
	}
	else
		msg_statusicon(id, ICON_SHOW);
	
	return FMRES_IGNORED;
}

public event_death(iVictim, iAttacker)
{
	reset_player(iVictim);
	if(g_player_data[iVictim][HAS_KIT])
	{
		g_player_data[iVictim][HAS_KIT] = false;
		drop_kit(iVictim);
	}
	
	static Float:minsize[3];
	pev(iVictim, pev_mins, minsize);

	if(minsize[2] == -18.0)
		g_player_data[iVictim][WAS_DUCKING] = true;
	else
		g_player_data[iVictim][WAS_DUCKING] = false;
	
	set_task(0.5, "task_check_dead_flag", iVictim);
}

public drop_kit(id)
{
	new Float:velocity[3];
	velocity_by_aim(id, 34, velocity);
		
	new Float:origin[3];
	pev(id, pev_origin, origin);

	velocity[2] = 0.0;
	xs_vec_add(origin, velocity, origin);

	new kit = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	if(pev_valid(kit))
	{
		set_pev(kit, pev_classname, ENTITY_KIT);
		engfunc(EngFunc_SetModel, kit, MODEL_RKIT);
		engfunc(EngFunc_SetOrigin, kit, origin);
		engfunc(EngFunc_SetSize, kit, Float:{-2.5, -2.5, -1.5}, Float:{2.5, 2.5, 1.5});
		set_pev(kit, pev_solid, SOLID_TRIGGER);
		set_pev(kit, pev_movetype, MOVETYPE_TOSS);
	}
	return PLUGIN_CONTINUE;
}

public task_check_dead_flag(id)
{
	if(!is_user_connected(id))
		return;
	
	if(pev(id, pev_deadflag) == DEAD_DEAD)
		create_fake_corpse(id);
	else
		set_task(0.5, "task_check_dead_flag", id);
}	

public create_fake_corpse(id)
{
	set_pev(id, pev_effects, EF_NODRAW);
	
	static model[32];
	cs_get_user_model(id, model, 31);
		
	static player_model[64];
	format(player_model, 63, "models/player/%s/%s.mdl", model, model);
			
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
	
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	if(ent)
	{
		set_pev(ent, pev_classname, "fake_corpse");
		engfunc(EngFunc_SetModel, ent, player_model);
		engfunc(EngFunc_SetOrigin, ent, player_origin);
		engfunc(EngFunc_SetSize, ent, mins, maxs);
		set_pev(ent, pev_solid, SOLID_TRIGGER);
		set_pev(ent, pev_movetype, MOVETYPE_TOSS);
		set_pev(ent, pev_owner, id);
		set_pev(ent, pev_angles, player_angles);
		set_pev(ent, pev_sequence, sequence);
		set_pev(ent, pev_frame, 9999.9);
	}	
}

public fwd_emitsound(id, channel, sound[]) 
{
	if(!is_user_alive(id) || !g_player_data[id][HAS_KIT])
		return FMRES_IGNORED;	
	
	if(!equali(sound, "common/wpn_denyselect.wav"))
		return FMRES_IGNORED;	
	
	if(task_exists(TASKID_REVIVE + id))
		return FMRES_IGNORED;
	
	if(!(pev(id, pev_button) & IN_USE))
		return FMRES_IGNORED;
	
	new body = find_dead_body(id);
	if(!pev_valid(body))
		return FMRES_IGNORED;

	new lucky_bastard = pev(body, pev_owner);
	new lb_team = get_user_team(lucky_bastard);
	new rev_team = get_user_team(id);
	if(lb_team != 1 && lb_team != 2 || lb_team != rev_team)
		return FMRES_IGNORED;

	static name[32];
	get_user_name(lucky_bastard, name, 31);
	client_print(id, print_chat, "Reviving %s", name);

	new revivaltime = g_values[V_REVIVAL_TIME];
	msg_bartime(id, revivaltime);
	
	new Float:gametime = get_gametime();
	g_player_data[id][REVIVE_DELAY] = gametime + float(revivaltime) - 0.01;

	emit_sound(id, CHAN_AUTO, SOUND_START, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
	set_task(0.0, "task_revive", TASKID_REVIVE + id);
	
	return FMRES_SUPERCEDE;
}

public task_revive(taskid)
{
	new id = taskid - TASKID_REVIVE;
	
	if(!is_user_alive(id))
	{
		failed_revive(id);
		return FMRES_IGNORED;
	}
	
	if(!(pev(id, pev_button) & IN_USE))
	{
		failed_revive(id);
		return FMRES_IGNORED;
	}
	
	new body = find_dead_body(id);
	if(!pev_valid(body))
	{
		failed_revive(id);
		return FMRES_IGNORED;
	}
	
	new lucky_bastard = pev(body, pev_owner);
	if(!is_user_connected(lucky_bastard))
	{
		failed_revive(id);
		return FMRES_IGNORED;
	}
	
	new lb_team = get_user_team(lucky_bastard);
	new rev_team = get_user_team(id);
	if(lb_team != 1 && lb_team != 2 || lb_team != rev_team)
	{
		failed_revive(id);
		return FMRES_IGNORED;
	}
	
	static Float:velocity[3];
	pev(id, pev_velocity, velocity);
	xs_vec_set(velocity, 0.0, 0.0, velocity[2]);
	set_pev(id, pev_velocity, velocity);
	
	new Float:gametime = get_gametime();
	if(g_player_data[id][REVIVE_DELAY] < gametime)
	{
		if(findemptyloc(body, 10.0))
		{
			engfunc(EngFunc_RemoveEntity, body);
			emit_sound(id, CHAN_AUTO, SOUND_FINISHED, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
			set_task(0.1, "task_respawn", TASKID_RESPAWN + lucky_bastard);
		}
		else
			 failed_revive(id);
	}
	else
		set_task(0.1, "task_revive", TASKID_REVIVE + id);
	
	return FMRES_IGNORED;
}

public failed_revive(id)
{
	msg_bartime(id, 0);
	emit_sound(id, CHAN_AUTO, SOUND_FAILED, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
}

public task_origin(taskid)
{
	new id = taskid - TASKID_ORIGIN;
	engfunc(EngFunc_SetOrigin, id, g_player_data[id][BODY_ORIGIN]);
	
	static  Float:origin[3];
	pev(id, pev_origin, origin);
	set_pev(id, pev_zorigin, origin[2]);
		
	set_task(0.1, "task_stuck_check", TASKID_CHECKST + id);
}

stock find_dead_body(id)
{
	static Float:origin[3];
	pev(id, pev_origin, origin);
	
	new ent;
	static classname[32]	;
	while((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, g_values[V_REVIVAL_DISTANCE])) != 0)
	{
		pev(ent, pev_classname, classname, 31);
		if(equali(classname, "fake_corpse") && is_ent_visible(id, ent))
			return ent;
	}
	return 0;
}

stock msg_bartime(id, seconds) 
{
	if(is_user_bot(id))
		return;
	
	message_begin(MSG_ONE, g_msg_data[MSG_BAR_TIME], _, id);
	write_byte(seconds);
	write_byte(0);
	message_end();
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

 public task_respawn(taskid) 
 {
	new id = taskid - TASKID_RESPAWN;
	
	set_pev(id, pev_deadflag, DEAD_RESPAWNABLE);
	dllfunc(DLLFunc_Spawn, id);
	set_pev(id, pev_iuser1, 0);
	
	set_task(0.1, "task_check_respawn", TASKID_CHECKRE + id);
}

public task_check_respawn(taskid)
{
	new id = taskid - TASKID_CHECKRE;
	
	if(pev(id, pev_iuser1))
		set_task(0.1, "task_respawn", TASKID_RESPAWN + id);
	else
		set_task(0.1, "task_origin", TASKID_ORIGIN + id);
}
 
public task_stuck_check(taskid)
{
	new id = taskid - TASKID_CHECKST;

	static Float:origin[3];
	pev(id, pev_origin, origin);
	
	if(origin[2] == pev(id, pev_zorigin))
		set_task(0.1, "task_respawn", TASKID_RESPAWN + id);
	else
		set_task(0.1, "task_setplayer", TASKID_SETUSER + id);
}

public task_setplayer(taskid)
{
	new id = taskid - TASKID_SETUSER;
	
	if (pev(id, pev_weapons) & (1<<CSW_C4))
	    engclient_cmd(id, "drop", "weapon_c4");

	strip_user_weapons(id);
	give_item(id, "weapon_knife");
	set_user_health(id, g_values[V_REVIVAL_HEALTH]);
	
	message_begin(MSG_ONE,g_msg_data[MSG_SCREEN_FADE], _, id)      ;
	write_short(seconds(2));
	write_short(seconds(2));
	write_short(0);
	write_byte(0);
	write_byte(0);
	write_byte(0);
	write_byte(255);
	message_end();
}

stock bool:findemptyloc(ent, Float:radius)
{
	if(!pev_valid(ent))
		return false;

	static Float:origin[3];
	pev(ent, pev_origin, origin);
	origin[2] += 2.0;
	
	new owner = pev(ent, pev_owner);
	new num = 0, bool:found = false;
	
	while(num <= 100)
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

stock bool:is_hull_vacant(const Float:origin[3])
{
	new tr = 0;
	engfunc(EngFunc_TraceHull, origin, origin, 0, HULL_HUMAN, 0, tr);
	if(!get_tr2(tr, TR_StartSolid) && !get_tr2(tr, TR_AllSolid) && get_tr2(tr, TR_InOpen))
		return true;
	
	return false;
}

//====================================================
// Remove all Entity.
//====================================================
stock remove_all_entity(className[])
{
	new iEnt = -1;

	while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", className)))
	{
		if (!pev_valid(iEnt))
			continue;

		engfunc(EngFunc_RemoveEntity, iEnt);
	}
}

stock bool:is_ent_visible(index, entity, ignoremonsters = 0) {
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
