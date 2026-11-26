extends RefCounted
## Weapon table. proj: 0 bolt, 1 homing missile, 2 wave bolt, 3 dumbfire rocket, 4 gravity bomb.
## ammo -1 = infinite. Index 7 (chaingun) is mech-only.
const LIST := [
	{"name": "TWIN BLASTER", "cd": 0.09, "max": -1, "start": -1, "cost": 1, "proj": 0, "speed": 300.0, "dmg": 6.0, "count": 1, "col": Color(0.4, 1.0, 0.5)},
	{"name": "SPREAD FAN", "cd": 0.32, "max": 120, "start": 60, "cost": 1, "proj": 0, "speed": 260.0, "dmg": 5.0, "count": 5, "fan": 7.0, "col": Color(1.0, 0.9, 0.3)},
	{"name": "LASER BEAM", "cd": 0.06, "max": 300, "start": 150, "cost": 1, "beam": true, "dmg": 2.6, "range": 380.0, "col": Color(1.0, 0.2, 0.3)},
	{"name": "WAVE BEAM", "cd": 0.18, "max": 160, "start": 80, "cost": 1, "proj": 2, "speed": 210.0, "dmg": 8.0, "count": 2, "col": Color(0.3, 0.8, 1.0)},
	{"name": "HOMING MISSILE", "cd": 0.7, "max": 16, "start": 8, "cost": 1, "proj": 1, "speed": 130.0, "dmg": 65.0, "splash": 16.0, "count": 1, "col": Color(1.0, 0.55, 0.15)},
	{"name": "ROCKET SALVO", "cd": 1.0, "max": 40, "start": 16, "cost": 4, "proj": 3, "speed": 170.0, "dmg": 38.0, "splash": 10.0, "count": 4, "col": Color(1.0, 0.35, 0.1)},
	{"name": "GRAVITY BOMB", "cd": 1.2, "max": 8, "start": 3, "cost": 1, "proj": 4, "speed": 0.0, "dmg": 120.0, "splash": 35.0, "count": 1, "col": Color(0.7, 0.3, 1.0)},
	{"name": "MECH CHAINGUN", "cd": 0.05, "max": -1, "start": -1, "cost": 1, "proj": 0, "speed": 340.0, "dmg": 5.0, "count": 1, "jitter": 0.025, "col": Color(1.0, 1.0, 0.6)},
	{"name": "HORDE BOLT", "cd": 1.0, "max": -1, "start": -1, "cost": 0, "proj": 0, "speed": 120.0, "dmg": 7.0, "count": 1, "col": Color(1.0, 0.25, 0.2)},
]
const SELECTABLE := 7
const MECH_GUN := 7
const MISSILE := 4
const HORDE_BOLT := 8   # enemy-only shot in Horde mode (never in a loadout)

static func start_ammo() -> PackedInt32Array:
	var a := PackedInt32Array()
	for w in LIST: a.append(w["start"])
	return a

static func default_loadout() -> PackedInt32Array:
	return PackedInt32Array([0, 4])  # Twin Blaster + Homing Missile

static func sanitize_loadout(raw: PackedInt32Array) -> PackedInt32Array:
	var out: Array = []
	for w in raw:
		var iw := int(w)
		if iw >= 0 and iw < SELECTABLE and iw not in out:
			out.append(iw)
		if out.size() == 2:
			break
	if out.size() != 2:
		return default_loadout()
	return PackedInt32Array(out)

## Accepts 1-based (--loadout=1,5) or 0-based slots; returns a sanitized 0-based pair.
static func parse_loadout_string(text: String) -> PackedInt32Array:
	var parts := text.split(",")
	var raw := PackedInt32Array()
	for p in parts:
		if p.strip_edges().is_valid_int():
			raw.append(int(p.strip_edges()))
	# player-facing 1-7: if every value is 1..7, treat as 1-based
	var one_based := raw.size() >= 2
	for v in raw:
		if v < 1 or v > SELECTABLE:
			one_based = false
			break
	if one_based:
		var conv := PackedInt32Array()
		for v in raw:
			conv.append(v - 1)
		raw = conv
	return sanitize_loadout(raw)

static func random_loadout() -> PackedInt32Array:
	var a := randi() % SELECTABLE
	var b := randi() % (SELECTABLE - 1)
	if b >= a:
		b += 1
	return PackedInt32Array([a, b])

static func has_slot(loadout: PackedInt32Array, w: int) -> bool:
	return w == MECH_GUN or (w in loadout)

## Procedural weapon icon (no textures). Used by the Hangar and the HUD so they always match.
static func draw_icon(ci: CanvasItem, r: Rect2, w: int, col: Color) -> void:
	var c := r.get_center()
	var s: float = minf(r.size.x, r.size.y)
	match w:
		0: # twin blaster: two parallel bolts
			for ox in [-0.18, 0.18]:
				ci.draw_rect(Rect2(c + Vector2(ox * s - s * 0.07, -s * 0.32), Vector2(s * 0.14, s * 0.64)), col)
		1: # spread fan
			for i in 5:
				var a := deg_to_rad(-40.0 + i * 20.0)
				var tip := c + Vector2(sin(a), -cos(a)) * s * 0.38
				ci.draw_line(c + Vector2(0, s * 0.2), tip, col, 1.2)
		2: # laser: long beam + core
			ci.draw_rect(Rect2(c - Vector2(s * 0.06, s * 0.4), Vector2(s * 0.12, s * 0.8)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.02, s * 0.4), Vector2(s * 0.04, s * 0.8)), Color.WHITE)
		3: # wave beam: two sine strokes
			for sign in [-1.0, 1.0]:
				var pts := PackedVector2Array()
				for i in 8:
					var t := float(i) / 7.0
					pts.append(c + Vector2((t - 0.5) * s * 0.7, sign * sin(t * TAU) * s * 0.2))
				ci.draw_polyline(pts, col, 1.3)
		4: # homing missile: chevron + diamond lock
			var tip := c + Vector2(0, -s * 0.36)
			ci.draw_colored_polygon(PackedVector2Array([tip, c + Vector2(-s * 0.16, s * 0.08), c + Vector2(s * 0.16, s * 0.08)]), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.07, s * 0.08), Vector2(s * 0.14, s * 0.28)), col)
			var k := s * 0.22
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, 0), c + Vector2(0, k), c + Vector2(-k, 0), c + Vector2(0, -k)]), Color.YELLOW, 1.0)
		5: # rocket salvo: four small missiles
			for i in 4:
				var x := c.x + (i - 1.5) * s * 0.2
				ci.draw_rect(Rect2(Vector2(x - s * 0.05, c.y - s * 0.3), Vector2(s * 0.1, s * 0.5)), col)
				ci.draw_rect(Rect2(Vector2(x - s * 0.03, c.y - s * 0.38), Vector2(s * 0.06, s * 0.1)), Color.WHITE)
		6: # gravity bomb: disc + ring
			ci.draw_circle(c, s * 0.28, col)
			ci.draw_arc(c, s * 0.38, 0.4, TAU - 0.4, 12, col.lightened(0.3), 1.2)
			ci.draw_circle(c, s * 0.08, Color.WHITE)
		_:
			ci.draw_rect(Rect2(c - Vector2(s, s) * 0.2, Vector2(s, s) * 0.4), col)
