@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/teleporter_mds.png")
class_name MDSGate
extends Area2D
## A room transition, like Hollow Knight's TransitionPoint.
##
## Put one per exit in a room scene and name it like the gate on the world map
## ([code]left1[/code], [code]right1[/code], [code]top1[/code], [code]bot1[/code],
## [code]door1[/code]...). When the player enters it, [signal player_entered] reports
## where to go, read from the [code].idpworld.json[/code] file, so connections are edited
## on the map instead of in every scene:
## [codeblock]
## func _on_gate_player_entered(t: Dictionary) -> void:
##     await load_room(t.scene_path)             # your room loader
##     var entry := MDSGate.find_gate(current_room, t.gate)
##     player.global_position = entry.get_spawn_position() if entry else t.entry_pos
## [/codeblock]
## - [member mode] INTERACT makes a door: it waits for the Interact action and shows a
##   prompt with where it leads.
## - [member link] makes it one end of a map link (an elevator, a stag station, a teleport):
##   it leads to the other end of the link instead of a gate connection.
## - [member transition_scene] plays a cinematic between the rooms ([MDSWorldGame]).
## - An [MDSGateBarrier] can keep it shut until its requirements are met.

## Emitted with {room, gate, scene_path, entry_pos, side, from_room, from_gate} when a
## player body enters (or, for doors, presses Interact). Links add {link: true, requires}.
signal player_entered(transition: Dictionary)

enum Mode { TOUCH, INTERACT }

## World file to read connections from. Empty: the project setting
## [code]interactive_dev_panel/world_file[/code].
@export_file("*.idpworld.json") var world_file := ""
## Gate name on the world map. Empty: this node's name.
@export var gate_name := ""
## Room id on the world map. Empty: looked up from the owning scene's path.
@export var room_id := ""
## Bodies in this group trigger the transition.
@export var player_group: StringName = &"player"
## Distance from the gate, towards the room's inside, where players entering through it
## are placed.
@export var spawn_offset := 96.0
## TOUCH: the player goes through on contact. INTERACT: a door, entered with
## [member interact_action] while the player stands in it.
@export var mode: Mode = Mode.TOUCH
@export var interact_action: StringName = &"ui_up"
## Shown over the gate while the player can use it (INTERACT). [code]{to}[/code] is
## replaced with where it leads.
@export var prompt := "Up: {to}"
## Leads to the other end of a map link (World map > Links) from this room, instead of
## the gate connection. The link can name the gate at each end; else the other room's first
## link gate (or its middle) is the way in.
@export var link := false
## A scene played over everything between the rooms (a travel cinematic). Its root may
## have a [code]play(transition)[/code] method (awaited) or a [code]finished[/code] signal.
@export var transition_scene: PackedScene

var _inside: Node2D
var _prompt: Label

func _ready() -> void:
	add_to_group(&"idp_gate")
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func get_gate_name() -> String:
	return gate_name if not gate_name.is_empty() else String(name)

func get_world() -> MDSWorld:
	var file := world_file
	if file.is_empty():
		file = ProjectSettings.get_setting("interactive_dev_panel/world_file", "")
	return MDSWorld.get_cached(file) if not file.is_empty() else null

func get_room_id() -> String:
	if not room_id.is_empty():
		return room_id
	var world := get_world()
	var scene_owner := owner if owner else get_tree().current_scene
	return world.find_room_by_scene(scene_owner.scene_file_path) if world and scene_owner else ""

## Where this gate leads, or {} when unconnected.
func get_transition() -> Dictionary:
	var world := get_world()
	if not world:
		return {}
	var t := world.get_link_transition(get_room_id(), get_gate_name()) if link else world.get_transition(get_room_id(), get_gate_name())
	if not t.is_empty() and transition_scene:
		t.transition_scene = transition_scene
	return t

## Side of the room the gate is on, from the world map or the gate name.
func get_side() -> String:
	var world := get_world()
	if world and world.has_gate(get_room_id(), get_gate_name()):
		return world.get_gate_side(get_room_id(), get_gate_name())
	return MDSWorld.side_from_name(get_gate_name())

## Global position to place a player who arrives through this gate. Doors put the player
## on the spot.
func get_spawn_position() -> Vector2:
	if mode == Mode.INTERACT or link:
		return global_position
	var inward := {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bot": Vector2.UP}
	return global_position + inward.get(get_side(), Vector2.ZERO) * spawn_offset

## Finds the gate named [param gate] under [param root] (a loaded room scene).
static func find_gate(root: Node, gate: String) -> MDSGate:
	if root is MDSGate and root.get_gate_name() == gate:
		return root
	for child in root.get_children():
		var found := find_gate(child, gate)
		if found:
			return found
	return null

## The name of where the gate leads, for its prompt: the room's name, else its area.
func destination_name() -> String:
	var t := get_transition()
	var world := get_world()
	if t.is_empty() or not world:
		return ""
	var room_name := str(world.get_room_value(t.room, "name", ""))
	if not room_name.is_empty():
		return room_name
	var area := world.get_room_area(t.room)
	return area if not area.is_empty() else str(t.room)

## Uses the gate now (a door's Interact, or your own trigger).
func use() -> void:
	var t := get_transition()
	if t.is_empty():
		return
	t.from_room = get_room_id()
	t.from_gate = get_gate_name()
	player_entered.emit(t)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(player_group):
		return
	if mode == Mode.TOUCH:
		use()
		return
	_inside = body
	_show_prompt(true)
	set_process(true)

func _on_body_exited(body: Node) -> void:
	if body == _inside:
		_inside = null
		_show_prompt(false)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or mode != Mode.INTERACT:
		set_process(false)
		return
	if _inside and is_instance_valid(_inside) and Input.is_action_just_pressed(interact_action):
		use()

func _show_prompt(on: bool) -> void:
	if prompt.is_empty():
		return
	if on and not _prompt:
		_prompt = Label.new()
		_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt.add_theme_constant_override("outline_size", 6)
		_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
		_prompt.z_index = 40
		add_child(_prompt)
	if _prompt:
		_prompt.text = prompt.replace("{to}", destination_name())
		_prompt.reset_size()
		_prompt.position = Vector2(-_prompt.size.x / 2.0, -110.0)
		_prompt.visible = on
