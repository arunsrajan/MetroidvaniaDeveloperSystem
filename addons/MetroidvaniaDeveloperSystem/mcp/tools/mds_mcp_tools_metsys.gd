@tool
class_name MDSMcpToolsMetSys
extends MDSMcpTools
## MetSys mode: a map painted in the MetSys editor. The map file is MetSys' and is never written:
## what the tools change is the notes beside it (MapData.mds.json), as the panel does. Links and
## pins take a map too: see mds_link and mds_pin.

const SEVERITIES: PackedStringArray = ["info", "warning", "error"]
const ROOM_VALUES: PackedStringArray = ["name", "type", "status", "boss", "grants", "notes", "area"]

func _register() -> void:
	var map := S.text("MetSys map file, res://...MapData.txt. Left out: the project's only one")
	var size := S.array(S.number("", 1), "[w, h] of a cell in the game, default 1152, 648", 2)
	_add("mds_metsys_get", "A MetSys map: its rooms, each with its name, type, cells, scene and notes, and its doors with what they need. Paged.", READ,
		{"map": map, "doors": S.boolean("Default false"), "cursor": S.integer("", 0)}, [], _metsys_get)
	_add("mds_metsys_annotate", "Notes on a MetSys map. room and values: %s. door (from mds_metsys_get), requires, one_way_from. start_room." % ", ".join(ROOM_VALUES), AUTHOR,
		{"map": map, "room": S.text("Room id"), "values": S.any_object(), "door": S.text("Door key"), "requires": S.array(S.text()), "one_way_from": S.text("A room, or empty for both ways"), "start_room": S.text(), "settings": S.object({"player": S.any_object("The player for the room checks, as a world's player setting"), "geometry_checks": S.boolean()})}, [], _metsys_annotate)
	_add("mds_metsys_check", "What the panel's Progress and Issues tabs say of a MetSys map, from its scenes as they are now. issues (paged), progression, backtracking, path (from, to), ability_uses (ability), geometry (plays rooms, gates passable and platforms landable with the map's player).", READ,
		{"map": map, "kind": S.choice(["issues", "progression", "backtracking", "path", "ability_uses", "objectives", "geometry"]), "rooms": S.array(S.text(), "geometry: which, default all"), "cell_size": size, "from": S.text(), "to": S.text(), "ability": S.text(), "cursor": S.integer("", 0)}, ["kind"], _metsys_check)
	_add("mds_metsys_export", "A MetSys map's data and progression as json, a dot graph, or a markdown document. Returns it, or writes it to path.", AUTHOR,
		{"map": map, "format": S.choice(["json", "dot", "markdown"]), "cell_size": size, "path": S.text("Writes it there")}, ["format"], _metsys_export)

## The map file [param args] means. "": see [member MDSMcpContext.error].
func _map_path(args: Dictionary) -> String:
	if args.has("map"):
		var p := MDSMcpGuard.normalize(str(args.map))
		if p.is_empty() or not FileAccess.file_exists(p):
			ctx.error = ctx.fail("not_found", "%s isn't a map file in the project." % args.map)
			return ""
		return p
	var found := _find_maps("res://")
	if found.size() == 1:
		return found[0]
	ctx.error = ctx.fail("map_needed", "No map given and %d in the project." % found.size(), "Pass map: one of %s." % ", ".join(found) if not found.is_empty() else "There is no MapData.txt in the project.")
	return ""

static func _find_maps(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(folder):
		if f == "MapData.txt":
			out.append(folder.path_join(f))
	for d in DirAccess.get_directories_at(folder):
		if not d.begins_with(".") and d != "addons":
			out.append_array(_find_maps(folder.path_join(d)))
	return out

func _metsys_get(args: Dictionary, _report: Callable) -> Dictionary:
	var path := _map_path(args)
	if path.is_empty():
		return ctx.error
	var model := MDSMapModel.load_file(path)
	var ann := MDSAnnotations.load_for_map(path)
	var rooms := []
	for room: MDSMapModel.Room in model.rooms.values():
		var entry := {"id": room.id, "scene": room.scene_path, "layer": room.cells[0].z if not room.cells.is_empty() else 0, "cells": room.cells.size(), "groups": model.get_room_group_names(room)}
		entry.merge(ann.get_room(room.id))
		rooms.append(entry)
	var out := _page(rooms, args.get("cursor"), 100, "rooms")
	out.map = path
	out.layers = model.layers
	out.start_room = ann.get_start_room()
	if args.get("doors", false):
		var doors := []
		for key: String in model.doors:
			var door: MDSMapModel.Door = model.doors[key]
			doors.append({"door": key, "a": door.a_room.id if door.a_room else "", "b": door.b_room.id if door.b_room else "", "requires": ann.get_door_requires(key), "one_way_from": ann.get_door_one_way_from(key)})
		out.doors = doors
	return out

func _metsys_annotate(args: Dictionary, _report: Callable) -> Dictionary:
	var path := _map_path(args)
	if path.is_empty():
		return ctx.error
	var model := MDSMapModel.load_file(path)
	var ann := MDSAnnotations.load_for_map(path)
	if not ctx.touch(ann.path):
		return ctx.error
	if args.has("room"):
		if not model.rooms.has(args.room):
			return ctx.fail("room_not_found", "The map has no room %s." % args.room, "mds_metsys_get lists them.")
		var values: Dictionary = args.get("values", {})
		for key: String in values:
			if not key in ROOM_VALUES:
				return ctx.fail("bad_arguments", "%s is not a value of a room. Values: %s." % [key, ", ".join(ROOM_VALUES)])
			if key == "type" and not values[key] in MDSAnnotations.ROOM_TYPES:
				return ctx.fail("bad_arguments", "%s is not a room type. Types: %s." % [values[key], ", ".join(MDSAnnotations.ROOM_TYPES)])
			if key == "status" and not values[key] in MDSAnnotations.STATUSES:
				return ctx.fail("bad_arguments", "%s is not a status. Statuses: %s." % [values[key], ", ".join(MDSAnnotations.STATUSES)])
			ann.set_room_value(args.room, key, values[key])
	if args.has("door"):
		if not model.doors.has(args.door):
			return ctx.fail("door_not_found", "The map has no door %s." % args.door, "mds_metsys_get with doors lists them.")
		if args.has("requires"):
			ann.set_door_value(args.door, "requires", args.requires)
		if args.has("one_way_from"):
			ann.set_door_value(args.door, "one_way_from", args.one_way_from)
	if args.has("start_room"):
		if not args.start_room.is_empty() and not model.rooms.has(args.start_room):
			return ctx.fail("room_not_found", "The map has no room %s." % args.start_room)
		ann.set_start_room(args.start_room)
	var settings: Dictionary = args.get("settings", {})
	for key: String in settings:
		ann.set_setting(key, settings[key])
	var err := ann.save()
	if err != OK:
		return ctx.fail("save_failed", "Could not save %s: %s." % [ann.path, error_string(err)])
	return {"map": path, "notes": ann.path}

## The map analysed from its scenes: {model, ann, db, paths, analysis}. Empty: see
## [member MDSMcpContext.error].
func _analyze(args: Dictionary) -> Dictionary:
	var path := _map_path(args)
	if path.is_empty():
		return {}
	var size: Array = args.get("cell_size", [1152, 648])
	var cell := Vector2(size[0], size[1])
	var model := MDSMapModel.load_file(path)
	var ann := MDSAnnotations.load_for_map(path)
	var scanner := MDSSceneScanner.new(cell)
	var paths: Array[String] = []
	for room: MDSMapModel.Room in model.rooms.values():
		if not room.scene_path.is_empty() and FileAccess.file_exists(room.scene_path) and not room.scene_path in paths:
			MDSWorldSceneTools.load_fresh(room.scene_path)
			paths.append(room.scene_path)
	var db: Dictionary = await scanner.scan_paths(paths)
	var analysis := MDSAnalysis.new(MDSGraph.from_metsys(model, db, cell), ann, db).run()
	return {"model": model, "ann": ann, "db": db, "paths": paths, "analysis": analysis}

## Plays the map's rooms in simulation, as the panel's room checks do.
func _geometry(args: Dictionary) -> Dictionary:
	var path := _map_path(args)
	if path.is_empty():
		return ctx.error
	var size: Array = args.get("cell_size", [1152, 648])
	var cell := Vector2(size[0], size[1])
	var model := MDSMapModel.load_file(path)
	var player: Variant = MDSAnnotations.load_for_map(path).get_setting("player", {})
	var tree := Engine.get_main_loop() as SceneTree
	var host := SubViewport.new()
	host.disable_3d = true
	host.size = Vector2i(4, 4)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(host)
	var out := {}
	var skipped := []
	for room: MDSMapModel.Room in model.rooms.values():
		if args.has("rooms") and not room.id in args.rooms:
			continue
		if room.scene_path.is_empty() or not FileAccess.file_exists(room.scene_path):
			skipped.append(room.id)
			continue
		MDSWorldSceneTools.load_fresh(room.scene_path)
		var issues := MDSGeometryChecker.check_now({"path": room.scene_path, "name": room.id, "rects": MDSRoomCheck.rects_from_metsys(room, cell), "passages": MDSRoomCheck.passages_from_metsys(model, room, cell), "player": player, "cell_size": cell}, host)
		out[room.id] = issues.map(func(i: Dictionary) -> Dictionary: return {"severity": SEVERITIES[int(i.get("severity", 0))], "category": i.get("category", ""), "message": i.get("message", "")})
		await tree.process_frame
	host.queue_free()
	return {"rooms": out, "no_scene": skipped}

func _metsys_check(args: Dictionary, _report: Callable) -> Dictionary:
	if args.kind == "geometry":
		return await _geometry(args)
	var found: Dictionary = await _analyze(args)
	if found.is_empty():
		return ctx.error
	var a: MDSAnalysis = found.analysis
	match args.kind:
		"issues":
			var issues := []
			for i: Variant in MDSValidator.run(found.model, found.ann, a, found.db, found.paths):
				issues.append({"severity": SEVERITIES[int(i.severity)], "category": i.category, "message": i.message, "room": i.room_id})
			return _page(issues, args.get("cursor"), 100, "issues")
		"progression":
			return MDSExporters.progression_to_dict(a)
		"backtracking":
			return {"save_distance": a.save_distance, "start_distance": a.start_distance, "dead_ends": a.dead_ends, "chokepoints": a.chokepoints, "hubs": a.hubs}
		"path":
			if not args.has("from") or not args.has("to"):
				return ctx.fail("bad_arguments", "path needs from and to.")
			return {"path": a.find_path(args.from, args.to)}
		"ability_uses":
			if not args.has("ability"):
				return ctx.fail("bad_arguments", "ability_uses needs ability.")
			return {"ability": args.ability, "uses": a.get_ability_uses(args.ability), "sources": a.get_ability_sources(args.ability)}
	return {"objectives": a.get_objectives()}

func _metsys_export(args: Dictionary, _report: Callable) -> Dictionary:
	var found: Dictionary = await _analyze(args)
	if found.is_empty():
		return ctx.error
	var a: MDSAnalysis = found.analysis
	var text := ""
	match args.format:
		"json":
			text = MDSExporters.to_json(found.model, found.ann, a, found.db, [])
		"dot":
			text = MDSExporters.to_dot(a)
		"markdown":
			var issues := MDSValidator.run(found.model, found.ann, a, found.db, found.paths)
			text = MDSExporters.to_markdown((found.model as MDSMapModel).source_path.get_file(), {"Rooms": (found.model as MDSMapModel).rooms.size()}, found.ann, a, issues)
	if not args.has("path"):
		return {"format": args.format, "text": text}
	if not ctx.touch(args.path):
		return ctx.error
	var path := MDSMcpGuard.normalize(args.path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return ctx.fail("save_failed", "Could not write %s: %s." % [path, error_string(FileAccess.get_open_error())])
	f.store_string(text)
	f.close()
	return {"format": args.format, "written": path}
