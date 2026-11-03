@tool
class_name MDSMcpEditorHost
extends MDSMcpHost
## The tools' host with the editor open: the world open in the panel is edited live (one undo step
## per tool call or batch, so Ctrl+Z on the map takes it back), and scenes the editor holds with
## unsaved changes are not written over.

## Returns the [MDSWorldPanel], or null while the panel shows MetSys mode.
var _panel_getter: Callable

func _init(panel_getter: Callable) -> void:
	_panel_getter = panel_getter

func _panel() -> MDSWorldPanel:
	var p: Variant = _panel_getter.call()
	return p if is_instance_valid(p) else null

func mode() -> String:
	return "editor"

func open_world(path: String) -> MDSWorld:
	var p := _panel()
	if p and p.world and p.world_path == path:
		return p.world
	return super(path)

func open_world_path() -> String:
	var p := _panel()
	return p.world_path if p and p.world else ""

func world_will_change(world: MDSWorld) -> void:
	var p := _panel()
	if p and p.world == world:
		world.checkpoint()

func save_world(world: MDSWorld) -> Error:
	var p := _panel()
	if p and p.world == world:
		return p.mcp_save_world()
	return super(world)

func room_write_problem(path: String, save_first: bool) -> String:
	var unsaved := unsaved_scenes()
	var held := path in unsaved
	var p := _panel()
	var in_room_view: bool = p != null and p.room_view.has_unsaved()
	if not held and not in_room_view:
		return ""
	if not save_first:
		return "%s has changes in the editor that aren't saved." % (path if held else "The Room view")
	if in_room_view:
		p.room_view.save()
	if held:
		save_scenes([path])
	return ""

func rooms_will_change() -> void:
	var p := _panel()
	if p:
		p.mcp_release_rooms()

func room_written(path: String) -> void:
	var p := _panel()
	if p:
		p.mcp_room_written(path)
	else:
		EditorInterface.get_resource_filesystem().update_file(path)
		if path in EditorInterface.get_open_scenes():
			EditorInterface.reload_scene_from_path(path)

func rooms_changed() -> void:
	var p := _panel()
	if p:
		p.mcp_restore_rooms()

func files_restored(paths: Array) -> void:
	var p := _panel()
	for path: String in paths:
		if p and p.world and path == p.world_path:
			p.mcp_reload_world()
		elif path.get_extension() in ["tscn", "scn"]:
			if FileAccess.file_exists(path):
				MDSWorldSceneTools.load_fresh(path)
			room_written(path)
		else:
			EditorInterface.get_resource_filesystem().update_file(path)

func unsaved_scenes() -> PackedStringArray:
	# 4.7 can say which. In 4.6 only the current tab could be looked at, and a fingerprint of it
	# misses painted tiles, so every open scene counts: stricter, but no work is lost.
	if EditorInterface.has_method(&"get_unsaved_scenes"):
		return PackedStringArray(Array(EditorInterface.call(&"get_unsaved_scenes")).filter(func(s: String) -> bool: return not s.is_empty()))
	return EditorInterface.get_open_scenes()

func save_scenes(paths: Array) -> PackedStringArray:
	var open := EditorInterface.get_open_scenes()
	var wanted := PackedStringArray()
	for path in open:
		if paths.is_empty() or path in paths:
			wanted.append(path)
	if wanted.size() == open.size():
		EditorInterface.save_all_scenes()
		return wanted
	var current := EditorInterface.get_edited_scene_root()
	var back := current.scene_file_path if current else ""
	for path in wanted:
		EditorInterface.open_scene_from_path(path)
		EditorInterface.save_scene()
	if not back.is_empty():
		EditorInterface.open_scene_from_path(back)
	return wanted

func show_in_editor(world: String, room: String) -> String:
	var p := _panel()
	if not p:
		return "The panel isn't showing world mode (MetSys mode is on)."
	if p.world_path != world:
		p.load_world(world)
	if not room.is_empty():
		if not p.world.has_room(room):
			return "%s has no room %s." % [world, room]
		p.show_room_view(room)
	return ""
