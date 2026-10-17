extends "res://tests/test_case.gd"
## Room outlines drawn in the Full view (MDSRoomSketches): rectangles, ellipses, polygons and
## curvy freehand shapes kept in the world, then made rooms on the map: one room per outline or
## split into rooms, outlines that overlap joined, cells other rooms have left out, areas made
## (new ones shared by outlines that touch), doors between the rooms and to what they touch.

var world: MDSWorld

func _run() -> void:
	world = MDSWorld.new()
	var s := world.get_paint_cell()
	check(s == Vector2(288, 162), "the default paint cell (%s)" % s)
	var sk := MDSRoomSketches.new()

	# Shapes.
	var rect := MDSRoomSketches.rectangle(Vector2(864, 324), Vector2.ZERO)
	check(MDSGeometry.bounds(rect) == Rect2(0, 0, 864, 324), "a rectangle from any two corners")
	var oval := MDSRoomSketches.ellipse(Vector2(0, 0), Vector2(1152, 648), 48)
	check(oval.size() == 48 and MDSGeometry.bounds(oval).grow(1.0).encloses(Rect2(1, 1, 1150, 646)), "an ellipse fills its box")
	var stroke := PackedVector2Array()
	for i in 80:
		var t := TAU * i / 80.0
		stroke.append(Vector2(600, 400) + Vector2(cos(t) * 500.0, sin(t) * 300.0) + Vector2(randf(), randf()) * 6.0)
	var curvy := MDSRoomSketches.freehand(stroke)
	check(curvy.size() >= 8 and MDSGeometry.is_simple(curvy), "a freehand stroke becomes a smooth simple outline (%d points)" % curvy.size())
	var eight := PackedVector2Array([Vector2(0, 0), Vector2(400, 400), Vector2(400, 0), Vector2(0, 400)])
	var untied := MDSRoomSketches.closed(eight)
	check(untied.size() >= 3 and MDSGeometry.is_simple(untied), "a twisted outline is untied (its biggest part)")
	check(MDSRoomSketches.snap_to_cells(world, Vector2(300, 170)) == Vector2(288, 162), "points snap to the paint cells' corners")

	# Outlines in the world.
	var a := MDSRoomSketches.add(world, 0, rect, MDSRoomSketches.ROOM, "Caves", "rectangle")
	check(a == 0 and MDSRoomSketches.count(world, 0) == 1 and MDSRoomSketches.count(world, 1) == 0, "an outline is kept on its layer")
	check(MDSRoomSketches.add(world, 0, PackedVector2Array([Vector2.ZERO, Vector2(1, 0)])) == -1, "two points are no outline")
	check(MDSRoomSketches.at(world, Vector2(100, 100), 0) == 0 and MDSRoomSketches.at(world, Vector2(2000, 100), 0) == -1, "found by a point inside it")
	check(MDSRoomSketches.in_box(world, Rect2(-10, -10, 900, 400), 0) == [0], "and by a box around it")
	MDSRoomSketches.move(world, [0], Vector2(288, 0))
	check(MDSGeometry.bounds(MDSRoomSketches.polygon(world, 0)).position == Vector2(288, 0), "moved")
	MDSRoomSketches.move(world, [0], Vector2(-288, 0))
	var saved := JSON.parse_string(JSON.stringify(world.data)) as Dictionary
	check(saved.has("sketches") and (saved.sketches as Array).size() == 1, "saved with the world")

	# One room: a rectangle on the cells is the room itself, no outline needed.
	world.checkpoint()
	var r := sk.generate(world, 0)
	check(r.rooms.size() == 1 and r.outlines == 1, "a rectangle makes one room (%d)" % r.rooms.size())
	var box_room: String = r.rooms[0]
	check(world.get_room_bounds(box_room) == Rect2(0, 0, 864, 324) and not world.has_room_shape(box_room), "of its size, without an outline of its own")
	check(world.get_room_area(box_room) == "Caves" and world.has_area("Caves"), "in the area named, made for it")
	check(MDSRoomSketches.count(world, 0) == 0, "the outline is a room now")
	world.undo()
	check(world.get_room_ids().is_empty() and MDSRoomSketches.count(world, 0) == 1, "Ctrl+Z on the map takes it back to the outline")
	world.redo()
	check(world.get_room_ids().size() == 1, "Ctrl+Y makes it again")

	# An ellipse beside it, in a new area: one room with a curved outline, a door to the first.
	world.checkpoint()
	MDSRoomSketches.add(world, 0, MDSRoomSketches.ellipse(Vector2(864, 0), Vector2(864 + 1152, 648)), MDSRoomSketches.ROOM, MDSRoomSketches.NEW_AREA, "ellipse")
	r = sk.generate(world, 0)
	check(r.rooms.size() == 1 and r.areas.size() == 1, "an ellipse in a new area: one room, one area")
	var oval_room: String = r.rooms[0]
	check(world.has_room_shape(oval_room), "with its curved outline on the map")
	check(world.get_room_area(oval_room) == r.areas[0] and world.get_room_area(oval_room) != "Caves", "in the new area (%s)" % world.get_room_area(oval_room))
	var shape_area := 0.0
	for poly in world.get_room_shape(oval_room):
		shape_area += absf(MDSGeometry.signed_area(poly))
	check_near(shape_area, PI * 576.0 * 324.0, PI * 576.0 * 324.0 * 0.12, "the outline is the ellipse")
	check(MDSAreaTools.rooms_connected(world, box_room, oval_room) and r.doors >= 1, "a door to the room it touches")
	for g in world.get_gates(oval_room).values():
		if str(g.get("to", "")) == box_room:
			check(world.room_shape_contains(oval_room, world.get_origin(oval_room) + Vector2(float(g.pos[0]), float(g.pos[1])) + Vector2(8, 0)), "where its curve meets the other room")

	# Overlapping outlines of one kind and area are one room; touching ones two, with a door.
	world.checkpoint()
	var y0 := 1296.0
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(0, y0), Vector2(864, y0 + 486)), MDSRoomSketches.ROOM, "Halls")
	MDSRoomSketches.add(world, 0, MDSRoomSketches.ellipse(Vector2(576, y0 + 162), Vector2(1440, y0 + 648)), MDSRoomSketches.ROOM, "Halls")
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(1440, y0), Vector2(2016, y0 + 486)), MDSRoomSketches.ROOM, "Halls")
	check(sk.outlines(world, 0).size() == 2, "a rectangle and an ellipse over it are one outline, the one beside them another")
	var preview := sk.preview(world, 0)
	check(preview.size() == 2 and not (preview[0].cells as Dictionary).is_empty(), "the preview has the cells each will take")
	r = sk.generate(world, 0)
	check(r.rooms.size() == 2, "two rooms (%d)" % r.rooms.size())
	check(MDSAreaTools.rooms_connected(world, r.rooms[0], r.rooms[1]), "joined by a door")

	# Split into rooms: a big curvy outline, every room reached through its doors.
	world.checkpoint()
	var blob := PackedVector2Array()
	for i in 64:
		var t := TAU * i / 64.0
		blob.append(Vector2(4000, 900) + Vector2(cos(t) * 1500.0 * (1.0 + 0.15 * sin(3.0 * t)), sin(t) * 700.0))
	MDSRoomSketches.add(world, 0, MDSRoomSketches.closed(blob), MDSRoomSketches.ROOMS, MDSRoomSketches.NEW_AREA, "curvy")
	r = sk.generate(world, 0)
	check(r.rooms.size() >= 4, "split into rooms (%d)" % r.rooms.size())
	check(r.areas.size() == 1, "of one new area")
	var reached: Dictionary = {r.rooms[0]: true}
	var queue: Array = [r.rooms[0]]
	while not queue.is_empty():
		var id: String = queue.pop_back()
		for g in world.get_gates(id).values():
			var to := str(g.get("to", ""))
			if r.rooms.has(to) and not reached.has(to):
				reached[to] = true
				queue.append(to)
	check(reached.size() == r.rooms.size(), "every room reached through doors (%d of %d)" % [reached.size(), r.rooms.size()])
	var shaped: int = r.rooms.filter(func(id: String) -> bool: return world.has_room_shape(id)).size()
	check(shaped >= 2, "the rooms on its edge keep its curves (%d)" % shaped)

	# Cells other rooms have are left out.
	world.checkpoint()
	var before := world.get_room_ids().size()
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(0, 0), Vector2(864, 324)), MDSRoomSketches.ROOM, "Caves")
	r = sk.generate(world, 0)
	check(r.rooms.is_empty() and r.left == 1 and world.get_room_ids().size() == before, "an outline over rooms only makes nothing")
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(0, -486), Vector2(864, 324)), MDSRoomSketches.ROOM, "Caves")
	r = sk.generate(world, 0)
	check(r.rooms.size() == 1 and world.get_room_bounds(r.rooms[0]) == Rect2(0, -486, 864, 486), "over a room and beside it: the part beside it")

	# New areas: outlines that touch share one, apart they get one each.
	world.checkpoint()
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(0, 4000), Vector2(576, 4324)), MDSRoomSketches.ROOM, MDSRoomSketches.NEW_AREA)
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(576, 4000), Vector2(1152, 4324)), MDSRoomSketches.ROOM, MDSRoomSketches.NEW_AREA)
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(4000, 4000), Vector2(4576, 4324)), MDSRoomSketches.ROOM, MDSRoomSketches.NEW_AREA)
	r = sk.generate(world, 0)
	check(r.rooms.size() == 3 and r.areas.size() == 2, "two new areas for three outlines, two of them touching (%d)" % r.areas.size())
	check(world.get_room_area(r.rooms[0]) == world.get_room_area(r.rooms[1]) and world.get_room_area(r.rooms[2]) != world.get_room_area(r.rooms[0]), "the touching ones share one")
	# Only the outlines picked.
	world.checkpoint()
	var i0 := MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(0, 6000), Vector2(576, 6324)), MDSRoomSketches.ROOM, "")
	MDSRoomSketches.add(world, 0, MDSRoomSketches.rectangle(Vector2(2000, 6000), Vector2(2576, 6324)), MDSRoomSketches.ROOM, "")
	r = sk.generate(world, 0, [i0])
	check(r.rooms.size() == 1 and world.get_room_area(r.rooms[0]).is_empty() and MDSRoomSketches.count(world, 0) == 1, "only the outlines picked; no area")
	check(MDSRoomSketches.clear_layer(world, 0) == 1 and MDSRoomSketches.count(world, 0) == 0, "Clear takes the rest away")
