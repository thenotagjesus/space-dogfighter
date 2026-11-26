extends CharacterBody3D
## Player / bot ship with swoopy inertial flight and a transforming mech mode.
## Movement + mech state are owned by the controlling peer; health/ammo/alive by the server.
const Meshes := preload("res://scripts/meshes.gd")
const Weapons := preload("res://scripts/weapons.gd")
const FX := preload("res://scripts/fx.gd")
const BASE_SPEED := 48.0
const BOOST_SPEED := 105.0
const BRAKE_SPEED := 14.0
const STRAFE := 18.0
const PITCH_RATE := 2.2
const YAW_RATE := 1.6
const ROLL_RATE := 3.2
const GRIP := 2.3          # how fast velocity re-aligns with the nose (lower = more drift)
const DRIFT_GRIP := 0.22
const MECH_TIME := 0.6
const CAM_FLY := Vector3(0, 1.8, 7.0)
const CAM_MECH := Vector3(0, 3.6, 11.0)  # higher/further so the head crest clears the tilted nose
# --- mech thruster physics (6DOF) ---
const MECH_THRUST := 48.0     # forward/back/lateral thruster accel (m/s^2)
const MECH_VTHRUST := 44.0    # vertical thruster accel
const MECH_DAMP_THRUST := 1.15  # damping on a commanded axis (cruise ~ 50 m/s at assist 0.78)
const MECH_DAMP_IDLE := 2.15    # vernier assist on a released axis
const MECH_DAMP_NEWTON := 0.22  # almost-free coast (assist blend = 0)
const MECH_ASSIST := 0.78       # 0 = newtonian, 1 = full stop-on-release; the feel dial
const MECH_DAMP_DASH := 0.38    # low drag during a quick-boost / inherit-glide
const MECH_MAX := 130.0
const MECH_GRAV_K := 2.4      # planets pull mechs harder than fighters
const MECH_HOVER := 0.5       # passive hover jets carry this share of the weight
const MECH_PITCH_RATE := 2.8  # rad/s, light torso pitch
const MECH_YAW_RATE := 2.2    # rad/s, heavier yaw around the long axis
const MECH_ANG_RESP := 12.0   # 1/s, exponential tracking of desired ang vel
const MECH_SNAP_RESP := 11.0  # 1/s, dash-cancel aim slerp
const MECH_ROLL_KP := 6.5     # planet auto-upright P
const MECH_ROLL_KD := 2.8     # planet auto-upright D
const MECH_AIM_EXPO := 1.35   # stick expo: fine aim near centre, full rate at the edge
const DASH_IMPULSE := 30.0    # instant m/s added along the dash dir (the "punch")
const DASH_ACCEL := 140.0     # m/s^2 for DASH_BURST seconds after the punch
const DASH_BURST := 0.15
const DASH_COST := 22.0
const DASH_TIME := 0.30       # low-drag window, includes the burst
const IFRAME_TIME := 0.20
const DASH_CD := 0.55         # a beat after the coast so QBs don't chain into a flywheel
const DTAP_WIN := 0.28        # double-tap window (s)
const SLING_K := 1.35         # mech -> fighter mid-dash slingshot multiplier
const SLING_MAX := 160.0
const SRV_IFRAME_MS := 260    # server-side i-frame window per dash (small latency grace)
const SRV_DASH_GAP_MS := 350  # server ignores dashes faster than this (measured between backdated starts)
const SRV_CHARGE_EXPIRE_MS := 8000   # a charge press with no fire after this long is dropped
const SRV_MAX_BACKDATE_MS := 100 # most the server backdates a dash for latency (estimate = ENet rtt/2)
const SRV_PARRY_RTT_CAP_MS := 120  # most the server credits a parrying pilot's press for latency (full RTT)
const PARRY_RANGE_K := 1.3         # parry only against a lunge within 1.3x blade range and the hit cone
const SRV_SPEED_TOL := 1.15        # 15% tolerance on the per-state speed cap for remote ships
const SRV_SPEED_SLACK := 3.0       # metres of jitter slack per check
const SRV_SLING_GRACE_MS := 1500   # after leaving mech, allow slingshot speed this long
const BOOST_REGEN := 15.0     # client and server share this regen rate
# --- energy blade + counter ---
const BLADE_WINDUP := 0.30    # readable tell before the lunge
const BLADE_HIT_TIME := 0.28
const BLADE_CD := 1.35
const BLADE_RANGE := 22.0
const BLADE_COS := 0.766      # ~40 degree cone
const BLADE_DMG := 56.0
const BLADE_LUNGE := 64.0
const RIPOSTE_WINDUP := 0.06
const RIPOSTE_WIN := 0.70
const PARRY_EARLY := 0.12     # seconds before connect
const PARRY_LATE := 0.14      # seconds after connect
const WHIFF_OPEN := 0.40
const STAGGER_TIME := 0.55
const OPEN_DMG := 1.35        # extra damage while open after a whiffed parry
# --- All-range fighter handling (fighter mode only; mech code is untouched) ---
const ALL_RANGE := true       # false = the old swoopy drift handling (_fly_legacy)
const AR_CRUISE := 50.0        # constant cruise speed (m/s)
const AR_BOOST := 100.0
const AR_BRAKE := 26.0
const AR_ACC_BOOST := 90.0     # m/s^2 cruise -> boost (0.55 s)
const AR_ACC_RECOVER := 55.0   # m/s^2 brake -> cruise (0.44 s)
const AR_DEC_BRAKE := 85.0     # m/s^2 cruise -> brake (0.28 s)
const AR_DEC_COAST := 45.0     # m/s^2 boost -> cruise (1.1 s); also bleeds slingshot overspeed
const AR_DEC_OVER := 70.0      # m/s^2 above boost speed
const AR_GRIP := 9.0           # 1/s: velocity tracks the nose (tau 0.11 s), so it carries but never drifts
const AR_PITCH_RATE := 2.0     # rad/s at cruise (115 deg/s)
const AR_YAW_RATE := 2.1       # rad/s at cruise (120 deg/s)
const AR_STICK_EXPO := 1.5
const AR_ANG_RESP := 16.0      # 1/s, exp tracking of the commanded turn rate (direct, tau 62 ms)
const AR_TURN_BRAKE := 1.35    # turn-rate multiplier at brake speed
const AR_TURN_BOOST := 0.78    # turn-rate multiplier at boost speed
const AR_LEVEL_K := 6.0        # 1/s, auto-level of the real (physics) roll after a manoeuvre / knockback
const AR_BANK_AUTO := 0.62     # rad (35.5 deg) of visual bank at full yaw stick
const AR_BANK_HOLD := 1.22     # rad (70 deg) of bank while a bank button is held
const AR_BANK_W := 15.0        # rad/s natural frequency: k = 225, c = 30, zeta = 1 (critically damped)
const AR_HOLD_YAW_MUL := 1.65  # hard-turn multiplier on yaw while banked
const AR_HOLD_YAW_BIAS := 0.80 # yaw stick equivalent added in the bank direction (hold alone = 2.5 rad/s)
const AR_HOLD_YAW_CAP := 1.25  # stick + bank together cap here (4.3 rad/s, 11.5 m radius at cruise)
const AR_BOOST_DRAIN := 30.0   # meter/s while boosting (3.3 s)
const AR_BRAKE_DRAIN := 18.0   # meter/s while braking (5.6 s)
const AR_REGEN := 20.0         # meter/s refill (5 s empty to full)
const AR_REFILL_DELAY := 0.9   # s after the last spend before the refill starts
const AR_REARM := 25.0         # after the meter hits 0, boost and brake stay off until it refills to this
const AR_ROLL_TIME := 0.55     # barrel roll: one 360 (mean 11.4 rad/s, peak 17 rad/s)
const AR_ROLL_TAP_WIN := 0.30  # double-tap window (s)
const AR_ROLL_CD := 1.0        # from the start of the roll
const AR_ROLL_SLIDE := 14.0    # m/s peak sideways slide (about 5 m total)
const AR_DEFLECT_FROM := 0.10  # deflect window as a fraction of the roll
const AR_DEFLECT_TO := 0.80
const AR_LOOP_TIME := 1.25     # somersault: 360 pitch, radius ~10 m at 52 m/s
const AR_LOOP_COST := 25.0
const AR_LOOP_DRIFT := 14.0    # m/s of forward progress held through the loop
const AR_UTURN_A := 0.60       # Immelmann half loop (radius ~10 m, climbs ~20 m)
const AR_UTURN_B := 0.40       # roll-out 180
const AR_UTURN_COST := 20.0
const AR_MAN_SPEED := 52.0     # tangential speed through a scripted manoeuvre
const AR_MAN_CD := 1.1         # s after a loop or U-turn
const AR_MAN_BUFFER := 0.25    # s a manoeuvre press waits for a roll to finish
const AR_IN_RECOVER := 8.0     # 1/s, steering fades back in after a manoeuvre
const AR_CHARGE_TIME := 0.85   # hold the secondary trigger to charge
const AR_LOCK_CONE := 14.0     # deg, lock cone for a tap shot
const AR_LOCK_CONE_FULL := 28.0  # deg, widened at full charge
const AR_LOCK_RANGE := 400.0
const AR_LOCK_RANGE_FULL := 520.0
const MAN_NONE := 0
const MAN_LOOP := 1
const MAN_UTURN := 2
const CAM_AR := Vector3(0, 2.4, 8.0)
const CAM_AR_BOOST := Vector3(0, 2.1, 7.0)
const CAM_AR_BRAKE := Vector3(0, 2.6, 8.8)
const AR_CAM_ROLL := 0.5       # fraction of the visual bank the chase camera rolls with
const AR_FOV := 74.0
const AR_FOV_BOOST := 14.0
const AR_FOV_BRAKE := -5.0
const SP_IDLE := 0
const SP_WINDUP := 1
const SP_LUNGE := 2
const SP_PARRY := 3
const SP_CLASH := 4
const SP_STAGGER := 5
const SP_OPEN := 6

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
var thrust := Vector3.ZERO   # local-space thrust direction (drives flares + lean on every peer)
var dash_seq := 0            # bumps on each dash; sent to the server with srv_dash (not replicated)
var blade_phase := 0         # SP_*; driven by the server, applied on every peer
var blade_seq := 0            # bumps on blade events so remotes can start tells
# replicated (server)
var health := 100
var alive := true
var ammo: PackedInt32Array = Weapons.start_ammo()

var weapon := 0
var loadout: PackedInt32Array = Weapons.default_loadout()
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
# mech movement state (owner side)
var dash_t := 0.0
var dash_cd := 0.0
var dash_burst_t := 0.0
var glide_t := 0.0            # inherited fighter-speed coast; not a combat dash
var dash_dir_w := Vector3.ZERO
var iframe_t := 0.0
var aim_snap_t := 0.0
var dodge_flash := 0.0
var deflect_flash := 0.0
var overdrive_t := 0.0        # Horde OVERDRIVE drop: fire cooldowns halved while > 0
var srv_overdrive_until := 0  # server clock (ms)
var mech_hint_t := 0.0
var blade_t := 0.0
var blade_cd := 0.0
var stagger_t := 0.0
var open_t := 0.0
var riposte_t := 0.0
var blade_riposte := false
var incoming_warn := 0.0
var _blade_btn_prev := false
var _seen_blade_seq := 0
var _bot_defend := 0          # 0 undecided, 1 parry, 2 dodge, 3 eat it
var _bot_skill := 0.4
var _mech_phase := false
# All-range fighter state (owner side)
var ar_man := 0                 # MAN_*: scripted loop / U-turn state machine
var ar_man_t := 0.0
var ar_man_dir := 1.0
var ar_man_cd := 0.0
var ar_fwd0 := Vector3.FORWARD
var ar_roll_t := 0.0            # > 0 while a barrel roll is running
var ar_roll_dir := 1.0
var ar_roll_cd := 0.0
var ar_deflect := false         # deflect window of the barrel roll (hook for the server, see REVIEW)
var ar_buffer := 0              # queued manoeuvre (MAN_*) waiting for a roll to end
var ar_buffer_t := 0.0
var ar_in_gain := 1.0           # steering authority (0 locked .. 1 free)
var ar_idle_t := 0.0            # s since the meter was last spent
var ar_lock := false            # meter ran dry: boost and brake stay off until AR_REARM
var charge_t := 0.0             # secondary trigger charge
var charge_full := false
var lock_tgt: Node3D = null     # client-side lock preview for the HUD
var _ar_bank := 0.0
var _ar_bank_v := 0.0
var _ar_tap_age := [9.0, 9.0]   # [left, right]
var _ar_side_down := [false, false]
var _ar_lock_think := 0.0
var _fire_s_prev := false
var _dash_btn_prev := false
var _dir_prev := [false, false, false, false, false, false]
var _dir_tap := [-9.0, -9.0, -9.0, -9.0, -9.0, -9.0]
# server-side i-frame bookkeeping
var _srv_dash_seq := 0         # last dash counter the server saw from this pilot (replay / jump check)
var srv_iframe_until := 0
var srv_last_dash := -100000   # server clock (ms): backdated start of the last accepted dash
var srv_recent_hits: Array = [] # [[server_ms, hp_lost], ...] last ~100 ms of weapon hits; a late dash can refund them
var _srv_ref_pos := Vector3.ZERO  # speed clamp reference (server copy of a remote ship)
var _srv_ref_ms := 0
var _srv_ref_ok := false
var _srv_last_mech_ms := -100000
var _srv_last_resync := 0
var srv_speed_violations := 0
var _last_dodge_bc := -100000
var srv_boost := 100.0
var _srv_hold_until := 0        # after a resync / respawn: hold the server copy while stale packets drain
var _srv_hold_pos := Vector3.ZERO
var _srv_join_until := 0        # join grace: the cap is lifted to boost speed (still clamped) for the first second
# server-side all-range validation (v0.3.0)
var _srv_roll_seq: int
var _srv_man_seq: int
var srv_last_roll: int = -100000
var srv_deflect_from: int
var srv_deflect_until: int
var srv_man_kind: int
var srv_man_start: int
var srv_man_until: int
var srv_man_ready: int
var _srv_man_p0: Vector3
var _srv_man_check: bool
var _srv_in_boost: bool
var _srv_in_brake: bool
var srv_ar_lock: bool
var _srv_idle: float
var _srv_boost_ms: int = -100000
var _srv_meter_sync_ms: int
var _srv_charge_press_ms: int = -1
var ar_roll_seq := 0
var ar_man_seq := 0
var ar_in_boost := false
var ar_in_brake := false
var srv_next_blade := 0
var srv_blade_from := 0       # expected connect time (msec)
var srv_blade_until := 0      # hit-window end (msec)
var srv_blade_hit := false
var srv_blade_riposte := false
var srv_parry_at := -100000
var srv_parry_pending = null
var srv_riposte_until := 0
var srv_stagger_until := 0
var srv_open_until := 0
var srv_parry_foe: Node3D = null
# mech rig visuals
var rig: Node3D
var head: Node3D
var flares: Array = []   # [MeshInstance pivot, exhaust dir (local)]
var _lean := Vector3.ZERO
var _leg_swing := Vector2.ZERO
var _head_tgt: Node3D = null
var _head_think := 0.0
var blade: MeshInstance3D
var blade_pivot: Node3D
var blade_mat: StandardMaterial3D
var blade_flare: MeshInstance3D
var cockpit_blade: MeshInstance3D
var sfx: AudioStreamPlayer3D
var sfx2: AudioStreamPlayer3D

func setup(data: Dictionary, w: Node, col: Color) -> void:
	world = w
	name = data["nn"]
	peer_id = data["pid"]
	is_bot = data["bot"]
	pilot_name = data["name"]
	color = col
	loadout = Weapons.sanitize_loadout(data.get("loadout", Weapons.default_loadout()))
	weapon = int(loadout[0])
	transform = data["xf"]
	net_xform = transform
	_last_pos = transform.origin
	# speed-clamp reference starts at the server's spawn point: no unclamped seed window on join/reconnect
	_srv_ref_pos = transform.origin
	_srv_ref_ms = Time.get_ticks_msec()
	_srv_ref_ok = true
	_srv_join_until = _srv_ref_ms + 1000
	vel = -transform.basis.z * BASE_SPEED
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 3
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new(); sh.radius = 1.8
	cs.shape = sh
	add_child(cs)
	_build_model(col)
	move_sync = _make_sync("MoveSync", [".:net_xform", ".:mech", ".:bank", ".:drifting", ".:thrust", ".:ar_in_boost", ".:ar_in_brake"], SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
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
	rig = Node3D.new()
	add_child(rig)
	model = Node3D.new()
	rig.add_child(model)
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
	rig.add_child(legs)
	arms = Node3D.new()
	for s in [-1.0, 1.0]:
		_box(arms, Vector3(s * 1.25, -0.1, -0.6), Vector3(0.55, 0.55, 1.6), col.lightened(0.1))
		_box(arms, Vector3(s * 1.25, -0.1, -1.8), Vector3(0.22, 0.22, 1.4), Color(0.25, 0.25, 0.3))
		_box(arms, Vector3(s * 1.4, 0.4, 0.1), Vector3(0.8, 0.5, 0.9), col.darkened(0.25)) # shoulder pod
	_box(arms, Vector3(0, 0.6, 1.2), Vector3(1.2, 0.9, 0.5), dark) # backpack
	rig.add_child(arms)
	# head: block + visor + crest, tracks the target
	head = Node3D.new()
	head.position = Vector3(0, 1.05, 0.05)
	_box(head, Vector3(0, 0.25, 0), Vector3(0.55, 0.5, 0.55), col.lightened(0.3))
	var visor := _box(head, Vector3(0, 0.28, -0.29), Vector3(0.42, 0.1, 0.04), Color(0.3, 1, 0.6))
	visor.material_override = _glow_mat(Color(0.3, 1.0, 0.6), false)
	for s in [-1.0, 1.0]:
		var fin := _box(head, Vector3(s * 0.2, 0.62, -0.25), Vector3(0.06, 0.06, 0.55), Color(1, 0.85, 0.2))
		fin.rotation = Vector3(0, s * 0.5, s * -0.9)
	rig.add_child(head)
	# thruster flares: back (push fwd), feet (push up), shoulders (lateral / brake / push down)
	var hot := Color(1.0, 0.55, 0.15)
	var cool_c := Color(0.45, 0.8, 1.0)
	for s in [-1.0, 1.0]:
		_flare(Vector3(s * 0.4, 0.6, 1.5), Vector3.BACK, hot, 1.4)          # backpack
		_flare(Vector3(s * 0.6, -2.3, 0.0), Vector3.DOWN, hot, 1.2)         # feet
		_flare(Vector3(s * 1.85, 0.4, 0.1), Vector3(s, 0, 0), cool_c, 0.9)  # shoulder sides
		_flare(Vector3(s * 1.4, 0.4, -0.4), Vector3.FORWARD, cool_c, 0.9)  # shoulder fronts (retro)
		_flare(Vector3(s * 1.4, 0.7, 0.1), Vector3.UP, cool_c, 0.8)        # shoulder tops (push down)
	# energy blade: hidden box on the right arm, only shown during windup / lunge / parry
	blade_pivot = Node3D.new()
	blade_pivot.position = Vector3(1.25, -0.1, -2.5)
	arms.add_child(blade_pivot)
	blade = MeshInstance3D.new()
	var sb := BoxMesh.new(); sb.size = Vector3(0.1, 0.1, 3.4)
	blade_mat = _glow_mat(Color(1.0, 0.35, 0.95), true)
	sb.material = blade_mat
	blade.mesh = sb
	blade.position = Vector3(0, 0, -1.7)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade_pivot.add_child(blade)
	blade_flare = MeshInstance3D.new()
	var flm := SphereMesh.new(); flm.radial_segments = 6; flm.rings = 3; flm.radius = 0.18; flm.height = 0.36
	flm.material = _glow_mat(Color(1.6, 0.7, 1.4), true)
	blade_flare.mesh = flm
	blade_flare.position = Vector3(0, 0, 0.05)
	blade_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade_pivot.add_child(blade_flare)
	blade_pivot.visible = false
	legs.visible = false
	arms.visible = false
	head.visible = false

func _glow_mat(c: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

## One exhaust cone. Pivot -Z points along the exhaust; scale.z = flame length.
func _flare(pos: Vector3, exhaust: Vector3, c: Color, size: float) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	var up := Vector3.UP if absf(exhaust.y) < 0.9 else Vector3.BACK
	pivot.basis = Basis.looking_at(exhaust, up)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = 1.0
	cm.top_radius = 0.02
	cm.bottom_radius = 0.22 * size
	cm.radial_segments = 5
	cm.rings = 0
	cm.material = _glow_mat(c)
	mi.mesh = cm
	mi.rotation.x = -PI / 2.0   # cylinder +Y -> pivot -Z (tip away from the nozzle)
	mi.position = Vector3(0, 0, -0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	pivot.scale = Vector3(1, 1, 0.01)
	pivot.visible = false
	rig.add_child(pivot)
	flares.append([pivot, exhaust.normalized(), size])

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
	sfx = AudioStreamPlayer3D.new()
	sfx.max_distance = 220.0
	sfx.unit_size = 8.0
	sfx.bus = &"Master"
	add_child(sfx)
	sfx2 = AudioStreamPlayer3D.new()
	sfx2.max_distance = 220.0
	sfx2.unit_size = 8.0
	sfx2.bus = &"Master"
	add_child(sfx2)
	_bot_skill = 0.28 + float(get_instance_id() % 5) * 0.06
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
	cockpit_blade = MeshInstance3D.new()
	var csb := BoxMesh.new(); csb.size = Vector3(0.05, 0.05, 1.8)
	csb.material = _glow_mat(Color(1.0, 0.35, 0.95), true)
	cockpit_blade.mesh = csb
	cockpit_blade.position = Vector3(0.55, -0.42, -2.1)
	cockpit_blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mech_cockpit.add_child(cockpit_blade)
	cockpit_blade.visible = false
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
		_cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		_cycle_weapon(-1)
	else:
		for i in Weapons.SELECTABLE:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				if Weapons.has_slot(loadout, i):
					weapon = i

func toggle_mech() -> void:
	if mech_t > 0.0 and mech_t < 1.0: return
	mech = not mech

func _cycle_weapon(dir: int) -> void:
	if loadout.size() < 1: return
	var idx := 0
	for i in loadout.size():
		if int(loadout[i]) == weapon:
			idx = i
			break
	weapon = int(loadout[posmod(idx + dir, loadout.size())])

func transforming() -> bool:
	return mech_t > 0.001 and mech_t < 0.999

func _exp_k(k: float, d: float) -> float:
	return 1.0 - exp(-k * d)

func _signed_pow(x: float, p: float) -> float:
	return signf(x) * pow(absf(x), p)

func _gather_input() -> Dictionary:
	var pitch := Input.get_axis("pitch_down", "pitch_up")
	var md := mouse_delta * 0.06
	mouse_delta = Vector2.ZERO
	pitch -= md.y
	var yaw := Input.get_axis("yaw_left", "yaw_right") + md.x
	var roll := Input.get_axis("roll_left", "roll_right")
	if Net.ui_open:
		_dash_btn_prev = false
		_blade_btn_prev = false
		return {"pitch": 0.0, "yaw": 0.0, "roll": 0.0, "sx": 0.0, "sy": 0.0, "fire_p": false, "fire_s": false, "boost": false, "brake": false, "drift": false, "blade": false}
	var dash_btn := Input.is_action_pressed("drift")
	var dash_edge := dash_btn and not _dash_btn_prev
	_dash_btn_prev = dash_btn
	var blade_btn := Input.is_action_pressed("melee")
	var blade_edge := blade_btn and not _blade_btn_prev
	_blade_btn_prev = blade_btn
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
		"dash": dash_edge,   # in mech mode the drift button is the dash button
		"dtap": true,        # players get double-tap dashes; bots set dash_dir instead
		"blade": blade_edge,
	}

func _physics_process(d: float) -> void:
	for k in cool.keys(): cool[k] -= d
	overdrive_t = max(0.0, overdrive_t - d)
	mech_t = move_toward(mech_t, 1.0 if mech else 0.0, d / MECH_TIME)
	dash_t = max(0.0, dash_t - d)
	dash_cd = max(0.0, dash_cd - d)
	dash_burst_t = max(0.0, dash_burst_t - d)
	glide_t = max(0.0, glide_t - d)
	iframe_t = max(0.0, iframe_t - d)
	aim_snap_t = max(0.0, aim_snap_t - d)
	blade_cd = max(0.0, blade_cd - d)
	stagger_t = max(0.0, stagger_t - d)
	open_t = max(0.0, open_t - d)
	riposte_t = max(0.0, riposte_t - d)
	incoming_warn = max(0.0, incoming_warn - d)
	_blade_phase_tick(d)
	if multiplayer.is_server():
		if alive:
			if mech_t > 0.0 or transforming():
				_srv_charge_press_ms = -1   # transforming clears a held charge
			if ALL_RANGE and not is_multiplayer_authority():
				_srv_meter_tick(d)
				_srv_man_end_check()
			else:
				srv_boost = min(100.0, srv_boost + BOOST_REGEN * d)
		_srv_blade_tick()
	if is_multiplayer_authority():
		if alive:
			var inp := _bot_input(d) if is_bot else _gather_input()
			if _td():
				if is_bot:
					inp["pitch"] = 0.0
					inp["sy"] = 0.0
				else:
					_td_input(inp)
			if inp.get("blade", false):
				_blade_pressed()
			var phase := mech_t > 0.5
			if phase != _mech_phase:
				_mech_phase = phase
				if phase: _enter_mech_momentum()
				else: _exit_mech_slingshot()
			if stagger_t > 0.0:
				_stagger_move(d)
			elif phase: _mech_move(inp, d)
			else: _fly(inp, d)
			if _td(): _td_plane_lock()
			if not transforming():
				var pw := Weapons.MECH_GUN if mech else weapon
				if inp["fire_p"]:
					if mech and dash_t > 0.0 and iframe_t <= 0.0: _dash_cancel()
					_try_fire(pw)
				var fire_m: bool = inp["fire_s"]
				if ALL_RANGE and not mech and not is_bot:
					fire_m = _ar_secondary(inp, d)   # tap or hold-to-charge; fires on release
				elif charge_t > 0.0:
					charge_t = 0.0
					charge_full = false
					lock_tgt = null
				if fire_m and Weapons.has_slot(loadout, Weapons.MISSILE):
					_try_fire(Weapons.MISSILE)
		elif is_local():
			mouse_delta = Vector2.ZERO
		net_xform = transform
	else:
		if multiplayer.is_server():
			_srv_speed_clamp()
		transform = transform.interpolate_with(net_xform, _exp_k(18.0, d))
		if transform.origin.distance_to(net_xform.origin) > 60.0:
			transform = net_xform
	est_vel = ((global_position - _last_pos) / d).limit_length(250.0)
	_last_pos = global_position

func _try_fire(w: int) -> void:
	if w != Weapons.MECH_GUN and not Weapons.has_slot(loadout, w): return
	if cool.get(w, 0.0) > 0.0: return
	if ammo[w] >= 0 and ammo[w] < int(Weapons.LIST[w]["cost"]): return
	cool[w] = Weapons.LIST[w]["cd"] * (0.5 if overdrive_t > 0.0 else 1.0)
	if multiplayer.is_server():
		_srv_fire(w)
	else:
		rpc_id(1, "srv_fire", w)

func _fly(inp: Dictionary, d: float) -> void:
	if ALL_RANGE:
		_fly_ar(inp, d)
	else:
		_fly_legacy(inp, d)

func _fly_legacy(inp: Dictionary, d: float) -> void:
	var cfg: Dictionary = world.cfg
	var b := global_transform.basis
	var fwd := -b.z
	# turn rate drops at speed (bigger arcs), tightens when braking
	var spd_frac := clampf((speed_cur - BRAKE_SPEED) / (BOOST_SPEED - BRAKE_SPEED), 0.0, 1.0)
	var turn_k := lerpf(1.45, 0.62, spd_frac)
	var want := Vector3(inp["pitch"] * PITCH_RATE * turn_k, -inp["yaw"] * YAW_RATE * turn_k, -inp["roll"] * ROLL_RATE)
	if cfg["planet"] and absf(inp["roll"]) < 0.15:
		# auto-level like an atmospheric fighter, but bank into yaw turns
		var target_bank: float = inp["yaw"] * 0.7
		var err := b.x.y + sin(target_bank)
		want.z += -err * 2.5
	ang = ang.lerp(want, _exp_k(6.5, d))
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
		boost_energy = min(100.0, boost_energy + BOOST_REGEN * d)
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
	bank = lerpf(bank, clampf(-inp["yaw"] * 0.75 - slip * 0.015, -1.2, 1.2), _exp_k(6.0, d))

# ================================================================ All-range flight
## Exact step of a critically damped spring (zeta = 1). Returns (position, velocity).
## Closed form, so it gives the same answer at any step length.
func _crit_spring(x: float, v: float, target: float, w: float, d: float) -> Vector2:
	var a := x - target
	var bb := v + w * a
	var e := exp(-w * d)
	return Vector2(target + (a + bb * d) * e, (bb - w * (a + bb * d)) * e)

func _ar_reset(bank_now: float) -> void:
	ar_man = MAN_NONE
	ar_man_t = 0.0
	ar_roll_t = 0.0
	ar_deflect = false
	ar_buffer = 0
	ar_in_gain = 1.0
	_ar_bank = bank_now
	_ar_bank_v = 0.0

## Hard-stop any scripted manoeuvre (stagger, transform, collision, respawn).
func _ar_abort() -> void:
	if ar_man != MAN_NONE:
		ar_man = MAN_NONE
		ar_man_cd = AR_MAN_CD
		ar_in_gain = 0.0
	if ar_roll_t > 0.0:
		ar_roll_t = 0.0
		ar_deflect = false

func _ar_turn_mult() -> float:
	if speed_cur < AR_CRUISE:
		return lerpf(AR_TURN_BRAKE, 1.0, clampf((speed_cur - AR_BRAKE) / (AR_CRUISE - AR_BRAKE), 0.0, 1.0))
	return lerpf(1.0, AR_TURN_BOOST, clampf((speed_cur - AR_CRUISE) / (AR_BOOST - AR_CRUISE), 0.0, 1.0))

func _ar_start_man(kind: int, dir: float) -> bool:
	var cost := AR_LOOP_COST if kind == MAN_LOOP else AR_UTURN_COST
	if ar_man != MAN_NONE or ar_man_cd > 0.0 or transforming() or mech or stagger_t > 0.0 or _td(): return false   # no loops off the plane
	if ar_roll_t > 0.0:
		ar_buffer = kind
		ar_buffer_t = AR_MAN_BUFFER
		return false
	if boost_energy < cost: return false
	boost_energy -= cost
	ar_idle_t = 0.0
	ar_man = kind
	ar_man_t = 0.0
	ar_man_dir = dir
	ar_fwd0 = -global_transform.basis.z
	ar_in_gain = 0.0
	add_shake(0.1)
	ar_man_seq += 1
	if multiplayer.is_server():
		_srv_note_man(ar_man_seq, kind, dir)
	else:
		rpc_id(1, "srv_ar_man", ar_man_seq, kind, dir)
	return true

func _ar_end_man() -> void:
	ar_man = MAN_NONE
	ar_man_cd = AR_MAN_CD
	ang = Vector3.ZERO
	vel = -global_transform.basis.z * AR_MAN_SPEED
	speed_cur = AR_MAN_SPEED

## One physics step of a scripted loop or U-turn. Angles are summed exactly, so any step length
## ends on exactly 360 / 180 degrees. Steering is locked; velocity is rebuilt from the nose.
func _ar_man_step(d: float) -> void:
	var dur := AR_LOOP_TIME if ar_man == MAN_LOOP else AR_UTURN_A + AR_UTURN_B
	var step := minf(d, dur - ar_man_t)
	if ar_man == MAN_LOOP:
		rotate_object_local(Vector3.RIGHT, TAU / AR_LOOP_TIME * step)
	else:
		var a := clampf(AR_UTURN_A - ar_man_t, 0.0, step)
		rotate_object_local(Vector3.RIGHT, PI / AR_UTURN_A * a)
		rotate_object_local(Vector3.BACK, ar_man_dir * PI / AR_UTURN_B * (step - a))
	ar_man_t += step
	transform = transform.orthonormalized()
	speed_cur = AR_MAN_SPEED
	vel = -global_transform.basis.z * AR_MAN_SPEED
	if ar_man == MAN_LOOP:
		vel += ar_fwd0 * AR_LOOP_DRIFT
	_bounds(d)
	velocity = vel
	move_and_slide()
	if get_slide_collision_count() > 0:
		vel = velocity * 0.6
		speed_cur *= 0.6
		add_shake(0.25)
		_ar_abort()
		return
	if ar_man_t >= dur - 0.00001:
		_ar_end_man()

func _ar_start_roll(s: float) -> bool:
	if ar_roll_t > 0.0 or ar_roll_cd > 0.0 or ar_man != MAN_NONE or transforming(): return false
	ar_roll_t = 0.0001
	ar_roll_dir = s
	ar_roll_cd = AR_ROLL_CD
	ar_roll_seq += 1
	if multiplayer.is_server():
		_srv_note_roll(ar_roll_seq, s)
	else:
		rpc_id(1, "srv_ar_roll", ar_roll_seq, s)
	return true

## Double-tap of a bank button / right stick = barrel roll; manoeuvre button = loop (U-turn with brake held).
func _ar_fly_input_edges(inp: Dictionary, hold: float, d: float) -> void:
	for i in 2:
		_ar_tap_age[i] = minf(_ar_tap_age[i] + d, 9.0)
	var sides := [-1.0, 1.0]
	for i in 2:
		var s: float = sides[i]
		var amt := hold * s
		if amt > 0.7 and not _ar_side_down[i]:
			_ar_side_down[i] = true
			if _ar_tap_age[i] < AR_ROLL_TAP_WIN and _ar_start_roll(s):
				_ar_tap_age[i] = 9.0
			else:
				_ar_tap_age[i] = 0.0
		elif amt < 0.35:
			_ar_side_down[i] = false
	var br: float = inp.get("ar_roll", 0.0)
	if br != 0.0: _ar_start_roll(signf(br))
	var want_man := 0
	if inp.get("dash", false):
		want_man = MAN_UTURN if inp["brake"] else MAN_LOOP
	var bm: int = inp.get("ar_man", 0)
	if bm != 0: want_man = bm
	if want_man != 0:
		var dir := signf(float(inp["yaw"]))
		if dir == 0.0: dir = 1.0
		_ar_start_man(want_man, dir)

func _fly_ar(inp: Dictionary, d: float) -> void:
	var cfg: Dictionary = world.cfg
	# boost / brake intent goes to the server, which runs its own copy of the meter
	if not multiplayer.is_server() and (bool(inp["boost"]) != ar_in_boost or bool(inp["brake"]) != ar_in_brake):
		ar_in_boost = inp["boost"]
		ar_in_brake = inp["brake"]
		rpc_id(1, "srv_ar_intent", ar_in_boost, ar_in_brake)
	ar_man_cd = maxf(0.0, ar_man_cd - d)
	ar_roll_cd = maxf(0.0, ar_roll_cd - d)
	ar_buffer_t = maxf(0.0, ar_buffer_t - d)
	if ar_buffer_t <= 0.0: ar_buffer = 0
	if mech and (ar_man != MAN_NONE or ar_roll_t > 0.0):
		_ar_abort()
	drifting = false
	drift_time = 0.0
	# bank button: roll axis (Q/E, right stick X) plus A/D; bots only yaw
	var hold := 0.0 if is_bot else clampf(float(inp["roll"]) + float(inp["sx"]), -1.0, 1.0)
	_ar_fly_input_edges(inp, hold, d)
	# a manoeuvre pressed during a roll fires the moment the roll ends
	if ar_buffer != 0 and ar_roll_t <= 0.0 and ar_man == MAN_NONE:
		var kind := ar_buffer
		ar_buffer = 0
		_ar_start_man(kind, 1.0)
	# ---- a scripted manoeuvre owns the ship
	if ar_man != MAN_NONE:
		_ar_man_step(d)
		_ar_bank_follow(0.0, d)
		return
	ar_in_gain += (1.0 - ar_in_gain) * _exp_k(AR_IN_RECOVER, d)
	# ---- steering: direct, expo, scaled by speed
	var pr := float(inp["pitch"]) * ar_in_gain
	var yr := float(inp["yaw"]) * ar_in_gain
	var hold_amt := signf(hold) * smoothstep(0.35, 0.8, absf(hold)) * ar_in_gain
	var yaw_lim := lerpf(1.5, AR_HOLD_YAW_CAP, absf(hold_amt))
	yr = clampf(yr + hold_amt * AR_HOLD_YAW_BIAS, -yaw_lim, yaw_lim)
	var px := _signed_pow(clampf(pr, -1.0, 1.0), AR_STICK_EXPO) + (pr - clampf(pr, -1.0, 1.0))
	var yx := _signed_pow(clampf(yr, -1.0, 1.0), AR_STICK_EXPO) + (yr - clampf(yr, -1.0, 1.0))
	var tm := _ar_turn_mult()
	var hard := lerpf(1.0, AR_HOLD_YAW_MUL, absf(hold_amt))
	var want := Vector3(px * AR_PITCH_RATE * tm, -yx * AR_YAW_RATE * tm * hard, 0.0)
	ang = ang.lerp(want, _exp_k(AR_ANG_RESP, d))
	ang.z = 0.0
	rotate_object_local(Vector3.RIGHT, ang.x * d)
	rotate_object_local(Vector3.UP, ang.y * d)
	# the physics roll only auto-levels (after a manoeuvre or a knock); the bank you see is visual
	var b0 := global_transform.basis
	var roll_err := atan2(b0.x.y, b0.y.y)
	rotate_object_local(Vector3.BACK, -roll_err * _exp_k(AR_LEVEL_K, d))
	transform = transform.orthonormalized()
	var fwd := -global_transform.basis.z
	var bx := global_transform.basis.x
	# ---- speed and the shared boost meter (boost, brake, loop and U-turn all draw on boost_energy)
	var can_use := not ar_lock and boost_energy > 0.0
	var boosting: bool = inp["boost"] and can_use
	var braking: bool = inp["brake"] and can_use and not boosting
	var target := AR_CRUISE
	if boosting:
		target = AR_BOOST
		boost_energy = maxf(0.0, boost_energy - AR_BOOST_DRAIN * d)
		ar_idle_t = 0.0
	elif braking:
		target = AR_BRAKE
		boost_energy = maxf(0.0, boost_energy - AR_BRAKE_DRAIN * d)
		ar_idle_t = 0.0
	else:
		ar_idle_t += d
		if ar_idle_t > AR_REFILL_DELAY:
			boost_energy = minf(100.0, boost_energy + AR_REGEN * d)
	if boost_energy <= 0.0 and (inp["boost"] or inp["brake"]):
		ar_lock = true
	elif ar_lock and boost_energy >= AR_REARM:
		ar_lock = false
	var rate: float
	if speed_cur < target:
		rate = AR_ACC_BOOST if boosting else AR_ACC_RECOVER
	else:
		rate = AR_DEC_BRAKE if braking else (AR_DEC_OVER if speed_cur > AR_BOOST * 1.05 else AR_DEC_COAST)
	speed_cur = move_toward(speed_cur, target, rate * d)
	var desired: Vector3 = fwd * speed_cur
	# ---- barrel roll: spin, deflect window, sideways slide
	var spin := 0.0
	ar_deflect = false
	if ar_roll_t > 0.0:
		ar_roll_t += d
		var u := clampf(ar_roll_t / AR_ROLL_TIME, 0.0, 1.0)
		spin = -ar_roll_dir * TAU * smoothstep(0.0, 1.0, u)
		ar_deflect = u >= AR_DEFLECT_FROM and u <= AR_DEFLECT_TO
		desired += bx * ar_roll_dir * AR_ROLL_SLIDE * sin(PI * u)
		if ar_roll_t >= AR_ROLL_TIME:
			ar_roll_t = 0.0
			spin = 0.0
			ar_deflect = false
	vel = vel.lerp(desired, _exp_k(AR_GRIP, d))
	if cfg["gravity"] > 0.0:
		vel.y -= cfg["gravity"] * d
	_bounds(d)
	velocity = vel
	move_and_slide()
	if get_slide_collision_count() > 0:
		vel = velocity * 0.7
		speed_cur *= 0.7
		add_shake(0.2)
		_ar_abort()
	# ---- auto-bank into the yaw input, critically damped spring-back to level
	var target_bank := -clampf(yr, -1.0, 1.0) * AR_BANK_AUTO
	if absf(hold_amt) > 0.05:
		target_bank = -hold_amt * AR_BANK_HOLD
	_ar_bank_follow(target_bank, d)
	bank += spin

func _ar_bank_follow(target_bank: float, d: float) -> void:
	var s := _crit_spring(_ar_bank, _ar_bank_v, target_bank, AR_BANK_W, d)
	_ar_bank = s.x
	_ar_bank_v = s.y
	bank = _ar_bank

## Secondary trigger: a tap fires on release; holding AR_CHARGE_TIME charges a wider, longer lock.
func _ar_secondary(inp: Dictionary, d: float) -> bool:
	var held: bool = inp["fire_s"]
	var fire := false
	if held and not _fire_s_prev:
		if multiplayer.is_server():
			_srv_charge_press_ms = Time.get_ticks_msec()
		else:
			rpc_id(1, "srv_charge_press")
	if held:
		charge_t += d
		_ar_lock_think -= d
		if _ar_lock_think <= 0.0:
			_ar_lock_think = 0.1
			var prog := clampf(charge_t / AR_CHARGE_TIME, 0.0, 1.0)
			lock_tgt = _ar_pick_lock(lerpf(AR_LOCK_CONE, AR_LOCK_CONE_FULL, prog), lerpf(AR_LOCK_RANGE, AR_LOCK_RANGE_FULL, prog))
	elif _fire_s_prev:
		fire = true
		charge_t = 0.0
		lock_tgt = null
	_fire_s_prev = held
	charge_full = held and charge_t >= AR_CHARGE_TIME
	return fire

func _ar_pick_lock(cone_deg: float, rng: float) -> Node3D:
	var best: Node3D = null
	var best_dot := cos(deg_to_rad(cone_deg))
	var fwd := -global_transform.basis.z
	for s in world.lock_candidates(self):
		var to: Vector3 = s.global_position - global_position
		if to.length() > rng: continue
		var dt := to.normalized().dot(fwd)
		if dt > best_dot:
			best_dot = dt
			best = s
	return best


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
	# --- aim: rate-control with expo; PD auto-upright on planets; exp tracking (frame-rate safe)
	var aim_k := 1.8 if aim_snap_t > 0.0 else 1.0
	var pr := float(inp["pitch"])
	var yr := float(inp["yaw"])
	var px := _signed_pow(clampf(pr, -1.0, 1.0), MECH_AIM_EXPO) + (pr - clampf(pr, -1.0, 1.0))
	var yx := _signed_pow(clampf(yr, -1.0, 1.0), MECH_AIM_EXPO) + (yr - clampf(yr, -1.0, 1.0))
	var want := Vector3(px * MECH_PITCH_RATE * aim_k, -yx * MECH_YAW_RATE * aim_k, 0.0)
	if cfg["planet"]:
		var roll_err := asin(clampf(global_transform.basis.x.y, -1.0, 1.0))
		want.z = -MECH_ROLL_KP * roll_err - MECH_ROLL_KD * ang.z
	ang = ang.lerp(want, _exp_k(MECH_ANG_RESP, d))
	rotate_object_local(Vector3.RIGHT, ang.x * d)
	rotate_object_local(Vector3.UP, ang.y * d)
	rotate_object_local(Vector3.BACK, ang.z * d)
	if aim_snap_t > 0.0:
		var lk = world.find_lock(self)
		if lk and is_instance_valid(lk):
			var to: Vector3 = (lk.global_position - global_position).normalized()
			var up := Vector3.UP if absf(to.y) < 0.95 else global_transform.basis.y
			var tb := Basis.looking_at(to, up)
			global_transform.basis = global_transform.basis.orthonormalized().slerp(tb, _exp_k(MECH_SNAP_RESP, d))
	transform = transform.orthonormalized()
	var b := global_transform.basis
	# --- 6DOF thruster input (local): x = lateral, y = vertical, z = fore/aft
	var fb := (1.0 if inp["boost"] else 0.0) - (1.0 if inp["brake"] else 0.0)
	var tv := Vector3(clampf(inp["sx"] + inp["roll"], -1.0, 1.0), clampf(inp["sy"], -1.0, 1.0), -fb)
	if tv.length() > 1.0: tv = tv.normalized()
	# --- dashes: dash button, double-tapped direction, or a bot's chosen dodge
	var dash_dir := Vector3.ZERO
	if inp.get("dash", false):
		dash_dir = tv if tv.length() > 0.25 else Vector3.FORWARD
	if inp.get("dtap", false):
		var comps := [tv.x > 0.6, tv.x < -0.6, tv.y > 0.6, tv.y < -0.6, tv.z < -0.6, tv.z > 0.6]
		var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
		var now := Time.get_ticks_msec() * 0.001
		for i in 6:
			if comps[i] and not _dir_prev[i]:
				if now - _dir_tap[i] < DTAP_WIN:
					dash_dir = dirs[i]
					_dir_tap[i] = -9.0
				else:
					_dir_tap[i] = now
			_dir_prev[i] = comps[i]
	var bd: Vector3 = inp.get("dash_dir", Vector3.ZERO)
	if bd != Vector3.ZERO: dash_dir = bd
	if dash_dir != Vector3.ZERO and blade_phase != SP_WINDUP and blade_phase != SP_LUNGE:
		_dash(dash_dir)
	if blade_phase == SP_WINDUP:
		tv *= 0.25
	# --- integrate: thrust accel, gravity vs hover jets, per-axis assist/newton damping
	var acc: Vector3 = b * Vector3(tv.x * MECH_THRUST, tv.y * MECH_VTHRUST, tv.z * MECH_THRUST)
	var hover_up := 0.0
	if cfg["gravity"] > 0.0:
		var g: float = cfg["gravity"] * MECH_GRAV_K
		acc.y -= g * (1.0 - MECH_HOVER)
		hover_up = MECH_HOVER * g / MECH_VTHRUST
	# burst phase of a quick-boost: brief high accel along the dash after the impulse
	if dash_burst_t > 0.0 and dash_dir_w.length_squared() > 0.25:
		acc += dash_dir_w * DASH_ACCEL
	vel += acc * d
	var low := 0.0
	if dash_t > 0.0:
		low = 1.0 if dash_t > 0.08 else dash_t / 0.08
	elif glide_t > 0.0:
		low = 1.0 if glide_t > 0.12 else glide_t / 0.12
	var lv: Vector3 = b.inverse() * vel
	var cmd := Vector3(absf(tv.x), absf(tv.y), absf(tv.z))
	for i in 3:
		var idle_or_thrust: float = lerpf(MECH_DAMP_IDLE, MECH_DAMP_THRUST, clampf(cmd[i] / 0.15, 0.0, 1.0))
		var axis_damp: float = lerpf(MECH_DAMP_NEWTON, idle_or_thrust, MECH_ASSIST)
		axis_damp = lerpf(axis_damp, MECH_DAMP_DASH, low)
		lv[i] *= exp(-axis_damp * d)
	vel = b * lv
	vel = vel.limit_length(MECH_MAX)
	# flares: thrust + hover jets, plus a kick while dashing (clamped so inherit-glide cannot overscale)
	var tl := tv + b.inverse() * Vector3(0, hover_up, 0)
	if dash_t > 0.0 and vel.length() > 1.0:
		tl += (b.inverse() * vel.normalized()) * 2.0 * clampf(dash_t / DASH_TIME, 0.0, 1.0)
	thrust = tl
	speed_cur = vel.length()
	boost_energy = min(100.0, boost_energy + BOOST_REGEN * d)
	drifting = false
	_bounds(d)
	velocity = vel
	move_and_slide()
	if get_slide_collision_count() > 0:
		vel = velocity * (0.6 if dash_t > 0.0 else 1.0)
		if dash_t > 0.0: add_shake(0.15)
	else:
		vel = velocity
	bank = lerpf(bank, 0.0, _exp_k(6.0, d))

## Quick-boost: keep momentum, cancel only the opposing component, punch, then a short burst.
func _dash(local_dir: Vector3) -> void:
	if dash_cd > 0.0 or boost_energy < DASH_COST or transforming() or stagger_t > 0.0: return
	if local_dir.length() < 0.001: return
	boost_energy -= DASH_COST
	var wd: Vector3 = (global_transform.basis * local_dir).normalized()
	dash_dir_w = wd
	var along := vel.dot(wd)
	if along < 0.0:
		vel -= wd * along
	vel += wd * DASH_IMPULSE
	vel = vel.limit_length(MECH_MAX)
	dash_t = DASH_TIME
	dash_burst_t = DASH_BURST
	iframe_t = IFRAME_TIME
	dash_cd = DASH_CD
	dash_seq += 1
	add_shake(0.12)
	if multiplayer.is_server():
		_srv_note_dash(dash_seq, local_dir)
	else:
		rpc_id(1, "srv_dash", dash_seq, local_dir)

## Fire during a dash (after the i-frames): retro-burn to kill the slide and snap the torso to the lock.
## Does not touch glide_t, so a fighter→mech inherit-glide is not cancelled by the first shot.
func _dash_cancel() -> void:
	dash_t = 0.0
	dash_burst_t = 0.0
	vel *= 0.45
	aim_snap_t = 0.3

## Fighter -> mech: keep the momentum as a long, low-drag glide instead of a dead stop.
func _enter_mech_momentum() -> void:
	_ar_abort()
	var s := vel.length()
	vel = vel.limit_length(MECH_MAX)
	dash_t = 0.0
	dash_burst_t = 0.0
	if s > 20.0:
		glide_t = clampf(s / 110.0, 0.3, 1.0)
	ang = Vector3.ZERO
	mech_hint_t = 5.0 if is_local() else 0.0

## Mech -> fighter: if you were dashing / gliding / moving fast, slingshot out. Caps vel and speed at SLING_MAX.
func _exit_mech_slingshot() -> void:
	var s := vel.length()
	if dash_t > 0.0 or glide_t > 0.0 or s > 25.0:
		var bonus := 25.0 if dash_t > 0.0 else 0.0
		vel = (vel * SLING_K).limit_length(SLING_MAX)
		speed_cur = clampf(max(s * SLING_K, BASE_SPEED) + bonus, BASE_SPEED, SLING_MAX)
		add_shake(0.25)
	else:
		speed_cur = max(s, BRAKE_SPEED)
	dash_t = 0.0
	dash_burst_t = 0.0
	glide_t = 0.0
	dash_dir_w = Vector3.ZERO
	thrust = Vector3.ZERO
	_ar_reset(bank)

## Per-state speed cap (m/s) for a remote pilot, before tolerance.
func _srv_speed_cap(now: int) -> float:
	if now < _srv_join_until:
		return maxf(MECH_MAX, AR_BOOST)          # join grace: still clamped, at boost speed
	if mech_t > 0.5:
		_srv_last_mech_ms = now
		return MECH_MAX                       # covers cruise, dash peak and the blade lunge
	if now - _srv_last_mech_ms < SRV_SLING_GRACE_MS:
		return SLING_MAX                      # mid-dash slingshot out of mech
	if ALL_RANGE:
		if now < srv_man_until + 200:
			return AR_MAN_SPEED + AR_LOOP_DRIFT   # scripted loop / U-turn path, only for the move's duration
		if now - _srv_boost_ms < 1300:
			return AR_BOOST                       # server-granted boost, plus the coast back to cruise
		return Vector2(AR_CRUISE, AR_ROLL_SLIDE).length()   # cruise plus the barrel-roll side slide
	return BOOST_SPEED * 1.15                 # boost + drift mini-turbo

## Server copy of a remote (client-owned) ship: clamp positions that move faster than the
## current state allows, keep the hit tests on the clamped spot, and resync the owner. No kick.
func _srv_speed_clamp() -> void:
	var now := Time.get_ticks_msec()
	if not alive:
		return   # the reference is re-seeded from the spawn point in _server_respawn
	_srv_plane_check(now)   # top-down arenas: off-plane positions are clamped back and resynced
	var p := net_xform.origin
	var drain := 2 * clampi(_srv_oneway_ms(), 0, 250) + 60
	if now < _srv_hold_until:
		# packets the pilot sent before it saw our correction are still arriving: keep the corrected spot
		net_xform.origin = _srv_hold_pos
		transform.origin = _srv_hold_pos
		_srv_ref_pos = _srv_hold_pos
		_srv_ref_ms = now
		return
	var dt := maxf(0.001, (now - _srv_ref_ms) * 0.001)
	var cap := _srv_speed_cap(now)
	var allowed := cap * SRV_SPEED_TOL * dt + SRV_SPEED_SLACK
	var moved := p.distance_to(_srv_ref_pos)
	if moved > allowed:
		var fixed := _srv_ref_pos + (p - _srv_ref_pos).normalized() * allowed
		net_xform.origin = fixed
		transform.origin = fixed
		srv_speed_violations += 1
		if OS.get_cmdline_user_args().has("--debug-net"):
			print("[net] speed clamp ", name, " moved=", snappedf(moved, 0.1), " allowed=", snappedf(allowed, 0.1), " cap=", cap)
		# hold the corrected spot on every violation; only the RPC is rate-limited
		_srv_hold_until = now + drain
		_srv_hold_pos = fixed
		if now - _srv_last_resync > 250:
			_srv_last_resync = now
			rpc_id(peer_id, "cl_resync", Transform3D(net_xform.basis, fixed))
		p = fixed
	# measure over a 250 ms window, not per packet, so the jitter slack can't be stacked tick after tick
	if dt >= 0.25:
		_srv_ref_pos = p
		_srv_ref_ms = now

## Server correction after a speed violation: snap the pilot back and bleed off the extra speed.
@rpc("any_peer", "call_remote", "reliable")
func cl_resync(xf: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	transform = xf
	net_xform = xf
	vel = vel.limit_length(BASE_SPEED)
	speed_cur = minf(speed_cur, BASE_SPEED)
	_ar_abort()
	dash_t = 0.0
	dash_burst_t = 0.0
	glide_t = 0.0

## One-way latency estimate (ms) for this pilot: half the RTT ENet measures at the server.
## 0 for the host's own ship and bots (they dash on the server clock already).
func _srv_oneway_ms() -> int:
	var mp := multiplayer.multiplayer_peer
	if peer_id == 1 or not (mp is ENetMultiplayerPeer): return 0
	var pp := (mp as ENetMultiplayerPeer).get_peer(peer_id)
	if pp == null: return 0
	return int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) / 2

## Dash notice from the pilot. Reliable + ordered: it can't be lost, and later dashes can't overtake it.
@rpc("any_peer", "call_remote", "reliable")
func srv_dash(seq: int, local_dir: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id: return
	_srv_note_dash(seq, local_dir)

## Server-side dash validation. Movement is pilot-owned, so the server validates the claim (counter, rate,
## boost, state) and backdates the i-frame window by the one-way latency so it matches what the pilot saw.
## No client-supplied timestamp is trusted: the only client input is the counter and a direction.
func _srv_note_dash(seq: int, local_dir: Vector3) -> void:
	if seq <= _srv_dash_seq: return   # replayed / stale counter: drop silently
	var jump := seq != _srv_dash_seq + 1
	_srv_dash_seq = seq               # resync even when rejecting (an honest client bumps it once per dash)
	var now := Time.get_ticks_msec()
	var start := now - clampi(_srv_oneway_ms(), 0, SRV_MAX_BACKDATE_MS)
	# rate limit on backdated starts; the backdate is capped so the long-run rate stays <= 1 per SRV_DASH_GAP_MS
	var ok := start - srv_last_dash >= SRV_DASH_GAP_MS and mech_t > 0.5 and alive and srv_boost >= DASH_COST and stagger_t <= 0.0
	ok = ok and not jump and local_dir.is_finite() and local_dir.length() > 0.2 and local_dir.length() < 1.5
	if not ok:
		if OS.get_cmdline_user_args().has("--debug-net"):
			print("[net] dash reject ", name, " boost=", snappedf(srv_boost, 0.1), " gap=", start - srv_last_dash, " jump=", jump)
		if is_multiplayer_authority():
			_reject_dash()
		else:
			rpc_id(peer_id, "cl_reject_dash")
		return
	srv_boost -= DASH_COST
	srv_iframe_until = start + SRV_IFRAME_MS
	srv_last_dash = start
	# give back weapon hits that landed after the pilot's dash but before we heard about it (lethal hits stay)
	var back := 0
	for h in srv_recent_hits:
		if h[0] >= start: back += h[1]
	srv_recent_hits.clear()
	if back > 0:
		health = mini(100, health + back)
		world.bc("cl_dodge", [String(name)])
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] dash grant ", name, " boost=", snappedf(srv_boost, 0.1))

func _reject_dash() -> void:
	dash_t = 0.0
	dash_burst_t = 0.0
	iframe_t = 0.0
	dash_dir_w = Vector3.ZERO
	vel *= 0.45

@rpc("any_peer", "call_remote", "reliable")
func cl_reject_dash() -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	_reject_dash()

# ---------------------------------------------------------------- all-range server checks (v0.3.0)

@rpc("any_peer", "call_remote", "reliable")
func srv_ar_intent(b: bool, k: bool) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id: return
	_srv_in_boost = b
	_srv_in_brake = k

func _srv_meter_tick(d: float) -> void:
	if not multiplayer.is_server(): return
	if mech_t > 0.5:
		srv_boost = min(100, srv_boost + BOOST_REGEN * d)
		return
	
	# intent comes from the reliable notice or the MoveSync flag (which rides with the positions)
	var wb: bool = _srv_in_boost or ar_in_boost
	var wk: bool = (_srv_in_brake or ar_in_brake) and not wb
	var can = not srv_ar_lock and srv_boost > 0
	
	if (wb or wk) and can:
		srv_boost = max(0, srv_boost - (AR_BOOST_DRAIN if wb else AR_BRAKE_DRAIN) * d)
		_srv_idle = 0
		if wb: _srv_boost_ms = Time.get_ticks_msec()
	else:
		_srv_idle += d
		if _srv_idle >= AR_REFILL_DELAY:
			srv_boost = min(100, srv_boost + AR_REGEN * d)
	
	if srv_boost <= 0 and (wb or wk) and not srv_ar_lock:
		srv_ar_lock = true
		_srv_send_meter(true)
	elif srv_ar_lock and srv_boost >= AR_REARM:
		srv_ar_lock = false
		_srv_send_meter(true)
	
	if Time.get_ticks_msec() - _srv_meter_sync_ms >= 1000:
		_srv_send_meter(false)

func _srv_send_meter(force: bool) -> void:
	if not force and Time.get_ticks_msec() - _srv_meter_sync_ms < 250: return
	if Time.get_ticks_msec() < _srv_join_until: return   # both sides start at 100; an unreliable sync could beat the spawn
	_srv_meter_sync_ms = Time.get_ticks_msec()
	if not is_multiplayer_authority():
		rpc_id(peer_id, "cl_ar_meter", srv_boost, srv_ar_lock)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func cl_ar_meter(v: float, lk: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	boost_energy = min(boost_energy, v + 2.0)
	ar_lock = ar_lock or lk
	if not lk and v >= AR_REARM:
		ar_lock = false

@rpc("any_peer", "call_remote", "reliable")
func srv_ar_roll(seq: int, dir: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id: return
	_srv_note_roll(seq, dir)

func _srv_note_roll(seq: int, dir: float) -> void:
	if seq <= _srv_roll_seq: return   # replay
	var jump := seq != _srv_roll_seq + 1
	_srv_roll_seq = seq
	var now := Time.get_ticks_msec()
	var start := now - clampi(_srv_oneway_ms(), 0, SRV_MAX_BACKDATE_MS)
	var ok := start - srv_last_roll >= int(AR_ROLL_CD * 1000) - 40 and alive and mech_t <= 0.5 and not transforming() and now >= srv_man_until and absf(dir) == 1.0 and not jump
	if is_multiplayer_authority():
		start = now
		ok = alive and mech_t <= 0.5 and not transforming() and absf(dir) == 1.0 and not jump
	
	if not ok:
		if OS.get_cmdline_user_args().has("--debug-net"):
			print("[net] roll reject ", name, " gap=", start - srv_last_roll, " jump=", jump)
		if is_multiplayer_authority(): _reject_roll()
		else: rpc_id(peer_id, "cl_reject_roll")
		return
	
	srv_last_roll = start
	srv_deflect_from = start + int(AR_ROLL_TIME * AR_DEFLECT_FROM * 1000)
	srv_deflect_until = start + int(AR_ROLL_TIME * AR_DEFLECT_TO * 1000)
	var refund := 0
	var keep := []
	for h in srv_recent_hits:
		if int(h[0]) >= srv_deflect_from and h.size() > 2 and _is_deflectable(int(h[2])):
			refund += int(h[1])
		else:
			keep.append(h)
	srv_recent_hits = keep
	
	if refund > 0:
		health = min(100, health + refund)
		world.bc("cl_deflect", [String(name)])
	
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] roll grant ", name, " start=", start, " deflect=", srv_deflect_from, "..", srv_deflect_until, " oneway=", _srv_oneway_ms())

func srv_deflecting(now_ms: int) -> bool:
	return now_ms >= srv_deflect_from and now_ms < srv_deflect_until

func _reject_roll() -> void:
	ar_roll_t = 0.0
	ar_deflect = false

@rpc("any_peer", "call_remote", "reliable")
func cl_reject_roll() -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	_reject_roll()

@rpc("any_peer", "call_remote", "reliable")
func srv_ar_man(seq: int, kind: int, dir: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id: return
	_srv_note_man(seq, kind, dir)

func _srv_note_man(seq: int, kind: int, dir: float) -> void:
	if seq <= _srv_man_seq: return   # replay
	var jump := seq != _srv_man_seq + 1
	_srv_man_seq = seq
	var now := Time.get_ticks_msec()
	var start := now - clampi(_srv_oneway_ms(), 0, SRV_MAX_BACKDATE_MS)
	var cost: float = AR_LOOP_COST if kind == MAN_LOOP else (AR_UTURN_COST if kind == MAN_UTURN else -1.0)
	var dur: float = AR_LOOP_TIME if kind == MAN_LOOP else (AR_UTURN_A + AR_UTURN_B if kind == MAN_UTURN else 0.0)
	var ok := alive and mech_t <= 0.5 and not transforming() and stagger_t <= 0 and not _td() and start >= srv_man_ready - 40 and cost >= 0.0 and srv_boost >= cost and not jump
	if is_multiplayer_authority():
		start = now
		ok = alive and mech_t <= 0.5 and not transforming() and stagger_t <= 0 and cost >= 0 and not jump
	
	if not ok:
		if OS.get_cmdline_user_args().has("--debug-net"):
			print("[net] man reject ", name, " kind=", kind, " boost=", snappedf(srv_boost, 0.1), " jump=", jump)
		if is_multiplayer_authority(): _reject_man(srv_boost)
		else: rpc_id(peer_id, "cl_reject_man", srv_boost)
		return
	
	if not is_multiplayer_authority():
		srv_boost -= cost
	
	_srv_idle = 0
	srv_man_kind = kind
	srv_man_start = start
	srv_man_until = start + int(dur * 1000)
	srv_man_ready = srv_man_until + int(AR_MAN_CD * 1000)
	_srv_man_p0 = net_xform.origin
	_srv_man_check = true
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] man grant ", name, " kind=", kind, " boost=", snappedf(srv_boost, 0.1))

func _reject_man(meter: float) -> void:
	if ar_man != 0:
		ar_man = 0
		ar_man_cd = AR_MAN_CD
		ang = Vector3.ZERO
		ar_in_gain = 0.0
	boost_energy = meter

@rpc("any_peer", "call_remote", "reliable")
func cl_reject_man(meter: float) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	_reject_man(meter)

func _srv_man_end_check() -> void:
	if not _srv_man_check: return
	var now := Time.get_ticks_msec()
	if now >= srv_man_until + 150:
		_srv_man_check = false
		var allowed := (AR_MAN_SPEED + AR_LOOP_DRIFT) * 1.15 * ((srv_man_until - srv_man_start + 150 + SRV_MAX_BACKDATE_MS) / 1000.0) + 10.0
		if net_xform.origin.distance_to(_srv_man_p0) > allowed:
			net_xform.origin = _srv_man_p0 + _srv_man_p0.direction_to(net_xform.origin) * allowed
			transform.origin = net_xform.origin
			srv_speed_violations += 1
			_srv_hold_until = now + 2 * clampi(_srv_oneway_ms(), 0, 250) + 60
			_srv_hold_pos = net_xform.origin
			if now - _srv_last_resync > 250:
				_srv_last_resync = now
				rpc_id(peer_id, "cl_resync", Transform3D(net_xform.basis, net_xform.origin))
			_srv_ref_pos = net_xform.origin
			_srv_ref_ms = now

@rpc("any_peer", "call_remote", "reliable")
func srv_charge_press() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id: return
	_srv_charge_press_ms = Time.get_ticks_msec()

func _srv_take_charge() -> float:
	if _srv_charge_press_ms < 0: return 0.0
	if Time.get_ticks_msec() - _srv_charge_press_ms > SRV_CHARGE_EXPIRE_MS:
		_srv_charge_press_ms = -1   # stale press (no fire followed): a tap shot
		return 0.0
	var progress := clampf((Time.get_ticks_msec() - _srv_charge_press_ms) / 1000.0 / AR_CHARGE_TIME, 0.0, 1.0)
	_srv_charge_press_ms = -1
	return progress

func _is_deflectable(w: int) -> bool:
	return w >= 0 and w < Weapons.LIST.size() and not Weapons.LIST[w].has("splash")

@rpc("any_peer", "call_remote", "reliable")
func srv_fire(w: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id: return
	_srv_fire(w)

func _srv_fire(w: int) -> void:
	if not alive or w < 0 or w >= Weapons.LIST.size(): return
	if (w == Weapons.MECH_GUN) != mech and w != Weapons.MISSILE: return
	if w != Weapons.MECH_GUN and not Weapons.has_slot(loadout, w): return
	var now := Time.get_ticks_msec()
	if now < srv_next.get(w, 0): return
	var wd: Dictionary = Weapons.LIST[w]
	srv_next[w] = now + int(wd["cd"] * 1000.0 * 0.75 * (0.5 if now < srv_overdrive_until else 1.0))
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

## Horde OVERDRIVE pickup (server): halves fire cooldowns for sec seconds, on both clocks.
func give_overdrive(sec: float) -> void:
	if not multiplayer.is_server(): return
	srv_overdrive_until = Time.get_ticks_msec() + int(sec * 1000.0)
	if is_multiplayer_authority():
		overdrive_t = sec
	else:
		rpc_id(peer_id, "cl_overdrive", sec)

@rpc("any_peer", "call_remote", "reliable")
func cl_overdrive(sec: float) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	overdrive_t = sec

func server_damage(amount: float, attacker_nn: String, w := 0, cause := "") -> void:
	if not multiplayer.is_server() or not alive: return
	if world.horde and attacker_nn != "" and not attacker_nn.begins_with("#"):
		return   # Horde is co-op: no friendly fire (pilots, their splash and blades)
	var now_ms := Time.get_ticks_msec()
	if attacker_nn != "" and now_ms < srv_iframe_until:
		if now_ms - _last_dodge_bc > 200:
			_last_dodge_bc = now_ms
			world.bc("cl_dodge", [String(name)])
		return   # dash i-frames: weapon hits and blade lunges whiff (environment hazards still hurt)
	var mult := 1.0
	if now_ms < srv_open_until:
		mult *= OPEN_DMG
	if transforming(): mult = 1.6            # vulnerable mid-transform
	elif mech_t >= 0.999: mult = 1.5 if w == 6 else 0.45   # armour, but bombs crack mechs
	var hp_before := health
	health = max(0, health - int(round(amount * mult)))
	if attacker_nn != "" and health > 0:
		srv_recent_hits.append([now_ms, hp_before - health, w])
		while srv_recent_hits.size() > 0 and now_ms - int(srv_recent_hits[0][0]) > SRV_MAX_BACKDATE_MS:
			srv_recent_hits.pop_front()
	if health <= 0:
		alive = false
		_srv_charge_press_ms = -1   # death clears a held charge
		world.server_frag(attacker_nn, self, cause)
		get_tree().create_timer(3.0).timeout.connect(_server_respawn)

func _server_respawn() -> void:
	if not is_inside_tree(): return
	var xf: Transform3D = world.random_spawn()
	health = 100
	ammo = Weapons.start_ammo()
	alive = true
	srv_boost = 100.0
	srv_iframe_until = 0
	srv_recent_hits.clear()
	srv_deflect_from = 0
	srv_deflect_until = 0
	srv_man_until = 0
	srv_man_ready = 0
	_srv_man_check = false
	srv_ar_lock = false
	_srv_idle = 0.0
	_srv_charge_press_ms = -1
	# speed-clamp reference jumps to the spawn point so the respawn teleport isn't a violation
	_srv_ref_pos = xf.origin
	_srv_ref_ms = Time.get_ticks_msec()
	_srv_ref_ok = true
	_srv_hold_until = _srv_ref_ms + 2 * clampi(_srv_oneway_ms(), 0, 250) + 60
	_srv_hold_pos = xf.origin
	srv_blade_until = 0
	srv_next_blade = 0
	srv_riposte_until = 0
	srv_stagger_until = 0
	srv_open_until = 0
	srv_parry_pending = null
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
	_mech_phase = false
	dash_t = 0.0
	dash_cd = 0.0
	iframe_t = 0.0
	aim_snap_t = 0.0
	thrust = Vector3.ZERO
	dash_burst_t = 0.0
	glide_t = 0.0
	dash_dir_w = Vector3.ZERO
	blade_phase = SP_IDLE
	blade_t = 0.0
	blade_cd = 0.0
	stagger_t = 0.0
	open_t = 0.0
	riposte_t = 0.0
	_ar_reset(0.0)
	ar_idle_t = 0.0
	ar_lock = false
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
	head.visible = t > 0.6
	_mech_visuals(d, t)
	_blade_visuals(d, t)
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
	dodge_flash = max(0.0, dodge_flash - d * 2.5)
	deflect_flash = max(0.0, deflect_flash - d * 2.5)
	mech_hint_t = max(0.0, mech_hint_t - d)
	if camera: _update_camera(d, t)

## Mech body language: lean into thrust/dashes, legs trail momentum, head tracks the target, flares fire.
func _mech_visuals(d: float, t: float) -> void:
	var k := clampf(t * 2.0 - 1.0, 0.0, 1.0)   # 0 until halfway through the transform
	var th := thrust if k > 0.0 else Vector3.ZERO
	# whole-mech lean: pitch into fore/aft thrust, roll into lateral thrust; dashes (|th|>1) lean hard
	var lean_t := Vector3(clampf(th.z * 0.22, -0.6, 0.6), 0.0, clampf(-th.x * 0.25, -0.65, 0.65)) * k
	_lean = _lean.lerp(lean_t, _exp_k(8.0, d))
	rig.rotation = _lean
	# legs swing opposite to the momentum (local velocity), like they're being dragged along
	var lv: Vector3 = global_transform.basis.inverse() * est_vel
	var sw := Vector2(clampf(lv.z * 0.014, -0.8, 0.8), clampf(-lv.x * 0.014, -0.7, 0.7)) * k
	_leg_swing = _leg_swing.lerp(sw, _exp_k(5.0, d))
	legs.rotation = Vector3(_leg_swing.x, 0, _leg_swing.y)
	# head (and a bit of torso twist) track the nearest enemy in front
	_head_think -= d
	if _head_think <= 0.0 and k > 0.0:
		_head_think = 0.25
		_head_tgt = null
		var best := 450.0
		for o in world.ships.get_children():
			if o == self or not o.alive: continue
			var to: Vector3 = o.global_position - global_position
			var dd := to.length()
			if dd < best and (-global_transform.basis.z).dot(to / max(dd, 0.01)) > 0.1:
				best = dd
				_head_tgt = o
	var hy := 0.0
	var hp := 0.0
	if _head_tgt and is_instance_valid(_head_tgt) and k > 0.0:
		var ld: Vector3 = (rig.global_transform.basis.inverse() * (_head_tgt.global_position - global_position)).normalized()
		hy = clampf(atan2(-ld.x, -ld.z), -1.1, 1.1)
		hp = clampf(asin(clampf(ld.y, -1.0, 1.0)), -0.7, 0.7)
	head.rotation = head.rotation.lerp(Vector3(hp, hy, 0), _exp_k(10.0, d))
	model.rotation.y = head.rotation.y * 0.3
	# flares: each nozzle burns in proportion to the thrust opposite its exhaust direction
	var fl := 0.85 + randf() * 0.3
	for f in flares:
		var pivot: Node3D = f[0]
		var e: Vector3 = f[1]
		var inten := maxf(0.0, -th.dot(e)) * k
		pivot.visible = inten > 0.05 and alive
		if pivot.visible:
			pivot.scale = Vector3(1, 1, clampf(inten, 0.0, 3.0) * 1.6 * f[2] * fl + 0.2)

func _update_camera(d: float, t: float) -> void:
	if _td():
		cockpit.visible = false
		mech_cockpit.visible = false
		rig.visible = true
		_td_camera(d)
		return
	var fp := Net.view == 1
	cockpit.visible = fp and alive and t < 0.5
	mech_cockpit.visible = fp and alive and t >= 0.5
	rig.visible = not fp
	arms.visible = arms.visible and not fp
	legs.visible = legs.visible and not fp
	if fp:
		# rigid mount; only a little G-lean (bank) and shake keep it lively
		var eye := Vector3(0, 0.55, -0.4).lerp(Vector3(0, 0.9, -0.9), t)
		var lean := Basis(Vector3.BACK, bank * 0.12)
		camera.global_transform = global_transform * Transform3D(lean, eye)
		camera.fov = lerpf(camera.fov, 80.0 + (est_vel.length() - BASE_SPEED) * 0.15 + (5.0 if drifting else 0.0), _exp_k(5.0, d))
		shake = max(0.0, shake - d * 2.0)
		camera.h_offset = randf_range(-1, 1) * shake * 0.12
		camera.v_offset = randf_range(-1, 1) * shake * 0.12
		_speed_lines(d)
		return
	var allr := ALL_RANGE
	var bf := clampf((speed_cur - AR_CRUISE) / (AR_BOOST - AR_CRUISE), 0.0, 1.0)
	var kf := clampf((AR_CRUISE - speed_cur) / (AR_CRUISE - AR_BRAKE), 0.0, 1.0)
	var fly_off := CAM_FLY
	var fly_pos_k := 12.0
	var fly_rot_k := 6.0
	var fly_fov := 76.0 + (est_vel.length() - BASE_SPEED) * 0.2 + (6.0 if drifting else 0.0)
	var roll_cam := bank * 0.35
	if allr:
		# the ship pulls away on boost (camera lags more, sits closer, FOV kicks) and tucks in on the brake
		fly_off = CAM_AR.lerp(CAM_AR_BOOST, bf).lerp(CAM_AR_BRAKE, kf)
		fly_pos_k = 13.0 - 2.5 * bf + 3.0 * kf
		fly_rot_k = 9.0 - 1.5 * bf + 2.0 * kf
		fly_fov = AR_FOV + AR_FOV_BOOST * bf + AR_FOV_BRAKE * kf
		roll_cam = _ar_bank * AR_CAM_ROLL   # follows the bank, never the barrel-roll spin
	roll_cam = lerpf(roll_cam, bank * 0.35, t)
	var off := fly_off.lerp(CAM_MECH, t)
	var target := global_transform * Transform3D(Basis.IDENTITY, off)
	# lag: tighter in mech so a quick-boost stays on screen
	var pos_k := lerpf(fly_pos_k, 16.5, t)
	var rot_k := lerpf(fly_rot_k, 10.5, t)
	var cp := camera.global_position.lerp(target.origin, 1.0 - exp(-pos_k * d))
	var lean := Basis(target.basis.z, roll_cam) * target.basis
	var cb := camera.global_transform.basis.orthonormalized().slerp(lean.orthonormalized(), 1.0 - exp(-rot_k * d))
	camera.global_transform = Transform3D(cb, cp)
	camera.fov = lerpf(camera.fov, lerpf(fly_fov, 76.0 + (est_vel.length() - BASE_SPEED) * 0.2, t), _exp_k(5.0, d))
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
	var inp := {"pitch": 0.0, "yaw": 0.0, "roll": 0.0, "sx": 0.0, "sy": 0.0, "fire_p": false, "fire_s": false, "boost": false, "brake": false, "drift": false, "blade": false}
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
		for s in world.lock_candidates(self):
			var dd: float = s.global_position.distance_to(global_position)
			if dd < best_d:
				best_d = dd
				bot_target = s
		# weapon choice from this bot's 2-slot loadout
		var opts: Array = []
		for w in loadout:
			if ammo[w] != 0: opts.append(int(w))
		if opts.is_empty():
			opts.append(int(loadout[0]))
		weapon = opts[randi() % opts.size()]
		if bot_target and bot_target.mech and Weapons.has_slot(loadout, 6) and ammo[6] > 0:
			weapon = 6
		# mech mode now and then when an enemy is close
		if not mech and bot_target and best_d < 180.0 and randf() < 0.08:
			mech = true
			bot_mech_timer = randf_range(3.5, 7.0)
		elif mech and (bot_mech_timer <= 0.0 or health < 30 or (bot_mech_timer < 1.5 and dash_t > 0.1)) and not transforming():
			mech = false   # prefers to bail out mid-dash for the slingshot
	var fwd := -global_transform.basis.z
	var aim := Vector3(-global_position.x, cfg["spawn_min"] + 40.0 - global_position.y, -global_position.z) if cfg["planet"] else -global_position
	if bot_target and is_instance_valid(bot_target) and bot_target.alive:
		aim = bot_target.global_position + bot_target.est_vel * (dist / 300.0) - global_position
		if weapon == 6 and not _td(): aim += Vector3.UP * 25.0 # get above the target to drop bombs
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + vel.normalized() * 60.0 if vel.length() > 5.0 else global_position + fwd * 60.0, 1))
	var blocked := not hit.is_empty()
	if blocked and not mech:
		aim = fwd + hit.normal * 3.0
	if cfg["planet"] and not mech and not cfg.get("topdown", false):
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
			if _td(): inp["fire_p"] = dist < 45.0   # top-down: the bomb is a mine, drop it in their path
		else:
			inp["fire_p"] = dist < (200.0 if weapon in [1, 2] else 280.0) and aligned > (0.9 if world.horde else 0.97) and burst
		inp["fire_s"] = dist < 320.0 and dist > 40.0 and aligned > 0.95 and randf() < 0.01
	if mech:
		_bot_mech_thrust(inp, dist, cfg)
	else:
		inp["boost"] = dist > 220.0
		inp["brake"] = dist < 35.0
		inp["drift"] = aligned < 0.3 and dist < 120.0 and randf() < 0.5
		if ALL_RANGE:
			# All-range bots: U-turn on a target that is behind and close, loop out of a close head-on
			inp["drift"] = false
			inp["roll"] = 0.0
			if aligned < -0.4 and dist < 140.0 and boost_energy > AR_UTURN_COST + 10.0 and randf() < 0.02:
				inp["ar_man"] = MAN_UTURN
			elif dist < 60.0 and aligned > 0.8 and boost_energy > AR_LOOP_COST + 10.0 and randf() < 0.0015:
				inp["ar_man"] = MAN_LOOP
			# barrel roll when someone close is pointing their guns at us
			if ar_roll_cd <= 0.0 and randf() < 0.04:
				for o in world.ships.get_children():
					if o == self or not o.alive or o.mech: continue
					var to_me: Vector3 = global_position - o.global_position
					if to_me.length() < 220.0 and (-o.global_transform.basis.z).dot(to_me.normalized()) > 0.985:
						inp["ar_roll"] = 1.0 if randf() < 0.5 else -1.0
						break
	return inp

## Bot mech piloting: hold a fighting range with fore/aft thrust, circle-strafe, fight gravity,
## and quick-step out of the line of fire.
func _bot_mech_thrust(inp: Dictionary, dist: float, cfg: Dictionary) -> void:
	var tms := Time.get_ticks_msec() * 0.001
	var seed_f := float(get_instance_id() % 997)
	inp["boost"] = dist > 110.0
	inp["brake"] = dist < 55.0
	inp["sx"] = sin(tms * 0.8 + seed_f)                # circle-strafe, changes direction smoothly
	var b := global_transform.basis
	if cfg["planet"]:
		var want_y: float = cfg["spawn_min"] + 30.0
		if bot_target and is_instance_valid(bot_target): want_y = bot_target.global_position.y + 8.0
		want_y = max(want_y, cfg["hazard_y"] + 28.0)
		var ground := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 18.0, 1))
		if not ground.is_empty(): want_y = max(want_y, global_position.y + 10.0)
		# thrust needed to hover + PD toward the wanted height (in world Y, mapped through the local up axis)
		var g: float = cfg["gravity"] * MECH_GRAV_K * (1.0 - MECH_HOVER) / MECH_VTHRUST
		var up_cmd := g + (want_y - global_position.y) * 0.05 - vel.y * 0.08
		inp["sy"] = clampf(up_cmd * b.y.y, -1.0, 1.0)
	else:
		inp["sy"] = sin(tms * 0.55 + seed_f * 1.7) * 0.6
	# dodge: target is pointing at us -> quick-step sideways / up
	if bot_target and is_instance_valid(bot_target) and dist < 220.0 and dash_cd <= 0.0 and boost_energy > DASH_COST + 10.0:
		var their_fwd: Vector3 = -bot_target.global_transform.basis.z
		var to_me: Vector3 = (global_position - bot_target.global_position).normalized()
		var side := 1.0 if randf() < 0.5 else -1.0
		if their_fwd.dot(to_me) > 0.95 and randf() < 0.08:
			inp["dash_dir"] = Vector3(side, 0.35 if randf() < 0.3 else 0.0, 0.0)
		elif dist > 160.0 and randf() < 0.01:
			inp["dash_dir"] = Vector3.FORWARD   # close the gap
		elif randf() < 0.006:
			inp["dash_dir"] = Vector3(side, 0.0, 0.0)   # unpredictable quick-step
	# blade: parry or dodge an incoming lunge, otherwise strike at close range
	var incoming: Node = _incoming_lunge()
	if incoming == null:
		_bot_defend = 0
		if bot_target and is_instance_valid(bot_target) and dist < BLADE_RANGE * 0.85 and blade_cd <= 0.0 and stagger_t <= 0.0:
			var to_t: Vector3 = (bot_target.global_position - global_position).normalized()
			if (-global_transform.basis.z).dot(to_t) > 0.85 and randf() < 0.04:
				inp["blade"] = true
	else:
		if _bot_defend == 0:
			var r := randf()
			if r < _bot_skill:
				_bot_defend = 1
			elif r < _bot_skill + 0.25:
				_bot_defend = 2
			else:
				_bot_defend = 3
		var connect_in := 0.0
		if incoming.blade_phase == SP_WINDUP:
			connect_in = incoming.blade_t
		if _bot_defend == 1 and stagger_t <= 0.0:
			# press in the parry window (a little early so the server sees it)
			if incoming.blade_phase == SP_LUNGE or connect_in <= PARRY_EARLY + 0.02:
				inp["blade"] = true
				_bot_defend = 3
		elif _bot_defend == 2 and dash_cd <= 0.0 and boost_energy > DASH_COST:
			if incoming.blade_phase == SP_LUNGE or connect_in <= 0.16:
				var side2 := 1.0 if randf() < 0.5 else -1.0
				inp["dash_dir"] = Vector3(side2, 0.2, 0.0)
				_bot_defend = 3

## Brief control loss after a successful parry: damp speed, ignore stick input.
func _stagger_move(d: float) -> void:
	_ar_abort()
	vel *= exp(-4.5 * d)
	speed_cur = vel.length()
	thrust = Vector3.ZERO
	_bounds(d)
	velocity = vel
	move_and_slide()
	vel = velocity
	bank = lerpf(bank, 0.0, clamp(6.0 * d, 0.0, 1.0))

func _play_sfx(kind: String, player: AudioStreamPlayer3D = null) -> void:
	var p := player if player else sfx
	if p == null: return
	p.stream = FX.sound(kind)
	p.play()

## Advance local windup → lunge visuals / owner velocity. Server starts the hit window.
func _blade_phase_tick(d: float) -> void:
	if blade_seq != _seen_blade_seq:
		# remote (or late) event: _apply already ran via cl_blade; this is a safety net from replication
		_seen_blade_seq = blade_seq
	if blade_phase == SP_WINDUP or blade_phase == SP_LUNGE or blade_phase == SP_PARRY or blade_phase == SP_CLASH:
		blade_t = max(0.0, blade_t - d)
		if blade_t <= 0.0:
			if blade_phase == SP_WINDUP:
				_begin_lunge_local()
			elif blade_phase == SP_LUNGE or blade_phase == SP_PARRY or blade_phase == SP_CLASH:
				if blade_phase == SP_LUNGE and multiplayer.is_server():
					_srv_end_lunge()
				else:
					blade_phase = SP_IDLE

func _begin_lunge_local() -> void:
	blade_phase = SP_LUNGE
	blade_t = BLADE_HIT_TIME
	_play_sfx("slash", sfx2)
	add_shake(0.16)
	if is_multiplayer_authority() and stagger_t <= 0.0 and alive:
		var dir := -global_transform.basis.z
		var lk = srv_parry_foe if blade_riposte and srv_parry_foe and is_instance_valid(srv_parry_foe) else world.find_lock(self)
		if lk and is_instance_valid(lk):
			dir = (lk.global_position - global_position).normalized()
		vel = vel * 0.35 + dir * BLADE_LUNGE
	if multiplayer.is_server():
		_srv_begin_hit_window()

func _blade_pressed() -> void:
	if not alive or mech_t < 0.5 or transforming() or stagger_t > 0.0:
		return
	if multiplayer.is_server():
		_srv_blade_button()
	else:
		rpc_id(1, "srv_blade")
		# predict: parry if we can already see a lunge coming, else start a windup
		if riposte_t > 0.0:
			_apply_blade_event(SP_WINDUP, "r")
		elif _incoming_lunge() != null:
			pass  # wait for the server to confirm parry or whiff
		elif blade_cd <= 0.0 and blade_phase == SP_IDLE:
			_apply_blade_event(SP_WINDUP, "")

@rpc("any_peer", "call_remote", "reliable")
func srv_blade() -> void:
	if not multiplayer.is_server(): return
	var sid := multiplayer.get_remote_sender_id()
	if sid != 0 and sid != peer_id: return
	_srv_blade_button()

func _srv_blade_button() -> void:
	if not alive or mech_t < 0.5 or transforming(): return
	var now := Time.get_ticks_msec()
	if now < srv_stagger_until: return
	if now < srv_riposte_until:
		_srv_start_windup(true)
		return
	var incoming: Node = _incoming_lunge()
	if incoming and not _parry_reachable(incoming):
		incoming = null   # too far / outside the hit cone: this press is an attack, not a parry
	if incoming:
		# credit the parrying pilot's press for their latency (server-measured, capped); keep `now` for cooldowns
		var press := now - clampi(2 * _srv_oneway_ms(), 0, SRV_PARRY_RTT_CAP_MS)
		srv_parry_at = press
		var connect: int = incoming.srv_blade_from
		var early := int(PARRY_EARLY * 1000.0)
		var late := int(PARRY_LATE * 1000.0)
		if connect <= 0:
			_srv_whiff()
			return
		if press < connect - early:
			_srv_whiff()  # jumped the tell
			return
		if press > connect + late:
			_srv_whiff()
			return
		if press >= connect or incoming.blade_phase == SP_LUNGE:
			_srv_resolve_parry(incoming)
		else:
			srv_parry_pending = incoming
			blade_phase = SP_PARRY
			blade_t = (connect - now) * 0.001 + 0.12
			world.bc("cl_blade", [String(name), SP_PARRY, String(incoming.name)])
		return
	if now < srv_next_blade: return
	_srv_start_windup(false)

## Parry only counts against a lunge that could actually connect: within PARRY_RANGE_K x blade range
## and inside the attacker's hit cone (same test as the slash).
func _parry_reachable(attacker: Node) -> bool:
	var to: Vector3 = global_position - attacker.global_position
	var dist := to.length()
	if dist > BLADE_RANGE * PARRY_RANGE_K or dist < 0.01: return false
	return (to / dist).dot(-attacker.global_transform.basis.z) >= BLADE_COS

func _srv_start_windup(riposte: bool) -> void:
	var now := Time.get_ticks_msec()
	var wind: float = RIPOSTE_WINDUP if riposte else BLADE_WINDUP
	srv_blade_riposte = riposte
	srv_blade_hit = false
	srv_iframe_until = 0   # attacking ends your own i-frames (no invulnerable riposte)
	srv_blade_from = now + int(wind * 1000.0)
	srv_blade_until = 0
	srv_next_blade = now + int(BLADE_CD * 1000.0)
	srv_riposte_until = 0
	blade_phase = SP_WINDUP
	blade_t = wind
	blade_riposte = riposte
	world.bc("cl_blade", [String(name), SP_WINDUP, "r" if riposte else ""])
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] blade windup ", name, " riposte=", riposte)

func _srv_begin_hit_window() -> void:
	var now := Time.get_ticks_msec()
	# connect time is "now" if windup already ran; keep the pre-announced time if we're on time
	if srv_blade_from <= 0 or abs(now - srv_blade_from) > 80:
		srv_blade_from = now
	srv_blade_until = now + int(BLADE_HIT_TIME * 1000.0)
	srv_blade_hit = false
	blade_phase = SP_LUNGE
	# pending parries that already sat in the early window resolve on the first tick
	_srv_blade_tick()

func _srv_end_lunge() -> void:
	srv_blade_until = 0
	if blade_phase == SP_LUNGE:
		blade_phase = SP_IDLE
		world.bc("cl_blade", [String(name), SP_IDLE, ""])

func _srv_blade_tick() -> void:
	if not multiplayer.is_server(): return
	var now := Time.get_ticks_msec()
	if srv_blade_until <= 0 or now > srv_blade_until:
		return
	if blade_phase != SP_LUNGE:
		return
	# honour a pending parry at connect
	for s in world.ships.get_children():
		if s == self or not s.alive: continue
		if s.srv_parry_pending == self:
			var connect := srv_blade_from
			if now >= connect and now <= connect + int(PARRY_LATE * 1000.0):
				s._srv_resolve_parry(self)
				return
	if srv_blade_hit:
		return
	var fwd := -global_transform.basis.z
	# mutual clash: both lunging into each other
	for s in world.ships.get_children():
		if s == self or not s.alive: continue
		if s.blade_phase != SP_LUNGE or s.srv_blade_until <= now: continue
		var to: Vector3 = s.global_position - global_position
		var dist := to.length()
		if dist > BLADE_RANGE or dist < 0.01: continue
		var n := to / dist
		if n.dot(fwd) < BLADE_COS: continue
		if n.dot(s.global_transform.basis.z) * -1.0 < BLADE_COS and (-s.global_transform.basis.z).dot(-n) < BLADE_COS:
			# still close enough for a clash if they're also in our cone
			pass
		if (-s.global_transform.basis.z).dot(-n) >= BLADE_COS * 0.7:
			_srv_mutual_clash(s)
			return
	for s in world.ships.get_children():
		if s == self or not s.alive: continue
		var to: Vector3 = s.global_position - global_position
		var dist := to.length()
		if dist > BLADE_RANGE or dist < 0.01: continue
		if (to / dist).dot(fwd) < BLADE_COS: continue
		# timed parry (press already recorded, even without pending pose)
		if s.srv_parry_at > 0 and abs(s.srv_parry_at - srv_blade_from) <= int(maxf(PARRY_EARLY, PARRY_LATE) * 1000.0) + 40:
			if s.srv_parry_at >= srv_blade_from - int(PARRY_EARLY * 1000.0) and s.srv_parry_at <= srv_blade_from + int(PARRY_LATE * 1000.0):
				s._srv_resolve_parry(self)
				return
		# evade: dash i-frames overlapping the hit moment
		if Time.get_ticks_msec() < s.srv_iframe_until:
			srv_blade_hit = true
			s.server_damage(0.0, String(name), 0)  # goes through the iframe branch and broadcasts DODGE!
			# server_damage returns without hurting; force the dodge broadcast if 0 dmg is skipped...
			# actually server_damage with amount 0 still hits the iframe early-return. Good.
			if OS.get_cmdline_user_args().has("--debug-net"):
				print("[net] blade evaded ", name, " vs ", s.name)
			return
		s.server_damage(BLADE_DMG, String(name), 0)
		srv_blade_hit = true
		world.bc("cl_fx", [0, s.global_position, 1.0])
		if OS.get_cmdline_user_args().has("--debug-net"):
			print("[net] blade hit ", name, " -> ", s.name, " hp=", s.health)
		return
	if world.horde:
		for e in world.horde.enemy_list():
			var to_e: Vector3 = e.global_position - global_position
			var de := to_e.length()
			if de > BLADE_RANGE + e.r or de < 0.01: continue
			if (to_e / de).dot(fwd) < BLADE_COS: continue
			srv_blade_hit = true
			e.server_damage(BLADE_DMG * 1.5, String(name), 0)
			world.bc("cl_fx", [0, e.global_position, 1.0])
			return

func _srv_resolve_parry(attacker: Node) -> void:
	if attacker == null or not is_instance_valid(attacker): return
	var now := Time.get_ticks_msec()
	attacker.srv_blade_until = 0
	attacker.srv_blade_hit = true
	attacker.srv_iframe_until = 0
	attacker.srv_stagger_until = now + int(STAGGER_TIME * 1000.0)
	attacker.srv_parry_pending = null
	srv_parry_pending = null
	srv_parry_at = -100000
	srv_parry_foe = attacker
	srv_riposte_until = now + int(RIPOSTE_WIN * 1000.0)
	srv_open_until = 0
	var mid: Vector3 = (global_position + attacker.global_position) * 0.5
	world.bc("cl_fx", [2, mid, 1.0])
	world.bc("cl_blade", [String(attacker.name), SP_STAGGER, String(name)])
	world.bc("cl_blade", [String(name), SP_CLASH, String(attacker.name)])
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] parry ", name, " vs ", attacker.name)

func _srv_mutual_clash(other: Node) -> void:
	var now := Time.get_ticks_msec()
	for s in [self, other]:
		s.srv_blade_until = 0
		s.srv_blade_hit = true
		s.srv_iframe_until = 0
		s.srv_stagger_until = now + int(STAGGER_TIME * 0.7 * 1000.0)
		s.srv_riposte_until = 0
		s.srv_parry_pending = null
	var mid: Vector3 = (global_position + other.global_position) * 0.5
	world.bc("cl_fx", [2, mid, 1.0])
	world.bc("cl_blade", [String(name), SP_STAGGER, String(other.name)])
	world.bc("cl_blade", [String(other.name), SP_STAGGER, String(name)])
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] mutual clash ", name, " vs ", other.name)

func _srv_whiff() -> void:
	var now := Time.get_ticks_msec()
	srv_parry_pending = null
	srv_parry_at = -100000
	srv_next_blade = now + int(BLADE_CD * 1000.0)
	srv_open_until = now + int(WHIFF_OPEN * 1000.0)
	world.bc("cl_blade", [String(name), SP_OPEN, ""])
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] parry whiff ", name)

## Used by the server and by bots / client prediction to see a lunge coming at us.
func _incoming_lunge() -> Node:
	if world == null: return null
	for s in world.ships.get_children():
		if s == self or not s.alive: continue
		if s.blade_phase != SP_WINDUP and s.blade_phase != SP_LUNGE: continue
		var to: Vector3 = global_position - s.global_position
		if to.length() > BLADE_RANGE * 2.2 or to.length() < 0.01: continue
		var fwd: Vector3 = -s.global_transform.basis.z
		if to.normalized().dot(fwd) >= BLADE_COS * 0.65:
			return s
	return null

func apply_blade_event(phase: int, extra: String) -> void:
	_apply_blade_event(phase, extra)

func _apply_blade_event(phase: int, extra: String) -> void:
	blade_seq += 1
	_seen_blade_seq = blade_seq
	blade_phase = phase
	blade_riposte = extra == "r"
	match phase:
		SP_WINDUP:
			blade_t = RIPOSTE_WINDUP if blade_riposte else BLADE_WINDUP
			blade_cd = BLADE_CD
			riposte_t = 0.0
			iframe_t = 0.0   # matches the server: attacking ends i-frames
			_play_sfx("windup")
			add_shake(0.06)
		SP_LUNGE:
			blade_t = BLADE_HIT_TIME
			_play_sfx("slash", sfx2)
		SP_PARRY:
			blade_t = 0.25
			_play_sfx("windup", sfx2)
		SP_CLASH:
			blade_t = 0.35
			riposte_t = RIPOSTE_WIN
			open_t = 0.0
			_play_sfx("clash")
			add_shake(0.28)
		SP_STAGGER:
			blade_t = 0.2
			stagger_t = STAGGER_TIME
			dash_t = 0.0
			iframe_t = 0.0
			vel *= 0.35
			_play_sfx("clash")
			add_shake(0.3)
		SP_OPEN:
			blade_t = 0.15
			open_t = WHIFF_OPEN
			blade_cd = BLADE_CD
			_play_sfx("whiff")
		SP_IDLE:
			blade_t = 0.0
		_:
			blade_t = 0.0

func _blade_visuals(_d: float, t: float) -> void:
	if blade_pivot == null: return
	var show := alive and t > 0.5 and blade_phase != SP_IDLE and (blade_t > 0.0 or blade_phase == SP_WINDUP or blade_phase == SP_LUNGE)
	if open_t > 0.0 and blade_phase == SP_OPEN:
		show = alive and t > 0.5
	blade_pivot.visible = show
	if cockpit_blade:
		cockpit_blade.visible = show and Net.view == 1
	if not show:
		return
	var pulse := 1.0
	var length := 1.0
	var tint := Color(1.0, 0.35, 0.95)
	match blade_phase:
		SP_WINDUP:
			var u := 1.0 - clampf(blade_t / max(0.001, (RIPOSTE_WINDUP if blade_riposte else BLADE_WINDUP)), 0.0, 1.0)
			length = lerpf(0.08, 1.0, u)
			pulse = 0.7 + 1.4 * u + 0.35 * sin(Time.get_ticks_msec() * 0.04)
			tint = Color(1.0, 0.55, 1.0)
		SP_LUNGE:
			length = 1.05
			pulse = 1.3
			blade_pivot.rotation_degrees.x = sin((1.0 - blade_t / BLADE_HIT_TIME) * PI) * -35.0
		SP_PARRY, SP_CLASH:
			length = 1.0
			pulse = 1.6 if blade_phase == SP_CLASH else 1.1
			blade_pivot.rotation_degrees.x = -25.0
			tint = Color(0.8, 0.9, 1.4) if blade_phase == SP_CLASH else tint
		SP_STAGGER, SP_OPEN:
			length = 0.7
			pulse = 0.5
			tint = Color(0.5, 0.4, 0.6)
		_:
			blade_pivot.rotation_degrees.x = 0.0
	if blade_phase != SP_LUNGE and blade_phase != SP_PARRY and blade_phase != SP_CLASH:
		blade_pivot.rotation_degrees.x = 0.0
	blade.scale = Vector3(pulse, pulse, length)
	if blade_mat:
		blade_mat.albedo_color = Color(tint.r * pulse, tint.g * pulse, tint.b * pulse, 1.0)
	if blade_flare:
		blade_flare.scale = Vector3.ONE * (0.6 + pulse * 0.8)
	# flag an incoming tell for the local target
	if world and world.local_ship == self:
		pass
	elif world and world.local_ship:
		var inc = world.local_ship._incoming_lunge()
		if inc == self and blade_phase == SP_WINDUP:
			world.local_ship.incoming_warn = 0.4

# ---------------------------------------------------------------- top-down arenas (v0.4.0)
func _td() -> bool:
	return world != null and world.cfg.get("topdown", false)

func _td_input(inp: Dictionary) -> void:
	var st := Vector2(Input.get_axis("yaw_left", "yaw_right"), Input.get_axis("pitch_down", "pitch_up"))
	inp["pitch"] = 0.0
	inp["sy"] = 0.0
	if st.length() > 0.3:
		var want := Vector3(st.x, 0, -st.y).normalized()
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		else:
			fwd = fwd.normalized()
		var a := fwd.signed_angle_to(want, Vector3.UP)
		inp["yaw"] = clampf(-a * 2.5, -1.0, 1.0)
		if mech and st.length() > 0.55:
			inp["boost"] = true

func _td_plane_lock() -> void:
	global_position.y = world.cfg["plane_y"]
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.01:
		f = Vector3.FORWARD
	else:
		f = f.normalized()
	global_transform.basis = Basis.looking_at(f, Vector3.UP)
	vel.y = 0.0
	velocity.y = 0.0
	ang.x = 0.0
	ang.z = 0.0

func _td_camera(d: float) -> void:
	var target := global_position + Vector3(0, 150, 48)
	camera.global_position = camera.global_position.lerp(target, _exp_k(8.0, d))
	camera.look_at(global_position, Vector3.FORWARD)
	camera.fov = lerpf(camera.fov, 55.0, _exp_k(5.0, d))
	shake = maxf(0, shake - d * 2)
	camera.h_offset = randf_range(-1, 1) * shake * 0.6
	camera.v_offset = randf_range(-1, 1) * shake * 0.6

func _srv_plane_check(now: int) -> bool:
	if not _td():
		return false
	var py: float = world.cfg["plane_y"]
	var p := net_xform.origin
	if absf(p.y - py) <= 1.5:
		return false
	p.y = py
	net_xform.origin = p
	transform.origin = p
	srv_speed_violations += 1
	if OS.get_cmdline_user_args().has("--debug-net"):
		print("[net] plane clamp ", name)
	_srv_hold_until = now + 2 * clampi(_srv_oneway_ms(), 0, 250) + 60
	_srv_hold_pos = p
	if now - _srv_last_resync > 250:
		_srv_last_resync = now
		rpc_id(peer_id, "cl_resync", Transform3D(net_xform.basis, p))
	return true