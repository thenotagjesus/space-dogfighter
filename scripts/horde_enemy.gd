extends StaticBody3D
const SWARMER := 0
const DARTER := 1
const GUNNER := 2
const SPLIT_L := 3
const SPLIT_M := 4
const SPLIT_S := 5
const MARCHER := 6
const BOSS := 7
const INFO := [
	{"r": 2.6, "hp": 14.0, "spd": 36.0, "score": 50, "col": Color(0.95, 0.25, 0.6)},
	{"r": 2.2, "hp": 8.0, "spd": 85.0, "score": 80, "col": Color(1.0, 0.85, 0.2)},
	{"r": 3.6, "hp": 40.0, "spd": 16.0, "score": 150, "col": Color(0.3, 1.0, 0.45)},
	{"r": 9.0, "hp": 45.0, "spd": 10.0, "score": 100, "col": Color(0.75, 0.35, 0.2)},
	{"r": 5.5, "hp": 20.0, "spd": 16.0, "score": 60, "col": Color(0.85, 0.45, 0.25)},
	{"r": 3.0, "hp": 8.0, "spd": 24.0, "score": 40, "col": Color(0.95, 0.6, 0.3)},
	{"r": 3.4, "hp": 16.0, "spd": 0.0, "score": 60, "col": Color(0.4, 0.8, 1.0)},
	{"r": 16.0, "hp": 900.0, "spd": 10.0, "score": 5000, "col": Color(1.0, 0.3, 0.2)},
]
var horde: Node = null
var id := 0
var type := 0
var hp := 10.0
var max_hp := 10.0
var r := 2.0
var alive := true
var mech := false
var est_vel := Vector3.ZERO
var vel := Vector3.ZERO
var pilot_name := "drone"
var t := 0.0
var t2 := 0.0
var phase := 0
var target_pos := Vector3.ZERO
var dash_dir := Vector3.ZERO
var mesh_i: MeshInstance3D
var hp_frac := 1.0
var _flash := 0.0

func setup(h: Node, eid: int, etype: int, pos: Vector3, hp_mul: float) -> void:
	horde = h
	id = eid
	type = etype
	name = "H%d" % eid
	position = pos
	target_pos = pos
	var info: Dictionary = INFO[type]
	hp = info.hp * hp_mul
	max_hp = hp
	r = info.r
	collision_layer = 2
	collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = r
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	add_child(collision_shape)
	mesh_i = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = info.col * 0.35
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Color = info.col
	match type:
		SWARMER:
			_prism(st, _star(4, r, r * 0.35, 0.0), -0.4, 0.4, c)
			_prism(st, _star(4, r * 0.8, r * 0.3, PI / 4.0), -0.25, 0.25, c.darkened(0.25))
		DARTER:
			_prism(st, PackedVector2Array([Vector2(0, -r * 1.4), Vector2(r * 0.7, r), Vector2(0, r * 0.6), Vector2(-r * 0.7, r)]), -0.4, 0.4, c)
		GUNNER:
			_prism(st, _star(8, r, r, 0.0), -0.6, 0.6, c)
			_prism(st, _box2(r * 0.4, r * 0.9, -r * 0.6), 0.6, 1.4, c.darkened(0.3))
		SPLIT_L, SPLIT_M, SPLIT_S:
			var rng := RandomNumberGenerator.new()
			rng.seed = eid
			var pts := PackedVector2Array()
			for i in 9:
				var a := TAU * i / 9.0
				pts.append(Vector2(cos(a), sin(a)) * r * (1.0 + rng.randf_range(-0.25, 0.25)))
			_prism(st, pts, -r * 0.4, r * 0.4, c)
		MARCHER:
			_prism(st, _box2(r, r * 0.6, 0.0), -0.5, 0.5, c)
			_prism(st, _box2(r * 0.25, r * 0.35, -r * 0.8, -r * 0.8), -0.4, 0.4, c.darkened(0.3))
			_prism(st, _box2(r * 0.25, r * 0.35, -r * 0.8, r * 0.8), -0.4, 0.4, c.darkened(0.3))
		BOSS:
			_prism(st, _star(6, r, r, 0.0), -2.0, 2.0, c)
			for i in 6:
				var a := TAU * i / 6.0
				var o := Vector2(cos(a), sin(a)) * r * 1.05
				_prism(st, _box2(r * 0.18, r * 0.18, o.y, o.x), -1.0, 3.0, c.darkened(0.35))
	st.generate_normals()
	mesh_i.mesh = st.commit()
	mesh_i.material_override = mat
	add_child(mesh_i)
	pilot_name = ["Swarmer", "Darter", "Gunner", "Magma rock", "Magma rock", "Magma shard", "Marcher", "Boss"][type]

func _process(d: float) -> void:
	if not multiplayer.is_server():
		position = position.lerp(target_pos, 1.0 - exp(-14.0 * d))
	if _flash > 0:
		_flash -= d
		if _flash > 0:
			(mesh_i.material_override as StandardMaterial3D).emission = Color.WHITE
		else:
			(mesh_i.material_override as StandardMaterial3D).emission = INFO[type].col * 0.35
	match type:
		SWARMER, SPLIT_L, SPLIT_M, SPLIT_S:
			mesh_i.rotation.y += d * (3.0 if type == SWARMER else 0.8)
		_:
			if est_vel.length() > 1.0:
				mesh_i.rotation.y = atan2(-est_vel.x, -est_vel.z)
	if type == BOSS:
		(mesh_i.material_override as StandardMaterial3D).emission_energy_multiplier = 0.35 + sin(Time.get_ticks_msec() / 200.0) * 0.15

func server_damage(amount: float, attacker_nn: String, w := 0, cause := "") -> void:
	if not multiplayer.is_server() or not alive:
		return
	if attacker_nn.begins_with("#"):
		return
	horde.enemy_hit(self, amount, attacker_nn)

func flash() -> void:
	_flash = 0.12
## Flat polygon (XZ, y = 0 plane; Vector2 is x,z) extruded between y0 and y1, flat colour.
func _prism(st: SurfaceTool, pts: PackedVector2Array, y0: float, y1: float, c: Color) -> void:
	st.set_color(c)
	var n := pts.size()
	var ctr := Vector2.ZERO
	for p in pts: ctr += p
	ctr /= float(n)
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		# top and bottom fans (both windings so the faces show from either side)
		for tri in [[ctr, p0, p1, y1], [ctr, p1, p0, y0], [ctr, p1, p0, y1], [ctr, p0, p1, y0]]:
			var yy: float = tri[3]
			for k in 3:
				var q: Vector2 = tri[k]
				st.add_vertex(Vector3(q.x, yy, q.y))
		# side quad
		var a0 := Vector3(p0.x, y0, p0.y)
		var a1 := Vector3(p1.x, y0, p1.y)
		var b0 := Vector3(p0.x, y1, p0.y)
		var b1 := Vector3(p1.x, y1, p1.y)
		for v in [a0, b0, b1, a0, b1, a1, a0, b1, b0, a0, a1, b1]:
			st.add_vertex(v)

func _star(k: int, ro: float, ri: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var m := k if is_equal_approx(ro, ri) else k * 2
	for i in m:
		var a := rot + TAU * i / float(m) - PI / 2.0
		var rr := ro if (i % 2 == 0 or m == k) else ri
		pts.append(Vector2(cos(a), sin(a)) * rr)
	return pts

func _box2(hx: float, hz: float, cz: float, cx := 0.0) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - hx, cz - hz), Vector2(cx + hx, cz - hz), Vector2(cx + hx, cz + hz), Vector2(cx - hx, cz + hz)])
