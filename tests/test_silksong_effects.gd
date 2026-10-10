extends "res://tests/test_case.gd"
## The Silksong-style effects: silk threads, will-o'-wisps, a gnat swarm, dripping water, hanging
## moss, swaying grass, cobwebs, void tendrils, incense smoke and forge sparks. In the catalog and
## the presets, their shaders, and how they react to bodies: grass and moss part around the
## player, tendrils reach for it and hurt, gnats gather around it, webs tremble and slow it,
## sparks burn.

const HURTABLE := "extends CharacterBody2D\nvar hurt := 0.0\nvar hits := 0\nfunc take_damage(amount: float) -> void:\n\thurt += amount\n\thits += 1\n"
const AMBIENT: PackedStringArray = ["silk_threads", "wisps", "gnat_swarm", "ceiling_drips"]
const PLACED: PackedStringArray = ["hanging_moss", "swaying_grass", "cobwebs", "void_tendrils", "incense_smoke", "forge_sparks"]
const PRESETS: PackedStringArray = ["weavenest", "bilewater", "wisp_thicket", "deep_docks", "wormways"]

func _run() -> void:
	await _catalog()
	_presets()
	await _bodies()
	await _harm()
	await _cobwebs()
	_settings()

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
	for id in Array(AMBIENT) + Array(PLACED):
		var ambient := AMBIENT.has(id)
		check(MDSEnvironment.effect_ids().has(id) and MDSEnvironment.ambient_ids().has(id) == ambient, "%s is an effect %s" % [id, "covering whole rooms" if ambient else "placed in a room"])
		check(MDSEnvironment.icon(id) != null and MDSEnvironment.icon(id) != MDSEnvironment.icon("weather"), "%s has its own icon" % id)
		check(not MDSEnvironment.display_name(id).is_empty() and MDSEnvironment.display_name(id) != id and not MDSEnvironment.describe(id).is_empty(), "%s has a name and a description" % id)
		var e := MDSEnvironment.create(id)
		check(e != null and e.get_effect_id() == id, "%s makes its node (%s)" % [id, e.get_class() if e else "null"])
		add_child(e)
		await get_tree().process_frame
		check(e.get_materials().size() == 1 and e.get_materials()[0].shader != null and e.get_child_count() == 0, "%s draws one quad with its shader, internal" % id)
		if real_renderer:
			check(e.get_materials()[0].shader.get_shader_uniform_list().size() > 10, "%s's shader compiles" % id)
		e.free()

func _presets() -> void:
	var room := Rect2(0, 0, 1152, 648)
	for id in PRESETS:
		check(MDSEnvironment.PRESETS.has(id) and MDSEnvironment.check(id).is_empty(), "preset %s is good weather" % id)
		var node := MDSEnvironment.build(id, room)
		var fx := MDSEnvironment.effects_in(node)
		check(fx.size() >= 2 and fx.all(func(f: MDSEnvironmentEffect) -> bool: return Rect2(f.position, f.size).encloses(room)), "%s builds %d effects covering the room" % [id, fx.size()])
		node.free()
	var nest := MDSEnvironment.parse("weavenest")
	check(nest.size() == 2 and nest[0].effect == "silk_threads", "the Weavenest is silk in a haze")
	var bile := MDSEnvironment.parse("bilewater").map(func(e: Dictionary) -> String: return e.effect)
	check(bile.has("gnat_swarm") and bile.has("ceiling_drips"), "Bilewater has gnats and drips")

## The bodies an effect's shader was sent.
func _sent(e: MDSEnvironmentEffect) -> PackedVector2Array:
	var m := e.get_materials()[0]
	var pts: PackedVector2Array = m.get_shader_parameter("bodies") if m.get_shader_parameter("bodies") != null else PackedVector2Array()
	var n := int(m.get_shader_parameter("body_count")) if m.get_shader_parameter("body_count") != null else 0
	return pts.slice(0, n)

func _bodies() -> void:
	var grass := MDSSwayingGrass.new()
	grass.position = Vector2(100, 400)
	grass.size = Vector2(400, 60)
	add_child(grass)
	var walker := _body(Vector2(250, 440))
	await get_tree().process_frame
	await get_tree().process_frame
	var sent := _sent(grass)
	check(sent.size() == 1 and sent[0].is_equal_approx(Vector2(150, 40)), "grass knows where the player walks through it, in its pixels (%s)" % [sent])
	walker.position = Vector2(250, 100)
	await get_tree().process_frame
	check(_sent(grass).is_empty(), "and that it's gone once it jumps away")
	walker.position = Vector2(250, 440)
	grass.bend = 0.0
	await get_tree().process_frame
	check(_sent(grass).is_empty(), "bend 0: the grass ignores it")
	grass.free()
	var moss := MDSHangingMoss.new()
	moss.position = Vector2(100, 380)
	moss.size = Vector2(400, 120)
	add_child(moss)
	await get_tree().process_frame
	sent = _sent(moss)
	check(sent.size() == 1 and sent[0].is_equal_approx(Vector2(150, 60)), "moss parts around the player among it (%s)" % [sent])
	moss.part_radius = 0.0
	await get_tree().process_frame
	check(_sent(moss).is_empty(), "part_radius 0: it doesn't part")
	moss.free()
	var tendrils := MDSVoidTendrils.new()
	tendrils.position = Vector2(0, 300)
	tendrils.size = Vector2(400, 220)
	tendrils.reach = 200.0
	add_child(tendrils)
	walker.position = Vector2(500, 450)
	await get_tree().process_frame
	check(_sent(tendrils).size() == 1, "tendrils sense the player within reach, beside them too")
	walker.position = Vector2(900, 450)
	await get_tree().process_frame
	check(_sent(tendrils).is_empty(), "but not farther")
	tendrils.free()
	var gnats := MDSGnatSwarm.new()
	gnats.size = Vector2(600, 400)
	gnats.lure_radius = 400.0
	add_child(gnats)
	await get_tree().process_frame
	check(_sent(gnats).size() == 1, "a gnat swarm is drawn to the player near it")
	gnats.lure = 0.0
	await get_tree().process_frame
	check(_sent(gnats).is_empty(), "lure 0: they leave it be")
	gnats.free()
	var crowd: Array[CharacterBody2D] = []
	var many := MDSSwayingGrass.new()
	many.size = Vector2(600, 60)
	add_child(many)
	for i in 6:
		crowd.append(_body(Vector2(50 + i * 100, 40)))
	walker.position = Vector2(300, 40)
	await get_tree().process_frame
	sent = _sent(many)
	check(sent.size() == 4 and sent[0].distance_to(Vector2(300, 40)) < 1.0, "at most four bodies, the nearest to its middle first (%s)" % [sent])
	many.free()
	for b in crowd:
		b.free()
	walker.free()

func _harm() -> void:
	var tendrils := MDSVoidTendrils.new()
	tendrils.position = Vector2(100, 200)
	tendrils.size = Vector2(300, 300)
	tendrils.height = 120.0
	add_child(tendrils)
	check(tendrils.get_body_rect().is_equal_approx(Rect2(0, 180, 300, 120)), "they hurt only as high as they rise (%s)" % tendrils.get_body_rect())
	var low := _body(Vector2(250, 460), HURTABLE)
	var high := _body(Vector2(250, 230), HURTABLE)
	await physics_frames(3)
	check(low.hits == 0, "scenery by default: they hurt no one")
	tendrils.damage = 5.0
	tendrils.damage_interval = 5.0
	await physics_frames(3)
	check(low.hits == 1 and is_equal_approx(low.hurt, 5.0), "with damage, a body among them is hurt once per interval (%d)" % low.hits)
	check(high.hits == 0, "above them, nothing")
	tendrils.free()
	low.free()
	high.free()
	var sparks := MDSForgeSparks.new()
	sparks.position = Vector2(100, 0)
	sparks.damage = 3.0
	sparks.damage_interval = 5.0
	add_child(sparks)
	var smith := _body(Vector2(250, 300), HURTABLE)
	await physics_frames(3)
	check(smith.hits == 1 and is_equal_approx(smith.hurt, 3.0), "forge sparks burn a body under them (%d)" % smith.hits)
	sparks.free()
	smith.free()

func _cobwebs() -> void:
	var webs := MDSCobwebs.new()
	webs.position = Vector2(100, 100)
	webs.size = Vector2(400, 300)
	webs.web_radius = 120.0
	add_child(webs)
	check(webs.is_in_web(Vector2(30, 30)) and webs.is_in_web(Vector2(370, 40)), "webs fill the top corners by default")
	check(not webs.is_in_web(Vector2(200, 150)) and not webs.is_in_web(Vector2(30, 280)), "not the middle or the bottom")
	webs.middle = true
	webs.bottom_left = true
	check(webs.is_in_web(Vector2(200, 150)) and webs.is_in_web(Vector2(30, 280)), "a whole web in the middle, and the bottom corners when asked")
	check(int(webs.get_materials()[0].get_shader_parameter("corners")) == 1 | 2 | 4 | 16, "the shader draws those webs")
	webs.stickiness = 4.0
	var fly := _body(Vector2(130, 130))
	await get_tree().process_frame
	check(webs.tremble == 0.0, "still: no trembling")
	fly.velocity = Vector2(300, 0)
	await physics_frames(3)
	check(fly.velocity.x < 290.0, "a sticky web slows a body in it (%.0f)" % fly.velocity.x)
	fly.position += Vector2(8, 0)
	# process_frame comes before the nodes' _process: one more for the webs to see it.
	await get_tree().process_frame
	await get_tree().process_frame
	check(webs.tremble > 0.3 and float(webs.get_materials()[0].get_shader_parameter("tremble")) > 0.3, "moving through it makes it tremble (%.2f)" % webs.tremble)
	var shaken := webs.tremble
	for i in 20:
		await get_tree().process_frame
	check(webs.tremble < shaken, "and it settles down (%.2f)" % webs.tremble)
	webs.free()
	fly.free()

func _settings() -> void:
	var sparks := MDSEnvironment.create("forge_sparks", {"bursts": "true", "angle": "180", "count": "20"}) as MDSForgeSparks
	add_child(sparks)
	var m := sparks.get_materials()[0]
	check(sparks.bursts and is_equal_approx(float(m.get_shader_parameter("burst")), 1.0) and int(m.get_shader_parameter("count")) == 20, "settings by name, as in a weather spec: bursts of 20")
	check(is_equal_approx(float(m.get_shader_parameter("angle")), 180.0), "sparks can spray up")
	sparks.free()
	var smoke := MDSIncenseSmoke.new()
	smoke.plumes = 3
	add_child(smoke)
	check(int(smoke.get_materials()[0].get_shader_parameter("plumes")) == 3, "three censers")
	smoke.free()
	var silk := MDSSilkThreads.new()
	silk.hanging = 0.0
	add_child(silk)
	check(is_equal_approx(float(silk.get_materials()[0].get_shader_parameter("hanging")), 0.0), "silk without hanging threads")
	silk.free()
	var d := MDSDrips.new()
	d.color = Color(0.6, 0.8, 0.3, 0.8)
	add_child(d)
	check(d.get_materials()[0].get_shader_parameter("color") == Color(0.6, 0.8, 0.3, 0.8), "green drips for bile")
	d.free()
