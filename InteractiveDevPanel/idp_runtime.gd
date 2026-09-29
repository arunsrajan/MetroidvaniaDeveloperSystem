class_name IDPRuntime
extends RefCounted
## Runtime side of the panel's "Play from here" action.
##
## The editor writes a request file and runs the launcher scene
## ([code]nodes/idp_play_launcher.tscn[/code]), which boots your game scene in the chosen
## room: it sets [code]starting_map[/code] (and [code]custom_run[/code], if present) before
## the game's [code]_ready[/code], then places the player. MetSys-style games need no code.
## During such a run [member active_request] holds the request, so a game can skip intros.
##
## Games with their own room loading can implement [code]idp_play_from(request)[/code] on
## the game scene's root instead; the launcher then calls it and does nothing else.
## Custom setups can also read the request themselves, as before:
## [codeblock]
## # In your MetSysGame-derived game script:
## func _ready() -> void:
##     var request := IDPRuntime.take_play_request()
##     if request.is_empty():
##         await load_room(starting_map)
##     else:
##         await load_room(request.scene_path)
##         player.position = request.position
## [/codeblock]
## Requests expire after [constant MAX_AGE_SECONDS], so a normal run is never affected.

const REQUEST_PATH := "user://idp_play_request.json"
const MAX_AGE_SECONDS := 120

## The request being played by the launcher, or empty in normal runs.
static var active_request: Dictionary = {}

## Written by the editor panel.
static func write_play_request(scene_path: String, room_uid: String, cell: Vector3i, position: Vector2, game_scene := "") -> Error:
	var file := FileAccess.open(REQUEST_PATH, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"scene_path": scene_path,
		"room_uid": room_uid,
		"cell": [cell.x, cell.y, cell.z],
		"position": [position.x, position.y],
		"game_scene": game_scene,
		"time": Time.get_unix_time_from_system(),
	}))
	return OK

static func has_play_request() -> bool:
	return FileAccess.file_exists(REQUEST_PATH)

## Returns {scene_path, room_uid, cell: Vector3i, layer, position: Vector2, game_scene} and deletes the
## request, or an empty Dictionary when there is no fresh request.
static func take_play_request() -> Dictionary:
	if not FileAccess.file_exists(REQUEST_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REQUEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST_PATH))
	if not parsed is Dictionary:
		return {}
	if Time.get_unix_time_from_system() - float(parsed.get("time", 0)) > MAX_AGE_SECONDS:
		return {}
	var c: Array = parsed.get("cell", [0, 0, 0])
	var p: Array = parsed.get("position", [0, 0])
	var scene_path: String = parsed.get("scene_path", "")
	# Prefer the uid: it survives the scene being moved since the request was written.
	var uid: String = parsed.get("room_uid", "")
	if uid.begins_with("uid://") and ResourceUID.has_id(ResourceUID.text_to_id(uid)):
		scene_path = ResourceUID.get_id_path(ResourceUID.text_to_id(uid))
	return {
		"scene_path": scene_path,
		"room_uid": uid,
		"cell": Vector3i(int(c[0]), int(c[1]), int(c[2])),
		"layer": int(c[2]),
		"position": Vector2(float(p[0]), float(p[1])),
		"game_scene": parsed.get("game_scene", ""),
	}
