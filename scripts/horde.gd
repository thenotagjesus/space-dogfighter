extends Node3D
## HORDE MODE: wave-based co-op survival on the top-down plane, a homage to the classic
## top-down arcade shooters (original names, shapes and rules only).
## Lives under World as "Horde" on every peer. The server runs the waves, the enemy AI,
## scoring and drops; clients get spawn/die events (reliable) and 20 Hz position snaps (unreliable).
## Built from a Z.ai GLM-4.5-Flash draft (AI, boss patterns, chains, drops) with the broken parts rewritten.
const EnemyScript := preload("res://scripts/horde_enemy.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Meshes := preload("res://scripts/meshes.gd")

const SWARMER := 0
const DARTER := 1
const GUNNER := 2
const SPLIT_L := 3
const SPLIT_M := 4
const SPLIT_S := 5
const MARCHER := 6
const BOSS := 7

const LEVELS := {
	5: {"name": "GRID SWARM", "mix": [SWARMER, DARTER, GUNNER], "boss": "HIVE MOTHER"},
	6: {"name": "MAGMA BREAK", "mix": [SPLIT_L, SWARMER, GUNNER], "boss": "CINDER COLOSSUS"},
	7: {"name": "SKYFALL LINE", "mix": [DARTER, GUNNER, SWARMER], "boss": "DREADNOUGHT BARGE"},
}
const WAVES_PER_LEVEL := 5        # wave 5 is the boss
const START_LIVES := 6            # shared by the team
const CHAIN_WINDOW := 2.5         # seconds between kills to keep a chain going
const CHAIN_MAX := 8
const DROP_NAMES := ["REPAIR", "AMMO", "OVERDRIVE"]
const DROP_COLS := [Color(0.3, 1.0, 0.4), Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 1.0)]
const DROP_LIFE := 12.0
const LINE_Z := 270.0             # Skyfall Line: marchers that reach this Z breach the line
const ST_INTER := 0
const ST_WAVE := 1
const ST_BOSS := 2
const ST_OVER := 3

var world: Node = null
var PLANE := 30.0
var level := 5
var level_name := ""
var boss_name := ""
var wave := 0
var loop := 0
var lives := START_LIVES
var state := ST_INTER
var banner := ""
var banner_t := 0.0
var boss_frac := 0.0
var enemies := {}            # id -> enemy node (every peer)
var drops := {}              # id -> {"type", "pos", "t", "node"}
var high_table: Array = []   # shown on game over: [[score, name, level, wave, loop], ...]
var over_t := 0.0
# server only
var next_id := 1
var next_drop := 1
var queue: Array = []
var spawn_t := 0.0
var inter_t := 4.0
var chain := {}              # nn -> {"n", "t"}
var contact_cd := {}
var form_x := 0.0
var form_dir := 1.0
var boss: Node3D = null
var boss_t := 0.0
var boss_t2 := 0.0
var now_s := 0.0
var snap_t := 0.0
var state_t := 0.0

func _ready() -> void:
	world = get_parent()
	PLANE = world.cfg["plane_y"]
	level = int(world.cfg["id"]) if LEVELS.has(int(world.cfg["id"])) else 5
	level_name = LEVELS[level]["name"]
	boss_name = LEVELS[level]["boss"]
	high_table = load_table(level_name)
	if multiplayer.is_server():
		banner = "%s - GET READY" % level_name
		banner_t = 3.5
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--horde-wave="):   # testing: start at wave N (5 = boss)
				wave = clampi(int(arg.substr(13)), 1, WAVES_PER_LEVEL) - 1

## Server -> everyone (locally first, then every ready peer).
func hbc(m: StringName, args: Array) -> void:
	callv(m, args)
	for p in world.ready_peers:
		callv("rpc_id", [p, m] + args)

func _process(d: float) -> void:
	banner_t -= d
	for id in drops:
		var dr: Dictionary = drops[id]
		if dr["node"]:
			dr["node"].rotation.y += d * 3.0
			dr["node"].position.y = PLANE + sin(Time.get_ticks_msec() * 0.005 + id) * 0.8

func _physics_process(d: float) -> void:
	if not multiplayer.is_server(): return
	now_s += d
	match state:
		ST_INTER:
			inter_t -= d
			if inter_t <= 0.0: _start_wave()
		ST_WAVE, ST_BOSS:
			_spawning(d)
			_ai(d)
			_contact()
			_chains()
			_drops(d)
			_wave_end_check()
		ST_OVER:
			over_t -= d
			if over_t <= 0.0: _reset()
	if lives <= 0 and state != ST_OVER:
		_game_over()
	boss_frac = clampf(boss.hp / boss.max_hp, 0.0, 1.0) if boss and is_instance_valid(boss) and boss.alive else 0.0
	snap_t -= d
	if snap_t <= 0.0:
		snap_t = 0.05
		var arr := PackedFloat32Array()
		for e in enemies.values():
			if e.alive:
				arr.append_array([float(e.id), e.position.x, e.position.z, e.hp / e.max_hp])
		for p in world.ready_peers:
			rpc_id(p, "cl_snap", arr)
	state_t -= d
	if state_t <= 0.0:
		state_t = 0.25
		for p in world.ready_peers:
			rpc_id(p, "cl_state", wave, loop, lives, state, banner, banner_t, boss_frac)

# ---------------------------------------------------------------- waves (server)
func _players() -> int:
	return maxi(1, world.ships.get_child_count())

func _start_wave() -> void:
	wave += 1
	if wave > WAVES_PER_LEVEL:
		wave = 1
		loop += 1
	var pl := _players()
	var mix: Array = LEVELS[level]["mix"]
	if wave == WAVES_PER_LEVEL:
		state = ST_BOSS
		boss_t = 0.0
		boss_t2 = 0.0
		boss = _spawn(BOSS, Vector3(0, PLANE, -200.0), (1.0 + 0.35 * (pl - 1)) * (1.0 + 0.5 * loop))
		banner = "WARNING - %s" % boss_name
		banner_t = 3.0
		for i in 4 + 2 * loop: queue.append(mix[0])
		return
	state = ST_WAVE
	var count := int((8.0 + wave * 4.0) * (1.0 + 0.35 * (pl - 1)) * (1.0 + 0.3 * loop))
	for i in count:
		var r := randf()
		if wave >= 3 and r > 0.82: queue.append(mix[2])
		elif wave >= 2 and r > 0.6: queue.append(mix[1])
		elif mix[0] == SPLIT_L and i % 3 != 0: queue.append(SWARMER)   # a big rock is 7 kills: thin them out
		else: queue.append(mix[0])
	if level == 7:
		_formation(2 + wave / 2, -240.0)
	banner = "WAVE %d" % wave if loop == 0 else "LOOP %d - WAVE %d" % [loop + 1, wave]
	banner_t = 2.5

## Skyfall Line: rows of 8 marchers that sweep side to side and step toward the line.
func _formation(rows: int, z0: float) -> void:
	var any := false
	for e in enemies.values():
		if is_instance_valid(e) and e.alive and e.type == MARCHER: any = true
	if not any:
		form_x = 0.0   # fresh sweep when no formation is on the field
	for row in rows:
		for i in 8:
			var hx := -77.0 + i * 22.0
			var m := _spawn(MARCHER, Vector3(hx + form_x, PLANE, z0 - row * 18.0), 1.0 + 0.25 * loop)
			m.dash_dir = Vector3(hx, 0, 0)   # home column offset in the formation

func _spawning(d: float) -> void:
	spawn_t -= d
	if queue.is_empty() or spawn_t > 0.0: return
	spawn_t = maxf(0.12, 0.45 - 0.04 * wave - 0.05 * loop)
	var t: int = queue.pop_front()
	var rr: float = world.cfg["radius"] - 15.0
	var pos := Vector3.ZERO
	for attempt in 6:
		var a := randf() * TAU
		pos = Vector3(cos(a) * rr, PLANE, sin(a) * rr)
		if level == 7: pos = Vector3(randf_range(-250.0, 250.0), PLANE, -rr * 0.9)
		var near: Node3D = world.find_ship_near(pos, 70.0)
		if near == null: break
	_spawn(t, pos, 1.0 + 0.25 * loop)

func _spawn(t: int, pos: Vector3, hp_mul: float) -> Node3D:
	var id := next_id
	next_id += 1
	var e := EnemyScript.new()
	e.setup(self, id, t, pos, hp_mul)
	add_child(e)
	enemies[id] = e
	for p in world.ready_peers:
		rpc_id(p, "cl_spawn", id, t, pos, hp_mul)
	return e

func _wave_end_check() -> void:
	if not queue.is_empty(): return
	for e in enemies.values():
		if e.alive: return
	if state == ST_BOSS:
		banner = "LEVEL CLEAR - +2000 - EXTRA LIFE - NEXT LOOP HARDER"
		lives += 1
		banner_t = 4.0
		inter_t = 6.0
		for nn in Net.scores:
			if world.ships.has_node(NodePath(nn)):
				Net.scores[nn]["score"] = int(Net.scores[nn].get("score", 0)) + 2000
		world.mark_scores_dirty()
	else:
		banner = "WAVE %d CLEAR" % wave
		banner_t = 2.0
		inter_t = 3.0
	state = ST_INTER

func _game_over() -> void:
	state = ST_OVER
	over_t = 9.0
	banner = "GAME OVER"
	banner_t = 9.0
	queue.clear()
	for id in enemies.keys(): _remove(id, 1.0)
	for id in drops.keys(): hbc("cl_drop_gone", [id])
	var entries: Array = []
	for nn in Net.scores:
		entries.append([int(Net.scores[nn].get("score", 0)), str(Net.scores[nn]["name"]), nn])
	hbc("cl_over", [entries, wave, loop])
	hbc("cl_feed_over", [])

func _reset() -> void:
	wave = 0
	loop = 0
	lives = START_LIVES
	chain.clear()
	boss = null
	form_x = 0.0
	form_dir = 1.0
	for nn in Net.scores:
		Net.scores[nn]["score"] = 0
		Net.scores[nn]["chain"] = 1
	world.mark_scores_dirty()
	state = ST_INTER
	inter_t = 4.0
	banner = "%s - GET READY" % level_name
	banner_t = 3.5

# ---------------------------------------------------------------- enemy AI (server)
func _ai(d: float) -> void:
	var r_arena: float = world.cfg["radius"] - 5.0
	var sp_mul := 1.0 + 0.2 * loop
	# formation sweep (Skyfall Line marchers)
	var edge := false
	var breached := false
	form_x += form_dir * (14.0 + 3.0 * wave) * sp_mul * d
	for e in enemies.values():
		if e.alive and e.type == MARCHER and (e.dash_dir.x + form_x) * form_dir > 250.0: edge = true   # only when heading outward
	if edge:
		form_dir = -form_dir
		form_x += form_dir * 2.0
		for e in enemies.values():
			if e.alive and e.type == MARCHER: e.position.z += 12.0
	for e in enemies.values().duplicate():
		if not is_instance_valid(e) or not e.alive: continue
		var tgt: Node3D = world.find_ship_near(e.position, 1.0e9)
		var spd: float = EnemyScript.INFO[e.type]["spd"] * sp_mul
		var to := Vector3.ZERO
		if tgt:
			to = tgt.global_position - e.position
			to.y = 0.0
		var dir := to.normalized()
		match e.type:
			SWARMER:
				var desired := dir * spd
				var sep := Vector3.ZERO
				for o in enemies.values():
					if o == e or not o.alive: continue
					var df: Vector3 = e.position - o.position
					df.y = 0.0
					var l2 := df.length_squared()
					if l2 < 64.0 and l2 > 0.001: sep += df / l2 * 40.0
				e.vel = e.vel.lerp(desired + sep, 1.0 - exp(-3.0 * d))
			DARTER:
				e.t += d
				if e.phase == 0:
					e.vel *= exp(-4.0 * d)
					if e.t > 1.1:
						e.phase = 1
						e.t = 0.0
						e.dash_dir = dir if tgt else Vector3.FORWARD
				else:
					e.vel = e.dash_dir * spd
					if e.t > 0.55:
						e.phase = 0
						e.t = 0.0
			GUNNER:
				var dd := to.length()
				var want := Vector3(-dir.z, 0, dir.x)   # strafe around the target at 70-110 m
				if dd > 110.0: want = dir
				elif dd < 70.0: want = -dir
				e.vel = e.vel.lerp(want * spd, 1.0 - exp(-2.0 * d))
				e.t += d
				if tgt and dd < 260.0 and e.t > 2.2 / sp_mul:
					e.t = 0.0
					_bolt(e, dir)
			SPLIT_L, SPLIT_M, SPLIT_S:
				if e.vel.length() < 1.0:
					var a := randf() * TAU
					e.vel = Vector3(cos(a), 0, sin(a)) * spd
				# bounce off the arena edge, drift slowly toward the nearest pilot
				var p2 := Vector2(e.position.x, e.position.z)
				if p2.length() > r_arena - e.r:
					var n := -p2.normalized()
					var v2 := Vector2(e.vel.x, e.vel.z)
					if v2.dot(n) < 0.0:
						v2 = v2 - 2.0 * v2.dot(n) * n
						e.vel = Vector3(v2.x, 0, v2.y)
				if tgt: e.vel = (e.vel + dir * spd * 0.3 * d).limit_length(spd * 1.6)
			MARCHER:
				e.vel = Vector3.ZERO
				var nx: float = e.dash_dir.x + form_x
				e.vel = Vector3((nx - e.position.x) / maxf(d, 0.001), 0, (6.0 + 2.0 * wave) * sp_mul)
				e.position.x = nx
				e.position.z += e.vel.z * d
				if randf() < 0.25 * d * sp_mul:
					_bolt(e, Vector3.BACK)
				if e.position.z > LINE_Z:
					breached = true
				continue
			BOSS:
				_boss_ai(e, tgt, dir, d)
				continue
		e.position += e.vel * d
		e.position.y = PLANE
		var q := Vector2(e.position.x, e.position.z)
		if q.length() > r_arena:
			q = q.normalized() * r_arena
			e.position.x = q.x
			e.position.z = q.y
		e.est_vel = e.vel
	if breached:
		# the formation lands: one team life, and every marcher still on the field is gone
		lives = maxi(0, lives - 1)
		banner = "LINE BREACHED - %d LIVES" % lives
		banner_t = 2.0
		for e in enemies.values().duplicate():
			if is_instance_valid(e) and e.alive and e.type == MARCHER:
				e.alive = false
				_remove(e.id, 1.0)

func _boss_ai(e: Node3D, tgt: Node3D, dir: Vector3, d: float) -> void:
	boss_t += d
	boss_t2 += d
	var enraged: bool = e.hp < e.max_hp * 0.4
	var prev: Vector3 = e.position
	match level:
		5:   # HIVE MOTHER: circles the yard, hatches swarmers, rings of bolts
			var a := now_s * 0.25
			e.position = Vector3(cos(a) * 120.0, PLANE, sin(a) * 120.0)
			if boss_t > (2.2 if enraged else 3.2):
				boss_t = 0.0
				for i in 3 + loop:
					var sa := a + i * TAU / float(3 + loop)
					_spawn(SWARMER, e.position + Vector3(cos(sa), 0, sin(sa)) * (e.r + 8.0), 1.0 + 0.25 * loop)
			if boss_t2 > (1.1 if enraged else 1.6):
				boss_t2 = 0.0
				var n := 16 if enraged else 12
				var off := randf() * TAU
				for i in n:
					var ba := off + i * TAU / float(n)
					_bolt(e, Vector3(cos(ba), 0, sin(ba)))
		6:   # CINDER COLOSSUS: stomps after the nearest pilot, fan bursts, sheds rocks as it cracks
			if tgt: e.position += dir * (14.0 if enraged else 9.0) * d
			if boss_t > (1.0 if enraged else 1.6) and tgt:
				boss_t = 0.0
				for i in 5:
					_bolt(e, dir.rotated(Vector3.UP, deg_to_rad((i - 2) * 14.0)))
			if (e.phase == 0 and e.hp < e.max_hp * 0.66) or (e.phase == 1 and e.hp < e.max_hp * 0.33):
				e.phase += 1
				for i in 3:
					var oa := i * TAU / 3.0
					_spawn(SPLIT_L, e.position + Vector3(cos(oa), 0, sin(oa)) * (e.r + 14.0), 1.0 + 0.25 * loop)
		7:   # DREADNOUGHT BARGE: sweeps the far edge, broadside fans, drops fresh formations
			e.position = Vector3(sin(now_s * 0.35) * 200.0, PLANE, -230.0)
			if boss_t > (0.7 if enraged else 1.0):
				boss_t = 0.0
				for i in 3:
					var bd := (dir if tgt else Vector3.BACK).rotated(Vector3.UP, deg_to_rad((i - 1) * 18.0))
					_bolt(e, bd)
			if boss_t2 > 9.0:
				boss_t2 = 0.0
				_formation(1, -200.0)
	e.position.y = PLANE
	e.vel = (e.position - prev) / maxf(d, 0.001)
	e.est_vel = e.vel

func _bolt(e: Node3D, dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001: return
	dir = dir.normalized()
	var spd := 95.0 + 10.0 * loop
	world.bc("cl_proj", [Weapons.HORDE_BOLT, e.position + dir * (e.r + 2.0), dir * spd, "#horde", "", Vector3.ZERO])

func _contact() -> void:
	for e in enemies.values().duplicate():
		if not is_instance_valid(e) or not e.alive: continue
		for s in world.ships.get_children():
			if not s.alive: continue
			var df: Vector3 = e.position - s.global_position
			df.y = 0.0
			if df.length() > e.r + 2.5: continue
			var key := "%d:%s" % [e.id, s.name]
			if contact_cd.get(key, 0.0) > now_s: continue
			contact_cd[key] = now_s + 0.6
			s.server_damage(30.0 if e.type == BOSS else 16.0, "#horde", 0, "was overrun by the horde")
			if e.type in [SWARMER, DARTER, SPLIT_S]:
				_remove(e.id, 0.6)   # small fry burst on impact (no score)
				break
	if contact_cd.size() > 400:
		for k in contact_cd.keys():
			if contact_cd[k] < now_s: contact_cd.erase(k)

func _chains() -> void:
	for nn in chain.keys():
		if now_s - float(chain[nn]["t"]) > CHAIN_WINDOW:
			chain.erase(nn)
			if Net.scores.has(nn) and int(Net.scores[nn].get("chain", 1)) != 1:
				Net.scores[nn]["chain"] = 1
				world.mark_scores_dirty()

func _drops(d: float) -> void:
	for id in drops.keys():
		var dr: Dictionary = drops[id]
		dr["t"] -= d
		if dr["t"] <= 0.0:
			hbc("cl_drop_gone", [id])
			continue
		for s in world.ships.get_children():
			if not s.alive: continue
			var df: Vector3 = s.global_position - dr["pos"]
			df.y = 0.0
			if df.length() > 7.0: continue
			match int(dr["type"]):
				0: s.health = mini(100, s.health + 40)
				1:
					var a: PackedInt32Array = s.ammo.duplicate()
					for wi in Weapons.LIST.size():
						if int(Weapons.LIST[wi]["max"]) > 0 and (Weapons.has_slot(s.loadout, wi) or wi == Weapons.MISSILE):
							a[wi] = int(Weapons.LIST[wi]["max"])
					s.ammo = a
				2: s.give_overdrive(8.0)
			world.bc("cl_feed", ["%s grabbed %s" % [s.pilot_name, DROP_NAMES[int(dr["type"])]]])
			hbc("cl_drop_gone", [id])
			break

# ---------------------------------------------------------------- hooks from world / enemies (server)
func enemy_hit(e: Node3D, amount: float, attacker_nn: String) -> void:
	if not e.alive or state == ST_OVER: return
	e.hp -= amount
	e.flash()
	if e.hp > 0.0: return
	e.alive = false
	var base: int = EnemyScript.INFO[e.type]["score"]
	if Net.scores.has(attacker_nn):
		var c: Dictionary = chain.get(attacker_nn, {"n": 0, "t": -100.0})
		c["n"] = int(c["n"]) + 1 if now_s - float(c["t"]) <= CHAIN_WINDOW else 1
		c["t"] = now_s
		chain[attacker_nn] = c
		var mult := mini(CHAIN_MAX, 1 + (int(c["n"]) - 1) / 3)
		var sc: Dictionary = Net.scores[attacker_nn]
		sc["score"] = int(sc.get("score", 0)) + int(base * mult * (1.0 + 0.5 * loop))
		sc["chain"] = mult
		sc["frags"] = int(sc["frags"]) + 1
		world.mark_scores_dirty()
		if e.type == BOSS:
			world.bc("cl_feed", ["%s destroyed the %s!" % [sc["name"], boss_name]])
	var p: Vector3 = e.position
	if e.type == SPLIT_L or e.type == SPLIT_M:
		var child_t := SPLIT_M if e.type == SPLIT_L else SPLIT_S
		var base_v: Vector3 = e.vel if e.vel.length() > 1.0 else Vector3(1, 0, 0) * 10.0
		for i in 2:
			var ang := deg_to_rad(50.0) * (1.0 if i == 0 else -1.0)
			var c2 := _spawn(child_t, p + base_v.normalized().rotated(Vector3.UP, ang) * e.r * 0.6, 1.0 + 0.25 * loop)
			c2.vel = base_v.rotated(Vector3.UP, ang) * 1.4
	var chance := 0.08
	if e.type == GUNNER: chance = 0.2
	if e.type == BOSS:
		for i in 3: _spawn_drop(i, p + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 14.0)
	elif randf() < chance:
		_spawn_drop(randi() % 3, p)
	if e == boss: boss = null
	_remove(e.id, maxf(0.8, e.r / 4.0))

func _spawn_drop(t: int, pos: Vector3) -> void:
	var id := next_drop
	next_drop += 1
	pos.y = PLANE
	hbc("cl_drop", [id, t, pos])

func _remove(id: int, fx: float) -> void:
	if not enemies.has(id): return
	var e = enemies[id]
	if fx > 0.0 and is_instance_valid(e):
		world.bc("cl_fx", [1, e.position, fx])
	hbc("cl_die", [id])

## Any pilot death in horde mode costs the team a life.
func on_player_down(nn: String) -> void:
	if state == ST_OVER: return
	lives = maxi(0, lives - 1)
	chain.erase(nn)
	if Net.scores.has(nn):
		Net.scores[nn]["chain"] = 1
		world.mark_scores_dirty()
	if lives > 0:
		banner = "PILOT DOWN - %d LIVES LEFT" % lives
		banner_t = 2.0

func enemy_list() -> Array:
	var out: Array = []
	for e in enemies.values():
		if is_instance_valid(e) and e.alive: out.append(e)
	return out

## Late joiner: send the live enemies, drops and state.
func sync_to(peer: int) -> void:
	for id in enemies:
		var e = enemies[id]
		if is_instance_valid(e) and e.alive:
			rpc_id(peer, "cl_spawn", id, e.type, e.position, e.max_hp / float(EnemyScript.INFO[e.type]["hp"]))
	for id in drops:
		rpc_id(peer, "cl_drop", id, int(drops[id]["type"]), drops[id]["pos"])
	rpc_id(peer, "cl_state", wave, loop, lives, state, banner, banner_t, boss_frac)

# ---------------------------------------------------------------- client side
@rpc("authority", "call_remote", "reliable")
func cl_spawn(id: int, t: int, pos: Vector3, hp_mul: float) -> void:
	if enemies.has(id): return
	var e := EnemyScript.new()
	e.setup(self, id, t, pos, hp_mul)
	add_child(e)
	enemies[id] = e

@rpc("authority", "call_remote", "reliable")
func cl_die(id: int) -> void:
	if not enemies.has(id): return
	var e = enemies[id]
	enemies.erase(id)
	if is_instance_valid(e):
		e.alive = false
		e.queue_free()

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_snap(arr: PackedFloat32Array) -> void:
	var i := 0
	while i + 3 < arr.size():
		var id := int(arr[i])
		if enemies.has(id):
			var e = enemies[id]
			var np := Vector3(arr[i + 1], PLANE, arr[i + 2])
			e.est_vel = (np - e.target_pos) / 0.05
			e.target_pos = np
			if arr[i + 3] < e.hp_frac - 0.001: e.flash()
			e.hp_frac = arr[i + 3]
		i += 4

@rpc("authority", "call_remote", "reliable")
func cl_state(w: int, lp: int, lv: int, st: int, b: String, bt: float, bf: float) -> void:
	wave = w
	loop = lp
	lives = lv
	state = st
	banner = b
	banner_t = bt
	boss_frac = bf

@rpc("authority", "call_remote", "reliable")
func cl_drop(id: int, t: int, pos: Vector3) -> void:
	if drops.has(id): return
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(0, 2.4, 0), Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(-2, 0, 0), Vector3(0, 0, -2), Vector3(0, -2.4, 0)]
	Meshes.piece(st, v, [[0,1,2],[0,2,3],[0,3,4],[0,4,1],[5,2,1],[5,3,2],[5,4,3],[5,1,4]], DROP_COLS[t])
	st.set_material(Meshes.material(true))
	mi.mesh = st.commit()
	mi.position = pos
	add_child(mi)
	drops[id] = {"type": t, "pos": pos, "t": DROP_LIFE, "node": mi}

@rpc("authority", "call_remote", "reliable")
func cl_drop_gone(id: int) -> void:
	if not drops.has(id): return
	var n = drops[id]["node"]
	if n and is_instance_valid(n): n.queue_free()
	drops.erase(id)

## Game over: every peer files its own pilot's score in its local high-score table.
@rpc("authority", "call_remote", "reliable")
func cl_over(entries: Array, wv: int, lp: int) -> void:
	over_t = 9.0
	var me := String(world.local_ship.name) if world.local_ship and is_instance_valid(world.local_ship) else ""
	var cfg := ConfigFile.new()
	cfg.load("user://horde_scores.cfg")
	var table: Array = cfg.get_value(level_name, "top", [])
	for en in entries:
		if str(en[2]) == me and int(en[0]) > 0:
			table.append([int(en[0]), str(en[1]), wv, lp + 1, Time.get_date_string_from_system()])
	table.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	if table.size() > 10: table = table.slice(0, 10)
	cfg.set_value(level_name, "top", table)
	if me != "": cfg.save("user://horde_scores.cfg")
	high_table = table

@rpc("authority", "call_remote", "reliable")
func cl_feed_over() -> void:
	if world.hud: world.hud.push_feed("GAME OVER - %s" % level_name)

func load_table(lvl: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load("user://horde_scores.cfg") != OK: return []
	return cfg.get_value(lvl, "top", [])
