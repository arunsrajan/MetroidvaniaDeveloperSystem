@tool
class_name MDSSceneScanner
extends RefCounted
## Scans room scenes for gameplay features (collectibles, bosses, save points...), ability
## metadata and terrain, so the map can show what is actually inside every room.
##
## Node metadata understood by the scanner (set in the Inspector, "Add Metadata"):
## - [code]mds_grants[/code] (String or Array): abilities/items picked up here, e.g. "dash".
## - [code]mds_requires[/code] (String or Array): put on a gate/breakable wall near a door;
##   the requirement is attached to the closest passage of that cell.
## - [code]mds_boss_name[/code] (String): marks the node as a boss and names it.
## - [code]mds_room_type[/code] (String, on the scene root): overrides the inferred type.
##
## Transition gates (non-linear mode) are nodes named like Hollow Knight's gates
## ([code]left1[/code], [code]right2[/code], [code]top1[/code], [code]bot1[/code],
## [code]door1[/code]), nodes in the [code]mds_gate[/code] group, or [MDSGate] nodes.
## Optional metadata: [code]mds_to_room[/code], [code]mds_to_gate[/code].

signal scan_progress_updated(current: int, total: int, current_file: String)
signal scan_completed(scene_database: Dictionary)
signal scan_map_data_txt_completed(map_data_txt_path: String)

const COLLECTIBLE_GROUPS := ["collectible", "collectibles", "item", "items", "pickup", "pickups"]
const ENEMY_GROUPS := ["enemy", "enemies", "monster", "monsters", "hostile"]
const SAVE_POINT_GROUPS := ["save_point", "savepoint", "save", "checkpoint", "bench"]
const BREAKABLE_GROUPS := ["breakable", "destroyable", "destructible", "crate"]
const TELEPORTER_GROUPS := ["teleporter", "warp", "portal", "transition", "fast_travel"]
const SHOP_GROUPS := ["shop", "merchant", "vendor", "trader"]
const BOSS_GROUPS := ["boss", "bosses", "mini_boss"]
const BOSS_NAME_PATTERNS := ["boss", "king", "queen", "lord", "guardian"]
const SHOP_NAME_PATTERNS := ["shop", "merchant", "vendor", "trader", "store"]
const TELEPORTER_NAME_PATTERNS := ["teleport", "warp", "portal"]
const BREAKABLE_NAME_PATTERNS := ["break", "crate", "pot", "barrel", "rock"]
const SAVE_NAME_PATTERNS := ["savepoint", "save_point", "bench", "checkpoint"]
const GATE_GROUPS := ["mds_gate", "transition_point", "scene_transition"]

static var _gate_name_re := RegEx.create_from_string("^(left|right|top|bot|bottom|door)\\d+$")

## Room pixels per silhouette pixel (raised automatically for very large rooms).
const SILHOUETTE_SCALE := 16.0
const SILHOUETTE_MAX_SIZE := 2048
const SCENES_PER_FRAME := 3

var in_game_cell_size := Vector2(1152, 648)
## MetSys rooms carry a RoomInstance node; non-linear rooms don't need one.
var require_room_instance := true
var scene_database: Dictionary = {}
var scan_stats: Dictionary = {}
var is_scanning := false
var _cancelled := false

func _init(p_cell_size := Vector2(1152, 648)) -> void:
	in_game_cell_size = p_cell_size
	reset()

func reset() -> void:
	scene_database.clear()
	scan_stats = {
		"total_scenes": 0,
		"total_collectibles": 0,
		"total_enemies": 0,
		"total_save_points": 0,
		"rooms_with_boss": 0,
		"rooms_with_shop": 0,
		"rooms_with_teleporter": 0,
		"rooms_with_breakable_walls": 0,
	}

func cancel() -> void:
	_cancelled = true

## Recursively scans [param root_path] for scenes (and MapData.txt files). Asynchronous.
func scan_all_scenes(root_path: String = "res://") -> Dictionary:
	var scene_files: Array[String] = []
	find_scene_files(root_path, scene_files)
	return await scan_paths(scene_files)

## Scans the given scene files. Only scenes containing a RoomInstance are kept. Asynchronous.
func scan_paths(scene_files: Array[String]) -> Dictionary:
	reset()
	is_scanning = true
	_cancelled = false
	scan_stats.total_scenes = scene_files.size()
	var tree := Engine.get_main_loop() as SceneTree
	for i in scene_files.size():
		if _cancelled:
			break
		var scene_path := scene_files[i]
		scan_progress_updated.emit(i + 1, scene_files.size(), scene_path.get_file())
		var metadata := analyze_scene(scene_path, require_room_instance)
		if metadata.get("room_instance") != null or (not require_room_instance and metadata.get("loaded", false)):
			scene_database[scene_path] = metadata
			update_stats_from_metadata(metadata)
		if tree and i % SCENES_PER_FRAME == SCENES_PER_FRAME - 1:
			await tree.process_frame
	is_scanning = false
	scan_completed.emit(scene_database)
	return scene_database

func find_scene_files(dir_path: String, result_array: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		printerr("Cannot open directory: ", dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != "addons":
				find_scene_files(dir_path.path_join(file_name), result_array)
		elif file_name.ends_with(".tscn") or file_name.ends_with(".scn"):
			result_array.append(dir_path.path_join(file_name))
		elif file_name.ends_with("MapData.txt"):
			scan_map_data_txt_completed.emit(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

## Analyzes any scene, with or without a MetSys RoomInstance (non-linear mode).
func analyze_scene_any(scene_path: String) -> Dictionary:
	return analyze_scene(scene_path, false)

func analyze_scene(scene_path: String, require_room := true) -> Dictionary:
	var metadata := {
		"type": "room",
		"collectibles": [],
		"enemies": [],
		"save_points": [],
		"bosses": [],
		"teleporters": [],
		"shops": [],
		"grants": PackedStringArray(),
		"gates": [],
		"transitions": [],
		"has_boss": false,
		"has_shopkeeper": false,
		"has_breakable_walls": false,
		"has_teleporter": false,
		"has_hidden_passage": false,
		"room_type_hint": "",
		"room_instance": null,
		"node_count": 0,
		"groups": [],
		"silhouette": null,
		"silhouette_rect": Rect2(),
		"content_rect": Rect2(),
		"occupied_cells": [],
		# One-way bodies and freeform shapes with the Platform role: {name, path, rect, one_way}.
		"platforms": [],
		# Outlines that cross themselves (no fill, no collision): {path, kind, position}.
		"twisted": [],
		# Objects standing in or behind each other: {a, b, position, cell} (MDSRoomDressing).
		"overlaps": [],
		# Tile layers with cells pointing at tiles their tileset no longer has:
		# {path, count, sample (atlas coords), position, cell}.
		"broken_tiles": [],
	}
	if not ResourceLoader.exists(scene_path):
		return metadata
	var packed_scene := load(scene_path) as PackedScene
	if not packed_scene:
		return metadata
	var instance := packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if not instance:
		return metadata
	# Stops MetSys' RoomInstance from building neighbor previews for this throwaway copy.
	instance.set_meta(&"fake_map", true)
	metadata.loaded = true
	var room_instance := find_room_instance(instance)
	if room_instance:
		metadata.room_instance = {"position": _local_transform(room_instance, instance).origin}
	if room_instance or not require_room:
		metadata.room_type_hint = str(MDSLegacy.get_meta_key(instance, &"mds_room_type", ""))
		var solids: Array[Rect2] = []
		var polygons: Array[PackedVector2Array] = []
		_scan_node(instance, instance, metadata, solids, polygons)
		# A root named like "BossArena" marks a boss room when no boss node was found.
		if not metadata.has_boss and _name_matches(_name_words(instance.name), BOSS_NAME_PATTERNS):
			metadata.has_boss = true
			var entry := create_feature_entry(instance, instance, "boss")
			entry.name = String(instance.name).capitalize()
			metadata.bosses.append(entry)
		metadata.groups = instance.get_groups()
		metadata.node_count = count_nodes(instance)
		_build_silhouette(metadata, solids, polygons)
		_find_broken_tiles(instance, metadata)
		for o in MDSRoomDressing.overlaps(instance):
			var pos: Vector2 = (o.rect as Rect2).get_center()
			metadata.overlaps.append({"a": o.a, "b": o.b, "position": pos, "cell": Vector2i((pos / in_game_cell_size).floor())})
		# Godot reports a twisted collision polygon as "Convex decomposing failed!" without
		# saying where: name it.
		for t in metadata.twisted:
			push_warning("%s: %s %s crosses itself, so it has no fill and no collision (see Map Dev's Issues tab)." % [scene_path, "Freeform shape" if t.kind == "freeform" else "CollisionPolygon2D", t.path])
	instance.free()
	return metadata

## Tile layers whose cells point at tiles their tileset no longer has (see
## [method MDSRoomPainter.is_cell_valid]). Hidden-tile layers ("<Layer>Blockout") are skipped.
func _find_broken_tiles(instance: Node, metadata: Dictionary) -> void:
	for node in instance.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if MDSLegacy.has_meta_key(layer, &"mds_blockout"):
			continue
		var broken := MDSRoomPainter.broken_cells_of(layer)
		if broken.is_empty():
			continue
		var sample: Array = []
		for c in broken.slice(0, 3):
			sample.append(layer.get_cell_atlas_coords(c))
		var pos := _local_transform(layer, instance) * layer.map_to_local(broken[0])
		metadata.broken_tiles.append({"path": String(instance.get_path_to(layer)), "count": broken.size(), "sample": sample,
			"position": pos, "cell": Vector2i((pos / in_game_cell_size).floor())})

func find_room_instance(node: Node) -> Node:
	if node.name == "RoomInstance" or node.is_class("RoomInstance"):
		return node
	var script := node.get_script() as Script
	if script and script.resource_path.ends_with("RoomInstance.gd"):
		return node
	for child in node.get_children():
		var result := find_room_instance(child)
		if result:
			return result
	return null

## Transform of [param node] relative to [param root]. Scenes are scanned outside the
## tree, where global_position is not available.
func _local_transform(node: Node, root: Node) -> Transform2D:
	var xform := Transform2D.IDENTITY
	var n := node
	while n and n != root:
		if n is Node2D:
			xform = (n as Node2D).transform * xform
		n = n.get_parent()
	return xform

func _scan_node(node: Node, root: Node, metadata: Dictionary, solids: Array[Rect2], polygons: Array[PackedVector2Array]) -> void:
	var name_lower := String(node.name).to_lower()
	var words := _name_words(node.name)
	var is_gate := _scan_transition(node, root, metadata)
	var matched_collectible := _in_any_group(node, COLLECTIBLE_GROUPS)
	if matched_collectible:
		metadata.collectibles.append(create_feature_entry(node, root, "collectible"))
	if _in_any_group(node, ENEMY_GROUPS):
		metadata.enemies.append(create_feature_entry(node, root, "enemy"))
	if _in_any_group(node, SAVE_POINT_GROUPS) or (node is Node2D and _contains_any(name_lower, SAVE_NAME_PATTERNS)):
		metadata.save_points.append(create_feature_entry(node, root, "save_point"))
	if _in_any_group(node, BREAKABLE_GROUPS) or _name_matches(words, BREAKABLE_NAME_PATTERNS):
		metadata.has_breakable_walls = true
	if not is_gate and (_in_any_group(node, TELEPORTER_GROUPS) or (node is Node2D and _name_matches(words, TELEPORTER_NAME_PATTERNS))):
		metadata.has_teleporter = true
		metadata.teleporters.append(create_feature_entry(node, root, "teleporter"))
	if _in_any_group(node, SHOP_GROUPS) or (node is Node2D and _name_matches(words, SHOP_NAME_PATTERNS)):
		metadata.has_shopkeeper = true
		metadata.shops.append(create_feature_entry(node, root, "shop"))
	var boss_name := str(MDSLegacy.get_meta_key(node, &"mds_boss_name", ""))
	if not boss_name.is_empty() or _in_any_group(node, BOSS_GROUPS) or (node != root and _name_matches(words, BOSS_NAME_PATTERNS)):
		metadata.has_boss = true
		var entry := create_feature_entry(node, root, "boss")
		entry.name = boss_name if not boss_name.is_empty() else String(node.name).capitalize()
		metadata.bosses.append(entry)
	if node is Area2D and (name_lower.contains("secret") or name_lower.contains("hidden")):
		metadata.has_hidden_passage = true
	if MDSLegacy.has_meta_key(node, &"mds_grants"):
		for ability in _meta_list(MDSLegacy.get_meta_key(node, &"mds_grants")):
			if not ability in metadata.grants:
				metadata.grants.append(ability)
	if MDSLegacy.has_meta_key(node, &"mds_requires"):
		metadata.gates.append({
			"requires": _meta_list(MDSLegacy.get_meta_key(node, &"mds_requires")),
			"position": _local_transform(node, root).origin,
			"name": String(node.name),
		})
	# Old terrain hidden by Convert to freeform: not part of the room any more.
	if MDSLegacy.has_meta_key(node, &"mds_blockout"):
		return
	_collect_solids(node, root, metadata, solids, polygons)
	for child in node.get_children():
		_scan_node(child, root, metadata, solids, polygons)

## Records Hollow Knight-style transition gates. Returns true when [param node] is one.
func _scan_transition(node: Node, root: Node, metadata: Dictionary) -> bool:
	if not node is Node2D or node == root:
		return false
	var gate_name := String(node.name)
	var script := node.get_script() as Script
	var is_mds_gate := script != null and script.get_global_name() == &"MDSGate"
	if is_mds_gate and not str(node.get("gate_name")).is_empty():
		gate_name = str(node.get("gate_name"))
	if not (is_mds_gate or _in_any_group(node, GATE_GROUPS) or _gate_name_re.search(gate_name.to_lower())):
		return false
	var side := str(MDSLegacy.get_meta_key(node, &"mds_side", ""))
	if side.is_empty():
		side = MDSWorld.side_from_name(gate_name.to_lower())
	metadata.transitions.append({
		"name": gate_name,
		"position": _local_transform(node, root).origin,
		"side": side,
		"to_room": str(MDSLegacy.get_meta_key(node, &"mds_to_room", "")),
		"to_gate": str(MDSLegacy.get_meta_key(node, &"mds_to_gate", "")),
	})
	return true

func _in_any_group(node: Node, groups: Array) -> bool:
	for group in groups:
		if MDSLegacy.in_group(node, group):
			return true
	return false

## "MossMotherBoss" -> ["moss", "mother", "boss"]. Whole-word matching avoids hits like
## "Walking" for "king" or "HitBox" for "box".
func _name_words(node_name: StringName) -> PackedStringArray:
	return String(node_name).to_snake_case().replace("-", "_").replace(" ", "_").split("_", false)

func _name_matches(words: PackedStringArray, patterns: Array) -> bool:
	for word in words:
		for pattern in patterns:
			if word.begins_with(pattern):
				return true
	return false

func _contains_any(name_lower: String, patterns: Array) -> bool:
	for pattern in patterns:
		if name_lower.contains(pattern):
			return true
	return false

func _meta_list(value: Variant) -> PackedStringArray:
	var ret: PackedStringArray = []
	var items: Array = Array(value) if (value is Array or value is PackedStringArray) else Array(str(value).split(",", false))
	for item in items:
		var s := str(item).strip_edges().to_lower().replace(" ", "_")
		if not s.is_empty():
			ret.append(s)
	return ret

func create_feature_entry(node: Node, root: Node, feature_type: String) -> Dictionary:
	return {
		"name": String(node.name),
		"type": feature_type,
		"position": _local_transform(node, root).origin,
		"scene_file": node.scene_file_path,
		"groups": node.get_groups(),
		"node_class": node.get_class(),
	}

func _collect_solids(node: Node, root: Node, metadata: Dictionary, solids: Array[Rect2], polygons: Array[PackedVector2Array]) -> void:
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		if layer.tile_set and layer.enabled and _is_terrain_layer(layer):
			# Cells pointing at tiles the tileset no longer has draw nothing: not terrain.
			var used := layer.get_used_cells().filter(func(c: Vector2i) -> bool: return MDSRoomPainter.is_cell_valid(layer, c))
			# With collision set up, only solid tiles are terrain (not foliage or vines).
			if layer.tile_set.get_physics_layers_count() > 0 and layer.collision_enabled:
				used = used.filter(func(c: Vector2i) -> bool:
					return layer.get_cell_tile_data(c).get_collision_polygons_count(0) > 0)
			_add_tile_rects(layer, used, layer.tile_set.tile_size, _local_transform(layer, root), solids)
	elif node.is_class("TileMap"):
		var tile_set: TileSet = node.get("tile_set")
		if tile_set:
			for i in node.call("get_layers_count"):
				_add_tile_rects(node, node.call("get_used_cells", i), tile_set.tile_size, _local_transform(node, root), solids)
	elif node is MDSFreeform:
		# Freeform terrain builds its collision at runtime: use its outline. Only terrain is
		# part of the room's shape; platforms are listed, decorations ignored.
		var f := node as MDSFreeform
		if f.points.size() < 3:
			return
		var xform := _local_transform(node, root)
		var outline := f.get_outline()
		if not MDSGeometry.is_simple(outline):
			_add_twisted(metadata, root, node, "freeform", xform * MDSGeometry.bounds(outline).get_center())
		if f.is_terrain():
			polygons.append(xform * outline)
		elif f.is_platform():
			metadata.platforms.append({"name": String(node.name), "path": String(root.get_path_to(node)), "rect": xform * MDSGeometry.bounds(outline), "one_way": f.is_one_way()})
	elif node is CollisionShape2D and node.get_parent() is StaticBody2D:
		var cs := node as CollisionShape2D
		var shape := cs.shape
		if shape is RectangleShape2D and not cs.disabled:
			var size: Vector2 = (shape as RectangleShape2D).size
			var r := _local_transform(node, root) * Rect2(-size / 2.0, size)
			if cs.one_way_collision:
				metadata.platforms.append({"name": String(node.get_parent().name), "path": String(root.get_path_to(node)), "rect": r, "one_way": true})
			else:
				solids.append(r)
	elif node is CollisionPolygon2D and node.get_parent() is StaticBody2D:
		var cp := node as CollisionPolygon2D
		var poly := cp.polygon
		if poly.size() >= 3 and not cp.disabled:
			var xform := _local_transform(node, root)
			if cp.build_mode == CollisionPolygon2D.BUILD_SOLIDS and not MDSGeometry.is_simple(poly):
				_add_twisted(metadata, root, node, "collision", xform * MDSGeometry.bounds(poly).get_center())
			if cp.one_way_collision:
				metadata.platforms.append({"name": String(node.get_parent().name), "path": String(root.get_path_to(node)), "rect": xform * MDSGeometry.bounds(poly), "one_way": true})
			else:
				polygons.append(xform * poly)

## Records an outline that crosses itself, with the map cell it is in (MetSys mode).
func _add_twisted(metadata: Dictionary, root: Node, node: Node, kind: String, pos: Vector2) -> void:
	metadata.twisted.append({"path": String(root.get_path_to(node)), "kind": kind, "position": pos, "cell": Vector2i((pos / in_game_cell_size).floor())})

## Background/decoration layers are art, not the room's shape.
func _is_terrain_layer(layer: TileMapLayer) -> bool:
	var n := String(layer.name).to_lower()
	for word in ["background", "backdrop", "decor", "foreground", "parallax"]:
		if n.contains(word):
			return false
	return not (n == "bg" or n == "fg")

func _add_tile_rects(layer: Node, used_cells: Array, tile_size: Vector2i, xform: Transform2D, solids: Array[Rect2]) -> void:
	var half := Vector2(tile_size) / 2.0
	for cell in used_cells:
		var center: Vector2 = layer.call("map_to_local", cell)
		solids.append(xform * Rect2(center - half, Vector2(tile_size)))

## Rasterizes terrain into a small alpha image (drawn on the map like a hand-made
## Hollow Knight map) and records which grid cells the content occupies.
func _build_silhouette(metadata: Dictionary, solids: Array[Rect2], polygons: Array[PackedVector2Array]) -> void:
	if solids.is_empty() and polygons.is_empty():
		return
	var bounds := Rect2()
	var first := true
	for r in solids:
		bounds = r if first else bounds.merge(r)
		first = false
	for poly in polygons:
		var pr := _poly_rect(poly)
		bounds = pr if first else bounds.merge(pr)
		first = false
	# Snap to the cell grid so textures line up with cells.
	metadata.content_rect = bounds
	var cell := in_game_cell_size
	var start := (bounds.position / cell).floor() * cell
	var end := (bounds.end / cell).ceil() * cell
	bounds = Rect2(start, end - start)
	var scale := SILHOUETTE_SCALE
	while bounds.size.x / scale > SILHOUETTE_MAX_SIZE or bounds.size.y / scale > SILHOUETTE_MAX_SIZE:
		scale *= 2.0
	var img_size := Vector2i((bounds.size / scale).ceil())
	if img_size.x <= 0 or img_size.y <= 0:
		return
	var img := Image.create(img_size.x, img_size.y, false, Image.FORMAT_LA8)
	var occupied: Dictionary = {}
	for r in solids:
		var p := Vector2i(((r.position - bounds.position) / scale).floor())
		var s := Vector2i(((r.end - bounds.position) / scale).ceil()) - p
		img.fill_rect(Rect2i(p, s.max(Vector2i.ONE)), Color.WHITE)
		_mark_occupied(r, occupied)
	for poly in polygons:
		var pr := _poly_rect(poly)
		var p0 := Vector2i(((pr.position - bounds.position) / scale).floor())
		var p1 := Vector2i(((pr.end - bounds.position) / scale).ceil())
		for y in range(maxi(p0.y, 0), mini(p1.y, img_size.y)):
			for x in range(maxi(p0.x, 0), mini(p1.x, img_size.x)):
				var world := bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * scale
				if Geometry2D.is_point_in_polygon(world, poly):
					img.set_pixel(x, y, Color.WHITE)
		_mark_occupied(pr, occupied)
	metadata.silhouette = img
	metadata.silhouette_rect = bounds
	metadata.occupied_cells = occupied.keys()

func _poly_rect(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r

func _mark_occupied(r: Rect2, occupied: Dictionary) -> void:
	# Shrink slightly so content that merely touches a cell edge does not count.
	var inner := r.grow(-1.0)
	if inner.size.x <= 0 or inner.size.y <= 0:
		inner = Rect2(r.get_center(), Vector2.ZERO)
	var c0 := Vector2i((inner.position / in_game_cell_size).floor())
	var c1 := Vector2i((inner.end / in_game_cell_size).floor())
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			occupied[Vector2i(x, y)] = true

func count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += count_nodes(child)
	return count

func update_stats_from_metadata(metadata: Dictionary) -> void:
	scan_stats.total_collectibles += metadata.collectibles.size()
	scan_stats.total_enemies += metadata.enemies.size()
	scan_stats.total_save_points += metadata.save_points.size()
	if metadata.has_boss:
		scan_stats.rooms_with_boss += 1
	if metadata.has_shopkeeper:
		scan_stats.rooms_with_shop += 1
	if metadata.has_teleporter:
		scan_stats.rooms_with_teleporter += 1
	if metadata.has_breakable_walls:
		scan_stats.rooms_with_breakable_walls += 1

func get_feature_summary() -> Dictionary:
	return {
		"total_scenes": scene_database.size(),
		"scenes_with_boss": scan_stats.rooms_with_boss,
		"scenes_with_shop": scan_stats.rooms_with_shop,
		"scenes_with_teleporter": scan_stats.rooms_with_teleporter,
		"scenes_with_breakable": scan_stats.rooms_with_breakable_walls,
		"total_collectibles": scan_stats.total_collectibles,
		"total_enemies": scan_stats.total_enemies,
		"total_save_points": scan_stats.total_save_points,
	}

func get_stats() -> Dictionary:
	return scan_stats.duplicate()
