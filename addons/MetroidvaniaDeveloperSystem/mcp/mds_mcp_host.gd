@tool
class_name MDSMcpHost
extends RefCounted
## Where the tools run. This base is the headless host: every call loads files fresh and writes
## them back. [MDSMcpEditorHost] goes through the open editor instead.

## "headless" or "editor".
func mode() -> String:
	return "headless"

## The world at [param path]: never a cached one, since this process outlives other writers.
func open_world(path: String) -> MDSWorld:
	return MDSWorld.load_world(path)

## The world file open in the editor, or "".
func open_world_path() -> String:
	return ""

## Called once per step before a tool first edits [param world].
func world_will_change(_world: MDSWorld) -> void:
	pass

## Writes [param world] to its file through a temporary file, so a process killed halfway leaves
## the old file whole.
func save_world(world: MDSWorld) -> Error:
	return write_world_file(world)

static func write_world_file(world: MDSWorld) -> Error:
	DirAccess.make_dir_recursive_absolute(world.path.get_base_dir())
	var temp := world.path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if not f:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(world.data, "\t", true))
	f.close()
	return DirAccess.rename_absolute(temp, world.path)

## Why the room scene [param path] can't be written now, or "" (see [method unsaved_scenes]).
## [param save_first]: unsaved changes may be saved rather than refused.
func room_write_problem(_path: String, _save_first: bool) -> String:
	return ""

## Before room scenes are written: lets go of anything holding them.
func rooms_will_change() -> void:
	pass

## After scene [param path] was written.
func room_written(_path: String) -> void:
	pass

## After a tool's room writes: gets back what [method rooms_will_change] let go of.
func rooms_changed() -> void:
	pass

## After files were put back (undo, or a failed step).
func files_restored(_paths: Array) -> void:
	pass

## Scenes with changes not saved yet.
func unsaved_scenes() -> PackedStringArray:
	return PackedStringArray()

## Saves [param paths] among the scenes open, or all of them when empty. Returns those saved.
func save_scenes(_paths: Array) -> PackedStringArray:
	return PackedStringArray()

## Shows [param world] (and [param room]) in the panel. Returns why not, or "".
func show_in_editor(_world: String, _room: String) -> String:
	return "This needs the editor."
