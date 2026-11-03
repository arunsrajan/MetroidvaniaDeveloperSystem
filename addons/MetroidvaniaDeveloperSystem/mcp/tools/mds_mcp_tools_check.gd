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
	_add("mds_analysis", "progression: what is reached with which ability, and what never is. backtracking: rooms by save distance, dead ends, hubs. path: the route from one room to another. ability_uses: where an ability is needed and found (ability). objectives: the world's goals.", READ,
		{"world": world, "kind": S.choice(["progression", "backtracking", "path", "ability_uses", "objectives"]), "from": S.text(), "to": S.text(), "ability": S.text()}, ["kind"], _analysis)
	_add("mds_room_check", "Plays rooms in simulation: gates passable, platforms landable, climbs reachable with the world's player settings.", READ,
		{"world": world, "rooms": S.array(S.text(), "", CHECK_ROOMS_MAX)}, ["rooms"], _room_check)
	_add("mds_export", "The world's progression and design as json, a dot graph, or a markdown document. Returns it, or writes it to path.", AUTHOR,
		{"world": world, "format": S.choice(["json", "dot", "markdown"]), "path": S.text("Writes it there")}, ["format"], _export)

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
	return {"objectives": a.get_objectives()}

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

func _export(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
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
