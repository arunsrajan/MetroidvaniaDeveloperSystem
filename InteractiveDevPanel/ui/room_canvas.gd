@tool
class_name IDPRoomCanvas
extends Control
## The Room view's painting surface: shows a room scene at its real size and paints its
## tile layers (see [IDPRoomPainter]).
##
## Left drag paints with the current brush, middle/right drag pans, the wheel zooms.
## Erase removes decorations and terrain (Shift: background).

signal painted
signal status_message(text: String)

enum Tool { TERRAIN, BACKGROUND, DECOR, ERASE }

var painter: IDPRoomPainter
var world: IDPWorld
var room_id := ""
var tool: int = Tool.TERRAIN
var terrain_pick := Vector2i(0, 0) ## terrain set, terrain
var decor_kind := "grass"
var brush_size := 2
var zoom := 0.5
var pan := Vector2(20, 20)

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
		for l in _display_scene.find_children("*", "TileMapLayer", true, false):
			l.visible = false # the painter's copies are shown instead
		_view.add_child(_display_scene)
	for n in IDPRoomPainter.LAYER_ORDER:
		_view.add_child(painter.layers[n])
	fit()

func close() -> void:
	if painter:
		for l in painter.layers.values():
			if l.get_parent() == _view:
				_view.remove_child(l)
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
	# Brush preview.
	if get_rect().has_point(_mouse):
		var color: Color = [Color(0.5, 1, 0.4), Color(0.3, 0.8, 1), Color(1, 0.8, 0.3), Color(1, 0.35, 0.35)][tool]
		for c in _brush_cells(painter.cell_at("Terrain", screen_to_local(_mouse))):
			var r := painter.cell_rect("Terrain", c)
			ci.draw_rect(Rect2(local_to_screen(r.position), r.size * zoom), Color(color, 0.18))
			ci.draw_rect(Rect2(local_to_screen(r.position), r.size * zoom), color, false, 1.0)
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

func _brush_cells(center: Vector2i) -> Array:
	var out: Array = []
	var n := 1 if tool == Tool.DECOR else brush_size
	var lo := -(n - 1) / 2
	for y in range(lo, lo + n):
		for x in range(lo, lo + n):
			out.append(center + Vector2i(x, y))
	return out

func _paint_line(a: Vector2i, b: Vector2i, shift: bool) -> void:
	var cells: Dictionary = {}
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in steps + 1:
		var c := Vector2i(Vector2(a).lerp(Vector2(b), float(i) / maxf(1.0, float(steps))).round())
		for bc in _brush_cells(c):
			cells[bc] = true
	var list: Array = cells.keys()
	match tool:
		Tool.TERRAIN:
			painter.paint_terrain("Terrain", list, terrain_pick.x, terrain_pick.y)
		Tool.BACKGROUND:
			painter.place_kind("Background", list, "foliage", _rng)
		Tool.DECOR:
			painter.place_kind("Decor", list, decor_kind, _rng)
		Tool.ERASE:
			if shift:
				painter.erase("Background", list)
			else:
				var decor: TileMapLayer = painter.layers.Decor
				var terrain_cells: Array = []
				for c in list:
					if decor.get_cell_source_id(c) != -1:
						decor.erase_cell(c)
					else:
						terrain_cells.append(c)
				if not terrain_cells.is_empty():
					painter.erase("Terrain", terrain_cells)
				painter.dirty = true
	painted.emit()

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
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_painting = true
				_last_cell = painter.cell_at("Terrain", screen_to_local(mb.position))
				_paint_line(_last_cell, _last_cell, mb.shift_pressed)
			else:
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
		elif _painting:
			var cell := painter.cell_at("Terrain", screen_to_local(mm.position))
			if cell != _last_cell:
				_paint_line(_last_cell, cell, mm.shift_pressed)
				_last_cell = cell
		_overlay.queue_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
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
