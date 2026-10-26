@tool
class_name MDSCaveShapes
extends RefCounted
## Caves shaped like letters and figures: Generate cave carves the room's open space as one or
## more shapes (a T, a U, an H, an L, an i, a cross, a ring, an S, a freeform cave, or several
## picked), each turned by any angle, instead of the cave it grows from the room's outline. The
## shapes are joined by tunnels. As a cave (nonlinear), their edges are rough rock and their tall
## parts get ledges on alternate sides to climb; linear, their walls are straight and their floors
## flat, the tall parts smooth walls for the player to wall-climb (see [constant STYLES]). Generate
## cave then opens the gates and joins them as for any cave (see
## [method MDSRoomPainter.generate_cave]).
## [codeblock]
## var fills := {"cave": {"shape": "u", "rotation": 45, "count": 2}}
## fills.cave = {"shape": "several", "shapes": ["t", "i", "h"], "count": 3, "rotation": -1, "style": "linear"}
## painter.generate_cave(world, "Hall", 7, 0, 0, {}, fills)
## [/codeblock]

## The shapes: id -> its strokes, segments [from, to] in the shape's box (0..1 across and down).
const STROKES := {
	"t": [[Vector2(0.06, 0.2), Vector2(0.94, 0.2)], [Vector2(0.5, 0.2), Vector2(0.5, 0.92)]],
	"u": [[Vector2(0.14, 0.06), Vector2(0.14, 0.84)], [Vector2(0.14, 0.84), Vector2(0.86, 0.84)], [Vector2(0.86, 0.84), Vector2(0.86, 0.06)]],
	"h": [[Vector2(0.14, 0.06), Vector2(0.14, 0.94)], [Vector2(0.86, 0.06), Vector2(0.86, 0.94)], [Vector2(0.14, 0.52), Vector2(0.86, 0.52)]],
	"l": [[Vector2(0.18, 0.06), Vector2(0.18, 0.84)], [Vector2(0.18, 0.84), Vector2(0.94, 0.84)]],
	"cross": [[Vector2(0.06, 0.52), Vector2(0.94, 0.52)], [Vector2(0.5, 0.06), Vector2(0.5, 0.94)]],
	"ring": [[Vector2(0.14, 0.16), Vector2(0.86, 0.16)], [Vector2(0.86, 0.16), Vector2(0.86, 0.84)], [Vector2(0.86, 0.84), Vector2(0.14, 0.84)], [Vector2(0.14, 0.84), Vector2(0.14, 0.16)]],
	"s": [[Vector2(0.1, 0.14), Vector2(0.86, 0.14)], [Vector2(0.86, 0.14), Vector2(0.86, 0.5)], [Vector2(0.86, 0.5), Vector2(0.14, 0.5)], [Vector2(0.14, 0.5), Vector2(0.14, 0.86)], [Vector2(0.14, 0.86), Vector2(0.9, 0.86)]],
	# A lowercase i: its stem and a foot to stand on; its dot is a chamber (see DOTS, NECKS).
	"i": [[Vector2(0.5, 0.5), Vector2(0.5, 0.94)], [Vector2(0.36, 0.94), Vector2(0.64, 0.94)]],
}
## Round chambers of a shape (its dots): id -> their middles, in the shape's box.
const DOTS := {"i": [Vector2(0.5, 0.12)]}
## Narrow passages of a shape (the neck from an i's dot down to its stem): id -> strokes.
const NECKS := {"i": [[Vector2(0.5, 0.12), Vector2(0.5, 0.5)]]}
## How the shapes are carved: "cave" (nonlinear: rough rock, ledges up the tall parts) or "linear"
## (straight walls, flat floors, the shapes' tall parts smooth walls to wall-climb, no ledges; the
## shafts Generate cave carves across open space to join gates keep theirs, having no wall).
const STYLES := [["cave", "Cave (nonlinear, ledges)"], ["linear", "Linear (straight, wall climb)"]]
## The shapes a picker lists, in order: [id, name]. "natural" is the cave grown from the room's
## outline (the shapes not used); "mixed" a shape picked at random for each.
## "several": the shapes picked ([code]shapes[/code]), shared out among the room's shapes.
const CHOICES := [
	["natural", "Natural (from the room's outline)"], ["t", "T"], ["u", "U"], ["h", "H"], ["l", "L"],
	["i", "i (a shaft and its chamber)"], ["cross", "Cross (+)"], ["ring", "Ring (O)"], ["s", "S (switchbacks)"],
	["freeform", "Freeform"], ["mixed", "Mixed (any)"], ["several", "Several picked"],
]
## The shapes that can be picked together (see CHOICES' "several").
const PICKABLE: PackedStringArray = ["t", "u", "h", "l", "i", "cross", "ring", "s", "freeform"]

## Whether [param cave] (Generate cave's "cave" fill: {shape, shapes, rotation, count, width,
## style}) asks for shapes.
static func wanted(cave: Dictionary) -> bool:
	var kind := str(cave.get("shape", "natural"))
	if kind == "several":
		return not _picked(cave).is_empty()
	return not kind.is_empty() and kind != "natural" and (STROKES.has(kind) or kind in ["freeform", "mixed"])

## Whether [param cave] carves linear rooms, to wall-climb (see [constant STYLES]).
static func wall_climb(cave: Dictionary) -> bool:
	return wanted(cave) and str(cave.get("style", "cave")) == "linear"

## The shapes picked in [param cave] ("several"), those that exist.
static func _picked(cave: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for k in cave.get("shapes", []):
		if str(k) in PICKABLE and not out.has(str(k)):
			out.append(str(k))
	return out

## The rock of a cave of shapes in [param inside] (a room's cells, in its box [param lo] to
## [param hi]): every cell of the box but the shapes'. [param cave]: {shape (an id of
## [constant STROKES], "freeform", "mixed" or "several"), shapes (the ids picked, for
## "several"), rotation (degrees clockwise, any; -1: each shape its own, at random), count
## (shapes, 1 to 8), width (their passages', tiles; 0: from the room's size), style ("cave" or
## "linear", see [constant STYLES])}. [param tall]: the player's height in tiles (passages are
## never lower), [param step]: rows between ledges up the tall parts (none when linear).
static func rock(inside: Dictionary, lo: Vector2i, hi: Vector2i, cave: Dictionary, rng: RandomNumberGenerator, tall := 4, step := 4) -> Dictionary:
	var solid: Dictionary = {}
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			solid[Vector2i(x, y)] = true
	var open := carve(inside, lo, hi, cave, rng, tall)
	for c in open.cells:
		solid.erase(c)
	if not wall_climb(cave):
		for c in ladders(open.cells, open.uprights, step):
			solid[c] = true
	return solid

## The open cells of the shapes in [param inside] (see [method rock]): {cells, uprights (the
## steep passages: [from, to, width] in cells), boxes (each shape's box), kinds (each shape's id),
## turns (each one's angle)}.
static func carve(inside: Dictionary, lo: Vector2i, hi: Vector2i, cave: Dictionary, rng: RandomNumberGenerator, tall := 4) -> Dictionary:
	var count := clampi(int(cave.get("count", 1)), 1, 8)
	var kind := str(cave.get("shape", "t"))
	var rotation := float(cave.get("rotation", 0))
	var linear := str(cave.get("style", "cave")) == "linear"
	# The shapes picked, shared out: each at least once when there are as many shapes, in an
	# order of their own each generation.
	var picked := _picked(cave)
	var order: Array = []
	if kind == "several" and not picked.is_empty():
		var round_: Array = Array(picked)
		while order.size() < count:
			for i in range(round_.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t: Variant = round_[i]
				round_[i] = round_[j]
				round_[j] = t
			order.append_array(round_)
		order.resize(count)
	var size := hi - lo + Vector2i.ONE
	# The shapes side by side along the room's long side (a grid when many).
	var across := count
	var down := 1
	if size.y > size.x:
		across = 1
		down = count
	if count >= 4:
		across = ceili(sqrt(float(count) * size.x / maxf(1.0, size.y)))
		across = clampi(across, 1, count)
		down = ceili(float(count) / across)
	var slot := Vector2(float(size.x) / across, float(size.y) / down)
	var width := int(cave.get("width", 0))
	if width <= 0:
		width = int(clampf(minf(slot.x, slot.y) * 0.24, tall + 1, tall + 6))
	width = maxi(width, tall + 1)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.18
	# Linear: straight walls.
	var rough: FastNoiseLite = null if linear else noise
	var neck := maxi(3, tall - 1)
	var cells: Dictionary = {}
	var uprights: Array = []
	var boxes: Array[Rect2i] = []
	var kinds: PackedStringArray = []
	var turns: PackedFloat32Array = []
	var mids: Array[Vector2i] = []
	var made := 0
	for j in down:
		for i in across:
			if made >= count:
				break
			made += 1
			# Each shape's box: its slot, a wall's width in from the room's edge.
			var margin := 2
			var box := Rect2i(lo + Vector2i(Vector2(i, j) * slot) + Vector2i(margin, margin), Vector2i(slot) - Vector2i(margin, margin) * 2)
			if box.size.x < width + 2 or box.size.y < width + 2:
				box = Rect2i(lo + Vector2i(Vector2(i, j) * slot), Vector2i(slot))
			boxes.append(box)
			var this := kind
			if kind == "mixed":
				this = PICKABLE[rng.randi_range(0, PICKABLE.size() - 1)]
			elif kind == "several" and not order.is_empty():
				this = order[made - 1]
			var turn: float = rotation if rotation >= 0.0 else rng.randf_range(0.0, 360.0)
			kinds.append(this)
			turns.append(turn)
			var strokes := freeform_strokes(rng) if this == "freeform" else _turned(STROKES.get(this, STROKES.t), turn)
			for s: Array in strokes:
				var a := _to_cells(s[0], box)
				var b := _to_cells(s[1], box)
				_stroke(cells, a, b, width, rough)
				if absi(b.y - a.y) > absi(b.x - a.x):
					uprights.append([a, b, width])
			for s: Array in _turned(NECKS.get(this, []), turn):
				var a := _to_cells(s[0], box)
				var b := _to_cells(s[1], box)
				_stroke(cells, a, b, neck, null)
				if absi(b.y - a.y) > absi(b.x - a.x):
					uprights.append([a, b, neck])
			for d: Vector2 in _turned_points(DOTS.get(this, []), turn):
				_disc(cells, _to_cells(d, box), width * 0.6, rough)
			if this == "freeform":
				# Chambers where its passages meet.
				for s: Array in strokes:
					_disc(cells, _to_cells(s[1], box), width * 0.9, rough)
			mids.append(box.get_center())
	# The shapes joined, one to the next: a tunnel across, then a shaft.
	for k in range(1, mids.size()):
		var a: Vector2i = mids[k - 1]
		var b: Vector2i = mids[k]
		var corner := Vector2i(b.x, a.y)
		_stroke(cells, a, corner, tall + 1, null)
		_stroke(cells, corner, b, tall + 1, null)
		if corner.y != b.y:
			uprights.append([corner, b, tall + 1])
	# Inside the room only, a wall left at its edge.
	var out: Dictionary = {}
	for c: Vector2i in cells:
		if not inside.has(c):
			continue
		var edge := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not inside.has(c + d):
				edge = true
				break
		if not edge:
			out[c] = true
	# The rough edges can leave specks of air apart in the rock: the cave alone.
	return {"cells": MDSAreaGenerator.largest_component(out), "uprights": uprights, "boxes": boxes, "kinds": kinds, "turns": turns}

## Ledges up the steep passages [param uprights] ([from, to, width] in cells, upright or
## slanted) of open [param cells]: half a passage wide, on alternate sides, every [param step]
## rows, following the passage; the top and bottom ones left open.
static func ladders(cells: Dictionary, uprights: Array, step: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for u: Array in uprights:
		var a: Vector2i = u[0]
		var b: Vector2i = u[1]
		var width: int = u[2]
		var top := mini(a.y, b.y)
		var bottom := maxi(a.y, b.y)
		if bottom - top + 1 <= step + 1:
			continue
		var half := maxi(1, width / 2)
		var left := true
		var y := bottom - step
		while y > top + 1:
			# Where the passage is on this row (a slanted one moves across).
			var t := float(y - a.y) / float(b.y - a.y) if b.y != a.y else 0.0
			var x0 := roundi(lerpf(a.x, b.x, t)) - width / 2
			for dx in half:
				var c := Vector2i(x0 + dx + (0 if left else width - half), y)
				if cells.has(c):
					out.append(c)
			left = not left
			y -= step
	return out

## A random freeform cave's strokes: a winding passage of four or five legs, in the 0..1 box.
static func freeform_strokes(rng: RandomNumberGenerator) -> Array:
	var points: Array[Vector2] = [Vector2(rng.randf_range(0.08, 0.3), rng.randf_range(0.15, 0.85))]
	var legs := rng.randi_range(4, 5)
	for k in legs:
		var last: Vector2 = points.back()
		# Mostly across, sometimes down or up: a cave a player can walk.
		var p := Vector2(clampf(last.x + rng.randf_range(0.12, 0.3), 0.06, 0.94), last.y) if k % 2 == 0 else Vector2(last.x, clampf(last.y + rng.randf_range(-0.55, 0.55), 0.1, 0.9))
		points.append(p)
	var out: Array = []
	for k in range(1, points.size()):
		out.append([points[k - 1], points[k]])
	return out

## [param strokes] (0..1 box) turned [param degrees] clockwise (any angle) round the box's
## middle (see [method _turned_points]).
static func _turned(strokes: Array, degrees: float) -> Array:
	var points: Array = []
	for s: Array in strokes:
		points.append(s[0])
		points.append(s[1])
	var turned := _turned_points(points, degrees)
	var out: Array = []
	for k in strokes.size():
		out.append([turned[k * 2], turned[k * 2 + 1]])
	return out

## [param points] (0..1 box) turned [param degrees] clockwise round its middle. Turned off the
## right angles, a shape reaches further (a square's corners at 45 degrees): it is made smaller as
## much, to stay in its box. Right angles turn it exactly.
static func _turned_points(points: Array, degrees: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var a := deg_to_rad(degrees)
	var c := cos(a)
	var s := sin(a)
	var k := 1.0 / maxf(absf(c) + absf(s), 1.0)
	for p: Vector2 in points:
		var o := p - Vector2(0.5, 0.5)
		var r := Vector2(o.x * c - o.y * s, o.x * s + o.y * c) * k
		out.append(Vector2(0.5, 0.5) + r.snapped(Vector2(0.000001, 0.000001)))
	return out

static func _to_cells(p: Vector2, box: Rect2i) -> Vector2i:
	return box.position + Vector2i((p * Vector2(box.size - Vector2i.ONE)).round())

## A passage [param width] cells across from [param a] to [param b], its sides roughened by
## [param noise] (none: straight).
static func _stroke(cells: Dictionary, a: Vector2i, b: Vector2i, width: int, noise: FastNoiseLite) -> void:
	var lo := a.min(b) - Vector2i(width, width)
	var hi := a.max(b) + Vector2i(width, width)
	var ab := Vector2(b - a)
	var len2 := maxf(ab.length_squared(), 0.0001)
	var half := width / 2.0
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var p := Vector2(x, y)
			var t := clampf((p - Vector2(a)).dot(ab) / len2, 0.0, 1.0)
			var d := p.distance_to(Vector2(a) + ab * t)
			var rough := noise.get_noise_2d(x, y) * half * 0.45 if noise else 0.0
			if d <= half + rough:
				cells[Vector2i(x, y)] = true

static func _disc(cells: Dictionary, at: Vector2i, r: float, noise: FastNoiseLite) -> void:
	var n := ceili(r) + 2
	for y in range(-n, n + 1):
		for x in range(-n, n + 1):
			var rough := noise.get_noise_2d(at.x + x, at.y + y) * r * 0.3 if noise else 0.0
			if Vector2(x, y).length() <= r + rough:
				cells[at + Vector2i(x, y)] = true
