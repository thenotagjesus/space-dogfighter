extends Node3D
## Arena + ship spawning + all server-authoritative combat rules.
## Server -> client broadcasts go through bc() to peers that have built the world.
const ShipScript := preload("res://scripts/ship.gd")
const ProjScript := preload("res://scripts/projectile.gd")
const HudScript := preload("res://scripts/hud.gd")
const Meshes := preload("res://scripts/meshes.gd")
const Arenas := preload("res://scripts/arenas.gd")
const Weapons := preload("res://scripts/weapons.gd")
const FX := preload("res://scripts/fx.gd")
const COLORS := [Color(0.9,0.2,0.15), Color(0.2,0.5,1.0), Color(0.95,0.8,0.1), Color(0.3,0.9,0.3), Color(0.8,0.3,0.9), Color(1.0,0.5,0.1), Color(0.9,0.9,0.95), Color(0.1,0.9,0.9)]

var arena_id := 0
var cfg: Dictionary
var ARENA_RADIUS := 600.0
var ships: Node3D
var spawner: MultiplayerSpawner
var local_ship: Node3D = null
var hud: CanvasLayer
var bot_seq := 0
var color_seq := 0
var rocks: Array = []
var pickups: Array = [] # {pos, node, active, t, w}
var ready_peers: Array = []
var hazard_cd := {}
var _dbg_t := 0.0

func _ready() -> void:
	cfg = Arenas.build(self, arena_id)
	ARENA_RADIUS = cfg["radius"]
	_build_pickups()
	ships = Node3D.new()
	ships.name = "Ships"
	add_child(ships)
	spawner = MultiplayerSpawner.new()
	spawner.name = "ShipSpawner"
	spawner.spawn_function = _spawn_ship
	add_child(spawner)
	spawner.spawn_path = spawner.get_path_to(ships)
	hud = HudScript.new()
	hud.world = self
	add_child(hud)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left)

## Call locally and on every ready remote peer.
func bc(m: StringName, args: Array) -> void:
	callv(m, args)
	for p in ready_peers:
		callv("rpc_id", [p, m] + args)

func _build_pickups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + arena_id
	for i in 14:
		var pos: Vector3
		if cfg["planet"]:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * 480.0
			pos = Vector3(cos(a) * d, rng.randf_range(cfg["spawn_min"] - 20.0, cfg["spawn_max"]), sin(a) * d)
		else:
			pos = Vector3(rng.randf_range(-1,1), rng.randf_range(-1,1), rng.randf_range(-1,1)).normalized() * rng.randf_range(60.0, 420.0)
		var w := 1 + (i % 6)
		var mi := MeshInstance3D.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var v := [Vector3(0,2,0), Vector3(1.4,0,0), Vector3(0,0,1.4), Vector3(-1.4,0,0), Vector3(0,0,-1.4), Vector3(0,-2,0)]
		Meshes.piece(st, v, [[0,1,2],[0,2,3],[0,3,4],[0,4,1],[5,2,1],[5,3,2],[5,4,3],[5,1,4]], Weapons.LIST[w]["col"])
		st.set_material(Meshes.material(true))
		mi.mesh = st.commit()
		mi.position = pos
		add_child(mi)
		pickups.append({"pos": pos, "node": mi, "active": true, "t": 0.0, "w": w})

func _process(d: float) -> void:
	for r in rocks:
		r[0].rotation += r[1] * d
	for p in pickups:
		p["node"].rotation.y += d * 2.0
		p["node"].visible = p["active"]
	_dbg_t += d
	if _dbg_t > 2.0 and OS.get_cmdline_user_args().has("--debug-net"):
		_dbg_t = 0.0
		var mechs := 0
		for s in ships.get_children(): if s.mech: mechs += 1
		print("[dbg] peer=%d arena=%s ships=%d mechs=%d scores=%s" % [multiplayer.get_unique_id(), cfg["name"], ships.get_child_count(), mechs, str(Net.scores.values().map(func(x): return "%s:%d" % [x["name"], x["frags"]]))])

func _physics_process(d: float) -> void:
	if not multiplayer.is_server(): return
	# pickups
	for i in pickups.size():
		var p: Dictionary = pickups[i]
		if not p["active"]:
			p["t"] -= d
			if p["t"] <= 0.0: bc("cl_pickup", [i, true])
			continue
		for s in ships.get_children():
			if s.alive and s.global_position.distance_to(p["pos"]) < 7.0:
				s.server_give(p["w"])
				p["t"] = 15.0
				bc("cl_pickup", [i, false])
				break
	# hazards
	for k in hazard_cd.keys(): hazard_cd[k] -= d
	if cfg["hazard"] != "":
		for s in ships.get_children():
			if s.alive and s.global_position.y < cfg["hazard_y"] + 2.0 and hazard_cd.get(s.name, 0.0) <= 0.0:
				hazard_cd[s.name] = 0.4
				s.server_damage(12.0 if cfg["hazard"] == "water" else 15.0, "", 0, "crashed into the sea" if cfg["hazard"] == "water" else "burned up on the star")
	# solar flares
	for i in cfg["flares"].size():
		var f: Dictionary = cfg["flares"][i]
		f["t"] -= d
		if f["t"] <= 0.0:
			var ns: int = (int(f["state"]) + 1) % 3
			f["t"] = [randf_range(4.0, 9.0), 1.3, 2.5][ns]
			bc("cl_flare", [i, ns])
		if f["state"] == 2:
			for s in ships.get_children():
				if s.alive and Vector2(s.global_position.x, s.global_position.z).distance_to(f["pos"]) < f["r"] and hazard_cd.get(String(s.name) + "f", 0.0) <= 0.0:
					hazard_cd[String(s.name) + "f"] = 0.3
					s.server_damage(14.0, "", 0, "was vaporised by a solar flare")

@rpc("authority", "reliable")
func cl_ready(list: Array) -> void:
	ready_peers = list.duplicate()
	for s in ships.get_children(): s.refresh_vis()

@rpc("authority", "reliable")
func cl_pickup(i: int, on: bool) -> void:
	pickups[i]["active"] = on

@rpc("authority", "reliable")
func cl_flare(i: int, state: int) -> void:
	var f: Dictionary = cfg["flares"][i]
	f["state"] = state
	f["mat"].set_shader_parameter("power", [0.0, 0.35, 1.6][state])
	f["node"].scale = Vector3.ONE * (1.4 if state == 2 else 1.0)

func random_spawn() -> Transform3D:
	var pos := Vector3.ZERO
	for attempt in 20:
		if cfg["planet"]:
			var a := randf() * TAU
			var dd := randf_range(150.0, 450.0)
			pos = Vector3(cos(a) * dd, randf_range(cfg["spawn_min"], cfg["spawn_max"]), sin(a) * dd)
		else:
			pos = Vector3(randf_range(-1,1), randf_range(-0.5,0.5), randf_range(-1,1)).normalized() * randf_range(250.0, 400.0)
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new(); sh.radius = 12.0
		q.shape = sh
		q.transform = Transform3D(Basis.IDENTITY, pos)
		q.collision_mask = 3
		if get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			break
	var look := Vector3(0, pos.y, 0) if cfg["planet"] else Vector3.ZERO
	return Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)

# ---------------------------------------------------------------- spawning
func server_begin(bots: int) -> void:
	Net.scores.clear()
	if not OS.get_cmdline_user_args().has("--dedicated"):
		_server_add_ship(1, Net.player_name, false)
	for i in bots:
		_server_add_ship(1, ["Viper","Kestrel","Nomad","Rook","Havoc","Jinx","Mako","Zed"][i % 8], true)

func _server_add_ship(pid: int, pname: String, bot: bool) -> void:
	var nn := ("Bot%d" % bot_seq) if bot else ("P%d" % pid)
	if bot: bot_seq += 1
	if ships.has_node(nn): return
	var data := {"nn": nn, "pid": pid, "bot": bot, "name": pname, "col": color_seq % COLORS.size(), "xf": random_spawn()}
	color_seq += 1
	Net.scores[nn] = {"name": pname + (" [BOT]" if bot else ""), "frags": 0, "deaths": 0}
	spawner.spawn(data)
	_broadcast_scores()
	bc("cl_feed", ["%s joined" % pname])

func _spawn_ship(data: Variant) -> Node:
	var s := ShipScript.new()
	s.setup(data, self, COLORS[data["col"]])
	return s

@rpc("any_peer", "reliable")
func srv_register(pname: String) -> void:
	if not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if id in ready_peers: return
	ready_peers.append(id)
	bc("cl_ready", [ready_peers])
	for i in pickups.size():
		if not pickups[i]["active"]: rpc_id(id, "cl_pickup", i, false)
	_server_add_ship(id, str(pname).substr(0, 16), false)

func _on_peer_left(id: int) -> void:
	ready_peers.erase(id)
	bc("cl_ready", [ready_peers])
	var n := ships.get_node_or_null("P%d" % id)
	if n:
		bc("cl_feed", ["%s left" % n.pilot_name])
		n.queue_free()
	Net.scores.erase("P%d" % id)
	_broadcast_scores()

# ---------------------------------------------------------------- combat (server)
func server_fire(ship: Node3D, w: int) -> void:
	var wd: Dictionary = Weapons.LIST[w]
	ship.muzzle_side = -ship.muzzle_side
	var xf: Transform3D = ship.global_transform
	var b := xf.basis
	var fwd := -b.z
	var origin: Vector3
	if ship.mech:
		origin = xf * Vector3(1.25 * ship.muzzle_side, -0.1, -2.4)
	elif w == 6:
		origin = xf * Vector3(0, -1.2, 0.5)
	else:
		origin = xf * (Vector3(1.0 * ship.muzzle_side, -0.1, -2.2) if wd.get("proj", 0) == 0 else Vector3(0, -0.6, -1.0))
	if wd.get("beam", false):
		var from := xf * Vector3(0, -0.2, -3.0)
		var to: Vector3 = from + fwd * wd["range"]
		var q := PhysicsRayQueryParameters3D.create(from, to, 3, [ship.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			to = hit.position
			if hit.collider.has_method("server_damage"):
				hit.collider.server_damage(wd["dmg"], String(ship.name), w)
		bc("cl_beam", [String(ship.name), from, to])
		return
	var tgt := ""
	if w == Weapons.MISSILE:
		var t = find_lock(ship)
		if t: tgt = String(t.name)
	var n: int = wd["count"]
	for i in n:
		var dir := fwd
		var extra := Vector3.ZERO
		var o := origin
		if wd.has("fan"):
			dir = fwd.rotated(b.y, deg_to_rad(wd["fan"]) * (i - (n - 1) * 0.5))
		if wd.has("jitter"):
			dir = (dir + Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1)) * wd["jitter"]).normalized()
		if wd["proj"] == 2:
			extra = Vector3(PI * i, 0, 0)
		if wd["proj"] == 3:
			o = xf * Vector3((i - 1.5) * 0.7, -0.5, -1.5)
			dir = (fwd + b.x * (i - 1.5) * 0.03).normalized()
		var vel: Vector3 = dir * wd["speed"] + ship.est_vel
		if wd["proj"] == 4:
			vel = ship.est_vel * 0.7 - b.y * 6.0
			extra = Vector3(0, -22.0, 0) if cfg["planet"] else -b.y * 14.0
		bc("cl_proj", [w, o, vel, String(ship.name), tgt, extra])

func find_lock(ship: Node3D) -> Node3D:
	var best: Node3D = null
	var best_dot := cos(deg_to_rad(20.0))
	var fwd: Vector3 = -ship.global_transform.basis.z
	for s in ships.get_children():
		if s == ship or not s.alive: continue
		var to: Vector3 = s.global_position - ship.global_position
		if to.length() > 450.0: continue
		var dt := to.normalized().dot(fwd)
		if dt > best_dot:
			best_dot = dt
			best = s
	return best

@rpc("authority", "reliable")
func cl_proj(w: int, origin: Vector3, vel: Vector3, shooter_nn: String, tgt_nn: String, extra: Vector3) -> void:
	var p := ProjScript.new()
	p.w = w
	p.world = self
	p.auth = multiplayer.is_server()
	p.shooter_nn = shooter_nn
	p.shooter = ships.get_node_or_null(shooter_nn)
	if tgt_nn != "": p.target = ships.get_node_or_null(tgt_nn)
	p.vel = vel
	p.extra = extra
	p.position = origin
	add_child(p)
	if Weapons.LIST[w]["proj"] != 4:
		FX.muzzle(self, origin, Weapons.LIST[w]["col"], 0.5 if Weapons.LIST[w]["proj"] == 0 else 0.9)
	if local_ship and p.shooter == local_ship:
		local_ship.add_shake(0.04 if Weapons.LIST[w]["proj"] in [0, 2] else 0.2)

@rpc("authority", "unreliable")
func cl_beam(shooter_nn: String, a: Vector3, b: Vector3) -> void:
	var s := ships.get_node_or_null(shooter_nn)
	if s: a = s.global_transform * Vector3(0, -0.2, -3.0) # glue beam to the ship visually
	FX.beam(self, a, b, Weapons.LIST[2]["col"])
	if local_ship and s == local_ship: local_ship.add_shake(0.02)

func server_proj_hit(p: Node, collider: Object, pos: Vector3) -> void:
	var wd: Dictionary = Weapons.LIST[p.w]
	if wd.has("splash"):
		server_explode(pos, p.shooter_nn, wd["dmg"], wd["splash"], p.w)
	else:
		if collider and collider.has_method("server_damage"):
			collider.server_damage(wd["dmg"], p.shooter_nn, p.w)
		bc("cl_fx", [0, pos, 1.0])

func server_explode(pos: Vector3, shooter_nn: String, dmg: float, radius: float, w: int) -> void:
	for s in ships.get_children():
		if not s.alive: continue
		var dist: float = s.global_position.distance_to(pos)
		if dist < radius:
			var dd := lerpf(dmg, dmg * 0.25, dist / radius)
			if String(s.name) == shooter_nn: dd *= 0.4
			s.server_damage(dd, shooter_nn, w)
	bc("cl_fx", [1, pos, radius / 12.0])

func server_frag(killer_nn: String, victim: Node3D, cause := "") -> void:
	var vn := String(victim.name)
	if Net.scores.has(vn): Net.scores[vn]["deaths"] += 1
	var text := ""
	if cause != "" and not Net.scores.has(killer_nn):
		text = "%s %s" % [victim.pilot_name, cause]
	elif killer_nn == vn or not Net.scores.has(killer_nn):
		if Net.scores.has(vn): Net.scores[vn]["frags"] -= 1
		text = "%s self-destructed" % victim.pilot_name
	else:
		Net.scores[killer_nn]["frags"] += 1
		text = "%s fragged %s" % [Net.scores[killer_nn]["name"], victim.pilot_name]
	bc("cl_fx", [1, victim.global_position, 2.2])
	bc("cl_feed", [text])
	_broadcast_scores()

func _broadcast_scores() -> void:
	bc("cl_scores", [Net.scores])

@rpc("authority", "unreliable")
func cl_fx(kind: int, pos: Vector3, size: float) -> void:
	if kind == 0:
		FX.spark(self, pos)
	else:
		FX.explosion(self, pos, size)
		if local_ship:
			var dist := local_ship.global_position.distance_to(pos)
			local_ship.add_shake(clamp((1.0 - dist / (60.0 * size)) * 0.5 * size, 0.0, 1.0))

@rpc("authority", "reliable")
func cl_scores(s: Dictionary) -> void:
	Net.scores = s

@rpc("authority", "reliable")
func cl_feed(text: String) -> void:
	print("[feed] ", text)
	if hud: hud.push_feed(text)
