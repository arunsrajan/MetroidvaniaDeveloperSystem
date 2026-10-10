extends "res://tests/test_case.gd"
## Animated backgrounds (MDSAnimatedBackground): the styles and their looks, the shader, saving
## a style's settings, specs and checks (MDSEnvironment), the room's, area's, boss rooms' and
## world's background in MDSWorldGame and the Room view, and pictures dropped on one.

const Fixture := preload("res://tests/game_fixture.gd")
const PICTURE := "res://addons/MetroidvaniaDeveloperSystem/assets/environment/animated_background.svg"
const DIR := "res://tests/tmp/animated_background"

func _run() -> void:
	await _styles()
	await _params()
	await _saved()
	_data()
	_specs()
	_rooms()
	_validator()
	await _in_game()
	await _canvas()

func _styles() -> void:
	var bg := MDSEnvironment.create("animated_background") as MDSAnimatedBackground
	check(bg != null and bg.get_effect_id() == "animated_background" and MDSEnvironment.icon("animated_background") != null, "animated_background is an effect with an icon")
	var parallax := MDSParallaxBackground.new()
	check(bg.z_index == -110 and bg.z_index < parallax.z_index, "it draws behind the parallax background (z %d)" % bg.z_index)
	parallax.free()
	check(not MDSEnvironment.ambient_ids().has("animated_background"), "it isn't weather covering every room")
	bg.free()
	var n := MDSAnimatedBackground.Style.size()
	check(n >= 15 and n <= 20, "%d styles" % n)
	check(MDSAnimatedBackground.STYLE_IDS.size() == n and MDSAnimatedBackground.STYLE_NAMES.size() == n and MDSAnimatedBackground.STYLE_INFO.size() == n, "an id, a name and a description per style")
	check(MDSAnimatedBackground.LOOKS.size() == n and Array(MDSAnimatedBackground.STYLE_IDS).all(func(id: String) -> bool: return MDSAnimatedBackground.LOOKS.has(id)), "and a look")
	check(MDSAnimatedBackground.BOSS_STYLES.size() >= 4 and Array(MDSAnimatedBackground.BOSS_STYLES).all(func(id: String) -> bool: return MDSAnimatedBackground.STYLE_IDS.has(id)), "some are made for boss rooms")
	check(MDSAnimatedBackground.is_boss_style("blood_moon") and MDSAnimatedBackground.is_boss_style(" Void_Pulse ") and not MDSAnimatedBackground.is_boss_style("bokeh"), "is_boss_style")
	var real_renderer := DisplayServer.get_name() != "headless"
	for i in n:
		var id := MDSAnimatedBackground.STYLE_IDS[i]
		var b := MDSAnimatedBackground.new()
		var look: Dictionary = MDSAnimatedBackground.LOOKS[id]
		if i == 0:
			b.style = MDSAnimatedBackground.Style.AURORA
		check(b.use_style(id) and b.style == i, "use_style(%s)" % id)
		check(b.color_a == look.color_a and b.color_c == look.color_c and is_equal_approx(b.blur, look.blur) and is_equal_approx(b.pulse, look.pulse), "%s gets its look" % id)
		add_child(b)
		await get_tree().process_frame
		check(b.get_materials().size() == 1 and b.get_child_count() == 0, "%s: one quad, internal" % id)
		check(int(b.get_materials()[0].get_shader_parameter("style")) == i, "%s: the shader draws it" % id)
		if real_renderer:
			check(b.get_materials()[0].shader.get_shader_uniform_list().size() > 15, "the shader compiles")
		b.free()
	var b2 := MDSAnimatedBackground.new()
	check(not b2.use_style("bogus") and b2.style == MDSAnimatedBackground.Style.BOKEH, "an unknown style is refused")
	check(b2.use_style("Blood Moon") and b2.style == MDSAnimatedBackground.Style.BLOOD_MOON, "a style's name works too")
	b2.blur = 0.1
	b2.style = MDSAnimatedBackground.Style.BLOOD_MOON
	check(is_equal_approx(b2.blur, 0.1), "picking the same style again keeps the changes")
	b2.free()

func _params() -> void:
	var bg := MDSAnimatedBackground.new()
	add_child(bg)
	await get_tree().process_frame
	var m: ShaderMaterial = bg.get_materials()[0]
	bg.color_c = Color.RED
	bg.blur = 0.9
	bg.speed = 2.5
	bg.pulse = 0.7
	bg.picture = load(PICTURE)
	check(m.get_shader_parameter("color_c") == Color.RED and is_equal_approx(float(m.get_shader_parameter("blur")), 0.9) and is_equal_approx(float(m.get_shader_parameter("speed")), 2.5), "settings reach the shader")
	check(is_equal_approx(float(m.get_shader_parameter("pulse")), 0.7) and bool(m.get_shader_parameter("has_picture")) and m.get_shader_parameter("picture_size") == Vector2(16, 16), "the pulse and the picture too")
	bg.intensity = 0.4
	check(is_equal_approx(float(m.get_shader_parameter("intensity")), 0.4), "intensity fades it")
	# Following the camera: it moves by its share of the camera's way from its middle.
	var mid := bg.get_effect_rect().get_center()
	bg.scroll_scale = Vector2(0.1, 0.05)
	check(bg.drift_for(mid) == Vector2.ZERO, "no drift with the camera in the middle")
	check_near(bg.drift_for(mid + Vector2(648, 648)).x, 0.1, 0.0001, "a tenth of the way (in view heights) at scroll 0.1")
	check_near(bg.drift_for(mid + Vector2(648, 648)).y, 0.05, 0.0001, "and half that vertically")
	# In the editor it covers its rectangle; in the game the view (follow_camera).
	bg.size = Vector2(400, 300)
	await get_tree().process_frame
	await get_tree().process_frame
	var quad := bg._quad
	check(Rect2(quad.polygon[0], quad.polygon[2] - quad.polygon[0]).encloses(bg.view_rect()), "in the game it covers what the camera sees, not only its rectangle")
	bg.follow_camera = false
	await get_tree().process_frame
	check(Rect2(quad.polygon[0], quad.polygon[2] - quad.polygon[0]).is_equal_approx(bg.get_effect_rect()), "follow_camera off: only its rectangle")
	bg.free()

func _saved() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var root := Node2D.new()
	var bg := MDSAnimatedBackground.new()
	bg.name = "Bg"
	root.add_child(bg)
	bg.owner = root
	bg.style = MDSAnimatedBackground.Style.VOID_PULSE
	bg.pulse = 0.0 # its own throb off (the script's default value)
	bg.blur = 0.6 # the script's default, not the style's
	bg.color_d = Color("#123456")
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, DIR + "/saved.tscn")
	root.free()
	var back := (ResourceLoader.load(DIR + "/saved.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var b := back.get_node("Bg") as MDSAnimatedBackground
	check(b.style == MDSAnimatedBackground.Style.VOID_PULSE and b.color_d == Color("#123456"), "a saved background keeps its style and colors")
	check(is_equal_approx(b.pulse, 0.0) and is_equal_approx(b.blur, 0.6), "and settings changed back to their defaults (not the style's)")
	back.free()

func _data() -> void:
	var bg := MDSAnimatedBackground.new()
	bg.style = MDSAnimatedBackground.Style.AURORA
	bg.speed = 0.3
	var d := bg.to_data()
	bg.style = MDSAnimatedBackground.Style.STARFIELD
	bg.speed = 2.0
	MDSEnvironmentEffect.apply_data(bg, d)
	check(bg.style == MDSAnimatedBackground.Style.AURORA and is_equal_approx(bg.speed, 0.3) and bg.color_c == MDSAnimatedBackground.LOOKS.aurora.color_c, "restoring a snapshot undoes a style change (Room view undo)")
	var copy := MDSEnvironmentEffect.from_data(d) as MDSAnimatedBackground
	check(copy.style == MDSAnimatedBackground.Style.AURORA and is_equal_approx(copy.speed, 0.3), "from_data copies it")
	bg.free()
	copy.free()

func _specs() -> void:
	check(MDSEnvironment.background_spec("aurora") == "animated_background(style=aurora)", "a style id is a background spec")
	check(MDSEnvironment.background_spec(" Blood Moon ") == "animated_background(style=blood_moon)", "its name too")
	check(MDSEnvironment.background_spec("nebula(blur=0.9, speed=0.5)") == "animated_background(style=nebula, blur=0.9, speed=0.5)", "with settings")
	check(MDSEnvironment.background_spec("res://bg.tscn") == "res://bg.tscn" and MDSEnvironment.background_spec("none") == "none" and MDSEnvironment.background_spec("") == "", "scenes, none and nothing stay")
	check(MDSEnvironment.check_background("").is_empty() and MDSEnvironment.check_background("none").is_empty() and MDSEnvironment.check_background("starfield").is_empty(), "good values have no problem")
	check(MDSEnvironment.check_background("animated_background(style=infection, pulse=0.2)").is_empty() and MDSEnvironment.check_background("holy_light(speed=0.5)").is_empty(), "nor specs with settings")
	check(MDSEnvironment.check_background("bloodmoon").contains("not an animated background style"), "a mistyped style is reported")
	check(not MDSEnvironment.check_background("res://nowhere.tscn").is_empty(), "and a missing scene")
	var room := Rect2(0, 0, 1152, 648)
	check(MDSEnvironment.build_background("none", room) == null and MDSEnvironment.build_background("", room) == null, "none builds nothing")
	var node := MDSEnvironment.build_background("deep_water(blur=0.9)", room)
	var fx := MDSEnvironment.effects_in(node)
	check(node.name == "MDSBackground" and fx.size() == 1 and fx[0] is MDSAnimatedBackground, "build_background makes the background node")
	var bg := fx[0] as MDSAnimatedBackground
	check(bg.style == MDSAnimatedBackground.Style.DEEP_WATER and is_equal_approx(bg.blur, 0.9) and bg.color_a == MDSAnimatedBackground.LOOKS.deep_water.color_a, "of the style, its look, then the settings")
	check(Rect2(bg.position, bg.size).encloses(room), "covering the room")
	node.free()

func _rooms() -> void:
	var world := Fixture.build()
	check(MDSEnvironment.background_for_room(world, "Garden_01").is_empty(), "no background by default")
	world.set_setting("background", "starfield")
	world.set_area_value("Gardens", "background", "forest_canopy")
	world.set_room_value("Garden_02", "background", "none")
	check(MDSEnvironment.background_for_room(world, "Garden_01") == "forest_canopy", "a room has its area's background")
	check(MDSEnvironment.background_for_room(world, "Garden_02") == "none", "or none")
	check(MDSEnvironment.background_for_room(world, "Crypt_01") == "starfield", "else the world's")
	check(not MDSEnvironment.is_boss_room(world, "Crypt_01"), "the Crypt isn't a boss room yet")
	world.set_setting("boss_background", "blood_moon")
	check(MDSEnvironment.background_for_room(world, "Crypt_01") == "starfield", "the boss rooms' background is only for boss rooms")
	world.set_room_value("Crypt_01", "boss", "Warden")
	check(MDSEnvironment.is_boss_room(world, "Crypt_01") and MDSEnvironment.background_for_room(world, "Crypt_01") == "blood_moon", "a room naming a boss is a boss room: it gets the boss rooms' background")
	world.set_room_value("Crypt_01", "boss", "")
	world.set_room_value("Crypt_01", "type", "mini_boss")
	check(MDSEnvironment.background_for_room(world, "Crypt_01") == "blood_moon", "so does a mini boss room")
	world.set_area_value("Crypt", "background", "toxic_swamp")
	world.set_area_value("Crypt", "boss_background", "void_pulse")
	check(MDSEnvironment.background_for_room(world, "Crypt_01") == "void_pulse", "its area's boss room background comes first")
	world.set_room_value("Crypt_01", "background", "arcane_vortex")
	check(MDSEnvironment.background_for_room(world, "Crypt_01") == "arcane_vortex", "and the room's own before all")
	world.set_room_value("Crypt_01", "type", "normal")
	world.set_room_value("Crypt_01", "background", "")
	check(MDSEnvironment.background_for_room(world, "Crypt_01") == "toxic_swamp", "an ordinary room has its area's")

func _validator() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "background", "aurorra")
	world.set_area_value("Crypt", "boss_background", "bloodmoon")
	world.set_room_value("Crypt_01", "background", "res://nowhere.tscn")
	world.set_setting("boss_background", "voidpulse")
	var analysis := MDSAnalysis.new(MDSGraph.from_world(world, {}), world, {}).run()
	var messages: Array = MDSWorldValidator.run(world, analysis, {}).map(func(i: Dictionary) -> String: return i.message)
	check(messages.any(func(m: String) -> bool: return m.contains("Gardens's animated background") and m.contains("aurorra")), "the Issues tab reports an area's mistyped background")
	check(messages.any(func(m: String) -> bool: return m.contains("Crypt's boss room background") and m.contains("bloodmoon")), "and its boss room background")
	check(messages.any(func(m: String) -> bool: return m.contains("animated background") and m.contains("nowhere.tscn")), "a room's missing scene")
	check(messages.any(func(m: String) -> bool: return m.contains("world's boss rooms background") and m.contains("voidpulse")), "and the world's")

func _in_game() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "background", "bokeh")
	world.set_area_value("Gardens", "parallax", "misty_forest")
	world.set_room_value("Garden_02", "background", "none")
	world.set_room_value("Crypt_01", "boss", "Warden")
	world.set_setting("boss_background", "blood_moon")
	world.save()
	MDSWorld._cache.erase(Fixture.WORLD)
	var game := Fixture.make_game()
	add_child(game)
	await game.room_loaded
	var fx := MDSEnvironment.effects_in(game.background) if game.background else []
	check(game.background != null and game.background.get_parent() == game.room_node, "Garden_01 gets its area's animated background, in the room")
	check(fx.size() == 1 and (fx[0] as MDSAnimatedBackground).style == MDSAnimatedBackground.Style.BOKEH, "bokeh lights")
	check(game.parallax != null, "next to its parallax background")
	await get_tree().process_frame
	var bg := fx[0] as MDSAnimatedBackground if not fx.is_empty() else null
	if bg:
		check(Rect2(bg._quad.polygon[0], bg._quad.polygon[2] - bg._quad.polygon[0]).encloses(bg.view_rect()), "covering what the camera sees")
	game.load_room("Garden_02", "left1")
	await game.room_loaded
	check(game.background == null and game.room_node.get_node_or_null("MDSBackground") == null, "a room set to none has none")
	game.load_room("Crypt_01", "left1")
	await game.room_loaded
	fx = MDSEnvironment.effects_in(game.background) if game.background else []
	check(fx.size() == 1 and (fx[0] as MDSAnimatedBackground).style == MDSAnimatedBackground.Style.BLOOD_MOON, "the boss room has the boss rooms' background")
	check(game.get_background_value("Crypt_01") == "blood_moon", "get_background_value")
	game.queue_free()
	await get_tree().process_frame
	var plain := Fixture.make_game()
	plain.room_background = false
	add_child(plain)
	await plain.room_loaded
	check(plain.background == null, "room_background off: none")
	plain.queue_free()
	await get_tree().process_frame

func _canvas() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "background", "aurora")
	var painter := MDSRoomPainter.open(world.get_scene_path("Garden_01"))
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(800, 500)
	add_child(canvas)
	canvas.open(world, "Garden_01", painter)
	var preview := canvas.get_background_preview()
	check(preview != null and preview.get_index() == 0 and MDSEnvironment.effects_in(preview).size() == 1, "the Room view shows the area's animated background behind the room")
	check(painter.effects().is_empty() and preview.get_parent() != painter.items_root, "as a preview, not part of the room")
	world.set_area_value("Gardens", "background", "nebula")
	canvas.refresh_weather()
	preview = canvas.get_background_preview()
	check(preview != null and (MDSEnvironment.effects_in(preview)[0] as MDSAnimatedBackground).style == MDSAnimatedBackground.Style.NEBULA, "and follows the Areas tab")
	canvas.set_parallax_preview(false)
	await get_tree().process_frame
	check(canvas.get_background_preview() == null, "it hides with the backgrounds check")
	# A picture dropped on an animated background in the room is shown blurred.
	canvas.tool = MDSRoomCanvas.Tool.EFFECT
	canvas._drop_data(Vector2(100, 100), {"type": MDSRoomCanvas.DRAG_EFFECT, "effect": "animated_background"})
	var bg := canvas.selected_effect as MDSAnimatedBackground
	check(bg != null and painter.effects().size() == 1, "an animated background can be dropped in the room")
	var traced: Array = []
	canvas.image_dropped.connect(func(p: String) -> void: traced.append(p))
	canvas._drop_data(Vector2(100, 100), {"type": "files", "files": [PICTURE]})
	check(bg.style == MDSAnimatedBackground.Style.PICTURE and bg.picture == load(PICTURE), "a picture dropped on it becomes its picture")
	check(traced.is_empty(), "instead of being traced")
	painter.undo()
	check(painter.effects().size() == 1 and (painter.effects()[0] as MDSAnimatedBackground).picture == null, "undo takes the picture back out")
	canvas.close()
	canvas.queue_free()
	painter.free_instance()
	await get_tree().process_frame
