@tool
class_name MDSRoomSketches
extends RefCounted
## Room outlines drawn at their actual size in the Full view (a rectangle, an ellipse, a
## polygon or a curvy freehand shape) before they are rooms on the map, and [method generate],
## which makes them rooms. The paint cells an outline covers become one room ([constant ROOM]),
## or are split into rooms like a generated area ([constant ROOMS], see [MDSAreaGenerator]).
## Each room keeps the part of the outline it holds as its outline on the map, so curves and
## slants show while its rectangles stay on the paint grid. Rooms made from one outline get
## doors between them, and each outline one door to every room or area it touches. Outlines of
## the same kind and area that overlap are one.
##
## The outlines are kept in the world ([code]"sketches": [{layer, kind, area, draw, points}][/code],
## points as flat world px), so they are saved with it and Ctrl+Z on the map takes them back like
## any other change. Plain data, no editor needed:
## [codeblock]
## world.checkpoint()
## MDSRoomSketches.add(world, 0, MDSRoomSketches.ellipse(Vector2.ZERO, Vector2(1440, 810)), MDSRoomSketches.ROOMS, MDSRoomSketches.NEW_AREA)
## var made := MDSRoomSketches.new().generate(world, 0)   # {rooms, areas, doors, outlines, left}
## [/codeblock]

## One room per outline.
const ROOM := "room"
## The outline split into rooms, with doors between them.
const ROOMS := "rooms"
## The area of an outline: a new one, shared by the outlines with it that touch.
const NEW_AREA := "+"

enum Draw { RECTANGLE, ELLIPSE, POLYGON, CURVY }
const DRAW_IDS: PackedStringArray = ["rectangle", "ellipse", "polygon", "curvy"]

## Rooms of a [constant ROOMS] outline: smallest and largest (paint cells).
var room_min := Vector2i(2, 2)
var room_max := Vector2i(4, 3)
## Share of those rooms joined into L, T and U shapes.
var irregularity := 0.35
## Share of the other neighbour pairs that get a door too (loops).
var loops := 0.2
var seed_value := 0
## Doors from what is made to the rooms it touches: one to each room or area.
var link_touching := true
## A paint cell is an outline's when the outline covers more than this share of it (as a
## generated area's, so the rooms' outlines follow what was drawn).
var min_cover := MDSAreaGenerator.MIN_COVER

# --- Outlines in the world ---------------------------------------------------------------------

## Every outline of [param world] (the list itself: change it only through these functions).
static func get_all(world: MDSWorld) -> Array:
	if not world.data.has("sketches") or not world.data.sketches is Array:
		world.data.sketches = []
	return world.data.sketches

## The indices of the outlines on [param layer], in the order they were drawn.
static func on_layer(world: MDSWorld, layer: int) -> Array[int]:
	var out: Array[int] = []
	var all := get_all(world)
	for i in all.size():
		if int(all[i].get("layer", 0)) == layer:
			out.append(i)
	return out

static func count(world: MDSWorld, layer: int) -> int:
	return on_layer(world, layer).size()

## Adds outline [param poly] (world px) on [param layer]: [param kind] [constant ROOM] or
## [constant ROOMS], [param area] an area's name, [constant NEW_AREA] or "" (none),
## [param draw] how it was drawn ([constant DRAW_IDS]). No checkpoint: the caller takes one.
## Returns its index, or -1 when [param poly] is no outline.
static func add(world: MDSWorld, layer: int, poly: PackedVector2Array, kind := ROOM, area := NEW_AREA, draw := "polygon") -> int:
	var clean := MDSGeometry.dedupe(poly, 0.5)
	if clean.size() < 3 or absf(MDSGeometry.signed_area(clean)) < 16.0:
		return -1
	var flat: Array = []
	for p in clean:
		flat.append(snappedf(p.x, 0.1))
		flat.append(snappedf(p.y, 0.1))
	get_all(world).append({"layer": layer, "kind": kind if kind in [ROOM, ROOMS] else ROOM, "area": area, "draw": draw, "points": flat})
	world._touch()
	return get_all(world).size() - 1

## The outline of sketch [param index] (world px).
static func polygon(world: MDSWorld, index: int) -> PackedVector2Array:
	var all := get_all(world)
	if index < 0 or index >= all.size():
		return PackedVector2Array()
	return polygon_of(all[index])

static func polygon_of(sketch: Dictionary) -> PackedVector2Array:
	var flat: Array = sketch.get("points", [])
	var poly := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		poly.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return poly

static func get_sketch(world: MDSWorld, index: int) -> Dictionary:
	var all := get_all(world)
	return all[index] if index >= 0 and index < all.size() else {}

## Sets what sketch [param index] makes: [param key] "kind" or "area".
static func set_value(world: MDSWorld, index: int, key: String, value: Variant) -> void:
	var all := get_all(world)
	if index >= 0 and index < all.size():
		all[index][key] = value
		world._touch()

## Removes the sketches [param indices].
static func remove(world: MDSWorld, indices: Array) -> void:
	var all := get_all(world)
	var sorted := indices.duplicate()
	sorted.sort()
	for k in range(sorted.size() - 1, -1, -1):
		var i := int(sorted[k])
		if i >= 0 and i < all.size():
			all.remove_at(i)
	world._touch()

## Removes the outlines of [param layer]. Returns how many there were.
static func clear_layer(world: MDSWorld, layer: int) -> int:
	var mine := on_layer(world, layer)
	remove(world, mine)
	return mine.size()

## Moves the sketches [param indices] by [param delta] world px from [param start] (index ->
## its points when the move began; their points now when empty).
static func move(world: MDSWorld, indices: Array, delta: Vector2, start: Dictionary = {}) -> void:
	var all := get_all(world)
	for v in indices:
		var i := int(v)
		if i < 0 or i >= all.size():
			continue
		var from: Array = start.get(i, all[i].points)
		var moved: Array = []
		for k in from.size():
			moved.append(snappedf(float(from[k]) + (delta.x if k % 2 == 0 else delta.y), 0.1))
		all[i].points = moved
	world._touch()

## The topmost sketch on [param layer] whose outline holds [param world_pos], or -1.
static func at(world: MDSWorld, world_pos: Vector2, layer: int) -> int:
	var mine := on_layer(world, layer)
	for k in range(mine.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(world_pos, polygon(world, mine[k])):
			return mine[k]
	return -1

## The sketches on [param layer] inside [param box] (world px), or touching it with
## [param touching].
static func in_box(world: MDSWorld, box: Rect2, layer: int, touching := false) -> Array[int]:
	var out: Array[int] = []
	for i in on_layer(world, layer):
		var b := MDSGeometry.bounds(polygon(world, i))
		if box.encloses(b) or (touching and box.intersects(b)):
			out.append(i)
	return out

# --- Shapes ------------------------------------------------------------------------------------

## The rectangle with corners [param a] and [param b].
static func rectangle(a: Vector2, b: Vector2) -> PackedVector2Array:
	return MDSGeometry.rect_polygon(Rect2(a, b - a).abs())

## The ellipse in the box with corners [param a] and [param b], of [param segments] sides.
static func ellipse(a: Vector2, b: Vector2, segments := 64) -> PackedVector2Array:
	var box := Rect2(a, b - a).abs()
	var half := box.size / 2.0
	var poly := PackedVector2Array()
	for i in segments:
		var t := TAU * i / segments
		poly.append(box.get_center() + Vector2(cos(t), sin(t)) * half)
	return poly

## A curvy closed outline from a freehand stroke [param points]: simplified, then smoothed
## (corner cutting, [param passes] times), untwisted where the stroke crossed itself (its
## biggest part).
static func freehand(points: PackedVector2Array, passes := 3, tolerance := 4.0) -> PackedVector2Array:
	var pts := MDSGeometry.dedupe(points, 1.0)
	if pts.size() < 3:
		return PackedVector2Array()
	pts = MDSGeometry.simplify_closed(pts, tolerance)
	for k in passes:
		var out := PackedVector2Array()
		for i in pts.size():
			var p := pts[i]
			var q := pts[(i + 1) % pts.size()]
			out.append(p.lerp(q, 0.25))
			out.append(p.lerp(q, 0.75))
		pts = out
	return closed(pts)

## [param points] as one simple closed outline: repeated points dropped, a twisted one untied
## (its biggest part), counter-clockwise on screen.
static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for part in MDSGeometry.untwist(points, 16.0):
		var a := absf(MDSGeometry.signed_area(part))
		if a > best_area:
			best_area = a
			best = part
	if best.size() >= 3 and Geometry2D.is_polygon_clockwise(best):
		best.reverse()
	return best

## [param p] at the nearest corner of the paint cells.
static func snap_to_cells(world: MDSWorld, p: Vector2) -> Vector2:
	var s := world.get_paint_cell()
	return (p / s).round() * s

# --- Cells -------------------------------------------------------------------------------------

## The paint cells outline [param poly] (world px) covers more than [member min_cover] of:
## {cells: cell -> true, cover: cell -> share}.
func cells_of(world: MDSWorld, poly: PackedVector2Array) -> Dictionary:
	var s := world.get_paint_cell()
	var in_cells := PackedVector2Array()
	for p in poly:
		in_cells.append(p / s)
	var b := MDSGeometry.bounds(in_cells)
	var region := Rect2i(Vector2i(b.position.floor()), Vector2i(b.end.ceil()) - Vector2i(b.position.floor()))
	var cover := MDSAreaGenerator.coverage(in_cells, region)
	var cells: Dictionary = {}
	for c in cover.keys():
		if float(cover[c]) > min_cover:
			cells[c] = true
		else:
			cover.erase(c)
	return {"cells": cells, "cover": cover}

## The outlines [method generate] makes rooms of on [param layer] ([param indices]: those
## sketches only; every one when empty): those of the same kind and area that overlap joined,
## in the order they were drawn. [{kind, area, polygon (world px), sketches: indices}].
func outlines(world: MDSWorld, layer: int, indices: Array = []) -> Array:
	var picked: Array[int] = []
	for i in on_layer(world, layer):
		if indices.is_empty() or indices.has(i):
			picked.append(i)
	var out: Array = []
	for i in picked:
		var sketch := get_sketch(world, i)
		var poly := closed(polygon_of(sketch))
		if poly.size() < 3:
			continue
		var kind := str(sketch.get("kind", ROOM))
		var area := str(sketch.get("area", NEW_AREA))
		var joined := {"kind": kind, "area": area, "polygon": poly, "sketches": [i]}
		# Joined with the ones drawn before it that it overlaps, and those with each other.
		var again := true
		while again:
			again = false
			for k in range(out.size() - 1, -1, -1):
				var o: Dictionary = out[k]
				if o.kind != kind or o.area != area or not _overlap(o.polygon, joined.polygon):
					continue
				var merged := Geometry2D.merge_polygons(o.polygon, joined.polygon)
				var outer := MDSGeometry.outer_of(merged)
				if outer < 0:
					continue
				joined.polygon = merged[outer]
				joined.sketches = o.sketches + joined.sketches
				out.remove_at(k)
				again = true
		out.append(joined)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.sketches.min()) < int(b.sketches.min()))
	return out

## Whether [param a] and [param b] share more than a sliver (touching edges only: no).
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if not MDSGeometry.bounds(a).intersects(MDSGeometry.bounds(b)):
		return false
	var shared := 0.0
	for part in Geometry2D.intersect_polygons(a, b):
		shared += absf(MDSGeometry.signed_area(part))
	return shared > minf(absf(MDSGeometry.signed_area(a)), absf(MDSGeometry.signed_area(b))) * 0.01

## What [method generate] would make on [param layer]: for each outline, the paint cells it
## would take (cells other rooms have left out). [{kind, area, polygon, cells, sketches}].
func preview(world: MDSWorld, layer: int, indices: Array = []) -> Array:
	var taken := MDSAreaTools.occupied(world, layer)
	var out: Array = []
	for o: Dictionary in outlines(world, layer, indices):
		var got := cells_of(world, o.polygon)
		var free: Dictionary = {}
		for c in got.cells:
			if not taken.has(c):
				free[c] = true
				taken[c] = "?"
		var entry := o.duplicate()
		entry.cells = free
		out.append(entry)
	return out

# --- Making rooms ------------------------------------------------------------------------------

## Makes rooms of the outlines on [param layer] ([param indices]: those sketches only; every one
## when empty), then removes those sketches. Cells other rooms have are left out; an outline cut
## in pieces by them makes rooms of each piece. Areas named that don't exist yet are made;
## [constant NEW_AREA] outlines that touch share one new area. No checkpoint: the caller takes
## one. Returns {rooms: ids, areas: new areas, doors, outlines: how many made rooms, left:
## outlines with no free cell}.
func generate(world: MDSWorld, layer: int, indices: Array = []) -> Dictionary:
	var list := outlines(world, layer, indices)
	var used: Array = []
	for o: Dictionary in list:
		used.append_array(o.sketches)
	var s := world.get_paint_cell()
	var taken := MDSAreaTools.occupied(world, layer)
	# The free cells of each outline first: new areas are shared by the outlines that touch.
	var parts: Array = []
	for o: Dictionary in list:
		var got := cells_of(world, o.polygon)
		var free: Dictionary = {}
		for c in got.cells:
			if not taken.has(c):
				free[c] = true
				taken[c] = "?"
		parts.append({"outline": o, "cells": free, "cover": got.cover})
	var new_areas := _new_areas(world, parts)
	var made: Array[String] = []
	var group_of: Dictionary = {} # room id -> group key
	var doors := 0
	var outlines_made := 0
	var left := 0
	var gen := MDSAreaGenerator.new()
	gen.room_min = room_min
	gen.room_max = room_max.max(room_min)
	gen.irregularity = irregularity
	gen.loops = loops
	for k in parts.size():
		var part: Dictionary = parts[k]
		var o: Dictionary = part.outline
		if part.cells.is_empty():
			left += 1
			continue
		var area := str(new_areas.get(k, o.area))
		if area == NEW_AREA:
			area = ""
		if not area.is_empty() and not world.has_area(area):
			world.add_area(area, MDSAreaGenerator.free_color(world, world.get_areas().size()))
		var ids: Array[String] = []
		var n := 0
		for piece: Dictionary in MDSAreaGenerator.components(part.cells):
			if o.kind == ROOMS:
				gen.seed_value = hash([seed_value, k, n])
				ids.append_array(gen.build_rooms(world, piece, layer, area, o.polygon, part.cover))
				doors += gen.last_doors
			else:
				ids.append(_one_room(world, piece, part.cover, o.polygon, layer, area, s))
			n += 1
		for id in ids:
			group_of[id] = "sketch%d" % k
		made.append_array(ids)
		outlines_made += 1
	if link_touching and not made.is_empty():
		doors += _link(world, made, group_of, layer)
	remove(world, used)
	var areas: Array[String] = []
	for k in new_areas:
		if not areas.has(new_areas[k]):
			areas.append(new_areas[k])
	return {"rooms": made, "areas": areas, "doors": doors, "outlines": outlines_made, "left": left}

## One room of [param cells] (one piece), keeping the part of [param poly] it holds as its outline
## on the map when the outline doesn't cover it all.
static func _one_room(world: MDSWorld, cells: Dictionary, cover: Dictionary, poly: PackedVector2Array, layer: int, area: String, s: Vector2) -> String:
	var lo := Vector2i(2147483647, 2147483647)
	var hi := -lo
	var weight := 0.0
	for c: Vector2i in cells:
		lo = lo.min(c)
		hi = hi.max(c)
		weight += float(cover.get(c, 1.0))
	var base := MDSAreaGenerator.room_base(area) if not area.is_empty() else "Room_01"
	var id := world.add_room(base, Rect2(Vector2(lo) * s, Vector2(hi - lo + Vector2i.ONE) * s), layer, area)
	world.set_room_cells(id, cells)
	if weight < cells.size() - 0.001:
		world.set_room_shape(id, MDSAreaGenerator.room_outline(cells, poly, s))
	return id

## The new areas of [param parts] whose outline asks for one: the ones that touch share it.
## Part index -> area name.
func _new_areas(world: MDSWorld, parts: Array) -> Dictionary:
	var wanting: Array[int] = []
	for k in parts.size():
		if str(parts[k].outline.area) == NEW_AREA and not (parts[k].cells as Dictionary).is_empty():
			wanting.append(k)
	var parent: Dictionary = {}
	for k in wanting:
		parent[k] = k
	var owner: Dictionary = {}
	for k in wanting:
		for c in parts[k].cells:
			owner[c] = k
	for k in wanting:
		for c: Vector2i in parts[k].cells:
			for d in MDSAreaTools.DIRS:
				var other: Variant = owner.get(c + d)
				if other != null and int(other) != k:
					var a := _root(parent, k)
					var b := _root(parent, int(other))
					if a != b:
						parent[a] = b
	var names: Dictionary = {}
	var out: Dictionary = {}
	var gen := MDSAreaGenerator.new()
	for k in wanting:
		var r := _root(parent, k)
		if not names.has(r):
			gen.seed_value = hash([seed_value, "area", names.size(), world.get_areas().size()])
			var area_name := gen.random_name(world)
			names[r] = area_name
			world.add_area(area_name, MDSAreaGenerator.free_color(world, world.get_areas().size()))
		out[k] = names[r]
	return out

static func _root(parent: Dictionary, k: int) -> int:
	while int(parent[k]) != k:
		parent[k] = parent[parent[k]]
		k = int(parent[k])
	return k

## Doors from the rooms [param made] (room -> its outline, [param group_of]) to what they touch:
## for each outline, one to every other outline and to every room or area already there, between
## the two rooms sharing the most. Returns how many.
static func _link(world: MDSWorld, made: Array[String], group_of: Dictionary, layer: int) -> int:
	var own := MDSAreaTools.cells_of(world, made)
	var all := MDSAreaTools.occupied(world, layer)
	var group := func(id: String) -> String: return str(group_of[id]) if group_of.has(id) else MDSAreaTools.group_of(world, id)
	var best: Dictionary = {} # "group|other group" -> [pair, count]
	var counts := MDSAreaTools.contacts(own, all)
	for pair: Array in counts:
		var ga: String = group.call(pair[0])
		var gb: String = group.call(pair[1])
		if ga == gb:
			continue
		var key := ga + "|" + gb if ga < gb else gb + "|" + ga
		if not best.has(key) or counts[pair] > best[key][1]:
			best[key] = [pair, counts[pair]]
	var n := 0
	var keys: Array = best.keys()
	keys.sort()
	for key in keys:
		var pair: Array = best[key][0]
		if MDSAreaTools.rooms_connected(world, pair[0], pair[1]):
			continue
		if not MDSAreaTools.add_door(world, pair[0], pair[1]).is_empty():
			n += 1
	return n
