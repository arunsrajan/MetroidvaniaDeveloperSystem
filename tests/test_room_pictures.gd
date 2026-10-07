extends "res://tests/test_case.gd"
## Brief 16: MDSRoomPictures (cache keyed by scene path and save time, background baking of the
## area's rooms, rooms stripped for pictures) and MDSLevelOverview (pictures laid out around the
## live room, the camera pulled back, no slow frame once the pictures exist).
##
## Headless runs have no renderer: there, pictures that would be drawn are stored by the test
## instead, and only the drawing itself goes unchecked. Run this scene without --headless to
## check real pictures too.
##
##   Keep: A (0,0) B (1152,0) on top, C (0,648) 2304 wide under them.   Yard (another area): D.

const DIR := "res://tests/tmp/pictures"
const WORLD := DIR + "/pictures.idpworld.json"

var world: MDSWorld
var game: MDSWorldGame
var rc: MDSRoomCamera
var headless := DisplayServer.get_name() == "headless"

func _run() -> void:
	_build_world()
	MDSRoomPictures.forget()
	MDSRoomPictures.clear_disk()
	_strip()
	_scope()
	await _cache()
	await _background_and_overview()
	if headless:
		print("  (headless: pictures were stored by the test; run without --headless to draw them)")
	MDSRoomPictures.flush()
	MDSRoomPictures.forget()

func path_of(id: String) -> String:
	return world.get_scene_path(id)

func fake_picture(id: String) -> Texture2D:
	var r := MDSRoomPictures.room_rect(world, id)
	var img := Image.create(ceili(r.size.x * MDSRoomPictures.bake_scale), ceili(r.size.y * MDSRoomPictures.bake_scale), false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.3))
	return MDSRoomPictures.store(path_of(id), img)

# --- Stripping and scope ----------------------------------------------------------------------------

func _strip() -> void:
	var inst := (load(path_of("A")) as PackedScene).instantiate()
	MDSRoomPictures.strip_for_preview(inst)
	check(inst.has_meta(&"idp_preview"), "a room copy for a picture is marked as a preview")
	check(inst.get_node_or_null("Guard") == null and inst.get_node_or_null("Cam") == null and inst.get_node_or_null("Hud") == null, "its enemies, cameras and UI are left out")
	check(inst.get_node_or_null("Ground") != null and inst.get_node_or_null("Skip") == null, "its art stays; nodes marked idp_preview_skip don't")
	var sound := inst.get_node("Sound") as AudioStreamPlayer
	check(sound.stream == null and not sound.autoplay, "its sounds are silenced")
	inst.free()

func _scope() -> void:
	var area := MDSRoomPictures.rooms_in_scope(world, "A", MDSRoomPictures.Scope.AREA)
	check(area == ["A", "B", "C"], "the area's rooms are in scope (%s)" % [area])
	check(MDSRoomPictures.rooms_in_scope(world, "A", MDSRoomPictures.Scope.WORLD).size() == 4, "the world's are all four")

# --- The cache --------------------------------------------------------------------------------------

func _cache() -> void:
	check(MDSRoomPictures.is_stale(path_of("A")), "a room never pictured is stale")
	fake_picture("A")
	check(MDSRoomPictures.picture(path_of("A")) != null and not MDSRoomPictures.is_stale(path_of("A")), "a stored picture is there")
	MDSRoomPictures.flush()
	MDSRoomPictures.forget()
	check(MDSRoomPictures.picture(path_of("A")) == null, "forget() empties the memory")
	check(MDSRoomPictures.load_cached(path_of("A")) != null, "and the picture comes back from the disk cache")
	# Editing the room (saving its scene) makes its picture stale, and only its.
	fake_picture("C")
	MDSRoomPictures.flush()
	await get_tree().create_timer(1.1).timeout # file times have a resolution of a second
	_save_room("A", Color(0.8, 0.4, 0.2))
	check(MDSRoomPictures.picture(path_of("A")) == null and MDSRoomPictures.is_stale(path_of("A")), "an edited room's picture is stale")
	check(MDSRoomPictures.picture(path_of("C")) != null, "an unchanged room's isn't")
	if not headless:
		var tex: Texture2D = await MDSRoomPictures.bake(self, path_of("A"), MDSRoomPictures.room_rect(world, "A"))
		check(tex != null and tex.get_size() == Vector2(ceilf(1152 * 0.35), ceilf(648 * 0.35)), "a room is drawn at 0.35 of its size (%s)" % (tex.get_size() if tex else "none"))
		var img := tex.get_image() if tex else null
		check(img and img.get_pixel(int(img.get_width() / 2.0), img.get_height() - 4).a > 0.5, "with its ground in it")
		check(img and img.get_pixel(int(img.get_width() / 2.0), 4).a < 0.1, "on a transparent background")

# --- Background pictures and the overview -----------------------------------------------------------

func _background_and_overview() -> void:
	# A's and C's pictures exist; B was never pictured.
	if headless:
		fake_picture("A")
	_make_game()
	var screen := SubViewport.new()
	screen.size = Vector2i(1152, 648)
	add_child(screen)
	screen.add_child(game)
	var pics := MDSRoomPictures.new()
	pics.name = "Pictures"
	pics.start_delay = 0.0
	pics.bake_gap = 0.05
	var baked: Array = []
	pics.bake_started.connect(func(p: String) -> void: baked.append(p))
	game.add_child(pics)
	await game.room_loaded
	check(pics.stale_rooms() == ["B"], "only the room never pictured needs a picture (%s)" % [pics.stale_rooms()])
	var end := Time.get_ticks_msec() + 3000
	while pics.pending() > 0 and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	check(baked == [path_of("B")], "the background baker draws only that room (%s)" % [baked])
	if headless:
		fake_picture("B")
	else:
		check(MDSRoomPictures.picture(path_of("B")) != null, "and its picture is ready")
	# The overview: every picture is ready, so opening it is cheap.
	var overview := MDSLevelOverview.new()
	overview.name = "Overview"
	overview.pull_time = 0.6
	game.add_child(overview)
	await frames(2)
	var slow := 0.0
	var opened_at := Time.get_ticks_usec()
	overview.open()
	slow = (Time.get_ticks_usec() - opened_at) / 1000.0
	check(MDSLevelOverview.is_open() and overview.pictures.size() == 2 and not overview.pictures.has("A"), "it shows the other rooms of the area, not the live one (%s)" % [overview.pictures.keys()])
	var b: Sprite2D = overview.pictures.get("B")
	check(b and b.texture and b.global_position == Vector2(1152, 0) and (b.texture.get_size() * b.scale).is_equal_approx(Vector2(1152, 648)), "each in its place on the map, at its size")
	check(overview.level_rect.encloses(Rect2(0, 0, 2304, 1296)), "the level is A, B and C (%s)" % overview.level_rect)
	var last := Time.get_ticks_usec()
	var end_pull := Time.get_ticks_msec() + 900
	while Time.get_ticks_msec() < end_pull:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		slow = maxf(slow, (now - last) / 1000.0)
		last = now
	check(slow < 20.0, "no frame over 20 ms while it opens and pulls back (worst %.1f ms)" % slow)
	var cam := rc.camera
	var shown := Rect2(cam.get_screen_center_position() - Vector2(576, 324) / cam.zoom.x, Vector2(1152, 648) / cam.zoom.x)
	check(shown.encloses(Rect2(0, 0, 2304, 1296)), "the camera has pulled back over the whole level (%s)" % shown)
	overview.close()
	check(not MDSLevelOverview.is_open() and overview.pictures.is_empty(), "close() takes the pictures away")
	var director := rc.get_director()
	end = Time.get_ticks_msec() + 4000
	while director.is_overriding() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	await frames(2)
	check(not director.is_overriding() and is_equal_approx(cam.zoom.x, 1.0) and cam.get_screen_center_position().distance_to(rc.rest_centre()) < 3.0, "and the camera returns to the room")
	screen.queue_free()
	await frames(2)

func frames(n := 2) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

# --- World ------------------------------------------------------------------------------------------

func _build_world() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	world = MDSWorld.new()
	world.path = WORLD
	world.data.areas["Keep"] = {"color": "#888888"}
	world.data.areas["Yard"] = {"color": "#448844"}
	world.add_room("A", Rect2(0, 0, 1152, 648), 0, "Keep")
	world.add_room("B", Rect2(1152, 0, 1152, 648), 0, "Keep")
	world.add_room("C", Rect2(0, 648, 2304, 648), 0, "Keep")
	world.add_room("D", Rect2(2304, 0, 1152, 648), 0, "Yard")
	for id in ["A", "B", "C", "D"]:
		world.set_room_scene(id, "%s/room_%s.tscn" % [DIR, id.to_lower()])
		_save_room(id, Color(0.3, 0.6, 0.3))
	world.set_start_room("A")
	world.save()
	MDSWorld._cache.erase(WORLD)

func _save_room(id: String, ground_color: Color) -> void:
	var size := world.get_room_bounds(id).size
	var root := Node2D.new()
	root.name = "Room" + id
	var ground := Polygon2D.new()
	ground.name = "Ground"
	ground.color = ground_color
	ground.polygon = PackedVector2Array([Vector2(0, size.y - 80), Vector2(size.x, size.y - 80), Vector2(size.x, size.y), Vector2(0, size.y)])
	root.add_child(ground)
	var guard := Polygon2D.new()
	guard.name = "Guard"
	guard.add_to_group(&"enemy", true)
	guard.polygon = rect_points(Rect2(200, size.y - 140, 40, 60))
	root.add_child(guard)
	var cam := Camera2D.new()
	cam.name = "Cam"
	root.add_child(cam)
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	root.add_child(hud)
	var skip := Node2D.new()
	skip.name = "Skip"
	skip.set_meta(&"idp_preview_skip", true)
	root.add_child(skip)
	var sound := AudioStreamPlayer.new()
	sound.name = "Sound"
	sound.autoplay = true
	sound.stream = AudioStreamWAV.new()
	root.add_child(sound)
	save_scene(root, "%s/room_%s.tscn" % [DIR, id.to_lower()])
	root.free()

func _make_game() -> void:
	game = MDSWorldGame.new()
	game.world_file = WORLD
	game.fade_time = 0.0
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group(&"player")
	game.add_child(player)
	game.player = player
	rc = MDSRoomCamera.new()
	rc.name = "RoomCamera"
	rc.backend = MDSRoomCamera.Backend.CAMERA_2D
	rc.use_world_settings = false
	rc.room_transition = MDSRoomCamera.Transition.CUT
	game.add_child(rc)
	game.room_camera = rc
