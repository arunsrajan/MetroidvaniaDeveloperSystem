extends "res://tests/test_case.gd"
## Gameplay Kit, phase 2: MDSPlayer in a running MDSWorldGame. Its run carries through a side gate
## (keep_momentum), jumping up through a floor gate sets it down beside the hole (land_beside_holes)
## and it stays there, an MDSBench sits it down, heals it and saves the game, and it runs and jumps
## on a Mossgrove freeform cave.

const Fixture := preload("res://tests/game_fixture.gd")
const DIR := TMP + "/player_game"
const SAVE := "user://mds_test_player_game.json"

var game: MDSWorldGame
var player: MDSPlayer

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	DirAccess.make_dir_recursive_absolute(DIR)
	Fixture.build()
	game = _game(Fixture.WORLD, "")
	add_child(game)
	await game.room_loaded
	await physics_frames(10)
	check(player.game == game and player.gameplay == MDSGameplay.find(game), "the player finds its game and the kit")
	await _side_gate()
	await _bench()
	game.queue_free()
	await get_tree().process_frame
	await _floor_gate()
	await _freeform_cave()
	_release_all()
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

func _game(world_file: String, start: String) -> MDSWorldGame:
	var g := MDSWorldGame.new()
	g.world_file = world_file
	g.fade_time = 0.0
	g.gate_cooldown = 0.0
	g.exploration_file = ""
	g.save_file = SAVE
	g.load_on_start = false
	if not start.is_empty():
		g.starting_room = start
	var kit := MDSGameplay.new()
	kit.name = "Gameplay"
	g.add_child(kit)
	player = load(MDSPlayer.SCENE).instantiate()
	g.add_child(player)
	g.player = player
	return g

func _release_all() -> void:
	for a in MDSGameplaySetup.ACTIONS:
		Input.action_release(a)

## Physics frames, at the game's pace in real time too (the gates' cooldown is real time).
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		OS.delay_msec(4)

func _until_loaded() -> void:
	for i in 600:
		if not game.current_room.is_empty() and not game.changing_room:
			return
		await get_tree().physics_frame

func _side_gate() -> void:
	player.global_position = game.world.get_origin("Garden_01") + Vector2(850, 540)
	player.velocity = Vector2.ZERO
	await physics_frames(20)
	Input.action_press(&"move_right")
	var arrived := false
	for i in 200:
		await _frames(1)
		if game.current_room == "Garden_02":
			arrived = true
			break
	await _until_loaded()
	var vx := player.velocity.x
	Input.action_release(&"move_right")
	check(arrived, "running right through right1 leads to Garden_02")
	check(vx > player.config.max_run_speed * 0.8, "with the run kept through the gate (vx %.0f)" % vx)
	await physics_frames(20)

func _bench() -> void:
	var bench := MDSBench.new()
	bench.name = "Bench"
	game.room_node.add_child(bench)
	bench.position = Vector2(600, 576)
	player.global_position = bench.global_position + Vector2(0, -40)
	player.velocity = Vector2.ZERO
	await physics_frames(20)
	player.health.take_damage(2)
	check(player.health.current == player.health.get_max() - 2, "hurt before resting")
	check(bench.rest(player), "the bench seats the player")
	check(player.machine.is_in(&"Rest") and player.velocity == Vector2.ZERO, "it sits (Rest)")
	check(player.health.current == player.health.get_max(), "it is healed")
	check(FileAccess.file_exists(SAVE) and game.read_save_game().has("ext"), "the game is saved, with the kit's data")
	await physics_frames(10)
	check(player.machine.is_in(&"Rest") and player.global_position.x == bench.global_position.x, "it stays put while resting")
	bench.leave()
	await physics_frames(5)
	check(not player.machine.is_in(&"Rest"), "getting up ends the rest (%s)" % player.machine.get_state())

## Two rooms stacked: Peak_01 with a floor and a hole under bot1, Depths_01 below with top1.
func _vertical_world() -> String:
	var path := DIR + "/vertical.mdsworld.json"
	var ts := MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	var world := MDSWorld.new()
	world.path = path
	world.add_room("Peak_01", Rect2(0, 0, 1152, 648), 0)
	world.add_room("Depths_01", Rect2(0, 688, 1152, 648), 0)
	world.get_gates("Peak_01")["bot1"] = {"pos": [576, 648], "side": "bot"}
	world.get_gates("Depths_01")["top1"] = {"pos": [576, 0], "side": "top"}
	world.connect_gates("Peak_01", "bot1", "Depths_01", "top1")
	for id in ["Peak_01", "Depths_01"]:
		var root := Node2D.new()
		root.name = id
		var t := TileMapLayer.new()
		t.name = "Terrain"
		t.tile_set = ts
		root.add_child(t)
		for x in 36:
			if id == "Peak_01" and x >= 16 and x <= 19:
				continue
			t.set_cell(Vector2i(x, 19), 0, Vector2i(0, 0))
			t.set_cell(Vector2i(x, 20), 0, Vector2i(0, 0))
		var gates := Node2D.new()
		gates.name = "Gates"
		root.add_child(gates)
		var g := MDSWorldSceneTools.new_gate_node(world, id, "bot1" if id == "Peak_01" else "top1")
		g.position = Vector2(576, 648) if id == "Peak_01" else Vector2(576, 0)
		gates.add_child(g)
		var scene := "%s/%s.tscn" % [DIR, id.to_lower()]
		save_scene(root, scene)
		root.free()
		world.set_room_scene(id, scene)
	world.save()
	MDSWorld._cache.erase(path)
	return path

func _floor_gate() -> void:
	game = _game(_vertical_world(), "Depths_01")
	add_child(game)
	await _until_loaded()
	await _frames(10)
	var origin := game.world.get_origin("Depths_01")
	player.global_position = origin + Vector2(576, 120)
	player.velocity = Vector2(0, -900)
	player.machine.force(&"Jump", {"keep_velocity": true})
	for i in 90:
		await _frames(1)
		if game.current_room == "Peak_01":
			break
	await _until_loaded()
	check(game.current_room == "Peak_01", "jumping up through top1 leads to Peak_01")
	for i in 240:
		await _frames(1)
		if player.is_on_floor() or game.current_room != "Peak_01":
			break
	var x := player.global_position.x - game.world.get_origin("Peak_01").x
	check(game.current_room == "Peak_01" and player.is_on_floor(), "the player lands in Peak_01 (at %s, %s)" % [player.global_position.round(), player.machine.get_state()])
	check(absf(x - 576.0) > 64.0 and absf(x - 576.0) < 160.0, "beside the hole (x %d; the hole is 512..640)" % x)
	await _frames(40)
	check(game.current_room == "Peak_01", "and does not fall back through it")
	game.queue_free()
	await get_tree().process_frame

func _freeform_cave() -> void:
	var path := "res://asset_packs/mossgrove/demo/freeform_cave.tscn"
	if not ResourceLoader.exists(path):
		check(false, "the Mossgrove freeform cave is there")
		return
	var cave: Node = (load(path) as PackedScene).instantiate()
	for n in cave.find_children("*", "", true, false):
		if n.is_in_group(&"player"):
			n.get_parent().remove_child(n)
			n.free()
	add_child(cave)
	player = load(MDSPlayer.SCENE).instantiate()
	add_child(player)
	await physics_frames(3)
	# A floor of freeform rock: straight down from the middle of the cave's shapes.
	var shapes := cave.find_children("*", "MDSFreeform", true, false)
	var space := player.get_world_2d().direct_space_state
	var spot := Vector2.INF
	var rect := Rect2()
	for f in cave.find_children("*", "Node2D", true, false):
		if f is MDSFreeform:
			var b := MDSGeometry.bounds((f as MDSFreeform).points)
			rect = Rect2((f as Node2D).global_position + b.position, b.size) if not rect.has_area() else rect.merge(Rect2((f as Node2D).global_position + b.position, b.size))
	for i in 40:
		var x := lerpf(rect.position.x + 100.0, rect.end.x - 100.0, float(i) / 39.0)
		var from := Vector2(x, rect.position.y + 10.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, Vector2(x, rect.end.y), 1))
		if hit.is_empty() or (hit.normal as Vector2).y > -0.8:
			continue
		var head := (hit.position as Vector2) - Vector2(0, 80)
		if space.intersect_point(_point(head)).is_empty() and space.intersect_point(_point(head + Vector2(0, 40))).is_empty():
			spot = head
			break
	check(not shapes.is_empty() and spot != Vector2.INF, "a floor in the freeform cave (%d shapes)" % shapes.size())
	if spot == Vector2.INF:
		return
	player.global_position = spot
	await physics_frames(60)
	check(player.is_on_floor(), "the player stands on freeform rock (%s)" % player.machine.get_state())
	var y0 := player.global_position.y
	var top := y0
	Input.action_press(&"jump")
	for i in 30:
		await get_tree().physics_frame
		top = minf(top, player.global_position.y)
	Input.action_release(&"jump")
	await physics_frames(60)
	check(y0 - top > 40.0 and player.is_on_floor(), "jumps (%.0f px) and lands again" % (y0 - top))
	cave.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _point(p: Vector2) -> PhysicsPointQueryParameters2D:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = 1
	return q
