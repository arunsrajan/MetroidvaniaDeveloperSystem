extends "res://tests/test_case.gd"
## Going up and down between rooms of two areas, one above the other: Peak_01 (area Peaks) has
## bot1 in a hole in its floor; Depths_01 (area Depths) below it has top1 in its ceiling, 40 px
## lower (rooms need not touch).
## - down: dropping through the hole, the player arrives in Depths_01 and lands on its floor;
## - up: jumping up through top1, the player arrives in Peak_01 set down beside the hole, on its
##   floor, and stays there: before, it came up over the hole with nothing to land on, and fell
##   straight back into Depths_01 (MDSWorldGame.land_beside_holes, ledge_beside());
## - a gate gone into while gates are still ignored (just arrived) is taken after, if the player
##   is still in it or went through it: before, the player fell out of the room for good;
## - a room with nothing beside the hole keeps the player over it.

const DIR := TMP + "/gate_arrival"
const WORLD := DIR + "/arrival.mdsworld.json"
const GRAVITY := 980.0

var game: MDSWorldGame
var player: CharacterBody2D

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := _world()
	game = MDSWorldGame.new()
	game.world_file = WORLD
	game.fade_time = 0.0
	game.save_file = ""
	game.exploration_file = ""
	game.load_on_start = false
	game.starting_room = "Depths_01"
	player = CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group(&"player", true)
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 16
	cap.height = 64
	cs.shape = cap
	player.add_child(cs)
	var script := GDScript.new()
	script.source_code = "extends CharacterBody2D\nfunc _physics_process(delta: float) -> void:\n\tvelocity.y = minf(velocity.y + %f * delta, 900.0)\n\tvelocity.x = 0.0\n\tmove_and_slide()\n" % GRAVITY
	script.reload()
	player.set_script(script)
	game.add_child(player)
	game.player = player
	add_child(game)
	await _until_loaded()
	check(game.current_room == "Depths_01", "the game starts in Depths_01")
	await _up(world)
	await _down(world)
	await _late_gate(world)
	_no_ledge(world)
	game.queue_free()
	await get_tree().process_frame

## Two rooms, stacked: Peak_01 with a floor and a 4-tile hole under bot1, Depths_01 40 px below.
func _world() -> MDSWorld:
	var ts := MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	var world := MDSWorld.new()
	world.path = WORLD
	world.data.areas["Peaks"] = {"color": "#8253b8"}
	world.data.areas["Depths"] = {"color": "#81b853"}
	world.add_room("Peak_01", Rect2(0, 0, 1152, 648), 0, "Peaks")
	world.add_room("Depths_01", Rect2(0, 688, 1152, 648), 0, "Depths")
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
			# Peak_01's floor has a hole under bot1 (x 512..640).
			if id == "Peak_01" and x >= 16 and x <= 19:
				continue
			t.set_cell(Vector2i(x, 19), 0, Vector2i(0, 0))
			t.set_cell(Vector2i(x, 20), 0, Vector2i(0, 0))
		var gates := Node2D.new()
		gates.name = "Gates"
		root.add_child(gates)
		var g := MDSWorldSceneTools.new_gate_node(world, id, "bot1" if id == "Peak_01" else "top1")
		g.position = Vector2(576, 648) if id == "Peak_01" else Vector2(576, 0)
		g.collision_mask = 1
		gates.add_child(g)
		var path := "%s/%s.tscn" % [DIR, id.to_lower()]
		save_scene(root, path)
		root.free()
		world.set_room_scene(id, path)
	world.save()
	MDSWorld._cache.erase(WORLD)
	return world

func _until_loaded() -> void:
	for i in 600:
		if not game.current_room.is_empty() and not game.changing_room:
			return
		await get_tree().physics_frame

## Physics frames, at the game's pace in real time too (the gates' cooldown is real time).
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		OS.delay_msec(4)

func _past_cooldown() -> void:
	OS.delay_msec(int(game.gate_cooldown * 1000.0) + 50)
	await _frames(4)

func _up(world: MDSWorld) -> void:
	await _past_cooldown()
	# Under top1, jumping up into it.
	player.global_position = world.get_origin("Depths_01") + Vector2(576, 120)
	player.velocity = Vector2(0, -900)
	for i in 60:
		await _frames(1)
		if game.current_room == "Peak_01":
			break
	await _until_loaded()
	check(game.current_room == "Peak_01", "jumping up through top1 leads to Peak_01")
	# It keeps its jump: a hop out of the hole, then down beside it.
	for i in 240:
		await _frames(1)
		if player.is_on_floor() or game.current_room != "Peak_01":
			break
	var x := player.global_position.x - world.get_origin("Peak_01").x
	check(game.current_room == "Peak_01" and player.is_on_floor(), "the player stays in Peak_01, standing (at %s)" % player.global_position.round())
	check(absf(x - 576.0) > 64.0 and absf(x - 576.0) < 140.0, "beside the hole, at its rim (x %d; the hole is 512..640)" % x)
	await _past_cooldown()
	await _frames(30)
	check(game.current_room == "Peak_01", "and does not fall back through it")

func _down(world: MDSWorld) -> void:
	await _past_cooldown()
	player.global_position = world.get_origin("Peak_01") + Vector2(576, 520)
	player.velocity = Vector2.ZERO
	for i in 120:
		await _frames(1)
		if game.current_room == "Depths_01":
			break
	await _until_loaded()
	check(game.current_room == "Depths_01", "dropping through the hole leads to Depths_01")
	await _frames(90)
	check(player.is_on_floor() and player.global_position.y < world.get_origin("Depths_01").y + 648.0, "and the player lands on its floor (at %s)" % player.global_position.round())

func _late_gate(world: MDSWorld) -> void:
	# Arriving in Peak_01 again, then straight into the hole while gates are still ignored.
	await _past_cooldown()
	game.load_room("Peak_01", "bot1")
	await _until_loaded()
	player.global_position = world.get_origin("Peak_01") + Vector2(576, 600)
	player.velocity = Vector2(0, 600)
	await get_tree().physics_frame
	check(Time.get_ticks_msec() < game._cooldown_until, "the player is in the gate while gates are still ignored")
	await _past_cooldown()
	await _until_loaded()
	check(game.current_room == "Depths_01", "the gate is taken once they are not: the player doesn't fall out of the room")

func _no_ledge(world: MDSWorld) -> void:
	# Peak_01 without its floor: nothing beside the hole.
	var floor_layer := game.room_node.get_node_or_null("Terrain") as TileMapLayer
	if game.current_room != "Peak_01":
		check(world.has_room("Peak_01"), "(skipped: not in Peak_01)")
		return
	floor_layer.clear()
	check(game.ledge_beside(MDSGate.find_gate(game.room_node, "bot1")) == Vector2.INF, "with nothing beside the hole, no ledge")
