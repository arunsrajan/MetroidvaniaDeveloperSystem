@tool
class_name MDSMcpHistory
extends RefCounted
## Undo that works with or without the editor: before a tool changes a file its bytes are copied
## to [code]<data dir>/history/<step>/[/code]. Undoing puts them back, but only while the files
## are as the step left them: a file changed since is not overwritten.

const MAX_STEPS := 50

var dir := ""
var _files: Dictionary = {} ## path being changed -> copy name, or "" when it didn't exist
var _tool := ""
var _open := false

func _init(data_dir: String) -> void:
	dir = data_dir.path_join("history")

func begin(tool_name: String) -> void:
	_files.clear()
	_tool = tool_name
	_open = true

## Remembers [param path] as it is now, the first time it is touched in this step.
func touch(path: String) -> void:
	if not _open or _files.has(path):
		return
	if FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(_pending())
		var copy := "%d.bin" % _files.size()
		_write(_pending().path_join(copy), FileAccess.get_file_as_bytes(path))
		_files[path] = copy
	else:
		_files[path] = ""

func touched() -> Array:
	return _files.keys()

## Ends the step. Returns its id, or 0 when no file changed.
func commit() -> int:
	_open = false
	var entries := []
	for path: String in _files:
		var was: String = _files[path]
		var now_there := FileAccess.file_exists(path)
		if not now_there and was.is_empty():
			continue
		var after := FileAccess.get_sha256(path) if now_there else ""
		if not was.is_empty() and after == FileAccess.get_sha256(_pending().path_join(was)):
			continue
		entries.append({"path": path, "copy": was, "after": after})
	if entries.is_empty():
		_remove(_pending())
		return 0
	var id := _last_id() + 1
	DirAccess.make_dir_recursive_absolute(_pending())
	_write(_pending().path_join("step.json"), MDSMcpSchema.to_json({"id": id, "tool": _tool, "time": Time.get_datetime_string_from_system(), "files": entries}).to_utf8_buffer())
	DirAccess.rename_absolute(_pending(), dir.path_join(str(id)))
	_prune(id)
	return id

## Ends the step, putting every touched file back. Returns their paths.
func rollback() -> Array:
	_open = false
	var out := []
	for path: String in _files:
		var was: String = _files[path]
		if was.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
				out.append(path)
		elif FileAccess.get_sha256(path) != FileAccess.get_sha256(_pending().path_join(was)):
			_write(path, FileAccess.get_file_as_bytes(_pending().path_join(was)))
			out.append(path)
	_remove(_pending())
	return out

## The steps that can be undone, newest first: {id, tool, time, files}.
func steps(limit := MAX_STEPS) -> Array:
	var out := []
	var ids := _ids()
	ids.reverse()
	for id in ids.slice(0, limit):
		var step := _read_step(id)
		if not step.is_empty():
			out.append({"id": id, "tool": step.get("tool", ""), "time": step.get("time", ""), "files": step.files.map(func(f: Dictionary) -> String: return f.path)})
	return out

## Undoes step [param id] (0: the newest). Returns {files: paths restored} or {error: why,
## conflicts: paths changed since}.
func undo(id := 0) -> Dictionary:
	var ids := _ids()
	if ids.is_empty():
		return {"error": "There is nothing to undo."}
	if id == 0:
		id = ids[-1]
	if id != ids[-1]:
		return {"error": "Only the newest step (%d) can be undone next." % ids[-1]}
	var step := _read_step(id)
	if step.is_empty():
		return {"error": "Step %d can't be read." % id}
	var conflicts := []
	for f: Dictionary in step.files:
		var now := FileAccess.get_sha256(f.path) if FileAccess.file_exists(f.path) else ""
		if now != f.after:
			conflicts.append(f.path)
	if not conflicts.is_empty():
		return {"error": "These files changed after the step, so it wasn't undone.", "conflicts": conflicts}
	var restored := []
	var folder := dir.path_join(str(id))
	for f: Dictionary in step.files:
		if str(f.copy).is_empty():
			DirAccess.remove_absolute(f.path)
		else:
			_write(f.path, FileAccess.get_file_as_bytes(folder.path_join(f.copy)))
		restored.append(f.path)
	_remove(folder)
	return {"files": restored}

func _pending() -> String:
	return dir.path_join("pending")

func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()

func _read_step(id: int) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(str(id)).path_join("step.json")))
	return parsed if parsed is Dictionary else {}

func _ids() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for d in DirAccess.get_directories_at(dir):
		if d.is_valid_int():
			out.append(d.to_int())
	out.sort()
	return out

func _last_id() -> int:
	var ids := _ids()
	return ids[-1] if not ids.is_empty() else 0

func _prune(newest: int) -> void:
	for id in _ids():
		if id <= newest - MAX_STEPS:
			_remove(dir.path_join(str(id)))

func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(f))
	DirAccess.remove_absolute(folder)
