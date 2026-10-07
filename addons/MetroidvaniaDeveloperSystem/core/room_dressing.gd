@tool
class_name MDSRoomDressing
extends RefCounted
## Room dressing helpers for quickly dressed or generated rooms, where props float, sink into
## floors or stand inside each other:
##
## - [method fit_to_floor]: objects that stand (save points, shops, NPCs, see
##   [method MDSRoomObjects.stands]) are put on the floor under them, or lifted out of the
##   ground they are buried in, then stepped along their floor out of any platform.
## - [method declutter]: taking objects in order of importance, each one that overlaps another
##   steps sideways along its own floor to the nearest clear spot, at least a gap away from
##   everything; a decoration with nowhere to go is removed.
## - [method overlaps]: the objects that stand in or behind each other (the Issues tab's
##   "objects overlap").
##
## Importance ([enum Rank]): fixtures (doors, machines, ladders, lifts, protected areas) and
## enemies never move, then objects that stand move first, then everything else, bigger first.
## Art drawn behind the room (z below 0) is scenery, not an object.
##
## The ground comes from an [MDSRoomCheck] built for the room (its physics copy: tiles,
## freeform shapes by role, static bodies). Rects are the objects' visible art
## ([method MDSRoomObjects.visual_rect], trimmed). Both return edits
## [code]{node, kind ("move" or "remove"), from, to}[/code] (positions in the node's parent's
## space) that [method apply] makes, or the Room view records as undoable scene edits.
## [codeblock]
## var check := MDSRoomCheck.new()
## check.build_from_scene(room, host)
## MDSRoomDressing.apply(MDSRoomDressing.fit_to_floor(room, check))
## MDSRoomDressing.apply(MDSRoomDressing.declutter(room, check))
## check.free_proxy()
## [/codeblock]

enum Rank { FIXED, ENEMY, STANDS, OTHER }

## How far an object may step along its floor, and in what steps.
const STEP := 16.0
const REACH := 640.0
## Overlap smaller than this share of the smaller object is two things touching.
const TOLERANCE := 0.08
## Space left between objects that were separated.
const GAP := 8.0
## A new spot's floor may be this much higher or lower than the old one's.
const SAME_FLOOR := 14.0
## How far down a floor is looked for under an object, and up out of the ground.
const MAX_DROP := 1200.0
const MAX_LIFT := 400.0
## Objects wider than this are scenery (bridges, trains, big backdrops), not something to move.
const MAX_WIDTH := 700.0
## Words in names of things that belong exactly where they are.
const FIXED_WORDS: PackedStringArray = ["door", "gate", "teleporter", "elevator", "lift", "ladder", "rope", "bridge", "wheel", "seesaw", "catapult", "spring", "piston", "train", "lever", "switch"]
const ENEMY_GROUPS: PackedStringArray = ["enemy", "enemies", "boss", "bosses", "mini_boss"]

# --- What objects are ----------------------------------------------------------------------------

static func rank(node: Node) -> Rank:
	if MDSRoomObjects.is_protected(node) or node.is_in_group(&"idp_fixed") or bool(node.get_meta(&"idp_fixed", false)):
		return Rank.FIXED
	if node is AnimatableBody2D or node is Path2D or node is PathFollow2D:
		return Rank.FIXED
	var n := String(node.name).to_lower()
	for w in FIXED_WORDS:
		if n.contains(w):
			return Rank.FIXED
	for g in ENEMY_GROUPS:
		if node.is_in_group(g):
			return Rank.ENEMY
	if MDSRoomObjects.stands(node):
		return Rank.STANDS
	return Rank.OTHER

## Something only there to be looked at, which may be removed when it has nowhere to go: no
## collision, no script, no gameplay group in it, and not standing ([code]idp_decoration[/code]
## metadata forces it either way).
static func is_decoration(node: Node) -> bool:
	if node.has_meta(&"idp_decoration"):
		return bool(node.get_meta(&"idp_decoration"))
	if rank(node) != Rank.OTHER:
		return false
	for n in [node] + node.find_children("*", "", true, false):
		if n is CollisionObject2D or n.get_script() != null:
			return false
		if not n.get_groups().filter(func(g: StringName) -> bool: return not String(g).begins_with("_")).is_empty():
			return false
	return true

## The z the node is drawn at (relative z indices added up to [param root]).
static func effective_z(node: Node, root: Node) -> int:
	var z := 0
	var n := node
	while n and n != root:
		if n is CanvasItem:
			z += (n as CanvasItem).z_index
			if not (n as CanvasItem).z_as_relative:
				return z
		n = n.get_parent()
	return z

## The objects the tools work on, with their rects ([code]{node, rect, rank}[/code]): visible,
## not drawn behind the room, not as wide as scenery, not removed in the Room view.
static func objects(root: Node, painter: MDSRoomPainter = null) -> Array:
	var out: Array = []
	for o in MDSRoomObjects.objects(root):
		if painter and painter.is_scene_node_hidden(o):
			continue
		# Static bodies are terrain and platforms, never props.
		if o is StaticBody2D:
			continue
		if o is CanvasItem and not (o as CanvasItem).visible:
			continue
		if effective_z(o, root) < 0:
			continue
		var r := rect_of(o, root, painter)
		if r.size.x <= 1.0 or r.size.y <= 1.0 or r.size.x > MAX_WIDTH:
			continue
		out.append({"node": o, "rect": r, "rank": rank(o)})
	return out

## The visible art of [param node] relative to [param root], with the Room view's moves.
static func rect_of(node: Node, root: Node, painter: MDSRoomPainter = null) -> Rect2:
	var r := MDSRoomObjects.visual_rect(node, root, true)
	if painter:
		r.position += painter.scene_offset(node)
	return r

static func _hits(r: Rect2, b: Rect2) -> bool:
	var i := r.intersection(b)
	return i.has_area() and i.get_area() > TOLERANCE * minf(r.get_area(), b.get_area())

## Pairs of objects that stand in or behind each other: [code]{a, b, rect}[/code] (paths from
## [param root], the overlap). Two fixtures or two enemies overlapping are left alone (a guard
## pair, a door in its frame).
static func overlaps(root: Node, painter: MDSRoomPainter = null) -> Array:
	var out: Array = []
	var objs := objects(root, painter)
	for i in objs.size():
		for j in range(i + 1, objs.size()):
			var a: Dictionary = objs[i]
			var b: Dictionary = objs[j]
			if a.rank == b.rank and a.rank <= Rank.ENEMY:
				continue
			if a.node.is_ancestor_of(b.node) or b.node.is_ancestor_of(a.node):
				continue
			if _hits(a.rect, b.rect):
				out.append({"a": String(root.get_path_to(a.node)), "b": String(root.get_path_to(b.node)), "rect": (a.rect as Rect2).intersection(b.rect)})
	return out

# --- The floor ------------------------------------------------------------------------------------

## Builds the ground the tools stand objects on: an [MDSRoomCheck] of the room (the Room view's
## [param painter], else the scene [param root]) under [param host] (a node in the tree), without
## the objects' own bodies. Free it with [method MDSRoomCheck.free_proxy].
static func ground_check(host: Node, root: Node, painter: MDSRoomPainter = null, room_rects: Array[Rect2] = []) -> MDSRoomCheck:
	var c := MDSRoomCheck.new()
	c.room_rects = room_rects
	for o in objects(root, painter):
		c.skip_nodes[o.node] = true
	if painter:
		c.build_from_painter(painter, host)
	else:
		c.build_from_scene(root, host)
	return c

## The floor under [param feet] (room space): the top of the ground or platform below it, or of
## the ground it is buried in. NAN when there is none in reach.
static func floor_under(check: MDSRoomCheck, feet: Vector2) -> float:
	var mask := MDSRoomCheck.GROUND | MDSRoomCheck.PLATFORM
	if check.solid_at(feet + Vector2(0, -2.0)):
		# Buried: up to where the ground ends.
		var y := feet.y - 2.0
		while y > feet.y - MAX_LIFT:
			y -= 8.0
			if not check.solid_at(Vector2(feet.x, y)):
				var hit := check.ray(Vector2(feet.x, y), Vector2(feet.x, feet.y + 4.0), MDSRoomCheck.GROUND)
				return hit.position.y if not hit.is_empty() else y
		return NAN
	var down := check.ray(feet + Vector2(0, -4.0), feet + Vector2(0, MAX_DROP), mask)
	return down.position.y if not down.is_empty() else NAN

## Moves [param node] by [param delta] (room space) in its parent's space: the new position.
static func _moved(node: Node2D, root: Node, delta: Vector2, painter: MDSRoomPainter) -> Vector2:
	var parent := node.get_parent()
	var basis := MDSRoomObjects.local_transform(parent, root) if parent and parent != root else Transform2D.IDENTITY
	basis.origin = Vector2.ZERO
	var from := painter.scene_position(node) if painter else node.position
	return from + basis.affine_inverse() * delta

static func _edit(node: Node2D, root: Node, delta: Vector2, painter: MDSRoomPainter) -> Dictionary:
	var from := painter.scene_position(node) if painter else node.position
	return {"node": node, "kind": "move", "from": from, "to": _moved(node, root, delta, painter)}

# --- Fit to the floor -----------------------------------------------------------------------------

## Stands every standing object (or those in [param nodes]) on the floor under it, then steps it
## along that floor out of the platforms. Returns the edits.
static func fit_to_floor(root: Node, check: MDSRoomCheck, painter: MDSRoomPainter = null, nodes: Array = []) -> Array:
	var edits: Array = []
	var platforms: Array[Rect2] = []
	for p in check.platforms:
		platforms.append(MDSGeometry.bounds(p.outline))
	for o in objects(root, painter):
		var node: Node2D = o.node
		if not nodes.is_empty() and not node in nodes:
			continue
		if nodes.is_empty() and o.rank != Rank.STANDS:
			continue
		var r: Rect2 = o.rect
		var feet := Vector2(r.get_center().x, r.end.y)
		var floor_y := floor_under(check, feet)
		if is_nan(floor_y):
			continue
		var delta := Vector2(0, floor_y - feet.y)
		r.position += delta
		# Out of the platforms standing in it, along the same floor.
		if platforms.any(func(b: Rect2) -> bool: return r.grow(-1.0).intersects(b)):
			var dx := _clear_spot(check, r, floor_y, platforms, [])
			if is_finite(dx):
				delta.x += dx
				var f2 := floor_under(check, Vector2(r.get_center().x + dx, r.end.y))
				if is_finite(f2):
					delta.y += f2 - floor_y
		if delta.length() > 0.5:
			edits.append(_edit(node, root, delta, painter))
	return edits

## The nearest sideways shift (either way, within reach) that puts [param r] clear of
## [param blockers] (and at least [param gap] from [param spaced]) on the same floor as
## [param floor_y] (any height when it is NAN: a hanging object), out of the ground. INF when
## there is none.
static func _clear_spot(check: MDSRoomCheck, r: Rect2, floor_y: float, blockers: Array[Rect2], spaced: Array[Rect2], gap := GAP) -> float:
	var room := check.room_bounds()
	var d := STEP
	while d <= REACH:
		for dir in [-1.0, 1.0]:
			var dx: float = dir * d
			var cand := Rect2(r.position + Vector2(dx, 0.0), r.size)
			if room.has_area() and not room.grow(1.0).encloses(cand):
				continue
			if blockers.any(func(b: Rect2) -> bool: return cand.grow(-1.0).intersects(b)):
				continue
			if spaced.any(func(b: Rect2) -> bool: return cand.grow(gap).intersects(b)):
				continue
			if is_finite(floor_y):
				var f := floor_under(check, Vector2(cand.get_center().x, floor_y))
				if not is_finite(f) or absf(f - floor_y) > SAME_FLOOR:
					continue
			elif check.solid_at(cand.get_center()):
				continue
			return dx
		d += STEP
	return INF

# --- Declutter ------------------------------------------------------------------------------------

## Separates objects that stand in or behind each other: in order of importance, each one that
## overlaps one already placed (or a platform, for objects that aren't fixed) steps sideways along
## its floor to the nearest spot at least [param gap] from everything; a decoration with nowhere
## to go is removed, anything else stays. Returns the edits.
static func declutter(root: Node, check: MDSRoomCheck, painter: MDSRoomPainter = null, gap := GAP) -> Array:
	var edits: Array = []
	var objs := objects(root, painter)
	var platforms: Array[Rect2] = []
	for p in check.platforms:
		platforms.append(MDSGeometry.bounds(p.outline))
	# Fixtures and enemies first (never moved), then what stands, then the rest; big first.
	objs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.rank != b.rank:
			return a.rank < b.rank
		return (a.rect as Rect2).get_area() > (b.rect as Rect2).get_area())
	var placed: Array[Rect2] = []
	for o in objs:
		var r: Rect2 = o.rect
		if o.rank <= Rank.ENEMY:
			placed.append(r)
			continue
		var blocked := placed.any(func(b: Rect2) -> bool: return _hits(r, b)) or platforms.any(func(b: Rect2) -> bool: return _hits(r, b))
		if not blocked:
			placed.append(r)
			continue
		var feet := Vector2(r.get_center().x, r.end.y)
		# Its floor: right under it (a hanging thing has none).
		var hit := check.ray(feet + Vector2(0, -24.0), feet + Vector2(0, 64.0))
		var floor_y: float = hit.position.y if not hit.is_empty() else NAN
		var dx := _clear_spot(check, r, floor_y, platforms, placed, gap)
		if is_finite(dx):
			var delta := Vector2(dx, 0.0)
			if is_finite(floor_y):
				var f := floor_under(check, Vector2(feet.x + dx, floor_y))
				if is_finite(f):
					delta.y = f - floor_y
			edits.append(_edit(o.node, root, delta, painter))
			placed.append(Rect2(r.position + delta, r.size))
		elif is_decoration(o.node):
			edits.append({"node": o.node, "kind": "remove", "from": painter.scene_position(o.node) if painter else o.node.position, "to": Vector2.ZERO})
		else:
			placed.append(r)
	return edits

## Makes [param edits]: in the Room view's [param painter] (undoable scene edits: call its
## checkpoint() first), or on the nodes themselves.
static func apply(edits: Array, painter: MDSRoomPainter = null) -> void:
	for e in edits:
		var node: Node2D = e.node
		if not is_instance_valid(node):
			continue
		if e.kind == "remove":
			if painter:
				painter.remove_scene_node(node)
			else:
				node.queue_free()
		elif painter:
			painter.move_scene_node(node, e.to)
		else:
			node.position = e.to
