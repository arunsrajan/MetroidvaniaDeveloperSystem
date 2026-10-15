extends "res://tests/test_case.gd"
## The room camera after a room change: it shows the new room, also when the player went into
## the gate right after moving between camera zones of the old room. That started a glide of the
## camera's limits (zone_blend_time) which went on after the new room was entered, setting the old
## room's limits over the new room's: the camera stayed on the old room, unloaded, and the screen
## was empty (the first time down a hole from a room's lower zone).
##
## Hall_01 is an L: a wide top and a narrow part under its left (two camera zones), bot1 at the
## bottom of the narrow part. Pit_01 lies 40 px below it, top1 in its ceiling.

const DIR := TMP + "/camera_rooms"
const WORLD := DIR + "/rooms.mdsworld.json"

var game: MDSWorldGame
var player: CharacterBody2D
var world: MDSWorld

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	world = _world()
	game = MDSWorldGame.new()
	game.world_file = WORLD
	game.save_file = ""
	game.exploration_file = ""
	game.load_on_start = false
	game.gate_cooldown = 0.0
	game.starting_room = "Hall_01"
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
	script.source_code = "extends CharacterBody2D\nfunc _physics_process(delta: float) -> void:\n\tvelocity.y = minf(velocity.y + 980.0 * delta, 900.0)\n\tmove_and_slide()\n"
	script.reload()
	player.set_script(script)
	# The camera rides on the player, as in a usual player scene.
	var cam := Camera2D.new()
	player.add_child(cam)
	game.add_child(player)
	game.player = player
	game.camera = cam
	var rc := MDSRoomCamera.new()
	rc.camera = cam
	rc.target = player
	rc.room_transition = MDSRoomCamera.Transition.FADE
	rc.zone_blend_time = 0.5
	game.add_child(rc)
	game.room_camera = rc
	add_child(game)
	await _until_loaded()
	# In the wide top, where the camera rests.
	player.global_position = world.get_origin("Hall_01") + Vector2(800, 300)
	player.velocity = Vector2.ZERO
	await _frames(20)
	var top_limits := _limits(cam)
	# Into the narrow part: the camera starts gliding to it... and straight down the hole.
	player.global_position = world.get_origin("Hall_01") + Vector2(288, 1150)
	player.velocity = Vector2(0, 600)
	await _frames(2)
	check(rc._limit_tween != null and rc._limit_tween.is_running(), "moving into the room's other zone starts the camera's glide to it")
	for i in 120:
		await _frames(1)
		if game.current_room == "Pit_01" and not game.changing_room:
			break
	check(game.current_room == "Pit_01", "down bot1 into Pit_01")
	# Long after the old glide would have ended.
	await _frames(90)
	var pit := world.get_room_bounds("Pit_01")
	var seen := Rect2(cam.get_screen_center_position() - Vector2(576, 324) / cam.zoom, Vector2(1152, 648) / cam.zoom)
	check(pit.intersects(seen) and pit.has_point(cam.get_screen_center_position()), "the camera shows Pit_01 (it looks at %s; Pit_01 is %s)" % [cam.get_screen_center_position().round(), pit])
	check(_limits(cam) != top_limits and pit.grow(1.0).encloses(_limits(cam)), "with Pit_01's limits, not Hall_01's (%s)" % _limits(cam))
	game.queue_free()
	await get_tree().process_frame

func _limits(cam: Camera2D) -> Rect2:
	return Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top)

func _world() -> MDSWorld:
	var w := MDSWorld.new()
	w.path = WORLD
	w.data.areas["Halls"] = {"color": "#8253b8"}
	w.data.areas["Pits"] = {"color": "#81b853"}
	w.add_room("Hall_01", Rect2(0, 0, 1152, 648), 0, "Halls")
	w.add_rect("Hall_01", Rect2(0, 648, 576, 648))
	w.add_room("Pit_01", Rect2(0, 1336, 1152, 648), 0, "Pits")
	w.get_gates("Hall_01")["bot1"] = {"pos": [288, 1296], "side": "bot"}
	w.get_gates("Pit_01")["top1"] = {"pos": [288, 0], "side": "top"}
	w.connect_gates("Hall_01", "bot1", "Pit_01", "top1")
	for id in ["Hall_01", "Pit_01"]:
		var root := Node2D.new()
		root.name = id
		var gates := Node2D.new()
		gates.name = "Gates"
		root.add_child(gates)
		var gate_name := "bot1" if id == "Hall_01" else "top1"
		var g := MDSWorldSceneTools.new_gate_node(w, id, gate_name)
		g.position = Vector2(w.get_gate_local_pos(id, gate_name))
		g.collision_mask = 1
		gates.add_child(g)
		var path := "%s/%s.tscn" % [DIR, id.to_lower()]
		save_scene(root, path)
		root.free()
		w.set_room_scene(id, path)
	w.save()
	MDSWorld._cache.erase(WORLD)
	return w

func _until_loaded() -> void:
	for i in 600:
		if not game.current_room.is_empty() and not game.changing_room:
			return
		await get_tree().physics_frame

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
