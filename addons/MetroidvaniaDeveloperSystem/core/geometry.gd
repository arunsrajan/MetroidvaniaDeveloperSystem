@tool
class_name IDPGeometry
extends RefCounted
## Polygon helpers shared by the freeform tools (repair, Convert to freeform, Decorate, Fill
## outside shape) and the room checks. No editor dependencies.
##
## A polygon Godot can fill ([Polygon2D]) and collide with ([CollisionPolygon2D] in solids
## mode) must be [i]simple[/i]: it triangulates and no two of its edges cross. A twisted one
## draws nothing and logs "Convex decomposing failed!", see [method is_simple].

## Parts smaller than this (px²) are slivers: dropped when untwisting.
const SLIVER_AREA := 400.0

static func signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a / 2.0

static func bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r

static func rect_polygon(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

static func transformed(xform: Transform2D, poly: PackedVector2Array) -> PackedVector2Array:
	return xform * poly

## [param poly] without consecutive duplicate points (the closing point included).
static func dedupe(poly: PackedVector2Array, eps := 0.01) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > eps * eps:
			out.append(p)
	while out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) <= eps * eps:
		out.remove_at(out.size() - 1)
	return out

## Whether an outline can be filled and collided with: it triangulates and no edge crosses
## another. Repeated points are ignored. Edges are swept by x, so big outlines stay fast.
static func is_simple(poly: PackedVector2Array) -> bool:
	var o := dedupe(poly)
	var n := o.size()
	if n < 3 or Geometry2D.triangulate_polygon(o).is_empty():
		return false
	# Edges sorted by their left end; each is tested against the edges that start before its
	# right end.
	var order: Array = []
	order.resize(n)
	for i in n:
		order[i] = i
	var lo_x := PackedFloat32Array()
	var hi_x := PackedFloat32Array()
	var lo_y := PackedFloat32Array()
	var hi_y := PackedFloat32Array()
	lo_x.resize(n)
	hi_x.resize(n)
	lo_y.resize(n)
	hi_y.resize(n)
	for i in n:
		var a := o[i]
		var b := o[(i + 1) % n]
		lo_x[i] = minf(a.x, b.x) - 0.01
		hi_x[i] = maxf(a.x, b.x) + 0.01
		lo_y[i] = minf(a.y, b.y) - 0.01
		hi_y[i] = maxf(a.y, b.y) + 0.01
	order.sort_custom(func(a: int, b: int) -> bool: return lo_x[a] < lo_x[b])
	for k in n:
		var i: int = order[k]
		for m in range(k + 1, n):
			var j: int = order[m]
			if lo_x[j] > hi_x[i]:
				break
			if absi(i - j) == 1 or absi(i - j) == n - 1:
				continue # neighbours share a point
			if lo_y[j] > hi_y[i] or hi_y[j] < lo_y[i]:
				continue
			if Geometry2D.segment_intersects_segment(o[i], o[(i + 1) % n], o[j], o[(j + 1) % n]) != null:
				return false
	return true

## A twisted polygon as simple ones: Clipper unties it, parts under [param min_area] px² are
## dropped, and holes it would enclose are cut open (a freeform shape has no holes). A
## simple polygon comes back as it is.
static func untwist(poly: PackedVector2Array, min_area := SLIVER_AREA) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var clean := dedupe(poly)
	if is_simple(clean):
		out.append(clean)
		return out
	var parts := Geometry2D.merge_polygons(clean, PackedVector2Array())
	return without_holes(parts, min_area)

## Splits Clipper output (outlines and holes) into simple polygons without holes: each hole
## is cut open by splitting its outline through the hole. Slivers are dropped.
static func without_holes(parts: Array, min_area := SLIVER_AREA) -> Array[PackedVector2Array]:
	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for p: PackedVector2Array in parts:
		if p.size() < 3:
			continue
		# Inside an odd number of the other outlines: a hole.
		var depth := 0
		var probe := _inner_point(p)
		for q: PackedVector2Array in parts:
			if q != p and q.size() >= 3 and absf(signed_area(q)) > absf(signed_area(p)) and Geometry2D.is_point_in_polygon(probe, q):
				depth += 1
		if depth % 2 == 1:
			holes.append(p)
		else:
			outers.append(p)
	var out: Array[PackedVector2Array] = []
	for o in outers:
		var mine: Array[PackedVector2Array] = []
		for h in holes:
			if Geometry2D.is_point_in_polygon(_inner_point(h), o):
				mine.append(h)
		for piece in _cut_holes(o, mine, min_area):
			if absf(signed_area(piece)) >= min_area:
				var simple := dedupe(piece)
				if is_simple(simple):
					out.append(simple)
	return out

## A point inside [param p] (the centroid of its largest triangle).
static func _inner_point(p: PackedVector2Array) -> Vector2:
	var tris := Geometry2D.triangulate_polygon(p)
	var best := -1.0
	var at := p[0]
	for t in range(0, tris.size(), 3):
		var a := p[tris[t]]
		var b := p[tris[t + 1]]
		var c := p[tris[t + 2]]
		var area := absf((b - a).cross(c - a))
		if area > best:
			best = area
			at = (a + b + c) / 3.0
	return at

static func _cut_holes(outer: PackedVector2Array, holes: Array[PackedVector2Array], min_area: float) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [outer]
	for h in holes:
		if absf(signed_area(h)) < min_area:
			continue # a pinhole: filled
		var x := bounds(h).get_center().x
		var next: Array[PackedVector2Array] = []
		for piece in pieces:
			var b := bounds(piece).grow(10.0)
			if not bounds(h).intersects(b):
				next.append(piece)
				continue
			for half in [Rect2(b.position, Vector2(x - b.position.x, b.size.y)), Rect2(Vector2(x, b.position.y), Vector2(b.end.x - x, b.size.y))]:
				for part in Geometry2D.intersect_polygons(piece, rect_polygon(half)):
					for rest in Geometry2D.clip_polygons(part, h):
						if Geometry2D.is_polygon_clockwise(rest) != Geometry2D.is_polygon_clockwise(part):
							continue # a hole the cut missed
						next.append(rest)
		pieces = next
	return pieces

## Douglas-Peucker on a closed outline: drops points within [param tolerance] px of the line
## between their neighbours.
static func simplify_closed(poly: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 5:
		return poly
	# Split the ring at its two farthest-apart points and simplify each half.
	var far := 0
	for i in n:
		if poly[i].distance_squared_to(poly[0]) > poly[far].distance_squared_to(poly[0]):
			far = i
	var keep := PackedByteArray()
	keep.resize(n)
	keep.fill(0)
	keep[0] = 1
	keep[far] = 1
	var stack: Array = [[0, far], [far, n]]
	while not stack.is_empty():
		var span: Array = stack.pop_back()
		var i0: int = span[0]
		var i1: int = span[1]
		var a := poly[i0]
		var b := poly[i1 % n]
		var worst := -1.0
		var at := -1
		for i in range(i0 + 1, i1):
			var d := Geometry2D.get_closest_point_to_segment(poly[i], a, b).distance_to(poly[i])
			if d > worst:
				worst = d
				at = i
		if at >= 0 and worst > tolerance:
			keep[at] = 1
			stack.append([i0, at])
			stack.append([at, i1])
	var out := PackedVector2Array()
	for i in n:
		if keep[i] == 1:
			out.append(poly[i])
	return out if out.size() >= 3 else poly

## Joins every pair of pieces that touch, until none do. Two pieces whose union would
## enclose air bigger than [param max_pocket] px² stay two pieces (a freeform shape has no
## holes); smaller pockets are filled.
static func union_all(pieces: Array[PackedVector2Array], max_pocket := 6000.0) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var pending: Array[PackedVector2Array] = pieces.duplicate()
	while not pending.is_empty():
		var cur: PackedVector2Array = pending.pop_back()
		var merged := true
		while merged:
			merged = false
			for i in range(out.size() - 1, -1, -1):
				if not bounds(cur).grow(1.0).intersects(bounds(out[i])):
					continue
				var res := Geometry2D.merge_polygons(cur, out[i])
				if res.size() == 1:
					cur = res[0]
					out.remove_at(i)
					merged = true
					break
				if res.size() > 1:
					var outer := outer_of(res)
					if outer < 0:
						continue # they don't touch
					var pocket := 0.0
					for j in res.size():
						if j != outer:
							pocket += absf(signed_area(res[j]))
					if pocket < max_pocket:
						cur = res[outer]
						out.remove_at(i)
						merged = true
						break
		out.append(cur)
	return out

## The polygon of [param polys] that holds all the others (an outline with holes), or -1.
static func outer_of(polys: Array) -> int:
	for i in polys.size():
		var all_in := true
		for j in polys.size():
			if i != j and not Geometry2D.is_point_in_polygon(polys[j][0], polys[i]):
				all_in = false
				break
		if all_in:
			return i
	return -1

## What is left of [param poly] once everything in [param rects] is taken out of it. A rect
## lying wholly inside leaves the polygon as it is (a freeform shape has no holes).
static func clear_of(poly: PackedVector2Array, rects: Array, min_area := SLIVER_AREA) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [poly]
	for r: Rect2 in rects:
		var box := rect_polygon(r)
		var next: Array[PackedVector2Array] = []
		for p in parts:
			if not bounds(p).intersects(r):
				next.append(p)
				continue
			var left := Geometry2D.clip_polygons(p, box)
			var holes := left.filter(func(q: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(q) != Geometry2D.is_polygon_clockwise(p))
			if not holes.is_empty():
				next.append(p)
				continue
			for q in left:
				if absf(signed_area(q)) >= min_area:
					next.append(q)
		parts = next
	return parts

static func point_in_any(polys: Array, p: Vector2) -> bool:
	for poly: PackedVector2Array in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false

## Going down column [param x] from [param y0]: where [param outline] turns solid (1.5 px of
## it running), or [param y1]. Probes sit off the half-pixel grid, so a probe never lies level
## with a vertex (where a point-in-polygon test can answer either way).
static func solid_from(outline: PackedVector2Array, x: float, y0: float, y1: float) -> float:
	var y := y0 + 0.137
	var run := 0
	while y < y1:
		run = run + 1 if Geometry2D.is_point_in_polygon(Vector2(x + 0.071, y), outline) else 0
		if run == 4:
			return y - 1.5
		y += 0.5
	return y1

static func segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false

## Merges cells (Vector2i keys of [param cells]) into rectangles, in cell units
## (see [method IDPWorld.cells_to_runs]).
static func cells_to_rects(cells: Dictionary, cell_size: Vector2, origin := Vector2.ZERO) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for run in IDPWorld.cells_to_runs(cells):
		out.append(Rect2(origin + Vector2(run[0], run[2]) * cell_size, Vector2(run[1] - run[0] + 1, run[3] - run[2] + 1) * cell_size))
	return out

## The union of rectangles as simple polygons (touching rectangles joined).
static func union_rects(rects: Array, max_pocket := 6000.0) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	for r: Rect2 in rects:
		pieces.append(rect_polygon(r))
	return union_all(pieces, max_pocket)

## [param box] minus the [param holes] (rectangles), as polygons without holes.
static func rect_minus(box: Rect2, holes: Array) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [rect_polygon(box)]
	for h: Rect2 in holes:
		var next: Array[PackedVector2Array] = []
		for p in parts:
			if not bounds(p).intersects(h):
				next.append(p)
				continue
			next.append_array(without_holes(Geometry2D.clip_polygons(p, rect_polygon(h)), 1.0))
		parts = next
	return parts
