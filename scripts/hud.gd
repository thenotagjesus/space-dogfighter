extends CanvasLayer
const ACCENT := Color(0.55, 0.95, 0.85)
const WARM := Color(1.0, 0.68, 0.3)
const ENEMY := Color(1.0, 0.36, 0.32)
const Weapons := preload("res://scripts/weapons.gd")
## Chunky 90s HUD: crosshair, hull/boost bars, frags, killfeed, target boxes, scoreboard.
var world: Node = null
var ctrl: Control
var feed: Array = [] # [text, time_left]
var font: Font

func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "DejaVu Sans", "Arial"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_LIGHT
	sf.fallbacks = [ThemeDB.fallback_font]
	font = sf
	ctrl = Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.draw.connect(_draw_hud)
	add_child(ctrl)

func push_feed(t: String) -> void:
	feed.append([t, 4.0])
	if feed.size() > 5: feed.pop_front()

func _process(d: float) -> void:
	for f in feed: f[1] -= d
	feed = feed.filter(func(f): return f[1] > 0.0)
	ctrl.queue_redraw()

func _txt(p: Vector2, t: String, col := Color.WHITE, sz := 10) -> void:
	# thin dark outline instead of a chunky drop shadow: crisp at 4K
	ctrl.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 2, Color(0, 0, 0, 0.55))
	ctrl.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _bar(p: Vector2, w: float, frac: float, col: Color, label: String) -> void:
	ctrl.draw_rect(Rect2(p, Vector2(w, 7)), Color(0, 0, 0, 0.6))
	ctrl.draw_rect(Rect2(p + Vector2(1, 1), Vector2((w - 2) * clamp(frac, 0.0, 1.0), 5)), col)
	ctrl.draw_rect(Rect2(p, Vector2(w, 7)), Color(1, 1, 1, 0.8), false, 0.6)
	_txt(p + Vector2(0, -2), label, col, 8)

func _draw_hud() -> void:
	var sz := ctrl.get_viewport_rect().size
	var c := sz * 0.5
	var ship = world.local_ship if world else null
	if Net.show_fps:
		_txt(Vector2(sz.x - 50, sz.y * 0 + 40), "%d FPS" % Engine.get_frames_per_second(), Color(0.6, 1, 0.6), 8)
	for i in feed.size():
		_txt(Vector2(6, 12 + i * 10), feed[i][0], Color(1, 0.85, 0.4), 8)
	if ship == null or not is_instance_valid(ship):
		_txt(c - Vector2(40, 0), "CONNECTING...", Color.YELLOW, 12)
		return
	var cam: Camera3D = ship.camera
	if ship.damage_flash > 0.0:
		ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0, 0, ship.damage_flash * 0.25))
	# target boxes
	var lock = world.find_lock(ship) if ship.alive else null
	for s in world.ships.get_children():
		if s == ship or not s.alive: continue
		if cam.is_position_behind(s.global_position): continue
		var sp := cam.unproject_position(s.global_position)
		var dist: float = s.global_position.distance_to(ship.global_position)
		var r: float = clamp(400.0 / max(dist, 1.0), 4.0, 16.0)
		var col := ENEMY
		ctrl.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), col, false, 0.6)
		_txt(sp + Vector2(r + 2, 3), "%s %dm" % [s.pilot_name, int(dist)], col, 8)
		if s == lock:
			var k := r + 4.0 + sin(Time.get_ticks_msec() * 0.02) * 2.0
			ctrl.draw_polyline(PackedVector2Array([sp + Vector2(0, -k), sp + Vector2(k, 0), sp + Vector2(0, k), sp + Vector2(-k, 0), sp + Vector2(0, -k)]), Color.YELLOW, 0.6)
	# crosshair
	var cc := ACCENT
	for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		ctrl.draw_line(c + v * 4, c + v * 10, cc, 0.6)
	ctrl.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), cc)
	if lock: _txt(c + Vector2(-14, 22), "LOCK", Color.YELLOW, 8)
	# bars
	_bar(Vector2(8, sz.y - 30), 110, ship.health / 100.0, ACCENT if ship.health > 35 else Color(1, 0.3, 0.2), "HULL %d" % ship.health)
	_bar(Vector2(8, sz.y - 14), 110, ship.boost_energy / 100.0, Color(0.3, 0.7, 1), "BOOST")
	_txt(Vector2(sz.x - 120, sz.y - 8), "SPD %d" % int(ship.speed_cur), Color(0.8, 0.8, 1), 8)
	var my = Net.scores.get(String(ship.name), {"frags": 0, "deaths": 0})
	_txt(Vector2(sz.x - 90, 16), "FRAGS %d" % my["frags"], WARM, 14)
	_txt(Vector2(sz.x - 90, 28), "DEATHS %d" % my["deaths"], Color(0.8, 0.8, 0.8), 8)
	# weapon + ammo strip
	var wi: int = Weapons.MECH_GUN if ship.mech else ship.weapon
	var wd: Dictionary = Weapons.LIST[wi]
	var am: int = ship.ammo[wi]
	_txt(Vector2(sz.x - 150, sz.y - 34), wd["name"], wd["col"], 12)
	_txt(Vector2(sz.x - 150, sz.y - 20), "AMMO " + ("--" if am < 0 else str(am)), Color.WHITE, 8)
	_txt(Vector2(sz.x - 70, sz.y - 20), "MSL %d" % ship.ammo[Weapons.MISSILE], Color(1, 0.8, 0.3), 8)
	for i in Weapons.SELECTABLE:
		var r := Rect2(Vector2(sz.x * 0.5 - 52 + i * 15, sz.y - 14), Vector2(13, 9))
		var a: int = ship.ammo[i]
		var col: Color = Weapons.LIST[i]["col"]
		if a == 0: col = col.darkened(0.7)
		ctrl.draw_rect(r, Color(0, 0, 0, 0.6))
		if i == wi and not ship.mech: ctrl.draw_rect(r, col)
		else: ctrl.draw_rect(r, col, false, 0.6)
		_txt(r.position + Vector2(4, 8), str(i + 1), Color.BLACK if (i == wi and not ship.mech) else col, 8)
	if ship.transforming():
		_txt(c + Vector2(-38, 34), "TRANSFORMING!", Color(1, 0.3 + 0.7 * float(Time.get_ticks_msec() / 120 % 2), 0.2), 10)
	elif ship.mech:
		_txt(c + Vector2(-16, 34), "MECH", Color(0.5, 0.9, 1), 10)
	if ship.drifting:
		_txt(c + Vector2(-14, 46), "DRIFT", Color(1, 0.4, 1), 10)
	var cfg: Dictionary = world.cfg
	if cfg["planet"]:
		var alt: float = ship.global_position.y - cfg["hazard_y"]
		_txt(Vector2(sz.x - 120, sz.y - 46), "ALT %d" % int(alt), Color(0.8, 1, 0.8), 8)
		if cfg["hazard"] != "" and alt < 15.0:
			_txt(c + Vector2(-40, -54), "PULL UP!" if cfg["hazard"] == "water" else "HEAT CRITICAL!", Color.RED, 12)
	_txt(Vector2(sz.x - 60, sz.y - 46), cfg["name"], Color(0.6, 0.6, 0.7), 8)
	var hd: float = Vector2(ship.global_position.x, ship.global_position.z).length() if cfg["planet"] else ship.global_position.length()
	if hd > world.ARENA_RADIUS:
		_txt(c + Vector2(-50, -40), "LEAVING ARENA", Color.RED, 12)
	if not ship.alive:
		_txt(c + Vector2(-70, -20), "DESTROYED - RESPAWNING", Color.RED, 12)
	if Input.is_action_pressed("scoreboard") or not ship.alive:
		_scoreboard(sz)

func _scoreboard(sz: Vector2) -> void:
	var rows: Array = Net.scores.values()
	rows.sort_custom(func(a, b): return a["frags"] > b["frags"])
	var r := Rect2(Vector2(sz.x * 0.5 - 110, 50), Vector2(220, 20 + rows.size() * 11))
	ctrl.draw_rect(r, Color(0, 0, 0, 0.7))
	ctrl.draw_rect(r, WARM, false, 0.6)
	_txt(r.position + Vector2(6, 11), "PILOT", WARM, 8)
	_txt(r.position + Vector2(150, 11), "FRAGS  DEATHS", WARM, 8)
	for i in rows.size():
		var y := r.position.y + 22 + i * 11
		_txt(Vector2(r.position.x + 6, y), str(rows[i]["name"]), Color.WHITE, 8)
		_txt(Vector2(r.position.x + 156, y), str(rows[i]["frags"]), Color.WHITE, 8)
		_txt(Vector2(r.position.x + 186, y), str(rows[i]["deaths"]), Color.WHITE, 8)
