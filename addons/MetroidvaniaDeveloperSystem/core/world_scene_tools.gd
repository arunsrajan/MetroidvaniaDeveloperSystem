@tool
class_name MDSWorldSceneTools
extends RefCounted
## Keeps rooms on the world map and their scenes in sync (non-linear mode).
##
## - [method place_scene]: a scene dropped on the map becomes a room sized to its terrain,
##   with its gate nodes as map gates.
## - [method create_scene_for_room]: a room drawn on the map becomes a new scene with
##   bounds guides and one [MDSGate] per map gate.
## - [method import_gates] / [method write_gates]: sync gates in either direction.
## - [method ensure_gate_nodes]: add the MDSGate nodes a scene lacks (the panel calls it
##   whenever gates are added or connected on the map).
## - [method fit_room_to_scene]: resize the room to the scene's actual content.

const GATE_SIZE_ALONG := 128.0
const GATE_SIZE_ACROSS := 48.0

## Adds a room for [param scene_path] with its content's top-left at [param world_pos].
## [param meta] is the scanner result for the scene. Returns the new room id.
static func place_scene(world: MDSWorld, scene_path: String, meta: Dictionary, world_pos: Vector2, layer: int, area := "") -> String:
	var local := _content_rect(world, meta)
	var origin := world.snap(world_pos) - local.position
	var id := world.add_room(scene_path.get_file().get_basename(), Rect2(origin + local.position, local.size), layer, area, scene_path, origin)
	import_gates(world, id, meta)
	return id

## Scene content rounded outwards to the grid, in scene-local pixels. Falls back to the
## world's default room size when the scene has no terrain yet.
static func _content_rect(world: MDSWorld, meta: Dictionary) -> Rect2:
	var content: Rect2 = meta.get("content_rect", Rect2())
	if not content.has_area():
		return Rect2(Vector2.ZERO, world.get_default_room_size())
	var g := world.get_grid()
	var start := (content.position / g).floor() * g
	var end := (content.end / g).ceil() * g
	return Rect2(start, end - start)

## Replaces the room's shape with the scene's content bounds (one rectangle), keeping the
## scene where it is on the map.
static func fit_room_to_scene(world: MDSWorld, id: String, meta: Dictionary) -> bool:
	var content: Rect2 = meta.get("content_rect", Rect2())
	if not content.has_area() or not world.has_room(id):
		return false
	var local := _content_rect(world, meta)
	world.data.rooms[id].rects = [[local.position.x, local.position.y, local.size.x, local.size.y]]
	world._touch()
	return true

## Adds/updates map gates from the scene's gate nodes. Connections stored as node
## metadata (idp_to_room / idp_to_gate) are applied to unconnected gates.
## Returns the number of gates added or moved.
static func import_gates(world: MDSWorld, id: String, meta: Dictionary) -> int:
	var count := 0
	for t in meta.get("transitions", []):
		var gates := world.get_gates(id)
		var pos: Vector2 = t.position
		if gates.has(t.name):
			gates[t.name].pos = [pos.x, pos.y]
			gates[t.name].side = t.side
		else:
			gates[t.name] = {"pos": [pos.x, pos.y], "side": t.side}
		count += 1
		var to_room: String = t.get("to_room", "")
		var to_gate: String = t.get("to_gate", "")
		if not to_room.is_empty() and str(gates[t.name].get("to", "")).is_empty():
			gates[t.name].to = to_room
			gates[t.name].to_gate = to_gate
			if world.has_gate(to_room, to_gate) and str(world.get_gate(to_room, to_gate).get("to", "")).is_empty():
				world.connect_gates(id, t.name, to_room, to_gate)
	world._touch()
	return count

## Creates a new scene for a room drawn on the map: a Node2D (or the world's
## "scene_template") with a MapBounds guide per rectangle and an MDSGate per map gate. With
## the world setting "notch_fill_style" (a .freeform.tres), an irregular room's notches are
## filled with that style (see [MDSNotchFill]).
static func create_scene_for_room(world: MDSWorld, id: String, scene_path: String) -> Error:
	last_error = ""
	var root: Node
	var template_scene: PackedScene = null
	var template: String = world.get_setting("scene_template", "")
	if not template.is_empty() and ResourceLoader.exists(template):
		template_scene = load(template) as PackedScene
		root = template_scene.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	else:
		root = Node2D.new()
		var terrain := TileMapLayer.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
		terrain.owner = root
	root.name = id.to_pascal_case() if not id.to_pascal_case().is_empty() else "Room"
	var bounds := Node2D.new()
	bounds.name = "MapBounds"
	bounds.set_meta(&"_edit_lock_", true)
	root.add_child(bounds)
	bounds.owner = root
	var rects := world.get_local_rects(id)
	for i in rects.size():
		var guide := ReferenceRect.new()
		guide.name = "Rect%d" % (i + 1)
		guide.editor_only = true
		guide.border_color = Color(0.3, 0.9, 1.0)
		guide.border_width = 4.0
		guide.position = rects[i].position
		guide.size = rects[i].size
		guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bounds.add_child(guide)
		guide.owner = root
	apply_gate_nodes(world, id, root)
	# Irregular rooms: the notches of their box drawn as deep ground (Fill outside shape).
	var fill_path := str(world.get_setting("notch_fill_style", ""))
	if not fill_path.is_empty() and ResourceLoader.exists(fill_path):
		var fill_style := load(fill_path) as MDSFreeformStyle
		if fill_style:
			MDSNotchFill.add_to_scene(root, rects, fill_style)
	DirAccess.make_dir_recursive_absolute(scene_path.get_base_dir())
	var err := repack_safely(root, template_scene, scene_path)
	root.free()
	if err == OK:
		world.set_room_scene(id, scene_path)
	return err

## Adds MDSGate nodes for map gates missing from the room's scene, turns plain gate nodes
## into MDSGates, and moves existing ones to their map position. Never deletes nodes.
## Returns the number of gates in the scene that match the map, or -1 on error.
static func write_gates(world: MDSWorld, id: String) -> int:
	last_error = ""
	var path := world.get_scene_path(id)
	if path.is_empty():
		return -1
	var packed := load(path) as PackedScene
	if not packed:
		return -1
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	apply_gate_nodes(world, id, root, true)
	var count := 0
	var existing: Dictionary = {}
	_collect_gate_nodes(root, root, existing)
	for g in world.get_gates(id):
		if existing.has(g):
			count += 1
	var err := repack_safely(root, packed, path)
	root.free()
	return count if err == OK else -1

## Adds the MDSGate nodes the room's saved scene lacks (and converts plain gate nodes),
## without moving anything already there. Saves only when something changed. Returns the
## gate names added or converted.
static func ensure_gate_nodes(world: MDSWorld, id: String) -> PackedStringArray:
	last_error = ""
	var path := world.get_scene_path(id)
	var packed: PackedScene = load(path) as PackedScene if not path.is_empty() and ResourceLoader.exists(path) else null
	if not packed:
		return PackedStringArray()
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var changed := apply_gate_nodes(world, id, root, false)
	if not changed.is_empty() and repack_safely(root, packed, path) != OK:
		changed = PackedStringArray()
	root.free()
	return changed

## What the scene needs for its map gates: {"add": gate names without a node, "convert":
## gate nodes of this scene that are plain nodes (no script, not an instanced scene)}.
static func gate_node_changes(world: MDSWorld, id: String, root: Node) -> Dictionary:
	var existing: Dictionary = {}
	_collect_gate_nodes(root, root, existing)
	var add: PackedStringArray = []
	var convert: Array[Node2D] = []
	for gate_name in world.get_gates(id):
		if not existing.has(gate_name):
			add.append(gate_name)
			continue
		var node: Node2D = existing[gate_name]
		if not node is MDSGate and node.get_script() == null and node.scene_file_path.is_empty() and node.owner == root:
			convert.append(node)
	return {"add": add, "convert": convert}

## A new MDSGate for a map gate, with a collision shape across the doorway (the shape is
## not owned yet).
static func new_gate_node(world: MDSWorld, id: String, gate_name: String) -> MDSGate:
	var gate := MDSGate.new()
	gate.name = gate_name
	gate.collision_layer = 0
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	var side := world.get_gate_side(id, gate_name)
	rect.size = Vector2(GATE_SIZE_ACROSS, GATE_SIZE_ALONG) if side in ["left", "right"] else Vector2(GATE_SIZE_ALONG, GATE_SIZE_ACROSS)
	shape.shape = rect
	gate.add_child(shape)
	return gate

## Position for a gate node under [param parent] so it sits at the map gate.
static func gate_position(world: MDSWorld, id: String, gate_name: String, parent: Node, root: Node) -> Vector2:
	return _local_transform(parent, root).affine_inverse() * world.get_gate_local_pos(id, gate_name)

## Converts a plain gate node into an MDSGate: an Area2D gets the MDSGate script, any
## other Node2D is replaced by a new MDSGate keeping its name, transform and children.
static func convert_gate_node(world: MDSWorld, id: String, node: Node2D, root: Node) -> Node2D:
	if node is Area2D:
		node.set_script(MDSGate)
		if node.find_children("*", "CollisionShape2D", false, false).is_empty() and node.find_children("*", "CollisionPolygon2D", false, false).is_empty():
			var tmp := new_gate_node(world, id, String(node.name))
			var shape: Node = tmp.get_child(0)
			tmp.remove_child(shape)
			tmp.free()
			node.add_child(shape)
			shape.owner = root
		return node
	var gate := new_gate_node(world, id, String(node.name))
	gate.transform = node.transform
	node.replace_by(gate, true)
	gate.owner = root
	for c in gate.get_children():
		if not c.owner:
			c.owner = root
	node.free()
	return gate

## Adds and converts gate nodes on a scene instance. With [param move_existing], gates
## already in the scene move to their map position. Returns the gate names added or
## converted.
static func apply_gate_nodes(world: MDSWorld, id: String, root: Node, move_existing := false) -> PackedStringArray:
	var changes := gate_node_changes(world, id, root)
	var done: PackedStringArray = []
	for node: Node2D in changes.convert:
		done.append(String(node.name))
		convert_gate_node(world, id, node, root)
	var container: Node = root.get_node_or_null(^"Gates")
	for gate_name in changes.add:
		if not container:
			container = Node2D.new()
			container.name = "Gates"
			root.add_child(container)
			container.owner = root
		var gate := new_gate_node(world, id, gate_name)
		gate.position = gate_position(world, id, gate_name, container, root)
		container.add_child(gate)
		gate.owner = root
		for c in gate.get_children():
			c.owner = root
		done.append(gate_name)
	if move_existing:
		var existing: Dictionary = {}
		_collect_gate_nodes(root, root, existing)
		for gate_name in world.get_gates(id):
			if existing.has(gate_name) and not gate_name in changes.add:
				var node: Node2D = existing[gate_name]
				node.position = gate_position(world, id, gate_name, node.get_parent(), root)
	return done

## Why the last [method repack_safely] failed, for the panel's status line ("" after a
## success).
static var last_error := ""

## Saves [param root], an instance of [param packed] (made with
## [code]PackedScene.GEN_EDIT_STATE_INSTANCE[/code]) that was edited, back to [param path]
## without losing anything silently:
## - properties the scene sets on nodes inside an instanced scene are kept (packing drops
##   them unless the instance is marked as having editable children, so it is marked);
## - a node whose script did not load (a compile error, or an autoload it needs missing)
##   would be saved with [code]script = null[/code]: the scene is not saved, and
##   [member last_error] names the node;
## - the UID stays the same.
## Every place MDS writes a room scene goes through here.
static func repack_safely(root: Node, packed: PackedScene, path: String) -> Error:
	last_error = ""
	if packed:
		keep_child_overrides(root, packed)
		var lost := lost_scripts(root, packed)
		if not lost.is_empty():
			last_error = "%s was not saved: %s lost %s script (it failed to load or compile, for example because an autoload it uses is missing). Fix the script, then reopen the scene." % [path.get_file(), ", ".join(lost), "its" if lost.size() == 1 else "their"]
			push_error("Metroidvania Developer System: " + last_error)
			return ERR_SCRIPT_FAILED
	var out := PackedScene.new()
	var err := out.pack(root)
	if err == OK:
		err = save_keeping_uid(out, path)
	if err != OK:
		last_error = "Could not save %s (error %d)." % [path.get_file(), err]
	return err

## Marks every instanced scene that [param packed] sets properties inside as having
## editable children, so packing [param root] again keeps those properties.
static func keep_child_overrides(root: Node, packed: PackedScene) -> void:
	var state := packed.get_state()
	for i in state.get_node_count():
		# A node with no type and no instance of its own is a node of an instanced scene
		# that this scene overrides.
		if not state.get_node_type(i).is_empty() or state.get_node_instance(i) != null or state.get_node_path(i) == NodePath("."):
			continue
		var n := root.get_node_or_null(state.get_node_path(i, true))
		while n and n != root and n.scene_file_path.is_empty():
			n = n.get_parent()
		if n and n != root and not root.is_editable_instance(n):
			root.set_editable_instance(n, true)

## Nodes of [param root] whose scene ([param packed], or a scene it instances) gives them a
## script they no longer have: the script failed to load. Paths relative to [param root].
static func lost_scripts(root: Node, packed: PackedScene) -> PackedStringArray:
	var expected: Dictionary = {}
	_scripted_paths(packed.get_state(), "", expected, 0)
	var out: PackedStringArray = []
	for p: String in expected:
		var n := root.get_node_or_null(NodePath(p if not p.is_empty() else "."))
		if n and n.get_script() == null:
			out.append(String(n.name) if n == root else p)
	return out

static func _scripted_paths(state: SceneState, prefix: String, out: Dictionary, depth: int) -> void:
	if depth > 8:
		return
	for i in state.get_node_count():
		var p := String(state.get_node_path(i)).trim_prefix("./")
		var full := prefix if p == "." else (p if prefix.is_empty() else prefix + "/" + p)
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"script":
				out[full] = true
		var inst := state.get_node_instance(i)
		if inst:
			_scripted_paths(inst.get_state(), full, out, depth + 1)

## Re-saves an existing scene without changing its UID. Maps (MetSys and worlds) point at
## rooms by UID, and some Godot versions drop it when a scene is re-saved from a script.
static func save_keeping_uid(packed: PackedScene, path: String) -> Error:
	var uid := file_uid(path)
	var err := ResourceSaver.save(packed, path)
	if err == OK and uid != ResourceUID.INVALID_ID:
		err = ResourceSaver.set_uid(path, uid)
	return err

static var _uid_re := RegEx.create_from_string("uid=\"(uid://[^\"]+)\"")

## The UID of the resource file at [param path]. A text file's header is read first: outside
## the editor (tools, CI) Godot's UID cache can be missing files saved since the project was
## imported, or hold the UID a file had before.
static func file_uid(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	if path.ends_with(".tscn") or path.ends_with(".tres"):
		var f := FileAccess.open(path, FileAccess.READ)
		var m := _uid_re.search(f.get_line()) if f else null
		if m and ResourceUID.text_to_id(m.get_string(1)) != ResourceUID.INVALID_ID:
			return ResourceUID.text_to_id(m.get_string(1))
	return ResourceLoader.get_resource_uid(path)

## Creates a ready-to-run game scene for the world: an MDSWorldGame root, a placeholder
## player (CharacterBody2D in the "player" group) with a following camera, a room camera with a
## camera director, area music, and a UI with an in-game map (MDSWorldMapView) in the
## top-right corner, area titles and objective banners.
static func create_game_scene(world: MDSWorld, scene_path: String) -> Error:
	var game := MDSWorldGame.new()
	game.name = world.get_world_name().to_pascal_case() + "Game" if not world.get_world_name().is_empty() else "WorldGame"
	game.world_file = world.path
	game.starting_room = world.get_start_room()
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group(&"player", true)
	game.add_child(player)
	player.owner = game
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 16
	capsule.height = 64
	shape.shape = capsule
	player.add_child(shape)
	shape.owner = game
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	player.add_child(camera)
	camera.owner = game
	# Irregular-room camera zones and room transitions (settings: World settings > Camera).
	var room_camera := MDSRoomCamera.new()
	room_camera.name = "RoomCamera"
	game.add_child(room_camera)
	room_camera.owner = game
	room_camera.camera = camera
	room_camera.target = player
	game.room_camera = room_camera
	var director := MDSCameraDirector.new()
	director.name = "Director"
	room_camera.add_child(director)
	director.owner = game
	var music := MDSMusic.new()
	music.name = "Music"
	game.add_child(music)
	music.owner = game
	var ui := CanvasLayer.new()
	ui.name = "UI"
	game.add_child(ui)
	ui.owner = game
	var map := MDSWorldMapView.new()
	map.name = "Map"
	map.world_file = world.path
	map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map.offset_left = -320
	map.offset_bottom = 220
	map.offset_top = 12
	map.offset_right = -12
	ui.add_child(map)
	map.owner = game
	var title := MDSAreaTitle.new()
	title.name = "AreaTitle"
	ui.add_child(title)
	title.owner = game
	var banner := MDSObjectiveBanner.new()
	banner.name = "ObjectiveBanner"
	ui.add_child(banner)
	banner.owner = game
	game.player = player
	game.camera = camera
	game.map_view = map
	var packed := PackedScene.new()
	var err := packed.pack(game)
	game.free()
	if err != OK:
		return err
	DirAccess.make_dir_recursive_absolute(scene_path.get_base_dir())
	return ResourceSaver.save(packed, scene_path)

static func _collect_gate_nodes(node: Node, root: Node, out: Dictionary) -> void:
	if node != root and node is Node2D:
		var n := String(node.name)
		if node is MDSGate:
			n = node.get_gate_name()
		if node is MDSGate or node.is_in_group(&"idp_gate") or MDSSceneScanner._gate_name_re.search(n.to_lower()):
			out[n] = node
	for child in node.get_children():
		_collect_gate_nodes(child, root, out)

static func _local_transform(node: Node, root: Node) -> Transform2D:
	var xform := Transform2D.IDENTITY
	var n := node
	while n and n != root:
		if n is Node2D:
			xform = (n as Node2D).transform * xform
		n = n.get_parent()
	return xform
