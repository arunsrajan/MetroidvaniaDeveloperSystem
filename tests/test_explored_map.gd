extends "res://tests/test_case.gd"
## Explored rooms on the maps. The game's map (MDSWorldMapView) puts a check mark on each room
## explored and a pin where the player is. The exploration file says whose world it is and where
## the player is, written as each room is entered. The editor's World map reads the last
## playtest's file (MDSWorldGame.read_exploration: the world's own, else one from before files
## said whose they are, named after the world, else the default one) and shows it: Show on map >
## Explored in the last playtest.
##
## The world: Hall_01 (start) | Well_01 | Shrine_01, side by side.

const DIR := TMP + "/explored_map"
const WORLD := DIR + "/explore.mdsworld.json"
const EXPLORED := DIR + "/explore_exploration.json"
const PLAYER := "extends CharacterBody2D\n"

var world: MDSWorld

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	world = MDSWorld.new()
	world.path = WORLD
	world.data.name = "Explore"
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	var room := world.get_default_room_size()
	var ids := ["Hall_01", "Well_01", "Shrine_01"]
	for i in ids.size():
		world.add_room(ids[i], Rect2(Vector2(i * room.x, 0), room), 0)
		MDSWorldSceneTools.create_scene_for_room(world, ids[i], DIR + "/%s.tscn" % ids[i].to_snake_case())
	world.set_start_room("Hall_01")
	world.save()
	await _playing()
	_reading()
	await _editor_map()

func _playing() -> void:
	var game := MDSWorldGame.new()
	game.world_file = WORLD
	game.starting_room = "Hall_01"
	game.fade_time = 0.0
	game.gate_cooldown = 0.0
	game.save_file = DIR + "/save.json"
	game.exploration_file = EXPLORED
	var s := GDScript.new()
	s.source_code = PLAYER
	s.reload()
	var player: CharacterBody2D = s.new()
	player.name = "Player"
	player.add_to_group(&"player", true)
	game.add_child(player)
	game.player = player
	var map := MDSWorldMapView.new()
	map.world_file = WORLD
	map.size = Vector2(320, 200)
	game.add_child(map)
	game.map_view = map
	add_child(game)
	await game.room_loaded
	game.load_room("Well_01")
	await game.room_loaded
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPLORED))
	check(str(data.get("world", "")) == WORLD, "the exploration file says whose world it is")
	check(data.visited.has("Hall_01") and data.visited.has("Well_01") and not data.visited.has("Shrine_01"), "it keeps the rooms explored")
	var at := player.global_position - game.world.get_origin("Well_01")
	var last: Dictionary = data.get("last", {})
	check(str(last.get("room", "")) == "Well_01" and Vector2(float(last.position[0]), float(last.position[1])).is_equal_approx(at), "and where the player is, as each room is entered (%s)" % [last])
	game.load_room("Hall_01")
	await game.room_loaded
	data = JSON.parse_string(FileAccess.get_file_as_string(EXPLORED))
	check(str(data.last.room) == "Hall_01", "a room entered again moves it on")
	# The game tells its map where the player is in its physics step (the frame after this one).
	for i in 2:
		await get_tree().physics_frame
	check(map.show_explored_marks and map.visited_rooms.has("Well_01") and map.current_room == "Hall_01", "the game's map has a check mark for each room explored and a pin for the player")
	map.queue_redraw()
	await get_tree().process_frame
	map.follow_player = true
	map.show_room_names = true
	map.queue_redraw()
	await get_tree().process_frame
	game.queue_free()
	await get_tree().process_frame

func _write(f: String, data: Dictionary) -> void:
	var file := FileAccess.open(DIR.path_join(f), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _reading() -> void:
	var e := MDSWorldGame.read_exploration(world, DIR)
	check(e.get("file", "") == EXPLORED and e.visited.size() == 2 and int(e.get("time", 0)) > 0, "the editor finds the world's exploration file (%s)" % e.get("file", ""))
	# Another world's, newer, is not it.
	_write("other_exploration.json", {"world": "res://other.mdsworld.json", "visited": ["Shrine_01"]})
	e = MDSWorldGame.read_exploration(world, DIR)
	check(e.get("file", "") == EXPLORED, "another world's file is not it")
	# Files from before they said whose they are: named after the world, else the default one.
	var old := MDSWorld.new()
	old.path = DIR + "/old.mdsworld.json"
	old.data.name = "Old Map"
	_write("mds_exploration.json", {"visited": ["Hall_01"]})
	check(MDSWorldGame.read_exploration(old, DIR).get("file", "") == DIR + "/mds_exploration.json", "a file saying nothing: the default one")
	_write("old_map_exploration.json", {"visited": ["Well_01"]})
	check(MDSWorldGame.read_exploration(old, DIR).get("file", "") == DIR + "/old_map_exploration.json", "the one named after the world comes before it")
	check(MDSWorldGame.read_exploration(world, DIR).get("file", "") == EXPLORED, "and the world's own before both")
	check(MDSWorldGame.read_exploration(world, DIR + "/nothing_here").is_empty(), "no file: nothing explored")

func _editor_map() -> void:
	var canvas := MDSWorldCanvas.new()
	canvas.size = Vector2(900, 500)
	canvas.exploration_dir = DIR
	add_child(canvas)
	canvas.set_data(world, null, {})
	check(not canvas.show.explored and canvas.explored.is_empty(), "the World map shows nothing explored until asked")
	canvas.set_show("explored", true)
	check(canvas.explored.get("file", "") == EXPLORED, "Explored in the last playtest reads it")
	var summary := canvas.explored_summary()
	check(summary.contains("2 of the layer's 3 rooms") and summary.contains("last in Hall_01"), "and says what it holds: %s" % summary)
	check(canvas.get_legend().any(func(item: Array) -> bool: return item[1] == MDSWorldCanvas.COLOR_EXPLORED), "with a legend line")
	canvas.fit_to_layer()
	canvas.redraw()
	await get_tree().process_frame
	canvas.set_show("explored", false)
	check(not canvas.get_legend().any(func(item: Array) -> bool: return item[1] == MDSWorldCanvas.COLOR_EXPLORED), "turned off, it goes")
	canvas.queue_free()
	await get_tree().process_frame
