@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSWorldMapView
extends Control
## In-game map for non-linear worlds, drawn from the same .mdsworld.json the editor uses.
##
## Reveal rules follow Hollow Knight: a room shows once it is visited, or dimmed when the
## player owns the map of its area (Cornifer/Shakra); everything else stays hidden. Each room
## explored (visited) has a check mark ([member show_explored_marks]); rooms only on a bought map
## have none. The save points (benches) found show as bench marks, the one last rested on
## brighter, and a pin marks where the player is.
## [codeblock]
## map_view.mark_visited(current_room_id)          # on every room change
## map_view.map_area("The Greenhouse")             # when the area map is bought
## map_view.set_player(current_room_id, player.position)
## save["map"] = map_view.get_save_data()
## [/codeblock]
## [MDSWorldGame] does all of this for the map view it is given, and keeps the map explored
## across restarts (its exploration file).
##
## With [member follow_player] it is a minimap: a corner of the screen showing the rooms around
## the player ([member view_span] px of the world across), instead of everything revealed.
##
## [b]Pins[/b] mark places on the map: the player's own, a quest's, a danger. [method set_pin]
## puts one ({position: world px, layer, kind, label}), drawn as a flag in its kind's color
## ([member pin_colors]) with its label; they are saved with the map. In a game, use
## [method MDSWorldGame.add_map_pin]: the game keeps them and shows them on its maps. With
## [member pins_editable] (the pause menu's map), a click on the map asks for a pin there
## ([signal pin_requested]) and a click on a pin for it to go ([signal pin_clicked]).

## A click on the map, away from any pin, with [member pins_editable]: a pin is wanted at
## [param world_pos] (world px) on [param map_layer].
signal pin_requested(world_pos: Vector2, map_layer: int)
## A click on pin [param id] with [member pins_editable].
signal pin_clicked(id: String)

@export_file("*.mdsworld.json", "*.idpworld.json") var world_file := "":
	set(value):
		world_file = value
		world = MDSWorld.load_world(value) if not value.is_empty() and FileAccess.file_exists(value) else null
		queue_redraw()
@export var layer := 0:
	set(value):
		layer = value
		queue_redraw()
## Show every room (for debugging or a "full map" item).
@export var reveal_all := false:
	set(value):
		reveal_all = value
		queue_redraw()
@export var show_area_names := true
@export var show_room_names := false
## Draw the current area's objective under the map ([member objective], set by
## MDSWorldGame).
@export var show_objective := true
@export var background := Color(0.08, 0.07, 0.07, 0.92)
@export var padding := 24.0
## Draw the save points found (benches), the one last rested on brighter.
@export var show_save_points := true
@export var save_point_color := Color(1.0, 0.86, 0.55)
## A check mark on each room explored (visited), when the room is big enough on the map to hold it.
@export var show_explored_marks := true
@export var explored_mark_color := Color(0.62, 0.95, 0.55)
## The pin marking where the player is.
@export var player_marker_color := Color(1.0, 0.42, 0.32)
@export_group("Pins")
## Draw the pins ([member pins]).
@export var show_pins := true
## Clicks place pins and take them away (see [signal pin_requested], [signal pin_clicked]).
@export var pins_editable := false
## The color of each kind of pin; a kind not listed is drawn in the "pin" color.
@export var pin_colors: Dictionary = PIN_COLORS.duplicate()
@export_group("Minimap")
## A minimap: centred on the player, showing [member view_span] px of the world across its
## shorter side, instead of fitting every revealed room.
@export var follow_player := false:
	set(value):
		follow_player = value
		clip_contents = value
		queue_redraw()
## How much of the world a minimap shows across its shorter side (px).
@export_range(200.0, 40000.0) var view_span := 3000.0:
	set(value):
		view_span = value
		queue_redraw()
## A frame around the minimap.
@export var frame_color := Color(0.85, 0.78, 0.62, 0.8)

## How small a room may be on the map (px across) and still get its explored mark.
const EXPLORED_MARK_MIN := 18.0
## How near (px) a click must be to a pin to pick it.
const PIN_GRAB := 12.0
## The kinds of pins and their colors, to start from (see [member pin_colors]).
const PIN_COLORS := {
	"pin": Color(0.98, 0.84, 0.32), "quest": Color(0.45, 0.85, 1.0), "danger": Color(1.0, 0.35, 0.3),
	"treasure": Color(0.75, 1.0, 0.45), "note": Color(0.9, 0.9, 0.95),
}

var world: MDSWorld
var visited_rooms: Dictionary = {}
var mapped_areas: Dictionary = {}
## Save points found: room id -> positions in the room (Vector2).
var save_points: Dictionary = {}
## The save point last rested on: its room and its position in the room ("": none).
var respawn_room := ""
var respawn_pos := Vector2.ZERO
var current_room := ""
var player_local_pos := Vector2.INF
## Pins on the map: id -> {position: [x, y] (world px), layer, kind, label}.
var pins: Dictionary = {}
var _offset := Vector2.ZERO ## the world as drawn last: world px * _scale + _offset
var _scale := 0.0
## The current area's objective and whether it is done.
var objective := "":
	set(v):
		objective = v
		queue_redraw()
var objective_done := false:
	set(v):
		objective_done = v
		queue_redraw()

func mark_visited(room_id: String) -> void:
	visited_rooms[room_id] = true
	queue_redraw()

func map_area(area: String) -> void:
	mapped_areas[area] = true
	queue_redraw()

## A save point (bench) found in [param room_id], at [param local_pos] in the room.
func mark_save_point(room_id: String, local_pos: Vector2) -> void:
	var list: Array = save_points.get(room_id, [])
	for p in list:
		if (p as Vector2).distance_to(local_pos) < 1.0:
			return
	list.append(local_pos)
	save_points[room_id] = list
	queue_redraw()

## The save point the player last rested on.
func set_respawn(room_id: String, local_pos: Vector2) -> void:
	respawn_room = room_id
	respawn_pos = local_pos
	queue_redraw()

## [param local_pos] is the player's position inside the room scene.
func set_player(room_id: String, local_pos: Vector2) -> void:
	current_room = room_id
	player_local_pos = local_pos
	if world and world.has_room(room_id):
		layer = world.get_room_layer(room_id)
	queue_redraw()

## Puts pin [param id] at [param world_pos] (world px) on [param map_layer] (-1: the layer
## shown), replacing a pin of that id. [param kind] picks its color ([member pin_colors]),
## [param label] is written beside it.
func set_pin(id: String, world_pos: Vector2, map_layer := -1, kind := "pin", label := "") -> void:
	pins[id] = {"position": [world_pos.x, world_pos.y], "layer": layer if map_layer < 0 else map_layer, "kind": kind, "label": label}
	queue_redraw()

## Takes pin [param id] away. Returns whether there was one.
func remove_pin(id: String) -> bool:
	var had := pins.erase(id)
	queue_redraw()
	return had

## Takes every pin away (of [param kind] only, unless empty).
func clear_pins(kind := "") -> void:
	for id: String in pins.keys():
		if kind.is_empty() or str(pins[id].get("kind", "pin")) == kind:
			pins.erase(id)
	queue_redraw()

## Shows the pins of [param list] (id -> {position, layer, kind, label}) and no others.
func set_pins(list: Dictionary) -> void:
	pins = list.duplicate(true)
	queue_redraw()

## Where [param pin] is (world px), INF when it says nowhere.
static func pin_position(pin: Dictionary) -> Vector2:
	var p: Array = pin.get("position", [])
	return Vector2(float(p[0]), float(p[1])) if p.size() == 2 else Vector2.INF

## The world point (px) under [param at] (on this control) as the map was last drawn; INF before
## it was.
func screen_to_world(at: Vector2) -> Vector2:
	return (at - _offset) / _scale if _scale > 0.0 else Vector2.INF

## The pin drawn nearest [param at] (on this control), within [constant PIN_GRAB] px of its foot
## or its flag; "" when none is.
func pin_at(at: Vector2) -> String:
	var best := ""
	var best_d := PIN_GRAB
	if _scale <= 0.0 or not show_pins:
		return best
	for id: String in pins:
		var pin: Dictionary = pins[id]
		var wp := pin_position(pin)
		if int(pin.get("layer", 0)) != layer or wp == Vector2.INF:
			continue
		var foot := _offset + wp * _scale
		var d := minf(at.distance_to(foot), at.distance_to(foot + Vector2(4, -12)))
		if d < best_d:
			best_d = d
			best = id
	return best

func _gui_input(event: InputEvent) -> void:
	if not pins_editable or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var id := pin_at(event.position)
	if not id.is_empty():
		pin_clicked.emit(id)
	elif _scale > 0.0:
		pin_requested.emit(screen_to_world(event.position), layer)
	accept_event()

func get_save_data() -> Dictionary:
	var points: Dictionary = {}
	for id in save_points:
		points[id] = (save_points[id] as Array).map(func(p: Vector2) -> Array: return [p.x, p.y])
	var out := {"visited": visited_rooms.keys(), "mapped_areas": mapped_areas.keys(), "save_points": points}
	if not pins.is_empty():
		out.pins = pins.duplicate(true)
	if not respawn_room.is_empty():
		out.respawn = {"room": respawn_room, "position": [respawn_pos.x, respawn_pos.y]}
	return out

func set_save_data(save: Dictionary) -> void:
	visited_rooms.clear()
	mapped_areas.clear()
	save_points.clear()
	pins = (save.get("pins", {}) as Dictionary).duplicate(true) if save.get("pins", {}) is Dictionary else {}
	respawn_room = ""
	for id in save.get("visited", []):
		visited_rooms[id] = true
	for a in save.get("mapped_areas", []):
		mapped_areas[a] = true
	var points: Variant = save.get("save_points", {})
	if points is Dictionary:
		for id in points:
			for p in points[id]:
				if p is Array and p.size() == 2:
					mark_save_point(id, Vector2(float(p[0]), float(p[1])))
	var r: Variant = save.get("respawn", {})
	if r is Dictionary and r.has("room") and (r.get("position", []) as Array).size() == 2:
		set_respawn(str(r.room), Vector2(float(r.position[0]), float(r.position[1])))
	queue_redraw()

func is_room_revealed(id: String) -> bool:
	return reveal_all or visited_rooms.has(id) or mapped_areas.has(world.get_room_area(id))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
	if show_objective and not objective.is_empty():
		var f := get_theme_default_font()
		var line := ("Done: " if objective_done else "Objective: ") + objective
		draw_string(f, Vector2(padding * 0.5, size.y - padding * 0.35), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - padding, 12, Color(0.65, 1.0, 0.6) if objective_done else Color(0.95, 0.9, 0.75))
	if not world:
		return
	var shown: Array[String] = []
	var bounds := Rect2()
	for id in world.get_room_ids():
		if world.get_room_layer(id) == layer and is_room_revealed(id):
			bounds = world.get_room_bounds(id) if shown.is_empty() else bounds.merge(world.get_room_bounds(id))
			shown.append(id)
	if shown.is_empty() or not bounds.has_area():
		_draw_frame()
		return
	var avail := size - Vector2(padding, padding) * 2.0
	var scale := minf(avail.x / bounds.size.x, avail.y / bounds.size.y)
	var offset := Vector2(padding, padding) + (avail - bounds.size * scale) / 2.0 - bounds.position * scale
	if follow_player:
		# A minimap: the player in the middle, view_span px of the world across.
		scale = minf(size.x, size.y) / maxf(view_span, 1.0)
		var focus := bounds.get_center()
		if world.has_room(current_room) and player_local_pos != Vector2.INF:
			focus = world.get_origin(current_room) + player_local_pos
		offset = size / 2.0 - focus * scale
	_offset = offset
	_scale = scale
	var to_screen := func(p: Vector2) -> Vector2: return offset + p * scale
	var border := clampf(scale * 40.0, 1.5, 4.0)
	# Same tileset as the editor map (world setting "map_style").
	var style := MDSMapStyle.get_style(str(world.get_setting("map_style", "handdrawn")))
	if style.kind == MDSMapStyle.Kind.GLOW:
		# Each area as one glowing shape.
		var groups: Dictionary = {}
		var members: Dictionary = {}
		var shaped: Dictionary = {}
		var fills: Dictionary = {}
		for id in shown:
			var color := world.get_area_color(world.get_room_area(id))
			fills[id] = color if visited_rooms.has(id) or reveal_all else color.darkened(0.45)
			var g := MDSAreaTools.group_of(world, id)
			if not groups.has(g):
				groups[g] = {}
				var list: Array[String] = []
				members[g] = list
			members[g].append(id)
			if world.has_room_shape(id):
				shaped[g] = true
			var owner: Dictionary = groups[g]
			for c in world.get_room_cells(id):
				owner[c] = id
		for g: String in groups:
			var rim: Color = fills[g.substr(1)] if g.begins_with("#") else world.get_area_color(g)
			if shaped.has(g):
				var rooms: Dictionary = {}
				for id: String in members[g]:
					rooms[id] = MDSMapStyle.room_polygons(world, id)
				MDSMapStyle.draw_glow_polygons(self, rooms, to_screen, scale, fills, rim, MDSMapStyle.area_outline(world, members[g]))
			else:
				MDSMapStyle.draw_glow(self, groups[g], world.get_paint_cell(), to_screen, scale, fills, rim)
	for id in shown:
		var color := world.get_area_color(world.get_room_area(id))
		if not visited_rooms.has(id) and not reveal_all:
			color = color.darkened(0.45)
		if style.kind == MDSMapStyle.Kind.GLOW:
			continue
		if world.has_room_shape(id):
			var band := Color.TRANSPARENT if style.kind == MDSMapStyle.Kind.FLAT else (color if style.kind == MDSMapStyle.Kind.ATLAS else color.lightened(0.3))
			MDSMapStyle.draw_outlined(self, MDSMapStyle.room_polygons(world, id), to_screen, style.outline_fill(color), color.darkened(0.5), band, border * 1.6)
			continue
		if style.kind != MDSMapStyle.Kind.FLAT:
			var border_color: Color = style.theme.default_border_color if style.kind == MDSMapStyle.Kind.METSYS and style.theme.get("default_border_color") is Color else color.lightened(0.3)
			style.draw_room(self, world.get_room_cells(id), world.get_paint_cell(), to_screen, scale, color, border_color)
			continue
		for r in world.get_world_rects(id):
			draw_rect(Rect2(to_screen.call(r.position), r.size * scale).grow(border), color.darkened(0.5))
		for r in world.get_world_rects(id):
			draw_rect(Rect2(to_screen.call(r.position), r.size * scale), color)
	var font := get_theme_default_font()
	if show_room_names:
		for id in shown:
			var text := str(world.get_room_value(id, "name", id))
			var p: Vector2 = to_screen.call(world.get_room_label_pos(id))
			p.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x / 2.0
			draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	if show_area_names:
		var area_bounds: Dictionary = {}
		for id in shown:
			var a := world.get_room_area(id)
			if a.is_empty():
				continue
			area_bounds[a] = world.get_room_bounds(id) if not area_bounds.has(a) else area_bounds[a].merge(world.get_room_bounds(id))
		for a in area_bounds:
			var r: Rect2 = area_bounds[a]
			var text: String = str(a).to_upper()
			var p: Vector2 = to_screen.call(Vector2(r.get_center().x, r.position.y))
			p -= Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x / 2.0, 6)
			draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
			draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, world.get_area_color(a).lightened(0.4))
	if show_save_points:
		for id in save_points:
			if not world.has_room(id) or world.get_room_layer(id) != layer or not is_room_revealed(id):
				continue
			for lp: Vector2 in save_points[id]:
				var here: bool = id == respawn_room and lp.distance_to(respawn_pos) < 48.0
				draw_bench_mark(self, to_screen.call(world.get_origin(id) + lp), save_point_color if here else save_point_color.darkened(0.25), 1.25 if here else 1.0)
	if show_explored_marks:
		for id in shown:
			if not visited_rooms.has(id):
				continue
			var b := world.get_room_bounds(id)
			if minf(b.size.x, b.size.y) * scale < EXPLORED_MARK_MIN:
				continue
			var at: Vector2 = to_screen.call(world.get_room_label_pos(id))
			if show_room_names:
				at.y -= 14.0 # over the room's name
			draw_explored_mark(self, at, explored_mark_color)
	if show_pins:
		for id: String in pins:
			var pin: Dictionary = pins[id]
			var wp := pin_position(pin)
			if int(pin.get("layer", 0)) != layer or wp == Vector2.INF:
				continue
			var at: Vector2 = to_screen.call(wp)
			var color: Color = pin_colors.get(str(pin.get("kind", "pin")), pin_colors.get("pin", Color.YELLOW))
			draw_map_pin(self, at, color)
			var text := str(pin.get("label", ""))
			if not text.is_empty():
				draw_string_outline(font, at + Vector2(12, -6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color.BLACK)
				draw_string(font, at + Vector2(12, -6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color.lightened(0.3))
	if world.has_room(current_room) and player_local_pos != Vector2.INF and world.get_room_layer(current_room) == layer:
		draw_player_mark(self, to_screen.call(world.get_origin(current_room) + player_local_pos), player_marker_color)
	_draw_frame()

func _draw_frame() -> void:
	if follow_player and frame_color.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.0), frame_color, false, 2.0)

## A check mark for a room explored, centred on [param at], on a dark disc.
static func draw_explored_mark(ci: CanvasItem, at: Vector2, color: Color, k := 1.0) -> void:
	ci.draw_circle(at, 6.5 * k, Color(0, 0, 0, 0.6))
	var tick := PackedVector2Array([at + Vector2(-3.4, 0.2) * k, at + Vector2(-1.0, 2.8) * k, at + Vector2(3.6, -2.8) * k])
	ci.draw_polyline(tick, color, 2.0 * k, true)

## A pin for where the player is, its tip on [param at]: a round head with a white eye, pointing
## down.
static func draw_player_mark(ci: CanvasItem, at: Vector2, color: Color, k := 1.0) -> void:
	var head := at + Vector2(0, -13.0) * k
	var r := 6.5 * k
	ci.draw_circle(at, 2.5 * k, Color(0, 0, 0, 0.45)) # its shadow on the map
	var outline := PackedVector2Array([at, head + Vector2(-r * 0.86, r * 0.5), head + Vector2(r * 0.86, r * 0.5)])
	ci.draw_colored_polygon(outline, Color.BLACK)
	ci.draw_circle(head, r + 1.5 * k, Color.BLACK)
	var body := PackedVector2Array([at + Vector2(0, -1.8) * k, head + Vector2(-r * 0.7, r * 0.45), head + Vector2(r * 0.7, r * 0.45)])
	ci.draw_colored_polygon(body, color)
	ci.draw_circle(head, r, color)
	ci.draw_circle(head, r * 0.42, Color.WHITE)

## A pin put on the map, its foot on [param at]: a flag on a pole.
static func draw_map_pin(ci: CanvasItem, at: Vector2, color: Color, k := 1.0) -> void:
	var top := at + Vector2(0, -15.0) * k
	ci.draw_circle(at, 2.5 * k, Color(0, 0, 0, 0.5))
	ci.draw_line(at, top, Color.BLACK, 3.0 * k)
	ci.draw_line(at, top, color.lightened(0.5), 1.4 * k)
	var rim := PackedVector2Array([top + Vector2(-1.0, -1.5) * k, top + Vector2(12.5, 3.5) * k, top + Vector2(-1.0, 8.5) * k])
	var flag := PackedVector2Array([top, top + Vector2(10.0, 3.5) * k, top + Vector2(0, 7.0) * k])
	ci.draw_colored_polygon(rim, Color.BLACK)
	ci.draw_colored_polygon(flag, color)

## A small bench mark for the map, centred on [param at]: a seat on two legs with a back.
static func draw_bench_mark(ci: CanvasItem, at: Vector2, color: Color, k := 1.0) -> void:
	var w := 7.0 * k
	ci.draw_circle(at, 7.5 * k, Color(0, 0, 0, 0.55))
	ci.draw_rect(Rect2(at + Vector2(-w, -1.0 * k), Vector2(w * 2.0, 2.2 * k)), color)
	ci.draw_rect(Rect2(at + Vector2(-w * 0.85, -4.5 * k), Vector2(w * 1.7, 1.6 * k)), color)
	for sx in [-1.0, 1.0]:
		ci.draw_rect(Rect2(at + Vector2(sx * w * 0.7 - 0.8 * k, 1.0 * k), Vector2(1.6 * k, 3.6 * k)), color)
		ci.draw_rect(Rect2(at + Vector2(sx * w * 0.7 - 0.6 * k, -4.5 * k), Vector2(1.2 * k, 3.6 * k)), color)
