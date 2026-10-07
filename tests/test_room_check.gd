extends "res://tests/test_case.gd"
## Brief 6: physics-level room checks.

var host: SubViewport

func _run() -> void:
	host = SubViewport.new()
	host.disable_3d = true
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.size = Vector2i(4, 4)
	add_child(host)
	_room_issues(false)
	# The editor doesn't step physics: the checks must work there too.
	PhysicsServer2D.set_active(false)
	_room_issues(true)
	PhysicsServer2D.set_active(true)
	_climb_needs_ledges()
	_demo_reports_nothing()
	_issues_tab_and_painter()
	host.queue_free()

## The background checker feeds the Issues tab; the Room view checks the painted room.
func _issues_tab_and_painter() -> void:
	var path := TMP + "/brief6_room.tscn"
	var room := _room()
	for c in room.get_children():
		c.owner = null
	check(save_scene(room, path) == OK, "the test room saves")
	room.free()
	var world := MDSWorld.new()
	var id := world.add_room("Shaft_01", Rect2(0, 0, 1152, 648), 0, "", path)
	world.get_gates(id)["left1"] = {"pos": [0, 520], "side": "left"}
	world.get_gates(id)["right1"] = {"pos": [1152, 520], "side": "right"}
	var job := {"path": path, "name": id, "rects": world.get_local_rects(id), "passages": MDSRoomCheck.passages_from_world(world, id), "player": {}}
	var found := MDSGeometryChecker.check_now(job, host)
	check(found.any(func(i: Dictionary) -> bool: return i.kind == "passage" and i.message.begins_with("Shaft_01: gate right1")), "the background check finds the blocked gate")
	var meta := MDSSceneScanner.new().analyze_scene(path, false)
	meta.geometry = found
	var db := {path: meta}
	var analysis := MDSAnalysis.new(MDSGraph.from_world(world, db), world, db).run()
	var issues := MDSWorldValidator.run(world, analysis, db)
	var geo := issues.filter(func(i: Dictionary) -> bool: return i.category == MDSValidator.CATEGORY_GEOMETRY and i.message.contains("right1"))
	check(geo.size() == 1 and geo[0].room_id == id and geo[0].pos == Vector2(1152, 520), "Issues > Geometry reports the gate, and jumps to it")
	# The Room view checks the room as painted: closing the left doorway shows up at once.
	var painter := MDSRoomPainter.open(path, TileSet.new())
	painter.add_freeform(rect_points(Rect2(-96, 400, 200, 200)), MDSFreeformStyle.new())
	var c := MDSRoomCheck.new()
	c.room_rects = world.get_local_rects(id)
	c.passages = MDSRoomCheck.passages_from_world(world, id)
	c.build_from_painter(painter, host)
	c.run()
	check(_has(c, "passage", "left1"), "a doorway closed in the Room view is reported: %s" % [_kinds(c)])
	c.free_proxy()
	painter.free_instance()

func _rock(parent: Node, r: Rect2, one_way := false) -> MDSFreeform:
	var f := MDSFreeform.new()
	f.smooth = false
	f.points = rect_points(r)
	if one_way:
		f.set_collision_override(MDSFreeformStyle.Role.PLATFORM, true)
	parent.add_child(f)
	return f

## A 1152 x 648 room: floor, walls, a ceiling with a hole for top1, a stair of one-way
## ledges up to it. left1 is open; right1 is walled up.
func _room(with_ledges := true) -> Node2D:
	var room := Node2D.new()
	room.name = "Room"
	_rock(room, Rect2(-96, 576, 1344, 168)) # floor
	_rock(room, Rect2(-96, -96, 160, 552)) # left wall, open below 456
	_rock(room, Rect2(1088, -96, 160, 700)) # right wall, closes right1
	_rock(room, Rect2(-96, -96, 576, 160)) # ceiling, left of the hole
	_rock(room, Rect2(680, -96, 568, 160)) # ceiling, right of the hole
	if with_ledges:
		for y in [440, 300, 170]:
			var ledge := _rock(room, Rect2(380, y, 240, 24), true)
			ledge.name = "Step%d" % y
	# A ledge 30 px under a rock.
	var low := _rock(room, Rect2(860, 330, 160, 24), true)
	low.name = "LowLedge"
	_rock(room, Rect2(840, 240, 200, 60))
	for p in [["SaveOk", Vector2(200, 576)], ["SaveFloating", Vector2(300, 450)], ["SaveBuried", Vector2(1000, 630)]]:
		var s := Node2D.new()
		s.name = p[0]
		s.position = p[1]
		s.add_to_group(&"save_point")
		room.add_child(s)
	return room

func _check(room: Node2D) -> MDSRoomCheck:
	var c := MDSRoomCheck.new()
	c.room_rects = [Rect2(0, 0, 1152, 648)]
	c.passages = [
		{"name": "left1", "pos": Vector2(0, 520), "side": "left"},
		{"name": "right1", "pos": Vector2(1152, 520), "side": "right"},
		{"name": "top1", "pos": Vector2(576, 0), "side": "top"},
	]
	c.build_from_scene(room, host)
	c.run("Test")
	return c

func _kinds(c: MDSRoomCheck) -> Array:
	return c.issues.map(func(i: Dictionary) -> String: return "%s:%s" % [i.kind, i.message])

func _has(c: MDSRoomCheck, kind: String, text: String) -> bool:
	return c.issues.any(func(i: Dictionary) -> bool: return i.kind == kind and i.message.contains(text))

func _room_issues(inactive: bool) -> void:
	var tag := " (physics inactive, as in the editor)" if inactive else ""
	var room := _room()
	var c := _check(room)
	check(_has(c, "passage", "right1"), "the walled-up doorway is reported" + tag)
	check(not _has(c, "passage", "left1"), "the open doorway is not reported" + tag)
	check(not _has(c, "passage", "top1"), "the hole in the ceiling is open" + tag)
	check(_has(c, "headroom", "LowLedge"), "the ledge 30 px under rock reports headroom" + tag)
	check(not _has(c, "headroom", "Step"), "the stair's ledges have headroom" + tag)
	check(_has(c, "floating", "SaveFloating"), "the floating save point is reported" + tag)
	check(_has(c, "buried", "SaveBuried"), "the buried save point is reported" + tag)
	check(not _has(c, "floating", "SaveOk") and not _has(c, "buried", "SaveOk"), "the save point on the floor is fine" + tag)
	check(not _has(c, "climb", "top1"), "the stair climbs to the top exit" + tag)
	check(c.issues.size() == 4, "nothing else is reported%s: %s" % [tag, _kinds(c)])
	check(c.surfaces.any(func(s: Dictionary) -> bool: return s.reachable), "some floors are reachable" + tag)
	c.free_proxy()
	room.free()

func _climb_needs_ledges() -> void:
	var room := _room(false)
	var c := _check(room)
	check(_has(c, "climb", "top1"), "without ledges the top exit is out of reach: %s" % [_kinds(c)])
	var r := c.simulate_jump(Vector2(200, 576), 200)
	check(r.landed and absf(r.pos.y - 576) < 2.0, "a jump on the spot lands back on the floor (%s)" % r)
	check_near(576.0 - r.peak, c.get_max_jump_height(), 20.0, "the jump rises about v²/2g")
	c.free_proxy()
	room.free()

func _demo_reports_nothing() -> void:
	for path in ["res://asset_packs/mossgrove/demo/freeform_cave.tscn", "res://asset_packs/mossgrove/demo/mossgrove_demo.tscn"]:
		var meta := MDSSceneScanner.new().analyze_scene(path, false)
		var scene := (load(path) as PackedScene).instantiate()
		var c := MDSRoomCheck.new()
		var bounds: Array[Rect2] = []
		var mb := scene.get_node_or_null("MapBounds")
		if mb:
			for r in mb.get_children():
				bounds.append(Rect2((r as Control).position, (r as Control).size))
		else:
			bounds.append(meta.content_rect)
		c.room_rects = bounds
		c.build_from_scene(scene, host)
		c.run()
		check(c.issues.is_empty(), "%s reports nothing: %s" % [path.get_file(), _kinds(c)])
		c.free_proxy()
		scene.free()
