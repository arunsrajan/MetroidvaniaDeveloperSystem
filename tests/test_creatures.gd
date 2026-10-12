extends "res://tests/test_case.gd"
## Creature backgrounds (MDSCreatures): the twenty kinds and their looks, the shader, how they move
## and react to the player (activity, fleeing, coming near, climbing, hiding, startling), their
## glow (near the player, the area's color), that they never touch the player, the background
## values of boss rooms, the game and the Room view, and saving.

const Fixture := preload("res://tests/game_fixture.gd")
const DT := 1.0 / 60.0

## The effects and the player live in a view of their own (a headless run's window is 64 px).
var vp: SubViewport

func _run() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1152, 648)
	vp.disable_3d = true
	add_child(vp)
	await _catalog()
	_kinds()
	await _all_move()
	await _activity()
	await _reactions()
	await _glow()
	await _harmless()
	_specs()
	_field()
	await _in_game()
	await _canvas()
	_saved()
	_data()

## A creature background in the tree, moved on with [method _run_for].
func _make(id: String) -> MDSCreatures:
	var fx := MDSCreatures.new()
	fx.use_creature(id)
	vp.add_child(fx)
	return fx

func _run_for(fx: MDSCreatures, seconds: float) -> void:
	for i in int(seconds / DT):
		fx._tick(DT)

func _player(at: Vector2) -> CharacterBody2D:
	var b := CharacterBody2D.new()
	b.add_to_group(&"player")
	b.position = at
	vp.add_child(b)
	return b

func _mean_distance(fx: MDSCreatures, to: Vector2) -> float:
	var pts := fx.creature_positions()
	var sum := 0.0
	for p in pts:
		sum += p.distance_to(to)
	return sum / maxf(pts.size(), 1.0)

func _catalog() -> void:
	check(MDSEnvironment.effect_ids().has("creatures") and not MDSEnvironment.ambient_ids().has("creatures"), "creatures are an effect, not weather")
	check(MDSEnvironment.icon("creatures") != null and MDSEnvironment.icon("creatures") != MDSEnvironment.icon("weather"), "with an icon of their own")
	var fx := MDSEnvironment.create("creatures") as MDSCreatures
	check(fx != null and fx.get_effect_id() == "creatures", "create('creatures') makes one")
	var anim := MDSAnimatedBackground.new()
	var par := MDSParallaxBackground.new()
	check(anim.z_index < fx.z_index and fx.z_index < par.z_index, "drawn in front of an animated background, behind a parallax one (z %d)" % fx.z_index)
	anim.free()
	par.free()
	add_child(fx)
	await get_tree().process_frame
	check(fx.get_materials().size() == 1 and fx.get_child_count() == 0, "one quad, internal")
	if DisplayServer.get_name() != "headless":
		check(fx.get_materials()[0].shader.get_shader_uniform_list().size() > 15, "the creatures shader compiles")
	fx.free()

func _kinds() -> void:
	var n := MDSCreatures.Creature.size()
	check(n == 20, "twenty kinds (%d)" % n)
	check(MDSCreatures.CREATURE_IDS.size() == n and MDSCreatures.CREATURE_NAMES.size() == n and MDSCreatures.CREATURE_INFO.size() == n and MDSCreatures.MOTIONS.size() == n, "an id, a name, a description and a way of moving each")
	check(Array(MDSCreatures.CREATURE_IDS).all(func(id: String) -> bool: return MDSCreatures.LOOKS.has(id)), "and a look each")
	for id in ["bees", "spiders", "songbirds", "bats", "jellyfish", "owls", "worms"]:
		check(MDSCreatures.CREATURE_IDS.has(id), "%s are one of them" % id)
	var fx := MDSCreatures.new()
	check(fx.use_creature("owls") and fx.creature == MDSCreatures.Creature.OWLS, "use_creature")
	var look: Dictionary = MDSCreatures.LOOKS.owls
	check(fx.glow_color == look.glow_color and fx.habitat == look.habitat and fx.count == look.count, "picking a kind gives it its look (glow, habitat, numbers)")
	check(not fx.use_creature("dragons") and fx.creature == MDSCreatures.Creature.OWLS, "an unknown kind is refused")
	check(fx.use_creature("Small birds") == false and fx.use_creature("songbirds"), "kinds go by id")
	fx.count = 3
	fx.creature = MDSCreatures.Creature.SONGBIRDS
	check(fx.count == 3, "picking the same kind again keeps the changes")
	fx.count = 99
	check(fx.count == MDSCreatures.MAX_COUNT, "at most %d" % MDSCreatures.MAX_COUNT)
	fx.free()

func _all_move() -> void:
	for id in MDSCreatures.CREATURE_IDS:
		var fx := _make(id)
		await get_tree().process_frame
		var start := fx.creature_positions()
		_run_for(fx, 6.0)
		var pts := fx.creature_positions()
		var half := fx._half
		var inside := true
		for p in pts:
			inside = inside and absf(p.x) < half.x + 0.45 and absf(p.y) < half.y + 0.45
		var moved := 0
		for i in pts.size():
			if pts[i].distance_to(start[i]) > 0.005:
				moved += 1
		var m := fx.get_materials()[0]
		check(pts.size() == fx.count and int(m.get_shader_parameter("count")) == fx.count, "%s: %d of them, sent to the shader" % [id, fx.count])
		check(inside, "%s stay about the view" % id)
		check(moved > 0 or id == "owls", "%s move (%d of %d)" % [id, moved, pts.size()])
		fx.free()

func _activity() -> void:
	var fx := _make("bats")
	var hero := _player(Vector2(500, 300))
	_run_for(fx, 1.0)
	check(fx.activity < 0.05, "a still player leaves them calm (%.2f)" % fx.activity)
	for i in 60:
		hero.position.x += 12.0
		fx._tick(DT)
	check(fx.activity > 0.5, "running about stirs them up (%.2f)" % fx.activity)
	_run_for(fx, 3.0)
	check(fx.activity < 0.3, "and they calm down again (%.2f)" % fx.activity)
	# One sudden leap, then still again.
	hero.position.y -= 40.0
	_run_for(fx, 0.3)
	check(fx.activity > 0.2, "a jolt (a jump, a dash) startles them (%.2f)" % fx.activity)
	_run_for(fx, 4.0)
	fx.excitement = 1.0
	_run_for(fx, 1.0)
	check(fx.activity > 0.9, "the game can keep them stirred (excitement)")
	fx.excitement = 0.0
	_run_for(fx, 4.0)
	fx.startle()
	_run_for(fx, 0.5)
	check(fx.activity > 0.5, "startle() from code (%.2f)" % fx.activity)
	fx.free()
	hero.free()

func _reactions() -> void:
	# Birds scatter from a busy player.
	var calm := _make("songbirds")
	var busy := _make("songbirds")
	busy.excitement = 1.0
	var hero := _player(Vector2(576, 324))
	await get_tree().process_frame
	_run_for(calm, 0.1)
	_run_for(busy, 0.1)
	var at := calm.to_view(hero.global_position)
	_run_for(calm, 5.0)
	_run_for(busy, 5.0)
	var d_calm := _mean_distance(calm, at)
	var d_busy := _mean_distance(busy, at)
	check(d_busy > d_calm, "a flock keeps farther from a busy player (%.2f vs %.2f)" % [d_busy, d_calm])
	calm.free()
	busy.free()
	# Moths come to a player standing still.
	var moths := _make("moths")
	moths.reactivity = 1.0
	await get_tree().process_frame
	_run_for(moths, 0.1)
	var spot := moths.to_view(hero.global_position)
	var before := _mean_distance(moths, spot)
	_run_for(moths, 10.0)
	check(_mean_distance(moths, spot) < before, "moths come to a still player, like to a flame (%.2f -> %.2f)" % [before, _mean_distance(moths, spot)])
	moths.free()
	# Spiders climb their threads when it gets busy.
	var calm_sp := _make("spiders")
	var busy_sp := _make("spiders")
	busy_sp.excitement = 1.0
	_run_for(calm_sp, 4.0)
	_run_for(busy_sp, 4.0)
	var thread_calm := 0.0
	var thread_busy := 0.0
	for i in calm_sp._p.size():
		if calm_sp._mode[i] == 1:
			thread_calm += calm_sp._ex[i]
			thread_busy += busy_sp._ex[i]
	check(thread_calm > 0.0 and thread_busy < thread_calm * 0.5, "spiders climb their threads when it's busy (%.2f vs %.2f)" % [thread_busy, thread_calm])
	calm_sp.free()
	busy_sp.free()
	# Snails stop.
	var snails := _make("snails")
	snails.excitement = 1.0
	_run_for(snails, 2.0)
	var still := snails.creature_positions()
	_run_for(snails, 1.0)
	var crept := 0.0
	for i in still.size():
		crept = maxf(crept, snails.creature_positions()[i].distance_to(still[i]))
	check(crept < 0.002, "snails stop when the player is busy (%.4f)" % crept)
	snails.free()
	# Worms come up more often when it's busy.
	var counts := []
	for e in [0.0, 1.0]:
		var worms := _make("worms")
		worms.excitement = e
		var ups := 0
		var was := PackedFloat32Array(worms._ex)
		for k in int(12.0 / DT):
			worms._tick(DT)
			if was.size() != worms._ex.size():
				was = PackedFloat32Array(worms._ex)
			for i in worms._ex.size():
				if was[i] < 0.0 and worms._ex[i] >= 0.0:
					ups += 1
			was = PackedFloat32Array(worms._ex)
		counts.append(ups)
		worms.free()
	check(counts[1] > counts[0], "worms come up more when the player stomps about (%d vs %d)" % [counts[1], counts[0]])
	# Owls look at the player.
	var owls := _make("owls")
	_run_for(owls, 0.1)
	hero.position = Vector2(1140, 324)
	_run_for(owls, 2.0)
	var looks := 0
	for i in owls._p.size():
		if owls._ph[i] > 0.5:
			looks += 1
	check(looks == owls._p.size(), "owls turn their heads to the player (%d of %d)" % [looks, owls._p.size()])
	owls.free()
	hero.free()

func _glow() -> void:
	var fx := _make("lumaflies")
	fx.proximity_glow = 2.0
	var hero := _player(Vector2(576, 324))
	await get_tree().process_frame
	_run_for(fx, 0.5)
	var pts := fx.creature_positions()
	var at := fx.to_view(hero.global_position)
	var near := -1
	var far := -1
	for i in pts.size():
		if near < 0 or pts[i].distance_to(at) < pts[near].distance_to(at):
			near = i
		if far < 0 or pts[i].distance_to(at) > pts[far].distance_to(at):
			far = i
	# Compare without their own blinking: the same kind of glow at the same moment.
	var boost_near := fx._gl[near] / maxf(0.25 + 0.75 * clampf(sin(fx._time * (0.7 + 0.6 * fx._h(near, 3)) + near * 2.3) * 1.4, 0.0, 1.0), 0.001)
	var boost_far := fx._gl[far] / maxf(0.25 + 0.75 * clampf(sin(fx._time * (0.7 + 0.6 * fx._h(far, 3)) + far * 2.3) * 1.4, 0.0, 1.0), 0.001)
	check(boost_near > boost_far, "those near the player glow brighter (%.2f vs %.2f)" % [boost_near, boost_far])
	check(fx.light_color() == fx.glow_color, "with no area, their light is their own")
	fx.area_color = Color(0.2, 0.4, 1.0)
	fx.area_tint = 0.5
	check(fx.light_color().is_equal_approx(fx.glow_color.lerp(Color(0.2, 0.4, 1.0, fx.glow_color.a), 0.5)), "their light takes the area's color")
	check((fx.get_materials()[0].get_shader_parameter("glow_color") as Color).is_equal_approx(fx.light_color()), "the shader lights with it")
	fx.free()
	hero.free()

func _harmless() -> void:
	var fx := _make("wasps")
	fx.excitement = 1.0
	var hero := _player(Vector2(300, 300))
	hero.velocity = Vector2(120, 0)
	await physics_frames(5)
	var bodies := fx.get_children(true).filter(func(n: Node) -> bool: return n is CollisionObject2D)
	check(bodies.is_empty(), "nothing in it collides")
	check(hero.velocity == Vector2(120, 0) and hero.position == Vector2(300, 300), "it never moves or slows the player")
	var hurt := [0]
	fx.body_hurt.connect(func(_b: Node2D, _a: float) -> void: hurt[0] += 1)
	await physics_frames(5)
	check(hurt[0] == 0, "nor hurts it")
	fx.free()
	hero.free()

func _specs() -> void:
	check(MDSEnvironment.background_spec("bats") == "creatures(creature=bats)", "a creature id is a background")
	check(MDSEnvironment.background_spec("owls(count=3)") == "creatures(creature=owls, count=3)", "with settings")
	check(MDSEnvironment.background_spec("blood_moon, bats") == "animated_background(style=blood_moon), creatures(creature=bats, backdrop=0)", "a style and creatures: they fly in front of it, with no habitat of their own")
	check(MDSEnvironment.background_spec("void_pulse, spiders(backdrop=0.5)") == "animated_background(style=void_pulse), creatures(creature=spiders, backdrop=0.5)", "unless told otherwise")
	check(MDSEnvironment.background_spec("aurora") == "animated_background(style=aurora)", "styles as before")
	check(MDSEnvironment.check_background("bats").is_empty() and MDSEnvironment.check_background("blood_moon, owls").is_empty() and MDSEnvironment.check_background("creatures(creature=worms)").is_empty(), "good values have no problem")
	var problem := MDSEnvironment.check_background("batz")
	check(problem.contains("not an animated background style") and problem.contains("bats"), "a mistyped creature is reported, naming them (%s)" % problem.left(60))
	var room := Rect2(0, 0, 1152, 648)
	var node := MDSEnvironment.build_background("blood_moon, owls", room)
	var fx := MDSEnvironment.effects_in(node)
	check(fx.size() == 2 and fx[0] is MDSAnimatedBackground and fx[1] is MDSCreatures, "build_background makes both")
	var owls := fx[1] as MDSCreatures
	check(owls.creature == MDSCreatures.Creature.OWLS and is_equal_approx(owls.backdrop, 0.0) and Rect2(owls.position, owls.size).encloses(room), "owls over the moon, covering the room")
	MDSEnvironment.apply_area_color(node, Color(0.1, 0.9, 0.3))
	check(owls.area_color == Color(0.1, 0.9, 0.3), "apply_area_color tints them")
	node.free()

## The background fields' menu: a creature on its own, or after the style already there.
func _field() -> void:
	var grid := GridContainer.new()
	var got: Array = []
	var edit := MDSUi.background_field(grid, "Boss room bg", "blood_moon", "", func(t: String) -> void: got.append(t))
	var menu: MenuButton = edit.get_parent().get_child(1)
	var popup := menu.get_popup()
	var bats := -1
	var creatures := 0
	for i in popup.item_count:
		var m: Variant = popup.get_item_metadata(i)
		if m is Array:
			creatures += 1
			if m[1] == "bats":
				bats = i
	check(creatures == 20, "the menu lists the twenty creatures (%d)" % creatures)
	popup.index_pressed.emit(bats)
	check(edit.text == "blood_moon, bats" and got.has("blood_moon, bats"), "picking one adds it after the style (%s)" % edit.text)
	popup.index_pressed.emit(bats)
	check(edit.text == "blood_moon, bats", "picking it again doesn't add it twice")
	edit.text = "owls"
	popup.index_pressed.emit(bats)
	check(edit.text == "bats", "and replaces other creatures")
	grid.free()

func _in_game() -> void:
	var world := Fixture.build()
	world.set_room_value("Crypt_01", "boss", "Warden")
	world.set_setting("boss_background", "spiders")
	world.save()
	MDSWorld._cache.erase(Fixture.WORLD)
	var game := Fixture.make_game()
	add_child(game)
	await game.room_loaded
	check(game.background == null, "an ordinary room has none")
	game.load_room("Crypt_01", "left1")
	await game.room_loaded
	var fx := MDSEnvironment.effects_in(game.background) if game.background else []
	check(fx.size() == 1 and fx[0] is MDSCreatures and (fx[0] as MDSCreatures).creature == MDSCreatures.Creature.SPIDERS, "the boss room has its creatures")
	if not fx.is_empty():
		check((fx[0] as MDSCreatures).area_color == world.get_area_color("Crypt"), "lit with the Crypt's color")
	game.queue_free()
	await get_tree().process_frame

func _canvas() -> void:
	var world := Fixture.build()
	world.set_area_value("Gardens", "background", "lumaflies")
	var painter := MDSRoomPainter.open(world.get_scene_path("Garden_01"))
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(800, 500)
	add_child(canvas)
	canvas.open(world, "Garden_01", painter)
	var preview := canvas.get_background_preview()
	var fx := MDSEnvironment.effects_in(preview) if preview else []
	check(fx.size() == 1 and fx[0] is MDSCreatures and (fx[0] as MDSCreatures).area_color == world.get_area_color("Gardens"), "the Room view shows them, in the area's light")
	canvas.close()
	canvas.queue_free()
	painter.free_instance()
	await get_tree().process_frame

func _saved() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var root := Node2D.new()
	var fx := MDSCreatures.new()
	fx.name = "Fx"
	root.add_child(fx)
	fx.owner = root
	fx.creature = MDSCreatures.Creature.OWLS
	fx.count = 26 # the script's default, not the owls'
	fx.reactivity = 0.2
	save_scene(root, TMP + "/creatures.tscn")
	root.free()
	var back := (ResourceLoader.load(TMP + "/creatures.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var b := back.get_node("Fx") as MDSCreatures
	check(b.creature == MDSCreatures.Creature.OWLS and b.count == 26 and is_equal_approx(b.reactivity, 0.2), "a saved background keeps its kind and its settings")
	back.free()

func _data() -> void:
	var fx := MDSCreatures.new()
	fx.creature = MDSCreatures.Creature.CRABS
	fx.count = 4
	var d := fx.to_data()
	fx.creature = MDSCreatures.Creature.BEES
	MDSEnvironmentEffect.apply_data(fx, d)
	check(fx.creature == MDSCreatures.Creature.CRABS and fx.count == 4, "restoring a snapshot undoes a change of kind (Room view undo)")
	fx.free()
