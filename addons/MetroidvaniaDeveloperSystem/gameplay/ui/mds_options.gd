@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_options.svg")
class_name MDSOptions
extends RefCounted
## The player's options, kept in [member path] ([code]user://mds_options.cfg[/code]) and applied
## when the game starts ([MDSGameplay] loads them) and whenever [MDSOptionsMenu] changes one:
## bus volumes, key and button bindings, window mode, and accessibility: game speed, assist mode
## (damage taken ×1, ×0.5 or ×0), screen shake and flash intensity (0 turns them off), camera
## motion (MDS's Glide or Cut, never glide), text size, input glyphs and toggled glide.

enum Glyphs { AUTO, KEYBOARD, GAMEPAD }

const ASSIST_LEVELS: PackedFloat32Array = [1.0, 0.5, 0.0]
const ASSIST_NAMES: PackedStringArray = ["Off", "Half damage", "No damage"]
const TEXT_SCALES: PackedFloat32Array = [1.0, 1.25, 1.5]
const GLYPH_NAMES: PackedStringArray = ["Auto", "Keyboard", "Gamepad"]

## Where the options are kept.
static var path := "user://mds_options.cfg"
## Bus name -> volume (0 to 1).
static var volumes: Dictionary = {}
static var fullscreen := false
static var vsync := true
## 0.5 to 1.0: the game's time scale.
static var game_speed := 1.0
## Index of [constant ASSIST_LEVELS].
static var assist := 0
## 0 to 1: screen shake ([member MDSRoomCamera.shake_scale]).
static var shake := 1.0
## 0 to 1: hit flashes ([member MDSHealth.flash_scale]).
static var flash := 1.0
## [enum MDSRoomCamera.Motion]: GLIDE, or CUT (never glide).
static var camera_motion := 0
## Index of [constant TEXT_SCALES].
static var text_size := 0
static var glyphs: Glyphs = Glyphs.AUTO
## Glide switched on and off by a jump press instead of held ([member MDSPlayerGlideState.toggled]).
static var toggle_glide := false
## Action -> serialized events ([[kind, ...], ...]) the player bound; empty: the project's.
static var bindings: Dictionary = {}

static var _loaded := false
static var _camera_motion_before: Dictionary = {} ## camera instance id -> its own motion

## Loads the options once (later calls do nothing) and applies them.
static func ensure_loaded(tree: SceneTree = null) -> void:
	if _loaded:
		return
	load_options()
	apply(tree)

## Reads [member path] (missing keys keep their defaults).
static func load_options() -> void:
	_loaded = true
	reset()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var v: Variant = cfg.get_value("audio", "volumes", {})
	volumes = (v as Dictionary).duplicate() if v is Dictionary else {}
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	game_speed = clampf(float(cfg.get_value("access", "game_speed", game_speed)), 0.5, 1.0)
	assist = clampi(int(cfg.get_value("access", "assist", assist)), 0, ASSIST_LEVELS.size() - 1)
	shake = clampf(float(cfg.get_value("access", "shake", shake)), 0.0, 1.0)
	flash = clampf(float(cfg.get_value("access", "flash", flash)), 0.0, 1.0)
	camera_motion = clampi(int(cfg.get_value("access", "camera_motion", camera_motion)), 0, 1)
	text_size = clampi(int(cfg.get_value("access", "text_size", text_size)), 0, TEXT_SCALES.size() - 1)
	glyphs = clampi(int(cfg.get_value("access", "glyphs", glyphs)), 0, 2) as Glyphs
	toggle_glide = bool(cfg.get_value("access", "toggle_glide", toggle_glide))
	var b: Variant = cfg.get_value("input", "bindings", {})
	bindings = (b as Dictionary).duplicate(true) if b is Dictionary else {}

## The defaults.
static func reset() -> void:
	volumes = {}
	fullscreen = false
	vsync = true
	game_speed = 1.0
	assist = 0
	shake = 1.0
	flash = 1.0
	camera_motion = 0
	text_size = 0
	glyphs = Glyphs.AUTO
	toggle_glide = false
	bindings = {}

static func save_options() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volumes", volumes)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("access", "game_speed", game_speed)
	cfg.set_value("access", "assist", assist)
	cfg.set_value("access", "shake", shake)
	cfg.set_value("access", "flash", flash)
	cfg.set_value("access", "camera_motion", camera_motion)
	cfg.set_value("access", "text_size", text_size)
	cfg.set_value("access", "glyphs", int(glyphs))
	cfg.set_value("access", "toggle_glide", toggle_glide)
	cfg.set_value("input", "bindings", bindings)
	return cfg.save(path)

## Applies every option (the window only outside the editor and headless runs).
static func apply(tree: SceneTree = null) -> void:
	for bus: String in volumes:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(volumes[bus]), 0.0001)))
			AudioServer.set_bus_mute(i, float(volumes[bus]) <= 0.0)
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN) != fullscreen:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.time_scale = game_speed
	MDSRoomCamera.shake_scale = shake
	MDSHealth.flash_scale = flash
	MDSPlayerGlideState.toggled = toggle_glide
	MDSGameplayUi.get_theme().default_font_size = MDSGameplayUi.font(MDSGameplayUi.BASE_FONT_SIZE)
	for action: String in bindings:
		_apply_binding(action)
	var game := MDSWorldGame.instance
	if game and is_instance_valid(game):
		apply_to_game(game)

## The options that live on the game's nodes: the player's damage taken, the camera's motion.
static func apply_to_game(game: MDSWorldGame) -> void:
	if game.player:
		var h := MDSHealth.of(game.player)
		if h:
			h.damage_taken_multiplier = damage_taken()
	var cam := game.room_camera
	if cam:
		var key := cam.get_instance_id()
		if not _camera_motion_before.has(key):
			_camera_motion_before[key] = int(cam.transition_style)
		var motion: int = MDSRoomCamera.Motion.CUT if camera_motion == MDSRoomCamera.Motion.CUT else int(_camera_motion_before[key])
		cam.transition_style = motion as MDSRoomCamera.Motion
		if cam.camera:
			cam.camera.position_smoothing_enabled = cam.follow_smoothing > 0.0 and not cam.is_cut()

## The share of damage the player takes (assist mode).
static func damage_taken() -> float:
	return ASSIST_LEVELS[clampi(assist, 0, ASSIST_LEVELS.size() - 1)]

static func text_scale() -> float:
	return TEXT_SCALES[clampi(text_size, 0, TEXT_SCALES.size() - 1)]

## Whether glyphs show gamepad buttons: the option, or with AUTO whether a gamepad is connected.
static func use_gamepad_glyphs() -> bool:
	match glyphs:
		Glyphs.KEYBOARD:
			return false
		Glyphs.GAMEPAD:
			return true
	return not Input.get_connected_joypads().is_empty()

static func volume(bus: String) -> float:
	if volumes.has(bus):
		return float(volumes[bus])
	var i := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(i)) if i >= 0 else 1.0

# --- Bindings -------------------------------------------------------------------------------------

## Binds [param event] to [param action], replacing the action's keyboard events (a key) or its
## gamepad events (a button or stick), and keeps it in the options.
static func bind(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action) or not event:
		return
	var pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	var kept: Array = []
	for e in InputMap.action_get_events(action):
		if (e is InputEventJoypadButton or e is InputEventJoypadMotion) != pad:
			kept.append(_serialize(e))
	kept.append(_serialize(event))
	bindings[action] = kept.filter(func(x: Array) -> bool: return not x.is_empty())
	_apply_binding(action)

## The project's own bindings of [param action] come back (all of them: null).
static func unbind(action: String = "") -> void:
	if action.is_empty():
		bindings.clear()
	else:
		bindings.erase(action)
	InputMap.load_from_project_settings()
	MDSGameplaySetup.ensure_runtime_actions()
	for a: String in bindings:
		_apply_binding(a)

static func _apply_binding(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var list: Variant = bindings.get(action, [])
	if not list is Array or (list as Array).is_empty():
		return
	InputMap.action_erase_events(action)
	for s in list:
		var e := _deserialize(s)
		if e:
			InputMap.action_add_event(action, e)

## The keyboard (or with [param pad], gamepad) event bound to [param action] first, or null.
static func get_binding(action: String, pad: bool) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if (e is InputEventJoypadButton or e is InputEventJoypadMotion) == pad:
			return e
	return null

## A short name of [param e] for the screen ("Space", "A", "Left stick right").
static func event_name(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(code)
	if e is InputEventJoypadButton:
		return MDSGameplaySetup.button_name((e as InputEventJoypadButton).button_index)
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return "Axis %d %s" % [m.axis, "+" if m.axis_value > 0 else "-"]
	if e is InputEventMouseButton:
		return "Mouse %d" % (e as InputEventMouseButton).button_index
	return "?"

static func _serialize(e: InputEvent) -> Array:
	if e is InputEventKey:
		var k := e as InputEventKey
		return ["key", int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)]
	if e is InputEventJoypadButton:
		return ["button", (e as InputEventJoypadButton).button_index]
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return ["axis", m.axis, 1.0 if m.axis_value > 0 else -1.0]
	if e is InputEventMouseButton:
		return ["mouse", (e as InputEventMouseButton).button_index]
	return []

static func _deserialize(s: Variant) -> InputEvent:
	if not s is Array or (s as Array).is_empty():
		return null
	var a := s as Array
	match str(a[0]):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(a[1]) as Key
			return k
		"button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(a[1]) as JoyButton
			return b
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(a[1]) as JoyAxis
			m.axis_value = float(a[2])
			return m
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(a[1]) as MouseButton
			return mb
	return null
