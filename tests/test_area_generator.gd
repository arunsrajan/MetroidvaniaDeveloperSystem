extends "res://tests/test_case.gd"
## The hybrid area map generator and painter: area shapes (MDSAreaGenerator), rooms and doors
## within an area, painted areas, areas moved as one piece that slide up to their neighbours
## and connect to them (MDSAreaTools), and the Area, Generate and Paint area tools of the
## world map (MDSWorldCanvas).

func _run() -> void:
	_shapes()
	_outlines()
	_shaped_rooms()
	_reshape()
	_rooms()
	_doors()
	_generate()
	_fill()
	_slide()
	_link()
	_outline()
	await _canvas_area_tool()
	await _canvas_paint_area()
	await _canvas_generate()
	_glow_style()

## Whether every room of [param ids] can be reached from the first through its gates.
func _reachable(world: MDSWorld, ids: Array[String]) -> bool:
	if ids.is_empty():
		return true
	var seen := {ids[0]: true}
	var todo: Array[String] = [ids[0]]
	while not todo.is_empty():
		var id: String = todo.pop_back()
		for g in world.get_gates(id).values():
			var to := str(g.get("to", ""))
			if ids.has(to) and not seen.has(to):
				seen[to] = true
				todo.append(to)
	return seen.size() == ids.size()

func _holes(cells: Dictionary, size: Vector2i) -> int:
	var copy := cells.duplicate()
	MDSAreaGenerator._fill_holes(copy, size)
	return copy.size() - cells.size()

func _shapes() -> void:
	var gen := MDSAreaGenerator.new()
	var size := Vector2i(20, 12)
	for s in MDSAreaGenerator.Shape.values():
		gen.shape = s
		var name := MDSAreaGenerator.SHAPE_IDS[s]
		for seed_value in [1, 2, 3]:
			gen.seed_value = seed_value
			var cells := gen.shape_cells(size)
			var inside := cells.keys().all(func(c: Vector2i) -> bool: return Rect2i(Vector2i.ZERO, size).has_point(c))
			check(cells.size() >= 12 and inside, "%s (seed %d) fills part of the box (%d cells)" % [name, seed_value, cells.size()])
			check(MDSAreaGenerator.components(cells).size() == 1 and _holes(cells, size) == 0, "%s (seed %d) is one piece without holes" % [name, seed_value])
	gen.shape = MDSAreaGenerator.Shape.RECTANGLE
	gen.curves = 0.0
	gen.slants = 0.0
	check(gen.shape_cells(size).size() == 240, "a rectangle with sharp corners fills its box")
	gen.curves = 0.45
	gen.slants = 0.3
	gen.shape = MDSAreaGenerator.Shape.FREEFORM
	gen.seed_value = 5
	var a := gen.shape_cells(size)
	check(a == gen.shape_cells(size), "the same seed makes the same shape")
	gen.seed_value = 6
	check(a != gen.shape_cells(size), "another seed another")
	check(a.size() < 240, "freeform isn't the whole box")

# --- Curved and slanted outlines -----------------------------------------------------------

## (straight sides at least a cell long, slanted or curved sides) of [param poly].
func _edges(poly: PackedVector2Array) -> Vector2i:
	var straight := 0
	var other := 0
	for i in poly.size():
		var d := poly[(i + 1) % poly.size()] - poly[i]
		if d.length() < 0.05:
			continue
		if absf(d.x) < 0.001 or absf(d.y) < 0.001:
			straight += 1 if d.length() >= 1.0 else 0
		else:
			other += 1
	return Vector2i(straight, other)

func _outlines() -> void:
	var gen := MDSAreaGenerator.new()
	var size := Vector2i(20, 12)
	gen.shape = MDSAreaGenerator.Shape.RECTANGLE
	gen.curves = 0.0
	gen.slants = 0.0
	var box := gen.outline(size)
	check(box.size() == 4 and is_equal_approx(absf(MDSGeometry.signed_area(box)), 240.0), "a rectangle with sharp corners is its box")
	gen.slants = 1.0
	var cut := gen.outline(size)
	var e := _edges(cut)
	check(e.y >= 4 and e.x >= 4 and absf(MDSGeometry.signed_area(cut)) < 240.0 and MDSGeometry.is_simple(cut), "Slants cuts its corners on a slant, its sides staying straight (%s)" % e)
	gen.slants = 0.0
	gen.curves = 1.0
	var round := gen.outline(size)
	check(round.size() > 20 and MDSGeometry.is_simple(round), "Curves rounds them (%d points)" % round.size())
	gen.curves = 0.45
	gen.slants = 0.3
	for s in [MDSAreaGenerator.Shape.HYBRID, MDSAreaGenerator.Shape.FREEFORM, MDSAreaGenerator.Shape.IRREGULAR]:
		for seed_value in [1, 2, 3, 4]:
			gen.shape = s
			gen.seed_value = seed_value
			var poly := gen.outline(size)
			var inside := poly.size() >= 3
			for p in poly:
				inside = inside and Rect2(Vector2.ZERO, Vector2(size)).grow(0.001).has_point(p)
			check(inside and MDSGeometry.is_simple(poly), "%s (seed %d): one simple outline inside the box" % [MDSAreaGenerator.SHAPE_IDS[s], seed_value])
			if s == MDSAreaGenerator.Shape.HYBRID:
				var he := _edges(poly)
				check(he.x >= 1 and he.y >= 6, "hybrid (seed %d) mixes straight sides with curves and slants (%s)" % [seed_value, he])
	var tri := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(0, 4)])
	var cover := MDSAreaGenerator.coverage(tri, Rect2i(0, 0, 4, 4))
	check(is_equal_approx(cover.get(Vector2i(0, 0), 0.0), 1.0) and is_equal_approx(cover.get(Vector2i(3, 0), 0.0), 0.5) and not cover.has(Vector2i(3, 3)), "coverage: how much of each cell an outline covers (%s)" % [cover])

func _shaped_rooms() -> void:
	var world := MDSWorld.new()
	var gen := MDSAreaGenerator.new()
	gen.shape = MDSAreaGenerator.Shape.HYBRID
	gen.seed_value = 6
	var r := gen.generate(world, Rect2i(0, 0, 22, 13), 0, "The Glass Reach")
	var ids: Array[String] = r.rooms
	var shaped := ids.filter(func(id: String) -> bool: return world.has_room_shape(id))
	check(not shaped.is_empty() and shaped.size() < ids.size(), "rooms on the outline keep its curves and slants, the inner ones are rectangles (%d of %d)" % [shaped.size(), ids.size()])
	var s := world.get_paint_cell()
	var outline_area := absf(MDSGeometry.signed_area(gen.outline(Vector2i(22, 13)))) * s.x * s.y
	var total := 0.0
	var within := true
	for id in ids:
		for poly in world.get_room_outline(id):
			total += absf(MDSGeometry.signed_area(poly))
			for p in poly:
				var hit := false
				for rect in world.get_world_rects(id):
					hit = hit or rect.grow(0.5).has_point(p)
				within = within and hit
	check(total <= outline_area * 1.001 and total >= outline_area * 0.9, "together the rooms' outlines are the area's (%.0f of %.0f)" % [total, outline_area])
	check(within, "each within its own rectangles")
	# Clicks follow the outline; the game still uses the rectangles.
	var probe := Vector2.INF
	var room := ""
	for id: String in shaped:
		for rect in world.get_world_rects(id):
			for k in 40:
				var p := rect.position + rect.size * Vector2(fposmod(k * 0.137, 1.0), fposmod(k * 0.291, 1.0))
				if probe == Vector2.INF and not world.room_shape_contains(id, p):
					probe = p
					room = id
	check(probe != Vector2.INF and world.room_at(probe, 0, true) != room and world.room_at(probe, 0) == room, "outside the outline, a click misses the room; the game's room is still there (%s)" % room)
	if room.is_empty():
		return
	var inner := world.get_room_shape(room)[0]
	check(world.room_at(MDSGeometry._inner_point(inner), 0, true) == room, "inside it, it hits")
	# Doors sit where both outlines reach.
	var good := 0
	var all := 0
	for id in ids:
		for g in world.get_gates(id):
			var gate := world.get_gate(id, g)
			var out: Vector2 = {"right": Vector2.RIGHT, "left": Vector2.LEFT, "bot": Vector2.DOWN, "top": Vector2.UP}[world.get_gate_side(id, g)]
			var at := world.get_gate_world_pos(id, g)
			all += 1
			if world.room_shape_contains(id, at - out * 3.0) and world.room_shape_contains(str(gate.to), at + out * 3.0):
				good += 1
	check(all > 0 and good >= all * 0.9, "doors are inside both rooms' outlines (%d of %d)" % [good, all])
	# The outline is saved with the world.
	var before := world.get_local_shape(room)
	world.data = JSON.parse_string(JSON.stringify(world.data))
	check(world.get_local_shape(room).size() == before.size() and world.get_local_shape(room)[0].size() == before[0].size(), "the outline is saved in the world file")
	var world_before := world.get_room_shape(room)
	world.rebase_origin(room, world.get_origin(room) + Vector2(100, 50))
	check(world.get_room_shape(room)[0][0].is_equal_approx(world_before[0][0]), "moving the room's origin keeps its outline in place")
	# Fill outside shape follows the outline.
	var local := world.get_local_rects(room)
	check(not MDSNotchFill.outside_polygons(local, 0.0, world.get_local_shape(room)).is_empty(), "Fill outside shape fills what lies outside the outline")
	check(MDSNotchFill.signature(local, world.get_local_shape(room)) != MDSNotchFill.signature(local), "and is redone when the outline changes")

func _reshape() -> void:
	var world := MDSWorld.new()
	var cell := world.get_paint_cell()
	var id := world.add_room("R", Rect2(Vector2.ZERO, cell * Vector2(4, 2)), 0)
	var round := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		round.append(cell * Vector2(2, 1) + Vector2(cos(a), sin(a)) * cell * Vector2(2, 1))
	world.set_room_shape(id, [round])
	var area0 := absf(MDSGeometry.signed_area(world.get_room_shape(id)[0]))
	var cells := world.get_room_cells(id)
	cells.erase(Vector2i(3, 0))
	cells.erase(Vector2i(3, 1))
	world.set_room_cells(id, cells)
	var shrunk := 0.0
	var inside := true
	for p in world.get_room_shape(id):
		shrunk += absf(MDSGeometry.signed_area(p))
		for q in p:
			inside = inside and q.x <= cell.x * 3 + 0.5
	check(inside and shrunk < area0 * 0.9, "erasing cells cuts the outline (%.0f -> %.0f)" % [area0, shrunk])
	cells[Vector2i(0, 2)] = true
	world.set_room_cells(id, cells)
	var grown := 0.0
	for p in world.get_room_shape(id):
		grown += absf(MDSGeometry.signed_area(p))
	check(absf(grown - (shrunk + cell.x * cell.y)) < 1.0, "painted cells join it whole (%.0f -> %.0f)" % [shrunk, grown])
	check(world.room_shape_contains(id, cell * Vector2(0.5, 2.5)), "and can be clicked")
	world.set_room_shape(id, [])
	check(not world.has_room_shape(id) and world.room_shape_contains(id, Vector2(1, 1)), "without an outline the room is its rectangles")

func _rooms() -> void:
	var gen := MDSAreaGenerator.new()
	gen.shape = MDSAreaGenerator.Shape.HYBRID
	for seed_value in [3, 4, 9]:
		gen.seed_value = seed_value
		var cells := gen.shape_cells(Vector2i(24, 14))
		var rooms := gen.partition(cells)
		var union: Dictionary = {}
		var overlap := false
		for r: Dictionary in rooms:
			for c in r:
				overlap = overlap or union.has(c)
				union[c] = true
		check(not overlap and union == cells, "seed %d: the rooms cover the area once (%d rooms)" % [seed_value, rooms.size()])
		check(rooms.all(func(r: Dictionary) -> bool: return MDSAreaGenerator.components(r).size() == 1), "each room is one piece")
		check(rooms.all(func(r: Dictionary) -> bool: return r.size() >= 2), "no single-cell slivers")
		check(rooms.size() >= 6, "split into several rooms")
	gen.shape = MDSAreaGenerator.Shape.RECTANGLE
	gen.curves = 0.0
	gen.slants = 0.0
	gen.irregularity = 1.0
	gen.shafts = 0.0
	gen.seed_value = 2
	var rooms := gen.partition(gen.shape_cells(Vector2i(20, 12)))
	var irregular := rooms.filter(func(r: Dictionary) -> bool: return r.size() != _box_of(r).get_area())
	check(not irregular.is_empty(), "irregularity joins rooms into L, T and U shapes (%d of %d)" % [irregular.size(), rooms.size()])
	gen.irregularity = 0.0
	gen.room_min = Vector2i(3, 2)
	gen.room_max = Vector2i(3, 2)
	rooms = gen.partition(gen.shape_cells(Vector2i(12, 6)))
	check(rooms.size() == 12 and rooms.all(func(r: Dictionary) -> bool: return r.size() == 6 and _box_of(r).size == Vector2i(3, 2)), "fixed sizes tile a rectangle (%d rooms)" % rooms.size())

func _box_of(cells: Dictionary) -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for c: Vector2i in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return Rect2i(lo, hi - lo + Vector2i.ONE)

func _doors() -> void:
	var gen := MDSAreaGenerator.new()
	gen.seed_value = 11
	var rooms := gen.partition(gen.shape_cells(Vector2i(22, 12)))
	var near := MDSAreaGenerator.neighbours(rooms)
	gen.loops = 0.0
	var tree := gen.doors(rooms)
	check(tree.size() == rooms.size() - 1, "without loops: a tree (%d doors, %d rooms)" % [tree.size(), rooms.size()])
	gen.loops = 1.0
	check(gen.doors(rooms).size() == near.size(), "all loops: every neighbour pair")
	var a := {Vector2i(0, 0): true, Vector2i(0, 1): true, Vector2i(0, 2): true}
	var b := {Vector2i(1, 1): true, Vector2i(1, 2): true, Vector2i(0, 3): true}
	var d := MDSAreaTools.door_between(a, b)
	check(d.cell == Vector2i(0, 2) and d.dir == Vector2i.RIGHT, "a side door on the lowest shared row (%s)" % [d])
	var up := MDSAreaTools.door_between({Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(2, 0): true}, {Vector2i(0, 1): true, Vector2i(1, 1): true, Vector2i(2, 1): true})
	check(up.cell == Vector2i(1, 0) and up.dir == Vector2i.DOWN, "else a floor door in the middle (%s)" % [up])
	check(MDSAreaTools.door_between(a, {Vector2i(5, 5): true}).is_empty(), "none when they don't touch")

func _generate() -> void:
	var world := MDSWorld.new()
	var gen := MDSAreaGenerator.new()
	gen.seed_value = 4
	var r := gen.generate(world, Rect2i(0, 0, 20, 12), 0, "The Ashen Depths", Color.ORANGE)
	var ids: Array[String] = r.rooms
	check(world.has_area("The Ashen Depths") and world.get_area_color("The Ashen Depths").is_equal_approx(Color.ORANGE), "the area is made, in its color")
	check(ids.size() >= 6 and ids.all(func(id: String) -> bool: return world.get_room_area(id) == "The Ashen Depths" and world.get_room_layer(id) == 0), "its rooms are in it (%d)" % ids.size())
	check(ids[0] == "Ashen_Depths_01" and ids.has("Ashen_Depths_02"), "named after it (%s)" % ids[0])
	check(r.doors >= ids.size() - 1 and _reachable(world, ids), "doors join every room (%d doors)" % r.doors)
	var cells := MDSAreaTools.cells_of(world, ids)
	check(cells.size() == gen.shape_cells(Vector2i(20, 12)).size(), "the rooms cover the shape")
	var gates_ok := true
	for id in ids:
		for g in world.get_gates(id):
			var to := str(world.get_gate(id, g).get("to", ""))
			gates_ok = gates_ok and MDSAreaTools._touch_at(world, id, g, to)
	check(gates_ok, "every gate sits where its two rooms meet")
	# A second area next to it leaves the first one's cells alone.
	var before := cells.size()
	var r2 := gen.generate(world, Rect2i(10, 0, 20, 12), 0, "The Frozen Reach")
	var cells2 := MDSAreaTools.cells_of(world, r2.rooms)
	check(not r2.rooms.is_empty() and MDSAreaTools.cells_of(world, ids).size() == before, "a box over another area fills only the free cells")
	check(cells2.keys().all(func(c: Vector2i) -> bool: return not cells.has(c)), "without overlapping it")
	check(world.get_area_color("The Frozen Reach") != world.get_area_color("The Ashen Depths"), "a new area gets a color of its own")
	var full := gen.generate(world, Rect2i(cells.keys()[0], Vector2i.ONE), 0, "Nowhere")
	check(full.rooms.is_empty() and not world.has_area("Nowhere"), "a full box makes nothing")
	check(MDSAreaGenerator.room_base("The Sunken Gardens") == "Sunken_Gardens_01" and MDSAreaGenerator.room_base("") == "Room_01", "room ids come from the area's name")
	var name := gen.random_name(world)
	check(name.begins_with("The ") and not world.has_area(name), "random names are new (%s)" % name)

func _fill() -> void:
	var world := MDSWorld.new()
	var gen := MDSAreaGenerator.new()
	var stroke: Dictionary = {}
	for x in 14:
		for y in 3:
			stroke[Vector2i(x, y)] = true
	world.add_area("Painted")
	var ids := gen.fill(world, stroke, 0, "Painted")
	check(ids.size() >= 3 and MDSAreaTools.cells_of(world, ids).size() == 42 and _reachable(world, ids), "a painted stroke becomes rooms joined by doors (%d)" % ids.size())
	# Painting on beside the area joins it.
	var more: Dictionary = {}
	for x in range(14, 20):
		for y in 3:
			more[Vector2i(x, y)] = true
	var added := gen.fill(world, more, 0, "Painted")
	var all := world.get_area_rooms("Painted")
	check(not added.is_empty() and _reachable(world, all), "painting more joins it to the area (%d rooms)" % all.size())
	var again := gen.fill(world, more, 0, "Painted")
	check(again.is_empty(), "painting over rooms adds nothing")

func _two_areas() -> MDSWorld:
	var world := MDSWorld.new()
	world.add_area("West")
	world.add_area("East")
	var w := world.add_room("West_01", Rect2(0, 0, 288 * 4, 162 * 4), 0, "West")
	world.add_room("West_02", Rect2(0, 162 * 4, 288 * 4, 162 * 2), 0, "West")
	MDSAreaTools.add_door(world, w, "West_02")
	world.add_room("East_01", Rect2(288 * 10, 0, 288 * 4, 162 * 6), 0, "East")
	return world

func _slide() -> void:
	var world := _two_areas()
	var west := MDSAreaTools.group_rooms(world, "West", 0)
	check(west.size() == 2 and MDSAreaTools.group_of(world, "West_01") == "West", "an area's rooms are its group")
	var loose := world.add_room("Loose", Rect2(0, 162 * 20, 288, 162), 0)
	var just: Array[String] = [loose]
	check(MDSAreaTools.group_of(world, loose) == "#Loose" and MDSAreaTools.group_rooms(world, "#Loose", 0) == just, "a room in no area is a group of its own")
	var own := MDSAreaTools.cells_of(world, west)
	var taken := MDSAreaTools.occupied(world, 0, west)
	check(MDSAreaTools.fits(own, Vector2i(6, 0), taken) and not MDSAreaTools.fits(own, Vector2i(7, 0), taken), "it fits up to the neighbour")
	check(MDSAreaTools.slide(own, taken, Vector2i.ZERO, Vector2i(12, 0)) == Vector2i(6, 0), "dragged into it, it stops at contact")
	check(MDSAreaTools.slide(own, taken, Vector2i.ZERO, Vector2i(4, 0)) == Vector2i(4, 0), "short of it, it goes all the way")
	var along := MDSAreaTools.slide(own, taken, Vector2i(6, 0), Vector2i(8, -9))
	check(along.y == -9 and along.x >= 6, "blocked sideways it slides along (%s)" % along)
	var starts: Dictionary = {}
	for id in west:
		starts[id] = world.get_origin(id)
	world.set_area_value("West", "label_pos", [10.0, 20.0])
	MDSAreaTools.place(world, west, starts, Vector2(288 * 6, 0), {"West": Vector2(10, 20)})
	check(world.get_origin("West_01") == Vector2(288 * 6, 0) and world.get_origin("West_02") == Vector2(288 * 6, 162 * 4), "place moves the whole area")
	check(world.get_area_label_pos("West") == Vector2(10 + 288 * 6, 20), "with its name")
	check(world.get_gate_world_pos("West_01", world.get_gates("West_01").keys()[0]).x > 288 * 6, "and its gates")

func _link() -> void:
	var world := _two_areas()
	var west := MDSAreaTools.group_rooms(world, "West", 0)
	check(MDSAreaTools.link_touching(world, west, 0).is_empty(), "apart: no door")
	var starts: Dictionary = {}
	for id in west:
		starts[id] = world.get_origin(id)
	MDSAreaTools.place(world, west, starts, Vector2(288 * 6, 0))
	var made := MDSAreaTools.link_touching(world, west, 0)
	check(made.size() == 1 and made[0][2] == "East_01", "touching another area makes one door to it (%s)" % [made])
	if made.size() == 1:
		var g := world.get_gate(made[0][0], made[0][1])
		check(g.get("to", "") == "East_01" and g.get(MDSAreaTools.AUTO_LINK, false), "connected, marked as made by touching")
		check(world.get_gate_side(made[0][0], made[0][1]) == "right" and world.get_gate_side("East_01", made[0][3]) == "left", "on the sides that meet")
		check(world.get_gate_world_pos(made[0][0], made[0][1]).y == world.get_gate_world_pos("East_01", made[0][3]).y, "at the same place")
	check(MDSAreaTools.link_touching(world, west, 0).is_empty(), "once")
	check(MDSAreaTools.unlink_apart(world, west) == 0, "touching, it stays")
	MDSAreaTools.place(world, west, starts, Vector2(0, 162 * 12))
	check(MDSAreaTools.unlink_apart(world, west) == 1, "moved apart, the door goes")
	var left := 0
	for id in world.get_room_ids():
		for g in world.get_gates(id).values():
			if g.get(MDSAreaTools.AUTO_LINK, false):
				left += 1
	check(left == 0 and world.get_gates("East_01").is_empty(), "from both rooms")
	check(world.get_gates("West_01").size() == 1, "the area's own doors stay")
	# Rooms painted beside each other in an area get a door.
	var w2 := MDSWorld.new()
	w2.add_area("A")
	var a := w2.add_room("A_01", Rect2(0, 0, 288 * 2, 162 * 2), 0, "A")
	var b := w2.add_room("A_02", Rect2(288 * 2, 0, 288 * 2, 162 * 2), 0, "A")
	w2.add_room("B_01", Rect2(0, 162 * 2, 288 * 2, 162 * 2), 0)
	check(MDSAreaTools.link_neighbors(w2, a, 0) == 1 and MDSAreaTools.rooms_connected(w2, a, b), "link_neighbors joins touching rooms of the area")
	check(MDSAreaTools.link_neighbors(w2, a, 0) == 0 and not MDSAreaTools.rooms_connected(w2, a, "B_01"), "once, and not rooms of another area")

func _outline() -> void:
	var s := Vector2(10, 10)
	var l := {Vector2i(0, 0): "a", Vector2i(1, 0): "a", Vector2i(0, 1): "b"}
	var edges := MDSAreaTools.outline(l, s)
	var length := 0.0
	for i in range(0, edges.size(), 2):
		length += edges[i].distance_to(edges[i + 1])
	check(edges.size() == 12 and is_equal_approx(length, 80.0), "an L of three cells has six straight sides, 8 cells long (%d, %.0f)" % [edges.size() / 2, length])
	var inner := MDSAreaTools.inner_edges(l, s)
	check(inner.size() == 2 and inner[0] == Vector2(0, 10) and inner[1] == Vector2(10, 10), "and one side between its two rooms (%s)" % inner)

# --- The world map --------------------------------------------------------------------------

func _canvas(world: MDSWorld) -> MDSWorldCanvas:
	var canvas := MDSWorldCanvas.new()
	canvas.size = Vector2(900, 600)
	add_child(canvas)
	canvas.set_data(world, null, {})
	canvas.zoom = 0.1
	canvas.pan = Vector2(20, 20)
	return canvas

func _click(canvas: MDSWorldCanvas, at: Vector2, pressed: bool, double := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.double_click = double
	mb.position = at
	canvas._gui_input(mb)

func _move(canvas: MDSWorldCanvas, at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(mm)

func _drag(canvas: MDSWorldCanvas, from: Vector2, to: Vector2, steps := 6) -> void:
	_click(canvas, from, true)
	for i in range(1, steps + 1):
		_move(canvas, from.lerp(to, float(i) / steps))
	_click(canvas, to, false)

func _canvas_area_tool() -> void:
	var world := _two_areas()
	var canvas := _canvas(world)
	var selected: Array = []
	var renamed: Array = []
	canvas.area_selected.connect(func(a: String) -> void: selected.append(a))
	canvas.area_activated.connect(func(a: String) -> void: renamed.append(a))
	canvas.set_tool(MDSWorldCanvas.Tool.AREA)
	var inside_west := canvas.world_to_screen(Vector2(288 * 2, 162 * 2))
	_click(canvas, inside_west, true)
	_click(canvas, inside_west, false)
	check(canvas.selected_area == "West" and selected == ["West"], "a click selects the room's whole area")
	# Dragging it far right: it stops against East and connects to it.
	var east_far := canvas.world_to_screen(Vector2(288 * 20, 162 * 2))
	_drag(canvas, inside_west, east_far)
	check(world.get_origin("West_01") == Vector2(288 * 6, 0), "dragged into another area it stops at contact (%s)" % world.get_origin("West_01"))
	check(MDSAreaTools.rooms_connected(world, "West_01", "East_01"), "and connects to it")
	check(world.can_undo(), "undoably")
	world.undo()
	check(world.get_origin("West_01") == Vector2.ZERO and not MDSAreaTools.rooms_connected(world, "West_01", "East_01"), "undo puts it back, unconnected")
	_click(canvas, inside_west, true, true)
	_click(canvas, inside_west, false)
	check(renamed == ["West"], "double-click asks to rename it")
	# Arrow keys nudge it, stopping at contact too.
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	for i in 9:
		canvas._gui_input(key)
	check(world.get_origin("West_01") == Vector2(288 * 6, 0) and MDSAreaTools.rooms_connected(world, "West_01", "East_01"), "arrows nudge it up to its neighbour, connecting (%s)" % world.get_origin("West_01"))
	canvas.queue_free()
	await get_tree().process_frame

func _canvas_paint_area() -> void:
	var world := MDSWorld.new()
	var canvas := _canvas(world)
	var selected: Array = []
	canvas.area_selected.connect(func(a: String) -> void: selected.append(a))
	canvas.set_tool(MDSWorldCanvas.Tool.AREA_PAINT)
	canvas.set_brush_size(2)
	var cell := world.get_paint_cell()
	_drag(canvas, canvas.world_to_screen(cell * Vector2(1.5, 1.5)), canvas.world_to_screen(cell * Vector2(14.5, 1.5)), 12)
	var areas := world.get_areas().keys()
	check(areas.size() == 1, "a stroke on empty space paints a new area (%s)" % [areas])
	var a: String = areas[0] if not areas.is_empty() else ""
	var ids := world.get_area_rooms(a)
	check(ids.size() >= 3 and _reachable(world, ids), "made of rooms joined by doors (%d)" % ids.size())
	check(canvas.selected_area == a and selected.back() == a, "and selected")
	# A stroke starting inside it grows it.
	_drag(canvas, canvas.world_to_screen(cell * Vector2(14.5, 1.5)), canvas.world_to_screen(cell * Vector2(14.5, 9.5)), 8)
	var grown := world.get_area_rooms(a)
	check(world.get_areas().size() == 1 and grown.size() > ids.size() and _reachable(world, grown), "a stroke from inside an area grows it (%d rooms)" % grown.size())
	world.undo()
	check(world.get_area_rooms(a).size() == ids.size(), "undo takes the stroke back")
	# The plain Paint tool joins rooms of an area too.
	canvas.set_tool(MDSWorldCanvas.Tool.PAINT)
	canvas.new_room_area = a
	_drag(canvas, canvas.world_to_screen(cell * Vector2(1.5, 3.5)), canvas.world_to_screen(cell * Vector2(1.5, 6.5)), 4)
	var painted := canvas.selected_room
	check(world.get_room_area(painted) == a and _reachable(world, world.get_area_rooms(a)), "a room painted onto an area gets a door into it")
	canvas.queue_free()
	await get_tree().process_frame

func _canvas_generate() -> void:
	var world := MDSWorld.new()
	var canvas := _canvas(world)
	var boxes: Array = []
	canvas.generate_requested.connect(func(b: Rect2i) -> void: boxes.append(b))
	canvas.set_tool(MDSWorldCanvas.Tool.GENERATE)
	var cell := world.get_paint_cell()
	_drag(canvas, canvas.world_to_screen(cell * Vector2(2.2, 1.2)), canvas.world_to_screen(cell * Vector2(17.8, 10.6)))
	check(boxes.size() == 1 and boxes[0] == Rect2i(2, 1, 16, 10), "dragging a box asks for an area in it, in paint cells (%s)" % [boxes])
	_drag(canvas, canvas.world_to_screen(cell * Vector2(2.2, 1.2)), canvas.world_to_screen(cell * Vector2(2.6, 1.4)))
	check(boxes.size() == 1, "a click alone doesn't")
	var dialog := MDSAreaGenerateDialog.new()
	add_child(dialog)
	dialog.open(world, Rect2i(2, 1, 16, 10), 0, canvas.generator)
	await get_tree().process_frame
	check(dialog.visible and dialog.get_area_name().begins_with("The "), "the dialog offers a name (%s)" % dialog.get_area_name())
	var p := dialog.get_preview()
	check(not p.is_empty() and p.rooms.size() >= 4, "and previews the rooms (%d)" % p.get("rooms", []).size())
	dialog._curves.value = 0
	dialog._slants.value = 0
	dialog.set_shape(MDSAreaGenerator.Shape.RECTANGLE)
	check(dialog.get_preview().cells.size() == 160, "changing the shape updates the preview")
	dialog._curves.value = 100
	check(dialog.get_preview().outline.size() > 20 and absf(MDSGeometry.signed_area(dialog.get_preview().outline)) < 160.0, "Curves rounds its corners (%d points)" % dialog.get_preview().outline.size())
	dialog._curves.value = 0
	var made: Array = []
	dialog.generated.connect(func(r: Dictionary) -> void: made.append(r))
	dialog.set_area_name("The Glass Spire")
	var want: int = dialog.get_preview().rooms.size()
	dialog.generate_now()
	check(made.size() == 1 and world.has_area("The Glass Spire") and world.get_area_rooms("The Glass Spire").size() == want, "Generate makes the previewed rooms in the world (%d)" % want)
	check(_reachable(world, world.get_area_rooms("The Glass Spire")), "its rooms all joined")
	check(world.can_undo(), "undoably")
	dialog.queue_free()
	canvas.queue_free()
	await get_tree().process_frame

func _glow_style() -> void:
	var style := MDSMapStyle.get_style("glow")
	check(style.kind == MDSMapStyle.Kind.GLOW and MDSMapStyle.BUILTIN.has("glow"), "a glowing area map style, like a hand-made atlas")
	var world := _two_areas()
	world.set_setting("map_style", "glow")
	var canvas := _canvas(world)
	canvas.queue_redraw()
	await get_tree().process_frame
	check(canvas.get_style().kind == MDSMapStyle.Kind.GLOW, "the world map draws with it")
	canvas.queue_free()
	await get_tree().process_frame
