extends Node
## Global session settings + frag table (replicated by the server via World.cl_scores).
const DEFAULT_PORT := 7777
var player_name := "Pilot"
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

func _ready() -> void:
	load_settings()
	apply_video()

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

func save_settings() -> void:
	invert_y = inv_pitch
	var c := ConfigFile.new()
	for k in SETTINGS:
		c.set_value("settings", k, get(k))
	c.save(CFG_PATH)
var bot_count := 3
var arena := 0
var scores := {} # ship node name -> {"name", "frags", "deaths"}
