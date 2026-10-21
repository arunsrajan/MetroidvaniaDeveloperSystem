@tool
class_name MDSFullViewTools
extends RefCounted
## The Full view's own tools (see [method MDSRoomView.open_full]), on [member canvas] in its Full
## view mode. Rooms are drawn at their actual size as outlines first (Rectangle, Ellipse, Polygon,
## Curvy), then Generate map makes them rooms on the map ([MDSRoomSketches]): one room per
## outline, or split into rooms ([member kind]), in the area picked ([member area]). The Rooms
## tool selects rooms and outlines (a click, Ctrl or Shift+click to add or take out, a box on
## empty space), moves them (rooms in paint cells, stopping against the others, with doors where
## they touch), Delete removes them, Ctrl+A selects them all, the arrows nudge them, and a
## double-click edits the rooms in the Room view. Generate area drags a box for the Generate area
## dialog. Ctrl+Z / Ctrl+Y under these tools undo and redo on the map.

signal status_message(text: String)
## A double-click on a room under the Rooms tool: edit [param ids] in the Room view.
signal rooms_requested(ids: Array[String])
## Generate area: the box of paint cells dragged.
signal generate_requested(box: Rect2i)
## The rooms or outlines selected changed.
signal selection_changed

enum Tool { ROOMS, RECTANGLE, ELLIPSE, POLYGON, CURVY, GENERATE }
const TOOL_NAMES: PackedStringArray = ["Rooms", "Rectangle", "Ellipse", "Polygon", "Curvy", "Gen. area"]
const TOOL_TIPS: PackedStringArray = [
	"Select rooms and outlines: click (Ctrl or Shift adds or takes out), or drag a box on empty space. Drag them to move them: rooms move in paint cells and stop against the others, with doors where they touch. Double-click a room to edit it (and the others selected) in the Room view. Delete removes them, Ctrl+A selects them all, the arrows nudge them",
	"Draw a room's outline: drag a rectangle (Snap to cells: on the paint cells). Generate map makes the outlines rooms on the map",
	"Draw an ellipse: drag its box (Shift: a circle). Generate map makes the outlines rooms on the map",
	"Draw a polygon: click its corners, then click the first one, double-click or press Enter to close it. Backspace takes the last corner back, Esc drops it",
	"Draw a curvy outline freehand: drag around it and release, it closes and is smoothed",
	"Generate area: drag a box for the Generate area dialog, an area of rooms with an outline of its own (rectangle, blocks, curvy or hybrid), like the map's Generate area tool",
]
const COLOR_SKETCH := Color(0.45, 0.85, 1.0)
const COLOR_SELECT := Color(1.0, 0.92, 0.35)
const COLOR_NO_AREA := Color(0.7, 0.72, 0.78)

enum Drag { NONE, BOX, FREEHAND, SELECT, MOVE }

var canvas: MDSRoomCanvas
## A [enum Tool], or -1 while one of the Room view's painting tools is used.
var tool := -1
## What an outline drawn makes: [constant MDSRoomSketches.ROOM] or [constant MDSRoomSketches.ROOMS].
var kind := MDSRoomSketches.ROOM
## The area of an outline drawn: an area's name, [constant MDSRoomSketches.NEW_AREA] or "".
var area := MDSRoomSketches.NEW_AREA
## Rectangle and Ellipse on the paint cells' corners, Polygon on the world grid.
var snap := true
## Each outline drawn is made a room at once.
var right_away := false
## How outlines are made rooms (room sizes of split outlines...).
var sketches := MDSRoomSketches.new()
## The rooms selected (id -> true) and the outlines (sketch index -> true).
var rooms: Dictionary = {}
var outlines: Dictionary = {}

var _drag: int = Drag.NONE
var _draft := PackedVector2Array() ## world px
var _from := Vector2.ZERO ## world px
var _to := Vector2.ZERO
var _add := false
var _moved := false
var _checkpointed := false
var _origins: Dictionary = {}
var _starts: Dictionary = {}
var _own: Dictionary = {}
var _taken: Dictionary = {}
var _delta := Vector2i.ZERO
var _mouse := Vector2.INF ## world px
var _preview: Array = []
var _preview_key := 0
var _runs := 0

func _init(p_canvas: MDSRoomCanvas) -> void:
	canvas = p_canvas

func _world() -> MDSWorld:
	return canvas.world

func _layer() -> int:
	return canvas.full_layer

## Screen to world px, and back.
func to_world(screen: Vector2) -> Vector2:
	return canvas.local_to_world(canvas.screen_to_local(screen))

func to_screen(world_pos: Vector2) -> Vector2:
	return canvas.local_to_screen(canvas.world_to_local(world_pos))

## Starts afresh (another world or layer): nothing drawn or selected.
func reset() -> void:
	_cancel()
	rooms.clear()
	outlines.clear()
	invalidate()

## The world changed: the cells the outlines will take are measured again.
func invalidate() -> void:
	_preview_key = 0
	for id: String in rooms.keys():
		if not _world() or not _world().has_room(id) or _world().get_room_layer(id) != _layer():
			rooms.erase(id)
	var count := MDSRoomSketches.get_all(_world()).size() if _world() else 0
	for i: int in outlines.keys():
		if i >= count:
			outlines.erase(i)

func set_tool(t: int) -> void:
	_cancel()
	tool = t
	canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS if t > Tool.ROOMS else Control.CURSOR_ARROW
	canvas._overlay.queue_redraw()

func _cancel() -> void:
	_drag = Drag.NONE
	_draft.clear()

## Whether a shape is being drawn or something moved.
func is_busy() -> bool:
	return _drag != Drag.NONE or not _draft.is_empty()

# --- Selection ---------------------------------------------------------------------------------

## The rooms selected, in the map's order.
func selected_rooms() -> Array[String]:
	var out: Array[String] = []
	if not _world():
		return out
	for id in _world().get_room_ids():
		if rooms.has(id) and _world().get_room_layer(id) == _layer():
			out.append(id)
	return out

func selected_outlines() -> Array[int]:
	var out: Array[int] = []
	for i: int in outlines:
		out.append(i)
	out.sort()
	return out

func select(ids: Array, sketch_indices: Array = []) -> void:
	rooms.clear()
	outlines.clear()
	for id in ids:
		if _world().has_room(str(id)):
			rooms[str(id)] = true
	for i in sketch_indices:
		outlines[int(i)] = true
	selection_changed.emit()
	canvas._overlay.queue_redraw()

func clear_selection() -> void:
	select([])

## Every room and outline of the layer.
func select_all() -> void:
	var ids: Array[String] = []
	for id in _world().get_room_ids():
		if _world().get_room_layer(id) == _layer():
			ids.append(id)
	select(ids, MDSRoomSketches.on_layer(_world(), _layer()))
	status_message.emit("Selected %d room(s) and %d outline(s)." % [rooms.size(), outlines.size()])

## The outlines' boxes (world px), to fit the view around.
func outline_bounds() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not _world():
		return out
	for i in MDSRoomSketches.on_layer(_world(), _layer()):
		out.append(MDSGeometry.bounds(MDSRoomSketches.polygon(_world(), i)))
	return out

## What the Make and Area pickers say goes for the outlines selected too.
func apply_to_selected() -> int:
	if outlines.is_empty():
		return 0
	_world().checkpoint()
	for i in selected_outlines():
		MDSRoomSketches.set_value(_world(), i, "kind", kind)
		MDSRoomSketches.set_value(_world(), i, "area", area)
	invalidate()
	return outlines.size()

# --- Actions -----------------------------------------------------------------------------------

## Makes rooms of the outlines [param indices], else of those selected, else of every outline of
## the layer (see [method MDSRoomSketches.generate]); the new rooms are selected. With
## [param checkpoint] it is one undo step on the map. Returns what it made ({} when there was
## nothing to make).
func generate_map(checkpoint := true, indices: Array = []) -> Dictionary:
	var picked: Array = indices if not indices.is_empty() else selected_outlines()
	if picked.is_empty():
		picked = MDSRoomSketches.on_layer(_world(), _layer())
	if picked.is_empty():
		status_message.emit("Nothing to generate: draw rooms first with Rectangle, Ellipse, Polygon or Curvy.")
		return {}
	if checkpoint:
		_world().checkpoint()
	_runs += 1
	sketches.seed_value = hash([_world().get_room_ids().size(), _runs])
	var r := sketches.generate(_world(), _layer(), picked)
	select(r.rooms)
	invalidate()
	var text := "Generate map: %d room(s) from %d outline(s), %d door(s)" % [r.rooms.size(), r.outlines, r.doors]
	if not r.areas.is_empty():
		text += ", new area(s): %s" % ", ".join(r.areas)
	if r.left > 0:
		text += "; %d outline(s) only over rooms there already, left out" % r.left
	status_message.emit(text + ". Ctrl+Z takes it back; click a room to paint it, or Generate all for caves.")
	return r

## Removes the rooms and outlines selected (one undo step).
func delete_selection() -> void:
	var ids := selected_rooms()
	var picked := selected_outlines()
	if ids.is_empty() and picked.is_empty():
		return
	_world().checkpoint()
	MDSRoomSketches.remove(_world(), picked)
	for id in ids:
		_world().remove_room(id)
	clear_selection()
	invalidate()
	status_message.emit("Deleted %d room(s) and %d outline(s). Ctrl+Z to undo." % [ids.size(), picked.size()])

## Removes every outline of the layer (one undo step). Returns how many.
func clear_outlines() -> int:
	if MDSRoomSketches.count(_world(), _layer()) == 0:
		return 0
	_world().checkpoint()
	var n := MDSRoomSketches.clear_layer(_world(), _layer())
	outlines.clear()
	invalidate()
	status_message.emit("Cleared %d outline(s). Ctrl+Z to undo." % n)
	return n

## Adds outline [param poly] (world px) drawn with [param draw], with what the pickers say; made a
## room at once with [member right_away]. Returns its index, or -1.
func add_outline(poly: PackedVector2Array, draw: String) -> int:
	poly = MDSRoomSketches.closed(poly)
	var s := _world().get_paint_cell()
	if poly.size() < 3 or absf(MDSGeometry.signed_area(poly)) < s.x * s.y * 0.1:
		status_message.emit("Too small for a room: draw it bigger (a paint cell is %d x %d px)." % [s.x, s.y])
		return -1
	_world().checkpoint()
	var i := MDSRoomSketches.add(_world(), _layer(), poly, kind, area, draw)
	invalidate()
	canvas._overlay.queue_redraw()
	if right_away:
		generate_map(false, [i])
		return i
	var got := sketches.cells_of(_world(), poly)
	status_message.emit("Outline drawn (%d paint cells, %s). Draw more, then Generate map makes them rooms; Rooms tool: select, move or delete them." % [got.cells.size(), "one room" if kind == MDSRoomSketches.ROOM else "split into rooms"])
	return i

# --- Input -------------------------------------------------------------------------------------

## Handles [param event] while a Full view tool is picked. Returns whether it did (the wheel and
## the middle and right buttons stay the canvas's: zoom and pan).
func gui_input(event: InputEvent) -> bool:
	if tool < 0 or not _world():
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		canvas.grab_focus()
		canvas._mouse = mb.position
		var p := to_world(mb.position)
		if mb.double_click:
			_double_click(mb, p)
		elif mb.pressed:
			_press(mb, p)
		else:
			_release(mb, p)
		return true
	if event is InputEventMouseMotion:
		if canvas._panning != 0:
			return false
		var mm := event as InputEventMouseMotion
		canvas._mouse = mm.position
		_motion(mm, to_world(mm.position))
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return _key(event as InputEventKey)
	return false

func _snap_cells(p: Vector2) -> Vector2:
	return MDSRoomSketches.snap_to_cells(_world(), p) if snap else p

func _snap_grid(p: Vector2) -> Vector2:
	return _world().snap(p) if snap else p

func _press(mb: InputEventMouseButton, p: Vector2) -> void:
	match tool:
		Tool.ROOMS:
			_rooms_press(mb, p)
		Tool.RECTANGLE, Tool.ELLIPSE:
			_drag = Drag.BOX
			_from = _snap_cells(p)
			_to = _from
		Tool.GENERATE:
			_drag = Drag.BOX
			_from = MDSRoomSketches.snap_to_cells(_world(), p)
			_to = _from
		Tool.POLYGON:
			if _draft.size() >= 3 and to_screen(_draft[0]).distance_to(mb.position) <= 10.0:
				_close_polygon()
				return
			_draft.append(_snap_grid(p))
			if _draft.size() == 1:
				status_message.emit("Polygon: click its next corners; click the first one, double-click or press Enter to close it.")
		Tool.CURVY:
			_drag = Drag.FREEHAND
			_draft = PackedVector2Array([p])

func _release(mb: InputEventMouseButton, p: Vector2) -> void:
	var was := _drag
	_drag = Drag.NONE
	match was:
		Drag.BOX:
			_to = _box_corner(p, mb.shift_pressed)
			if (to_screen(_to) - to_screen(_from)).abs().x < 6.0 or (to_screen(_to) - to_screen(_from)).abs().y < 6.0:
				return
			if tool == Tool.GENERATE:
				var s := _world().get_paint_cell()
				var b := Rect2(_from, _to - _from).abs()
				var c0 := Vector2i((b.position / s).round())
				var c1 := Vector2i((b.end / s).round())
				if c1.x - c0.x >= 2 and c1.y - c0.y >= 2:
					generate_requested.emit(Rect2i(c0, c1 - c0))
				else:
					status_message.emit("Generate area needs a box of 2 x 2 paint cells or more.")
			elif tool == Tool.ELLIPSE:
				add_outline(MDSRoomSketches.ellipse(_from, _to), "ellipse")
			else:
				add_outline(MDSRoomSketches.rectangle(_from, _to), "rectangle")
		Drag.FREEHAND:
			_draft.append(p)
			var stroke := _draft
			_draft = PackedVector2Array()
			if stroke.size() >= 3:
				add_outline(MDSRoomSketches.freehand(stroke), "curvy")
		Drag.SELECT:
			_to = p
			_box_select(Rect2(_from, _to - _from).abs())
		Drag.MOVE:
			_finish_move()

func _motion(_mm: InputEventMouseMotion, p: Vector2) -> void:
	_mouse = p
	match _drag:
		Drag.BOX:
			_to = _box_corner(p, _mm.shift_pressed)
		Drag.FREEHAND:
			if _draft.is_empty() or to_screen(_draft[_draft.size() - 1]).distance_to(_mm.position) >= 4.0:
				_draft.append(p)
		Drag.SELECT:
			_to = p
		Drag.MOVE:
			_move_to(p)

## The box tools' second corner: snapped, and square for a circle ([param square]).
func _box_corner(p: Vector2, square: bool) -> Vector2:
	var q := MDSRoomSketches.snap_to_cells(_world(), p) if tool == Tool.GENERATE else _snap_cells(p)
	if square and tool == Tool.ELLIPSE:
		var d := q - _from
		var side := maxf(absf(d.x), absf(d.y))
		q = _from + Vector2(side * signf(d.x if d.x != 0.0 else 1.0), side * signf(d.y if d.y != 0.0 else 1.0))
	return q

func _close_polygon() -> void:
	var pts := _draft
	_draft = PackedVector2Array()
	if pts.size() >= 3:
		add_outline(pts, "polygon")

func _double_click(mb: InputEventMouseButton, p: Vector2) -> void:
	if tool == Tool.POLYGON:
		_close_polygon()
	elif tool == Tool.ROOMS:
		var id := _world().room_at(p, _layer(), true)
		if not id.is_empty():
			if not rooms.has(id):
				select([id])
			rooms_requested.emit(selected_rooms())
	else:
		_press(mb, p)

func _rooms_press(mb: InputEventMouseButton, p: Vector2) -> void:
	var add := mb.ctrl_pressed or mb.shift_pressed or mb.meta_pressed
	var sketch := MDSRoomSketches.at(_world(), p, _layer())
	var room := _world().room_at(p, _layer(), true) if sketch < 0 else ""
	if sketch < 0 and room.is_empty():
		if not add:
			clear_selection()
		_drag = Drag.SELECT
		_add = add
		_from = p
		_to = p
		return
	if add:
		if sketch >= 0:
			if outlines.has(sketch):
				outlines.erase(sketch)
			else:
				outlines[sketch] = true
		elif rooms.has(room):
			rooms.erase(room)
		else:
			rooms[room] = true
		selection_changed.emit()
		return
	if (sketch >= 0 and not outlines.has(sketch)) or (not room.is_empty() and not rooms.has(room)):
		if sketch >= 0:
			select([], [sketch])
		else:
			select([room])
	_begin_move(p)
	var what: PackedStringArray = []
	if not rooms.is_empty():
		what.append("%d room(s)" % rooms.size() if rooms.size() != 1 else selected_rooms()[0])
	if not outlines.is_empty():
		what.append("%d outline(s)" % outlines.size())
	status_message.emit("Selected %s: drag to move, Delete removes, double-click a room to edit it in the Room view." % " and ".join(what))

func _box_select(box: Rect2) -> void:
	if not _add:
		rooms.clear()
		outlines.clear()
	for id in _world().get_room_ids():
		if _world().get_room_layer(id) == _layer() and _world().get_room_bounds(id).intersects(box):
			rooms[id] = true
	for i in MDSRoomSketches.in_box(_world(), box, _layer(), true):
		outlines[i] = true
	selection_changed.emit()
	status_message.emit("Selected %d room(s) and %d outline(s). Double-click one of the rooms (or press Room view) to edit them in the Room view." % [rooms.size(), outlines.size()])

func _begin_move(p: Vector2) -> void:
	_drag = Drag.MOVE
	_from = p
	_moved = false
	_checkpointed = false
	_origins.clear()
	_starts.clear()
	var ids := selected_rooms()
	for id in ids:
		_origins[id] = _world().get_origin(id)
	for i in selected_outlines():
		_starts[i] = (MDSRoomSketches.get_sketch(_world(), i).points as Array).duplicate()
	_own = MDSAreaTools.cells_of(_world(), ids)
	_taken = MDSAreaTools.occupied(_world(), _layer(), ids)
	_delta = Vector2i.ZERO

func _move_to(p: Vector2) -> void:
	var d := p - _from
	if not _moved and (d * canvas.zoom).length() < 4.0:
		return
	if not _checkpointed:
		_world().checkpoint()
		_checkpointed = true
	_moved = true
	_place(d)

## The rooms and outlines moving go [param d] world px from where they were: rooms by whole
## paint cells, stopping against others (the outlines with them); outlines alone by the grid.
func _place(d: Vector2) -> void:
	var ids: Array[String] = []
	ids.assign(_origins.keys())
	var px := d
	if not ids.is_empty():
		var s := _world().get_paint_cell()
		_delta = MDSAreaTools.slide(_own, _taken, _delta, Vector2i((d / s).round()))
		px = Vector2(_delta) * s
	elif snap:
		px = d.snapped(Vector2.ONE * _world().get_grid())
	var before: Vector2 = canvas.frame_origin()
	MDSAreaTools.place(_world(), ids, _origins, px)
	MDSRoomSketches.move(_world(), _starts.keys(), px, _starts)
	# The room edited moved: its frame goes with it, so nothing jumps on screen.
	if canvas.is_editing() and _origins.has(canvas.room_id):
		canvas.pan += (canvas.frame_origin() - before) * canvas.zoom
		canvas._apply_view()
	canvas.refresh_context()
	invalidate()

func _finish_move() -> void:
	if not _moved:
		return
	var ids := selected_rooms()
	if ids.is_empty():
		status_message.emit("Moved %d outline(s)." % outlines.size())
		return
	var gone := MDSAreaTools.unlink_apart(_world(), ids)
	var made := MDSAreaTools.link_touching(_world(), ids, _layer())
	var text := "Moved %d room(s)%s." % [ids.size(), " and %d outline(s)" % outlines.size() if not outlines.is_empty() else ""]
	if not made.is_empty():
		text += " Connected to %d other area(s)." % made.size()
	if gone > 0:
		text += " %d door(s) to areas they left taken out." % gone
	status_message.emit(text + " Ctrl+Z to undo.")

## Moves the selection [param d] paint cells (the arrows), unless rooms would land on others.
func nudge(d: Vector2i) -> void:
	if rooms.is_empty() and outlines.is_empty():
		return
	_begin_move(_from)
	_drag = Drag.NONE
	if not MDSAreaTools.fits(_own, d, _taken):
		status_message.emit("The rooms selected are against a neighbour there.")
		return
	_world().checkpoint()
	var s := _world().get_paint_cell()
	_delta = Vector2i.ZERO
	_place(Vector2(d) * s)
	_moved = true
	_finish_move()

func _key(key: InputEventKey) -> bool:
	if key.ctrl_pressed and (key.keycode == KEY_Z or key.keycode == KEY_Y):
		_cancel()
		var redo := key.keycode == KEY_Y or key.shift_pressed
		if _world().redo() if redo else _world().undo():
			invalidate()
			status_message.emit("Redone on the map." if redo else "Undone on the map.")
		return true
	if key.ctrl_pressed and key.keycode == KEY_A:
		select_all()
		return true
	match key.keycode:
		KEY_ESCAPE:
			if is_busy():
				_cancel()
			else:
				clear_selection()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if tool == Tool.POLYGON and _draft.size() >= 3:
				_close_polygon()
				return true
		KEY_BACKSPACE:
			if tool == Tool.POLYGON and not _draft.is_empty():
				_draft.remove_at(_draft.size() - 1)
				return true
			delete_selection()
			return true
		KEY_DELETE:
			delete_selection()
			return true
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if tool == Tool.ROOMS:
				nudge({KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT, KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN}[key.keycode])
				return true
	return false

# --- Drawing -----------------------------------------------------------------------------------

## The view's title.
func title() -> String:
	var w := _world()
	var n := 0
	for id in w.get_room_ids():
		if w.get_room_layer(id) == _layer():
			n += 1
	var text := "Full view: %s, %d room(s)" % [w.get_layer_name(_layer()), n]
	var m := MDSRoomSketches.count(w, _layer())
	if m > 0:
		text += ", %d outline(s) to generate" % m
	if canvas.is_editing():
		text += "  |  painting %s%s" % [canvas.room_id, " *unsaved" if canvas.painter.dirty else ""]
	if n == 0 and m == 0:
		text += "  |  draw rooms: Rectangle, Ellipse, Polygon, Curvy"
	return text

## Under the room edited: every room's outline in its area's color with its name, the area names,
## the outlines drawn and the cells they will take, the paint grid.
func draw_under(ci: CanvasItem, font: Font) -> void:
	var w := _world()
	var s := w.get_paint_cell()
	var view := Rect2(canvas.screen_to_local(Vector2.ZERO) + canvas.frame_origin(), canvas.size / canvas.zoom)
	# The paint cells, where rooms are drawn and moved.
	if s.x * canvas.zoom >= 14.0:
		var lines := PackedVector2Array()
		var x := floorf(view.position.x / s.x) * s.x
		while x <= view.end.x:
			lines.append(to_screen(Vector2(x, view.position.y)))
			lines.append(to_screen(Vector2(x, view.end.y)))
			x += s.x
		var y := floorf(view.position.y / s.y) * s.y
		while y <= view.end.y:
			lines.append(to_screen(Vector2(view.position.x, y)))
			lines.append(to_screen(Vector2(view.end.x, y)))
			y += s.y
		if not lines.is_empty():
			ci.draw_multiline(lines, Color(1, 1, 1, 0.05))
	var areas: Dictionary = {}
	# World px to screen px, for whole outlines at once (a world shows hundreds).
	var xf := Transform2D(0.0, Vector2(canvas.zoom, canvas.zoom), 0.0, to_screen(Vector2.ZERO))
	for id in w.get_room_ids():
		if w.get_room_layer(id) != _layer():
			continue
		var b := w.get_room_bounds(id)
		var a := w.get_room_area(id)
		if not a.is_empty():
			areas[a] = b if not areas.has(a) else (areas[a] as Rect2).merge(b)
		if not b.intersects(view):
			continue
		var color := w.get_area_color(a) if not a.is_empty() else COLOR_NO_AREA
		var edited: bool = canvas.is_editing() and id == canvas.room_id
		var no_scene := w.get_scene_path(id).is_empty()
		for poly in w.get_room_outline(id):
			var pts := xf * poly
			if no_scene and pts.size() >= 3:
				ci.draw_colored_polygon(pts, Color(color, 0.2))
			pts.append(pts[0])
			if rooms.has(id):
				ci.draw_polyline(pts, Color(COLOR_SELECT, 0.35), 7.0)
			ci.draw_polyline(pts, COLOR_SELECT if rooms.has(id) else Color(color.lightened(0.2), 1.0 if edited else 0.8), 3.0 if rooms.has(id) or edited else 2.0)
		if not edited:
			for g in w.get_gates(id):
				var gp := to_screen(w.get_gate_world_pos(id, g))
				ci.draw_rect(Rect2(gp - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.9, 0.3, 0.75))
		var sr := Rect2(to_screen(b.position), b.size * canvas.zoom)
		if sr.size.x >= 70.0:
			var label := id + ("  (no scene: click to paint)" if no_scene and sr.size.x >= 220.0 else "")
			# Kept on screen while the room is (its corner may be off it).
			var at := Vector2(clampf(sr.position.x, 0.0, maxf(0.0, sr.end.x - 80.0)), clampf(sr.position.y, 30.0, maxf(30.0, sr.end.y - 30.0))) + Vector2(8, 20)
			var room_w := sr.end.x - at.x - 4.0
			ci.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, room_w, 14, 4, Color.BLACK)
			ci.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, room_w, 14, Color(1, 1, 1, 0.9))
	# Area names over their rooms, when the rooms are small on screen.
	for a: String in areas:
		var r: Rect2 = areas[a]
		var sr := Rect2(to_screen(r.position), r.size * canvas.zoom)
		if not canvas.get_rect().intersects(sr):
			continue
		var fs := int(clampf(sr.size.x / 14.0, 13.0, 30.0))
		var width := font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := sr.get_center() + Vector2(-width / 2.0, fs * 0.35)
		# Fainter over rooms big on screen (being painted), clear when the view is zoomed out.
		var alpha := 0.45 if sr.size.x > canvas.size.x * 0.6 else 0.95
		ci.draw_string_outline(font, at, a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.8 * alpha))
		ci.draw_string(font, at, a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(w.get_area_color(a).lightened(0.45), alpha))
	_draw_outlines(ci, font)

## The outlines drawn: filled lightly, the cells they will take, what they make.
func _draw_outlines(ci: CanvasItem, font: Font) -> void:
	var w := _world()
	var key := hash([MDSRoomSketches.get_all(w), w.get_room_ids().size(), _layer()])
	if key != _preview_key:
		_preview_key = key
		_preview = sketches.preview(w, _layer())
	var s := w.get_paint_cell()
	for o: Dictionary in _preview:
		var picked := false
		for i in o.sketches:
			picked = picked or outlines.has(int(i))
		var color := COLOR_SELECT if picked else COLOR_SKETCH
		for c: Vector2i in o.cells:
			ci.draw_rect(Rect2(to_screen(Vector2(c) * s), s * canvas.zoom).grow(-1.0), Color(color, 0.07))
		var pts := PackedVector2Array()
		for q in o.polygon:
			pts.append(to_screen(q))
		if pts.size() < 3:
			continue
		ci.draw_colored_polygon(pts, Color(color, 0.12))
		pts.append(pts[0])
		ci.draw_polyline(pts, color, 3.0 if picked else 2.0)
		var b := MDSGeometry.bounds(o.polygon)
		var sr := Rect2(to_screen(b.position), b.size * canvas.zoom)
		if sr.size.x >= 80.0:
			var a := str(o.area)
			var label := "%s, %s" % ["1 room" if o.kind == MDSRoomSketches.ROOM else "rooms", "new area" if a == MDSRoomSketches.NEW_AREA else ("no area" if a.is_empty() else a)]
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var at := sr.get_center() + Vector2(-width / 2.0, 5)
			ci.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
			ci.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

## Over everything: the shape being drawn, the selection box.
func draw_over(ci: CanvasItem, _font: Font) -> void:
	var color := COLOR_SKETCH
	match _drag:
		Drag.BOX:
			var poly := MDSRoomSketches.ellipse(_from, _to) if tool == Tool.ELLIPSE else MDSRoomSketches.rectangle(_from, _to)
			var pts := PackedVector2Array()
			for q in poly:
				pts.append(to_screen(q))
			if tool == Tool.GENERATE:
				color = Color(0.7, 1.0, 0.5)
			if MDSGeometry.bounds(pts).has_area():
				ci.draw_colored_polygon(pts, Color(color, 0.15))
			pts.append(pts[0])
			ci.draw_polyline(pts, color, 2.0)
			var size := (_to - _from).abs()
			var label := "%d x %d px" % [size.x, size.y]
			if tool == Tool.GENERATE:
				var s := _world().get_paint_cell()
				label = "%d x %d paint cells" % [roundi(size.x / s.x), roundi(size.y / s.y)]
			ci.draw_string_outline(canvas.get_theme_default_font(), to_screen(_to) + Vector2(10, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
			ci.draw_string(canvas.get_theme_default_font(), to_screen(_to) + Vector2(10, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
		Drag.SELECT:
			var r := Rect2(to_screen(_from), to_screen(_to) - to_screen(_from)).abs()
			ci.draw_rect(r, Color(COLOR_SELECT, 0.08))
			ci.draw_rect(r, COLOR_SELECT, false, 1.0)
	if not _draft.is_empty():
		var line := PackedVector2Array()
		for q in _draft:
			line.append(to_screen(q))
		if tool == Tool.POLYGON and _mouse != Vector2.INF:
			line.append(to_screen(_snap_grid(_mouse)))
		if line.size() >= 2:
			ci.draw_polyline(line, color, 2.0)
		if tool == Tool.POLYGON:
			for k in _draft.size():
				ci.draw_circle(to_screen(_draft[k]), 6.0 if k == 0 else 4.0, color)
