@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_idp.png")
class_name IDPFreeform
extends Node2D
## Freeform terrain: a closed outline drawn with curves instead of tiles, for organic
## caves (rounded ledges, bulging moss walls, arches). The scene stores only the control
## points and an [IDPFreeformStyle]; the visuals and collision are built when the node
## enters the tree, in the editor and in the game:
## - a textured fill (repeating), an outline,
## - strips along edges facing up (moss, grass) and down (drips, roots),
## - clumps from the style's stamp set scattered along those edges,
## - with [member solid], a StaticBody2D with the exact curved collision.
## Made by the Room view's Freeform tool; can also be edited in the inspector.

@export var points: PackedVector2Array = []:
	set(v):
		points = v
		_queue_rebuild()
@export var style: IDPFreeformStyle:
	set(v):
		style = v
		_queue_rebuild()
## Collides (terrain). Off for backgrounds and foregrounds.
@export var solid := true:
	set(v):
		solid = v
		_queue_rebuild()
## Round the outline through the points (Catmull-Rom). Off: straight edges.
@export var smooth := true:
	set(v):
		smooth = v
		_queue_rebuild()
## Scatter the style's clumps along the edges.
@export var edge_clumps := true:
	set(v):
		edge_clumps = v
		_queue_rebuild()
@export var seed_value := 0:
	set(v):
		seed_value = v
		_queue_rebuild()

var _pending := false

func _ready() -> void:
	rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_rebuild_deferred.call_deferred()

func _rebuild_deferred() -> void:
	_pending = false
	rebuild()

func get_style() -> IDPFreeformStyle:
	return style if style else _default_style()

static var _fallback: IDPFreeformStyle

static func _default_style() -> IDPFreeformStyle:
	if not _fallback:
		_fallback = IDPFreeformStyle.builtins()[0]
	return _fallback

# --- Geometry ---------------------------------------------------------------------------------

## The outline actually drawn and collided with (closed, smoothed through the points).
func get_outline() -> PackedVector2Array:
	return outline_of(points, smooth)

static func outline_of(pts: PackedVector2Array, round_it := true) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or not round_it:
		return pts
	var out := PackedVector2Array()
	for i in n:
		var p0 := pts[(i - 1 + n) % n]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p3 := pts[(i + 2) % n]
		var steps := clampi(int(p1.distance_to(p2) / 10.0), 1, 24)
		for s in steps:
			out.append(_centripetal(p0, p1, p2, p3, float(s) / steps))
	return out

## Centripetal Catmull-Rom (no loops or cusps on uneven spacing).
static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 1e-3)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-3)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-3)
	var u := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - u) / (t1 - t0) + p1 * (u - t0) / (t1 - t0)
	var a2 := p1 * (t2 - u) / (t2 - t1) + p2 * (u - t1) / (t2 - t1)
	var a3 := p2 * (t3 - u) / (t3 - t2) + p3 * (u - t2) / (t3 - t2)
	var b1 := a1 * (t2 - u) / (t2 - t0) + a2 * (u - t0) / (t2 - t0)
	var b2 := a2 * (t3 - u) / (t3 - t1) + a3 * (u - t1) / (t3 - t1)
	return b1 * (t2 - u) / (t2 - t1) + b2 * (u - t1) / (t2 - t1)

static func signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a / 2.0

## Outward normal of each outline segment (i -> i + 1).
static func outward_normals(poly: PackedVector2Array) -> PackedVector2Array:
	var sgn := 1.0 if signed_area(poly) > 0 else -1.0
	var out := PackedVector2Array()
	for i in poly.size():
		var d := poly[(i + 1) % poly.size()] - poly[i]
		out.append(Vector2(d.y, -d.x).normalized() * sgn)
	return out

## Runs of consecutive segments whose outward normal is within [param angle_deg] of
## [param dir], as point lists ordered left to right.
static func edge_runs(poly: PackedVector2Array, normals: PackedVector2Array, dir: Vector2, angle_deg: float) -> Array:
	var n := poly.size()
	var ok := PackedByteArray()
	ok.resize(n)
	var cos_a := cos(deg_to_rad(angle_deg))
	var any_off := false
	for i in n:
		ok[i] = 1 if normals[i].dot(dir) >= cos_a else 0
		any_off = any_off or ok[i] == 0
	var runs: Array = []
	if not any_off:
		var all := PackedVector2Array(poly)
		all.append(poly[0])
		runs.append(all)
		return runs
	# Start after a segment that is off, so runs don't wrap around the start.
	var start := 0
	while ok[start] == 1:
		start += 1
	var cur := PackedVector2Array()
	for k in range(1, n + 1):
		var i := (start + k) % n
		if ok[i] == 1:
			if cur.is_empty():
				cur.append(poly[i])
			cur.append(poly[(i + 1) % n])
		elif not cur.is_empty():
			runs.append(cur)
			cur = PackedVector2Array()
	if not cur.is_empty():
		runs.append(cur)
	for r in runs.size():
		var run: PackedVector2Array = runs[r]
		if run[0].x > run[run.size() - 1].x:
			run.reverse()
			runs[r] = run
	return runs

# --- Building ------------------------------------------------------------------------------------

func rebuild() -> void:
	for c in get_children(true):
		if c.has_meta(&"idp_part"):
			remove_child(c)
			c.queue_free()
	var outline := get_outline()
	if outline.size() < 3:
		return
	var st := get_style()
	var fill := Polygon2D.new()
	fill.polygon = outline
	fill.color = st.fill_color if not st.fill_texture else Color.WHITE
	if st.fill_texture:
		fill.texture = st.fill_texture
		fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		fill.texture_scale = Vector2.ONE / maxf(st.fill_scale, 0.01)
	_part(fill)
	if st.outline_width > 0.0:
		var line := Line2D.new()
		line.points = outline
		line.closed = true
		line.width = st.outline_width
		line.default_color = st.outline_color
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		_part(line)
	var normals := outward_normals(outline)
	var tops := edge_runs(outline, normals, Vector2.UP, st.top_angle)
	var bottoms := edge_runs(outline, normals, Vector2.DOWN, st.top_angle)
	if st.bottom_width > 0.0:
		for run in bottoms:
			_strip(run, st.bottom_inset, st.bottom_width, st.bottom_texture, st.bottom_color)
	if st.top_width > 0.0:
		for run in tops:
			_strip(run, -st.top_inset, st.top_width, st.top_texture, st.top_color)
	if edge_clumps and st.stamp_set and st.clump_spacing > 1.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(seed_value) ^ outline.size()
		if not st.top_clumps.is_empty():
			for run in tops:
				_scatter(run, st, st.top_clumps, rng, false)
		if not st.bottom_clumps.is_empty():
			for run in bottoms:
				_scatter(run, st, st.bottom_clumps, rng, true)
	if solid:
		var body := StaticBody2D.new()
		var col := CollisionPolygon2D.new()
		col.polygon = outline
		body.add_child(col)
		_part(body)

func _part(node: Node) -> void:
	node.set_meta(&"idp_part", true)
	add_child(node, false, Node.INTERNAL_MODE_BACK)

## A textured strip along a left-to-right edge run, shifted by [param shift] along the
## run's upward side (negative: down).
func _strip(run: PackedVector2Array, shift: float, width: float, tex: Texture2D, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in run.size():
		pts.append(run[i] + _normal_at(run, i) * shift)
	var line := Line2D.new()
	line.points = pts
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	if tex:
		line.texture = tex
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line.default_color = Color.WHITE
	else:
		line.default_color = color
	_part(line)

## Upward-side normal at point [param i] of a left-to-right run (from its neighbors): the
## outside for top edges, the inside for bottom edges.
static func _normal_at(run: PackedVector2Array, i: int) -> Vector2:
	var a := run[maxi(i - 1, 0)]
	var b := run[mini(i + 1, run.size() - 1)]
	var d := (b - a).normalized()
	var n := Vector2(d.y, -d.x)
	return n

## Clumps along an edge run, anchored on the edge (tops grow up, bottoms hang down).
func _scatter(run: PackedVector2Array, st: IDPFreeformStyle, category: String, rng: RandomNumberGenerator, hang: bool) -> void:
	var picks := st.stamp_set.indices(category)
	if picks.is_empty() or run.size() < 2:
		return
	var travelled := 0.0
	var next := st.clump_spacing * rng.randf_range(0.2, 0.8)
	for i in range(1, run.size()):
		var seg := run[i] - run[i - 1]
		var ln := seg.length()
		while travelled + ln >= next:
			var t := (next - travelled) / maxf(ln, 1e-3)
			var p := run[i - 1] + seg * t
			var n := _normal_at(run, i)
			if hang:
				n = -n # a left-to-right run under the shape: the local normal points in
			var s := st.stamp_set.make_sprite(picks[rng.randi_range(0, picks.size() - 1)])
			var k := rng.randf_range(st.clump_scale.x, st.clump_scale.y)
			s.scale = Vector2(k * (-1 if rng.randf() < 0.5 else 1), k)
			s.position = p - n * (4.0 if not hang else -2.0)
			s.rotation = n.angle() + (PI / 2 if not hang else -PI / 2) + rng.randf_range(-0.15, 0.15)
			if hang:
				s.rotation = rng.randf_range(-0.1, 0.1)
			_part(s)
			next += st.clump_spacing * rng.randf_range(0.6, 1.4)
		travelled += ln

# --- Data (undo, copies) ---------------------------------------------------------------------

func to_data() -> Dictionary:
	return {"points": points, "style": style, "solid": solid, "smooth": smooth, "edge_clumps": edge_clumps,
		"seed": seed_value, "position": position, "name": String(name)}

static func from_data(d: Dictionary) -> IDPFreeform:
	var f := IDPFreeform.new()
	f.points = d.points
	f.style = d.style
	f.solid = d.solid
	f.smooth = d.smooth
	f.edge_clumps = d.edge_clumps
	f.seed_value = d.seed
	f.position = d.position
	if not str(d.get("name", "")).is_empty():
		f.name = d.name
	return f

## Whether [param p] (in this node's parent space) is inside the shape.
func has_point(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p - position, get_outline())
