extends Node
## Main menu + session bootstrap (Solo / Host / Join).
const WorldScript := preload("res://scripts/world.gd")
const Arenas := preload("res://scripts/arenas.gd")

var world: Node3D = null
var menu: Control
var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: LineEdit
var bots_spin: SpinBox
var invert_chk: CheckBox
var arena_opt: OptionButton
var overlay: CanvasLayer
var opt_title: Label
var opt_checks := {}
var video_opts := {}
var view_opt: OptionButton
var resume_btn: Button
var leave_btn: Button
var status_lbl: Label

func _ready() -> void:
	_build_menu()
	_build_overlay()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--bots="):
			bots_spin.value = int(a.substr(7))
		elif a.begins_with("--arena="):
			arena_opt.select(clampi(int(a.substr(8)), 0, Arenas.NAMES.size() - 1))
		elif a.begins_with("--view="):
			Net.view = clampi(int(a.substr(7)), 0, 1)
		elif a.begins_with("--video="):
			var p := a.substr(8).split(",")
			Net.display_mode = int(p[0]); Net.render_scale = int(p[1]); Net.msaa = int(p[2]); Net.show_fps = true
			Net.apply_video()
			print("[video] applied ", p, " scale3d=", get_viewport().scaling_3d_scale, " msaa=", get_viewport().msaa_3d, " mode=", get_window().content_scale_mode)
		elif a == "--ui-test":
			get_tree().create_timer(2.0).timeout.connect(func(): open_overlay(world != null); print("[ui] overlay open"))
			get_tree().create_timer(3.0).timeout.connect(func(): opt_checks["inv_yaw"].button_pressed = true; close_overlay(); print("[ui] overlay closed, inv_yaw=", Net.inv_yaw))
		elif a.begins_with("--name="):
			name_edit.text = a.substr(7)
	for a in args:
		if a == "--solo":
			_start_solo()
		elif a == "--host":
			_start_host()
		elif a.begins_with("--join="):
			ip_edit.text = a.substr(7)
			_start_join()

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var box := VBoxContainer.new()
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(cc)
	box.custom_minimum_size = Vector2(220, 0)
	box.add_theme_constant_override("separation", 2)
	cc.add_child(box)
	var title := Label.new()
	title.text = "SPACE DOGFIGHTER"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.6, 0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	name_edit = _field(box, "Pilot name", "Pilot")
	ip_edit = _field(box, "Server IP", "127.0.0.1")
	port_edit = _field(box, "UDP port", str(Net.DEFAULT_PORT))
	var hb := HBoxContainer.new()
	var bl := Label.new(); bl.text = "Bots"; _small(bl); hb.add_child(bl)
	bots_spin = SpinBox.new(); bots_spin.min_value = 0; bots_spin.max_value = 8; bots_spin.value = Net.bot_count
	hb.add_child(bots_spin)
	invert_chk = CheckBox.new(); invert_chk.text = "Invert Y"; _small(invert_chk); hb.add_child(invert_chk)
	invert_chk.button_pressed = Net.inv_pitch
	invert_chk.toggled.connect(func(on): _set_opt("inv_pitch", on))
	box.add_child(hb)
	var ab := HBoxContainer.new()
	var al := Label.new(); al.text = "Arena (host/solo)"; _small(al); ab.add_child(al)
	arena_opt = OptionButton.new(); _small(arena_opt)
	for n in Arenas.NAMES: arena_opt.add_item(n)
	arena_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ab.add_child(arena_opt)
	box.add_child(ab)
	for pair in [["SOLO VS BOTS", _start_solo], ["HOST GAME", _start_host], ["JOIN GAME", _start_join], ["OPTIONS", func(): open_overlay(false)], ["QUIT", func(): get_tree().quit()]]:
		var b := Button.new(); b.text = pair[0]; _small(b)
		b.pressed.connect(pair[1])
		box.add_child(b)
	status_lbl = Label.new(); _small(status_lbl); status_lbl.text = "Gamepad or mouse+keyboard. Esc = release mouse / leave."
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(status_lbl)

# ---------------------------------------------------------------- options / pause overlay
func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 20
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var pc := PanelContainer.new()
	cc.add_child(pc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(200, 0)
	pc.add_child(box)
	opt_title = Label.new()
	opt_title.add_theme_font_size_override("font_size", 16)
	opt_title.add_theme_color_override("font_color", Color(1, 0.6, 0.1))
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(opt_title)
	for pair in [["inv_pitch", "Invert Pitch (Y)"], ["inv_yaw", "Invert Yaw (X)"], ["inv_roll", "Invert Roll"], ["inv_mech_y", "Invert Mech Aim Y"]]:
		var cb := CheckBox.new(); cb.text = pair[1]; _small(cb)
		var key: String = pair[0]
		cb.toggled.connect(func(on): _set_opt(key, on))
		box.add_child(cb)
		opt_checks[key] = cb
	var vh := HBoxContainer.new()
	var vl := Label.new(); vl.text = "Camera"; _small(vl); vh.add_child(vl)
	view_opt = OptionButton.new(); _small(view_opt)
	view_opt.add_item("Chase"); view_opt.add_item("Cockpit")
	view_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_opt.item_selected.connect(func(i): Net.view = i; Net.save_settings())
	vh.add_child(view_opt)
	box.add_child(vh)
	for spec in [["display_mode", "Display", ["Fullscreen", "Borderless", "Windowed"]], ["render_scale", "Render scale", ["100%", "75%", "50%", "Retro 480p"]], ["msaa", "MSAA", ["Off", "2x", "4x"]]]:
		var key: String = spec[0]
		var hh := HBoxContainer.new()
		var ll := Label.new(); ll.text = spec[1]; ll.custom_minimum_size = Vector2(70, 0); _small(ll); hh.add_child(ll)
		var ob := OptionButton.new(); _small(ob)
		for it in spec[2]: ob.add_item(it)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.item_selected.connect(func(i): Net.set(key, i); Net.save_settings(); Net.apply_video())
		hh.add_child(ob)
		box.add_child(hh)
		video_opts[key] = ob
	for pair in [["vsync", "VSync"], ["show_fps", "Show FPS counter"]]:
		var cb := CheckBox.new(); cb.text = pair[1]; _small(cb)
		var key: String = pair[0]
		cb.toggled.connect(func(on): Net.set(key, on); Net.save_settings(); Net.apply_video())
		box.add_child(cb)
		opt_checks[key] = cb
	var note := Label.new(); note.text = "Applies to gamepad and mouse. Saved automatically."; _small(note)
	note.add_theme_font_size_override("font_size", 8)
	box.add_child(note)
	resume_btn = Button.new(); _small(resume_btn)
	resume_btn.pressed.connect(close_overlay)
	box.add_child(resume_btn)
	leave_btn = Button.new(); leave_btn.text = "LEAVE MATCH"; _small(leave_btn)
	leave_btn.pressed.connect(func(): close_overlay(); leave_game())
	box.add_child(leave_btn)
	overlay.hide()

func _set_opt(key: String, on: bool) -> void:
	if key == "vsync" or key == "show_fps": return
	Net.set(key, on)
	Net.save_settings()
	if key == "inv_pitch" and invert_chk.button_pressed != on:
		invert_chk.set_pressed_no_signal(on)

func open_overlay(in_game: bool) -> void:
	for k in opt_checks:
		opt_checks[k].set_pressed_no_signal(Net.get(k))
	view_opt.select(Net.view)
	for k in video_opts: video_opts[k].select(Net.get(k))
	opt_title.text = "PAUSED" if in_game else "OPTIONS"
	resume_btn.text = "RESUME" if in_game else "BACK"
	leave_btn.visible = in_game
	overlay.show()
	Net.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_btn.grab_focus()

func close_overlay() -> void:
	overlay.hide()
	Net.ui_open = false
	invert_chk.set_pressed_no_signal(Net.inv_pitch)
	if world: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _small(c: Control) -> void:
	c.add_theme_font_size_override("font_size", 10)

func _field(parent: Control, label: String, val: String) -> LineEdit:
	var hb := HBoxContainer.new()
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(70, 0); _small(l)
	hb.add_child(l)
	var e := LineEdit.new(); e.text = val; e.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _small(e)
	hb.add_child(e)
	parent.add_child(hb)
	return e

func _apply_settings() -> void:
	Net.player_name = name_edit.text.strip_edges().substr(0, 16)
	if Net.player_name == "": Net.player_name = "Pilot"
	Net.bot_count = int(bots_spin.value)
	Net.arena = arena_opt.selected

func _start_world() -> void:
	if world: return
	world = WorldScript.new()
	world.arena_id = Net.arena
	world.name = "World"
	add_child(world)
	menu.hide()

func _start_solo() -> void:
	_apply_settings()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_world()
	world.server_begin(max(1, Net.bot_count))

func _start_host() -> void:
	_apply_settings()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(int(port_edit.text), 16)
	if err != OK:
		status_lbl.text = "Host failed (err %d) - port in use?" % err
		return
	multiplayer.multiplayer_peer = peer
	print("[net] hosting on UDP ", port_edit.text)
	_start_world()
	world.server_begin(Net.bot_count)

func _start_join() -> void:
	_apply_settings()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_edit.text.strip_edges(), int(port_edit.text))
	if err != OK:
		status_lbl.text = "Join failed (err %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	status_lbl.text = "Connecting..."

func _on_connected() -> void:
	print("[net] connected to server as ", multiplayer.get_unique_id())
	rpc_id(1, "srv_hello")

## Join handshake: ask the server which arena to build before any world traffic.
@rpc("any_peer", "call_remote", "reliable")
func srv_hello() -> void:
	if multiplayer.is_server():
		rpc_id(multiplayer.get_remote_sender_id(), "cl_welcome", Net.arena)

@rpc("authority", "call_remote", "reliable")
func cl_welcome(arena: int) -> void:
	Net.arena = clampi(arena, 0, Arenas.NAMES.size() - 1)
	print("[net] server arena: ", Arenas.NAMES[Net.arena])
	_start_world()
	world.rpc_id(1, "srv_register", Net.player_name)

func _on_conn_failed() -> void:
	leave_game("Connection failed.")

func _on_server_gone() -> void:
	leave_game("Server disconnected.")

func leave_game(msg := "") -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if world:
		world.queue_free()
		world = null
	Net.scores.clear()
	Net.ui_open = false
	overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show()
	if msg != "": status_lbl.text = msg

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if overlay.visible: close_overlay()
		elif world: open_overlay(true)
		get_viewport().set_input_as_handled()
		return
	if world == null or overlay.visible: return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
