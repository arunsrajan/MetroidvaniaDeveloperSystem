extends "res://tests/test_case.gd"
## The Full view of a big world loads as it goes, never all at once: zoomed out, rooms show their
## pictures (else their outlines) and no scene; zoomed in, the scenes of the rooms in view come in
## a few a frame, the nearest the middle first; panning away lets them go for their pictures; a
## room with a painter always shows its tiles. The world asks the file system whether a room's
## scene is there at most every couple of seconds, and again as soon as it changes.

const DIR := TMP + "/full_view_loading"
const COLS := 8
const ROWS := 5

var world: MDSWorld
var view: MDSRoomView
var canvas: MDSRoomCanvas

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	world = MDSWorld.new()
	world.path = DIR + "/loading.mdsworld.json"
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	var room := world.get_default_room_size()
	for y in ROWS:
		for x in COLS:
			var id := world.add_room("R%d_%d" % [x, y], Rect2(Vector2(x, y) * room, room), 0)
			MDSWorldSceneTools.create_scene_for_room(world, id, DIR + "/r%d_%d.tscn" % [x, y])
	_scene_files()
	view = MDSRoomView.new()
	view.size = Vector2(1400, 900)
	add_child(view)
	await get_tree().process_frame
	canvas = view.canvas
	check(view.open_full(world, 0).is_empty() and canvas._context.size() == COLS * ROWS, "the Full view opens on %d rooms" % canvas._context.size())
	check(_live().is_empty(), "with no scene loaded yet: they come in from the next frame on")
	await _zoomed_out()
	await _zoomed_in()
	await _panned_away()
	await _painter_room()
	view.close_room(false)
	check(canvas._context.is_empty() and not canvas.is_full_loading(), "closing lets go of them all")
	MDSRoomPictures.forget()
	view.queue_free()
	await get_tree().process_frame

func _scene_files() -> void:
	var path := world.get_scene_path("R0_0")
	check(not path.is_empty() and world.scene_file_exists(path), "a room's scene is there")
	var moved := ProjectSettings.globalize_path(path) + ".moved"
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), moved)
	check(world.get_scene_path("R0_0") == path, "asked again only every couple of seconds (each ask is a file system call)")
	world.set_origin("R0_0", world.get_origin("R0_0"))
	check(world.get_scene_path("R0_0").is_empty(), "and at once after the world changed: gone")
	DirAccess.rename_absolute(moved, ProjectSettings.globalize_path(path))
	world.set_origin("R0_0", world.get_origin("R0_0"))
	check(world.get_scene_path("R0_0") == path, "back")

## Looks at the world's (x, y) at [param zoom].
func _look(at: Vector2, zoom: float) -> void:
	canvas.zoom = zoom
	canvas.pan = canvas.size / 2.0 - canvas.world_to_local(at) * zoom
	canvas._apply_view()

func _settle() -> void:
	for i in 600:
		await get_tree().process_frame
		if not canvas.is_full_loading():
			return
	check(false, "the Full view settles")

func _live() -> Array:
	return canvas._context.keys().filter(func(id: String) -> bool: return canvas.is_room_live(id))

func _middle(id: String) -> Vector2:
	return world.get_room_bounds(id).get_center()

func _zoomed_out() -> void:
	_look(_middle("R3_2"), 0.05)
	await _settle()
	check(_live().is_empty(), "zoomed out, no room's scene is loaded")
	check(canvas._context.keys().all(func(id: String) -> bool: return canvas.shown_picture(id) == null), "no picture drawn yet (none can be without a renderer): outlines")
	# Pictures made before (the World map's, the game's): shown in place of the scenes.
	for id in ["R0_0", "R1_0"]:
		var img := Image.create(64, 36, false, Image.FORMAT_RGBA8)
		img.fill(Color.ORANGE)
		MDSRoomPictures.store(world.get_scene_path(id), img, false)
	view.refresh_full()
	await _settle()
	var pic := canvas.shown_picture("R0_0")
	var r := MDSRoomPictures.room_rect(world, "R0_0")
	check(pic != null and canvas.shown_picture("R1_0") != null and canvas.shown_picture("R2_0") == null, "rooms with a picture show it")
	check(pic != null and pic.position.is_equal_approx(r.position) and (pic.scale * pic.texture.get_size()).is_equal_approx(r.size), "over the whole room (%s)" % r)
	check(_live().is_empty(), "still no scene")

func _zoomed_in() -> void:
	_look(_middle("R3_2"), 0.3)
	await get_tree().process_frame
	check(canvas.is_room_live("R3_2"), "zoomed in, the room in the middle of the view comes first")
	await _settle()
	var live := _live()
	check(live.has("R2_2") and live.has("R4_2") and live.has("R3_1") and live.has("R3_3"), "then the rooms around it (%d)" % live.size())
	check(not live.has("R0_0") and not live.has("R7_4") and live.size() < COLS * ROWS, "not the far ones (canvas %s, %s)" % [canvas.size, live])
	check(live.size() <= MDSRoomCanvas.FULL_MAX_LIVE, "never more than %d" % MDSRoomCanvas.FULL_MAX_LIVE)
	check(live.has("R1_0") and canvas.shown_picture("R1_0") == null, "a room with a picture shows its scene once near")
	check(canvas.shown_picture("R0_0") != null, "the room further out keeps its picture")
	var shown := (canvas._context["R3_2"] as Node2D).get_child(0)
	check(shown.get_meta(&"fake_map", false) and shown.process_mode == Node.PROCESS_MODE_DISABLED, "its scene is shown, not run")

func _panned_away() -> void:
	_look(world.get_room_bounds("R7_4").end + Vector2(20000, 20000), 0.3)
	await _settle()
	check(_live().is_empty(), "panned far away, the rooms let go of their scenes")
	check(canvas.shown_picture("R1_0") != null and canvas.shown_picture("R0_0") != null, "those with a picture show it again")
	check((canvas._context["R3_2"] as Node2D).get_child_count() == 0, "the others their outlines")

func _painter_room() -> void:
	_look(_middle("R3_2"), 0.3)
	await _settle()
	check(view.activate_room("R3_2") and view.room_id == "R3_2", "a room is edited")
	check(view.activate_room("R4_2") and view.room_id == "R4_2", "then another")
	_look(_middle("R3_2"), 0.05)
	await _settle()
	check(canvas.is_room_live("R3_2") and view._painters["R3_2"].layers.Terrain.get_parent() == canvas._context["R3_2"], "zoomed out, a room with a painter still shows its tiles")
	check(_live() == ["R3_2"], "the only one (%s)" % [_live()])
