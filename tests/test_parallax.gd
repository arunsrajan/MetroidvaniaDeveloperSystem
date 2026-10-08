extends "res://tests/test_case.gd"
## Parallax backgrounds (MDSParallaxBackground, MDSParallaxLayer): presets, layers following the
## camera, specs and checks (MDSEnvironment), undo copies, the room's or area's background in
## MDSWorldGame and the Room view, and pictures dropped on one.

const Fixture := preload("res://tests/game_fixture.gd")
const PICTURE := "res://addons/MetroidvaniaDeveloperSystem/assets/environment/parallax.svg"

func _run() -> void:
	await _presets()
	await _layers()
	_scrolling()
	await _follows_camera()
	_data()
	_specs()
	_validator()
	await _in_game()
	await _canvas()

func _presets() -> void:
	var bg := MDSEnvironment.create("parallax") as MDSParallaxBackground
	check(bg != null and bg.get_effect_id() == "parallax" and MDSEnvironment.icon("parallax") != null, "parallax is an effect with an icon")
	check(bg.z_index == -100, "it draws behind the room (z %d)" % bg.z_index)
	check(not MDSEnvironment.ambient_ids().has("parallax"), "it isn't weather covering every room")
	bg.free()
	check(MDSParallaxBackground.PRESET_IDS.size() == MDSParallaxBackground.Preset.size() and MDSParallaxBackground.PRESET_NAMES.size() == MDSParallaxBackground.PRESET_IDS.size(), "an id and a name per preset")
	var real_renderer := DisplayServer.get_name() != "headless"
	for i in range(1, MDSParallaxBackground.PRESET_IDS.size()):
		var id := MDSParallaxBackground.PRESET_IDS[i]
		var list := MDSParallaxBackground.layers_of(i as MDSParallaxBackground.Preset)
		check(list.size() >= 3 and list[0].kind == MDSParallaxLayer.Kind.SKY and list[0].scroll_scale == Vector2.ZERO, "%s starts with a sky that stays put (%d layers)" % [id, list.size()])
		var far_to_near := true
		for k in range(1, list.size()):
			far_to_near = far_to_near and list[k].scroll_scale.x >= list[k - 1].scroll_scale.x
		check(far_to_near, "%s: farthest first (the nearer, the more it moves)" % id)
		var p := MDSParallaxBackground.new()
		check(p.use_preset(id) and p.preset == i and p.layers.size() == list.size(), "use_preset(%s)" % id)
		add_child(p)
		await get_tree().process_frame
		check(p.get_materials().size() == list.size() and p.get_child_count() == 0, "%s: a quad per layer, internal" % id)
		if real_renderer:
			check(p.get_materials()[0].shader.get_shader_uniform_list().size() > 10, "the layer shader compiles")
		p.free()
	var bg2 := MDSParallaxBackground.new()
	check(not bg2.use_preset("bogus") and not bg2.use_preset("custom") and bg2.preset == MDSParallaxBackground.Preset.DUSK_MOUNTAINS, "an unknown preset is refused")
	bg2.free()

func _layers() -> void:
	var bg := MDSParallaxBackground.new()
	bg.preset = MDSParallaxBackground.Preset.RUINED_CITY
	add_child(bg)
	await get_tree().process_frame
	var m: ShaderMaterial = bg.get_materials()[2]
	bg.layers[2].color = Color.RED
	bg.layers[2].horizon = 0.5
	await get_tree().process_frame
	m = bg.get_materials()[2]
	check(m.get_shader_parameter("color") == Color.RED, "a layer's change reaches its shader")
	check_near(float(m.get_shader_parameter("base_y")), bg.size.y * 0.5, 0.01, "its horizon is a share of the height")
	check(int(m.get_shader_parameter("kind")) == int(bg.layers[2].kind), "and its kind")
	var tex: Texture2D = load(PICTURE)
	var n := bg.layers.size()
	var l := bg.add_picture(tex)
	await get_tree().process_frame
	check(bg.preset == MDSParallaxBackground.Preset.CUSTOM and bg.layers.size() == n + 1 and bg.layers[-1] == l, "add_picture adds the nearest layer and makes it custom")
	check(l.kind == MDSParallaxLayer.Kind.PICTURE and l.picture == tex and bg.get_materials().size() == n + 1, "drawn from the picture")
	check((bg.get_materials()[-1].get_shader_parameter("picture_size") as Vector2) == Vector2(tex.get_size()), "its size reaches the shader")
	var old := bg.layers[0]
	var list := bg.layers.duplicate()
	list.remove_at(0)
	bg.layers = list
	await get_tree().process_frame
	check(bg.get_materials().size() == n and not old.changed.is_connected(bg._changed), "removing a layer rebuilds and lets it go")
	bg.free()

func _scrolling() -> void:
	var bg := MDSParallaxBackground.new()
	bg.size = Vector2(1000, 600)
	var far := MDSParallaxLayer.make(MDSParallaxLayer.Kind.MOUNTAINS, {"scroll_scale": Vector2(0.2, 0.1)})
	var cam := Vector2(700, 300)
	check(bg.layer_offset(far, cam).is_equal_approx(Vector2(160, 0)), "a far layer moves a fifth as far as the camera (%s)" % bg.layer_offset(far, cam))
	check(bg.layer_offset(MDSParallaxLayer.make(MDSParallaxLayer.Kind.SKY, {"scroll_scale": Vector2.ZERO}), Vector2(900, 100)).is_equal_approx(Vector2(400, -200)), "scroll 0 stays on the screen")
	check(bg.layer_offset(MDSParallaxLayer.make(MDSParallaxLayer.Kind.HILLS, {"scroll_scale": Vector2.ONE}), Vector2(900, 100)) == Vector2.ZERO, "scroll 1 moves with the room")
	check(bg.layer_offset(far, Vector2(500, 300)) == Vector2.ZERO, "everything lines up with the camera in the middle")
	check(bg.view_rect() == bg.get_effect_rect(), "out of the tree its view is its rectangle")
	bg.free()

func _follows_camera() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var bg := MDSParallaxBackground.new()
	bg.position = Vector2(-200, -100)
	holder.add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(3000, 900)
	holder.add_child(cam)
	cam.make_current()
	for i in 3:
		await get_tree().process_frame
	var view := bg.view_rect()
	check(view.get_center().is_equal_approx(cam.position - bg.position), "its view is around the camera (%s)" % view)
	var quad: Polygon2D = bg._layer_quads[1]
	var covered := Rect2(quad.polygon[0], quad.polygon[2] - quad.polygon[0])
	check(covered.encloses(view), "in the game every layer covers the view, wherever the camera is (%s)" % covered)
	var m := bg.get_materials()[1]
	check((m.get_shader_parameter("offset") as Vector2).is_equal_approx(bg.layer_offset(bg.layers[1], view.get_center())), "and is offset for it")
	bg.follow_camera = false
	await get_tree().process_frame
	covered = Rect2(quad.polygon[0], quad.polygon[2] - quad.polygon[0])
	check(covered.is_equal_approx(bg.get_effect_rect()), "follow_camera off: only its rectangle")
	holder.free()

func _data() -> void:
	var bg := MDSParallaxBackground.new()
	bg.preset = MDSParallaxBackground.Preset.DESERT_DUNES
	bg.layers[1].color = Color.RED
	var d := bg.to_data()
	bg.layers[1].color = Color.BLUE
	check((d.props.layers[1] as MDSParallaxLayer).color == Color.RED, "a snapshot keeps its own copy of the layers")
	MDSEnvironmentEffect.apply_data(bg, d)
	check(bg.layers[1].color == Color.RED and bg.preset == MDSParallaxBackground.Preset.DESERT_DUNES, "restoring it undoes a layer's change")
	var copy := MDSEnvironmentEffect.from_data(d) as MDSParallaxBackground
	check(copy.layers.size() == bg.layers.size() and copy.layers[1].color == Color.RED and copy.layers[1] != bg.layers[1], "from_data makes its own layers")
	var first := bg.layers[0]
	MDSEnvironmentEffect.apply_data(bg, bg.to_data())
	check(bg.layers[0] == first, "restoring the same settings leaves the layers alone")
	bg.free()
	copy.free()

func _specs() -> void:
	check(MDSEnvironment.parallax_spec("dusk_mountains") == "parallax(preset=dusk_mountains)", "a preset id is a parallax spec")
	check(MDSEnvironment.parallax_spec(" Misty Forest ") == "parallax(preset=misty_forest)", "its name too")
	check(MDSEnvironment.parallax_spec("res://bg.tscn") == "res://bg.tscn" and MDSEnvironment.parallax_spec("none") == "none" and MDSEnvironment.parallax_spec("") == "", "scenes, none and nothing stay")
	check(MDSEnvironment.check_parallax("").is_empty() and MDSEnvironment.check_parallax("none").is_empty() and MDSEnvironment.check_parallax("night_sky").is_empty(), "good values have no problem")
	check(MDSEnvironment.check_parallax("parallax(preset=volcanic, seed_value=4)").is_empty(), "nor a spec with settings")
	check(MDSEnvironment.check_parallax("nightsky").contains("not a parallax preset"), "a mistyped preset is reported")
	check(not MDSEnvironment.check_parallax("res://nowhere.tscn").is_empty(), "and a missing scene")
	var room := Rect2(0, 0, 1152, 648)
	check(MDSEnvironment.build_parallax("none", room) == null and MDSEnvironment.build_parallax("", room) == null, "none builds nothing")
	var node := MDSEnvironment.build_parallax("volcanic", room)
	var fx := MDSEnvironment.effects_in(node)
	check(node.name == "MDSParallax" and fx.size() == 1 and fx[0] is MDSParallaxBackground, "build_parallax makes the background node")
	check((fx[0] as MDSParallaxBackground).preset == MDSParallaxBackground.Preset.VOLCANIC, "of the preset")
	check(Rect2(fx[0].position, fx[0].size).encloses(room), "covering the room")
	node.free()
	var world := Fixture.build()
	world.set_setting("parallax", "night_sky")
	world.set_area_value("Gardens", "parallax", "misty_forest")
	world.set_room_value("Garden_02", "parallax", "none")
	world.set_room_value("Crypt_01", "parallax", "deep_cavern")
	check(MDSEnvironment.parallax_for_room(world, "Garden_01") == "misty_forest", "a room has its area's background")
	check(MDSEnvironment.parallax_for_room(world, "Garden_02") == "none", "or none")
	check(MDSEnvironment.parallax_for_room(world, "Crypt_01") == "deep_cavern", "or its own")
	world.set_room_value("Crypt_01", "parallax", "")
	check(MDSEnvironment.parallax_for_room(world, "Crypt_01") == "night_sky", "else the world's")

func _validator() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "parallax", "misty forrest")
	world.set_room_value("Crypt_01", "parallax", "res://nowhere.tscn")
	var analysis := MDSAnalysis.new(MDSGraph.from_world(world, {}), world, {}).run()
	var messages: Array = MDSWorldValidator.run(world, analysis, {}).map(func(i: Dictionary) -> String: return i.message)
	check(messages.any(func(m: String) -> bool: return m.contains("Gardens's parallax background") and m.contains("misty forrest")), "the Issues tab reports an area's mistyped background")
	check(messages.any(func(m: String) -> bool: return m.contains("parallax background") and m.contains("nowhere.tscn")), "and a room's missing scene")

func _in_game() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "parallax", "misty_forest")
	world.set_room_value("Garden_02", "parallax", "none")
	world.set_setting("parallax", "night_sky")
	world.save()
	MDSWorld._cache.erase(Fixture.WORLD)
	var game := Fixture.make_game()
	add_child(game)
	await game.room_loaded
	var fx := MDSEnvironment.effects_in(game.parallax) if game.parallax else []
	check(game.parallax != null and game.parallax.get_parent() == game.room_node, "Garden_01 gets its area's background, in the room")
	check(fx.size() == 1 and (fx[0] as MDSParallaxBackground).preset == MDSParallaxBackground.Preset.MISTY_FOREST, "the misty forest")
	await get_tree().process_frame
	var bg := fx[0] as MDSParallaxBackground if not fx.is_empty() else null
	if bg:
		var quad: Polygon2D = bg._layer_quads[0]
		check(Rect2(quad.polygon[0], quad.polygon[2] - quad.polygon[0]).encloses(bg.view_rect()), "covering what the camera sees")
	game.load_room("Garden_02", "left1")
	await game.room_loaded
	check(game.parallax == null and game.room_node.get_node_or_null("MDSParallax") == null, "a room set to none has none")
	game.load_room("Crypt_01", "left1")
	await game.room_loaded
	fx = MDSEnvironment.effects_in(game.parallax) if game.parallax else []
	check(fx.size() == 1 and (fx[0] as MDSParallaxBackground).preset == MDSParallaxBackground.Preset.NIGHT_SKY, "the Crypt has the world's")
	game.queue_free()
	await get_tree().process_frame
	var plain := Fixture.make_game()
	plain.room_parallax = false
	add_child(plain)
	await plain.room_loaded
	check(plain.parallax == null, "room_parallax off: none")
	plain.queue_free()
	await get_tree().process_frame

func _canvas() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "parallax", "dusk_mountains")
	var painter := MDSRoomPainter.open(world.get_scene_path("Garden_01"))
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(800, 500)
	add_child(canvas)
	canvas.open(world, "Garden_01", painter)
	var preview := canvas.get_parallax_preview()
	check(preview != null and preview.get_index() == 0 and MDSEnvironment.effects_in(preview).size() == 1, "the Room view shows the area's background behind the room")
	check(painter.effects().is_empty() and preview.get_parent() != painter.items_root, "as a preview, not part of the room")
	world.set_area_value("Gardens", "parallax", "volcanic")
	canvas.refresh_weather()
	preview = canvas.get_parallax_preview()
	check(preview != null and (MDSEnvironment.effects_in(preview)[0] as MDSParallaxBackground).preset == MDSParallaxBackground.Preset.VOLCANIC, "and follows the Areas tab")
	canvas.set_parallax_preview(false)
	await get_tree().process_frame
	check(canvas.get_parallax_preview() == null, "it can be hidden")
	# A picture dropped on a parallax background in the room becomes its nearest layer.
	canvas.tool = MDSRoomCanvas.Tool.EFFECT
	canvas._drop_data(Vector2(100, 100), {"type": MDSRoomCanvas.DRAG_EFFECT, "effect": "parallax"})
	var bg := canvas.selected_effect as MDSParallaxBackground
	check(bg != null and painter.effects().size() == 1, "a parallax background can be dropped in the room")
	var n := bg.layers.size() if bg else 0
	var traced: Array = []
	canvas.image_dropped.connect(func(p: String) -> void: traced.append(p))
	canvas._drop_data(Vector2(100, 100), {"type": "files", "files": [PICTURE]})
	check(bg.layers.size() == n + 1 and bg.layers[-1].picture == load(PICTURE), "a picture dropped on it is added as a layer")
	check(traced.is_empty(), "instead of being traced")
	painter.undo()
	var again := painter.effects()[0] as MDSParallaxBackground if not painter.effects().is_empty() else null
	check(again != null and again.layers.size() == n, "undo takes the layer out")
	canvas.tool = MDSRoomCanvas.Tool.TERRAIN
	canvas._drop_data(Vector2(100, 100), {"type": "files", "files": [PICTURE]})
	check(traced == [PICTURE] and again.layers.size() == n, "with another tool a dropped picture is traced")
	canvas.close()
	canvas.queue_free()
	painter.free_instance()
