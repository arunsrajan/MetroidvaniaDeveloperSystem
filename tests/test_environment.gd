extends "res://tests/test_case.gd"
## Environment effects (MDSEnvironmentEffect and its 29 effects), weather specs and presets
## (MDSEnvironment), effects acting on bodies, effects in the Room view's painter and canvas,
## and area weather in MDSWorldGame.

const Fixture := preload("res://tests/game_fixture.gd")
const ROOM := TMP + "/env_room.tscn"
const WEATHER_SCENE := TMP + "/env_weather.tscn"

const HURTABLE := "extends CharacterBody2D\nvar hurt := 0.0\nvar hits := 0\nfunc take_damage(amount: float) -> void:\n\thurt += amount\n\thits += 1\n"

## Collects the engine errors logged while it is added (OS.add_logger).
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s: %s %s" % [function, code, rationale])

func _run() -> void:
	_catalog()
	_specs()
	_presets()
	await _build_and_fit()
	_data()
	await _bodies()
	await _held_bodies()
	_steam_cycle()
	await _activation()
	_lightning()
	await _painter()
	await _canvas()
	await _area_weather()

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

# --- The catalog ------------------------------------------------------------------------------------

func _catalog() -> void:
	check(MDSEnvironment.effect_ids().size() == 29, "29 effects (%d)" % MDSEnvironment.effect_ids().size())
	var real_renderer := DisplayServer.get_name() != "headless"
	for id in MDSEnvironment.effect_ids():
		var e := MDSEnvironment.create(id)
		check(e is MDSEnvironmentEffect and e.get_effect_id() == id, "%s makes its effect (%s)" % [id, e.get_class() if e else "null"])
		check(MDSEnvironment.icon(id) != null, "%s has an icon" % id)
		add_child(e)
		check(not e.get_materials().is_empty() and e.get_materials().all(func(m: ShaderMaterial) -> bool: return m.shader != null), "%s draws with its shader" % id)
		if real_renderer:
			for m in e.get_materials():
				check(m.shader.get_shader_uniform_list().size() > 3, "%s's shader compiles" % id)
		check(e.get_child_count() == 0 and e.get_child_count(true) > 0, "%s's parts are internal (never saved)" % id)
		e.free()
	check(MDSEnvironment.ambient_ids().has("rain") and not MDSEnvironment.ambient_ids().has("lava"), "rain covers rooms, lava is placed")

# --- Weather specs ----------------------------------------------------------------------------------

func _specs() -> void:
	var storm := MDSEnvironment.parse("storm")
	check(storm.map(func(e: Dictionary) -> String: return e.get("effect", "")) == ["rain", "lightning", "fog"], "storm is rain, lightning and fog (%s)" % [storm])
	var mixed := MDSEnvironment.parse("rain(angle=-20, density=0.8), fog(color=#3a4350), bogus, none")
	check(mixed.size() == 3 and mixed[0].settings == {"angle": "-20", "density": "0.8"}, "settings in parentheses are read (%s)" % [mixed])
	check(mixed[2].has("unknown") and MDSEnvironment.check("rain, bogus").contains("bogus"), "an unknown name is reported")
	check(MDSEnvironment.check("storm, rain(angle=4)").is_empty(), "a good spec has no problems")
	check(MDSEnvironment.is_none(" None ") and MDSEnvironment.parse("none").is_empty() and MDSEnvironment.build("none", Rect2(0, 0, 10, 10)) == null, "none is no weather")
	var dust := MDSEnvironment.create("dust_storm", {"blows_toward": "left", "wind_speed": "600", "far_plane": "false"}) as MDSDustStorm
	check(dust.blows_toward == MDSDustStorm.Toward.LEFT and is_equal_approx(dust.wind_speed, 600.0) and not dust.far_plane, "enum names, numbers and booleans are understood")
	dust.free()
	var shafts := MDSEnvironment.create("light_shafts", {"color": "Color(0.75, 0.9, 1.0, 0.45)"}) as MDSLightShafts
	check(shafts.color.is_equal_approx(Color(0.75, 0.9, 1.0, 0.45)), "Color(...) values work")
	shafts.free()
	var fog := MDSEnvironment.create("fog", {"color": "#3a4350"}) as MDSFog
	check(fog.color.is_equal_approx(Color("#3a4350")), "#hex colors work")
	check(not MDSEnvironment.set_setting(fog, "nonsense", "1") and not MDSEnvironment.set_setting(fog, "density", "Vector2(1, 2)"), "an unknown setting or a value that doesn't fit is refused")
	fog.free()
	check(MDSEnvironment.split_list("a(b, c(d, e)), f") == PackedStringArray(["a(b, c(d, e))", " f"]), "lists split outside parentheses")
	check(MDSEnvironment.summary("storm") == "Rain, Lightning, Fog / mist", "a spec has a summary (%s)" % MDSEnvironment.summary("storm"))

func _presets() -> void:
	for id in MDSEnvironment.preset_ids():
		var entries := MDSEnvironment.parse(id)
		check(not entries.is_empty() and entries.all(func(e: Dictionary) -> bool: return e.has("effect")), "preset %s is made of effects" % id)
		for e in entries:
			var fx := MDSEnvironment.create(e.effect)
			for k in e.settings:
				check(MDSEnvironment.set_setting(fx, k, e.settings[k]), "preset %s: %s.%s = %s" % [id, e.effect, k, e.settings[k]])
			fx.free()

func _build_and_fit() -> void:
	var room := Rect2(0, 0, 1152, 648)
	var w := MDSEnvironment.build("storm", room)
	check(w != null and w.name == MDSEnvironment.NODE_NAME and w.get_child_count() == 3, "build makes the weather node")
	var want := room.grow(MDSEnvironment.ROOM_MARGIN)
	for fx in MDSEnvironment.effects_in(w):
		check(fx.fit_room and Rect2(fx.position + fx.get_effect_rect().position, fx.size).is_equal_approx(want), "%s covers the room and its margin" % fx.name)
	w.free()
	# A scene of effect nodes: those with fit_room are sized to the room, the others stay put.
	var root := Node2D.new()
	root.name = "Weather"
	var offset := Node2D.new()
	offset.name = "Offset"
	offset.position = Vector2(100, 50)
	root.add_child(offset)
	var f := MDSFog.new()
	f.name = "Fog"
	f.fit_room = true
	offset.add_child(f)
	var vent := MDSSteamVent.new()
	vent.name = "Vent"
	vent.position = Vector2(300, 400)
	root.add_child(vent)
	check(save_scene(root, WEATHER_SCENE) == OK, "saved a weather scene")
	root.free()
	var built := MDSEnvironment.build("%s, rain" % WEATHER_SCENE, room)
	add_child(built)
	var fog: MDSFog = built.get_node("Weather/Offset/Fog")
	check(fog.position.is_equal_approx(want.position - Vector2(100, 50)) and fog.size.is_equal_approx(want.size), "a fit_room effect in a scene covers the room (%s, %s)" % [fog.position, fog.size])
	check((built.get_node("Weather/Vent") as Node2D).position == Vector2(300, 400), "the others stay where the scene put them")
	check(built.get_child_count() == 2 and built.get_child(1) is MDSRain, "scenes and effects mix")
	await get_tree().process_frame
	check(fog.get_materials().size() == 1 and (fog.get_materials()[0].get_shader_parameter("rect_size") as Vector2).is_equal_approx(want.size), "its shader covers its new size")
	built.free()

func _data() -> void:
	var rain := MDSRain.new()
	rain.angle = -20.0
	rain.affect_groups = PackedStringArray(["player", "npc"])
	rain.position = Vector2(5, 6)
	rain.set_meta(&"note", "x")
	var d := rain.to_data()
	var copy := MDSEnvironmentEffect.from_data(d) as MDSRain
	check(copy.angle == -20.0 and copy.affect_groups == rain.affect_groups and copy.position == Vector2(5, 6) and copy.get_meta(&"note") == "x", "to_data / from_data keep the settings")
	copy.affect_groups.append("x")
	check(rain.affect_groups.size() == 2 and (d.props.affect_groups as PackedStringArray).size() == 2, "copies don't share arrays")
	rain.free()
	copy.free()

# --- Bodies -----------------------------------------------------------------------------------------

func _bodies() -> void:
	# Wind shoves bodies downwind.
	var storm := MDSDustStorm.new()
	storm.size = Vector2(800, 400)
	storm.gustiness = 0.0
	storm.push = 200.0
	add_child(storm)
	var b := _body(Vector2(300, 200))
	await physics_frames(10)
	check(b.position.x > 300.0 + 20.0, "the dust storm pushes the player toward the right (%.1f)" % b.position.x)
	storm.blows_toward = MDSDustStorm.Toward.LEFT
	var x := b.position.x
	await physics_frames(10)
	check(b.position.x < x - 20.0, "and toward the left when it blows left (%.1f)" % b.position.x)
	var entered := [0]
	storm.body_exited_effect.connect(func(_b: Node2D) -> void: entered[0] += 1)
	b.position = Vector2(2000, 200)
	await physics_frames(2)
	check(entered[0] == 1, "leaving it is reported")
	storm.free()
	b.free()
	# A constant steam jet throws bodies up and scalds them once per eruption.
	var vent := MDSSteamVent.new()
	vent.cycle = MDSSteamVent.Cycle.CONSTANT
	vent.damage = 5.0
	vent.position = Vector2(100, 600)
	add_child(vent)
	var hurt := _body(Vector2(100, 450), HURTABLE)
	await physics_frames(3)
	check(hurt.velocity.y <= -vent.launch_speed + 1.0, "the jet throws the player up (%.0f)" % hurt.velocity.y)
	check(hurt.hits == 1 and is_equal_approx(hurt.hurt, 5.0), "and scalds it once (%d hits)" % hurt.hits)
	var beside := _body(Vector2(100 + 60, 450))
	await physics_frames(2)
	check(beside.velocity.y >= 0.0, "grazing the jet's billows is free")
	vent.free()
	hurt.free()
	beside.free()
	# Lava hurts every damage_interval.
	var lava := MDSLava.new()
	lava.position = Vector2(0, 500)
	lava.damage = 10.0
	lava.damage_interval = 5.0
	add_child(lava)
	var burned := [0]
	lava.body_hurt.connect(func(_b: Node2D, _a: float) -> void: burned[0] += 1)
	var victim := _body(Vector2(200, 490), HURTABLE)
	await physics_frames(4)
	check(victim.hits == 1 and burned[0] == 1, "lava hurts a body at its surface, once per interval (%d)" % victim.hits)
	lava.free()
	victim.free()
	# A body can take over how it is pushed.
	var own := _body(Vector2(100, 100), "extends CharacterBody2D\nvar pushed := Vector2.ZERO\nfunc mds_environment_push(v: Vector2, _d: float, _e: Node) -> void:\n\tpushed = v\n")
	var wind := MDSDustStorm.new()
	wind.gustiness = 0.0
	add_child(wind)
	await physics_frames(2)
	check(own.pushed.x > 0.0 and own.position == Vector2(100, 100), "mds_environment_push replaces the default push")
	wind.free()
	own.free()

## A body held still (process_mode disabled, as MDSWorldGame holds the player during a room
## change) is out of the physics space: effects leave it alone instead of moving it.
func _held_bodies() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var storm := MDSDustStorm.new()
	storm.gustiness = 0.0
	storm.push = 300.0
	add_child(storm)
	var vent := MDSSteamVent.new()
	vent.cycle = MDSSteamVent.Cycle.CONSTANT
	vent.damage = 5.0
	vent.position = Vector2(600, 600)
	add_child(vent)
	var lava := MDSLava.new()
	lava.position = Vector2(800, 400)
	add_child(lava)
	var blown := _body(Vector2(200, 200))
	var thrown := _body(Vector2(600, 450), HURTABLE)
	var burned := _body(Vector2(900, 400), HURTABLE)
	await physics_frames(2)
	for b in [blown, thrown, burned]:
		b.process_mode = Node.PROCESS_MODE_DISABLED
		b.velocity = Vector2.ZERO
	thrown.hits = 0
	burned.hits = 0
	var at := blown.position
	await physics_frames(6)
	OS.remove_logger(catcher)
	check(catcher.errors.is_empty(), "no physics errors while bodies are held still (%s)" % "; ".join(catcher.errors))
	check(blown.position == at and thrown.velocity == Vector2.ZERO and thrown.hits == 0 and burned.hits == 0, "and they aren't pushed, thrown or hurt")
	for b in [blown, thrown, burned]:
		b.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frames(4)
	check(blown.position.x > at.x and thrown.velocity.y < 0.0, "once released, the effects act on them again")
	for n in [storm, vent, lava, blown, thrown, burned]:
		n.free()

func _steam_cycle() -> void:
	var vent := MDSSteamVent.new()
	vent.rest_time = 0.2
	vent.warning_time = 0.1
	vent.blast_time = 0.2
	vent.phase_offset = 0.1
	var events: Array[String] = []
	vent.erupted.connect(func() -> void: events.append("erupted"))
	vent.calmed.connect(func() -> void: events.append("calmed"))
	var phases: Array = []
	for i in 40:
		vent._tick(0.05)
		if phases.is_empty() or phases[phases.size() - 1] != vent.phase:
			phases.append(vent.phase)
	check(phases.slice(0, 5) == [MDSSteamVent.Phase.REST, MDSSteamVent.Phase.WARN, MDSSteamVent.Phase.RISE, MDSSteamVent.Phase.BLAST, MDSSteamVent.Phase.FADE], "a vent rests, warns, rises, blasts and fades (%s)" % [phases])
	check(events.count("erupted") >= 2 and events.count("calmed") >= 1, "it erupts again and again (%s)" % [events])
	var once := MDSSteamVent.new()
	once.cycle = MDSSteamVent.Cycle.ON_DEMAND
	for i in 20:
		once._tick(0.1)
	check(once.phase == MDSSteamVent.Phase.REST and once.erupt() and not once.erupt(), "ON_DEMAND waits for erupt()")
	check(once.get_effect_rect() == Rect2(-40, -520, 80, 520), "the jet rises from the vent")
	vent.free()
	once.free()

func _activation() -> void:
	var rain := MDSRain.new()
	rain.size = Vector2(400, 400)
	rain.activation = MDSEnvironmentEffect.Activation.PLAYER_INSIDE
	rain.fade_time = 0.0
	add_child(rain)
	var b := _body(Vector2(900, 200))
	await get_tree().process_frame
	check(rain.get_strength() == 0.0, "PLAYER_INSIDE: off while nobody is in it")
	b.position = Vector2(200, 200)
	await get_tree().process_frame
	await get_tree().process_frame
	check(rain.get_strength() == 1.0, "and on once the player is")
	var snow := MDSSnowfall.new()
	snow.activation = MDSEnvironmentEffect.Activation.MANUAL
	add_child(snow)
	await get_tree().process_frame
	check(snow.get_strength() == 0.0, "MANUAL: off until started")
	snow.start(0.0)
	check(snow.get_strength() == 1.0, "start(0) turns it on at once")
	snow.intensity = 0.5
	check(is_equal_approx(snow.get_strength(), 0.5) and is_equal_approx(float(snow.get_materials()[0].get_shader_parameter("intensity")), 0.5), "intensity reaches the shaders")
	snow.stop(0.0)
	check(snow.get_strength() == 0.0 and not (snow.get_child(0, true) as CanvasItem).visible, "stop(0) turns it off and hides it")
	rain.free()
	snow.free()
	b.free()

func _lightning() -> void:
	var l := MDSLightning.new()
	l.interval = Vector2.ZERO
	add_child(l)
	var hits: Array = []
	l.struck.connect(func(at: Vector2) -> void: hits.append(at))
	l.strike(0.5)
	check(hits.size() == 1 and l.get_effect_rect().grow(200).has_point(hits[0]), "strike() strikes inside the sky (%s)" % [hits])
	check(l._bolt_root.get_child_count() == 2 * (1 + l.forks), "a bolt with its forks, each a glow and a core")
	l._tick(0.01)
	check(float(l.get_materials()[0].get_shader_parameter("flash")) > 0.5, "the sky flashes")
	for i in 30:
		l._tick(0.05)
	check(float(l.get_materials()[0].get_shader_parameter("flash")) < 0.05 and not l._bolt_root.visible, "and goes dark again")
	var pts := MDSLightning.bolt_points(Vector2.ZERO, Vector2(0, 400), RandomNumberGenerator.new())
	check(pts.size() == 65 and pts[0] == Vector2.ZERO and pts[pts.size() - 1] == Vector2(0, 400), "bolts are jagged lines between their ends")
	l.free()

# --- The Room view ----------------------------------------------------------------------------------

func _save_room() -> void:
	var root := Node2D.new()
	root.name = "EnvRoom"
	var effects := Node2D.new()
	effects.name = "Effects"
	root.add_child(effects)
	var rain := MDSRain.new()
	rain.name = "Rain"
	rain.angle = 25.0
	effects.add_child(rain)
	var vent := MDSSteamVent.new()
	vent.name = "OwnVent"
	vent.position = Vector2(400, 600)
	root.add_child(vent)
	save_scene(root, ROOM)
	root.free()

func _painter() -> void:
	_save_room()
	load_fresh(ROOM)
	var painter := MDSRoomPainter.open(ROOM)
	check(painter.effects().size() == 1 and painter.effects()[0].name == "Rain", "the painter edits the effects in the Effects node (%d)" % painter.effects().size())
	var lava := painter.add_effect("lava", Vector2(500, 600))
	check(lava is MDSLava and (lava.position + lava.get_effect_rect().get_center()).is_equal_approx(Vector2(500, 600)), "add_effect centres it on the point")
	var vent := painter.add_effect("steam_vent", Vector2(800, 640))
	check(vent.position == Vector2(800, 640), "a vent stands on the point")
	check(painter.effect_at(Vector2(500, 600)) == lava and painter.effect_at(Vector2(800, 400)) == vent, "effect_at finds them")
	painter.checkpoint()
	painter.add_effect("waterfall", Vector2(100, 100))
	check(painter.effects().size() == 4, "a waterfall added")
	painter.undo()
	check(painter.effects().size() == 3, "undo takes it out")
	(painter.effects()[0] as MDSRain).density = 0.9
	check(painter.save() == OK, "saved")
	painter.free_instance()
	load_fresh(ROOM)
	var again := MDSRoomPainter.open(ROOM)
	var names: Array = again.effects().map(func(e: Node) -> String: return String(e.name))
	check(names.size() == 3 and names.has("Rain") and again.effects()[0] is MDSRain, "the effects are in the scene (%s)" % [names])
	var rain := again.effects()[0] as MDSRain
	check(is_equal_approx(rain.angle, 25.0) and is_equal_approx(rain.density, 0.9), "with their settings")
	check(again.root.get_node_or_null("OwnVent") is MDSSteamVent and again.root.get_node("Effects").get_child_count() == 3, "an effect outside the Effects node is left where it is")
	var before := FileAccess.get_file_as_string(ROOM)
	check(again.save() == OK and FileAccess.get_file_as_string(ROOM) == before, "saving unchanged changes nothing")
	again.free_instance()

func _canvas() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "weather", "storm")
	var painter := MDSRoomPainter.open(world.get_scene_path("Garden_01"))
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(800, 500)
	add_child(canvas)
	canvas.open(world, "Garden_01", painter)
	var preview := canvas.get_weather_preview()
	check(preview != null and MDSEnvironment.effects_in(preview).size() == 3, "the Room view shows the area's weather")
	check(painter.effects().is_empty() and preview.get_parent() != painter.items_root, "as a preview, not part of the room")
	canvas.set_weather_preview(false)
	await get_tree().process_frame
	check(canvas.get_weather_preview() == null, "it can be hidden")
	canvas.tool = MDSRoomCanvas.Tool.EFFECT
	var data := {"type": MDSRoomCanvas.DRAG_EFFECT, "effect": "fireflies"}
	check(canvas._can_drop_data(Vector2(100, 100), data), "an effect can be dropped on the view")
	canvas._drop_data(Vector2(100, 100), data)
	check(painter.effects().size() == 1 and canvas.selected_effect is MDSFireflies, "dropping places and selects it")
	check(painter.dirty and painter.can_undo(), "undoably")
	var dropped: Array = []
	canvas.image_dropped.connect(func(p: String) -> void: dropped.append(p))
	check(canvas._can_drop_data(Vector2.ZERO, {"type": "files", "files": ["res://a/drawing.PNG"]}) and not canvas._can_drop_data(Vector2.ZERO, {"type": "files", "files": ["res://a/notes.txt"]}), "image files can be dropped, other files not")
	canvas._drop_data(Vector2.ZERO, {"type": "files", "files": ["res://a/drawing.png"]})
	check(dropped == ["res://a/drawing.png"], "a dropped image asks to be traced")
	canvas.delete_selected_effect()
	check(painter.effects().is_empty() and canvas.selected_effect == null, "Delete removes the selected effect")
	canvas.close()
	canvas.queue_free()
	painter.free_instance()

# --- In the game ------------------------------------------------------------------------------------

func _area_weather() -> void:
	var typo := Fixture.build()
	typo.set_area_value("Gardens", "weather", "stormy")
	typo.set_room_value("Crypt_01", "weather", "rain(angle=4), res://nowhere.tscn")
	var analysis := MDSAnalysis.new(MDSGraph.from_world(typo, {}), typo, {}).run()
	var messages: Array = MDSWorldValidator.run(typo, analysis, {}).map(func(i: Dictionary) -> String: return i.message)
	check(messages.any(func(m: String) -> bool: return m.contains("Gardens's weather") and m.contains("'stormy'")), "the Issues tab reports an area's mistyped weather")
	check(messages.any(func(m: String) -> bool: return m.contains("weather") and m.contains("nowhere.tscn")), "and a room's missing weather scene")
	var world := Fixture.build()
	world.set_area_value("Gardens", "weather", "storm")
	world.set_room_value("Garden_02", "weather", "none")
	world.set_area_value("Crypt", "weather", "dust_storm(blows_toward=left, gustiness=0, push=300)")
	world.save()
	MDSWorld._cache.erase(Fixture.WORLD)
	var game := Fixture.make_game()
	add_child(game)
	await game.room_loaded
	check(game.get_weather_spec("Garden_01") == "storm" and game.weather != null, "Garden_01 has its area's weather")
	var kinds: Array = MDSEnvironment.effects_in(game.weather).map(func(e: Node) -> String: return e.get_effect_id())
	check(kinds == ["rain", "lightning", "fog"], "rain, lightning and fog (%s)" % [kinds])
	check(game.weather.get_parent() == game.room_node, "in the room, so it goes with it")
	var rain: MDSRain = game.weather.get_child(0)
	check(Rect2(rain.position, rain.size).encloses(Rect2(0, 0, 1152, 648)), "covering the room")
	game.load_room("Garden_02", "left1")
	await game.room_loaded
	check(game.weather == null and MDSEnvironment.effects_in(game.room_node).is_empty(), "a room set to none has no weather")
	game.load_room("Crypt_01", "left1")
	await game.room_loaded
	await physics_frames(2)
	var storm := MDSEnvironment.effects_in(game.weather)
	check(storm.size() == 1 and storm[0] is MDSDustStorm and (storm[0] as MDSDustStorm).blows_toward == MDSDustStorm.Toward.LEFT, "the Crypt's storm blows left")
	var x := game.player.global_position.x
	await physics_frames(10)
	check(game.player.global_position.x < x - 10.0, "and pushes the player (%.0f -> %.0f)" % [x, game.player.global_position.x])
	# Leaving through a gate with a fade: the player is held still while the storm still blows.
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	game.fade_time = 0.15
	game.load_room("Garden_02", "right1")
	await game.room_loaded
	await physics_frames(4)
	OS.remove_logger(catcher)
	check(game.current_room == "Garden_02", "the player leaves the storm through a fading gate")
	check(catcher.errors.is_empty(), "with no physics errors while the player is held during the fade (%s)" % "; ".join(catcher.errors))
	game.queue_free()
	await get_tree().process_frame
	var calm := Fixture.make_game()
	calm.room_weather = false
	add_child(calm)
	await calm.room_loaded
	check(calm.weather == null, "room_weather off: no weather")
	calm.queue_free()
	await get_tree().process_frame
