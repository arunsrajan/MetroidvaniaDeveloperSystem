@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_gameplay_setup.svg")
class_name MDSGameplaySetup
extends RefCounted
## Project setup of the Gameplay Kit, run by the plugin when the editor starts: input actions,
## collision layer names and the kit's project settings
## ([code]metroidvania_developer_system/gameplay/...[/code]). Only what the project lacks is
## added; nothing is ever removed, and a project's own bindings and names stay as they are.
##
## Input actions: [code]move_left[/code], [code]move_right[/code], [code]move_up[/code],
## [code]move_down[/code], [code]jump[/code], [code]attack[/code], [code]dash[/code],
## [code]special[/code], [code]interact[/code], [code]grapple[/code], [code]map[/code],
## [code]pause[/code] (the names [MDSBench] listens for). A game run without them (a test, a
## project made before the kit) gets them in its InputMap at runtime ([method ensure_runtime_actions]).
##
## Collision layers (numbers are settings, [method layer]): 1 world, 3 player, 4 enemy,
## 5 player_hitbox, 6 enemy_hitbox, 7 player_hurtbox, 8 enemy_hurtbox, 9 interact.

const PREFIX := "metroidvania_developer_system/gameplay/"

## A gamepad button's name, Xbox style ("A", "LB", "Start").
static func button_name(index: int) -> String:
	const NAMES: PackedStringArray = ["A", "B", "X", "Y", "Back", "Guide", "Start", "L3", "R3", "LB", "RB", "Up", "Down", "Left", "Right"]
	return NAMES[index] if index >= 0 and index < NAMES.size() else "Button %d" % index

## Action -> [keys, gamepad buttons, gamepad axes ([axis, direction])]. menu_prev and menu_next
## switch the pause menu's tabs; map_zoom_* and map_pan_* zoom and move its map.
const ACTIONS := {
	"move_left": [[KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]]],
	"move_right": [[KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]]],
	"move_up": [[KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]]],
	"move_down": [[KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]]],
	"jump": [[KEY_Z, KEY_SPACE], [JOY_BUTTON_A], []],
	"attack": [[KEY_X], [JOY_BUTTON_X], []],
	"dash": [[KEY_C], [JOY_BUTTON_RIGHT_SHOULDER], []],
	"special": [[KEY_V], [JOY_BUTTON_Y], []],
	"interact": [[KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], []],
	"grapple": [[KEY_F], [JOY_BUTTON_LEFT_SHOULDER], []],
	"map": [[KEY_TAB], [JOY_BUTTON_BACK], []],
	"pause": [[KEY_ESCAPE], [JOY_BUTTON_START], []],
	"menu_prev": [[KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], []],
	"menu_next": [[KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], []],
	"map_zoom_in": [[KEY_EQUAL, KEY_KP_ADD], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]],
	"map_zoom_out": [[KEY_MINUS, KEY_KP_SUBTRACT], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]]],
	"map_pan_left": [[KEY_J], [], [[JOY_AXIS_RIGHT_X, -1.0]]],
	"map_pan_right": [[KEY_L], [], [[JOY_AXIS_RIGHT_X, 1.0]]],
	"map_pan_up": [[KEY_I], [], [[JOY_AXIS_RIGHT_Y, -1.0]]],
	"map_pan_down": [[KEY_K], [], [[JOY_AXIS_RIGHT_Y, 1.0]]],
}

## Layer name -> default layer number (1 to 32).
const LAYERS := {"world": 1, "player": 3, "enemy": 4, "player_hitbox": 5, "enemy_hitbox": 6, "player_hurtbox": 7, "enemy_hurtbox": 8, "interact": 9}

enum DeathPenalty { NONE, LOSE_PERCENT, CORPSE }
enum Progression { UPGRADES, LEVELS }

## Setting -> [default, type, hint, hint string]. Layers are added from [constant LAYERS].
const SETTINGS := {
	"feel/hitstop": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"feel/hitstop_time_scale": [0.05, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.0,1.0,0.01"],
	"feel/screen_shake": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"feel/hit_flash": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"feel/attack_fx": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"feel/hurt_particles": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"fx/player_color": [Color("#fff7e6"), TYPE_COLOR, PROPERTY_HINT_NONE, ""],
	"fx/player_glow": [Color("#6fd8ff"), TYPE_COLOR, PROPERTY_HINT_NONE, ""],
	"fx/enemy_color": [Color("#ffe3dc"), TYPE_COLOR, PROPERTY_HINT_NONE, ""],
	"fx/enemy_glow": [Color("#ff3b4e"), TYPE_COLOR, PROPERTY_HINT_NONE, ""],
	"fx/particle_glow": [1.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.0,3.0,0.05"],
	"feel/damage_numbers": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"feel/rumble": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"death_penalty": [DeathPenalty.CORPSE, TYPE_INT, PROPERTY_HINT_ENUM, "None,Lose a share,Corpse"],
	"death_penalty_share": [0.5, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.0,1.0,0.05"],
	"death_reverts_to_save": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"progression": [Progression.UPGRADES, TYPE_INT, PROPERTY_HINT_ENUM, "Upgrades,Levels"],
	"equip_at_bench_only": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"debug_keys": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
}

## A kit setting ([code]feel/hitstop[/code], [code]death_penalty[/code]...): the project's, else
## its default.
static func setting(key: String, default: Variant = null) -> Variant:
	var d: Variant = SETTINGS[key][0] if SETTINGS.has(key) else default
	return ProjectSettings.get_setting(PREFIX + key, d)

## The collision layer number (1 to 32) of a kit layer name ("player", "enemy_hurtbox"...).
static func layer(name: String) -> int:
	return int(ProjectSettings.get_setting(PREFIX + "layers/" + name, LAYERS.get(name, 1)))

## The bit of a kit layer, for collision_layer and collision_mask.
static func bit(name: String) -> int:
	return 1 << (clampi(layer(name), 1, 32) - 1)

## What pickups, switches, climbables and water look for: the player's layer, and layer 1 too, so a
## player body of your own left on layer 1 (as MDS's gates expect) works with them.
static func player_detect_mask() -> int:
	return bit("player") | bit("world")

## The events of an action's default bindings.
static func default_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not ACTIONS.has(action):
		return out
	var spec: Array = ACTIONS[action]
	for k in spec[0]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		out.append(e)
	for b in spec[1]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		out.append(e)
	for a in spec[2]:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		out.append(e)
	return out

## Adds the kit's input actions the project lacks to its settings (and saves them, in the
## editor, with [param save]) and to the running InputMap. Returns how many were added.
static func ensure_input_actions(save := true) -> int:
	var added := 0
	for action: String in ACTIONS:
		var key := "input/" + action
		if Engine.is_editor_hint() and not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, {"deadzone": 0.2, "events": default_events(action)})
			added += 1
	if added > 0 and save and Engine.is_editor_hint():
		ProjectSettings.save()
	ensure_runtime_actions()
	return added

## Adds the kit's input actions the running game lacks to its InputMap (not to the project).
static func ensure_runtime_actions() -> int:
	var added := 0
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for e in default_events(action):
			InputMap.action_add_event(action, e)
		added += 1
	return added

## Names the kit's collision layers whose slot has no name yet, and adds the kit's settings the
## project lacks. Returns how many were added.
static func ensure_layer_names(save := true) -> int:
	var added := 0
	for n: String in LAYERS:
		var key := "layer_names/2d_physics/layer_%d" % layer(n)
		if str(ProjectSettings.get_setting(key, "")).is_empty():
			ProjectSettings.set_setting(key, n)
			added += 1
	added += ensure_settings(false)
	if added > 0 and save and Engine.is_editor_hint():
		ProjectSettings.save()
	return added

## Adds the kit's settings (with their defaults and hints) the project lacks.
static func ensure_settings(save := true) -> int:
	var added := 0
	var all := SETTINGS.duplicate()
	for n: String in LAYERS:
		all["layers/" + n] = [LAYERS[n], TYPE_INT, PROPERTY_HINT_RANGE, "1,32,1"]
	for key: String in all:
		var spec: Array = all[key]
		if not ProjectSettings.has_setting(PREFIX + key):
			ProjectSettings.set_setting(PREFIX + key, spec[0])
			added += 1
		ProjectSettings.set_initial_value(PREFIX + key, spec[0])
		ProjectSettings.add_property_info({"name": PREFIX + key, "type": spec[1], "hint": spec[2], "hint_string": spec[3]})
	if added > 0 and save and Engine.is_editor_hint():
		ProjectSettings.save()
	return added

## The text of the first key (or, with [param gamepad], button) bound to [param action], for
## prompts and the ability popup ("X", "Space", "A").
static func glyph(action: StringName, gamepad := false) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if gamepad and e is InputEventJoypadButton:
			return button_name((e as InputEventJoypadButton).button_index)
		if not gamepad and e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
	return ""
