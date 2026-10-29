extends CharacterBody3D
## Player / bot ship with swoopy inertial flight and a transforming mech mode.
## Movement + mech state are owned by the controlling peer; health/ammo/alive by the server.
const Meshes := preload("res://scripts/meshes.gd")
const Weapons := preload("res://scripts/weapons.gd")
const BASE_SPEED := 48.0
const BOOST_SPEED := 105.0
const BRAKE_SPEED := 14.0
const STRAFE := 18.0
const PITCH_RATE := 2.2
const YAW_RATE := 1.6
const ROLL_RATE := 3.2
const GRIP := 2.3          # how fast velocity re-aligns with the nose (lower = more drift)
const DRIFT_GRIP := 0.22
const MECH_SPEED := 11.0
const MECH_TIME := 0.6
const CAM_FLY := Vector3(0, 1.8, 7.0)
const CAM_MECH := Vector3(0, 2.8, 9.5)

var peer_id := 1
var is_bot := false
var pilot_name := "?"
var color := Color.WHITE
var world: Node = null

# replicated (owner)
var net_xform := Transform3D.IDENTITY
var mech := false
var bank := 0.0
var drifting := false
# replicated (server)
var health := 100
var alive := true
var ammo: PackedInt32Array = Weapons.start_ammo()

var weapon := 0
var vel := Vector3.ZERO
var speed_cur := BASE_SPEED
var boost_energy := 100.0
var ang := Vector3.ZERO
var est_vel := Vector3.ZERO
var mech_t := 0.0
var drift_time := 0.0
var _last_pos := Vector3.ZERO
var muzzle_side := 1.0
var cool := {}
var srv_next := {}
var mouse_delta := Vector2.ZERO
var camera: Camera3D = null
var speed_lines: MultiMeshInstance3D = null
var line_mat: StandardMaterial3D
var shake := 0.0
var damage_flash := 0.0
var _last_health := 100
var last_cause := ""
var model: Node3D
var wings: Array = []
var legs: Node3D
var arms: Node3D
var engine: MeshInstance3D
var spray: CPUParticles3D = null
var move_sync: MultiplayerSynchronizer
var state_sync: MultiplayerSynchronizer
# bot brain
var bot_target: Node3D = null
var bot_think := 0.0
var bot_wobble := Vector3.ZERO
var bot_mech_timer := 0.0

func setup(data: Dictionary, w: Node, col: Color) -> void:
	world = w
	name = data["nn"]
	peer_id = data["pid"]
	is_bot = data["bot"]
	pilot_name = data["name"]
	color = col
	transform = data["xf"]
	net_xform = transform
	_last_pos = transform.origin
	vel = -transform.basis.z * BASE_SPEED
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 3
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new(); sh.radius = 1.8
	cs.shape = sh
	add_child(cs)
	_build_model(col)
	move_sync = _make_sync("MoveSync", [".:net_xform", ".:mech", ".:bank", ".:drifting"], SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	state_sync = _make_sync("StateSync", [".:health", ".:alive", ".:ammo"], SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	set_multiplayer_authority(peer_id, true)
	state_sync.set_multiplayer_authority(1)
	# only replicate to peers that have finished building the arena
	move_sync.add_visibility_filter(_vis)
	state_sync.add_visibility_filter(_vis)

func _vis(p: int) -> bool:
	return p == 1 or p in world.ready_peers

func _make_sync(n: String, props: Array, mode: int) -> MultiplayerSynchronizer:
	var s := MultiplayerSynchronizer.new()
	s.name = n
	var c := SceneReplicationConfig.new()
	for prop in props:
		c.add_property(NodePath(prop))
		c.property_set_replication_mode(NodePath(prop), mode)
	s.replication_config = c
	s.root_path = NodePath("..")
	add_child(s)
	return s

func refresh_vis() -> void:
	move_sync.update_visibility()
	state_sync.update_visibility()

func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 1.0
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_model(col: Color) -> void:
	model = Node3D.new()
	add_child(model)
	var body := MeshInstance3D.new()
	body.mesh = Meshes.ship_body(col)
	model.add_child(body)
	for s in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(s * 0.5, 0, 0.5)
		var wm := MeshInstance3D.new()
		wm.mesh = Meshes.ship_wing(col, s)
		hinge.add_child(wm)
		model.add_child(hinge)
		wings.append(hinge)
	engine = MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.8, 0.4, 0.6)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(0.4, 0.8, 1.0)
	bm.material = em
	engine.mesh = bm
	engine.position = Vector3(0, 0.05, 2.1)
	model.add_child(engine)
	# mech parts (hidden in flight)
	var dark := col.darkened(0.5)
	legs = Node3D.new()
	legs.position = Vector3(0, -0.3, 0.6)
	for s in [-1.0, 1.0]:
		_box(legs, Vector3(s * 0.6, -1.0, 0), Vector3(0.45, 2.0, 0.6), dark)
		_box(legs, Vector3(s * 0.6, -2.1, -0.25), Vector3(0.7, 0.3, 1.1), Color(0.3, 0.3, 0.35))
	add_child(legs)
	arms = Node3D.new()
	for s in [-1.0, 1.0]:
		_box(arms, Vector3(s * 1.25, -0.1, -0.6), Vector3(0.55, 0.55, 1.6), col.lightened(0.1))
		_box(arms, Vector3(s * 1.25, -0.1, -1.8), Vector3(0.22, 0.22, 1.4), Color(0.25, 0.25, 0.3))
	add_child(arms)
	legs.visible = false
	arms.visible = false

func _ready() -> void:
	if world.cfg["hazard"] == "water":
		spray = CPUParticles3D.new()
		var pm := BoxMesh.new(); pm.size = Vector3.ONE * 0.6
		pm.material = Meshes.material(true)
		spray.mesh = pm
		spray.amount = 30
		spray.lifetime = 0.7
		spray.local_coords = false
		spray.direction = Vector3.UP
		spray.spread = 35.0
		spray.initial_velocity_min = 6.0
		spray.initial_velocity_max = 14.0
		spray.gravity = Vector3(0, -25, 0)
		spray.color = Color(0.85, 0.95, 1.0)
		spray.emitting = false
		add_child(spray)
	if not is_bot and peer_id == multiplayer.get_unique_id():
		world.local_ship = self
		camera = Camera3D.new()
		camera.top_level = true
		camera.fov = 78.0
		camera.far = 4000.0
		add_child(camera)
		camera.global_transform = global_transform * Transform3D(Basis.IDENTITY, CAM_FLY)
		camera.current = true
		camera.near = 0.05
		_build_cockpit()
		_build_speed_lines()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_speed_lines() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new(); bm.size = Vector3(0.03, 0.03, 3.0)
	line_mat = StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(1, 1, 1, 0)
	bm.material = line_mat
	mm.mesh = bm
	mm.instance_count = 40
	for i in 40:
		var p := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0).normalized() * randf_range(2.0, 6.0)
		p.z = randf_range(-40.0, -2.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
	speed_lines = MultiMeshInstance3D.new()
	speed_lines.multimesh = mm
	camera.add_child(speed_lines)

var cockpit: Node3D
var mech_cockpit: Node3D

func _cockpit_box(parent: Node3D, pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	var mi := _box(parent, pos, size, col)
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Low-poly canopy frame + nose for first person, parented to the camera.
func _build_cockpit() -> void:
	var frame := Color(0.12, 0.12, 0.15)
	cockpit = Node3D.new()
	camera.add_child(cockpit)
	# canopy struts converging forward
	for s in [-1.0, 1.0]:
		_cockpit_box(cockpit, Vector3(s * 0.42, 0.12, -0.55), Vector3(0.04, 0.04, 1.0), frame, Vector3(0.18, -s * 0.38, s * 0.5))
		_cockpit_box(cockpit, Vector3(s * 0.55, -0.15, -0.45), Vector3(0.05, 0.5, 0.05), frame, Vector3(0, 0, -s * 0.35))
	_cockpit_box(cockpit, Vector3(0, 0.3, -0.7), Vector3(0.9, 0.04, 0.05), frame)
	_cockpit_box(cockpit, Vector3(0, 0.33, -0.3), Vector3(0.03, 0.03, 0.8), frame)
	# dashboard + nose
	_cockpit_box(cockpit, Vector3(0, -0.36, -0.55), Vector3(1.1, 0.14, 0.4), Color(0.08, 0.08, 0.1), Vector3(-0.25, 0, 0))
	_cockpit_box(cockpit, Vector3(0, -0.42, -1.4), Vector3(0.35, 0.12, 1.6), color.darkened(0.2), Vector3(-0.08, 0, 0))
	_cockpit_box(cockpit, Vector3(-0.3, -0.3, -0.45), Vector3(0.12, 0.05, 0.08), Color(0.2, 1, 0.4))
	_cockpit_box(cockpit, Vector3(0.3, -0.3, -0.45), Vector3(0.12, 0.05, 0.08), Color(1, 0.5, 0.1))
	# mech torso view: chunky window bars + arm barrels at the bottom corners
	mech_cockpit = Node3D.new()
	camera.add_child(mech_cockpit)
	for s in [-1.0, 1.0]:
		_cockpit_box(mech_cockpit, Vector3(s * 0.62, 0, -0.5), Vector3(0.18, 1.2, 0.1), frame)
		_cockpit_box(mech_cockpit, Vector3(s * 0.55, -0.42, -1.2), Vector3(0.14, 0.14, 1.4), Color(0.25, 0.25, 0.3))
	_cockpit_box(mech_cockpit, Vector3(0, 0.42, -0.5), Vector3(1.4, 0.14, 0.1), frame)
	_cockpit_box(mech_cockpit, Vector3(0, -0.4, -0.5), Vector3(1.4, 0.18, 0.1), frame)
	cockpit.visible = false
	mech_cockpit.visible = false

func is_local() -> bool:
	return camera != null

func add_shake(v: float) -> void:
	if is_local(): shake = min(shake + v, 1.2)

func _unhandled_input(event: InputEvent) -> void:
	if not is_local(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative
	if event.is_action_pressed("camera_toggle"):
		Net.view = (Net.view + 1) % 2
		Net.save_settings()
		return
	if not alive or Net.ui_open: return
	if event.is_action_pressed("mech_toggle"):
		toggle_mech()
	elif event.is_action_pressed("weapon_next"):
		weapon = (weapon + 1) % Weapons.SELECTABLE
	elif event.is_action_pressed("weapon_prev"):
		weapon = (weapon + Weapons.SELECTABLE - 1) % Weapons.SELECTABLE
	else:
		for i in Weapons.SELECTABLE:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				weapon = i

func toggle_mech() -> void:
	if mech_t > 0.0 and mech_t < 1.0: return
	mech = not mech

func transforming() -> bool:
	return mech_t > 0.001 and mech_t < 0.999

func _gather_input() -> Dictionary:
	var pitch := Input.get_axis("pitch_down", "pitch_up")
	var md := mouse_delta * 0.06
	mouse_delta = Vector2.ZERO
	pitch -= md.y
	var yaw := Input.get_axis("yaw_left", "yaw_right") + md.x
	var roll := Input.get_axis("roll_left", "roll_right")
	if Net.ui_open:
		return {"pitch": 0.0, "yaw": 0.0, "roll": 0.0, "sx": 0.0, "sy": 0.0, "fire_p": false, "fire_s": false, "boost": false, "brake": false, "drift": false}
	if (Net.inv_mech_y if mech_t > 0.5 else Net.inv_pitch): pitch = -pitch
	if Net.inv_yaw: yaw = -yaw
	if Net.inv_roll: roll = -roll
	return {
		"pitch": clamp(pitch, -1.5, 1.5),
		"yaw": clamp(yaw, -1.5, 1.5),
		"roll": roll,
		"sx": Input.get_axis("strafe_left", "strafe_right"),
		"sy": Input.get_axis("strafe_down", "strafe_up"),
		"fire_p": Input.is_action_pressed("fire_primary"),
		"fire_s": Input.is_action_pressed("fire_secondary"),
		"boost": Input.is_action_pressed("boost"),
		"brake": Input.is_action_pressed("brake"),
		"drift": Input.is_action_pressed("drift"),
	}

func _physics_process(d: float) -> void:
	for k in cool.keys(): cool[k] -= d
	mech_t = move_toward(mech_t, 1.0 if mech else 0.0, d / MECH_TIME)
	if is_multiplayer_authority():
		if alive:
			var inp := _bot_input(d) if is_bot else _gather_input()
			if mech_t > 0.5: _mech_move(inp, d)
			else: _fly(inp, d)
			if not transforming():
				var pw := Weapons.MECH_GUN if mech else weapon
				if inp["fire_p"]: _try_fire(pw)
				if inp["fire_s"]: _try_fire(Weapons.MISSILE)
		elif is_local():
			mouse_delta = Vector2.ZERO
		net_xform = transform
	else:
		transform = transform.interpolate_with(net_xform, clamp(18.0 * d, 0.0, 1.0))
		if transform.origin.distance_to(net_xform.origin) > 60.0:
			transform = net_xform
	est_vel = ((global_position - _last_pos) / d).limit_length(250.0)
	_last_pos = global_position

func _try_fire(w: int) -> void:
	if cool.get(w, 0.0) > 0.0: return
	if ammo[w] >= 0 and ammo[w] < int(Weapons.LIST[w]["cost"]): return
	cool[w] = Weapons.LIST[w]["cd"]
	if multiplayer.is_server():
		_srv_fire(w)
	else:
		rpc_id(1, "srv_fire", w)

func _fly(inp: Dictionary, d: float) -> void:
	var cfg: Dictionary = world.cfg
	var b := global_transform.basis
	var fwd := -b.z
	# turn rate drops at speed (bigger arcs), tightens when braking
	var spd_frac := clampf((speed_cur - BRAKE_SPEED) / (BOOST_SPEED - BRAKE_SPEED), 0.0, 1.0)
	var turn_k := lerpf(1.45, 0.62, spd_frac)
	var want := Vector3(inp["pitch"] * PITCH_RATE * turn_k, -inp["yaw"] * YAW_RATE * turn_k, -inp["roll"] * ROLL_RATE)
	if cfg["planet"] and absf(inp["roll"]) < 0.15:
		# Ace-Combat style: auto-level, but bank into yaw turns
		var target_bank: float = inp["yaw"] * 0.7
		var err := b.x.y + sin(target_bank)
		want.z += -err * 2.5
	ang = ang.lerp(want, clamp(6.5 * d, 0.0, 1.0))
	rotate_object_local(Vector3.RIGHT, ang.x * d)
	rotate_object_local(Vector3.UP, ang.y * d)
	rotate_object_local(Vector3.BACK, ang.z * d)
	transform = transform.orthonormalized()
	b = global_transform.basis
	fwd = -b.z
	var target := BASE_SPEED
	if inp["boost"] and boost_energy > 1.0:
		target = BOOST_SPEED
		boost_energy = max(0.0, boost_energy - 35.0 * d)
	else:
		boost_energy = min(100.0, boost_energy + 15.0 * d)
		if inp["brake"]: target = BRAKE_SPEED
	# drift: kill grip, slide; release for a mini-boost
	drifting = inp["drift"]
	if drifting:
		drift_time += d
		target = max(speed_cur, BASE_SPEED)
	elif drift_time > 0.0:
		if drift_time > 0.4:
			speed_cur = min(BOOST_SPEED * 1.15, speed_cur + 30.0)
			add_shake(0.15)
		drift_time = 0.0
	speed_cur = move_toward(speed_cur, target, (60.0 if speed_cur > target else 90.0) * d)
	var desired: Vector3 = fwd * speed_cur + b.x * inp["sx"] * STRAFE + b.y * inp["sy"] * STRAFE
	var grip := DRIFT_GRIP if drifting else GRIP
	vel = vel.lerp(desired, 1.0 - exp(-grip * d))
	if cfg["gravity"] > 0.0:
		vel.y -= cfg["gravity"] * d
	_bounds(d)
	velocity = vel
	move_and_slide()
	if get_slide_collision_count() > 0:
		vel = velocity * 0.7
		speed_cur *= 0.7
		add_shake(0.2)
	var slip := b.x.dot(vel) # sideways slide
	bank = lerpf(bank, clampf(-inp["yaw"] * 0.75 - slip * 0.015, -1.2, 1.2), clamp(6.0 * d, 0.0, 1.0))

func _bounds(d: float) -> void:
	var cfg: Dictionary = world.cfg
	var r: float = cfg["radius"]
	var p := global_position
	if cfg["planet"]:
		var hp := Vector2(p.x, p.z)
		if hp.length() > r:
			var push := -hp.normalized() * (hp.length() - r) * 2.0 * d
			vel += Vector3(push.x, 0, push.y)
		if p.y > cfg["ceil"]:
			vel.y -= (p.y - cfg["ceil"]) * 3.0 * d
		if p.y < cfg["hazard_y"] + 1.5:
			vel.y = max(vel.y, 14.0) # bounce off water / plasma
	elif p.length() > r:
		vel += -p.normalized() * (p.length() - r) * 2.0 * d

func _mech_move(inp: Dictionary, d: float) -> void:
	var cfg: Dictionary = world.cfg
	var want := Vector3(inp["pitch"] * 2.4, -inp["yaw"] * 2.6, 0.0)
	var sx: float = inp["sx"] + (inp["roll"] if cfg["planet"] else 0.0)
	if cfg["planet"]:
		want.z = -global_transform.basis.x.y * 4.0 # stay upright
	else:
		want.z = -inp["roll"] * 1.5
	ang = ang.lerp(want, clamp(10.0 * d, 0.0, 1.0))
	rotate_object_local(Vector3.RIGHT, ang.x * d)
	rotate_object_local(Vector3.UP, ang.y * d)
	rotate_object_local(Vector3.BACK, ang.z * d)
	transform = transform.orthonormalized()
	var b := global_transform.basis
	var fb := (1.0 if inp["boost"] else 0.0) - (1.0 if inp["brake"] else 0.0)
	var desired: Vector3 = (b.x * sx + b.y * inp["sy"] - b.z * fb) * MECH_SPEED
	vel = vel.lerp(desired, 1.0 - exp(-3.0 * d))
	speed_cur = 0.0
	boost_energy = min(100.0, boost_energy + 15.0 * d)
	drifting = false
	_bounds(d)
	velocity = vel
	move_and_slide()
	vel = velocity
	bank = lerpf(bank, 0.0, clamp(6.0 * d, 0.0, 1.0))

@rpc("any_peer", "call_remote", "reliable")
func srv_fire(w: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id: return
	_srv_fire(w)

func _srv_fire(w: int) -> void:
	if not alive or w < 0 or w >= Weapons.LIST.size(): return
	if (w == Weapons.MECH_GUN) != mech and w != Weapons.MISSILE: return
	var now := Time.get_ticks_msec()
	if now < srv_next.get(w, 0): return
	var wd: Dictionary = Weapons.LIST[w]
	srv_next[w] = now + int(wd["cd"] * 1000.0 * 0.75)
	if ammo[w] >= 0:
		if ammo[w] < int(wd["cost"]): return
		var a := ammo.duplicate()
		a[w] -= int(wd["cost"])
		ammo = a
	world.server_fire(self, w)

# ---------------------------------------------------------------- server rules
func server_give(w: int) -> void:
	var a := ammo.duplicate()
	var mx: int = Weapons.LIST[w]["max"]
	a[w] = min(mx, a[w] + max(1, mx / 2))
	ammo = a
	health = min(100, health + 20)

func server_damage(amount: float, attacker_nn: String, w := 0, cause := "") -> void:
	if not multiplayer.is_server() or not alive: return
	var mult := 1.0
	if transforming(): mult = 1.6            # vulnerable mid-transform
	elif mech_t >= 0.999: mult = 1.5 if w == 6 else 0.45   # armour, but bombs crack mechs
	health = max(0, health - int(round(amount * mult)))
	if health <= 0:
		alive = false
		world.server_frag(attacker_nn, self, cause)
		get_tree().create_timer(3.0).timeout.connect(_server_respawn)

func _server_respawn() -> void:
	if not is_inside_tree(): return
	var xf: Transform3D = world.random_spawn()
	health = 100
	ammo = Weapons.start_ammo()
	alive = true
	if is_multiplayer_authority():
		_apply_respawn(xf)
	else:
		rpc_id(peer_id, "cl_respawn", xf)

@rpc("any_peer", "call_remote", "reliable")
func cl_respawn(xf: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	_apply_respawn(xf)

func _apply_respawn(xf: Transform3D) -> void:
	transform = xf
	net_xform = xf
	speed_cur = BASE_SPEED
	vel = -xf.basis.z * BASE_SPEED
	boost_energy = 100.0
	ang = Vector3.ZERO
	mech = false
	mech_t = 0.0
	if camera:
		camera.global_transform = global_transform * Transform3D(Basis.IDENTITY, CAM_FLY)

# ---------------------------------------------------------------- visuals
func _process(d: float) -> void:
	visible = alive
	collision_layer = 2 if alive else 0
	if not is_multiplayer_authority():
		mech_t = move_toward(mech_t, 1.0 if mech else 0.0, d / MECH_TIME)
	# transform animation: wings fold up, nose pitches up into a torso, legs/arms extend
	var t := smoothstep(0.0, 1.0, mech_t)
	model.rotation = Vector3(t * 1.15, 0, bank)
	model.position = Vector3(0, t * 0.6 + sin(Time.get_ticks_msec() * 0.004) * 0.15 * t, t * 0.4)
	wings[0].rotation.z = -t * 1.35
	wings[1].rotation.z = t * 1.35
	legs.visible = t > 0.02
	arms.visible = t > 0.02
	legs.scale = Vector3(1, max(t, 0.01), 1)
	arms.scale = Vector3(1, 1, max(t, 0.01))
	var spd := clampf(est_vel.length() / BOOST_SPEED, 0.2, 1.2)
	engine.scale = Vector3(1, 1, (1.0 + spd * 3.0) * (1.0 - t))
	if spray:
		spray.emitting = alive and global_position.y < 10.0 and est_vel.length() > 25.0
		spray.position = Vector3(0, -global_position.y + 0.5, 0)
	if health < _last_health and is_local():
		shake = min(shake + 0.25, 1.2)
		damage_flash = 1.0
	_last_health = health
	damage_flash = max(0.0, damage_flash - d * 3.0)
	if camera: _update_camera(d, t)

func _update_camera(d: float, t: float) -> void:
	var fp := Net.view == 1
	cockpit.visible = fp and alive and t < 0.5
	mech_cockpit.visible = fp and alive and t >= 0.5
	model.visible = not fp
	arms.visible = arms.visible and not fp
	legs.visible = legs.visible and not fp
	if fp:
		# rigid mount; only a little G-lean (bank) and shake keep it lively
		var eye := Vector3(0, 0.55, -0.4).lerp(Vector3(0, 0.9, -0.9), t)
		var lean := Basis(Vector3.BACK, bank * 0.12)
		camera.global_transform = global_transform * Transform3D(lean, eye)
		camera.fov = lerpf(camera.fov, 80.0 + (est_vel.length() - BASE_SPEED) * 0.15 + (5.0 if drifting else 0.0), clamp(5.0 * d, 0.0, 1.0))
		shake = max(0.0, shake - d * 2.0)
		camera.h_offset = randf_range(-1, 1) * shake * 0.12
		camera.v_offset = randf_range(-1, 1) * shake * 0.12
		_speed_lines(d)
		return
	var off := CAM_FLY.lerp(CAM_MECH, t)
	var target := global_transform * Transform3D(Basis.IDENTITY, off)
	# lag: position chases quickly, rotation lags more so the ship swings on screen
	var cp := camera.global_position.lerp(target.origin, 1.0 - exp(-12.0 * d))
	var lean := Basis(target.basis.z, bank * 0.35) * target.basis
	var cb := camera.global_transform.basis.orthonormalized().slerp(lean.orthonormalized(), 1.0 - exp(-6.0 * d))
	camera.global_transform = Transform3D(cb, cp)
	camera.fov = lerpf(camera.fov, 76.0 + (est_vel.length() - BASE_SPEED) * 0.2 + (6.0 if drifting else 0.0), clamp(5.0 * d, 0.0, 1.0))
	shake = max(0.0, shake - d * 2.0)
	camera.h_offset = randf_range(-1, 1) * shake * 0.6
	camera.v_offset = randf_range(-1, 1) * shake * 0.6
	_speed_lines(d)

func _speed_lines(d: float) -> void:
	var s := est_vel.length()
	line_mat.albedo_color.a = clampf((s - 55.0) / 60.0, 0.0, 0.7)
	speed_lines.visible = line_mat.albedo_color.a > 0.02
	if speed_lines.visible:
		var mm := speed_lines.multimesh
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			xf.origin.z += s * d * 0.8
			if xf.origin.z > -1.0: xf.origin.z -= 40.0
			mm.set_instance_transform(i, xf)

# ---------------------------------------------------------------- bot brain
func _bot_input(d: float) -> Dictionary:
	var inp := {"pitch": 0.0, "yaw": 0.0, "roll": 0.0, "sx": 0.0, "sy": 0.0, "fire_p": false, "fire_s": false, "boost": false, "brake": false, "drift": false}
	var cfg: Dictionary = world.cfg
	bot_think -= d
	bot_mech_timer -= d
	var dist := 9999.0
	if bot_target and is_instance_valid(bot_target) and bot_target.alive:
		dist = bot_target.global_position.distance_to(global_position)
	if bot_think <= 0.0:
		bot_think = randf_range(0.4, 0.9)
		bot_wobble = Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1)) * 0.08
		var best_d := INF
		bot_target = null
		for s in world.ships.get_children():
			if s == self or not s.alive: continue
			var dd: float = s.global_position.distance_to(global_position)
			if dd < best_d:
				best_d = dd
				bot_target = s
		# weapon choice
		var opts := [0, 0]
		for w in [1, 2, 3, 5]:
			if ammo[w] > 0: opts.append(w)
		weapon = opts[randi() % opts.size()]
		if bot_target and bot_target.mech and ammo[6] > 0: weapon = 6
		# mech mode now and then when an enemy is close
		if not mech and bot_target and best_d < 180.0 and randf() < 0.08:
			mech = true
			bot_mech_timer = randf_range(3.5, 7.0)
		elif mech and (bot_mech_timer <= 0.0 or health < 30) and not transforming():
			mech = false
	var fwd := -global_transform.basis.z
	var aim := Vector3(-global_position.x, cfg["spawn_min"] + 40.0 - global_position.y, -global_position.z) if cfg["planet"] else -global_position
	if bot_target and is_instance_valid(bot_target) and bot_target.alive:
		aim = bot_target.global_position + bot_target.est_vel * (dist / 300.0) - global_position
		if weapon == 6: aim += Vector3.UP * 25.0 # get above the target to drop bombs
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + vel.normalized() * 60.0 if vel.length() > 5.0 else global_position + fwd * 60.0, 1))
	var blocked := not hit.is_empty()
	if blocked and not mech:
		aim = fwd + hit.normal * 3.0
	if cfg["planet"] and not mech:
		if global_position.y < cfg["hazard_y"] + 30.0 or not space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 30.0, 1)).is_empty():
			aim = aim.normalized() + Vector3.UP * 2.0
	var r: float = cfg["radius"]
	if (Vector2(global_position.x, global_position.z).length() if cfg["planet"] else global_position.length()) > r * 0.95:
		aim = -Vector3(global_position.x, 0, global_position.z) if cfg["planet"] else -global_position
	var loc: Vector3 = global_transform.basis.inverse() * (aim.normalized() + bot_wobble)
	inp["pitch"] = clamp(loc.y * 4.0, -1.0, 1.0)
	inp["yaw"] = clamp(loc.x * 4.0, -1.0, 1.0)
	if loc.z > 0.0 and absf(loc.x) < 0.3 and absf(loc.y) < 0.3:
		inp["pitch"] = 1.0
	if not cfg["planet"]:
		inp["roll"] = clamp(loc.x * 2.0, -1.0, 1.0) * 0.6
	var aligned := -loc.z
	if bot_target and not blocked:
		var burst := (Time.get_ticks_msec() / 600 + get_instance_id()) % 3 != 0
		if weapon == 6:
			var below: Vector3 = bot_target.global_position - global_position
			inp["fire_p"] = below.y < -5.0 and Vector2(below.x, below.z).length() < 25.0
		else:
			inp["fire_p"] = dist < (200.0 if weapon in [1, 2] else 280.0) and aligned > 0.97 and burst
		inp["fire_s"] = dist < 320.0 and dist > 40.0 and aligned > 0.95 and randf() < 0.01
	if mech:
		inp["sx"] = sin(Time.get_ticks_msec() * 0.001 + get_instance_id()) # circle-strafe
	else:
		inp["boost"] = dist > 220.0
		inp["brake"] = dist < 35.0
		inp["drift"] = aligned < 0.3 and dist < 120.0 and randf() < 0.5
	return inp
