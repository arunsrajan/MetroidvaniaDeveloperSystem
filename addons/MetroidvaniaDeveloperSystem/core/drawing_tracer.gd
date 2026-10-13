@tool
class_name MDSDrawingTracer
extends RefCounted
## Trace drawing: turns a picture of a room (a sketch, a paint-over, a level drawing made in
## any paint program) into the room's terrain, background and foreground. [member output] says
## how it is drawn:
## - freeform shapes in the freeform styles you pick (the default);
## - freeform shapes filled with solid colors (the drawing's own colors, or ones you pick);
## - tiles: each color paints the room's tile grid with a fill (a terrain, tiles of a kind,
##   palette tiles from a spritesheet, or a solid color);
## - the drawing itself, kept as it is drawn ([MDSDrawing]), its paper cut out; its terrain and
##   platforms can get invisible freeform shapes to collide with, like CollisionPolygon2D.
##
## Each color of the drawing is a layer. Out of the box:
## - black, grey and brown: solid terrain;
## - red, orange and yellow: one-way platforms;
## - green: background;
## - blue and purple: foreground;
## - white and transparent: paper (nothing).
## The drawing is laid over the room's box on the map ([member target]), stretched or keeping
## its proportions; with [member crop] (the default), only what is drawn counts: the paper
## around it is cut off, so the drawing fills the room's width and height. Without white or
## transparent paper, the color filling most of the picture's border is taken as the paper. Rock that touches the drawing's edge runs on past the room's edge
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
## # Or tiles, solid colors, or the drawing itself: tracer.output = MDSDrawingTracer.Output.TILES
## painter.checkpoint()
## print(tracer.apply(painter))
## painter.save()
## [/codeblock]

enum Layer { IGNORE, TERRAIN, PLATFORM, BACKGROUND, FOREGROUND }
const LAYER_NAMES: PackedStringArray = ["Nothing (paper)", "Terrain (solid)", "Platform (one-way)", "Background", "Foreground"]
## How the drawing goes into the room:
## - [code]STYLES[/code]: freeform shapes, in the style picked for each color ("style");
## - [code]COLORS[/code]: freeform shapes filled with a solid color: each color's
##   "fill_color", else its own;
## - [code]TILES[/code]: the room's tile grid, each color painted with its "fill" (see
##   [method MDSRoomPainter.paint_fill]: a terrain, tiles of a kind, palette tiles or a solid
##   color), else with tiles of its own color;
## - [code]PICTURE[/code]: the drawing itself, as it is drawn: a picture ([MDSDrawing]) at each
##   depth (behind the terrain, at its depth, in front) keeping that layer's colors, the paper cut
##   out ([member cut_paper]); with [member collision], its terrain and platforms get invisible
##   freeform shapes to collide with.
enum Output { STYLES, COLORS, TILES, PICTURE }
const OUTPUT_NAMES: PackedStringArray = ["Freeform styles", "Solid colors", "Tiles (spritesheets, terrains)", "The drawing itself"]
## The freeform group (Room view layer) each layer's shapes go to.
const LAYER_GROUPS := {Layer.TERRAIN: "Freeform", Layer.PLATFORM: "Freeform", Layer.BACKGROUND: "FreeformBack", Layer.FOREGROUND: "FreeformFront"}
## The tile layer each layer's tiles go to ([code]TILES[/code]), and the depth of its picture
## ([code]PICTURE[/code]).
const LAYER_TILES := {Layer.TERRAIN: "Terrain", Layer.PLATFORM: "Terrain", Layer.BACKGROUND: "Background", Layer.FOREGROUND: "Foreground"}
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
## Fit what is drawn (everything that isn't paper) to [member target], cutting off the paper
## around it, instead of the whole picture.
var crop := true
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
## How the drawing goes into the room (see [enum Output]).
var output := Output.STYLES
## [code]PICTURE[/code]: give the drawing's terrain and platforms invisible freeform shapes to
## collide with (one-way for platforms).
var collision := true
## [code]PICTURE[/code]: make the paper (colors set to Nothing) transparent.
var cut_paper := true
## [code]PICTURE[/code]: where a drawing that is not in the project is copied (a PNG), so the
## room's scene can link to it. Empty: next to the room's scene ([code]<room>_drawing.png[/code]).
var picture_path := ""

# --- The drawing -------------------------------------------------------------------------------

## The drawing as traced (scaled to [member resolution]).
var image: Image
## The drawing at its own size ([code]PICTURE[/code] shows it).
var original: Image
## The file it was loaded from ("" when set with [method set_image]).
var source_path := ""
## Its colors, most used first: [{color, share (0..1), layer}]. Change their layer (and set
## a "style" of their own, an MDSFreeformStyle; a "fill_color"; a tile "fill") before
## [method trace] or [method apply].
var colors: Array = []
var _labels := PackedInt32Array() ## per pixel: index in colors, -1 transparent
var _content_key := ""
var _content := Rect2i()

## Loads the drawing from a file (res:// or anywhere on disk). Returns the error.
func load_image(path: String) -> Error:
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path)
	if err != OK:
		return err
	set_image(img)
	source_path = path
	return OK

## Uses [param img] as the drawing (it is copied) and finds its colors.
func set_image(img: Image) -> void:
	source_path = ""
	original = img.duplicate() as Image
	if original.is_compressed():
		original.decompress()
	original.convert(Image.FORMAT_RGBA8)
	image = original.duplicate() as Image
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
	# Candidates come from coarser bins (3 bits per channel), each the mean of the fine bins in
	# it: the shades of one color (a gradient, a glow) add up to one candidate instead of many
	# too small to count.
	var coarse_count := PackedInt32Array()
	coarse_count.resize(512)
	var coarse_sum: Array[Vector3] = []
	coarse_sum.resize(512)
	coarse_sum.fill(Vector3.ZERO)
	for b in bins:
		var cb: int = (((b >> 9) & 7) << 6) | (((b >> 5) & 7) << 3) | ((b >> 1) & 7)
		var c := _bin_color(b)
		coarse_count[cb] += counts[b]
		coarse_sum[cb] += Vector3(c.r, c.g, c.b) * counts[b]
	var coarse: Array = []
	for cb in 512:
		if coarse_count[cb] > 0:
			coarse.append(cb)
	coarse.sort_custom(func(a: int, b: int) -> bool: return coarse_count[a] > coarse_count[b])
	# The most used become colors; the others join them. A candidate between two colors is the
	# soft edge between them (anti-aliasing), not a color of its own.
	var centers: Array[Color] = []
	var weights: Array[int] = []
	var min_count := maxi(1, int(opaque * min_share))
	for cb in coarse:
		var m: Vector3 = coarse_sum[cb] / coarse_count[cb]
		var c := Color(m.x, m.y, m.z)
		var best := -1
		var best_d := MERGE_DISTANCE
		for k in centers.size():
			var d := _distance(c, centers[k])
			if d < best_d:
				best_d = d
				best = k
		if best >= 0:
			centers[best] = centers[best].lerp(c, float(coarse_count[cb]) / (weights[best] + coarse_count[cb]))
			weights[best] += coarse_count[cb]
		elif coarse_count[cb] >= min_count and centers.size() < max_colors and not _is_blend(c, centers):
			centers.append(c)
			weights.append(coarse_count[cb])
	if centers.is_empty():
		return
	var bin_label := PackedInt32Array()
	bin_label.resize(4096)
	for b in bins:
		bin_label[b] = _label_for(_bin_color(b), centers)
	# One refining pass: each color becomes the mean of the bins it got.
	var sums: Array[Vector3] = []
	sums.resize(centers.size())
	sums.fill(Vector3.ZERO)
	var got := PackedInt32Array()
	got.resize(centers.size())
	for b in bins:
		var c := _bin_color(b)
		sums[bin_label[b]] += Vector3(c.r, c.g, c.b) * counts[b]
		got[bin_label[b]] += counts[b]
	for k in centers.size():
		if got[k] > 0:
			var m: Vector3 = sums[k] / got[k]
			centers[k] = Color(m.x, m.y, m.z)
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
	# Grain (a scan, a photo, JPEG noise): a pixel unlike all four of its neighbours takes the
	# color most of them have. Lines a pixel wide keep their neighbours along them.
	var w := image.get_width()
	var h := image.get_height()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var l := _labels[i]
			var up := _labels[i - w]
			var down := _labels[i + w]
			var left := _labels[i - 1]
			var right := _labels[i + 1]
			if l != up and l != down and l != left and l != right:
				var pick := up
				if (down == left or down == right) and down != up:
					pick = down
				elif left == right and left != up:
					pick = left
				share[l] -= 1 if l >= 0 else 0
				_labels[i] = pick
				if pick >= 0:
					share[pick] += 1
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
	if opaque == n and not colors.any(func(c: Dictionary) -> bool: return c.layer == Layer.IGNORE):
		var k := border_color()
		if k >= 0:
			colors[k].layer = Layer.IGNORE

## The color filling most of the picture's border (over half of it), or -1: the paper of a
## drawing made on a colored or dark background.
func border_color() -> int:
	var w := image.get_width()
	var h := image.get_height()
	var counts := PackedInt32Array()
	counts.resize(colors.size())
	var total := 0
	for x in w:
		for y in [0, h - 1]:
			var l := _labels[y * w + x]
			if l >= 0:
				counts[l] += 1
				total += 1
	for y in range(1, h - 1):
		for x in [0, w - 1]:
			var l := _labels[y * w + x]
			if l >= 0:
				counts[l] += 1
				total += 1
	var best := -1
	for k in counts.size():
		if best < 0 or counts[k] > counts[best]:
			best = k
	return best if best >= 0 and total > 0 and counts[best] * 2 > total else -1

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

## What is drawn: the bounding box (image px) of the pixels of colors that aren't paper, or the
## whole picture when there are none. Cached until the colors' layers change.
func content_rect() -> Rect2i:
	var key := str(colors.map(func(c: Dictionary) -> int: return c.layer))
	if key == _content_key and _content.has_area():
		return _content
	var w := image.get_width()
	var h := image.get_height()
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	var drawn := PackedByteArray()
	drawn.resize(colors.size())
	for k in colors.size():
		drawn[k] = 1 if colors[k].layer != Layer.IGNORE else 0
	for y in h:
		var row := y * w
		for x in w:
			var l := _labels[row + x]
			if l >= 0 and drawn[l] == 1:
				lo.x = mini(lo.x, x)
				hi.x = maxi(hi.x, x)
				lo.y = mini(lo.y, y)
				hi.y = maxi(hi.y, y)
	_content = Rect2i(lo, hi - lo + Vector2i.ONE) if hi.x >= 0 else Rect2i(Vector2i.ZERO, image.get_size())
	_content_key = key
	return _content

## The part of the picture laid over [member target]: [method content_rect] with [member crop],
## else the whole picture.
func source_rect() -> Rect2i:
	return content_rect() if crop else Rect2i(Vector2i.ZERO, image.get_size())

## From the traced image's pixels to [member target].
func image_to_target() -> Transform2D:
	var src := source_rect()
	var k := target.size / Vector2(src.size)
	var off := target.position
	if keep_aspect:
		var s := minf(k.x, k.y)
		k = Vector2(s, s)
		off = target.position + (target.size - Vector2(src.size) * s) * 0.5
	return Transform2D(Vector2(k.x, 0.0), Vector2(0.0, k.y), off - Vector2(src.position) * k)

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
	var src := source_rect()
	var drawn := Rect2(xform * Vector2(src.position), Vector2(src.size) * xform.get_scale())
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
		var outers: Array[PackedVector2Array] = []
		for poly: PackedVector2Array in masks[k].opaque_to_polygons(all, eps):
			outers.append(_place(poly, xform, src, drawn))
		# Paper enclosed by the color: holes (what touches the padding is the outside).
		var holes: Array[PackedVector2Array] = []
		for poly: PackedVector2Array in inverse[k].opaque_to_polygons(all, eps):
			var b := MDSGeometry.bounds(poly)
			if b.position.x > 0.5 and b.position.y > 0.5 and b.end.x < w + 1.5 and b.end.y < h + 1.5:
				holes.append(_place(poly, xform, src, drawn))
		var min_area := min_size * min_size * 0.5
		var pieces := assemble(outers, holes, min_area)
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

## A traced outline (padded pixels) in target coordinates; points on the edge of what is laid
## over the room ([param src], image px) run on [member bleed] px past it.
func _place(poly: PackedVector2Array, xform: Transform2D, src: Rect2i, drawn: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		var p := v - Vector2.ONE
		var q := xform * p
		if bleed > 0.0:
			if p.x <= src.position.x + 0.01:
				q.x = drawn.position.x - bleed
			elif p.x >= src.end.x - 0.01:
				q.x = drawn.end.x + bleed
			if p.y <= src.position.y + 0.01:
				q.y = drawn.position.y - bleed
			elif p.y >= src.end.y - 0.01:
				q.y = drawn.end.y + bleed
		out.append(q)
	return MDSGeometry.dedupe(out)

## Shapes without holes from traced [param outers] and the [param holes] of paper they
## enclose: each hole is cut out of the smallest outline around it (a freeform shape has no
## holes, so that outline is cut in two around it). Outlines and holes under [param min_area]
## are dropped first: a busy picture has hundreds of specks, and comparing every outline with
## every other one took seconds.
static func assemble(outers: Array[PackedVector2Array], holes: Array[PackedVector2Array], min_area: float) -> Array[PackedVector2Array]:
	var polys: Array[PackedVector2Array] = []
	var boxes: Array[Rect2] = []
	var areas := PackedFloat32Array()
	for o in outers:
		var a := absf(MDSGeometry.signed_area(o))
		if o.size() >= 3 and a >= min_area:
			polys.append(o)
			boxes.append(MDSGeometry.bounds(o))
			areas.append(a)
	var cut: Array = []
	cut.resize(polys.size())
	for i in polys.size():
		cut[i] = []
	for h in holes:
		if h.size() < 3 or absf(MDSGeometry.signed_area(h)) < min_area:
			continue # a pinhole: filled
		var hb := MDSGeometry.bounds(h)
		var best := -1
		for i in polys.size():
			if (best < 0 or areas[i] < areas[best]) and boxes[i].grow(1.0).encloses(hb) and Geometry2D.is_point_in_polygon(h[0], polys[i]):
				best = i
		if best >= 0:
			cut[best].append(h)
	var out: Array[PackedVector2Array] = []
	for i in polys.size():
		if cut[i].is_empty():
			var simple := MDSGeometry.dedupe(polys[i])
			if MDSGeometry.is_simple(simple):
				out.append(simple)
			continue
		var mine: Array[PackedVector2Array] = []
		mine.assign(cut[i])
		for piece in MDSGeometry._cut_holes(polys[i], mine, min_area):
			if absf(MDSGeometry.signed_area(piece)) >= min_area:
				var simple := MDSGeometry.dedupe(piece)
				if MDSGeometry.is_simple(simple):
					out.append(simple)
	return out

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

## A style that fills shapes with [param color] and nothing else ([code]COLORS[/code]), solid
## for terrain, one-way for platforms.
static func solid_style(color: Color, layer: Layer) -> MDSFreeformStyle:
	var st := MDSFreeformStyle.new()
	st.display_name = "Solid #%s" % color.to_html(false)
	st.fill_color = color
	st.outline_width = 0.0
	st.solid = layer == Layer.TERRAIN or layer == Layer.PLATFORM
	st.default_layer = "back" if layer == Layer.BACKGROUND else ("front" if layer == Layer.FOREGROUND else "terrain")
	if layer == Layer.PLATFORM:
		st.role = MDSFreeformStyle.Role.PLATFORM
		st.one_way = true
	return st

## The style of the invisible shapes a picture collides with ([code]PICTURE[/code]): nothing
## drawn in the game (the editor outlines them), not extruded in 2.5D; one-way for
## [param platform].
static func collision_style(platform: bool) -> MDSFreeformStyle:
	var st := MDSFreeformStyle.new()
	st.display_name = "Collision only, one-way" if platform else "Collision only"
	st.fill_color = Color(0, 0, 0, 0)
	st.outline_width = 0.0
	st.extrude = false
	if platform:
		st.role = MDSFreeformStyle.Role.PLATFORM
		st.one_way = true
	return st

## Traces the drawing into the room [param painter] edits, as [member output] says (call
## [method MDSRoomPainter.checkpoint] first). With [param replace], what an earlier trace made
## (shapes, pictures, tiles) is removed first. Returns {terrain, platform, background,
## foreground (shapes), tiles (cells painted), pictures, collision (shapes), removed (shapes and
## pictures), removed_tiles}.
func apply(painter: MDSRoomPainter, replace := true) -> Dictionary:
	var report := {"terrain": 0, "platform": 0, "background": 0, "foreground": 0, "tiles": 0, "pictures": 0, "collision": 0, "removed": 0, "removed_tiles": 0}
	if replace:
		var gone := remove_traced(painter)
		report.removed = gone.items
		report.removed_tiles = gone.cells
	match output:
		Output.TILES:
			_apply_tiles(painter, report)
		Output.PICTURE:
			_apply_picture(painter, report)
		_:
			_apply_shapes(painter, report)
	return report

## How much a trace made (see [method apply]): shapes, tiles and pictures.
static func made(report: Dictionary) -> int:
	var n := 0
	for k in ["terrain", "platform", "background", "foreground", "tiles", "pictures", "collision"]:
		n += int(report.get(k, 0))
	return n

## Takes out what earlier traces made in the room: their shapes and pictures, and the tiles they
## painted. Returns {items, cells}.
static func remove_traced(painter: MDSRoomPainter) -> Dictionary:
	var out := {"items": 0, "cells": 0}
	for g in ["Freeform", "FreeformBack", "FreeformFront", MDSRoomPainter.PICTURES_GROUP]:
		for item in painter.items(g):
			if item.has_meta(META):
				painter.remove_item(item)
				out.items += 1
	for layer_name in MDSRoomPainter.LAYER_ORDER:
		var l: TileMapLayer = painter.layers[layer_name]
		if not l.has_meta(MDSRoomPainter.TRACED_CELLS):
			continue
		var cells: Array = l.get_meta(MDSRoomPainter.TRACED_CELLS)
		painter.erase(layer_name, cells.filter(func(c: Variant) -> bool: return c is Vector2i))
		out.cells += cells.size()
		l.remove_meta(MDSRoomPainter.TRACED_CELLS)
	return out

const _REPORT_KEYS := {Layer.TERRAIN: "terrain", Layer.PLATFORM: "platform", Layer.BACKGROUND: "background", Layer.FOREGROUND: "foreground"}

## A traced shape ([param s], from [method trace]) as a freeform shape of [param st], set up before
## it goes into the room so it is built once.
func _shape(s: Dictionary, st: MDSFreeformStyle, shape_name: String) -> MDSFreeform:
	var layer: Layer = s.layer
	var f := MDSFreeform.new()
	f.points = s.points
	f.style = st
	f.solid = layer == Layer.TERRAIN or layer == Layer.PLATFORM
	f.smooth = s.smooth
	f.seed_value = randi() % 100000
	f.name = shape_name
	match layer:
		Layer.PLATFORM:
			f.set_collision_override(MDSFreeformStyle.Role.PLATFORM, true)
		Layer.TERRAIN:
			if st.get_role() != MDSFreeformStyle.Role.TERRAIN or st.is_one_way():
				f.set_collision_override(MDSFreeformStyle.Role.TERRAIN, false)
	f.set_meta(META, true)
	if not (s.seams as PackedFloat32Array).is_empty():
		f.set_meta(&"mds_seams", s.seams)
	return f

## [code]STYLES[/code] and [code]COLORS[/code]: the shapes, in their styles or solid colors.
func _apply_shapes(painter: MDSRoomPainter, report: Dictionary) -> void:
	var flat: Dictionary = {} # color index -> its solid style (one per color, shared by its shapes)
	for s in trace():
		var layer: Layer = s.layer
		var st: MDSFreeformStyle
		if output == Output.COLORS:
			if not flat.has(s.color):
				var c: Dictionary = colors[s.color]
				flat[s.color] = solid_style(c.get("fill_color", c.color), layer)
			st = flat[s.color]
		else:
			st = style_for(layer, s.color)
		var key: String = _REPORT_KEYS[layer]
		painter.add_item(_shape(s, st, "Traced%s%d" % [key.capitalize(), report[key] + 1]), LAYER_GROUPS[layer])
		report[key] += 1

# --- Tiles ---------------------------------------------------------------------------------------

## The room's tile cells each color covers ([code]TILES[/code]): color index -> cells of
## [param painter]'s grid. A cell goes to the color most of it is drawn in (paper counts too, so
## a cell half on the paper goes to whichever covers more of it); cells past the drawing's edge,
## up to [member bleed] px, continue the colors along it. Patches of a color smaller than
## [member min_size] across are dropped.
func cells_by_color(painter: MDSRoomPainter) -> Dictionary:
	var out: Dictionary = {}
	if not image or _labels.is_empty():
		return out
	var w := image.get_width()
	var xform := image_to_target()
	var inv := xform.affine_inverse()
	var src := source_rect()
	var drawn := Rect2(xform * Vector2(src.position), Vector2(src.size) * xform.get_scale())
	var area := drawn.grow(bleed)
	var ts := painter.tile_size()
	var lo := painter.cell_at("Terrain", area.position)
	var hi := painter.cell_at("Terrain", area.end - Vector2(0.01, 0.01))
	var drawn_color := PackedByteArray()
	drawn_color.resize(colors.size())
	for k in colors.size():
		drawn_color[k] = 1 if colors[k].layer != Layer.IGNORE else 0
	var votes := PackedInt32Array()
	votes.resize(colors.size() + 1)
	var inside := drawn.grow(-0.01)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, y)
			var center := painter.cell_rect("Terrain", cell).get_center()
			votes.fill(0)
			var total := 0
			for sy in [-1, 0, 1]:
				for sx in [-1, 0, 1]:
					var q: Vector2 = center + Vector2(sx, sy) * ts / 3.0
					if not drawn.has_point(q):
						if bleed <= 0.0 or not area.has_point(q):
							continue
						q = q.clamp(inside.position, inside.end)
					var p := inv * q
					var px := clampi(int(p.x), src.position.x, src.end.x - 1)
					var py := clampi(int(p.y), src.position.y, src.end.y - 1)
					var l := _labels[py * w + px]
					votes[l + 1 if l >= 0 and drawn_color[l] == 1 else 0] += 1
					total += 1
			if total == 0:
				continue
			var best := 0
			for k in range(1, votes.size()):
				if votes[k] > votes[best]:
					best = k
			if best > 0:
				var k := best - 1
				if not out.has(k):
					out[k] = []
				out[k].append(cell)
	if min_size > 0.0:
		for k in out.keys():
			out[k] = _without_specks(out[k], ts)
			if out[k].is_empty():
				out.erase(k)
	return out

## [param cells] without the patches (4-connected) smaller than [member min_size] across.
func _without_specks(cells: Array, ts: Vector2) -> Array:
	var left: Dictionary = {}
	for c in cells:
		left[c] = true
	var keep: Array = []
	while not left.is_empty():
		var start: Vector2i = left.keys()[0]
		var patch: Array = [start]
		left.erase(start)
		var lo := start
		var hi := start
		var i := 0
		while i < patch.size():
			var c: Vector2i = patch[i]
			i += 1
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if left.has(c + d):
					left.erase(c + d)
					patch.append(c + d)
		var across := Vector2(hi - lo + Vector2i.ONE) * ts
		if maxf(across.x, across.y) >= min_size:
			keep.append_array(patch)
	return keep

## [code]TILES[/code]: paints each color's cells with its fill, on its layer's tile layer, and
## remembers them (so Replace the last trace can erase them).
func _apply_tiles(painter: MDSRoomPainter, report: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var painted: Dictionary = {} # tile layer -> cells
	var by_color := cells_by_color(painter)
	# Background first, foreground last; within a layer, the most used color first.
	var order: Array = by_color.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		var la: int = [Layer.BACKGROUND, Layer.TERRAIN, Layer.PLATFORM, Layer.FOREGROUND].find(colors[a].layer)
		var lb: int = [Layer.BACKGROUND, Layer.TERRAIN, Layer.PLATFORM, Layer.FOREGROUND].find(colors[b].layer)
		return la < lb if la != lb else a < b)
	for k in order:
		var c: Dictionary = colors[k]
		var layer_name: String = LAYER_TILES[c.layer]
		var fill: Dictionary = c.get("fill", {})
		if fill.is_empty():
			fill = {"type": "color", "color": c.color}
		var cells: Array = by_color[k]
		painter.paint_fill(layer_name, cells, fill, rng)
		if not painted.has(layer_name):
			painted[layer_name] = []
		painted[layer_name].append_array(cells)
		report.tiles += cells.size()
	for layer_name in painted:
		var l: TileMapLayer = painter.layers[layer_name]
		var all: Dictionary = {}
		for cell in l.get_meta(MDSRoomPainter.TRACED_CELLS, []):
			all[cell] = true
		for cell in painted[layer_name]:
			all[cell] = true
		l.set_meta(MDSRoomPainter.TRACED_CELLS, all.keys())
	painter.dirty = true

# --- The drawing itself -------------------------------------------------------------------------

## The drawing as a texture a room scene can link to: its file when it is in the project, else
## a PNG copy at [member picture_path] (or next to the room's scene). Outside the editor the copy
## is embedded instead.
func picture_texture(painter: MDSRoomPainter) -> Texture2D:
	if source_path.begins_with("res://"):
		var tex := MDSRoomPainter._sheet_texture(source_path)
		if tex:
			return tex
	if not original:
		return null
	var path := picture_path
	if path.is_empty():
		var base := painter.scene_path.get_basename() if painter and not painter.scene_path.is_empty() else "res://mds_drawings/drawing"
		path = base + "_drawing.png"
	if path.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return MDSRoomPainter._file_texture(original, path)

## [code]PICTURE[/code]: the drawing at each depth that has colors of its own, keeping them and
## cutting out the rest (and the paper, with [member cut_paper]); then, with [member collision],
## invisible shapes for its terrain and platforms.
func _apply_picture(painter: MDSRoomPainter, report: Dictionary) -> void:
	if not image or colors.is_empty():
		return
	var tex := picture_texture(painter)
	if not tex:
		report.error = "Could not read the drawing's picture."
		return
	# Original pixels per traced pixel.
	var k := Vector2(original.get_size()) / Vector2(image.get_size()) if original else Vector2.ONE
	var src := source_rect()
	var region := Rect2(Vector2(src.position) * k, Vector2(src.size) * k)
	var xform := image_to_target() * Transform2D(0.0, Vector2.ONE / k, 0.0, Vector2.ZERO) * Transform2D(0.0, region.position)
	var depths := {"Background": [Layer.BACKGROUND], "Terrain": [Layer.TERRAIN, Layer.PLATFORM], "Foreground": [Layer.FOREGROUND]}
	for layer_name in depths:
		var keep := PackedColorArray()
		var cut := PackedColorArray()
		var own := 0
		for c in colors:
			var mine: bool = c.layer in depths[layer_name]
			if mine:
				own += 1
			if mine or (c.layer == Layer.IGNORE and not cut_paper and layer_name == "Terrain"):
				keep.append(c.color)
			else:
				cut.append(c.color)
		if own == 0 and not (layer_name == "Terrain" and not cut_paper):
			continue
		if keep.size() == colors.size():
			cut.clear() # nothing to cut: the picture as it is
		var d := painter.add_drawing(tex, region, xform, layer_name, keep, cut)
		d.name = "Traced%sPicture" % layer_name
		d.set_meta(META, true)
		report.pictures += 1
	if not collision:
		return
	var walls := collision_style(false)
	var ledges := collision_style(true)
	for s in trace():
		if s.layer != Layer.TERRAIN and s.layer != Layer.PLATFORM:
			continue
		var f := _shape(s, ledges if s.layer == Layer.PLATFORM else walls, "TracedCollision%d" % (report.collision + 1))
		f.edge_clumps = false
		painter.add_item(f, "Freeform")
		report.collision += 1
