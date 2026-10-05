@tool
class_name IDPShapeGenerators
extends RefCounted
## Scenery outlines made from a few parameters, for freeform shapes: ruins and rock that stand
## on a floor (column, broken arch, garden wall, mound) or hang from a ceiling (stalactite
## curtain). Each fills a box: standing ones stand on its bottom edge (and reach a little
## below it, hidden by the floor), hanging ones hang from its top edge. Used by Decorate
## freeform and the Freeform tool's Shape list. No editor dependencies.

enum Kind { COLUMN, ARCH, GARDEN_WALL, MOUND, STALACTITES }
const NAMES: PackedStringArray = ["Column", "Arch (broken)", "Garden wall", "Mound", "Stalactite curtain"]
const TIPS: PackedStringArray = [
	"A broken column: plinth, a slightly swelling shaft, a jagged break at the top",
	"A ruined arch: one pier standing, the arch broken off partway over, the stump of the far pier",
	"A low, overgrown garden wall",
	"A low rounded mound of rock or earth",
	"A row of stalactites hanging from a ceiling",
]
## Kinds that stand on a floor (the others hang from a ceiling).
const STANDING: Array[int] = [Kind.COLUMN, Kind.ARCH, Kind.GARDEN_WALL, Kind.MOUND]
## A good width for each kind, px.
const WIDTHS: PackedFloat32Array = [110.0, 380.0, 300.0, 260.0, 320.0]

static func is_standing(kind: int) -> bool:
	return kind in STANDING

## The outline of [param kind] filling [param box]: {points, smooth}. Points are in the box's
## space (absolute). The outline is simple (see [method IDPGeometry.is_simple]); a few random
## variations are tried, then a plainer one.
static func make(kind: int, box: Rect2, rng: RandomNumberGenerator) -> Dictionary:
	for attempt in 6:
		var d := _make(kind, box, rng, attempt >= 4)
		if d.points.size() >= 3 and IDPGeometry.is_simple(IDPFreeform.outline_of(d.points, d.smooth)):
			return d
	var plain := _make(kind, box, rng, true)
	plain.smooth = false
	return plain

static func _make(kind: int, box: Rect2, rng: RandomNumberGenerator, calm: bool) -> Dictionary:
	var x := box.get_center().x
	var floor_y := box.end.y
	var w := box.size.x
	var h := box.size.y
	match kind:
		Kind.COLUMN:
			return {"points": _column(x, floor_y, w, h, rng, calm), "smooth": false}
		Kind.ARCH:
			return {"points": _arch(x, floor_y, w, h, rng, calm), "smooth": false}
		Kind.GARDEN_WALL:
			return {"points": _garden_wall(x, floor_y, w, h, rng, calm), "smooth": true}
		Kind.MOUND:
			return {"points": _mound(x, floor_y, w, h, rng, calm), "smooth": true}
		_:
			return {"points": _stalactites(box, rng, calm), "smooth": false}

## A broken column: plinth, a slightly swelling shaft, a jagged break where its top fell.
static func _column(x: float, floor_y: float, w: float, h: float, rng: RandomNumberGenerator, calm: bool) -> PackedVector2Array:
	var hw := w * 0.5
	var top := floor_y - h
	var pts := PackedVector2Array([
		Vector2(x - hw - 10.0, floor_y + 30.0), Vector2(x - hw - 10.0, floor_y - 14.0), Vector2(x - hw + 2.0, floor_y - 26.0),
		Vector2(x - hw + 4.0, floor_y - h * 0.5), Vector2(x - hw + 7.0, top + 26.0)])
	var jag := rng.randi_range(3, 5)
	for j in range(jag + 1):
		var t := float(j) / jag
		var dip := 0.0 if j % 2 or calm else rng.randf_range(14.0, 46.0)
		pts.append(Vector2(lerpf(x - hw + 7.0, x + hw - 7.0, t), top + dip + (0.0 if calm else rng.randf_range(-8.0, 8.0))))
	pts.append_array([Vector2(x + hw - 4.0, floor_y - h * 0.5), Vector2(x + hw - 2.0, floor_y - 26.0),
		Vector2(x + hw + 10.0, floor_y - 14.0), Vector2(x + hw + 10.0, floor_y + 30.0)])
	return pts

## A ruined arch: one pier standing, the arch springing from it and broken off partway over,
## with the stump of the far pier. Under the floor line the outline closes the gap.
static func _arch(x: float, floor_y: float, w: float, h: float, rng: RandomNumberGenerator, calm: bool) -> PackedVector2Array:
	var pier := clampf(w * 0.14, 30.0, 54.0)
	var left := x - w * 0.5
	var right := x + w * 0.5
	var radius := (w - pier) * 0.5
	var centre := Vector2(left + pier * 0.5 + radius, floor_y - maxf(h - radius - pier * 0.5, 80.0))
	var outer := radius + pier * 0.5
	var inner := radius - pier * 0.5
	var broken := (0.65 if calm else rng.randf_range(0.55, 0.8)) * PI
	var pts := PackedVector2Array([Vector2(left - 6.0, floor_y + 40.0), Vector2(left - 6.0, centre.y)])
	var steps := 12
	for j in range(steps + 1):
		var a := PI + broken * float(j) / steps
		pts.append(centre + Vector2(cos(a), sin(a)) * outer)
	var a_end := PI + broken
	pts.append(centre + Vector2(cos(a_end + 0.05), sin(a_end + 0.05)) * (outer + inner) * 0.5 + Vector2(0, 14.0))
	for j in range(steps, -1, -1):
		var a := PI + broken * float(j) / steps
		pts.append(centre + Vector2(cos(a), sin(a)) * inner)
	pts.append(Vector2(left + pier + 4.0, floor_y + 12.0))
	var stump := minf(h * 0.4, 120.0)
	pts.append_array([Vector2(right - pier - 4.0, floor_y + 12.0), Vector2(right - pier, floor_y - stump * (0.5 if calm else rng.randf_range(0.4, 1.0))),
		Vector2(right - pier * 0.4, floor_y - stump * (0.8 if calm else rng.randf_range(0.7, 1.2))), Vector2(right + 6.0, floor_y - stump * (0.5 if calm else rng.randf_range(0.3, 0.9))),
		Vector2(right + 6.0, floor_y + 40.0)])
	return pts

## A low, overgrown garden wall.
static func _garden_wall(x: float, floor_y: float, w: float, h: float, rng: RandomNumberGenerator, calm: bool) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(x - w * 0.5, floor_y + 30.0)])
	var k := 6
	for j in range(k + 1):
		var t := float(j) / k
		var lift := sin(t * PI)
		pts.append(Vector2(lerpf(x - w * 0.5, x + w * 0.5, t), floor_y - h * (0.35 + 0.65 * lift) + (0.0 if calm else rng.randf_range(-10.0, 10.0))))
	pts.append(Vector2(x + w * 0.5, floor_y + 30.0))
	return pts

## A low rounded mound, a little lopsided.
static func _mound(x: float, floor_y: float, w: float, h: float, rng: RandomNumberGenerator, calm: bool) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(x - w * 0.5, floor_y + 24.0)])
	var k := 7
	var lean := 0.0 if calm else rng.randf_range(-0.12, 0.12)
	for j in range(k + 1):
		var t := float(j) / k
		var bump := pow(sin(t * PI), 0.8)
		pts.append(Vector2(lerpf(x - w * 0.5, x + w * 0.5, t) + lean * w * bump * 0.2, floor_y - h * bump + (0.0 if calm else rng.randf_range(-6.0, 6.0))))
	pts.append(Vector2(x + w * 0.5, floor_y + 24.0))
	return pts

## A strip under a ceiling with stalactites of mixed lengths hanging from it.
static func _stalactites(box: Rect2, rng: RandomNumberGenerator, calm: bool) -> PackedVector2Array:
	var top := box.position.y
	var pts := PackedVector2Array([Vector2(box.end.x, top - 30.0), Vector2(box.position.x, top - 30.0), Vector2(box.position.x, top + 6.0)])
	var x := box.position.x
	var spike := 0
	while x < box.end.x - 20.0:
		var half := clampf(box.size.x / 14.0, 10.0, 28.0) * (1.0 if calm else rng.randf_range(0.6, 1.2))
		if x + half * 2.0 > box.end.x:
			break
		var length := box.size.y * ((0.6 if spike % 2 == 0 else 0.35) if calm else rng.randf_range(0.25, 1.0))
		pts.append(Vector2(x + half * 0.15, top + 6.0))
		pts.append(Vector2(x + half, top + maxf(length, 16.0)))
		pts.append(Vector2(x + half * 1.85, top + 6.0))
		x += half * 2.0 + (4.0 if calm else rng.randf_range(0.0, 14.0))
		spike += 1
	pts.append(Vector2(box.end.x, top + 6.0))
	return pts
