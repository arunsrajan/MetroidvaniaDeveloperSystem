@tool
class_name MDSFreeformConverter
extends RefCounted
## Convert to freeform: turns a room blocked out with tiles, collision polygons or
## straight-edged freeform shapes into organic freeform terrain, keeping its layout: every
## doorway, step and floor stays where it was.
##
## - [b]Rock.[/b] The solid tiles, static bodies and blockout shapes join into as few shapes
##   as they make, running on past the room's edges (out of the camera's sight). Corners
##   become bowls (inside) and rounded lips (outside); walls bulge, ceilings sag and hang in
##   lobes, floors rise in low mounds. Never into a doorway, above a platform, or where
##   anything stands, see [member protect].
## - [b]Floors stay put[/b] under everything standing in the room (within 2.5 px).
## - [b]Platforms[/b] (one-way bodies and tiles, platform shapes) become one-way freeform
##   ledges with exactly their old top and a rounded underside.
## - [b]Background and Foreground tiles[/b] can become freeform back and front shapes.
## - The old terrain is hidden (kept in the scene, disabled) or removed.
## Everything goes through an [MDSRoomPainter], so the Room view can undo it, and tools and CI
## can run it on any room scene:
## [codeblock]
## var painter := MDSRoomPainter.open("res://rooms/cave_02.tscn")
## var conv := MDSFreeformConverter.new()
## conv.rock_style = load("res://styles/mossy_rock.freeform.tres")
## conv.use_world_room(world, "Cave_02")
## print(conv.convert(painter))
## painter.save()
## [/codeblock]

enum Edge { TOP, BOTTOM, SIDE }

# --- Options -----------------------------------------------------------------------------------

## Style of the rock (solid). Empty: the built-in plain rock.
var rock_style: MDSFreeformStyle
## Style of the ledges made from platforms. Empty: the rock style, as one-way platforms.
var ledge_style: MDSFreeformStyle
## Style the Background tiles become (non-solid, behind). Empty: they stay tiles.
var back_style: MDSFreeformStyle
## Style the Foreground tiles become (in front). Empty: they stay tiles.
var front_style: MDSFreeformStyle
## How much the faces grow (0 = only rounded corners, 1 = normal, 2 = wild).
var growth := 1.0
## Radius of rounded inside corners (bowls), px.
var bowl_radius := 64.0
## Radius of rounded outside corners (lips), px.
var lip_radius := 18.0
var seed_value := 0
## Keep the old terrain in the scene, hidden and without collision (true), or remove it.
var keep_old := true
## Convert solid freeform shapes with straight edges (smooth off) too.
var include_blockout := true
## How far rock runs on past the room's edge, px.
var margin := 96.0

# --- The room ------------------------------------------------------------------------------------

## The room's shape (scene-local). Empty: the bounds of its terrain.
var room_rects: Array[Rect2] = []
## Its gates [{name, pos, side}], named in [member openings].
var gates: Array = []

# --- Results -------------------------------------------------------------------------------------

## Ways in and out found along the room's edge: [{name, pos, side}] (for checking them).
var openings: Array = []
## Areas rock may not grow into.
var protect: Array[Rect2] = []
## Objects and the areas around them, which scenery keeps out of (Decorate freeform uses it).
var busy: Array[Rect2] = []
## Space above every platform.
var headroom: Array[Rect2] = []
## Floors that must not move: [x, y] under everything standing.
var standing: Array = []
## The new shapes: [{node, kind ("rock", "ledge", "back", "front"), top (ledges)}].
var made: Array = []

var rect := Rect2()
var _pins: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _lobe := FastNoiseLite.new()
var _on_edge := 0.6
var _warnings: PackedStringArray = []

## Sets the room's shape and gates (and its bounds, for [method find_openings] on its own).
func set_room(rects: Array, p_gates: Array) -> void:
	room_rects.assign(rects)
	gates = p_gates
	rect = room_rects[0] if not room_rects.is_empty() else Rect2()
	for r in room_rects:
		rect = rect.merge(r)

## Takes the room's shape and gates from a world.
func use_world_room(world: MDSWorld, id: String) -> void:
	room_rects = world.get_local_rects(id)
	gates = MDSRoomCheck.passages_from_world(world, id)

## Converts the room [param painter] is editing. Call [method MDSRoomPainter.checkpoint]
## first to make it undoable. Returns a report: {rock, ledges, back, front, old (nodes and
## tiles taken out), openings, warnings, error}.
func convert(painter: MDSRoomPainter) -> Dictionary:
	var report := {"rock": 0, "ledges": 0, "back": 0, "front": 0, "old": 0, "openings": 0, "warnings": PackedStringArray(), "error": ""}
	made.clear()
	_rng.seed = hash("mds_convert_%d" % seed_value)
	_noise.seed = _rng.randi()
	_noise.frequency = 0.0045
	_noise.fractal_octaves = 2
	_lobe.seed = _rng.randi()
	_lobe.frequency = 0.0026
	if not rock_style:
		rock_style = MDSFreeform._default_style()
	# 1. What the room is built of.
	var src := _read(painter)
	if src.solids.is_empty() and src.platforms.is_empty():
		report.error = "Nothing to convert: no solid tiles, static bodies or straight-edged freeform shapes."
		return report
	if room_rects.is_empty():
		var b := Rect2()
		var first := true
		for p in src.solids + src.platforms:
			b = MDSGeometry.bounds(p) if first else b.merge(MDSGeometry.bounds(p))
			first = false
		room_rects = [b]
	rect = room_rects[0]
	for r in room_rects:
		rect = rect.merge(r)
	_on_edge = maxf(0.6, src.tile * 0.5)
	# 2. Rock pieces, untied, running on past the room's edges.
	var sound: Array[PackedVector2Array] = []
	var twisted: Array[PackedVector2Array] = []
	for s in src.solids:
		if MDSGeometry.is_simple(s):
			sound.append(_run_on(s))
		else:
			for part in MDSGeometry.untwist(s):
				twisted.append(_run_on(part))
	var doors := find_openings(MDSGeometry.union_all(sound))
	find_zones(painter, src.platforms, doors)
	# Pieces that never collided (twisted) may not start colliding where they'd close a way.
	var pieces: Array[PackedVector2Array] = sound.duplicate()
	var ways: Array = doors.duplicate()
	ways.append_array(headroom)
	for t in twisted:
		pieces.append_array(MDSGeometry.clear_of(t, ways))
	var masses := MDSGeometry.union_all(pieces)
	standing = _standing(painter, masses)
	# 3. Out with the old.
	report.old = _take_out(painter, src)
	# 4. In with the new.
	_warnings.clear()
	var designs := _design_all(masses)
	var names: Dictionary = {}
	for i in masses.size():
		var f := _add(painter, "Freeform", _mass_name(masses[i], names), designs[i][0], rock_style, true, designs[i][1])
		made.append({"node": f, "kind": "rock"})
	report.rock = masses.size()
	var k := 0
	for pl in src.platforms:
		k += 1
		var b := MDSGeometry.bounds(pl)
		var nm: String = src.platform_names[k - 1] if k - 1 < src.platform_names.size() and not str(src.platform_names[k - 1]).is_empty() else "Ledge%d" % k
		var f := _ledge(painter, nm, b)
		made.append({"node": f, "kind": "ledge", "top": b.position.y})
	report.ledges = src.platforms.size()
	report.back = _soft_shapes(painter, src.back, back_style, "FreeformBack", "Back", "back")
	report.front = _soft_shapes(painter, src.front, front_style, "FreeformFront", "Leaves", "front")
	report.openings = openings.size()
	report.warnings = _warnings.duplicate()
	return report

# --- Reading the room ----------------------------------------------------------------------------

## {solids, platforms (polygons, scene-local), platform_names, back, front (polygons),
##  tiles: {layer: cells}, bodies: [nodes], items: [freeform blockout], tile (size)}
func _read(painter: MDSRoomPainter) -> Dictionary:
	var out := {"solids": [], "platforms": [], "platform_names": [], "back": [], "front": [], "tiles": {}, "bodies": [], "items": [], "tile": 0.0}
	var terrain: TileMapLayer = painter.layers["Terrain"]
	var ts := terrain.tile_set
	if ts:
		out.tile = float(ts.tile_size.x)
	_read_tiles(terrain, out, true)
	if back_style:
		_read_tiles(painter.layers["Background"], out, false, "back")
	if front_style:
		_read_tiles(painter.layers["Foreground"], out, false, "front")
	_read_bodies(painter.root, painter.root, painter, out)
	if include_blockout:
		for f in MDSFreeform.shapes_in(painter.items_root):
			if f.is_collider() and not f.smooth and f.points.size() >= 3:
				var poly := MDSRoomObjects.local_transform(f, painter.items_root) * f.get_outline()
				if f.is_platform():
					out.platforms.append(poly)
					out.platform_names.append(String(f.name))
				else:
					out.solids.append(poly)
				out.items.append(f)
	return out

## Tiles of a layer as polygons: solid ones (collision, or every tile when the tileset has no
## physics), one-way ones as platforms; [param into] collects every tile as art instead.
func _read_tiles(layer: TileMapLayer, out: Dictionary, solid: bool, into := "") -> void:
	var ts := layer.tile_set
	if not ts:
		return
	var has_physics := ts.get_physics_layers_count() > 0
	var half := Vector2(ts.tile_size) / 2.0
	var full: Dictionary = {}
	var one_way: Dictionary = {}
	var taken: Array = []
	for cell in layer.get_used_cells():
		if not MDSRoomPainter.is_cell_valid(layer, cell):
			continue # a tile the tileset no longer has: it draws nothing
		if not solid:
			full[cell] = true
			taken.append(cell)
			continue
		var td := layer.get_cell_tile_data(cell)
		if not has_physics:
			full[cell] = true
			taken.append(cell)
			continue
		if not td:
			continue
		var used := false
		for pl in ts.get_physics_layers_count():
			for pi in td.get_collision_polygons_count(pl):
				var pts := td.get_collision_polygon_points(pl, pi)
				var ow := td.is_collision_polygon_one_way(pl, pi)
				used = true
				if pts.size() == 4 and MDSGeometry.bounds(pts).is_equal_approx(Rect2(-half, half * 2.0)):
					(one_way if ow else full)[cell] = true
				elif pts.size() >= 3:
					var poly := PackedVector2Array()
					for p in pts:
						poly.append(layer.transform * (layer.map_to_local(cell) + p))
					(out.platforms if ow else out.solids).append(poly)
					if ow:
						out.platform_names.append("")
		if used:
			taken.append(cell)
	var origin := layer.map_to_local(Vector2i.ZERO) - half
	var key: String = into if not into.is_empty() else "solids"
	for r in MDSGeometry.cells_to_rects(full, Vector2(ts.tile_size), origin):
		out[key].append(layer.transform * MDSGeometry.rect_polygon(r))
	# One-way tiles: a ledge per horizontal run.
	var rows: Dictionary = {}
	for c: Vector2i in one_way:
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
	for y in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		for i in range(1, xs.size() + 1):
			if i < xs.size() and xs[i] == xs[i - 1] + 1:
				continue
			var r := Rect2(origin + Vector2(start, y) * Vector2(ts.tile_size), Vector2(xs[i - 1] - start + 1, 1) * Vector2(ts.tile_size))
			out.platforms.append(layer.transform * MDSGeometry.rect_polygon(r))
			out.platform_names.append("")
			if i < xs.size():
				start = xs[i]
	out.tiles[String(layer.name)] = taken

## Whether a static body is terrain to convert: [code]mds_convert[/code] metadata or group
## says so; else a body with no sprites, no script and no moving parts (moving platforms are
## AnimatableBody2D and stay).
static func is_convertible(node: Node) -> bool:
	if MDSLegacy.has_meta_key(node, &"mds_convert"):
		return bool(MDSLegacy.get_meta_key(node, &"mds_convert"))
	if MDSLegacy.in_group(node, &"mds_convert"):
		return true
	if not node is StaticBody2D or node is AnimatableBody2D or node.get_script() != null:
		return false
	for c in node.find_children("*", "", true, false):
		if c is Sprite2D or c is AnimatedSprite2D or c.get_script() != null:
			return false
	return true

func _read_bodies(node: Node, root: Node, painter: MDSRoomPainter, out: Dictionary) -> void:
	for c in node.get_children():
		if c is TileMapLayer or c is MDSFreeform or c is MDSGate or MDSLegacy.has_meta_key(c, &"mds_blockout") or painter.is_scene_node_hidden(c):
			continue
		if c is StaticBody2D and is_convertible(c):
			var any := false
			for s in c.find_children("*", "", true, false):
				var poly := PackedVector2Array()
				var ow := false
				if s is CollisionPolygon2D and not s.disabled and s.polygon.size() >= 3:
					poly = MDSRoomObjects.local_transform(s, root) * (s as CollisionPolygon2D).polygon
					ow = s.one_way_collision
				elif s is CollisionShape2D and not s.disabled and (s.shape is RectangleShape2D or s.shape is ConvexPolygonShape2D):
					var pts: PackedVector2Array = MDSGeometry.rect_polygon(s.shape.get_rect()) if s.shape is RectangleShape2D else (s.shape as ConvexPolygonShape2D).points
					poly = MDSRoomObjects.local_transform(s, root) * pts
					ow = s.one_way_collision
				if poly.size() < 3:
					continue
				any = true
				if ow:
					out.platforms.append(poly)
					out.platform_names.append(String(c.name))
				else:
					out.solids.append(poly)
			if any:
				out.bodies.append(c)
			continue
		_read_bodies(c, root, painter, out)

## Hides or removes what was converted. Returns how many tiles and nodes went.
func _take_out(painter: MDSRoomPainter, src: Dictionary) -> int:
	var n := 0
	for layer_name in src.tiles:
		var cells: Array = src.tiles[layer_name]
		if keep_old:
			painter.hide_cells(layer_name, cells)
		else:
			for c in cells:
				painter.layers[layer_name].erase_cell(c)
			painter.dirty = true
		n += cells.size()
	for b in src.bodies:
		if keep_old:
			painter.hide_scene_node(b)
		else:
			painter.remove_scene_node(b)
		n += 1
	for f in src.items:
		painter.remove_item(f)
		n += 1
	return n

# --- Rock ------------------------------------------------------------------------------------------

## A piece touching the room's edge, carried on [member margin] px past it: points on the edge
## move out. Openings stay open, because nothing that was not on the edge moves.
func _run_on(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		var q := p
		if absf(p.x - rect.position.x) <= _on_edge or p.x < rect.position.x:
			q.x = minf(p.x, rect.position.x) - margin
		elif absf(p.x - rect.end.x) <= _on_edge or p.x > rect.end.x:
			q.x = maxf(p.x, rect.end.x) + margin
		if absf(p.y - rect.position.y) <= _on_edge or p.y < rect.position.y:
			q.y = minf(p.y, rect.position.y) - margin
		elif absf(p.y - rect.end.y) <= _on_edge or p.y > rect.end.y:
			q.y = maxf(p.y, rect.end.y) + margin
		out.append(q)
	return MDSGeometry.dedupe(out)

func _in_room(p: Vector2) -> bool:
	for r in room_rects:
		if r.has_point(p):
			return true
	return false

## The room's ways out: every stretch of its outline with no rock just inside it, at least
## 24 px long. Returned as the corridors each needs kept clear inside the room; recorded in
## [member openings], named after the gate in them.
func find_openings(masses: Array[PackedVector2Array]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	openings.clear()
	for r in room_rects:
		var edges := [
			["top", r.position, Vector2.RIGHT, r.size.x, Vector2.UP],
			["bot", Vector2(r.position.x, r.end.y), Vector2.RIGHT, r.size.x, Vector2.DOWN],
			["left", r.position, Vector2.DOWN, r.size.y, Vector2.LEFT],
			["right", Vector2(r.end.x, r.position.y), Vector2.DOWN, r.size.y, Vector2.RIGHT],
		]
		for e in edges:
			var side: String = e[0]
			var a: Vector2 = e[1]
			var dir: Vector2 = e[2]
			var length: float = e[3]
			var n: Vector2 = e[4]
			var start := -1.0
			var t := 0.0
			while t <= length:
				var p := a + dir * t
				var open := t < length and not _in_room(p + n * 2.0) and not MDSGeometry.point_in_any(masses, p - n * 3.0)
				if open and start < 0.0:
					start = t
				elif not open and start >= 0.0:
					if t - start >= 24.0:
						var p0 := a + dir * start
						var p1 := a + dir * t
						var c: Rect2
						match side:
							"top": c = Rect2(p0.x - 48.0, p0.y - margin, t - start + 96.0, 300.0 + margin)
							"bot": c = Rect2(p0.x - 48.0, p0.y - 300.0, t - start + 96.0, 300.0 + margin)
							"left": c = Rect2(p0.x - margin, p0.y - 40.0, 300.0 + margin, t - start + 80.0)
							_: c = Rect2(p0.x - 300.0, p0.y - 40.0, 300.0 + margin, t - start + 80.0)
						out.append(c)
						var mid := (p0 + p1) / 2.0
						var gate_name := "opening%d" % (openings.size() + 1)
						for g in gates:
							if g.side == side and Geometry2D.get_closest_point_to_segment(g.pos, p0, p1).distance_to(g.pos) < 8.0:
								gate_name = g.name
						openings.append({"name": gate_name, "pos": mid, "side": side})
					start = -1.0
				t += 4.0
	return out

## What rock may not grow into ([member protect]) and scenery keeps out of
## ([member busy]): the doorways, room above every platform, and every object.
func find_zones(painter: MDSRoomPainter, platforms: Array, doors: Array[Rect2]) -> void:
	protect.clear()
	busy.clear()
	headroom.clear()
	_pins.clear()
	protect.append_array(doors)
	for pl in platforms:
		var b := MDSGeometry.bounds(pl)
		protect.append(Rect2(b.position.x - 36.0, b.position.y - 160.0, b.size.x + 72.0, 160.0 + maxf(b.size.y, 24.0) * 1.5 + 30.0))
		headroom.append(Rect2(b.position.x - 36.0, b.position.y - 200.0, b.size.x + 72.0, 200.0))
	for o in MDSRoomObjects.objects(painter.root):
		if painter.is_scene_node_hidden(o):
			continue
		var r := MDSRoomObjects.visual_rect(o, painter.root)
		r.position += painter.scene_offset(o)
		if MDSRoomObjects.stands(o):
			r = r.grow_individual(60.0, 80.0, 60.0, 20.0)
		elif MDSRoomObjects.is_big(o):
			r = r.grow(120.0)
		else:
			r = r.grow(40.0)
		protect.append(r)
		busy.append(r)
	for n in painter.root.find_children("*", "", true, false):
		if MDSRoomObjects.is_protected(n) and not painter.is_scene_node_hidden(n):
			var r := MDSRoomObjects.visual_rect(n, painter.root)
			protect.append(r)
			busy.append(r)

## Under everything resting on the rock: [x, the floor's height there].
func _standing(painter: MDSRoomPainter, masses: Array[PackedVector2Array]) -> Array:
	var out: Array = []
	for o in MDSRoomObjects.objects(painter.root):
		if painter.is_scene_node_hidden(o):
			continue
		var r := MDSRoomObjects.visual_rect(o, painter.root)
		r.position += painter.scene_offset(o)
		var xs := [r.get_center().x]
		if r.size.x > 24.0:
			xs.append_array([r.position.x + 8.0, r.end.x - 8.0])
		for x in xs:
			var y := r.end.y - 30.0
			if MDSGeometry.point_in_any(masses, Vector2(x + 0.071, y + 0.137)):
				# Sunk into the rock: its floor is the surface above.
				while y > r.end.y - 110.0 and MDSGeometry.point_in_any(masses, Vector2(x + 0.071, y + 0.137)):
					y -= 1.0
				if y > r.end.y - 110.0:
					out.append([x, y + 1.0])
				continue
			while y < r.end.y + 60.0 and not MDSGeometry.point_in_any(masses, Vector2(x + 0.071, y + 0.137)):
				y += 1.0
			if y < r.end.y + 60.0:
				out.append([x, y])
	return out

## Every mass designed, then the floor checked under everything standing on it: where it
## moved, that stretch is pinned and the mass designed again.
func _design_all(masses: Array[PackedVector2Array]) -> Array:
	var designs: Array = []
	for m in masses:
		designs.append(_design_valid(m))
	var off: PackedStringArray = []
	for attempt in 4:
		var moved := {}
		off.clear()
		for s in standing:
			var x: float = s[0]
			var want: float = s[1]
			for i in masses.size():
				if not Geometry2D.is_point_in_polygon(Vector2(x + 0.071, want + 2.137), masses[i]):
					continue
				var outline := MDSFreeform.outline_of(designs[i][0], designs[i][1])
				var y := MDSGeometry.solid_from(outline, x, want - 40.0, want + 40.0)
				if absf(y - want) > 2.5:
					var pin := Rect2(x - 170.0, want - 140.0, 340.0, 200.0)
					protect.append(pin)
					_pins.append(pin)
					moved[i] = true
					off.append("x %d: %+.1f px" % [int(x), y - want])
		if moved.is_empty():
			return designs
		for i in moved:
			designs[i] = _design_valid(masses[i])
	_warnings.append("The floor under some objects moved: " + ", ".join(off))
	return designs

## [points, smooth] for a mass, as long as the outline is simple; gentler designs are tried
## when it folds over itself (thin curls of rock), and last the mass as it was.
func _design_valid(mass: PackedVector2Array) -> Array:
	for attempt in [[1.0, true], [0.5, true], [0.0, true], [0.0, false]]:
		var pts := _design_rock(mass, attempt[0], attempt[1])
		if pts.size() >= 3 and MDSGeometry.is_simple(MDSFreeform.outline_of(pts, true)):
			return [pts, true]
	var plain := MDSGeometry.simplify_closed(mass, 2.0)
	return [plain if MDSGeometry.is_simple(plain) else mass, false]

## A mass as freeform control points: simplified, corners rounded, open faces grown by kind
## ([param amount] of [member growth]), all kept out of [member protect].
func _design_rock(mass: PackedVector2Array, amount := 1.0, round_corners := true) -> PackedVector2Array:
	var pts := MDSGeometry.simplify_closed(mass, 2.0)
	var n := pts.size()
	var sgn := 1.0 if MDSGeometry.signed_area(pts) > 0.0 else -1.0
	var inner := rect.grow(-2.0)
	var corners: Array = []
	for i in n:
		corners.append(_round_corner(pts[(i - 1 + n) % n], pts[i], pts[(i + 1) % n], sgn, inner) if round_corners else PackedVector2Array([pts[i]]))
	var out := PackedVector2Array()
	var s := 0.0
	for i in n:
		var here: PackedVector2Array = corners[i]
		var there: PackedVector2Array = corners[(i + 1) % n]
		for q in here:
			out.append(q)
		var a := here[here.size() - 1]
		var b := there[0]
		var d := b - a
		var length := d.length()
		if length < 1.0:
			continue
		var normal := Vector2(d.y, -d.x).normalized() * sgn
		var kind: Edge = Edge.TOP if normal.y < -0.75 else (Edge.BOTTOM if normal.y > 0.75 else Edge.SIDE)
		var spacing := 64.0 if kind == Edge.BOTTOM else 72.0
		var k := int(length / spacing) if length >= spacing * 2.0 else 0
		for j in range(1, k + 1):
			var q0 := a.lerp(b, float(j) / float(k + 1))
			var along := s + length * float(j) / float(k + 1)
			if not inner.has_point(q0):
				out.append(q0)
				continue
			out.append(q0 + normal * _clear_amount(q0, normal, _amount(kind, along) * amount * growth, out[out.size() - 1]))
		s += length
	return MDSGeometry.dedupe(out)

## Rounds the corner at p1 (between p0 and p2) into a lip or a bowl, or leaves it.
func _round_corner(p0: Vector2, p1: Vector2, p2: Vector2, sgn: float, inner: Rect2) -> PackedVector2Array:
	var d1 := (p1 - p0).normalized()
	var d2 := (p2 - p1).normalized()
	if _pins.any(func(r: Rect2) -> bool: return r.has_point(p1)):
		# Something stands by this corner: the curve is held to it by a point either side.
		var g := minf(4.0, minf(p0.distance_to(p1), p1.distance_to(p2)) / 3.0)
		return PackedVector2Array([p1 - d1 * g, p1, p1 + d2 * g])
	if absf(d1.angle_to(d2)) < deg_to_rad(25.0) or not inner.has_point(p1):
		return PackedVector2Array([p1])
	var convex := d1.cross(d2) * sgn > 0.0
	var r := minf(lip_radius if convex else bowl_radius, 0.4 * minf(p0.distance_to(p1), p1.distance_to(p2)))
	while r >= 6.0:
		var a := p1 - d1 * r
		var b := p1 + d2 * r
		if convex:
			return PackedVector2Array([a, b])
		# An inside corner fills with rock: only where nothing needs the room.
		var m := ((a + b) * 0.5).lerp(p1, 0.35)
		if not _triangle_hits(a, p1, b):
			return PackedVector2Array([a, m, b])
		r *= 0.5
	return PackedVector2Array([p1])

## How far rock grows out of a face at [param along] px round its outline: floors in low
## mounds now and then, ceilings sag and hang in deep lobes, walls bulge.
func _amount(kind: Edge, along: float) -> float:
	var v := clampf(_noise.get_noise_1d(along) / 0.55, -1.0, 1.0)
	match kind:
		Edge.TOP:
			return 16.0 * clampf((v - 0.15) / 0.85, 0.0, 1.0)
		Edge.BOTTOM:
			var lobe := clampf((_lobe.get_noise_1d(along) / 0.55 - 0.3) / 0.7, 0.0, 1.0)
			return 8.0 + 22.0 * (v * 0.5 + 0.5) + 64.0 * lobe * lobe
		_:
			return 6.0 + 24.0 * (v * 0.5 + 0.5)

## [param amount], halved until rock grown that far keeps out of everything protected.
func _clear_amount(q0: Vector2, normal: Vector2, amount: float, prev: Vector2) -> float:
	for attempt in 5:
		if amount < 1.0:
			return 0.0
		var q := q0 + normal * amount
		if not _hits(q, prev):
			return amount
		amount *= 0.5
	return 0.0

func _hits(q: Vector2, prev: Vector2) -> bool:
	for r in protect:
		if r.has_point(q) or MDSGeometry.segment_hits_rect(prev, q, r):
			return true
	return false

func _triangle_hits(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var tri := PackedVector2Array([a, b, c])
	for r in protect:
		if not Geometry2D.intersect_polygons(tri, MDSGeometry.rect_polygon(r)).is_empty():
			return true
	return false

func _mass_name(m: PackedVector2Array, names: Dictionary) -> String:
	var b := MDSGeometry.bounds(m)
	var low := b.end.y > rect.end.y
	var high := b.position.y < rect.position.y
	var base := "Rock" if low and high else ("Ground" if low else ("Ceiling" if high else "Outcrop"))
	names[base] = int(names.get(base, 0)) + 1
	return base if names[base] == 1 else "%s%d" % [base, names[base]]

# --- Shapes ----------------------------------------------------------------------------------------

func _add(painter: MDSRoomPainter, group: String, shape_name: String, pts: PackedVector2Array, st: MDSFreeformStyle, solid: bool, smooth := true, pos := Vector2.ZERO) -> MDSFreeform:
	var f := painter.add_freeform(pts, st, group, solid)
	f.smooth = smooth
	f.position = pos
	f.seed_value = _rng.randi() % 100000
	f.name = shape_name
	return f

## A platform as a ledge: its top exactly, edge to edge, and under it a rounded belly no
## deeper than the platform was (40 px at least).
func _ledge(painter: MDSRoomPainter, ledge_name: String, b: Rect2) -> MDSFreeform:
	var half := b.size.x * 0.5
	var h := maxf(b.size.y, 40.0)
	var pts := PackedVector2Array([Vector2(-half, 0), Vector2(-half + 10.0, 0)])
	var k := maxi(1, int(b.size.x / 60.0))
	for j in range(1, k):
		pts.append(Vector2(lerpf(-half + 10.0, half - 10.0, float(j) / k), 0))
	pts.append_array([Vector2(half - 10.0, 0), Vector2(half, 0), Vector2(half + 3.0, h * 0.38)])
	pts.append(Vector2(half * 0.64 + _rng.randf_range(-6, 6), h * _rng.randf_range(0.8, 0.95)))
	pts.append(Vector2(half * 0.2 + _rng.randf_range(-8, 8), h * _rng.randf_range(0.95, 1.1)))
	pts.append(Vector2(-half * 0.35 + _rng.randf_range(-8, 8), h * _rng.randf_range(0.9, 1.05)))
	pts.append(Vector2(-half * 0.7 + _rng.randf_range(-6, 6), h * _rng.randf_range(0.75, 0.9)))
	pts.append(Vector2(-half - 3.0, h * 0.38))
	var st := ledge_style if ledge_style else rock_style
	var f := _add(painter, "Freeform", ledge_name, pts, st, true, true, Vector2(b.get_center().x, b.position.y))
	if not (st.get_role() == MDSFreeformStyle.Role.PLATFORM and st.is_one_way()):
		f.set_collision_override(MDSFreeformStyle.Role.PLATFORM, true)
	if not MDSGeometry.is_simple(f.get_outline()):
		f.smooth = false
	return f

## Background or foreground tiles as freeform shapes: joined, simplified, corners rounded.
func _soft_shapes(painter: MDSRoomPainter, polys: Array, st: MDSFreeformStyle, group: String, base: String, kind: String) -> int:
	if not st or polys.is_empty():
		return 0
	var pieces: Array[PackedVector2Array] = []
	for p in polys:
		pieces.append(_run_on(p))
	var count := 0
	for m in MDSGeometry.union_all(pieces, INF):
		var pts := MDSGeometry.simplify_closed(m, 3.0)
		var smooth := MDSGeometry.is_simple(MDSFreeform.outline_of(pts, true))
		count += 1
		var f := _add(painter, group, "%s%d" % [base, count] if count > 1 else base, pts if smooth else m, st, false, smooth)
		made.append({"node": f, "kind": kind})
	return count
