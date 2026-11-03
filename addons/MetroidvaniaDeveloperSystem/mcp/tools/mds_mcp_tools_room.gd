@tool
class_name MDSMcpToolsRoom
extends MDSMcpTools
## Room scenes: generating, painting and placing things in them, on [MDSRoomPainter], and seeing
## them, as text and as a picture drawn without the GPU.

const TEMPLATES_DIR := "res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/"
const STAMP_GROUPS: PackedStringArray = ["StampsBack", "StampsFront"]
const ASCII_LIMIT := 200
const PREVIEW_LIMIT := 2048
## What each layer looks like in the preview, back to front.
const LAYER_COLORS := {"Background": Color(0.24, 0.27, 0.33), "Terrain": Color(0.56, 0.58, 0.62), "Decor": Color(0.36, 0.62, 0.36), "Foreground": Color(0.42, 0.40, 0.50)}
const PREVIEW_SKY := Color(0.09, 0.10, 0.13)
const PREVIEW_GATE := Color(0.25, 0.85, 0.95)
const PREVIEW_ITEM := Color(0.95, 0.45, 0.30)

func _register() -> void:
	var world := _world_schema()
	var unsaved := _unsaved_schema()
	var layer := S.choice(Array(MDSRoomPainter.LAYER_ORDER))
	_add("mds_tileset_create", "Makes the starter tileset: terrains and decoration tiles, its PNG next to it. An existing file is kept.", AUTHOR,
		{"path": S.text("res://....tres"), "palette": S.choice(MDSTilesetFactory.PALETTES.keys())}, ["path"], _tileset_create)
	_add("mds_room_scene_create", "Makes a room's scene, with its map guides and gate nodes. Default path: the world's scene_folder.", AUTHOR,
		{"world": world, "room": S.text(), "scene_path": S.text()}, ["room"], _scene_create)
	_add("mds_room_generate", "Generates a cave (or a linear, outdoor or arena room) in one room, joining its gates so they can all be reached and walked back. Makes the scene if it has none. Refuses to replace painted terrain unless overwrite is true. A fixed seed gives the same room.", AUTHOR,
		{
			"world": world, "room": S.text(), "style": S.choice(_ids_of(MDSCaveShapes.STYLES)), "shape": S.choice(_ids_of(MDSCaveShapes.CHOICES)), "shapes": S.array(S.choice(Array(MDSCaveShapes.PICKABLE)), "With shape several"),
			"rotation": S.number("Degrees"), "count": S.integer("", 1, 8), "width": S.integer("Tunnel width in tiles", 0), "seed": S.integer(),
			"fills": S.any_object("Layer fills: terrain, background, decor, foreground, as {type: terrain, set, terrain}, {type: kind, kind}, {type: color, color}"),
			"overwrite": S.boolean("Default false"), "on_unsaved": unsaved,
		}, ["room"], _room_generate)
	_add("mds_area_generate_caves", "Generates caves in many rooms: the given rooms, or a whole area. Painted rooms are left alone unless skip_painted is false. Reports progress.", AUTHOR,
		{
			"world": world, "rooms": S.array(S.text()), "area": S.text(),
			"cave": S.any_object("style, shape, shapes, rotation, count, width, as in mds_room_generate"), "fills": S.any_object("As in mds_room_generate"),
			"skip_painted": S.boolean("Default true"), "seed": S.integer(), "on_unsaved": unsaved,
		}, [], _area_caves)
	_add("mds_room_paint", "Paints tiles on a layer of a room's scene, on cells or a rectangle of cells. op: terrain (set, terrain), kind (kind), fill (fill), tile (source, atlas), erase, clear (the whole layer).", AUTHOR,
		{
			"world": world, "room": S.text(), "layer": layer, "op": S.choice(["terrain", "kind", "fill", "tile", "erase", "clear"]),
			"cells": S.cells(), "rect": S.cell_box("Tile cells"), "set": S.integer("", 0), "terrain": S.integer("", 0), "kind": S.text(), "fill": S.any_object(),
			"source": S.integer(), "atlas": S.array(S.integer(), "[x, y]", 2), "on_unsaved": unsaved,
		}, ["room", "layer", "op"], _room_paint)
	_add("mds_room_decorate", "Grass and plants on floors, stalactites, vines and moss under ceilings, inside the room's shape.", AUTHOR,
		{"world": world, "room": S.text(), "seed": S.integer(), "clear": S.boolean("Default true: replaces the Decor layer"), "floor_fill": S.any_object("Most floor decorations are of this fill"), "on_unsaved": unsaved}, ["room"], _room_decorate)
	_add("mds_room_place", "Puts something in a room's scene at pos (scene pixels). kind enemy: template, one of mds_catalog enemy_templates. scene: template, a scene path. stamp: template, a stamp set path, with index, scale, rotation, group. effect: template, an id of mds_catalog effects, with settings.", AUTHOR,
		{
			"world": world, "room": S.text(), "kind": S.choice(["enemy", "scene", "stamp", "effect"]), "template": S.text(), "pos": S.point("Scene pixels"),
			"name": S.text(), "settings": S.any_object(), "index": S.integer("", 0), "scale": S.number("Default 1", 0), "rotation": S.number("Degrees"), "group": S.choice(Array(STAMP_GROUPS)), "on_unsaved": unsaved,
		}, ["room", "kind", "template", "pos"], _room_place)
	_add("mds_room_fit_objects", "floor: stands the room's objects on the floor under them. declutter: spaces out those in each other's way, removing what doesn't fit.", AUTHOR,
		{"world": world, "room": S.text(), "mode": S.choice(["floor", "declutter"]), "on_unsaved": unsaved}, ["room", "mode"], _fit_objects)
	_add("mds_room_remove_item", "Removes a node of a room's scene that isn't a tile layer or a gate.", AUTHOR, {"world": world, "room": S.text(), "node": S.text("Node path from mds_room_items"), "on_unsaved": unsaved}, ["room", "node"], _remove_item, {"destructive": true})
	_add("mds_room_items", "What is in a room's scene: enemies and other scenes, stamps, effects, gates. Paged.", READ, {"world": world, "room": S.text(), "cursor": S.integer("", 0)}, ["room"], _room_items)
	_add("mds_room_ascii", "A room as text, a cheap way to see it: # solid, . open, g gate, E thing. scale N: one character per N tiles.", READ,
		{"world": world, "room": S.text(), "layer": layer, "region": S.cell_box("Tile cells"), "scale": S.integer("Default: fits 200 columns", 1, 64)}, ["room"], _room_ascii)
	_add("mds_room_preview", "A room as a PNG, drawn from its tile layers, gates and items: not how the game renders it.", READ, {"world": world, "room": S.text(), "scale": S.integer("Pixels per tile, default 2", 1, 8)}, ["room"], _room_preview)

static func _ids_of(choices: Array) -> Array:
	return choices.map(func(c: Array) -> String: return c[0])

## A fill as JSON gives it, as [method MDSRoomPainter.paint_fill] takes it.
static func _fill(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var out: Dictionary = value.duplicate()
	if out.has("color") and out.color is String:
		out.color = S.color(out.color, Color.BLACK)
	if out.get("region") is Array and out.region.size() == 4:
		out.region = Rect2i(out.region[0], out.region[1], out.region[2], out.region[3])
	return out

## Fills as JSON gives them: the layers' fills, as [method MDSRoomPainter.generate_cave] takes them.
static func _fills(value: Dictionary) -> Dictionary:
	var out := value.duplicate()
	for key in ["terrain", "background", "decor", "foreground"]:
		if out.has(key):
			out[key] = _fill(out[key])
	return out

func _tileset_create(args: Dictionary, _report: Callable) -> Dictionary:
	var path := MDSMcpGuard.normalize(args.path)
	if path.is_empty() or path.get_extension() != "tres":
		return ctx.fail("bad_arguments", "%s must be a .tres path inside res://." % args.path)
	if FileAccess.file_exists(path):
		return {"tileset": path, "existed": true}
	if not ctx.touch(path) or not ctx.touch(path.get_basename() + ".png"):
		return ctx.error
	var made := MDSTilesetFactory.get_or_create(path, str(args.get("palette", "cave")))
	if not made or not FileAccess.file_exists(path):
		return ctx.fail("save_failed", "Could not make %s." % path)
	return {"tileset": path}

## Makes the room's scene (and tells the world) unless it has one. Returns its path; "" and see
## [member MDSMcpContext.error] if that failed.
func _ensure_scene(world: MDSWorld, id: String, wanted := "") -> String:
	var path := world.get_scene_path(id)
	if not path.is_empty() and FileAccess.file_exists(path):
		return path
	path = MDSMcpGuard.normalize(wanted) if not wanted.is_empty() else _default_scene_path(world, id)
	if path.is_empty() or path.get_extension() != "tscn":
		ctx.error = ctx.fail("bad_arguments", "%s must be a .tscn path inside res://." % wanted)
		return ""
	if not ctx.touch(path):
		return ""
	var err := MDSWorldSceneTools.create_scene_for_room(world, id, path)
	if err != OK:
		ctx.error = ctx.fail("save_failed", "Could not create %s: %s" % [path, MDSWorldSceneTools.last_error if not MDSWorldSceneTools.last_error.is_empty() else error_string(err)])
		return ""
	return path

func _scene_create(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world or not ctx.has_room(world, args.room):
		return ctx.error
	var old := world.get_scene_path(args.room)
	if not old.is_empty() and FileAccess.file_exists(old):
		return ctx.fail("already_exists", "Room %s already has the scene %s." % [args.room, old])
	var path := _ensure_scene(world, args.room, str(args.get("scene_path", "")))
	if path.is_empty():
		return ctx.error
	MDSWorldSceneTools.load_fresh(path)
	ctx.host.room_written(path)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": args.room, "scene": path}

func _room_generate(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world or not ctx.has_room(world, args.room):
		return ctx.error
	var id: String = args.room
	var old := world.get_scene_path(id)
	if not old.is_empty() and FileAccess.file_exists(old) and not ctx.prepare_room_write(old, args):
		return ctx.error
	var path := _ensure_scene(world, id)
	if path.is_empty():
		return ctx.error
	var tiles := ctx.room_tiles(world)
	if not tiles:
		return ctx.error
	var packed := MDSWorldSceneTools.load_fresh(path)
	var painter := MDSRoomPainter.open_packed(packed, path, tiles) if packed else null
	if not painter:
		return ctx.fail("scene_not_loaded", "Could not load %s." % path)
	if not args.get("overwrite", false) and path == old and not painter.layers.Terrain.get_used_cells().is_empty():
		painter.free_instance()
		return ctx.fail("room_already_painted", "%s has terrain already." % id, "Pass overwrite: true to replace it.")
	var fills := _fills(args.get("fills", {}))
	var cave := {}
	for key in ["style", "shape", "shapes", "rotation", "count", "width"]:
		if args.has(key):
			cave[key] = args[key]
	if not cave.is_empty():
		fills.cave = cave
	var rock: Dictionary = fills.get("terrain", {})
	if rock.is_empty() or str(rock.get("type", "")) == "terrain":
		if not painter.has_terrains():
			painter.free_instance()
			return ctx.fail("no_terrains", "The tileset has no terrains.", "Fill terrain with a color or tiles, or use a tileset with terrains.")
		if rock.is_empty():
			var first: Array = painter.get_terrains()[0]
			rock = {"type": "terrain", "set": first[0], "terrain": first[1]}
			fills.terrain = rock
	painter.generate_cave(world, id, int(args.get("seed", 0)), int(rock.get("set", 0)), int(rock.get("terrain", 0)), {}, fills)
	var warnings := []
	if not painter.paths_joined:
		warnings.append("Not all gates could be joined by a walkable path.")
	var bad := _save_room(painter)
	if bad.is_empty():
		bad = ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": id, "scene": path, "paths_joined": warnings.is_empty(), "warnings": warnings}

func _area_caves(args: Dictionary, report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var ids: Array[String] = []
	if args.has("rooms"):
		ids.assign(args.rooms)
	elif args.has("area"):
		if not world.has_area(args.area):
			return ctx.fail("area_not_found", "%s has no area %s." % [world.path, args.area])
		ids = world.get_area_rooms(args.area)
	else:
		return ctx.fail("bad_arguments", "Give rooms or area.")
	for id in ids:
		if not ctx.has_room(world, id):
			return ctx.error
	var tiles := ctx.room_tiles(world)
	if not tiles:
		return ctx.error
	var fills := _fills(args.get("fills", {}))
	if args.has("cave"):
		fills.cave = args.cave
	var seed_value := int(args.get("seed", hash(args.get("area", ""))))
	var out := {"made": [], "generated": [], "skipped": [], "failed": {}}
	var tree := Engine.get_main_loop() as SceneTree
	var path_for := func(id: String) -> String: return _default_scene_path(world, id)
	for i in ids.size():
		var id := ids[i]
		var path := world.get_scene_path(id)
		if path.is_empty() or not FileAccess.file_exists(path):
			path = path_for.call(id)
			if not ctx.touch(path):
				return ctx.error
		else:
			if not ctx.prepare_room_write(path, args):
				return ctx.error
			MDSWorldSceneTools.load_fresh(path)
		var one: Array[String] = [id]
		var r := MDSWorldSceneTools.generate_area_caves(world, one, path_for, fills, tiles, args.get("skip_painted", true), seed_value)
		for key in ["made", "generated", "skipped"]:
			out[key].append_array(r[key])
		out.failed.merge(r.failed)
		if id in r.made or id in r.generated:
			MDSWorldSceneTools.load_fresh(world.get_scene_path(id))
			ctx.host.room_written(world.get_scene_path(id))
		if report.is_valid():
			report.call(i + 1, ids.size(), id)
		await tree.process_frame
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else out

static func _box_cells(box: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(box.y, box.y + box.h):
		for x in range(box.x, box.x + box.w):
			out.append(Vector2i(x, y))
	return out

func _room_paint(args: Dictionary, _report: Callable) -> Dictionary:
	var cells: Array[Vector2i] = []
	if args.has("cells"):
		cells = _cells(args.cells)
	elif args.has("rect"):
		if int(args.rect.w) * int(args.rect.h) > 250000:
			return ctx.fail("too_many_cells", "A rectangle may have up to 250000 cells.")
		cells = _box_cells(args.rect)
	elif args.op != "clear":
		return ctx.fail("bad_arguments", "Give cells or rect.")
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var layer: String = args.layer
	match args.op:
		"terrain":
			painter.paint_terrain(layer, cells, int(args.get("set", 0)), int(args.get("terrain", 0)))
		"kind":
			painter.place_kind(layer, cells, str(args.get("kind", "")))
		"fill":
			painter.paint_fill(layer, cells, _fill(args.get("fill", {})))
		"tile":
			var atlas: Array = args.get("atlas", [0, 0])
			for c in cells:
				painter.place_tile(layer, c, int(args.get("source", 0)), Vector2i(atlas[0], atlas[1]))
		"erase":
			painter.erase(layer, cells)
		"clear":
			painter.clear_layer(layer)
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "layer": layer, "cells": cells.size()}

func _room_decorate(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var placed := painter.auto_decorate(int(args.get("seed", 0)), args.get("clear", true), painter.room_cells(world, args.room), _fill(args.get("floor_fill", {})))
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "placed": placed}

func _room_place(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var template: String = args.template
	var path := template
	if args.kind == "enemy":
		path = template if template.begins_with("res://") else TEMPLATES_DIR + "mds_%s.tscn" % template.trim_prefix("mds_")
	if args.kind in ["enemy", "scene", "stamp"]:
		path = MDSMcpGuard.normalize(path)
		if path.is_empty() or not FileAccess.file_exists(path):
			return ctx.fail("not_found", "%s isn't there." % template, "mds_catalog lists enemy_templates and stamp_sets.")
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var pos := _vec2(args.pos)
	var node: Node2D = null
	match args.kind:
		"enemy", "scene":
			var scene := load(path) as PackedScene
			node = (scene.instantiate() as Node2D) if scene else null
			if node:
				node.position = pos
				if args.has("name"):
					node.name = args.name
				elif args.kind == "enemy":
					node.name = template.get_file().get_basename().trim_prefix("mds_").to_pascal_case()
				painter.root.add_child(node, true)
				node.owner = painter.root
				painter.dirty = true
		"stamp":
			var stamps := load(path) as MDSStampSet
			var size := float(args.get("scale", 1.0))
			node = painter.add_stamp(stamps, int(args.get("index", 0)), pos, Vector2(size, size), deg_to_rad(float(args.get("rotation", 0.0))), str(args.get("group", "StampsFront"))) if stamps else null
		"effect":
			if not template in MDSEnvironment.effect_ids():
				painter.free_instance()
				return ctx.fail("not_found", "%s is not an effect." % template, "mds_catalog lists effects.")
			node = painter.add_effect(template, pos, args.get("settings", {}))
	if not node:
		painter.free_instance()
		return ctx.fail("not_placed", "%s couldn't be placed: it isn't a 2D scene of that kind." % template)
	var at := _path_of(node, painter)
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "node": at}

func _fit_objects(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var tree := Engine.get_main_loop() as SceneTree
	var host := SubViewport.new()
	host.disable_3d = true
	host.size = Vector2i(4, 4)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(host)
	var check := MDSRoomDressing.ground_check(host, painter.root, null, world.get_local_rects(args.room))
	var edits: Array = MDSRoomDressing.fit_to_floor(painter.root, check) if args.mode == "floor" else MDSRoomDressing.declutter(painter.root, check)
	MDSRoomDressing.apply(edits)
	if not edits.is_empty():
		painter.dirty = true
	check.free_proxy()
	host.queue_free()
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "edits": edits.size()}

## [param node]'s path in the saved scene. The painter holds its items apart until it saves.
static func _path_of(node: Node, painter: MDSRoomPainter) -> String:
	if painter.items_root.is_ancestor_of(node):
		return "%s/%s" % [painter.items_root.name, painter.items_root.get_path_to(node)]
	return str(painter.root.get_path_to(node))

## The node at [param path] (see [method _path_of]), or null.
static func _node_at(path: String, painter: MDSRoomPainter) -> Node:
	var items: String = painter.items_root.name + "/"
	if path.begins_with(items):
		return painter.items_root.get_node_or_null(NodePath(path.trim_prefix(items)))
	return painter.root.get_node_or_null(NodePath(path))

## A node that [method _remove_item] may remove: not the layers, the map guides, the items' groups
## or a gate.
static func _is_removable(node: Node, painter: MDSRoomPainter) -> bool:
	if node == painter.root or node is TileMapLayer or node.name == "MapBounds" or node.name == painter.items_root.name or node.get_parent() == painter.items_root:
		return false
	return not node in painter.gate_nodes().values()

func _remove_item(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var node := _node_at(args.node, painter)
	if not node or not _is_removable(node, painter):
		painter.free_instance()
		return ctx.fail("node_not_found", "%s is not a node that can be removed." % args.node, "mds_room_items lists them.")
	painter.remove_item(node)
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"removed": args.node}

func _room_items(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _open_room(world, args.room)
	if not painter:
		return ctx.error
	var out := []
	var gates := painter.gate_nodes()
	for g: String in gates:
		out.append(_item(gates[g], painter, "gate"))
	for n: Node2D in painter.effects():
		out.append(_item(n, painter, "effect"))
	for n: Node2D in painter.pickable_items():
		out.append(_item(n, painter, MDSRoomPainter.item_kind(n)))
	for n in painter.root.get_children():
		if n is Node2D and n.name != painter.items_root.name and not n is TileMapLayer and n.name != "MapBounds" and not n in gates.values():
			out.append(_item(n, painter, "enemy" if n is MDSEnemy else "scene"))
	var page := _page(out, args.get("cursor"))
	painter.free_instance()
	return page

static func _item(node: Node2D, painter: MDSRoomPainter, kind: String) -> Dictionary:
	var out := {"node": _path_of(node, painter), "kind": kind, "pos": _local_pos(node, painter)}
	if not node.scene_file_path.is_empty():
		out.scene = node.scene_file_path
	return out

static func _local_pos(node: Node2D, painter: MDSRoomPainter) -> Vector2:
	var pos := node.position
	var n := node.get_parent()
	while n and n != painter.root and n != painter.items_root:
		if n is Node2D:
			pos = (n as Node2D).transform * pos
		n = n.get_parent()
	return pos

## The tile cell of gate [param gate], inside [param box]: gates sit on a room's outer edge.
static func _gate_cell(world: MDSWorld, id: String, gate: String, tile: Vector2, box: Rect2i) -> Vector2i:
	var cell := Vector2i((world.get_gate_local_pos(id, gate) / tile).floor())
	return cell.clamp(box.position, box.end - Vector2i.ONE)

## The tile cells of the room's rectangles, [lo, hi) in the painter's grid.
static func _cell_bounds(world: MDSWorld, id: String, painter: MDSRoomPainter) -> Rect2i:
	var tile := painter.tile_size()
	var out := Rect2()
	var first := true
	for r in world.get_local_rects(id):
		out = r if first else out.merge(r)
		first = false
	var lo := Vector2i((out.position / tile).floor())
	return Rect2i(lo, Vector2i((out.end / tile).ceil()) - lo)

func _room_ascii(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _open_room(world, args.room)
	if not painter:
		return ctx.error
	var box := _cell_bounds(world, args.room, painter)
	if args.has("region"):
		box = Rect2i(args.region.x, args.region.y, args.region.w, args.region.h)
	var scale := int(args.get("scale", maxi(1, ceili(box.size.x / float(ASCII_LIMIT)))))
	var layer: TileMapLayer = painter.layer(str(args.get("layer", "Terrain")))
	var tile := painter.tile_size()
	var marks := {}
	for g: String in world.get_gates(args.room):
		marks[_gate_cell(world, args.room, g, tile, box)] = "g"
	for n in painter.root.get_children():
		if n is MDSEnemy:
			marks[Vector2i(((n as Node2D).position / tile).floor())] = "E"
	var rows := PackedStringArray()
	for y in range(box.position.y, box.end.y, scale):
		var row := ""
		for x in range(box.position.x, box.end.x, scale):
			var c := "."
			for dy in scale:
				for dx in scale:
					var cell := Vector2i(x + dx, y + dy)
					if marks.has(cell):
						c = marks[cell]
					elif c == "." and layer.get_cell_source_id(cell) != -1:
						c = "#"
			row += c
		rows.append(row)
		if rows.size() >= ASCII_LIMIT:
			break
	painter.free_instance()
	return {"room": args.room, "layer": str(args.get("layer", "Terrain")), "origin_cell": box.position, "scale": scale, "rows": rows}

func _room_preview(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _open_room(world, args.room)
	if not painter:
		return ctx.error
	var box := _cell_bounds(world, args.room, painter)
	var scale := int(args.get("scale", 2))
	scale = mini(scale, maxi(1, PREVIEW_LIMIT / maxi(maxi(box.size.x, box.size.y), 1)))
	var size := box.size * scale
	if size.x <= 0 or size.y <= 0 or size.x > PREVIEW_LIMIT or size.y > PREVIEW_LIMIT:
		painter.free_instance()
		return ctx.fail("too_large", "The room is too large to draw: %s tiles." % box.size)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(PREVIEW_SKY)
	var dot := func(cell: Vector2i, color: Color, grow := 0) -> void:
		var at := (cell - box.position) * scale
		img.fill_rect(Rect2i(at - Vector2i(grow, grow), Vector2i(scale + grow * 2, scale + grow * 2)).intersection(Rect2i(Vector2i.ZERO, size)), color)
	for layer_name: String in MDSRoomPainter.LAYER_ORDER:
		var layer: TileMapLayer = painter.layer(layer_name)
		if layer:
			for cell in layer.get_used_cells():
				if box.has_point(cell):
					dot.call(cell, LAYER_COLORS[layer_name])
	var tile := painter.tile_size()
	for n in painter.root.get_children():
		if n is MDSEnemy:
			dot.call(Vector2i(((n as Node2D).position / tile).floor()), PREVIEW_ITEM, scale)
	for g: String in world.get_gates(args.room):
		dot.call(_gate_cell(world, args.room, g, tile, box), PREVIEW_GATE, scale)
	painter.free_instance()
	return {"room": args.room, "width": size.x, "height": size.y, "_image": Marshalls.raw_to_base64(img.save_png_to_buffer())}
