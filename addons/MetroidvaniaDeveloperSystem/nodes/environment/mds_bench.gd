@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/bench.svg")
class_name MDSBench
extends MDSEnvironmentEffect
## A bench to rest on: the save point of a room, after Hollow Knight: Silksong's benches. A
## wrought-iron bench with a cushioned seat and a lantern on a hook, drawn and animated by a
## shader (shaders/environment/bench.gdshader). The lantern flickers and lights the bench, and
## motes drift up in its light.
##
## When the player (a node of [member MDSEnvironmentEffect.affect_groups]) stands at it, a
## warm rim shows and [member prompt_text] floats above it. Pressing one of
## [member rest_actions] (Up) sits the player down:
## - the player is held still on the bench (or its [code]mds_bench_rest(bench)[/code] runs, for
##   a sitting animation of its own) until one of [member leave_actions] is pressed;
## - its health is restored ([code]heal_full()[/code], [code]restore_health()[/code], or
##   [code]health = max_health[/code]), with [member heal_on_rest];
## - the running [MDSWorldGame] saves the game here ([method MDSWorldGame.save_game]), with
##   [member save_on_rest]: a game started again continues on this bench, dying brings the player
##   back to it ([method MDSWorldGame.return_to_save_point]), and the map shows it;
## - the bench glows, threads of light rise from it and a ring of light spreads out.
##
## It is in the [code]bench[/code] and [code]save_point[/code] groups, so the map, the analysis
## and "Play from here" know it as a save point, and in [code]lantern[/code], so it carries a
## light in dark rooms. Place it from the Room view's Effects tool (it stands on the floor where
## you click), or add it like any node.

## The player sat down on the bench (the game was saved, if a game runs and saves).
signal rested(body: Node2D)
## The player got up from the bench.
signal left(body: Node2D)

@export var frame_color := Color(0.17, 0.15, 0.19):
	set(v):
		frame_color = v
		_changed()
@export var trim_color := Color(0.80, 0.63, 0.36):
	set(v):
		trim_color = v
		_changed()
@export var seat_color := Color(0.42, 0.27, 0.18):
	set(v):
		seat_color = v
		_changed()
@export var cushion_color := Color(0.52, 0.16, 0.22):
	set(v):
		cushion_color = v
		_changed()
## The lantern's light, the glow while resting and the ring of light when saving.
@export var glow_color := Color(1.0, 0.78, 0.46):
	set(v):
		glow_color = v
		_changed()
## A lantern hanging from a hook beside the back.
@export var lantern := true:
	set(v):
		lantern = v
		_changed()
@export_range(0.0, 1.0) var motes := 0.6:
	set(v):
		motes = v
		_changed()
@export_group("Rest")
## Input actions that sit the player down when it is at the bench (the first ones that exist).
@export var rest_actions: PackedStringArray = ["interact", "ui_up", "move_up"]
## Input actions that get the player up again.
@export var leave_actions: PackedStringArray = ["ui_left", "ui_right", "ui_down", "move_left", "move_right", "move_down", "jump", "ui_accept", "ui_cancel"]
## How far (px) to each side of the bench the player can be and still sit down.
@export_range(0.0, 400.0) var reach := 36.0
## Resting saves the game (the running [MDSWorldGame]'s [method MDSWorldGame.save_game]).
@export var save_on_rest := true
## Resting restores the player's health.
@export var heal_on_rest := true
## Shown above the bench while the player is at it ("" for none).
@export var prompt_text := "Rest"
## Shown for a moment after the game is saved here ("" for none).
@export var saved_text := "Game saved"
## Where the player is put when a game loads on this bench, from the bench's feet: up by about
## half the player's height for a player whose origin is its middle (0 for one whose origin is
## its feet).
@export var spawn_offset := Vector2(0, -32)

var _near := 0.0
var _rest := 0.0
var _pulse := 1.0
var _sitter: Node2D
var _sitter_mode := Node.PROCESS_MODE_INHERIT
var _held := false ## the bench holds the sitter still (it has no mds_bench_rest of its own)
var _label: Label
var _saved_for := 0.0

func _init() -> void:
	size = Vector2(300, 240)
	z_index = -1
	add_to_group(&"bench")
	add_to_group(&"save_point")
	add_to_group(&"lantern")

func get_effect_id() -> String:
	return "bench"

## The bench stands on the node's position: [member size] wide and high around its feet, the
## bench itself 0.4 of the width.
func get_effect_rect() -> Rect2:
	return Rect2(Vector2(-size.x * 0.5, -size.y), size)

## Where the player can sit down from: over the bench, [member reach] px to each side.
func get_body_rect() -> Rect2:
	var w := get_bench_width()
	return Rect2(-w * 0.5 - reach, -w * 1.1, w + reach * 2.0, w * 1.1 + 24.0)

## How wide the bench itself is (px): 0.4 of [member size]'s width, as its height allows.
func get_bench_width() -> float:
	return minf(size.x * 0.4, size.y * 0.5)

## Where a game loaded on this bench puts the player.
func get_spawn_position() -> Vector2:
	return global_position + spawn_offset

func _build() -> void:
	add_quad(shader("bench"), get_effect_rect())
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.82))
	_label.add_theme_color_override(&"font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.size = Vector2(200, 24)
	_label.position = Vector2(-100, -get_bench_width() * 0.95 - 30.0)
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_part(_label)

func _update_params() -> void:
	set_param(&"frame_color", frame_color)
	set_param(&"trim_color", trim_color)
	set_param(&"seat_color", seat_color)
	set_param(&"cushion_color", cushion_color)
	set_param(&"glow_color", glow_color)
	set_param(&"lamp", lantern)
	set_param(&"motes", motes)
	set_param(&"bench_width", get_bench_width())

# --- Resting -------------------------------------------------------------------------------------

## The player at the bench, able to sit down (null: none).
func player_at_bench() -> Node2D:
	if Engine.is_editor_hint():
		return null
	for b in bodies_inside():
		return b
	return null

func is_resting() -> bool:
	return is_instance_valid(_sitter)

## Who is resting on the bench (null: nobody).
func get_sitter() -> Node2D:
	return _sitter if is_instance_valid(_sitter) else null

## Sits [param body] down on the bench: held still on it, healed, the game saved here (see the
## class description). Returns whether it sat down.
func rest(body: Node2D) -> bool:
	if not is_instance_valid(body) or is_resting():
		return false
	_sitter = body
	body.global_position.x = global_position.x
	if "velocity" in body:
		body.set("velocity", Vector2.ZERO)
	if body.has_method(&"mds_bench_rest"):
		body.call(&"mds_bench_rest", self)
		_held = false
	else:
		_sitter_mode = body.process_mode
		body.process_mode = Node.PROCESS_MODE_DISABLED
		_held = true
	if heal_on_rest:
		heal(body)
	_pulse = 0.0
	if save_on_rest and MDSWorldGame.instance and MDSWorldGame.instance.is_inside_tree() and not Engine.is_editor_hint():
		if MDSWorldGame.instance.save_game(self) == OK:
			_saved_for = 2.0
	rested.emit(body)
	return true

## Gets the sitter up again.
func leave() -> void:
	if not is_resting():
		_sitter = null
		return
	var body := _sitter
	_sitter = null
	if _held:
		body.process_mode = _sitter_mode
	elif body.has_method(&"mds_bench_leave"):
		body.call(&"mds_bench_leave", self)
	_held = false
	left.emit(body)

## Restores [param body]'s health: its heal_full() or restore_health(), else
## [code]health = max_health[/code].
static func heal(body: Node) -> void:
	if body.has_method(&"heal_full"):
		body.call(&"heal_full")
	elif body.has_method(&"restore_health"):
		body.call(&"restore_health")
	elif "health" in body and "max_health" in body:
		body.set("health", body.get("max_health"))

func _pressed(event: InputEvent, actions: PackedStringArray) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	if is_resting():
		if _pressed(event, leave_actions):
			leave()
			get_viewport().set_input_as_handled()
		return
	if _pressed(event, rest_actions):
		var body := player_at_bench()
		if body and can_affect(body) and rest(body):
			get_viewport().set_input_as_handled()

func _tick(delta: float) -> void:
	var at := player_at_bench() != null
	_near = move_toward(_near, 1.0 if at and not is_resting() else 0.0, delta * 4.0)
	_rest = move_toward(_rest, 1.0 if is_resting() else 0.0, delta * (1.5 if is_resting() else 3.0))
	if _pulse < 1.0:
		_pulse = minf(1.0, _pulse + delta / 1.6)
	set_param(&"near", _near)
	set_param(&"rest", _rest)
	set_param(&"pulse", _pulse)
	if _label:
		_saved_for = maxf(0.0, _saved_for - delta)
		if _saved_for > 0.0 and not saved_text.is_empty():
			_label.text = saved_text
			_label.modulate.a = minf(1.0, _saved_for * 2.0)
		else:
			_label.text = prompt_text
			_label.modulate.a = _near if not prompt_text.is_empty() else 0.0

func _exit_tree() -> void:
	# A sitter held still is let go when the bench goes (its room unloads).
	if is_resting() and _held:
		_sitter.process_mode = _sitter_mode
	_sitter = null
	_held = false
