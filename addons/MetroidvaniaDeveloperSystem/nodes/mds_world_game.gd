@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSWorldGame
extends Node2D
## Game runtime for non-linear worlds: the counterpart of MetSys' MetSysGame, with no
## MetSys dependency. Reads the same .mdsworld.json the MetDevSys panel edits.
##
## Use it as the root of your game scene (or extend it):
## [codeblock]
## Game (MDSWorldGame)      world_file = "res://world.mdsworld.json", starting_room = "Crossroads_01"
## ├── Player               assigned to "player"
## ├── Camera2D             optional; limited to the room on every room change
## ├── RoomCamera (MDSRoomCamera)  optional; irregular-room camera zones and transitions
##                          (cut, fade, slide, blend) with Camera2D or Phantom Camera
## └── UI/Map (MDSWorldMapView)   optional; kept up to date automatically
## [/codeblock]
## What it does:
## - Loads one room scene at a time, placed at its world position (so world coordinates
##   are the same in every room and on the map), like Hollow Knight.
## - Follows [MDSGate] transitions: entering a gate (or pressing Interact at a door) loads
##   the target room and puts the player at the entry gate. Gate and link requirements from
##   the map can be enforced; map links can be fast-travel pairs; a gate can play a
##   cinematic between rooms.
## - Optionally switches rooms without gates when the player walks into a touching room.
## - Dresses each room as it loads: 2.5D ([MDSDepth25D]), the area's backdrop
##   ([MDSBackdropView]), the area's weather (rain, dust storms, snow... see
##   [MDSEnvironment]), darkness with lights around the player and enemies.
## - Tracks visited rooms, the current area, abilities, collected objects, defeated enemies
##   and bosses, and area objectives, with [method get_save_data] / [method set_save_data].
##   An exploration file keeps the map explored (and the save points found) even when the game
##   isn't saved, so a restarted game shows the map as far as the player got.
## - Markers on the map ([method add_map_marker]): a boss room, a locked door, a key, a quest's
##   target, the player's own pins (placed on the pause menu's map), each with a title and a
##   description; kept like the explored map and shown on every map of the game.
## - Saves the game at save points, like Hollow Knight's benches: [method save_game] writes
##   [member save_file] (an [MDSBench] calls it when the player rests on it) and records the
##   bench as the place to come back to ([method return_to_save_point], after dying). A game
##   started again continues from that save ([member load_on_start]); [method new_game] starts
##   over.
## - Carries followers (the [member carry_over_group]) through gates with the player.
## - Works with the panel's "Play from here" ([method mds_play_from]).

signal room_loaded(room_id: String)
signal room_changed(from_room: String, to_room: String)
signal area_changed(from_area: String, to_area: String)
## Emitted when a gate needs abilities the player doesn't have (see enforce_requirements).
signal transition_blocked(transition: Dictionary, missing: PackedStringArray)
signal ability_gained(ability: String)
## An area's objective ([code]areas[name].objective[/code]) was completed.
signal objective_completed(area: String)
## The game was saved to [member save_file], at [param save_point] (a bench; null: elsewhere).
signal game_saved(save_point: Node)
## A save was loaded (see [method load_game], [member load_on_start]).
signal game_loaded
## A node was recorded as defeated ([method mark_defeated]); [param boss] is the boss's name
## when it was one.
signal defeated(id: String, boss: String)
## Marker [param id] was put on the map (or moved), see [method add_map_marker].
signal map_pin_added(id: String)
## Marker [param id] was taken off the map.
signal map_pin_removed(id: String)

## The running game (the last one that entered the tree), for nodes that need it: title
## cards, music, banners, barriers.
static var instance: MDSWorldGame

@export_file("*.mdsworld.json", "*.idpworld.json") var world_file := ""
## Room id (as on the map) loaded when the game starts without save data.
@export var starting_room := ""
## Gate the player starts at in the starting room (empty: the room's first save point or
## its middle).
@export var starting_gate := ""
@export var player: Node2D
@export var camera: Camera2D
@export var map_view: MDSWorldMapView
## Camera controller for irregular rooms and room transitions. Empty: an MDSRoomCamera
## child if there is one, else the Camera2D is limited to the room's bounding box.
@export var room_camera: MDSRoomCamera
## Refuse gate transitions whose map requirements the player lacks.
@export var enforce_requirements := false
## Load the neighboring room when the player walks into it, without a gate.
@export var seamless_rooms := false
## Fade to black between rooms (seconds, 0 = instant). With a room camera, its
## transition settings are used instead.
@export var fade_time := 0.2
## Ignores gates briefly after arriving, so the player can't bounce straight back.
@export var gate_cooldown := 0.35
## Keep the player's velocity through gates, like Hollow Knight: a run or a jump carries
## into the next room. Off: the player arrives standing still.
@export var keep_momentum := true
## Coming up through a gate in the floor of the next room ("bot" gates), the player gets
## at least this upward speed (px/s), so it clears the hole and can land beside it instead
## of falling straight back. 0 = off.
@export var up_exit_speed := 650.0
## Coming up through a gate in the floor of the next room, the player is set down at the rim
## of the hole, on the nearest floor beside it (within reach of [member up_exit_speed]'s hop),
## as Hollow Knight does: else, with nothing pushing it sideways, it would fall straight back
## through the hole. Rooms with no floor beside the hole keep the player over it.
@export var land_beside_holes := true
## Room scenes may contain a player of their own, to test them on their own (F6). It is
## removed when the room is loaded into the game, which has the real player.
@export var remove_room_players := true

@export_group("Presentation")
## 2.5D in every room ([MDSDepth25D]): as the world settings say ([code]depth_25d[/code]),
## always, or never. A room that has its own MDSDepth25D keeps it.
@export_enum("World setting", "On", "Off") var depth_25d := 0
## Style of the 2.5D. Empty: the world setting [code]depth_style[/code] (a .tres), else the
## defaults.
@export var depth_style: MDSDepthStyle
## Draws the distance behind the rooms: the [MDSBackdrop] of the room
## ([code]rooms[id].backdrop[/code] in the world file), else of its area
## ([code]areas[name].backdrop[/code]), else the world's ([code]settings.backdrop[/code]).
## Empty: made when a backdrop is needed.
@export var backdrop_view: MDSBackdropView
## Dim dark rooms ([code]darkness[/code] of the room or its area, see [method get_darkness]).
@export var room_darkness := true
## Add each room's weather as it loads: the room's ([code]rooms[id].weather[/code]), else its
## area's ([code]areas[name].weather[/code]), else the world's ([code]settings.weather[/code]),
## sized to the room (see [MDSEnvironment]).
@export var room_weather := true
## Add each room's parallax background as it loads: the room's
## ([code]rooms[id].parallax[/code]), else its area's, else the world's
## ([code]settings.parallax[/code]), see [MDSParallaxBackground].
@export var room_parallax := true
## Add each room's animated background as it loads: the room's
## ([code]rooms[id].background[/code]); in a boss room its area's or the world's
## [code]boss_background[/code]; else its area's, else the world's
## ([code]settings.background[/code]), see [MDSAnimatedBackground].
@export var room_background := true
## Nodes in these groups carry a soft light in dark rooms (the player, enemies, lanterns).
## The world setting [code]light_groups[/code] replaces the list.
@export var light_groups: PackedStringArray = ["player", "enemy", "lantern"]

@export_group("Persistence")
## Where [method save_game] writes the game, as JSON (resting on a bench saves there). Empty:
## no save file ([method get_save_data] still gives the data, to save it your own way).
@export var save_file := "user://mds_save.json"
## When the game starts, continue from [member save_file] if there is one (at the bench it was
## saved at), else start a new game in [member starting_room]. "Play from here" and a save
## your own code loads first win.
@export var load_on_start := true
## A file of its own that keeps the visited rooms, the map's reveal, the save points found and
## the room the player is in, written as each room is entered: dying or quitting without saving
## never forgets the map, and a restarted game shows it as far as the player got. The editor's
## World map shows it too (Show on map > Explored in the last playtest, see
## [method read_exploration]). Empty: off.
@export var exploration_file := "user://mds_exploration.json"
## Nodes in this group that are near the gate the player leaves through (a guard giving
## chase) come along into the next room, and stay where they end up.
@export var carry_over_group: StringName = &"carry_over"
## How close (px) to the exit gate a node of the carry-over group must be to come along.
@export var carry_over_distance := 400.0

var world: MDSWorld
var current_room := ""
var current_area := ""
var room_node: Node2D
var visited_rooms: Dictionary = {}
var abilities: Dictionary = {}
var stored_objects: Dictionary = {}
var changing_room := false
## How many times each area was entered (an area's first visit is when it is 1).
var area_visits: Dictionary = {}
## Areas whose objective is done.
var completed_objectives: Dictionary = {}
## Object ids of defeated enemies and destroyed things (see [method mark_defeated]).
var defeated_ids: Dictionary = {}
## Names of defeated bosses.
var defeated_bosses: Dictionary = {}
## Followers away from where their room placed them: object id -> {scene, name, room, pos}.
var moved: Dictionary = {}
## Where the player comes back to (the bench last rested on): {room, position (world, [x, y]),
## save_point (its object id)}. Empty: nowhere yet (see [method return_to_save_point]).
var respawn: Dictionary = {}
## The save points (benches) found so far: room id -> list of [x, y] positions in the room.
## Kept in the exploration file and the save, and shown on the map.
var save_points: Dictionary = {}
## Markers on the map: id -> {position: [x, y] (world px), layer, kind, label (its title),
## description, color, icon} (see [method add_map_marker]). Kept like the explored map: in the
## exploration file as soon as they change, and in the save.
var map_pins: Dictionary = {}
## Darkness of the current room (0 = lit).
var darkness := 0.0
## The current room's weather node (null: none), see [method get_weather_spec].
var weather: Node2D
## The current room's parallax background (null: none).
var parallax: Node2D
## The current room's animated background (null: none).
var background: Node2D

var _cooldown_until := 0
var _fade: ColorRect
var _load_requested := false
var _pending_save: Dictionary = {}
var _exit: Dictionary = {} ## the gate being left: {gate, pos, room, to_room, to_gate}
var _arrived_frame := -100
## A gate the player went into while gates were ignored (just arrived): taken once they are
## not, if the player is still in it or went through it, instead of falling out of the room.
var _pending_gate: Dictionary = {}
var _cinema: CanvasLayer

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _ready() -> void:
	if _inside_another_game():
		# A room scene whose root has this script: only the outer game runs.
		push_warning("MDSWorldGame: '%s' was loaded inside another MDSWorldGame. Room scenes should have a plain Node2D root; only the game scene uses MDSWorldGame." % scene_file_path)
		return
	if world_file.is_empty():
		world_file = str(MDSLegacy.get_setting("metroidvania_developer_system/world_file", ""))
	world = MDSWorld.get_cached(world_file)
	if world.get_room_ids().is_empty():
		push_error("MDSWorldGame: world file '%s' has no rooms." % world_file)
		return
	_find_player_and_camera()
	if not room_camera:
		for c in get_children():
			if c is MDSRoomCamera:
				room_camera = c
	if room_camera:
		room_camera.setup(self)
	if fade_time > 0 or room_camera:
		var layer := CanvasLayer.new()
		layer.layer = 100
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_fade)
		add_child(layer)
	get_tree().node_added.connect(_on_node_added)
	_load_exploration()
	if not _pending_save.is_empty():
		_apply_save(_pending_save)
		_pending_save = {}
	_auto_start.call_deferred()

func _inside_another_game() -> bool:
	var n := get_parent()
	while n:
		if n is MDSWorldGame:
			return true
		n = n.get_parent()
	return false

## Unassigned player: the game's node in the "player" group. Unassigned camera: a Camera2D
## under the player.
func _find_player_and_camera() -> void:
	if not player:
		for n in get_tree().get_nodes_in_group(&"player"):
			if n is Node2D and is_ancestor_of(n):
				player = n
				push_warning("MDSWorldGame: 'player' is not assigned; using %s (in the \"player\" group). Assign it in the inspector to be sure." % get_path_to(n))
				break
	if not player:
		push_warning("MDSWorldGame: no player. Assign 'player' (a CharacterBody2D in the \"player\" group); without it, room changes can't move the player and the camera leaves it behind.")
	if not camera and player:
		for c in player.find_children("*", "Camera2D", true, false):
			camera = c
			break

## Loads the starting room unless a save, "Play from here" or your own code already
## asked for a room.
func _auto_start() -> void:
	if _load_requested or not MDSRuntime.active_request.is_empty():
		return
	# Continue where the last save left off.
	if load_on_start and load_game():
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
	if not _pending_gate.is_empty() and _gates_open():
		var t := _pending_gate
		_pending_gate = {}
		var g := MDSGate.find_gate(room_node, t.get("from_gate", "")) if room_node else null
		if g and (g.overlaps_body(player) or went_through(g, player.global_position)):
			_on_gate_entered(t)
			return
	if seamless_rooms and not world.room_contains(current_room, player.global_position):
		var next := world.room_at(player.global_position, world.get_room_layer(current_room))
		if not next.is_empty() and next != current_room:
			# Walking into a touching room: the camera glides over.
			load_room(next, "", player.global_position, MDSRoomCamera.Transition.BLEND if room_camera else -1)

# --- Rooms --------------------------------------------------------------------------------

## Loads [param room] (a room id, or a scene path on the map). The player is placed at
## [param entry_gate] if given, else at [param world_position] if given, else at the
## room's first save point or middle. [param transition] (an [enum MDSRoomCamera.Transition])
## overrides the room camera's transition for this change. Asynchronous: await it or use
## [signal room_loaded].
func load_room(room: String, entry_gate := "", world_position := Vector2.INF, transition := -1) -> void:
	if changing_room:
		return
	_load_requested = true
	var id := room if world.has_room(room) else world.find_room_by_scene(room)
	var path := world.get_scene_path(id)
	if path.is_empty():
		push_error("MDSWorldGame: room '%s' has no scene." % room)
		return
	changing_room = true
	# A player resting on a bench gets up first (the bench holds it still, and the room it is in
	# is about to go).
	for b in find_save_points(room_node):
		if b.has_method(&"is_resting") and b.is_resting():
			b.leave()
	# The player is held still during the transition; its velocity carries over.
	var carried := Vector2.ZERO
	var player_mode := Node.PROCESS_MODE_INHERIT
	if player:
		if "velocity" in player:
			carried = player.velocity
		player_mode = player.process_mode
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var style := transition
	if style < 0:
		style = room_camera.get_room_transition() if room_camera else (MDSRoomCamera.Transition.FADE if fade_time > 0 else MDSRoomCamera.Transition.CUT)
	elif room_camera:
		style = room_camera.get_room_transition(style)
	if room_node == null and style != MDSRoomCamera.Transition.FADE:
		style = MDSRoomCamera.Transition.CUT # nothing to slide or blend from
	var previous_center := room_camera.screen_center() if room_camera and room_camera.camera else Vector2.ZERO
	if style == MDSRoomCamera.Transition.FADE:
		await _fade_to(1.0)
	var old_room := room_node
	if old_room:
		_record_followers(old_room, current_room, id, entry_gate)
		if style == MDSRoomCamera.Transition.SLIDE or style == MDSRoomCamera.Transition.BLEND:
			# Stays visible (but inert) until the camera has moved over.
			old_room.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			old_room.queue_free()
			await old_room.tree_exited
			old_room = null
	_exit = {}
	room_node = (load(path) as PackedScene).instantiate()
	_clean_room(room_node, path)
	_remove_defeated(room_node, id)
	_place_followers(room_node, id, entry_gate)
	room_node.position = world.get_origin(id)
	# Before the room enters the tree: its nodes' _ready may ask for their object_id().
	var previous := current_room
	current_room = id
	add_child(room_node)
	move_child(room_node, 0)
	for gate in room_node.find_children("*", "Area2D", true, false):
		if not gate is MDSGate:
			continue
		if gate.world_file.is_empty():
			gate.world_file = world_file
		if gate.room_id.is_empty():
			gate.room_id = id
		gate.player_entered.connect(_on_gate_entered)
	visited_rooms[id] = true
	_record_save_points(room_node, id)
	_dress_room(room_node, id)
	_pending_gate = {}
	if player:
		# Back in the physics space first: a body moved while it is out of it keeps its old
		# position there, and would land in the entry gate it came through.
		player.process_mode = player_mode
		player.global_position = _spawn_position(id, entry_gate, world_position)
		if "velocity" in player:
			player.velocity = _arrival_velocity(id, entry_gate, carried)
		var entry := MDSGate.find_gate(room_node, entry_gate) if not entry_gate.is_empty() else null
		if land_beside_holes and entry and entry.get_side() == "bot" and entry.mode == MDSGate.Mode.TOUCH and not entry.link:
			await _land_beside_hole(entry, player_mode)
	_warn_missing_gate_nodes(id, path)
	if room_camera:
		await room_camera.enter_room(id, style, previous_center)
	elif camera:
		apply_camera_limits(camera)
	if old_room:
		old_room.queue_free()
	if map_view:
		map_view.mark_visited(id)
	# Every room entered: the room the player is in is kept too (the editor's map shows it).
	_save_exploration()
	_cooldown_until = Time.get_ticks_msec() + int(gate_cooldown * 1000.0)
	_arrived_frame = Engine.get_physics_frames()
	changing_room = false
	var area := world.get_room_area(id)
	if previous != id:
		room_changed.emit(previous, id)
	if area != current_area:
		var old_area := current_area
		current_area = area
		if not area.is_empty():
			area_visits[area] = int(area_visits.get(area, 0)) + 1
		area_changed.emit(old_area, area)
	check_objectives()
	_show_objective_on_map()
	# Last: awaiting room_loaded means everything above has happened.
	room_loaded.emit(id)
	if style == MDSRoomCamera.Transition.FADE:
		await _fade_to(0.0)

## Room scenes are plain scenes: players placed in them for testing are removed, and a
## game script on their root is reported (it would try to run a second game).
func _clean_room(room: Node, path: String) -> void:
	if room is MDSWorldGame:
		push_warning("MDSWorldGame: room scene '%s' has the MDSWorldGame script on its root. Rooms should have a plain Node2D root; only the game scene uses MDSWorldGame." % path)
	if not remove_room_players:
		return
	for n in room.find_children("*", "", true, false):
		if is_instance_valid(n) and n.is_in_group(&"player") and n != player:
			n.get_parent().remove_child(n)
			n.free()

## Presentation added to a room as it loads.
func _dress_room(room: Node2D, id: String) -> void:
	_apply_backdrop(room, id)
	if is_depth_25d_on() and not room.find_children("*", "Node2D", true, false).any(func(n: Node) -> bool: return n is MDSDepth25D):
		var d := MDSDepth25D.new()
		d.name = "Depth25D"
		d.style = depth_style if depth_style else _setting_resource("depth_style") as MDSDepthStyle
		d.room_camera = room_camera
		d.player = player
		room.add_child(d)
	_apply_weather(room, id)
	_apply_background(room, id)
	_apply_parallax(room, id)
	_apply_darkness(room, id)

func is_depth_25d_on() -> bool:
	match depth_25d:
		1:
			return true
		2:
			return false
	return bool(world.get_setting("depth_25d", false))

## The backdrop of a room: its own, else its area's, else the world's.
func get_backdrop_path(id: String) -> String:
	var p := str(world.get_room_value(id, "backdrop", ""))
	if p.is_empty():
		p = str(world.get_areas().get(world.get_room_area(id), {}).get("backdrop", ""))
	if p.is_empty():
		p = str(world.get_setting("backdrop", ""))
	return p

func _apply_backdrop(room: Node2D, id: String) -> void:
	var p := get_backdrop_path(id)
	var res: MDSBackdrop = load(p) as MDSBackdrop if not p.is_empty() and ResourceLoader.exists(p) else null
	if not res and not backdrop_view:
		return
	if not backdrop_view:
		backdrop_view = MDSBackdropView.new()
		backdrop_view.name = "Backdrop"
		add_child(backdrop_view)
	var b := world.get_room_bounds(id)
	backdrop_view.global_position = b.position
	backdrop_view.room = room
	if backdrop_view.backdrop != res or not backdrop_view.room_size.is_equal_approx(b.size):
		backdrop_view.room_size = b.size
		backdrop_view.backdrop = res

## The weather of a room: its own, else its area's, else the world's ("none": off).
func get_weather_spec(id: String) -> String:
	return MDSEnvironment.spec_for_room(world, id)

## Adds the room's weather to it, its effects covering the room's box.
func _apply_weather(room: Node2D, id: String) -> void:
	weather = null
	if not room_weather:
		return
	var spec := get_weather_spec(id)
	if spec.is_empty() or MDSEnvironment.is_none(spec):
		return
	var rects := world.get_local_rects(id)
	if rects.is_empty():
		return
	var b := rects[0]
	for r in rects:
		b = b.merge(r)
	weather = MDSEnvironment.build(spec, b)
	if weather:
		room.add_child(weather)

## Adds the room's parallax background to it.
func _apply_parallax(room: Node2D, id: String) -> void:
	parallax = null
	if not room_parallax:
		return
	var value := MDSEnvironment.parallax_for_room(world, id)
	var rects := world.get_local_rects(id)
	if value.is_empty() or MDSEnvironment.is_none(value) or rects.is_empty():
		return
	var b := rects[0]
	for r in rects:
		b = b.merge(r)
	parallax = MDSEnvironment.build_parallax(value, b)
	if parallax:
		room.add_child(parallax)

## The animated background of a room ("none": off), see
## [method MDSEnvironment.background_for_room].
func get_background_value(id: String) -> String:
	return MDSEnvironment.background_for_room(world, id)

## Adds the room's animated background to it.
func _apply_background(room: Node2D, id: String) -> void:
	background = null
	if not room_background:
		return
	var value := get_background_value(id)
	var rects := world.get_local_rects(id)
	if value.is_empty() or MDSEnvironment.is_none(value) or rects.is_empty():
		return
	var b := rects[0]
	for r in rects:
		b = b.merge(r)
	background = MDSEnvironment.build_background(value, b)
	if background:
		var area := world.get_room_area(id)
		if not area.is_empty():
			MDSEnvironment.apply_area_color(background, world.get_area_color(area))
		room.add_child(background)

## A resource named by a world setting (a res:// path), or null.
func _setting_resource(key: String) -> Resource:
	var p := str(world.get_setting(key, ""))
	return load(p) if not p.is_empty() and ResourceLoader.exists(p) else null

# --- Darkness and lights ------------------------------------------------------------------------

## How dark a room is: its [code]darkness[/code] (0 lit, 0.05 to 0.8 dimmed, -1 automatic),
## automatic falling back to its area's, and an automatic area to the world: with the world
## setting [code]dark_room_share[/code] (0..1), that share of rooms (picked from the room id,
## so a room is always the same) is dimmed by 0.35 to 0.55.
func get_darkness(id: String) -> float:
	var d := float(world.get_room_value(id, "darkness", -1.0))
	if d < 0.0:
		d = float(world.get_areas().get(world.get_room_area(id), {}).get("darkness", -1.0))
	if d < 0.0:
		var share := float(world.get_setting("dark_room_share", 0.0))
		if share <= 0.0:
			return 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		if rng.randf() >= share:
			return 0.0
		return snappedf(rng.randf_range(0.35, 0.55), 0.05)
	return clampf(d, 0.0, 0.95)

## A dark room gets a subtractive [DirectionalLight2D] (it dims the room's canvas only: the
## HUD and the backdrop are on canvas layers of their own), and the light carriers' lights
## turn on.
func _apply_darkness(room: Node2D, id: String) -> void:
	darkness = get_darkness(id) if room_darkness else 0.0
	if darkness > 0.0:
		var dl := DirectionalLight2D.new()
		dl.name = "MDSDarkness"
		dl.blend_mode = Light2D.BLEND_MODE_SUB
		# A little less blue is taken away: dark rooms read as cool dusk.
		dl.color = Color(1.0, 0.95, 0.8)
		dl.energy = darkness
		room.add_child(dl)
	update_lights()

func _light_groups() -> PackedStringArray:
	var s: Variant = world.get_setting("light_groups", null) if world else null
	return PackedStringArray(s) if s is Array else light_groups

## How a group's light looks: [texture scale, color, energy].
static func light_look(group: String) -> Array:
	match group:
		"player":
			return [1.7, Color(1.0, 0.94, 0.82), 0.95]
		"enemy", "enemies":
			return [0.7, Color(1.0, 0.62, 0.45), 0.55]
	return [1.1, Color(1.0, 0.78, 0.5), 0.7]

## Gives the light carriers of the current room (and the player) their lights, on in dark
## rooms and off in lit ones.
func update_lights() -> void:
	if not is_inside_tree():
		return
	for g in _light_groups():
		for n in get_tree().get_nodes_in_group(g):
			if n is Node2D and (n == player or (room_node and room_node.is_ancestor_of(n))):
				_give_light(n, g)

func _give_light(n: Node2D, group: String) -> void:
	var light := n.get_node_or_null(^"MDSLight") as PointLight2D
	if not light:
		for c in n.get_children():
			if c is PointLight2D:
				return # it brings its own
		if darkness <= 0.0:
			return
		var look := light_look(group)
		light = PointLight2D.new()
		light.name = "MDSLight"
		light.texture = radial_light_texture()
		light.texture_scale = look[0]
		light.color = look[1]
		light.energy = look[2]
		var s := n.global_scale.abs() if n.is_inside_tree() else n.scale.abs()
		light.scale = Vector2(1.0 / maxf(s.x, 0.01), 1.0 / maxf(s.y, 0.01))
		n.add_child(light)
	light.enabled = darkness > 0.0

func _on_node_added(n: Node) -> void:
	if darkness <= 0.0 or not n is Node2D or not room_node or not room_node.is_ancestor_of(n):
		return
	for g in _light_groups():
		if n.is_in_group(g):
			_give_light.call_deferred(n, g)
			return

static var _radial: GradientTexture2D

## A soft round light texture, shared by every light the game adds.
static func radial_light_texture() -> GradientTexture2D:
	if not _radial:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.5, Color(1, 1, 1, 0.45))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_radial = GradientTexture2D.new()
		_radial.gradient = g
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 256
		_radial.height = 256
	return _radial

# --- Arriving -----------------------------------------------------------------------------------

## Velocity on arrival through [param entry_gate]: kept (with keep_momentum), pushed up
## when coming up through a floor gate, never upwards when dropping in through a ceiling.
func _arrival_velocity(id: String, entry_gate: String, carried: Vector2) -> Vector2:
	if entry_gate.is_empty():
		return Vector2.ZERO
	var v := carried if keep_momentum else Vector2.ZERO
	var gate := MDSGate.find_gate(room_node, entry_gate)
	var side := gate.get_side() if gate else (world.get_gate_side(id, entry_gate) if world.has_gate(id, entry_gate) else "")
	if side == "bot" and up_exit_speed > 0.0:
		v.y = minf(v.y, -up_exit_speed)
	elif side == "top":
		v.y = maxf(v.y, 0.0)
	return v

var _warned_gates: Dictionary = {}

## A connected map gate without an MDSGate node in the scene can't be walked through.
func _warn_missing_gate_nodes(id: String, path: String) -> void:
	for g in world.get_gates(id):
		var key := "%s/%s" % [id, g]
		if _warned_gates.has(key) or world.get_transition(id, g).is_empty():
			continue
		if MDSGate.find_gate(room_node, g) == null:
			_warned_gates[key] = true
			push_warning("MDSWorldGame: gate '%s' of room '%s' is connected on the map but %s has no MDSGate node for it, so the player can't leave through it. In MetDevSys, select the room and press Write to scene (Inspect tab)." % [g, id, path])

func _spawn_position(id: String, entry_gate: String, world_position: Vector2) -> Vector2:
	if not entry_gate.is_empty():
		var gate := MDSGate.find_gate(room_node, entry_gate)
		if gate:
			return gate.get_spawn_position()
		if world.has_gate(id, entry_gate):
			var inward := {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bot": Vector2.UP}
			return world.get_gate_world_pos(id, entry_gate) + inward.get(world.get_gate_side(id, entry_gate), Vector2.ZERO) * 96.0
	if world_position != Vector2.INF:
		return world_position
	var save := find_save_points(room_node)
	if not save.is_empty():
		return save[0].get_spawn_position() if save[0].has_method(&"get_spawn_position") else save[0].global_position
	return world.get_room_label_pos(id)

## The save points under [param root] (a room): nodes in the save_point or bench groups, or named
## like one (SavePoint...).
static func find_save_points(root: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not root:
		return out
	for n in root.find_children("*", "", true, false):
		if n is Node2D and (n.is_in_group(&"save_point") or n.is_in_group(&"bench") or String(n.name).to_lower().contains("savepoint")):
			out.append(n)
	return out

## Remembers the save points of room [param id] (for the map). Returns whether it found new ones.
func _record_save_points(room: Node, id: String) -> bool:
	var found: Array = []
	for n in find_save_points(room):
		var local: Vector2 = MDSRoomObjects.local_transform(n, room).origin
		found.append([local.x, local.y])
	if found.is_empty() or save_points.get(id, []) == found:
		return false
	save_points[id] = found
	if map_view and map_view.has_method(&"mark_save_point"):
		for p in found:
			map_view.mark_save_point(id, Vector2(p[0], p[1]))
	return true

## Whether gates lead anywhere now: not while a room changes, nor just after arriving.
func _gates_open() -> bool:
	return not changing_room and Time.get_ticks_msec() >= _cooldown_until and Engine.get_physics_frames() - _arrived_frame >= 3

## Whether [param at] (global) is past gate [param g]: out of the room through its doorway.
static func went_through(g: MDSGate, at: Vector2) -> bool:
	var half := g.get_opening_size() * 0.5 + Vector2(48, 48)
	var d := at - g.global_position
	match g.get_side():
		"bot":
			return d.y > 0.0 and absf(d.x) <= half.x
		"top":
			return d.y < 0.0 and absf(d.x) <= half.x
		"left":
			return d.x < 0.0 and absf(d.y) <= half.y
		"right":
			return d.x > 0.0 and absf(d.y) <= half.y
	return false

## Where a player coming up through bottom gate [param g] stands: on the nearest floor beside
## its hole, at the rim, with room to stand and within reach of the hop out of it (global; INF:
## none). Needs the room's collision in the physics space.
func ledge_beside(g: MDSGate) -> Vector2:
	var space := g.get_world_2d().direct_space_state
	var body := _player_extent()
	var hole := g.get_opening_size().x * 0.5
	var mouth := g.global_position.y
	var gravity := maxf(float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)), 1.0)
	var reach := clampf(up_exit_speed * up_exit_speed / (2.0 * gravity), 96.0, 384.0)
	var exclude: Array[RID] = []
	if player is CollisionObject2D:
		exclude.append((player as CollisionObject2D).get_rid())
	var mask: int = (player as CollisionObject2D).collision_mask if player is CollisionObject2D else 1
	var best := Vector2.INF
	for dir: float in [-1.0, 1.0]:
		for k in 24:
			var x := g.global_position.x + dir * (hole + body.x + 2.0 + k * 8.0)
			var from := Vector2(x, mouth - reach - body.y * 2.0)
			var probe := PhysicsPointQueryParameters2D.new()
			probe.position = from
			probe.collision_mask = mask
			probe.exclude = exclude
			if not space.intersect_point(probe, 1).is_empty():
				continue
			var ray := PhysicsRayQueryParameters2D.create(from, Vector2(x, mouth + 4.0), mask, exclude)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or (hit.normal as Vector2).y > -0.6 or (hit.position as Vector2).y > mouth:
				continue
			var foot: Vector2 = hit.position
			var up := PhysicsRayQueryParameters2D.create(foot + Vector2(0, -1), foot + Vector2(0, -body.y * 2.0 - 4.0), mask, exclude)
			if not space.intersect_ray(up).is_empty():
				continue
			var stand := Vector2(x, foot.y - body.y - 1.0)
			if best == Vector2.INF or absf(x - g.global_position.x) < absf(best.x - g.global_position.x):
				best = stand
			break
	return best

## Half the player's size (px, global): its own get_spawn_extent() (an [MDSPlayer]), else its
## collision shape's, else a 32 x 64 body's.
func _player_extent() -> Vector2:
	if player.has_method(&"get_spawn_extent"):
		return player.call(&"get_spawn_extent")
	for c in player.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape:
			var r := (c as CollisionShape2D).shape.get_rect()
			var k := ((c as CollisionShape2D).global_transform.get_scale()).abs()
			return Vector2(r.size.x * k.x, r.size.y * k.y) * 0.5 + Vector2(absf(c.position.x), 0.0) * k.x
	return Vector2(16, 32)

## Sets the player, come up through [param g], down at the rim of its hole (see
## [method ledge_beside]), once the room's collision is in the physics space. It keeps its hop.
func _land_beside_hole(g: MDSGate, player_mode: int) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	# The room's tiles build their collision at the end of the frame; the next step has it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var at := ledge_beside(g) if is_instance_valid(g) and is_instance_valid(player) else Vector2.INF
	# Back in the physics space before it moves (see load_room).
	player.process_mode = player_mode
	if at != Vector2.INF:
		player.global_position = at

func _on_gate_entered(t: Dictionary) -> void:
	# A teleported CharacterBody2D moves to its new place during the next physics step,
	# passing the gate it came through: arrivals ignore gates for a few physics frames, even
	# with no cooldown. One gone into meanwhile is taken after, if the player is still in it or
	# went through it (else it would fall out of the room).
	if not _gates_open():
		if not changing_room and current_room == t.get("from_room", current_room):
			_pending_gate = t
		return
	if enforce_requirements:
		var missing: PackedStringArray = []
		var reqs: Array = t.get("requires", []) if t.get("link", false) else world.get_gate(current_room, t.get("from_gate", "")).get("requires", [])
		for r in reqs:
			# Abilities, and the other conditions too (item:, flag:, boss:, object:).
			if not is_condition_met(str(r)) and not _opened_by_barrier(str(r)):
				missing.append(r)
		if not missing.is_empty():
			transition_blocked.emit(t, missing)
			return
	var from := MDSGate.find_gate(room_node, t.get("from_gate", "")) if room_node else null
	_exit = {"gate": t.get("from_gate", ""), "pos": from.global_position if from else (player.global_position if player else Vector2.ZERO)}
	var cinematic: PackedScene = t.get("transition_scene")
	if cinematic:
		await play_cinematic(cinematic, t)
	load_room(t.room, t.gate)

## Whether an open [MDSGateBarrier] in the current room asked for [param requirement]: a key
## its door used up ([member MDSGateBarrier.consume_items]) still lets the player through the
## gate behind it.
func _opened_by_barrier(requirement: String) -> bool:
	if not room_node:
		return false
	for b in room_node.find_children("*", "StaticBody2D", true, false):
		if b is MDSGateBarrier and (b as MDSGateBarrier).is_open and (b as MDSGateBarrier).get_requirements().has(requirement):
			return true
	return false

## Plays a cinematic scene between rooms, over everything. Its root may have a method
## [code]play(transition: Dictionary)[/code] (awaited) or a [code]finished[/code] signal;
## else it shows for a second. The player is held still meanwhile.
func play_cinematic(scene: PackedScene, transition := {}) -> void:
	if not _cinema:
		_cinema = CanvasLayer.new()
		_cinema.name = "Cinematic"
		_cinema.layer = 90
		add_child(_cinema)
	var node := scene.instantiate()
	_cinema.add_child(node)
	var mode := player.process_mode if player else Node.PROCESS_MODE_INHERIT
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	if node.has_method("play"):
		await node.call("play", transition)
	elif node.has_signal("finished"):
		await Signal(node, "finished")
	else:
		await get_tree().create_timer(1.0).timeout
	if player:
		player.process_mode = mode
	if is_instance_valid(node):
		node.queue_free()

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
		check_objectives()

func has_ability(ability: String) -> bool:
	return abilities.has(ability)

## Stable id for a node in the current room ("Room_01/Items/HeartPiece"), for
## remembering collected items, opened walls and defeated enemies across rooms and saves. A
## node carried into another room keeps the id it had ([code]mds_object_id[/code] metadata).
func object_id(node: Node) -> String:
	if MDSLegacy.has_meta_key(node, &"mds_object_id"):
		return str(MDSLegacy.get_meta_key(node, &"mds_object_id"))
	return "%s/%s" % [current_room, room_node.get_path_to(node) if room_node and room_node.is_ancestor_of(node) else node.name]

func store_object(node_or_id: Variant) -> void:
	stored_objects[node_or_id if node_or_id is String else object_id(node_or_id)] = true
	check_objectives()

func is_object_stored(node_or_id: Variant) -> bool:
	return stored_objects.has(node_or_id if node_or_id is String else object_id(node_or_id))

# --- Defeated enemies and bosses ------------------------------------------------------------------

## Records an enemy (or anything) as defeated: it stays gone when its room loads again, and
## after saving and loading. A boss (group boss/bosses/mini_boss, or mds_boss_name metadata)
## is also recorded by name, for objectives. Freeing the node is up to the caller.
func mark_defeated(node_or_id: Variant) -> void:
	var id: String = node_or_id if node_or_id is String else object_id(node_or_id)
	defeated_ids[id] = true
	moved.erase(id)
	var boss := ""
	if node_or_id is Node:
		var n := node_or_id as Node
		if MDSLegacy.has_meta_key(n, &"mds_boss_name"):
			boss = str(MDSLegacy.get_meta_key(n, &"mds_boss_name"))
		elif n.is_in_group(&"boss") or n.is_in_group(&"bosses") or n.is_in_group(&"mini_boss"):
			boss = String(n.name)
	if not boss.is_empty():
		defeated_bosses[boss] = true
	defeated.emit(id, boss)
	check_objectives()

func is_defeated(node_or_id: Variant) -> bool:
	return defeated_ids.has(node_or_id if node_or_id is String else object_id(node_or_id))

## Records a boss as defeated by name (when it has no node of its own to pass to
## [method mark_defeated]).
func defeat_boss(boss_name: String) -> void:
	defeated_bosses[boss_name] = true
	defeated.emit("", boss_name)
	check_objectives()

## Whether the boss named [param boss_name] (any letter case) was defeated.
func is_boss_defeated(boss_name: String) -> bool:
	if defeated_bosses.has(boss_name):
		return true
	for b in defeated_bosses:
		if str(b).nocasecmp_to(boss_name) == 0:
			return true
	return false

## Nodes the scene placed that are recorded as defeated are taken out before the room enters
## the tree.
func _remove_defeated(room: Node, id: String) -> void:
	if defeated_ids.is_empty() and moved.is_empty():
		return
	for n in room.find_children("*", "", true, false):
		if not is_instance_valid(n) or n.owner != room:
			continue
		var oid := "%s/%s" % [id, room.get_path_to(n)]
		var gone := defeated_ids.has(oid)
		# A follower that went on into another room isn't here any more.
		if not gone and moved.has(oid) and moved[oid].room != id:
			gone = true
		if gone:
			n.get_parent().remove_child(n)
			n.free()

# --- Followers (carry-over) ----------------------------------------------------------------------

## As a room unloads: its followers near the gate the player leaves through come along; the
## others that have moved stay where they are.
func _record_followers(room: Node, id: String, to_room: String, to_gate: String) -> void:
	if carry_over_group == &"" or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(carry_over_group):
		if not n is Node2D or not room.is_ancestor_of(n) or n.scene_file_path.is_empty():
			continue
		var oid := str(MDSLegacy.get_meta_key(n, &"mds_object_id")) if MDSLegacy.has_meta_key(n, &"mds_object_id") else "%s/%s" % [id, room.get_path_to(n)]
		if defeated_ids.has(oid):
			continue
		var gp: Vector2 = (n as Node2D).global_position
		if not _exit.is_empty() and gp.distance_to(_exit.pos) <= carry_over_distance:
			moved[oid] = {"scene": n.scene_file_path, "name": String(n.name), "room": to_room, "gate": to_gate, "offset": [gp.x - _exit.pos.x, gp.y - _exit.pos.y]}
		elif moved.has(oid) or n.has_meta(&"mds_carried"):
			var local := gp - world.get_origin(id)
			moved[oid] = {"scene": n.scene_file_path, "name": String(n.name), "room": id, "pos": [local.x, local.y]}

## Followers that are in [param id] now: brought along through [param entry_gate], or left
## there earlier.
func _place_followers(room: Node, id: String, entry_gate: String) -> void:
	for oid in moved.keys():
		var e: Dictionary = moved[oid]
		if e.room != id or not ResourceLoader.exists(e.scene) or defeated_ids.has(oid):
			continue
		var node := room.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.owner == room and "%s/%s" % [id, room.get_path_to(n)] == oid)
		var inst: Node2D = node[0] if not node.is_empty() else (load(e.scene) as PackedScene).instantiate() as Node2D
		if not inst:
			continue
		if node.is_empty():
			inst.name = e.name
			inst.set_meta(&"mds_object_id", oid)
			inst.set_meta(&"mds_carried", true)
			room.add_child(inst)
		if e.has("offset"):
			# Just inside the gate the player came through, as far along it as it was.
			var gate_name := str(e.get("gate", entry_gate))
			var gate := MDSGate.find_gate(room, gate_name)
			var side := world.get_gate_side(id, gate_name) if world.has_gate(id, gate_name) else (MDSWorld.side_from_name(gate_name))
			var at := MDSRoomObjects.local_transform(gate, room).origin if gate else world.get_gate_local_pos(id, gate_name)
			var off := Vector2(e.offset[0], e.offset[1])
			var inward: Vector2 = {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bot": Vector2.UP}.get(side, Vector2.ZERO)
			var along := Vector2(0, clampf(off.y, -100.0, 100.0)) if side in ["left", "right"] else Vector2(clampf(off.x, -100.0, 100.0), 0)
			inst.position = at + inward * 32.0 + along
			var local := inst.position
			moved[oid] = {"scene": e.scene, "name": e.name, "room": id, "pos": [local.x, local.y]}
		else:
			inst.position = Vector2(e.pos[0], e.pos[1])

# --- Objectives ----------------------------------------------------------------------------------

## The objective of [param area] ([code]areas[name].objective[/code]), or "".
func get_objective(area: String) -> String:
	return str(world.get_areas().get(area, {}).get("objective", "")) if world else ""

## What completes it ([code]areas[name].objective_done_when[/code]):
## [code]"ability:dash"[/code], [code]"object:Room_01/Chest"[/code] (stored object) or
## [code]"boss:Moss Mother"[/code] (defeated boss). A bare name is an ability.
func get_objective_condition(area: String) -> String:
	return str(world.get_areas().get(area, {}).get("objective_done_when", "")) if world else ""

## [kind ("ability", "object", "boss", "item", "flag"), value] of a condition.
static func parse_condition(condition: String) -> Array:
	return MDSAnnotations.parse_condition(condition)

## Whether [param condition] is met: an ability, a stored object, a defeated boss, and with the
## Gameplay Kit ([MDSGameplay] under the game) an item count or a story flag.
func is_condition_met(condition: String) -> bool:
	if condition.strip_edges().is_empty():
		return false
	var c := parse_condition(condition)
	match c[0]:
		"object":
			return is_object_stored(str(c[1]))
		"boss":
			return is_boss_defeated(str(c[1]))
		"item", "flag":
			var kit := MDSGameplay.find(self)
			return kit != null and kit.is_condition_met(str(c[0]), str(c[1]))
	var ability := str(c[1]).to_lower().replace(" ", "_")
	if has_ability(ability):
		return true
	# Equipment worn can lend an ability.
	var gameplay := MDSGameplay.find(self)
	return gameplay != null and gameplay.has_equipped_ability(ability)

func is_objective_complete(area: String) -> bool:
	return completed_objectives.has(area)

## Marks an area's objective done (also for objectives with no condition).
func complete_objective(area: String) -> void:
	if not completed_objectives.has(area):
		completed_objectives[area] = true
		_show_objective_on_map()
		objective_completed.emit(area)

func _show_objective_on_map() -> void:
	if map_view:
		map_view.objective = get_objective(current_area)
		map_view.objective_done = is_objective_complete(current_area)

## Completes every objective whose condition is now met.
func check_objectives() -> void:
	if not world:
		return
	for area in world.get_areas():
		if not completed_objectives.has(area) and not get_objective(area).is_empty() and is_condition_met(get_objective_condition(area)):
			complete_objective(area)

# --- Exploration file ------------------------------------------------------------------------------

func _load_exploration() -> void:
	if exploration_file.is_empty() or not FileAccess.file_exists(exploration_file):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(exploration_file))
	if not data is Dictionary:
		return
	for id in data.get("visited", []):
		visited_rooms[id] = true
		if map_view:
			map_view.mark_visited(id)
	_merge_save_points(data.get("save_points", {}))
	if map_view:
		for a in data.get("map", {}).get("mapped_areas", []):
			map_view.map_area(a)
	if data.get("pins", {}) is Dictionary:
		map_pins = (data.get("pins", {}) as Dictionary).duplicate(true)
		_show_map_pins()

func _save_exploration() -> void:
	if exploration_file.is_empty():
		return
	var data := {"world": world_file, "visited": visited_rooms.keys(), "save_points": save_points.duplicate(true), "pins": map_pins.duplicate(true)}
	if map_view:
		data.map = map_view.get_save_data()
	if not current_room.is_empty() and player and world and world.has_room(current_room):
		var at := player.global_position - world.get_origin(current_room)
		data.last = {"room": current_room, "position": [at.x, at.y]}
	_write_json(exploration_file, data)

## What a game of [param world] explored last: its exploration file (see [member exploration_file])
## read, {world, visited, save_points, map, last}, with [code]file[/code] (its path) and
## [code]time[/code] (when it was written, Unix seconds) added; empty when there is none. The
## newest file in [param dir] named [code]*exploration.json[/code] that says it is
## [param world]'s wins; a file written before files said whose they are counts when it is
## named after the world (as [method MDSWorldSceneTools.create_game_scene] names it), or is the
## default one.
static func read_exploration(world: MDSWorld, dir := "user://") -> Dictionary:
	var best: Dictionary = {}
	var best_rank := -1
	if not world or not DirAccess.dir_exists_absolute(dir):
		return best
	var named := "%s_exploration.json" % MDSWorldSceneTools.file_stem(world)
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with("exploration.json"):
			continue
		var path := dir.path_join(f)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			continue
		var rank := -1
		if data.has("world"):
			rank = 2 if str(data.world) == world.path else -1
		elif f == named:
			rank = 1
		elif f == "mds_exploration.json":
			rank = 0
		var time := FileAccess.get_modified_time(path)
		if rank < 0 or rank < best_rank or (rank == best_rank and time <= int(best.get("time", 0))):
			continue
		best = data
		best.file = path
		best.time = time
		best_rank = rank
	return best

## Writes [param data] to [param path] as JSON, through a ".tmp" file renamed over it: a crash
## while writing leaves the old file whole.
static func _write_json(path: String, data: Dictionary) -> Error:
	if path.begins_with("res://") or path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if not f:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK and FileAccess.file_exists(path):
		# Some platforms don't rename over a file: the old one goes first.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	return err

## Save points from a file (room -> [[x, y], ...]) join the ones known, and show on the map.
func _merge_save_points(from: Variant) -> void:
	if not from is Dictionary:
		return
	for id in from:
		if not from[id] is Array:
			continue
		save_points[id] = (from[id] as Array).duplicate(true)
		if map_view and map_view.has_method(&"mark_save_point"):
			for p in from[id]:
				if p is Array and p.size() == 2:
					map_view.mark_save_point(id, Vector2(float(p[0]), float(p[1])))

# --- Markers on the map ---------------------------------------------------------------------------

## Puts a marker on the map and returns its id. [param where]: a world position (px), a node (where
## it is) or a room id (the room's middle, on its layer). [param kind] picks its icon and color
## (pin, boss, locked_door, key, quest, danger, treasure, note, or one of
## [method MDSWorldMapView.define_marker_kind]); [param title] is written beside it and
## [param description] shows when the marker is pointed at on the map. [param options]:
## [code]id[/code] (a marker of that id moves there: a quest's target as the quest goes on; else a
## new id is made), [code]layer[/code] (else the room's, or the player's), [code]color[/code] and
## [code]icon[/code] (a Color, and an icon name or a texture, of its own), [code]player[/code]
## (true: a mark of the player's own, which the pause menu's map lets them change and remove; see
## [method is_player_marker]). It is kept at once (the exploration file) and saved with the game.
## [codeblock]
## game.add_map_marker(elder, "quest", "The elder", "Bring him the moss lantern.", {"id": "quest"})
## game.add_map_marker("Shrine_01", "note", "Shrine", "A bench, and a merchant on Sundays.")
## game.add_map_marker(Vector2(4200, 900), "danger", "Thorns", "", {"color": Color.ORANGE})
## [/codeblock]
## For the usual ones: [method mark_boss_room], [method mark_locked_door], [method mark_key],
## [method mark_quest_target].
func add_map_marker(where: Variant, kind := "pin", title := "", description := "", options := {}) -> String:
	var at := _marker_place(where)
	if at.x == INF:
		return ""
	var id := str(options.get("id", ""))
	if id.is_empty():
		var n := map_pins.size() + 1
		while map_pins.has("pin_%d" % n):
			n += 1
		id = "pin_%d" % n
	var map_layer := int(options.get("layer", -1))
	if map_layer < 0:
		map_layer = int(at.z)
	var m := {"position": [at.x, at.y], "layer": map_layer, "kind": kind, "label": title, "description": description}
	if options.get("color") is Color:
		m.color = (options.color as Color).to_html()
	if options.get("icon") is Texture2D:
		m.icon = (options.icon as Texture2D).resource_path
	elif options.has("icon"):
		m.icon = str(options.icon)
	if options.get("player", false):
		m.player = true
	map_pins[id] = m
	if map_view and map_view.has_method(&"set_marker"):
		map_view.set_marker(id, m)
	_save_exploration()
	map_pin_added.emit(id)
	return id

## Where a marker goes: [param where] (a world position, a node, a room id) as x, y (world px)
## and z (its layer); x is INF when it says nowhere.
func _marker_place(where: Variant) -> Vector3:
	var here := world.get_room_layer(current_room) if world and world.has_room(current_room) else 0
	if where is Vector2:
		return Vector3(where.x, where.y, here)
	if where is Node2D and is_instance_valid(where):
		var p: Vector2 = (where as Node2D).global_position
		return Vector3(p.x, p.y, here)
	if (where is String or where is StringName) and world and world.has_room(str(where)):
		var p := world.get_room_label_pos(str(where))
		return Vector3(p.x, p.y, world.get_room_layer(str(where)))
	return Vector3(INF, INF, here)

## Puts a pin on the map at [param world_pos] (world px) and returns its id (see
## [method add_map_marker], with [param label] as its title).
## [codeblock]
## game.add_map_pin(game.player.global_position)                   # the player's own pin
## game.add_map_pin(elder.global_position, "quest", "The elder", "quest_elder")
## game.remove_map_pin("quest_elder")                              # done
## [/codeblock]
func add_map_pin(world_pos: Vector2, kind := "pin", label := "", id := "", map_layer := -1) -> String:
	return add_map_marker(world_pos, kind, label, "", {"id": id, "layer": map_layer})

## Marks boss room [param room_id] (a skull in its middle). [param title]: else the room's boss
## (its "boss" on the map), else "Boss". Its id is [code]boss_<room>[/code], so marking it again
## changes it.
func mark_boss_room(room_id: String, title := "", description := "") -> String:
	if not world or not world.has_room(room_id):
		return ""
	if title.is_empty():
		title = str(world.get_room_value(room_id, "boss", ""))
	if title.is_empty():
		title = "Boss"
	return add_map_marker(room_id, "boss", title, description, {"id": "boss_" + room_id})

## Marks door [param gate_name] of room [param room_id] as locked (a padlock on the gate).
## [param description]: else what the gate needs (its "requires" on the map: "Needs Red Key").
## Its id is [code]door_<room>_<gate>[/code]; take it away as the door opens
## ([method remove_map_pin]).
func mark_locked_door(room_id: String, gate_name: String, title := "Locked door", description := "") -> String:
	if not world or not world.has_gate(room_id, gate_name):
		return ""
	if description.is_empty():
		description = describe_requires(world.get_gate(room_id, gate_name).get("requires", []))
	var at := world.get_gate_world_pos(room_id, gate_name)
	return add_map_marker(at, "locked_door", title, description, {"id": "door_%s_%s" % [room_id, gate_name], "layer": world.get_room_layer(room_id)})

## Marks a key (or any item to fetch) at [param where] (see [method add_map_marker]).
func mark_key(where: Variant, title := "Key", description := "", id := "") -> String:
	return add_map_marker(where, "key", title, description, {"id": id})

## Marks a quest's target at [param where] (see [method add_map_marker]). Its id is
## [param id] ("quest"), so the next target of the quest moves it.
func mark_quest_target(where: Variant, title: String, description := "", id := "quest") -> String:
	return add_map_marker(where, "quest", title, description, {"id": id})

## Marker [param id] ({position, layer, kind, label, description...}), {} when there is none.
func get_map_marker(id: String) -> Dictionary:
	return map_pins.get(id, {})

## What a gate needing [param requires] needs, in words: "Needs Red Key and Dash" ("" for
## nothing).
static func describe_requires(requires: Variant) -> String:
	var names: PackedStringArray = []
	for r in requires if requires is Array or requires is PackedStringArray else []:
		var c := MDSAnnotations.parse_condition(str(r))
		var what := str(c[1])
		match str(c[0]):
			"item":
				what = str(MDSAnnotations.parse_item_requirement(what)[0])
			"boss":
				names.append("defeating " + what)
				continue
		names.append(what.get_file().capitalize())
	if names.is_empty():
		return ""
	return "Needs " + (", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1] if names.size() > 1 else names[0])

## Puts a pin of the player's own where the player is (see [method add_map_marker]).
func pin_player_position(kind := "pin", label := "", description := "") -> String:
	if not player:
		return ""
	return add_map_marker(player.global_position, kind, label, description, {"player": true})

## Whether [param marker] is the player's own (put with [code]player[/code], or a plain "pin"):
## the pause menu's map lets the player change it and take it away.
static func is_player_marker(marker: Dictionary) -> bool:
	return bool(marker.get("player", false)) or str(marker.get("kind", "")) == "pin"

## Takes marker (or pin) [param id] off the map. Returns whether there was one.
func remove_map_pin(id: String) -> bool:
	if not map_pins.erase(id):
		return false
	if map_view and map_view.has_method(&"remove_pin"):
		map_view.remove_pin(id)
	_save_exploration()
	map_pin_removed.emit(id)
	return true

## Takes every marker off the map (of [param kind] only, unless empty).
func clear_map_pins(kind := "") -> void:
	for id: String in map_pins.keys():
		if kind.is_empty() or str(map_pins[id].get("kind", "pin")) == kind:
			remove_map_pin(id)

## Shows [member map_pins] on [member map_view] (after it read a save of its own).
func _show_map_pins() -> void:
	if map_view and map_view.has_method(&"set_pins"):
		map_view.set_pins(map_pins)

## A new game forgets the explored map (the exploration file is deleted).
func reset_exploration() -> void:
	visited_rooms.clear()
	save_points.clear()
	map_pins.clear()
	if map_view:
		map_view.set_save_data({})
	if not exploration_file.is_empty() and FileAccess.file_exists(exploration_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(exploration_file))

# --- Saving at benches ----------------------------------------------------------------------------

## Saves the game to [member save_file]. At [param save_point] (a bench), the player will come
## back there: [method return_to_save_point] takes them back to it. Once a bench was rested on,
## loading a save always puts the player on it, like Hollow Knight, wherever the game was saved
## from. Returns the error ([code]OK[/code] without a save file: the progress is kept in memory
## only).
func save_game(save_point: Node2D = null) -> Error:
	if save_point and not current_room.is_empty():
		var at: Vector2 = save_point.get_spawn_position() if save_point.has_method(&"get_spawn_position") else save_point.global_position
		respawn = {"room": current_room, "position": [at.x, at.y], "save_point": object_id(save_point)}
		if map_view and map_view.has_method(&"set_respawn"):
			map_view.set_respawn(current_room, at - world.get_origin(current_room))
	var data := get_save_data()
	if not respawn.is_empty():
		# Loading the save puts the player on the bench, wherever they were when saving.
		data.room = respawn.room
		data.position = respawn.position
	_save_exploration()
	var err := OK
	if not save_file.is_empty():
		err = _write_json(save_file, data)
	if err == OK:
		game_saved.emit(save_point)
	return err

## Whether [member save_file] holds a save.
func has_save_game() -> bool:
	return not save_file.is_empty() and FileAccess.file_exists(save_file)

## The save in [member save_file] ({} when there is none, or it can't be read).
func read_save_game() -> Dictionary:
	if not has_save_game():
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_file))
	return data if data is Dictionary else {}

## Continues from [member save_file]: progress restored, the player at the bench it was saved at.
## Returns false when there is no save to load.
func load_game() -> bool:
	var data := read_save_game()
	if data.is_empty() or not world or not world.has_room(str(data.get("room", ""))):
		return false
	set_save_data(data)
	game_loaded.emit()
	return true

## Deletes [member save_file].
func delete_save_game() -> void:
	if has_save_game():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_file))

## Starts over: the save and the explored map are deleted, progress is forgotten, and the
## player starts in [member starting_room].
func new_game() -> void:
	delete_save_game()
	reset_exploration()
	_apply_save({})
	var room := starting_room if world.has_room(starting_room) else world.get_start_room()
	if not world.has_room(room):
		room = world.get_room_ids()[0]
	_load_requested = true
	load_room(room, starting_gate)

## Takes the player back to the bench last rested on (after dying, like Hollow Knight), or to
## the starting room when they never rested. Asynchronous: await it or use
## [signal room_loaded].
func return_to_save_point() -> void:
	if respawn.is_empty() or not world.has_room(str(respawn.get("room", ""))):
		var room := starting_room if world.has_room(starting_room) else world.get_start_room()
		await load_room(room, starting_gate)
		return
	var p: Array = respawn.position
	await load_room(respawn.room, "", Vector2(float(p[0]), float(p[1])))

# --- Save data ------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var data := {
		"room": current_room,
		"position": [player.global_position.x, player.global_position.y] if player else [0, 0],
		"visited": visited_rooms.keys(),
		"abilities": abilities.keys(),
		"stored": stored_objects.keys(),
		"areas": area_visits.duplicate(),
		"objectives": completed_objectives.keys(),
		"defeated": defeated_ids.keys(),
		"bosses": defeated_bosses.keys(),
		"moved": moved.duplicate(true),
		"respawn": respawn.duplicate(true),
		"save_points": save_points.duplicate(true),
		"pins": map_pins.duplicate(true),
	}
	if map_view:
		data.map = map_view.get_save_data()
	# Nodes that save data of their own with the game (the Gameplay Kit's MDSGameplay): by key.
	var ext: Dictionary = {}
	for n in _save_extensions():
		ext[_extension_key(n)] = n.call(&"mds_get_save_data")
	if not ext.is_empty():
		data.ext = ext
	return data

## The nodes of the game that save data of their own with it: in the
## [code]mds_save_extension[/code] group, with [code]mds_get_save_data()[/code] and
## [code]mds_set_save_data(data)[/code].
func _save_extensions() -> Array[Node]:
	var out: Array[Node] = []
	var nodes: Array = get_tree().get_nodes_in_group(&"mds_save_extension") if is_inside_tree() else find_children("*", "", true, false)
	for n: Node in nodes:
		if n.is_in_group(&"mds_save_extension") and is_ancestor_of(n) and n.has_method(&"mds_get_save_data"):
			out.append(n)
	return out

## The key a save extension's data has in the save's [code]ext[/code]: its mds_save_key(), else
## its name.
static func _extension_key(n: Node) -> String:
	return str(n.call(&"mds_save_key")) if n.has_method(&"mds_save_key") else String(n.name)

## Restores progress and loads the saved room. Can be called before the game enters the
## tree (e.g. by your title screen right after instancing it) or at any time after. Rooms
## in the exploration file stay visited.
func set_save_data(data: Dictionary) -> void:
	if not world:
		_pending_save = data
		return
	_apply_save(data)

func _apply_save(data: Dictionary) -> void:
	var explored := visited_rooms.duplicate() if not exploration_file.is_empty() else {}
	visited_rooms.clear()
	abilities.clear()
	stored_objects.clear()
	completed_objectives.clear()
	defeated_ids.clear()
	defeated_bosses.clear()
	for id in data.get("visited", []):
		visited_rooms[id] = true
	visited_rooms.merge(explored)
	for a in data.get("abilities", []):
		abilities[a] = true
	for o in data.get("stored", []):
		stored_objects[o] = true
	for a in data.get("objectives", []):
		completed_objectives[a] = true
	for o in data.get("defeated", []):
		defeated_ids[o] = true
	for b in data.get("bosses", []):
		defeated_bosses[b] = true
	area_visits = (data.get("areas", {}) as Dictionary).duplicate()
	moved = (data.get("moved", {}) as Dictionary).duplicate(true)
	respawn = (data.get("respawn", {}) as Dictionary).duplicate(true) if data.get("respawn", {}) is Dictionary else {}
	var known_save_points := save_points.duplicate(true) if not exploration_file.is_empty() else {}
	save_points.clear()
	# Pins: the exploration file's when the game keeps one (they are written there as they change,
	# so a pin taken away after saving stays away), else the save's.
	if exploration_file.is_empty() and data.get("pins", {}) is Dictionary:
		map_pins = (data.get("pins", {}) as Dictionary).duplicate(true)
	if map_view and data.has("map"):
		map_view.set_save_data(data.map)
		for id in explored:
			map_view.mark_visited(id)
	_show_map_pins()
	_merge_save_points(data.get("save_points", {}))
	_merge_save_points(known_save_points)
	if map_view and map_view.has_method(&"set_respawn") and respawn.has("room") and world.has_room(str(respawn.room)):
		var rp: Array = respawn.get("position", [])
		if rp.size() == 2:
			map_view.set_respawn(respawn.room, Vector2(float(rp[0]), float(rp[1])) - world.get_origin(respawn.room))
	# Save extensions get their part ({} for a new game, or a save made without them).
	var ext: Dictionary = data.get("ext", {}) if data.get("ext", {}) is Dictionary else {}
	for n in _save_extensions():
		if n.has_method(&"mds_set_save_data"):
			var part: Variant = ext.get(_extension_key(n), {})
			n.call(&"mds_set_save_data", part if part is Dictionary else {})
	var room: String = data.get("room", "")
	if world.has_room(room):
		_load_requested = true
		var p: Array = data.get("position", [])
		# Coming back into a room after a load isn't a new visit of its area.
		current_area = world.get_room_area(room)
		load_room.call_deferred(room, "", Vector2(float(p[0]), float(p[1])) if p.size() == 2 else Vector2.INF)

## Called by the MetDevSys panel's "Play from here".
func mds_play_from(request: Dictionary) -> void:
	if not world:
		return
	_load_requested = true
	var id := world.find_room_by_scene(request.scene_path)
	await load_room(id, "", world.get_origin(id) + request.position)

func _fade_to(alpha: float) -> void:
	var time := room_camera.transition_time / 2.0 if room_camera else fade_time
	if not _fade or time <= 0 or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, time)
	await tween.finished
