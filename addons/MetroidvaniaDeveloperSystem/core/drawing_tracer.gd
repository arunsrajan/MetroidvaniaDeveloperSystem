@tool
class_name MDSDrawingTracer
extends RefCounted
## Trace drawing: turns a picture of a room (a sketch, a paint-over, a level drawing made in
## any paint program) into freeform shapes drawn with the freeform styles you pick.
##
## Each color of the drawing is a layer. Out of the box:
## - black, grey and brown: solid terrain;
## - red, orange and yellow: one-way platforms;
## - green: background;
## - blue and purple: foreground;
## - white and transparent: paper (nothing).
## The drawing is laid over the room's box on the map ([member target]), stretched or keeping
## its proportions. Rock that touches the drawing's edge runs on past the room's edge
## ([member bleed]), out of the camera's sight. Holes in a shape (a cave inside the rock) stay
## open: the shape is cut in two around them, since a freeform shape has no holes; the halves
## meet without an outline or rounded corners along the cut (see [MDSFreeform]'s mds_seams).
##
## Everything goes through an [MDSRoomPainter], so the Room view can undo it, and tools and
## CI can trace any room:
## [codeblock]
## var painter := MDSRoomPainter.open("res://rooms/cave_02.tscn")
## var tracer := MDSDrawingTracer.new()
## tracer.load_image("res://drawings/cave_02.png")
## tracer.target = Rect2(0, 0, 2304, 1296)
## tracer.styles[MDSDrawingTracer.Layer.TERRAIN] = load("res://styles/mossy_rock.freeform.tres")
## painter.checkpoint()
## print(tracer.apply(painter))
## painter.save()
## [/codeblock]

enum Layer { IGNORE, TERRAIN, PLATFORM, BACKGROUND, FOREGROUND }
const LAYER_NAMES: PackedStringArray = ["Nothing (paper)", "Terrain (solid)", "Platform (one-way)", "Background", "Foreground"]
## The freeform group (Room view layer) each layer's shapes go to.
const LAYER_GROUPS := {Layer.TERRAIN: "Freeform", Layer.PLATFORM: "Freeform", Layer.BACKGROUND: "FreeformBack", Layer.FOREGROUND: "FreeformFront"}
## Colors shown for the layers in previews.
const LAYER_COLORS := {Layer.IGNORE: Color(0, 0, 0, 0), Layer.TERRAIN: Color("#5d6b78"), Layer.PLATFORM: Color("#e8913a"), Layer.BACKGROUND: Color("#3f9a6a"), Layer.FOREGROUND: Color("#8a63d2")}
## Traced shapes carry this metadata, so tracing again can replace them.
const META := &"mds_traced"
## Colors closer than this (0..1, RGB distance) are one color.
const MERGE_DISTANCE := 0.2

# --- Options -----------------------------------------------------------------------------------

## The longest side the drawing is traced at (px). Bigger follows it more closely and is slower.
var resolution := 512
## The most colors told apart.
var max_colors := 8
## A color must cover this share of the drawing to be a layer of its own (smaller ones join
## the nearest color).
var min_share := 0.004
## The room-local rectangle the drawing covers (the room's box on the map).
var target := Rect2(0, 0, 1152, 648)
## Keep the drawing's proportions (fit inside [member target], centred) instead of stretching it.
var keep_aspect := false
## 0: smooth outlines with few points; 1: follows every wiggle of the drawing.
var detail := 0.5
## Shapes smaller than this across (px) are dropped as specks.
var min_size := 24.0
## Round the outlines through their points.
var smooth := true
## How far (px) shapes touching the drawing's edge run on past it.
var bleed := 64.0
## The style of each layer's shapes: Layer -> MDSFreeformStyle (missing: a built-in one).
var styles: Dictionary = {}

# --- The drawing -------------------------------------------------------------------------------

## The drawing as traced (scaled to [member resolution]).
var image: Image
## Its colors, most used first: [{color, share (0..1), layer}]. Change their layer (and set
## a "style" of their own, an MDSFreeformStyle) before [method trace] or [method apply].
var colors: Array = []
var _labels := PackedInt32Array() ## per pixel: index in colors, -1 transparent

## Loads the drawing from a file (res:// or anywhere on disk). Returns the error.
func load_image(path: String) -> Error:
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path)
	if err != OK:
		return err
	set_image(img)
	return OK

## Uses [param img] as the drawing (it is copied) and finds its colors.
func set_image(img: Image) -> void:
	image = img.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > resolution:
		var k := float(resolution) / longest
		image.resize(maxi(1, roundi(image.get_width() * k)), maxi(1, roundi(image.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	analyze()

## Finds the drawing's colors (see [member colors]) and gives each its default layer.
func analyze() -> void:
	colors.clear()
	_labels = PackedInt32Array()
	if not image or image.is_empty():
		return
	var data := image.get_data()
	var n := image.get_width() * image.get_height()
	# Pixels binned by 4 bits per channel.
	var counts := PackedInt32Array()
	counts.resize(4096)
	var opaque := 0
	for i in n:
		var o := i * 4
		if data[o + 3] < 128:
			continue
		counts[((data[o] >> 4) << 8) | ((data[o + 1] >> 4) << 4) | (data[o + 2] >> 4)] += 1
		opaque += 1
	var bins: Array = []
	for b in 4096:
		if counts[b] > 0:
			bins.append(b)
	bins.sort_custom(func(a: int, b: int) -> bool: return counts[a] > counts[b])
	# The most used bins become colors; the others join them. A bin between two colors is the
	# soft edge between them (anti-aliasing), not a color of its own.
	var centers: Array[Color] = []
	var weights: Array[int] = []
	var min_count := maxi(1, int(opaque * min_share))
	for b in bins:
		var c := _bin_color(b)
		var best := -1
		var best_d := MERGE_DISTANCE
		for k in centers.size():
			var d := _distance(c, centers[k])
			if d < best_d:
				best_d = d
				best = k
		if best >= 0:
			centers[best] = centers[best].lerp(c, float(counts[b]) / (weights[best] + counts[b]))
			weights[best] += counts[b]
		elif counts[b] >= min_count and centers.size() < max_colors and not _is_blend(c, centers):
			centers.append(c)
			weights.append(counts[b])
	if centers.is_empty():
		return
	var bin_label := PackedInt32Array()
	bin_label.resize(4096)
	for b in bins:
		bin_label[b] = _label_for(_bin_color(b), centers)
	var share := PackedInt32Array()
	share.resize(centers.size())
	_labels.resize(n)
	for i in n:
		var o := i * 4
		if data[o + 3] < 128:
			_labels[i] = -1
			continue
		var l := bin_label[((data[o] >> 4) << 8) | ((data[o + 1] >> 4) << 4) | (data[o + 2] >> 4)]
		_labels[i] = l
		share[l] += 1
	for k in centers.size():
		colors.append({"color": centers[k], "share": float(share[k]) / n, "layer": default_layer(centers[k])})
	# Most used first (the labels follow).
	var order: Array = range(colors.size())
	order.sort_custom(func(a: int, b: int) -> bool: return colors[a].share > colors[b].share)
	var remap := PackedInt32Array()
	remap.resize(colors.size())
	var sorted: Array = []
	for k in order.size():
		remap[order[k]] = k
		sorted.append(colors[order[k]])
	colors = sorted
	for i in n:
		if _labels[i] >= 0:
			_labels[i] = remap[_labels[i]]

static func _bin_color(b: int) -> Color:
	return Color((((b >> 8) & 15) * 16 + 8) / 255.0, (((b >> 4) & 15) * 16 + 8) / 255.0, ((b & 15) * 16 + 8) / 255.0)

static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

static func _nearest(c: Color, centers: Array[Color]) -> int:
	var best := 0
	for k in range(1, centers.size()):
		if _distance(c, centers[k]) < _distance(c, centers[best]):
			best = k
	return best

## The color [param c] belongs to: the nearest one, unless it lies between two colors (a soft
## edge, grey between black and white): then the nearer of those two, whatever color happens
## to be closer to the blend.
static func _label_for(c: Color, centers: Array[Color]) -> int:
	var near := _nearest(c, centers)
	var direct := _distance(c, centers[near])
	if direct < MERGE_DISTANCE:
		return near
	var p := Vector3(c.r, c.g, c.b)
	var best := -1
	var best_d := minf(direct, MERGE_DISTANCE * 0.8)
	for i in centers.size():
		for j in range(i + 1, centers.size()):
			var a := Vector3(centers[i].r, centers[i].g, centers[i].b)
			var ab := Vector3(centers[j].r, centers[j].g, centers[j].b) - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := (a + ab * t).distance_to(p)
			if d < best_d:
				best_d = d
				best = i if t < 0.5 else j
	return best if best >= 0 else near

## Whether [param c] lies between two of [param centers] (a soft edge between them).
static func _is_blend(c: Color, centers: Array[Color]) -> bool:
	var p := Vector3(c.r, c.g, c.b)
	for i in centers.size():
		for j in range(i + 1, centers.size()):
			var a := Vector3(centers[i].r, centers[i].g, centers[i].b)
			var b := Vector3(centers[j].r, centers[j].g, centers[j].b)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if (a + ab * t).distance_to(p) < MERGE_DISTANCE * 0.6:
				return true
	return false

## The layer a color gets by default (see the class description).
static func default_layer(c: Color) -> Layer:
	if c.v > 0.85 and c.s < 0.18:
		return Layer.IGNORE
	if c.s < 0.25 or c.v < 0.3:
		return Layer.TERRAIN
	var hue := c.h * 360.0
	if hue >= 15.0 and hue < 50.0 and c.v < 0.62:
		return Layer.TERRAIN # brown
	if hue < 70.0 or hue >= 330.0:
		return Layer.PLATFORM
	if hue < 170.0:
		return Layer.BACKGROUND
	return Layer.FOREGROUND

## The drawing in its layers' colors (paper transparent): what [method trace] will see.
func layer_preview() -> Image:
	if not image:
		return null
	var w := image.get_width()
	var h := image.get_height()
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in _labels.size():
		var l := _labels[i]
		if l < 0:
			continue
		var c: Color = LAYER_COLORS[colors[l].layer]
		data[i * 4] = c.r8
		data[i * 4 + 1] = c.g8
		data[i * 4 + 2] = c.b8
		data[i * 4 + 3] = c.a8
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)

# --- Tracing -----------------------------------------------------------------------------------

## From the traced image's pixels to [member target].
func image_to_target() -> Transform2D:
	var isz := Vector2(image.get_size())
	var k := target.size / isz
	var off := target.position
	if keep_aspect:
		var s := minf(k.x, k.y)
		k = Vector2(s, s)
		off = target.position + (target.size - isz * s) * 0.5
	return Transform2D(Vector2(k.x, 0.0), Vector2(0.0, k.y), off)

## The shapes the drawing makes, in [member target]'s coordinates:
## [{layer, color (index in colors), points, smooth, seams}], largest first within each
## color (seams: x of the cuts the shape meets another along).
func trace() -> Array:
	var out: Array = []
	if not image or _labels.is_empty():
		return out
	var w := image.get_width()
	var h := image.get_height()
	var xform := image_to_target()
	var drawn := Rect2(xform.origin, Vector2(w, h) * xform.get_scale())
	# One pass builds every color's mask and its inverse, padded by a pixel of paper.
	var masks: Array[BitMap] = []
	var inverse: Array[BitMap] = []
	var used := PackedByteArray()
	used.resize(colors.size())
	for k in colors.size():
		var bm := BitMap.new()
		bm.create(Vector2i(w + 2, h + 2))
		masks.append(bm)
		var inv := BitMap.new()
		inv.create(Vector2i(w + 2, h + 2))
		if colors[k].layer != Layer.IGNORE:
			inv.set_bit_rect(Rect2i(0, 0, w + 2, h + 2), true)
		inverse.append(inv)
	for y in h:
		for x in w:
			var l := _labels[y * w + x]
			if l >= 0 and colors[l].layer != Layer.IGNORE:
				masks[l].set_bit(x + 1, y + 1, true)
				inverse[l].set_bit(x + 1, y + 1, false)
				used[l] = 1
	var all := Rect2i(0, 0, w + 2, h + 2)
	var eps := lerpf(2.0, 0.7, detail)
	var tolerance := lerpf(9.0, 1.5, detail) * maxf(xform.get_scale().x, xform.get_scale().y) * 0.5
	for k in colors.size():
		if used[k] == 0:
			continue
		var parts: Array[PackedVector2Array] = []
		for poly: PackedVector2Array in masks[k].opaque_to_polygons(all, eps):
			parts.append(_place(poly, xform, w, h, drawn))
		# Paper enclosed by the color: holes (what touches the padding is the outside).
		for poly: PackedVector2Array in inverse[k].opaque_to_polygons(all, eps):
			var b := MDSGeometry.bounds(poly)
			if b.position.x > 0.5 and b.position.y > 0.5 and b.end.x < w + 1.5 and b.end.y < h + 1.5:
				parts.append(_place(poly, xform, w, h, drawn))
		var min_area := min_size * min_size * 0.5
		var pieces := MDSGeometry.without_holes(parts, min_area)
		pieces.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
			return absf(MDSGeometry.signed_area(a)) > absf(MDSGeometry.signed_area(b)))
		var cuts := seam_lines(pieces)
		for piece in pieces:
			var seams := PackedFloat32Array()
			for x in cuts:
				if _has_vertical_edge(piece, x):
					seams.append(x)
			var simple := MDSGeometry.simplify_closed(piece, tolerance)
			if smooth:
				# Rounded through sparse corners, long straight edges would bow: points along
				# them keep the curve on the drawing, rounding only the corners. Where the shape
				# meets its other half along a cut, the corners stay sharp.
				simple = sharpen_at(densify(simple, maxf(tolerance * 4.0, 24.0)), seams)
			for part in MDSFreeform.repair_points(simple, smooth):
				var pts: PackedVector2Array = part.points
				var bb := MDSGeometry.bounds(pts)
				if pts.size() >= 3 and maxf(bb.size.x, bb.size.y) >= min_size and absf(MDSGeometry.signed_area(pts)) >= min_area:
					out.append({"layer": colors[k].layer, "color": k, "points": pts, "smooth": part.smooth, "seams": seams})
	return out

## The x of the vertical lines along which two of [param pieces] meet (where a shape was cut
## around a hole).
static func seam_lines(pieces: Array[PackedVector2Array]) -> PackedFloat32Array:
	var by_x: Dictionary = {} # snapped x -> [[piece, y0, y1], ...]
	for k in pieces.size():
		var poly := pieces[k]
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if absf(a.x - b.x) < 0.01 and absf(a.y - b.y) > 0.5:
				var key := snappedf(a.x, 0.01)
				if not by_x.has(key):
					by_x[key] = []
				by_x[key].append([k, minf(a.y, b.y), maxf(a.y, b.y)])
	var out := PackedFloat32Array()
	for key in by_x:
		var edges: Array = by_x[key]
		var found := false
		for i in edges.size():
			for j in range(i + 1, edges.size()):
				if edges[i][0] != edges[j][0] and minf(edges[i][2], edges[j][2]) - maxf(edges[i][1], edges[j][1]) > 1.0:
					found = true
					break
			if found:
				break
		if found:
			out.append(key)
	return out

static func _has_vertical_edge(poly: PackedVector2Array, x: float) -> bool:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if absf(a.x - x) < 0.01 and absf(b.x - x) < 0.01 and absf(a.y - b.y) > 0.5:
			return true
	return false

## [param poly] with points 2 px either side of each corner where it leaves a seam (a vertical
## line of [param seams]), so rounding the outline leaves those corners sharp and the two
## halves of a cut shape meet without a notch.
static func sharpen_at(poly: PackedVector2Array, seams: PackedFloat32Array) -> PackedVector2Array:
	if seams.is_empty():
		return poly
	var on_seam := func(p: Vector2) -> float:
		for x in seams:
			if absf(p.x - x) < 0.5:
				return x
		return NAN
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var prev := poly[(i - 1 + n) % n]
		var p := poly[i]
		var next := poly[(i + 1) % n]
		var x: float = on_seam.call(p)
		if is_nan(x):
			out.append(p)
			continue
		var from_seam := absf(prev.x - x) < 0.5
		var to_seam := absf(next.x - x) < 0.5
		if from_seam == to_seam:
			out.append(p)
			continue
		if p.distance_to(prev) > 4.0:
			out.append(p.move_toward(prev, 2.0))
		out.append(p)
		if p.distance_to(next) > 4.0:
			out.append(p.move_toward(next, 2.0))
	return out

## [param poly] with points added along edges longer than [param step] px.
static func densify(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		out.append(a)
		var pieces := int(ceil(a.distance_to(b) / maxf(step, 1.0)))
		for k in range(1, pieces):
			out.append(a.lerp(b, float(k) / pieces))
	return out

## A traced outline (padded pixels) in target coordinates; points on the drawing's edge run
## on [member bleed] px past it.
func _place(poly: PackedVector2Array, xform: Transform2D, w: int, h: int, drawn: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		var p := v - Vector2.ONE
		var q := xform * p
		if bleed > 0.0:
			if p.x <= 0.01:
				q.x = drawn.position.x - bleed
			elif p.x >= w - 0.01:
				q.x = drawn.end.x + bleed
			if p.y <= 0.01:
				q.y = drawn.position.y - bleed
			elif p.y >= h - 0.01:
				q.y = drawn.end.y + bleed
		out.append(q)
	return MDSGeometry.dedupe(out)

## The style shapes of [param layer] get: the color's own (colors[i].style, with
## [param color_index]), else [member styles], else a built-in one.
func style_for(layer: Layer, color_index := -1) -> MDSFreeformStyle:
	if color_index >= 0 and color_index < colors.size() and colors[color_index].get("style") is MDSFreeformStyle:
		return colors[color_index].style
	var st: MDSFreeformStyle = styles.get(layer)
	if st:
		return st
	var builtins := MDSFreeformStyle.builtins()
	match layer:
		Layer.BACKGROUND:
			return builtins[1]
		Layer.FOREGROUND:
			return builtins[2]
		Layer.PLATFORM:
			var rock: MDSFreeformStyle = styles.get(Layer.TERRAIN)
			return rock if rock else builtins[0]
	return builtins[0]

## Traces the drawing into the room [param painter] edits (call
## [method MDSRoomPainter.checkpoint] first). With [param replace], shapes an earlier trace made
## are removed first. Returns {terrain, platform, background, foreground, removed}.
func apply(painter: MDSRoomPainter, replace := true) -> Dictionary:
	var report := {"terrain": 0, "platform": 0, "background": 0, "foreground": 0, "removed": 0}
	if replace:
		for g in ["Freeform", "FreeformBack", "FreeformFront"]:
			for item in painter.items(g):
				if item.has_meta(META):
					painter.remove_item(item)
					report.removed += 1
	var keys := {Layer.TERRAIN: "terrain", Layer.PLATFORM: "platform", Layer.BACKGROUND: "background", Layer.FOREGROUND: "foreground"}
	for s in trace():
		var layer: Layer = s.layer
		var st := style_for(layer, s.color)
		var solid := layer == Layer.TERRAIN or layer == Layer.PLATFORM
		var f := painter.add_freeform(s.points, st, LAYER_GROUPS[layer], solid)
		f.smooth = s.smooth
		f.name = "Traced%s%d" % [str(keys[layer]).capitalize(), report[keys[layer]] + 1]
		match layer:
			Layer.PLATFORM:
				f.set_collision_override(MDSFreeformStyle.Role.PLATFORM, true)
			Layer.TERRAIN:
				if st.get_role() != MDSFreeformStyle.Role.TERRAIN or st.is_one_way():
					f.set_collision_override(MDSFreeformStyle.Role.TERRAIN, false)
		f.set_meta(META, true)
		if not (s.seams as PackedFloat32Array).is_empty():
			f.set_meta(&"mds_seams", s.seams)
		report[keys[layer]] += 1
	return report
