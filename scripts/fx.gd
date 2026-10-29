extends RefCounted

## Drafted with Gemini (gemini-3-flash-preview), reviewed/fixed by hand.
## Polished low-poly effects for Godot 4.x (Compatibility Renderer)
## Uses CPUParticles3D and Tweens for juice and bloom-ready colors.

const Meshes := preload("res://scripts/meshes.gd")

static func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Multiply color for bloom (Compatibility renderer uses energy > 1.0 for glow)
	m.albedo_color = Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, col.a)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m

static func explosion(parent: Node, pos: Vector3, size: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos

	# 1. Debris Particles
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.2 * size
	p.mesh = bm
	p.amount = int(16 * size)
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.2
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -12, 0)
	p.initial_velocity_min = 8.0 * size
	p.initial_velocity_max = 16.0 * size
	p.damping_min = 2.0
	p.damping_max = 5.0
	
	# Material for debris using vertex colors
	var p_mat := _glow_mat(Color.WHITE)
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL # Shaded debris
	p.mesh.material = p_mat
	
	var g := Gradient.new()
	g.set_color(0, Color(4, 3, 1))      # Bright Flash
	g.add_point(0.2, Color(2, 1, 0.2))  # Hot Orange
	g.add_point(0.6, Color(0.2, 0.1, 0.1)) # Darker cooling
	g.set_color(1, Color(0, 0, 0, 0))   # Fade to nothing
	p.color_ramp = g
	
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	
	root.add_child(p)
	p.emitting = true

	# 2. Flash Sphere
	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 8; sm.rings = 4
	flash.mesh = sm
	var f_mat := _glow_mat(Color(2, 1.5, 0.5, 0.9))
	flash.material_override = f_mat
	root.add_child(flash)

	# 3. Shockwave Ring
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8; tm.outer_radius = 1.0
	tm.rings = 16; tm.ring_segments = 4
	ring.mesh = tm
	var r_mat := _glow_mat(Color(2, 0.8, 0.2, 0.6))
	ring.material_override = r_mat
	root.add_child(ring)

	# 4. Omni Light
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.6, 0.3)
	light.omni_range = 15.0 * size
	light.light_energy = 8.0
	root.add_child(light)

	# Animation logic
	var tw := root.create_tween().set_parallel(true)
	# Flash expand and vanish
	tw.tween_property(flash, "scale", Vector3.ONE * 4.0 * size, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(f_mat, "albedo_color:a", 0.0, 0.25).set_delay(0.05)
	# Ring expand and vanish
	ring.scale = Vector3.ONE * 0.1
	tw.tween_property(ring, "scale", Vector3(6, 0.1, 6) * size, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(r_mat, "albedo_color:a", 0.0, 0.4)
	# Light fade
	tw.tween_property(light, "light_energy", 0.0, 0.6)
	
	root.get_tree().create_timer(1.5).timeout.connect(root.queue_free)

static func spark(parent: Node, pos: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	
	var p := CPUParticles3D.new()
	var qm := BoxMesh.new()
	qm.size = Vector3(0.1, 0.1, 0.4)
	p.mesh = qm
	p.mesh.material = _glow_mat(Color(2, 2, 1))
	p.amount = 6
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.3
	p.spread = 180.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -5, 0)
	
	root.add_child(p)
	p.emitting = true
	
	root.get_tree().create_timer(0.4).timeout.connect(root.queue_free)

static func muzzle(parent: Node, pos: Vector3, col: Color, size: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 6; sm.rings = 3
	mi.mesh = sm
	var mat := _glow_mat(col)
	mi.material_override = mat
	root.add_child(mi)
	
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 5.0
	light.omni_range = 5.0 * size
	root.add_child(light)
	
	mi.scale = Vector3.ONE * 0.1
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.5, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.1).set_delay(0.02)
	tw.tween_property(light, "light_energy", 0.0, 0.1)
	
	root.get_tree().create_timer(0.15).timeout.connect(root.queue_free)

static func beam(parent: Node, a: Vector3, b: Vector3, col: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.1: return
	
	var root := Node3D.new()
	parent.add_child(root)
	
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, length)
	mi.mesh = bm
	var mat := _glow_mat(col)
	mi.material_override = mat
	root.add_child(mi)
	
	# Position and rotate beam
	root.global_position = (a + b) * 0.5
	var dir := (b - a).normalized()
	root.look_at(b, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	
	# Inner white core
	var core := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(0.08, 0.08, length)
	core.mesh = cbm
	core.material_override = _glow_mat(Color.WHITE)
	mi.add_child(core)
	
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0, 0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	
	root.get_tree().create_timer(0.2).timeout.connect(root.queue_free)
	spark(parent, b)

