@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSWorldMapView
extends Control
## In-game map for non-linear worlds, drawn from the same .idpworld.json the editor uses.
##
## Reveal rules follow Hollow Knight: a room shows once it is visited, or dimmed when the
## player owns the map of its area (Cornifer/Shakra); everything else stays hidden.
## [codeblock]
## map_view.mark_visited(current_room_id)          # on every room change
## map_view.map_area("The Greenhouse")             # when the area map is bought
## map_view.set_player(current_room_id, player.position)
## save["map"] = map_view.get_save_data()
## [/codeblock]

@export_file("*.idpworld.json") var world_file := "":
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

var world: MDSWorld
var visited_rooms: Dictionary = {}
var mapped_areas: Dictionary = {}
var current_room := ""
var player_local_pos := Vector2.INF
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

## [param local_pos] is the player's position inside the room scene.
func set_player(room_id: String, local_pos: Vector2) -> void:
	current_room = room_id
	player_local_pos = local_pos
	if world and world.has_room(room_id):
		layer = world.get_room_layer(room_id)
	queue_redraw()

func get_save_data() -> Dictionary:
	return {"visited": visited_rooms.keys(), "mapped_areas": mapped_areas.keys()}

func set_save_data(save: Dictionary) -> void:
	visited_rooms.clear()
	mapped_areas.clear()
	for id in save.get("visited", []):
		visited_rooms[id] = true
	for a in save.get("mapped_areas", []):
		mapped_areas[a] = true
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
		return
	var avail := size - Vector2(padding, padding) * 2.0
	var scale := minf(avail.x / bounds.size.x, avail.y / bounds.size.y)
	var offset := Vector2(padding, padding) + (avail - bounds.size * scale) / 2.0 - bounds.position * scale
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
	if world.has_room(current_room) and player_local_pos != Vector2.INF and world.get_room_layer(current_room) == layer:
		var p: Vector2 = to_screen.call(world.get_origin(current_room) + player_local_pos)
		draw_circle(p, 5.0, Color.WHITE)
		draw_circle(p, 5.0, Color.BLACK, false, 1.5)
