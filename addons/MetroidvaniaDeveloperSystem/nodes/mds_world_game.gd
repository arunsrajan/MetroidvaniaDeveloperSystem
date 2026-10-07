@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSWorldGame
extends Node2D
## Game runtime for non-linear worlds: the counterpart of MetSys' MetSysGame, with no
## MetSys dependency. Reads the same .idpworld.json the Map Dev panel edits.
##
## Use it as the root of your game scene (or extend it):
## [codeblock]
## Game (MDSWorldGame)      world_file = "res://world.idpworld.json", starting_room = "Crossroads_01"
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
##   An exploration file keeps the map explored even when the game isn't saved.
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
## A node was recorded as defeated ([method mark_defeated]); [param boss] is the boss's name
## when it was one.
signal defeated(id: String, boss: String)

## The running game (the last one that entered the tree), for nodes that need it: title
## cards, music, banners, barriers.
static var instance: MDSWorldGame

@export_file("*.idpworld.json") var world_file := ""
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
## Nodes in these groups carry a soft light in dark rooms (the player, enemies, lanterns).
## The world setting [code]light_groups[/code] replaces the list.
@export var light_groups: PackedStringArray = ["player", "enemy", "lantern"]

@export_group("Persistence")
## A file of its own that keeps the visited rooms and the map's reveal, written as soon as a
## room is first entered: dying or quitting without saving never forgets the map. Empty: off.
@export var exploration_file := ""
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
## Darkness of the current room (0 = lit).
var darkness := 0.0
## The current room's weather node (null: none), see [method get_weather_spec].
var weather: Node2D

var _cooldown_until := 0
var _fade: ColorRect
var _load_requested := false
var _pending_save: Dictionary = {}
var _exit: Dictionary = {} ## the gate being left: {gate, pos, room, to_room, to_gate}
var _arrived_frame := -100
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
		world_file = ProjectSettings.get_setting("interactive_dev_panel/world_file", "")
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
	var first_visit := not visited_rooms.has(id)
	visited_rooms[id] = true
	_dress_room(room_node, id)
	if player:
		# Back in the physics space first: a body moved while it is out of it keeps its old
		# position there, and would land in the entry gate it came through.
		player.process_mode = player_mode
		player.global_position = _spawn_position(id, entry_gate, world_position)
		if "velocity" in player:
			player.velocity = _arrival_velocity(id, entry_gate, carried)
	_warn_missing_gate_nodes(id, path)
	if room_camera:
		await room_camera.enter_room(id, style, previous_center)
	elif camera:
		apply_camera_limits(camera)
	if old_room:
		old_room.queue_free()
	if map_view:
		map_view.mark_visited(id)
	if first_visit:
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
			push_warning("MDSWorldGame: gate '%s' of room '%s' is connected on the map but %s has no MDSGate node for it, so the player can't leave through it. In Map Dev, select the room and press Write to scene (Inspect tab)." % [g, id, path])

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
	var save := room_node.find_children("*", "", true, false).filter(func(n: Node) -> bool:
		return n is Node2D and (n.is_in_group(&"save_point") or n.is_in_group(&"bench") or String(n.name).to_lower().contains("savepoint")))
	if not save.is_empty():
		return save[0].global_position
	return world.get_room_label_pos(id)

func _on_gate_entered(t: Dictionary) -> void:
	# A teleported CharacterBody2D moves to its new place during the next physics step,
	# passing the gate it came through: arrivals ignore gates for a few physics frames, even
	# with no cooldown.
	if changing_room or Time.get_ticks_msec() < _cooldown_until or Engine.get_physics_frames() - _arrived_frame < 3:
		return
	if enforce_requirements:
		var missing: PackedStringArray = []
		var reqs: Array = t.get("requires", []) if t.get("link", false) else world.get_gate(current_room, t.get("from_gate", "")).get("requires", [])
		for r in reqs:
			if not has_ability(r):
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
## node carried into another room keeps the id it had ([code]idp_object_id[/code] metadata).
func object_id(node: Node) -> String:
	if node.has_meta(&"idp_object_id"):
		return str(node.get_meta(&"idp_object_id"))
	return "%s/%s" % [current_room, room_node.get_path_to(node) if room_node and room_node.is_ancestor_of(node) else node.name]

func store_object(node_or_id: Variant) -> void:
	stored_objects[node_or_id if node_or_id is String else object_id(node_or_id)] = true
	check_objectives()

func is_object_stored(node_or_id: Variant) -> bool:
	return stored_objects.has(node_or_id if node_or_id is String else object_id(node_or_id))

# --- Defeated enemies and bosses ------------------------------------------------------------------

## Records an enemy (or anything) as defeated: it stays gone when its room loads again, and
## after saving and loading. A boss (group boss/bosses/mini_boss, or idp_boss_name metadata)
## is also recorded by name, for objectives. Freeing the node is up to the caller.
func mark_defeated(node_or_id: Variant) -> void:
	var id: String = node_or_id if node_or_id is String else object_id(node_or_id)
	defeated_ids[id] = true
	moved.erase(id)
	var boss := ""
	if node_or_id is Node:
		var n := node_or_id as Node
		if n.has_meta(&"idp_boss_name"):
			boss = str(n.get_meta(&"idp_boss_name"))
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
		var oid := str(n.get_meta(&"idp_object_id")) if n.has_meta(&"idp_object_id") else "%s/%s" % [id, room.get_path_to(n)]
		if defeated_ids.has(oid):
			continue
		var gp: Vector2 = (n as Node2D).global_position
		if not _exit.is_empty() and gp.distance_to(_exit.pos) <= carry_over_distance:
			moved[oid] = {"scene": n.scene_file_path, "name": String(n.name), "room": to_room, "gate": to_gate, "offset": [gp.x - _exit.pos.x, gp.y - _exit.pos.y]}
		elif moved.has(oid) or n.has_meta(&"idp_carried"):
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
			inst.set_meta(&"idp_object_id", oid)
			inst.set_meta(&"idp_carried", true)
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

## [kind ("ability", "object", "boss"), value] of a condition.
static func parse_condition(condition: String) -> Array:
	return MDSAnnotations.parse_condition(condition)

func is_condition_met(condition: String) -> bool:
	if condition.strip_edges().is_empty():
		return false
	var c := parse_condition(condition)
	match c[0]:
		"object":
			return is_object_stored(str(c[1]))
		"boss":
			return is_boss_defeated(str(c[1]))
	return has_ability(str(c[1]).to_lower().replace(" ", "_"))

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
	if map_view:
		for a in data.get("map", {}).get("mapped_areas", []):
			map_view.map_area(a)

func _save_exploration() -> void:
	if exploration_file.is_empty():
		return
	var data := {"visited": visited_rooms.keys()}
	if map_view:
		data.map = map_view.get_save_data()
	var f := FileAccess.open(exploration_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

## A new game forgets the explored map (the exploration file is deleted).
func reset_exploration() -> void:
	visited_rooms.clear()
	if not exploration_file.is_empty() and FileAccess.file_exists(exploration_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(exploration_file))

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
	}
	if map_view:
		data.map = map_view.get_save_data()
	return data

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
	if map_view and data.has("map"):
		map_view.set_save_data(data.map)
		for id in explored:
			map_view.mark_visited(id)
	var room: String = data.get("room", "")
	if world.has_room(room):
		_load_requested = true
		var p: Array = data.get("position", [])
		# Coming back into a room after a load isn't a new visit of its area.
		current_area = world.get_room_area(room)
		load_room.call_deferred(room, "", Vector2(float(p[0]), float(p[1])) if p.size() == 2 else Vector2.INF)

## Called by the Map Dev panel's "Play from here".
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
