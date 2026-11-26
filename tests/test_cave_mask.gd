extends "res://tests/test_case.gd"
## The cave's open air (MDSCaveMask): which cells are open, the mask texture, effects clipped to
## it (every effect's shader, following the effect as it moves), in the Room view and in the game.

const Fixture := preload("res://tests/game_fixture.gd")

func _run() -> void:
	_cells()
	_notched()
	_effects()
	await _canvas()
	_game()

func _cells() -> void:
	var world := MDSWorld.new()
	world.add_room("R", Rect2(0, 0, 160, 96))
	var terrain := TileMapLayer.new()
	terrain.tile_set = MDSTilesetFactory.get_or_create()
	var ts := Vector2(terrain.tile_set.tile_size)
	var fresh := MDSCaveMask.build(world, "R", terrain)
	var want := int(160.0 / ts.x) * int(96.0 / ts.y)
	check(fresh != null and fresh.shape.size() == want and fresh.open.size() == want, "a room with no Terrain is open all over (%d of %d)" % [fresh.open.size() if fresh else -1, want])
	for x in 3:
		terrain.set_cell(Vector2i(x, 0), 0, Vector2i.ZERO)
	var m := MDSCaveMask.build(world, "R", terrain)
	check(m.open.size() == want - 3 and not m.open.has(Vector2i(1, 0)) and m.open.has(Vector2i(4, 2)), "Terrain tiles are rock")
	check(m.is_open(Vector2(4.5, 2.5) * ts) and not m.is_open(Vector2(1.5, 0.5) * ts) and not m.is_open(Vector2(-20, 10)), "is_open: air, rock, outside")
	var img := m.texture.get_image()
	var origin := m.rect.position / ts
	check(img.get_size() == Vector2i(int(160.0 / ts.x) + 2, int(96.0 / ts.y) + 2), "one pixel per cell, a closed cell around (%s)" % img.get_size())
	check(m.rect.position.is_equal_approx(-ts) and m.rect.size.is_equal_approx(Vector2(img.get_size()) * ts), "the mask covers the room and one cell more (%s)" % m.rect)
	check(img.get_pixelv(Vector2i(4, 2) - Vector2i(origin)).r > 0.9 and img.get_pixelv(Vector2i(1, 0) - Vector2i(origin)).r < 0.1 and img.get_pixel(0, 0).r < 0.1, "white where open, black on rock and around")
	terrain.free()

func _notched() -> void:
	var world := MDSWorld.new()
	# An L: the top right corner is not in the room.
	world.add_room("L", Rect2(0, 0, 320, 160))
	world.data.rooms["L"]["rects"] = [[0, 0, 320, 80], [0, 80, 160, 80]]
	var ts := Vector2(MDSTilesetFactory.get_or_create().tile_size)
	var m := MDSCaveMask.build(world, "L", null, ts)
	check(m.is_open(Vector2(40, 120)) and m.is_open(Vector2(300, 40)) and not m.is_open(Vector2(300, 120)), "the notch of an L-shaped room is not open")

func _effects() -> void:
	var world := MDSWorld.new()
	world.add_room("R", Rect2(0, 0, 640, 320))
	var m := MDSCaveMask.build(world, "R", null)
	var space := Node2D.new()
	add_child(space)
	for id in MDSEnvironment.effect_ids():
		var e := MDSEnvironment.create(id)
		space.add_child(e)
		e.set_cave_mask(m.texture, m.rect, space)
		var all_on := e.get_materials().all(func(mat: ShaderMaterial) -> bool: return mat.get_shader_parameter("cave_on") == true and mat.get_shader_parameter("cave_mask") == m.texture)
		check(all_on and e.is_clipped_to_cave(), "%s is clipped to the cave" % id)
		e.rebuild()
		check(e.get_materials().all(func(mat: ShaderMaterial) -> bool: return mat.get_shader_parameter("cave_on") == true), "%s keeps it when its parts are made again" % id)
		e.free()
	var shader_text := FileAccess.get_file_as_string("res://addons/MetroidvaniaDeveloperSystem/shaders/environment/fog.gdshader")
	check(shader_text.contains("env_cave(px)"), "the shaders multiply by the mask")
	for f in DirAccess.get_files_at("res://addons/MetroidvaniaDeveloperSystem/shaders/environment"):
		if f.ends_with(".gdshader") and not f.begins_with("machinery_"):
			check(FileAccess.get_file_as_string("res://addons/MetroidvaniaDeveloperSystem/shaders/environment/" + f).contains("env_cave(px)"), "%s draws only in the cave" % f)
	# The mask stays on the room as the effect moves.
	var fog := MDSEnvironment.create("fog")
	space.add_child(fog)
	fog.set_cave_mask(m.texture, m.rect, space)
	var r0: Vector4 = fog.get_materials()[0].get_shader_parameter("cave_rect")
	check(is_equal_approx(r0.x, m.rect.position.x) and is_equal_approx(r0.z, m.rect.size.x), "the mask's rectangle in the effect's coordinates (%s)" % r0)
	fog.position = Vector2(100, 50)
	var r1: Vector4 = fog.get_materials()[0].get_shader_parameter("cave_rect")
	check(is_equal_approx(r1.x, m.rect.position.x - 100.0) and is_equal_approx(r1.y, m.rect.position.y - 50.0), "follows the effect as it moves (%s)" % r1)
	fog.clip_to_cave = false
	check(fog.get_materials()[0].get_shader_parameter("cave_on") == false and not fog.is_clipped_to_cave(), "Clip To Cave off draws it whole")
	fog.clip_to_cave = true
	fog.clear_cave_mask()
	check(fog.get_materials()[0].get_shader_parameter("cave_on") == false, "without a mask it is whole")
	var data := fog.to_data()
	check(data.props.has("clip_to_cave") and data.props.has("depth"), "clip_to_cave and depth are saved")
	space.free()

func _canvas() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "weather", "fog")
	var painter := MDSRoomPainter.open(world.get_scene_path("Garden_01"))
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(800, 500)
	add_child(canvas)
	canvas.open(world, "Garden_01", painter)
	check(canvas.cave_mask != null, "the Room view makes the room's open air")
	var preview := canvas.get_weather_preview()
	check(preview != null and MDSEnvironment.effects_in(preview).all(func(e: MDSEnvironmentEffect) -> bool: return e.is_clipped_to_cave()), "the weather preview is clipped to it")
	var fx := canvas.place_effect("embers", Vector2(300, 300)) as MDSEnvironmentEffect
	check(fx.is_clipped_to_cave(), "a placed effect too")
	var open_before := canvas.cave_mask.open.size()
	painter.layers["Terrain"].set_cell(painter.cell_at("Terrain", Vector2(300, 300)), 0, Vector2i.ZERO)
	canvas.painted.emit()
	await get_tree().process_frame
	check(canvas.cave_mask.open.size() == open_before - 1 and not canvas.cave_mask.is_open(Vector2(300, 300)), "painting Terrain makes the open air again")
	canvas.set_clip_effects(false)
	check(canvas.cave_mask == null and not fx.is_clipped_to_cave() and not MDSEnvironment.effects_in(canvas.get_weather_preview()).front().is_clipped_to_cave(), "clipping can be turned off")
	canvas.set_clip_effects(true)
	check(fx.is_clipped_to_cave(), "and on again")
	canvas.close()
	canvas.queue_free()
	painter.free_instance()
	await get_tree().process_frame

func _game() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "weather", "fog")
	var room: Node2D = (load(world.get_scene_path("Garden_01")) as PackedScene).instantiate()
	add_child(room)
	var terrain := MDSCaveMask.terrain_of(room)
	var game := MDSWorldGame.new()
	game.world = world
	game._apply_weather(room, "Garden_01")
	game._clip_to_cave(room, "Garden_01")
	var fx := MDSEnvironment.effects_in(room)
	check(not fx.is_empty() and fx.all(func(e: MDSEnvironmentEffect) -> bool: return e.is_clipped_to_cave()), "the game clips the room's weather to the cave (%d effects)" % fx.size())
	var m := MDSCaveMask.build(world, "Garden_01", terrain)
	check(m != null and m.shape.size() > 0, "from the room's Terrain")
	game.free()
	room.free()
