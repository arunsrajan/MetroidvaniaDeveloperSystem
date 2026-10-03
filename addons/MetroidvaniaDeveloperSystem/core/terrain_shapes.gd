@tool
class_name IDPTerrainShapes
extends RefCounted
## Shape brushes for the Room view: the cells of a dragged rectangle filled as a plain
## block, an irregular rock blob, or a mass with one curved side (floor hills, bowls,
## ramps, quarter-pipes, overhanging ceilings, curved walls...).
##
## A curved side is the free face of the shape; the opposite side is its flat base:
## "Top curved" is ground whose surface follows the curve, "Bottom curved" hangs from a
## ceiling, "Left curved" sticks out of a wall on the right, "Right curved" out of a wall on
## the left. Convex bulges out of the base, concave dips into it.

enum Shape { BRUSH, RECT, IRREGULAR, LEFT, RIGHT, TOP, BOTTOM }
const SHAPE_NAMES: PackedStringArray = ["Brush", "Rectangle", "Irregular", "Left curved", "Right curved", "Top curved", "Bottom curved"]
const SHAPE_TIPS: PackedStringArray = [
	"Freehand brush",
	"Drag a rectangle to fill",
	"Drag a box: an organic rock blob that fills it (Irregular % sets how rough)",
	"Drag a box: a mass attached on the right whose left face follows the curve",
	"Drag a box: a mass attached on the left whose right face follows the curve",
	"Drag a box: ground whose surface follows the curve (hills, bowls, ramps)",
	"Drag a box: a ceiling mass whose underside follows the curve (arches, overhangs)",
]

enum CurveType { CONVEX, CONCAVE, SLOPE, ROUNDED, QUARTER_PIPE, S_CURVE, HILL, MESA, WAVE, STEPS, SPIKES }
const CURVE_NAMES: PackedStringArray = [
	"Convex (dome)", "Concave (bowl)", "Slope (straight ramp)", "Rounded corner (convex ramp)",
	"Quarter-pipe (concave ramp)", "S-curve (eased ramp)", "Hill (bell)", "Mesa (flat top)",
	"Rolling hills (wave)", "Steps (stairs)", "Spikes (stalagmites)",
]

## Height of the curved face (0 = at the base, 1 = the far side of the box) at [param t]
## (0..1 along the face).
static func profile(curve: int, t: float, count := 3) -> float:
	t = clampf(t, 0.0, 1.0)
	match curve:
		CurveType.CONVEX:
			return sqrt(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 2)))
		CurveType.CONCAVE:
			return 1.0 - sqrt(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 2)))
		CurveType.SLOPE:
			return t
		CurveType.ROUNDED:
			return sqrt(maxf(0.0, 1.0 - pow(1.0 - t, 2)))
		CurveType.QUARTER_PIPE:
			return 1.0 - sqrt(maxf(0.0, 1.0 - t * t))
		CurveType.S_CURVE:
			return t * t * (3.0 - 2.0 * t)
		CurveType.HILL:
			return exp(-pow((t - 0.5) * 4.0, 2))
		CurveType.MESA:
			var e := clampf(minf(t, 1.0 - t) * 4.0, 0.0, 1.0)
			return e * e * (3.0 - 2.0 * e)
		CurveType.WAVE:
			return 0.5 - 0.5 * cos(TAU * maxi(1, count) * t)
		CurveType.STEPS:
			var n := maxi(2, count)
			return minf(1.0, (floorf(t * n) + 1.0) / n)
		CurveType.SPIKES:
			var n := maxi(1, count * 2)
			var f := fposmod(t * n, 1.0)
			return 1.0 - absf(2.0 * f - 1.0)
	return 1.0

static func is_curved(shape: int) -> bool:
	return shape >= Shape.LEFT

## Cells of [param shape] in the box spanned by cells [param a] and [param b].
## [param rough] (0..1) makes the face irregular; [param mirror] flips the curve along the
## face; [param count] is the number of waves, steps or spikes.
static func cells(shape: int, a: Vector2i, b: Vector2i, curve := CurveType.CONVEX, rough := 0.0, mirror := false, seed_value := 0, count := 3) -> Array[Vector2i]:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var size := hi - lo + Vector2i.ONE
	var out: Array[Vector2i] = []
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3
	match shape:
		Shape.RECT, Shape.BRUSH:
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					out.append(Vector2i(x, y))
		Shape.IRREGULAR:
			var amount := rough if rough > 0.0 else 0.35
			var center := (Vector2(lo) + Vector2(hi)) / 2.0
			var radius := Vector2(size) / 2.0
			noise.frequency = 1.6
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var d := (Vector2(x, y) - center) / radius
					var angle := d.angle()
					# Noise sampled on a circle so the outline closes seamlessly.
					var n := noise.get_noise_2d(cos(angle), sin(angle))
					var jitter := noise.get_noise_2d(x * 0.9 + 100.0, y * 0.9) * 0.25
					if d.length() <= 1.0 + amount * (n * 0.9 + jitter) - amount * 0.25:
						out.append(Vector2i(x, y))
		_:
			var horizontal := shape == Shape.TOP or shape == Shape.BOTTOM # the face runs along x
			var along := size.x if horizontal else size.y
			var depth := size.y if horizontal else size.x
			noise.frequency = 3.0 / maxf(8.0, float(along))
			for i in along:
				# Ends inclusive, so ramps and bowls reach the full height at the box edges.
				var t := float(i) / (along - 1) if along > 1 else 0.5
				if mirror:
					t = 1.0 - t
				var f := profile(curve, t, count)
				if rough > 0.0:
					f += rough * 0.35 * noise.get_noise_1d(i * 3.0)
					f += rough * 0.12 * (noise.get_noise_1d(i * 37.0 + 500.0))
				# Always at least one cell deep, so the shape stays attached to its base.
				var d := clampi(roundi(f * depth), 1, depth)
				for k in d:
					match shape:
						Shape.TOP:
							out.append(Vector2i(lo.x + i, hi.y - k))
						Shape.BOTTOM:
							out.append(Vector2i(lo.x + i, lo.y + k))
						Shape.LEFT:
							out.append(Vector2i(hi.x - k, lo.y + i))
						Shape.RIGHT:
							out.append(Vector2i(lo.x + k, lo.y + i))
	return out
