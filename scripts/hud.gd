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
	_txt(Vector2(8, 10), Net.VERSION, Color(0.5, 0.55, 0.6), 8)
	if Net.show_fps:
		_txt(Vector2(sz.x - 50, sz.y * 0 + 40), "%d FPS" % Engine.get_frames_per_second(), Color(0.6, 1, 0.6), 8)
	for i in feed.size():
		_txt(Vector2(6, 22 + i * 10), feed[i][0], Color(1, 0.85, 0.4), 8)
	if ship == null or not is_instance_valid(ship):
		_txt(c - Vector2(40, 0), "CONNECTING...", Color.YELLOW, 12)
		return
	if not ship.is_inside_tree(): return   # quitting / tearing down
	var cam: Camera3D = ship.camera
	if ship.damage_flash > 0.0:
		ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0, 0, ship.damage_flash * 0.25))
	# target boxes
	var lock = null
	if ship.alive and ship.is_inside_tree():
		if ship.ALL_RANGE and not ship.mech:
			lock = world.find_lock(ship, ship.AR_LOCK_CONE, ship.AR_LOCK_RANGE)   # tap-shot cone, same as the server
		else:
			lock = world.find_lock(ship)
	if world.horde: _horde_marks(ship, cam, lock)
	for s in world.ships.get_children():
		if s == ship or not s.alive: continue
		if cam.is_position_behind(s.global_position): continue
		var sp := cam.unproject_position(s.global_position)
		var dist: float = s.global_position.distance_to(ship.global_position)
		var r: float = clamp(400.0 / max(dist, 1.0), 4.0, 16.0)
		var col := ACCENT if world.horde else ENEMY   # Horde is co-op: other pilots are wingmen
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
	if ship.mech:
		for i in int(ship.boost_energy / 22.0):  # 22 = ship DASH_COST
			ctrl.draw_rect(Rect2(Vector2(122 + i * 6, sz.y - 18), Vector2(4, 4)), Color(0.4, 0.9, 1))
	_txt(Vector2(sz.x - 120, sz.y - 8), "SPD %d" % int(ship.speed_cur), Color(0.8, 0.8, 1), 8)
	var my = Net.scores.get(String(ship.name), {"frags": 0, "deaths": 0})
	if world.horde:
		_horde_panel(sz, c, ship, my)
	else:
		_txt(Vector2(sz.x - 90, 16), "FRAGS %d" % my["frags"], WARM, 14)
		_txt(Vector2(sz.x - 90, 28), "DEATHS %d" % my["deaths"], Color(0.8, 0.8, 0.8), 8)
	# weapon + ammo strip
	var wi: int = Weapons.MECH_GUN if ship.mech else ship.weapon
	var wd: Dictionary = Weapons.LIST[wi]
	var am: int = ship.ammo[wi]
	_txt(Vector2(sz.x - 150, sz.y - 34), wd["name"], wd["col"], 12)
	_txt(Vector2(sz.x - 150, sz.y - 20), "AMMO " + ("--" if am < 0 else str(am)), Color.WHITE, 8)
	if Weapons.has_slot(ship.loadout, Weapons.MISSILE):
		_txt(Vector2(sz.x - 70, sz.y - 20), "MSL %d" % ship.ammo[Weapons.MISSILE], Color(1, 0.8, 0.3), 8)
	# two loadout slots; icons match the Hangar
	for i in ship.loadout.size():
		var slot: int = int(ship.loadout[i])
		var r := Rect2(Vector2(sz.x * 0.5 - 42 + i * 44, sz.y - 30), Vector2(40, 26))
		var a: int = ship.ammo[slot]
		var col: Color = Weapons.LIST[slot]["col"]
		if a == 0: col = col.darkened(0.7)
		ctrl.draw_rect(r, Color(0, 0, 0, 0.65))
		if slot == wi and not ship.mech:
			ctrl.draw_rect(r, col, false, 1.2)
		else:
			ctrl.draw_rect(r, col, false, 0.6)
		Weapons.draw_icon(ctrl, Rect2(r.position + Vector2(2, 2), Vector2(22, 22)), slot, col)
		_txt(r.position + Vector2(26, 10), str(slot + 1), Color.WHITE if (slot == wi and not ship.mech) else col, 8)
	if ship.transforming():
		_txt(c + Vector2(-38, 34), "TRANSFORMING!", Color(1, 0.3 + 0.7 * float(Time.get_ticks_msec() / 120 % 2), 0.2), 10)
	elif ship.mech:
		_txt(c + Vector2(-16, 34), "MECH", Color(0.5, 0.9, 1), 10)
		if ship.iframe_t > 0.0:
			_txt(c + Vector2(-22, 46), "EVADE", Color(1, 1, 1), 10)
		elif ship.stagger_t > 0.0:
			_txt(c + Vector2(-28, 46), "STAGGER", Color(1, 0.5, 0.3), 10)
		elif ship.open_t > 0.0:
			_txt(c + Vector2(-18, 46), "OPEN", Color(1, 0.4, 0.5), 10)
		elif ship.blade_phase == ship.SP_WINDUP:
			_txt(c + Vector2(-28, 46), "RIPOSTE" if ship.blade_riposte else "BLADE", Color(1, 0.5, 1), 10)
		elif ship.blade_phase == ship.SP_LUNGE:
			_txt(c + Vector2(-16, 46), "LUNGE", Color(1, 0.4, 0.9), 10)
		elif ship.blade_phase == ship.SP_CLASH or ship.blade_phase == ship.SP_PARRY:
			_txt(c + Vector2(-22, 46), "PARRY", Color(0.7, 0.9, 1), 10)
		elif ship.riposte_t > 0.0:
			_txt(c + Vector2(-28, 46), "RIPOSTE", Color(1, 0.85, 0.3), 10)
		elif ship.dash_t > 0.0:
			_txt(c + Vector2(-16, 46), "DASH", Color(0.4, 0.9, 1), 10)
		if ship.mech_hint_t > 0.0:
			var hc := Color(0.75, 0.85, 1, clampf(ship.mech_hint_t, 0.0, 1.0))
			_txt(c + Vector2(-150, 70), "THRUST: RB/LB fwd/back - R-stick strafe/rise (W/S, A/D Q/E, Space/C)", hc, 8)
			_txt(c + Vector2(-150, 80), "DASH: A / Shift, or double-tap a direction - fire mid-dash to cancel + snap aim", hc, 8)
			_txt(c + Vector2(-150, 90), "BLADE: B - windup then lunge. Parry with B as it connects; mistime and you're open. After a parry, B ripostes.", hc, 8)
	if ship.incoming_warn > 0.0:
		_txt(c + Vector2(-52, -44), "INCOMING BLADE!", Color(1, 0.3 + 0.7 * float(Time.get_ticks_msec() / 100 % 2), 0.9, clampf(ship.incoming_warn * 3.0, 0.4, 1.0)), 12)
	if ship.dodge_flash > 0.0:
		_txt(c + Vector2(-24, -30), "DODGE!", Color(0.5, 1, 1, ship.dodge_flash), 12)
	# all-range fighter HUD: meter pips, charge ring, lock reticle, manoeuvre and deflect cues
	if ship.ALL_RANGE and not ship.mech:
		for i in range(4):
			var rect_pos = Vector2(122 + i * 6, sz.y - 18)
			var rect_color = Color(0.4, 0.9, 1) if ship.boost_energy >= (i + 1) * 25 else Color(0.2, 0.3, 0.4)
			ctrl.draw_rect(Rect2(rect_pos, Vector2(4, 4)), rect_color)
		var loop_text_color = Color(0.5, 1, 0.6) if ship.boost_energy >= ship.AR_LOOP_COST and ship.ar_man_cd <= 0 else Color(0.5, 0.5, 0.5)
		var uturn_text_color = Color(0.5, 1, 0.6) if ship.boost_energy >= ship.AR_UTURN_COST and ship.ar_man_cd <= 0 else Color(0.5, 0.5, 0.5)
		_txt(Vector2(150, sz.y - 14), "LOOP", loop_text_color, 7)
		_txt(Vector2(172, sz.y - 14), "U-TURN", uturn_text_color, 7)
		if ship.ar_lock:
			var flicker_alpha = (Time.get_ticks_msec() / 120 % 2) == 0
			_txt(Vector2(8, sz.y - 40), "METER EMPTY", Color(1, 0.4, 0.3, 1.0 if flicker_alpha else 0.25), 8)
			_txt(Vector2(8, sz.y - 32), "RECHARGING TO 25", Color(1, 0.4, 0.3, 1.0 if flicker_alpha else 0.25), 8)
		if ship.charge_t > 0.05:
			var charge_color = Color(1, 1, 0.4) if ship.charge_full else Color(1, 0.8, 0.3)
			var arc_angle = -PI / 2 + TAU * clampf(ship.charge_t / ship.AR_CHARGE_TIME, 0, 1)
			ctrl.draw_arc(c, 18, -PI / 2, arc_angle, 32, charge_color, 1.5)
			if ship.charge_full:
				_txt(c + Vector2(-16, -24), "CHARGED", Color(1, 1, 0.4), 8)
		if ship.lock_tgt != null and is_instance_valid(ship.lock_tgt) and ship.lock_tgt.alive and not cam.is_position_behind(ship.lock_tgt.global_position):
			var sp = cam.unproject_position(ship.lock_tgt.global_position)
			var k = 14 if ship.charge_full else 10
			var rot = Time.get_ticks_msec() / 1000.0 * PI / 4
			var bracket_color = Color(1, 0.3, 0.3) if ship.charge_full else Color(1, 0.9, 0.3)
			ctrl.draw_line(sp + Vector2(k * cos(rot), k * sin(rot)), sp + Vector2(k * cos(rot + PI / 2), k * sin(rot + PI / 2)), bracket_color)
			ctrl.draw_line(sp + Vector2(k * cos(rot + PI / 2), k * sin(rot + PI / 2)), sp + Vector2(k * cos(rot + PI), k * sin(rot + PI)), bracket_color)
			ctrl.draw_line(sp + Vector2(k * cos(rot + PI), k * sin(rot + PI)), sp + Vector2(k * cos(rot + 3 * PI / 2), k * sin(rot + 3 * PI / 2)), bracket_color)
			ctrl.draw_line(sp + Vector2(k * cos(rot + 3 * PI / 2), k * sin(rot + 3 * PI / 2)), sp + Vector2(k * cos(rot), k * sin(rot)), bracket_color)
			ctrl.draw_line(c, sp, Color(bracket_color, 0.25))
		if ship.ar_roll_t > 0:
			_txt(c + Vector2(-26, 46), "ROLL", Color(0.6, 0.9, 1), 10)
		elif ship.ar_man == 1:
			_txt(c + Vector2(-26, 46), "LOOP", Color(0.6, 0.9, 1), 10)
		elif ship.ar_man == 2:
			_txt(c + Vector2(-26, 46), "U-TURN", Color(0.6, 0.9, 1), 10)
		if ship.deflect_flash > 0:
			_txt(c + Vector2(-30, -30), "DEFLECT!", Color(0.6, 1, 1, ship.deflect_flash), 12)
	var cfg: Dictionary = world.cfg
	if cfg["planet"] and not cfg.get("topdown", false):
		var hy: float = cfg["hazard_y"] if cfg["hazard_y"] > -1.0e9 else 0.0   # desert/tech have no hazard floor (-INF)
		var alt: float = ship.global_position.y - hy
		_txt(Vector2(sz.x - 120, sz.y - 46), "ALT %d" % int(alt), Color(0.8, 1, 0.8), 8)
		if cfg["hazard"] != "" and alt < 15.0:
			_txt(c + Vector2(-40, -54), "PULL UP!" if cfg["hazard"] == "water" else "HEAT CRITICAL!", Color.RED, 12)
	_txt(Vector2(sz.x - 60, sz.y - 46), cfg["name"], Color(0.6, 0.6, 0.7), 8)
	var hd: float = Vector2(ship.global_position.x, ship.global_position.z).length() if cfg["planet"] else ship.global_position.length()
	if hd > world.ARENA_RADIUS:
		_txt(c + Vector2(-50, -40), "LEAVING ARENA", Color.RED, 12)
	if not ship.alive:
		_txt(c + Vector2(-70, -20), "DESTROYED - RESPAWNING", Color.RED, 12)
	if world.horde and world.horde.state == world.horde.ST_OVER:
		_high_scores(sz)
	elif Input.is_action_pressed("scoreboard") or not ship.alive:
		_scoreboard(sz)

func _scoreboard(sz: Vector2) -> void:
	var rows: Array = Net.scores.values()
	if world.horde:
		rows.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	else:
		rows.sort_custom(func(a, b): return a["frags"] > b["frags"])
	var r := Rect2(Vector2(sz.x * 0.5 - 110, 50), Vector2(220, 20 + rows.size() * 11))
	ctrl.draw_rect(r, Color(0, 0, 0, 0.7))
	ctrl.draw_rect(r, WARM, false, 0.6)
	_txt(r.position + Vector2(6, 11), "PILOT", WARM, 8)
	_txt(r.position + Vector2(150, 11), "FRAGS  DEATHS", WARM, 8)
	if world.horde: _txt(r.position + Vector2(100, 11), "SCORE", WARM, 8)
	for i in rows.size():
		var y := r.position.y + 22 + i * 11
		_txt(Vector2(r.position.x + 6, y), str(rows[i]["name"]), Color.WHITE, 8)
		if world.horde: _txt(Vector2(r.position.x + 100, y), str(int(rows[i].get("score", 0))), Color(1, 0.9, 0.5), 8)
		_txt(Vector2(r.position.x + 156, y), str(rows[i]["frags"]), Color.WHITE, 8)
		_txt(Vector2(r.position.x + 186, y), str(rows[i]["deaths"]), Color.WHITE, 8)

# ---------------------------------------------------------------- Horde mode
func _horde_marks(ship: Node3D, cam: Camera3D, lock) -> void:
	var h = world.horde
	for e in h.enemies.values():
		if not is_instance_valid(e) or not e.alive or cam.is_position_behind(e.global_position): continue
		var sp := cam.unproject_position(e.global_position)
		var dist: float = e.global_position.distance_to(ship.global_position)
		var r: float = clamp(e.r * 260.0 / max(dist, 1.0), 3.0, 22.0)
		var col := Color(1.0, 0.75, 0.2) if e.type == e.BOSS else ENEMY
		ctrl.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), Color(col, 0.55), false, 0.6)
		if e == lock:
			var k := r + 4.0 + sin(Time.get_ticks_msec() * 0.02) * 2.0
			ctrl.draw_polyline(PackedVector2Array([sp + Vector2(0, -k), sp + Vector2(k, 0), sp + Vector2(0, k), sp + Vector2(-k, 0), sp + Vector2(0, -k)]), Color.YELLOW, 0.6)
	for id in h.drops:
		var dr: Dictionary = h.drops[id]
		var p: Vector3 = dr["pos"]
		if cam.is_position_behind(p): continue
		var dp := cam.unproject_position(p)
		var dc: Color = h.DROP_COLS[int(dr["type"])]
		ctrl.draw_circle(dp, 7.0, Color(dc, 0.18))
		_txt(dp + Vector2(-14, -9), h.DROP_NAMES[int(dr["type"])], dc, 7)

func _horde_panel(sz: Vector2, c: Vector2, ship: Node3D, my: Dictionary) -> void:
	var h = world.horde
	_txt(Vector2(sz.x - 130, 16), "SCORE %d" % int(my.get("score", 0)), WARM, 14)
	var ch := int(my.get("chain", 1))
	if ch > 1:
		_txt(Vector2(sz.x - 130, 30), "CHAIN x%d" % ch, Color(1, 0.4 + 0.6 * float(Time.get_ticks_msec() / 150 % 2), 0.3), 10)
	_txt(Vector2(sz.x - 130, 42), "%s  WAVE %d/%d  LOOP %d" % [h.level_name, max(h.wave, 1), h.WAVES_PER_LEVEL, h.loop + 1], Color(0.8, 0.85, 1), 8)
	var lv := ""
	for i in max(h.lives, 0): lv += "* "
	_txt(Vector2(sz.x - 130, 52), "LIVES " + (lv if lv != "" else "-"), Color(0.5, 1, 0.6), 8)
	if h.banner_t > 0.0 and h.banner != "":
		var a := clampf(h.banner_t * 2.0, 0.0, 1.0)
		var w := font.get_string_size(h.banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_txt(Vector2(c.x - w * 0.5, c.y - 70), h.banner, Color(1, 0.85, 0.3, a), 16)
	if h.boss_frac > 0.0:
		var bw := sz.x * 0.5
		var bp := Vector2(c.x - bw * 0.5, 34)
		ctrl.draw_rect(Rect2(bp, Vector2(bw, 8)), Color(0, 0, 0, 0.65))
		ctrl.draw_rect(Rect2(bp + Vector2(1, 1), Vector2((bw - 2) * h.boss_frac, 6)), Color(1, 0.3, 0.2))
		ctrl.draw_rect(Rect2(bp, Vector2(bw, 8)), Color(1, 0.8, 0.4), false, 0.8)
		_txt(bp + Vector2(0, -3), h.boss_name, Color(1, 0.8, 0.4), 9)
	if ship.overdrive_t > 0.0:
		_txt(c + Vector2(-34, 58), "OVERDRIVE %.0f" % ceilf(ship.overdrive_t), Color(1, 0.35, 1), 10)

func _high_scores(sz: Vector2) -> void:
	var h = world.horde
	var rows: Array = Net.scores.values()
	rows.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var t: Array = h.high_table
	var r := Rect2(Vector2(sz.x * 0.5 - 130, 60), Vector2(260, 46 + (rows.size() + t.size()) * 11))
	ctrl.draw_rect(r, Color(0, 0, 0, 0.8))
	ctrl.draw_rect(r, WARM, false, 0.8)
	_txt(r.position + Vector2(8, 13), "GAME OVER - %s - this run" % h.level_name, WARM, 10)
	var y := r.position.y + 26
	for row in rows:
		_txt(Vector2(r.position.x + 10, y), str(row["name"]), Color.WHITE, 8)
		_txt(Vector2(r.position.x + 180, y), str(int(row.get("score", 0))), Color(1, 0.9, 0.5), 8)
		y += 11
	y += 6
	_txt(Vector2(r.position.x + 8, y), "YOUR HIGH SCORES (this PC)", Color(0.6, 0.9, 1), 8)
	y += 11
	for i in t.size():
		var en: Array = t[i]
		_txt(Vector2(r.position.x + 10, y), "%2d. %s" % [i + 1, str(en[1])], Color.WHITE, 8)
		_txt(Vector2(r.position.x + 120, y), "wave %d loop %d" % [int(en[2]), int(en[3])], Color(0.7, 0.7, 0.8), 7)
		_txt(Vector2(r.position.x + 200, y), str(int(en[0])), Color(1, 0.9, 0.5), 8)
		y += 11
