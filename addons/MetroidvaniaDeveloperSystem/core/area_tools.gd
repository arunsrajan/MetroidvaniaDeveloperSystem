@tool
class_name MDSAreaTools
extends RefCounted
## Areas of the world map handled as one piece: their cells and outline on the paint grid,
## moving one (it slides up to its neighbours, never over them), and the doors (connected
## gate pairs) made where rooms touch: between the rooms of an area, and between two areas
## that come to touch ([constant AUTO_LINK] doors, taken out again when they part).
##
## A "group" is an area's name, or [code]#room_id[/code] for a room that is in no area.

## Gate key marking a door made because two areas touched (see [method link_touching]).
const AUTO_LINK := "auto_link"
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const SIDE_OF := {Vector2i.RIGHT: "right", Vector2i.LEFT: "left", Vector2i.DOWN: "bot", Vector2i.UP: "top"}

## The group of room [param id]: its area, else [code]#id[/code].
static func group_of(world: MDSWorld, id: String) -> String:
	var a := world.get_room_area(id)
	return a if not a.is_empty() else "#" + id

## The rooms of [param group] on [param layer].
static func group_rooms(world: MDSWorld, group: String, layer: int) -> Array[String]:
	var out: Array[String] = []
	if group.is_empty():
		return out
	if group.begins_with("#"):
		var id := group.substr(1)
		if world.has_room(id) and world.get_room_layer(id) == layer:
			out.append(id)
		return out
	for id in world.get_area_rooms(group):
		if world.get_room_layer(id) == layer:
			out.append(id)
	return out

## A display name for [param group].
static func group_name(group: String) -> String:
	return "room " + group.substr(1) if group.begins_with("#") else group

## The paint cells of rooms [param ids]: cell -> room id.
static func cells_of(world: MDSWorld, ids: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for id in ids:
		for c in world.get_room_cells(id):
			out[c] = id
	return out

## The paint cells of every room on [param layer] but [param except]: cell -> room id.
static func occupied(world: MDSWorld, layer: int, except: Array[String] = []) -> Dictionary:
	var out: Dictionary = {}
	for id in world.get_room_ids():
		if world.get_room_layer(id) == layer and not except.has(id):
			for c in world.get_room_cells(id):
				out[c] = id
	return out

static func bounds_of(world: MDSWorld, ids: Array[String]) -> Rect2:
	var b := Rect2()
	for i in ids.size():
		b = world.get_room_bounds(ids[i]) if i == 0 else b.merge(world.get_room_bounds(ids[i]))
	return b

# --- Moving ----------------------------------------------------------------------------------

## Whether [param own] cells moved by [param delta] cells land on none of [param taken].
static func fits(own: Dictionary, delta: Vector2i, taken: Dictionary) -> bool:
	for c in own:
		if taken.has(c + delta):
			return false
	return true

## How far [param own] cells get moving from [param from] to [param to] (cell offsets) without
## landing on [param taken]. They move a cell at a time, so they never pass through others:
## they stop where they meet them, and slide along them when only one axis is blocked.
static func slide(own: Dictionary, taken: Dictionary, from: Vector2i, to: Vector2i) -> Vector2i:
	var at := from
	var guard := absi(to.x - from.x) + absi(to.y - from.y) + 2
	while at != to and guard > 0:
		guard -= 1
		var r := to - at
		var sx := Vector2i(signi(r.x), 0)
		var sy := Vector2i(0, signi(r.y))
		# The axis with further to go first: close to a straight line.
		var tries: Array[Vector2i] = [sx, sy]
		if absi(r.x) < absi(r.y):
			tries.reverse()
		var moved := false
		for t in tries:
			if t != Vector2i.ZERO and fits(own, at + t, taken):
				at += t
				moved = true
				break
		if not moved:
			break
	return at

## Places rooms [param ids] at their [param start_origins] (id -> Vector2) moved by
## [param delta] world px; an area's own label goes along ([param start_labels]: area ->
## Vector2, Vector2.INF when placed automatically).
static func place(world: MDSWorld, ids: Array[String], start_origins: Dictionary, delta: Vector2, start_labels: Dictionary = {}) -> void:
	for id in ids:
		if world.has_room(id) and start_origins.has(id):
			var want: Vector2 = start_origins[id] + delta
			if world.get_origin(id) != want:
				world.set_origin(id, want)
	for a in start_labels:
		if start_labels[a] != Vector2.INF and world.has_area(a):
			var p: Vector2 = start_labels[a] + delta
			world.set_area_value(a, "label_pos", [p.x, p.y])

# --- Doors -------------------------------------------------------------------------------------

## Where a door between cell sets [param a] and [param b] goes: {cell (in a), dir (towards
## b)}. Cells the room outlines cover well come first ([param cover]: cell -> share, 0 to 1;
## all of it without). Then a side door on the lowest row they share, like a corridor's floor,
## else a door in the middle of a floor or ceiling they share. Empty when they don't touch.
static func door_between(a: Dictionary, b: Dictionary, cover := Callable()) -> Dictionary:
	var side: Array = [[], [], []]
	var vertical: Array = [[], [], []]
	for c: Vector2i in a:
		for d in DIRS:
			if b.has(c + d):
				var share := minf(float(cover.call(c)), float(cover.call(c + d))) if cover.is_valid() else 1.0
				var tier := 2 if share >= 0.85 else (1 if share >= 0.4 else 0)
				(side if d.x != 0 else vertical)[tier].append([c, d])
	for tier in [2, 1, 0]:
		var list: Array = side[tier]
		if not list.is_empty():
			list.sort_custom(func(p: Array, q: Array) -> bool: return p[0].y > q[0].y or (p[0].y == q[0].y and p[0].x < q[0].x))
			return {"cell": list[0][0], "dir": list[0][1]}
		list = vertical[tier]
		if not list.is_empty():
			list.sort_custom(func(p: Array, q: Array) -> bool: return p[0].x < q[0].x or (p[0].x == q[0].x and p[0].y < q[0].y))
			var m: Array = list[list.size() / 2]
			return {"cell": m[0], "dir": m[1]}
	return {}

## Adds a connected gate pair between rooms [param a] and [param b] where their cells touch
## ([param a_cells], [param b_cells]; the rooms' own when empty), on the part of the side both
## rooms' outlines on the map reach. Returns [gate of a, gate of b], or [] when they don't touch.
static func add_door(world: MDSWorld, a: String, b: String, auto_link := false, a_cells: Dictionary = {}, b_cells: Dictionary = {}, cover := Callable()) -> Array:
	var ca := a_cells if not a_cells.is_empty() else world.get_room_cells(a)
	var cb := b_cells if not b_cells.is_empty() else world.get_room_cells(b)
	var share := cover
	if not share.is_valid() and (world.has_room_shape(a) or world.has_room_shape(b)):
		share = func(c: Vector2i) -> float: return shape_cover(world, a if ca.has(c) else b, c)
	var d := door_between(ca, cb, share)
	if d.is_empty():
		return []
	var s := world.get_paint_cell()
	var dir: Vector2i = d.dir
	var mid := (Vector2(d.cell) + Vector2(0.5, 0.5)) * s + Vector2(dir) * s * 0.5
	var half := Vector2(absf(dir.y), absf(dir.x)) * s * 0.5
	var pos := _inside_point(world, a, b, mid - half, mid + half, Vector2(dir))
	var ga := world.add_gate(a, pos, SIDE_OF[dir], "", false)
	var gb := world.add_gate(b, pos, SIDE_OF[-dir], "", false)
	world.connect_gates(a, ga, b, gb)
	if auto_link:
		world.set_gate_value(a, ga, AUTO_LINK, true)
		world.set_gate_value(b, gb, AUTO_LINK, true)
	return [ga, gb]

## How much of [param cell] room [param id]'s outline on the map covers, 0 to 1 (1 without one).
static func shape_cover(world: MDSWorld, id: String, cell: Vector2i) -> float:
	if not world.has_room_shape(id):
		return 1.0
	var r := world.cell_to_world_rect(cell)
	var area := 0.0
	for poly in world.get_room_shape(id):
		for part in Geometry2D.intersect_polygons(MDSGeometry.rect_polygon(r), poly):
			area += absf(MDSGeometry.signed_area(part)) * (-1.0 if Geometry2D.is_polygon_clockwise(part) else 1.0)
	return clampf(absf(area) / maxf(1.0, r.get_area()), 0.0, 1.0)

## The middle of the part of the side [param e0]-[param e1] both rooms' outlines reach (its
## middle when one of them has no part of it).
static func _inside_point(world: MDSWorld, a: String, b: String, e0: Vector2, e1: Vector2, dir: Vector2) -> Vector2:
	if not world.has_room_shape(a) and not world.has_room_shape(b):
		return e0.lerp(e1, 0.5)
	var spans := _spans(world, a, e0 - dir, e1 - dir)
	var other := _spans(world, b, e0 + dir, e1 + dir)
	var best := Vector2(-1, -1)
	for p: Vector2 in spans:
		for q: Vector2 in other:
			var lo := maxf(p.x, q.x)
			var hi := minf(p.y, q.y)
			if hi - lo > best.y - best.x:
				best = Vector2(lo, hi)
	if best.y - best.x <= 0.02:
		return e0.lerp(e1, 0.5)
	return e0.lerp(e1, (best.x + best.y) / 2.0)

## The parts (t from 0 to 1) of the segment [param e0]-[param e1] inside room [param id]'s outline.
static func _spans(world: MDSWorld, id: String, e0: Vector2, e1: Vector2) -> Array:
	if not world.has_room_shape(id):
		return [Vector2(0, 1)]
	var out: Array = []
	var length := maxf(0.001, e0.distance_to(e1))
	for poly in world.get_room_shape(id):
		for piece in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([e0, e1]), poly):
			if piece.size() >= 2:
				var t0 := e0.distance_to(piece[0]) / length
				var t1 := e0.distance_to(piece[piece.size() - 1]) / length
				out.append(Vector2(minf(t0, t1), maxf(t0, t1)))
	return out

static func rooms_connected(world: MDSWorld, a: String, b: String) -> bool:
	for g in world.get_gates(a).values():
		if g.get("to", "") == b:
			return true
	for g in world.get_gates(b).values():
		if g.get("to", "") == a:
			return true
	return false

## Touching room pairs: [own room, other room] -> number of cell sides they share, for the
## cells [param own] (cell -> room) against [param others] (cell -> room).
static func contacts(own: Dictionary, others: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for c in own:
		for d in DIRS:
			var n: Vector2i = c + d
			if others.has(n) and others[n] != own[c]:
				var key := [own[c], others[n]]
				out[key] = out.get(key, 0) + 1
	return out

## Connects room [param id] to each touching room of the same area (no area counts as one too)
## that it has no door to yet. Returns the number of doors made.
static func link_neighbors(world: MDSWorld, id: String, layer: int) -> int:
	if not world.has_room(id):
		return 0
	var area := world.get_room_area(id)
	var one: Array[String] = [id]
	var mine := cells_of(world, one)
	var others: Dictionary = {}
	for other in world.get_room_ids():
		if other != id and world.get_room_layer(other) == layer and world.get_room_area(other) == area:
			for c in world.get_room_cells(other):
				others[c] = other
	var n := 0
	for pair in contacts(mine, others):
		if not rooms_connected(world, pair[0], pair[1]) and not add_door(world, pair[0], pair[1]).is_empty():
			n += 1
	return n

## Connects the rooms [param ids] (one area's, on [param layer]) to every other area they
## touch and have no door to yet: one door per area, between the two rooms sharing the most,
## marked [constant AUTO_LINK]. Returns [[room, gate, other room, other gate], ...].
static func link_touching(world: MDSWorld, ids: Array[String], layer: int) -> Array:
	var own := cells_of(world, ids)
	var others := occupied(world, layer, ids)
	var mine: Dictionary = {}
	for id in ids:
		mine[group_of(world, id)] = true
	var best: Dictionary = {} # other group -> [pair, count]
	var counts := contacts(own, others)
	for pair in counts:
		var g := group_of(world, pair[1])
		if mine.has(g):
			continue
		if not best.has(g) or counts[pair] > best[g][1]:
			best[g] = [pair, counts[pair]]
	var made: Array = []
	for g in best:
		if _groups_connected(world, ids, g):
			continue
		var pair: Array = best[g][0]
		var gates := add_door(world, pair[0], pair[1], true)
		if not gates.is_empty():
			made.append([pair[0], gates[0], pair[1], gates[1]])
	return made

static func _groups_connected(world: MDSWorld, ids: Array[String], group: String) -> bool:
	for id in ids:
		for g in world.get_gates(id).values():
			var to := str(g.get("to", ""))
			if not to.is_empty() and world.has_room(to) and group_of(world, to) == group:
				return true
	return false

## Takes out the [constant AUTO_LINK] doors of rooms [param ids] that lead out of them and whose
## two rooms no longer touch there. Returns how many.
static func unlink_apart(world: MDSWorld, ids: Array[String]) -> int:
	var n := 0
	for id in ids:
		for gate_name in world.get_gates(id).keys():
			var g := world.get_gate(id, gate_name)
			var to := str(g.get("to", ""))
			if not g.get(AUTO_LINK, false) or to.is_empty() or ids.has(to):
				continue
			if not _touch_at(world, id, gate_name, to):
				world.remove_gate(to, str(g.get("to_gate", "")))
				world.remove_gate(id, gate_name)
				n += 1
	return n

## Whether gate [param gate_name] of [param id] still sits where [param id] meets [param to].
static func _touch_at(world: MDSWorld, id: String, gate_name: String, to: String) -> bool:
	var side := world.get_gate_side(id, gate_name)
	var out: Vector2 = {"right": Vector2.RIGHT, "left": Vector2.LEFT, "bot": Vector2.DOWN, "top": Vector2.UP}.get(side, Vector2.ZERO)
	if out == Vector2.ZERO:
		return world.room_contains(to, world.get_gate_world_pos(id, gate_name))
	var p := world.get_gate_world_pos(id, gate_name)
	var q := minf(world.get_paint_cell().x, world.get_paint_cell().y) * 0.25
	return world.room_contains(id, p - out * q) and world.room_contains(to, p + out * q)

# --- Outlines ----------------------------------------------------------------------------------

## The outline of [param cells] (cell -> anything) as world segments: pairs of points, one
## straight run of cell sides each.
static func outline(cells: Dictionary, cell_size: Vector2) -> PackedVector2Array:
	var top: Dictionary = {}
	var bottom: Dictionary = {}
	var left: Dictionary = {}
	var right: Dictionary = {}
	for c: Vector2i in cells:
		if not cells.has(c + Vector2i.UP):
			_add_to(top, c.y, c.x)
		if not cells.has(c + Vector2i.DOWN):
			_add_to(bottom, c.y + 1, c.x)
		if not cells.has(c + Vector2i.LEFT):
			_add_to(left, c.x, c.y)
		if not cells.has(c + Vector2i.RIGHT):
			_add_to(right, c.x + 1, c.y)
	var out := PackedVector2Array()
	for lines in [top, bottom]:
		_runs(lines, cell_size, true, out)
	for lines in [left, right]:
		_runs(lines, cell_size, false, out)
	return out

## The sides between cells of different rooms in [param owner] (cell -> room id), as world
## segments like [method outline].
static func inner_edges(owner: Dictionary, cell_size: Vector2) -> PackedVector2Array:
	var rows: Dictionary = {}
	var cols: Dictionary = {}
	for c: Vector2i in owner:
		var r: Vector2i = c + Vector2i.RIGHT
		if owner.has(r) and owner[r] != owner[c]:
			_add_to(cols, c.x + 1, c.y)
		var d: Vector2i = c + Vector2i.DOWN
		if owner.has(d) and owner[d] != owner[c]:
			_add_to(rows, c.y + 1, c.x)
	var out := PackedVector2Array()
	_runs(rows, cell_size, true, out)
	_runs(cols, cell_size, false, out)
	return out

static func _add_to(lines: Dictionary, line: int, at: int) -> void:
	if not lines.has(line):
		lines[line] = []
	lines[line].append(at)

static func _runs(lines: Dictionary, s: Vector2, horizontal: bool, out: PackedVector2Array) -> void:
	for line: int in lines:
		var list: Array = lines[line]
		list.sort()
		var i := 0
		while i < list.size():
			var a: int = list[i]
			var b: int = a
			while i + 1 < list.size() and list[i + 1] == b + 1:
				i += 1
				b = list[i]
			if horizontal:
				out.append(Vector2(a * s.x, line * s.y))
				out.append(Vector2((b + 1) * s.x, line * s.y))
			else:
				out.append(Vector2(line * s.x, a * s.y))
				out.append(Vector2(line * s.x, (b + 1) * s.y))
			i += 1
