@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSFreeform
extends Node2D
## Freeform terrain: a closed outline drawn with curves instead of tiles, for organic
## caves (rounded ledges, bulging moss walls, arches). The scene stores only the control
## points and an [MDSFreeformStyle]; the visuals and collision are built when the node
## enters the tree, in the editor and in the game:
## - a textured fill (repeating), an outline,
## - strips along edges facing up (moss, grass) and down (drips, roots),
## - clumps from the style's stamp set scattered along those edges,
## - with [member solid], a StaticBody2D with the exact curved collision, on the style's
##   collision layers, one-way for ledges (see [member MDSFreeformStyle.role]).
## Made by the Room view's Freeform tool; can also be edited in the inspector.
##
## A shape that continues into another one along a vertical line (Trace drawing cuts rock in
## two around a cave, since a shape has no holes) lists those lines' x (its own coordinates)
## in the metadata [code]mds_seams[/code]; no outline is drawn along them.
##
## An outline that crosses itself can't be filled or collided with: in the editor it is
## drawn red and reported (see [method is_outline_simple]); the Room view's Repair fixes it.

@export var points: PackedVector2Array = []:
	set(v):
		points = v
		_simple_state = -1
		_queue_rebuild()
@export var style: MDSFreeformStyle:
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
		_simple_state = -1
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
@export_group("Collision override")
## Use the settings below instead of the style's role, layers and one-way.
@export var override_collision := false:
	set(v):
		override_collision = v
		_queue_rebuild()
@export var role: MDSFreeformStyle.Role = MDSFreeformStyle.Role.TERRAIN:
	set(v):
		role = v
		_queue_rebuild()
@export_flags_2d_physics var collision_layer := 1:
	set(v):
		collision_layer = v
		_queue_rebuild()
@export_flags_2d_physics var collision_mask := 1:
	set(v):
		collision_mask = v
		_queue_rebuild()
@export var one_way := false:
	set(v):
		one_way = v
		_queue_rebuild()
@export var one_way_margin := 16.0:
	set(v):
		one_way_margin = v
		_queue_rebuild()

var _pending := false
var _simple_state := -1 ## -1 unknown, 0 twisted, 1 simple
var _warned := false

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

func get_style() -> MDSFreeformStyle:
	return style if style else _default_style()

static var _fallback: MDSFreeformStyle

static func _default_style() -> MDSFreeformStyle:
	if not _fallback:
		_fallback = MDSFreeformStyle.builtins()[0]
	return _fallback

# --- Collision ---------------------------------------------------------------------------------

## Terrain, platform or decoration: the override's, else the style's.
func get_role() -> MDSFreeformStyle.Role:
	return role if override_collision else get_style().get_role()

func get_body_layer() -> int:
	return collision_layer if override_collision else get_style().collision_layer

func get_body_mask() -> int:
	return collision_mask if override_collision else get_style().collision_mask

func is_one_way() -> bool:
	return one_way if override_collision else get_style().is_one_way()

func get_one_way_margin() -> float:
	return one_way_margin if override_collision else get_style().one_way_margin

## Has a collision body: [member solid] and not a decoration.
func is_collider() -> bool:
	return solid and get_role() != MDSFreeformStyle.Role.DECOR

## Solid ground: collides and counts toward the room's silhouette on the map.
func is_terrain() -> bool:
	return is_collider() and get_role() == MDSFreeformStyle.Role.TERRAIN

## A ledge or platform (one-way or not).
func is_platform() -> bool:
	return is_collider() and get_role() == MDSFreeformStyle.Role.PLATFORM

## Gives this shape its own collision settings (kept by undo, copies and saves).
func set_collision_override(p_role: MDSFreeformStyle.Role, p_one_way: bool, layer := -1, mask := -1) -> void:
	var st := get_style()
	role = p_role
	one_way = p_one_way
	collision_layer = layer if layer >= 0 else st.collision_layer
	collision_mask = mask if mask >= 0 else st.collision_mask
	one_way_margin = st.one_way_margin
	override_collision = true

## Every freeform shape under [param root] (inside item groups or not), [param root]
## included.
static func shapes_in(root: Node) -> Array[MDSFreeform]:
	var out: Array[MDSFreeform] = []
	if not root:
		return out
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MDSFreeform:
			out.append(n)
			continue
		stack.append_array(n.get_children())
	return out

## The platforms (ledges) under [param root]: solid shapes with the Platform role, wherever
## they are (the Room view keeps shapes in item groups, not directly in the room).
static func platforms_in(root: Node) -> Array[MDSFreeform]:
	var out: Array[MDSFreeform] = []
	for f in shapes_in(root):
		if f.is_platform():
			out.append(f)
	return out

## The solid ground shapes under [param root].
static func terrain_in(root: Node) -> Array[MDSFreeform]:
	var out: Array[MDSFreeform] = []
	for f in shapes_in(root):
		if f.is_terrain():
			out.append(f)
	return out

# --- Validity ----------------------------------------------------------------------------------

## Whether the outline can be filled and collided with (no edge crosses another). A twisted
## outline draws nothing and has no collision. Cached until the shape changes.
func is_outline_simple() -> bool:
	if _simple_state < 0:
		_simple_state = 1 if MDSGeometry.is_simple(get_outline()) else 0
	return _simple_state == 1

func _get_configuration_warnings() -> PackedStringArray:
	if points.size() >= 3 and not is_outline_simple():
		return PackedStringArray(["The outline crosses itself, so this shape has no fill and no collision. Move its points apart, or select it in the Room view (Freeform > Edit) and press Repair."])
	return PackedStringArray()

## A twisted shape made simple: [{points, smooth}, ...], largest first (empty when nothing of
## it is bigger than a sliver). Clipper unties the control points, or, when only the rounding
## folds the outline over itself, the drawn outline (then simplified back into control
## points, rounded again if that stays simple). A simple shape comes back as it is.
static func repair_points(pts: PackedVector2Array, round_it: bool) -> Array:
	var out: Array = []
	if MDSGeometry.is_simple(outline_of(pts, round_it)):
		out.append({"points": pts, "smooth": round_it})
		return out
	var parts: Array[PackedVector2Array]
	if not MDSGeometry.is_simple(pts):
		parts = MDSGeometry.untwist(pts)
	else:
		parts = MDSGeometry.untwist(outline_of(pts, true))
	for part in parts:
		var found := false
		for tolerance in [2.0, 4.0, 8.0]:
			var simple := MDSGeometry.simplify_closed(part, tolerance)
			if simple.size() >= 3 and round_it and MDSGeometry.is_simple(outline_of(simple, true)):
				out.append({"points": simple, "smooth": true})
				found = true
				break
		if not found:
			var straight := MDSGeometry.simplify_closed(part, 0.5)
			out.append({"points": straight if MDSGeometry.is_simple(straight) else part, "smooth": false})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(MDSGeometry.signed_area(a.points)) > absf(MDSGeometry.signed_area(b.points)))
	return out

## "res://rooms/cave.tscn: Freeform/Shape3", or the node's path in the tree.
func describe() -> String:
	if owner and owner.is_ancestor_of(self):
		var scene := owner.scene_file_path
		return "%s%s" % [scene + ": " if not scene.is_empty() else "", owner.get_path_to(self)]
	var p := get_parent()
	return "%s/%s" % [p.name, name] if p else String(name)

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

## The outline as lines to draw, leaving out its segments along [param seams] (x of vertical
## lines where the shape continues into another): [[points, closed], ...].
static func outline_runs(outline: PackedVector2Array, seams: PackedFloat32Array) -> Array:
	var n := outline.size()
	var skip := PackedByteArray()
	skip.resize(n)
	var any := false
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		for x in seams:
			if absf(a.x - x) < 0.75 and absf(b.x - x) < 0.75:
				skip[i] = 1
				any = true
				break
	if not any:
		return [[outline, true]]
	var runs: Array = []
	var start := 0
	while skip[start] == 0:
		start += 1
	var cur := PackedVector2Array()
	for k in range(1, n + 1):
		var i := (start + k) % n
		if skip[i] == 0:
			if cur.is_empty():
				cur.append(outline[i])
			cur.append(outline[(i + 1) % n])
		elif not cur.is_empty():
			runs.append([cur, false])
			cur = PackedVector2Array()
	if not cur.is_empty():
		runs.append([cur, false])
	return runs

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
	if st.fill_material:
		fill.material = st.fill_material
	_part(fill)
	if st.edge_material:
		var band := MDSEdgeBand.edge_mesh(outline, st.edge_inside, st.edge_outside, st.skip_edges_on_grid, position)
		if band:
			var mi := MeshInstance2D.new()
			mi.mesh = band
			mi.material = st.edge_material
			_part(mi)
	if st.outline_width > 0.0:
		for run in outline_runs(outline, get_meta(&"mds_seams", PackedFloat32Array())):
			var line := Line2D.new()
			line.points = run[0]
			line.closed = run[1]
			line.width = st.outline_width
			line.default_color = st.outline_color
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			if not run[1]:
				line.begin_cap_mode = Line2D.LINE_CAP_ROUND
				line.end_cap_mode = Line2D.LINE_CAP_ROUND
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
	if is_collider():
		var body := StaticBody2D.new()
		body.collision_layer = get_body_layer()
		body.collision_mask = get_body_mask()
		var col := CollisionPolygon2D.new()
		col.polygon = outline
		col.one_way_collision = is_one_way()
		col.one_way_collision_margin = get_one_way_margin()
		body.add_child(col)
		_part(body)
	_report_validity(outline)

## In the editor, a twisted outline is drawn red and reported once.
func _report_validity(outline: PackedVector2Array) -> void:
	var was := _simple_state
	_simple_state = 1 if MDSGeometry.is_simple(outline) else 0
	if was != _simple_state and Engine.is_editor_hint() and is_inside_tree():
		update_configuration_warnings()
	if _simple_state == 1 or not Engine.is_editor_hint():
		return
	var line := Line2D.new()
	line.points = outline
	line.closed = true
	line.width = 4.0
	line.default_color = Color(1, 0.15, 0.1)
	line.z_index = 50
	_part(line)
	if not _warned:
		_warned = true
		push_warning("MDSFreeform %s: its outline crosses itself, so it has no fill and no collision. Select it in the Room view (Freeform > Edit) and press Repair." % describe())

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
func _scatter(run: PackedVector2Array, st: MDSFreeformStyle, category: String, rng: RandomNumberGenerator, hang: bool) -> void:
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
	# Packed arrays are shared by reference: snapshots get their own copy.
	var d := {"points": points.duplicate(), "style": style, "solid": solid, "smooth": smooth, "edge_clumps": edge_clumps,
		"seed": seed_value, "position": position, "name": String(name)}
	if override_collision:
		d.collision = {"role": role, "layer": collision_layer, "mask": collision_mask, "one_way": one_way, "margin": one_way_margin}
	var meta: Dictionary = {}
	for k in get_meta_list():
		meta[k] = get_meta(k)
	if not meta.is_empty():
		d.meta = meta
	return d

static func from_data(d: Dictionary) -> MDSFreeform:
	var f := MDSFreeform.new()
	f.points = (d.points as PackedVector2Array).duplicate()
	f.style = d.style
	f.solid = d.solid
	f.smooth = d.smooth
	f.edge_clumps = d.edge_clumps
	f.seed_value = d.seed
	f.position = d.position
	if not str(d.get("name", "")).is_empty():
		f.name = d.name
	var c: Dictionary = d.get("collision", {})
	if not c.is_empty():
		f.role = c.role
		f.collision_layer = c.layer
		f.collision_mask = c.mask
		f.one_way = c.one_way
		f.one_way_margin = c.margin
		f.override_collision = true
	var meta: Dictionary = d.get("meta", {})
	for k in meta:
		f.set_meta(k, meta[k])
	return f

## Whether [param p] (in this node's parent space) is inside the shape.
func has_point(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p - position, get_outline())
