@tool
class_name MDSNotchFill
extends RefCounted
## Fill outside shape: an irregular room's scene covers its bounding box, but the cells of the
## box outside the room's shape on the map (its notches) belong to the neighbouring rooms.
## They are drawn as non-solid freeform shapes in a "deep ground" style, over the rock's edges,
## and never collide: passages may lead into them. No editor dependencies.
##
## The shapes are decorations ([enum MDSFreeformStyle.Role] DECOR), so the map silhouette, the
## scanner and the checks ignore them. They carry the room shape they were made for (metadata
## [code]idp_fill_outside[/code]), so the Room view redoes them when the shape changes.

const META := &"idp_fill_outside"
## How far the fill runs past the room's box (out of the camera's sight).
const MARGIN := 96.0

## The parts of the room's box outside its shape ([param rects], scene-local), carried
## [param margin] px past the box's edges.
static func outside_polygons(rects: Array, margin := MARGIN) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if rects.size() < 2:
		return out
	var box: Rect2 = rects[0]
	for r: Rect2 in rects:
		box = box.merge(r)
	for part in MDSGeometry.rect_minus(box, rects):
		if absf(MDSGeometry.signed_area(part)) < 64.0:
			continue
		var run := PackedVector2Array()
		for p in part:
			var q := p
			if absf(p.x - box.position.x) < 0.5:
				q.x -= margin
			elif absf(p.x - box.end.x) < 0.5:
				q.x += margin
			if absf(p.y - box.position.y) < 0.5:
				q.y -= margin
			elif absf(p.y - box.end.y) < 0.5:
				q.y += margin
			run.append(q)
		out.append(MDSGeometry.dedupe(run))
	return out

## What a fill was made for: the room's shape.
static func signature(rects: Array) -> String:
	return JSON.stringify(rects.map(func(r: Rect2) -> Array: return [r.position.x, r.position.y, r.size.x, r.size.y]))

## The fill shapes of the room [param painter] edits.
static func shapes_of(painter: MDSRoomPainter) -> Array[MDSFreeform]:
	var out: Array[MDSFreeform] = []
	for f in MDSFreeform.shapes_in(painter.items_root):
		if f.has_meta(META):
			out.append(f)
	return out

## Whether the room's fill was made for another shape than [param rects].
static func is_stale(painter: MDSRoomPainter, rects: Array) -> bool:
	var sig := signature(rects)
	for f in shapes_of(painter):
		if str(f.get_meta(META)) != sig:
			return true
	return false

## Replaces the room's fill with shapes of [param style] covering the box outside
## [param rects]. Call [method MDSRoomPainter.checkpoint] first. Returns how many shapes.
static func fill(painter: MDSRoomPainter, rects: Array, style: MDSFreeformStyle, margin := MARGIN) -> int:
	for f in shapes_of(painter):
		painter.remove_item(f)
	var sig := signature(rects)
	var n := 0
	for poly in outside_polygons(rects, margin):
		var f := painter.add_freeform(poly, style, "Freeform", false)
		_set_up(f, sig, n)
		n += 1
	return n

## Adds fill shapes to a scene being built (Create scene), in its Freeform group.
static func add_to_scene(root: Node, rects: Array, style: MDSFreeformStyle, margin := MARGIN) -> int:
	var polys := outside_polygons(rects, margin)
	if polys.is_empty():
		return 0
	var group := root.get_node_or_null(^"Freeform")
	if not group:
		group = Node2D.new()
		group.name = "Freeform"
		group.z_index = MDSRoomPainter.ITEM_GROUPS["Freeform"]
		root.add_child(group)
		group.owner = root
	var sig := signature(rects)
	for i in polys.size():
		var f := MDSFreeform.new()
		f.style = style
		f.solid = false
		f.points = polys[i]
		group.add_child(f)
		f.owner = root
		_set_up(f, sig, i)
	return polys.size()

static func _set_up(f: MDSFreeform, sig: String, i: int) -> void:
	f.name = "OutsideShape" if i == 0 else "OutsideShape%d" % (i + 1)
	f.smooth = false
	f.edge_clumps = false
	f.set_collision_override(MDSFreeformStyle.Role.DECOR, false)
	f.set_meta(META, sig)
