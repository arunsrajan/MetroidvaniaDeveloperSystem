@tool
class_name MDSMcpToolsMap
extends MDSMcpTools
## The rest of the map panel: copying, moving and extending rooms, keeping rooms and scenes in step,
## links and pins, map layers, outlines drawn at their real size, imported map pictures and worlds
## made from a MetSys map, and a picture of the map.

const SHEET_LIMIT := 4096
const MAP_BACKGROUND := Color(0.08, 0.09, 0.12)
const MAP_NO_AREA := Color(0.42, 0.45, 0.52)
const MAP_WALL := Color(0.02, 0.02, 0.03)
const MAP_GATE := Color(0.25, 0.85, 0.95)
const IMPORT_OPTIONS := {
	"auto_grid": TYPE_BOOL, "cell_size": TYPE_VECTOR2, "grid_offset": TYPE_VECTOR2, "background": TYPE_COLOR, "color_tolerance": TYPE_FLOAT, "background_tolerance": TYPE_FLOAT,
	"ink_level": TYPE_FLOAT, "wall_contrast": TYPE_FLOAT, "min_fill": TYPE_FLOAT, "detect_doors": TYPE_BOOL, "connect_unreached": TYPE_BOOL, "passage_cells": TYPE_INT,
	"cell_aspect": TYPE_FLOAT, "cells_per_map_cell": TYPE_VECTOR2I, "shape_cells_across": TYPE_INT,
}
const ROOM_MODES: PackedStringArray = ["walls", "color_regions", "cells", "shapes"]

func _register() -> void:
	var world := _world_schema()
	var notes := {"world": world, "map": S.text("Or a MetSys map file, for its notes")}
	_add("mds_room_duplicate", "Copies a room next to the original, without its gate connections.", AUTHOR, {"world": world, "id": S.text()}, ["id"], _room_duplicate)
	_add("mds_room_cells", "Adds paint cells to a room or takes them away. Taking away every cell removes the room.", AUTHOR,
		{"world": world, "id": S.text(), "add": S.cells(), "erase": S.cells()}, ["id"], _room_cells)
	_add("mds_room_from_scene", "Makes a room from an existing scene, sized to its terrain with its gate nodes as gates. With room, fills that room of the map instead. pos is in world pixels; free_spot moves it to the nearest place no room is.", AUTHOR,
		{"world": world, "scene": S.text("res://....tscn"), "room": S.text(), "pos": S.point("World pixels"), "layer": S.integer("Default 0", 0), "area": S.text(), "free_spot": S.boolean("Default true")}, ["scene"], _room_from_scene)
	_add("mds_room_sync", "Keeps a room and its scene in step. fit: resizes the room to the scene's terrain. import_gates: adds or moves map gates to match the scene's gate nodes. write_gates: adds MDSGate nodes for the map's gates and moves them to their map positions.", AUTHOR,
		{"world": world, "id": S.text(), "op": S.choice(["fit", "import_gates", "write_gates"]), "on_unsaved": _unsaved_schema()}, ["id", "op"], _room_sync)
	_add("mds_rooms_move", "Moves rooms, or an area's rooms and its label, by a distance in world pixels. They may end up over other rooms: mds_validate says so.", AUTHOR,
		{"world": world, "ids": S.array(S.text()), "area": S.text(), "by": S.point("World pixels")}, ["by"], _rooms_move)
	_add("mds_rooms_extend", "Extends rooms by a box in world pixels: each piece goes to the room nearest it, so a box under a row of rooms extends each downwards.", AUTHOR,
		{"world": world, "ids": S.array(S.text()), "box": S.rect("World pixels")}, ["ids", "box"], _rooms_extend)
	_add("mds_area_link", "Doors for rooms or an area's rooms. touching: to every area they touch and have no door to. apart: passages joining parts that touch nothing, of up to bridge paint cells. unlink: removes automatic doors whose rooms no longer touch.", AUTHOR,
		{"world": world, "ids": S.array(S.text()), "area": S.text(), "op": S.choice(["touching", "apart", "unlink"]), "bridge": S.integer("Default 0", 0), "layer": S.integer("Default the first room's", 0)}, ["op"], _area_link)
	_add("mds_layer", "A world's map layers. add: a new layer, its name in name. rename: layer gets name.", AUTHOR,
		{"world": world, "op": S.choice(["add", "rename"]), "layer": S.integer("", 0), "name": S.text()}, ["op", "name"], _layer)
	_add("mds_link", "Links between rooms that gates don't express: elevators, teleporters, moves between layers. list, add (a, b, note), update (index, values), remove (index).", AUTHOR,
		notes.merged({"op": S.choice(["list", "add", "update", "remove"]), "a": S.text("A room"), "b": S.text("A room"), "note": S.text(), "index": S.integer("", 0), "values": S.any_object("Field -> value, such as requires or one_way")}), ["op"], _link)
	_add("mds_pin", "Pins on the map. list, add (pos, text, kind, layer), remove (index). Pins of kind todo and bug show in mds_validate.", AUTHOR,
		notes.merged({"op": S.choice(["list", "add", "remove"]), "pos": S.point("World pixels"), "text": S.text(), "kind": S.choice(Array(MDSAnnotations.PIN_KINDS)), "layer": S.integer("Default 0", 0), "index": S.integer("", 0)}), ["op"], _pin)
	_add("mds_sketch", "Outlines drawn at the rooms' real size, the Full view's, before they are rooms. list; add: draw rectangle or ellipse from a to b, polygon or curvy through points; kind room (one each) or rooms (split up); area is a name, + for a new one, or empty; update (index, kind, area); remove (indices); clear (layer).", AUTHOR,
		{
			"world": world, "op": S.choice(["list", "add", "update", "remove", "clear"]), "draw": S.choice(Array(MDSRoomSketches.DRAW_IDS)), "a": S.point("World pixels"), "b": S.point("World pixels"),
			"points": S.array(S.array(S.number(), "", 2), "[x, y] in world pixels"), "kind": S.choice([MDSRoomSketches.ROOM, MDSRoomSketches.ROOMS]), "area": S.text(), "layer": S.integer("Default 0", 0),
			"index": S.integer("", 0), "indices": S.array(S.integer("", 0)),
		}, ["op"], _sketch)
	_add("mds_sketches_generate", "Makes rooms of outlines from mds_sketch, the Full view's Generate map, with doors between them. dry_run says which paint cells they would take.", AUTHOR,
		{
			"world": world, "layer": S.integer("Default 0", 0), "indices": S.array(S.integer("", 0), "Default all"), "room_min": S.array(S.integer("", 1), "[w, h] in paint cells", 2), "room_max": S.array(S.integer("", 1), "[w, h] in paint cells", 2),
			"irregularity": S.number("", 0, 1), "loops": S.number("", 0, 1), "seed": S.integer(), "link_touching": S.boolean("Default true"), "dry_run": S.boolean(),
		}, [], _sketches_generate)
	_add("mds_map_import", "Turns a picture of a map inside the project into rooms, areas and doors, as the panel's Import map image does. dry_run says what it sees. options: %s. A map exported by MDS has a sidecar that gives its grid exactly." % ", ".join(PackedStringArray(IMPORT_OPTIONS.keys())), AUTHOR,
		{
			"world": world, "image": S.text("res://....png"), "room_mode": S.choice(Array(ROOM_MODES), "Default walls"), "options": S.any_object(), "layer": S.integer("Default 0", 0), "at_cell": S.array(S.integer(), "[x, y] for the picture's top-left room cell", 2),
			"area_names": S.array(S.text(), "In order of the colors dry_run lists"), "keep_cells": S.boolean("Each grid cell lands on the paint cell of the same number"), "dry_run": S.boolean(),
		}, ["image"], _map_import)
	_add("mds_world_from_metsys", "Makes a world from a MetSys map and its notes: cells merge into rooms, passages become connected gates.", AUTHOR,
		{"map": S.text("res://...MapData.txt"), "path": S.text("res://...%s" % MDSWorld.EXTENSION), "cell_size": S.array(S.number("", 1), "[w, h] of a cell in the game, default 1152, 648", 2)}, ["map", "path"], _world_from_metsys)
	_add("mds_map_style_template", "Writes the picture a map style is drawn from: 4 x 5 square tiles (16 edge masks and 4 inner corners), to edit. mds_world_update with map_style tileset:<path> uses it.", AUTHOR,
		{"style": S.choice(Array(MDSMapStyle.BUILTIN), "Default handdrawn"), "path": S.text("res://....png")}, ["path"], _map_style_template)
	_add("mds_map_preview", "A picture of a map layer, drawn from its rooms, areas and gates: not the panel's map styles. mds_export with format png writes it to a file with its sidecar, which mds_map_import reads back exactly.", READ,
		{"world": world, "layer": S.integer("Default 0", 0), "scale": S.integer("Pixels per paint cell, default 8", 1, 64)}, [], _map_preview)

func _ids_given(world: MDSWorld, args: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if args.has("ids"):
		out.assign(args.ids)
	if args.has("area"):
		if not world.has_area(args.area):
			ctx.error = ctx.fail("area_not_found", "%s has no area %s." % [world.path, args.area])
			return []
		out.assign(world.get_area_rooms(args.area))
	if out.is_empty():
		ctx.error = ctx.fail("bad_arguments", "Give ids, or an area with rooms.")
		return []
	for id in out:
		if not ctx.has_room(world, id):
			return []
	return out

func _room_duplicate(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world or not ctx.has_room(world, args.id):
		return ctx.error
	var id := world.duplicate_room(args.id)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"id": id, "origin": world.get_origin(id)}

func _room_cells(args: Dictionary, _report: Callable) -> Dictionary:
	if not args.has("add") and not args.has("erase"):
		return ctx.fail("bad_arguments", "Give add, or erase.")
	var world := ctx.edit_world(args)
	if not world or not ctx.has_room(world, args.id):
		return ctx.error
	if args.has("add"):
		world.paint_cells(args.id, _cells(args.add))
	var mine := world.get_room_cells(args.id)
	var layer := world.get_room_layer(args.id)
	if args.has("erase"):
		# Only this room's: erase_cells takes them from any room on the layer.
		var cells := _cells(args.erase).filter(func(c: Vector2i) -> bool: return mine.has(c))
		world.erase_cells(cells, layer)
	var bad := ctx.save_world(world)
	if not bad.is_empty():
		return bad
	return {"id": args.id, "removed": true} if not world.has_room(args.id) else {"id": args.id, "bounds": world.get_room_bounds(args.id)}

func _room_from_scene(args: Dictionary, _report: Callable) -> Dictionary:
	var scene := MDSMcpGuard.normalize(str(args.scene))
	if scene.is_empty() or not FileAccess.file_exists(scene):
		return ctx.fail("scene_not_found", "%s is not a scene inside res://." % args.scene)
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var meta := MDSSceneScanner.new(world.get_default_room_size()).analyze_scene_any(scene)
	var id: String
	if args.has("room"):
		id = args.room
		if not ctx.has_room(world, id):
			return ctx.error
		if world.has_scene_reference(id):
			return ctx.fail("already_exists", "Room %s already has a scene." % id)
		world.rebase_origin(id, world.get_room_bounds(id).position)
		world.set_room_scene(id, scene)
		if world.get_gates(id).is_empty():
			MDSWorldSceneTools.import_gates(world, id, meta)
	else:
		if args.has("area") and not world.has_area(args.area):
			world.add_area(args.area)
		var pos := _vec2(args.pos) if args.has("pos") else Vector2.ZERO
		id = MDSWorldSceneTools.place_scene(world, scene, meta, pos, int(args.get("layer", 0)), str(args.get("area", "")), args.get("free_spot", true))
		if id.is_empty():
			return ctx.fail("not_placed", "%s couldn't be placed there." % scene)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else MDSMcpToolsWorld.room_summary(world, id)

func _room_sync(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var path := _scene_of(world, args.id)
	if path.is_empty():
		return ctx.error
	var out := {"id": args.id, "op": args.op}
	if args.op == "write_gates":
		if not ctx.prepare_room_write(path, args):
			return ctx.error
		var n := MDSWorldSceneTools.write_gates(world, args.id)
		if n < 0:
			return ctx.fail("save_failed", MDSWorldSceneTools.last_error if not MDSWorldSceneTools.last_error.is_empty() else "Could not write gates to %s." % path)
		MDSWorldSceneTools.load_fresh(path)
		ctx.host.room_written(path)
		out.gate_nodes = n
	else:
		MDSWorldSceneTools.load_fresh(path)
		var meta := MDSSceneScanner.new(world.get_default_room_size()).analyze_scene_any(path)
		if args.op == "fit":
			if not MDSWorldSceneTools.fit_room_to_scene(world, args.id, meta):
				return ctx.fail("nothing_to_fit", "%s has no terrain to fit the room to." % path)
			out.bounds = world.get_room_bounds(args.id)
		else:
			out.gates_changed = MDSWorldSceneTools.import_gates(world, args.id, meta)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else out

func _rooms_move(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var ids := _ids_given(world, args)
	if ids.is_empty():
		return ctx.error
	var origins := {}
	for id in ids:
		origins[id] = world.get_origin(id)
	var labels := {}
	if args.has("area"):
		var at: Variant = world.get_areas()[args.area].get("label_pos")
		labels[args.area] = Vector2(at[0], at[1]) if at is Array and at.size() == 2 else Vector2.INF
	MDSAreaTools.place(world, ids, origins, _vec2(args.by), labels)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"moved": ids}

func _rooms_extend(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var ids := _ids_given(world, args)
	if ids.is_empty():
		return ctx.error
	var parts := MDSAreaTools.split_extension(world, ids, _rect2(args.box))
	var out := {}
	for id: String in parts:
		for r: Rect2 in parts[id]:
			world.add_rect(id, r)
		out[id] = world.get_room_bounds(id)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"extended": out}

func _area_link(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var ids := _ids_given(world, args)
	if ids.is_empty():
		return ctx.error
	var layer := int(args.get("layer", world.get_room_layer(ids[0])))
	var out := {}
	match args.op:
		"touching":
			out.doors = MDSAreaTools.link_touching(world, ids, layer)
		"apart":
			out = MDSAreaTools.link_apart(world, ids, int(args.get("bridge", 0)))
		"unlink":
			out.removed = MDSAreaTools.unlink_apart(world, ids)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else out

func _layer(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var layers: Array = world.data.get("layers", [])
	if args.op == "add":
		layers.append(args.name)
	else:
		var at := int(args.get("layer", -1))
		if at < 0 or at >= layers.size():
			return ctx.fail("bad_arguments", "%s has layers 0 to %d." % [world.path, layers.size() - 1])
		layers[at] = args.name
	world.data.layers = layers
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"layers": layers}

# --- Notes: links and pins -------------------------------------------------------------------

## The notes [param args] means, a world's or a MetSys map's, with what saves them. Null: see
## [member MDSMcpContext.error]. [param write]: they will change.
func _open_notes(args: Dictionary, write: bool) -> MDSAnnotations:
	if not args.has("map"):
		return ctx.edit_world(args) if write else ctx.read_world(args)
	var map := MDSMcpGuard.normalize(str(args.map))
	if map.is_empty() or not FileAccess.file_exists(map):
		ctx.error = ctx.fail("not_found", "%s isn't a map file in the project." % args.map)
		return null
	var ann := MDSAnnotations.load_for_map(map)
	if write and not ctx.touch(ann.path):
		return null
	return ann

func _save_notes(ann: MDSAnnotations) -> Dictionary:
	if ann is MDSWorld:
		return ctx.save_world(ann as MDSWorld)
	var err := ann.save()
	return {} if err == OK else ctx.fail("save_failed", "Could not save %s: %s." % [ann.path, error_string(err)])

func _link(args: Dictionary, _report: Callable) -> Dictionary:
	var ann := _open_notes(args, args.op != "list")
	if not ann:
		return ctx.error
	var links := ann.get_links()
	if args.op == "list":
		return {"links": links}
	match args.op:
		"add":
			if not args.has("a") or not args.has("b"):
				return ctx.fail("bad_arguments", "add needs a and b.")
			if ann is MDSWorld and (not ctx.has_room(ann, args.a) or not ctx.has_room(ann, args.b)):
				return ctx.error
			ann.add_link(args.a, args.b, str(args.get("note", "")))
		"update", "remove":
			var at := int(args.get("index", -1))
			if at < 0 or at >= links.size():
				return ctx.fail("bad_arguments", "index must be from 0 to %d." % (links.size() - 1))
			if args.op == "remove":
				ann.remove_link(at)
			else:
				for key: String in args.get("values", {}):
					ann.set_link_value(at, key, args.values[key])
	var bad := _save_notes(ann)
	return bad if not bad.is_empty() else {"links": ann.get_links()}

func _pin(args: Dictionary, _report: Callable) -> Dictionary:
	var ann := _open_notes(args, args.op != "list")
	if not ann:
		return ctx.error
	if args.op == "list":
		return {"pins": ann.get_pins()}
	if args.op == "add":
		if not args.has("pos"):
			return ctx.fail("bad_arguments", "add needs pos.")
		ann.add_pin(int(args.get("layer", 0)), _vec2(args.pos), str(args.get("text", "")), str(args.get("kind", "note")))
	else:
		var at := int(args.get("index", -1))
		if at < 0 or at >= ann.get_pins().size():
			return ctx.fail("bad_arguments", "index must be from 0 to %d." % (ann.get_pins().size() - 1))
		ann.remove_pin(at)
	var bad := _save_notes(ann)
	return bad if not bad.is_empty() else {"pins": ann.get_pins()}

# --- Outlines --------------------------------------------------------------------------------

func _sketch(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args) if args.op != "list" else ctx.read_world(args)
	if not world:
		return ctx.error
	var layer := int(args.get("layer", 0))
	var out := {}
	match args.op:
		"list":
			var list := []
			var all := MDSRoomSketches.get_all(world)
			for i in all.size():
				var s: Dictionary = all[i]
				list.append({"index": i, "layer": s.get("layer", 0), "kind": s.get("kind", ""), "area": s.get("area", ""), "draw": s.get("draw", ""), "points": (s.get("points", []) as Array).size() / 2})
			return {"sketches": list}
		"add":
			var poly := _sketch_polygon(args)
			if poly.is_empty():
				return ctx.fail("bad_arguments", "rectangle and ellipse need a and b; polygon and curvy need points.")
			var at := MDSRoomSketches.add(world, layer, poly, str(args.get("kind", MDSRoomSketches.ROOM)), str(args.get("area", MDSRoomSketches.NEW_AREA)), str(args.get("draw", "polygon")))
			if at < 0:
				return ctx.fail("bad_arguments", "That is no outline: it needs three points and some area.")
			out.index = at
		"update":
			var at := int(args.get("index", -1))
			if MDSRoomSketches.get_sketch(world, at).is_empty():
				return ctx.fail("bad_arguments", "There is no outline %d." % at)
			for key in ["kind", "area"]:
				if args.has(key):
					MDSRoomSketches.set_value(world, at, key, args[key])
			out.index = at
		"remove":
			MDSRoomSketches.remove(world, args.get("indices", []))
		"clear":
			MDSRoomSketches.clear_layer(world, layer)
	var bad := ctx.save_world(world)
	if not bad.is_empty():
		return bad
	out.count = MDSRoomSketches.get_all(world).size()
	return out

static func _sketch_polygon(args: Dictionary) -> PackedVector2Array:
	var draw := str(args.get("draw", "polygon"))
	if draw in ["rectangle", "ellipse"]:
		if not args.has("a") or not args.has("b"):
			return PackedVector2Array()
		return MDSRoomSketches.rectangle(_vec2(args.a), _vec2(args.b)) if draw == "rectangle" else MDSRoomSketches.ellipse(_vec2(args.a), _vec2(args.b))
	var points := PackedVector2Array()
	for p: Array in args.get("points", []):
		if p.size() == 2:
			points.append(Vector2(p[0], p[1]))
	return MDSRoomSketches.freehand(points) if draw == "curvy" else points

func _sketches_generate(args: Dictionary, _report: Callable) -> Dictionary:
	var dry: bool = args.get("dry_run", false)
	var world := ctx.read_world(args) if dry else ctx.edit_world(args)
	if not world:
		return ctx.error
	var maker := MDSRoomSketches.new()
	for key in ["room_min", "room_max"]:
		if args.has(key) and args[key].size() == 2:
			maker.set(key, Vector2i(args[key][0], args[key][1]))
	if args.has("irregularity"):
		maker.irregularity = args.irregularity
	if args.has("loops"):
		maker.loops = args.loops
	if args.has("seed"):
		maker.seed_value = args.seed
	if args.has("link_touching"):
		maker.link_touching = args.link_touching
	var layer := int(args.get("layer", 0))
	var indices: Array = args.get("indices", [])
	if dry:
		var seen := []
		for o: Dictionary in maker.preview(world, layer, indices):
			seen.append({"kind": o.kind, "area": o.area, "cells": (o.cells as Array).size() if o.cells is Array else (o.cells as Dictionary).size()})
		return {"outlines": seen}
	var made := maker.generate(world, layer, indices)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else made

# --- Pictures of maps ------------------------------------------------------------------------

func _map_import(args: Dictionary, _report: Callable) -> Dictionary:
	var image := MDSMcpGuard.normalize(str(args.image))
	if image.is_empty() or not FileAccess.file_exists(image):
		return ctx.fail("not_found", "%s isn't a picture in the project." % args.image)
	var imp := MDSMapImageImporter.new()
	if imp.load_image(image) != OK:
		return ctx.fail("not_loaded", "Could not read %s as a picture." % image)
	var problem := _apply_import_options(imp, args)
	if not problem.is_empty():
		return ctx.fail("bad_value", problem)
	var found := imp.analyze()
	var seen := {"rooms": (found.get("rooms", []) as Array).size(), "areas": (found.get("areas", []) as Array).size(), "doors": (found.get("doors", []) as Array).size(), "cell_size": found.get("cell_size", Vector2.ZERO), "shapes": found.get("shapes", false)}
	if args.get("dry_run", false):
		return {"found": seen}
	if seen.rooms == 0:
		return ctx.fail("nothing_found", "No rooms found in %s." % image, "Try room_mode, or options such as cell_size.")
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var at := Vector2i.MAX
	if args.has("at_cell"):
		at = Vector2i(args.at_cell[0], args.at_cell[1])
	var made := imp.apply(world, int(args.get("layer", 0)), at, args.get("area_names", []), args.get("keep_cells", false))
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else made

static func _apply_import_options(imp: MDSMapImageImporter, args: Dictionary) -> String:
	if args.has("room_mode"):
		imp.room_mode = ROOM_MODES.find(args.room_mode)
	var options: Dictionary = args.get("options", {})
	var reader := MDSMcpValues.new()
	for key: String in options:
		if not IMPORT_OPTIONS.has(key):
			return "%s is not an option. Options: %s." % [key, ", ".join(PackedStringArray(IMPORT_OPTIONS.keys()))]
		var value: Variant = reader.decode(options[key], {"name": key, "type": IMPORT_OPTIONS[key], "hint": 0, "hint_string": ""})
		if not reader.error.is_empty():
			return reader.error
		imp.set(key, value)
	return ""

func _world_from_metsys(args: Dictionary, _report: Callable) -> Dictionary:
	var map := MDSMcpGuard.normalize(str(args.map))
	if map.is_empty() or not FileAccess.file_exists(map):
		return ctx.fail("not_found", "%s isn't a map file in the project." % args.map)
	var path := MDSMcpGuard.normalize(str(args.path))
	if path.is_empty() or not MDSWorld.is_world_file(path):
		return ctx.fail("bad_world", "%s must be a path inside res:// ending in %s." % [args.path, MDSWorld.EXTENSION])
	if FileAccess.file_exists(path):
		return ctx.fail("already_exists", "%s already exists." % path)
	if not ctx.touch(path):
		return ctx.error
	var size: Array = args.get("cell_size", [1152, 648])
	var world := MDSWorld.from_metsys(MDSMapModel.load_file(map), MDSAnnotations.load_for_map(map), Vector2(size[0], size[1]))
	world.path = path
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"world": path, "rooms": world.get_room_ids().size()}

## A picture of [param layer] of [param world]: {image, pan, cell_px}, or {error}.
static func draw_map(world: MDSWorld, layer: int, scale: int) -> Dictionary:
	var bounds := world.get_layer_bounds(layer)
	if not bounds.has_area():
		return {"error": "Layer %d has no rooms." % layer}
	var cell := world.get_paint_cell()
	var per_px := Vector2(scale, scale) / cell
	var margin := Vector2(scale * 2, scale * 2)
	var size := Vector2i((bounds.size * per_px + margin * 2.0).ceil())
	if size.x > SHEET_LIMIT or size.y > SHEET_LIMIT:
		return {"error": "That would be %d x %d pixels. Use a smaller scale." % [size.x, size.y]}
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(MAP_BACKGROUND)
	var pan := margin - bounds.position * per_px
	var to_px := func(r: Rect2) -> Rect2i: return Rect2i(Rect2(r.position * per_px + pan, r.size * per_px))
	for id in world.get_room_ids():
		if world.get_room_layer(id) == layer:
			var color := world.get_area_color(world.get_room_area(id)) if world.has_area(world.get_room_area(id)) else MAP_NO_AREA
			color.a = 1.0
			for r: Rect2 in world.get_world_rects(id):
				var box: Rect2i = to_px.call(r)
				img.fill_rect(box, MAP_WALL)
				img.fill_rect(box.grow(-1), color)
	for id in world.get_room_ids():
		if world.get_room_layer(id) == layer:
			for g: String in world.get_gates(id):
				var at := Vector2i(world.get_gate_world_pos(id, g) * per_px + pan)
				img.fill_rect(Rect2i(at - Vector2i(2, 2), Vector2i(5, 5)), MAP_GATE)
	return {"image": img, "pan": pan, "cell_px": Vector2(scale, scale)}

func _map_style_template(args: Dictionary, _report: Callable) -> Dictionary:
	var path := MDSMcpGuard.normalize(str(args.path))
	if path.is_empty() or path.get_extension() != "png":
		return ctx.fail("bad_arguments", "%s must be a .png path inside res://." % args.path)
	if not ctx.touch(path):
		return ctx.error
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := MDSMapStyle.save_template(str(args.get("style", "handdrawn")), path)
	if err != OK:
		return ctx.fail("save_failed", "Could not write %s: %s." % [path, error_string(err)])
	ctx.host.resource_written(path)
	return {"written": path, "use_as": "tileset:" + path}

func _map_preview(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var layer := int(args.get("layer", 0))
	var drawn := draw_map(world, layer, int(args.get("scale", 8)))
	if drawn.has("error"):
		return ctx.fail("cant_draw", drawn.error)
	var img: Image = drawn.image
	var out := {"layer": layer, "width": img.get_width(), "height": img.get_height()}
	out["_image"] = Marshalls.raw_to_base64(img.save_png_to_buffer())
	return out
