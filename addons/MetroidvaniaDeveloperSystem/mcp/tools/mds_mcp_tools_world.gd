@tool
class_name MDSMcpToolsWorld
extends MDSMcpTools
## Worlds and maps: rooms, areas and gates, on [MDSWorld].

## The settings an agent may change: what the panel's Settings shows for a world.
const SETTINGS: PackedStringArray = ["auto_gate_nodes", "backdrop", "background", "boss_background", "brightness", "camera", "dark_room_share", "default_room_size", "depth_25d", "depth_style", "geometry_checks", "grid", "light_groups", "map_style", "notch_fill_style", "paint_cell", "parallax", "play_scene", "player", "room_tileset", "save_distance_warn", "scene_folder", "scene_template", "weather"]
## Those that name a file or folder, which must stay inside the project.
const PATH_SETTINGS: PackedStringArray = ["notch_fill_style", "play_scene", "room_tileset", "scene_folder", "scene_template"]
const ROOM_TYPES: PackedStringArray = ["", "normal", "save", "boss", "shop", "teleporter", "corridor", "secret"]
const GENERATOR_SHAPES: PackedStringArray = ["rectangle", "irregular", "freeform", "hybrid"]
const INCLUDES: PackedStringArray = ["settings", "areas", "rooms", "gates"]

func _register() -> void:
	var world := _world_schema()
	_add("mds_world_list", "The world files in the project, with their names and room counts.", READ, {}, [], _world_list)
	_add("mds_world_get", "A world's name, start room, settings, areas and rooms. Rooms are paged.", READ,
		{"world": world, "include": S.array(S.choice(INCLUDES), "Which parts; default settings, areas, rooms. gates adds each room's gates."), "cursor": S.integer("next_cursor of the last page", 0)}, [], _world_get)
	_add("mds_world_create", "Makes a new, empty world file.", AUTHOR,
		{"path": S.text("res://...%s" % MDSWorld.EXTENSION), "name": S.text("Its name"), "settings": S.any_object("See mds_world_update")}, ["path", "name"], _world_create)
	_add("mds_world_update", "Changes a world's name, start room or settings. Settings: %s." % ", ".join(SETTINGS), AUTHOR,
		{"world": world, "name": S.text(), "start_room": S.text(), "settings": S.any_object("Setting -> value; null removes it")}, [], _world_update)
	_add("mds_area_set", "Makes an area, or changes one.", AUTHOR,
		{"world": world, "area": S.text("Its name"), "title": S.text(), "subtitle": S.text(), "color": S.text("#rrggbb"), "parallax": S.text("A parallax background's id"), "darkness": S.number("0 to 1", 0, 1), "rename_to": S.text()}, ["area"], _area_set)
	_add("mds_area_remove", "Removes an area. Its rooms stay, with no area.", AUTHOR, {"world": world, "area": S.text()}, ["area"], _area_remove, {"destructive": true})
	_add("mds_area_generate", "Generates an area's rooms and doors in a box of the map, the panel's Generate area. box is in paint cells. dry_run shows the rooms without making them.", AUTHOR,
		{
			"world": world, "area": S.text(), "box": S.cell_box("In paint cells"), "layer": S.integer("Map layer, default 0", 0),
			"shape": S.choice(GENERATOR_SHAPES, "Default hybrid"),
			"room_min": S.array(S.integer("", 1), "[w, h] in paint cells", 2), "room_max": S.array(S.integer("", 1), "[w, h] in paint cells", 2),
			"irregularity": S.number("", 0, 1), "shafts": S.number("", 0, 1), "loops": S.number("", 0, 1), "roughness": S.number("", 0, 1),
			"tendrils": S.integer("", 0, 16), "curves": S.number("", 0, 1), "slants": S.number("", 0, 1), "seed": S.integer(), "dry_run": S.boolean(),
		}, ["area", "box"], _area_generate)
	_add("mds_room_add", "Adds a room to the map, from a rectangle (world pixels) or paint cells. Returns its id, which differs from the one asked for if that was taken.", AUTHOR,
		{"world": world, "id": S.text(), "rect": S.rect("World pixels"), "cells": S.cells("Paint cells as [x, y] pairs"), "layer": S.integer("Default 0", 0), "area": S.text(), "type": S.choice(ROOM_TYPES), "scene": S.text("An existing scene to use")}, ["id"], _room_add)
	_add("mds_room_update", "Changes a room on the map. rects are local to its origin, [x, y, w, h]; shape is outlines in world pixels, [[x, y], ...], empty to remove.", AUTHOR,
		{
			"world": world, "id": S.text(), "rename_to": S.text(), "area": S.text("Empty: no area"), "type": S.choice(ROOM_TYPES), "origin": S.point("World pixels"),
			"rects": S.array(S.array(S.number(), "", 4)), "shape": S.array(S.array(S.array(S.number(), "", 2))), "scene": S.text("Empty: none"),
		}, ["id"], _room_update)
	_add("mds_room_merge", "Merges rooms into one, bringing what is painted in their scenes along.", AUTHOR,
		{"world": world, "ids": S.array(S.text(), "At least two", 200), "keep_id": S.text("Which id stays")}, ["ids"], _room_merge)
	_add("mds_room_remove", "Removes a room from the map. Its scene file stays unless delete_scene is true.", AUTHOR, {"world": world, "id": S.text(), "delete_scene": S.boolean("Default false")}, ["id"], _room_remove, {"destructive": true})
	_add("mds_gate_add", "Adds a gate to a room. pos is in world pixels. Its side and name come from where it is unless given.", AUTHOR,
		{"world": world, "room": S.text(), "pos": S.point("World pixels"), "side": S.choice(Array(MDSWorld.SIDES)), "name": S.text(), "snap_to_edge": S.boolean("Default true")}, ["room", "pos"], _gate_add)
	_add("mds_gate_update", "Changes a gate. values: requires (abilities), and other gate fields.", AUTHOR,
		{"world": world, "room": S.text(), "gate": S.text(), "rename_to": S.text(), "pos": S.point("World pixels"), "values": S.any_object("Field -> value; null removes it")}, ["room", "gate"], _gate_update)
	_add("mds_gate_remove", "Removes a gate.", AUTHOR, {"world": world, "room": S.text(), "gate": S.text()}, ["room", "gate"], _gate_remove, {"destructive": true})
	_add("mds_gate_connect", "Connects two gates. requires: abilities needed to pass. two_way false makes a one-way drop.", AUTHOR,
		{"world": world, "a": S.text("Room"), "a_gate": S.text(), "b": S.text("Room"), "b_gate": S.text(), "two_way": S.boolean("Default true"), "requires": S.array(S.text())}, ["a", "a_gate", "b", "b_gate"], _gate_connect)
	_add("mds_gate_disconnect", "Disconnects a gate.", AUTHOR, {"world": world, "room": S.text(), "gate": S.text()}, ["room", "gate"], _gate_disconnect)
	_add("mds_gates_auto", "touching: makes a pair of connected gates between rooms that touch. nearest: connects free gates near each other.", AUTHOR,
		{"world": world, "mode": S.choice(["touching", "nearest"]), "max_distance": S.number("nearest: world pixels", 0)}, ["mode"], _gates_auto)

## A room as the tools report it.
static func room_summary(world: MDSWorld, id: String, with_gates := true) -> Dictionary:
	var out := {
		"id": id, "area": world.get_room_area(id), "layer": world.get_room_layer(id),
		"type": str(world.get_room_value(id, "type", "")), "origin": world.get_origin(id), "bounds": world.get_room_bounds(id), "scene": world.get_scene_path(id),
	}
	if with_gates:
		var gates := {}
		var all := world.get_gates(id)
		for g: String in all:
			var gate: Dictionary = all[g]
			var entry := {"side": world.get_gate_side(id, g), "pos": world.get_gate_world_pos(id, g)}
			for key in ["to", "to_gate", "requires"]:
				if gate.has(key):
					entry[key] = gate[key]
			gates[g] = entry
		out.gates = gates
	return out

func _world_list(_args: Dictionary, _report: Callable) -> Dictionary:
	var out := []
	for p in MDSMcpContext.find_worlds():
		var w := ctx.host.open_world(p)
		if w:
			out.append({"path": p, "name": w.get_world_name(), "rooms": w.get_room_ids().size(), "areas": w.get_areas().size()})
	return {"worlds": out}

func _world_get(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var include: Array = args.get("include", ["settings", "areas", "rooms"])
	var out := {"path": world.path, "name": world.get_world_name(), "start_room": world.get_start_room(), "room_count": world.get_room_ids().size()}
	if "settings" in include:
		out.settings = world.data.get("settings", {})
	if "areas" in include:
		out.areas = world.get_areas()
	if "rooms" in include or "gates" in include:
		var rooms := []
		var page := _page(world.get_room_ids(), args.get("cursor"), 50, "ids")
		for id: String in page.ids:
			rooms.append(room_summary(world, id, "gates" in include))
		out.rooms = rooms
		if page.has("next_cursor"):
			out.next_cursor = page.next_cursor
	return out

## Checks and applies [param settings]. Returns a failure, or {}.
func _apply_settings(world: MDSWorld, settings: Dictionary) -> Dictionary:
	for key: String in settings:
		if not key in SETTINGS:
			return ctx.fail("unknown_setting", "%s is not a world setting." % key, "Settings: %s." % ", ".join(SETTINGS))
		if key in PATH_SETTINGS and settings[key] != null and MDSMcpGuard.normalize(str(settings[key])).is_empty():
			return ctx.fail("path_not_allowed", "%s is not a path inside res://." % settings[key])
		if settings[key] == null:
			(world.data.settings as Dictionary).erase(key)
		else:
			world.set_setting(key, settings[key])
	return {}

func _world_create(args: Dictionary, _report: Callable) -> Dictionary:
	var path := MDSMcpGuard.normalize(args.path)
	if path.is_empty() or not MDSWorld.is_world_file(path):
		return ctx.fail("bad_world", "%s must be a path inside res:// ending in %s." % [args.path, MDSWorld.EXTENSION])
	if FileAccess.file_exists(path):
		return ctx.fail("already_exists", "%s already exists." % path)
	if not ctx.touch(path):
		return ctx.error
	var world := MDSWorld.new()
	world.path = path
	world.data.name = args.name
	var bad := _apply_settings(world, args.get("settings", {}))
	if not bad.is_empty():
		return bad
	bad = ctx.save_world(world)
	return bad if not bad.is_empty() else {"world": path}

func _world_update(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	if args.has("name"):
		world.data.name = args.name
	if args.has("start_room"):
		if not ctx.has_room(world, args.start_room):
			return ctx.error
		world.set_start_room(args.start_room)
	var bad := _apply_settings(world, args.get("settings", {}))
	if not bad.is_empty():
		return bad
	bad = ctx.save_world(world)
	return bad if not bad.is_empty() else {"world": world.path}

func _area_set(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var area: String = args.area
	if area.is_empty():
		return ctx.fail("bad_arguments", "area can't be empty.")
	if not world.has_area(area):
		world.add_area(area)
	for key in ["title", "subtitle", "parallax", "darkness"]:
		if args.has(key):
			world.set_area_value(area, key, args[key])
	if args.has("color"):
		if not Color.html_is_valid(args.color):
			return ctx.fail("bad_arguments", "%s is not a color." % args.color)
		world.set_area_value(area, "color", args.color)
	if args.has("rename_to"):
		if world.has_area(args.rename_to):
			return ctx.fail("already_exists", "There is already an area %s." % args.rename_to)
		world.rename_area(area, args.rename_to)
		area = args.rename_to
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"area": area, "values": world.get_areas()[area]}

func _area_remove(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	if not world.has_area(args.area):
		return ctx.fail("area_not_found", "%s has no area %s." % [world.path, args.area])
	world.remove_area(args.area)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"removed": args.area}

static func _generator(args: Dictionary) -> MDSAreaGenerator:
	var g := MDSAreaGenerator.new()
	if args.has("shape"):
		g.shape = GENERATOR_SHAPES.find(args.shape) as MDSAreaGenerator.Shape
	if args.has("room_min") and args.room_min.size() == 2:
		g.room_min = Vector2i(args.room_min[0], args.room_min[1])
	if args.has("room_max") and args.room_max.size() == 2:
		g.room_max = Vector2i(args.room_max[0], args.room_max[1])
	for key in ["irregularity", "shafts", "loops", "roughness", "curves", "slants"]:
		if args.has(key):
			g.set(key, float(args[key]))
	if args.has("tendrils"):
		g.tendrils = args.tendrils
	g.seed_value = int(args.get("seed", 0))
	return g

func _area_generate(args: Dictionary, _report: Callable) -> Dictionary:
	var box := Rect2i(args.box.x, args.box.y, args.box.w, args.box.h)
	var layer := int(args.get("layer", 0))
	var g := _generator(args)
	if args.get("dry_run", false):
		var read := ctx.read_world(args)
		if not read:
			return ctx.error
		var taken := {}
		for c: Vector2i in MDSAreaTools.occupied(read, layer):
			taken[c - box.position] = true
		var p := g.preview(box.size, taken)
		return {"rooms": p.rooms.size(), "doors": p.doors.size(), "cells": p.cells.size(), "dry_run": true}
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var r := g.generate(world, box, layer, args.area)
	if r.rooms.is_empty():
		return ctx.fail("nothing_generated", "No room fit: the box is taken or too small.")
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else r

func _room_add(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var area := str(args.get("area", ""))
	if not area.is_empty() and not world.has_area(area):
		return ctx.fail("area_not_found", "%s has no area %s." % [world.path, area], "mds_area_set makes one.")
	var layer := int(args.get("layer", 0))
	var id := ""
	if args.has("rect"):
		id = world.add_room(args.id, _rect2(args.rect), layer, area)
	elif args.has("cells"):
		id = world.add_room_from_cells(_cells(args.cells), layer, area, args.id)
		if id.is_empty():
			return ctx.fail("cells_taken", "Other rooms cover all those cells.")
	else:
		return ctx.fail("bad_arguments", "Give rect or cells.")
	if args.has("type"):
		world.set_room_value(id, "type", args.type)
	if args.has("scene"):
		var scene := MDSMcpGuard.normalize(args.scene)
		if scene.is_empty() or not FileAccess.file_exists(scene):
			return ctx.fail("scene_not_found", "%s is not a scene inside res://." % args.scene)
		world.set_room_scene(id, scene)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": room_summary(world, id)}

func _room_update(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var id: String = args.id
	if not ctx.has_room(world, id):
		return ctx.error
	if args.has("area"):
		if not args.area.is_empty() and not world.has_area(args.area):
			return ctx.fail("area_not_found", "%s has no area %s." % [world.path, args.area])
		world.set_room_value(id, "area", args.area)
	if args.has("type"):
		world.set_room_value(id, "type", args.type)
	if args.has("origin"):
		world.set_origin(id, _vec2(args.origin))
	if args.has("rects"):
		if args.rects.is_empty():
			return ctx.fail("bad_arguments", "A room needs at least one rectangle.")
		for r: Array in args.rects:
			if r.size() != 4:
				return ctx.fail("bad_arguments", "Each rectangle is [x, y, w, h].")
		world.set_room_value(id, "rects", args.rects)
	if args.has("shape"):
		var polys := []
		for poly: Array in args.shape:
			var points := PackedVector2Array()
			for p: Array in poly:
				if p.size() == 2:
					points.append(Vector2(p[0], p[1]))
			polys.append(points)
		world.set_room_shape(id, polys)
	if args.has("scene"):
		var scene := MDSMcpGuard.normalize(args.scene)
		if not args.scene.is_empty() and (scene.is_empty() or not FileAccess.file_exists(scene)):
			return ctx.fail("scene_not_found", "%s is not a scene inside res://." % args.scene)
		world.set_room_scene(id, scene)
	if args.has("rename_to"):
		id = world.rename_room(id, args.rename_to)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": room_summary(world, id)}

func _room_merge(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var keep := str(args.get("keep_id", ""))
	var why := world.merge_error(args.ids, keep)
	if not why.is_empty():
		return ctx.fail("cant_merge", why)
	for r: String in args.ids:
		var p := world.get_scene_path(r)
		if not p.is_empty() and not ctx.prepare_room_write(p, args):
			return ctx.error
	var r := world.merge_rooms(args.ids, keep)
	if r.has("error"):
		return ctx.fail("cant_merge", str(r.error))
	var id: String = r.id
	var path := world.get_scene_path(id)
	var with_scenes: Array = r.sources.filter(func(src: Dictionary) -> bool: return not str(src.scene_path).is_empty())
	var notes := []
	if not with_scenes.is_empty():
		if path.is_empty():
			path = _default_scene_path(world, id)
			if not ctx.touch(path):
				return ctx.error
			if MDSWorldSceneTools.create_scene_for_room(world, id, path) != OK:
				return ctx.fail("save_failed", "Could not create %s: %s" % [path, MDSWorldSceneTools.last_error])
		else:
			ctx.touch(path)
		var got := MDSWorldSceneTools.combine_room_scenes(world, id, r.sources, ctx.room_tiles(world))
		if got.error != OK:
			notes.append("Their scenes could not be brought in: %s" % MDSWorldSceneTools.last_error)
	if not path.is_empty():
		var drop := PackedStringArray()
		for d: String in r.dropped:
			if d.begins_with(id + "/"):
				drop.append(d.substr(id.length() + 1))
		if MDSWorldSceneTools.prepare_merged_scene(world, id, drop) != OK:
			notes.append("Its gate nodes could not be updated: %s" % MDSWorldSceneTools.last_error)
		MDSWorldSceneTools.load_fresh(path)
		ctx.host.room_written(path)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": room_summary(world, id), "dropped_gates": r.dropped, "warnings": notes}

func _room_remove(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	if not ctx.has_room(world, args.id):
		return ctx.error
	var scene := world.get_scene_path(args.id)
	if args.get("delete_scene", false) and not scene.is_empty() and FileAccess.file_exists(scene):
		if not ctx.prepare_room_write(scene, args):
			return ctx.error
		DirAccess.remove_absolute(scene)
	world.remove_room(args.id)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"removed": args.id}

## The world and checks the gate exists. Null: see [member MDSMcpContext.error].
func _edit_gate(args: Dictionary) -> MDSWorld:
	var world := ctx.edit_world(args)
	if not world or not ctx.has_room(world, args.room):
		return null
	if not world.has_gate(args.room, args.gate):
		ctx.error = ctx.fail("gate_not_found", "Room %s has no gate %s." % [args.room, args.gate], "Gates: %s" % ", ".join(PackedStringArray(world.get_gates(args.room).keys())))
		return null
	return world

func _gate_add(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world or not ctx.has_room(world, args.room):
		return ctx.error
	var gate := world.add_gate(args.room, _vec2(args.pos), str(args.get("side", "")), str(args.get("name", "")), args.get("snap_to_edge", true))
	if gate.is_empty():
		return ctx.fail("gate_not_added", "The gate could not be added to %s." % args.room)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": args.room, "gate": gate, "pos": world.get_gate_world_pos(args.room, gate), "side": world.get_gate_side(args.room, gate)}

func _gate_update(args: Dictionary, _report: Callable) -> Dictionary:
	var world := _edit_gate(args)
	if not world:
		return ctx.error
	var gate: String = args.gate
	if args.has("pos"):
		world.set_gate_world_pos(args.room, gate, _vec2(args.pos))
	var values: Dictionary = args.get("values", {})
	for key: String in values:
		if key in ["pos", "side", "to", "to_gate"]:
			return ctx.fail("bad_arguments", "%s isn't set through values: use pos, mds_gate_connect, or a new gate." % key)
		world.set_gate_value(args.room, gate, key, values[key])
	if args.has("rename_to"):
		gate = world.rename_gate(args.room, gate, args.rename_to)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": args.room, "gate": gate, "values": world.get_gate(args.room, gate)}

func _gate_remove(args: Dictionary, _report: Callable) -> Dictionary:
	var world := _edit_gate(args)
	if not world:
		return ctx.error
	world.remove_gate(args.room, args.gate)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"removed": args.gate}

func _gate_connect(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	for pair: Array in [[args.a, args.a_gate], [args.b, args.b_gate]]:
		if not ctx.has_room(world, pair[0]):
			return ctx.error
		if not world.has_gate(pair[0], pair[1]):
			return ctx.fail("gate_not_found", "Room %s has no gate %s." % pair)
	world.connect_gates(args.a, args.a_gate, args.b, args.b_gate, args.get("two_way", true))
	if args.has("requires"):
		world.set_door_value(MDSWorld.edge_key(args.a, args.a_gate, args.b, args.b_gate), "requires", args.requires)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"door": MDSWorld.edge_key(args.a, args.a_gate, args.b, args.b_gate)}

func _gate_disconnect(args: Dictionary, _report: Callable) -> Dictionary:
	var world := _edit_gate(args)
	if not world:
		return ctx.error
	world.disconnect_gate(args.room, args.gate)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"room": args.room, "gate": args.gate}

func _gates_auto(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var made := world.auto_gates_between_touching() if args.mode == "touching" else world.auto_connect_gates(float(args.get("max_distance", -1.0)))
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"made": made}
