@tool
class_name MDSMcpToolsCore
extends MDSMcpTools
## Status, the catalog of ids, batches, undo, and the tools that only the editor can do.

const TEMPLATES_DIR := "res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/"
const CATALOGS: Array = ["cave_styles", "cave_shapes", "attack_fx", "hit_particles", "damage_types", "effects", "enemy_templates", "tile_palettes", "stamp_sets"]

func _register() -> void:
	_add("mds_status", "Where the server stands: mode (editor or headless), versions, permission tier, worlds in the project, what the editor has open and unsaved.", READ, {}, [], _status)
	_add("mds_catalog", "The valid ids of a kind, with names: cave styles and shapes, attack effects, hit particles, damage types, environment effects, enemy templates, tile palettes, stamp sets.", READ,
		{"kind": S.choice(CATALOGS)}, ["kind"], _catalog)
	_add("mds_batch", "Runs several tools in order as one undo step. By default, if one fails the files go back as they were and the rest don't run.", AUTHOR,
		{
			"ops": S.array(S.object({"tool": S.text("Tool name"), "args": S.any_object("Its arguments")}, ["tool"]), "The calls, in order", MDSMcpProtocol.MAX_BATCH_OPS),
			"atomic": S.boolean("Default true. False keeps the calls before a failure."),
		}, ["ops"], _batch)
	_add("mds_history", "The recent changes that can be undone, newest first.", READ, {"limit": S.integer("Default 20", 1, MDSMcpHistory.MAX_STEPS)}, [], _history)
	_add("mds_undo", "Undoes the newest change made through this server, if its files haven't been changed since.", AUTHOR, {"undo_id": S.integer("The newest step's id; left out means the newest.")}, [], _undo, {"writes": false})
	_add("mds_editor_open", "Shows a world, and optionally a room, in the MetDevSys panel. Editor only.", AUTHOR, {"world": _world_schema(), "room": S.text("Room id")}, [], _editor_open, {"editor_only": true, "writes": false})
	_add("mds_editor_save_scenes", "Saves scenes open in the editor. They may hold the user's unfinished work: ask first. Editor only.", AUTHOR, {"paths": S.array(S.text(), "Scene paths; left out or empty: all open scenes")}, [], _editor_save, {"editor_only": true, "writes": false})

func _status(_args: Dictionary, _report: Callable) -> Dictionary:
	var worlds := MDSMcpContext.find_worlds()
	return {
		"server_version": MDSMcpProtocol.server_version(),
		"godot_version": Engine.get_version_info().string,
		"mode": ctx.host.mode(),
		"tier": MDSMcpGuard.TIER_NAMES[ctx.guard.tier],
		"worlds": worlds,
		"open_world": ctx.host.open_world_path(),
		"unsaved_scenes": ctx.host.unsaved_scenes(),
	}

func _catalog(args: Dictionary, _report: Callable) -> Dictionary:
	var items: Array = []
	match str(args.kind):
		"cave_styles":
			for s: Array in MDSCaveShapes.STYLES:
				items.append({"id": s[0], "name": s[1]})
		"cave_shapes":
			for s: Array in MDSCaveShapes.CHOICES:
				items.append({"id": s[0], "name": s[1]})
		"attack_fx":
			for id: String in MDSAttackFX.EFFECTS:
				var e: Array = MDSAttackFX.EFFECTS[id]
				items.append({"id": id, "kind": e[0], "description": e[4]})
		"hit_particles":
			for id in MDSHitParticles.KINDS.split(","):
				items.append({"id": id})
		"damage_types":
			for id in MDSDamageInfo.TYPES.split(","):
				items.append({"id": id})
		"effects":
			for id in MDSEnvironment.effect_ids():
				items.append({"id": id, "name": MDSEnvironment.display_name(id)})
			for id in MDSEnvironment.preset_ids():
				items.append({"id": id, "name": MDSEnvironment.display_name(id), "preset": true})
		"enemy_templates":
			for f in DirAccess.get_files_at(TEMPLATES_DIR):
				if f.ends_with(".tscn"):
					items.append({"id": f.get_basename().trim_prefix("mds_"), "scene": TEMPLATES_DIR + f})
		"tile_palettes":
			for id: String in MDSTilesetFactory.PALETTES:
				items.append({"id": id})
		"stamp_sets":
			for p in _find_files("res://", ".stamps.tres"):
				items.append({"id": p})
	return {"kind": args.kind, "items": items}

static func _find_files(folder: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(folder):
		if f.ends_with(suffix):
			out.append(folder.path_join(f))
	for d in DirAccess.get_directories_at(folder):
		if not d.begins_with(".") and d != "addons" and d != "tests":
			out.append_array(_find_files(folder.path_join(d), suffix))
	return out

func _batch(args: Dictionary, report: Callable) -> Dictionary:
	var atomic: bool = args.get("atomic", true)
	var results := []
	var ops: Array = args.ops
	for i in ops.size():
		var op: Dictionary = ops[i]
		var tool_name := str(op.tool)
		if tool_name == "mds_batch" or tool_name == "mds_undo":
			return ctx.fail("bad_batch", "%s can't be used inside a batch." % tool_name, "", {"failed_op": i})
		var result: Dictionary = await protocol_ref.get_ref().call_tool(tool_name, op.get("args", {}))
		if ctx.is_failure(result):
			result._error.details = result._error.get("details", {})
			result._error.details.failed_op = i
			if atomic:
				return result
			return {"results": results, "stopped_at": i, "error": result._error}
		results.append(result)
		if report.is_valid():
			report.call(i + 1, ops.size(), tool_name)
		await (Engine.get_main_loop() as SceneTree).process_frame
	return {"results": results}

func _history(args: Dictionary, _report: Callable) -> Dictionary:
	return {"steps": ctx.history.steps(int(args.get("limit", 20)))}

func _undo(args: Dictionary, _report: Callable) -> Dictionary:
	var refused: Dictionary = await ctx.begin("mds_undo")
	if not refused.is_empty():
		return refused
	var r := ctx.history.undo(int(args.get("undo_id", 0)))
	ctx.history.begin("")
	ctx.finish(true)
	if r.has("error"):
		return ctx.fail("undo_refused", r.error, "", {"conflicts": r.get("conflicts", [])})
	ctx.host.files_restored(r.files)
	return {"restored": r.files}

func _editor_open(args: Dictionary, _report: Callable) -> Dictionary:
	var path := ctx.world_path(args)
	if path.is_empty():
		return ctx.error
	var why := ctx.host.show_in_editor(path, str(args.get("room", "")))
	return ctx.fail("not_shown", why) if not why.is_empty() else {"shown": path}

func _editor_save(args: Dictionary, _report: Callable) -> Dictionary:
	return {"saved": ctx.host.save_scenes(args.get("paths", []))}
