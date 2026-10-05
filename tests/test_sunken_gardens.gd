extends "res://tests/test_case.gd"
## Brief 8: the Sunken Gardens asset pack.

const PACK := "res://asset_packs/sunken_gardens"

func _run() -> void:
	_resources()
	await _demo_runs()

func _resources() -> void:
	var styles := IDPFreeformStyle.find_in_project()
	var names: PackedStringArray = []
	for st in styles:
		names.append(st.get_display_name())
	for want in ["Garden limestone", "Garden ledge", "Sunken ruin (background)", "Deep ground", "Garden foreground leaves"]:
		check(want in names, "%s is in the Room view's style list" % want)
	var ledge := load(PACK + "/freeform/styles/garden_ledge.freeform.tres") as IDPFreeformStyle
	check(ledge.get_role() == IDPFreeformStyle.Role.PLATFORM and ledge.is_one_way() and not ledge.has_meta(&"one_way_platform"), "the ledge uses the one-way export, not metadata")
	var deep := load(PACK + "/freeform/styles/sunken_deep.freeform.tres") as IDPFreeformStyle
	check(deep.get_role() == IDPFreeformStyle.Role.DECOR, "deep ground is a decoration")
	var stamps := load(PACK + "/freeform/sunken_gardens.stamps.tres") as IDPStampSet
	check(stamps and stamps.regions.size() == 24 and stamps.texture != null, "the stamp set has its 24 clumps")
	check(IDPStampSet.find_in_project().has(stamps), "the stamp set is in the Stamps list")
	for f in DirAccess.get_files_at(PACK + "/freeform/styles"):
		if f.ends_with(".tres"):
			var text := FileAccess.get_file_as_string(PACK + "/freeform/styles/" + f)
			check(not text.contains("res://sprites/"), "%s points into the pack" % f)
	var by := IDPFreeformDecorator.categories_by_anchor(stamps)
	check("ivy" in by.hang and "grass" in by.stand, "Decorate guesses hanging and standing categories (%s)" % by)

func _demo_runs() -> void:
	var scene := (load(PACK + "/demo/sunken_garden_demo.tscn") as PackedScene).instantiate()
	add_child(scene)
	var player := scene.get_node("Player") as CharacterBody2D
	for i in 90:
		await get_tree().physics_frame
	check(player.is_on_floor(), "the demo runs: its player stands on the floor (at %s)" % player.position)
	check_near(player.position.y + 32.0, 1200.0, 6.0, "on the lower floor")
	var ledges := IDPFreeform.platforms_in(scene)
	check(ledges.size() == 3 and ledges.all(func(f: IDPFreeform) -> bool: return f.is_one_way()), "the demo has three one-way garden ledges")
	check(IDPFreeform.shapes_in(scene).all(func(f: IDPFreeform) -> bool: return f.is_outline_simple()), "every shape of the demo is simple")
	scene.queue_free()
	await get_tree().process_frame
	var host := SubViewport.new()
	add_child(host)
	var c := IDPRoomCheck.new()
	c.room_rects = [Rect2(0, 0, 2304, 648), Rect2(0, 648, 1152, 648)]
	var fresh := (load(PACK + "/demo/sunken_garden_demo.tscn") as PackedScene).instantiate()
	c.build_from_scene(fresh, host)
	c.run()
	check(c.issues.is_empty(), "the demo passes the room checks: %s" % [c.issues.map(func(i: Dictionary) -> String: return i.message)])
	var reach := c.surfaces.filter(func(s: Dictionary) -> bool: return s.reachable).size()
	check(reach == c.surfaces.size(), "every floor of the demo can be reached (%d of %d)" % [reach, c.surfaces.size()])
	c.free_proxy()
	fresh.free()
	host.queue_free()
