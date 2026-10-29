extends RefCounted
## Hand-built flat-shaded low-poly meshes (vertex coloured, no textures).

static func material(unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		n = -n
		var t := b; b = c; c = t
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)

static func piece(st: SurfaceTool, verts: Array, faces: Array, col: Color) -> void:
	var c := Vector3.ZERO
	for v in verts: c += v
	c /= verts.size()
	for f in faces:
		tri(st, verts[f[0]], verts[f[1]], verts[f[2]], col, c)

static func prism(st: SurfaceTool, t: Array, off: Vector3, col: Color) -> void:
	var v := [t[0] + off, t[1] + off, t[2] + off, t[0] - off, t[1] - off, t[2] - off]
	piece(st, v, [[0,1,2],[3,5,4],[0,3,1],[1,3,4],[1,4,2],[2,4,5],[2,5,0],[0,5,3]], col)

static func ship_body(col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := [Vector3(0,0,-3.2), Vector3(0,0.55,0.6), Vector3(0.7,0,0.8), Vector3(0,-0.45,0.8), Vector3(-0.7,0,0.8), Vector3(0,0.1,2.0)]
	piece(st, body, [[0,1,2],[0,2,3],[0,3,4],[0,4,1],[5,2,1],[5,3,2],[5,4,3],[5,1,4]], col)
	var glass := [Vector3(0,0.25,-1.8), Vector3(0.35,0.3,0), Vector3(-0.35,0.3,0), Vector3(0,0.75,-0.1)]
	piece(st, glass, [[0,1,3],[0,3,2],[1,2,3],[0,2,1]], Color(0.2,0.9,1.0))
	for s in [-1.0, 1.0]:
		prism(st, [Vector3(s*0.55,0.1,0.6), Vector3(s*0.85,1.3,1.9), Vector3(s*0.55,0.1,1.9)], Vector3(0.05,0,0), col.lightened(0.2))
	st.set_material(material())
	return st.commit()

## Wing built relative to its hinge at (s*0.5, 0, 0.5) so it can fold.
static func ship_wing(col: Color, s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := Vector3(s*0.5, 0, 0.5)
	prism(st, [Vector3(s*0.5,0,-0.6) - h, Vector3(s*3.4,-0.15,1.6) - h, Vector3(s*0.5,0,1.5) - h], Vector3(0,0.07,0), col.darkened(0.45))
	prism(st, [Vector3(s*1.0,-0.1,-1.6) - h, Vector3(s*1.15,-0.1,0.4) - h, Vector3(s*0.85,-0.1,0.4) - h], Vector3(0,0.08,0), Color(0.35,0.35,0.4))
	st.set_material(material())
	return st.commit()

## Append an axis-aligned flat-shaded box to a SurfaceTool.
static func box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var v := []
	for i in 8:
		v.append(c + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var faces := [[0,1,3],[0,3,2],[4,6,7],[4,7,5],[0,4,5],[0,5,1],[2,3,7],[2,7,6],[0,2,6],[0,6,4],[1,5,7],[1,7,3]]
	for f in faces:
		var shade := 1.0 if f[0] == 2 else (0.75 if f[0] == 0 and f[1] == 4 else 0.88)
		var cc := col * shade
		cc.a = 1.0
		tri(st, v[f[0]], v[f[1]], v[f[2]], cc, c)

static func icosphere(radius: float, jitter: float, rng: RandomNumberGenerator, base: Color, subdiv := 1, squash := Vector3.ONE) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array = [Vector3(-1,t,0),Vector3(1,t,0),Vector3(-1,-t,0),Vector3(1,-t,0),Vector3(0,-1,t),Vector3(0,1,t),Vector3(0,-1,-t),Vector3(0,1,-t),Vector3(t,0,-1),Vector3(t,0,1),Vector3(-t,0,-1),Vector3(-t,0,1)]
	var faces: Array = [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	for i in subdiv:
		var cache := {}
		var nf: Array = []
		for f in faces:
			var m := []
			for e in [[f[0],f[1]],[f[1],f[2]],[f[2],f[0]]]:
				var k := "%d_%d" % [min(e[0],e[1]), max(e[0],e[1])]
				if not cache.has(k):
					cache[k] = verts.size()
					verts.append((verts[e[0]] + verts[e[1]]) * 0.5)
				m.append(cache[k])
			nf.append([f[0],m[0],m[2]]); nf.append([f[1],m[1],m[0]]); nf.append([f[2],m[2],m[1]]); nf.append([m[0],m[1],m[2]])
		faces = nf
	for i in verts.size():
		verts[i] = verts[i].normalized() * radius * (1.0 + rng.randf_range(-jitter, jitter)) * squash
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var c := base * rng.randf_range(0.75, 1.15)
		c.a = 1.0
		tri(st, verts[f[0]], verts[f[1]], verts[f[2]], c, Vector3.ZERO)
	st.set_material(material())
	return st.commit()
