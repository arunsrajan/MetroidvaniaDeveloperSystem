@tool
class_name MDSPlayHere
extends RefCounted
## Editor side of "Play from here": picks the game scene that should host the room, writes
## a play request and runs the launcher scene, which boots that game scene in the room.
##
## No game code is needed for MetSys-style games: any scene whose root script extends
## MetSysGame, or simply has a [code]starting_map[/code] property or a
## [code]load_room(path)[/code] method, is found automatically.
## When several exist (one per level, say) the one closest to the room in the file tree
## wins. Override with the project setting [code]metroidvania_developer_system/play_scene[/code]
## (or the world's "Play scene" setting in non-linear mode).

const LAUNCHER := "res://addons/MetroidvaniaDeveloperSystem/nodes/mds_play_launcher.tscn"
const SETTING_PLAY_SCENE := "metroidvania_developer_system/play_scene"
const CACHE_SECONDS := 60.0

static var _cache: Array = []
static var _cache_time := -INF

## Starts the game in [param scene_path] with the player at [param local_pos] (room-local
## pixels). Returns a status message for the panel.
static func play(scene_path: String, room_uid: String, layer: int, local_pos: Vector2, preferred_game_scene := "") -> String:
	var game_scene := preferred_game_scene
	if game_scene.is_empty():
		game_scene = ProjectSettings.get_setting(SETTING_PLAY_SCENE, "")
	if not game_scene.is_empty() and not ResourceLoader.exists(game_scene):
		game_scene = ""
	if game_scene.is_empty():
		game_scene = pick_game_scene(scene_path)
	var err := MDSRuntime.write_play_request(scene_path, room_uid, Vector3i(0, 0, layer), local_pos, game_scene)
	if err != OK:
		return "Could not write the play request (error %d)." % err
	EditorInterface.play_custom_scene(LAUNCHER)
	if game_scene.is_empty():
		return "Playing %s on its own: no game scene (MetSysGame / starting_map) was found. Set Project Settings > %s to choose one." % [scene_path.get_file(), SETTING_PLAY_SCENE]
	return "Playing %s in %s. Change the host scene in Project Settings > %s (non-linear: World settings > Play scene)." % [scene_path.get_file(), game_scene.get_file(), SETTING_PLAY_SCENE]

## Game scene whose folder (or starting room's folder) shares the longest path with the room.
static func pick_game_scene(room_path: String) -> String:
	var best := ""
	var best_score := -1
	for candidate in find_game_scenes():
		var score := maxi(_common_dir_length(candidate.path, room_path), _common_dir_length(candidate.starting_map, room_path))
		if score > best_score:
			best_score = score
			best = candidate.path
	return best

static func _common_dir_length(a: String, b: String) -> int:
	if a.begins_with("uid://"):
		a = ResourceUID.ensure_path(a)
	var pa := a.get_base_dir().split("/")
	var pb := b.get_base_dir().split("/")
	var n := 0
	while n < mini(pa.size(), pb.size()) and pa[n] == pb[n]:
		n += 1
	return n

## Scenes that can host a room: root script extends MetSysGame, has a starting_map
## property, or implements mds_play_from(request) or load_room(path). Cached for a minute.
static func find_game_scenes() -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _cache_time < CACHE_SECONDS:
		return _cache
	_cache.clear()
	var files: PackedStringArray = []
	_collect_scenes("res://", files, 0)
	for f in files:
		var info := _root_info(f, 0)
		if info.get("is_game", false):
			_cache.append({"path": f, "starting_map": info.get("starting_map", "")})
	_cache_time = now
	return _cache

static func _collect_scenes(dir: String, out: PackedStringArray, depth: int) -> void:
	if depth > 8:
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with(".") and d != "addons" and d != MDSWorldPanel.EXPORT_DIR.get_file() and d != MDSLegacy.OLD_EXPORT_DIR.get_file():
			_collect_scenes(dir.path_join(d), out, depth + 1)

## Reads the root node of a .tscn as text (no instancing): its script, inherited scene and
## starting_map value.
static func _root_info(scene_path: String, depth: int) -> Dictionary:
	var info := {}
	if depth > 3:
		return info
	var text := FileAccess.get_file_as_string(scene_path)
	if text.is_empty():
		return info
	var ext: Dictionary = {}
	var re_ext := RegEx.create_from_string("\\[ext_resource[^\\]]*?path=\"([^\"]+)\"[^\\]]*?id=\"([^\"]+)\"")
	for m in re_ext.search_all(text):
		ext[m.get_string(2)] = m.get_string(1)
	var start := text.find("[node ")
	if start < 0:
		return info
	var end := text.find("\n[", start + 1)
	var root := text.substr(start, end - start if end > 0 else -1)
	var header := root.get_slice("\n", 0)
	if header.contains(" parent="):
		return info
	var m_map := RegEx.create_from_string("\\nstarting_map = \"([^\"]*)\"").search(root)
	if m_map:
		info.starting_map = m_map.get_string(1)
	var m_script := RegEx.create_from_string("\\nscript = ExtResource\\(\"([^\"]+)\"\\)").search(root)
	if m_script and ext.has(m_script.get_string(1)):
		info.is_game = is_game_script(ext[m_script.get_string(1)])
	if not info.get("is_game", false):
		var m_inst := RegEx.create_from_string("instance=ExtResource\\(\"([^\"]+)\"\\)").search(header)
		if m_inst and ext.has(m_inst.get_string(1)):
			var base := _root_info(ext[m_inst.get_string(1)], depth + 1)
			info.is_game = base.get("is_game", false)
			if not info.has("starting_map"):
				info.starting_map = base.get("starting_map", "")
	return info

static func is_game_script(script_path: String) -> bool:
	if not ResourceLoader.exists(script_path):
		return false
	var script := load(script_path) as Script
	while script:
		if script.resource_path.ends_with("MetSysGame.gd"):
			return true
		for p in script.get_script_property_list():
			if p.name == "starting_map":
				return true
		for m in script.get_script_method_list():
			if m.name in ["mds_play_from", MDSLegacy.OLD_PLAY_HOOK, "load_room"]:
				return true
		script = script.get_base_script()
	return false
