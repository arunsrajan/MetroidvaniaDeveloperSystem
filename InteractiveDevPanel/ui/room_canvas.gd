@tool
class_name IDPRoomCanvas
extends Control
## The Room view's painting surface: shows a room scene at its real size and paints its
## tile layers (see [IDPRoomPainter]).
##
## Left drag paints with the current brush, middle/right drag pans, the wheel zooms.
## Erase removes the top tile under the brush (stamp, foreground, decoration, terrain, then
## background), or one layer's tiles, or all of them ([member erase_mode]; Shift:
## background only). With a shape (rectangle, irregular blob, curved side), left drag
## spans the shape's box and releasing paints it; Esc cancels. Ctrl+Z / Ctrl+Y undo, redo.
##
## Freeform tool: Draw clicks points (or drags freehand) and closes the shape on its first
## point, a double-click or Enter; with a shape picked, the dragged shape becomes a smooth
## freeform. Edit drags points, Alt+click removes one, double-click on an edge adds one,
## dragging inside moves the shape and Delete removes it.
## Stamps tool: click or drag to place clumps, Shift to remove them.

signal painted
signal status_message(text: String)

enum Tool { TERRAIN, BACKGROUND, DECOR, ERASE, FOREGROUND, FREEFORM, STAMP }
enum EraseMode { TOP, DECOR, TERRAIN, BACKGROUND, ALL, FOREGROUND }
const ERASE_MODE_NAMES: PackedStringArray = ["Top tile (stamp, foreground, decor, terrain, then background)", "Decor only", "Terrain only", "Background only", "All layers", "Foreground only"]
const TOOL_COLORS: Array[Color] = [Color(0.5, 1, 0.4), Color(0.3, 0.8, 1), Color(1, 0.8, 0.3), Color(1, 0.35, 0.35), Color(0.75, 0.6, 1), Color(0.4, 1, 0.85), Color(1, 0.6, 0.85)]
enum FreeformMode { DRAW, EDIT }

var painter: IDPRoomPainter
var world: IDPWorld
var room_id := ""
var tool: int = Tool.TERRAIN
## Fill painted by each tool (see [method IDPRoomPainter.paint_fill]).
var fills: Dictionary = {
	Tool.TERRAIN: {"type": "terrain", "set": 0, "terrain": 0},
	Tool.BACKGROUND: {"type": "kind", "kind": "foliage"},
	Tool.DECOR: {"type": "kind", "kind": "grass"},
	Tool.FOREGROUND: {"type": "color", "color": Color("#03070a")},
}
var brush_size := 2
var erase_mode: int = EraseMode.TOP
var shape: int = IDPTerrainShapes.Shape.BRUSH
var curve: int = IDPTerrainShapes.CurveType.CONVEX
var roughness := 0.0 ## 0..1, "Irregular"
var mirror := false
var curve_count := 3 ## waves, steps or spikes
var zoom := 0.5
var pan := Vector2(20, 20)
## Freeform tool.
var freeform_mode: int = FreeformMode.DRAW
var freeform_style: IDPFreeformStyle
var freeform_group := "Freeform" ## "FreeformBack", "Freeform" or "FreeformFront"
var freeform_solid := true
var selected: IDPFreeform
## Stamps tool.
var stamp_set: IDPStampSet
var stamp_category := ""
var stamp_group := "StampsFront"
var stamp_scale := 1.0

var _view: Node2D
var _display_scene: Node
var _overlay: Control
var _painting := false
var _panning := 0
var _pan_start := Vector2.ZERO
var _pan_orig := Vector2.ZERO
var _last_cell := Vector2i.ZERO
var _mouse := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _shape_from := Vector2i.ZERO
var _shape_to := Vector2i.ZERO
var _shaping := false
var _shape_seed := 1
var _stroke_erased: Dictionary = {} ## cells already erased in this stroke (one layer each)
var _draft := PackedVector2Array() ## freeform points being drawn (scene-local)
var _draft_press := Vector2.INF ## screen position of the current press while drawing
var _draft_freehand := false
var _drag_vertex := -1
var _drag_move := Vector2.INF ## scene-local point where a shape move started
var _drag_checkpointed := false
var _last_stamp := Vector2.INF

func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The room renders in its own SubViewport: layers with their own z_index (Background,
	# Decor) would otherwise escape this control's clipping and draw over other editor panels.
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container, false, Node.INTERNAL_MODE_FRONT)
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.gui_disable_input = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	container.add_child(vp)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.07, 0.08)
	backdrop.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
	backdrop.position = Vector2(-100000, -100000)
	backdrop.size = Vector2(200000, 200000)
	vp.add_child(backdrop)
	_view = Node2D.new()
	vp.add_child(_view)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay, false, Node.INTERNAL_MODE_BACK)

## Shows [param p_painter]'s room: the whole scene for context, its tile layers editable.
func open(p_world: IDPWorld, id: String, p_painter: IDPRoomPainter) -> void:
	close()
	world = p_world
	room_id = id
	painter = p_painter
	var packed := load(painter.scene_path) as PackedScene
	if packed:
		_display_scene = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		_display_scene.set_meta(&"fake_map", true)
		_display_scene.process_mode = Node.PROCESS_MODE_DISABLED
		for l in _display_scene.find_children("*", "", true, false):
			# The painter's copies are shown instead.
			if l is TileMapLayer or l is IDPFreeform or IDPRoomPainter.is_stamp(l):
				l.visible = false
		_view.add_child(_display_scene)
	for n in IDPRoomPainter.LAYER_ORDER:
		_view.add_child(painter.layers[n])
	_view.add_child(painter.items_root)
	selected = null
	_draft.clear()
	fit()

func close() -> void:
	if painter:
		for l in painter.layers.values():
			if l.get_parent() == _view:
				_view.remove_child(l)
		if painter.items_root.get_parent() == _view:
			_view.remove_child(painter.items_root)
	if is_instance_valid(_display_scene):
		_display_scene.queue_free()
	_display_scene = null
	painter = null

func fit() -> void:
	if not world or not world.has_room(room_id) or size.x <= 0:
		return
	var b := Rect2()
	var first := true
	for r in world.get_local_rects(room_id):
		b = r if first else b.merge(r)
		first = false
	if not b.has_area():
		return
	zoom = minf((size.x - 40.0) / b.size.x, (size.y - 40.0) / b.size.y)
	pan = size / 2.0 - b.get_center() * zoom
	_apply_view()

func set_zoom(value: float, anchor := Vector2(-1, -1)) -> void:
	if anchor.x < 0:
		anchor = size / 2.0
	var local := (anchor - pan) / zoom
	zoom = clampf(value, 0.05, 8.0)
	pan = anchor - local * zoom
	_apply_view()

func _apply_view() -> void:
	_view.position = pan
	_view.scale = Vector2(zoom, zoom)
	queue_redraw()
	_overlay.queue_redraw()

func screen_to_local(p: Vector2) -> Vector2:
	return (p - pan) / zoom

func local_to_screen(p: Vector2) -> Vector2:
	return pan + p * zoom

func _draw_overlay() -> void:
	if not painter or not world or not world.has_room(room_id):
		return
	var ci := _overlay
	var rects := world.get_local_rects(room_id)
	# Shade what lies outside the room's shape on the map.
	var b := rects[0]
	for r in rects:
		b = b.merge(r)
	var outer := b.grow(maxf(b.size.x, b.size.y))
	var shade := Color(0, 0, 0, 0.55)
	_shade_outside(ci, rects, outer, shade)
	for r in rects:
		ci.draw_rect(Rect2(local_to_screen(r.position), r.size * zoom), Color(1, 1, 1, 0.8), false, 2.0)
	# Tile grid when zoomed in.
	var ts := painter.tile_size() * zoom
	if ts.x >= 10.0:
		var x := b.position.x
		while x <= b.end.x:
			ci.draw_line(local_to_screen(Vector2(x, b.position.y)), local_to_screen(Vector2(x, b.end.y)), Color(1, 1, 1, 0.06))
			x += painter.tile_size().x
		var y := b.position.y
		while y <= b.end.y:
			ci.draw_line(local_to_screen(Vector2(b.position.x, y)), local_to_screen(Vector2(b.end.x, y)), Color(1, 1, 1, 0.06))
			y += painter.tile_size().y
	# Gates.
	var font := get_theme_default_font()
	for g in world.get_gates(room_id):
		var p := local_to_screen(world.get_gate_local_pos(room_id, g))
		ci.draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(1, 0.9, 0.3))
		ci.draw_string_outline(font, p + Vector2(9, -8), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		ci.draw_string(font, p + Vector2(9, -8), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.3))
	# Brush / shape preview.
	var color: Color = TOOL_COLORS[tool]
	if tool == Tool.FREEFORM:
		_draw_freeform_overlay(ci, color)
	if tool == Tool.STAMP and get_rect().has_point(_mouse):
		ci.draw_arc(_mouse, 48.0 * stamp_scale * zoom, 0, TAU, 32, color, 1.5)
	if _shaping:
		_draw_cells(ci, shape_cells(), color)
		var a := painter.cell_rect("Terrain", Vector2i(mini(_shape_from.x, _shape_to.x), mini(_shape_from.y, _shape_to.y)))
		var bb := painter.cell_rect("Terrain", Vector2i(maxi(_shape_from.x, _shape_to.x), maxi(_shape_from.y, _shape_to.y)))
		ci.draw_rect(Rect2(local_to_screen(a.position), (bb.end - a.position) * zoom), color, false, 1.0)
	elif get_rect().has_point(_mouse) and tool != Tool.STAMP and not (tool == Tool.FREEFORM and (shape == IDPTerrainShapes.Shape.BRUSH or freeform_mode == FreeformMode.EDIT)):
		if shape == IDPTerrainShapes.Shape.BRUSH:
			for c in _brush_cells(painter.cell_at("Terrain", screen_to_local(_mouse))):
				var r := painter.cell_rect("Terrain", c)
				ci.draw_rect(Rect2(local_to_screen(r.position), r.size * zoom), Color(color, 0.18))
				ci.draw_rect(Rect2(local_to_screen(r.position), r.size * zoom), color, false, 1.0)
		else:
			var r := painter.cell_rect("Terrain", painter.cell_at("Terrain", screen_to_local(_mouse)))
			var p := local_to_screen(r.get_center())
			ci.draw_line(p - Vector2(8, 0), p + Vector2(8, 0), color, 1.0)
			ci.draw_line(p - Vector2(0, 8), p + Vector2(0, 8), color, 1.0)
	var title := "%s  (actual view)%s" % [room_id, "  *unsaved" if painter.dirty else ""]
	ci.draw_rect(Rect2(Vector2(6, 6), font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14) + Vector2(12, 8)), Color(0, 0, 0, 0.6))
	ci.draw_string(font, Vector2(12, 23), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

## Darkens [param outer] except the room rectangles (row by row over the rect edges).
func _shade_outside(ci: CanvasItem, rects: Array[Rect2], outer: Rect2, color: Color) -> void:
	var ys: Array = [outer.position.y, outer.end.y]
	for r in rects:
		ys.append(r.position.y)
		ys.append(r.end.y)
	ys.sort()
	for i in ys.size() - 1:
		var y0: float = ys[i]
		var y1: float = ys[i + 1]
		if y1 <= y0:
			continue
		var spans: Array = []
		for r in rects:
			if r.position.y <= y0 and r.end.y >= y1:
				spans.append([r.position.x, r.end.x])
		spans.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var x := outer.position.x
		for s in spans:
			if s[0] > x:
				ci.draw_rect(Rect2(local_to_screen(Vector2(x, y0)), Vector2(s[0] - x, y1 - y0) * zoom), color)
			x = maxf(x, s[1])
		if x < outer.end.x:
			ci.draw_rect(Rect2(local_to_screen(Vector2(x, y0)), Vector2(outer.end.x - x, y1 - y0) * zoom), color)

func _draw_freeform_overlay(ci: CanvasItem, color: Color) -> void:
	if _draft.size() > 0:
		var pts := PackedVector2Array()
		for q in _draft:
			pts.append(local_to_screen(q))
		if get_rect().has_point(_mouse) and not _draft_freehand:
			pts.append(_mouse)
		if pts.size() >= 2:
			ci.draw_polyline(pts, color, 2.0, true)
		for q in _draft:
			ci.draw_rect(Rect2(local_to_screen(q) - Vector2(3, 3), Vector2(6, 6)), color)
		if _draft.size() >= 3:
			ci.draw_arc(local_to_screen(_draft[0]), 9.0, 0, TAU, 20, Color.WHITE, 1.5)
	if is_instance_valid(selected) and selected.is_inside_tree():
		var outline := selected.get_outline()
		var pts := PackedVector2Array()
		for q in outline:
			pts.append(local_to_screen(q + selected.position))
		if pts.size() >= 2:
			pts.append(pts[0])
			ci.draw_polyline(pts, Color(color, 0.9), 1.5, true)
		if freeform_mode == FreeformMode.EDIT:
			for q in selected.points:
				var sp := local_to_screen(q + selected.position)
				ci.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color.BLACK)
				ci.draw_rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), color)

func _brush_cells(center: Vector2i) -> Array:
	var out: Array = []
	var n := 1 if tool == Tool.DECOR else brush_size
	var lo := -(n - 1) / 2
	for y in range(lo, lo + n):
		for x in range(lo, lo + n):
			out.append(center + Vector2i(x, y))
	return out

## Cells as merged row spans (cheap to draw even for big shapes).
func _draw_cells(ci: CanvasItem, cells: Array, color: Color) -> void:
	var rows: Dictionary = {}
	for c: Vector2i in cells:
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
	for y in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		for i in range(1, xs.size() + 1):
			if i < xs.size() and xs[i] == prev + 1:
				prev = xs[i]
				continue
			var a := painter.cell_rect("Terrain", Vector2i(start, y))
			var b := painter.cell_rect("Terrain", Vector2i(prev, y))
			ci.draw_rect(Rect2(local_to_screen(a.position), (b.end - a.position) * zoom), Color(color, 0.35))
			if i < xs.size():
				start = xs[i]
				prev = xs[i]

## Cells of the shape being dragged.
func shape_cells() -> Array[Vector2i]:
	return IDPTerrainShapes.cells(shape, _shape_from, _shape_to, curve, roughness, mirror, _shape_seed, curve_count)

## Paints a shape spanning cells [param a] to [param b] with the current tool (also used
## by tests).
func paint_shape(a: Vector2i, b: Vector2i, shift := false) -> void:
	_shape_from = a
	_shape_to = b
	_stroke_erased.clear()
	painter.checkpoint()
	_apply(shape_cells(), shift)
	_shape_seed += 1

func _paint_line(a: Vector2i, b: Vector2i, shift: bool) -> void:
	var cells: Dictionary = {}
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in steps + 1:
		var c := Vector2i(Vector2(a).lerp(Vector2(b), float(i) / maxf(1.0, float(steps))).round())
		for bc in _brush_cells(c):
			cells[bc] = true
	_apply(cells.keys(), shift)

func _apply(list: Array, shift: bool) -> void:
	match tool:
		Tool.TERRAIN:
			painter.paint_fill("Terrain", list, fills[Tool.TERRAIN], _rng)
		Tool.BACKGROUND:
			painter.paint_fill("Background", list, fills[Tool.BACKGROUND], _rng)
		Tool.DECOR:
			painter.paint_fill("Decor", list, fills[Tool.DECOR], _rng)
		Tool.FOREGROUND:
			painter.paint_fill("Foreground", list, fills[Tool.FOREGROUND], _rng)
		Tool.FREEFORM:
			add_freeform_from_cells(list)
		Tool.ERASE:
			erase_cells(list, EraseMode.BACKGROUND if shift else erase_mode)
	painted.emit()

## Erases [param cells] as [param mode] says. In one stroke a cell is erased once, so
## dragging back and forth doesn't dig through every layer.
func erase_cells(cells: Array, mode: int) -> void:
	var by_layer := {"Foreground": [], "Decor": [], "Terrain": [], "Background": []}
	for c: Vector2i in cells:
		if _stroke_erased.has(c):
			continue
		_stroke_erased[c] = true
		if mode == EraseMode.TOP or mode == EraseMode.ALL:
			# Stamps first: a stamp anchored in the cell goes before the tiles under it.
			var r := painter.cell_rect("Terrain", c)
			var hit := false
			for st in painter.stamps_near(r.get_center(), r.size.x * 0.75):
				painter.remove_item(st)
				hit = true
			if hit and mode == EraseMode.TOP:
				continue
		match mode:
			EraseMode.TOP:
				for n in ["Foreground", "Decor", "Terrain", "Background"]:
					if painter.layers[n].get_cell_source_id(c) != -1:
						by_layer[n].append(c)
						break
			EraseMode.FOREGROUND:
				by_layer.Foreground.append(c)
			EraseMode.DECOR:
				by_layer.Decor.append(c)
			EraseMode.TERRAIN:
				by_layer.Terrain.append(c)
			EraseMode.BACKGROUND:
				by_layer.Background.append(c)
			EraseMode.ALL:
				for n in by_layer:
					by_layer[n].append(c)
	for n in by_layer:
		if not by_layer[n].is_empty():
			painter.erase(n, by_layer[n])
	painter.dirty = true

# --- Freeform shapes ---------------------------------------------------------------------------

## Adds a freeform shape through [param points] (scene-local) with the current style and
## layer, and selects it.
func add_freeform(points: PackedVector2Array) -> IDPFreeform:
	if points.size() < 3:
		return null
	var st := freeform_style if freeform_style else IDPFreeform._default_style()
	selected = painter.add_freeform(points, st, freeform_group, freeform_solid)
	painted.emit()
	status_message.emit("Freeform shape added (%d points). Edit mode drags its points; Delete removes it." % points.size())
	return selected

## The outline of a set of cells (e.g. a curved or irregular shape) as a freeform shape:
## the contour is traced, simplified and then rounded by the shape itself.
func add_freeform_from_cells(cells: Array) -> IDPFreeform:
	var pts := cells_outline(cells)
	return add_freeform(pts) if pts.size() >= 3 else null

func cells_outline(cells: Array) -> PackedVector2Array:
	if cells.is_empty():
		return PackedVector2Array()
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for c: Vector2i in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var bm := BitMap.new()
	bm.create(hi - lo + Vector2i(3, 3))
	for c: Vector2i in cells:
		bm.set_bitv(c - lo + Vector2i.ONE, true)
	var polys := bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, bm.get_size()), 1.2)
	var best := PackedVector2Array()
	var best_area := 0.0
	for poly: PackedVector2Array in polys:
		var a := absf(IDPFreeform.signed_area(poly))
		if a > best_area:
			best_area = a
			best = poly
	var ts := painter.tile_size()
	var origin := painter.cell_rect("Terrain", lo - Vector2i.ONE).position
	var out := PackedVector2Array()
	for q in best:
		out.append(origin + q * ts)
	return out

## Ramer-Douglas-Peucker simplification of an open polyline.
static func simplify(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array = [[0, pts.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var a: int = seg[0]
		var b: int = seg[1]
		var best := -1
		var best_d := eps
		for i in range(a + 1, b):
			var d := Geometry2D.get_closest_point_to_segment(pts[i], pts[a], pts[b]).distance_to(pts[i])
			if d > best_d:
				best_d = d
				best = i
		if best >= 0:
			keep[best] = 1
			stack.append([a, best])
			stack.append([best, b])
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i]:
			out.append(pts[i])
	return out

func _finish_draft() -> void:
	var pts := _draft
	if _draft_freehand:
		pts = simplify(_draft, 6.0)
	_draft = PackedVector2Array()
	_draft_freehand = false
	if pts.size() >= 3:
		painter.checkpoint()
		add_freeform(pts)
	_overlay.queue_redraw()

func _freeform_input(mb: InputEventMouseButton) -> void:
	var p := screen_to_local(mb.position)
	var grab := 10.0 / zoom
	if freeform_mode == FreeformMode.DRAW:
		if mb.pressed:
			if mb.double_click and _draft.size() >= 3:
				_finish_draft()
				return
			if _draft.size() >= 3 and p.distance_to(_draft[0]) <= grab:
				_finish_draft()
				return
			_draft.append(p)
			_draft_press = mb.position
			_draft_freehand = false
		else:
			_draft_press = Vector2.INF
			if _draft_freehand:
				_finish_draft()
		return
	# Edit.
	if mb.pressed:
		_drag_checkpointed = false
		if is_instance_valid(selected):
			var local := p - selected.position
			for i in selected.points.size():
				if selected.points[i].distance_to(local) <= grab:
					if mb.alt_pressed:
						if selected.points.size() > 3:
							painter.checkpoint()
							var pts := selected.points
							pts.remove_at(i)
							selected.points = pts
							painter.dirty = true
							painted.emit()
						return
					_drag_vertex = i
					return
			if mb.double_click:
				var pts := selected.points
				for i in pts.size():
					var a := pts[i]
					var b := pts[(i + 1) % pts.size()]
					if Geometry2D.get_closest_point_to_segment(local, a, b).distance_to(local) <= grab:
						painter.checkpoint()
						pts.insert(i + 1, local)
						selected.points = pts
						painter.dirty = true
						painted.emit()
						return
		selected = painter.freeform_at(p)
		if selected:
			_drag_move = p
			status_message.emit("%s selected: drag to move, drag its points to reshape, Delete removes it." % selected.name)
	else:
		_drag_vertex = -1
		_drag_move = Vector2.INF

func _freeform_motion(mm: InputEventMouseMotion) -> void:
	var p := screen_to_local(mm.position)
	if freeform_mode == FreeformMode.DRAW:
		if _draft_press != Vector2.INF and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if mm.position.distance_to(_draft_press) > 6.0:
				_draft_freehand = true
			if _draft_freehand and p.distance_to(_draft[_draft.size() - 1]) >= 10.0:
				_draft.append(p)
		return
	if not is_instance_valid(selected) or not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	if (_drag_vertex >= 0 or _drag_move != Vector2.INF) and not _drag_checkpointed:
		painter.checkpoint()
		_drag_checkpointed = true
	if _drag_vertex >= 0:
		var pts := selected.points
		pts[_drag_vertex] = p - selected.position
		selected.points = pts
		painter.dirty = true
	elif _drag_move != Vector2.INF:
		selected.position += p - _drag_move
		_drag_move = p
		painter.dirty = true

func delete_selected() -> void:
	if is_instance_valid(selected):
		painter.checkpoint()
		painter.remove_item(selected)
		selected = null
		painted.emit()
		status_message.emit("Freeform shape removed.")

# --- Stamps -----------------------------------------------------------------------------------

## Places a random stamp of the current category at [param p] (scene-local).
func place_stamp(p: Vector2) -> Sprite2D:
	if not stamp_set:
		status_message.emit("No stamp set: add the Mossgrove pack (or any *.stamps.tres) to the project.")
		return null
	var picks := stamp_set.indices(stamp_category)
	if picks.is_empty():
		return null
	var k := stamp_scale * _rng.randf_range(0.8, 1.2)
	var s := painter.add_stamp(stamp_set, picks[_rng.randi_range(0, picks.size() - 1)], p, Vector2(k * (-1.0 if _rng.randf() < 0.5 else 1.0), k), _rng.randf_range(-0.12, 0.12), stamp_group)
	painted.emit()
	return s

func _stamp_input(mb: InputEventMouseButton) -> void:
	if not mb.pressed:
		_last_stamp = Vector2.INF
		return
	painter.checkpoint()
	var p := screen_to_local(mb.position)
	_last_stamp = p
	if mb.shift_pressed:
		for st in painter.stamps_near(p, 48.0 * stamp_scale):
			painter.remove_item(st)
		painted.emit()
	else:
		place_stamp(p)

func _stamp_motion(mm: InputEventMouseMotion) -> void:
	if _last_stamp == Vector2.INF or not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	var p := screen_to_local(mm.position)
	if mm.shift_pressed:
		for st in painter.stamps_near(p, 48.0 * stamp_scale):
			painter.remove_item(st)
		painted.emit()
	elif p.distance_to(_last_stamp) >= 70.0 * stamp_scale:
		place_stamp(p)
		_last_stamp = p

func _gui_input(event: InputEvent) -> void:
	if not painter:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			set_zoom(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.button_index if mb.pressed else 0
			_pan_start = mb.position
			_pan_orig = pan
		elif mb.button_index == MOUSE_BUTTON_LEFT and tool == Tool.STAMP:
			grab_focus()
			_stamp_input(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT and tool == Tool.FREEFORM and (shape == IDPTerrainShapes.Shape.BRUSH or freeform_mode == FreeformMode.EDIT):
			grab_focus()
			_freeform_input(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var cell := painter.cell_at("Terrain", screen_to_local(mb.position))
			if mb.pressed:
				grab_focus()
				if shape != IDPTerrainShapes.Shape.BRUSH:
					_shaping = true
					_shape_from = cell
					_shape_to = cell
				else:
					painter.checkpoint()
					_stroke_erased.clear()
					_painting = true
					_last_cell = cell
					_paint_line(_last_cell, _last_cell, mb.shift_pressed)
			elif _shaping:
				_shaping = false
				_shape_to = cell
				paint_shape(_shape_from, _shape_to, mb.shift_pressed)
				status_message.emit("%s shape painted (%d x %d tiles). Ctrl+Z undoes it." % [IDPTerrainShapes.SHAPE_NAMES[shape], absi(_shape_to.x - _shape_from.x) + 1, absi(_shape_to.y - _shape_from.y) + 1])
			elif _painting:
				_painting = false
				status_message.emit("Painted %s. Save writes it into the scene; the map silhouette updates after saving." % room_id)
		accept_event()
		_overlay.queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _panning:
			pan = _pan_orig + (mm.position - _pan_start)
			_apply_view()
		elif tool == Tool.STAMP:
			_stamp_motion(mm)
		elif tool == Tool.FREEFORM and not _shaping:
			_freeform_motion(mm)
		elif _shaping:
			_shape_to = painter.cell_at("Terrain", screen_to_local(mm.position))
		elif _painting:
			var cell := painter.cell_at("Terrain", screen_to_local(mm.position))
			if cell != _last_cell:
				_paint_line(_last_cell, cell, mm.shift_pressed)
				_last_cell = cell
		_overlay.queue_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.ctrl_pressed and (key.keycode == KEY_Z or key.keycode == KEY_Y):
			var redo := key.keycode == KEY_Y or key.shift_pressed
			if painter.redo() if redo else painter.undo():
				painted.emit()
				status_message.emit("Redone." if redo else "Undone.")
			accept_event()
			return
		match event.keycode:
			KEY_ESCAPE:
				_shaping = false
				_draft.clear()
				_draft_freehand = false
			KEY_ENTER, KEY_KP_ENTER:
				if tool == Tool.FREEFORM and _draft.size() >= 3:
					_finish_draft()
			KEY_BACKSPACE:
				if tool == Tool.FREEFORM and not _draft.is_empty():
					_draft.remove_at(_draft.size() - 1)
			KEY_DELETE:
				if tool == Tool.FREEFORM:
					delete_selected()
			KEY_BRACKETLEFT:
				brush_size = maxi(1, brush_size - 1)
			KEY_BRACKETRIGHT:
				brush_size = mini(12, brush_size + 1)
			KEY_F:
				fit()
		_overlay.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _overlay:
		_overlay.queue_redraw()
