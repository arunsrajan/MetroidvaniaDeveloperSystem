@tool
class_name MDSMcpContext
extends RefCounted
## What a tool works through: the host, the guard, and the current step (one tool call or one
## batch): the files it changes are remembered so it can be undone, or put back if it fails.

var host: MDSMcpHost
var guard: MDSMcpGuard
var history: MDSMcpHistory
## Why the last call returning null or false failed: an error result for the tool to return.
var error: Dictionary = {}

var _depth := 0
var _worlds_changing: Dictionary = {} ## world path -> true, told to the host in this step
var _rooms_released := false

func _init(p_host: MDSMcpHost, p_guard: MDSMcpGuard) -> void:
	host = p_host
	guard = p_guard
	history = MDSMcpHistory.new(p_guard.data_dir)

## An error result for a tool to return: code, what happened, and what to do about it.
static func fail(code: String, message: String, hint := "", details: Dictionary = {}) -> Dictionary:
	var e := {"code": code, "message": message}
	if not hint.is_empty():
		e.hint = hint
	if not details.is_empty():
		e.details = details
	return {"_error": e}

static func is_failure(result: Variant) -> bool:
	return result is Dictionary and result.has("_error")

## Starts a step (nested calls join it). Returns a failure, or {}.
func begin(tool_name: String) -> Dictionary:
	if _depth == 0:
		var live := MDSMcpEndpoint.read_live(guard.data_dir.path_join("endpoint.json"))
		if host.mode() == "headless" and not live.is_empty() and int(live.pid) != OS.get_process_id():
			return fail("editor_open_mcp_off", "The editor has this project open with MCP turned off, so writing here could lose work there.", "Turn MCP on in the MetDevSys panel (Settings), or close the editor.")
		if not await guard.acquire_lock():
			return fail("project_busy", "Another process is writing to this project.", "Try again in a moment.")
		history.begin(tool_name)
		_worlds_changing.clear()
		_rooms_released = false
	_depth += 1
	return {}

## Ends the step. On success returns {changed, undo_id}; otherwise puts its files back.
func finish(ok: bool) -> Dictionary:
	_depth -= 1
	if _depth > 0:
		return {}
	var out := {}
	if ok:
		var changed := history.touched()
		var id := history.commit()
		out = {"changed": changed.filter(func(p: String) -> bool: return FileAccess.file_exists(p)), "undo_id": id}
	else:
		var restored := history.rollback()
		if not restored.is_empty():
			host.files_restored(restored)
	if _rooms_released:
		_rooms_released = false
		host.rooms_changed()
	guard.release_lock()
	return out

## Remembers [param path] before a write. Returns false (see [member error]) if it can't be
## written.
func touch(path: String) -> bool:
	var problem := guard.write_problem(path)
	if not problem.is_empty():
		error = fail("path_not_allowed", problem)
		return false
	history.touch(MDSMcpGuard.normalize(path))
	guard.renew_lock()
	return true

# --- Worlds ----------------------------------------------------------------------------------

## Every world file in the project, except under addons and hidden folders.
static func find_worlds(folder := "res://") -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(folder):
		if MDSWorld.is_world_file(f):
			out.append(folder.path_join(f))
	for d in DirAccess.get_directories_at(folder):
		if not d.begins_with(".") and d != "addons" and d != "tests":
			out.append_array(find_worlds(folder.path_join(d)))
	out.sort()
	return out

## The path [param args] names: its "world", else the one open in the editor, else the project's
## only world. "" (see [member error]) when that doesn't settle it.
func world_path(args: Dictionary) -> String:
	if args.has("world"):
		var p := MDSMcpGuard.normalize(str(args.world))
		if p.is_empty() or not MDSWorld.is_world_file(p):
			error = fail("bad_world", "%s is not a world file inside res:// (*%s)." % [args.world, MDSWorld.EXTENSION])
			return ""
		if not FileAccess.file_exists(p):
			error = fail("world_not_found", "%s doesn't exist." % p, "mds_world_list lists the worlds.")
			return ""
		return p
	var open := host.open_world_path()
	if not open.is_empty():
		return open
	var worlds := find_worlds()
	if worlds.size() == 1:
		return worlds[0]
	error = fail("world_needed", "No world given and %d in the project." % worlds.size(), "Pass world: one of %s." % ", ".join(PackedStringArray(worlds)) if not worlds.is_empty() else "Make one with mds_world_create.")
	return ""

## The world [param args] names, to read. Null: see [member error].
func read_world(args: Dictionary) -> MDSWorld:
	var p := world_path(args)
	return host.open_world(p) if not p.is_empty() else null

## The world [param args] names, to change. Null: see [member error].
func edit_world(args: Dictionary) -> MDSWorld:
	var p := world_path(args)
	if p.is_empty() or not touch(p):
		return null
	var world := host.open_world(p)
	if not _worlds_changing.has(p):
		_worlds_changing[p] = true
		host.world_will_change(world)
	return world

## Saves a world changed through [method edit_world]. Returns a failure, or {}.
func save_world(world: MDSWorld) -> Dictionary:
	var err := host.save_world(world)
	return {} if err == OK else fail("save_failed", "Could not save %s: %s." % [world.path, error_string(err)])

## A room of [param world], or null (see [member error]).
func has_room(world: MDSWorld, id: String) -> bool:
	if world.has_room(id):
		return true
	error = fail("room_not_found", "%s has no room %s." % [world.path, id], "Rooms: %s" % ", ".join(PackedStringArray(world.get_room_ids().slice(0, 40))))
	return false

# --- Room scenes -----------------------------------------------------------------------------

## Gets ready to write room scene [param path]: checks the editor isn't holding unsaved changes,
## and remembers the file. Returns false (see [member error]) if it can't be.
func prepare_room_write(path: String, args: Dictionary) -> bool:
	var problem := host.room_write_problem(path, str(args.get("on_unsaved", "refuse")) == "save_first")
	if not problem.is_empty():
		error = fail("scene_has_unsaved_changes", problem, "Ask the user, then retry with on_unsaved: \"save_first\", or have them save.", {"unsaved": host.unsaved_scenes()})
		return false
	if not touch(path):
		return false
	if not _rooms_released:
		_rooms_released = true
		host.rooms_will_change()
	return true

## The tileset rooms of [param world] paint with, made if it isn't there yet.
func room_tiles(world: MDSWorld) -> TileSet:
	var p := str(world.get_setting("room_tileset", ""))
	if p.is_empty():
		p = world.path.get_base_dir().path_join("tiles/%s_tileset.tres" % MDSWorldSceneTools.file_stem(world))
		world.set_setting("room_tileset", p)
	if not FileAccess.file_exists(p):
		if not touch(p):
			return null
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	return MDSTilesetFactory.get_or_create(p)
