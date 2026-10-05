@tool
class_name IDPFreeformDecorator
extends RefCounted
## Decorate freeform: scenery placed relative to a room's freeform rock, kept out of
## doorways and away from everything in the room.
## - [b]Hanging[/b]: stamps (ivy, hanging moss...) hung under ceilings and ledges.
## - [b]Floor plants[/b]: stamps (ferns, flowers, grass...) along floors.
## - [b]Structures[/b]: background shapes from [IDPShapeGenerators] (broken columns, ruined
##   arches, garden walls, mounds) standing on flat floors, with leaf stamps on top; and
##   stalactite curtains under flat ceilings.
## - [b]Foreground framing[/b]: leaf silhouettes in the room's free corners.
## Everything goes into the Room view's item groups (shapes and stamps it can edit
## afterwards) and is tagged, so running it again replaces it: the same seed gives the same
## room. No editor dependencies.

const META := &"idp_decor"
## Structures and plants are spread over regions of this size (a screen).
const REGION := Vector2(1152, 648)

var stamp_set: IDPStampSet
var hanging := true
## Stamp category hung under ceilings ("" = none).
var hanging_category := ""
var floor_plants := true
## Stamp categories placed on floors.
var floor_categories: PackedStringArray = []
var structures := true
## [enum IDPShapeGenerators.Kind]s to build.
var structure_kinds: Array[int] = [IDPShapeGenerators.Kind.COLUMN, IDPShapeGenerators.Kind.ARCH, IDPShapeGenerators.Kind.GARDEN_WALL]
## Style of the structures (non-solid, behind). Empty: the built-in plain background.
var structure_style: IDPFreeformStyle
## Stamp category put on top of structures ("" = none).
var leaf_category := ""
var foreground := true
## Style of the foreground leaves. Empty: the built-in foreground silhouette.
var foreground_style: IDPFreeformStyle
## More or less of everything (1 = normal).
var density := 1.0
var seed_value := 0
## The room's shape (scene-local) and gates [{name, pos, side}].
var room_rects: Array[Rect2] = []
var gates: Array = []

## What was placed: [{node, kind, rect}].
var placed: Array = []
## Areas nothing is placed over: doorways, room above platforms, objects.
var keep_out: Array[Rect2] = []

var rect := Rect2()
var _rock: Array[PackedVector2Array] = []
var _rng := RandomNumberGenerator.new()

func use_world_room(world: IDPWorld, id: String) -> void:
	room_rects = world.get_local_rects(id)
	gates = IDPRoomCheck.passages_from_world(world, id)

## Decorates the room [param painter] edits (call [method IDPRoomPainter.checkpoint]
## first). Returns {hanging, plants, structures, foreground, removed (earlier decoration)}.
func decorate(painter: IDPRoomPainter) -> Dictionary:
	var report := {"hanging": 0, "plants": 0, "structures": 0, "foreground": 0, "removed": 0}
	placed.clear()
	_rng.seed = hash("idp_decor_%d" % seed_value)
	for g in IDPRoomPainter.ITEM_GROUPS:
		for item in painter.items(g):
			if item.has_meta(META):
				painter.remove_item(item)
				report.removed += 1
	_rock.clear()
	var platforms: Array = []
	for f in IDPFreeform.shapes_in(painter.items_root):
		if f.is_collider() and f.points.size() >= 3:
			var poly := IDPRoomObjects.local_transform(f, painter.items_root) * f.get_outline()
			_rock.append(poly)
			if f.is_platform():
				platforms.append(poly)
	_rock.append_array(_tile_rock(painter.layers["Terrain"]))
	if room_rects.is_empty():
		var b := Rect2()
		for i in _rock.size():
			b = IDPGeometry.bounds(_rock[i]) if i == 0 else b.merge(IDPGeometry.bounds(_rock[i]))
		room_rects = [b]
	rect = room_rects[0]
	for r in room_rects:
		rect = rect.merge(r)
	# Keep-out: the converter's doorways and zones.
	var conv := IDPFreeformConverter.new()
	conv.set_room(room_rects, gates)
	var doors := conv.find_openings(_rock)
	conv.find_zones(painter, platforms, doors)
	keep_out.clear()
	keep_out.append_array(doors)
	keep_out.append_array(conv.busy)
	keep_out.append_array(conv.headroom)
	if hanging and stamp_set and not hanging_category.is_empty():
		report.hanging = _hang(painter)
	if floor_plants and stamp_set and not floor_categories.is_empty():
		report.plants = _plants(painter)
	if structures and not structure_kinds.is_empty():
		report.structures = _structures(painter)
	if foreground:
		report.foreground = _foreground(painter)
	return report

## Solid tiles of the Terrain layer as rectangles (rock, for tests of where rock is).
func _tile_rock(layer: TileMapLayer) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var ts := layer.tile_set
	if not ts:
		return out
	var cells: Dictionary = {}
	for c in layer.get_used_cells():
		if not ts.has_source(layer.get_cell_source_id(c)):
			continue
		var td := layer.get_cell_tile_data(c)
		if ts.get_physics_layers_count() == 0 or (td and td.get_collision_polygons_count(0) > 0):
			cells[c] = true
	var half := Vector2(ts.tile_size) / 2.0
	for r in IDPGeometry.cells_to_rects(cells, Vector2(ts.tile_size), layer.map_to_local(Vector2i.ZERO) - half):
		out.append(layer.transform * IDPGeometry.rect_polygon(r))
	return out

func _in_rock(p: Vector2) -> bool:
	return IDPGeometry.point_in_any(_rock, p)

func _in_room(p: Vector2, inset := 8.0) -> bool:
	for r in room_rects:
		if r.grow(-inset).has_point(p):
			return true
	return false

func _blocked(r: Rect2) -> bool:
	for k in keep_out:
		if k.intersects(r):
			return true
	return false

func _tag(node: Node, kind: String, r: Rect2) -> void:
	node.set_meta(META, true)
	placed.append({"node": node, "kind": kind, "rect": r})

## The area a stamp covers.
func _stamp_rect(index: int, pos: Vector2, size: float) -> Rect2:
	var region := stamp_set.regions[index].size * size
	return Rect2(pos - stamp_set.anchor(index) * region, region)

func _stamp(painter: IDPRoomPainter, category: String, pos: Vector2, size: float, rot: float, group: String, kind: String) -> Sprite2D:
	var picks := stamp_set.indices(category)
	if picks.is_empty():
		return null
	var index := picks[_rng.randi_range(0, picks.size() - 1)]
	var r := _stamp_rect(index, pos, size)
	if _blocked(r):
		return null
	var s := painter.add_stamp(stamp_set, index, pos, Vector2(size * (-1.0 if _rng.randf() < 0.5 else 1.0), size), rot, group)
	_tag(s, kind, r)
	return s

## Points every [param spacing] px (varied) along edge runs facing [param dir].
func _along(dir: Vector2, spacing: float) -> Array:
	var out: Array = []
	for poly in _rock:
		for run in IDPFreeform.edge_runs(poly, IDPFreeform.outward_normals(poly), dir, 50.0):
			var travelled := 0.0
			var next := spacing * _rng.randf_range(0.3, 1.0)
			for i in range(1, run.size()):
				var seg: Vector2 = run[i] - run[i - 1]
				var ln := seg.length()
				while travelled + ln >= next:
					out.append(run[i - 1] + seg * ((next - travelled) / maxf(ln, 0.001)))
					next += spacing * _rng.randf_range(0.6, 1.4)
				travelled += ln
	return out

func _hang(painter: IDPRoomPainter) -> int:
	var n := 0
	for p: Vector2 in _along(Vector2.DOWN, 150.0 / maxf(density, 0.1)):
		if not _in_room(p) or _in_rock(p + Vector2(0, 16)):
			continue
		if _stamp(painter, hanging_category, p + Vector2(0, -4), _rng.randf_range(0.55, 1.0), _rng.randf_range(-0.06, 0.06), "StampsBack", "hanging"):
			n += 1
	return n

func _plants(painter: IDPRoomPainter) -> int:
	var n := 0
	for p: Vector2 in _along(Vector2.UP, 80.0 / maxf(density, 0.1)):
		if not _in_room(p) or _in_rock(p + Vector2(0, -16)):
			continue
		var cat := floor_categories[_rng.randi_range(0, floor_categories.size() - 1)]
		if _stamp(painter, cat, p + Vector2(0, 4), _rng.randf_range(0.55, 0.9), _rng.randf_range(-0.05, 0.05), "StampsBack", "plant"):
			n += 1
	return n

## Every rock top (floor) under (x, y0) down to y1, going down.
func _floors(x: float, y0: float, y1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var was := _in_rock(Vector2(x + 0.071, y0))
	var y := y0
	while y < y1:
		y += 2.0
		var now := _in_rock(Vector2(x + 0.071, y + 0.137))
		if now and not was:
			out.append(y)
		was = now
	return out

## Going up from (x, y): where the first rock ends (a ceiling's underside), or [param limit].
func _ceiling(x: float, y: float, limit: float) -> float:
	var yy := y
	while yy > limit:
		yy -= 2.0
		if _in_rock(Vector2(x + 0.071, yy + 0.137)):
			return yy
	return limit

## A floor flat (within 18 px) from x0 to x1 in [param region], or -1.
func _flat_floor(x0: float, x1: float, region: Rect2) -> float:
	var options := _floors(lerpf(x0, x1, 0.5), region.position.y, region.end.y + 40.0)
	if options.is_empty():
		return -1.0
	var floor_y := options[_rng.randi_range(0, options.size() - 1)]
	for i in 7:
		var x := lerpf(x0, x1, i / 6.0)
		var ys := _floors(x, floor_y - 30.0, floor_y + 30.0)
		if ys.is_empty() or _in_rock(Vector2(x + 0.071, floor_y - 20.0)):
			return -1.0
		floor_y = minf(floor_y, ys[0])
	return floor_y

func _regions() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in room_rects:
		var cols := maxi(1, roundi(r.size.x / REGION.x))
		var rows := maxi(1, roundi(r.size.y / REGION.y))
		var size := r.size / Vector2(cols, rows)
		for y in rows:
			for x in cols:
				out.append(Rect2(r.position + Vector2(x, y) * size, size))
	return out

func _structures(painter: IDPRoomPainter) -> int:
	var count := 0
	var taken: Array[Rect2] = []
	var st := structure_style if structure_style else IDPFreeformStyle.builtins()[1]
	var per_region := maxi(1, roundi(2.0 * density))
	for region in _regions():
		var made := 0
		for attempt in 40:
			if made >= per_region:
				break
			var kind: int = structure_kinds[_rng.randi_range(0, structure_kinds.size() - 1)]
			var w := IDPShapeGenerators.WIDTHS[kind] * _rng.randf_range(0.85, 1.15)
			if w > region.size.x - 120.0:
				continue
			var x := _rng.randf_range(region.position.x + w * 0.5 + 60.0, region.end.x - w * 0.5 - 60.0)
			var box: Rect2
			if IDPShapeGenerators.is_standing(kind):
				var floor_y := _flat_floor(x - w * 0.5, x + w * 0.5, region)
				if floor_y < 0.0:
					continue
				var ceil_y := _ceiling(x, floor_y - 40.0, region.position.y - 96.0)
				var room_h := floor_y - ceil_y
				var h := 0.0
				match kind:
					IDPShapeGenerators.Kind.COLUMN, IDPShapeGenerators.Kind.ARCH:
						h = minf(_rng.randf_range(250.0, 400.0), room_h - 70.0)
						if h < 120.0:
							continue
					IDPShapeGenerators.Kind.MOUND:
						h = _rng.randf_range(50.0, 90.0)
					_:
						h = _rng.randf_range(70.0, 110.0)
				box = Rect2(x - w * 0.5, floor_y - h, w, h)
			else:
				# Hanging: under a flat stretch of ceiling.
				var y := region.get_center().y
				if _in_rock(Vector2(x, y)):
					continue
				var top := _ceiling(x, y, region.position.y - 96.0)
				if top <= region.position.y - 96.0:
					continue
				var flat := true
				for i in 5:
					var xx := lerpf(x - w * 0.5, x + w * 0.5, i / 4.0)
					if absf(_ceiling(xx, top + 40.0, top - 40.0) - top) > 16.0 or _in_rock(Vector2(xx, top + 30.0)):
						flat = false
				if not flat:
					continue
				box = Rect2(x - w * 0.5, top, w, _rng.randf_range(60.0, 140.0))
			if not _in_room(box.get_center(), 0.0) or _blocked(box) or taken.any(func(t: Rect2) -> bool: return t.grow(80.0).intersects(box)):
				continue
			var d := IDPShapeGenerators.make(kind, box, _rng)
			if not IDPGeometry.is_simple(IDPFreeform.outline_of(d.points, d.smooth)):
				continue
			taken.append(box)
			count += 1
			made += 1
			var f := painter.add_freeform(d.points, st, "FreeformBack", false)
			f.smooth = d.smooth
			f.seed_value = _rng.randi() % 100000
			f.name = "%s%d" % [IDPShapeGenerators.NAMES[kind].get_slice(" ", 0), count]
			_tag(f, "structure", box)
			if stamp_set and not leaf_category.is_empty() and IDPShapeGenerators.is_standing(kind):
				for k in _rng.randi_range(1, 2):
					_stamp(painter, leaf_category, Vector2(x + _rng.randf_range(-w * 0.5, w * 0.5), box.position.y + _rng.randf_range(-10.0, 50.0)), _rng.randf_range(0.6, 0.95), 0.0, "StampsBack", "leaves")
	return count

## Leaves in front of the room in its corners: a bush where a floor meets a side wall and a
## hanging mass where the ceiling does, only where nothing in the room is behind them.
func _foreground(painter: IDPRoomPainter) -> int:
	var count := 0
	var st := foreground_style if foreground_style else IDPFreeformStyle.builtins()[2]
	var margin := 96.0
	for side in [-1, 1]:
		var edge_x: float = rect.position.x if side < 0 else rect.end.x
		var x: float = edge_x - side * 200.0
		# Floor corner: the lowest floor near that side.
		var floors := _floors(x, rect.end.y - REGION.y, rect.end.y + 40.0)
		if not floors.is_empty() and _in_room(Vector2(x, floors[floors.size() - 1] - 20.0)):
			var fy: float = floors[floors.size() - 1]
			var w := _rng.randf_range(200.0, 300.0)
			var h := _rng.randf_range(60.0, 110.0)
			var area := Rect2(minf(edge_x, edge_x - side * w), fy - h, w, h)
			if not _blocked(area):
				var pts := PackedVector2Array([Vector2(edge_x + side * margin, fy + 80.0), Vector2(edge_x + side * margin, fy - h)])
				for j in range(1, 5):
					var t := float(j) / 5.0
					pts.append(Vector2(edge_x - side * w * t, fy - h * (1.0 - t * t) + _rng.randf_range(-12.0, 8.0)))
				pts.append(Vector2(edge_x - side * w, fy + 80.0))
				count += _front_shape(painter, pts, st, area, count)
		# Ceiling corner: where the rock above that side ends.
		var cy := _ceiling(x, rect.position.y + REGION.y * 0.5, rect.position.y - margin)
		if cy > rect.position.y - margin + 1.0 and _in_room(Vector2(x, cy + 20.0)):
			var w := _rng.randf_range(220.0, 340.0)
			var droop := _rng.randf_range(30.0, 70.0)
			var area := Rect2(minf(edge_x, edge_x - side * w), cy, w, droop)
			if not _blocked(area):
				var pts := PackedVector2Array([Vector2(edge_x + side * margin, rect.position.y - margin), Vector2(edge_x - side * w, rect.position.y - margin)])
				for j in range(5, -1, -1):
					var t := float(j) / 5.0
					pts.append(Vector2(edge_x - side * w * t, cy + droop * (1.0 - t) * (1.0 - t) * 1.2 + _rng.randf_range(-6.0, 10.0)))
				pts.append(Vector2(edge_x + side * margin, cy + droop))
				count += _front_shape(painter, pts, st, area, count)
	return count

func _front_shape(painter: IDPRoomPainter, pts: PackedVector2Array, st: IDPFreeformStyle, area: Rect2, count: int) -> int:
	if not IDPGeometry.is_simple(IDPFreeform.outline_of(pts, true)):
		return 0
	var f := painter.add_freeform(pts, st, "FreeformFront", false)
	f.seed_value = _rng.randi() % 100000
	f.name = "Leaves%d" % (count + 1)
	_tag(f, "foreground", area)
	return 1

## Stamp categories of [param set] that hang (anchored at their top) and that stand
## (anchored at their bottom), for the dialog's defaults.
static func categories_by_anchor(set: IDPStampSet) -> Dictionary:
	var hang: PackedStringArray = []
	var stand: PackedStringArray = []
	for cat in set.get_categories():
		var idx := set.indices(cat)
		if idx.is_empty():
			continue
		var a := set.anchor(idx[0])
		if a.y < 0.3:
			hang.append(cat)
		elif a.y > 0.7:
			stand.append(cat)
	return {"hang": hang, "stand": stand}
