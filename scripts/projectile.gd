extends Node3D
## All projectile types. Every peer simulates one for visuals; only the
## server's copy (auth == true) reports hits.
const Meshes := preload("res://scripts/meshes.gd")
const Weapons := preload("res://scripts/weapons.gd")

var w := 0
var kind := 0
var vel := Vector3.ZERO
var extra := Vector3.ZERO
var life := 2.0
var age := 0.0
var auth := false
var world: Node = null
var shooter: Node3D = null
var shooter_nn := ""
var target: Node3D = null
var base := Vector3.ZERO
var side := Vector3.RIGHT
var light: OmniLight3D

func _ready() -> void:
	var wd: Dictionary = Weapons.LIST[w]
	kind = wd["proj"]
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = wd["col"]
	var bm := BoxMesh.new()
	match kind:
		0:
			bm.size = Vector3(0.25, 0.25, 3.0); life = 1.6
		1, 3:
			bm.size = Vector3(0.5, 0.5, 1.4); life = 4.0 if kind == 1 else 3.0
			_trail()
		2:
			bm.size = Vector3(0.6, 0.6, 1.6); life = 1.8
		4:
			bm.size = Vector3(1.2, 1.2, 1.2); life = 8.0
			mat.albedo_color = Color(0.25, 0.1, 0.35)
			light = OmniLight3D.new()
			light.light_color = wd["col"]
			light.omni_range = 10.0
			add_child(light)
	bm.material = mat
	mi.mesh = bm
	add_child(mi)
	base = position
	if kind == 2:
		side = vel.normalized().cross(Vector3.UP if absf(vel.normalized().y) < 0.95 else Vector3.RIGHT).normalized()
	_face()

func _trail() -> void:
	var trail := CPUParticles3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3.ONE * 0.5
	pm.material = Meshes.material(true)
	trail.mesh = pm
	trail.amount = 16
	trail.lifetime = 0.45
	trail.gravity = Vector3.ZERO
	trail.spread = 20.0
	trail.initial_velocity_min = 1.0
	trail.initial_velocity_max = 3.0
	trail.direction = Vector3(0, 0, 1)
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.8, 0.4)); g.set_color(1, Color(0.2, 0.2, 0.25))
	trail.color_ramp = g
	add_child(trail)

func _face() -> void:
	if vel.length_squared() > 0.01:
		var up := Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT
		look_at(global_position + vel, up)

func _end() -> void:
	if auth and Weapons.LIST[w].has("splash"):
		world.server_explode(global_position, shooter_nn, Weapons.LIST[w]["dmg"], Weapons.LIST[w]["splash"], w)
	queue_free()

func _physics_process(d: float) -> void:
	life -= d
	age += d
	if life <= 0.0:
		_end()
		return
	var to: Vector3
	match kind:
		1:
			if target and is_instance_valid(target) and target.alive:
				var want := (target.global_position - global_position).normalized() * vel.length()
				vel = vel.lerp(want, clamp(2.4 * d, 0.0, 1.0))
				_face()
			to = global_position + vel * d
		2:
			base += vel * d
			to = base + side * sin(age * 16.0 + extra.x) * 3.0
		3:
			vel *= 1.0 + 0.8 * d
			to = global_position + vel * d
		4:
			vel += extra * d
			vel *= 1.0 - 0.5 * d
			to = global_position + vel * d
			var armed := age > 0.7
			if light: light.light_energy = 3.0 if (armed and int(age * 8.0) % 2 == 0) else 0.6
			if auth and armed:
				for s in world.ships.get_children():
					if s.alive and String(s.name) != shooter_nn and s.global_position.distance_to(global_position) < 11.0:
						_end()
						return
		_:
			to = global_position + vel * d
	var q := PhysicsRayQueryParameters3D.create(global_position, to, 3)
	if shooter and is_instance_valid(shooter):
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		if auth:
			global_position = hit.position
			if Weapons.LIST[w].has("splash"):
				_end()
				return
			world.server_proj_hit(self, hit.collider, hit.position)
		queue_free()
		return
	global_position = to
