extends "res://tests/test_case.gd"
## Brief 15: MDSCameraDirector on an MDSRoomCamera in an L-shaped room: pull-outs never show
## outside the room's shape, every action ends back on the room's rest camera, a focus beats a
## threat, automatic framing of a chasing enemy, and the cut style. With the Camera2D backend,
## and again with PhantomCamera2D when the Phantom Camera addon is installed and enabled.
##
##   Hall: (0,0)-(2304,1296) plus the leg (0,1296)-(1152,1944); missing: the bottom right.

const DIR := "res://tests/tmp/camera"
const WORLD := DIR + "/camera.mdsworld.json"
const HALL: Array[Rect2] = [Rect2(0, 0, 2304, 1296), Rect2(0, 1296, 1152, 648)]
const CHASER_SCRIPT := "extends Node2D\nenum State { IDLE, CHASE }\nvar state := State.IDLE\n"

var game: MDSWorldGame
var rc: MDSRoomCamera
var director: MDSCameraDirector
var cam: Camera2D
var player: Node2D

func _run() -> void:
	_build_world()
	await _run_with(MDSRoomCamera.Backend.CAMERA_2D)
	if MDSRoomCamera.phantom_available():
		print("  again with PhantomCamera2D")
		await _run_with(MDSRoomCamera.Backend.PHANTOM_CAMERA)
	else:
		print("  (Phantom Camera isn't installed: only the Camera2D backend was tested)")

func _run_with(backend: MDSRoomCamera.Backend) -> void:
	_make_game(backend)
	# Headless windows are tiny: the game gets a screen of its own.
	var screen := SubViewport.new()
	screen.size = Vector2i(1152, 648)
	add_child(screen)
	screen.add_child(game)
	await game.room_loaded
	await frames(3)
	check(cam.get_viewport_rect().size == Vector2(1152, 648), "sanity: a 1152 x 648 view (%s)" % cam.get_viewport_rect().size)
	check(rc.zones.size() == 2, "sanity: the L room has two camera zones (%s)" % [rc.zones])
	check(rc.using_phantom == (backend == MDSRoomCamera.Backend.PHANTOM_CAMERA), "sanity: the backend asked for")
	await _threat_pull_out()
	await _pull_out_kept_inside_shape()
	await _focus_beats_threat()
	await _punch_and_reveal()
	await _automatic()
	await _cut_style()
	await _cancel()
	Engine.time_scale = 1.0
	screen.queue_free()
	await frames(2)

## Waits [param n] frames, physics frames included: Phantom Camera's host moves the camera on
## physics frames when it follows a physics body.
func frames(n := 2) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

## What the camera shows now.
func view() -> Rect2:
	var half := cam.get_viewport_rect().size / 2.0 / cam.zoom.x
	return Rect2(cam.get_screen_center_position() - half, half * 2.0)

func place_player(p: Vector2) -> void:
	var zone := rc.zone
	player.global_position = p
	await get_tree().physics_frame
	await frames(3)
	if rc.zone != zone and not rc.is_cut():
		# The room camera glides to the new zone first.
		await wait(rc.zone_blend_time + 0.1)

## Watches the view for [param seconds] (real time): returns the views that showed outside the
## room's shape and the smallest zoom seen.
func watch(seconds: float) -> Dictionary:
	var bad: Array = []
	var min_z := INF
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var v := view()
		min_z = minf(min_z, cam.zoom.x)
		if not MDSCameraDirector.covered(v, HALL):
			bad.append(v)
	return {"bad": bad, "min_zoom": min_z}

func until_released(timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while director.is_overriding() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	await frames(2)
	return not director.is_overriding()

## After a director action: the room's own camera, exactly.
func check_at_rest(what: String) -> void:
	check(not rc.directed and is_equal_approx(cam.zoom.x, rc.zoom.x) and cam.offset == Vector2.ZERO, "%s: the camera is back at the room's zoom, unoffset (zoom %s, offset %s)" % [what, cam.zoom, cam.offset])
	var l := rc.rest_limits()
	check(cam.limit_left == floori(l.position.x) and cam.limit_right == ceili(l.end.x) and cam.limit_top == floori(l.position.y) and cam.limit_bottom == ceili(l.end.y), "%s: with the room camera's limits back" % what)
	check(cam.get_screen_center_position().distance_to(rc.rest_centre()) < 3.0, "%s: looking where the room's camera looks (%s vs %s)" % [what, cam.get_screen_center_position(), rc.rest_centre()])

func _enemy(at: Vector2, script_text := "") -> Node2D:
	var e := Node2D.new()
	if not script_text.is_empty():
		var s := GDScript.new()
		s.source_code = script_text
		s.reload()
		e.set_script(s)
	e.add_to_group(&"enemy")
	game.room_node.add_child(e)
	e.global_position = at
	return e

# --- Threats ----------------------------------------------------------------------------------------

func _threat_pull_out() -> void:
	await place_player(Vector2(600, 900))
	check_at_rest("at the start")
	var threat := _enemy(Vector2(2100, 300))
	var started := [0]
	director.started.connect(func(_k: int) -> void: started[0] += 1)
	director.frame_threat(threat, 0.8)
	check(director.is_overriding() and director.current_kind() == MDSCameraDirector.Kind.THREAT and started[0] == 1, "a threat off screen takes the camera")
	var w: Dictionary = await watch(0.6)
	check(w.bad.is_empty(), "the pull-out never shows outside the room (%d bad views: %s)" % [w.bad.size(), w.bad.slice(0, 3)])
	check(w.min_zoom < 0.8 and w.min_zoom >= 0.6 - 0.001, "it pulls out, not past min_zoom (%.2f)" % w.min_zoom)
	check(view().has_point(threat.global_position) and view().has_point(player.global_position), "the threat and the player are both in view")
	check(await until_released(), "it lets go after the hold")
	check_at_rest("after framing a threat")
	threat.queue_free()

func _pull_out_kept_inside_shape() -> void:
	# Player in the leg, threat in the big part's bottom right: any pull-out wide enough would
	# show the missing corner.
	await place_player(Vector2(600, 1700))
	var threat := _enemy(Vector2(2000, 1100))
	director.frame_threat(threat, 0.6)
	var w: Dictionary = await watch(0.5)
	check(w.bad.is_empty(), "in the leg of the L, no view shows the missing corner (%d bad: %s)" % [w.bad.size(), w.bad.slice(0, 3)])
	check(await until_released(), "nothing holds the camera")
	check_at_rest("after a pull-out the room had no space for")
	# The plan itself: wherever the centre is asked to be, legal views stay inside the shape.
	for z in [0.6, 0.7, 0.8, 0.9]:
		var legal := director.legal_view(Vector2(1700, 1500), z, player.global_position)
		if not legal.is_empty():
			var half := Vector2(576, 324) / float(legal.zoom)
			check(MDSCameraDirector.covered(Rect2(legal.centre - half, half * 2.0), HALL), "a legal view at zoom %.1f is inside the shape" % z)
	threat.queue_free()

func _focus_beats_threat() -> void:
	await place_player(Vector2(600, 900))
	var boss := _enemy(Vector2(800, 900))
	var far := _enemy(Vector2(2100, 300))
	director.focus_on(boss, 1.5, 0.5, 0.5)
	check(director.current_kind() == MDSCameraDirector.Kind.FOCUS and is_equal_approx(Engine.time_scale, 0.5), "a focus takes the camera and slows the game")
	director.frame_threat(far, 2.0)
	check(director.current_kind() == MDSCameraDirector.Kind.FOCUS, "a threat doesn't take over a focus")
	director.punch_in(1.2, 1.0)
	check(director.current_kind() == MDSCameraDirector.Kind.FOCUS, "nor does a punch")
	await wait(0.4)
	check(cam.zoom.x > 1.3, "the focus pushes in (%.2f)" % cam.zoom.x)
	check(view().has_point(boss.global_position), "on what it focuses on")
	check(await until_released(), "the focus ends")
	check(is_equal_approx(Engine.time_scale, 1.0), "and the game runs at full speed again")
	check_at_rest("after a focus")
	boss.queue_free()
	far.queue_free()

func _punch_and_reveal() -> void:
	director.punch_in(1.25, 0.3)
	await wait(0.25)
	check(cam.zoom.x > 1.1, "a punch pushes in (%.2f)" % cam.zoom.x)
	check(await until_released(), "and ends")
	check_at_rest("after a punch")
	director.reveal(Rect2(0, 0, 2304, 1296), 0.5)
	check(director.current_kind() == MDSCameraDirector.Kind.THREAT, "a reveal takes the camera")
	var w: Dictionary = await watch(0.5)
	check(w.bad.is_empty() and w.min_zoom < 0.75, "it pulls out over the arena, inside the room (zoom %.2f, %d bad)" % [w.min_zoom, w.bad.size()])
	director.release()
	check(await until_released(), "release() lets go early")
	check_at_rest("after a reveal")

func _automatic() -> void:
	await place_player(Vector2(600, 900))
	var e := _enemy(Vector2(1900, 400), CHASER_SCRIPT)
	director.automatic = true
	director.watch_interval = 0.05
	await wait(0.3)
	check(not director.is_overriding(), "an idle enemy off screen is left alone")
	e.set("state", 1) # CHASE
	await wait(0.3)
	check(director.is_overriding() and director.current_kind() == MDSCameraDirector.Kind.THREAT, "a chasing one is framed")
	director.automatic = false
	e.queue_free()
	director.release()
	check(await until_released(), "and released")
	check_at_rest("after automatic framing")

func _cut_style() -> void:
	rc.transition_style = MDSRoomCamera.Motion.CUT
	director.punch_in(1.3, 0.2)
	await frames(2) # Phantom Camera's host applies its camera on its next frame
	check(is_equal_approx(cam.zoom.x, 1.3), "with the cut style the director cuts in at once (%.2f)" % cam.zoom.x)
	check(await until_released(), "and lets go")
	check_at_rest("after a cut")
	# Zones cut too: walking into the leg moves the limits at once.
	await place_player(Vector2(300, 1700))
	var l := rc.rest_limits()
	check(rc.zone.position.y == 0 and rc.zone.size.y == 1944 and cam.limit_bottom == ceili(l.end.y), "a zone change cuts (limits %d, zone %s)" % [cam.limit_bottom, rc.zone])
	check(rc.get_room_transition(MDSRoomCamera.Transition.SLIDE) == MDSRoomCamera.Transition.CUT, "and room slides become cuts")
	rc.transition_style = MDSRoomCamera.Motion.GLIDE

func _cancel() -> void:
	await place_player(Vector2(600, 900))
	director.focus_on(player, 2.0, 5.0)
	await wait(0.2)
	director.cancel()
	await frames(2)
	check(not director.is_overriding(), "cancel() gives the camera back at once")
	check_at_rest("after cancel")

# --- World ------------------------------------------------------------------------------------------

func _build_world() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := MDSWorld.new()
	world.path = WORLD
	var id := world.add_room("Hall", HALL[0])
	world.add_rect(id, HALL[1])
	var root := Node2D.new()
	root.name = "Hall"
	save_scene(root, DIR + "/hall.tscn")
	root.free()
	world.set_room_scene(id, DIR + "/hall.tscn")
	world.set_start_room(id)
	world.save()
	MDSWorld._cache.erase(WORLD)

func _make_game(backend: MDSRoomCamera.Backend) -> void:
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
	rc.backend = backend
	rc.use_world_settings = false
	rc.room_transition = MDSRoomCamera.Transition.CUT
	game.add_child(rc)
	game.room_camera = rc
	director = MDSCameraDirector.new()
	director.name = "Director"
	rc.add_child(director)
	game.ready.connect(func() -> void: cam = rc.camera)
