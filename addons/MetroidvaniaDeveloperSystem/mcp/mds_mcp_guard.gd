@tool
class_name MDSMcpGuard
extends RefCounted
## What an agent may touch: permission tiers, path rules, the write lock between processes and
## the audit log. The tools' annotations are only hints to the client; this enforces the rules.

enum Tier { READ, AUTHOR, FULL }

const TIER_NAMES: PackedStringArray = ["read", "author", "full"]
## Where the server keeps its files: under .godot, never committed.
const DATA_DIR := "res://.godot/mds_mcp"
## Nothing writes under these, nor to [constant PROJECT_FILE] (see [member allow_project_file]).
const NO_WRITE: PackedStringArray = ["res://addons/", "res://.godot/", "res://.git/", "res://.github/"]
const PROJECT_FILE := "res://project.godot"
const AUDIT_MAX_BYTES := 1024 * 1024

var tier: Tier = Tier.AUTHOR
var data_dir := DATA_DIR
## How long a tool waits for another process's write to finish.
var lock_wait_msec := 5000
var lock_stale_sec := 60
## Set while a tool that may write project.godot runs.
var allow_project_file := false

func _init(p_tier: Tier = Tier.AUTHOR, p_data_dir := DATA_DIR) -> void:
	tier = p_tier
	data_dir = p_data_dir

static func tier_from_name(tier_name: String, default: Tier = Tier.AUTHOR) -> Tier:
	var i := TIER_NAMES.find(tier_name)
	return i as Tier if i >= 0 else default

## [param path] normalized if it stays inside res://, or "".
static func normalize(path: String) -> String:
	var p := path.replace("\\", "/").strip_edges()
	if not p.begins_with("res://"):
		return ""
	for part in p.trim_prefix("res://").split("/"):
		if part == "..":
			return ""
	return "res://" + p.trim_prefix("res://").simplify_path().trim_prefix("./")

## Why [param path] can't be read, or "".
func read_problem(path: String) -> String:
	return "%s is not a path inside res://" % path if normalize(path).is_empty() else ""

## Why [param path] can't be written, or "".
func write_problem(path: String) -> String:
	var p := normalize(path)
	if p.is_empty():
		return "%s is not a path inside res://" % path
	if p == PROJECT_FILE:
		return "" if allow_project_file else "project.godot can only be changed by mds_gameplay_setup"
	for no in NO_WRITE:
		if p.begins_with(no):
			return "%s is under %s, which the server doesn't write" % [path, no]
	return ""

# --- Lock ------------------------------------------------------------------------------------

func _lock_path() -> String:
	return data_dir.path_join("lock")

## Takes the write lock, waiting for another process to let go. A lock not renewed for
## [member lock_stale_sec] was left by one that was killed: [method OS.is_process_running] can't
## tell, it only knows a process's own children. Returns whether it got the lock.
func acquire_lock() -> bool:
	DirAccess.make_dir_recursive_absolute(data_dir)
	var until := Time.get_ticks_msec() + lock_wait_msec
	var tree := Engine.get_main_loop() as SceneTree
	while FileAccess.file_exists(_lock_path()):
		var holder := FileAccess.get_file_as_string(_lock_path()).to_int()
		var age := Time.get_unix_time_from_system() - FileAccess.get_modified_time(_lock_path())
		if holder <= 0 or holder == OS.get_process_id() or age > lock_stale_sec:
			break
		if Time.get_ticks_msec() > until:
			return false
		await tree.create_timer(0.05, true, false, true).timeout
	return renew_lock()

## Writes the lock again: long tools call this as they go. Returns whether it could.
func renew_lock() -> bool:
	var f := FileAccess.open(_lock_path(), FileAccess.WRITE)
	if not f:
		return false
	f.store_string(str(OS.get_process_id()))
	f.close()
	return true

func release_lock() -> void:
	DirAccess.remove_absolute(_lock_path())

# --- Audit -----------------------------------------------------------------------------------

## Adds a line to the audit log: when, who, which tool, what changed.
func audit(tool_name: String, client: String, ok: bool, changed: Array) -> void:
	DirAccess.make_dir_recursive_absolute(data_dir)
	var path := data_dir.path_join("audit.log")
	if FileAccess.file_exists(path) and FileAccess.open(path, FileAccess.READ).get_length() > AUDIT_MAX_BYTES:
		DirAccess.rename_absolute(path, path + ".1")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if not f:
		return
	f.seek_end()
	f.store_line(MDSMcpSchema.to_json({"time": Time.get_datetime_string_from_system(), "client": client, "tool": tool_name, "ok": ok, "changed": changed}))
	f.close()

## The last [param limit] audit lines, newest first.
func recent_audit(limit := 50) -> Array:
	var path := data_dir.path_join("audit.log")
	if not FileAccess.file_exists(path):
		return []
	var out := []
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	for i in range(lines.size() - 1, maxi(-1, lines.size() - 1 - limit), -1):
		var parsed: Variant = JSON.parse_string(lines[i])
		if parsed != null:
			out.append(MDSMcpSchema.clean(parsed))
	return out
