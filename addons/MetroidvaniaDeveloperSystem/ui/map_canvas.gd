@tool
class_name IDPMapCanvas
extends Control
## Interactive schematic map of one MetSys layer.
##
## Rooms are drawn by their exact cell footprint (irregular rooms included) with outlines
## only on the room perimeter, passages as gaps, and ability gates as colored locks.
## Optionally overlays baked terrain silhouettes, live scene previews, markers, pins,
## issues and a highlighted route.
##
## Mouse: wheel = zoom at cursor, middle/right drag = pan, left = select,
## double-click = open scene, Shift+left = route from the selected room, right-click = menu.

signal room_selected(room_id: String)
signal room_activated(room_id: String)
signal route_requested(from_id: String, to_id: String)
signal context_requested(room_id: String, cell_pos: Vector2, local_pos: Vector2)
signal hovered_changed(room_id: String, cell: Vector3i)
signal view_changed

enum ColorMode { METSYS, ROOM_TYPE, AREA, PROGRESSION, SAVE_DISTANCE, STATUS }
const COLOR_MODE_NAMES: PackedStringArray = ["MetSys colors", "Room type", "Area", "Progression", "Save distance", "Build status"]

const TYPE_COLORS := {
	"": Color(0.36, 0.42, 0.52),
	"normal": Color(0.36, 0.42, 0.52),
	"corridor": Color(0.3, 0.33, 0.38),
	"hub": Color(0.2, 0.55, 0.6),
	"save": Color(0.2, 0.42, 0.85),
	"boss": Color(0.8, 0.18, 0.2),
	"mini_boss": Color(0.85, 0.42, 0.25),
	"shop": Color(0.85, 0.65, 0.15),
	"npc": Color(0.55, 0.7, 0.3),
	"fast_travel": Color(0.2, 0.7, 0.4),
	"secret": Color(0.55, 0.3, 0.75),
	"treasure": Color(0.9, 0.8, 0.3),
	"challenge": Color(0.8, 0.35, 0.55),
	"transition": Color(0.45, 0.45, 0.45),
}
const STATUS_COLORS := {
	"": Color(0.35, 0.35, 0.38),
	"idea": Color(0.55, 0.55, 0.6),
	"blockout": Color(0.85, 0.5, 0.2),
	"art_pass": Color(0.25, 0.5, 0.85),
	"polish": Color(0.6, 0.35, 0.8),
	"done": Color(0.25, 0.7, 0.35),
}
const PIN_COLORS := {
	"note": Color(0.95, 0.95, 0.95),
	"todo": Color(1.0, 0.75, 0.2),
	"secret": Color(0.7, 0.45, 1.0),
	"bug": Color(1.0, 0.3, 0.3),
	"idea": Color(0.4, 0.9, 1.0),
}
const COLOR_LOCKED := Color(0.45, 0.12, 0.12)
const COLOR_DISCONNECTED := Color(0.22, 0.22, 0.24)
const COLOR_UNASSIGNED := Color(0.25, 0.25, 0.27)
const COLOR_WALL := Color(0.04, 0.04, 0.07)
const COLOR_SELECT := Color(1.0, 0.92, 0.35)
const COLOR_ROUTE := Color(0.3, 0.95, 1.0)
const COLOR_BACKGROUND := Color(0.1, 0.11, 0.13)
const COLOR_GRID := Color(1, 1, 1, 0.05)

const SAVEPOINT_TEXTURE := preload("res://addons/MetroidvaniaDeveloperSystem/assets/savepoint_idp.png")
const COLLECTIBLE_TEXTURE := preload("res://addons/MetroidvaniaDeveloperSystem/assets/collectible_idp.png")
const TELEPORTER_TEXTURE := preload("res://addons/MetroidvaniaDeveloperSystem/assets/teleporter_idp.png")
const LABELS_TEXTURE := preload("res://addons/MetroidvaniaDeveloperSystem/assets/labels_idp.png")

const BASE_CELL_WIDTH := 96.0
const MIN_ZOOM := 0.08
const MAX_ZOOM := 8.0

var model: IDPMapModel
var annotations: IDPAnnotations
var analysis: IDPAnalysis
var scene_db: Dictionary = {}
var in_game_cell_size := Vector2(1152, 648)
var metsys_default_color := Color(0.4, 0.45, 0.55)
var layer := 0
var color_mode: int = ColorMode.ROOM_TYPE

## View toggles.
var show := {
	"labels": true, "terrain": true, "previews": false, "doors": true, "grid": true,
	"pins": true, "issues": true, "legend": true, "markers": true, "elements": true,
}
## Marker/custom element categories enabled from the panel filters ("Save Points"...).
var marker_filters: Dictionary = {}
## Vector3i -> highest severity (IDPValidator.Severity).
var issue_cells: Dictionary = {}

var selected_room := ""
var hovered_room := ""
var hovered_cell := Vector3i.MAX
var route: Array[String] = []
## When non-empty, rooms not in this set are dimmed.
var highlight_rooms: Dictionary = {}

var zoom := 1.0
var pan := Vector2(40, 40) ## Screen position of cell (0, 0).

var _silhouettes: Dictionary = {} ## scene path -> ImageTexture
var _preview_root: Node2D
var _preview_layer := -9999
var _overlay: Control
var _drag_button := 0
var _drag_start := Vector2.ZERO
var _drag_moved := false
var _pan_start := Vector2.ZERO

func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	_preview_root = Node2D.new()
	_preview_root.name = "Previews"
	add_child(_preview_root, false, Node.INTERNAL_MODE_FRONT)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay, false, Node.INTERNAL_MODE_BACK)

# --- Public API ------------------------------------------------------------------

func set_data(p_model: IDPMapModel, p_annotations: IDPAnnotations, p_analysis: IDPAnalysis, p_scene_db: Dictionary) -> void:
	model = p_model
	annotations = p_annotations
	analysis = p_analysis
	if not is_same(p_scene_db, scene_db):
		_silhouettes.clear()
	scene_db = p_scene_db
	_preview_layer = -9999
	_update_previews()
	redraw()

func set_layer(p_layer: int) -> void:
	if layer == p_layer:
		return
	layer = p_layer
	hovered_room = ""
	_update_previews()
	redraw()

func set_show(key: String, value: bool) -> void:
	show[key] = value
	if key == "previews":
		_preview_layer = -9999
		_update_previews()
	redraw()

func redraw() -> void:
	queue_redraw()
	_overlay.queue_redraw()

func get_cell_px() -> Vector2:
	return Vector2(BASE_CELL_WIDTH, BASE_CELL_WIDTH * in_game_cell_size.y / in_game_cell_size.x) * zoom

func cell_to_screen(cell: Vector2) -> Vector2:
	return pan + cell * get_cell_px()

func screen_to_cell(pos: Vector2) -> Vector2:
	return (pos - pan) / get_cell_px()

func get_room_at_screen(pos: Vector2) -> IDPMapModel.Room:
	if not model:
		return null
	var c := screen_to_cell(pos).floor()
	return model.get_room_at(Vector3i(int(c.x), int(c.y), layer))

func set_zoom(value: float, anchor := Vector2(-1, -1)) -> void:
	if anchor.x < 0:
		anchor = size / 2.0
	var cell_at_anchor := screen_to_cell(anchor)
	zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	pan = anchor - cell_at_anchor * get_cell_px()
	_after_view_change()

func fit_to_layer() -> void:
	if not model:
		return
	var bounds := model.get_layer_bounds(layer)
	if bounds.size == Vector2i.ZERO or size.x <= 0 or size.y <= 0:
		return
	var base := get_cell_px() / zoom
	var margin := 48.0
	var z := minf((size.x - margin * 2) / (bounds.size.x * base.x), (size.y - margin * 2) / (bounds.size.y * base.y))
	zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)
	var center := Vector2(bounds.position) + Vector2(bounds.size) / 2.0
	pan = size / 2.0 - center * get_cell_px()
	_after_view_change()

func center_on_room(id: String) -> void:
	var room := model.get_room(id) if model else null
	if not room:
		return
	var c := Vector2(room.get_rect().position) + Vector2(room.get_rect().size) / 2.0
	pan = size / 2.0 - c * get_cell_px()
	_after_view_change()

func _after_view_change() -> void:
	_update_preview_transform()
	redraw()
	view_changed.emit()

## Bounding rect of the current layer in screen space (used for PNG export).
func get_layer_screen_rect() -> Rect2:
	if not model:
		return Rect2()
	var b := model.get_layer_bounds(layer)
	return Rect2(cell_to_screen(Vector2(b.position)), Vector2(b.size) * get_cell_px())

# --- Colors -------------------------------------------------------------------------

func get_room_color(room: IDPMapModel.Room) -> Color:
	if room.scene_uid.is_empty():
		return COLOR_UNASSIGNED
	var info: Dictionary = analysis.get_info(room.id) if analysis else {}
	match color_mode:
		ColorMode.METSYS:
			var cell := model.get_cell(room.cells[0])
			return cell.color if cell.color.a > 0 else metsys_default_color
		ColorMode.ROOM_TYPE:
			return TYPE_COLORS.get(info.get("type", ""), TYPE_COLORS[""])
		ColorMode.AREA:
			return area_color(info.get("area", ""))
		ColorMode.PROGRESSION:
			if analysis and analysis.sphere_of.has(room.id):
				return sphere_color(analysis.sphere_of[room.id], analysis.spheres.size())
			if analysis and room.id in analysis.locked:
				return COLOR_LOCKED
			return COLOR_DISCONNECTED
		ColorMode.SAVE_DISTANCE:
			var d: int = analysis.save_distance.get(room.id, -1) if analysis else -1
			return save_distance_color(d)
		ColorMode.STATUS:
			return STATUS_COLORS.get(info.get("status", ""), STATUS_COLORS[""])
	return TYPE_COLORS[""]

static func area_color(area: String) -> Color:
	if area.is_empty():
		return Color(0.35, 0.37, 0.42)
	var h := float(hash(area) % 360) / 360.0
	return Color.from_hsv(h, 0.45, 0.62)

static func sphere_color(sphere: int, total: int) -> Color:
	var t := float(sphere) / maxf(1.0, float(total - 1))
	return Color.from_hsv(lerpf(0.33, 0.78, t), 0.55, 0.68)

func save_distance_color(d: int) -> Color:
	if d < 0:
		return COLOR_DISCONNECTED
	if d == 0:
		return TYPE_COLORS.save
	var warn: int = int(annotations.get_setting("save_distance_warn", 4)) if annotations else 4
	var t := clampf(float(d - 1) / maxf(1.0, float(warn)), 0.0, 1.0)
	return Color(0.25, 0.7, 0.35).lerp(Color(0.85, 0.2, 0.2), t)

func get_legend() -> Array:
	var items: Array = []
	match color_mode:
		ColorMode.ROOM_TYPE:
			var seen := {}
			for room: IDPMapModel.Room in model.get_rooms_on_layer(layer):
				if analysis and not room.scene_uid.is_empty():
					seen[analysis.get_info(room.id).get("type", "")] = true
			for t in TYPE_COLORS:
				if seen.has(t) and not (t == "" and seen.has("normal")):
					items.append([t.capitalize() if not t.is_empty() else "Normal", TYPE_COLORS[t]])
		ColorMode.PROGRESSION:
			if analysis:
				for s in analysis.spheres:
					var label := "Start" if s.index == 0 else "After %s" % ", ".join(analysis.spheres[s.index - 1].gained)
					items.append(["Sphere %d: %s" % [s.index, label], sphere_color(s.index, analysis.spheres.size())])
			items.append(["Locked", COLOR_LOCKED])
			items.append(["Not connected", COLOR_DISCONNECTED])
		ColorMode.SAVE_DISTANCE:
			var warn: int = int(annotations.get_setting("save_distance_warn", 4)) if annotations else 4
			items.append(["Save room", save_distance_color(0)])
			items.append(["1 room away", save_distance_color(1)])
			items.append(["%d+ rooms" % (warn + 1), save_distance_color(warn + 1)])
			items.append(["No save reachable", COLOR_DISCONNECTED])
		ColorMode.STATUS:
			for s in STATUS_COLORS:
				items.append([s.capitalize() if not s.is_empty() else "No status", STATUS_COLORS[s]])
		ColorMode.AREA:
			var seen := {}
			for room: IDPMapModel.Room in model.get_rooms_on_layer(layer):
				if analysis:
					seen[analysis.get_info(room.id).get("area", "")] = true
			for a in seen:
				items.append([a if not a.is_empty() else "No area", area_color(a)])
	return items

# --- Drawing: base layer (fills + terrain) ---------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if not model:
		return
	var cell_px := get_cell_px()
	if show.grid and cell_px.x >= 12:
		_draw_grid(cell_px)
	var dim := not highlight_rooms.is_empty()
	for room: IDPMapModel.Room in model.get_rooms_on_layer(layer):
		var color := get_room_color(room)
		if dim and not highlight_rooms.has(room.id):
			color = color.darkened(0.6)
		for c in room.cells:
			draw_rect(Rect2(cell_to_screen(Vector2(c.x, c.y)), cell_px), color)
		if show.terrain and not show.previews:
			var tex := _get_silhouette(room.scene_path)
			if tex:
				var meta: Dictionary = scene_db[room.scene_path]
				var r: Rect2 = meta.silhouette_rect
				var origin := Vector2(room.min_cell) + r.position / in_game_cell_size
				draw_texture_rect(tex, Rect2(cell_to_screen(origin), r.size / in_game_cell_size * cell_px), false, color.darkened(0.55))

func _draw_grid(cell_px: Vector2) -> void:
	var c0 := screen_to_cell(Vector2.ZERO).floor()
	var c1 := screen_to_cell(size).ceil()
	for x in range(int(c0.x), int(c1.x) + 1):
		var sx := cell_to_screen(Vector2(x, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), COLOR_GRID)
	for y in range(int(c0.y), int(c1.y) + 1):
		var sy := cell_to_screen(Vector2(0, y)).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), COLOR_GRID)

func _get_silhouette(scene_path: String) -> Texture2D:
	if scene_path.is_empty():
		return null
	if _silhouettes.has(scene_path):
		return _silhouettes[scene_path]
	var img = scene_db.get(scene_path, {}).get("silhouette")
	var tex: Texture2D = ImageTexture.create_from_image(img) if img is Image else null
	_silhouettes[scene_path] = tex
	return tex

# --- Drawing: overlay (walls, doors, labels, markers...) -------------------------------

func _draw_overlay() -> void:
	if not model:
		_draw_centered_message("No map loaded. Pick a MapData.txt in the tool panel.")
		return
	var ci := _overlay
	var cell_px := get_cell_px()
	var wall_w := clampf(cell_px.x * 0.035, 1.5, 4.0)
	var rooms := model.get_rooms_on_layer(layer)
	if rooms.is_empty():
		_draw_centered_message("Layer %d has no cells." % layer)

	for room in rooms:
		if room.id == hovered_room:
			for c in room.cells:
				ci.draw_rect(Rect2(cell_to_screen(Vector2(c.x, c.y)), cell_px), Color(1, 1, 1, 0.12))
		_draw_room_outline(ci, room, cell_px, wall_w, COLOR_WALL, true)

	if not selected_room.is_empty():
		var sel := model.get_room(selected_room)
		if sel and sel.layer == layer:
			_draw_room_outline(ci, sel, cell_px, wall_w + 2.0, COLOR_SELECT, false)

	_draw_route(ci, cell_px)
	if show.elements:
		_draw_custom_elements(ci, cell_px)
	if show.markers:
		for room in rooms:
			_draw_room_markers(ci, room, cell_px)
	if show.labels and cell_px.x >= 34:
		for room in rooms:
			_draw_room_label(ci, room, cell_px)
	if show.issues:
		_draw_issue_badges(ci, cell_px)
	if show.pins:
		_draw_pins(ci, cell_px)
	_draw_layer_title(ci)
	if show.legend:
		_draw_legend(ci)

func _draw_centered_message(text: String) -> void:
	var font := get_theme_default_font()
	var fs := 16
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_overlay.draw_string(font, Vector2((size.x - w) / 2.0, size.y / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.6))

## Perimeter-only outline. Passages leave a gap; the door marker is drawn once per door.
func _draw_room_outline(ci: CanvasItem, room: IDPMapModel.Room, cell_px: Vector2, width: float, color: Color, with_doors: bool) -> void:
	for c in room.cells:
		var tl := cell_to_screen(Vector2(c.x, c.y))
		# Corner i starts edge i: R = TR->BR, D = BR->BL, L = BL->TL, U = TL->TR.
		var corners := [tl + Vector2(cell_px.x, 0), tl + cell_px, tl + Vector2(0, cell_px.y), tl]
		for d in 4:
			var n := Vector2i(c.x, c.y) + IDPMapModel.FWD[d]
			var p0: Vector2 = corners[d]
			var p1: Vector2 = corners[(d + 1) % 4]
			if room.has_cell(n):
				# Interior edge of a multi-cell room: faint cell divider.
				if with_doors and cell_px.x >= 30:
					ci.draw_line(p0, p1, Color(0, 0, 0, 0.12), 1.0)
				continue
			var door: IDPMapModel.Door = model.doors.get(IDPMapModel.door_key(c, d)) if show.doors else null
			if door:
				ci.draw_line(p0, p0.lerp(p1, 0.3), color, width)
				ci.draw_line(p0.lerp(p1, 0.7), p1, color, width)
				if with_doors and (door.a_room == room or door.b_room == null):
					_draw_door_marker(ci, door, p0, p1, d, width)
			else:
				ci.draw_line(p0, p1, color, width)

func _draw_door_marker(ci: CanvasItem, door: IDPMapModel.Door, p0: Vector2, p1: Vector2, dir: int, width: float) -> void:
	var a := p0.lerp(p1, 0.3)
	var b := p0.lerp(p1, 0.7)
	var mid := (a + b) / 2.0
	var reqs := analysis.get_door_requires(door.key) if analysis else PackedStringArray()
	var one_way := annotations.get_door_one_way_from(door.key) if annotations else ""
	var r := clampf(get_cell_px().y * 0.13, 5.0, 12.0)
	if door.leads_nowhere():
		ci.draw_line(a, b, Color(1, 0.25, 0.25), width)
		_draw_text_badge(ci, mid, "?", Color(1, 0.25, 0.25), r)
	elif not reqs.is_empty():
		var c := ability_color(reqs[0])
		ci.draw_line(a, b, c, width + 1.0)
		_draw_lock(ci, mid, r, c)
	elif door.get_border_type() >= 2:
		ci.draw_line(a, b, Color(1, 0.6, 0.2), width)
	if not one_way.is_empty() or (door.is_one_sided() and not door.leads_nowhere()):
		# Arrow pointing away from the side that can pass.
		var from_a := one_way == door.a_room.id if not one_way.is_empty() else door.a_border > 0
		var fwd := Vector2(IDPMapModel.FWD[door.a_dir]) * (1.0 if from_a else -1.0)
		var col := Color(1, 0.85, 0.2) if one_way.is_empty() else Color(0.9, 0.9, 0.9)
		var tip := mid + fwd * r * 1.6
		var side := Vector2(-fwd.y, fwd.x) * r * 0.8
		ci.draw_colored_polygon(PackedVector2Array([tip, mid + side, mid - side]), col)

static func ability_color(ability: String) -> Color:
	return Color.from_hsv(float(hash(ability) % 360) / 360.0, 0.7, 1.0)

func _draw_lock(ci: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	ci.draw_arc(center - Vector2(0, r * 0.35), r * 0.5, PI, TAU, 10, color, maxf(1.5, r * 0.25))
	ci.draw_rect(Rect2(center - Vector2(r * 0.75, r * 0.3), Vector2(r * 1.5, r * 1.1)), color)
	ci.draw_rect(Rect2(center - Vector2(r * 0.75, r * 0.3), Vector2(r * 1.5, r * 1.1)), Color.BLACK, false, 1.0)

func _draw_text_badge(ci: CanvasItem, center: Vector2, text: String, color: Color, r: float) -> void:
	ci.draw_circle(center, r, color)
	var font := get_theme_default_font()
	var fs := int(r * 1.5)
	var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(font, center + Vector2(-s.x / 2.0, s.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)

func _draw_room_label(ci: CanvasItem, room: IDPMapModel.Room, cell_px: Vector2) -> void:
	if room.scene_uid.is_empty():
		return
	var info: Dictionary = analysis.get_info(room.id) if analysis else {}
	var font := get_theme_default_font()
	var fs := int(clampf(cell_px.y * 0.2, 9, 18))
	var lc := room.get_label_cell()
	var center := cell_to_screen(Vector2(lc) + Vector2(0.5, 0.5))
	# Labels of multi-cell rooms may span the room's width.
	var max_w := cell_px.x * maxf(1.0, room.get_rect().size.x) - 6.0
	var lines: Array = [[info.get("name", room.get_display_name()), Color.WHITE]]
	if info.get("is_boss", false):
		var boss_names: PackedStringArray = info.get("boss_names", PackedStringArray())
		lines.append([", ".join(boss_names) if not boss_names.is_empty() else "Boss", Color(1, 0.55, 0.5)])
	var total_h := fs * 1.2 * lines.size()
	var y := center.y - total_h / 2.0 + fs
	for line in lines:
		var text: String = line[0]
		var w := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, max_w)
		var pos := Vector2(center.x - w / 2.0, y)
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, 4, Color(0, 0, 0, 0.85))
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, line[1])
		y += fs * 1.2
	if info.get("is_boss", false):
		_draw_crown(ci, Vector2(center.x, center.y - total_h / 2.0 - fs * 0.6), fs * 0.6, Color(1, 0.35, 0.3))

func _draw_crown(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-r, r * 0.6), c + Vector2(-r, -r * 0.4), c + Vector2(-r * 0.5, r * 0.1),
		c + Vector2(0, -r * 0.7), c + Vector2(r * 0.5, r * 0.1), c + Vector2(r, -r * 0.4), c + Vector2(r, r * 0.6),
	])
	ci.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color.BLACK, 1.0)

func _marker_enabled(category: String) -> bool:
	return marker_filters.get(category, false)

func _draw_room_markers(ci: CanvasItem, room: IDPMapModel.Room, cell_px: Vector2) -> void:
	var meta: Dictionary = scene_db.get(room.scene_path, {})
	if meta.is_empty():
		return
	var icon := clampf(cell_px.y * 0.28, 10.0, 30.0)
	var groups := [
		["Save Points", "save_points", SAVEPOINT_TEXTURE],
		["Collectibles", "collectibles", COLLECTIBLE_TEXTURE],
		["Teleporters", "teleporters", TELEPORTER_TEXTURE],
		["Shops", "shops", null],
		["Enemies", "enemies", null],
	]
	for g in groups:
		if not _marker_enabled(g[0]):
			continue
		for entry in meta.get(g[1], []):
			var p := _local_to_screen(room, entry.position)
			if g[2]:
				ci.draw_texture_rect(g[2], Rect2(p - Vector2(icon / 2.0, icon), Vector2(icon, icon)), false)
			elif g[1] == "shops":
				_draw_text_badge(ci, p - Vector2(0, icon * 0.5), "$", Color(1, 0.8, 0.2), icon * 0.45)
			else:
				ci.draw_circle(p, maxf(2.0, icon * 0.15), Color(1, 0.3, 0.3))
	if _marker_enabled("Bosses"):
		for entry in meta.get("bosses", []):
			_draw_crown(ci, _local_to_screen(room, entry.position), icon * 0.4, Color(1, 0.35, 0.3))
	for gate in meta.get("gates", []):
		if show.doors and cell_px.x >= 40:
			var p := _local_to_screen(room, gate.position)
			ci.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), ability_color(gate.requires[0]) if not gate.requires.is_empty() else Color.WHITE)

func _local_to_screen(room: IDPMapModel.Room, local_px: Vector2) -> Vector2:
	return cell_to_screen(Vector2(room.min_cell) + local_px / in_game_cell_size)

func _draw_custom_elements(ci: CanvasItem, cell_px: Vector2) -> void:
	var font := get_theme_default_font()
	for e in model.custom_elements:
		if e.coords.z != layer or not _marker_enabled(e.name.capitalize()):
			continue
		var r := Rect2(cell_to_screen(Vector2(e.coords.x, e.coords.y)), Vector2(e.size) * cell_px)
		ci.draw_rect(r, Color(0.9, 0.9, 1.0, 0.8), false, 1.5)
		var icon := clampf(cell_px.y * 0.25, 10, 26)
		ci.draw_texture_rect(LABELS_TEXTURE, Rect2(r.position + Vector2(3, 3), Vector2(icon, icon)), false)
		var text := e.data if not e.data.is_empty() else e.name.capitalize()
		var fs := int(clampf(cell_px.y * 0.18, 9, 16))
		ci.draw_string_outline(font, r.position + Vector2(icon + 6, 3 + fs), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - icon - 8, fs, 3, Color.BLACK)
		ci.draw_string(font, r.position + Vector2(icon + 6, 3 + fs), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - icon - 8, fs, Color(0.9, 0.9, 1.0))

func _draw_issue_badges(ci: CanvasItem, cell_px: Vector2) -> void:
	var r := clampf(cell_px.y * 0.1, 5.0, 10.0)
	for c in issue_cells:
		if c.z != layer:
			continue
		var sev: int = issue_cells[c]
		var color: Color = [Color(0.5, 0.75, 1.0), Color(1.0, 0.75, 0.2), Color(1.0, 0.3, 0.3)][sev]
		_draw_text_badge(ci, cell_to_screen(Vector2(c.x + 1, c.y)) + Vector2(-r - 3, r + 3), "!", color, r)

func _draw_pins(ci: CanvasItem, cell_px: Vector2) -> void:
	if not annotations:
		return
	var font := get_theme_default_font()
	var fs := int(clampf(cell_px.y * 0.16, 9, 14))
	for pin in annotations.get_pins():
		if int(pin.layer) != layer:
			continue
		var p := cell_to_screen(Vector2(pin.x, pin.y))
		var color: Color = PIN_COLORS.get(pin.get("kind", "note"), Color.WHITE)
		ci.draw_line(p, p - Vector2(0, 14), Color.BLACK, 2.0)
		ci.draw_circle(p - Vector2(0, 16), 5.0, color)
		ci.draw_circle(p - Vector2(0, 16), 5.0, Color.BLACK, false, 1.0)
		if cell_px.x >= 50:
			ci.draw_string_outline(font, p + Vector2(8, -12), pin.text, HORIZONTAL_ALIGNMENT_LEFT, 180, fs, 3, Color.BLACK)
			ci.draw_string(font, p + Vector2(8, -12), pin.text, HORIZONTAL_ALIGNMENT_LEFT, 180, fs, color)

func _draw_route(ci: CanvasItem, cell_px: Vector2) -> void:
	if route.size() < 2:
		return
	var pts := PackedVector2Array()
	for i in route.size():
		var room := model.get_room(route[i])
		if not room:
			continue
		if room.layer == layer:
			pts.append(cell_to_screen(Vector2(room.get_label_cell()) + Vector2(0.5, 0.5)))
		if i + 1 < route.size():
			var door := _door_between(route[i], route[i + 1])
			if door and door.a_room.layer == layer:
				var fwd := Vector2(IDPMapModel.FWD[door.a_dir])
				pts.append(cell_to_screen(Vector2(door.a_cell.x, door.a_cell.y) + Vector2(0.5, 0.5) + fwd * 0.5))
	if pts.size() >= 2:
		ci.draw_polyline(pts, Color(0, 0, 0, 0.6), 6.0, true)
		ci.draw_polyline(pts, COLOR_ROUTE, 3.0, true)
		ci.draw_circle(pts[0], 6.0, COLOR_ROUTE)
		ci.draw_circle(pts[pts.size() - 1], 6.0, Color(1, 0.4, 0.8))

func _door_between(a_id: String, b_id: String) -> IDPMapModel.Door:
	var a := model.get_room(a_id)
	if not a:
		return null
	for door in a.doors:
		if door.other(a) and door.other(a).id == b_id:
			return door
	return null

func _draw_layer_title(ci: CanvasItem) -> void:
	var font := get_theme_default_font()
	var text := "%s  (layer %d)" % [model.get_layer_name(layer), layer]
	ci.draw_rect(Rect2(Vector2(6, 6), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15) + Vector2(12, 8)), Color(0, 0, 0, 0.55))
	ci.draw_string(font, Vector2(12, 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

func _draw_legend(ci: CanvasItem) -> void:
	var items := get_legend()
	if items.is_empty():
		return
	var font := get_theme_default_font()
	var fs := 12
	var line_h := 17.0
	var w := 0.0
	for item in items:
		w = maxf(w, font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var box := Rect2(Vector2(6, size.y - 12 - line_h * items.size()), Vector2(w + 34, line_h * items.size() + 6))
	ci.draw_rect(box, Color(0, 0, 0, 0.6))
	for i in items.size():
		var y := box.position.y + 4 + i * line_h
		ci.draw_rect(Rect2(Vector2(box.position.x + 6, y + 2), Vector2(14, 12)), items[i][1])
		ci.draw_string(font, Vector2(box.position.x + 26, y + 12), items[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

# --- Live scene previews -------------------------------------------------------------

func _update_previews() -> void:
	if not show.previews or not model:
		for child in _preview_root.get_children():
			child.queue_free()
		_preview_layer = -9999
		return
	if _preview_layer == layer:
		return
	_preview_layer = layer
	for child in _preview_root.get_children():
		child.queue_free()
	for room: IDPMapModel.Room in model.get_rooms_on_layer(layer):
		if room.scene_path.is_empty() or not ResourceLoader.exists(room.scene_path):
			continue
		var packed := load(room.scene_path) as PackedScene
		if not packed:
			continue
		var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		instance.set_meta(&"fake_map", true)
		instance.process_mode = Node.PROCESS_MODE_DISABLED
		if instance is Node2D:
			instance.position = Vector2(room.min_cell) * in_game_cell_size
		_preview_root.add_child(instance)
	_update_preview_transform()

func _update_preview_transform() -> void:
	_preview_root.position = pan
	_preview_root.scale = get_cell_px() / in_game_cell_size

# --- Input ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			set_zoom(zoom * pow(factor, maxf(mb.factor, 1.0)), mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_drag_button = mb.button_index
				_drag_start = mb.position
				_pan_start = pan
				_drag_moved = false
			elif mb.button_index == _drag_button:
				_drag_button = 0
				if mb.button_index == MOUSE_BUTTON_RIGHT and not _drag_moved:
					var room := get_room_at_screen(mb.position)
					context_requested.emit(room.id if room else "", screen_to_cell(mb.position), mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			grab_focus()
			var room := get_room_at_screen(mb.position)
			var id := room.id if room else ""
			if mb.double_click and room:
				room_activated.emit(id)
			elif mb.shift_pressed and room and not selected_room.is_empty():
				route_requested.emit(selected_room, id)
			else:
				selected_room = id
				redraw()
				room_selected.emit(id)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_button != 0:
			if mm.position.distance_to(_drag_start) > 4.0:
				_drag_moved = true
			pan = _pan_start + (mm.position - _drag_start)
			_after_view_change()
			accept_event()
		else:
			_update_hover(mm.position)
	elif event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		match key.keycode:
			KEY_F:
				fit_to_layer()
				accept_event()
			KEY_EQUAL, KEY_KP_ADD:
				set_zoom(zoom * 1.25)
				accept_event()
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_zoom(zoom / 1.25)
				accept_event()

func _update_hover(pos: Vector2) -> void:
	if not model:
		return
	var c := screen_to_cell(pos).floor()
	var cell := Vector3i(int(c.x), int(c.y), layer)
	var room := model.get_room_at(cell)
	var id := room.id if room else ""
	if cell != hovered_cell or id != hovered_room:
		var room_changed := id != hovered_room
		hovered_cell = cell
		hovered_room = id
		if room_changed:
			_overlay.queue_redraw()
		hovered_changed.emit(id, cell)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			if not hovered_room.is_empty():
				hovered_room = ""
				_overlay.queue_redraw()
			hovered_cell = Vector3i.MAX
			hovered_changed.emit("", Vector3i.MAX)
		NOTIFICATION_RESIZED:
			redraw()

func _get_tooltip(at_position: Vector2) -> String:
	if not model:
		return ""
	var room := get_room_at_screen(at_position)
	if not room:
		return ""
	if room.scene_uid.is_empty():
		return "Unassigned cell(s)\nAssign a scene in the MetSys editor."
	var info: Dictionary = analysis.get_info(room.id) if analysis else {}
	var lines: PackedStringArray = [info.get("name", room.get_display_name())]
	var type: String = info.get("type", "")
	var tags: PackedStringArray = []
	if not type.is_empty():
		tags.append(type.capitalize())
	if not str(info.get("area", "")).is_empty():
		tags.append(info.area)
	if not str(info.get("status", "")).is_empty():
		tags.append(str(info.status).capitalize())
	if not tags.is_empty():
		lines.append(" | ".join(tags))
	if info.get("is_boss", false) and not info.boss_names.is_empty():
		lines.append("Boss: " + ", ".join(info.boss_names))
	if not info.get("grants", PackedStringArray()).is_empty():
		lines.append("Grants: " + ", ".join(info.grants))
	var meta: Dictionary = scene_db.get(room.scene_path, {})
	if not meta.is_empty():
		lines.append("%d collectibles, %d enemies, %d save points" % [meta.collectibles.size(), meta.enemies.size(), meta.save_points.size()])
	if analysis:
		if analysis.sphere_of.has(room.id):
			lines.append("Progression sphere %d" % analysis.sphere_of[room.id])
		elif room.id in analysis.locked:
			lines.append("Locked (requirements never met)")
		var d: int = analysis.save_distance.get(room.id, -1)
		lines.append("Nearest save: %s" % ("here" if d == 0 else ("%d rooms" % d if d > 0 else "none reachable")))
	var r := room.get_rect()
	lines.append("%d cell(s), %dx%d%s at (%d,%d)" % [room.cells.size(), r.size.x, r.size.y, " irregular" if room.is_irregular() else "", room.min_cell.x, room.min_cell.y])
	var notes: String = annotations.get_room_value(room.id, "notes", "") if annotations else ""
	if not notes.is_empty():
		lines.append("Notes: " + notes.get_slice("\n", 0))
	lines.append(room.scene_path)
	return "\n".join(lines)
