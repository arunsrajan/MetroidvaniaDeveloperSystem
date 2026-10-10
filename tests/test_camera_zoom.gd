extends "res://tests/test_case.gd"
## MDSRoomCamera's zoom between rooms (auto_zoom): fixed, a room's own zoom, or fitted to the
## room (out in a big room, in in a small one); gliding there (zoom_tween) after a cut, with a
## blend, or snapping; small changes snapping; limits never smaller than the view.
##
##   Big (3456 x 1944) -> Small (768 x 432) -> Own (1152 x 648, camera_zoom 1.5)

const DIR := "res://tests/tmp/camera_zoom"
const WORLD := DIR + "/zoom.idpworld.json"

var game: MDSWorldGame
var rc: MDSRoomCamera
var player: Node2D
var screen: SubViewport

func _run() -> void:
	_build_world()
	await _start(MDSRoomCamera.AutoZoom.OFF)
	check(rc.camera.zoom == Vector2.ONE and is_equal_approx(rc.rest_zoom(), 1.0), "Off: the big room at the set zoom")
	await _go("Small", "left1")
	check(rc.camera.zoom == Vector2.ONE, "and the small one too")
	await _stop()

	await _start(MDSRoomCamera.AutoZoom.FIT)
	check(rc.camera.zoom.is_equal_approx(Vector2(0.5, 0.5)) and is_equal_approx(rc.rest_zoom(), 0.5), "Fit: a big room is seen from farther out, down to Min zoom (%s)" % rc.camera.zoom)
	var view := rc.camera.get_viewport_rect().size / rc.camera.zoom
	check(rc.camera.limit_right - rc.camera.limit_left >= view.x - 1.0 and rc.camera.limit_bottom - rc.camera.limit_top >= view.y - 1.0, "its limits are never smaller than the view")
	rc.zoom_time = 0.3
	await _go("Small", "left1")
	await wait(0.1)
	var mid := rc.camera.zoom.x
	check(mid > 0.5 and mid < 1.5, "after the cut into a small room the zoom glides (%.2f)" % mid)
	await wait(0.45)
	check(rc.camera.zoom.is_equal_approx(Vector2(1.5, 1.5)), "to the zoom that fills the screen with it (%s)" % rc.camera.zoom)
	await _go("Own", "left1")
	await wait(0.45)
	check(rc.camera.zoom.is_equal_approx(Vector2(1.5, 1.5)) and is_equal_approx(rc.room_zoom("Own"), 1.5), "a room's own zoom wins")
	await _stop()

	await _start(MDSRoomCamera.AutoZoom.FIT, false)
	await _go("Small", "left1")
	await frames(1)
	check(rc.camera.zoom.is_equal_approx(Vector2(1.5, 1.5)), "zoom glide off: it snaps (%s)" % rc.camera.zoom)
	await _stop()

	await _start(MDSRoomCamera.AutoZoom.ROOM)
	check(rc.camera.zoom == Vector2.ONE, "Per room: rooms without a zoom of their own keep the set zoom")
	rc.zoom_time = 0.2
	await _go("Small", "left1")
	await _go("Own", "left1")
	await wait(0.35)
	check(rc.camera.zoom.is_equal_approx(Vector2(1.5, 1.5)), "and a room with one glides to it (%s)" % rc.camera.zoom)
	# A tiny change snaps.
	game.world.set_room_value("Own", MDSRoomCamera.ROOM_ZOOM_KEY, 1.52)
	rc._glide_zoom(rc.zoom_for(rc.zone), 1.0)
	check(rc.camera.zoom.is_equal_approx(Vector2(1.52, 1.52)), "a change under the threshold snaps (%s)" % rc.camera.zoom)
	await _stop()

	# Blend: the zoom glides with the limits.
	await _start(MDSRoomCamera.AutoZoom.FIT, true, MDSRoomCamera.Transition.BLEND)
	rc.transition_time = 0.3
	game.load_room("Small", "left1")
	await wait(0.12)
	check(rc.camera.zoom.x > 0.5 and rc.camera.zoom.x < 1.5, "a blend glides the zoom too (%.2f)" % rc.camera.zoom.x)
	await wait(0.5)
	check(rc.camera.zoom.is_equal_approx(Vector2(1.5, 1.5)), "and ends at the room's (%s)" % rc.camera.zoom)
	await _stop()
	# The world file's settings.
	var from_world := MDSRoomCamera.new()
	from_world.apply_settings({"auto_zoom": 2, "zoom_factor": 1.2, "min_zoom": 0.4, "max_zoom": 3.0, "zoom_tween": 0, "zoom_time": 0.9, "zoom_tween_threshold": 0.1})
	check(from_world.auto_zoom == MDSRoomCamera.AutoZoom.FIT and is_equal_approx(from_world.zoom_factor, 1.2) and is_equal_approx(from_world.min_zoom, 0.4) and not from_world.zoom_tween and is_equal_approx(from_world.zoom_time, 0.9), "the zoom settings come from the world file (World settings > Camera)")
	from_world.free()

func frames(n := 2) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _build_world() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := MDSWorld.new()
	world.path = WORLD
	var big := world.add_room("Big", Rect2(0, 0, 3456, 1944))
	var small := world.add_room("Small", Rect2(3456, 1512, 768, 432))
	var own := world.add_room("Own", Rect2(4224, 1296, 1152, 648))
	world.set_room_value(own, MDSRoomCamera.ROOM_ZOOM_KEY, 1.5)
	var a := world.add_gate(big, Vector2(3456, 1800), "right", "right1", false)
	var b := world.add_gate(small, Vector2(3456, 1800), "left", "left1", false)
	world.connect_gates(big, a, small, b)
	var c := world.add_gate(small, Vector2(4224, 1800), "right", "right1", false)
	var d := world.add_gate(own, Vector2(4224, 1800), "left", "left1", false)
	world.connect_gates(small, c, own, d)
	# Scenes with their MDSGate nodes.
	for id in [big, small, own]:
		MDSWorldSceneTools.create_scene_for_room(world, id, DIR + "/" + id.to_lower() + ".tscn")
	world.set_start_room(big)
	world.save()
	MDSWorld._cache.erase(WORLD)

func _start(mode: MDSRoomCamera.AutoZoom, tween := true, transition := MDSRoomCamera.Transition.CUT) -> void:
	game = MDSWorldGame.new()
	game.world_file = WORLD
	game.fade_time = 0.0
	game.room_darkness = false
	player = CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group(&"player")
	game.add_child(player)
	game.player = player
	rc = MDSRoomCamera.new()
	rc.name = "RoomCamera"
	rc.backend = MDSRoomCamera.Backend.CAMERA_2D
	rc.use_world_settings = false
	rc.room_transition = transition
	rc.auto_zoom = mode
	rc.zoom_tween = tween
	game.add_child(rc)
	game.room_camera = rc
	screen = SubViewport.new()
	screen.size = Vector2i(1152, 648)
	add_child(screen)
	screen.add_child(game)
	await game.room_loaded
	await frames(2)

func _go(id: String, gate: String) -> void:
	game.load_room(id, gate)
	await game.room_loaded

func _stop() -> void:
	screen.queue_free()
	await frames(2)
