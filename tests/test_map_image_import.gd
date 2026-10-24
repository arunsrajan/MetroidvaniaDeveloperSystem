extends "res://tests/test_case.gd"
## Import map image (MDSMapImageImporter): a picture of a map, its rooms outlined in dark lines
## on a dark background, cells wider than tall, becomes rooms on the world map. The grid is
## found by itself (x and y on their own), or read from the sidecar MDS writes with its map
## images. Colors are areas, outlined cells are rooms, a gate marker on a wall or a gap in it
## is a door; rooms no door reaches get one to a room they touch.
## A map drawn freely (Hollow Knight, Silksong: no grid, each area a shape filled with a dark
## color and outlined in a light one, areas touching, names written beside them) is read as
## shapes: each area split into rooms on the paint cells, keeping its outline, a door where two
## areas touch, a passage to a part apart, the names left out.

const DIR := TMP + "/map_import"
const CELL := Vector2i(40, 24)
const ORIGIN := Vector2i(13, 7)
const BG := Color("#241f1f")
const INK := Color("#141010")
const RED := Color("#c86a5a")
const BLUE := Color("#5a7ec8")
const GREEN := Color("#6ac86e")

## Rooms: [x, y, w, h] in cells, color.
var rooms := [
	[Rect2i(0, 0, 3, 2), RED], [Rect2i(3, 0, 2, 2), RED], [Rect2i(5, 0, 1, 3), RED],
	[Rect2i(0, 2, 2, 1), BLUE], [Rect2i(2, 2, 3, 2), BLUE],
	[Rect2i(7, 1, 4, 3), GREEN], [Rect2i(7, 4, 2, 2), GREEN], [Rect2i(9, 4, 2, 1), GREEN],
]

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var img := _map_picture()
	var path := DIR + "/map.png"
	img.save_png(path)
	var imp := MDSMapImageImporter.new()
	check(imp.load_image(path) == OK, "the picture loads")
	var found := imp.analyze()
	check(found.grid_found, "a grid is found (%s)" % [found.warnings])
	check(absf(found.cell_size.x - CELL.x) < 0.5 and absf(found.cell_size.y - CELL.y) < 0.5, "its cells are 40 x 24 px, found on their own across and down (%s)" % found.cell_size)
	var off: Vector2 = found.grid_offset
	var dx := fposmod(off.x - ORIGIN.x + CELL.x * 0.5, CELL.x) - CELL.x * 0.5
	var dy := fposmod(off.y - ORIGIN.y + CELL.y * 0.5, CELL.y) - CELL.y * 0.5
	check(absf(dx) <= 1.5 and absf(dy) <= 1.5, "and where they start (%s, want %s)" % [off, ORIGIN])
	# Read with the grid exactly, the rest is the same.
	imp.auto_grid = false
	imp.cell_size = Vector2(CELL)
	imp.grid_offset = Vector2(ORIGIN)
	found = imp.analyze()
	check(found.cells.size() == 6 + 4 + 3 + 2 + 6 + 12 + 4 + 2, "every room cell is found (%d)" % found.cells.size())
	check(found.areas.size() == 3, "three colors, three areas (%d)" % found.areas.size())
	check(found.rooms.size() == 8, "eight rooms, parted by their walls (%d)" % found.rooms.size())
	var doors: Array = found.doors
	check(doors.size() == 4, "four doors: a gate marker, three gaps (%d: %s)" % [doors.size(), doors])
	check(_has_door(found, Vector2i(2, 0), "right"), "the marker on the wall between the first two rooms is a door")
	check(_has_door(found, Vector2i(4, 1), "right"), "the gap between the second and third is one")
	check(_has_door(found, Vector2i(0, 1), "bot"), "the gap down to the blue room is one, between two areas")
	check(_has_door(found, Vector2i(7, 3), "bot"), "the gap in the green rooms' wall is one")
	for d: Dictionary in doors:
		if d.cell == Vector2i(0, 1):
			check_near(d.t, 0.5, 0.15, "the door is where the gap is along the wall")
	# Other ways to make rooms.
	imp.room_mode = MDSMapImageImporter.RoomMode.COLOR_REGIONS
	check(imp.analyze().rooms.size() == 3, "one room per color region: 3")
	imp.room_mode = MDSMapImageImporter.RoomMode.CELLS
	check(imp.analyze().rooms.size() == found.cells.size(), "one room per cell")
	imp.room_mode = MDSMapImageImporter.RoomMode.WALLS
	imp.analyze()
	_apply(imp)
	_sidecar(img)
	_drawn_map()

func _apply(imp: MDSMapImageImporter) -> void:
	var world := MDSWorld.new()
	world.add_room("Old", Rect2(0, 0, 1152, 648))
	world.checkpoint()
	var made := imp.apply(world, 0, Vector2i.MAX, ["Green Halls"])
	check(made.rooms.size() == 8, "eight rooms on the map (%d)" % made.rooms.size())
	check(world.has_area("Green Halls") and world.has_area("Imported 1") and world.has_area("Imported 2"), "areas, biggest first: the name given (the green rooms), then Imported 1, 2 (%s)" % [world.get_areas().keys()])
	var at := MDSMapImageImporter.free_cell(world, 0)
	var first: String = made.rooms[0]
	check(world.get_room_bounds(first) == Rect2(6 * 288, 0, 3 * 288, 2 * 162), "the first room is right of what was there, 3 x 2 paint cells (%s)" % world.get_room_bounds(first))
	check(not world.get_room_bounds("Old").intersects(world.get_room_bounds(first)), "clear of the old room")
	check(world.get_room_area(first) == "Imported 1", "in its area (the red one, second biggest)")
	# Doors: the four seen, plus one into each group no door reached.
	check(made.doors == 6, "6 doors: 4 seen, 2 so every room is reached from its group (%d)" % made.doors)
	var connected := 0
	for id: String in made.rooms:
		for g: Dictionary in world.get_gates(id).values():
			if world.has_gate(str(g.get("to", "")), str(g.get("to_gate", ""))):
				connected += 1
	check(connected == 12, "each door is a pair of connected gates (%d gates)" % connected)
	var a: String = made.rooms[0]
	var gate_ok := false
	for g in world.get_gates(a):
		var to := str(world.get_gate(a, g).get("to", ""))
		if to == made.rooms[1]:
			gate_ok = world.get_gate_world_pos(a, g).distance_to(Vector2(9 * 288, 81)) < 8.0
	check(gate_ok, "the marker's door is on the wall between the rooms, where the marker was")
	check(at.x > 6, "the next import goes right of this one (%s)" % at)
	world.undo()
	check(world.get_room_ids().size() == 1 and world.has_room("Old") and world.get_areas().is_empty(), "one undo takes the import back")

func _sidecar(img: Image) -> void:
	var path := DIR + "/exported.png"
	img.save_png(path)
	MDSMapImageImporter.write_sidecar(path, Vector2(CELL), Vector2(ORIGIN), Vector2(288, 162), 0)
	var imp := MDSMapImageImporter.new()
	imp.load_image(path)
	check(not imp.auto_grid and imp.cell_size == Vector2(CELL) and imp.grid_offset == Vector2(ORIGIN), "the sidecar gives the grid")
	imp.analyze()
	var world := MDSWorld.new()
	var made := imp.apply(world, 0, Vector2i.MAX, [], true)
	check(world.get_room_bounds(made.rooms[0]) == Rect2(0, 0, 864, 324), "kept where they were: grid cell (0, 0) is paint cell (0, 0) (%s)" % world.get_room_bounds(made.rooms[0]))
	var green := ""
	for id: String in made.rooms:
		if world.get_room_bounds(id).position == Vector2(7 * 288, 162):
			green = id
	check(not green.is_empty(), "the green room is at cell (7, 1) too")
	imp.cells_per_map_cell = Vector2i(2, 2)
	var big := MDSWorld.new()
	made = imp.apply(big, 0, Vector2i.ZERO)
	check(big.get_room_bounds(made.rooms[0]) == Rect2(0, 0, 6 * 288, 4 * 162), "a map cell can be 2 x 2 paint cells (%s)" % big.get_room_bounds(made.rooms[0]))

func _has_door(found: Dictionary, cell: Vector2i, side: String) -> bool:
	for d: Dictionary in found.doors:
		if d.cell == cell and d.side == side:
			return true
	return false

## The picture: dark background, rooms in their area colors outlined in dark lines (each room
## its own, so two rooms side by side have a double line), a white gate marker on one wall,
## gaps in three.
func _map_picture() -> Image:
	var img := Image.create(ORIGIN.x + 12 * CELL.x + 30, ORIGIN.y + 7 * CELL.y + 20, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for r in rooms:
		var cells: Rect2i = r[0]
		var px := Rect2i(ORIGIN + cells.position * CELL, cells.size * CELL)
		img.fill_rect(px, r[1])
		for side in [Rect2i(px.position, Vector2i(px.size.x, 2)), Rect2i(px.position, Vector2i(2, px.size.y)),
				Rect2i(Vector2i(px.end.x - 2, px.position.y), Vector2i(2, px.size.y)), Rect2i(Vector2i(px.position.x, px.end.y - 2), Vector2i(px.size.x, 2))]:
			img.fill_rect(side, INK)
	# Gaps: the walls open there, each room's color up to the edge.
	_gap(img, Vector2i(ORIGIN.x + 5 * CELL.x, ORIGIN.y + 1 * CELL.y + 12), true, RED, RED)
	_gap(img, Vector2i(ORIGIN.x + 20, ORIGIN.y + 2 * CELL.y), false, RED, BLUE)
	_gap(img, Vector2i(ORIGIN.x + 7 * CELL.x + 20, ORIGIN.y + 4 * CELL.y), false, GREEN, GREEN)
	# A gate marker (white, outlined) on the wall between the first two rooms.
	var m := Vector2i(ORIGIN.x + 3 * CELL.x, ORIGIN.y + 12)
	img.fill_rect(Rect2i(m - Vector2i(4, 4), Vector2i(8, 8)), Color.BLACK)
	img.fill_rect(Rect2i(m - Vector2i(3, 3), Vector2i(6, 6)), Color.WHITE)
	return img

## A gap 10 px wide in the double wall at [param at] (on the edge; [param upright]: the wall
## runs up and down), [param a] the color before it, [param b] after.
func _gap(img: Image, at: Vector2i, upright: bool, a: Color, b: Color) -> void:
	if upright:
		img.fill_rect(Rect2i(at.x - 2, at.y - 5, 2, 10), a)
		img.fill_rect(Rect2i(at.x, at.y - 5, 2, 10), b)
	else:
		img.fill_rect(Rect2i(at.x - 5, at.y - 2, 10, 2), a)
		img.fill_rect(Rect2i(at.x - 5, at.y, 10, 2), b)

## A drawn map: an L of green with a hole and a thin corridor, a blue shape touching it, a red one
## apart, and a name written on the background.
func _drawn_map() -> void:
	var img := Image.create(640, 420, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var green := [Color(0.16, 0.23, 0.14), Color(0.45, 0.55, 0.4)]
	var blue := [Color(0.13, 0.14, 0.2), Color(0.36, 0.37, 0.43)]
	var red := [Color(0.25, 0.12, 0.1), Color(0.6, 0.35, 0.3)]
	for r in [Rect2i(40, 40, 260, 90), Rect2i(40, 130, 34, 200), Rect2i(74, 300, 190, 10)]:
		_shape(img, r, green)
	img.fill_rect(Rect2i(120, 70, 60, 30), Color.BLACK)
	_shape(img, Rect2i(298, 60, 220, 140), blue)
	_shape(img, Rect2i(420, 240, 150, 60), red)
	# A name: thin strokes, no fill.
	for k in 6:
		img.fill_rect(Rect2i(120 + k * 12, 370, 2, 14), Color(0.6, 0.6, 0.5))
		img.fill_rect(Rect2i(120 + k * 12, 370, 8, 2), Color(0.6, 0.6, 0.5))
	var imp := MDSMapImageImporter.new()
	imp.set_image(img)
	imp.room_mode = MDSMapImageImporter.RoomMode.SHAPES
	imp.shape_cells_across = 40
	var found := imp.analyze()
	check(found.get("shapes", false) and found.areas.size() == 3, "a drawn map: three areas, its three shapes, the name left out (%d %s)" % [found.areas.size(), found.warnings])
	var green_area := -1
	for a in found.areas.size():
		var col: Color = found.areas[a].color
		if col.g > col.r and col.g > col.b:
			green_area = a
	check(green_area >= 0 and absf(found.areas[green_area].color.g - 0.23) < 0.04, "an area's color is its fill's")
	var green_cells: Dictionary = {}
	for c: Vector2i in found.areas[green_area].cells:
		green_cells[c] = true
	check(MDSAreaGenerator.components(green_cells).size() == 1 and green_cells.size() >= 20, "the L's thin corridor is kept: one piece (%d cells)" % green_cells.size())
	var hole := Vector2i(((Vector2(150, 85) - found.grid_offset) / found.cell_size).floor())
	check(not green_cells.has(hole), "its hole isn't a room's")
	check(not (found.areas[green_area].outline as Array).is_empty(), "and its outline is traced")
	var rooms_of: Dictionary = {}
	for r: Dictionary in found.rooms:
		rooms_of[r.area] = int(rooms_of.get(r.area, 0)) + 1
	check(rooms_of.size() == 3 and int(rooms_of[green_area]) >= 2, "each area split into rooms (%s)" % [rooms_of])
	var across := false
	for d: Dictionary in found.doors:
		across = across or found.rooms[d.a].area != found.rooms[d.b].area
	check(across, "a door where two areas touch")
	var world := MDSWorld.new()
	var made := imp.apply(world, 0)
	check(made.areas.size() == 3 and made.rooms.size() == found.rooms.size() + made.get("passages", []).size(), "imported: its areas and rooms on the map")
	check(not made.get("passages", []).is_empty() and MDSAreaTools.pieces(world, world.get_room_ids()) == 1, "the part apart joined by a passage: every room reached (%s)" % [made.get("passages", [])])
	var shaped := world.get_room_ids().filter(func(id: String) -> bool: return world.has_room_shape(id))
	check(not shaped.is_empty(), "rooms keep the shape's outline where it doesn't fill their cells (%d)" % shaped.size())
	# Read again with the same settings: the same.
	check(imp.analyze().rooms.size() == found.rooms.size(), "read again, the same")

## A shape of [param r] filled with [param look][0], outlined in [param look][1].
func _shape(img: Image, r: Rect2i, look: Array) -> void:
	img.fill_rect(r, look[1])
	img.fill_rect(r.grow(-2), look[0])
