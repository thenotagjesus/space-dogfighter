extends Node
## Global session settings + frag table (replicated by the server via World.cl_scores).
const DEFAULT_PORT := 7777
const VERSION := "v0.4.0"
const Weapons := preload("res://scripts/weapons.gd")
var player_name := "Pilot"
var loadout: PackedInt32Array = PackedInt32Array([0, 4])
var skip_hangar := false  # set by --loadout or headless
var invert_y := false # legacy alias of inv_pitch
var inv_pitch := false
var inv_yaw := false
var inv_roll := false
var inv_mech_y := false
var view := 0 # 0 = chase, 1 = cockpit
var display_mode := 1 # 0 exclusive fullscreen, 1 borderless fullscreen, 2 windowed
var render_scale := 0 # 0 100%, 1 75%, 2 50%, 3 retro 480x270 pixelated
var vsync := true
var msaa := 1 # 0 off, 1 2x, 2 4x
var show_fps := false
var ui_open := false # pause/options overlay is up: ignore flight input
const CFG_PATH := "user://settings.cfg"
const SETTINGS := ["inv_pitch", "inv_yaw", "inv_roll", "inv_mech_y", "view", "display_mode", "render_scale", "vsync", "msaa", "show_fps"]

var debug_input := false
var _toast: Label
var _toast_t := 0.0
var _dbg_events := 0

func _ready() -> void:
	load_settings()
	apply_video()
	debug_input = OS.get_cmdline_user_args().has("--debug-input")
	_ensure_pad_ui_events()
	_build_toast()
	Input.joy_connection_changed.connect(_on_joy_changed)
	_log_joypads("startup")
	# a pad that was already plugged in at launch still gets the toast
	for id in Input.get_connected_joypads():
		show_toast("Controller connected: %s" % Input.get_joy_name(id))

## Pads work on every device id (-1). Make sure menu navigation has pad events too,
## even if a project or engine default ever drops them.
func _ensure_pad_ui_events() -> void:
	var want := {
		"ui_accept": [_jb(JOY_BUTTON_A)],
		"ui_cancel": [_jb(JOY_BUTTON_B)],
		"ui_up": [_jb(JOY_BUTTON_DPAD_UP), _ja(JOY_AXIS_LEFT_Y, -1.0)],
		"ui_down": [_jb(JOY_BUTTON_DPAD_DOWN), _ja(JOY_AXIS_LEFT_Y, 1.0)],
		"ui_left": [_jb(JOY_BUTTON_DPAD_LEFT), _ja(JOY_AXIS_LEFT_X, -1.0)],
		"ui_right": [_jb(JOY_BUTTON_DPAD_RIGHT), _ja(JOY_AXIS_LEFT_X, 1.0)],
	}
	for action in want:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		for ev in want[action]:
			var found := false
			for have in InputMap.action_get_events(action):
				if have is InputEventJoypadButton and ev is InputEventJoypadButton and have.button_index == ev.button_index:
					found = true
				elif have is InputEventJoypadMotion and ev is InputEventJoypadMotion and have.axis == ev.axis and signf(have.axis_value) == signf(ev.axis_value):
					found = true
			if not found:
				InputMap.action_add_event(action, ev)
	# every gameplay binding must be device -1 (all pads); force it in case a binding was saved with an id
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			if (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) and ev.device != -1:
				InputMap.action_erase_event(action, ev)
				ev.device = -1
				InputMap.action_add_event(action, ev)

func _jb(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new(); e.device = -1; e.button_index = b
	return e

func _ja(axis: int, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new(); e.device = -1; e.axis = axis; e.axis_value = v
	return e

func _on_joy_changed(device: int, connected: bool) -> void:
	_log_joypads("connected %d" % device if connected else "disconnected %d" % device)
	if connected:
		show_toast("Controller connected: %s" % Input.get_joy_name(device))
	else:
		show_toast("Controller disconnected")

func _log_joypads(why: String) -> void:
	if not debug_input: return
	var pads := Input.get_connected_joypads()
	print("[input] %s: %d pad(s) %s" % [why, pads.size(), str(pads)])
	for id in pads:
		print("[input]   id=%d name=\"%s\" guid=%s known=%s info=%s" % [id, Input.get_joy_name(id), Input.get_joy_guid(id), Input.is_joy_known(id), str(Input.get_joy_info(id))])

func _input(event: InputEvent) -> void:
	if not debug_input or _dbg_events > 400: return
	if event is InputEventJoypadButton:
		_dbg_events += 1
		print("[input] pad %d button %d %s" % [event.device, event.button_index, "down" if event.pressed else "up"])
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_dbg_events += 1
		print("[input] pad %d axis %d = %.2f" % [event.device, event.axis, event.axis_value])

func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 10)
	_toast.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 3)
	_toast.position = Vector2(8, 340)
	_toast.visible = false
	layer.add_child(_toast)

func show_toast(text: String) -> void:
	if debug_input: print("[input] toast: ", text)
	if _toast == null: return
	_toast.text = text
	_toast.visible = true
	_toast_t = 3.5

func _process(d: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= d
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0: _toast.visible = false

## Apply display settings. Resolution always comes from the monitor, never hardcoded.
func apply_video() -> void:
	var win := get_window()
	var vp := get_viewport()
	# smooth text normally, chunky pixels in retro mode
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST if render_scale == 3 else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	if render_scale == 3:
		# authentic 90s: whole frame at 480x270, nearest-neighbour upscale
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_size = Vector2i(480, 270)
		vp.scaling_3d_scale = 1.0
	else:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_size = Vector2i(640, 360) # HUD/menu layout base, rendered crisp at native res
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [1.0, 0.75, 0.5][render_scale]
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa]
	if DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var scr := DisplayServer.window_get_current_screen()
	var native := DisplayServer.screen_get_size(scr)
	match display_mode:
		0:
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		1:
			win.mode = Window.MODE_FULLSCREEN
		_:
			win.mode = Window.MODE_WINDOWED
			var sz := Vector2i(native * 0.75)
			win.size = sz
			win.position = DisplayServer.screen_get_position(scr) + (native - sz) / 2

func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(CFG_PATH) != OK: return
	for k in SETTINGS:
		set(k, c.get_value("settings", k, get(k)))
	invert_y = inv_pitch
	if c.has_section_key("settings", "loadout"):
		var raw = c.get_value("settings", "loadout", loadout)
		if raw is PackedInt32Array:
			loadout = Weapons.sanitize_loadout(raw)
		elif raw is Array:
			var tmp := PackedInt32Array()
			for v in raw:
				tmp.append(int(v))
			loadout = Weapons.sanitize_loadout(tmp)

func save_settings() -> void:
	invert_y = inv_pitch
	var c := ConfigFile.new()
	for k in SETTINGS:
		c.set_value("settings", k, get(k))
	c.set_value("settings", "loadout", loadout)
	c.save(CFG_PATH)
var bot_count := 3
var arena := 0
var mode := 0 # 0 Dogfight, 1 Horde (co-op waves on a top-down arena)
const MODE_NAMES := ["Dogfight", "Horde (top-down co-op)"]
var scores := {} # ship node name -> {"name", "frags", "deaths"}
