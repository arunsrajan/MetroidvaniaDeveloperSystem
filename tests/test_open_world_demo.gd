extends "res://tests/test_case.gd"
## The open world demo (examples/open_world_demo, built by build_open_world_demo.gd): its rooms are
## walked through and back, the meadows into the arena and down into the Hollow, from their
## Terrain layers; and its game streams them, the next meadow there before the player walks in.

const DEMO := "res://examples/open_world_demo"
const TS := 32

func _run() -> void:
	var world := MDSWorld.get_cached(DEMO + "/open_world_demo.mdsworld.json")
	check(world.get_room_ids().size() == 6, "six rooms (%s)" % [world.get_room_ids()])
	check(bool(world.get_setting("depth_25d", false)) and str(world.get_setting("depth_style", "")) == MDSDepthStyle.DAYLIGHT and ResourceLoader.exists(str(world.get_setting("room_tileset", ""))), "2.5D in daylight, its own daylight tileset")
	# Every room's open cells, in world cells.
	var open: Dictionary = {}
	for id in world.get_room_ids():
		var p := MDSRoomPainter.open(world.get_scene_path(id))
		var solid: Dictionary = {}
		for c in p.layers.Terrain.get_used_cells():
			solid[c] = true
		var o := Vector2i((world.get_origin(id) / TS).round())
		for c in p.room_cells(world, id, false):
			if not solid.has(c):
				open[c + o] = true
		p.free_instance()
	var start := _ground(open, Vector2i(20, 2))
	var there := MDSRoomPainter.climb_reach(open, start, 6, 3)
	var arena := _ground(open, Vector2i(4 * 72 + 27, 2))
	var hollow := Vector2i(72 + 36, 27 + 10)
	var hollow_reached := false
	for c: Vector2i in there:
		if c.y > 27 and c.x > 72 and c.x < 144:
			hollow_reached = true
			break
	check(there.has(arena), "from Meadow_01, across the meadows into the Ridge Arena")
	check(hollow_reached, "and down the hole into the Hollow")
	var back := MDSRoomPainter.climb_reach(open, arena, 6, 3)
	check(back.has(start), "and back from the arena to Meadow_01")
	var hollow_ground := _ground(open, hollow)
	check(MDSRoomPainter.climb_reach(open, hollow_ground, 6, 3).has(start), "and back up out of the Hollow")
	# The game.
	var game := (load(DEMO + "/game.tscn") as PackedScene).instantiate() as MDSWorldGame
	check(game.stream_rooms, "its game streams the rooms around the player")
	game.load_on_start = false
	game.save_file = ""
	game.exploration_file = ""
	add_child(game)
	for i in 600:
		if not game.current_room.is_empty() and not game.changing_room and game.is_stream_ready():
			break
		await get_tree().physics_frame
	check(game.current_room == "Meadow_01" and game.streamed.has("Meadow_02"), "starts in Meadow_01, Meadow_02 loaded beside it (%s)" % [game.streamed.keys()])
	var next: Node2D = game.streamed.get("Meadow_02")
	game.player.global_position = world.get_origin("Meadow_02") + Vector2(300, 200)
	for i in 120:
		await get_tree().physics_frame
		if game.current_room == "Meadow_02" and not game.changing_room:
			break
	check(game.current_room == "Meadow_02" and game.room_node == next, "walked into Meadow_02: the room loaded beside it, not loaded again")
	await get_tree().create_timer(0.5).timeout
	game.queue_free()
	await get_tree().process_frame

## The open cell standing on the ground in [param at]'s column, from [param at] down.
func _ground(open: Dictionary, at: Vector2i) -> Vector2i:
	var c := at
	for i in 80:
		if open.has(c) and not open.has(c + Vector2i.DOWN):
			return c
		c.y += 1
	return at
