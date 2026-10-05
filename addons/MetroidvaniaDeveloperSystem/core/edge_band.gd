@tool
class_name IDPEdgeBand
extends RefCounted
## Meshes for shader-skinned freeform shapes ([member IDPFreeformStyle.fill_material],
## [member IDPFreeformStyle.edge_material]). No editor dependencies.
##
## The edge band is one continuous strip along each run of visible edges, [code]outside[/code]
## px beyond the outline and [code]inside[/code] px into the shape. Where two edges meet, the
## normals are mitred, so the band bends round corners instead of overlapping itself.
## - [code]UV.x[/code]: distance along the outline, px.
## - [code]UV.y[/code]: depth into the shape: 0 at the outline, 1 at the band's inner edge,
##   negative outside ([code]-outside / inside[/code] at the outer edge).
## - [code]COLOR.r[/code]: which way the surface faces, 0 up .. 1 down; [code]COLOR.g[/code]:
##   0 left .. 1 right. A shader tells floors, walls and ceilings apart with it.

## The triangulated body of [param poly], for a fill material on a MeshInstance2D.
static func body_mesh(poly: PackedVector2Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in idx:
		verts.append(poly[i])
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Whether segment a-b lies on a line of the [param grid] (x = k * grid.x or y = k * grid.y),
## i.e. on a room's outer boundary in a world laid out on that grid.
static func on_grid(a: Vector2, b: Vector2, grid: Vector2) -> bool:
	if grid.x <= 0.0 or grid.y <= 0.0:
		return false
	var eps := 0.6
	if absf(a.x - b.x) < eps:
		var k := a.x / grid.x
		if absf(k - roundf(k)) * grid.x < eps:
			return true
	if absf(a.y - b.y) < eps:
		var k := a.y / grid.y
		if absf(k - roundf(k)) * grid.y < eps:
			return true
	return false

## The band along [param poly]'s edges (see the class description), or null when no edge is
## drawn. Edges on the [param skip_grid] lines (after moving by [param offset], e.g. the
## shape's position in the room) are left bare.
static func edge_mesh(poly: PackedVector2Array, inside: float, outside: float, skip_grid := Vector2.ZERO, offset := Vector2.ZERO) -> ArrayMesh:
	var n := poly.size()
	if n < 3 or inside <= 0.0:
		return null
	var visible: Array[bool] = []
	var normals: Array[Vector2] = []
	var sgn := 1.0 if IDPGeometry.signed_area(poly) > 0.0 else -1.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var d := b - a
		visible.append(d.length() >= 0.5 and not on_grid(a + offset, b + offset, skip_grid))
		normals.append((Vector2(d.y, -d.x).normalized() * sgn) if d.length() > 0.0 else Vector2.UP)
	var start := -1
	for i in n:
		if not visible[i]:
			start = (i + 1) % n
			break
	var closed := start == -1
	if closed:
		start = 0
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var run: Array[int] = []
	for k in n:
		var i := (start + k) % n
		if visible[i]:
			run.append(i)
		elif not run.is_empty():
			_emit_run(poly, normals, run, false, inside, outside, verts, uvs, cols)
			run = []
	if not run.is_empty():
		_emit_run(poly, normals, run, closed, inside, outside, verts, uvs, cols)
	if verts.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _emit_run(poly: PackedVector2Array, normals: Array[Vector2], run: Array[int], closed: bool, inside: float, outside: float,
		verts: PackedVector2Array, uvs: PackedVector2Array, cols: PackedColorArray) -> void:
	var n := poly.size()
	var pts: Array[Vector2] = []
	var nrms: Array[Vector2] = []
	for j in run.size():
		var e := run[j]
		var prev := run[j - 1] if j > 0 else (run[run.size() - 1] if closed else -1)
		pts.append(poly[e])
		nrms.append(_joint(normals, prev, e))
	var last := run[run.size() - 1]
	pts.append(poly[(last + 1) % n])
	nrms.append(_joint(normals, last, run[0] if closed else -1))
	var u := 0.0
	var vo := -outside / inside
	for j in pts.size() - 1:
		var a := pts[j]
		var b := pts[j + 1]
		var na := nrms[j]
		var nb := nrms[j + 1]
		var ua := u
		u += a.distance_to(b)
		var ub := u
		var ca := _facing(na)
		var cb := _facing(nb)
		var oa := a + na * outside
		var ob := b + nb * outside
		var ia := a - na * inside
		var ib := b - nb * inside
		for t in [[oa, Vector2(ua, vo), ca], [ob, Vector2(ub, vo), cb], [ib, Vector2(ub, 1.0), cb],
				[oa, Vector2(ua, vo), ca], [ib, Vector2(ub, 1.0), cb], [ia, Vector2(ua, 1.0), ca]]:
			verts.append(t[0])
			uvs.append(t[1])
			cols.append(t[2])

static func _facing(normal: Vector2) -> Color:
	var nn := normal.normalized()
	return Color(nn.y * 0.5 + 0.5, nn.x * 0.5 + 0.5, 0.0, 1.0)

## The normal where edge [param a] meets edge [param b] (either may be -1, the end of a run),
## mitred so the band keeps its width round the corner, never stretched more than twice.
static func _joint(normals: Array[Vector2], a: int, b: int) -> Vector2:
	if a < 0:
		return normals[b]
	if b < 0:
		return normals[a]
	var m := normals[a] + normals[b]
	if m.length() < 0.01:
		return normals[b]
	m = m.normalized()
	return m / maxf(m.dot(normals[b]), 0.5)
