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
## [b]Markers[/b] (pins) mark places on the map: a boss room, a locked door, a key, a quest's
## target, the player's own marks. [method set_marker] puts one ({position: world px, layer,
## kind, label, description, color, icon}): a badge with its kind's icon and color
## ([member marker_kinds]: pin, boss, locked_door, key, quest, danger, treasure, note, or your own
## with [method define_marker_kind]), its label (a title) beside it; pointed at (the mouse over
## it, or the middle of the map on a gamepad), its description shows in a box
## ([member show_marker_info], [signal marker_focused]). They are saved with the map. In a game,
## use [method MDSWorldGame.add_map_marker]: the game keeps them and shows them on its maps. With
## [member pins_editable] (the pause menu's map), a click on the map asks for a pin there
## ([signal pin_requested]) and a click on a marker for it to go ([signal pin_clicked]).
##
## [b]Zoom.[/b] With [member zoomable] (the pause menu's map) the full map zooms and moves: the
## mouse wheel and [code]map_zoom_in[/code] / [code]map_zoom_out[/code] (RT / LT, = / -) zoom,
## from [member min_zoom] (the whole map small in the middle) to [member max_zoom], a drag and
## [code]map_pan_*[/code] (the right stick, I J K L) move it. Marks and markers keep their size on
## the screen, and clicks put pins where they point at any zoom.

## A click on the map, away from any pin, with [member pins_editable]: a pin is wanted at
## [param world_pos] (world px) on [param map_layer].
signal pin_requested(world_pos: Vector2, map_layer: int)
## A click on marker [param id] with [member pins_editable].
signal pin_clicked(id: String)
## The marker pointed at changed (its description shows): [param id], "" for none.
signal marker_focused(id: String)

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
@export_group("Zoom")
## The full map zooms and moves (see the class description, [member zoom]).
@export var zoomable := false:
	set(value):
		zoomable = value
		clip_contents = value or follow_player
		queue_redraw()
## How far it zooms in: this many times the whole map's fit.
@export_range(1.0, 32.0) var max_zoom := 8.0
## How far it zooms out: this share of the whole map's fit (1: no further than every room).
@export_range(0.05, 1.0) var min_zoom := 0.25
## How fast map_pan_* move it, held all the way (screen px a second).
@export var pan_speed := 700.0
@export_group("Pins")
## Draw the markers ([member pins]).
@export var show_pins := true
## Clicks place pins and take them away (see [signal pin_requested], [signal pin_clicked]).
@export var pins_editable := false
## The description of the marker pointed at shows in a box beside it.
@export var show_marker_info := true
## This map's own colors for kinds of markers (kind -> Color), over [member marker_kinds]'.
@export var pin_colors: Dictionary = {}
@export_group("Minimap")
## A minimap: centred on the player, showing [member view_span] px of the world across its
## shorter side, instead of fitting every revealed room.
@export var follow_player := false:
	set(value):
		follow_player = value
		clip_contents = value or zoomable
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
## A wheel step zooms by this much; map_zoom_in held all the way, this much a second.
const ZOOM_STEP := 1.25
const ZOOM_RATE := 3.0
## How far (px) the mouse moves, pressed, before it drags the map instead of clicking.
const DRAG_START := 6.0
## The kinds of markers to start from: kind -> {name, color, icon} (see [member marker_kinds]).
const MARKER_KINDS := {
	"pin": {"name": "Pin", "color": Color(0.98, 0.84, 0.32), "icon": "flag"},
	"boss": {"name": "Boss", "color": Color(1.0, 0.36, 0.32), "icon": "skull"},
	"locked_door": {"name": "Locked door", "color": Color(0.96, 0.64, 0.28), "icon": "lock"},
	"key": {"name": "Key", "color": Color(1.0, 0.88, 0.4), "icon": "key"},
	"quest": {"name": "Quest", "color": Color(0.45, 0.85, 1.0), "icon": "star"},
	"danger": {"name": "Danger", "color": Color(1.0, 0.35, 0.3), "icon": "warning"},
	"treasure": {"name": "Treasure", "color": Color(0.75, 1.0, 0.45), "icon": "gem"},
	"note": {"name": "Note", "color": Color(0.9, 0.9, 0.95), "icon": "dot"},
}
## The icons markers draw themselves (a marker's icon can also be a texture or its path).
const MARKER_ICONS: PackedStringArray = ["flag", "skull", "lock", "key", "star", "warning", "gem", "dot", "door", "cross"]
## How far over its point (px) a marker's badge is.
const MARKER_LIFT := 13.0

## The kinds of markers every map knows: kind -> {name, color, icon}. [method define_marker_kind]
## adds one (an NPC, a shop, a lever...). A marker of an unknown kind looks like a "pin".
static var marker_kinds: Dictionary = MARKER_KINDS.duplicate(true)
static var _icon_cache: Dictionary = {} ## texture path -> Texture2D

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
## Markers on the map: id -> {position: [x, y] (world px), layer, kind, label, description,
## and color (HTML) and icon (an icon name or a texture's path) of its own when it has them}.
var pins: Dictionary = {}
## The marker pointed at, whose description shows ("": none; see [method focus_pin]).
var focused_pin := ""
## How far the full map is zoomed in ([member zoomable]): 1 shows every room revealed, up to
## [member max_zoom].
var zoom := 1.0
## The world point (px) in the middle of the zoomed map (INF: the middle of the rooms shown).
var view_center := Vector2.INF
var _offset := Vector2.ZERO ## the world as drawn last: world px * _scale + _offset
var _scale := 0.0
var _fit_scale := 0.0 ## the scale that shows every room revealed
var _bounds := Rect2() ## the rooms revealed, as drawn last
var _press_at := Vector2.INF ## where the mouse was pressed on the map
var _dragged := false
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

## Adds a kind of marker every map knows, or changes one: its [param color], its [param icon]
## (one of [constant MARKER_ICONS], a Texture2D or its path) and [param name].
## [codeblock]
## MDSWorldMapView.define_marker_kind("shop", Color.GOLD, "gem", "Shop")
## MDSWorldMapView.define_marker_kind("npc", Color.SKY_BLUE, preload("res://ui/npc_icon.png"))
## [/codeblock]
static func define_marker_kind(kind: String, color: Color, icon: Variant = "flag", name := "") -> void:
	marker_kinds[kind] = {"name": name if not name.is_empty() else kind.capitalize(), "color": color, "icon": icon}

## How [param marker] looks: {color, icon (a name of [constant MARKER_ICONS] or a Texture2D),
## name}: its own color and icon, else its kind's ([param colors]: a map's own colors by kind).
static func marker_style(marker: Dictionary, colors: Dictionary = {}) -> Dictionary:
	var kind := str(marker.get("kind", "pin"))
	var k: Dictionary = marker_kinds.get(kind, marker_kinds.get("pin", MARKER_KINDS.pin))
	var color: Color = colors.get(kind, k.get("color", Color.WHITE))
	var own := str(marker.get("color", ""))
	if not own.is_empty() and Color.html_is_valid(own):
		color = Color.html(own)
	var icon: Variant = k.get("icon", "flag")
	var own_icon := str(marker.get("icon", ""))
	if not own_icon.is_empty():
		icon = own_icon
	return {"color": color, "icon": _icon(icon), "name": str(k.get("name", kind.capitalize()))}

## [param icon] as drawn: an icon name, else a texture (loaded once from its path).
static func _icon(icon: Variant) -> Variant:
	if icon is Texture2D:
		return icon
	var n := str(icon)
	if n in MARKER_ICONS:
		return n
	if not _icon_cache.has(n):
		_icon_cache[n] = load(n) as Texture2D if ResourceLoader.exists(n) else null
	return _icon_cache[n] if _icon_cache[n] else "flag"

## Puts marker [param id] at [param world_pos] (world px) on [param map_layer] (-1: the layer
## shown), replacing a marker of that id. [param kind] picks its look ([member marker_kinds]),
## [param label] is written beside it and [param description] shows when it is pointed at.
## [param style]: {color, icon} of its own.
func set_pin(id: String, world_pos: Vector2, map_layer := -1, kind := "pin", label := "", description := "", style := {}) -> void:
	var m := {"position": [world_pos.x, world_pos.y], "layer": layer if map_layer < 0 else map_layer, "kind": kind, "label": label, "description": description}
	if style.get("color") is Color:
		m.color = (style.color as Color).to_html()
	if style.get("icon") is Texture2D:
		m.icon = (style.icon as Texture2D).resource_path
	elif style.has("icon"):
		m.icon = str(style.icon)
	set_marker(id, m)

## Puts marker [param id] as [param marker] says ({position, layer, kind, label, description,
## color, icon}; see [member pins]).
func set_marker(id: String, marker: Dictionary) -> void:
	pins[id] = marker.duplicate(true)
	queue_redraw()

## Points at marker [param id] (its description shows), "" for none.
func focus_pin(id: String) -> void:
	if id != focused_pin:
		focused_pin = id
		marker_focused.emit(id)
		queue_redraw()

## Takes marker [param id] away. Returns whether there was one.
func remove_pin(id: String) -> bool:
	var had := pins.erase(id)
	if id == focused_pin:
		focus_pin("")
	queue_redraw()
	return had

## Takes every pin away (of [param kind] only, unless empty).
func clear_pins(kind := "") -> void:
	for id: String in pins.keys():
		if kind.is_empty() or str(pins[id].get("kind", "pin")) == kind:
			pins.erase(id)
	queue_redraw()

## Shows the markers of [param list] (id -> {position, layer, kind, label...}) and no others.
func set_pins(list: Dictionary) -> void:
	pins = list.duplicate(true)
	if not pins.has(focused_pin):
		focus_pin("")
	queue_redraw()

## Where [param pin] is (world px), INF when it says nowhere.
static func pin_position(pin: Dictionary) -> Vector2:
	var p: Array = pin.get("position", [])
	return Vector2(float(p[0]), float(p[1])) if p.size() == 2 else Vector2.INF

## The world point (px) under [param at] (on this control) as the map was last drawn; INF before
## it was.
func screen_to_world(at: Vector2) -> Vector2:
	return (at - _offset) / _scale if _scale > 0.0 else Vector2.INF

## The marker drawn nearest [param at] (on this control), within [param reach] px of its point
## or its badge; "" when none is.
func pin_at(at: Vector2, reach := PIN_GRAB) -> String:
	var best := ""
	var best_d := reach
	if _scale <= 0.0 or not show_pins:
		return best
	for id: String in pins:
		var pin: Dictionary = pins[id]
		var wp := pin_position(pin)
		if int(pin.get("layer", 0)) != layer or wp == Vector2.INF:
			continue
		var foot := _offset + wp * _scale
		var d := minf(at.distance_to(foot), at.distance_to(foot + Vector2(0, -MARKER_LIFT)))
		if d < best_d:
			best_d = d
			best = id
	return best

# --- Zoom ----------------------------------------------------------------------------------------

## Zooms the full map to [param value] times its fit ([member min_zoom] to [member max_zoom]),
## keeping the world point under [param at] (on this control; INF: its middle) where it is.
func set_zoom(value: float, at := Vector2.INF) -> void:
	value = clampf(value, clampf(min_zoom, 0.01, 1.0), maxf(max_zoom, 1.0))
	if _fit_scale <= 0.0 or _scale <= 0.0:
		zoom = value
		queue_redraw()
		return
	if at == Vector2.INF:
		at = size / 2.0
	var w := screen_to_world(at)
	zoom = value
	_view_to(w - (at - size / 2.0) / (_fit_scale * zoom), _fit_scale * zoom)

## Moves the full map by [param screen_delta] px, as a drag does.
func pan_by(screen_delta: Vector2) -> void:
	if _scale > 0.0:
		_view_to((size / 2.0 - _offset) / _scale - screen_delta / _scale, _scale)

## Puts [param world_pos] in the middle of the full map (as far as the rooms go).
func center_on(world_pos: Vector2) -> void:
	view_center = world_pos
	if _scale > 0.0:
		_view_to(world_pos, _scale)
	queue_redraw()

## Back to every room revealed.
func reset_view() -> void:
	zoom = 1.0
	view_center = Vector2.INF
	queue_redraw()

func _view_to(center: Vector2, scale: float) -> void:
	view_center = _clamped_center(center, scale)
	_scale = scale
	_offset = size / 2.0 - view_center * scale
	queue_redraw()

## [param center] kept so the map shows rooms: along a side the rooms fit on the screen, their
## middle; else the screen stays over them.
func _clamped_center(center: Vector2, scale: float) -> Vector2:
	if not _bounds.has_area() or scale <= 0.0:
		return center
	var half := size / 2.0 / scale
	var out := center
	for axis in 2:
		if _bounds.size[axis] <= half[axis] * 2.0:
			out[axis] = _bounds.get_center()[axis]
		else:
			out[axis] = clampf(center[axis], _bounds.position[axis] + half[axis], _bounds.end[axis] - half[axis])
	return out

static func _strength(action: StringName) -> float:
	return Input.get_action_strength(action) if InputMap.has_action(action) else 0.0

func _process(delta: float) -> void:
	if not zoomable or follow_player or Engine.is_editor_hint() or not is_visible_in_tree():
		return
	var z := _strength(&"map_zoom_in") - _strength(&"map_zoom_out")
	if absf(z) > 0.05:
		set_zoom(zoom * pow(ZOOM_RATE, z * delta))
	var pan := Vector2(_strength(&"map_pan_right") - _strength(&"map_pan_left"), _strength(&"map_pan_down") - _strength(&"map_pan_up"))
	if pan.length() > 0.1:
		# The stick looks that way: the map moves the other.
		pan_by(-pan * pan_speed * delta)
	if absf(z) > 0.05 or pan.length() > 0.1:
		# On a gamepad, the marker in the middle of the map is the one pointed at.
		focus_pin(pin_at(size / 2.0, PIN_GRAB * 4.0))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if zoomable and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_zoom(zoom * (ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP), mb.position)
			accept_event()
			return
		var drag_button := mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE] and zoomable
		if mb.button_index != MOUSE_BUTTON_LEFT and not drag_button:
			return
		if mb.pressed:
			_press_at = mb.position
			_dragged = drag_button
		else:
			# A click (pressed and let go without dragging) puts or picks a pin.
			if mb.button_index == MOUSE_BUTTON_LEFT and not _dragged and _press_at != Vector2.INF and pins_editable:
				_pin_click(mb.position)
			_press_at = Vector2.INF
		if pins_editable or zoomable:
			accept_event()
	elif event is InputEventMouseMotion and zoomable and _press_at != Vector2.INF:
		var mm := event as InputEventMouseMotion
		if not _dragged and mm.position.distance_to(_press_at) > DRAG_START:
			_dragged = true
		if _dragged:
			pan_by(mm.relative)
			accept_event()
	elif event is InputEventMouseMotion and show_marker_info:
		# The mouse over a marker points at it.
		focus_pin(pin_at((event as InputEventMouseMotion).position))

func _pin_click(at: Vector2) -> void:
	var id := pin_at(at)
	if not id.is_empty():
		focus_pin(id)
		pin_clicked.emit(id)
	elif _scale > 0.0:
		pin_requested.emit(screen_to_world(at), layer)

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
	_fit_scale = scale
	_bounds = bounds
	if zoomable and not follow_player and scale > 0.0 and (zoom != 1.0 or view_center != Vector2.INF):
		# Zoomed: view_center in the middle, the screen kept over the rooms (zoomed out, the
		# rooms small in the middle).
		scale *= clampf(zoom, clampf(min_zoom, 0.01, 1.0), maxf(max_zoom, 1.0))
		var center := _clamped_center(view_center if view_center != Vector2.INF else bounds.get_center(), scale)
		offset = size / 2.0 - center * scale
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
			var st := marker_style(pin, pin_colors)
			var at: Vector2 = to_screen.call(wp)
			draw_marker(self, at, st.icon, st.color, 1.2 if id == focused_pin else 1.0)
			# Zoomed out below the fit the markers crowd: only the one pointed at keeps its title.
			if not (zoomable and zoom < 1.0) or id == focused_pin:
				draw_marker_label(self, font, at, str(pin.get("label", "")), st.color)
	if world.has_room(current_room) and player_local_pos != Vector2.INF and world.get_room_layer(current_room) == layer:
		draw_player_mark(self, to_screen.call(world.get_origin(current_room) + player_local_pos), player_marker_color)
	if show_pins and show_marker_info and pins.has(focused_pin) and int(pins[focused_pin].get("layer", 0)) == layer:
		var wp := pin_position(pins[focused_pin])
		if wp != Vector2.INF:
			draw_marker_info(self, font, to_screen.call(wp), pins[focused_pin], marker_style(pins[focused_pin], pin_colors), Rect2(Vector2.ZERO, size))
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

## A pin put on the map, its point on [param at] (a marker with the flag icon).
static func draw_map_pin(ci: CanvasItem, at: Vector2, color: Color, k := 1.0) -> void:
	draw_marker(ci, at, "flag", color, k)

## A marker, its point on [param at]: a dark badge over it, rimmed in [param color], with
## [param icon] (one of [constant MARKER_ICONS], or a Texture2D) in it.
static func draw_marker(ci: CanvasItem, at: Vector2, icon: Variant, color: Color, k := 1.0) -> void:
	var c := at + Vector2(0, -MARKER_LIFT) * k
	var r := 8.5 * k
	ci.draw_circle(at, 2.2 * k, Color(0, 0, 0, 0.5))
	ci.draw_colored_polygon(PackedVector2Array([at, c + Vector2(-r * 0.62, r * 0.6), c + Vector2(r * 0.62, r * 0.6)]), Color.BLACK)
	ci.draw_circle(c, r + 1.6 * k, Color.BLACK)
	ci.draw_circle(c, r, color.darkened(0.55))
	ci.draw_arc(c, r - 0.6 * k, 0.0, TAU, 20, color, 1.4 * k, true)
	if icon is Texture2D:
		var t := icon as Texture2D
		var side := r * 1.3
		ci.draw_texture_rect(t, Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side)), false)
		return
	_draw_icon(ci, c, str(icon), color, r * 0.62)

## Icon [param icon] centred on [param c], [param s] px from its middle to its edge.
static func _draw_icon(ci: CanvasItem, c: Vector2, icon: String, color: Color, s: float) -> void:
	var dark := Color(0.05, 0.04, 0.05)
	match icon:
		"skull":
			ci.draw_circle(c + Vector2(0, -0.15) * s, s * 0.85, color)
			ci.draw_rect(Rect2(c + Vector2(-0.5, 0.35) * s, Vector2(1.0, 0.6) * s), color)
			ci.draw_circle(c + Vector2(-0.35, -0.15) * s, s * 0.22, dark)
			ci.draw_circle(c + Vector2(0.35, -0.15) * s, s * 0.22, dark)
			ci.draw_line(c + Vector2(-0.15, 0.6) * s, c + Vector2(-0.15, 0.95) * s, dark, maxf(1.0, s * 0.15))
			ci.draw_line(c + Vector2(0.15, 0.6) * s, c + Vector2(0.15, 0.95) * s, dark, maxf(1.0, s * 0.15))
		"lock":
			ci.draw_arc(c + Vector2(0, -0.2) * s, s * 0.5, PI, TAU, 10, color, maxf(1.2, s * 0.28))
			ci.draw_rect(Rect2(c + Vector2(-0.75, -0.2) * s, Vector2(1.5, 1.15) * s), color)
			ci.draw_circle(c + Vector2(0, 0.3) * s, s * 0.18, dark)
		"key":
			ci.draw_arc(c + Vector2(-0.45, -0.35) * s, s * 0.42, 0.0, TAU, 12, color, maxf(1.2, s * 0.26))
			ci.draw_line(c + Vector2(-0.15, -0.05) * s, c + Vector2(0.85, 0.85) * s, color, maxf(1.2, s * 0.26))
			ci.draw_line(c + Vector2(0.45, 0.45) * s, c + Vector2(0.75, 0.2) * s, color, maxf(1.2, s * 0.22))
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * (1.0 if i % 2 == 0 else 0.45))
			ci.draw_colored_polygon(pts, color)
		"warning":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1.0) * s, c + Vector2(0.95, 0.75) * s, c + Vector2(-0.95, 0.75) * s]), color)
			ci.draw_line(c + Vector2(0, -0.45) * s, c + Vector2(0, 0.2) * s, dark, maxf(1.0, s * 0.2))
			ci.draw_circle(c + Vector2(0, 0.48) * s, maxf(0.8, s * 0.12), dark)
		"gem":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.95) * s, c + Vector2(0.8, -0.2) * s, c + Vector2(0, 0.95) * s, c + Vector2(-0.8, -0.2) * s]), color)
			ci.draw_line(c + Vector2(-0.8, -0.2) * s, c + Vector2(0.8, -0.2) * s, dark, maxf(1.0, s * 0.12))
		"dot":
			ci.draw_circle(c, s * 0.55, color)
		"door":
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.4) * s, Vector2(1.2, 1.35) * s), color)
			ci.draw_circle(c + Vector2(0, -0.4) * s, s * 0.6, color)
			ci.draw_circle(c + Vector2(0.3, 0.35) * s, maxf(0.8, s * 0.12), dark)
		"cross":
			ci.draw_line(c + Vector2(-0.75, -0.75) * s, c + Vector2(0.75, 0.75) * s, color, maxf(1.4, s * 0.3))
			ci.draw_line(c + Vector2(0.75, -0.75) * s, c + Vector2(-0.75, 0.75) * s, color, maxf(1.4, s * 0.3))
		_: # flag
			ci.draw_line(c + Vector2(-0.55, 0.95) * s, c + Vector2(-0.55, -0.95) * s, color.lightened(0.4), maxf(1.0, s * 0.2))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.45, -0.95) * s, c + Vector2(0.9, -0.45) * s, c + Vector2(-0.45, 0.1) * s]), color)

## A marker's [param text] (its title) beside it, its point on [param at].
static func draw_marker_label(ci: CanvasItem, font: Font, at: Vector2, text: String, color: Color) -> void:
	if text.is_empty():
		return
	var p := at + Vector2(13, -MARKER_LIFT + 4)
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color.BLACK)
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color.lightened(0.35))

## The box with [param marker]'s title (its label, else its kind's name) and description, beside
## its point [param at], kept inside [param bounds].
static func draw_marker_info(ci: CanvasItem, font: Font, at: Vector2, marker: Dictionary, style: Dictionary, bounds: Rect2) -> void:
	var title := str(marker.get("label", ""))
	if title.is_empty():
		title = str(style.get("name", "Marker"))
	var text := str(marker.get("description", ""))
	var w := 230.0
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, w, 13)
	var body := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, 11) if not text.is_empty() else Vector2.ZERO
	var box := Rect2(at + Vector2(16, -MARKER_LIFT - 8), Vector2(maxf(title_size.x, body.x) + 16.0, 12.0 + title_size.y + (body.y + 4.0 if not text.is_empty() else 0.0)))
	# Kept on the map: to the left of the marker when there's no room on its right.
	if box.end.x > bounds.end.x - 4.0:
		box.position.x = at.x - 16.0 - box.size.x
	box.position.x = clampf(box.position.x, bounds.position.x + 4.0, maxf(bounds.position.x + 4.0, bounds.end.x - box.size.x - 4.0))
	box.position.y = clampf(box.position.y, bounds.position.y + 4.0, maxf(bounds.position.y + 4.0, bounds.end.y - box.size.y - 4.0))
	var color: Color = style.get("color", Color.WHITE)
	ci.draw_rect(box, Color(0.04, 0.035, 0.04, 0.9))
	ci.draw_rect(box, color, false, 1.5)
	ci.draw_string(font, box.position + Vector2(8, 6 + font.get_ascent(13)), title, HORIZONTAL_ALIGNMENT_LEFT, w, 13, color.lightened(0.3))
	if not text.is_empty():
		ci.draw_multiline_string(font, box.position + Vector2(8, 10 + title_size.y + font.get_ascent(11)), text, HORIZONTAL_ALIGNMENT_LEFT, w, 11, -1, Color(0.9, 0.88, 0.84))

## A small bench mark for the map, centred on [param at]: a seat on two legs with a back.
static func draw_bench_mark(ci: CanvasItem, at: Vector2, color: Color, k := 1.0) -> void:
	var w := 7.0 * k
	ci.draw_circle(at, 7.5 * k, Color(0, 0, 0, 0.55))
	ci.draw_rect(Rect2(at + Vector2(-w, -1.0 * k), Vector2(w * 2.0, 2.2 * k)), color)
	ci.draw_rect(Rect2(at + Vector2(-w * 0.85, -4.5 * k), Vector2(w * 1.7, 1.6 * k)), color)
	for sx in [-1.0, 1.0]:
		ci.draw_rect(Rect2(at + Vector2(sx * w * 0.7 - 0.8 * k, 1.0 * k), Vector2(1.6 * k, 3.6 * k)), color)
		ci.draw_rect(Rect2(at + Vector2(sx * w * 0.7 - 0.6 * k, -4.5 * k), Vector2(1.2 * k, 3.6 * k)), color)
