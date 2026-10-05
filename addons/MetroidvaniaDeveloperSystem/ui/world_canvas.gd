@tool
class_name IDPWorldCanvas
extends Control
## Free-form world map editor for non-linear mode.
##
## Rooms are drawn and placed anywhere in world pixels (any size, any shape made of
## rectangles), grouped into colored areas and connected by named gates, like a
## Hollow Knight map. Room scenes can be dragged in from the FileSystem dock.
##
## Tools: V select/move/resize, R draw room, E extend room (add a rectangle), G gate,
## P pin. Drag from one gate to another to connect them (Shift+drag moves a gate).
## Wheel zooms, middle/right drag or left drag on empty space pans, double-click opens the
## scene, Shift+click routes, Delete removes, Ctrl+Z / Ctrl+Y undo/redo, Ctrl+D
## duplicates, arrows nudge by one grid step.

signal room_selected(room_id: String)
signal room_activated(room_id: String)
signal gate_selected(room_id: String, gate_name: String)
signal context_requested(room_id: String, world_pos: Vector2, local_pos: Vector2)
signal hovered_changed(room_id: String, world_pos: Vector2)
signal view_changed
signal route_requested(from_id: String, to_id: String)
signal pin_requested(world_pos: Vector2)
signal scenes_dropped(files: PackedStringArray, world_pos: Vector2)
signal tool_changed(new_tool: int)
signal status_message(text: String)
signal brush_size_changed(size: int)

enum Tool { SELECT, ROOM, RECT, GATE, PIN, PAINT, ERASE }
const TOOL_NAMES: PackedStringArray = ["Select (V)", "Draw room (R)", "Extend room (E)", "Gate (G)", "Pin (P)", "Paint (B)", "Erase (X)"]
const TOOL_HINTS: PackedStringArray = [
	"Click to select, drag to move, drag handles to resize, drag from a gate to another gate to connect. Drop .tscn files here to place scenes.",
	"Drag to draw a new room.",
	"Drag to add a rectangle to the selected room (irregular shapes).",
	"Click a room edge to add a gate. Drag from a gate to another gate to connect.",
	"Click to place a pin.",
	"Paint the map: drag on empty space for a new room, start inside a room to grow it (Shift: always a new room). [ ] change the brush size.",
	"Erase painted cells from any room. [ ] change the brush size.",
]
enum Drag { NONE, PAN, MOVE_ROOM, RESIZE, RUBBER, CONNECT, MOVE_GATE, MOVE_LABEL, PAINT }

const COLOR_BACKGROUND := Color(0.14, 0.12, 0.12)
const COLOR_GRID := Color(1, 1, 1, 0.04)
const COLOR_SELECT := Color(1.0, 0.92, 0.35)
const COLOR_ROUTE := Color(0.3, 0.95, 1.0)
const COLOR_NO_AREA := Color(0.55, 0.55, 0.6)
const MIN_ZOOM := 0.003
const MAX_ZOOM := 2.0

var world: IDPWorld
var analysis: IDPAnalysis
var scene_db: Dictionary = {}
var layer := 0
var color_mode: int = IDPMapCanvas.ColorMode.AREA
var tool: int = Tool.SELECT
var show := {
	"labels": true, "area_labels": true, "terrain": true, "previews": false, "gates": true,
	"markers": true, "pins": true, "issues": true, "grid": true, "legend": true,
}
var marker_filters: Dictionary = {}
var issue_rooms: Dictionary = {} ## id -> highest severity
var selected_room := ""
var selected_gate := ""
var hovered_room := ""
var route: Array[String] = []
var highlight_rooms: Dictionary = {}
## Area given to rooms drawn with the Room tool.
var new_room_area := ""

var zoom := 0.06 ## Screen pixels per world pixel.
var pan := Vector2(40, 40)

var _overlay: Control
var _preview_root: Node2D
var _preview_layer := -9999
var _preview_nodes: Dictionary = {} ## room id -> preview instance
var _silhouettes: Dictionary = {}
var _area_label_rects: Dictionary = {}
var _drag := Drag.NONE
var _drag_button := 0
var _drag_start := Vector2.ZERO ## screen
var _drag_moved := false
var _drag_room := ""
var _drag_gate := ""
var _drag_rect_index := -1
var _drag_handle := -1
var _drag_orig_pan := Vector2.ZERO
var _drag_orig_origin := Vector2.ZERO
var _drag_orig_rect := Rect2()
var _drag_orig_bounds := Rect2()
var _drag_area := ""
var _drag_checkpointed := false
var _mouse := Vector2.ZERO
## Brush width/height in paint cells.
var brush_size := 1
var _paint_room := ""
var _paint_last := Vector2i.ZERO
var _cells_cache: Dictionary = {} ## room id -> [signature, cells]

func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	_preview_root = Node2D.new()
	add_child(_preview_root, false, Node.INTERNAL_MODE_FRONT)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay, false, Node.INTERNAL_MODE_BACK)

# --- Public API ------------------------------------------------------------------------

func set_data(p_world: IDPWorld, p_analysis: IDPAnalysis, p_scene_db: Dictionary) -> void:
	if not is_same(p_scene_db, scene_db) or p_world != world:
		_silhouettes.clear()
		_preview_layer = -9999
	world = p_world
	analysis = p_analysis
	scene_db = p_scene_db
	if not world or not world.has_room(selected_room):
		selected_room = ""
		selected_gate = ""
	_update_previews()
	redraw()

func set_layer(p_layer: int) -> void:
	if layer != p_layer:
		layer = p_layer
		hovered_room = ""
		_update_previews()
		redraw()

func set_tool(p_tool: int) -> void:
	tool = p_tool
	_drag = Drag.NONE
	tool_changed.emit(tool)
	status_message.emit(TOOL_HINTS[tool])
	redraw()

func set_show(key: String, value: bool) -> void:
	show[key] = value
	if key == "previews":
		_preview_layer = -9999
		_update_previews()
	redraw()

## Call after the scene files behind rooms changed (e.g. rescans).
func refresh_previews() -> void:
	_preview_layer = -9999
	_silhouettes.clear()
	_update_previews()
	redraw()

func redraw() -> void:
	queue_redraw()
	_overlay.queue_redraw()

func world_to_screen(p: Vector2) -> Vector2:
	return pan + p * zoom

func screen_to_world(p: Vector2) -> Vector2:
	return (p - pan) / zoom

func world_rect_to_screen(r: Rect2) -> Rect2:
	return Rect2(world_to_screen(r.position), r.size * zoom)

func set_zoom(value: float, anchor := Vector2(-1, -1)) -> void:
	if anchor.x < 0:
		anchor = size / 2.0
	var w := screen_to_world(anchor)
	zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	pan = anchor - w * zoom
	_after_view_change()

func fit_to_layer() -> void:
	if not world:
		return
	var b := world.get_layer_bounds(layer)
	if not b.has_area() or size.x <= 0 or size.y <= 0:
		return
	var margin := 70.0
	# Room for area names beside the map, but never more than a fifth of the width each side.
	var side := minf(200.0, size.x * 0.2) if show.area_labels and not world.get_areas().is_empty() else margin
	side = maxf(side, minf(margin, size.x * 0.1))
	zoom = clampf(minf((size.x - side * 2) / b.size.x, (size.y - margin * 2) / b.size.y), MIN_ZOOM, MAX_ZOOM)
	pan = size / 2.0 - b.get_center() * zoom
	_after_view_change()

func center_on(world_pos: Vector2) -> void:
	pan = size / 2.0 - world_pos * zoom
	_after_view_change()

func center_on_room(id: String) -> void:
	if world and world.has_room(id):
		center_on(world.get_room_bounds(id).get_center())

func _after_view_change() -> void:
	_preview_root.position = pan
	_preview_root.scale = Vector2(zoom, zoom)
	redraw()
	view_changed.emit()

# --- Colors ------------------------------------------------------------------------------

func get_room_color(id: String) -> Color:
	var info: Dictionary = analysis.get_info(id) if analysis else {}
	match color_mode:
		IDPMapCanvas.ColorMode.AREA, IDPMapCanvas.ColorMode.METSYS:
			var area := world.get_room_area(id)
			return world.get_area_color(area) if not area.is_empty() else COLOR_NO_AREA
		IDPMapCanvas.ColorMode.ROOM_TYPE:
			return IDPMapCanvas.TYPE_COLORS.get(info.get("type", ""), IDPMapCanvas.TYPE_COLORS[""])
		IDPMapCanvas.ColorMode.PROGRESSION:
			if analysis and analysis.sphere_of.has(id):
				return IDPMapCanvas.sphere_color(analysis.sphere_of[id], analysis.spheres.size())
			return IDPMapCanvas.COLOR_LOCKED if analysis and id in analysis.locked else IDPMapCanvas.COLOR_DISCONNECTED
		IDPMapCanvas.ColorMode.SAVE_DISTANCE:
			return _save_distance_color(analysis.save_distance.get(id, -1) if analysis else -1)
		IDPMapCanvas.ColorMode.STATUS:
			return IDPMapCanvas.STATUS_COLORS.get(info.get("status", ""), IDPMapCanvas.STATUS_COLORS[""])
	return COLOR_NO_AREA

func _save_distance_color(d: int) -> Color:
	if d < 0:
		return IDPMapCanvas.COLOR_DISCONNECTED
	if d == 0:
		return IDPMapCanvas.TYPE_COLORS.save
	var warn: int = int(world.get_setting("save_distance_warn", 4))
	return Color(0.25, 0.7, 0.35).lerp(Color(0.85, 0.2, 0.2), clampf(float(d - 1) / maxf(1.0, float(warn)), 0.0, 1.0))

func get_legend() -> Array:
	var items: Array = []
	match color_mode:
		IDPMapCanvas.ColorMode.AREA, IDPMapCanvas.ColorMode.METSYS:
			for a in world.get_areas():
				items.append([a, world.get_area_color(a)])
		IDPMapCanvas.ColorMode.ROOM_TYPE:
			var seen := {}
			for id in world.get_room_ids():
				if analysis:
					seen[analysis.get_info(id).get("type", "")] = true
			for t in IDPMapCanvas.TYPE_COLORS:
				if seen.has(t) and not (t == "" and seen.has("normal")):
					items.append([t.capitalize() if not t.is_empty() else "Normal", IDPMapCanvas.TYPE_COLORS[t]])
		IDPMapCanvas.ColorMode.PROGRESSION:
			if analysis:
				for s in analysis.spheres:
					var text := "Start" if s.index == 0 else "After %s" % ", ".join(analysis.spheres[s.index - 1].gained)
					items.append(["Sphere %d: %s" % [s.index, text], IDPMapCanvas.sphere_color(s.index, analysis.spheres.size())])
			items.append(["Locked", IDPMapCanvas.COLOR_LOCKED])
			items.append(["Not connected", IDPMapCanvas.COLOR_DISCONNECTED])
		IDPMapCanvas.ColorMode.SAVE_DISTANCE:
			var warn: int = int(world.get_setting("save_distance_warn", 4))
			items.append(["Save room", _save_distance_color(0)])
			items.append(["1 room away", _save_distance_color(1)])
			items.append(["%d+ rooms" % (warn + 1), _save_distance_color(warn + 1)])
			items.append(["No save reachable", IDPMapCanvas.COLOR_DISCONNECTED])
		IDPMapCanvas.ColorMode.STATUS:
			for s in IDPMapCanvas.STATUS_COLORS:
				items.append([s.capitalize() if not s.is_empty() else "No status", IDPMapCanvas.STATUS_COLORS[s]])
	return items

func _border_px() -> float:
	return clampf(zoom * 40.0, 1.5, 5.0)

func _gate_px() -> float:
	return clampf(zoom * 70.0, 5.0, 12.0)

# --- Drawing: rooms ------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if not world:
		return
	if tool == Tool.PAINT or tool == Tool.ERASE:
		_draw_paint_grid()
	elif show.grid:
		_draw_grid()
	var style := get_style()
	var b := _border_px()
	var dim := not highlight_rooms.is_empty()
	for id in world.get_room_ids():
		if world.get_room_layer(id) != layer:
			continue
		var color := get_room_color(id)
		if dim and not highlight_rooms.has(id):
			color = color.darkened(0.65)
		var rects := world.get_world_rects(id)
		# Rooms without a scene keep their full color (a freshly painted map is all of them);
		# their label says "(no scene)".
		var fill := color
		if style.kind == IDPMapStyle.Kind.ATLAS:
			fill = color.lightened(0.2)
		if style.kind != IDPMapStyle.Kind.FLAT:
			style.draw_room(self, get_cells(id), world.get_paint_cell(), world_to_screen, zoom, fill, _style_border_color(style, color), _passages(id))
		else:
			# Border first, fill on top: rects of one room merge into a single shape.
			for r in rects:
				draw_rect(world_rect_to_screen(r).grow(b), color.darkened(0.5))
			for r in rects:
				draw_rect(world_rect_to_screen(r), fill)
		if show.terrain and not show.previews:
			var path := world.get_scene_path(id)
			var tex := _get_silhouette(path)
			if tex:
				var sr: Rect2 = scene_db[path].silhouette_rect
				draw_texture_rect(tex, world_rect_to_screen(Rect2(world.get_origin(id) + sr.position, sr.size)), false, color.darkened(0.5))

func set_brush_size(value: int) -> void:
	brush_size = clampi(value, 1, 8)
	brush_size_changed.emit(brush_size)
	status_message.emit("Brush %dx%d cells" % [brush_size, brush_size])
	_overlay.queue_redraw()

func get_style() -> IDPMapStyle:
	return IDPMapStyle.get_style(str(world.get_setting("map_style", "handdrawn")))

func _style_border_color(style: IDPMapStyle, color: Color) -> Color:
	if style.kind == IDPMapStyle.Kind.METSYS and style.theme.get("default_border_color") is Color:
		return style.theme.default_border_color
	return color.lightened(0.3)

## Paint cells of a room, cached until its shape changes.
func get_cells(id: String) -> Dictionary:
	var room: Dictionary = world.data.rooms.get(id, {})
	var sig := str(room.get("rects", [])) + str(room.get("origin", [])) + str(world.get_paint_cell())
	var cached: Array = _cells_cache.get(id, [])
	if cached.is_empty() or cached[0] != sig:
		cached = [sig, world.get_room_cells(id)]
		_cells_cache[id] = cached
	return cached[1]

## "x,y:side" keys of cell edges that carry a gate (MetSys themes draw passages there).
func _passages(id: String) -> Dictionary:
	var out: Dictionary = {}
	var inward := {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bot": Vector2.UP}
	for g in world.get_gates(id):
		var side := world.get_gate_side(id, g)
		if not inward.has(side):
			continue
		var c := world.world_to_cell(world.get_gate_world_pos(id, g) + inward[side])
		out["%d,%d:%s" % [c.x, c.y, side]] = true
	return out

func _draw_paint_grid() -> void:
	var s := world.get_paint_cell()
	if s.x * zoom < 6.0:
		return
	var w0 := (screen_to_world(Vector2.ZERO) / s).floor() * s
	var w1 := screen_to_world(size)
	var x := w0.x
	while x <= w1.x:
		var sx := world_to_screen(Vector2(x, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(1, 1, 1, 0.07))
		x += s.x
	var y := w0.y
	while y <= w1.y:
		var sy := world_to_screen(Vector2(0, y)).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(1, 1, 1, 0.07))
		y += s.y

func _brush_cells(center: Vector2i) -> Array:
	var out: Array = []
	var lo := -(brush_size - 1) / 2
	for y in range(lo, lo + brush_size):
		for x in range(lo, lo + brush_size):
			out.append(center + Vector2i(x, y))
	return out

## Cells along the segment from [param a] to [param b], so fast strokes leave no gaps.
func _line_cells(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var t := float(i) / maxf(1.0, float(n))
		var c := Vector2i(Vector2(a).lerp(Vector2(b), t).round())
		if out.is_empty() or out.back() != c:
			out.append(c)
	return out

func _paint_along(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var cells: Dictionary = {}
	for c in _line_cells(from_cell, to_cell):
		for bc in _brush_cells(c):
			cells[bc] = true
	var list: Array = cells.keys()
	if tool == Tool.ERASE:
		var changed := world.erase_cells(list, layer)
		if not world.has_room(selected_room):
			selected_room = ""
			selected_gate = ""
		if not changed.is_empty():
			status_message.emit("Erased from %s" % ", ".join(changed))
		return
	if _paint_room.is_empty() or not world.has_room(_paint_room):
		_paint_room = world.add_room_from_cells(list, layer, new_room_area)
		if not _paint_room.is_empty():
			selected_room = _paint_room
			selected_gate = ""
			room_selected.emit(_paint_room)
	else:
		world.paint_cells(_paint_room, list)

func _draw_grid() -> void:
	var g := world.get_grid()
	var room := world.get_default_room_size()
	var step := Vector2(g, g)
	if g * zoom < 8.0:
		step = room
		if room.x * zoom < 12.0:
			return
	var w0 := (screen_to_world(Vector2.ZERO) / step).floor() * step
	var w1 := screen_to_world(size)
	var x := w0.x
	while x <= w1.x:
		var sx := world_to_screen(Vector2(x, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), COLOR_GRID)
		x += step.x
	var y := w0.y
	while y <= w1.y:
		var sy := world_to_screen(Vector2(0, y)).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), COLOR_GRID)
		y += step.y

func _get_silhouette(scene_path: String) -> Texture2D:
	if scene_path.is_empty():
		return null
	if not _silhouettes.has(scene_path):
		var img = scene_db.get(scene_path, {}).get("silhouette")
		_silhouettes[scene_path] = ImageTexture.create_from_image(img) if img is Image else null
	return _silhouettes[scene_path]

# --- Drawing: overlay ------------------------------------------------------------------------

func _draw_overlay() -> void:
	var ci := _overlay
	if not world:
		_draw_message("No world open. Use the world picker: New world... or Import from MetSys map.")
		return
	var ids: Array[String] = []
	for id in world.get_room_ids():
		if world.get_room_layer(id) == layer:
			ids.append(id)
	if ids.is_empty():
		_draw_message("Empty layer. Press R and drag to draw a room, or drop .tscn scenes here.")
	if not hovered_room.is_empty() and world.has_room(hovered_room):
		for r in world.get_world_rects(hovered_room):
			ci.draw_rect(world_rect_to_screen(r), Color(1, 1, 1, 0.1))
	_draw_links(ci)
	if show.gates:
		_draw_connections(ci, ids)
	_draw_route(ci)
	if show.markers:
		for id in ids:
			_draw_markers(ci, id)
	if show.gates:
		for id in ids:
			_draw_gates(ci, id)
	if show.labels:
		for id in ids:
			_draw_room_label(ci, id)
	if show.area_labels:
		_draw_area_labels(ci, ids)
	if show.issues:
		_draw_issue_badges(ci, ids)
	if show.pins:
		_draw_pins(ci)
	if world.has_room(selected_room) and world.get_room_layer(selected_room) == layer:
		_draw_selection(ci)
	_draw_drag_feedback(ci)
	_draw_title(ci)
	if show.legend:
		_draw_legend(ci)

func _draw_message(text: String) -> void:
	var font := get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_overlay.draw_string(font, Vector2((size.x - w) / 2.0, size.y / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.6))

func _draw_connections(ci: CanvasItem, ids: Array[String]) -> void:
	var b := _border_px()
	for id in ids:
		var gates := world.get_gates(id)
		for gate_name in gates:
			var gate: Dictionary = gates[gate_name]
			var to: String = gate.get("to", "")
			if not world.has_gate(to, gate.get("to_gate", "")) or world.get_room_layer(to) != layer:
				continue
			var back := world.get_gate(to, gate.to_gate)
			var two_way: bool = back.get("to", "") == id and back.get("to_gate", "") == gate_name
			if two_way and to < id:
				continue # drawn from the other side
			var p1 := world_to_screen(world.get_gate_world_pos(id, gate_name))
			var p2 := world_to_screen(world.get_gate_world_pos(to, gate.to_gate))
			var reqs: PackedStringArray = analysis.get_door_requires(IDPWorld.edge_key(id, gate_name, to, gate.to_gate)) if analysis else PackedStringArray()
			var color := get_room_color(id).lightened(0.15)
			var near := p1.distance_to(p2) < maxf(world.get_grid() * 4.0 * zoom, 18.0)
			if near:
				# Short corridor between touching rooms, as on a hand-drawn map.
				ci.draw_line(p1, p2, color.darkened(0.5), b * 3.0 + 2.0)
				ci.draw_line(p1, p2, color, b * 3.0)
			else:
				ci.draw_dashed_line(p1, p2, Color(color, 0.8), 2.0, 8.0)
			var mid := (p1 + p2) / 2.0
			if not reqs.is_empty():
				_draw_lock(ci, mid, 6.0, IDPMapCanvas.ability_color(reqs[0]))
			if not two_way or gate.get("one_way", false):
				var dir := (p2 - p1).normalized() if p1.distance_to(p2) > 1 else Vector2.RIGHT
				var tip := mid + dir * 7.0
				var side := Vector2(-dir.y, dir.x) * 5.0
				ci.draw_colored_polygon(PackedVector2Array([tip, mid - dir * 3.0 + side, mid - dir * 3.0 - side]), Color(1, 0.85, 0.2))

func _draw_links(ci: CanvasItem) -> void:
	for link in world.get_links():
		if not world.has_room(link.a) or not world.has_room(link.b):
			continue
		if world.get_room_layer(link.a) != layer or world.get_room_layer(link.b) != layer:
			continue
		var p1 := world_to_screen(world.get_room_label_pos(link.a))
		var p2 := world_to_screen(world.get_room_label_pos(link.b))
		ci.draw_dashed_line(p1, p2, Color(0.8, 0.6, 1.0, 0.9), 2.0, 5.0)

func _draw_gates(ci: CanvasItem, id: String) -> void:
	var s := _gate_px()
	var font := get_theme_default_font()
	var gates := world.get_gates(id)
	for gate_name in gates:
		var gate: Dictionary = gates[gate_name]
		var p := world_to_screen(world.get_gate_world_pos(id, gate_name))
		var connected := world.has_gate(gate.get("to", ""), gate.get("to_gate", ""))
		var color := Color.WHITE if connected else Color(1, 0.3, 0.3)
		if gate.get("one_way", false):
			color = Color(1, 0.85, 0.2)
		var reqs: Array = gate.get("requires", [])
		if not reqs.is_empty():
			color = IDPMapCanvas.ability_color(reqs[0])
		var r := Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s))
		if gate.get("side", "") == "door":
			ci.draw_circle(p, s * 0.6, color)
			ci.draw_circle(p, s * 0.6, Color.BLACK, false, 1.0)
		else:
			ci.draw_rect(r, color)
			ci.draw_rect(r, Color.BLACK, false, 1.0)
		if id == selected_room and gate_name == selected_gate:
			ci.draw_rect(r.grow(3), COLOR_SELECT, false, 2.0)
		if zoom >= 0.12:
			ci.draw_string_outline(font, p + Vector2(s * 0.7, -s * 0.7), gate_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			ci.draw_string(font, p + Vector2(s * 0.7, -s * 0.7), gate_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))

func _draw_lock(ci: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	ci.draw_arc(center - Vector2(0, r * 0.35), r * 0.5, PI, TAU, 10, color, maxf(1.5, r * 0.25))
	ci.draw_rect(Rect2(center - Vector2(r * 0.75, r * 0.3), Vector2(r * 1.5, r * 1.1)), color)
	ci.draw_rect(Rect2(center - Vector2(r * 0.75, r * 0.3), Vector2(r * 1.5, r * 1.1)), Color.BLACK, false, 1.0)

func _draw_room_label(ci: CanvasItem, id: String) -> void:
	var bounds := world_rect_to_screen(world.get_room_bounds(id))
	if bounds.size.x < 90 or bounds.size.y < 26:
		return
	var info: Dictionary = analysis.get_info(id) if analysis else {}
	var font := get_theme_default_font()
	var fs := int(clampf(bounds.size.y * 0.18, 9, 16))
	var center := world_to_screen(world.get_room_label_pos(id))
	var lines: Array = [[info.get("name", id), Color.WHITE]]
	if info.get("is_boss", false):
		var names: PackedStringArray = info.get("boss_names", PackedStringArray())
		lines.append([", ".join(names) if not names.is_empty() else "Boss", Color(1, 0.6, 0.55)])
	if not world.has_scene_reference(id) and bounds.size.y >= 48:
		lines.append(["(no scene)", Color(1, 1, 1, 0.55)])
	var y := center.y - fs * 1.2 * lines.size() / 2.0 + fs
	for line in lines:
		var text: String = line[0]
		var w := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, bounds.size.x - 4)
		var pos := Vector2(center.x - w / 2.0, y)
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, bounds.size.x - 4, fs, 4, Color(0, 0, 0, 0.85))
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, bounds.size.x - 4, fs, line[1])
		y += fs * 1.2

## Big area names beside their rooms, like a hand-made metroidvania map.
func _draw_area_labels(ci: CanvasItem, ids: Array[String]) -> void:
	_area_label_rects.clear()
	var bounds: Dictionary = {}
	for id in ids:
		var a := world.get_room_area(id)
		if a.is_empty():
			continue
		var rb := world.get_room_bounds(id)
		bounds[a] = rb if not bounds.has(a) else bounds[a].merge(rb)
	var font := get_theme_default_font()
	var fs := int(clampf(14.0 + zoom * 60.0, 14.0, 30.0))
	var layer_center := world_rect_to_screen(world.get_layer_bounds(layer)).get_center()
	for a in bounds:
		var text: String = a.to_upper()
		var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var custom := world.get_area_label_pos(a)
		var pos: Vector2
		if custom != Vector2.INF:
			pos = world_to_screen(custom)
		else:
			# Outside the map: areas right of the map's center get their name on the right.
			var sb := world_rect_to_screen(bounds[a])
			if sb.get_center().x >= layer_center.x:
				pos = Vector2(sb.end.x + 14.0, sb.get_center().y + fs * 0.35)
			else:
				pos = Vector2(sb.position.x - tsize.x - 14.0, sb.get_center().y + fs * 0.35)
		var color := world.get_area_color(a).lightened(0.25)
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.05, 0.04, 0.04))
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		_area_label_rects[a] = Rect2(pos - Vector2(0, fs), tsize)

func _draw_markers(ci: CanvasItem, id: String) -> void:
	var meta: Dictionary = scene_db.get(world.get_scene_path(id), {})
	if meta.is_empty():
		return
	var origin := world.get_origin(id)
	var icon := clampf(zoom * 250.0, 8.0, 26.0)
	var groups := [
		["Save Points", "save_points", IDPMapCanvas.SAVEPOINT_TEXTURE],
		["Collectibles", "collectibles", IDPMapCanvas.COLLECTIBLE_TEXTURE],
		["Teleporters", "teleporters", IDPMapCanvas.TELEPORTER_TEXTURE],
		["Shops", "shops", null],
		["Enemies", "enemies", null],
	]
	for g in groups:
		if not marker_filters.get(g[0], false):
			continue
		for entry in meta.get(g[1], []):
			var p := world_to_screen(origin + entry.position)
			if g[2]:
				ci.draw_texture_rect(g[2], Rect2(p - Vector2(icon / 2.0, icon), Vector2(icon, icon)), false)
			elif g[1] == "shops":
				ci.draw_circle(p, icon * 0.4, Color(1, 0.8, 0.2))
			else:
				ci.draw_circle(p, maxf(2.0, icon * 0.15), Color(1, 0.3, 0.3))
	if marker_filters.get("Bosses", false):
		for entry in meta.get("bosses", []):
			_draw_crown(ci, world_to_screen(origin + entry.position), icon * 0.4, Color(1, 0.35, 0.3))

func _draw_crown(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-r, r * 0.6), c + Vector2(-r, -r * 0.4), c + Vector2(-r * 0.5, r * 0.1),
		c + Vector2(0, -r * 0.7), c + Vector2(r * 0.5, r * 0.1), c + Vector2(r, -r * 0.4), c + Vector2(r, r * 0.6),
	])
	ci.draw_colored_polygon(pts, color)

func _draw_issue_badges(ci: CanvasItem, ids: Array[String]) -> void:
	var font := get_theme_default_font()
	for id in ids:
		if not issue_rooms.has(id):
			continue
		var b := world_rect_to_screen(world.get_room_bounds(id))
		var color: Color = [Color(0.5, 0.75, 1.0), Color(1.0, 0.75, 0.2), Color(1.0, 0.3, 0.3)][issue_rooms[id]]
		var c := Vector2(b.end.x - 8, b.position.y + 8)
		ci.draw_circle(c, 6.0, color)
		ci.draw_string(font, c + Vector2(-2, 4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)

func _draw_pins(ci: CanvasItem) -> void:
	var font := get_theme_default_font()
	for pin in world.get_pins():
		if int(pin.layer) != layer:
			continue
		var p := world_to_screen(Vector2(float(pin.x), float(pin.y)))
		var color: Color = IDPMapCanvas.PIN_COLORS.get(pin.get("kind", "note"), Color.WHITE)
		ci.draw_line(p, p - Vector2(0, 14), Color.BLACK, 2.0)
		ci.draw_circle(p - Vector2(0, 16), 5.0, color)
		ci.draw_string_outline(font, p + Vector2(8, -12), pin.text, HORIZONTAL_ALIGNMENT_LEFT, 200, 12, 3, Color.BLACK)
		ci.draw_string(font, p + Vector2(8, -12), pin.text, HORIZONTAL_ALIGNMENT_LEFT, 200, 12, color)

func _draw_route(ci: CanvasItem) -> void:
	if route.size() < 2:
		return
	var pts := PackedVector2Array()
	for i in route.size():
		if not world.has_room(route[i]):
			continue
		if world.get_room_layer(route[i]) == layer:
			pts.append(world_to_screen(world.get_room_label_pos(route[i])))
		if i + 1 < route.size():
			var gate := _gate_towards(route[i], route[i + 1])
			if not gate.is_empty() and world.get_room_layer(route[i]) == layer:
				pts.append(world_to_screen(world.get_gate_world_pos(route[i], gate)))
	if pts.size() >= 2:
		ci.draw_polyline(pts, Color(0, 0, 0, 0.6), 6.0, true)
		ci.draw_polyline(pts, COLOR_ROUTE, 3.0, true)
		ci.draw_circle(pts[0], 6.0, COLOR_ROUTE)
		ci.draw_circle(pts[pts.size() - 1], 6.0, Color(1, 0.4, 0.8))

func _gate_towards(a: String, b: String) -> String:
	var gates := world.get_gates(a)
	for gate_name in gates:
		if gates[gate_name].get("to", "") == b:
			return gate_name
	for gate_name in world.get_gates(b):
		var g: Dictionary = world.get_gates(b)[gate_name]
		if g.get("to", "") == a and world.has_gate(a, g.get("to_gate", "")):
			return g.to_gate
	return ""

func _draw_selection(ci: CanvasItem) -> void:
	var rects := world.get_world_rects(selected_room)
	for r in rects:
		ci.draw_rect(world_rect_to_screen(r).grow(_border_px() + 1.0), COLOR_SELECT, false, 2.0)
	if tool == Tool.SELECT:
		for r in rects:
			if not _has_handles(world_rect_to_screen(r)):
				continue
			for h in _handles(world_rect_to_screen(r)):
				ci.draw_rect(Rect2(h - Vector2(4, 4), Vector2(8, 8)), COLOR_SELECT)
				ci.draw_rect(Rect2(h - Vector2(4, 4), Vector2(8, 8)), Color.BLACK, false, 1.0)

## Rects smaller than this on screen get no resize handles, so clicking a small room
## always moves it (zoom in to resize).
const MIN_HANDLE_RECT := 36.0

func _has_handles(screen_rect: Rect2) -> bool:
	return screen_rect.size.x >= MIN_HANDLE_RECT and screen_rect.size.y >= MIN_HANDLE_RECT

## Corner and edge-middle handle positions: TL, T, TR, R, BR, B, BL, L.
func _handles(r: Rect2) -> Array[Vector2]:
	var c := r.get_center()
	return [r.position, Vector2(c.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, c.y),
		r.end, Vector2(c.x, r.end.y), Vector2(r.position.x, r.end.y), Vector2(r.position.x, c.y)]

func _draw_drag_feedback(ci: CanvasItem) -> void:
	if (tool == Tool.PAINT or tool == Tool.ERASE) and get_rect().has_point(_mouse):
		var color := Color(1, 0.35, 0.35) if tool == Tool.ERASE else COLOR_SELECT
		for c in _brush_cells(world.world_to_cell(screen_to_world(_mouse))):
			ci.draw_rect(world_rect_to_screen(world.cell_to_world_rect(c)), Color(color, 0.25))
			ci.draw_rect(world_rect_to_screen(world.cell_to_world_rect(c)), color, false, 1.5)
	match _drag:
		Drag.PAINT:
			if tool == Tool.PAINT and world.has_room(_paint_room):
				status_message.emit("Painted %s (%d cells). Drop a scene on it, or keep painting; Scenes > Add doors between touching rooms connects neighbors." % [_paint_room, world.get_room_cells(_paint_room).size()])
		Drag.RUBBER:
			var r := _rubber_world_rect()
			ci.draw_rect(world_rect_to_screen(r), Color(COLOR_SELECT, 0.2))
			ci.draw_rect(world_rect_to_screen(r), COLOR_SELECT, false, 2.0)
			var font := get_theme_default_font()
			ci.draw_string(font, world_to_screen(r.end) + Vector2(6, 14), "%d x %d" % [r.size.x, r.size.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_SELECT)
		Drag.CONNECT:
			if _drag_moved:
				ci.draw_line(world_to_screen(world.get_gate_world_pos(_drag_room, _drag_gate)), _mouse, COLOR_SELECT, 2.0)

func _draw_title(ci: CanvasItem) -> void:
	var font := get_theme_default_font()
	var text := "%s: %s  (layer %d)   Tool: %s" % [world.get_world_name(), world.get_layer_name(layer), layer, TOOL_NAMES[tool]]
	ci.draw_rect(Rect2(Vector2(6, 6), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14) + Vector2(12, 8)), Color(0, 0, 0, 0.55))
	ci.draw_string(font, Vector2(12, 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _draw_legend(ci: CanvasItem) -> void:
	var items := get_legend()
	if items.is_empty():
		return
	var font := get_theme_default_font()
	var line_h := 17.0
	var w := 0.0
	for item in items:
		w = maxf(w, font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var box := Rect2(Vector2(6, size.y - 12 - line_h * items.size()), Vector2(w + 34, line_h * items.size() + 6))
	ci.draw_rect(box, Color(0, 0, 0, 0.6))
	for i in items.size():
		var y := box.position.y + 4 + i * line_h
		ci.draw_rect(Rect2(Vector2(box.position.x + 6, y + 2), Vector2(14, 12)), items[i][1])
		ci.draw_string(font, Vector2(box.position.x + 26, y + 12), items[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

# --- Previews ----------------------------------------------------------------------------------

func _update_previews() -> void:
	if not show.previews or not world:
		for child in _preview_root.get_children():
			child.queue_free()
		_preview_nodes.clear()
		_preview_layer = -9999
		return
	if _preview_layer == layer:
		return
	_preview_layer = layer
	_preview_nodes.clear()
	for child in _preview_root.get_children():
		child.queue_free()
	for id in world.get_room_ids():
		var path := world.get_scene_path(id)
		if world.get_room_layer(id) != layer or path.is_empty():
			continue
		# A picture made while the game was played (IDPRoomPictures) is much cheaper than the
		# live scene, and is only used while the scene is unchanged since.
		var tex := IDPRoomPictures.load_cached(path)
		if tex:
			var pic := Sprite2D.new()
			pic.centered = false
			pic.texture = tex
			var r := IDPRoomPictures.room_rect(world, id)
			pic.position = world.get_origin(id) + r.position
			pic.scale = r.size / Vector2(tex.get_size())
			pic.set_meta(&"idp_offset", r.position)
			_preview_root.add_child(pic)
			_preview_nodes[id] = pic
			continue
		var packed := load(path) as PackedScene
		if not packed:
			continue
		var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		instance.set_meta(&"fake_map", true)
		instance.process_mode = Node.PROCESS_MODE_DISABLED
		if instance is Node2D:
			instance.position = world.get_origin(id)
		_preview_root.add_child(instance)
		_preview_nodes[id] = instance
	_after_view_change()

## Keeps a moved room's live preview in place without reloading every scene.
func _sync_preview_position(id: String) -> void:
	var node = _preview_nodes.get(id)
	if node is Node2D and is_instance_valid(node):
		node.position = world.get_origin(id) + node.get_meta(&"idp_offset", Vector2.ZERO)

# --- Hit testing -------------------------------------------------------------------------------

func gate_at(screen_pos: Vector2) -> Array:
	var s := _gate_px() * 0.8 + 3.0
	var ids := world.get_room_ids()
	for i in range(ids.size() - 1, -1, -1):
		var id := ids[i]
		if world.get_room_layer(id) != layer:
			continue
		for gate_name in world.get_gates(id):
			if world_to_screen(world.get_gate_world_pos(id, gate_name)).distance_to(screen_pos) <= s:
				return [id, gate_name]
	return []

func _handle_at(screen_pos: Vector2) -> Array:
	if not world.has_room(selected_room) or world.get_room_layer(selected_room) != layer:
		return []
	var rects := world.get_world_rects(selected_room)
	for i in rects.size():
		if not _has_handles(world_rect_to_screen(rects[i])):
			continue
		var hs := _handles(world_rect_to_screen(rects[i]))
		for h in hs.size():
			if hs[h].distance_to(screen_pos) <= 7.0:
				return [i, h]
	return []

func _area_label_at(screen_pos: Vector2) -> String:
	for a in _area_label_rects:
		if _area_label_rects[a].grow(4).has_point(screen_pos):
			return a
	return ""

func _rubber_world_rect() -> Rect2:
	var a := world.snap(screen_to_world(_drag_start))
	var b := world.snap(screen_to_world(_mouse))
	return Rect2(a, b - a).abs()

# --- Input ---------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not world:
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)

func _on_mouse_button(mb: InputEventMouseButton) -> void:
	_mouse = mb.position
	if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var factor := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
		set_zoom(zoom * pow(factor, maxf(mb.factor, 1.0)), mb.position)
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_begin_drag(Drag.PAN, mb)
		elif _drag == Drag.PAN and mb.button_index == _drag_button:
			_drag = Drag.NONE
			if mb.button_index == MOUSE_BUTTON_RIGHT and not _drag_moved:
				var w := screen_to_world(mb.position)
				context_requested.emit(world.room_at(w, layer), w, mb.position)
		accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if mb.pressed:
		grab_focus()
		_on_left_press(mb)
	else:
		_on_left_release(mb)

func _begin_drag(kind: int, mb: InputEventMouseButton) -> void:
	_drag = kind
	_drag_button = mb.button_index
	_drag_start = mb.position
	_drag_moved = false
	_drag_orig_pan = pan
	_drag_checkpointed = false

func _checkpoint_once() -> void:
	if not _drag_checkpointed:
		world.checkpoint()
		_drag_checkpointed = true

func _on_left_press(mb: InputEventMouseButton) -> void:
	var w := screen_to_world(mb.position)
	var room := world.room_at(w, layer)
	match tool:
		Tool.PAINT, Tool.ERASE:
			world.checkpoint()
			_begin_drag(Drag.PAINT, mb)
			var cell := world.world_to_cell(w)
			_paint_last = cell
			_paint_room = ""
			if tool == Tool.PAINT and not mb.shift_pressed:
				_paint_room = world.room_at_cell(cell, layer)
				if not _paint_room.is_empty():
					selected_room = _paint_room
					room_selected.emit(_paint_room)
			_paint_along(cell, cell)
			redraw()
			return
		Tool.ROOM:
			_begin_drag(Drag.RUBBER, mb)
			return
		Tool.RECT:
			if selected_room.is_empty():
				status_message.emit("Select a room first, then drag to add a rectangle to it.")
				return
			_begin_drag(Drag.RUBBER, mb)
			return
		Tool.PIN:
			pin_requested.emit(w)
			return
		Tool.GATE:
			var hit := gate_at(mb.position)
			if not hit.is_empty():
				_select_gate(hit[0], hit[1])
				_begin_drag(Drag.CONNECT, mb)
				_drag_room = hit[0]
				_drag_gate = hit[1]
				return
			if not room.is_empty():
				world.checkpoint()
				var g := world.add_gate(room, w)
				_select_gate(room, g)
				status_message.emit("Added gate %s.%s. Drag from it to another gate to connect." % [room, g])
			return
	# Select tool.
	if mb.double_click and not room.is_empty():
		room_activated.emit(room)
		return
	# Gates before resize handles: a gate often sits on an edge's middle handle.
	var hit := gate_at(mb.position)
	if not hit.is_empty():
		_select_gate(hit[0], hit[1])
		_begin_drag(Drag.MOVE_GATE if mb.shift_pressed else Drag.CONNECT, mb)
		_drag_room = hit[0]
		_drag_gate = hit[1]
		return
	var handle := _handle_at(mb.position)
	if not handle.is_empty():
		_begin_drag(Drag.RESIZE, mb)
		_drag_room = selected_room
		_drag_rect_index = handle[0]
		_drag_handle = handle[1]
		_drag_orig_rect = world.get_world_rects(selected_room)[handle[0]]
		return
	var label := _area_label_at(mb.position)
	if not label.is_empty() and room.is_empty():
		_begin_drag(Drag.MOVE_LABEL, mb)
		_drag_area = label
		return
	if room.is_empty():
		selected_room = ""
		selected_gate = ""
		room_selected.emit("")
		_begin_drag(Drag.PAN, mb)
		redraw()
		return
	if mb.shift_pressed and not selected_room.is_empty() and selected_room != room:
		route_requested.emit(selected_room, room)
		return
	selected_room = room
	selected_gate = ""
	room_selected.emit(room)
	_begin_drag(Drag.MOVE_ROOM, mb)
	_drag_room = room
	_drag_orig_origin = world.get_origin(room)
	_drag_orig_bounds = world.get_room_bounds(room)
	redraw()

func _on_left_release(mb: InputEventMouseButton) -> void:
	var w := screen_to_world(mb.position)
	match _drag:
		Drag.RUBBER:
			var r := _rubber_world_rect()
			if r.size.x >= world.get_grid() and r.size.y >= world.get_grid():
				world.checkpoint()
				if tool == Tool.ROOM:
					var id := world.add_room("Room_01", r, layer, new_room_area)
					selected_room = id
					selected_gate = ""
					room_selected.emit(id)
					status_message.emit("Created %s. Assign a scene in Inspect, or right-click > Create scene." % id)
				elif world.has_room(selected_room):
					world.add_rect(selected_room, r)
		Drag.CONNECT:
			if _drag_moved:
				var target := gate_at(mb.position)
				if target.is_empty():
					var room := world.room_at(w, layer)
					if not room.is_empty() and room != _drag_room:
						world.checkpoint()
						var g := world.add_gate(room, w)
						world.connect_gates(_drag_room, _drag_gate, room, g)
						status_message.emit("Connected %s.%s <-> %s.%s" % [_drag_room, _drag_gate, room, g])
				elif target[0] != _drag_room:
					world.checkpoint()
					world.connect_gates(_drag_room, _drag_gate, target[0], target[1])
					status_message.emit("Connected %s.%s <-> %s.%s" % [_drag_room, _drag_gate, target[0], target[1]])
	_drag = Drag.NONE
	redraw()

func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	_mouse = mm.position
	if _drag == Drag.PAINT:
		var cell := world.world_to_cell(screen_to_world(mm.position))
		if cell != _paint_last:
			_paint_along(_paint_last, cell)
			_paint_last = cell
		redraw()
		accept_event()
		return
	if tool == Tool.PAINT or tool == Tool.ERASE:
		_overlay.queue_redraw()
	if _drag != Drag.NONE:
		if mm.position.distance_to(_drag_start) > 3.0:
			_drag_moved = true
		if _drag_moved:
			_apply_drag(mm.position)
		accept_event()
		return
	var w := screen_to_world(mm.position)
	var room := world.room_at(w, layer)
	if room != hovered_room:
		hovered_room = room
		_overlay.queue_redraw()
	hovered_changed.emit(room, w)
	# Cursor feedback.
	if tool == Tool.SELECT:
		var handle := _handle_at(mm.position)
		if not gate_at(mm.position).is_empty():
			mouse_default_cursor_shape = CURSOR_CROSS
		elif not handle.is_empty():
			mouse_default_cursor_shape = [CURSOR_FDIAGSIZE, CURSOR_VSIZE, CURSOR_BDIAGSIZE, CURSOR_HSIZE][handle[1] % 4]
		elif not room.is_empty():
			mouse_default_cursor_shape = CURSOR_MOVE
		else:
			mouse_default_cursor_shape = CURSOR_ARROW
	else:
		mouse_default_cursor_shape = CURSOR_CROSS

func _apply_drag(pos: Vector2) -> void:
	var delta_world := (pos - _drag_start) / zoom
	match _drag:
		Drag.PAN:
			pan = _drag_orig_pan + (pos - _drag_start)
			_after_view_change()
			return
		Drag.MOVE_ROOM:
			_checkpoint_once()
			# Snap the room's top-left corner, not its origin, so it lines up with neighbors.
			var snapped := world.snap(_drag_orig_bounds.position + delta_world)
			world.set_origin(_drag_room, _drag_orig_origin + snapped - _drag_orig_bounds.position)
			_sync_preview_position(_drag_room)
		Drag.RESIZE:
			_checkpoint_once()
			var r := _drag_orig_rect
			var p := world.snap(screen_to_world(pos))
			var left := r.position.x
			var top := r.position.y
			var right := r.end.x
			var bottom := r.end.y
			if _drag_handle in [0, 6, 7]:
				left = minf(p.x, right - world.get_grid())
			if _drag_handle in [2, 3, 4]:
				right = maxf(p.x, left + world.get_grid())
			if _drag_handle in [0, 1, 2]:
				top = minf(p.y, bottom - world.get_grid())
			if _drag_handle in [4, 5, 6]:
				bottom = maxf(p.y, top + world.get_grid())
			var nr := Rect2(left, top, right - left, bottom - top)
			world.set_local_rect(_drag_room, _drag_rect_index, Rect2(nr.position - world.get_origin(_drag_room), nr.size))
		Drag.MOVE_GATE:
			_checkpoint_once()
			world.set_gate_world_pos(_drag_room, _drag_gate, screen_to_world(pos))
		Drag.MOVE_LABEL:
			_checkpoint_once()
			var p := screen_to_world(pos)
			world.set_area_value(_drag_area, "label_pos", [p.x, p.y])
	redraw()

func _on_key(key: InputEventKey) -> void:
	var handled := true
	var ctrl := key.ctrl_pressed or key.meta_pressed
	match key.keycode:
		KEY_Z when ctrl and key.shift_pressed:
			_redo()
		KEY_Z when ctrl:
			if world.undo():
				status_message.emit("Undo")
		KEY_Y when ctrl:
			_redo()
		KEY_D when ctrl:
			if world.has_room(selected_room):
				world.checkpoint()
				selected_room = world.duplicate_room(selected_room)
				room_selected.emit(selected_room)
		KEY_V:
			set_tool(Tool.SELECT)
		KEY_R:
			set_tool(Tool.ROOM)
		KEY_E:
			set_tool(Tool.RECT)
		KEY_G:
			set_tool(Tool.GATE)
		KEY_P:
			set_tool(Tool.PIN)
		KEY_B:
			set_tool(Tool.PAINT)
		KEY_X:
			set_tool(Tool.ERASE)
		KEY_BRACKETLEFT:
			set_brush_size(brush_size - 1)
		KEY_BRACKETRIGHT:
			set_brush_size(brush_size + 1)
		KEY_F:
			fit_to_layer()
		KEY_ESCAPE:
			if tool != Tool.SELECT:
				set_tool(Tool.SELECT)
			else:
				route.clear()
				highlight_rooms.clear()
				redraw()
		KEY_DELETE, KEY_BACKSPACE:
			delete_selection()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if world.has_room(selected_room):
				var d: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[key.keycode]
				world.checkpoint()
				world.set_origin(selected_room, world.get_origin(selected_room) + d * world.get_grid())
				_sync_preview_position(selected_room)
			else:
				handled = false
		KEY_EQUAL, KEY_KP_ADD:
			set_zoom(zoom * 1.25)
		KEY_MINUS, KEY_KP_SUBTRACT:
			set_zoom(zoom / 1.25)
		_:
			handled = false
	if handled:
		accept_event()
		redraw()

func _redo() -> void:
	if world.redo():
		status_message.emit("Redo")

## Deletes the selected gate, else the selected room.
func delete_selection() -> void:
	if not world.has_room(selected_room):
		return
	world.checkpoint()
	if world.has_gate(selected_room, selected_gate):
		world.remove_gate(selected_room, selected_gate)
		status_message.emit("Deleted gate %s. Ctrl+Z to undo." % selected_gate)
		selected_gate = ""
	else:
		var id := selected_room
		world.remove_room(id)
		selected_room = ""
		room_selected.emit("")
		status_message.emit("Deleted room %s. Ctrl+Z to undo." % id)
	redraw()

func _select_gate(room: String, gate_name: String) -> void:
	selected_room = room
	selected_gate = gate_name
	room_selected.emit(room)
	gate_selected.emit(room, gate_name)
	redraw()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			if not hovered_room.is_empty():
				hovered_room = ""
				_overlay.queue_redraw()
		NOTIFICATION_RESIZED:
			redraw()

# --- Drag and drop from the FileSystem dock --------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not world or not data is Dictionary or data.get("type", "") != "files":
		return false
	for f in data.get("files", []):
		if str(f).ends_with(".tscn") or str(f).ends_with(".scn"):
			return true
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var files: PackedStringArray = []
	for f in data.get("files", []):
		if str(f).ends_with(".tscn") or str(f).ends_with(".scn"):
			files.append(f)
	scenes_dropped.emit(files, screen_to_world(at_position))

func _get_tooltip(at_position: Vector2) -> String:
	if not world:
		return ""
	var hit := gate_at(at_position)
	if not hit.is_empty():
		var gate := world.get_gate(hit[0], hit[1])
		var text := "Gate %s.%s (%s)" % [hit[0], hit[1], world.get_gate_side(hit[0], hit[1])]
		if gate.has("to"):
			text += "\n-> %s.%s" % [gate.to, gate.get("to_gate", "?")]
		else:
			text += "\nNot connected: drag from it to another gate."
		if not gate.get("requires", []).is_empty():
			text += "\nRequires: " + ", ".join(gate.requires)
		return text
	var id := world.room_at(screen_to_world(at_position), layer)
	if id.is_empty():
		return ""
	var info: Dictionary = analysis.get_info(id) if analysis else {}
	var lines: PackedStringArray = [info.get("name", id)]
	var tags: PackedStringArray = []
	for key in ["type", "area", "status"]:
		if not str(info.get(key, "")).is_empty():
			tags.append(str(info[key]).capitalize() if key != "area" else info[key])
	if not tags.is_empty():
		lines.append(" | ".join(tags))
	if info.get("is_boss", false) and not info.boss_names.is_empty():
		lines.append("Boss: " + ", ".join(info.boss_names))
	if not info.get("grants", PackedStringArray()).is_empty():
		lines.append("Grants: " + ", ".join(info.grants))
	if analysis:
		lines.append("Sphere %s, nearest save: %s" % [analysis.sphere_of.get(id, "-"), analysis.save_distance.get(id, "none")])
	var b := world.get_room_bounds(id)
	lines.append("%d x %d px, %d gate(s)" % [b.size.x, b.size.y, world.get_gates(id).size()])
	var path := world.get_scene_path(id)
	lines.append(path if not path.is_empty() else "No scene assigned")
	return "\n".join(lines)
