@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSDepth25D
extends Node2D
## 2.5D for flat rooms, made only of their own 2D art. Add one to a room (or turn on
## [code]depth_25d[/code] in the world settings and [MDSWorldGame] adds one to every room).
## Every frame it reads where the camera looks and fakes depth around that point:
## - [b]Extruded terrain[/b]: every wall, floor and platform gets the side faces of a solid
##   block, running back toward the vanishing point (the middle of the view), so they swing
##   as the camera moves. Solid freeform shapes (Terrain and Platform roles, styles with
##   [member MDSFreeformStyle.extrude]), the collision of tile layers, and static bodies.
##   Decorations and background/foreground shapes are never extruded.
## - [b]Tilted floors[/b]: the tops of floors and ledges become planes receding into the
##   screen, paved in perspective.
## - [b]Light[/b]: faces are lit from the key light and fall off with distance from the player;
##   the view darkens away from the player and toward its edges.
## - [b]Shadows[/b]: bodies in [member shadow_groups] cast soft shadows on the ground under
##   them that spread and fade as they rise.
## Nothing here collides: it's all drawing. Colors come from the freeform styles (their fill
## and top textures or colors, or [member MDSFreeformStyle.depth_side_color]), and from the
## tileset's art for tiles. No dependency on MetSys or game classes.

## How the depth looks. Empty: the defaults of [MDSDepthStyle].
@export var style: MDSDepthStyle
## Nodes whose terrain is extruded. Empty: the parent (the room).
@export var sources: Array[Node] = []
## The body the light follows. Empty: the first node in [member player_group].
@export var player: Node2D
@export var player_group: StringName = &"player"
## Bodies (CharacterBody2D, RigidBody2D) in these groups cast shadows.
@export var shadow_groups: Array[StringName] = [&"player", &"enemy"]
@export var extrude_tiles := true
@export var extrude_bodies := true
@export var light_falloff := true
## Run in the editor (the Room view's 2.5D preview). Off: the node only works in the game.
@export var preview_in_editor := false
## Where the camera looks, from an [MDSRoomCamera] (empty: the viewport's camera).
@export var room_camera: MDSRoomCamera

## The view to fake depth for, in this node's space (empty: the camera's).
var view_override := Rect2()
## Faces drawn last frame, and how long building them took (µs).
var stats := {"side": 0, "floor": 0, "usec": 0, "edges": 0}

## Extruded masses: [{node, edges: [[a, b, normal]] (in this node's space), side, top, joint}].
var masses: Array = []
var _faces: _Faces
var _shadows: _Shadows
var _light: _ViewCover
var _dirty := true
var _drawn_view := Rect2()
var _drawn_light := Vector2.INF
var _cache: Dictionary = {} ## node id -> [key, edges]
var _rescan_timer := 0.0
static var _avg_colors: Dictionary = {} ## texture rid -> Color

const LIGHT_SHADER := """
shader_type canvas_item;
render_mode blend_mul, unshaded;
uniform vec2 light_at = vec2(0.0);
uniform float inner = 260.0;
uniform float outer = 900.0;
uniform vec4 dark : source_color = vec4(0.66, 0.66, 0.74, 1.0);
uniform vec2 centre = vec2(0.0);
uniform vec2 half_size = vec2(576.0, 324.0);
uniform float vignette = 0.3;
varying vec2 local_pos;
void vertex() {
	local_pos = VERTEX;
}
void fragment() {
	float t = smoothstep(inner, outer, distance(local_pos, light_at));
	vec2 q = abs(local_pos - centre) / max(half_size, vec2(1.0));
	float edge = smoothstep(0.55, 1.15, length(q * vec2(0.85, 1.0)));
	vec3 c = mix(vec3(1.0), dark.rgb, t) * (1.0 - vignette * edge);
	COLOR = vec4(c, 1.0);
}
"""
static var _light_shader: Shader

func _ready() -> void:
	if not style:
		style = MDSDepthStyle.new()
	_faces = _Faces.new()
	_faces.owner_node = self
	_faces.z_index = style.face_z
	add_child(_faces, false, Node.INTERNAL_MODE_FRONT)
	_shadows = _Shadows.new()
	_shadows.owner_node = self
	_shadows.z_index = style.face_z
	add_child(_shadows, false, Node.INTERNAL_MODE_FRONT)
	if light_falloff:
		_light = _ViewCover.new()
		if not _light_shader:
			_light_shader = Shader.new()
			_light_shader.code = LIGHT_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = _light_shader
		_light.material = mat
		_light.z_index = style.light_z
		add_child(_light, false, Node.INTERNAL_MODE_FRONT)
	if is_inside_tree():
		get_tree().node_added.connect(_on_tree_changed)
		get_tree().node_removed.connect(_on_tree_changed)
	_dirty = true

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_tree_changed):
		get_tree().node_added.disconnect(_on_tree_changed)
		get_tree().node_removed.disconnect(_on_tree_changed)

func _enter_tree() -> void:
	if _faces and not get_tree().node_added.is_connected(_on_tree_changed):
		get_tree().node_added.connect(_on_tree_changed)
		get_tree().node_removed.connect(_on_tree_changed)

func _on_tree_changed(node: Node) -> void:
	if _dirty or node == self or is_ancestor_of(node):
		return
	for s in _sources():
		if is_instance_valid(s) and (s == node or s.is_ancestor_of(node)):
			_dirty = true
			return

func _sources() -> Array:
	if not sources.is_empty():
		return sources
	return [get_parent()] if get_parent() else []

func _active() -> bool:
	return not Engine.is_editor_hint() or preview_in_editor

# --- View --------------------------------------------------------------------------------------------

## The part of the room on screen, in this node's space.
func view_rect() -> Rect2:
	if view_override.has_area():
		return view_override
	if room_camera and room_camera.camera:
		var c := to_local(room_camera.screen_center())
		var s := room_camera.view_size()
		return Rect2(c - s * 0.5, s)
	var vp := get_viewport()
	if not vp:
		return Rect2(0, 0, 1152, 648)
	var ct := vp.get_canvas_transform()
	var k := ct.get_scale().abs()
	var size := vp.get_visible_rect().size / Vector2(maxf(k.x, 0.001), maxf(k.y, 0.001))
	var centre := to_local(ct.affine_inverse() * (vp.get_visible_rect().size * 0.5))
	return Rect2(centre - size * 0.5, size)

## Where the camera looks (the vanishing point), in this node's space.
func view_centre() -> Vector2:
	return view_rect().get_center()

func _player() -> Node2D:
	if is_instance_valid(player):
		return player
	if not is_inside_tree() or Engine.is_editor_hint():
		return null
	var p := get_tree().get_first_node_in_group(player_group)
	return p as Node2D

func _process(delta: float) -> void:
	if not _active():
		return
	_rescan_timer -= delta
	if _dirty or _rescan_timer <= 0.0:
		rescan()
	var view := view_rect()
	var p := _player()
	var light_at := to_local(p.global_position) if p else view.get_center()
	if _masses_moved() or view.get_center().distance_squared_to(_drawn_view.get_center()) > 0.04 \
			or not view.size.is_equal_approx(_drawn_view.size) or light_at.distance_squared_to(_drawn_light) > 16.0:
		_drawn_view = view
		_drawn_light = light_at
		_faces.queue_redraw()
	_shadows.queue_redraw()
	if _light:
		var cover := view.grow(maxf(view.size.x, view.size.y) * 0.1)
		_light.cover(cover)
		var mat := _light.material as ShaderMaterial
		mat.set_shader_parameter("light_at", light_at)
		mat.set_shader_parameter("inner", style.light_inner)
		mat.set_shader_parameter("outer", style.light_reach)
		mat.set_shader_parameter("dark", style.light_dark)
		mat.set_shader_parameter("centre", view.get_center())
		mat.set_shader_parameter("half_size", view.size * 0.5)
		mat.set_shader_parameter("vignette", style.vignette)

# --- Masses ----------------------------------------------------------------------------------------

## Finds the terrain to extrude again (done when the sources' trees change, and twice a second
## for moved or reshaped bodies).
func rescan() -> void:
	_dirty = false
	_rescan_timer = 0.5
	masses.clear()
	for s in _sources():
		if is_instance_valid(s):
			_scan(s)

func _scan(n: Node) -> void:
	if n == self or n.has_meta(&"idp_blockout"):
		return
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is MDSFreeform:
		var f := n as MDSFreeform
		var r := f.get_role()
		if f.is_collider() and r != MDSFreeformStyle.Role.DECOR and f.get_style().extrude and f.points.size() >= 3:
			masses.append(_freeform_mass(f))
		return
	if n is TileMapLayer:
		if extrude_tiles and n.enabled and n.collision_enabled and n.tile_set:
			var m := _tile_mass(n)
			if not m.edges.is_empty():
				masses.append(m)
		return
	if extrude_bodies and (n is StaticBody2D or n is AnimatableBody2D) and n.process_mode != Node.PROCESS_MODE_DISABLED:
		var m := _body_mass(n)
		if not m.edges.is_empty():
			masses.append(m)
	for c in n.get_children():
		_scan(c)

## Whether a mass moved or was reshaped since it was read (re-read when so).
func _masses_moved() -> bool:
	var moved := false
	for i in masses.size():
		var m: Dictionary = masses[i]
		if not is_instance_valid(m.node) or not m.node.is_inside_tree():
			continue
		# Tile layers: only a move counts here (their cells are read again by rescan()).
		var changed: bool = _xf(m.node) != m.key[0] if m.node is TileMapLayer else _key_of(m.node) != m.key
		if changed:
			moved = true
			if m.node is MDSFreeform:
				masses[i] = _freeform_mass(m.node)
			elif m.node is TileMapLayer:
				masses[i] = _tile_mass(m.node)
			else:
				masses[i] = _body_mass(m.node)
	return moved

func _xf(n: Node2D) -> Transform2D:
	return global_transform.affine_inverse() * n.global_transform if n.is_inside_tree() and is_inside_tree() else MDSRoomObjects.local_transform(n, get_parent())

func _key_of(n: Node) -> Array:
	var key: Array = [_xf(n)]
	if n is MDSFreeform:
		key.append_array([hash((n as MDSFreeform).points), (n as MDSFreeform).smooth, (n as MDSFreeform).style])
	elif n is TileMapLayer:
		key.append((n as TileMapLayer).get_used_cells().size())
	return key

static func _edges_of(poly: PackedVector2Array) -> Array:
	var out: Array = []
	var n := poly.size()
	if n < 3:
		return out
	var sgn := 1.0 if MDSGeometry.signed_area(poly) > 0.0 else -1.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var d := b - a
		if d.length_squared() >= 4.0:
			out.append([a, b, Vector2(d.y, -d.x).normalized() * sgn])
	return out

func _freeform_mass(f: MDSFreeform) -> Dictionary:
	var st := f.get_style()
	var key := _key_of(f)
	var hit: Array = _cache.get(f.get_instance_id(), [])
	var edges: Array
	if not hit.is_empty() and hit[0] == key:
		edges = hit[1]
	else:
		var xf: Transform2D = key[0]
		edges = _edges_of(MDSGeometry.simplify_closed(xf * f.get_outline(), 1.5))
		_cache[f.get_instance_id()] = [key, edges]
	var fill := st.fill_color if not st.fill_texture else average_color(st.fill_texture, st.fill_color)
	var top_base := st.top_color if not st.top_texture else average_color(st.top_texture, st.top_color)
	var side := st.depth_side_color if st.depth_side_color.a > 0.0 else fill
	var top := st.depth_top_color if st.depth_top_color.a > 0.0 else fill.lerp(top_base, 0.55 if st.top_width > 0.0 or st.top_texture else 0.0)
	return _prepared({"node": f, "key": key, "edges": edges, "side": side, "top": top, "joint": st.outline_color})

## A tile layer's collision as edges: each cell edge between a solid cell and an empty one,
## merged into runs.
func _tile_mass(layer: TileMapLayer) -> Dictionary:
	var key := _key_of(layer)
	var hit: Array = _cache.get(layer.get_instance_id(), [])
	if not hit.is_empty() and hit[0] == key:
		return hit[1]
	var m := _read_tiles(layer, key)
	_cache[layer.get_instance_id()] = [key, m]
	return m

func _read_tiles(layer: TileMapLayer, key: Array) -> Dictionary:
	var ts := layer.tile_set
	var solid: Dictionary = {}
	var tex: Texture2D = null
	for c in layer.get_used_cells():
		var sid := layer.get_cell_source_id(c)
		if not MDSRoomPainter.is_cell_valid(layer, c):
			continue
		var td := layer.get_cell_tile_data(c)
		if td and ts.get_physics_layers_count() > 0 and td.get_collision_polygons_count(0) > 0 and not td.is_collision_polygon_one_way(0, 0):
			solid[c] = true
			if not tex:
				var src := ts.get_source(sid) as TileSetAtlasSource
				tex = src.texture if src else null
	var xf: Transform2D = key[0]
	var size := Vector2(ts.tile_size)
	var origin := layer.map_to_local(Vector2i.ZERO) - size / 2.0
	var edges: Array = []
	# Per direction: cells whose neighbour that way is empty, grouped into runs.
	for d in [[Vector2i.UP, Vector2.UP], [Vector2i.DOWN, Vector2.DOWN], [Vector2i.LEFT, Vector2.LEFT], [Vector2i.RIGHT, Vector2.RIGHT]]:
		var dir: Vector2i = d[0]
		var lines: Dictionary = {}
		for c: Vector2i in solid:
			if solid.has(c + dir):
				continue
			var line := c.y if dir.y != 0 else c.x
			var along := c.x if dir.y != 0 else c.y
			if not lines.has(line):
				lines[line] = []
			lines[line].append(along)
		for line in lines:
			var xs: Array = lines[line]
			xs.sort()
			var start: int = xs[0]
			for i in range(1, xs.size() + 1):
				if i < xs.size() and xs[i] == xs[i - 1] + 1:
					continue
				var last: int = xs[i - 1]
				var a: Vector2
				var b: Vector2
				match dir:
					Vector2i.UP:
						a = origin + Vector2(start, line) * size
						b = origin + Vector2(last + 1, line) * size
					Vector2i.DOWN:
						a = origin + Vector2(start, line + 1) * size
						b = origin + Vector2(last + 1, line + 1) * size
					Vector2i.LEFT:
						a = origin + Vector2(line, start) * size
						b = origin + Vector2(line, last + 1) * size
					_:
						a = origin + Vector2(line + 1, start) * size
						b = origin + Vector2(line + 1, last + 1) * size
				edges.append([xf * a, xf * b, (xf.basis_xform(Vector2(d[1]))).normalized()])
				if i < xs.size():
					start = xs[i]
	var art := average_color(tex, style.plain_side) if tex else style.plain_side
	return _prepared({"node": layer, "key": key, "edges": edges, "side": art, "top": art.lightened(0.1), "joint": style.plain_joint})

func _body_mass(body: Node2D) -> Dictionary:
	var edges: Array = []
	for c in body.get_children():
		var poly := PackedVector2Array()
		if c is CollisionPolygon2D and not c.disabled and c.build_mode == CollisionPolygon2D.BUILD_SOLIDS:
			poly = (c as CollisionPolygon2D).polygon
		elif c is CollisionShape2D and not c.disabled and c.shape is RectangleShape2D:
			poly = MDSGeometry.rect_polygon(c.shape.get_rect())
		if poly.size() >= 3:
			edges.append_array(_edges_of(_xf(c) * poly))
	return _prepared({"node": body, "key": _key_of(body), "edges": edges, "side": style.plain_side, "top": style.plain_top, "joint": style.plain_joint})

## The average color of a texture's opaque pixels (cached), for faces matching the art.
static func average_color(tex: Texture2D, fallback: Color) -> Color:
	if not tex:
		return fallback
	var rid := tex.get_rid()
	if _avg_colors.has(rid):
		return _avg_colors[rid]
	var img := tex.get_image()
	if not img:
		return fallback
	if img.is_compressed():
		img.decompress()
	var sum := Color(0, 0, 0, 0)
	var n := 0
	var step := Vector2i(maxi(1, img.get_width() / 32), maxi(1, img.get_height() / 32))
	for y in range(0, img.get_height(), step.y):
		for x in range(0, img.get_width(), step.x):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += c
				n += 1
	var out := Color(sum.r / n, sum.g / n, sum.b / n, 1.0) if n > 0 else fallback
	_avg_colors[rid] = out
	return out

## Adds what drawing needs to a mass: its bounds, and per edge its middle, key light, kind
## (0 floor top, 1 wall, 2 ceiling underside) and bounds.
func _prepared(m: Dictionary) -> Dictionary:
	var light_dir := -style.light_dir.normalized()
	var out: Array = []
	var bounds := Rect2()
	var first := true
	for e in m.edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n: Vector2 = e[2]
		var r := Rect2(a, Vector2.ZERO).expand(b)
		bounds = r if first else bounds.merge(r)
		first = false
		var key := lerpf(0.5, 1.0, (n.dot(light_dir) + 1.0) * 0.5)
		out.append([a, b, n, (a + b) * 0.5, key, 0 if n.y < -0.55 else (2 if n.y > 0.55 else 1), r])
	m.edges = out
	m.bounds = bounds
	return m

# --- Drawing ---------------------------------------------------------------------------------------

class _Faces extends Node2D:
	var owner_node: MDSDepth25D
	var _pts := PackedVector2Array()
	var _cols := PackedColorArray()
	var _idx := PackedInt32Array()
	## Joint lines, drawn natively in two batches (thin courses and joints, thicker far edges).
	var _thin := PackedVector2Array()
	var _thin_cols := PackedColorArray()
	var _thick := PackedVector2Array()
	var _thick_cols := PackedColorArray()

	func _quad(a: Vector2, b: Vector2, b2: Vector2, a2: Vector2, front: Color, back: Color) -> void:
		_pts.push_back(a)
		_pts.push_back(b)
		_pts.push_back(b2)
		_pts.push_back(a)
		_pts.push_back(b2)
		_pts.push_back(a2)
		_cols.push_back(front)
		_cols.push_back(front)
		_cols.push_back(back)
		_cols.push_back(front)
		_cols.push_back(back)
		_cols.push_back(back)

	func _line(a: Vector2, b: Vector2, c: Color, thick: bool) -> void:
		if thick:
			_thick.push_back(a)
			_thick.push_back(b)
			_thick_cols.push_back(c)
		else:
			_thin.push_back(a)
			_thin.push_back(b)
			_thin_cols.push_back(c)

	func _draw() -> void:
		var o := owner_node
		var t0 := Time.get_ticks_usec()
		_pts.clear()
		_cols.clear()
		_thin.clear()
		_thin_cols.clear()
		_thick.clear()
		_thick_cols.clear()
		var sides := 0
		var floors := 0
		var count := 0
		var view := o._drawn_view.grow(maxf(o._drawn_view.size.x, o._drawn_view.size.y) * 0.12)
		var vp := o._drawn_view.get_center()
		var st := o.style
		var dx := st.depth_x
		var dy := st.depth_y
		var light := o._drawn_light
		var has_light := light != Vector2.INF
		var reach := maxf(st.light_reach, 1.0)
		var courses := st.floor_courses
		var paving := maxf(st.paving, 4.0)
		var joints := st.joints
		for m in o.masses:
			if not view.intersects(m.bounds):
				continue
			var top: Color = m.top
			var top_front: Color = top.lightened(0.12)
			var top_back: Color = top.darkened(0.35)
			var side: Color = m.side
			var joint: Color = m.joint
			var course_line := Color(joint, joints * 0.9)
			var edge_line := Color(joint, joints * 1.4)
			for e in m.edges:
				count += 1
				var a: Vector2 = e[0]
				var b: Vector2 = e[1]
				var n: Vector2 = e[2]
				var mid: Vector2 = e[3]
				# Off screen, or turned away from the vanishing point (inside the block).
				if not view.intersects(e[6]) or n.dot(vp - mid) <= 0.0:
					continue
				var a2 := Vector2(a.x + (vp.x - a.x) * dx, a.y + (vp.y - a.y) * dy)
				var b2 := Vector2(b.x + (vp.x - b.x) * dx, b.y + (vp.y - b.y) * dy)
				var lit: float = e[4]
				if has_light:
					lit *= lerpf(1.0, 0.5, clampf(mid.distance_to(light) / reach, 0.0, 1.0))
				if e[5] == 0:
					floors += 1
					var front := top_front * lit
					var back := top_back * lit
					front.a = 1.0
					back.a = 1.0
					_quad(a, b, b2, a2, front, back)
					if joints > 0.0:
						for k in courses:
							var t := 0.16 + 0.62 * float(k) / maxf(courses - 1, 1)
							_line(a.lerp(a2, t), b.lerp(b2, t), course_line, false)
						var count_j := int((b - a).length() / paving)
						for j in range(1, count_j):
							var u := float(j) / float(count_j)
							_line(a.lerp(b, u), a2.lerp(b2, u), course_line, false)
						_line(a2, b2, edge_line, true)
				else:
					sides += 1
					var front := side.darkened(0.25 if e[5] == 2 else 0.1) * lit
					var back := front.darkened(0.45)
					front.a = 1.0
					back.a = 1.0
					_quad(a, b, b2, a2, front, back)
					if joints > 0.0:
						_line(a2, b2, edge_line, true)
		var nv := _pts.size()
		if nv >= 3:
			if _idx.size() < nv:
				var old := _idx.size()
				_idx.resize(nv)
				for i in range(old, nv):
					_idx[i] = i
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx.slice(0, nv) if _idx.size() > nv else _idx, _pts, _cols)
		if not _thin.is_empty():
			RenderingServer.canvas_item_add_multiline(get_canvas_item(), _thin, _thin_cols, 1.5, true)
		if not _thick.is_empty():
			RenderingServer.canvas_item_add_multiline(get_canvas_item(), _thick, _thick_cols, 2.0, true)
		o.stats = {"side": sides, "floor": floors, "usec": Time.get_ticks_usec() - t0, "edges": count}

## Soft shadows on the ground under bodies: small and dark standing, wide and faint high up.
class _Shadows extends Node2D:
	var owner_node: MDSDepth25D
	var _stand: Dictionary = {}
	var _widths: Dictionary = {}
	var _tri := PackedVector2Array()
	var _tri_cols := PackedColorArray()

	func _draw() -> void:
		var o := owner_node
		if not is_inside_tree() or Engine.is_editor_hint():
			return
		var space := get_world_2d().direct_space_state
		_tri.clear()
		_tri_cols.clear()
		var view := o._drawn_view.grow(200.0)
		for g in o.shadow_groups:
			for body in get_tree().get_nodes_in_group(g):
				if not (body is CharacterBody2D or body is RigidBody2D) or not (body as CanvasItem).is_visible_in_tree():
					continue
				var at := o.to_local(body.global_position)
				if not view.has_point(at):
					continue
				var q := PhysicsRayQueryParameters2D.create(body.global_position, body.global_position + Vector2(0, 900), o.style.shadow_mask)
				q.exclude = [body.get_rid()]
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					continue
				var ground := o.to_local(hit.position)
				var dist := ground.y - at.y
				var id: int = body.get_instance_id()
				var stand: float = minf(_stand.get(id, dist), dist)
				_stand[id] = stand
				var height := maxf(dist - stand, 0.0)
				if not _widths.has(id):
					_widths[id] = _width_of(body)
				var width := maxf(_widths[id], 40.0)
				var spread := 1.0 + height / 380.0
				var alpha := o.style.shadow_strength * clampf(1.0 - height / 520.0, 0.15, 1.0)
				var ry := width * 0.2 * spread
				_ellipse(Vector2(at.x, ground.y - ry * 0.9), width * 0.75 * spread, ry, alpha)
		if _tri.size() >= 3:
			var idx := PackedInt32Array()
			idx.resize(_tri.size())
			for i in _tri.size():
				idx[i] = i
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, _tri, _tri_cols)

	static func _width_of(body: Node) -> float:
		for c in body.get_children():
			if c is CollisionShape2D and c.shape:
				var s: Vector2 = (c as Node2D).global_transform.get_scale().abs()
				return c.shape.get_rect().size.x * s.x
		return 44.0

	func _ellipse(c: Vector2, rx: float, ry: float, alpha: float) -> void:
		var dark := Color(0, 0, 0, alpha)
		var clear := Color(0, 0, 0, 0)
		var prev := c + Vector2(rx, 0)
		for i in range(1, 21):
			var ang := TAU * float(i) / 20.0
			var p := c + Vector2(cos(ang) * rx, sin(ang) * ry)
			_tri.append_array(PackedVector2Array([c, prev, p]))
			_tri_cols.append_array(PackedColorArray([dark, clear, clear]))
			prev = p

## A rectangle kept over the view (the light falloff and vignette).
class _ViewCover extends Node2D:
	var rect := Rect2()

	func cover(r: Rect2) -> void:
		if not r.is_equal_approx(rect):
			rect = r
			queue_redraw()

	func _draw() -> void:
		draw_rect(rect, Color.WHITE)
