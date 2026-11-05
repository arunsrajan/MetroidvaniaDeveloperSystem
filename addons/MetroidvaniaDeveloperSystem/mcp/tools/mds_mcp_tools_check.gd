@tool
class_name MDSMcpToolsCheck
extends MDSMcpTools
## Checks: the validator, the progression analysis, whether rooms can be walked, and the exports.

## In the order of [enum MDSValidator.Severity].
const SEVERITIES: PackedStringArray = ["info", "warning", "error"]
const CHECK_ROOMS_MAX := 200

func _register() -> void:
	var world := _world_schema()
	_add("mds_validate", "The world's problems: unreachable rooms, broken doors, missing scenes, far saves. Paged.", READ,
		{"world": world, "min_severity": S.choice(Array(SEVERITIES), "Default info"), "cursor": S.integer("", 0)}, [], _validate)
	_add("mds_analysis", "progression: what is reached with which ability, and what never is. backtracking: rooms by save distance, dead ends, hubs. path: the route from one room to another. ability_uses: where an ability is needed and found (ability). objectives: the world's goals. stats: the panel's Stats tab: rooms, areas, bosses and how far they are built.", READ,
		{"world": world, "kind": S.choice(["progression", "backtracking", "path", "ability_uses", "objectives", "stats"]), "from": S.text(), "to": S.text(), "ability": S.text()}, ["kind"], _analysis)
	_add("mds_scene_scan", "What the panel's scanner finds in a scene: collectibles, enemies, save points, bosses, shops, teleporters, gate nodes, terrain and its bounds.", READ,
		{"world": world, "room": S.text(), "scene": S.text("Or a scene file"), "folder": S.text("Or every scene under a folder: rooms not on the map yet, with the world given, say so"), "cursor": S.integer("", 0)}, [], _scene_scan)
	_add("mds_room_check", "Plays rooms in simulation: gates passable, platforms landable, climbs reachable with the world's player settings.", READ,
		{"world": world, "rooms": S.array(S.text(), "", CHECK_ROOMS_MAX)}, ["rooms"], _room_check)
	_add("mds_export", "The world's progression and design as json, a dot graph, or a markdown document; or the map as a png with a sidecar: in the editor as the panel draws it, else plain (mds_map_preview). Returns it, or writes it to path.", AUTHOR,
		{"world": world, "format": S.choice(["json", "dot", "markdown", "png"]), "layer": S.integer("png: default 0", 0), "scale": S.integer("png: pixels per paint cell, default 8", 1, 64), "path": S.text("Writes it there")}, ["format"], _export)

## Analysis of [param world] from its scenes as they are now.
func analyze(world: MDSWorld) -> Dictionary:
	var scanner := MDSSceneScanner.new(world.get_default_room_size())
	scanner.require_room_instance = false
	var paths: Array[String] = []
	for id in world.get_room_ids():
		var p := world.get_scene_path(id)
		if not p.is_empty() and FileAccess.file_exists(p) and not p in paths:
			MDSWorldSceneTools.load_fresh(p)
			paths.append(p)
	var db: Dictionary = await scanner.scan_paths(paths)
	var graph := MDSGraph.from_world(world, db)
	var analysis := MDSAnalysis.new(graph, world, db).run()
	return {"db": db, "analysis": analysis}

func _validate(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var found: Dictionary = await analyze(world)
	var least := SEVERITIES.find(str(args.get("min_severity", "info")))
	var issues := []
	var counts := {}
	for i: Dictionary in MDSWorldValidator.run(world, found.analysis, found.db):
		var rank := int(i.get("severity", 0))
		var severity := SEVERITIES[rank]
		counts[severity] = int(counts.get(severity, 0)) + 1
		if rank >= least:
			issues.append({"severity": severity, "category": i.get("category", ""), "message": i.get("message", ""), "room": i.get("room_id", "")})
	var out := _page(issues, args.get("cursor"), 100, "issues")
	out.counts = counts
	return out

func _analysis(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var found: Dictionary = await analyze(world)
	var a: MDSAnalysis = found.analysis
	match args.kind:
		"progression":
			return MDSExporters.progression_to_dict(a)
		"backtracking":
			return {"save_distance": a.save_distance, "start_distance": a.start_distance, "dead_ends": a.dead_ends, "chokepoints": a.chokepoints, "hubs": a.hubs}
		"path":
			if not args.has("from") or not args.has("to"):
				return ctx.fail("bad_arguments", "path needs from and to.")
			if not ctx.has_room(world, args.from) or not ctx.has_room(world, args.to):
				return ctx.error
			return {"path": a.find_path(args.from, args.to)}
		"ability_uses":
			if not args.has("ability"):
				return ctx.fail("bad_arguments", "ability_uses needs ability.")
			return {"ability": args.ability, "uses": a.get_ability_uses(args.ability), "sources": a.get_ability_sources(args.ability)}
		"stats":
			return _stats(world, a)
	return {"objectives": a.get_objectives()}

## What the Stats tab counts.
static func _stats(world: MDSWorld, a: MDSAnalysis) -> Dictionary:
	var status := {}
	var bosses := []
	var by_area := {}
	var with_scene := 0
	for id in world.get_room_ids():
		var s := str(world.get_room_value(id, "status", ""))
		status[s if not s.is_empty() else "unset"] = int(status.get(s if not s.is_empty() else "unset", 0)) + 1
		var area := world.get_room_area(id)
		by_area[area if not area.is_empty() else "no area"] = int(by_area.get(area if not area.is_empty() else "no area", 0)) + 1
		if world.has_scene_reference(id):
			with_scene += 1
		if str(world.get_room_value(id, "type", "")) == "boss" or not str(world.get_room_value(id, "boss", "")).is_empty():
			bosses.append({"room": id, "boss": str(world.get_room_value(id, "boss", "")), "save_distance": a.save_distance.get(id, -1)})
	return {"rooms": world.get_room_ids().size(), "rooms_with_scene": with_scene, "areas": world.get_areas().size(), "rooms_by_area": by_area, "rooms_by_status": status, "bosses": bosses, "objectives": a.get_objectives().size()}

## The scenes under a folder, as Scan project folder finds them.
func _scan_folder(args: Dictionary) -> Dictionary:
	var folder := MDSMcpGuard.normalize(str(args.folder))
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return ctx.fail("not_found", "%s isn't a folder in the project." % args.folder)
	var on_map := {}
	var world: MDSWorld = null
	if args.has("world") or not ctx.host.open_world_path().is_empty():
		world = ctx.read_world(args)
		if not world:
			return ctx.error
		for id in world.get_room_ids():
			on_map[world.get_scene_path(id)] = id
	var finder := MDSSceneScanner.new(world.get_default_room_size() if world else Vector2(1152, 648))
	var maps := []
	finder.scan_map_data_txt_completed.connect(func(p: String) -> void: maps.append(p))
	var files: Array[String] = []
	finder.find_scene_files(folder, files)
	var found := []
	for p in files:
		var entry := {"scene": p}
		if on_map.has(p):
			entry.room = on_map[p]
		found.append(entry)
	var page := _page(found, args.get("cursor"), 200, "scenes")
	page.metsys_maps = maps
	return page

func _scene_scan(args: Dictionary, _report: Callable) -> Dictionary:
	if args.has("folder"):
		return _scan_folder(args)
	var path := MDSMcpGuard.normalize(str(args.get("scene", "")))
	var size := Vector2(1152, 648)
	if not args.has("scene"):
		if not args.has("room"):
			return ctx.fail("bad_arguments", "Give room, or scene.")
		var world := ctx.read_world(args)
		if not world:
			return ctx.error
		path = _scene_of(world, args.room)
		if path.is_empty():
			return ctx.error
		size = world.get_default_room_size()
	if path.is_empty() or not FileAccess.file_exists(path):
		return ctx.fail("not_found", "%s isn't a scene in the project." % args.get("scene", path))
	MDSWorldSceneTools.load_fresh(path)
	return {"scene": path, "found": MDSExporters.sanitize_scene_db({path: MDSSceneScanner.new(size).analyze_scene_any(path)}).get(path, {})}

func _room_check(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var tree := Engine.get_main_loop() as SceneTree
	var host := SubViewport.new()
	host.disable_3d = true
	host.size = Vector2i(4, 4)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(host)
	var out := {}
	var skipped := []
	for id: String in args.rooms:
		if not world.has_room(id):
			host.queue_free()
			ctx.has_room(world, id)
			return ctx.error
		var path := world.get_scene_path(id)
		if path.is_empty() or not FileAccess.file_exists(path):
			skipped.append(id)
			continue
		MDSWorldSceneTools.load_fresh(path)
		var issues := MDSGeometryChecker.check_now({
			"path": path, "name": id, "rects": world.get_local_rects(id),
			"passages": MDSRoomCheck.passages_from_world(world, id), "player": world.get_setting("player", {}),
		}, host)
		out[id] = issues.map(func(i: Dictionary) -> Dictionary: return {"severity": SEVERITIES[int(i.get("severity", 0))], "category": i.get("category", ""), "message": i.get("message", ""), "pos": i.get("pos", null)})
		await tree.process_frame
	host.queue_free()
	return {"rooms": out, "no_scene": skipped}

## The map as a picture, and the sidecar that says where its grid is.
func _export_png(world: MDSWorld, args: Dictionary) -> Dictionary:
	var drawn := {}
	if args.has("path"):
		var found: Dictionary = await analyze(world)
		drawn = await ctx.host.render_map(world, int(args.get("layer", 0)), found.analysis, found.db)
	var as_panel := not drawn.is_empty()
	if not as_panel:
		drawn = MDSMcpToolsMap.draw_map(world, int(args.get("layer", 0)), int(args.get("scale", 8)))
	if drawn.has("error"):
		return ctx.fail("cant_draw", drawn.error)
	var img: Image = drawn.image
	if not args.has("path"):
		return {"format": "png", "width": img.get_width(), "height": img.get_height(), "_image": Marshalls.raw_to_base64(img.save_png_to_buffer())}
	var path := MDSMcpGuard.normalize(str(args.path))
	if path.is_empty() or path.get_extension() != "png":
		return ctx.fail("bad_arguments", "%s must be a .png path inside res://." % args.path)
	if not ctx.touch(path) or not ctx.touch(path + MDSMapImageImporter.SIDECAR_SUFFIX):
		return ctx.error
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		return ctx.fail("save_failed", "Could not write %s: %s." % [path, error_string(err)])
	MDSMapImageImporter.write_sidecar(path, drawn.cell_px, drawn.pan, world.get_paint_cell(), int(args.get("layer", 0)))
	return {"format": "png", "written": path, "drawn": "as the panel draws it" if as_panel else "plain: the map styles need the editor, with a window"}

func _export(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	if args.format == "png":
		return await _export_png(world, args)
	var found: Dictionary = await analyze(world)
	var a: MDSAnalysis = found.analysis
	var text := ""
	match args.format:
		"json":
			text = S.to_json({"world": world.data, "progression": MDSExporters.progression_to_dict(a)})
		"dot":
			text = MDSExporters.to_dot(a)
		"markdown":
			var issues := MDSWorldValidator.run(world, a, found.db)
			text = MDSExporters.to_markdown(world.get_world_name(), {"Rooms": world.get_room_ids().size(), "Areas": world.get_areas().size()}, world, a, issues)
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
