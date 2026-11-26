extends CanvasLayer
## Pre-match Hangar: pick exactly 2 weapons from the pool of 7. Pad- and keyboard-friendly.
const Weapons := preload("res://scripts/weapons.gd")

signal confirmed(loadout: PackedInt32Array)
signal cancelled

var _picks: Array = []
var _cards: Array = []
var _hint: Label
var _confirm: Button
var _font: Font
var _on_confirm: Callable
var _on_cancel: Callable

func _ready() -> void:
	layer = 20
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "DejaVu Sans", "Arial"])
	_font = sf
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.92)
	root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_top = 10
	box.offset_bottom = -10
	root.add_child(box)
	var title := Label.new()
	title.text = "HANGAR"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.6, 0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Pick 2 weapons. The energy blade is always ready in mech mode."
	sub.add_theme_font_size_override("font_size", 10)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for i in Weapons.SELECTABLE:
		var card := Button.new()
		card.custom_minimum_size = Vector2(78, 110)
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_ALL
		card.set_meta("wid", i)
		card.toggled.connect(_on_toggle.bind(i, card))
		card.draw.connect(_draw_card.bind(card, i))
		card.tooltip_text = Weapons.LIST[i]["name"]
		row.add_child(card)
		_cards.append(card)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	box.add_child(btns)
	var back := Button.new()
	back.text = "BACK  (B / Esc)"
	back.add_theme_font_size_override("font_size", 10)
	back.pressed.connect(func(): _close_cancel())
	btns.add_child(back)
	_confirm = Button.new()
	_confirm.text = "LAUNCH  (A / Enter)"
	_confirm.add_theme_font_size_override("font_size", 10)
	_confirm.pressed.connect(_try_confirm)
	btns.add_child(_confirm)
	hide()

func open(on_ok: Callable, on_back: Callable) -> void:
	_on_confirm = on_ok
	_on_cancel = on_back
	_picks = []
	for w in Net.loadout:
		if int(w) not in _picks and _picks.size() < 2:
			_picks.append(int(w))
	for i in _cards.size():
		_cards[i].set_pressed_no_signal(i in _picks)
	_refresh_hint()
	show()
	Net.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var focus_i := int(_picks[0]) if _picks.size() > 0 else 0
	_cards[focus_i].grab_focus()

func _draw_card(card: Button, w: int) -> void:
	var r := Rect2(Vector2(8, 8), Vector2(card.size.x - 16, 52))
	card.draw_rect(r, Color(0, 0, 0, 0.45))
	Weapons.draw_icon(card, r, w, Weapons.LIST[w]["col"])
	var title := "%d  %s" % [w + 1, Weapons.LIST[w]["name"]]
	card.draw_string(_font, Vector2(6, 74), title, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 12, 8, Color.WHITE)
	var am: int = Weapons.LIST[w]["start"]
	var ammo := "INF" if am < 0 else "AMMO %d" % am
	card.draw_string(_font, Vector2(6, 88), ammo, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 12, 8, Color(0.7, 0.7, 0.8))
	if w in _picks:
		var slot := _picks.find(w) + 1
		card.draw_string(_font, Vector2(6, 102), "SLOT %d" % slot, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 12, 9, Color(1, 0.7, 0.2))
		card.draw_rect(Rect2(Vector2.ZERO, card.size), Color(1, 0.6, 0.15), false, 1.5)

func _on_toggle(on: bool, w: int, card: Button) -> void:
	if on:
		if w in _picks:
			return
		if _picks.size() >= 2:
			# replace the older pick so you can always change a slot
			_picks.pop_front()
			for c in _cards:
				var id: int = c.get_meta("wid")
				c.set_pressed_no_signal(id in _picks or id == w)
		_picks.append(w)
	else:
		_picks.erase(w)
	_refresh_hint()
	for c in _cards:
		c.queue_redraw()
	if on and _picks.size() == 2:
		_confirm.call_deferred("grab_focus")

func _refresh_hint() -> void:
	if _picks.size() == 2:
		_hint.text = "Ready: %s  +  %s.  Move with arrows / D-pad, A or Enter to toggle, Launch to fly." % [
			Weapons.LIST[_picks[0]]["name"], Weapons.LIST[_picks[1]]["name"]]
		_confirm.disabled = false
	else:
		_hint.text = "Select two weapons  (%d / 2).  Arrows / D-pad move, A / Enter toggles, B / Esc goes back." % _picks.size()
		_confirm.disabled = true

func _try_confirm() -> void:
	if _picks.size() != 2: return
	Net.loadout = Weapons.sanitize_loadout(PackedInt32Array(_picks))
	Net.save_settings()
	hide()
	if _on_confirm.is_valid():
		_on_confirm.call()

func _close_cancel() -> void:
	hide()
	if _on_cancel.is_valid():
		_on_cancel.call()

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	for i in Weapons.SELECTABLE:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			_cards[i].button_pressed = not (i in _picks)
			get_viewport().set_input_as_handled()
			return
	# Start launches when two are picked; B / Esc goes back. A / Enter toggles the focused card.
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if _picks.size() == 2:
			_try_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_close_cancel()
		get_viewport().set_input_as_handled()
	elif get_viewport().gui_get_focus_owner() == null and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		_cards[0].grab_focus()
