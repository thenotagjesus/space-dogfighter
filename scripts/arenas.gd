extends RefCounted
## Procedural, seeded arenas. Every peer builds the identical layout from the arena id.
const Meshes := preload("res://scripts/meshes.gd")
const NAMES := ["Deep Space", "Star Surface", "Ocean", "Desert", "Tech Planet"]

static func build(w: Node3D, id: int) -> Dictionary:
	var cfg := {"id": id, "name": NAMES[id], "planet": id != 0, "gravity": 0.0 if id == 0 else 7.0,
		"radius": 600.0, "ceil": 400.0, "spawn_min": 0.0, "spawn_max": 0.0,
		"hazard": "", "hazard_y": -INF, "flares": []}
	match id:
		0: _space(w, cfg)
		1: _star(w, cfg)
		2: _ocean(w, cfg)
		3: _desert(w, cfg)
		4: _tech(w, cfg)
	return cfg

# ------------------------------------------------------------ helpers
static func _env(w: Node3D, bg: Color, amb: Color, amb_e: float, sun_col: Color, sun_e: float, sun_rot: Vector3, fog_col := Color.BLACK, fog_d := 0.0, glow := 0.6) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	# polish: filmic tonemap, soft bloom on emissive/bright bits, slight grade
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = glow > 0.0
	env.glow_intensity = glow
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	if fog_d <= 0.0:
		# faint depth fog everywhere so distant geometry recedes
		fog_d = 0.0007
		fog_col = bg.lerp(amb, 0.25)
	if fog_d > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog_col
		env.fog_density = fog_d
		env.fog_sky_affect = 0.0
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.rotation_degrees = sun_rot
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 350.0
	sun.shadow_blur = 1.5
	w.add_child(sun)

static func _stars(w: Node3D, count: int, tint := Color.WHITE) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 3.0
	bm.material = Meshes.material(true)
	mm.mesh = bm
	mm.instance_count = count
	for i in count:
		var dir := Vector3(rng.randf_range(-1,1), rng.randf_range(-1,1), rng.randf_range(-1,1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.5, 2.0)), dir * rng.randf_range(2200, 2800)))
		var c := Color(1,1,1).lerp([Color(0.6,0.7,1), Color(1,0.8,0.6), tint][i % 3], 0.6) * rng.randf_range(0.5, 1.0)
		c.a = 1.0
		mm.set_instance_color(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	w.add_child(mmi)

static func _rocks(w: Node3D, rng: RandomNumberGenerator, count: int, rmin: float, rmax: float, place: Callable, col_a: Color, col_b: Color) -> void:
	for i in count:
		var r := rng.randf_range(rmin, rmax)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = place.call(rng)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = r * 0.92
		cs.shape = sh
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.icosphere(r, 0.22, rng, col_a.lerp(col_b, rng.randf()))
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		body.add_child(mi)
		w.add_child(body)
		w.rocks.append([mi, Vector3(rng.randf_range(-0.2,0.2), rng.randf_range(-0.2,0.2), 0)])

static func _floor_plane(w: Node3D, y: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position.y = y
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	w.add_child(body)

static func _shader_plane(w: Node3D, size: float, subdiv: int, code: String, y := 0.0) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = subdiv
	pm.subdivide_depth = subdiv
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	sm.shader = sh
	pm.material = sm
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position.y = y
	w.add_child(mi)
	return mi

## Many boxes merged into one mesh + one static body (cheap draw calls).
class BoxBatch:
	var st := SurfaceTool.new()
	var body := StaticBody3D.new()
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		body.collision_layer = 1
	func add(c: Vector3, size: Vector3, col: Color, collide := true) -> void:
		Meshes.box(st, c, size, col)
		if collide:
			var cs := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = size
			cs.shape = b
			cs.position = c
			body.add_child(cs)
	func finish(w: Node3D, unshaded := false) -> void:
		st.set_material(Meshes.material(unshaded))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		body.add_child(mi)
		w.add_child(body)

static func _rand_xz(rng: RandomNumberGenerator, r: float) -> Vector2:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * r
	return Vector2(cos(a) * d, sin(a) * d)

# ------------------------------------------------------------ 0 deep space
static func _space(w: Node3D, cfg: Dictionary) -> void:
	_env(w, Color(0.01, 0.012, 0.04), Color(0.3, 0.32, 0.55), 0.75, Color(1.0, 0.88, 0.7), 1.5, Vector3(-35, 40, 0))
	_stars(w, 1500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var planet := MeshInstance3D.new()
	planet.mesh = Meshes.icosphere(400.0, 0.0, rng, Color(0.6, 0.25, 0.4), 2)
	planet.position = Vector3(-1200, -500, -1600)
	w.add_child(planet)
	_rocks(w, rng, 70, 4.0, 28.0, func(r: RandomNumberGenerator): return Vector3(r.randf_range(-1,1), r.randf_range(-1,1), r.randf_range(-1,1)).normalized() * r.randf_range(40.0, 550.0), Color(0.5, 0.42, 0.36), Color(0.4, 0.4, 0.45))

# ------------------------------------------------------------ 1 star surface
const SUN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment(){
	vec2 p = floor(UV * 90.0);
	float n = h(p);
	float t = 0.5 + 0.5 * sin(TIME * (0.6 + n * 1.5) + n * 40.0);
	vec3 c = mix(vec3(1.0, 0.35, 0.02), vec3(1.0, 0.85, 0.3), n * 0.6 + t * 0.4);
	ALBEDO = c * 1.6;
}
"""
const FLARE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;
uniform float power = 0.0;
void fragment(){
	float band = 0.6 + 0.4 * sin(UV.y * 40.0 - TIME * 12.0);
	ALBEDO = vec3(1.0, 0.6, 0.15) * band * power;
	ALPHA = clamp(power, 0.0, 1.0) * 0.8;
}
"""
static func _star(w: Node3D, cfg: Dictionary) -> void:
	_env(w, Color(0.18, 0.04, 0.02), Color(1.0, 0.55, 0.3), 0.9, Color(1.0, 0.7, 0.4), 0.6, Vector3(90, 0, 0), Color(1.0, 0.45, 0.1), 0.0025, 1.0)
	_stars(w, 600, Color(1, 0.6, 0.4))
	_shader_plane(w, 2400.0, 1, SUN_SHADER)
	_floor_plane(w, 0.0)
	cfg["hazard"] = "sun"; cfg["hazard_y"] = 2.0
	cfg["spawn_min"] = 80.0; cfg["spawn_max"] = 260.0; cfg["ceil"] = 380.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001
	_rocks(w, rng, 40, 5.0, 22.0, func(r: RandomNumberGenerator):
		var p := _rand_xz(r, 520.0)
		return Vector3(p.x, r.randf_range(40.0, 320.0), p.y), Color(0.25, 0.12, 0.08), Color(0.4, 0.2, 0.1))
	for i in 9:
		var p := _rand_xz(rng, 480.0)
		var cm := CylinderMesh.new()
		cm.top_radius = 14.0; cm.bottom_radius = 22.0; cm.height = 420.0
		cm.radial_segments = 8; cm.rings = 1
		var sm := ShaderMaterial.new()
		var sh := Shader.new(); sh.code = FLARE_SHADER
		sm.shader = sh
		cm.material = sm
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.position = Vector3(p.x, 210.0, p.y)
		w.add_child(mi)
		cfg["flares"].append({"pos": Vector2(p.x, p.y), "r": 20.0, "mat": sm, "node": mi, "state": 0, "t": rng.randf_range(2.0, 8.0)})
	# heat haze post effect (cheap at 480x270)
	var cl := CanvasLayer.new()
	cl.layer = -1
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hm := ShaderMaterial.new()
	var hs := Shader.new()
	hs.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
void fragment(){
	vec2 uv = SCREEN_UV;
	float k = smoothstep(0.35, 1.0, uv.y);
	uv.x += sin(uv.y * 70.0 + TIME * 5.0) * 0.003 * k;
	COLOR = texture(screen_tex, uv);
}
"""
	hm.shader = hs
	cr.material = hm
	cl.add_child(cr)
	w.add_child(cl)

# ------------------------------------------------------------ 2 ocean
const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;
varying vec3 wp;
void vertex(){
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(p.x * 0.05 + TIME * 1.3) * 1.2 + cos(p.z * 0.07 + TIME * 1.1) * 1.0;
	wp = p;
}
void fragment(){
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float f = 0.5 + 0.5 * sin(wp.x * 0.11 + wp.z * 0.07);
	ALBEDO = mix(vec3(0.02, 0.22, 0.4), vec3(0.05, 0.4, 0.55), f);
	ROUGHNESS = 0.6;
}
"""
static func _ocean(w: Node3D, cfg: Dictionary) -> void:
	_env(w, Color(0.5, 0.72, 0.92), Color(0.55, 0.68, 0.85), 0.8, Color(1.0, 0.93, 0.8), 1.35, Vector3(-40, 30, 0), Color(0.62, 0.78, 0.92), 0.0016, 0.35)
	_shader_plane(w, 2000.0, 80, WATER_SHADER)
	_floor_plane(w, -0.5)
	cfg["hazard"] = "water"; cfg["hazard_y"] = 1.0
	cfg["spawn_min"] = 70.0; cfg["spawn_max"] = 200.0; cfg["ceil"] = 350.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3003
	for i in 26:
		var p := _rand_xz(rng, 560.0)
		var r := rng.randf_range(10.0, 24.0)
		var hgt := rng.randf_range(2.5, 6.0)
		var mesh := Meshes.icosphere(r, 0.25, rng, Color(0.35, 0.32, 0.28).lerp(Color(0.45, 0.42, 0.35), rng.randf()), 1, Vector3(1, hgt, 1))
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = Vector3(p.x, 0, p.y)
		var mi := MeshInstance3D.new(); mi.mesh = mesh
		body.add_child(mi)
		var cs := CollisionShape3D.new(); cs.shape = mesh.create_convex_shape()
		body.add_child(cs)
		w.add_child(body)
	var bb := BoxBatch.new()
	for i in 7:
		var p := _rand_xz(rng, 450.0)
		var ang := rng.randf() * PI
		var span := rng.randf_range(40.0, 70.0)
		var tall := rng.randf_range(50.0, 90.0)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var c := Vector3(p.x, 0, p.y)
		var rc := Color(0.42, 0.36, 0.3)
		bb.add(c + dir * span * 0.5 + Vector3(0, tall * 0.5, 0), Vector3(14, tall, 14), rc)
		bb.add(c - dir * span * 0.5 + Vector3(0, tall * 0.5, 0), Vector3(14, tall, 14), rc)
		# arch top: a few stepped blocks along the span
		for k in 5:
			var t := (k - 2) / 4.0
			bb.add(c + dir * span * t + Vector3(0, tall + 6 - abs(t) * 6.0, 0), Vector3(span / 4.0 + 10, 12, 14), rc.lightened(0.1))
	bb.finish(w)

# ------------------------------------------------------------ 3 desert
static func desert_height(x: float, z: float, n1: FastNoiseLite, n2: FastNoiseLite) -> float:
	var h := (n1.get_noise_2d(x, z) * 0.5 + 0.5) * 18.0 + sin(x * 0.03 + z * 0.012) * 4.0
	var m := n2.get_noise_2d(x, z)
	h = lerpf(h, 85.0 + n1.get_noise_2d(z, x) * 4.0, smoothstep(0.2, 0.3, m))
	var cz := 180.0 * sin(x / 220.0)
	var dc := absf(z - cz)
	h = lerpf(-35.0, h, smoothstep(22.0, 50.0, dc))
	var rr := Vector2(x, z).length()
	h += maxf(0.0, rr - 600.0) * 0.8
	return h

static func _desert(w: Node3D, cfg: Dictionary) -> void:
	_env(w, Color(0.98, 0.72, 0.45), Color(0.85, 0.68, 0.55), 0.7, Color(1.0, 0.88, 0.65), 1.5, Vector3(-50, -30, 0), Color(0.95, 0.74, 0.52), 0.002, 0.35)
	cfg["spawn_min"] = 120.0; cfg["spawn_max"] = 220.0; cfg["ceil"] = 380.0
	var n1 := FastNoiseLite.new(); n1.seed = 7; n1.frequency = 0.006
	var n2 := FastNoiseLite.new(); n2.seed = 11; n2.frequency = 0.004
	var n := 90
	var cell := 16.0
	var half := n * cell * 0.5
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for zi in n + 1:
		for xi in n + 1:
			hs[zi * (n + 1) + xi] = desert_height(xi * cell - half, zi * cell - half, n1, n2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 4004
	for zi in n:
		for xi in n:
			var p := []
			for o in [[0,0],[1,0],[0,1],[1,1]]:
				var X: int = xi + o[0]; var Z: int = zi + o[1]
				p.append(Vector3(X * cell - half, hs[Z * (n + 1) + X], Z * cell - half))
			for t in [[0, 1, 2], [1, 3, 2]]:
				var a: Vector3 = p[t[0]]; var b: Vector3 = p[t[1]]; var c: Vector3 = p[t[2]]
				var hy := (a.y + b.y + c.y) / 3.0
				var col := Color(0.86, 0.66, 0.4)
				if hy > 60.0: col = Color(0.72, 0.36, 0.2)
				elif hy > 25.0: col = Color(0.62, 0.32, 0.2).lerp(Color(0.8, 0.5, 0.3), fmod(hy, 12.0) / 12.0)
				elif hy < -10.0: col = Color(0.55, 0.38, 0.25)
				col = col * rng.randf_range(0.92, 1.05); col.a = 1.0
				Meshes.tri(st, a, b, c, col, (a + b + c) / 3.0 - Vector3(0, 10, 0))
	st.set_material(Meshes.material())
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var mi := MeshInstance3D.new(); mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new(); cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	w.add_child(body)

# ------------------------------------------------------------ 4 tech planet
const GRID_SHADER := """
shader_type spatial;
render_mode unshaded;
varying vec3 wp;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec2 g = abs(fract(wp.xz / 20.0) - 0.5);
	float line = step(0.46, max(g.x, g.y));
	ALBEDO = mix(vec3(0.03, 0.03, 0.07), vec3(0.1, 0.9, 1.0) * (0.6 + 0.4 * sin(TIME * 2.0 + wp.x * 0.02)), line);
}
"""
static func _tech(w: Node3D, cfg: Dictionary) -> void:
	_env(w, Color(0.03, 0.02, 0.08), Color(0.35, 0.4, 0.6), 0.8, Color(0.7, 0.8, 1.0), 1.0, Vector3(-45, 60, 0), Color(0.08, 0.06, 0.18), 0.0018, 0.9)
	_stars(w, 900)
	_shader_plane(w, 2000.0, 1, GRID_SHADER, 0.05)
	_floor_plane(w, 0.0)
	cfg["spawn_min"] = 180.0; cfg["spawn_max"] = 280.0; cfg["ceil"] = 420.0
	var rng := RandomNumberGenerator.new(); rng.seed = 5005
	var bb := BoxBatch.new()
	var slab_c := Color(0.32, 0.34, 0.42)
	# raised city slabs on both sides of the central trench (trench floor = y 0)
	for s in [-1.0, 1.0]:
		bb.add(Vector3(0, 20, s * 367.5), Vector3(1300, 40, 665), slab_c)
	# trench greebles + crossing pipes
	for i in 40:
		var s := -1.0 if i % 2 == 0 else 1.0
		var x := rng.randf_range(-640.0, 640.0)
		var sz := Vector3(rng.randf_range(8, 30), rng.randf_range(4, 18), rng.randf_range(3, 8))
		bb.add(Vector3(x, sz.y * 0.5 + rng.randf_range(0, 20), s * (35.0 - sz.z * 0.5)), sz, Color(0.25, 0.27, 0.33))
	for x in [-450.0, -150.0, 150.0, 450.0]:
		bb.add(Vector3(x, 22, 0), Vector3(8, 8, 70), Color(0.5, 0.45, 0.3))
	# towers on a street grid
	for gx in range(-9, 10):
		for gz in range(-9, 10):
			var z := gz * 65.0
			if absf(z) < 70.0 or rng.randf() < 0.35: continue
			var x := gx * 65.0
			if Vector2(x, z).length() > 640.0: continue
			var hgt := rng.randf_range(15.0, 110.0)
			var fw := rng.randf_range(18.0, 34.0)
			var col := Color(0.4, 0.44, 0.55).lerp(Color(0.55, 0.5, 0.6), rng.randf())
			bb.add(Vector3(x, 40 + hgt * 0.5, z), Vector3(fw, hgt, fw), col)
			if rng.randf() < 0.4:
				bb.add(Vector3(x, 40 + hgt + 5, z), Vector3(fw * 0.5, 10, fw * 0.5), col.lightened(0.2))
	bb.finish(w)
	var glow := BoxBatch.new()
	var caps := BoxBatch.new()
	for i in 12:
		var p := _rand_xz(rng, 600.0)
		if absf(p.y) < 60.0: p.y += 80.0 * sign(p.y + 0.01)
		glow.add(Vector3(p.x, 40 + 100, p.y), Vector3(4, 200, 4), Color(0.2, 0.2, 0.25))
		caps.add(Vector3(p.x, 40 + 203, p.y), Vector3(8, 6, 8), Color(1.0, 0.15, 0.15), false)
	glow.finish(w)
	caps.finish(w, true)
