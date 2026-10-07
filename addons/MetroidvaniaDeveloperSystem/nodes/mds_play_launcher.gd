extends Node
## Run by the panel's "Play from here". Boots the game scene with the chosen room as its
## starting room, puts the player where you clicked, then gets out of the way.
##
## The same script runs twice: as the launcher scene (reads the request, prepares the game
## scene and switches to it) and as a small helper left on the root that places the player
## once the game has loaded the room.

## The game's own room-loading hook, and the name it had before the IDP to MDS rename.
const PLAY_HOOKS: PackedStringArray = ["mds_play_from", "idp_play_from"]

var _game: Node
var _req: Dictionary
var _mode := ""
var _hook := ""

func _ready() -> void:
	if _mode.is_empty():
		_boot.call_deferred()
	else:
		_finish.call_deferred()

func _boot() -> void:
	var req := MDSRuntime.take_play_request()
	if req.is_empty():
		push_error("Play from here: no fresh play request. Start it again from the Map Dev panel.")
		return
	MDSRuntime.active_request = req
	var room_path: String = req.scene_path
	var game_path: String = req.get("game_scene", "")
	var packed := load(game_path if not game_path.is_empty() else room_path) as PackedScene
	if not packed:
		push_error("Play from here: could not load %s" % (game_path if not game_path.is_empty() else room_path))
		return
	var game := packed.instantiate()
	var mode := "room_only"
	var hook := ""
	for h in PLAY_HOOKS:
		if hook.is_empty() and game.has_method(h):
			hook = h
	if not game_path.is_empty():
		if not hook.is_empty():
			mode = "custom"
		elif "starting_map" in game:
			# Set before the game's _ready, which loads starting_map. custom_run is the MetSys
			# template's flag for "don't let the save file move me to another room".
			game.set("starting_map", room_path)
			if "custom_run" in game:
				game.set("custom_run", true)
			mode = "starting_map"
		elif game.has_method("load_room"):
			mode = "load_room"
	print("Play from here: %s in %s" % [room_path.get_file(), game_path.get_file() if not game_path.is_empty() else "(room scene)"])
	if mode != "room_only":
		var helper := Node.new()
		helper.name = "MDSPlayFromHere"
		helper.set_script(get_script())
		helper._game = game
		helper._req = req
		helper._mode = mode
		helper._hook = hook
		get_tree().root.add_child(helper)
	# Replaces this launcher, so the game is a normal current scene during its _ready.
	get_tree().change_scene_to_node(game)

func _finish() -> void:
	if not is_instance_valid(_game):
		queue_free()
		return
	if not _game.is_node_ready():
		await _game.ready
	match _mode:
		"custom":
			await _game.call(_hook, _req)
		"starting_map":
			# MetSysGame loads its first room during _ready; wait if it's still changing.
			if _game.get("map_changing") and _game.has_signal("room_loaded"):
				await _game.room_loaded
			await get_tree().process_frame
			_place_player()
		"load_room":
			await _game.load_room(_req.scene_path)
			_place_player()
	queue_free()

## Places the player at the requested room-local spot. The loaded room's own transform is
## used, so it works whether the game puts rooms at the origin (MetSys) or at their world
## position (non-linear/streaming games).
func _place_player() -> void:
	var player = _game.get("player")
	if not player is Node2D:
		player = get_tree().get_first_node_in_group(&"player")
	if not player is Node2D:
		player = _game.find_child("Player", true, false)
	if not player is Node2D:
		return
	var room := _find_room_node(get_tree().root, _req.scene_path)
	if room is Node2D:
		player.global_position = (room as Node2D).global_transform * _req.position
	else:
		player.global_position = _req.position
	if "velocity" in player:
		player.velocity = Vector2.ZERO

func _find_room_node(node: Node, scene_path: String) -> Node:
	if node.scene_file_path == scene_path:
		return node
	for child in node.get_children():
		var found := _find_room_node(child, scene_path)
		if found:
			return found
	return null
