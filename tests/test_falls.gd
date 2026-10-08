extends "res://tests/test_case.gd"
## Hot water falls (MDSHotWaterfall) and lava falls (MDSLavaFall): in the catalog, their
## rectangles and shaders, the liquids, scalding and burning bodies, and saved in a room.

const ROOM := TMP + "/falls_room.tscn"
const HURTABLE := "extends CharacterBody2D\nvar hurt := 0.0\nvar hits := 0\nfunc take_damage(amount: float) -> void:\n\thurt += amount\n\thits += 1\n"

func _run() -> void:
	await _catalog()
	_layout()
	_liquids()
	await _harm()
	_room()

func _body(at: Vector2, script_source := "") -> CharacterBody2D:
	var b: CharacterBody2D
	if script_source.is_empty():
		b = CharacterBody2D.new()
	else:
		var s := GDScript.new()
		s.source_code = script_source
		s.reload()
		b = s.new()
	b.add_to_group(&"player")
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(20, 40)
	cs.shape = r
	b.add_child(cs)
	b.position = at
	add_child(b)
	return b

func _catalog() -> void:
	var real_renderer := DisplayServer.get_name() != "headless"
	for id in ["hot_waterfall", "lava_fall"]:
		check(MDSEnvironment.effect_ids().has(id) and not MDSEnvironment.ambient_ids().has(id), "%s is an effect placed in a room" % id)
		check(MDSEnvironment.icon(id) != null and MDSEnvironment.icon(id) != MDSEnvironment.icon("weather"), "%s has its own icon" % id)
		var e := MDSEnvironment.create(id)
		check(e != null and e.get_effect_id() == id, "%s makes its node (%s)" % [id, e.get_class() if e else "null"])
		add_child(e)
		await get_tree().process_frame
		check(e.get_materials().size() == 1 and e.get_materials()[0].shader != null and e.get_child_count() == 0, "%s draws one quad with its shader, internal" % id)
		if real_renderer:
			check(e.get_materials()[0].shader.get_shader_uniform_list().size() > 10, "%s's shader compiles" % id)
		check(e.z_index < 0, "%s falls behind the terrain by default (z %d)" % [id, e.z_index])
		e.free()
	check(MDSEnvironment.display_name("hot_waterfall") == "Hot water falls" and MDSEnvironment.display_name("lava_fall") == "Lava falls", "named for the effects list")

func _layout() -> void:
	var hot := MDSHotWaterfall.new()
	hot.size = Vector2(160, 500)
	hot.steam_spread = 100.0
	hot.steam_height = 120.0
	add_child(hot)
	hot.rebuild()
	var m := hot.get_materials()[0]
	check((m.get_shader_parameter("column") as Vector4).is_equal_approx(Vector4(100, 120, 160, 500)), "the sheet sits inside room for its steam (%s)" % m.get_shader_parameter("column"))
	check((m.get_shader_parameter("rect_size") as Vector2).is_equal_approx(Vector2(160 + 200, 500 + 120 + hot.mist_depth)), "the steam reaches above, beside and below it")
	hot.steam = 0.3
	check(is_equal_approx(float(m.get_shader_parameter("steam")), 0.3), "its settings reach the shader")
	hot.free()
	var lava := MDSLavaFall.new()
	lava.size = Vector2(90, 400)
	lava.glow_spread = 70.0
	add_child(lava)
	lava.rebuild()
	var lm := lava.get_materials()[0]
	check((lm.get_shader_parameter("column") as Vector4).is_equal_approx(Vector4(70, MDSLavaFall.HEADROOM, 90, 400)), "the lava falls inside room for its glow and splash (%s)" % lm.get_shader_parameter("column"))
	lava.size = Vector2(120, 400)
	lava.rebuild()
	check((lava.get_materials()[0].get_shader_parameter("column") as Vector4).z == 120.0, "resizing it moves the fall")
	lava.free()

func _liquids() -> void:
	var lava := MDSLavaFall.new()
	var lava_hot := lava.hot_color
	lava.liquid = MDSLava.Liquid.ACID
	check(lava.hot_color != lava_hot and lava.hot_color.g > lava.hot_color.r, "acid falls run green (%s)" % lava.hot_color)
	lava.liquid = MDSLava.Liquid.CURSED
	check(lava.hot_color.b > lava.hot_color.g, "cursed ooze runs purple")
	lava.liquid = MDSLava.Liquid.LAVA
	check(lava.hot_color.is_equal_approx(lava_hot), "and back to lava")
	var spec := MDSEnvironment.parse("lava_fall(liquid=magma, flow_speed=90)")
	var e := MDSEnvironment.create(spec[0].effect, spec[0].settings) as MDSLavaFall
	check(e.liquid == MDSLava.Liquid.MAGMA and is_equal_approx(e.flow_speed, 90.0), "settings by name, as in a weather spec")
	lava.free()
	e.free()

func _harm() -> void:
	var hot := MDSHotWaterfall.new()
	hot.position = Vector2(100, 0)
	hot.size = Vector2(120, 500)
	hot.damage = 4.0
	hot.damage_interval = 5.0
	hot.push_down = 300.0
	add_child(hot)
	var scalded := _body(Vector2(160, 250), HURTABLE)
	var y := scalded.position.y
	await physics_frames(4)
	check(scalded.hits == 1 and is_equal_approx(scalded.hurt, 4.0), "hot water scalds a body under it, once per interval (%d)" % scalded.hits)
	check(scalded.position.y > y + 5.0, "and presses it down (%.0f -> %.0f)" % [y, scalded.position.y])
	var dry := _body(Vector2(400, 250), HURTABLE)
	await physics_frames(2)
	check(dry.hits == 0, "beside it, nothing")
	hot.free()
	scalded.free()
	dry.free()
	var lava := MDSLavaFall.new()
	lava.position = Vector2(100, 0)
	lava.damage = 15.0
	lava.damage_interval = 5.0
	add_child(lava)
	var burned := [0]
	lava.body_hurt.connect(func(_b: Node2D, _a: float) -> void: burned[0] += 1)
	var victim := _body(Vector2(150, 300), HURTABLE)
	await physics_frames(4)
	check(victim.hits == 1 and is_equal_approx(victim.hurt, 15.0) and burned[0] == 1, "lava falls burn a body in them (%d)" % victim.hits)
	lava.free()
	victim.free()

func _room() -> void:
	var root := Node2D.new()
	root.name = "FallsRoom"
	save_scene(root, ROOM)
	root.free()
	load_fresh(ROOM)
	var painter := MDSRoomPainter.open(ROOM)
	var hot := painter.add_effect("hot_waterfall", Vector2(300, 300)) as MDSHotWaterfall
	var lava := painter.add_effect("lava_fall", Vector2(700, 300)) as MDSLavaFall
	check(hot != null and lava != null, "both can be placed in a room (Room view, Effects tool)")
	lava.liquid = MDSLava.Liquid.ACID
	hot.steam = 0.4
	check(painter.save() == OK, "saved")
	painter.free_instance()
	load_fresh(ROOM)
	var again := MDSRoomPainter.open(ROOM)
	var kinds: Array = again.effects().map(func(e: Node) -> String: return e.get_effect_id())
	check(kinds == ["hot_waterfall", "lava_fall"], "they are in the scene (%s)" % [kinds])
	var saved_lava := again.effects()[1] as MDSLavaFall
	var saved_hot := again.effects()[0] as MDSHotWaterfall
	check(saved_lava.liquid == MDSLava.Liquid.ACID and saved_lava.hot_color.g > saved_lava.hot_color.r and is_equal_approx(saved_hot.steam, 0.4), "with their settings")
	again.free_instance()
