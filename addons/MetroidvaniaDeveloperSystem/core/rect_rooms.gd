@tool
class_name MDSRectRooms
extends RefCounted
## Rooms of straight-walled chambers, for Generate cave's "rooms" style (see
## [constant MDSCaveShapes.STYLES]): the room's box is split again and again (binary space
## partitioning) and each part holds one rectangular chamber. Chambers side by side are joined by
## flat corridors, with ledges to climb where a corridor drops into a lower chamber; chambers one
## above the other by shafts with ledges on alternate sides. Tall chambers get ledges in tiers.
## The gates are led to their nearest chamber. Every chamber and side gate is checked to reach every
## other and back (walking, jumping, falling, see [method MDSRoomPainter.climb_reach]); a layout that
## doesn't is made again from the next seed, and a chamber that still can't be reached is filled in.
## Generate cave then opens the gates, joins them and places hazards as for any room (see
## [method MDSRoomPainter.generate_cave], [MDSRoomHazards]).
## [codeblock]
## painter.generate_cave(world, "Keep_03", 7, 0, 0, {}, {"cave": {"style": "rooms", "depth": 4, "hazards": "some"}})
## [/codeblock]
## [param cave]: [code]style: "rooms"[/code], [code]depth[/code] (splits, 1 to 6: more, smaller
## chambers; default 4), [code]tries[/code] (layouts made to find one that is joined, default 12),
## [code]version[/code] (reserved, see [constant VERSION]).

## The algorithm's version: bump it when a change would alter the room a seed gives, and keep the
## old branch, so a seed written down today still gives today's room.
const VERSION := 1
## Rock left at the room's edge, cells.
const MARGIN := 2
## The narrowest part a split leaves, cells.
const MIN_WIDTH := 12
const DEFAULT_DEPTH := 4
## Width of the shafts between chambers one above the other, cells.
const SHAFT := 4
## How far a player jumps across, cells (as [method MDSRoomPainter.climb_reach]'s default).
const JUMP_W := 3

static func wanted(cave: Dictionary) -> bool:
	return str(cave.get("style", "")) == "rooms"

## The layout of a rooms-style room in [param inside] (its cells, in its box [param lo] to
## [param hi]), with [param gates] ([{cell, side}], as Generate cave finds them):
## {solid (rock cells of the box), chambers (each one's [x0, y0, x1, y1], open cells, its floor
## row y1), anchors (a standing cell in each chamber), keep (cells hazards stay off: doorsteps,
## the ends of corridors and shafts, ledges), joined (whether every chamber was reached both ways
## before any had to be filled in)}. [param tall]: the player's height in tiles (corridors are a
## row more), [param step]: rows between ledges, [param reach]: rows a jump climbs.
static func build(inside: Dictionary, lo: Vector2i, hi: Vector2i, cave: Dictionary, gates: Array, rng: RandomNumberGenerator, tall := 4, step := 3, reach := 5) -> Dictionary:
	var depth := clampi(int(cave.get("depth", DEFAULT_DEPTH)), 1, 6)
	var tries := clampi(int(cave.get("tries", 12)), 1, 32)
	var best: Layout = null
	for t in tries:
		var sub := RandomNumberGenerator.new()
		sub.seed = rng.randi()
		var l := Layout.new(inside, lo, hi, gates, sub, tall, step, reach)
		l.make(depth)
		if l.doors_ok and l.joined_count == l.chambers.size() and not l.chambers.is_empty():
			return l.result(true)
		if best == null or l.score() > best.score():
			best = l
	best.prune()
	return best.result(false)


## One try at a layout.
class Layout extends RefCounted:
	var inside: Dictionary
	var lo: Vector2i
	var hi: Vector2i
	var gates: Array
	var rng: RandomNumberGenerator
	var tall: int
	var step: int
	var reach: int
	## Open cells -> true.
	var open: Dictionary = {}
	## Cells of the chambers themselves -> true.
	var chamber_cells: Dictionary = {}
	var chambers: Array = []
	var keep: Dictionary = {}
	var anchors: Array = []
	## The door standing cells of side gates (checked with the chambers).
	var doors: Array = []
	var joined_count := 0
	## Whether the side gates reach the first chamber and back.
	var doors_ok := false

	func _init(inside_: Dictionary, lo_: Vector2i, hi_: Vector2i, gates_: Array, rng_: RandomNumberGenerator, tall_: int, step_: int, reach_: int) -> void:
		inside = inside_
		lo = lo_
		hi = hi_
		gates = gates_
		rng = rng_
		tall = tall_
		step = step_
		reach = reach_

	func make(depth: int) -> void:
		var tree := _split([lo.x + MARGIN, lo.y + MARGIN, hi.x - MARGIN, hi.y - MARGIN], depth)
		_carve_chambers(tree)
		_connect(tree)
		_doors()
		_platforms()
		anchors = _anchors()
		joined_count = _joined().size()
		doors_ok = _doors_joined()

	## Better layouts first: the gates joined, then the most chambers joined.
	func score() -> int:
		return (1000 if doors_ok else 0) + joined_count

	func result(joined: bool) -> Dictionary:
		var solid: Dictionary = {}
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector2i(x, y)
				if not open.has(c):
					solid[c] = true
		return {"solid": solid, "chambers": chambers, "anchors": anchors, "keep": keep, "joined": joined}

	# --- cells ---

	func is_open(c: Vector2i) -> bool:
		return open.has(c)

	func _open_rect(x0: int, y0: int, x1: int, y1: int) -> void:
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			for x in range(mini(x0, x1), maxi(x0, x1) + 1):
				var c := Vector2i(x, y)
				if inside.has(c):
					open[c] = true

	func _rock(c: Vector2i) -> void:
		open.erase(c)

	# --- splitting ---

	func _split(r: Array, depth: int) -> Dictionary:
		var w: int = r[2] - r[0] + 1
		var h: int = r[3] - r[1] + 1
		var min_h := tall + 6
		var can_v := w >= 2 * MIN_WIDTH
		var can_h := h >= 2 * min_h
		if depth == 0 or not (can_v or can_h) or (depth <= 1 and rng.randf() < 0.25):
			return {"leaf": r}
		var vert := can_v
		if can_v and can_h:
			vert = float(w) / h > 1.2 or (float(h) / w <= 1.2 and rng.randf() < 0.5)
		var a: Array
		var b: Array
		if vert:
			var cut := rng.randi_range(r[0] + MIN_WIDTH, r[2] - MIN_WIDTH + 1)
			a = [r[0], r[1], cut - 1, r[3]]
			b = [cut, r[1], r[2], r[3]]
		else:
			var cut := rng.randi_range(r[1] + min_h, r[3] - min_h + 1)
			a = [r[0], r[1], r[2], cut - 1]
			b = [r[0], cut, r[2], r[3]]
		return {"vert": vert, "a": _split(a, depth - 1), "b": _split(b, depth - 1)}

	func _leaves(node: Dictionary) -> Array:
		if node.has("leaf"):
			return [node]
		return _leaves(node.a) + _leaves(node.b)

	## One chamber in each part, padded from its edges, at least [member tall] + 2 rows high. A
	## part mostly outside the room's shape (an L-shaped or curved room) gets none.
	func _carve_chambers(tree: Dictionary) -> void:
		for leaf: Dictionary in _leaves(tree):
			var r: Array = leaf.leaf
			var x0: int = r[0] + rng.randi_range(1, 2)
			var x1: int = r[2] - rng.randi_range(1, 2)
			var y0: int = r[1] + rng.randi_range(1, 3)
			var y1: int = r[3] - rng.randi_range(1, 2)
			if y1 - y0 + 1 < tall + 2:
				y0 = y1 - (tall + 1)
			leaf.chamber = -1
			if x1 - x0 < SHAFT + 2:
				continue
			var n := 0
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					if inside.has(Vector2i(x, y)):
						n += 1
			if n < (x1 - x0 + 1) * (y1 - y0 + 1) * 0.9:
				continue
			leaf.chamber = chambers.size()
			chambers.append([x0, y0, x1, y1])
			_open_rect(x0, y0, x1, y1)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					chamber_cells[Vector2i(x, y)] = true

	func _chambers_of(node: Dictionary) -> Array:
		var out: Array = []
		for leaf: Dictionary in _leaves(node):
			if int(leaf.chamber) >= 0:
				out.append(chambers[leaf.chamber])
		return out

	# --- joining ---

	## Joins the two halves of every split, from the smallest up: the closest pair of chambers
	## across it, by a corridor (side by side) or a shaft (one above the other).
	func _connect(node: Dictionary) -> void:
		if node.has("leaf"):
			return
		_connect(node.a)
		_connect(node.b)
		var A := _chambers_of(node.a)
		var B := _chambers_of(node.b)
		if A.is_empty() or B.is_empty():
			return
		var best: Array = []
		var best_d := INF
		for a: Array in A:
			for b: Array in B:
				var d: float
				if node.vert:
					d = (b[0] - a[2]) + absi(a[3] - b[3]) * 0.5
				else:
					d = (b[1] - a[3]) + _x_gap(a, b) * 2.0
				if d < best_d:
					best_d = d
					best = [a, b]
		if node.vert:
			_corridor(best[0], best[1])
		else:
			_shaft(best[0], best[1])

	static func _x_gap(a: Array, b: Array) -> int:
		return maxi(0, maxi(a[0], b[0]) - mini(a[2], b[2]))

	## A floor under open cells of row [param y] from [param x0] to [param x1], except in a chamber.
	func _floor(x0: int, x1: int, y: int) -> void:
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			var c := Vector2i(x, y)
			if not chamber_cells.has(c):
				_rock(c)

	## Ledges up a wall from standing row [param floor_y] toward row [param top_y], every
	## [member step] rows, alternating between the two ends of [param x_from]..[param x_to] (two
	## cells each), so a drop can be climbed back.
	func _stairs(x_from: int, x_to: int, floor_y: int, top_y: int) -> void:
		var x_lo := mini(x_from, x_to)
		var x_hi := maxi(x_from, x_to)
		var y := floor_y - step
		var left := true
		while y > top_y:
			var xs := [x_lo, x_lo + 1] if left else [x_hi - 1, x_hi]
			for x: int in xs:
				if is_open(Vector2i(x, y)) and is_open(Vector2i(x, y - 1)):
					_rock(Vector2i(x, y))
					keep[Vector2i(x, y)] = true
			left = not left
			y -= step

	## Left chamber [param a] to right chamber [param b]: a flat corridor [member tall] + 1 rows
	## high at the higher floor (kept within both chambers' heights), ledges where it drops into
	## the lower one.
	func _corridor(a: Array, b: Array) -> void:
		var fa: int = a[3]
		var fb: int = b[3]
		var f := mini(fa, fb)
		f = maxi(f, maxi(a[1], b[1]) + tall)
		f = mini(f, mini(fa, fb))
		var x0: int = a[2] + 1
		var x1: int = b[0] - 1
		_open_rect(x0, f - tall, x1, f)
		_floor(x0, x1, f + 1)
		for x in range(x0 - 3, x1 + 4):
			keep[Vector2i(x, f + 1)] = true
			keep[Vector2i(x, f)] = true
		for side: Array in [[a, a[2], -1], [b, b[0], 1]]:
			var ch: Array = side[0]
			var mouth_x: int = side[1]
			if ch[3] - f > reach - 1:
				_stairs(mouth_x, mouth_x + side[2] * 3, ch[3], f)

	## A column [member SHAFT] wide from row [param top] to [param bottom], ledges on alternate
	## sides every [member step] rows from [param bottom] up.
	func _column(x: int, top: int, bottom: int) -> void:
		_open_rect(x, top, x + SHAFT - 1, bottom)
		var y := bottom - step
		var left := true
		while y >= top:
			for dx: int in ([0, 1] if left else [2, 3]):
				var c := Vector2i(x + dx, y)
				if is_open(c):
					_rock(c)
			left = not left
			y -= step
		for yy in range(top - 1, bottom + 2):
			for xx in range(x - 2, x + SHAFT + 2):
				keep[Vector2i(xx, yy)] = true

	## Upper chamber [param a] to lower chamber [param b]: a shaft with ledges. When they don't
	## overlap across, the shaft comes down beside [param b] and a corridor runs into it.
	func _shaft(a: Array, b: Array) -> void:
		var x_lo := maxi(a[0], b[0])
		var x_hi := mini(a[2], b[2])
		if x_hi - x_lo + 1 >= SHAFT:
			_column(rng.randi_range(x_lo, x_hi - SHAFT + 1), a[3], b[3])
			return
		var x := rng.randi_range(a[0], a[2] - SHAFT + 1)
		var f: int = b[3]
		_column(x, a[3], f)
		var to: int = b[0] if x + SHAFT - 1 < b[0] else b[2]
		_open_rect(x, f - tall, to, f)
		_floor(x, to, f + 1)

	## The gates led to their nearest chamber: a corridor in from a side gate, a shaft down from
	## a top one or down to a bottom one, at the gate's own place (where Generate cave opens it).
	func _doors() -> void:
		if chambers.is_empty():
			return
		for g: Dictionary in gates:
			var gc: Vector2i = g.cell
			var side := str(g.side)
			if side == "left" or side == "right":
				# The doorway's rows are gc.y - 2 to gc.y + 1, its ground gc.y + 2.
				var pos := gc.y + 1
				var ch := _nearest(func(c: Array) -> float:
					return absi(c[3] - pos) + 0.3 * (c[0] - lo.x if side == "left" else hi.x - c[2]))
				var cx: int = ch[0] if side == "left" else ch[2] - SHAFT + 1
				var edge := lo.x if side == "left" else hi.x
				var inner: int = cx + SHAFT - 1 if side == "left" else cx
				_open_rect(edge, pos - tall, inner, pos)
				_floor(edge, inner, pos + 1)
				for x in range(mini(edge, inner) - 2, maxi(edge, inner) + 3):
					keep[Vector2i(x, pos)] = true
					keep[Vector2i(x, pos + 1)] = true
				var top := mini(pos, ch[3])
				var bottom := maxi(pos, ch[3])
				if bottom != top:
					_open_rect(cx, top, cx + SHAFT - 1, bottom)
				if bottom - top > reach - 1:
					_stairs(cx, cx + SHAFT - 1, bottom, top)
				doors.append(Vector2i(gc.x, pos))
			elif side == "top" or side == "bot":
				var ch := _nearest(func(c: Array) -> float:
					return absf((c[0] + c[2]) * 0.5 - gc.x) + (c[1] - lo.y if side == "top" else hi.y - c[3]))
				var x := gc.x - 2
				var inside_x: bool = x >= ch[0] and x + SHAFT - 1 <= ch[2]
				if side == "top":
					_column(x, lo.y, ch[3])
					if not inside_x:
						var to: int = ch[0] if x < ch[0] else ch[2]
						_open_rect(x, ch[3] - tall, to, ch[3])
						_floor(x, to, ch[3] + 1)
				else:
					var from: int = ch[3]
					if not inside_x:
						var to: int = ch[0] if x < ch[0] else ch[2]
						_open_rect(x, ch[3] - tall, to, ch[3])
					_column(x, from, hi.y)

	func _nearest(score: Callable) -> Array:
		var best: Array = chambers[0]
		var best_s := INF
		for c: Array in chambers:
			var s: float = score.call(c)
			if s < best_s:
				best_s = s
				best = c
		return best

	## Tall chambers: staggered ledges in tiers, a jump apart (now and then one floating in the
	## middle), so their height is used.
	@warning_ignore("integer_division")
	func _platforms() -> void:
		for ch: Array in chambers:
			var x0: int = ch[0]
			var y0: int = ch[1]
			var x1: int = ch[2]
			var y1: int = ch[3]
			if y1 - y0 + 1 < 2 * tall + 2:
				continue
			var y := y1 - (reach - 1)
			var left := rng.randf() < 0.5
			while y >= y0 + tall + 1:
				var n := rng.randi_range(3, 6)
				var start := x0 if left else x1 - n + 1
				if x1 - x0 > 14 and rng.randf() < 0.4:
					start = (x0 + x1) / 2 + rng.randi_range(-3, 3) - n / 2
				var ok := true
				for x in range(start, start + n):
					for yy in range(y - tall, y + 1):
						if not is_open(Vector2i(x, yy)):
							ok = false
					for yy in range(y - 1, y + 2):
						if keep.has(Vector2i(x, yy)):
							ok = false
				if ok:
					for x in range(start, start + n):
						_rock(Vector2i(x, y))
				left = not left
				y -= reach - 1

	# --- checking ---

	## A standing cell on each chamber's floor, near its middle.
	@warning_ignore("integer_division")
	func _anchors() -> Array:
		var out: Array = []
		for ch: Array in chambers:
			var spots: Array = []
			var any: Array = []
			for x in range(ch[0], ch[2] + 1):
				var c := Vector2i(x, ch[3])
				if is_open(c) and not is_open(c + Vector2i.DOWN):
					any.append(c)
					# Room to stand: the player's height clear above.
					var clear := true
					for dy in tall:
						clear = clear and is_open(c - Vector2i(0, dy))
					if clear:
						spots.append(c)
			if spots.is_empty():
				spots = any
			if spots.is_empty():
				spots.append(Vector2i((ch[0] + ch[2]) / 2, ch[3]))
			out.append(spots[spots.size() / 2])
		return out

	## Whether the side gates reach the first chamber and back.
	func _doors_joined() -> bool:
		if anchors.is_empty() or not open.has(anchors[0]):
			return false
		var land := MDSRoomPainter.land_map(open)
		var home: Vector2i = land[anchors[0]]
		var from0 := MDSRoomPainter.climb_reach(open, anchors[0], reach, JUMP_W, land)
		for d: Vector2i in doors:
			if not open.has(d) or not from0.has(land[d]):
				return false
			if not MDSRoomPainter.climb_reach(open, d, reach, JUMP_W, land, false, {}, {home: true}).has(home):
				return false
		return true

	## The chambers (indices) the first one reaches and is reached back from.
	func _joined() -> Array:
		var out: Array = []
		if anchors.is_empty():
			return out
		var land := MDSRoomPainter.land_map(open)
		var a0: Vector2i = anchors[0]
		if not open.has(a0):
			return out
		var home: Vector2i = land[a0]
		var from0 := MDSRoomPainter.climb_reach(open, a0, reach, JUMP_W, land)
		for i in anchors.size():
			var a: Vector2i = anchors[i]
			if not open.has(a) or not from0.has(land[a]):
				continue
			if i == 0 or MDSRoomPainter.climb_reach(open, a, reach, JUMP_W, land, false, {}, {home: true}).has(home):
				out.append(i)
		return out

	## Fills in the chambers that aren't joined, so none is left that can't be reached.
	func prune() -> void:
		var keep_i := _joined()
		var kept: Array = []
		var kept_anchors: Array = []
		for i in chambers.size():
			var ch: Array = chambers[i]
			if i in keep_i:
				kept.append(ch)
				kept_anchors.append(anchors[i])
				continue
			for y in range(ch[1], ch[3] + 1):
				for x in range(ch[0], ch[2] + 1):
					_rock(Vector2i(x, y))
		chambers = kept
		anchors = kept_anchors
		joined_count = chambers.size()
