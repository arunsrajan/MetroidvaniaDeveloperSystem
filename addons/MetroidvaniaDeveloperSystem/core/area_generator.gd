@tool
class_name MDSAreaGenerator
extends RefCounted
## Generates an area of the world map. Its outline is a polygon: a rectangle or square,
## irregular blocks, a freeform curvy blob, or a hybrid of them (a blob with halls and towers,
## corridors reaching out), its corners rounded into curves ([member curves]) or cut on a
## slant ([member slants]). The paint cells it covers are split into rooms: rectangles,
## irregular L, T and U shapes, a few tall shafts. Each room keeps the part of the outline it
## holds as its outline on the map ([method MDSWorld.set_room_shape]), so the area's curved and
## slanted sides show while the rooms stay rectangles for the game. Neighbouring rooms are joined
## with doors (connected gate pairs) so every room can be reached, plus a few loops. Painted
## cells are split and joined the same way ([method fill]).
##
## Plain data: works on an [MDSWorld] and cell sets (Vector2i -> true), no editor needed.
## [codeblock]
## var gen := MDSAreaGenerator.new()
## gen.shape = MDSAreaGenerator.Shape.HYBRID
## gen.seed_value = 7
## var result := gen.generate(world, Rect2i(0, 0, 24, 14), 0, "The Ashen Depths")
## print(result.rooms, " ", result.doors)
## [/codeblock]

enum Shape { RECTANGLE, IRREGULAR, FREEFORM, HYBRID }
const SHAPE_IDS: PackedStringArray = ["rectangle", "irregular", "freeform", "hybrid"]
const SHAPE_NAMES: PackedStringArray = ["Rectangle or square", "Irregular blocks", "Freeform (curvy)", "Hybrid (curves, slants and blocks)"]
## Cells the outline covers less of than this are left out.
const MIN_COVER := 0.04

const _ADJECTIVES: PackedStringArray = ["Ashen", "Sunken", "Hollow", "Crimson", "Frozen", "Whispering", "Shattered", "Gilded", "Drowned", "Verdant", "Silent", "Burning", "Forgotten", "Iron", "Weeping", "Pale", "Ember", "Moonlit", "Thorned", "Howling", "Crystal", "Rotting", "Starlit", "Sundered"]
const _NOUNS: PackedStringArray = ["Depths", "Gardens", "Spire", "Crypts", "Caverns", "Wastes", "Marsh", "Ruins", "Halls", "Forge", "Hollows", "Peaks", "Mines", "Archive", "Citadel", "Grotto", "Thicket", "Bastion", "Reach", "Vaults", "Jungle", "Glacier", "Sanctum", "Warrens"]

var shape: Shape = Shape.HYBRID
## Smallest room (paint cells).
var room_min := Vector2i(2, 2)
## Largest room (paint cells).
var room_max := Vector2i(5, 3)
## Share of rooms joined with a neighbour into one irregular room (L, T, U shapes).
var irregularity := 0.35
## Share of rooms that are tall, narrow shafts.
var shafts := 0.12
## Share of the other neighbour pairs that get a door too: loops (0: one way to each room).
var loops := 0.2
## How ragged a freeform outline is.
var roughness := 0.5
## Corridors reaching out of a freeform or hybrid shape.
var tendrils := 2
## Share of the outline's corners rounded into curves (and of the corridors that curve).
var curves := 0.45
## Share of the outline's corners cut on a slant, of the blocks with a slanted side, and of the
## corridors that run straight and turn at angles.
var slants := 0.3
var seed_value := 0
## Doors made by the last [method generate] or [method fill].
var last_doors := 0

var _rng := RandomNumberGenerator.new()

func _reseed(salt: String) -> void:
	_rng.seed = hash([seed_value, salt])

## A name for a new area not used in [param world] yet ("The Ashen Depths").
func random_name(world: MDSWorld = null) -> String:
	_reseed("name")
	var name := ""
	for i in 40:
		name = "The %s %s" % [_ADJECTIVES[_rng.randi() % _ADJECTIVES.size()], _NOUNS[_rng.randi() % _NOUNS.size()]]
		if not world or not world.has_area(name):
			return name
	return name + " %d" % _rng.randi_range(2, 99)

## A color for a new area, away from the colors [param world]'s areas have.
static func free_color(world: MDSWorld, salt := 0) -> Color:
	var used: Array[float] = []
	if world:
		for a in world.get_areas():
			used.append(world.get_area_color(a).h)
	var best_h := 0.0
	var best_d := -1.0
	for i in 24:
		var h := fposmod(float(i) / 24.0 + float(salt) * 0.137, 1.0)
		var d := 1.0
		for u in used:
			d = minf(d, minf(absf(h - u), 1.0 - absf(h - u)))
		if d > best_d:
			best_d = d
			best_h = h
	return Color.from_hsv(best_h, 0.55, 0.72)

## The base of the ids of an area's rooms: "The Ashen Depths" -> "Ashen_Depths_01".
static func room_base(area: String) -> String:
	var a := area.strip_edges()
	if a.to_lower().begins_with("the "):
		a = a.substr(4)
	a = a.strip_edges().replace(" ", "_")
	return (a if not a.is_empty() else "Room") + "_01"

# --- Shapes ------------------------------------------------------------------------------------

## The cells of the area's shape in a box of [param size] cells, from (0, 0): those its
## [method outline] covers.
func shape_cells(size: Vector2i) -> Dictionary:
	# A corridor curling back can close a pocket off: it is the area's too.
	return shape_cells_of(coverage(outline(size), Rect2i(Vector2i.ZERO, size.max(Vector2i.ONE))), size)

## The cells of a [method coverage] in a box of [param size]: its biggest piece, pockets
## filled.
static func shape_cells_of(cover: Dictionary, size: Vector2i) -> Dictionary:
	var cells: Dictionary = {}
	for c in cover:
		cells[c] = true
	cells = largest_component(cells)
	_fill_holes(cells, size.max(Vector2i.ONE))
	return cells

## The area's outline in a box of [param size] cells, in cells from (0, 0): one polygon inside
## the box with straight sides, curves and slants as the settings ask.
func outline(size: Vector2i) -> PackedVector2Array:
	_reseed("shape")
	size = size.max(Vector2i.ONE)
	var box := Rect2(Vector2.ZERO, Vector2(size))
	var parts: Array[PackedVector2Array] = []
	match shape:
		Shape.RECTANGLE:
			parts.append(MDSGeometry.rect_polygon(box))
		Shape.IRREGULAR:
			_blocks(parts, size, 2 + _rng.randi() % 3)
		Shape.FREEFORM:
			parts.append(_blob(size, 0.86))
			_tubes(parts, size)
		Shape.HYBRID:
			parts.append(_blob(size, 0.7))
			_blocks(parts, size, 1 + _rng.randi() % 2)
			_tubes(parts, size)
	var main := _largest(MDSGeometry.union_all(parts, INF))
	main = shape_corners(main)
	var inside := _largest(Geometry2D.intersect_polygons(main, MDSGeometry.rect_polygon(box)))
	return inside if inside.size() >= 3 else MDSGeometry.rect_polygon(Rect2(Vector2(size) / 4.0, (Vector2(size) / 2.0).max(Vector2.ONE)))

static func _largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for p: PackedVector2Array in polys:
		if p.size() < 3 or Geometry2D.is_polygon_clockwise(p):
			continue
		var a := absf(MDSGeometry.signed_area(p))
		if a > best_area:
			best_area = a
			best = p
	return best

## A curvy blob filling about [param reach] of the box: an outline wobbling around an ellipse.
## Where it bulges past the box it is cut straight.
func _blob(size: Vector2i, reach: float) -> PackedVector2Array:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.5
	noise.fractal_octaves = 2
	var half := Vector2(size) / 2.0
	var amp := 0.15 + 0.45 * roughness
	var poly := PackedVector2Array()
	var n := 96
	for i in n:
		var a := TAU * i / n
		var dir := Vector2(cos(a), sin(a))
		var r := clampf(reach * (1.0 + noise.get_noise_2d(dir.x * 1.7, dir.y * 1.7) * amp), 0.3, 1.2)
		poly.append(half + dir * half * r)
	return poly

## Rectangular blocks on the cell grid: a big one when there is nothing yet, then [param n]
## sticking out of the outline (halls, towers). [member slants] of them get a slanted side.
func _blocks(parts: Array[PackedVector2Array], size: Vector2i, n: int) -> void:
	if parts.is_empty():
		var w := clampi(roundi(size.x * _rng.randf_range(0.5, 0.75)), 1, size.x)
		var h := clampi(roundi(size.y * _rng.randf_range(0.5, 0.75)), 1, size.y)
		parts.append(_block(Rect2(Vector2(_rng.randi_range(0, size.x - w), _rng.randi_range(0, size.y - h)), Vector2(w, h))))
	for i in n:
		var main: PackedVector2Array = parts[0]
		var anchor: Vector2 = main[_rng.randi() % main.size()]
		var w := clampi(roundi(size.x * _rng.randf_range(0.2, 0.45)), mini(room_min.x, size.x), size.x)
		var h := clampi(roundi(size.y * _rng.randf_range(0.25, 0.6)), mini(room_min.y, size.y), size.y)
		var p := Vector2i(anchor.round()) - Vector2i(_rng.randi_range(0, w - 1), _rng.randi_range(0, h - 1))
		p = p.clamp(Vector2i.ZERO, size - Vector2i(w, h))
		parts.append(_block(Rect2(Vector2(p), Vector2(w, h))))

func _block(r: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if _rng.randf() < slants:
		# One side slanted: one of its corners moved in.
		var side := _rng.randi() % 4
		var k := _rng.randf_range(0.25, 0.6)
		var i := (side + (_rng.randi() % 2)) % 4
		match side:
			0:
				pts[i].y += r.size.y * k
			1:
				pts[i].x -= r.size.x * k
			2:
				pts[i].y -= r.size.y * k
			3:
				pts[i].x += r.size.x * k
	return pts

## Corridors leaving the outline: curving like pipes, or ([member slants]) running straight
## and turning at angles.
func _tubes(parts: Array[PackedVector2Array], size: Vector2i) -> void:
	var center := Vector2(size) / 2.0
	for t in tendrils:
		var main: PackedVector2Array = parts[0]
		var start: Vector2 = main[_rng.randi() % main.size()]
		var dir := (start - center).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var angular := _rng.randf() < slants / maxf(0.01, slants + curves)
		if angular:
			dir = Vector2.RIGHT.rotated(snappedf(dir.angle(), PI / 4.0))
		var path := PackedVector2Array([start - dir * 1.5, start])
		var at := start
		var steps := _rng.randi_range(2, maxi(3, maxi(size.x, size.y) / 4))
		for s in steps:
			if angular:
				if _rng.randf() < 0.4:
					dir = dir.rotated(PI / 4.0 * (1 if _rng.randf() < 0.5 else -1))
				at += dir * 2.0
			else:
				dir = dir.rotated(_rng.randf_range(-0.6, 0.6))
				at += dir * 1.5
			path.append(at)
		if not angular:
			path = _chaikin(path, 2)
		var width := _rng.randf_range(0.9, 1.4)
		var join := Geometry2D.JOIN_MITER if angular else Geometry2D.JOIN_ROUND
		var end := Geometry2D.END_SQUARE if angular else Geometry2D.END_ROUND
		for poly in Geometry2D.offset_polyline(path, width / 2.0, join, end):
			if not Geometry2D.is_polygon_clockwise(poly):
				parts.append(poly)

static func _chaikin(path: PackedVector2Array, passes: int) -> PackedVector2Array:
	for k in passes:
		var out := PackedVector2Array([path[0]])
		for i in path.size() - 1:
			out.append(path[i].lerp(path[i + 1], 0.25))
			out.append(path[i].lerp(path[i + 1], 0.75))
		out.append(path[path.size() - 1])
		path = out
	return path

## [param poly] with its sharp corners rounded into curves ([member curves]) or cut on a slant
## ([member slants]), by different amounts; the others stay sharp. Gentle bends (a blob's) are
## left alone.
func shape_corners(poly: PackedVector2Array) -> PackedVector2Array:
	if (curves <= 0.0 and slants <= 0.0) or poly.size() < 3:
		return poly
	poly = MDSGeometry.dedupe(poly)
	var n := poly.size()
	var treat := clampf(curves + slants, 0.0, 1.0)
	var slant_share := slants / maxf(0.0001, curves + slants)
	var out := PackedVector2Array()
	for i in n:
		var p0 := poly[(i - 1 + n) % n]
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var a := p0 - p1
		var b := p2 - p1
		var la := a.length()
		var lb := b.length()
		if la < 0.2 or lb < 0.2 or absf((p1 - p0).angle_to(p2 - p1)) < deg_to_rad(25.0) or _rng.randf() >= treat:
			out.append(p1)
			continue
		var most := 0.45 * minf(la, lb)
		var sa := minf(most, lerpf(0.5, most, _rng.randf()))
		var sb := minf(0.45 * lb, sa * _rng.randf_range(0.6, 1.6))
		sa = minf(sa, 0.45 * la)
		var qa := p1 + a / la * sa
		var qb := p1 + b / lb * sb
		if _rng.randf() < slant_share:
			out.append(qa)
			out.append(qb)
		else:
			for k in 9:
				var t := k / 8.0
				out.append(qa.lerp(p1, t).lerp(p1.lerp(qb, t), t))
	return out if MDSGeometry.is_simple(out) else poly

## How much of each cell of [param region] (cells) [param poly] (in cells) covers, 0 to 1:
## cell -> share, for the cells it covers more than [constant MIN_COVER] of.
static func coverage(poly: PackedVector2Array, region: Rect2i) -> Dictionary:
	var out: Dictionary = {}
	if poly.size() < 3:
		return out
	var b := MDSGeometry.bounds(poly)
	var lo := Vector2i(b.position.floor()).max(region.position)
	var hi := Vector2i(b.end.ceil()).min(region.end)
	# Cells the outline passes through are measured; the others are wholly in or out.
	var edge: Dictionary = {}
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var steps := maxi(1, ceili(p.distance_to(q) / 0.2))
		for k in steps + 1:
			var at := p.lerp(q, float(k) / steps)
			for o in [Vector2(0.02, 0.02), Vector2(-0.02, 0.02), Vector2(0.02, -0.02), Vector2(-0.02, -0.02)]:
				edge[Vector2i((at + o).floor())] = true
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var c := Vector2i(x, y)
			var share := 0.0
			if edge.has(c):
				for part in Geometry2D.intersect_polygons(MDSGeometry.rect_polygon(Rect2(Vector2(c), Vector2.ONE)), poly):
					share += MDSGeometry.signed_area(part) * (-1.0 if Geometry2D.is_polygon_clockwise(part) else 1.0)
				share = absf(share)
			elif Geometry2D.is_point_in_polygon(Vector2(c) + Vector2(0.5, 0.5), poly):
				share = 1.0
			if share > MIN_COVER:
				out[c] = minf(share, 1.0)
	return out

## The biggest 4-connected piece of [param cells].
static func largest_component(cells: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for part in components(cells):
		if part.size() > best.size():
			best = part
	return best

## The 4-connected pieces of [param cells], biggest first.
static func components(cells: Dictionary) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	var keys: Array = cells.keys()
	keys.sort()
	for start: Vector2i in keys:
		if seen.has(start):
			continue
		var part: Dictionary = {start: true}
		seen[start] = true
		var todo: Array[Vector2i] = [start]
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			for d in MDSAreaTools.DIRS:
				var n: Vector2i = c + d
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					part[n] = true
					todo.append(n)
		out.append(part)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.size() > b.size())
	return out

## Fills the holes of [param cells] in a box of [param size]: what the outside can't reach.
static func _fill_holes(cells: Dictionary, size: Vector2i) -> void:
	var outside: Dictionary = {}
	var todo: Array[Vector2i] = []
	for x in range(-1, size.x + 1):
		todo.append(Vector2i(x, -1))
		todo.append(Vector2i(x, size.y))
	for y in range(0, size.y):
		todo.append(Vector2i(-1, y))
		todo.append(Vector2i(size.x, y))
	for t in todo:
		outside[t] = true
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in MDSAreaTools.DIRS:
			var n: Vector2i = c + d
			if n.x < -1 or n.y < -1 or n.x > size.x or n.y > size.y or outside.has(n) or cells.has(n):
				continue
			outside[n] = true
			todo.append(n)
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not cells.has(c) and not outside.has(c):
				cells[c] = true

# --- Rooms -------------------------------------------------------------------------------------

## Splits [param cells] (one piece) into rooms: cell sets, each one piece. Rectangles of
## [member room_min] to [member room_max] cells and some shafts. Slivers (counting the
## [param cover] share of each cell the outline covers) join their neighbours, and
## [member irregularity] of the rooms join one to make L, T and U shapes.
func partition(cells: Dictionary, cover: Dictionary = {}) -> Array:
	_reseed("rooms")
	var free := cells.duplicate()
	var order: Array = cells.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var lo := room_min.max(Vector2i.ONE)
	var hi := room_max.max(lo)
	var rooms: Array = []
	for c: Vector2i in order:
		if not free.has(c):
			continue
		var want := Vector2i(_rng.randi_range(lo.x, hi.x), _rng.randi_range(lo.y, hi.y))
		if _rng.randf() < shafts:
			want = Vector2i(maxi(1, lo.x - 1), hi.y + 2)
		var w := 0
		while w < want.x and free.has(c + Vector2i(w, 0)):
			w += 1
		# Take in what is left of the row when it would be too narrow for a room of its own.
		var rest := 0
		while rest < lo.x and free.has(c + Vector2i(w + rest, 0)):
			rest += 1
		if rest > 0 and rest < lo.x and w + rest <= hi.x + lo.x:
			w += rest
		var h := 1
		while h < want.y:
			var row_free := true
			for i in w:
				if not free.has(c + Vector2i(i, h)):
					row_free = false
					break
			if not row_free:
				break
			h += 1
		var room: Dictionary = {}
		for y in h:
			for x in w:
				var k := c + Vector2i(x, y)
				room[k] = true
				free.erase(k)
		rooms.append(room)
	_merge_small(rooms, maxi(2, (lo.x * lo.y + 1) / 2), cover)
	_merge_irregular(rooms, hi.x * hi.y)
	return rooms

static func _weight(room: Dictionary, cover: Dictionary) -> float:
	if cover.is_empty():
		return float(room.size())
	var w := 0.0
	for c in room:
		w += float(cover.get(c, 1.0))
	return w

static func _owners(rooms: Array) -> Dictionary:
	var owner: Dictionary = {}
	for i in rooms.size():
		for c in rooms[i]:
			owner[c] = i
	return owner

## Neighbouring rooms: Vector2i(i, j) (i < j) -> the cell sides they share.
static func neighbours(rooms: Array) -> Dictionary:
	var owner := _owners(rooms)
	var out: Dictionary = {}
	for c: Vector2i in owner:
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if owner.has(n) and owner[n] != owner[c]:
				var key := Vector2i(mini(owner[c], owner[n]), maxi(owner[c], owner[n]))
				out[key] = out.get(key, 0) + 1
	return out

func _merge_small(rooms: Array, min_cells: int, cover: Dictionary = {}) -> void:
	var again := true
	while again:
		again = false
		var near := neighbours(rooms)
		for i in rooms.size():
			if rooms[i].is_empty() or _weight(rooms[i], cover) >= min_cells - 0.001:
				continue
			var best := -1
			var best_n := 0
			for key: Vector2i in near:
				if key.x != i and key.y != i:
					continue
				var j := key.y if key.x == i else key.x
				if rooms[j].is_empty():
					continue
				if near[key] > best_n or (near[key] == best_n and best >= 0 and rooms[j].size() < rooms[best].size()):
					best = j
					best_n = near[key]
			if best >= 0:
				rooms[best].merge(rooms[i])
				rooms[i] = {}
				again = true
				break
	_compact(rooms)

func _merge_irregular(rooms: Array, max_cells: int) -> void:
	if irregularity <= 0.0 or rooms.size() < 3:
		return
	var near := neighbours(rooms)
	var used: Dictionary = {}
	var order: Array = range(rooms.size())
	_shuffle(order)
	for i: int in order:
		if used.has(i) or _rng.randf() >= irregularity:
			continue
		var options: Array = []
		for key: Vector2i in near:
			if key.x != i and key.y != i:
				continue
			var j := key.y if key.x == i else key.x
			if not used.has(j) and rooms[i].size() + rooms[j].size() <= int(max_cells * 1.6):
				options.append(j)
		if options.is_empty():
			continue
		var j: int = options[_rng.randi() % options.size()]
		rooms[i].merge(rooms[j])
		rooms[j] = {}
		used[i] = true
		used[j] = true
	_compact(rooms)

static func _compact(rooms: Array) -> void:
	for i in range(rooms.size() - 1, -1, -1):
		if rooms[i].is_empty():
			rooms.remove_at(i)

func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t

## The room pairs that get a door, as Vector2i(i, j): a random tree over the neighbours (each
## room can be reached), and [member loops] of the other neighbour pairs.
func doors(rooms: Array) -> Array:
	_reseed("doors")
	var pairs: Array = neighbours(rooms).keys()
	pairs.sort()
	_shuffle(pairs)
	var parent: Array = range(rooms.size())
	var out: Array = []
	var extra: Array = []
	for p: Vector2i in pairs:
		var a := _find(parent, p.x)
		var b := _find(parent, p.y)
		if a != b:
			parent[a] = b
			out.append(p)
		else:
			extra.append(p)
	for p in extra:
		if _rng.randf() < loops:
			out.append(p)
	return out

static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

## What [method generate] would make in a box of [param size] cells with [param taken] cells
## (box-local, cell -> anything) left out, in cells from the box's corner: {outline, cells,
## rooms (cell sets), shapes (each room's outline polygons), doors ([cell, dir])}. For previews.
func preview(size: Vector2i, taken: Dictionary = {}) -> Dictionary:
	var poly := outline(size)
	var cover := coverage(poly, Rect2i(Vector2i.ZERO, size.max(Vector2i.ONE)))
	var cells: Dictionary = {}
	for c in shape_cells_of(cover, size):
		if not taken.has(c):
			cells[c] = true
	cells = largest_component(cells)
	var rooms := partition(cells, cover) if not cells.is_empty() else []
	var shapes: Array = []
	for r: Dictionary in rooms:
		shapes.append(room_outline(r, poly, Vector2.ONE))
	var list: Array = []
	for p: Vector2i in doors(rooms):
		var d := MDSAreaTools.door_between(rooms[p.x], rooms[p.y], func(c: Vector2i) -> float: return cover.get(c, 0.0))
		if not d.is_empty():
			list.append([d.cell, d.dir])
	return {"outline": poly, "cells": cells, "rooms": rooms, "shapes": shapes, "doors": list}

## The part of [param poly] that cells [param cells] hold, as polygons: [param cell_size] px
## per cell (poly in the same px).
static func room_outline(cells: Dictionary, poly: PackedVector2Array, cell_size: Vector2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for piece in MDSGeometry.union_rects(MDSGeometry.cells_to_rects(cells, cell_size), INF):
		for part in Geometry2D.intersect_polygons(piece, poly):
			if not Geometry2D.is_polygon_clockwise(part) and absf(MDSGeometry.signed_area(part)) > cell_size.x * cell_size.y * 0.002:
				out.append(part)
	return out

# --- In the world ------------------------------------------------------------------------------

## Generates an area in [param box] (paint cells) on [param layer], leaving out cells other
## rooms cover. [param area] is made when it doesn't exist yet ([param color], or a color of
## its own). Returns {area, rooms (ids), doors}; no rooms when the box is full.
func generate(world: MDSWorld, box: Rect2i, layer: int, area: String, color := Color.TRANSPARENT) -> Dictionary:
	var poly := outline(box.size)
	var taken := MDSAreaTools.occupied(world, layer)
	var cover: Dictionary = {}
	var cells: Dictionary = {}
	var local_cover := coverage(poly, Rect2i(Vector2i.ZERO, box.size.max(Vector2i.ONE)))
	for c: Vector2i in shape_cells_of(local_cover, box.size):
		var at := c + box.position
		cover[at] = local_cover.get(c, 0.0)
		if not taken.has(at):
			cells[at] = true
	cells = largest_component(cells)
	last_doors = 0
	if cells.is_empty():
		var none: Array[String] = []
		return {"area": area, "rooms": none, "doors": 0}
	if not area.is_empty() and not world.has_area(area):
		world.add_area(area, color if color.a > 0 else free_color(world, seed_value))
	var s := world.get_paint_cell()
	var world_poly := PackedVector2Array()
	for p in poly:
		world_poly.append((p + Vector2(box.position)) * s)
	var ids := build_rooms(world, cells, layer, area, world_poly, cover)
	return {"area": area, "rooms": ids, "doors": last_doors}

## Makes rooms of painted [param cells] (paint cells; ones other rooms cover are left out) in
## [param area] on [param layer], with doors between them; each piece also gets a door to a
## room of [param area] it touches. The pieces' corners are rounded and slanted like a
## generated area's ([member curves], [member slants]).
func fill(world: MDSWorld, cells: Dictionary, layer: int, area: String) -> Array[String]:
	var taken := MDSAreaTools.occupied(world, layer)
	var free: Dictionary = {}
	for c in cells:
		if not taken.has(c):
			free[c] = true
	var before: Array[String] = []
	if not area.is_empty():
		before = world.get_area_rooms(area)
	last_doors = 0
	var ids: Array[String] = []
	var s := world.get_paint_cell()
	for part in components(free):
		_reseed("shape")
		var poly := shape_corners(_largest(MDSGeometry.union_rects(MDSGeometry.cells_to_rects(part, Vector2.ONE), INF)))
		var cover: Dictionary = {}
		var kept: Dictionary = {}
		var lo := Vector2i(2147483647, 2147483647)
		var hi := -lo
		for c: Vector2i in part:
			lo = lo.min(c)
			hi = hi.max(c)
		var measured := coverage(poly, Rect2i(lo, hi - lo + Vector2i.ONE))
		for c in part:
			if measured.has(c):
				cover[c] = measured[c]
				kept[c] = true
		kept = largest_component(kept)
		if kept.is_empty():
			continue
		var world_poly := PackedVector2Array()
		for p in poly:
			world_poly.append(p * s)
		var made := build_rooms(world, kept, layer, area, world_poly, cover)
		ids.append_array(made)
		if area.is_empty() or before.is_empty():
			continue
		# Join the piece to the area it was painted onto.
		var mine := MDSAreaTools.cells_of(world, made)
		var old: Dictionary = {}
		for id in before:
			if world.get_room_layer(id) == layer:
				for c in world.get_room_cells(id):
					old[c] = id
		var counts := MDSAreaTools.contacts(mine, old)
		var best: Array = []
		for pair in counts:
			if best.is_empty() or counts[pair] > counts[best]:
				best = pair
		if not best.is_empty() and not MDSAreaTools.add_door(world, best[0], best[1]).is_empty():
			last_doors += 1
	return ids

## Makes rooms of [param cells] (free paint cells, one piece) with doors between them. With
## [param outline] (world px), each room keeps the part of it it holds as its outline on the map;
## [param cover] (cell -> share of it the outline covers) steers slivers and doors.
func build_rooms(world: MDSWorld, cells: Dictionary, layer: int, area: String, outline_px := PackedVector2Array(), cover: Dictionary = {}) -> Array[String]:
	var rooms := partition(cells, cover)
	var ids: Array[String] = []
	var s := world.get_paint_cell()
	for r: Dictionary in rooms:
		var lo := Vector2i(2147483647, 2147483647)
		var hi := -lo
		for c: Vector2i in r:
			lo = lo.min(c)
			hi = hi.max(c)
		var id := world.add_room(room_base(area), Rect2(Vector2(lo) * s, Vector2(hi - lo + Vector2i.ONE) * s), layer, area)
		world.set_room_cells(id, r)
		if outline_px.size() >= 3 and _weight(r, cover) < r.size() - 0.001:
			world.set_room_shape(id, room_outline(r, outline_px, s))
		ids.append(id)
	var share := func(c: Vector2i) -> float: return cover.get(c, 1.0)
	for p: Vector2i in doors(rooms):
		if not MDSAreaTools.add_door(world, ids[p.x], ids[p.y], false, rooms[p.x], rooms[p.y], share).is_empty():
			last_doors += 1
	return ids
