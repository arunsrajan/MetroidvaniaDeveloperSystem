@tool
class_name MDSRoomCanvas
extends Control
## The Room view's painting surface: shows a room scene at its real size and paints its
## tile layers (see [MDSRoomPainter]).
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
## Effects tool: drag an effect from the palette onto the room (or pick one and click), click
## one to select it (it shows in the Inspector), drag it to move it, drag its corner to
## resize it, Delete removes it. An image file dropped on the view opens Trace drawing.
## Place tool: click to place the tiles picked in the tile palette anywhere, at the angle and
## mirror picked there (R / Shift+R turn them), off the grid: a free tile piece (see
## [method MDSRoomPainter.add_tile_piece]) that draws and collides like its layer's tiles.
## Shift+click removes a free tile piece.
## Select tool: click tiles, free tiles, stamps, pictures and freeform shapes to select them
## (Shift or Ctrl adds or removes), or drag a box around them; drag the selection to move it by
## pixels ([member snap_to_grid]: by whole tiles). Tiles moved off the grid become free tiles;
## moved by whole tiles, they stay on the grid. R / Shift+R turn the selection, the arrows
## nudge it a pixel (Shift: a tile), Delete removes it, Esc clears it.

signal painted
signal status_message(text: String)
## The selected freeform shape changed (null: none).
signal selection_changed(shape: MDSFreeform)
## The selected effect changed (null: none).
signal effect_selected(effect: MDSEnvironmentEffect)
## The effect a click places changed by itself (after placing one): "" for none.
signal effect_pick_changed(effect_id: String)
## An image file was dropped on the view (to trace it).
signal image_dropped(path: String)
## What the Select tool has selected changed (see [member selection], [member selected_cells]).
signal picked_changed
## R / Shift+R under the Place tool: turn the palette's tiles by [param degrees].
signal turn_requested(degrees: float)

enum Tool { TERRAIN, BACKGROUND, DECOR, ERASE, FOREGROUND, FREEFORM, STAMP, EFFECT, PLACE, SELECT }
## What the Select tool's clicks and boxes pick: everything, the tiles of one layer (on the grid
## and free), or only items (free tiles, stamps, pictures, freeform shapes).
enum PickLayer { ALL, TERRAIN, BACKGROUND, DECOR, FOREGROUND, ITEMS }
const PICK_LAYER_NAMES: PackedStringArray = ["Everything", "Terrain tiles", "Background tiles", "Decor tiles", "Foreground tiles", "Items only (free tiles, stamps, pictures, shapes)"]
const PICK_LAYERS := {PickLayer.ALL: ["Foreground", "Decor", "Terrain", "Background"], PickLayer.TERRAIN: ["Terrain"], PickLayer.BACKGROUND: ["Background"],
	PickLayer.DECOR: ["Decor"], PickLayer.FOREGROUND: ["Foreground"], PickLayer.ITEMS: []}
## Collision role of new (and the selected) freeform shapes: the style's, or an override.
enum RoleChoice { STYLE, TERRAIN, PLATFORM_ONE_WAY, PLATFORM, DECOR }
## Freeform tool shapes from MDSShapeGenerators have ids from here on (Column = 100...).
const GENERATOR_BASE := 100
const ROLE_CHOICE_NAMES: PackedStringArray = ["Style's role", "Terrain", "Platform, one-way", "Platform, two-way", "Decoration (no collision)"]
enum EraseMode { TOP, DECOR, TERRAIN, BACKGROUND, ALL, FOREGROUND }
const ERASE_MODE_NAMES: PackedStringArray = ["Top tile (stamp, free tiles, foreground, decor, terrain, then background)", "Decor only", "Terrain only", "Background only", "All layers", "Foreground only"]
const TOOL_COLORS: Array[Color] = [Color(0.5, 1, 0.4), Color(0.3, 0.8, 1), Color(1, 0.8, 0.3), Color(1, 0.35, 0.35), Color(0.75, 0.6, 1), Color(0.4, 1, 0.85), Color(1, 0.6, 0.85), Color(0.55, 0.85, 1), Color(1, 0.9, 0.45), Color(0.95, 0.95, 1)]
## Image files Trace drawing reads (dropped on the view).
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]
## Drag data of an effect from the palette: {"type": DRAG_EFFECT, "effect": id}.
const DRAG_EFFECT := "mds_effect"
enum FreeformMode { DRAW, EDIT }

var painter: MDSRoomPainter
var world: MDSWorld
var room_id := ""
var tool: int = Tool.TERRAIN
## Fill painted by each tool (see [method MDSRoomPainter.paint_fill]).
var fills: Dictionary = {
	Tool.TERRAIN: {"type": "terrain", "set": 0, "terrain": 0},
	Tool.BACKGROUND: {"type": "kind", "kind": "foliage"},
	Tool.DECOR: {"type": "kind", "kind": "grass"},
	Tool.FOREGROUND: {"type": "color", "color": Color("#03070a")},
}
var brush_size := 2
var erase_mode: int = EraseMode.TOP
var shape: int = MDSTerrainShapes.Shape.BRUSH
var curve: int = MDSTerrainShapes.CurveType.CONVEX
var roughness := 0.0 ## 0..1, "Irregular"
var mirror := false
var curve_count := 3 ## waves, steps or spikes
var zoom := 0.5
var pan := Vector2(20, 20)
## Freeform tool.
var freeform_mode: int = FreeformMode.DRAW
var freeform_style: MDSFreeformStyle
var freeform_group := "Freeform" ## "FreeformBack", "Freeform" or "FreeformFront"
var freeform_solid := true
var freeform_role: int = RoleChoice.STYLE
var selected: MDSFreeform:
	set(v):
		if v != selected:
			selected = v
			selection_changed.emit(v)
## Stamps tool.
var stamp_set: MDSStampSet
var stamp_category := ""
var stamp_group := "StampsFront"
var stamp_scale := 1.0
## Effects tool: the effect a click places ("" = none, only selecting).
var effect_id := ""
var selected_effect: MDSEnvironmentEffect:
	set(v):
		# A selection that undo took out (and freed) is replaced too.
		if v != selected_effect or not is_instance_valid(selected_effect):
			selected_effect = v
			effect_selected.emit(v)
## Show the room's weather (its own, else its area's) over the view, as in the game.
var weather_preview := true
## Called before an effect dropped from the palette is placed (the Room view switches to the
## Effects tool).
var before_effect_drop: Callable
var _weather: Node2D
var _weather_spec := ""
## Parts of the room's rects outside its outline on the map (shaded), and what they were made for.
var _shape_shade: Array[PackedVector2Array] = []
var _shape_shade_key := 0
## Show the room's backgrounds behind it: its parallax and its animated background (its own,
## else its area's...).
var parallax_preview := true
var _parallax: Node2D
var _parallax_value := ""
var _background: Node2D
var _background_value := ""
var _effect_drag := 0 ## 0 none, 1 move, 2 resize
var _effect_from := Vector2.ZERO
var _effect_orig := Rect2()
var _effect_moved := false ## the press has moved or resized the effect
var _effect_checkpointed := false ## the press already took an undo step
var _effect_cycle := false ## a click without dragging picks the next effect under it
## Last Check room result: {issues, surfaces} (see MDSRoomCheck), drawn over the room until
## the next edit.
var check_result: Dictionary = {}
## Draw the floors of the last check: green where the player gets, red where not.
var show_reachability := true
## Show the room as MDSDepth25D will draw it in the game.
var depth_preview := false
var _depth: MDSDepth25D
## Place and Select: move by whole tiles (on the grid) instead of by pixels.
var snap_to_grid := false
## Place: the tiles to place (a palette fill: {source, region, random, rotation, flip}) and the
## tile layer whose depth they go to.
var place_fill: Dictionary = {}
var place_layer := "Terrain"
## Place and Select: how far R / Shift+R turn (degrees).
var turn_step := 15.0
## Select: what clicks and boxes pick (see [enum PickLayer]).
var pick_layer: int = PickLayer.ALL
## Select: the selected items (free tile pieces, stamps, pictures, freeform shapes)...
var selection: Array[Node2D] = []
## ...and grid tiles: layer name -> {cell: true}.
var selected_cells: Dictionary = {}
var _sel_drag := 0 ## 0 none, 1 box, 2 move
var _sel_from := Vector2.ZERO
var _sel_to := Vector2.ZERO
var _sel_add := false
var _sel_moved := false
var _sel_pick: Dictionary = {} ## what the press picked when it was selected already
var _sel_orig: Dictionary = {} ## node -> position when the move started
var _lifted: Array[TileMapLayer] = [] ## grid tiles taken off the grid for this move
var _place_drag: TileMapLayer ## the piece just placed, following the mouse until release
var _place_from := Vector2.ZERO
var _place_orig := Vector2.ZERO
var _place_pick := Vector2i(-1, -1) ## Random: the tile the next click places

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
func open(p_world: MDSWorld, id: String, p_painter: MDSRoomPainter) -> void:
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
			if l is TileMapLayer or MDSRoomPainter.is_item(l, _display_scene):
				l.visible = false
		_view.add_child(_display_scene)
	for n in MDSRoomPainter.LAYER_ORDER:
		_view.add_child(painter.layers[n])
	_view.add_child(painter.items_root)
	selected = null
	selected_effect = null
	set_selection([])
	_draft.clear()
	set_depth_preview(depth_preview)
	refresh_weather()
	fit()

func close() -> void:
	if is_instance_valid(_depth):
		_depth.queue_free()
	_depth = null
	if is_instance_valid(_weather):
		_weather.queue_free()
	_weather = null
	_weather_spec = ""
	if is_instance_valid(_parallax):
		_parallax.queue_free()
	_parallax = null
	_parallax_value = ""
	if is_instance_valid(_background):
		_background.queue_free()
	_background = null
	_background_value = ""
	selected_effect = null
	selection.clear()
	selected_cells.clear()
	_lifted.clear()
	_place_drag = null
	_sel_drag = 0
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

## Turns the 2.5D preview on or off: the room's terrain extruded toward the middle of the view,
## lit like in the game (see MDSDepth25D).
func set_depth_preview(on: bool) -> void:
	depth_preview = on
	if on and not is_instance_valid(_depth) and painter:
		_depth = MDSDepth25D.new()
		_depth.name = "DepthPreview"
		_depth.preview_in_editor = true
		var srcs: Array[Node] = [painter.items_root]
		for l in painter.layers.values():
			srcs.append(l)
		if is_instance_valid(_display_scene):
			srcs.append(_display_scene)
		_depth.sources = srcs
		_view.add_child(_depth)
		_update_depth_view()
	elif not on and is_instance_valid(_depth):
		_depth.queue_free()
		_depth = null

func _update_depth_view() -> void:
	if is_instance_valid(_depth) and zoom > 0.0:
		_depth.view_override = Rect2(screen_to_local(Vector2.ZERO), size / zoom)

func _apply_view() -> void:
	_view.position = pan
	_view.scale = Vector2(zoom, zoom)
	_update_depth_view()
	queue_redraw()
	_overlay.queue_redraw()

func screen_to_local(p: Vector2) -> Vector2:
	return (p - pan) / zoom

func local_to_screen(p: Vector2) -> Vector2:
	return pan + p * zoom

## Shows the Room view's changes to the scene's other nodes (hidden, removed, moved) on the
## displayed copy of the scene, and undoes the ones undone.
func refresh_scene_edits() -> void:
	if not painter or not is_instance_valid(_display_scene):
		return
	var originals := painter.scene_originals()
	for p in originals:
		var n := _display_scene.get_node_or_null(NodePath(p))
		if not n:
			continue
		var o: Dictionary = originals[p]
		var e: Dictionary = painter.scene_edits.get(p, {})
		if n is CanvasItem:
			n.visible = o.visible and not e.get("hidden", false) and not e.get("removed", false)
		if n is Node2D:
			n.position = e.get("position", o.position)

func _draw_overlay() -> void:
	if not painter or not world or not world.has_room(room_id):
		return
	refresh_scene_edits()
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
	# A curved or slanted outline on the map: what lies outside it lightly shaded, the outline drawn.
	var map_shape := world.get_local_shape(room_id)
	if not map_shape.is_empty():
		var key := hash([rects, map_shape.map(func(p: PackedVector2Array) -> String: return var_to_str(p))])
		if _shape_shade_key != key:
			_shape_shade_key = key
			_shape_shade.clear()
			for r: Rect2 in rects:
				var parts: Array[PackedVector2Array] = [MDSGeometry.rect_polygon(r)]
				for poly in map_shape:
					var next: Array[PackedVector2Array] = []
					for part in parts:
						next.append_array(MDSGeometry.without_holes(Geometry2D.clip_polygons(part, poly), 1.0))
					parts = next
				_shape_shade.append_array(MDSMapStyle.drawable(parts))
		for part in _shape_shade:
			var pts := PackedVector2Array()
			for q in part:
				pts.append(local_to_screen(q))
			ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.3))
		for poly in map_shape:
			var line := PackedVector2Array()
			for q in poly:
				line.append(local_to_screen(q))
			line.append(line[0])
			ci.draw_polyline(line, Color(0.3, 0.9, 1.0, 0.9), 2.0)
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
	_draw_check(ci, font)
	_draw_effects(ci, font)
	# Brush / shape preview.
	var color: Color = TOOL_COLORS[tool]
	if tool == Tool.FREEFORM:
		_draw_freeform_overlay(ci, color)
	if tool == Tool.SELECT or tool == Tool.PLACE:
		_draw_select_overlay(ci, color)
	if tool == Tool.PLACE:
		_draw_place_overlay(ci, color)
	if tool == Tool.STAMP and get_rect().has_point(_mouse):
		ci.draw_arc(_mouse, 48.0 * stamp_scale * zoom, 0, TAU, 32, color, 1.5)
	if _shaping and shape >= GENERATOR_BASE:
		var d := _generated(_shape_seed)
		var pts := PackedVector2Array()
		for q in MDSFreeform.outline_of(d.points, d.smooth):
			pts.append(local_to_screen(q))
		if pts.size() >= 2:
			pts.append(pts[0])
			ci.draw_polyline(pts, color, 2.0, true)
	elif _shaping:
		_draw_cells(ci, shape_cells(), color)
		var a := painter.cell_rect("Terrain", Vector2i(mini(_shape_from.x, _shape_to.x), mini(_shape_from.y, _shape_to.y)))
		var bb := painter.cell_rect("Terrain", Vector2i(maxi(_shape_from.x, _shape_to.x), maxi(_shape_from.y, _shape_to.y)))
		ci.draw_rect(Rect2(local_to_screen(a.position), (bb.end - a.position) * zoom), color, false, 1.0)
	elif get_rect().has_point(_mouse) and not tool in [Tool.STAMP, Tool.EFFECT, Tool.PLACE, Tool.SELECT] and not (tool == Tool.FREEFORM and (shape == MDSTerrainShapes.Shape.BRUSH or freeform_mode == FreeformMode.EDIT)):
		if shape == MDSTerrainShapes.Shape.BRUSH:
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

## The last Check room: reachable (green) and unreachable (red) floors, and issue markers.
func _draw_check(ci: CanvasItem, font: Font) -> void:
	if check_result.is_empty():
		return
	if show_reachability:
		for s in check_result.get("surfaces", []):
			var pts := PackedVector2Array()
			for q in s.points:
				pts.append(local_to_screen(q))
			var c := Color(0.35, 1.0, 0.45, 0.9) if s.reachable else Color(1.0, 0.3, 0.3, 0.9)
			if pts.size() >= 2:
				ci.draw_polyline(pts, c, 4.0)
			elif pts.size() == 1:
				ci.draw_circle(pts[0], 3.0, c)
	for i in check_result.get("issues", []):
		var p := local_to_screen(i.pos)
		ci.draw_circle(p, 9.0, Color(1, 0.25, 0.2, 0.85))
		ci.draw_arc(p, 12.0, 0, TAU, 24, Color.WHITE, 1.5)
		var label: String = MDSRoomCheck.KINDS.get(i.kind, i.kind)
		ci.draw_string_outline(font, p + Vector2(15, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		ci.draw_string(font, p + Vector2(15, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.7, 0.6))

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
	if freeform_mode == FreeformMode.EDIT:
		# One-way shapes: their tops (where bodies land) dashed.
		for f in MDSFreeform.shapes_in(painter.items_root):
			if not f.is_collider() or not f.is_one_way() or f.points.size() < 3:
				continue
			var outline := f.get_outline()
			for run in MDSFreeform.edge_runs(outline, MDSFreeform.outward_normals(outline), Vector2.UP, 60.0):
				for i in range(1, run.size()):
					ci.draw_dashed_line(local_to_screen(run[i - 1] + f.position) + Vector2(0, -3), local_to_screen(run[i] + f.position) + Vector2(0, -3), Color(0.45, 0.9, 1.0), 2.0, 7.0)
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
	if shape >= GENERATOR_BASE:
		var none: Array[Vector2i] = []
		return none
	return MDSTerrainShapes.cells(shape, _shape_from, _shape_to, curve, roughness, mirror, _shape_seed, curve_count)

## Name of a Shape list entry (brushes, shapes and scenery generators).
static func shape_name(id: int) -> String:
	if id >= GENERATOR_BASE:
		return MDSShapeGenerators.NAMES[id - GENERATOR_BASE]
	return MDSTerrainShapes.SHAPE_NAMES[id]

## The box being dragged, in scene space (whole cells).
func _shape_box() -> Rect2:
	var a := painter.cell_rect("Terrain", Vector2i(mini(_shape_from.x, _shape_to.x), mini(_shape_from.y, _shape_to.y)))
	var b := painter.cell_rect("Terrain", Vector2i(maxi(_shape_from.x, _shape_to.x), maxi(_shape_from.y, _shape_to.y)))
	return Rect2(a.position, b.end - a.position)

## The generator's outline in the dragged box: {points, smooth}.
func _generated(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return MDSShapeGenerators.make(shape - GENERATOR_BASE, _shape_box(), rng)

## Paints a shape spanning cells [param a] to [param b] with the current tool (also used
## by tests).
func paint_shape(a: Vector2i, b: Vector2i, shift := false) -> void:
	_shape_from = a
	_shape_to = b
	_stroke_erased.clear()
	painter.checkpoint()
	if shape >= GENERATOR_BASE and tool == Tool.FREEFORM:
		var d := _generated(_shape_seed)
		var f := add_freeform(d.points)
		if f:
			f.smooth = d.smooth
			f.name = shape_name(shape).get_slice(" ", 0) + str(f.get_index() + 1)
	else:
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
			# Then free tiles: the tile of a piece under the cell's center.
			for piece in painter.tile_pieces():
				var pc: Vector2i = piece.local_to_map(piece.transform.affine_inverse() * r.get_center())
				if piece.get_cell_source_id(pc) != -1:
					piece.erase_cell(pc)
					hit = true
					if piece.get_used_cells().is_empty():
						painter.remove_item(piece)
					if mode == EraseMode.TOP:
						break
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
func add_freeform(points: PackedVector2Array) -> MDSFreeform:
	if points.size() < 3:
		return null
	var st := freeform_style if freeform_style else MDSFreeform._default_style()
	var f := painter.add_freeform(points, st, freeform_group, freeform_solid)
	apply_role_choice(f, freeform_role)
	selected = f
	painted.emit()
	status_message.emit("Freeform shape added (%d points). Edit mode drags its points; Delete removes it." % points.size())
	return selected

## The outline of a set of cells (e.g. a curved or irregular shape) as a freeform shape:
## the contour is traced, simplified and then rounded by the shape itself.
func add_freeform_from_cells(cells: Array) -> MDSFreeform:
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
		var a := absf(MDSFreeform.signed_area(poly))
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

## Gives [param f] the collision role picked in the Role list (see [enum RoleChoice]).
static func apply_role_choice(f: MDSFreeform, choice: int) -> void:
	match choice:
		RoleChoice.TERRAIN:
			f.set_collision_override(MDSFreeformStyle.Role.TERRAIN, false)
		RoleChoice.PLATFORM_ONE_WAY:
			f.set_collision_override(MDSFreeformStyle.Role.PLATFORM, true)
		RoleChoice.PLATFORM:
			f.set_collision_override(MDSFreeformStyle.Role.PLATFORM, false)
		RoleChoice.DECOR:
			f.set_collision_override(MDSFreeformStyle.Role.DECOR, false)
		_:
			f.override_collision = false

## The Role list entry matching [param f]'s settings.
static func role_choice_of(f: MDSFreeform) -> int:
	if not f.override_collision:
		return RoleChoice.STYLE
	match f.role:
		MDSFreeformStyle.Role.PLATFORM:
			return RoleChoice.PLATFORM_ONE_WAY if f.one_way else RoleChoice.PLATFORM
		MDSFreeformStyle.Role.DECOR:
			return RoleChoice.DECOR
	return RoleChoice.TERRAIN

func delete_selected() -> void:
	if is_instance_valid(selected):
		painter.checkpoint()
		painter.remove_item(selected)
		selected = null
		painted.emit()
		status_message.emit("Freeform shape removed.")

# --- Place: tiles off the grid -------------------------------------------------------------------

## [param p] (scene-local) on the nearest corner of the tile grid.
func snap_point(p: Vector2) -> Vector2:
	var o: Vector2 = painter.layers["Terrain"].transform.origin
	var ts := painter.tile_size()
	return o + ((p - o) / ts).round() * ts

## Size (px) of what the Place tool places.
func _place_size() -> Vector2:
	var region: Rect2i = place_fill.get("region", Rect2i(0, 0, 1, 1))
	return painter.tile_size() * (Vector2.ONE if bool(place_fill.get("random", false)) else Vector2(region.size))

## Where a piece of the Place tool's tiles centred on [param at] (scene-local) goes: turned and
## mirrored as picked in the palette; with [member snap_to_grid], its corner on the grid (so tiles
## turned in right angles line up with the grid's).
func place_transform(at: Vector2) -> Transform2D:
	var mirror := Transform2D.FLIP_X if bool(place_fill.get("flip", false)) else Transform2D.IDENTITY
	var xf := Transform2D(0.0, at) * Transform2D(deg_to_rad(float(place_fill.get("rotation", 0.0))), Vector2.ZERO) * mirror * Transform2D(0.0, -_place_size() / 2.0)
	if snap_to_grid:
		xf.origin = snap_point(xf.origin)
	return xf

## The tiles a Place click puts down: cell of the piece -> [source id, atlas coords, 0] (with
## Random, one tile of the picked ones).
func place_tiles() -> Dictionary:
	var out: Dictionary = {}
	var sid := int(place_fill.get("source", -1))
	if not painter or sid < 0 or not painter.tile_set.has_source(sid):
		return out
	var region: Rect2i = place_fill.get("region", Rect2i())
	var tiles := painter.tiles_in(sid, region)
	if tiles.is_empty():
		return out
	if bool(place_fill.get("random", false)):
		if not _place_pick in tiles:
			_place_pick = tiles[_rng.randi_range(0, tiles.size() - 1)]
		out[Vector2i.ZERO] = [sid, _place_pick, 0]
		return out
	for t in tiles:
		out[t - region.position] = [sid, t, 0]
	return out

## Places the tiles picked in the palette as a free tile piece centred on [param at]
## (scene-local), at [member place_layer]'s depth, and selects it. Returns it (null when no
## tiles are picked).
func place_tiles_at(at: Vector2) -> TileMapLayer:
	var tiles := place_tiles()
	if tiles.is_empty():
		status_message.emit("Pick tiles in the tile palette first (drag over them): the Place tool puts them anywhere in the room, at any angle.")
		return null
	painter.checkpoint()
	var piece := painter.add_tile_piece(place_layer, tiles, place_transform(at))
	_place_pick = Vector2i(-1, -1)
	set_selection([piece])
	painted.emit()
	return piece

func _place_input(mb: InputEventMouseButton) -> void:
	var p := screen_to_local(mb.position)
	if not mb.pressed:
		if is_instance_valid(_place_drag):
			status_message.emit("%s placed at (%d, %d), turned %d°. The Select tool moves, turns and deletes it; R / Shift+R turn the next tiles." % [_place_drag.name, _place_drag.position.x, _place_drag.position.y, roundi(rad_to_deg(_place_drag.rotation))])
		_place_drag = null
		return
	if mb.shift_pressed:
		# Shift+click removes the free tiles under the mouse.
		var hit := painter.item_at(p)
		if hit and MDSRoomPainter.is_tile_piece(hit):
			painter.checkpoint()
			var n := hit.name
			painter.remove_item(hit)
			_clean_selection()
			painted.emit()
			status_message.emit("%s removed." % n)
		return
	var piece := place_tiles_at(p)
	if piece:
		_place_drag = piece
		_place_from = p
		_place_orig = piece.position

func _place_motion(mm: InputEventMouseMotion) -> void:
	if not is_instance_valid(_place_drag) or not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	# Dragging right after the click moves the new piece (the click's undo step covers it).
	_place_drag.position = _place_orig + _drag_delta(screen_to_local(mm.position) - _place_from)
	painter.dirty = true

## A move of [param d] px: whole pixels, or whole tiles with [member snap_to_grid].
func _drag_delta(d: Vector2) -> Vector2:
	if snap_to_grid:
		var ts := painter.tile_size()
		return (d / ts).round() * ts
	return d.round()

func _draw_place_overlay(ci: CanvasItem, color: Color) -> void:
	if not get_rect().has_point(_mouse) or is_instance_valid(_place_drag) or _panning:
		return
	var tiles := place_tiles()
	if tiles.is_empty():
		return
	var src := painter.tile_set.get_source(int(place_fill.source)) as TileSetAtlasSource
	var ts := painter.tile_size()
	ci.draw_set_transform_matrix(Transform2D(Vector2(zoom, 0), Vector2(0, zoom), pan) * place_transform(screen_to_local(_mouse)))
	for c: Vector2i in tiles:
		ci.draw_texture_rect_region(src.texture, Rect2(Vector2(c) * ts, ts), src.get_tile_texture_region(tiles[c][1]), Color(1, 1, 1, 0.7))
	ci.draw_rect(Rect2(Vector2.ZERO, _place_size()), color, false, 1.5 / zoom)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# --- Select: picking and moving tiles and items ---------------------------------------------------

## Selects [param nodes] (items) and [param cells] (layer name -> Array of cells), replacing the
## selection.
func set_selection(nodes: Array, cells: Dictionary = {}) -> void:
	selection.clear()
	for n in nodes:
		if is_instance_valid(n) and not n in selection:
			selection.append(n)
	selected_cells.clear()
	for layer_name in cells:
		var d: Dictionary = {}
		for c in cells[layer_name]:
			d[c] = true
		if not d.is_empty():
			selected_cells[layer_name] = d
	picked_changed.emit()
	_overlay.queue_redraw()

## How many items and grid tiles are selected.
func selection_counts() -> Vector2i:
	var cells := 0
	for layer_name in selected_cells:
		cells += selected_cells[layer_name].size()
	return Vector2i(selection.size(), cells)

func has_selection() -> bool:
	_clean_selection()
	return not selection.is_empty() or not selected_cells.is_empty()

## Drops from the selection what undo or a delete took out of the room.
func _clean_selection() -> void:
	if not painter:
		selection.clear()
		selected_cells.clear()
		return
	var before := selection_counts()
	selection.assign(selection.filter(func(n: Variant) -> bool: return is_instance_valid(n) and painter.items_root.is_ancestor_of(n)))
	for layer_name in selected_cells.keys():
		var l: TileMapLayer = painter.layers[layer_name]
		for c in selected_cells[layer_name].keys():
			if l.get_cell_source_id(c) == -1:
				selected_cells[layer_name].erase(c)
		if selected_cells[layer_name].is_empty():
			selected_cells.erase(layer_name)
	if selection_counts() != before:
		picked_changed.emit()

func _pickable(node: Node) -> bool:
	if pick_layer == PickLayer.ALL or pick_layer == PickLayer.ITEMS:
		return true
	return MDSRoomPainter.is_tile_piece(node) and MDSRoomPainter.piece_layer(node) in PICK_LAYERS[pick_layer]

## What a click at [param p] (scene-local) picks: {item} or {layer, cell} ({} for nothing): the
## top-most of the items and the grid tiles of the layers [member pick_layer] picks.
func pick_at(p: Vector2) -> Dictionary:
	var best := {}
	var best_z := 0
	for node in painter.pickable_items():
		if _pickable(node) and MDSRoomPainter.item_contains(node, p):
			var z: int = (node.get_parent() as Node2D).z_index + node.z_index
			if best.is_empty() or z >= best_z:
				best = {"item": node}
				best_z = z
	for layer_name in PICK_LAYERS[pick_layer]:
		var l: TileMapLayer = painter.layers[layer_name]
		var c := painter.cell_at(layer_name, p)
		if l.get_cell_source_id(c) != -1 and (best.is_empty() or l.z_index > best_z):
			best = {"layer": layer_name, "cell": c}
			best_z = l.z_index
	return best

func _is_picked(pick: Dictionary) -> bool:
	if pick.has("item"):
		return pick.item in selection
	return selected_cells.get(pick.layer, {}).has(pick.cell)

## Adds [param pick] (from [method pick_at]) to the selection, or takes it out.
func _toggle_pick(pick: Dictionary, on: bool) -> void:
	if pick.has("item"):
		if on and not pick.item in selection:
			selection.append(pick.item)
		elif not on:
			selection.erase(pick.item)
	else:
		if on:
			if not selected_cells.has(pick.layer):
				selected_cells[pick.layer] = {}
			selected_cells[pick.layer][pick.cell] = true
		elif selected_cells.has(pick.layer):
			selected_cells[pick.layer].erase(pick.cell)
			if selected_cells[pick.layer].is_empty():
				selected_cells.erase(pick.layer)
	picked_changed.emit()

## Selects what lies in [param box] (scene-local): items whose middle is in it, and grid tiles
## whose cell's middle is. With [param add], the selection keeps what it had.
func select_box(box: Rect2, add := false) -> void:
	box = box.abs()
	var nodes: Array = selection.duplicate() if add else []
	var cells: Dictionary = {}
	if add:
		for layer_name in selected_cells:
			cells[layer_name] = selected_cells[layer_name].keys()
	for node in painter.pickable_items():
		if _pickable(node) and not node in nodes and box.has_point(MDSGeometry.bounds(MDSRoomPainter.item_outline(node)).get_center()):
			nodes.append(node)
	for layer_name in PICK_LAYERS[pick_layer]:
		var l: TileMapLayer = painter.layers[layer_name]
		var lo := painter.cell_at(layer_name, box.position)
		var hi := painter.cell_at(layer_name, box.end)
		var list: Array = cells.get(layer_name, [])
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector2i(x, y)
				if l.get_cell_source_id(c) != -1 and box.has_point(painter.cell_rect(layer_name, c).get_center()) and not c in list:
					list.append(c)
		if not list.is_empty():
			cells[layer_name] = list
	set_selection(nodes, cells)
	_report_selection()

func _report_selection() -> void:
	var n := selection_counts()
	if n == Vector2i.ZERO:
		status_message.emit("Nothing selected. Click tiles, free tiles, stamps, pictures or shapes (Shift adds), or drag a box around them.")
		return
	var parts: PackedStringArray = []
	if n.y > 0:
		parts.append("%d tile(s)" % n.y)
	if n.x > 0:
		parts.append("%d item(s)" % n.x)
	status_message.emit("%s selected: drag to move %s (%s), R / Shift+R turn, the arrows nudge, Delete removes." % [" and ".join(parts), "them" if n.x + n.y > 1 else "it", "by whole tiles" if snap_to_grid else "by pixels"])

## The selection's bounds (scene-local).
func selection_bounds() -> Rect2:
	var b := Rect2()
	var first := true
	for node in selection:
		var r := MDSGeometry.bounds(MDSRoomPainter.item_outline(node))
		b = r if first else b.merge(r)
		first = false
	for layer_name in selected_cells:
		for c in selected_cells[layer_name]:
			var r := painter.cell_rect(layer_name, c)
			b = r if first else b.merge(r)
			first = false
	return b

## Takes the selected grid tiles off the grid, into free tile pieces (one per layer) that join the
## selection, so they can move by pixels and turn. Call [method MDSRoomPainter.checkpoint] first.
func _lift_selected_cells() -> void:
	for layer_name in selected_cells:
		var piece := painter.lift_cells(layer_name, selected_cells[layer_name].keys())
		if piece:
			selection.append(piece)
			_lifted.append(piece)
	selected_cells.clear()

## Puts the tiles lifted for a move or turn back on the grid where they line up with it again.
## Returns how many of them stay off the grid.
func _settle_lifted() -> int:
	var off := 0
	var cells: Dictionary = {}
	for piece in _lifted:
		if not is_instance_valid(piece):
			continue
		if painter.is_piece_on_grid(piece):
			var layer_name := MDSRoomPainter.piece_layer(piece)
			if not cells.has(layer_name):
				cells[layer_name] = []
			cells[layer_name].append_array(painter.merge_piece(piece))
			selection.erase(piece)
		else:
			off += piece.get_used_cells().size()
	_lifted.clear()
	for layer_name in cells:
		if not selected_cells.has(layer_name):
			selected_cells[layer_name] = {}
		for c in cells[layer_name]:
			selected_cells[layer_name][c] = true
	picked_changed.emit()
	return off

func _begin_move() -> void:
	painter.checkpoint()
	_lift_selected_cells()
	_sel_orig.clear()
	for node in selection:
		_sel_orig[node] = node.position
	_sel_moved = true

func _move_to(d: Vector2) -> void:
	var step := _drag_delta(d)
	for node in selection:
		if _sel_orig.has(node):
			node.position = _sel_orig[node] + step
	painter.dirty = true

func _finish_move() -> void:
	var d := Vector2.ZERO
	if not selection.is_empty() and _sel_orig.has(selection[0]):
		d = selection[0].position - _sel_orig[selection[0]]
	var off := _settle_lifted()
	_sel_orig.clear()
	_sel_moved = false
	painted.emit()
	status_message.emit("Moved the selection by (%d, %d) px.%s Ctrl+Z undoes it." % [d.x, d.y, " %d tile(s) left the grid: they are free tiles now (Select > To grid puts them back)." % off if off > 0 else ""])

## Moves the selection by [param d] px (whole tiles with [member snap_to_grid]), as one undo step.
func move_selection(d: Vector2) -> void:
	if not has_selection():
		return
	_begin_move()
	_move_to(d)
	_finish_move()

## Turns the selection [param degrees] clockwise around its middle (with [member snap_to_grid],
## around the nearest grid corner, so tiles turned in right angles stay on the grid). Grid tiles
## turned off the grid become free tiles; freeform shapes turn their points.
func rotate_selection(degrees: float) -> void:
	if not has_selection():
		return
	painter.checkpoint()
	_lift_selected_cells()
	var pivot := selection_bounds().get_center()
	if snap_to_grid:
		pivot = snap_point(pivot)
	var xf := Transform2D(0.0, pivot) * Transform2D(deg_to_rad(degrees), Vector2.ZERO) * Transform2D(0.0, -pivot)
	for node in selection:
		if node is MDSFreeform:
			var f := node as MDSFreeform
			var pts := PackedVector2Array()
			for q in f.points:
				pts.append(xf * (q + f.position) - f.position)
			f.points = pts
		else:
			node.transform = xf * node.transform
	var off := _settle_lifted()
	painter.dirty = true
	painted.emit()
	status_message.emit("Turned the selection %d°.%s Ctrl+Z undoes it." % [roundi(degrees), " %d tile(s) left the grid: they are free tiles now." % off if off > 0 else ""])

## Removes the selected tiles and items.
func delete_selection() -> void:
	if not has_selection():
		return
	painter.checkpoint()
	var n := selection_counts()
	for layer_name in selected_cells:
		painter.erase(layer_name, selected_cells[layer_name].keys())
	for node in selection:
		painter.remove_item(node)
	set_selection([])
	painted.emit()
	status_message.emit("Removed %d tile(s) and %d item(s). Ctrl+Z undoes it." % [n.y, n.x])

## Puts the selected free tiles back on their layer's grid (turned to the nearest right angle).
## Returns how many tiles went back.
func merge_selection_to_grid() -> int:
	_clean_selection()
	var pieces := selection.filter(func(node: Node2D) -> bool: return MDSRoomPainter.is_tile_piece(node))
	if pieces.is_empty():
		status_message.emit("Select free tiles first (tiles placed with Place, or moved off the grid).")
		return 0
	painter.checkpoint()
	var cells: Dictionary = {}
	for layer_name in selected_cells:
		cells[layer_name] = selected_cells[layer_name].keys()
	var n := 0
	for piece in pieces:
		var layer_name := MDSRoomPainter.piece_layer(piece)
		var written := painter.merge_piece(piece)
		n += written.size()
		if not cells.has(layer_name):
			cells[layer_name] = []
		cells[layer_name].append_array(written)
	set_selection(selection.filter(func(node: Node2D) -> bool: return not node in pieces), cells)
	painted.emit()
	status_message.emit("Put %d free tile(s) back on the grid. Ctrl+Z undoes it." % n)
	return n

func _select_input(mb: InputEventMouseButton) -> void:
	var p := screen_to_local(mb.position)
	if mb.pressed:
		_clean_selection()
		_sel_from = p
		_sel_to = p
		_sel_moved = false
		_sel_add = mb.shift_pressed or mb.ctrl_pressed or mb.meta_pressed
		var pick := pick_at(p)
		if pick.is_empty():
			if not _sel_add:
				set_selection([])
			_sel_drag = 1
			return
		if _sel_add and _is_picked(pick):
			_toggle_pick(pick, false)
			_sel_drag = 0
			_report_selection()
			return
		_sel_pick = {}
		if not _is_picked(pick):
			if _sel_add:
				_toggle_pick(pick, true)
			elif pick.has("item"):
				set_selection([pick.item])
			else:
				set_selection([], {pick.layer: [pick.cell]})
		elif not _sel_add:
			_sel_pick = pick
		_sel_drag = 2
		_report_selection()
		return
	if _sel_drag == 1:
		select_box(Rect2(_sel_from, _sel_to - _sel_from), _sel_add)
	elif _sel_drag == 2 and _sel_moved:
		_finish_move()
	elif _sel_drag == 2 and not _sel_pick.is_empty() and selection_counts().x + selection_counts().y > 1:
		# A click (no drag) on one of several selected things selects only it.
		if _sel_pick.has("item"):
			set_selection([_sel_pick.item])
		else:
			set_selection([], {_sel_pick.layer: [_sel_pick.cell]})
		_report_selection()
	_sel_pick = {}
	_sel_drag = 0

func _select_motion(mm: InputEventMouseMotion) -> void:
	if _sel_drag == 0 or not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	var p := screen_to_local(mm.position)
	_sel_to = p
	if _sel_drag == 2:
		if not _sel_moved:
			if (p - _sel_from).length() * zoom < 3.0:
				return
			_begin_move()
		_move_to(p - _sel_from)

func _draw_select_overlay(ci: CanvasItem, color: Color) -> void:
	_clean_selection()
	for node in selection:
		var pts := PackedVector2Array()
		for q in MDSRoomPainter.item_outline(node):
			pts.append(local_to_screen(q))
		if pts.size() >= 2:
			pts.append(pts[0])
			ci.draw_polyline(pts, Color.BLACK, 3.5, true)
			ci.draw_polyline(pts, color, 1.5, true)
	for layer_name in selected_cells:
		_draw_cells(ci, selected_cells[layer_name].keys(), Color(color, 0.8))
	if _sel_drag == 1:
		var r := Rect2(local_to_screen(_sel_from), (_sel_to - _sel_from) * zoom).abs()
		ci.draw_rect(r, Color(color, 0.08))
		ci.draw_rect(r, color, false, 1.0)
	elif _sel_drag == 0 and tool == Tool.SELECT and get_rect().has_point(_mouse) and not _panning:
		# What a click would pick.
		var pick := pick_at(screen_to_local(_mouse))
		if pick.has("item") and not pick.item in selection:
			var pts := PackedVector2Array()
			for q in MDSRoomPainter.item_outline(pick.item):
				pts.append(local_to_screen(q))
			if pts.size() >= 2:
				pts.append(pts[0])
				ci.draw_polyline(pts, Color(color, 0.45), 1.0, true)
		elif pick.has("cell"):
			var r := painter.cell_rect(pick.layer, pick.cell)
			ci.draw_rect(Rect2(local_to_screen(r.position), r.size * zoom), Color(color, 0.45), false, 1.0)

# --- Effects ----------------------------------------------------------------------------------

## Whether [param e] is still one of the room's effects. Undo remakes them and frees the ones it
## takes out, so [param e] may be a freed one (the selection): it is checked before its type.
func _is_room_effect(e: Variant) -> bool:
	return is_instance_valid(e) and e is MDSEnvironmentEffect and painter != null and (e as Node).get_parent() == painter.items_root.get_node(MDSRoomPainter.EFFECTS_GROUP)

## Places an effect of [param id] centred on [param p] (scene-local), selects it and returns it.
func place_effect(id: String, p: Vector2) -> MDSEnvironmentEffect:
	if not painter or id.is_empty():
		return null
	painter.checkpoint()
	var e := painter.add_effect(id, p)
	if not e:
		return null
	selected_effect = e
	painted.emit()
	_overlay.queue_redraw()
	status_message.emit("%s added. Drag it to move it, drag its corner to resize it; its settings are in the Inspector. Delete removes it. To place another, pick it again (or Ctrl+click to keep it picked)." % MDSEnvironment.display_name(id))
	return e

func delete_selected_effect() -> void:
	if _is_room_effect(selected_effect):
		painter.checkpoint()
		var n := selected_effect.name
		painter.remove_item(selected_effect)
		selected_effect = null
		painted.emit()
		status_message.emit("Effect %s removed." % n)

## An effect's area on screen.
func _effect_screen_rect(e: MDSEnvironmentEffect) -> Rect2:
	var r := e.transform * e.get_effect_rect()
	return Rect2(local_to_screen(r.position), r.size * zoom)

## Picks the effect a click places ("" for none: clicks select, move and resize).
func set_effect_pick(id: String) -> void:
	if id != effect_id:
		effect_id = id
		effect_pick_changed.emit(id)
	_overlay.queue_redraw()

func _begin_effect_drag(kind: int, p: Vector2, checkpointed: bool) -> void:
	_effect_drag = kind
	_effect_from = p
	_effect_orig = Rect2(selected_effect.position, selected_effect.size)
	_effect_moved = false
	_effect_checkpointed = checkpointed

func _effect_input(mb: InputEventMouseButton) -> void:
	var p := screen_to_local(mb.position)
	if not mb.pressed:
		if _effect_drag != 0 and _is_room_effect(selected_effect):
			if not _effect_moved and _effect_cycle:
				# A click (no drag) on the selected effect: the next one under the mouse, for
				# effects stacked on each other (most cover the whole room).
				var hits := painter.effects_at(p)
				if hits.size() > 1:
					selected_effect = hits[(hits.find(selected_effect) + 1) % hits.size()]
					status_message.emit("%s selected (one of %d effects here: click again for the next)." % [selected_effect.name, hits.size()])
			elif _effect_moved:
				status_message.emit("%s: %d x %d px at (%d, %d)." % [selected_effect.name, selected_effect.size.x, selected_effect.size.y, selected_effect.position.x, selected_effect.position.y])
		_effect_drag = 0
		_effect_cycle = false
		return
	if _is_room_effect(selected_effect) and _effect_screen_rect(selected_effect).end.distance_to(mb.position) <= 10.0:
		_begin_effect_drag(2, p, false)
		return
	# An effect picked in the list: a click places it (dragging right away moves it), then clicks
	# select and drag again, the new one too. Ctrl+click keeps the effect picked, to place several;
	# Shift+click selects instead of placing.
	if not effect_id.is_empty() and not mb.shift_pressed:
		var placed := place_effect(effect_id, p)
		if placed:
			_begin_effect_drag(1, p, true)
			if not (mb.ctrl_pressed or mb.meta_pressed):
				set_effect_pick("")
		return
	var hits := painter.effects_at(p)
	if hits.is_empty():
		selected_effect = null
		status_message.emit("Drag an effect from the list onto the room, or pick one and click.")
		return
	# The selected effect keeps the mouse when it is under it (to drag it); else the top-most.
	_effect_cycle = _is_room_effect(selected_effect) and hits.has(selected_effect)
	if not _effect_cycle:
		selected_effect = hits[0]
		status_message.emit("%s selected (its settings are in the Inspector): drag to move it, drag its corner to resize it, Delete removes it.%s" % [selected_effect.name, " Click it again for the next of the %d effects here." % hits.size() if hits.size() > 1 else ""])
	_begin_effect_drag(1, p, false)

func _effect_motion(mm: InputEventMouseMotion) -> void:
	if _effect_drag == 0 or not _is_room_effect(selected_effect) or not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	var d := screen_to_local(mm.position) - _effect_from
	if not _effect_moved and d.length() * zoom < 3.0:
		return
	if not _effect_checkpointed:
		# The undo step is taken when it starts moving, so a click alone adds none.
		painter.checkpoint()
		_effect_checkpointed = true
	_effect_moved = true
	if _effect_drag == 1:
		selected_effect.position = (_effect_orig.position + d).round()
	else:
		# The corner follows the mouse; an effect standing on its position (a vent) grows
		# out from it both ways.
		var along := selected_effect.transform.basis_xform_inv(d)
		var grow := along if selected_effect.get_effect_rect().position == Vector2.ZERO else Vector2(along.x * 2.0, -along.y)
		selected_effect.size = (_effect_orig.size + grow).max(Vector2(16, 16)).round()
	painter.dirty = true

func _draw_effects(ci: CanvasItem, font: Font) -> void:
	if not painter:
		return
	var active := tool == Tool.EFFECT
	for e in painter.effects():
		var r := _effect_screen_rect(e)
		var sel: bool = e == selected_effect
		var c := Color(0.55, 0.85, 1.0, 0.9 if sel else (0.55 if active else 0.2))
		ci.draw_rect(r, c, false, 2.0 if sel else 1.0)
		if active or sel:
			ci.draw_string_outline(font, r.position + Vector2(4, 14), String(e.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
			ci.draw_string(font, r.position + Vector2(4, 14), String(e.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
		if sel:
			ci.draw_rect(Rect2(r.end - Vector2(5, 5), Vector2(10, 10)), Color(0.55, 0.85, 1.0))
	if active and get_rect().has_point(_mouse) and not effect_id.is_empty() and _effect_drag == 0:
		var icon := MDSEnvironment.icon(effect_id)
		if icon:
			ci.draw_texture_rect(icon, Rect2(_mouse + Vector2(10, 10), Vector2(16, 16)), false)

## Shows the room's weather over the view (its own, else its area's, else the world's), as
## the game adds it. It is only a preview: nothing is saved into the scene.
func refresh_weather() -> void:
	_refresh_parallax()
	_refresh_background()
	var spec := ""
	if weather_preview and world and painter and world.has_room(room_id):
		spec = MDSEnvironment.spec_for_room(world, room_id)
	if spec == _weather_spec and (spec.is_empty() or MDSEnvironment.is_none(spec) or is_instance_valid(_weather)):
		return
	_weather_spec = spec
	if is_instance_valid(_weather):
		_weather.queue_free()
	_weather = null
	if spec.is_empty() or MDSEnvironment.is_none(spec):
		return
	var b := Rect2()
	var first := true
	for r in world.get_local_rects(room_id):
		b = r if first else b.merge(r)
		first = false
	_weather = MDSEnvironment.build(spec, b)
	if _weather:
		_weather.name = "WeatherPreview"
		_view.add_child(_weather)

## Shows the room's parallax background behind it, as the game adds it (not saved).
func _refresh_parallax() -> void:
	var value := ""
	if parallax_preview and world and painter and world.has_room(room_id):
		value = MDSEnvironment.parallax_for_room(world, room_id)
	if value == _parallax_value and (value.is_empty() or MDSEnvironment.is_none(value) or is_instance_valid(_parallax)):
		return
	_parallax_value = value
	if is_instance_valid(_parallax):
		_parallax.queue_free()
	_parallax = null
	if value.is_empty() or MDSEnvironment.is_none(value):
		return
	var b := Rect2()
	var first := true
	for r in world.get_local_rects(room_id):
		b = r if first else b.merge(r)
		first = false
	_parallax = MDSEnvironment.build_parallax(value, b)
	if _parallax:
		_parallax.name = "ParallaxPreview"
		_view.add_child(_parallax)
		_view.move_child(_parallax, 0)

## Shows the room's animated background behind it, as the game adds it (not saved).
func _refresh_background() -> void:
	var value := ""
	if parallax_preview and world and painter and world.has_room(room_id):
		value = MDSEnvironment.background_for_room(world, room_id)
	if value == _background_value and (value.is_empty() or MDSEnvironment.is_none(value) or is_instance_valid(_background)):
		return
	_background_value = value
	if is_instance_valid(_background):
		_background.queue_free()
	_background = null
	if value.is_empty() or MDSEnvironment.is_none(value):
		return
	var b := Rect2()
	var first := true
	for r in world.get_local_rects(room_id):
		b = r if first else b.merge(r)
		first = false
	_background = MDSEnvironment.build_background(value, b)
	if _background:
		var area := world.get_room_area(room_id)
		if not area.is_empty():
			MDSEnvironment.apply_area_color(_background, world.get_area_color(area))
		_background.name = "BackgroundPreview"
		_view.add_child(_background)
		_view.move_child(_background, 0)

## The animated background preview (null when the room has none).
func get_background_preview() -> Node2D:
	return _background if is_instance_valid(_background) else null

## The parallax background preview (null when the room has none).
func get_parallax_preview() -> Node2D:
	return _parallax if is_instance_valid(_parallax) else null

func set_parallax_preview(on: bool) -> void:
	parallax_preview = on
	_refresh_parallax()
	_refresh_background()

## The weather preview node (null when the room has none).
func get_weather_preview() -> Node2D:
	return _weather if is_instance_valid(_weather) else null

func set_weather_preview(on: bool) -> void:
	weather_preview = on
	refresh_weather()

# --- Dropping ----------------------------------------------------------------------------------

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not painter or not data is Dictionary:
		return false
	if data.get("type", "") == DRAG_EFFECT:
		return true
	if data.get("type", "") == "files":
		for f in data.get("files", []):
			if str(f).get_extension().to_lower() in IMAGE_EXTENSIONS:
				return true
	return false

## The background an image dropped at [param at] goes to (a parallax background, as a layer,
## or an animated one, as its picture): the selected one under the Effects tool, or the one
## under the mouse.
func _background_at(at: Vector2) -> MDSEnvironmentEffect:
	if tool != Tool.EFFECT:
		return null
	if _is_room_effect(selected_effect) and (selected_effect is MDSParallaxBackground or selected_effect is MDSAnimatedBackground):
		return selected_effect
	for hit in painter.effects_at(screen_to_local(at)):
		if hit is MDSParallaxBackground or hit is MDSAnimatedBackground:
			return hit
	return null

func _drop_data(at: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	if data.get("type", "") == DRAG_EFFECT:
		if before_effect_drop.is_valid():
			before_effect_drop.call()
		place_effect(str(data.effect), screen_to_local(at))
		return
	var target := _background_at(at)
	for f in data.get("files", []):
		if str(f).get_extension().to_lower() in IMAGE_EXTENSIONS:
			if target:
				var tex: Texture2D = load(str(f)) as Texture2D if ResourceLoader.exists(str(f)) else null
				if tex:
					painter.checkpoint()
					if target is MDSAnimatedBackground:
						var bg := target as MDSAnimatedBackground
						bg.style = MDSAnimatedBackground.Style.PICTURE
						bg.picture = tex
						status_message.emit("%s now shows %s, blurred (Blur, Size and the colors are in the Inspector)." % [target.name, str(f).get_file()])
					else:
						(target as MDSParallaxBackground).add_picture(tex)
						status_message.emit("%s added to %s as its nearest layer. Its settings are in the Inspector (layers)." % [str(f).get_file(), target.name])
					painter.dirty = true
					painted.emit()
				continue
			image_dropped.emit(str(f))
			return

## Image files dropped on the window from outside Godot, over this view.
func _on_files_dropped(files: PackedStringArray) -> void:
	if not painter or not is_visible_in_tree() or not get_global_rect().has_point(get_global_mouse_position()):
		return
	for f in files:
		if f.get_extension().to_lower() in IMAGE_EXTENSIONS:
			image_dropped.emit(f)
			return

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
		elif mb.button_index == MOUSE_BUTTON_LEFT and tool == Tool.EFFECT:
			grab_focus()
			_effect_input(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT and tool == Tool.PLACE:
			grab_focus()
			_place_input(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT and tool == Tool.SELECT:
			grab_focus()
			_select_input(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT and tool == Tool.FREEFORM and (shape == MDSTerrainShapes.Shape.BRUSH or freeform_mode == FreeformMode.EDIT):
			grab_focus()
			_freeform_input(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var cell := painter.cell_at("Terrain", screen_to_local(mb.position))
			if mb.pressed:
				grab_focus()
				if shape != MDSTerrainShapes.Shape.BRUSH:
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
				status_message.emit("%s shape painted (%d x %d tiles). Ctrl+Z undoes it." % [shape_name(shape), absi(_shape_to.x - _shape_from.x) + 1, absi(_shape_to.y - _shape_from.y) + 1])
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
		elif tool == Tool.EFFECT:
			_effect_motion(mm)
		elif tool == Tool.PLACE:
			_place_motion(mm)
		elif tool == Tool.SELECT:
			_select_motion(mm)
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
		if (tool == Tool.SELECT or tool == Tool.PLACE) and _selection_key(key):
			accept_event()
			_overlay.queue_redraw()
			return
		match event.keycode:
			KEY_ESCAPE:
				_shaping = false
				_draft.clear()
				_draft_freehand = false
				if tool == Tool.EFFECT:
					set_effect_pick("")
			KEY_ENTER, KEY_KP_ENTER:
				if tool == Tool.FREEFORM and _draft.size() >= 3:
					_finish_draft()
			KEY_BACKSPACE:
				if tool == Tool.FREEFORM and not _draft.is_empty():
					_draft.remove_at(_draft.size() - 1)
			KEY_DELETE:
				if tool == Tool.FREEFORM:
					delete_selected()
				elif tool == Tool.EFFECT:
					delete_selected_effect()
			KEY_BRACKETLEFT:
				brush_size = maxi(1, brush_size - 1)
			KEY_BRACKETRIGHT:
				brush_size = mini(12, brush_size + 1)
			KEY_F:
				fit()
		_overlay.queue_redraw()

## Keys of the Place and Select tools: R / Shift+R turn (the palette's tiles, or the selection),
## the arrows nudge the selection, Delete removes it, Esc clears it. Returns whether [param key]
## was one of them.
func _selection_key(key: InputEventKey) -> bool:
	if key.keycode == KEY_R and not key.ctrl_pressed and not key.alt_pressed:
		var deg := -turn_step if key.shift_pressed else turn_step
		if tool == Tool.PLACE:
			turn_requested.emit(deg)
		else:
			rotate_selection(deg)
		return true
	if tool != Tool.SELECT:
		return false
	var nudge := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
	if nudge.has(key.keycode):
		move_selection(nudge[key.keycode] * (painter.tile_size() if key.shift_pressed or snap_to_grid else Vector2.ONE))
		return true
	match key.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			delete_selection()
			return true
		KEY_ESCAPE:
			_sel_drag = 0
			set_selection([])
			return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _overlay:
		_overlay.queue_redraw()
		_update_depth_view()
	elif what == NOTIFICATION_ENTER_TREE:
		if not get_window().files_dropped.is_connected(_on_files_dropped):
			get_window().files_dropped.connect(_on_files_dropped)
	elif what == NOTIFICATION_EXIT_TREE:
		var w := get_window()
		if w and w.files_dropped.is_connected(_on_files_dropped):
			w.files_dropped.disconnect(_on_files_dropped)
