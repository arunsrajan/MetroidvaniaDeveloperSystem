@tool
class_name IDPWorldSceneTools
extends RefCounted
## Keeps rooms on the world map and their scenes in sync (non-linear mode).
##
## - [method place_scene]: a scene dropped on the map becomes a room sized to its terrain,
##   with its gate nodes as map gates.
## - [method create_scene_for_room]: a room drawn on the map becomes a new scene with
##   bounds guides and one [IDPGate] per map gate.
## - [method import_gates] / [method write_gates]: sync gates in either direction.
## - [method fit_room_to_scene]: resize the room to the scene's actual content.

const GATE_SIZE_ALONG := 128.0
const GATE_SIZE_ACROSS := 48.0

## Adds a room for [param scene_path] with its content's top-left at [param world_pos].
## [param meta] is the scanner result for the scene. Returns the new room id.
static func place_scene(world: IDPWorld, scene_path: String, meta: Dictionary, world_pos: Vector2, layer: int, area := "") -> String:
	var local := _content_rect(world, meta)
	var origin := world.snap(world_pos) - local.position
	var id := world.add_room(scene_path.get_file().get_basename(), Rect2(origin + local.position, local.size), layer, area, scene_path, origin)
	import_gates(world, id, meta)
	return id

## Scene content rounded outwards to the grid, in scene-local pixels. Falls back to the
## world's default room size when the scene has no terrain yet.
static func _content_rect(world: IDPWorld, meta: Dictionary) -> Rect2:
	var content: Rect2 = meta.get("content_rect", Rect2())
	if not content.has_area():
		return Rect2(Vector2.ZERO, world.get_default_room_size())
	var g := world.get_grid()
	var start := (content.position / g).floor() * g
	var end := (content.end / g).ceil() * g
	return Rect2(start, end - start)

## Replaces the room's shape with the scene's content bounds (one rectangle), keeping the
## scene where it is on the map.
static func fit_room_to_scene(world: IDPWorld, id: String, meta: Dictionary) -> bool:
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
static func import_gates(world: IDPWorld, id: String, meta: Dictionary) -> int:
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
## "scene_template") with a MapBounds guide per rectangle and an IDPGate per map gate.
static func create_scene_for_room(world: IDPWorld, id: String, scene_path: String) -> Error:
	var root: Node
	var template: String = world.get_setting("scene_template", "")
	if not template.is_empty() and ResourceLoader.exists(template):
		root = (load(template) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
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
	_add_missing_gates(world, id, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return err
	DirAccess.make_dir_recursive_absolute(scene_path.get_base_dir())
	err = ResourceSaver.save(packed, scene_path)
	if err == OK:
		world.set_room_scene(id, scene_path)
	return err

## Adds IDPGate nodes for map gates missing from the room's scene and moves existing ones
## to their map position. Never deletes nodes. Returns the number of gates written.
static func write_gates(world: IDPWorld, id: String) -> int:
	var path := world.get_scene_path(id)
	if path.is_empty():
		return -1
	var packed := load(path) as PackedScene
	if not packed:
		return -1
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var count := _add_missing_gates(world, id, root)
	packed.pack(root)
	root.free()
	if save_keeping_uid(packed, path) != OK:
		return -1
	return count

## Re-saves an existing scene without changing its UID. Maps (MetSys and worlds) point at
## rooms by UID, and some Godot versions drop it when a scene is re-saved from a script.
static func save_keeping_uid(packed: PackedScene, path: String) -> Error:
	var uid := ResourceLoader.get_resource_uid(path) if ResourceLoader.exists(path) else ResourceUID.INVALID_ID
	var err := ResourceSaver.save(packed, path)
	if err == OK and uid != ResourceUID.INVALID_ID:
		err = ResourceSaver.set_uid(path, uid)
	return err

static func _add_missing_gates(world: IDPWorld, id: String, root: Node) -> int:
	var existing: Dictionary = {}
	_collect_gate_nodes(root, root, existing)
	var container: Node = root.get_node_or_null(^"Gates")
	var count := 0
	var gates := world.get_gates(id)
	for gate_name in gates:
		var local := world.get_gate_local_pos(id, gate_name)
		if existing.has(gate_name):
			var node: Node2D = existing[gate_name]
			var parent_xform := _local_transform(node.get_parent(), root)
			node.position = parent_xform.affine_inverse() * local
			count += 1
			continue
		if not container:
			container = Node2D.new()
			container.name = "Gates"
			root.add_child(container)
			container.owner = root
		var gate := IDPGate.new()
		gate.name = gate_name
		gate.position = local
		gate.collision_layer = 0
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var rect := RectangleShape2D.new()
		var side := world.get_gate_side(id, gate_name)
		rect.size = Vector2(GATE_SIZE_ACROSS, GATE_SIZE_ALONG) if side in ["left", "right"] else Vector2(GATE_SIZE_ALONG, GATE_SIZE_ACROSS)
		shape.shape = rect
		container.add_child(gate)
		gate.owner = root
		gate.add_child(shape)
		shape.owner = root
		count += 1
	return count

## Creates a ready-to-run game scene for the world: an IDPWorldGame root, a placeholder
## player (CharacterBody2D in the "player" group) with a following camera, and an in-game
## map (IDPWorldMapView) in the top-right corner.
static func create_game_scene(world: IDPWorld, scene_path: String) -> Error:
	var game := IDPWorldGame.new()
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
	var ui := CanvasLayer.new()
	ui.name = "UI"
	game.add_child(ui)
	ui.owner = game
	var map := IDPWorldMapView.new()
	map.name = "Map"
	map.world_file = world.path
	map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map.offset_left = -320
	map.offset_bottom = 220
	map.offset_top = 12
	map.offset_right = -12
	ui.add_child(map)
	map.owner = game
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
		if node is IDPGate:
			n = node.get_gate_name()
		if node is IDPGate or node.is_in_group(&"idp_gate") or IDPSceneScanner._gate_name_re.search(n.to_lower()):
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
