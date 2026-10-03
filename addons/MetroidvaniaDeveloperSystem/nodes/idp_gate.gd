@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/teleporter_idp.png")
class_name IDPGate
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
##     var entry := IDPGate.find_gate(current_room, t.gate)
##     player.global_position = entry.get_spawn_position() if entry else t.entry_pos
## [/codeblock]

## Emitted with {room, gate, scene_path, entry_pos, side, from_room, from_gate} when a
## player body enters.
signal player_entered(transition: Dictionary)

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

func _ready() -> void:
	add_to_group(&"idp_gate")
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)

func get_gate_name() -> String:
	return gate_name if not gate_name.is_empty() else String(name)

func get_world() -> IDPWorld:
	var file := world_file
	if file.is_empty():
		file = ProjectSettings.get_setting("interactive_dev_panel/world_file", "")
	return IDPWorld.get_cached(file) if not file.is_empty() else null

func get_room_id() -> String:
	if not room_id.is_empty():
		return room_id
	var world := get_world()
	var scene_owner := owner if owner else get_tree().current_scene
	return world.find_room_by_scene(scene_owner.scene_file_path) if world and scene_owner else ""

## Where this gate leads, or {} when unconnected.
func get_transition() -> Dictionary:
	var world := get_world()
	return world.get_transition(get_room_id(), get_gate_name()) if world else {}

## Side of the room the gate is on, from the world map or the gate name.
func get_side() -> String:
	var world := get_world()
	if world and world.has_gate(get_room_id(), get_gate_name()):
		return world.get_gate_side(get_room_id(), get_gate_name())
	return IDPWorld.side_from_name(get_gate_name())

## Global position to place a player who arrives through this gate.
func get_spawn_position() -> Vector2:
	var inward := {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bot": Vector2.UP}
	return global_position + inward.get(get_side(), Vector2.ZERO) * spawn_offset

## Finds the gate named [param gate] under [param root] (a loaded room scene).
static func find_gate(root: Node, gate: String) -> IDPGate:
	if root is IDPGate and root.get_gate_name() == gate:
		return root
	for child in root.get_children():
		var found := find_gate(child, gate)
		if found:
			return found
	return null

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(player_group):
		return
	var t := get_transition()
	if not t.is_empty():
		t.from_room = get_room_id()
		t.from_gate = get_gate_name()
		player_entered.emit(t)
