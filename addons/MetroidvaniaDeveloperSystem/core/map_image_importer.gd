@tool
class_name MDSMapImageImporter
extends RefCounted
## Import map image: turns a picture of a map (a PNG exported from MDS or MetSys, a map made in
## another tool or drawn in a paint program, a screenshot of a game's map) into rooms on the
## world map, its areas and the doors between them.
## [codeblock]
## var imp := MDSMapImageImporter.new()
## imp.load_image("res://maps/castle.png")
## var found := imp.analyze()       # the grid, the rooms, areas and doors it sees
## world.checkpoint()
## var made := imp.apply(world, 0)  # rooms, areas and doors on layer 0, right of what is there
## [/codeblock]
## How it reads the picture:
## - The background is the color most of the picture's frame has; pixels near it, transparent
##   ones, and dark ones (ink: walls, outlines) are not rooms.
## - The map's grid (one cell of it = one paint cell of the world, or [member cells_per_map_cell]
##   of them across) is found from where room edges are, along x and y on their own (cells are
##   often wider than tall), unless [member auto_grid] is off ([member cell_size],
##   [member grid_offset]) or the picture has a sidecar file [code]<picture>.mdsmap.json[/code]
##   (MDS writes one with each map image it exports) that gives it exactly.
## - A cell is a room's when [member min_fill] of its middle is room color. Room colors group
##   into areas by hue and saturation (shades of one color are one area; see
##   [member color_tolerance]).
## - Two cells side by side are one room when nothing parts them (no wall line, the same area);
##   a wall with a gap, or a gate marker on it (the squares MDS draws), is a door between two
##   rooms ([member room_mode] can also make one room of each color region, or of each cell).
## - A map drawn freely, with no grid (a Hollow Knight or Silksong map: each area one shape, a
##   dark fill outlined in a lighter color), is read as shapes ([constant RoomMode.SHAPES], also
##   when no grid is found): each area's shape lies on [member shape_cells_across] paint cells
##   across, is split into rooms with doors between them, and keeps its outline on the map (see
##   [MDSMapShapes]).

## How cells become rooms.
enum RoomMode {
	WALLS, ## cells not parted by a wall line, of one area, are one room
	COLOR_REGIONS, ## the cells of one area that touch are one room
	CELLS, ## each cell is a room
	SHAPES, ## a map drawn freely: each area a shape, split into rooms (see [MDSMapShapes])
}

const SIDECAR_SUFFIX := ".mdsmap.json"
const SIDECAR_FORMAT := "mds_map_image"
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]
## Lines across a cell edge looked along for a wall.
const EDGE_LINES := 9
## Labels of a pixel.
const BACKGROUND := 0
const INK := 1
const FILL := 2

## The picture (RGBA8).
var image: Image
## The file it came from ("" if set with [method set_image]).
var source_path := ""
## Find the grid by itself; off: [member cell_size] and [member grid_offset].
var auto_grid := true
## Size of one cell of the map's grid in the picture (px), and where a cell's corner is.
var cell_size := Vector2(32, 32)
var grid_offset := Vector2.ZERO
## The background color; alpha 0: the color most of the picture's frame has.
var background := Color(0, 0, 0, 0)
## How far apart room colors may be and be one area (0..1).
var color_tolerance := 0.12
## How near the background a pixel may be and be background (0..1, RGB).
var background_tolerance := 0.08
## Pixels darker than this are ink (walls, outlines), not rooms (0..1).
var ink_level := 0.16
## A line between two cells whose color differs from both cells' by more than this (in any of
## red, green, blue, 0..1) is a wall: the lines map styles part rooms with, darker or lighter.
var wall_contrast := 0.14
## The share of a cell's middle that must be room color for it to be a room's.
var min_fill := 0.45
var room_mode: int = RoomMode.WALLS
## Find doors: gaps in the walls between rooms, gate markers on them.
var detect_doors := true
## Rooms no door reaches get one to a room they touch, so the whole map can be walked. In a map
## drawn freely, parts apart from the rest (a gap in the drawing) get a passage to the nearest
## room, of up to [member passage_cells] paint cells.
var connect_unreached := true
var passage_cells := 12
## The shape (width / height) the map's cells are likely to have, to choose between periods
## that fit as well: the world's paint cell (0: the biggest are taken).
var cell_aspect := 0.0
## Paint cells of the world each cell of the picture's grid covers, across and down.
var cells_per_map_cell := Vector2i.ONE
## A map drawn freely ([constant RoomMode.SHAPES]): paint cells across its width.
var shape_cells_across := 120
## Reads maps drawn freely (see [constant RoomMode.SHAPES]).
var shapes := MDSMapShapes.new()
## Sidecar found with the picture: {cell_px, grid_origin_px, paint_cell, layer}.
var sidecar: Dictionary = {}
## What [method analyze] found last.
var found: Dictionary = {}

var _data := PackedByteArray()
var _w := 0
var _h := 0
var _bg := PackedInt32Array([0, 0, 0])
var _bg_tol := 0
var _ink := 0
var _grid_key := ""
var _grid_found: Dictionary = {}
var _shapes_key := ""
var _shapes_found: Dictionary = {}

## Loads a picture from a file (res://, user:// or anywhere on disk), with its sidecar if it has
## one. Returns the error.
func load_image(path: String) -> Error:
	var img := Image.new()
	var file := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var err := img.load(file)
	if err != OK:
		return err
	set_image(img)
	source_path = path
	sidecar = read_sidecar(path)
	if not sidecar.is_empty():
		auto_grid = false
		cell_size = sidecar.cell_px
		grid_offset = sidecar.grid_origin_px
	return OK

## Uses [param img] as the picture (it is copied).
func set_image(img: Image) -> void:
	source_path = ""
	sidecar = {}
	image = img.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	_data = image.get_data()
	_w = image.get_width()
	_h = image.get_height()
	_grid_key = ""
	found = {}

## The sidecar of the picture [param path] (see [method write_sidecar]), or {}.
static func read_sidecar(path: String) -> Dictionary:
	var side := path + SIDECAR_SUFFIX
	if not FileAccess.file_exists(side):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(side))
	if not d is Dictionary or str(d.get("format", "")) != SIDECAR_FORMAT:
		return {}
	var cell: Array = d.get("cell_px", [])
	var origin: Array = d.get("grid_origin_px", [0, 0])
	if cell.size() < 2 or float(cell[0]) <= 0.0 or float(cell[1]) <= 0.0 or origin.size() < 2:
		return {}
	var out := {"cell_px": Vector2(float(cell[0]), float(cell[1])), "grid_origin_px": Vector2(float(origin[0]), float(origin[1]))}
	var paint: Array = d.get("paint_cell", [])
	if paint.size() >= 2:
		out.paint_cell = Vector2(float(paint[0]), float(paint[1]))
	out.layer = int(d.get("layer", 0))
	return out

## Writes the sidecar of a map picture saved at [param path]: one cell of the map's grid is
## [param cell_px] in it, the grid's cell (0, 0) has its corner at [param origin_px].
static func write_sidecar(path: String, cell_px: Vector2, origin_px: Vector2, paint_cell: Vector2, layer: int) -> Error:
	var f := FileAccess.open(path + SIDECAR_SUFFIX, FileAccess.WRITE)
	if not f:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"format": SIDECAR_FORMAT, "version": 1, "cell_px": [cell_px.x, cell_px.y],
		"grid_origin_px": [origin_px.x, origin_px.y], "paint_cell": [paint_cell.x, paint_cell.y], "layer": layer}, "\t"))
	return OK

# --- Reading the picture -----------------------------------------------------------------------

## Finds the map in the picture: {cell_size, grid_offset (px), grid_found (the grid was found,
## not given), cells: {Vector2i: area index}, areas: [{color, cells}], rooms: [{cells:
## Array[Vector2i], area}], doors: [{a, b (room indices), cell (of room a), side (of room a),
## t (0..1 along that side)}], warnings}. Cells are counted from the grid's cell (0, 0).
func analyze() -> Dictionary:
	var warnings: PackedStringArray = []
	found = {"cell_size": cell_size, "grid_offset": grid_offset, "grid_found": false, "cells": {}, "areas": [], "rooms": [], "doors": [], "warnings": warnings}
	if not image or _w < 2 or _h < 2:
		warnings.append("No picture.")
		return found
	_prepare_labels()
	if room_mode == RoomMode.SHAPES:
		found = _analyze_shapes()
		return found
	if auto_grid:
		var g := _find_grid()
		# No grid: a map drawn freely, read as shapes when it is one.
		if g.is_empty():
			var drawn := _analyze_shapes()
			if not drawn.rooms.is_empty():
				drawn.warnings.insert(0, "No grid found: read as a map drawn freely (Rooms: one shape per area).")
				found = drawn
				return found
		if g.is_empty():
			warnings.append("No grid found in the picture: set the cell size (and where a cell starts) by hand.")
		else:
			cell_size = g.cell_size
			grid_offset = g.grid_offset
			found.grid_found = true
	found.cell_size = cell_size
	found.grid_offset = grid_offset
	if cell_size.x < 2.0 or cell_size.y < 2.0:
		warnings.append("The cell size is too small.")
		return found
	# Cells: those whose middle is mostly room color, and their colors.
	var share: Dictionary = {}
	var colors: Dictionary = {}
	var i0 := floori(-grid_offset.x / cell_size.x)
	var i1 := floori((_w - 1 - grid_offset.x) / cell_size.x)
	var j0 := floori(-grid_offset.y / cell_size.y)
	var j1 := floori((_h - 1 - grid_offset.y) / cell_size.y)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var s := _sample_cell(Vector2i(i, j))
			if s.share > 0.0:
				share[Vector2i(i, j)] = s.share
				colors[Vector2i(i, j)] = s.color
	var room_cells: Dictionary = {}
	for c: Vector2i in share:
		if float(share[c]) >= min_fill:
			room_cells[c] = colors[c]
	# Holes of a label or a marker in the middle of a room: room too.
	for c: Vector2i in share:
		if room_cells.has(c) or float(share[c]) < 0.15:
			continue
		var around := 0
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if room_cells.has(c + d):
				around += 1
		if around >= 3:
			room_cells[c] = colors[c]
	if room_cells.is_empty():
		warnings.append("No rooms found: check the background color, the ink level and the cell size.")
		return found
	# Areas: the room colors, grouped.
	var groups := _group_colors(room_cells)
	var group_of: Dictionary = {}
	for c: Vector2i in room_cells:
		group_of[c] = _nearest_group(groups, room_cells[c])
	# An area of a cell or two among another's (a label covering a cell's middle): theirs.
	var counts: Dictionary = {}
	for c: Vector2i in group_of:
		counts[group_of[c]] = int(counts.get(group_of[c], 0)) + 1
	for c: Vector2i in group_of:
		if int(counts[group_of[c]]) > 2:
			continue
		var votes: Dictionary = {}
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var g: int = group_of.get(c + d, -1)
			if g >= 0 and g != group_of[c] and int(counts[g]) > 2:
				votes[g] = int(votes.get(g, 0)) + 1
		var best := -1
		for g: int in votes:
			if best < 0 or int(votes[g]) > int(votes[best]):
				best = g
		if best >= 0:
			counts[group_of[c]] = int(counts[group_of[c]]) - 1
			group_of[c] = best
			room_cells[c] = groups[best].color
	var used: Array = []
	for g in groups.size():
		if int(counts.get(g, 0)) > 0:
			used.append(g)
	var cells: Dictionary = {}
	var areas: Array = []
	for g in used:
		areas.append({"color": groups[g].color, "cells": []})
	for c: Vector2i in group_of:
		var g := used.find(group_of[c])
		cells[c] = g
		areas[g].cells.append(c)
	found.cells = cells
	found.areas = areas
	# Rooms: cells joined where nothing parts them.
	var parent: Dictionary = {}
	for c: Vector2i in cells:
		parent[c] = c
	var door_list: Array = []
	for c: Vector2i in cells:
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not cells.has(n):
				continue
			var same_area: bool = cells[c] == cells[n]
			var e := _edge(c, n, room_cells[c], room_cells[n]) if room_mode == RoomMode.WALLS or detect_doors else {}
			var join := false
			match room_mode:
				RoomMode.WALLS:
					join = same_area and bool(e.get("open", false))
				RoomMode.COLOR_REGIONS:
					join = same_area
			if join:
				_union(parent, c, n)
			elif detect_doors and (e.has("door_t")):
				door_list.append({"a_cell": c, "b_cell": n, "side": "right" if d == Vector2i.RIGHT else "bot", "t": float(e.door_t)})
	var room_of: Dictionary = {}
	var rooms: Array = []
	for c: Vector2i in cells:
		var r: Vector2i = _find(parent, c)
		if not room_of.has(r):
			room_of[r] = rooms.size()
			rooms.append({"cells": [], "area": -1})
		rooms[room_of[r]].cells.append(c)
	for room: Dictionary in rooms:
		var votes: Dictionary = {}
		for c: Vector2i in room.cells:
			votes[cells[c]] = int(votes.get(cells[c], 0)) + 1
		var best := -1
		for g: int in votes:
			if best < 0 or int(votes[g]) > int(votes[best]):
				best = g
		room.area = best
	var doors: Array = []
	var seen: Dictionary = {}
	for d: Dictionary in door_list:
		var a: int = room_of[_find(parent, d.a_cell)]
		var b: int = room_of[_find(parent, d.b_cell)]
		if a == b:
			continue
		var key := "%s|%s" % [d.a_cell, d.b_cell]
		if seen.has(key):
			continue
		seen[key] = true
		doors.append({"a": a, "b": b, "cell": d.a_cell, "side": d.side, "t": d.t})
	found.rooms = rooms
	found.doors = doors
	return found

## [method analyze] for a map drawn freely ([MDSMapShapes]); the same picture and settings are
## read once.
func _analyze_shapes() -> Dictionary:
	shapes.cells_across = shape_cells_across
	var bg := background if background.a > 0.0 else frame_color()
	var aspect := cell_aspect if cell_aspect > 0.0 else 288.0 / 162.0
	var key := "%d|%s|%s|%s" % [image.get_instance_id(), bg, aspect, [shapes.cells_across, shapes.min_cover, shapes.flat, shapes.fill_tolerance, shapes.same_area, shapes.background_tolerance, shapes.room_min, shapes.room_max]]
	if key != _shapes_key or _shapes_found.is_empty():
		_shapes_key = key
		_shapes_found = shapes.analyze(image, bg, Vector2(aspect, 1.0))
	var out := _shapes_found.duplicate()
	out.warnings = (_shapes_found.warnings as PackedStringArray).duplicate()
	return out

## Pixel labels' settings from the background (found on the frame) and the levels.
func _prepare_labels() -> void:
	var bg := background if background.a > 0.0 else frame_color()
	_bg = PackedInt32Array([roundi(bg.r * 255.0), roundi(bg.g * 255.0), roundi(bg.b * 255.0)])
	_bg_tol = roundi(background_tolerance * 765.0)
	_ink = roundi(ink_level * 255.0)

## The color most of the picture's frame has (its background).
func frame_color() -> Color:
	var votes: Dictionary = {}
	var step := maxi(1, (_w + _h) / 400)
	var add := func(x: int, y: int) -> void:
		var o := (y * _w + x) * 4
		if _data[o + 3] < 128:
			votes[-1] = int(votes.get(-1, 0)) + 1
			return
		var key := (_data[o] >> 3) << 10 | (_data[o + 1] >> 3) << 5 | (_data[o + 2] >> 3)
		votes[key] = int(votes.get(key, 0)) + 1
	for x in range(0, _w, step):
		add.call(x, 0)
		add.call(x, _h - 1)
	for y in range(0, _h, step):
		add.call(0, y)
		add.call(_w - 1, y)
	var best := -2
	for k: int in votes:
		if best == -2 or int(votes[k]) > int(votes[best]):
			best = k
	if best == -1:
		return Color(0, 0, 0, 0)
	return Color(((best >> 10) & 31) / 31.0, ((best >> 5) & 31) / 31.0, (best & 31) / 31.0)

## The label of pixel (x, y): [constant BACKGROUND], [constant INK] or [constant FILL].
func label_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return BACKGROUND
	var o := (y * _w + x) * 4
	if _data[o + 3] < 128:
		return BACKGROUND
	var r := _data[o]
	var g := _data[o + 1]
	var b := _data[o + 2]
	if absi(r - _bg[0]) + absi(g - _bg[1]) + absi(b - _bg[2]) <= _bg_tol:
		return BACKGROUND
	if (r * 299 + g * 587 + b * 114) / 1000 < _ink:
		return INK
	return FILL

func _pixel(x: int, y: int) -> Color:
	var o := (clampi(y, 0, _h - 1) * _w + clampi(x, 0, _w - 1)) * 4
	return Color(_data[o] / 255.0, _data[o + 1] / 255.0, _data[o + 2] / 255.0)

## The middle of cell [param c]: {share (of room color), color (their average)}.
func _sample_cell(c: Vector2i) -> Dictionary:
	var samples: Array[Color] = []
	for b in 5:
		for a in 5:
			var x := floori(grid_offset.x + (c.x + 0.2 + 0.15 * a) * cell_size.x)
			var y := floori(grid_offset.y + (c.y + 0.2 + 0.15 * b) * cell_size.y)
			if label_at(x, y) == FILL:
				samples.append(_pixel(x, y))
	if samples.is_empty():
		return {"share": 0.0, "color": Color.BLACK}
	# The middle sample by brightness, and the average of those like it (a label's letters, a
	# marker, left out).
	var by_v := samples.duplicate()
	by_v.sort_custom(func(p: Color, q: Color) -> bool: return p.v < q.v)
	var mid: Color = by_v[by_v.size() / 2]
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for p in samples:
		if maxf(maxf(absf(p.r - mid.r), absf(p.g - mid.g)), absf(p.b - mid.b)) <= wall_contrast:
			sum += Color(p.r, p.g, p.b, 1.0)
			n += 1
	return {"share": samples.size() / 25.0, "color": Color(sum.r / n, sum.g / n, sum.b / n)}

# --- The grid ----------------------------------------------------------------------------------

## The map's grid from where room edges are: {cell_size, grid_offset}, or {} when the picture
## shows none.
func _find_grid() -> Dictionary:
	var key := "%s|%s|%s|%s|%s|%d" % [_bg, _bg_tol, _ink, wall_contrast, cell_aspect, _data.size()]
	if key == _grid_key:
		return _grid_found
	_grid_key = key
	_grid_found = {}
	var gx := _edges_along(true)
	var gy := _edges_along(false)
	if gx.is_empty() or gy.is_empty():
		return _grid_found
	# Of the periods that fit as well, the cells shaped like the world's paint cells (when it
	# is known), else the biggest.
	if cell_aspect > 0.0 and absf(log((float(gx.period) / float(gy.period)) / cell_aspect)) > 0.1:
		var best := 0.0
		var xs: Array = gx.candidates
		var ys: Array = gy.candidates
		var pair: Array = []
		for cx: Dictionary in xs:
			for cy: Dictionary in ys:
				var off := absf(log((float(cx.period) / float(cy.period)) / cell_aspect))
				var fit := float(cx.strength) * float(cy.strength)
				if off <= 0.1 and fit > best:
					best = fit
					pair = [cx, cy]
		if not pair.is_empty():
			gx = pair[0]
			gy = pair[1]
	_grid_found = {"cell_size": Vector2(gx.period, gy.period), "grid_offset": Vector2(gx.phase, gy.phase)}
	return _grid_found

## The period of the straight room edges across the picture ([param across]: edges that stand
## up, found along rows; else edges that lie, found along columns): see [method periodicity].
## Where rooms start (into room color), where they end, and wall lines between two rooms are
## counted where they go on from the line looked along before (curved outlines are left out).
func _edges_along(across: bool) -> Dictionary:
	var n := _w if across else _h
	var lines := _h if across else _w
	var enter := PackedFloat32Array()
	enter.resize(n)
	var leave := PackedFloat32Array()
	leave.resize(n)
	var walls := PackedFloat32Array()
	walls.resize(n)
	var contrast := roundi(wall_contrast * 255.0)
	var step := maxi(1, lines / 300)
	var before := PackedByteArray()
	before.resize(n)
	var now_marks := PackedByteArray()
	now_marks.resize(n)
	var stride := 4 if across else _w * 4
	# What _label_o() does, inline: this looks at a million pixels or so.
	var data := _data
	var bg0 := _bg[0]
	var bg1 := _bg[1]
	var bg2 := _bg[2]
	var bg_tol := _bg_tol
	var ink := _ink
	for line in range(0, lines, step):
		now_marks.fill(0)
		var o := (line * _w) * 4 if across else line * 4
		var last := _label_o(o)
		for i in range(1, n):
			var po := o
			o += stride
			var r: int = data[o]
			var g: int = data[o + 1]
			var b: int = data[o + 2]
			var now := FILL
			if data[o + 3] < 128 or absi(r - bg0) + absi(g - bg1) + absi(b - bg2) <= bg_tol:
				now = BACKGROUND
			elif (r * 299 + g * 587 + b * 114) / 1000 < ink:
				now = INK
			var mark := 0
			if now == FILL and last != FILL:
				mark = 1
			elif last == FILL and now != FILL:
				mark = 2
			elif now == FILL and last == FILL and maxi(maxi(absi(r - data[po]), absi(g - data[po + 1])), absi(b - data[po + 2])) > contrast:
				mark = 3
			if mark > 0:
				now_marks[i] = mark
				# A straight edge: the line before had it too, here or a pixel off.
				if line > 0 and (before[i] == mark or before[i - 1] == mark or (i + 1 < n and before[i + 1] == mark)):
					if mark == 1:
						enter[i] += 1.0
					elif mark == 2:
						leave[i] += 1.0
					else:
						walls[i] += 1.0
			last = now
		var swap := before
		before = now_marks
		now_marks = swap
	return periodicity(enter, leave, walls)

## The label of the pixel at byte offset [param o] (see [method label_at]).
func _label_o(o: int) -> int:
	if _data[o + 3] < 128:
		return BACKGROUND
	var r := _data[o]
	var g := _data[o + 1]
	var b := _data[o + 2]
	if absi(r - _bg[0]) + absi(g - _bg[1]) + absi(b - _bg[2]) <= _bg_tol:
		return BACKGROUND
	if (r * 299 + g * 587 + b * 114) / 1000 < _ink:
		return INK
	return FILL

## The period of the edges of a map: [param enter] counts at each x the rooms that start there
## (into room color), [param leave] those that end. {period, phase (where a cell starts),
## strength (0..1: how well the edges keep to it)}, or {} when they keep to none. Edges are
## mostly at whole cells: the biggest period they keep to about as well as to any is taken (its
## halves fit them as well, its doubles not). A room's outline is seen a little inside it (where
## its color starts), the same at its start and end: that is worked out too. [param walls]: lines
## between two rooms (both sides of them, so seen where they are).
static func periodicity(enter: PackedFloat32Array, leave := PackedFloat32Array(), walls := PackedFloat32Array(), p_min := 4.0, p_max := 0.0) -> Dictionary:
	var xs := PackedFloat32Array()
	var ws := PackedFloat32Array()
	var signs := PackedFloat32Array()
	_peaks(enter, 1.0, xs, ws, signs)
	_peaks(leave, -1.0, xs, ws, signs)
	_peaks(walls, 0.0, xs, ws, signs)
	if xs.size() < 3:
		return {}
	var lo_x := xs[0]
	var hi_x := xs[0]
	for x in xs:
		lo_x = minf(lo_x, x)
		hi_x = maxf(hi_x, x)
	var span := maxf(1.0, hi_x - lo_x)
	if p_max <= 0.0:
		p_max = minf(600.0, span / 2.0)
	var ps := PackedFloat32Array()
	var rs := PackedFloat32Array()
	var p := p_min
	while p <= p_max:
		ps.append(p)
		rs.append(_resultant(xs, ws, p).length())
		p += maxf(0.02, p * p / (8.0 * span))
	if ps.is_empty():
		return {}
	var best := 0.0
	for r in rs:
		best = maxf(best, r)
	if best < 0.5:
		return {}
	# The biggest period (a peak) the edges keep to nearly as well as to the best one is taken;
	# the periods they keep to fairly well are there to choose from ("candidates", smallest
	# first).
	var candidates: Array = []
	var pick := -1
	for i in ps.size():
		var peak := (i == 0 or rs[i] >= rs[i - 1]) and (i == ps.size() - 1 or rs[i] >= rs[i + 1])
		if peak and rs[i] >= best * 0.6:
			candidates.append(_refine(xs, ws, signs, ps[maxi(0, i - 1)], ps[mini(ps.size() - 1, i + 1)], ps[i], rs[i], p_min))
			if rs[i] >= best * 0.85:
				pick = candidates.size() - 1
	if pick < 0:
		return {}
	var out: Dictionary = candidates[pick].duplicate()
	out.candidates = candidates
	return out

## The exact period near [param period] (between [param lo] and [param hi]) and its phase:
## {period, phase, strength}.
static func _refine(xs: PackedFloat32Array, ws: PackedFloat32Array, signs: PackedFloat32Array, lo: float, hi: float, period: float, strength: float, p_min: float) -> Dictionary:
	for k in 41:
		var q := lerpf(lo, hi, k / 40.0)
		var r := _resultant(xs, ws, q).length()
		if r > strength:
			strength = r
			period = q
	var v := _resultant(xs, ws, period)
	var phase := fposmod(atan2(v.y, v.x) / TAU * period, period)
	# Then exactly: each edge at its whole number of cells, where rooms start a little after the
	# grid line and end as much before it (edges far from every grid line left out).
	var inset := 0.0
	for it in 4:
		var m := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		var rhs := [0.0, 0.0, 0.0]
		var used := 0
		for i in xs.size():
			var k := roundf((xs[i] - phase - signs[i] * inset) / period)
			if absf(xs[i] - phase - signs[i] * inset - k * period) > period * 0.25:
				continue
			var f := [1.0, k, signs[i]]
			for r in 3:
				for c in 3:
					m[r][c] += ws[i] * f[r] * f[c]
				rhs[r] += ws[i] * f[r] * xs[i]
			used += 1
		if used < 3:
			break
		var sol := _solve3(m, rhs)
		if sol.is_empty() or sol[1] < p_min or absf(sol[1] - period) > period * 0.1:
			break
		period = sol[1]
		phase = fposmod(sol[0], period)
		inset = clampf(sol[2], -period * 0.25, period * 0.25)
	return {"period": period, "phase": phase, "strength": strength}

## The peaks of [param profile] (more than 15% of the highest), with [param sign].
static func _peaks(profile: PackedFloat32Array, sign_value: float, xs: PackedFloat32Array, ws: PackedFloat32Array, signs: PackedFloat32Array) -> void:
	var n := profile.size()
	var top := 0.0
	for v in profile:
		top = maxf(top, v)
	if top <= 0.0:
		return
	for x in range(1, n - 1):
		var v := profile[x]
		if v >= top * 0.15 and v >= profile[x - 1] and v > profile[x + 1]:
			xs.append(x)
			ws.append(v)
			signs.append(sign_value)

## Solves the 3 x 3 system [param m] * x = [param b]; [] when it has no single solution.
static func _solve3(m: Array, b: Array) -> Array:
	var det := _det3(m)
	if absf(det) < 0.000001:
		return []
	var out := []
	for c in 3:
		var mc := [m[0].duplicate(), m[1].duplicate(), m[2].duplicate()]
		for r in 3:
			mc[r][c] = b[r]
		out.append(_det3(mc) / det)
	return out

static func _det3(m: Array) -> float:
	return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
		- m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
		+ m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))

## Mean of the edges [param xs] (weights [param ws]) as angles on a circle of [param period].
static func _resultant(xs: PackedFloat32Array, ws: PackedFloat32Array, period: float) -> Vector2:
	var c := 0.0
	var s := 0.0
	var total := 0.0
	var k := TAU / period
	for i in xs.size():
		c += ws[i] * cos(xs[i] * k)
		s += ws[i] * sin(xs[i] * k)
		total += ws[i]
	return Vector2(c, s) / total if total > 0.0 else Vector2.ZERO

# --- Areas, walls, doors -----------------------------------------------------------------------

## How far apart two room colors are, for areas: hue and saturation count, brightness less (the
## shades one map style draws a room in are one area).
static func color_distance(a: Color, b: Color) -> float:
	var dh := absf(a.h - b.h)
	dh = minf(dh, 1.0 - dh)
	return dh * 2.0 * minf(a.s, b.s) + absf(a.s - b.s) * 0.7 + absf(a.v - b.v) * 0.35

func _group_colors(room_cells: Dictionary) -> Array:
	var groups: Array = [] # {color, sum (Color), n}
	for c: Vector2i in room_cells:
		var col: Color = room_cells[c]
		var g := _nearest_group(groups, col)
		if g >= 0 and color_distance(groups[g].color, col) <= color_tolerance:
			groups[g].sum += col
			groups[g].n += 1
			groups[g].color = groups[g].sum / float(groups[g].n)
		else:
			groups.append({"color": col, "sum": col, "n": 1})
	# Biggest first.
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.n) > int(b.n))
	return groups

static func _nearest_group(groups: Array, col: Color) -> int:
	var best := -1
	var best_d := INF
	for i in groups.size():
		var d := color_distance(groups[i].color, col)
		if d < best_d:
			best_d = d
			best = i
	return best

## The edge between cells [param a] and [param b] (b right of or under a): {open (nothing parts
## them), door_t (0..1 along it: a gap in its wall, or a gate marker on it)}. Lines across it
## are looked along: closed where a wall line is right at the edge (ink, or a color unlike both
## cells'), open where not; lines whose ends aren't room (a cell the room's curved outline
## cuts) count for nothing. A wall closes most of them, a door gap opens its middle; a label's
## letters close a few here and there.
func _edge(a: Vector2i, b: Vector2i, color_a: Color, color_b: Color) -> Dictionary:
	var across := b.x != a.x # the edge is upright: lines cross it left to right
	var along := cell_size.y if across else cell_size.x
	var depth := cell_size.x if across else cell_size.y
	var edge := grid_offset.x + b.x * cell_size.x if across else grid_offset.y + b.y * cell_size.y
	var start := grid_offset.y + a.y * cell_size.y if across else grid_offset.x + a.x * cell_size.x
	var near := maxf(2.0, depth * 0.06)
	var states: Array[int] = [] # per line looked along: 0 open, 1 closed
	var ts: Array[float] = []
	var hits: Array[float] = [] # closed lines: how far from the edge, and in what color
	var hit_colors: Array[Color] = []
	for i in EDGE_LINES:
		var t := 0.1 + 0.8 * i / float(EDGE_LINES - 1)
		var u := start + t * along
		var ends_in := true
		for k in [-depth * 0.3, depth * 0.3]:
			if label_at(floori(edge + k) if across else floori(u), floori(u) if across else floori(edge + k)) != FILL:
				ends_in = false
		if not ends_in:
			continue
		var hit := false
		var k := -near
		while k <= near:
			var x := floori(edge + k) if across else floori(u)
			var y := floori(u) if across else floori(edge + k)
			if label_at(x, y) != FILL or _parts(_pixel(x, y), color_a, color_b):
				hit = true
				hits.append(k)
				hit_colors.append(_pixel(x, y))
				break
			k += 1.0
		states.append(1 if hit else 0)
		ts.append(t)
	var closed := states.count(1)
	var out := {"open": states.size() < 2 or closed < 0.7 * states.size()}
	if out.open:
		# Unless it is a wall with a gap: one straight line (as far from the edge, of one color)
		# closing two lines or more at each end, open in one run in the middle.
		var first := states.find(0)
		var last := states.rfind(0)
		var gap := states.size() >= 5 and first >= 2 and last <= states.size() - 3
		if gap:
			for i in range(first, last + 1):
				if states[i] == 1:
					gap = false
		if gap:
			gap = _straight(hits, hit_colors)
		if not gap:
			return out
		out.open = false
		if detect_doors:
			out.door_t = (ts[first] + ts[last]) / 2.0
		return out
	if not _straight(hits, hit_colors):
		# Closed here and there by what isn't one line (letters of a label across the edge).
		out.open = true
		return out
	if detect_doors:
		# A gate marker on the wall: a bright spot of another color than both rooms.
		var mark := _marker(across, edge, start, along, depth, color_a, color_b)
		if mark >= 0.0:
			out.door_t = mark
	return out

## Whether the closed lines of an edge are closed by one straight line: most of them (a gate
## marker on it closes some) as far from
## the edge (2 px), of one color.
func _straight(hits: Array[float], colors: Array[Color]) -> bool:
	if hits.size() < 2:
		return true
	var sorted := hits.duplicate()
	sorted.sort()
	var mid: float = sorted[sorted.size() / 2]
	var mid_color: Color = colors[hits.find(mid)]
	var like := 0
	for i in hits.size():
		var c := colors[i]
		if absf(hits[i] - mid) <= 2.0 and maxf(maxf(absf(c.r - mid_color.r), absf(c.g - mid_color.g)), absf(c.b - mid_color.b)) <= wall_contrast:
			like += 1
	return like >= 0.6 * hits.size()

## Whether [param p] is unlike both [param a] and [param b] (see [member wall_contrast]).
func _parts(p: Color, a: Color, b: Color) -> bool:
	var da := maxf(maxf(absf(p.r - a.r), absf(p.g - a.g)), absf(p.b - a.b))
	var db := maxf(maxf(absf(p.r - b.r), absf(p.g - b.g)), absf(p.b - b.b))
	return da > wall_contrast and db > wall_contrast

## Where along an edge a gate marker is (0..1), or -1.
func _marker(across: bool, edge: float, start: float, along: float, depth: float, color_a: Color, color_b: Color) -> float:
	var step := maxf(1.0, minf(along, depth) / 30.0)
	var n := 0
	var sum := 0.0
	var u := start + along * 0.1
	while u <= start + along * 0.9:
		var k := -depth * 0.2
		while k <= depth * 0.2:
			var x := floori(edge + k) if across else floori(u)
			var y := floori(u) if across else floori(edge + k)
			if label_at(x, y) == FILL:
				var p := _pixel(x, y)
				var bright := p.v > 0.8 and (p.s < 0.2 or p.s > 0.5)
				if bright and color_distance(p, color_a) > color_tolerance * 2.0 and color_distance(p, color_b) > color_tolerance * 2.0:
					n += 1
					sum += u
			k += step
		u += step
	if n < 3:
		return -1.0
	return clampf((sum / n - start) / along, 0.0, 1.0)

static func _find(parent: Dictionary, c: Vector2i) -> Vector2i:
	var r: Vector2i = c
	while parent[r] != r:
		r = parent[r]
	var x: Vector2i = c
	while parent[x] != r:
		var nx: Vector2i = parent[x]
		parent[x] = r
		x = nx
	return r

static func _union(parent: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra

# --- Onto the map ------------------------------------------------------------------------------

## The paint cell where a picture's top-left room lands by default on [param layer]: right of
## the rooms there (two cells apart), at their top; (0, 0) on an empty layer.
static func free_cell(world: MDSWorld, layer: int) -> Vector2i:
	var b := world.get_layer_bounds(layer)
	if not b.has_area():
		return Vector2i.ZERO
	var c := world.get_paint_cell()
	return Vector2i(ceili(b.end.x / c.x) + 2, floori(b.position.y / c.y))

## Puts what [method analyze] found on [param world]'s [param layer]: an area per color
## ([param area_names] names them in order, else "Imported N"), a room per room, a pair of
## connected gates per door. The picture's top-left room cell lands on paint cell
## [param at_cell] (default [method free_cell]); with [param keep_cells], each grid cell lands
## on the paint cell of the same number (a picture MDS exported, with its sidecar: where the
## rooms were). Cells other rooms have are left out. No checkpoint: the caller takes one.
## Returns {areas, rooms: names made; doors: gate pairs made; skipped_cells; passages: rooms made
## to join parts apart}.
func apply(world: MDSWorld, layer := 0, at_cell := Vector2i.MAX, area_names: Array = [], keep_cells := false) -> Dictionary:
	var out := {"areas": [], "rooms": [], "doors": 0, "skipped_cells": 0}
	if found.is_empty():
		analyze()
	if found.rooms.is_empty():
		return out
	var drawn := bool(found.get("shapes", false))
	var k := Vector2i.ONE if drawn else Vector2i(maxi(1, cells_per_map_cell.x), maxi(1, cells_per_map_cell.y))
	var first := Vector2i(1 << 30, 1 << 30)
	for c: Vector2i in found.cells:
		first = Vector2i(mini(first.x, c.x), mini(first.y, c.y))
	var shift := Vector2i.ZERO
	if not keep_cells or drawn:
		var at := at_cell if at_cell != Vector2i.MAX else free_cell(world, layer)
		shift = at - first * k
	var taken := MDSAreaTools.occupied(world, layer)
	# Areas.
	var area_of: Array[String] = []
	for g in found.areas.size():
		var wanted := str(area_names[g]).strip_edges() if g < area_names.size() else ""
		var name := wanted
		if name.is_empty() or (world.has_area(name) and g >= area_names.size()):
			var n := 1
			name = "Imported %d" % n
			while world.has_area(name):
				n += 1
				name = "Imported %d" % n
		if not world.has_area(name):
			world.add_area(name, found.areas[g].color as Color)
			out.areas.append(name)
		area_of.append(name)
	# A drawn map's areas' outlines (world px), which their rooms keep as theirs on the map.
	var s := world.get_paint_cell()
	var outlines: Array = []
	if drawn:
		var cell_px: Vector2 = found.cell_size
		var origin: Vector2 = found.grid_offset
		for g in found.areas.size():
			var polys: Array = []
			for poly: PackedVector2Array in found.areas[g].get("outline", []):
				var world_poly := PackedVector2Array()
				for p in poly:
					world_poly.append(((p - origin) / cell_px + Vector2(shift)) * s)
				polys.append(world_poly)
			outlines.append(polys)
	# Rooms.
	var ids: Array[String] = []
	var room_cells: Array = [] # per room: {paint cell: true}
	for room: Dictionary in found.rooms:
		var paint: Dictionary = {}
		for c: Vector2i in room.cells:
			for dy in k.y:
				for dx in k.x:
					var pc := c * k + Vector2i(dx, dy) + shift
					if taken.has(pc):
						out.skipped_cells += 1
					else:
						paint[pc] = true
		room_cells.append(paint)
		if paint.is_empty():
			ids.append("")
			continue
		var area: String = area_of[room.area] if room.area >= 0 and room.area < area_of.size() else ""
		var cells: Array = paint.keys()
		cells.sort()
		var id := world.add_room(MDSAreaGenerator.room_base(area), world.cell_to_world_rect(cells[0]), layer, area)
		world.set_room_cells(id, paint)
		if drawn and room.area >= 0 and room.area < outlines.size():
			_shape_room(world, id, room.cells, paint, outlines[room.area], found.cover, s)
		for pc in paint:
			taken[pc] = id
		ids.append(id)
		out.rooms.append(id)
	# Doors where the picture shows them.
	var cell := world.get_paint_cell()
	var joined: Dictionary = {}
	for d: Dictionary in found.doors:
		var a := ids[d.a]
		var b := ids[d.b]
		if a.is_empty() or b.is_empty():
			continue
		var c: Vector2i = d.cell
		var base := Vector2(c * k + shift) * cell
		var size := Vector2(k) * cell
		var pos: Vector2 = base + (Vector2(size.x, size.y * d.t) if d.side == "right" else Vector2(size.x * d.t, size.y))
		if _door(world, a, b, pos, d.side):
			out.doors += 1
			joined[[a, b]] = true
			joined[[b, a]] = true
	# Rooms no door reaches: one to a room they touch.
	if connect_unreached and ids.size() > 1:
		var made: Array[String] = []
		for id in ids:
			if not id.is_empty():
				made.append(id)
		out.doors += _connect_all(world, made, layer)
		if drawn and passage_cells > 0 and MDSAreaTools.pieces(world, made) > 1:
			var joined_up := MDSAreaTools.link_apart(world, made, passage_cells)
			out.doors += joined_up.doors.size()
			out.rooms.append_array(joined_up.rooms)
			out["passages"] = joined_up.rooms
	return out

## Room [param id] of a drawn map keeps the part of its area's outline ([param polys], world px)
## its cells hold, when the outline doesn't cover them all ([param cover]: picture cell -> share).
static func _shape_room(world: MDSWorld, id: String, cells: Array, paint: Dictionary, polys: Array, cover: Dictionary, s: Vector2) -> void:
	var weight := 0.0
	for c: Vector2i in cells:
		weight += float(cover.get(c, 1.0))
	if weight >= cells.size() - 0.001 or polys.is_empty():
		return
	var shape: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in polys:
		if MDSGeometry.bounds(poly).intersects(world.get_room_bounds(id)):
			shape.append_array(MDSAreaGenerator.room_outline(paint, poly, s))
	if not shape.is_empty():
		world.set_room_shape(id, shape)

## A pair of connected gates between rooms [param a] and [param b] at [param pos] (world px, on
## their shared edge; [param side]: a's side there).
func _door(world: MDSWorld, a: String, b: String, pos: Vector2, side: String) -> bool:
	var other: String = {"right": "left", "left": "right", "bot": "top", "top": "bot"}[side]
	var ga := world.add_gate(a, pos, side, "", false)
	var gb := world.add_gate(b, pos, other, "", false)
	if ga.is_empty() or gb.is_empty():
		return false
	world.connect_gates(a, ga, b, gb)
	return true

## Doors so every room of [param ids] can be reached from the first: between rooms that touch,
## where none joins their groups yet. Returns how many.
static func _connect_all(world: MDSWorld, ids: Array[String], layer: int) -> int:
	var group: Dictionary = {}
	for id in ids:
		group[id] = id
	var root := func(id: String) -> String:
		var r: String = id
		while group[r] != r:
			r = group[r]
		return r
	for id in ids:
		for g: Dictionary in world.get_gates(id).values():
			var to := str(g.get("to", ""))
			if group.has(to):
				var ra: String = root.call(id)
				var rb: String = root.call(to)
				if ra != rb:
					group[rb] = ra
	var cells := MDSAreaTools.cells_of(world, ids)
	var contacts := MDSAreaTools.contacts(cells, cells)
	var pairs: Array = contacts.keys()
	# Longest shared walls first.
	pairs.sort_custom(func(x: Array, y: Array) -> bool: return int(contacts[x]) > int(contacts[y]))
	var n := 0
	for pair: Array in pairs:
		var a: String = pair[0]
		var b: String = pair[1]
		if not group.has(a) or not group.has(b):
			continue
		var ra: String = root.call(a)
		var rb: String = root.call(b)
		if ra == rb:
			continue
		var made := MDSAreaTools.add_door(world, a, b, false)
		if not made.is_empty():
			group[rb] = ra
			n += 1
	return n
