@icon("res://addons/InteractiveDevPanel/assets/labels_idp.png")
class_name IDPWorldGame
extends Node2D
## Game runtime for non-linear worlds: the counterpart of MetSys' MetSysGame, with no
## MetSys dependency. Reads the same .idpworld.json the Map Dev panel edits.
##
## Use it as the root of your game scene (or extend it):
## [codeblock]
## Game (IDPWorldGame)      world_file = "res://world.idpworld.json", starting_room = "Crossroads_01"
## ├── Player               assigned to "player"
## ├── Camera2D             optional; apply_camera_limits() is called on every room change
## └── UI/Map (IDPWorldMapView)   optional; kept up to date automatically
## [/codeblock]
## What it does:
## - Loads one room scene at a time, placed at its world position (so world coordinates
##   are the same in every room and on the map), like Hollow Knight.
## - Follows [IDPGate] transitions: entering a gate loads the target room and puts the
##   player at the entry gate. Gate requirements from the map can be enforced.
## - Optionally switches rooms without gates when the player walks into a touching room.
## - Tracks visited rooms, the current area, abilities and collected objects, with
##   [method get_save_data] / [method set_save_data].
## - Works with the panel's "Play from here" ([method idp_play_from]).

signal room_loaded(room_id: String)
signal room_changed(from_room: String, to_room: String)
signal area_changed(from_area: String, to_area: String)
## Emitted when a gate needs abilities the player doesn't have (see enforce_requirements).
signal transition_blocked(transition: Dictionary, missing: PackedStringArray)
signal ability_gained(ability: String)

@export_file("*.idpworld.json") var world_file := ""
## Room id (as on the map) loaded when the game starts without save data.
@export var starting_room := ""
## Gate the player starts at in the starting room (empty: the room's first save point or
## its middle).
@export var starting_gate := ""
@export var player: Node2D
@export var camera: Camera2D
@export var map_view: IDPWorldMapView
## Refuse gate transitions whose map requirements the player lacks.
@export var enforce_requirements := false
## Load the neighboring room when the player walks into it, without a gate.
@export var seamless_rooms := false
## Fade to black between rooms (seconds, 0 = instant).
@export var fade_time := 0.2
## Ignores gates briefly after arriving, so the player can't bounce straight back.
@export var gate_cooldown := 0.35

var world: IDPWorld
var current_room := ""
var current_area := ""
var room_node: Node2D
var visited_rooms: Dictionary = {}
var abilities: Dictionary = {}
var stored_objects: Dictionary = {}
var changing_room := false

var _cooldown_until := 0
var _fade: ColorRect
var _load_requested := false
var _pending_save: Dictionary = {}

func _ready() -> void:
	if world_file.is_empty():
		world_file = ProjectSettings.get_setting("interactive_dev_panel/world_file", "")
	world = IDPWorld.get_cached(world_file)
	if world.get_room_ids().is_empty():
		push_error("IDPWorldGame: world file '%s' has no rooms." % world_file)
		return
	if fade_time > 0:
		var layer := CanvasLayer.new()
		layer.layer = 100
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_fade)
		add_child(layer)
	if not _pending_save.is_empty():
		_apply_save(_pending_save)
		_pending_save = {}
	_auto_start.call_deferred()

## Loads the starting room unless a save, "Play from here" or your own code already
## asked for a room.
func _auto_start() -> void:
	if _load_requested or not IDPRuntime.active_request.is_empty():
		return
	var room := starting_room if world.has_room(starting_room) else world.get_start_room()
	if not world.has_room(room):
		room = world.get_room_ids()[0]
	load_room(room, starting_gate)

func _physics_process(_delta: float) -> void:
	if not world or changing_room or not player or current_room.is_empty():
		return
	if map_view:
		map_view.set_player(current_room, player.global_position - world.get_origin(current_room))
	if seamless_rooms and not world.room_contains(current_room, player.global_position):
		var next := world.room_at(player.global_position, world.get_room_layer(current_room))
		if not next.is_empty() and next != current_room:
			load_room(next, "", player.global_position)

# --- Rooms --------------------------------------------------------------------------------

## Loads [param room] (a room id, or a scene path on the map). The player is placed at
## [param entry_gate] if given, else at [param world_position] if given, else at the
## room's first save point or middle. Asynchronous: await it or use [signal room_loaded].
func load_room(room: String, entry_gate := "", world_position := Vector2.INF) -> void:
	if changing_room:
		return
	_load_requested = true
	var id := room if world.has_room(room) else world.find_room_by_scene(room)
	var path := world.get_scene_path(id)
	if path.is_empty():
		push_error("IDPWorldGame: room '%s' has no scene." % room)
		return
	changing_room = true
	await _fade_to(1.0)
	if room_node:
		room_node.queue_free()
		await room_node.tree_exited
	room_node = (load(path) as PackedScene).instantiate()
	room_node.position = world.get_origin(id)
	add_child(room_node)
	move_child(room_node, 0)
	for gate in room_node.find_children("*", "Area2D", true, false):
		if not gate is IDPGate:
			continue
		if gate.world_file.is_empty():
			gate.world_file = world_file
		if gate.room_id.is_empty():
			gate.room_id = id
		gate.player_entered.connect(_on_gate_entered)
	var previous := current_room
	current_room = id
	visited_rooms[id] = true
	if player:
		player.global_position = _spawn_position(id, entry_gate, world_position)
		if "velocity" in player:
			player.velocity = Vector2.ZERO
	if camera:
		apply_camera_limits(camera)
	if map_view:
		map_view.mark_visited(id)
	_cooldown_until = Time.get_ticks_msec() + int(gate_cooldown * 1000.0)
	changing_room = false
	var area := world.get_room_area(id)
	if previous != id:
		room_changed.emit(previous, id)
	if area != current_area:
		var old_area := current_area
		current_area = area
		area_changed.emit(old_area, area)
	# Last: awaiting room_loaded means everything above has happened.
	room_loaded.emit(id)
	await _fade_to(0.0)

func _spawn_position(id: String, entry_gate: String, world_position: Vector2) -> Vector2:
	if not entry_gate.is_empty():
		var gate := IDPGate.find_gate(room_node, entry_gate)
		if gate:
			return gate.get_spawn_position()
		if world.has_gate(id, entry_gate):
			var inward := {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bot": Vector2.UP}
			return world.get_gate_world_pos(id, entry_gate) + inward.get(world.get_gate_side(id, entry_gate), Vector2.ZERO) * 96.0
	if world_position != Vector2.INF:
		return world_position
	var save := room_node.find_children("*", "", true, false).filter(func(n: Node) -> bool:
		return n is Node2D and (n.is_in_group(&"save_point") or n.is_in_group(&"bench") or String(n.name).to_lower().contains("savepoint")))
	if not save.is_empty():
		return save[0].global_position
	return world.get_room_label_pos(id)

func _on_gate_entered(t: Dictionary) -> void:
	if changing_room or Time.get_ticks_msec() < _cooldown_until:
		return
	if enforce_requirements:
		var missing: PackedStringArray = []
		for r in world.get_gate(current_room, t.get("from_gate", "")).get("requires", []):
			if not has_ability(r):
				missing.append(r)
		if not missing.is_empty():
			transition_blocked.emit(t, missing)
			return
	load_room(t.room, t.gate)

## World-space bounds of the current room (its rectangles' bounding box).
func get_room_bounds() -> Rect2:
	return world.get_room_bounds(current_room) if world and not current_room.is_empty() else Rect2()

## Clamps [param cam] to the current room, like MetSys' RoomInstance.adjust_camera_limits.
func apply_camera_limits(cam: Camera2D) -> void:
	var b := get_room_bounds()
	cam.limit_left = int(b.position.x)
	cam.limit_top = int(b.position.y)
	cam.limit_right = int(b.end.x)
	cam.limit_bottom = int(b.end.y)

func get_room_name(id := "") -> String:
	id = current_room if id.is_empty() else id
	return str(world.get_room_value(id, "name", id))

func is_room_visited(id: String) -> bool:
	return visited_rooms.has(id)

# --- Abilities and collected objects ---------------------------------------------------------

func grant_ability(ability: String) -> void:
	if not abilities.has(ability):
		abilities[ability] = true
		ability_gained.emit(ability)

func has_ability(ability: String) -> bool:
	return abilities.has(ability)

## Stable id for a node in the current room ("Room_01/Items/HeartPiece"), for
## remembering collected items and opened walls across rooms and saves.
func object_id(node: Node) -> String:
	return "%s/%s" % [current_room, room_node.get_path_to(node) if room_node and room_node.is_ancestor_of(node) else node.name]

func store_object(node_or_id: Variant) -> void:
	stored_objects[node_or_id if node_or_id is String else object_id(node_or_id)] = true

func is_object_stored(node_or_id: Variant) -> bool:
	return stored_objects.has(node_or_id if node_or_id is String else object_id(node_or_id))

# --- Save data ------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var data := {
		"room": current_room,
		"position": [player.global_position.x, player.global_position.y] if player else [0, 0],
		"visited": visited_rooms.keys(),
		"abilities": abilities.keys(),
		"stored": stored_objects.keys(),
	}
	if map_view:
		data.map = map_view.get_save_data()
	return data

## Restores progress and loads the saved room. Can be called before the game enters the
## tree (e.g. by your title screen right after instancing it) or at any time after.
func set_save_data(data: Dictionary) -> void:
	if not world:
		_pending_save = data
		return
	_apply_save(data)

func _apply_save(data: Dictionary) -> void:
	visited_rooms.clear()
	abilities.clear()
	stored_objects.clear()
	for id in data.get("visited", []):
		visited_rooms[id] = true
	for a in data.get("abilities", []):
		abilities[a] = true
	for o in data.get("stored", []):
		stored_objects[o] = true
	if map_view and data.has("map"):
		map_view.set_save_data(data.map)
	var room: String = data.get("room", "")
	if world.has_room(room):
		_load_requested = true
		var p: Array = data.get("position", [])
		load_room.call_deferred(room, "", Vector2(float(p[0]), float(p[1])) if p.size() == 2 else Vector2.INF)

## Called by the Map Dev panel's "Play from here".
func idp_play_from(request: Dictionary) -> void:
	if not world:
		return
	_load_requested = true
	var id := world.find_room_by_scene(request.scene_path)
	await load_room(id, "", world.get_origin(id) + request.position)

func _fade_to(alpha: float) -> void:
	if not _fade or fade_time <= 0 or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, fade_time)
	await tween.finished
