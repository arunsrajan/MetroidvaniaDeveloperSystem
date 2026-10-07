@tool
class_name MDSRoomCheck
extends RefCounted
## Physics-level checks of a room's real geometry: whether the player actually gets through.
## The room graph can say a door exists while rock closes it; these catch that.
##
## The room's collision (tile layers, solid freeform shapes, static bodies) is copied into a
## physics proxy under a host node (ideally a [SubViewport], which has a physics space of its
## own), and then:
## - [b]passages[/b]: every gate is open at its edge of the room, wide enough for the player;
## - [b]platforms[/b]: every platform is landed on at its top, with headroom above it;
## - [b]standing objects[/b] (save points, shops, NPCs...): ground under them, not buried;
## - [b]climbs[/b]: a player-sized body jumps from floor to floor, and every exit up out of the
##   room is reached from where the player comes in. The floors it reaches make the
##   reachability overlay of the Room view.
## The player is described by the world's [code]settings.player[/code] (size, jump velocity,
## gravity, run speed, head clearance), see [constant PLAYER_DEFAULTS].
##
## [codeblock]
## var check := MDSRoomCheck.new(world.get_setting("player", {}))
## check.passages = MDSRoomCheck.passages_from_world(world, room_id)
## check.room_rects = world.get_local_rects(room_id)
## check.build_from_scene(scene_instance, host)   # host: a node in the tree
## var issues := check.run()                        # [{kind, message, pos}]
## check.free_proxy()
## [/codeblock]

const GROUND := 1
const PLATFORM := 2
const DT := 1.0 / 60.0
## Player defaults: 32 x 64 body, a 700 px/s jump under 900 px/s² gravity (272 px high).
const PLAYER_DEFAULTS := {"size": [32.0, 64.0], "jump_velocity": 700.0, "gravity": 900.0, "run_speed": 300.0, "head_clearance": 90.0}
## Gates are tested this far (px) either side of their position along the room's edge.
const GATE_WINDOW := 256.0
## The most physics steps a climb may try, per room.
const MAX_JUMPS := 500
const KINDS := {"passage": "Passage blocked", "headroom": "No headroom", "landing": "Platform can't be landed on", "floating": "Floating", "buried": "Buried", "climb": "Exit out of reach"}

var player_size := Vector2(32, 64)
var jump_velocity := 700.0
var gravity := 900.0
var run_speed := 300.0
var head_clearance := 90.0

## The room's shape (scene-local rectangles).
var room_rects: Array[Rect2] = []
## Ways in and out: [{name, pos (scene-local), side ("left", "right", "top", "bot", "door")}].
var passages: Array = []
## Found by [method run]: [{kind, message, pos}].
var issues: Array = []
## Floors found by [method run]: [{points: PackedVector2Array, reachable: bool}].
var surfaces: Array = []
## Platforms of the room: [{name, outline (scene-local)}].
var platforms: Array = []
## Objects that stand on the floor: [{name, feet}].
var standing: Array = []

var proxy: Node2D
## Nodes (keys) whose bodies are left out of the physics copy (the dressing tools leave out the
## objects' own bodies, so an object never stands on itself).
var skip_nodes: Dictionary = {}
var _ground: StaticBody2D
var _platforms: StaticBody2D
var _probe: CharacterBody2D
var _space: PhysicsDirectSpaceState2D
var _jumps := 0

func _init(settings: Dictionary = {}) -> void:
	configure(settings)

## Reads the player description ([code]settings.player[/code] of a world).
func configure(s: Dictionary) -> void:
	var d := PLAYER_DEFAULTS.duplicate()
	d.merge(s, true)
	var size: Variant = d.size
	player_size = Vector2(float(size[0]), float(size[1])) if size is Array and size.size() == 2 else Vector2(32, 64)
	jump_velocity = absf(float(d.jump_velocity))
	gravity = maxf(1.0, float(d.gravity))
	run_speed = maxf(1.0, float(d.run_speed))
	head_clearance = float(d.head_clearance)

## How high a jump reaches: v² / 2g.
static func max_jump_height(velocity: float, grav: float) -> float:
	return velocity * velocity / (2.0 * maxf(grav, 1.0))

func get_max_jump_height() -> float:
	return max_jump_height(jump_velocity, gravity)

# --- Passages ------------------------------------------------------------------------------------

## The gates of a world room as passages.
static func passages_from_world(world: MDSWorld, id: String) -> Array:
	var out: Array = []
	for g in world.get_gates(id):
		out.append({"name": g, "pos": world.get_gate_local_pos(id, g), "side": world.get_gate_side(id, g)})
	return out

## The passages of a MetSys room, in its scene's coordinates.
static func passages_from_metsys(model: MDSMapModel, room: MDSMapModel.Room, cell_size: Vector2) -> Array:
	var out: Array = []
	var sides := ["right", "bot", "left", "top"]
	for door: MDSMapModel.Door in model.doors.values():
		for end in [[door.a_room, door.a_cell, door.a_dir], [door.b_room, door.b_cell, (door.a_dir + 2) % 4]]:
			if end[0] != room:
				continue
			var cell: Vector3i = end[1]
			var local := Vector2(cell.x - room.min_cell.x, cell.y - room.min_cell.y)
			var pos := (local + Vector2(0.5, 0.5) + Vector2(MDSMapModel.FWD[end[2]]) * 0.5) * cell_size
			out.append({"name": "%s (%d,%d)" % [sides[end[2]], cell.x, cell.y], "pos": pos, "side": sides[end[2]]})
	return out

## A MetSys room's cells as scene-local rectangles.
static func rects_from_metsys(room: MDSMapModel.Room, cell_size: Vector2) -> Array[Rect2]:
	var cells: Dictionary = {}
	for c in room.cells:
		cells[Vector2i(c.x, c.y) - room.min_cell] = true
	return MDSGeometry.cells_to_rects(cells, cell_size)

# --- Proxy ---------------------------------------------------------------------------------------

## Builds the physics copy of a room scene instance (in the tree or not) under
## [param host], which must be in the tree.
func build_from_scene(root: Node, host: Node) -> void:
	_begin()
	_add_node(root, root, false)
	_collect_standing(root)
	_finish(host)

## Builds the physics copy of the room the Room view is editing: its edited tile layers and
## shapes, and the rest of its scene.
func build_from_painter(painter: MDSRoomPainter, host: Node) -> void:
	_begin()
	for n in MDSRoomPainter.LAYER_ORDER:
		_add_tile_layer(painter.layers[n], painter.layers[n].transform)
	for f in MDSFreeform.shapes_in(painter.items_root):
		_add_freeform(f, MDSRoomObjects.local_transform(f, painter.items_root))
	_add_node(painter.root, painter.root, true, painter)
	_collect_standing(painter.root, painter)
	_finish(host)

func free_proxy() -> void:
	if is_instance_valid(proxy):
		if proxy.get_parent():
			proxy.get_parent().remove_child(proxy)
		proxy.free()
	proxy = null
	_space = null

func _begin() -> void:
	free_proxy()
	platforms.clear()
	standing.clear()
	proxy = Node2D.new()
	proxy.name = "MDSRoomCheckProxy"
	_ground = StaticBody2D.new()
	_ground.collision_layer = GROUND
	_ground.collision_mask = 0
	proxy.add_child(_ground)
	_platforms = StaticBody2D.new()
	_platforms.collision_layer = PLATFORM
	_platforms.collision_mask = 0
	proxy.add_child(_platforms)

func _finish(host: Node) -> void:
	_probe = CharacterBody2D.new()
	_probe.collision_layer = 0
	_probe.collision_mask = GROUND | PLATFORM
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = player_size
	cs.shape = rect
	_probe.add_child(cs)
	_probe.position = Vector2(-1e6, -1e6)
	proxy.add_child(_probe)
	host.add_child(proxy)
	# A motion test makes the physics server take in the new shapes now, even where it isn't
	# stepping (the editor).
	_probe.test_move(_probe.global_transform, Vector2(0, 1))
	_space = proxy.get_world_2d().direct_space_state

## Whether a node of the painter's scene was hidden or removed in the Room view.
static func _gone(node: Node, painter: MDSRoomPainter) -> bool:
	return painter != null and painter.is_scene_node_hidden(node)

func _add_node(node: Node, root: Node, skip_painted: bool, painter: MDSRoomPainter = null) -> void:
	if node.has_meta(&"idp_blockout") or _gone(node, painter) or skip_nodes.has(node):
		return
	if node is TileMapLayer:
		if not skip_painted:
			_add_tile_layer(node, MDSRoomObjects.local_transform(node, root))
		return
	if node is MDSFreeform:
		if not skip_painted:
			_add_freeform(node, MDSRoomObjects.local_transform(node, root))
		return
	if (node is StaticBody2D or node is AnimatableBody2D) and node.process_mode != Node.PROCESS_MODE_DISABLED:
		for c in node.get_children():
			if c is CollisionShape2D or c is CollisionPolygon2D:
				_add_shape(c, MDSRoomObjects.local_transform(c, root), String(node.name))
	for c in node.get_children():
		_add_node(c, root, skip_painted, painter)

func _add_polygon(poly: PackedVector2Array, one_way: bool, solids := true) -> void:
	var cp := CollisionPolygon2D.new()
	cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS if solids else CollisionPolygon2D.BUILD_SEGMENTS
	cp.polygon = poly
	cp.one_way_collision = one_way
	(_platforms if one_way else _ground).add_child(cp)

func _add_tile_layer(layer: TileMapLayer, xform: Transform2D) -> void:
	if not layer.enabled or not layer.collision_enabled or not layer.tile_set or layer.tile_set.get_physics_layers_count() == 0:
		return
	var ts := layer.tile_set
	var half := Vector2(ts.tile_size) / 2.0
	var full: Dictionary = {}
	var one_way_full: Dictionary = {}
	for cell in layer.get_used_cells():
		if not ts.has_source(layer.get_cell_source_id(cell)):
			continue # a tile whose source is gone from the tileset
		var td := layer.get_cell_tile_data(cell)
		if not td:
			continue
		var center := layer.map_to_local(cell)
		for pl in ts.get_physics_layers_count():
			for pi in td.get_collision_polygons_count(pl):
				var pts := td.get_collision_polygon_points(pl, pi)
				var one_way := td.is_collision_polygon_one_way(pl, pi)
				if pts.size() == 4 and MDSGeometry.bounds(pts).is_equal_approx(Rect2(-half, half * 2.0)) and ts.tile_shape == TileSet.TILE_SHAPE_SQUARE:
					(one_way_full if one_way else full)[cell] = true
				elif pts.size() >= 3:
					var poly := PackedVector2Array()
					for p in pts:
						poly.append(xform * (center + p))
					_add_polygon(poly, one_way)
	# Full tiles merged into rectangles (cell (x, y) covers (x, y) * tile_size).
	for cells in [full, one_way_full]:
		for r in MDSGeometry.cells_to_rects(cells, Vector2(ts.tile_size), layer.map_to_local(Vector2i.ZERO) - half):
			var poly := xform * MDSGeometry.rect_polygon(r)
			_add_polygon(poly, cells == one_way_full)
			if cells == one_way_full:
				platforms.append({"name": "%s tiles" % layer.name, "outline": poly})

func _add_freeform(f: MDSFreeform, xform: Transform2D) -> void:
	if not f.is_collider() or f.points.size() < 3:
		return
	var outline := f.get_outline()
	if not MDSGeometry.is_simple(outline):
		return # it collides with nothing in the game either
	var poly := xform * outline
	_add_polygon(poly, f.is_one_way())
	if f.is_platform() or f.is_one_way():
		platforms.append({"name": String(f.name), "outline": poly})

func _add_shape(c: Node2D, xform: Transform2D, body_name: String) -> void:
	if c is CollisionShape2D:
		var cs := c as CollisionShape2D
		if cs.disabled or not cs.shape:
			return
		var copy := CollisionShape2D.new()
		copy.shape = cs.shape
		copy.transform = xform
		copy.one_way_collision = cs.one_way_collision
		(_platforms if cs.one_way_collision else _ground).add_child(copy)
		if cs.one_way_collision:
			platforms.append({"name": body_name, "outline": xform * MDSGeometry.rect_polygon(cs.shape.get_rect())})
	else:
		var cp := c as CollisionPolygon2D
		if cp.disabled or cp.polygon.size() < 3:
			return
		var poly := xform * cp.polygon
		if cp.build_mode == CollisionPolygon2D.BUILD_SOLIDS and not MDSGeometry.is_simple(poly):
			return
		_add_polygon(poly, cp.one_way_collision, cp.build_mode == CollisionPolygon2D.BUILD_SOLIDS)
		if cp.one_way_collision:
			platforms.append({"name": body_name, "outline": poly})

func _collect_standing(root: Node, painter: MDSRoomPainter = null) -> void:
	for o in MDSRoomObjects.objects(root):
		if MDSRoomObjects.stands(o) and not _gone(o, painter):
			var feet := MDSRoomObjects.feet(o, root) + (painter.scene_offset(o) if painter else Vector2.ZERO)
			standing.append({"name": String(root.get_path_to(o)), "feet": feet})

# --- Queries -------------------------------------------------------------------------------------

func solid_at(p: Vector2, mask := GROUND) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = mask
	return not _space.intersect_point(q, 1).is_empty()

func ray(a: Vector2, b: Vector2, mask := GROUND | PLATFORM) -> Dictionary:
	var q := PhysicsRayQueryParameters2D.create(a, b, mask)
	return _space.intersect_ray(q)

func box_free(center: Vector2, size: Vector2, mask := GROUND) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	q.shape = r
	q.transform = Transform2D(0.0, center)
	q.collision_mask = mask
	return _space.intersect_shape(q, 1).is_empty()

func room_bounds() -> Rect2:
	if room_rects.is_empty():
		return Rect2()
	var b := room_rects[0]
	for r in room_rects:
		b = b.merge(r)
	return b

func in_room(p: Vector2) -> bool:
	for r in room_rects:
		if r.grow(1.0).has_point(p):
			return true
	return room_rects.is_empty()

# --- Checks --------------------------------------------------------------------------------------

## Runs every check on the built proxy. [param room_name] prefixes the messages.
func run(room_name := "") -> Array:
	issues.clear()
	surfaces.clear()
	_jumps = 0
	if not _space:
		return issues
	var prefix := room_name + ": " if not room_name.is_empty() else ""
	for p in passages:
		_check_passage(p, prefix)
	for pl in platforms:
		_check_platform(pl, prefix)
	for s in standing:
		_check_standing(s, prefix)
	if not room_rects.is_empty():
		_reachability(prefix)
	return issues

func _issue(kind: String, message: String, pos: Vector2) -> void:
	issues.append({"kind": kind, "message": message, "pos": pos})

const INWARD := {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bot": Vector2.UP}

func _check_passage(p: Dictionary, prefix: String) -> void:
	var pos: Vector2 = p.pos
	var side: String = p.side
	if not INWARD.has(side):
		var lifted := pos + Vector2(0, -player_size.y / 2.0 - 2.0)
		if not box_free(lifted, player_size * 0.9) and not box_free(pos, player_size * 0.9):
			_issue("passage", "%sdoor %s is inside terrain: the player can't stand in it" % [prefix, p.name], pos)
		return
	var along_x := side == "top" or side == "bot"
	var inward: Vector2 = INWARD[side]
	var lo := (pos.x if along_x else pos.y) - GATE_WINDOW
	var hi := (pos.x if along_x else pos.y) + GATE_WINDOW
	# Only along the room's own edge there.
	for r in room_rects:
		var on_edge := false
		match side:
			"left": on_edge = absf(r.position.x - pos.x) < 2.0 and pos.y >= r.position.y - 2.0 and pos.y <= r.end.y + 2.0
			"right": on_edge = absf(r.end.x - pos.x) < 2.0 and pos.y >= r.position.y - 2.0 and pos.y <= r.end.y + 2.0
			"top": on_edge = absf(r.position.y - pos.y) < 2.0 and pos.x >= r.position.x - 2.0 and pos.x <= r.end.x + 2.0
			"bot": on_edge = absf(r.end.y - pos.y) < 2.0 and pos.x >= r.position.x - 2.0 and pos.x <= r.end.x + 2.0
		if on_edge:
			lo = maxf(lo, r.position.x if along_x else r.position.y)
			hi = minf(hi, r.end.x if along_x else r.end.y)
			break
	var need := player_size.x + 16.0 if along_x else player_size.y + 8.0
	var best := 0.0
	var run_len := 0.0
	var t := lo + 2.0
	while t <= hi - 2.0:
		var probe := (Vector2(t, pos.y) if along_x else Vector2(pos.x, t)) + inward * 8.0
		if solid_at(probe):
			run_len = 0.0
		else:
			run_len += 4.0
			best = maxf(best, run_len)
		t += 4.0
	if best < need:
		_issue("passage", "%sgate %s is blocked by terrain: the widest opening along the %s edge near it is %d px, the player needs %d" % [prefix, p.name, side, int(best), int(need)], pos)

## The top of [param outline] at [param x] (going down), or INF.
static func _top_at(outline: PackedVector2Array, x: float) -> float:
	var b := MDSGeometry.bounds(outline)
	var y := MDSGeometry.solid_from(outline, x, b.position.y - 2.0, b.end.y + 1.0)
	return y if y < b.end.y else INF

func _check_platform(pl: Dictionary, prefix: String) -> void:
	var outline: PackedVector2Array = pl.outline
	var b := MDSGeometry.bounds(outline)
	var x := b.get_center().x
	var top := _top_at(outline, x)
	if top == INF:
		return
	var hit := ray(Vector2(x, top - 40.0), Vector2(x, top + 40.0))
	if hit.is_empty() or absf(hit.position.y - top) > 3.0:
		_issue("landing", "%splatform %s can't be landed on at its top (something covers it)" % [prefix, pl.name], Vector2(x, top))
		return
	var blocked := 0
	var center_blocked := false
	var least := head_clearance
	for k in 3:
		var xx: float = [x, lerpf(b.position.x, b.end.x, 0.25), lerpf(b.position.x, b.end.x, 0.75)][k]
		var t := _top_at(outline, xx)
		if t == INF:
			continue
		var up := ray(Vector2(xx, t - 3.0), Vector2(xx, t - head_clearance), GROUND)
		if not up.is_empty():
			blocked += 1
			center_blocked = center_blocked or k == 0
			least = minf(least, t - up.position.y)
	if center_blocked or blocked >= 2:
		_issue("headroom", "%splatform %s has %d px of headroom; the player needs %d" % [prefix, pl.name, int(least), int(head_clearance)], Vector2(x, top))

func _check_standing(s: Dictionary, prefix: String) -> void:
	var f: Vector2 = s.feet
	if solid_at(f + Vector2(0, -12.0)) and solid_at(f + Vector2(0, -player_size.y * 0.5)):
		_issue("buried", "%s%s is buried in terrain" % [prefix, s.name], f)
		return
	if ray(f + Vector2(0, -24.0), f + Vector2(0, 48.0)).is_empty():
		_issue("floating", "%s%s floats: no ground within 48 px under it" % [prefix, s.name], f)

# --- Reachability and climbs ----------------------------------------------------------------------

## Floors in a column: where solid starts with room for the player above, going down.
func _floors_in_column(x: float, b: Rect2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var y := b.position.y + 2.0
	var was_solid := solid_at(Vector2(x + 0.31, y), GROUND | PLATFORM)
	while y < b.end.y + 48.0:
		y += 4.0
		var solid := solid_at(Vector2(x + 0.31, y), GROUND | PLATFORM)
		if solid and not was_solid:
			var hit := ray(Vector2(x + 0.31, y - 5.0), Vector2(x + 0.31, y + 1.0))
			var top: float = hit.position.y if not hit.is_empty() else y
			if in_room(Vector2(x, top - 4.0)) and box_free(Vector2(x, top - player_size.y / 2.0 - 1.5), Vector2(player_size.x * 0.6, player_size.y - 2.0)):
				out.append(top)
		was_solid = solid
	return out

## Groups column floors into surfaces (runs of floor the player can walk along).
func _build_surfaces() -> void:
	var b := room_bounds()
	var step := 16.0
	var open: Array = [] # surfaces of the previous column
	var x := b.position.x + maxf(8.0, player_size.x * 0.5)
	while x <= b.end.x - maxf(8.0, player_size.x * 0.5):
		var next: Array = []
		for y in _floors_in_column(x, b):
			var joined: Dictionary = {}
			for s in open:
				var last: Vector2 = s.points[s.points.size() - 1]
				if absf(last.y - y) <= 12.0:
					joined = s
					break
			if joined.is_empty():
				joined = {"points": PackedVector2Array(), "reachable": false}
				surfaces.append(joined)
			else:
				open.erase(joined)
			var pts: PackedVector2Array = joined.points
			pts.append(Vector2(x, y))
			joined.points = pts
			next.append(joined)
		open = next
		x += step

func _surface_near(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 40.0
	for s in surfaces:
		for q in s.points:
			var d: float = q.distance_to(p)
			if d < best_d:
				best_d = d
				best = s
	return best

## Where the player stands after coming in through a passage: down from just inside it.
func _arrival(p: Dictionary) -> Dictionary:
	var side: String = p.side
	var inward: Vector2 = INWARD.get(side, Vector2.ZERO)
	var start: Vector2 = p.pos + inward * maxf(48.0, player_size.x)
	if side == "bot":
		start = p.pos + Vector2(0, -player_size.y * 2.0)
	var hit := ray(start, start + Vector2(0, room_bounds().size.y + 200.0))
	return _surface_near(hit.position) if not hit.is_empty() else {}

func _reachability(prefix: String) -> void:
	_build_surfaces()
	if surfaces.is_empty():
		return
	var queue: Array = []
	for p in passages:
		var s := _arrival(p)
		if not s.is_empty() and not s.reachable:
			s.reachable = true
			queue.append(s)
	if queue.is_empty():
		var lowest: Dictionary = surfaces[0]
		for s in surfaces:
			if s.points[0].y > lowest.points[0].y:
				lowest = s
		lowest.reachable = true
		queue.append(lowest)
	var h := get_max_jump_height()
	while not queue.is_empty() and _jumps < MAX_JUMPS:
		var s: Dictionary = queue.pop_front()
		for t in surfaces:
			if t.reachable or not _may_reach(s, t, h):
				continue
			if _jump_between(s, t):
				t.reachable = true
				queue.append(t)
	# Exits up out of the room.
	for p in passages:
		if p.side != "top":
			continue
		var out := false
		for s in surfaces:
			if s.reachable and _may_exit(s, p, h) and _jump_out(s, p):
				out = true
				break
		if not out:
			var highest := INF
			for s in surfaces:
				if s.reachable:
					for q in s.points:
						highest = minf(highest, q.y)
			_issue("climb", "%sthe exit %s can't be reached by jumping (the highest floor the player reaches is %d px below it; a jump rises %d px)" % [prefix, p.name, int(highest - p.pos.y) if highest != INF else 0, int(h)], p.pos)

func _span(s: Dictionary) -> Vector2:
	return Vector2(s.points[0].x, s.points[s.points.size() - 1].x)

func _top(s: Dictionary) -> float:
	var y := INF
	for q in s.points:
		y = minf(y, q.y)
	return y

## Rough reach of a jump from [param s] to [param t]: not too high, not too far.
func _may_reach(s: Dictionary, t: Dictionary, h: float) -> bool:
	var rise := _top(s) - _top(t) # > 0: t is higher
	if rise > h - 4.0:
		return false
	var a := _span(s)
	var b := _span(t)
	var gap := maxf(0.0, maxf(b.x - a.y, a.x - b.y))
	var air := (jump_velocity + sqrt(maxf(0.0, jump_velocity * jump_velocity - 2.0 * gravity * rise))) / gravity
	return gap <= run_speed * air + player_size.x

func _may_exit(s: Dictionary, p: Dictionary, h: float) -> bool:
	var rise: float = _top(s) - p.pos.y
	if rise > h + player_size.y * 0.5:
		return false
	var a := _span(s)
	var gap := maxf(0.0, maxf(p.pos.x - a.y, a.x - p.pos.x))
	return gap <= run_speed * (2.0 * jump_velocity / gravity) + player_size.x

## The point of [param s] nearest x, kept a little inside its ends.
func _point_toward(s: Dictionary, x: float) -> Vector2:
	var best: Vector2 = s.points[0]
	for q in s.points:
		if absf(q.x - x) < absf(best.x - x):
			best = q
	return best

func _jump_between(s: Dictionary, t: Dictionary) -> bool:
	var tb := _span(t)
	var from_mid := (_span(s).x + _span(s).y) / 2.0
	for tries in 2:
		var tx := clampf(from_mid, tb.x + 8.0, tb.y - 8.0) if tb.y - tb.x > 16.0 else (tb.x + tb.y) / 2.0
		var from := _point_toward(s, tx) if tries == 0 else _point_toward(s, from_mid)
		var r := simulate_jump(from, tx)
		if r.landed and r.pos.x >= tb.x - 12.0 and r.pos.x <= tb.y + 12.0:
			var ty := _point_toward(t, r.pos.x).y
			if absf(r.pos.y - ty) <= 14.0:
				return true
	return false

func _jump_out(s: Dictionary, p: Dictionary) -> bool:
	var from := _point_toward(s, p.pos.x)
	return simulate_jump(from, p.pos.x, p.pos.y).exited

## Jumps a player-sized body from a floor point toward [param target_x], steering in the
## air. Returns {landed, exited (passed above [param exit_y]), pos (feet), peak (highest
## feet y)}.
func simulate_jump(from: Vector2, target_x: float, exit_y := -INF) -> Dictionary:
	_jumps += 1
	var half := player_size.y / 2.0
	_probe.global_position = from + Vector2(0, -half - 1.0)
	var vel := Vector2(0, -jump_velocity)
	var peak := from.y
	var floor_y := room_bounds().end.y + 400.0
	for i in 300:
		vel.x = clampf((target_x - _probe.global_position.x) * 6.0, -run_speed, run_speed)
		vel.y = minf(vel.y + gravity * DT, 2000.0)
		var motion := vel * DT
		for k in 3:
			var col := _probe.move_and_collide(motion)
			if not col:
				break
			var n := col.get_normal()
			if n.y < -0.65 and vel.y >= 0.0 and i > 2:
				return {"landed": true, "exited": false, "pos": _probe.global_position + Vector2(0, half), "peak": peak}
			if n.y > 0.65:
				vel.y = maxf(vel.y, 0.0)
			motion = col.get_remainder().slide(n)
			vel = vel.slide(n)
		var feet := _probe.global_position.y + half
		peak = minf(peak, feet)
		if _probe.global_position.y < exit_y:
			return {"landed": false, "exited": true, "pos": _probe.global_position + Vector2(0, half), "peak": peak}
		if feet > floor_y:
			break
	return {"landed": false, "exited": false, "pos": _probe.global_position + Vector2(0, half), "peak": peak}
