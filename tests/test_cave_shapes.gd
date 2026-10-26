extends "res://tests/test_case.gd"
## Caves of shapes (MDSCaveShapes): Generate cave carves a room's open space as a T, U, H, L, i
## (a shaft and its chamber), cross, ring, S, a freeform cave, a mix of them or several picked,
## turned by any angle (or each at random), one or several in a room, joined by tunnels. As a cave
## their edges are rough and their tall parts get ledges; linear, their walls are straight, their
## floors flat, and their tall parts smooth walls the player climbs (the paths too). The room's
## gates still reach each other both ways. The Room view's Cave shape picks it for Generate cave,
## New variation, Generate all and New variation for all (the Full view too). And a room dragged in
## the Full view takes its tiles along, an L, T or U room's too (its mask moves).

const DIR := TMP + "/cave_shapes"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	_geometry()
	_more_shapes()
	_wall_climb()
	_walkable()
	await _room_view()
	await _drag_takes_tiles()

## A box of cells (0, 0) to [param size] - 1.
static func _box(size: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for y in size.y:
		for x in size.x:
			out[Vector2i(x, y)] = true
	return out

## The share of the open cells in the box [param r].
static func _share(cells: Dictionary, r: Rect2i) -> float:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if cells.has(Vector2i(x, y)):
				n += 1
	return float(n) / maxf(1.0, r.get_area())

func _geometry() -> void:
	var inside := _box(Vector2i(60, 40))
	var rng := RandomNumberGenerator.new()
	var carve := func(shape: String, turn := 0, count := 1) -> Dictionary:
		rng.seed = 7
		return MDSCaveShapes.carve(inside, Vector2i.ZERO, Vector2i(59, 39), {"shape": shape, "rotation": turn, "count": count}, rng, 4)
	var t: Dictionary = carve.call("t")
	var top := _share(t.cells, Rect2i(8, 6, 44, 6))
	var bottom_middle := _share(t.cells, Rect2i(26, 28, 8, 6))
	var bottom_side := _share(t.cells, Rect2i(4, 28, 12, 6))
	check(top > 0.6 and bottom_middle > 0.6 and bottom_side < 0.1, "a T: a bar across the top, a stem down the middle (%.2f %.2f %.2f)" % [top, bottom_middle, bottom_side])
	var t180: Dictionary = carve.call("t", 180)
	check(_share(t180.cells, Rect2i(8, 28, 44, 6)) > 0.6 and _share(t180.cells, Rect2i(4, 6, 12, 6)) < 0.1, "turned 180 degrees: the bar along the bottom")
	var t90: Dictionary = carve.call("t", 90)
	check(_share(t90.cells, Rect2i(46, 6, 6, 28)) > 0.6 and _share(t90.cells, Rect2i(6, 4, 10, 8)) < 0.1, "turned 90 degrees: the bar down the right side")
	var u: Dictionary = carve.call("u")
	check(_share(u.cells, Rect2i(26, 4, 8, 10)) < 0.1 and _share(u.cells, Rect2i(26, 30, 8, 4)) > 0.6 and _share(u.cells, Rect2i(6, 6, 6, 20)) > 0.6, "a U: open at the top, joined at the bottom")
	var h: Dictionary = carve.call("h", 90)
	check(_share(h.cells, Rect2i(10, 4, 40, 4)) > 0.6 and _share(h.cells, Rect2i(10, 32, 40, 4)) > 0.6 and _share(h.cells, Rect2i(28, 14, 4, 12)) > 0.6, "an H turned: two bars across, joined down the middle")
	var ring: Dictionary = carve.call("ring")
	check(_share(ring.cells, Rect2i(24, 16, 12, 8)) < 0.1, "a ring is hollow")
	for shape in ["l", "cross", "s", "freeform", "mixed"]:
		var c: Dictionary = carve.call(shape)
		check(c.cells.size() > 200 and MDSAreaGenerator.components(c.cells).size() == 1, "%s: one cave (%d cells)" % [shape, c.cells.size()])
	# Several: side by side along the long side, joined.
	var three: Dictionary = carve.call("u", 0, 3)
	check(three.boxes.size() == 3 and three.boxes[0].position.x < three.boxes[1].position.x, "three shapes side by side")
	check(MDSAreaGenerator.components(three.cells).size() == 1, "joined into one cave")
	# Inside the room only, a wall left at its edge.
	var edge_open := false
	for c: Vector2i in three.cells:
		edge_open = edge_open or c.x <= 0 or c.y <= 0 or c.x >= 59 or c.y >= 39
	check(not edge_open, "inside the room, a wall at its edge")
	# The tall parts get ledges on alternate sides.
	var ladders := MDSCaveShapes.ladders(u.cells, u.uprights, 4)
	var rows: Dictionary = {}
	for c in ladders:
		rows[c.y] = true
	check(u.uprights.size() >= 2 and rows.size() >= 3, "the U's legs get ledges to climb (%d rows)" % rows.size())
	var rock := MDSCaveShapes.rock(inside, Vector2i.ZERO, Vector2i(59, 39), {"shape": "u"}, rng, 4, 4)
	check(rock.has(Vector2i(0, 0)) and ladders.all(func(c: Vector2i) -> bool: return rock.has(c) or not u.cells.has(c)), "the rock: the box but the shape, ledges in")
	check(not MDSCaveShapes.wanted({"shape": "natural"}) and MDSCaveShapes.wanted({"shape": "h"}) and not MDSCaveShapes.wanted({}), "Natural is the cave from the room's outline")

func _more_shapes() -> void:
	var inside := _box(Vector2i(60, 40))
	var rng := RandomNumberGenerator.new()
	var carve := func(cave: Dictionary) -> Dictionary:
		rng.seed = 7
		return MDSCaveShapes.carve(inside, Vector2i.ZERO, Vector2i(59, 39), cave, rng, 4)
	# An i: its stem, its chamber over it, a narrow neck between.
	var i: Dictionary = carve.call({"shape": "i"})
	check(_share(i.cells, Rect2i(26, 22, 8, 10)) > 0.6 and _share(i.cells, Rect2i(27, 4, 6, 4)) > 0.8 and _share(i.cells, Rect2i(4, 4, 14, 30)) < 0.05, "an i: a stem, its dot a chamber over it (%.2f %.2f)" % [_share(i.cells, Rect2i(26, 22, 8, 10)), _share(i.cells, Rect2i(27, 4, 6, 4))])
	check(_share(i.cells, Rect2i(29, 12, 2, 3)) > 0.9 and _share(i.cells, Rect2i(22, 12, 4, 3)) < 0.1, "joined by a narrow neck")
	check(MDSAreaGenerator.components(i.cells).size() == 1, "one cave")
	# Any angle: 45 degrees slants a T, and it stays in its box.
	var t45: Dictionary = carve.call({"shape": "t", "rotation": 45})
	var lo := Vector2i(99, 99)
	var hi := Vector2i(-1, -1)
	for c: Vector2i in t45.cells:
		lo = lo.min(c)
		hi = hi.max(c)
	var t0: Dictionary = carve.call({"shape": "t", "rotation": 0})
	check(t45.cells.size() > 150 and t45.cells != t0.cells and lo.x >= 1 and lo.y >= 1 and hi.x <= 58 and hi.y <= 38, "a T turned 45 degrees: slanted, in its room (%s to %s)" % [lo, hi])
	var t90 := MDSCaveShapes._turned_points([Vector2(0.5, 0.2)], 90.0)
	check(t90[0].is_equal_approx(Vector2(0.8, 0.5)), "right angles turn exactly (%s)" % t90[0])
	var t33: Dictionary = carve.call({"shape": "u", "rotation": 33})
	check(t33.turns.size() == 1 and is_equal_approx(t33.turns[0], 33.0), "any angle, 33 degrees too")
	var randoms: Dictionary = carve.call({"shape": "h", "rotation": -1, "count": 3})
	check(randoms.turns.size() == 3 and not is_equal_approx(randoms.turns[0], randoms.turns[1]), "random: each shape its own angle (%s)" % [randoms.turns])
	# Several picked: shared out, each at least once.
	var several: Dictionary = carve.call({"shape": "several", "shapes": ["t", "i", "h"], "count": 3})
	var kinds: Array = Array(several.kinds)
	kinds.sort()
	check(kinds == ["h", "i", "t"], "several picked: each of them once in three shapes (%s)" % [several.kinds])
	var six: Dictionary = carve.call({"shape": "several", "shapes": ["l", "ring"], "count": 5})
	check(six.kinds.size() == 5 and Array(six.kinds).all(func(k: String) -> bool: return k in ["l", "ring"]) and Array(six.kinds).has("l") and Array(six.kinds).has("ring"), "five shapes of two picked: only those, both (%s)" % [six.kinds])
	check(not MDSCaveShapes.wanted({"shape": "several", "shapes": []}) and MDSCaveShapes.wanted({"shape": "several", "shapes": ["i"]}), "several with none picked: the natural cave")
	# Linear: straight walls, a bar's rows open from end to end.
	var straight: Dictionary = carve.call({"shape": "t", "style": "linear"})
	var rough: Dictionary = carve.call({"shape": "t", "style": "cave"})
	var row_runs := func(cells: Dictionary) -> int:
		var ends: Dictionary = {}
		for c: Vector2i in cells:
			if c.y >= 7 and c.y <= 10:
				ends[c.y] = [mini(int(ends.get(c.y, [99, -1])[0]), c.x), maxi(int(ends.get(c.y, [99, -1])[1]), c.x)]
		var sizes: Dictionary = {}
		for y in ends:
			sizes[ends[y]] = true
		return sizes.size()
	check(row_runs.call(straight.cells) == 1 and row_runs.call(rough.cells) > 1, "linear: the bar's rows end at the same walls (straight); as a cave they don't")
	check(MDSCaveShapes.wall_climb({"shape": "u", "style": "linear"}) and not MDSCaveShapes.wall_climb({"shape": "u"}) and not MDSCaveShapes.wall_climb({"shape": "natural", "style": "linear"}), "linear shapes are climbed by their walls")
	var rock := MDSCaveShapes.rock(inside, Vector2i.ZERO, Vector2i(59, 39), {"shape": "u", "style": "linear"}, rng, 4, 4)
	var u: Dictionary = carve.call({"shape": "u", "style": "linear"})
	var ledges := 0
	for c in MDSCaveShapes.ladders(u.cells, u.uprights, 4):
		if rock.has(c):
			ledges += 1
	check(ledges == 0, "and get no ledges")

## Climbing walls (a linear room): a tall smooth shaft a jump can't get up, a wall climb can.
func _wall_climb() -> void:
	var open: Dictionary = {}
	# A floor 30 wide, a shaft 3 wide going up 20 rows from its right end.
	for x in 30:
		for y in range(20, 24):
			open[Vector2i(x, y)] = true
	for y in range(0, 20):
		for x in range(26, 29):
			open[Vector2i(x, y)] = true
	# A shelf at its top to stand on.
	for y in range(0, 3):
		for x in range(26, 40):
			open[Vector2i(x, y)] = true
	var jump := MDSRoomPainter.climb_reach(open, Vector2i(2, 23), 4, 3)
	var climb := MDSRoomPainter.climb_reach(open, Vector2i(2, 23), 4, 3, {}, true)
	var top := func(reached: Dictionary) -> int:
		var best := 99
		for c: Vector2i in reached:
			best = mini(best, c.y)
		return best
	check(top.call(jump) >= 19 and top.call(climb) <= 2, "a jump doesn't get up a tall shaft, climbing its walls does (%d, %d)" % [top.call(jump), top.call(climb)])
	var e := {"side": "top", "mouth": Vector2i(27, -1), "cell": Vector2i(27, 3)}
	var land := MDSRoomPainter.land_map(open)
	check(not MDSRoomPainter._arrives(jump, e, open, land, 4) and MDSRoomPainter._arrives(climb, e, open, land, 4, true), "a gate at its top: reached by climbing")

func _walkable() -> void:
	var world := MDSWorld.new()
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	var bad: Array = []
	var shapes := ["t", "u", "h", "l", "i", "cross", "ring", "s", "freeform", "mixed"]
	for i in shapes.size():
		var id: String = "Room_%s" % shapes[i]
		var at := Vector2(i * 2000, 0)
		world.add_room(id, Rect2(at, Vector2(1728, 972)))
		world.add_gate(id, at + Vector2(0, 760), "left", "left1", false)
		world.add_gate(id, at + Vector2(1728, 300), "right", "right1", false)
		world.add_gate(id, at + Vector2(864, 0), "top", "top1", false)
		world.add_gate(id, at + Vector2(1300, 972), "bot", "bot1", false)
		var root := Node2D.new()
		root.name = id
		save_scene(root, DIR + "/%s.tscn" % id.to_lower())
		root.free()
		world.set_room_scene(id, DIR + "/%s.tscn" % id.to_lower())
		var p := MDSRoomPainter.open(DIR + "/%s.tscn" % id.to_lower(), load(DIR + "/tiles.tres"))
		for turn in [0, 90, -1, 45]:
			var style := "linear" if turn == 45 else "cave"
			var cave := {"shape": shapes[i], "rotation": turn, "count": 2 if turn == 90 else 1, "style": style}
			p.generate_cave(world, id, 11 + turn, 0, 0, {}, {"cave": cave})
			var solid: Dictionary = {}
			for c in p.layers.Terrain.get_used_cells():
				solid[c] = true
			var open: Dictionary = {}
			for c in p.room_cells(world, id, false):
				if not solid.has(c):
					open[c] = true
			var ends: Array = []
			for g in world.get_gates(id):
				var e := p.gate_end(world, id, g, open)
				if not e.is_empty():
					ends.append(e)
			if ends.size() != 4 or not p.gates_joined(open, {}, ends, int(p.climb_params(world).reach), MDSCaveShapes.wall_climb(cave)) or not p.paths_joined:
				bad.append("%s %s" % [shapes[i], turn])
		p.free_instance()
	check(bad.is_empty(), "every shape, turned (45 degrees too, linear), several: a door on each side reaches every other and back (%s)" % [bad])

func _room_view() -> void:
	var world := MDSWorld.new()
	world.path = DIR + "/rv.mdsworld.json"
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	world.add_room("A", Rect2(0, 0, 1728, 972))
	world.add_room("B", Rect2(1728, 0, 1728, 972))
	MDSAreaTools.add_door(world, "A", "B")
	var view := MDSRoomView.new()
	view.size = Vector2(1400, 900)
	view.scene_path_for = func(id: String) -> String: return DIR.path_join("rv_" + id.to_snake_case() + ".tscn")
	add_child(view)
	await get_tree().process_frame
	view.open_full(world, 0)
	var picker := view.cave_shape_picker
	check(picker != null and picker.item_count == MDSCaveShapes.CHOICES.size(), "the Room view has a Cave shape picker (%d)" % (picker.item_count if picker else 0))
	check(not view.generation_fills().has("cave"), "Natural by default: the cave from the room's outline")
	var h := MDSCaveShapes.CHOICES.map(func(c: Array) -> String: return c[0]).find("h")
	picker.select(h)
	picker.item_selected.emit(h)
	check(view.generation_fills().get("cave", {}).get("shape", "") == "h", "picked, Generate cave makes that shape")
	view.cave_rotation_spin.value = 135
	check(int(view.generation_fills().cave.rotation) == 135, "turned by any angle")
	var several := MDSCaveShapes.CHOICES.map(func(c: Array) -> String: return c[0]).find("several")
	picker.select(several)
	picker.item_selected.emit(several)
	check(view.cave_shapes_menu.visible and view.generation_fills().get("cave", {}).get("shapes", []) == ["t", "u", "h"], "Several picked: the shapes ticked (%s)" % [view.cave_shape.get("shapes")])
	var pop := view.cave_shapes_menu.get_popup()
	pop.id_pressed.emit(MDSCaveShapes.PICKABLE.find("i"))
	check((view.generation_fills().cave.shapes as Array).has("i") and view.cave_shapes_menu.text.contains("i"), "ticking one more adds it")
	picker.select(h)
	picker.item_selected.emit(h)
	check(view.generate_all(false) == 2, "Generate all in the Full view: both rooms")
	var a: MDSRoomPainter = view._painters.get("A")
	check(a != null and a.paths_joined and not a.layers.Terrain.get_used_cells().is_empty(), "shaped caves, joined at their doors")
	var before: int = hash(a.layers.Terrain.get_used_cells()) if a else 0
	view.generate_all(true)
	check(a != null and hash(a.layers.Terrain.get_used_cells()) != before and a.paths_joined, "New variation for all makes them again, another way")
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _drag_takes_tiles() -> void:
	var world := MDSWorld.new()
	world.path = DIR + "/drag.mdsworld.json"
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	# An L: its tiles show only inside its rectangles (a mask on its layers).
	world.add_room("Ell", Rect2(0, 0, 1152, 648))
	world.add_rect("Ell", Rect2(0, 648, 576, 324))
	var view := MDSRoomView.new()
	view.size = Vector2(1400, 900)
	view.scene_path_for = func(id: String) -> String: return DIR.path_join("drag_" + id.to_snake_case() + ".tscn")
	add_child(view)
	await get_tree().process_frame
	view.open_full(world, 0)
	view.generate_all(false)
	view.save()
	var canvas := view.canvas
	canvas.zoom = 0.3
	canvas.pan = Vector2(40, 40)
	canvas._apply_view()
	for i in 30:
		if canvas.is_room_live("Ell") and not canvas.is_full_loading():
			break
		await get_tree().process_frame
	var box: Node2D = canvas._context.get("Ell")
	var mask: ShaderMaterial = canvas._masks.get("Ell")
	check(box != null and mask != null, "an L room shown with its mask")
	# Moved with the Rooms tool.
	view.set_full_tool(MDSFullViewTools.Tool.ROOMS)
	view.full_tools.select(["Ell"])
	view.full_tools._begin_move(Vector2.ZERO)
	view.full_tools._move_to(Vector2(700, 300))
	view.full_tools._finish_move()
	box = canvas._context.get("Ell")
	var origin: Vector2 = mask.get_shader_parameter("origin") if mask else Vector2.INF
	check(box != null and world.get_origin("Ell") == Vector2(700, 300) and origin.is_equal_approx(canvas.pan + box.position * canvas.zoom), "dragged, its tiles go with its outline: the mask moves with it (%s, want %s)" % [origin, canvas.pan + (box.position if box else Vector2.ZERO) * canvas.zoom])
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame
