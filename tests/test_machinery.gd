extends "res://tests/test_case.gd"
## Machinery backgrounds (MDSMachineryBackground): forty machines, twenty gothic (Castlevania-
## style castles) and twenty sci-fi (Metroid-style stations), each laid out as its kind says
## (hanging, standing, spread about, one big one in front) on screen-sized cells of the room,
## drawn by its theme's shader, fixed in the world and moving by time alone (nothing the
## player or the camera does moves them), and set from the background fields.

func _run() -> void:
	_catalog()
	_layouts()
	await _time_only()
	_specs()
	_saved()
	_menu()

func _catalog() -> void:
	var ids := MDSMachineryBackground.MACHINE_IDS
	var unique: Dictionary = {}
	for id in ids:
		unique[id] = true
	check(ids.size() == 40 and unique.size() == 40, "forty machines, each its own id")
	check(MDSMachineryBackground.MACHINE_NAMES.size() == 40 and MDSMachineryBackground.MACHINE_INFO.size() == 40 and MDSMachineryBackground.Machine.size() == 40, "each named and described")
	check(MDSMachineryBackground.GOTHIC_IDS.size() == 20 and MDSMachineryBackground.SCIFI_IDS.size() == 20, "twenty gothic, twenty sci-fi")
	check(MDSMachineryBackground.GOTHIC_IDS.has("giant_wheels") and MDSMachineryBackground.GOTHIC_IDS.has("clockwork") and MDSMachineryBackground.SCIFI_IDS.has("reactor_cores"), "giant wheels and clockwork are gothic, reactor cores sci-fi")
	check(Array(ids).all(func(id: String) -> bool: return MDSMachineryBackground.LOOKS.has(id) and MDSMachineryBackground.LAYOUTS.has(id)), "each has its look and layout")
	var clash := Array(ids).filter(func(id: String) -> bool: return MDSAnimatedBackground.STYLE_IDS.has(id) or MDSCreatures.CREATURE_IDS.has(id) or MDSEnvironment.EFFECTS.has(id))
	check(clash.is_empty(), "no machine id is also a style, a creature or an effect (%s)" % [clash])
	var fx := MDSEnvironment.create("machinery") as MDSMachineryBackground
	check(fx != null and fx.z_index == -108 and fx.affect_groups.is_empty() and MDSEnvironment.icon("machinery") != null, "the machinery background is an effect, between the animated background and the creatures, acting on nobody")
	fx.free()

func _layouts() -> void:
	var m := MDSMachineryBackground.new()
	var aspect := 16.0 / 9.0
	var ok_order := true
	var ok_view := true
	var ok_place := true
	for i in MDSMachineryBackground.MACHINE_IDS.size():
		var id := MDSMachineryBackground.MACHINE_IDS[i]
		m.use_machine(id)
		check(m.count == int(MDSMachineryBackground.LOOKS[id].count), "%s: its count" % id) if i == 0 else null
		var l := m.layout(aspect)
		var a: PackedVector4Array = l[0]
		var b: PackedVector4Array = l[1]
		if a.size() != m.count or b.size() != m.count:
			ok_view = false
		var rule: Array = MDSMachineryBackground.LAYOUTS[id]
		for k in a.size():
			var p := a[k]
			if k > 0 and p.w > a[k - 1].w + 1e-6:
				ok_order = false
			if absf(p.x) > aspect * 0.5 * 1.05 + p.z * 2.2 or p.z < rule[1] - 1e-4 or p.z > rule[2] + 1e-4 or p.w < 0.0 or p.w > 1.0:
				ok_view = false
			if rule[0] == "hang" and absf(p.y - p.z - (-0.5)) > p.z * 0.2:
				ok_place = false
			if rule[0] == "stand" and absf(p.y + p.z - 0.5) > p.z * 0.11:
				ok_place = false
			if absf(b[k].w) != 1.0:
				ok_view = false
	check(ok_order, "machines are drawn far to near")
	check(ok_view, "each layout has its count, sizes in its range, on the view")
	check(ok_place, "hanging ones hang from the top, standing ones stand on the bottom")
	m.use_machine("clock_faces")
	var hero: PackedVector4Array = m.layout(aspect)[0]
	var big := hero[0]
	for p in hero:
		if p.z > big.z:
			big = p
	check(is_equal_approx(big.z, float(MDSMachineryBackground.LAYOUTS.clock_faces[2])) and is_equal_approx(big.w, 0.3), "a hero layout puts one big clock in front")
	var clear := true
	for p in hero:
		if p != big and absf(p.x - big.x) < big.z * 1.3:
			clear = false
	check(clear, "the smaller ones stand clear of it")
	var again: PackedVector4Array = m.layout(aspect)[0]
	check(again == hero, "the same layout every time")
	m.seed_value = 7
	check(m.layout(aspect)[0] != hero, "another seed, another layout")
	m.use_machine("clockwork")
	var paces: Array = Array(m.layout(aspect)[1]).map(func(v: Vector4) -> float: return v.y)
	check(paces.any(func(p: float) -> bool: return p < 0.0) and paces.any(func(p: float) -> bool: return p > 0.0), "cogwheels turn both ways")
	m.use_machine("clock_faces")
	check(Array(m.layout(aspect)[1]).all(func(v: Vector4) -> bool: return v.y > 0.0 and v.w == 1.0), "clocks always go forward, never mirrored")
	m.free()

func _time_only() -> void:
	var host := SubViewport.new()
	host.size = Vector2i(640, 360)
	add_child(host)
	var m := MDSMachineryBackground.new()
	m.size = Vector2(1152, 648)
	m.use_machine("reactor_cores")
	host.add_child(m)
	await get_tree().process_frame
	var mat: ShaderMaterial = m.get_materials()[0]
	check(mat.shader.resource_path.ends_with("machinery_scifi.gdshader") and int(mat.get_shader_parameter("kind")) == 1 and int(mat.get_shader_parameter("count")) == m.count, "a sci-fi machine is drawn by the sci-fi shader, its kind and count sent")
	check((mat.get_shader_parameter("inst_a") as PackedVector4Array).size() == MDSMachineryBackground.MAX_COUNT, "the places go to the shader")
	m.use_machine("giant_wheels")
	await get_tree().process_frame
	await get_tree().process_frame
	mat = m.get_materials()[0]
	check(mat.shader.resource_path.ends_with("machinery_gothic.gdshader") and int(mat.get_shader_parameter("kind")) == 0, "a gothic one by the gothic shader")
	check(mat.shader.get_shader_uniform_list().all(func(u: Dictionary) -> bool: return not str(u.name) in ["drift", "view_rect"]), "the shader knows nothing of the view or the camera")
	# A camera and a player moving over it change nothing: the machines are fixed in the world.
	var cam := Camera2D.new()
	host.add_child(cam)
	cam.make_current()
	var player := CharacterBody2D.new()
	player.add_to_group(&"player")
	host.add_child(player)
	var keys := ["inst_a", "inst_b", "count", "unit", "layout_rect", "rect_origin", "rect_size"]
	var snapshot := func() -> Array: return keys.map(func(k: String) -> Variant: return mat.get_shader_parameter(k))
	var before: Array = snapshot.call()
	var places := m.machine_places()
	var quad := (m.get_materials()[0] as ShaderMaterial)
	for step in 10:
		cam.position = Vector2(step * 150.0, step * 40.0)
		cam.zoom = Vector2.ONE * (1.0 + step * 0.1)
		player.position = Vector2(step * 120.0, 300.0 + step * 20.0)
		await get_tree().process_frame
		await get_tree().physics_frame
	check(snapshot.call() == before and m.machine_places() == places and quad == m.get_materials()[0], "the camera and the player moving change nothing in it")
	check(m.bodies_inside().is_empty() and m.affect_groups.is_empty(), "and it acts on nobody")
	m.queue_free()
	await get_tree().process_frame
	# A room four screens big: four cells, each with machines of its own, standing on the floor.
	var big := MDSMachineryBackground.new()
	big.use_machine("castle_spires")
	big.fit_room = true
	var room := Rect2(0, 0, 2304, 1296)
	big.fit_to(room.grow(MDSEnvironment.ROOM_MARGIN))
	host.add_child(big)
	await get_tree().process_frame
	check(big.layout_rect().is_equal_approx(Rect2(room.position - big.position, room.size)) and big.cell_grid() == Vector2i(2, 2), "a room four screens big is laid out in four cells (%s)" % big.cell_grid())
	var unit := big.cell_height()
	var pl := big.machine_places()
	check(pl.size() == 4 * big.count and is_equal_approx(unit, 648.0), "each with its machines (%d)" % pl.size())
	var on_floor := 0
	var inside := true
	for p in pl:
		var at := Vector2(p.x, p.y) * unit
		if not big.layout_rect().grow(p.z * unit * 2.0).has_point(at):
			inside = false
		if absf(at.y + p.z * unit - big.layout_rect().end.y) < p.z * unit * 0.11:
			on_floor += 1
	check(inside and on_floor == 2 * big.count, "spread over the room, the two bottom cells' spires standing on its floor (%d)" % on_floor)
	big.count = 12
	await get_tree().process_frame
	check(big.machine_places().size() <= MDSMachineryBackground.MAX_COUNT, "never more than the most a background draws")
	host.queue_free()
	await get_tree().process_frame

func _specs() -> void:
	check(MDSEnvironment.background_spec("clockwork") == "machinery(machine=clockwork)", "a machine id is a background")
	check(MDSEnvironment.background_spec("turbines(count=8)") == "machinery(machine=turbines, count=8)", "with settings")
	check(MDSEnvironment.background_spec("storm_clouds, castle_spires") == "animated_background(style=storm_clouds), machinery(machine=castle_spires, backdrop=0)", "after a style it draws no backdrop of its own")
	check(MDSEnvironment.check_background("clock_faces").is_empty() and MDSEnvironment.check_background("frozen_night, windmills").is_empty(), "good values have no problem")
	var problem := MDSEnvironment.check_background("clockworks")
	check(problem.contains("a machine") and problem.contains("clockwork"), "a mistyped machine is reported, naming them")
	var room := Rect2(0, 0, 1152, 648)
	var node := MDSEnvironment.build_background("storm_clouds, warp_portals(count=1)", room)
	var fx := MDSEnvironment.effects_in(node)
	check(fx.size() == 2 and fx[0] is MDSAnimatedBackground and fx[1] is MDSMachineryBackground, "build_background makes both")
	var portals := fx[1] as MDSMachineryBackground
	check(portals.machine == MDSMachineryBackground.Machine.WARP_PORTALS and portals.count == 1 and not portals.backdrop and Rect2(portals.position, portals.size).encloses(room), "portals in front of the storm, covering the room")
	node.free()

func _saved() -> void:
	var root := Node2D.new()
	root.name = "MachineRoom"
	var m := MDSMachineryBackground.new()
	m.name = "Works"
	m.use_machine("banners")
	m.count = 3
	m.metal_color = Color("#3a3030")
	root.add_child(m)
	var path := TMP + "/machinery_room.tscn"
	check(save_scene(root, path) == OK, "saved a room with banners")
	root.free()
	var back := (load_fresh(path) as PackedScene).instantiate()
	var w := back.get_node("Works") as MDSMachineryBackground
	check(w.machine == MDSMachineryBackground.Machine.BANNERS and w.count == 3 and w.metal_color == Color("#3a3030") and w.accent_color == MDSMachineryBackground.LOOKS.banners.accent_color, "it comes back as it was, its look kept (%s, %d)" % [MDSMachineryBackground.MACHINE_IDS[w.machine], w.count])
	back.free()

func _menu() -> void:
	var grid := GridContainer.new()
	var got: Array = []
	var edit := MDSUi.background_field(grid, "Animated bg", "storm_clouds", "", func(t: String) -> void: got.append(t))
	var popup := (edit.get_parent().get_child(1) as MenuButton).get_popup()
	var machines := 0
	var spires := -1
	for i in popup.item_count:
		var meta: Variant = popup.get_item_metadata(i)
		if meta is Array and meta[0] == "machine":
			machines += 1
			if meta[1] == "castle_spires":
				spires = i
			check(popup.get_item_icon(i) != null, "%s has an icon" % meta[1]) if machines == 1 else null
	check(machines == 40, "the menu lists the forty machines (%d)" % machines)
	popup.index_pressed.emit(spires)
	check(edit.text == "storm_clouds, castle_spires" and got.has("storm_clouds, castle_spires"), "picking one adds it after the style (%s)" % edit.text)
	grid.free()
