@tool
class_name MDSMcpEndpoint
extends RefCounted
## How the stdio process finds an open editor: the plugin keeps a small file under .godot with its
## process id and, when MCP is on, the port and token of its HTTP server. It is written again every
## few seconds, since [method OS.is_process_running] only knows a process's own children: a file
## not written for [constant STALE_SEC] is what an editor that crashed leaves.

const FILE := MDSMcpGuard.DATA_DIR + "/endpoint.json"
const REFRESH_SEC := 3.0
const STALE_SEC := 10

## Says this editor is running: [param port] 0 means MCP is turned off in it.
static func write(port: int, token: String, file := FILE) -> void:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f:
		f.store_string(MDSMcpSchema.to_json({"pid": OS.get_process_id(), "port": port, "token": token}))
		f.close()

static func remove(file := FILE) -> void:
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(file)

## The running editor's {pid, port, token}, or {} when none is running.
static func read_live(file := FILE) -> Dictionary:
	if not FileAccess.file_exists(file):
		return {}
	if Time.get_unix_time_from_system() - FileAccess.get_modified_time(file) > STALE_SEC:
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not parsed is Dictionary:
		return {}
	return {"pid": int(parsed.get("pid", 0)), "port": int(parsed.get("port", 0)), "token": str(parsed.get("token", ""))}
