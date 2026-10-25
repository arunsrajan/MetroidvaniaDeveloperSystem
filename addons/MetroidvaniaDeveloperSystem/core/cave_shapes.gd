@tool
class_name MDSCaveShapes
extends RefCounted
## Caves shaped like letters and figures: Generate cave carves the room's open space as one or
## more shapes (a T, a U, an H, an L, a cross, a ring, an S, a freeform cave), each turned as asked,
## with rough rock edges, instead of the cave it grows from the room's outline. The shapes are joined
## by tunnels; the tall parts get ledges on alternate sides to climb. Generate cave then opens the
## gates and joins them as for any cave (see [method MDSRoomPainter.generate_cave]).
## [codeblock]
## var fills := {"cave": {"shape": "u", "rotation": 90, "count": 2}}
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
}
## The shapes a picker lists, in order: [id, name]. "natural" is the cave grown from the room's
## outline (the shapes not used); "mixed" a shape picked at random for each.
const CHOICES := [
	["natural", "Natural (from the room's outline)"], ["t", "T"], ["u", "U"], ["h", "H"], ["l", "L"],
	["cross", "Cross (+)"], ["ring", "Ring (O)"], ["s", "S (switchbacks)"], ["freeform", "Freeform"], ["mixed", "Mixed"],
]
## Rotations a picker lists: degrees clockwise, -1 a random one for each shape.
const ROTATIONS := [[0, "0°"], [90, "90°"], [180, "180°"], [270, "270°"], [-1, "Random"]]

## Whether [param cave] (Generate cave's "cave" fill: {shape, rotation, count, width}) asks for
## shapes.
static func wanted(cave: Dictionary) -> bool:
	var kind := str(cave.get("shape", "natural"))
	return not kind.is_empty() and kind != "natural" and (STROKES.has(kind) or kind in ["freeform", "mixed"])

## The rock of a cave of shapes in [param inside] (a room's cells, in its box [param lo] to
## [param hi]): every cell of the box but the shapes'. [param cave]: {shape (an id of
## [constant STROKES], "freeform" or "mixed"), rotation (degrees, -1 random), count (shapes,
## 1 to 8), width (their passages', tiles; 0: from the room's size)}. [param tall]: the player's
## height in tiles (passages are never lower), [param step]: rows between ledges up the tall parts.
static func rock(inside: Dictionary, lo: Vector2i, hi: Vector2i, cave: Dictionary, rng: RandomNumberGenerator, tall := 4, step := 4) -> Dictionary:
	var solid: Dictionary = {}
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			solid[Vector2i(x, y)] = true
	var open := carve(inside, lo, hi, cave, rng, tall)
	for c in open.cells:
		solid.erase(c)
	for c in ladders(open.cells, open.uprights, step):
		solid[c] = true
	return solid

## The open cells of the shapes in [param inside] (see [method rock]): {cells, uprights (the
## vertical passages: [Rect2i] of cells), boxes (each shape's box)}.
static func carve(inside: Dictionary, lo: Vector2i, hi: Vector2i, cave: Dictionary, rng: RandomNumberGenerator, tall := 4) -> Dictionary:
	var count := clampi(int(cave.get("count", 1)), 1, 8)
	var kind := str(cave.get("shape", "t"))
	var rotation := int(cave.get("rotation", 0))
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
	var cells: Dictionary = {}
	var uprights: Array[Rect2i] = []
	var boxes: Array[Rect2i] = []
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
				var ids: Array = STROKES.keys()
				ids.append("freeform")
				this = ids[rng.randi_range(0, ids.size() - 1)]
			var turn: int = rotation if rotation >= 0 else [0, 90, 180, 270][rng.randi_range(0, 3)]
			var strokes := freeform_strokes(rng) if this == "freeform" else _turned(STROKES.get(this, STROKES.t), turn)
			for s: Array in strokes:
				var a := _to_cells(s[0], box)
				var b := _to_cells(s[1], box)
				_stroke(cells, a, b, width, noise)
				if absi(b.y - a.y) > absi(b.x - a.x):
					uprights.append(Rect2i(Vector2i(mini(a.x, b.x) - width / 2, mini(a.y, b.y)), Vector2i(width, absi(b.y - a.y) + 1)))
			if this == "freeform":
				# Chambers where its passages meet.
				for s: Array in strokes:
					_disc(cells, _to_cells(s[1], box), width * 0.9, noise)
			mids.append(box.get_center())
	# The shapes joined, one to the next: a tunnel across, then a shaft.
	for k in range(1, mids.size()):
		var a: Vector2i = mids[k - 1]
		var b: Vector2i = mids[k]
		var corner := Vector2i(b.x, a.y)
		_stroke(cells, a, corner, tall + 1, null)
		_stroke(cells, corner, b, tall + 1, null)
		if corner.y != b.y:
			uprights.append(Rect2i(Vector2i(corner.x - (tall + 1) / 2, mini(corner.y, b.y)), Vector2i(tall + 1, absi(b.y - corner.y) + 1)))
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
	return {"cells": MDSAreaGenerator.largest_component(out), "uprights": uprights, "boxes": boxes}

## Ledges up the vertical passages [param uprights] of open [param cells]: half a passage wide,
## on alternate sides, every [param step] rows, the top and bottom ones left open.
static func ladders(cells: Dictionary, uprights: Array[Rect2i], step: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in uprights:
		if r.size.y <= step + 1:
			continue
		var half := maxi(1, r.size.x / 2)
		var left := true
		var y := r.end.y - 1 - step
		while y > r.position.y + 1:
			for dx in half:
				var c := Vector2i(r.position.x + dx + (0 if left else r.size.x - half), y)
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

## [param strokes] (0..1 box) turned [param degrees] clockwise round the box's middle.
static func _turned(strokes: Array, degrees: int) -> Array:
	var out: Array = []
	for s: Array in strokes:
		out.append([_turn(s[0], degrees), _turn(s[1], degrees)])
	return out

static func _turn(p: Vector2, degrees: int) -> Vector2:
	match posmod(degrees, 360):
		90:
			return Vector2(1.0 - p.y, p.x)
		180:
			return Vector2(1.0 - p.x, 1.0 - p.y)
		270:
			return Vector2(p.y, 1.0 - p.x)
	return p

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
