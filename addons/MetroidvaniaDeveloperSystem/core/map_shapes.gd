@tool
class_name MDSMapShapes
extends RefCounted
## Reads a map drawn freely, with no grid (a Hollow Knight or Silksong map): each area one shape
## filled with a dark color of its own and outlined in a lighter one, areas touching each other,
## names written beside them. [MDSMapImageImporter] uses it when its rooms are
## [constant MDSMapImageImporter.RoomMode.SHAPES], or when the picture shows no grid.
## [codeblock]
## var shapes := MDSMapShapes.new()
## var found := shapes.analyze(image, Color.BLACK, world.get_paint_cell())  # areas, rooms, doors, outlines
## [/codeblock]
## How it reads the picture:
## - The background is [param background] (the picture's frame); pixels near it are not the map.
## - Fills: regions of one flat color (each pixel within [member flat] of the next), thick
##   enough not to be lines: outlines, letters and icons are lines.
## - The lines and pixels around a fill (its outline, blends, icons drawn on it) are the fill's,
##   up to [member claim_px] away. Names written apart from the map are left out.
## - Fills that touch, of about the same color ([member same_area]), are one area.
## - The areas lie on the world's paint cells, [member cells_across] of them across the map:
##   a cell is an area's when [member min_cover] of it is that area's. An area's cells are split
##   into rooms like a generated area's ([MDSAreaGenerator]), with doors between them, and keep
##   the area's outline (traced from the picture) as their outline on the map.

## Paint cells across the map's width (its scale).
var cells_across := 120
## The share of a paint cell an area must cover to have it.
var min_cover := 0.3
## How far a pixel may be from the next and be the same flat fill (0..1, any of R, G, B).
var flat := 0.05
## How far a pixel may be from its fill's first color (0..1): two areas' fills meeting with no
## line between, a shade apart, stay two.
var fill_tolerance := 0.03
## How far from the background a pixel must be to be the map's (0..1).
var background_tolerance := 0.06
## Fills whose colors are this near (0..1, any of R, G, B) and that touch are one area.
var same_area := 0.02
## How far (picture px) a fill takes in the lines around it.
var claim_px := 6.0
## The smallest fill (picture px²): smaller ones are specks, or parts of letters.
var min_fill_px := 120.0
## The biggest picture side worked on (px): bigger pictures are read scaled down.
var work_size := 1200
## Rooms' sizes in paint cells (see [member MDSAreaGenerator.room_min], [member MDSAreaGenerator.room_max]).
var room_min := Vector2i(1, 1)
var room_max := Vector2i(5, 3)
var seed_value := 0

## Finds the areas and rooms in [param image] ([param background]: its background color) for a
## world of [param paint_cell] paint cells: {shapes: true, cell_size (picture px per paint cell),
## grid_offset, cells: {paint cell: area index}, cover: {paint cell: share}, areas: [{color,
## cells, outline: [polygons, picture px]}], rooms: [{cells, area}], doors: [{a, b, cell, side
## ("right" or "bot", of room a's cell), t}], warnings}.
func analyze(image: Image, background: Color, paint_cell := Vector2(288, 162)) -> Dictionary:
	var warnings: PackedStringArray = []
	var out := {"shapes": true, "cell_size": Vector2.ONE, "grid_offset": Vector2.ZERO, "grid_found": false, "cells": {}, "cover": {}, "areas": [], "rooms": [], "doors": [], "warnings": warnings}
	if not image or image.get_width() < 8 or image.get_height() < 8:
		warnings.append("No picture.")
		return out
	# Worked on at most work_size px a side.
	var f := minf(1.0, float(work_size) / maxf(image.get_width(), image.get_height()))
	var img := image.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if f < 1.0:
		img.resize(maxi(8, roundi(img.get_width() * f)), maxi(8, roundi(img.get_height() * f)), Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var n := w * h
	var bg := [int(background.r8), int(background.g8), int(background.b8)]
	var bg_tol := int(background_tolerance * 255.0)
	var map := PackedByteArray()
	map.resize(n)
	for i in n:
		var o := i * 4
		if data[o + 3] >= 128 and maxi(maxi(absi(data[o] - bg[0]), absi(data[o + 1] - bg[1])), absi(data[o + 2] - bg[2])) > bg_tol:
			map[i] = 1
	# Flat regions: neighbours within `flat` of each other.
	var region := PackedInt32Array()
	region.resize(n)
	region.fill(-1)
	var flat_8 := int(flat * 255.0)
	var fill_8 := int(fill_tolerance * 255.0)
	var sizes: Array[int] = []
	var inner: Array[int] = []
	var sums: Array = []
	var stack := PackedInt32Array()
	for start in n:
		if map[start] == 0 or region[start] >= 0:
			continue
		var id := sizes.size()
		var count := 0
		var inside := 0
		var sr := 0
		var sg := 0
		var sb := 0
		var s0 := start * 4
		var seed := [data[s0], data[s0 + 1], data[s0 + 2]]
		region[start] = id
		stack.clear()
		stack.append(start)
		while not stack.is_empty():
			var p: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var o := p * 4
			sr += data[o]
			sg += data[o + 1]
			sb += data[o + 2]
			var x := p % w
			var all_in := x > 0 and x < w - 1 and p >= w and p < n - w
			for q in [p - 1, p + 1, p - w, p + w]:
				if q < 0 or q >= n or (q == p - 1 and x == 0) or (q == p + 1 and x == w - 1):
					continue
				if map[q] == 0:
					all_in = false
					continue
				var oq: int = q * 4
				if maxi(maxi(absi(data[oq] - data[o]), absi(data[oq + 1] - data[o + 1])), absi(data[oq + 2] - data[o + 2])) > flat_8 or maxi(maxi(absi(data[oq] - seed[0]), absi(data[oq + 1] - seed[1])), absi(data[oq + 2] - seed[2])) > fill_8:
					all_in = false
					continue
				if region[q] < 0:
					region[q] = id
					stack.append(q)
			if all_in:
				inside += 1
		sizes.append(count)
		inner.append(inside)
		sums.append(Color(sr / 255.0 / count, sg / 255.0 / count, sb / 255.0 / count))
	# Fills: big and thick (most of their pixels inside them); the rest are lines.
	var min_px := min_fill_px * f * f
	var fill_of := PackedInt32Array() # region -> fill index, -1
	fill_of.resize(sizes.size())
	fill_of.fill(-1)
	var fill_colors: Array[Color] = []
	for r in sizes.size():
		if sizes[r] >= min_px and inner[r] >= sizes[r] * 0.35:
			fill_of[r] = fill_colors.size()
			fill_colors.append(sums[r])
	if fill_colors.is_empty():
		warnings.append("No filled shapes found: is the map's background %s?" % background.to_html(false))
		return out
	# Every map pixel near a fill is the fill's: its outline, blends, icons on it.
	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(-1)
	var dist := PackedInt32Array()
	dist.resize(n)
	var queue := PackedInt32Array()
	for i in n:
		if region[i] >= 0 and fill_of[region[i]] >= 0:
			owner[i] = fill_of[region[i]]
			queue.append(i)
	var reach := maxi(1, roundi(claim_px * f))
	var contact: Dictionary = {} # Vector2i(fill a, fill b) -> count
	var head := 0
	while head < queue.size():
		var p: int = queue[head]
		head += 1
		var x := p % w
		for q in [p - 1, p + 1, p - w, p + w]:
			if q < 0 or q >= n or (q == p - 1 and x == 0) or (q == p + 1 and x == w - 1) or map[q] == 0:
				continue
			if owner[q] >= 0:
				if owner[q] != owner[p]:
					var key := Vector2i(mini(owner[p], owner[q]), maxi(owner[p], owner[q]))
					contact[key] = int(contact.get(key, 0)) + 1
				continue
			if dist[p] >= reach:
				continue
			owner[q] = owner[p]
			dist[q] = dist[p] + 1
			queue.append(q)
	# Areas: fills that touch, of about the same color.
	var parent: Array[int] = []
	for i in fill_colors.size():
		parent.append(i)
	for key: Vector2i in contact:
		var ra := _root(parent, key.x)
		var rb := _root(parent, key.y)
		# The two areas' first fills alike, so shades don't chain from one area into the next.
		var a: Color = fill_colors[ra]
		var b: Color = fill_colors[rb]
		if ra != rb and maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) <= same_area:
			parent[maxi(ra, rb)] = mini(ra, rb)
	var area_index: Dictionary = {} # root fill -> area
	var area_of_fill: Array[int] = []
	for i in fill_colors.size():
		var r := _root(parent, i)
		if not area_index.has(r):
			area_index[r] = area_index.size()
		area_of_fill.append(area_index[r])
	var area_count := area_index.size()
	var area_px: Array[int] = []
	area_px.resize(area_count)
	var area_col: Array = []
	for a in area_count:
		area_col.append(Vector3.ZERO)
	for i in n:
		var o: int = owner[i]
		if o >= 0 and region[i] >= 0 and fill_of[region[i]] == o:
			var a: int = area_of_fill[o]
			area_px[a] += 1
			area_col[a] += Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
	# The paint cells: the map's scale from its width (what the areas take of it).
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for i in n:
		if owner[i] >= 0:
			lo = Vector2i(mini(lo.x, i % w), mini(lo.y, i / w))
			hi = Vector2i(maxi(hi.x, i % w), maxi(hi.y, i / w))
	var cell_w := maxf(2.0, float(hi.x - lo.x + 1) / maxi(1, cells_across))
	var cell := Vector2(cell_w, cell_w * paint_cell.y / paint_cell.x)
	var origin := Vector2(lo)
	var cols := ceili((hi.x - lo.x + 1) / cell.x) + 1
	var rows := ceili((hi.y - lo.y + 1) / cell.y) + 1
	# Each cell's pixels by area.
	var counts: Dictionary = {} # Vector3i(x, y, area) -> px
	for i in n:
		var o: int = owner[i]
		if o < 0:
			continue
		var c := Vector2i(int((i % w - origin.x) / cell.x), int((i / w - origin.y) / cell.y))
		var key := Vector3i(c.x, c.y, area_of_fill[o])
		counts[key] = int(counts.get(key, 0)) + 1
	var cell_area := cell.x * cell.y
	var best: Dictionary = {} # cell -> [area, share]
	var shares: Array = [] # per area: {cell: share}
	for a in area_count:
		shares.append({})
	for key: Vector3i in counts:
		var share := float(counts[key]) / cell_area
		var c := Vector2i(key.x, key.y)
		shares[key.z][c] = share
		if not best.has(c) or share > float(best[c][1]):
			best[c] = [key.z, share]
	var area_cells: Array = []
	for a in area_count:
		area_cells.append({})
	for c: Vector2i in best:
		if float(best[c][1]) >= min_cover:
			area_cells[best[c][0]][c] = true
	# Thin parts (a corridor across two rows of cells) kept: an area's pieces joined through the
	# cells it covers least.
	var taken: Dictionary = {}
	for a in area_count:
		for c in area_cells[a]:
			taken[c] = a
	for a in area_count:
		_join_pieces(area_cells[a], shares[a], taken, a)
	# Areas, their outlines, their rooms.
	var gen := MDSAreaGenerator.new()
	gen.room_min = room_min
	gen.room_max = room_max.max(room_min)
	var cells_out: Dictionary = {}
	var cover_out: Dictionary = {}
	var areas: Array = []
	var rooms: Array = []
	var doors: Array = []
	var kept: Array[int] = [] # work area -> output area
	kept.resize(area_count)
	kept.fill(-1)
	for a in area_count:
		if (area_cells[a] as Dictionary).is_empty():
			continue
		kept[a] = areas.size()
		var col: Vector3 = area_col[a] / maxf(1.0, float(area_px[a])) / 255.0
		var listed: Array[Vector2i] = []
		for c: Vector2i in area_cells[a]:
			listed.append(c)
			cells_out[c] = kept[a]
			cover_out[c] = minf(1.0, float(shares[a].get(c, 0.0)))
		areas.append({"color": Color(col.x, col.y, col.z), "cells": listed, "outline": _outline(owner, area_of_fill, a, w, h, f)})
		for piece: Dictionary in MDSAreaGenerator.components(area_cells[a]):
			gen.seed_value = hash([seed_value, a, rooms.size()])
			var parts := gen.partition(piece, cover_out)
			var first := rooms.size()
			for part: Dictionary in parts:
				var cl: Array[Vector2i] = []
				for c: Vector2i in part:
					cl.append(c)
				rooms.append({"cells": cl, "area": kept[a]})
			for pair: Vector2i in gen.doors(parts):
				var d := _door(parts[pair.x], parts[pair.y], cover_out, first + pair.x, first + pair.y)
				if not d.is_empty():
					doors.append(d)
	if rooms.is_empty():
		warnings.append("The shapes found are smaller than a paint cell: raise the cells across.")
		return out
	# A door between areas that touch, between the two rooms sharing the most.
	var room_at: Dictionary = {}
	for r in rooms.size():
		for c: Vector2i in rooms[r].cells:
			room_at[c] = r
	var between: Dictionary = {} # Vector2i(area a, area b) -> [room a, room b, count]
	for c: Vector2i in room_at:
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			var o: Vector2i = c + d
			if not room_at.has(o):
				continue
			var ra: int = room_at[c]
			var rb: int = room_at[o]
			var aa: int = rooms[ra].area
			var ab: int = rooms[rb].area
			if aa == ab:
				continue
			var key := Vector2i(mini(aa, ab), maxi(aa, ab))
			var pair := Vector2i(mini(ra, rb), maxi(ra, rb))
			var tally: Dictionary = between.get(key, {})
			tally[pair] = int(tally.get(pair, 0)) + 1
			between[key] = tally
	for key: Vector2i in between:
		var tally: Dictionary = between[key]
		var top := Vector2i(-1, -1)
		for pair: Vector2i in tally:
			if top.x < 0 or int(tally[pair]) > int(tally[top]):
				top = pair
		var room_cells: Array = [{}, {}]
		for k in 2:
			for c: Vector2i in rooms[top.x if k == 0 else top.y].cells:
				room_cells[k][c] = true
		var d := _door(room_cells[0], room_cells[1], cover_out, top.x, top.y)
		if not d.is_empty():
			doors.append(d)
	out.cell_size = cell / f
	out.grid_offset = origin / f
	out.cells = cells_out
	out.cover = cover_out
	out.areas = areas
	out.rooms = rooms
	out.doors = doors
	return out

## A door between room cells [param a] (room [param ia]) and [param b] (room [param ib]) where
## they touch, in [MDSMapImageImporter]'s form: {a, b, cell, side ("right" or "bot"), t}.
static func _door(a: Dictionary, b: Dictionary, cover: Dictionary, ia: int, ib: int) -> Dictionary:
	var d := MDSAreaTools.door_between(a, b, func(c: Vector2i) -> float: return float(cover.get(c, 1.0)))
	if d.is_empty():
		return {}
	var c: Vector2i = d.cell
	var dir: Vector2i = d.dir
	if dir == Vector2i.RIGHT or dir == Vector2i.DOWN:
		return {"a": ia, "b": ib, "cell": c, "side": "right" if dir == Vector2i.RIGHT else "bot", "t": 0.5}
	return {"a": ib, "b": ia, "cell": c + dir, "side": "right" if dir == Vector2i.LEFT else "bot", "t": 0.5}

## Joins the pieces of [param cells] (one area's, changed in place) through the cells it covers
## at all ([param shares]) and no other area has ([param taken]: cell -> area), fewest first.
static func _join_pieces(cells: Dictionary, shares: Dictionary, taken: Dictionary, area: int) -> void:
	var pieces := MDSAreaGenerator.components(cells)
	while pieces.size() > 1:
		var main: Dictionary = pieces[0]
		var prev: Dictionary = {}
		var queue: Array[Vector2i] = []
		for c: Vector2i in main:
			prev[c] = c
			queue.append(c)
		var found := Vector2i(1 << 30, 0)
		var head := 0
		while head < queue.size() and found.x == 1 << 30:
			var c: Vector2i = queue[head]
			head += 1
			for d in MDSAreaTools.DIRS:
				var nb: Vector2i = c + d
				if prev.has(nb) or not shares.has(nb) or (taken.has(nb) and int(taken[nb]) != area):
					continue
				prev[nb] = c
				if cells.has(nb) and not main.has(nb):
					found = nb
					break
				queue.append(nb)
		if found.x == 1 << 30:
			return
		var at: Vector2i = prev[found]
		while not main.has(at):
			cells[at] = true
			taken[at] = area
			at = prev[at]
		pieces = MDSAreaGenerator.components(cells)

## The outline of area [param a] (picture px): its pixels' shapes, traced.
static func _outline(owner: PackedInt32Array, area_of_fill: Array[int], a: int, w: int, h: int, f: float) -> Array:
	var bits := BitMap.new()
	bits.create(Vector2i(w, h))
	for i in owner.size():
		if owner[i] >= 0 and area_of_fill[owner[i]] == a:
			bits.set_bit(i % w, i / w, true)
	var out: Array = []
	for poly: PackedVector2Array in bits.opaque_to_polygons(Rect2i(0, 0, w, h), 1.0):
		if poly.size() >= 3 and absf(MDSGeometry.signed_area(poly)) >= 16.0:
			var scaled := PackedVector2Array()
			for p in poly:
				scaled.append(p / f)
			out.append(scaled)
	return out

static func _root(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
