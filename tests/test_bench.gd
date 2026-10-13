extends "res://tests/test_case.gd"
## Benches (MDSBench) and saving in MDSWorldGame, like Hollow Knight's:
## - a bench is a save point the scanner, the map and the game know;
## - Up at a bench sits the player down: held still, healed, the game saved there; a step gets
##   it up again; dying (return_to_save_point) brings it back to the bench;
## - a game started again continues on the bench, its map showing every room explored (the
##   exploration file: rooms explored after saving too) and the benches found, as a minimap;
## - new_game() starts over.
##
## The world: Well_01 | Hall_01 (start) | Shrine_01 (a bench on its floor), side by side.

const DIR := TMP + "/bench"
const WORLD := DIR + "/bench.mdsworld.json"
const SAVE := DIR + "/save.json"
const EXPLORED := DIR + "/explored.json"
const SHRINE := DIR + "/shrine_01.tscn"
const PLAYER := "extends CharacterBody2D\nvar health := 1\nvar max_health := 5\n"

var spawn := Vector2.ZERO

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in [SAVE, EXPLORED]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_catalog()
	_world()
	_scanned()
	await _resting()
	await _restart()
	await _new_game()
	_defaults()

func _catalog() -> void:
	var b := MDSEnvironment.create("bench") as MDSBench
	check(b != null and b.name == &"Bench" and MDSEnvironment.icon("bench") != null, "the bench is in the effects catalog, with its icon (%s)" % [b.name if b else "none"])
	check(b.is_in_group(&"bench") and b.is_in_group(&"save_point") and b.is_in_group(&"lantern"), "it is a bench, a save point and a lantern")
	var r := b.get_effect_rect()
	check(is_equal_approx(r.end.y, 0.0) and is_equal_approx(r.get_center().x, 0.0) and is_equal_approx(b.get_bench_width(), 120.0), "it stands on its position, 120 px wide")
	check(b.get_body_rect().has_point(Vector2(70, -10)) and not b.get_body_rect().has_point(Vector2(200, -10)), "the player can sit down from beside it, not from afar")
	b.position = Vector2(10, 20)
	check(b.get_spawn_position() == Vector2(10, -12), "a loaded game puts the player on it")
	var s := GDScript.new()
	s.source_code = PLAYER
	s.reload()
	var p: Node = s.new()
	MDSBench.heal(p)
	check(p.health == 5, "resting heals: health = max_health")
	p.free()
	b.free()

func _room_scene(path: String, bench_at := Vector2.INF) -> void:
	var root := Node2D.new()
	root.name = path.get_file().get_basename().to_pascal_case()
	if bench_at != Vector2.INF:
		var fx := Node2D.new()
		fx.name = "Effects"
		root.add_child(fx)
		var bench := MDSBench.new()
		bench.name = "Bench"
		bench.position = bench_at
		fx.add_child(bench)
	save_scene(root, path)
	root.free()

func _world() -> void:
	var world := MDSWorld.new()
	world.path = WORLD
	world.data.name = "Bench World"
	world.add_room("Well_01", Rect2(-1152, 0, 1152, 648))
	world.add_room("Hall_01", Rect2(0, 0, 1152, 648))
	world.add_room("Shrine_01", Rect2(1152, 0, 1152, 648))
	world.set_start_room("Hall_01")
	for id in ["Well_01", "Hall_01"]:
		var path := "%s/%s.tscn" % [DIR, id.to_lower()]
		_room_scene(path)
		world.set_room_scene(id, path)
	_room_scene(SHRINE, Vector2(600, 560))
	world.set_room_scene("Shrine_01", SHRINE)
	world.save()
	MDSWorld._cache.erase(WORLD)

func _scanned() -> void:
	var meta := MDSSceneScanner.new().analyze_scene_any(SHRINE)
	check((meta.get("save_points", []) as Array).size() == 1, "the scanner finds the bench as the room's save point (%s)" % [meta.get("save_points", [])])

func _game() -> MDSWorldGame:
	var game := MDSWorldGame.new()
	game.world_file = WORLD
	game.starting_room = "Hall_01"
	game.fade_time = 0.0
	game.gate_cooldown = 0.0
	game.save_file = SAVE
	game.exploration_file = EXPLORED
	var s := GDScript.new()
	s.source_code = PLAYER
	s.reload()
	var player: CharacterBody2D = s.new()
	player.name = "Player"
	player.add_to_group(&"player", true)
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 16
	cap.height = 64
	cs.shape = cap
	player.add_child(cs)
	game.add_child(player)
	game.player = player
	var map := MDSWorldMapView.new()
	map.world_file = WORLD
	map.size = Vector2(240, 160)
	map.follow_player = true
	game.add_child(map)
	game.map_view = map
	return game

func _action(bench: MDSBench, action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	bench._unhandled_input(e)

func _resting() -> void:
	var game := _game()
	add_child(game)
	await game.room_loaded
	check(game.current_room == "Hall_01" and not game.has_save_game(), "with no save, the game starts in its starting room")
	var saved: Array = []
	game.game_saved.connect(func(at: Node) -> void: saved.append(at))
	game.load_room("Shrine_01")
	await game.room_loaded
	var bench := game.room_node.get_node("Effects/Bench") as MDSBench
	spawn = bench.get_spawn_position()
	check(game.save_points.has("Shrine_01") and game.map_view.save_points.has("Shrine_01"), "the bench is known as a save point, and shows on the map")
	check(FileAccess.get_file_as_string(EXPLORED).contains("Shrine_01"), "the exploration file keeps it")
	var p := game.player as CharacterBody2D
	p.global_position = bench.global_position + Vector2(300, -32)
	_action(bench, "ui_up")
	check(bench.player_at_bench() == null and not bench.is_resting(), "away from the bench, Up does nothing")
	p.global_position = bench.global_position + Vector2(40, -32)
	check(bench.player_at_bench() == p, "at it, the player can sit")
	_action(bench, "ui_up")
	check(bench.is_resting() and bench.get_sitter() == p and p.process_mode == Node.PROCESS_MODE_DISABLED and is_equal_approx(p.global_position.x, bench.global_position.x), "Up sits the player down on it, held still")
	check(p.health == 5, "and heals it")
	check(saved.size() == 1 and saved[0] == bench and game.has_save_game(), "the game is saved (%d)" % saved.size())
	var data := game.read_save_game()
	check(data.get("room") == "Shrine_01" and Vector2(data.position[0], data.position[1]).is_equal_approx(spawn), "at the bench (%s)" % [data.get("position")])
	check(data.respawn.save_point == game.object_id(bench) and game.map_view.respawn_room == "Shrine_01", "the bench is the one to come back to, and the map marks it")
	_action(bench, "ui_up")
	check(bench.is_resting(), "Up again keeps resting")
	_action(bench, "ui_right")
	check(not bench.is_resting() and p.process_mode == Node.PROCESS_MODE_INHERIT, "a step gets the player up again")
	# Leaving the room while resting lets the player go.
	_action(bench, "ui_up")
	game.load_room("Hall_01")
	await game.room_loaded
	check(p.process_mode == Node.PROCESS_MODE_INHERIT and game.current_room == "Hall_01", "a room change gets the player up first")
	# Explored after saving: the map keeps it, though the game isn't saved again.
	game.load_room("Well_01")
	await game.room_loaded
	p.health = 0
	await game.return_to_save_point()
	check(game.current_room == "Shrine_01" and p.global_position.is_equal_approx(spawn), "dying brings the player back to the bench (%s)" % p.global_position)
	game.queue_free()
	await get_tree().process_frame

func _restart() -> void:
	var game := _game()
	var loaded := [false]
	game.game_loaded.connect(func() -> void: loaded[0] = true)
	add_child(game)
	await game.room_loaded
	check(loaded[0] and game.current_room == "Shrine_01" and game.player.global_position.is_equal_approx(spawn), "a game started again continues on the bench (%s, %s)" % [game.current_room, game.player.global_position])
	var map := game.map_view
	check(game.is_room_visited("Hall_01") and game.is_room_visited("Shrine_01") and map.visited_rooms.has("Hall_01"), "its map shows the rooms explored")
	check(game.is_room_visited("Well_01") and map.visited_rooms.has("Well_01"), "even the one explored after saving")
	check(map.save_points.has("Shrine_01") and map.respawn_room == "Shrine_01" and game.respawn.get("room") == "Shrine_01", "and the bench, the one to come back to")
	check(map.follow_player and map.clip_contents, "a minimap, following the player")
	map.player_local_pos = Vector2(600, 500)
	map.current_room = "Shrine_01"
	map.queue_redraw()
	await get_tree().process_frame
	check(map.is_room_revealed("Well_01") and map.is_room_revealed("Shrine_01"), "the rooms explored are revealed on it")
	game.queue_free()
	await get_tree().process_frame

func _new_game() -> void:
	var game := _game()
	add_child(game)
	await game.room_loaded
	game.new_game()
	await game.room_loaded
	check(game.current_room == "Hall_01" and not game.has_save_game(), "a new game starts over in the starting room, without the save")
	check(not game.is_room_visited("Shrine_01") and not game.map_view.visited_rooms.has("Shrine_01") and game.save_points.is_empty() and game.respawn.is_empty(), "with the map and benches forgotten")
	check(not FileAccess.get_file_as_string(EXPLORED).contains("Shrine_01"), "in the exploration file too")
	game.queue_free()
	await get_tree().process_frame

func _defaults() -> void:
	var g := MDSWorldGame.new()
	check(g.save_file == "user://mds_save.json" and g.exploration_file == "user://mds_exploration.json" and g.load_on_start, "by default a game saves, keeps its map and continues where it was saved")
	g.free()
	var world := MDSWorld.get_cached(WORLD)
	var path := DIR + "/game.tscn"
	check(MDSWorldSceneTools.create_game_scene(world, path) == OK, "a game scene is created")
	var scene := (load_fresh(path) as PackedScene).instantiate() as MDSWorldGame
	check(scene.save_file == "user://bench_world_save.json" and scene.exploration_file == "user://bench_world_exploration.json", "saving in files named for the world (%s)" % scene.save_file)
	check((scene.get_node("UI/Map") as MDSWorldMapView).follow_player, "with a minimap")
	scene.free()
