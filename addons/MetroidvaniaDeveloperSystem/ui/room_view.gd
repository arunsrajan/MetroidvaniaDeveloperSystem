@tool
class_name MDSRoomView
extends HBoxContainer
## Room view (the "actual view" next to the map view): paint a room scene's terrain,
## background and decorations with brushes or shapes (rectangles, irregular blobs, curved
## sides), or generate a starting cave from the room's shape on the map. Fills come from
## the tileset's terrains and tagged kinds, tiles picked in the palette (spritesheets), or
## solid colors. Saving writes the tiles into the scene; the map's silhouette follows.
##
## The Effects tool places environment effects (rain, dust storms, steam vents, lava,
## waterfalls...) by dragging them from its list onto the room, and shows the weather of the
## room's area over it. Trace drawing turns a picture of the room into freeform shapes.
##
## Its buttons are in [member controls], a narrow column that Map Dev puts in its left
## tool panel, and Map Dev shows the [member palette] as a tab. Used on its own, the view
## shows the column on its left and the palette on its right.

signal saved(scene_path: String)
signal status_message(text: String)
## The Tile palette button was pressed while the palette lives elsewhere (Map Dev shows it
## as a tab).
signal palette_requested
## The area bar asks for another room of the area.
signal room_requested(room_id: String)
## Generate caves in all the rooms of [param area] ([param rooms]) was pressed.
signal area_caves_requested(area: String, rooms: Array[String])

const DEFAULT_TILESET := "res://idp_tiles/idp_cave_tileset.tres"
const Shape := MDSTerrainShapes.Shape
const TOOL_LAYERS: PackedStringArray = ["Terrain", "Background", "Decor", "Erase", "Foreground", "Freeform", "Stamps", "Effects"]
const FREEFORM_LAYERS: PackedStringArray = ["Terrain (solid)", "Background", "Foreground"]
const FREEFORM_GROUPS: PackedStringArray = ["Freeform", "FreeformBack", "FreeformFront"]
const STAMP_LAYERS: PackedStringArray = ["Behind terrain", "In front of terrain", "Foreground"]
const STAMP_GROUPS: PackedStringArray = ["StampsBack", "StampsFront", "StampsForeground"]

var canvas: MDSRoomCanvas
var palette: MDSTilePalette
var painter: MDSRoomPainter
var world: MDSWorld
var room_id := ""
var tool_buttons: Array[Button] = []
var fill_opt: OptionButton
var color_button: ColorPickerButton
var brush_spin: SpinBox
var shape_opt: OptionButton
var curve_opt: OptionButton
var count_spin: SpinBox
var rough_spin: SpinBox
var flip_check: CheckBox
var generate_button: Button
var undo_button: Button
var redo_button: Button
## The brush and action buttons, as a column for a side panel.
var controls: VBoxContainer
var _split: HSplitContainer
var _variation := 0
var _filling := false
var layer_opt: OptionButton ## freeform / stamp layer
var mode_opt: OptionButton ## freeform Draw / Edit
var role_opt: OptionButton ## freeform collision role
var repair_row: Control ## freeform Repair / Repair all
var size_spin: SpinBox ## stamp size
var _styles: Array[MDSFreeformStyle] = []
var _stamp_sets: Array[MDSStampSet] = []
var _shape_rows: Array[Control] = []
var _check_host: SubViewport
var _convert_dialog: MDSConvertDialog
var _decorate_dialog: MDSDecorateDialog
var _fill_style_opt: OptionButton
var _trace_dialog: MDSTraceDialog
## The Effects tool's list (drag an effect onto the room).
var effect_list: ItemList
var _effect_box: VBoxContainer
var no_effects_check: CheckBox
## What Generate cave makes besides terrain: background, decor, foreground, stamps, paths.
var generate_options := {"background": true, "decor": true, "foreground": true, "stamps": true, "paths": true}
var _area := ""
var _area_rooms: Array[String] = []
var _area_box: VBoxContainer
var _area_label: Label
var _weather_label: Label
## Shown while the room has cells pointing at tiles its tileset no longer has.
var broken_button: Button

## The Effects tool's list: dragging an entry onto the room places that effect.
class EffectList extends ItemList:
	func _get_drag_data(at_position: Vector2) -> Variant:
		var i := get_item_at_position(at_position, true)
		if i < 0:
			return null
		if get_viewport() and get_viewport().gui_is_dragging():
			var preview := HBoxContainer.new()
			var icon := TextureRect.new()
			icon.texture = get_item_icon(i)
			preview.add_child(icon)
			var l := Label.new()
			l.text = get_item_text(i)
			preview.add_child(l)
			set_drag_preview(preview)
		if str(get_item_metadata(i)).is_empty():
			return null
		return {"type": MDSRoomCanvas.DRAG_EFFECT, "effect": str(get_item_metadata(i))}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls = VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# What to paint.
	var tool_grid := MDSSidePanel.grid(controls, 2)
	var group := ButtonGroup.new()
	var names := ["Terrain", "Background", "Decor", "Erase", "Foreground", "Freeform", "Stamps", "Effects"]
	var tips := ["Paint the Terrain layer (solid ground: autotiled terrain, palette tiles or colors)", "Paint the Background layer (foliage, palette tiles or a solid color)", "Paint the Decor layer (grass, vines, stalactites, palette tiles...)", "Erase the top item under the brush: a stamp, else foreground, decoration, terrain, then background (palette tiles and colors too). Pick one layer or all layers in the list next to it; Shift erases background only. Works with shapes too, to carve curved caves",
		"Paint the Foreground layer, drawn in front of everything (dark silhouettes framing the room)",
		"Freeform terrain: smooth curvy shapes instead of tiles (rounded ledges, bulging moss walls), with textured edges, clumps and exact collision. Draw by clicking points or dragging freehand, or pick a shape and drag its box. Edit mode reshapes them",
		"Place large clumps freely (moss bubbles, leaves, ferns, hanging moss, background bubbles, foreground silhouettes). Click or drag; Shift removes",
		"Environment effects: rain, snow, dust storms, lightning, fog, steam vents, lava, waterfalls, water, light shafts, embers, fireflies, leaves, heat haze. Drag one from the list onto the room (or pick one and click), drag to move, drag the corner to resize; the selected effect's settings are in the Inspector. Delete removes it"]
	for i in names.size():
		var b := MDSUi.button(names[i], tips[i])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.pressed.connect(func() -> void: set_tool(i))
		tool_buttons.append(b)
		tool_grid.add_child(MDSSidePanel.fill(b))
	fill_opt = OptionButton.new()
	fill_opt.fit_to_longest_item = false
	fill_opt.clip_text = true
	fill_opt.tooltip_text = "What the current tool paints: a terrain (autotiled), random tiles of a kind, the tiles picked in the palette, or a solid color"
	fill_opt.item_selected.connect(_on_fill_selected)
	var fill_row := MDSSidePanel.field(controls, "Fill", fill_opt)
	layer_opt = OptionButton.new()
	layer_opt.tooltip_text = "Layer of new freeform shapes or stamps"
	layer_opt.item_selected.connect(_on_layer_selected)
	_shape_rows.append(MDSSidePanel.field(controls, "Layer", layer_opt))
	mode_opt = OptionButton.new()
	mode_opt.add_item("Draw", MDSRoomCanvas.FreeformMode.DRAW)
	mode_opt.add_item("Edit", MDSRoomCanvas.FreeformMode.EDIT)
	mode_opt.tooltip_text = "Draw: click points (or drag freehand) and click the first point, double-click or press Enter to close; or pick a shape below and drag its box.\nEdit: drag points, Alt+click removes one, double-click an edge adds one, drag inside to move, Delete removes the shape."
	mode_opt.item_selected.connect(func(idx: int) -> void:
		canvas.freeform_mode = mode_opt.get_item_id(idx)
		canvas._overlay.queue_redraw())
	_shape_rows.append(MDSSidePanel.field(controls, "Mode", mode_opt))
	role_opt = OptionButton.new()
	for i in MDSRoomCanvas.ROLE_CHOICE_NAMES.size():
		role_opt.add_item(MDSRoomCanvas.ROLE_CHOICE_NAMES[i], i)
	role_opt.tooltip_text = "Collision of new freeform shapes (and of the selected one in Edit mode): the style's role, terrain, a platform (one-way ledges are jumped up through), or a decoration that never collides. Dashed tops in Edit mode mark one-way shapes"
	role_opt.item_selected.connect(_on_role_selected)
	MDSSidePanel.field(controls, "Role", role_opt)
	var repair := MDSUi.button("Repair", "Untwist the selected shape: an outline that crosses itself has no fill and no collision. The largest part stays; other parts become shapes of their own; slivers go")
	repair.pressed.connect(repair_selected)
	var repair_all := MDSUi.button("Repair all", "Untwist every shape of the room whose outline crosses itself (drawn red)")
	repair_all.pressed.connect(repair_all_shapes)
	repair_row = MDSSidePanel.row(controls, [repair, repair_all])
	size_spin = SpinBox.new()
	size_spin.min_value = 20
	size_spin.max_value = 400
	size_spin.step = 10
	size_spin.value = 100
	size_spin.prefix = "Size"
	size_spin.suffix = "%"
	size_spin.tooltip_text = "Stamp size (each stamp also varies a little)"
	size_spin.value_changed.connect(func(v: float) -> void: canvas.stamp_scale = v / 100.0)
	controls.add_child(MDSSidePanel.fill(size_spin))
	_effect_box = VBoxContainer.new()
	controls.add_child(_effect_box)
	effect_list = EffectList.new()
	effect_list.custom_minimum_size.y = 230 * MDSUi.editor_scale()
	effect_list.fixed_icon_size = Vector2i(16, 16) * int(maxf(1.0, MDSUi.editor_scale()))
	effect_list.tooltip_text = "Drag an effect onto the room, or pick one and click in the room (each click places another; Shift+click selects one already there). No effect: clicks only select, move and resize effects"
	effect_list.add_item("No effect (select and move)")
	effect_list.set_item_metadata(0, "")
	effect_list.set_item_tooltip(0, "Place nothing: click an effect in the room to select it, drag it to move it, drag its corner to resize it")
	for id in MDSEnvironment.EFFECTS:
		effect_list.add_item(MDSEnvironment.display_name(id), MDSEnvironment.icon(id))
		effect_list.set_item_metadata(effect_list.item_count - 1, id)
		effect_list.set_item_tooltip(effect_list.item_count - 1, MDSEnvironment.describe(id))
	effect_list.item_selected.connect(func(i: int) -> void:
		canvas.effect_id = str(effect_list.get_item_metadata(i))
		if canvas.effect_id.is_empty():
			status_message.emit("No effect: click an effect in the room to select, move or resize it.")
		else:
			status_message.emit("Click in the room to place %s; each click places another (Shift+click selects one already there)." % effect_list.get_item_text(i)))
	effect_list.select(0)
	_effect_box.add_child(effect_list)
	var clear_effects := MDSUi.button("Remove all", "Remove every effect placed in this room (Ctrl+Z undoes it)")
	clear_effects.pressed.connect(remove_all_effects)
	no_effects_check = CheckBox.new()
	no_effects_check.text = "No effects here"
	no_effects_check.tooltip_text = "No weather or effects from the room's area (or the world) in this room: its weather is set to none (Inspect tab). Effects placed in the room itself stay"
	no_effects_check.toggled.connect(set_no_effects)
	MDSSidePanel.row(_effect_box, [clear_effects, no_effects_check])
	_effect_box.add_child(MDSUi.hint("Drag onto the room. Click one in the room to edit it in the Inspector; drag its corner to resize it. Drop an image on a parallax background to add it as a layer."))
	var weather_check := CheckBox.new()
	weather_check.text = "Show the area's weather"
	weather_check.button_pressed = true
	weather_check.tooltip_text = "Show the weather of the room's area (Areas tab > Weather), or of the room itself (Inspect tab), as the game adds it to every room of the area. Only a preview: it isn't saved into the scene"
	weather_check.toggled.connect(func(on: bool) -> void:
		canvas.set_weather_preview(on)
		_update_weather_label())
	_effect_box.add_child(weather_check)
	var parallax_check := CheckBox.new()
	parallax_check.text = "Show the parallax background"
	parallax_check.button_pressed = true
	parallax_check.tooltip_text = "Show the parallax background of the room's area (Areas tab > Parallax), or of the room itself, behind the room as the game adds it; pan the view to see it move. Only a preview: it isn't saved into the scene"
	parallax_check.toggled.connect(func(on: bool) -> void:
		canvas.set_parallax_preview(on)
		_update_weather_label())
	_effect_box.add_child(parallax_check)
	_weather_label = MDSUi.hint("")
	_effect_box.add_child(_weather_label)
	color_button = ColorPickerButton.new()
	color_button.color = Color("#0f2a2c")
	color_button.custom_minimum_size = Vector2(36, 0)
	color_button.tooltip_text = "Solid color painted by the \"Solid color\" fill"
	color_button.visible = false
	color_button.color_changed.connect(func(c: Color) -> void:
		if canvas.fills.get(canvas.tool, {}).get("type", "") == "color":
			canvas.fills[canvas.tool] = {"type": "color", "color": c})
	fill_row.add_child(color_button)
	brush_spin = SpinBox.new()
	brush_spin.min_value = 1
	brush_spin.max_value = 12
	brush_spin.value = 2
	brush_spin.prefix = "Brush"
	brush_spin.tooltip_text = "Brush size in tiles ([ and ] in the view)"
	brush_spin.value_changed.connect(func(v: float) -> void: canvas.brush_size = int(v))
	controls.add_child(MDSSidePanel.fill(brush_spin))
	# Shapes.
	shape_opt = OptionButton.new()
	for i in MDSTerrainShapes.SHAPE_NAMES.size():
		shape_opt.add_item(MDSTerrainShapes.SHAPE_NAMES[i], i)
		shape_opt.set_item_tooltip(i, MDSTerrainShapes.SHAPE_TIPS[i])
	shape_opt.tooltip_text = "Brush or shape. Shapes: drag a box in the view, release to paint it (Esc cancels)"
	shape_opt.item_selected.connect(func(idx: int) -> void:
		canvas.shape = shape_opt.get_item_id(idx)
		_update_shape_controls())
	MDSSidePanel.field(controls, "Shape", shape_opt)
	curve_opt = OptionButton.new()
	curve_opt.fit_to_longest_item = false
	curve_opt.clip_text = true
	for i in MDSTerrainShapes.CURVE_NAMES.size():
		curve_opt.add_item(MDSTerrainShapes.CURVE_NAMES[i], i)
	curve_opt.tooltip_text = "Curve of the curved side: convex bulges out, concave dips in; ramps rise along the side (Flip mirrors them)"
	curve_opt.item_selected.connect(func(idx: int) -> void:
		canvas.curve = curve_opt.get_item_id(idx)
		_update_shape_controls())
	MDSSidePanel.field(controls, "Curve", curve_opt)
	count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 12
	count_spin.value = 3
	count_spin.prefix = "x"
	count_spin.tooltip_text = "Number of waves, steps or spikes"
	count_spin.value_changed.connect(func(v: float) -> void: canvas.curve_count = int(v))
	rough_spin = SpinBox.new()
	rough_spin.min_value = 0
	rough_spin.max_value = 100
	rough_spin.step = 5
	rough_spin.value = 0
	rough_spin.prefix = "Irregular"
	rough_spin.suffix = "%"
	rough_spin.tooltip_text = "How rough and natural the shape's edge is (0 = clean curve)"
	rough_spin.value_changed.connect(func(v: float) -> void: canvas.roughness = v / 100.0)
	controls.add_child(MDSSidePanel.fill(rough_spin))
	flip_check = CheckBox.new()
	flip_check.text = "Flip"
	flip_check.tooltip_text = "Mirror the curve along the side (ramps rise the other way)"
	flip_check.toggled.connect(func(on: bool) -> void: canvas.mirror = on)
	MDSSidePanel.row(controls, [count_spin, flip_check])
	# Actions.
	controls.add_child(HSeparator.new())
	var generation := VBoxContainer.new()
	controls.add_child(generation)
	broken_button = MDSUi.button("Remove broken tiles", "Erase the painted tiles that point at tiles the tileset no longer has (their sheet was removed, or its tile size was made bigger so fewer tiles fit). They draw nothing and have no collision, and Godot logs \"The TileSetAtlasSource atlas has no tile at ...\" for them. Saving also rewrites the tileset without the tiles it can no longer load. Ctrl+Z undoes it")
	broken_button.visible = false
	broken_button.pressed.connect(remove_broken_tiles)
	generation.add_child(broken_button)
	var actions := MDSSidePanel.grid(controls, 2)
	_area_box = VBoxContainer.new()
	_area_box.visible = false
	generation.add_child(_area_box)
	_area_label = MDSUi.hint("")
	_area_box.add_child(_area_label)
	var prev := MDSUi.button("<", "The area's previous room")
	prev.pressed.connect(func() -> void: _area_step(-1))
	var next := MDSUi.button(">", "The area's next room")
	next.pressed.connect(func() -> void: _area_step(1))
	var area_caves := MDSUi.button("Caves for the area", "Generate a cave in every room of the area, with the fills and options here. Rooms without a scene get one. Every room's gates are joined by paths a player can walk, jump and climb both ways, so the whole area can be crossed and backtracked")
	area_caves.pressed.connect(func() -> void:
		if not _area.is_empty():
			area_caves_requested.emit(_area, _area_rooms))
	MDSSidePanel.row(_area_box, [prev, next, area_caves])
	var gen := MDSUi.button("Generate cave", "Replace the tiles with a cave built from the room's shape on the map: walls, floor, ledges, openings at its gates, paths between them, then background, decorations, foreground and stamps. Uses the fills picked for each layer (and the stamps picked for the Stamps tool), as the options below say")
	gen.pressed.connect(func() -> void: generate(false))
	generate_button = gen
	generation.add_child(gen)
	var again := MDSUi.button("New variation", "Generate again with another random layout")
	again.pressed.connect(func() -> void: generate(true))
	generation.add_child(again)
	var options := HFlowContainer.new()
	generation.add_child(options)
	for o in [["background", "Background", "Paint the Background fill behind the cave"], ["decor", "Decor", "Decorations on floors and under ceilings; most floor ones of the Decor fill"], ["foreground", "Foreground", "The Foreground fill in front: a solid color or a terrain darkens the rock deep in the walls; tiles hang from ceilings and edge floors"], ["stamps", "Stamps", "Stamps of the set and category picked for the Stamps tool along the floors"], ["paths", "Paths", "Every gate reaches every other one and back: tunnels and shafts with ledges are carved where the cave doesn't allow it"]]:
		var c := CheckBox.new()
		c.text = o[1]
		c.tooltip_text = o[2]
		c.button_pressed = true
		var key: String = o[0]
		c.toggled.connect(func(on: bool) -> void: generate_options[key] = on)
		options.add_child(c)
	var deco := MDSUi.button("Auto-decorate", "Redo grass, plants, vines, stalactites and moss on the current terrain (uses tiles tagged with those kinds)")
	deco.pressed.connect(func() -> void:
		if painter:
			painter.checkpoint()
			_variation += 1
			var n := painter.auto_decorate(hash(room_id) + _variation, true, painter.room_cells(world, room_id))
			_changed("Placed %d decorations." % n))
	generation.add_child(deco)
	var back := MDSUi.button("Fill background", "Fill the room's shape with the Background fill (foliage, palette tiles or a solid color)")
	back.pressed.connect(fill_background)
	generation.add_child(back)
	var convert := MDSUi.button("Convert to freeform...", "Turn the room's solid tiles, static bodies and straight-edged freeform shapes into organic freeform rock, keeping every doorway, platform top and floor under objects. Platforms become one-way ledges. Block a room out with rectangles or tiles, then make it organic")
	convert.pressed.connect(open_convert_dialog)
	generation.add_child(convert)
	var trace := MDSUi.button("Trace drawing...", "Draw the room from a picture: each color of a drawing (any image file, or drop one on the view) becomes freeform shapes of the style you pick. Black, grey and brown: terrain; red, orange and yellow: one-way platforms; green: background; blue and purple: foreground")
	trace.icon = load("res://addons/MetroidvaniaDeveloperSystem/assets/environment/trace.svg")
	trace.pressed.connect(func() -> void: open_trace_dialog())
	generation.add_child(trace)
	var decorate := MDSUi.button("Decorate freeform...", "Place scenery relative to the freeform rock: stamps hung under ceilings, plants along floors, background structures (columns, broken arches, garden walls, mounds, stalactites) on flat floors, and foreground leaves in free corners. Never over doorways or anything in the room; running it again replaces it")
	decorate.pressed.connect(open_decorate_dialog)
	generation.add_child(decorate)
	_fill_style_opt = OptionButton.new()
	_fill_style_opt.fit_to_longest_item = false
	_fill_style_opt.clip_text = true
	_fill_style_opt.tooltip_text = "Style of Fill outside shape (deep ground)"
	var outside := MDSUi.button("Fill outside shape", "Cover the cells of the room's box that are outside its shape on the map (its notches, which belong to neighbouring rooms) with non-solid shapes of the style picked next to it, drawn over the rock's edges. Run it again after changing the room's shape; the Room view also redoes it when it opens a room whose shape changed")
	outside.pressed.connect(fill_outside)
	MDSSidePanel.row(generation, [outside, _fill_style_opt])
	var check := MDSUi.button("Check room", "Load the room's terrain into an off-screen physics space and check it like a player would: every gate open, platforms landed on with headroom, objects on the ground, exits up reachable by jumping (World settings > Player). Problems are marked in the view")
	check.pressed.connect(check_room)
	var reach := CheckBox.new()
	reach.text = "Reachability"
	reach.button_pressed = true
	reach.tooltip_text = "After Check room, draw the floors the player can reach from the gates in green, the others in red"
	reach.toggled.connect(func(on: bool) -> void:
		canvas.show_reachability = on
		canvas._overlay.queue_redraw())
	MDSSidePanel.row(generation, [check, reach])
	var fit_props := MDSUi.button("Fit props to floor", "Stand every object that stands (save points, shops, NPCs, benches, spawn points: see the idp_stands group) on the floor under it, or lift it out of the ground it is sunk in, then step it along its floor out of any platform. Ctrl+Z undoes it")
	fit_props.pressed.connect(fit_props_to_floor)
	var declutter := MDSUi.button("Declutter", "Separate objects that stand in or behind each other: doors, machines and enemies stay; save points and shops, then everything else, step along their floor to the nearest clear spot. A decoration with nowhere to go is removed. Ctrl+Z undoes it")
	declutter.pressed.connect(declutter_room)
	MDSSidePanel.row(generation, [fit_props, declutter])
	var depth := CheckBox.new()
	depth.text = "2.5D preview"
	depth.tooltip_text = "Show the room as MDSDepth25D draws it in the game: walls and floors extruded toward the middle of the view, floors paved in perspective, lit from above (World settings > 2.5D turns it on in the game)"
	depth.toggled.connect(func(on: bool) -> void: canvas.set_depth_preview(on))
	generation.add_child(depth)
	var clear := MDSUi.button("Clear", "Remove all tiles, freeform shapes and stamps")
	clear.pressed.connect(func() -> void:
		if painter:
			painter.checkpoint()
			for n in MDSRoomPainter.LAYER_ORDER:
				painter.clear_layer(n)
			painter.clear_items()
			canvas.selected = null
			_changed("Cleared."))
	actions.add_child(MDSSidePanel.fill(clear))
	undo_button = MDSUi.button("Undo", "Undo the last stroke or shape (Ctrl+Z)")
	undo_button.pressed.connect(func() -> void:
		if painter and painter.undo():
			_changed("Undone."))
	actions.add_child(MDSSidePanel.fill(undo_button))
	redo_button = MDSUi.button("Redo", "Redo (Ctrl+Y)")
	redo_button.pressed.connect(func() -> void:
		if painter and painter.redo():
			_changed("Redone."))
	actions.add_child(MDSSidePanel.fill(redo_button))
	var save_btn := MDSUi.button("Save", "Write the tiles into the room scene")
	save_btn.pressed.connect(save)
	actions.add_child(MDSSidePanel.fill(save_btn))
	var revert := MDSUi.button("Revert", "Reload the scene, dropping unsaved painting")
	revert.pressed.connect(func() -> void:
		if painter:
			painter.dirty = false
			open_room(world, room_id))
	actions.add_child(MDSSidePanel.fill(revert))
	var edit := MDSUi.button("Edit in 2D", "Open the room scene in Godot's editor (saves first)")
	edit.pressed.connect(func() -> void:
		if painter:
			if painter.dirty:
				save()
			EditorInterface.open_scene_from_path(painter.scene_path))
	actions.add_child(MDSSidePanel.fill(edit))
	var palette_toggle := MDSUi.button("Tile palette", "Show the tile palette (spritesheets)")
	palette_toggle.pressed.connect(func() -> void:
		if palette.get_parent() == _split:
			palette.visible = not palette.visible
		else:
			palette_requested.emit())
	actions.add_child(MDSSidePanel.fill(palette_toggle))
	# View and palette.
	_split = HSplitContainer.new()
	_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_split)
	canvas = MDSRoomCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.painted.connect(func() -> void:
		canvas.check_result = {}
		canvas._overlay.queue_redraw())
	canvas.status_message.connect(func(t: String) -> void: status_message.emit(t))
	canvas.selection_changed.connect(func(f: MDSFreeform) -> void:
		if f and canvas.freeform_mode == MDSRoomCanvas.FreeformMode.EDIT:
			role_opt.select(MDSRoomCanvas.role_choice_of(f)))
	canvas.effect_selected.connect(_inspect_effect)
	canvas.image_dropped.connect(func(path: String) -> void: open_trace_dialog(path))
	canvas.before_effect_drop = func() -> void:
		if canvas.tool != MDSRoomCanvas.Tool.EFFECT:
			set_tool(MDSRoomCanvas.Tool.EFFECT)
	_split.add_child(canvas)
	palette = MDSTilePalette.new()
	palette.status_message.connect(func(t: String) -> void: status_message.emit(t))
	palette.selection_changed.connect(_on_palette_picked)
	palette.tileset_changed.connect(func() -> void:
		_fill_pickers(true)
		canvas._overlay.queue_redraw())
	_update_shape_controls()
	_update_tool_controls()

## Opens the room for painting. Returns an error message, or "" on success.
func open_room(p_world: MDSWorld, id: String) -> String:
	if painter and painter.dirty:
		save()
	close_room(false)
	world = p_world
	room_id = id
	var path := world.get_scene_path(id)
	if path.is_empty():
		return "%s has no scene." % id
	var tiles_path := str(world.get_setting("room_tileset", ""))
	var tiles := MDSTilesetFactory.get_or_create(tiles_path if not tiles_path.is_empty() else DEFAULT_TILESET)
	var moved := MDSRoomPainter.externalize_sheets(tiles) if tiles else 0
	if moved > 0:
		status_message.emit("Moved %d sheet image(s) embedded in %s out to PNG files next to it, so the tileset loads fast." % [moved, tiles.resource_path.get_file()])
	painter = MDSRoomPainter.open(path, tiles)
	if not painter:
		return "Could not open %s." % path
	canvas.open(world, id, painter)
	palette.set_painter(painter)
	_load_styles()
	_fill_pickers(true)
	_refresh_outside_fill()
	_update_weather_label()
	if not painter.has_terrains():
		status_message.emit("%s's tileset has no terrains: Generate cave paints with the Terrain fill (palette tiles or a solid color), or make a terrain from a 3x3 block in the palette." % id)
	no_effects_check.set_pressed_no_signal(MDSEnvironment.is_none(str(world.get_room_value(id, "weather", ""))))
	set_area("", [])
	_report_broken_tiles()
	_fit_later()
	return ""

func _ready() -> void:
	_adopt_controls.call_deferred()
	# Effects are edited in the Inspector: changes there are changes to the room.
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var inspector: Object = Engine.get_singleton(&"EditorInterface").get_inspector()
		if inspector and not inspector.property_edited.is_connected(_on_inspector_edited):
			inspector.property_edited.connect(_on_inspector_edited)

## Used on its own (not in Map Dev), the button column goes on the left of the view and
## the palette on its right.
func _adopt_controls() -> void:
	if palette and not palette.get_parent():
		_split.add_child(palette)
	if controls and not controls.get_parent():
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.x = MDSSidePanel.WIDTH * MDSUi.editor_scale()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(controls)
		add_child(scroll)
		move_child(scroll, 0)

func _fit_later() -> void:
	await get_tree().process_frame
	canvas.fit()

func _notification(what: int) -> void:
	# Panel going away with a room open: the displayed layers go with the tree, but the
	# off-tree scene instance must be freed here.
	if what == NOTIFICATION_PREDELETE:
		if painter and is_instance_valid(painter.root):
			painter.root.free()
		if is_instance_valid(controls) and not controls.get_parent():
			controls.free()
		if is_instance_valid(palette) and not palette.get_parent():
			palette.free()

func close_room(auto_save := true) -> void:
	if painter and painter.dirty and auto_save:
		save()
	canvas.close()
	if painter:
		painter.free_instance()
	painter = null
	palette.set_painter(null)

func save() -> Error:
	if not painter:
		return ERR_UNCONFIGURED
	var err := painter.save()
	if err == OK:
		saved.emit(painter.scene_path)
		status_message.emit("Saved %s." % painter.scene_path.get_file())
	elif not MDSWorldSceneTools.last_error.is_empty():
		status_message.emit(MDSWorldSceneTools.last_error)
	else:
		status_message.emit("Could not save %s (error %d)." % [painter.scene_path, err])
	canvas._overlay.queue_redraw()
	return err

func set_tool(t: int) -> void:
	canvas.tool = t
	tool_buttons[t].set_pressed_no_signal(true)
	_fill_pickers(false)
	_update_tool_controls()
	canvas._overlay.queue_redraw()
	canvas.grab_focus()

## Shows the controls the current tool uses.
func _update_tool_controls() -> void:
	var t := canvas.tool
	var freeform := t == MDSRoomCanvas.Tool.FREEFORM
	var stamps := t == MDSRoomCanvas.Tool.STAMP
	var effects := t == MDSRoomCanvas.Tool.EFFECT
	fill_opt.get_parent().visible = not effects
	_effect_box.visible = effects
	layer_opt.get_parent().visible = freeform or stamps
	mode_opt.get_parent().visible = freeform
	role_opt.get_parent().visible = freeform
	repair_row.visible = freeform
	_update_generator_shapes(freeform)
	size_spin.visible = stamps
	brush_spin.visible = not freeform and not stamps and not effects
	shape_opt.get_parent().visible = not stamps and not effects
	curve_opt.get_parent().visible = not stamps and not effects
	rough_spin.visible = not stamps and not effects
	flip_check.get_parent().visible = not stamps and not effects
	_filling = true
	layer_opt.clear()
	if freeform:
		for i in FREEFORM_LAYERS.size():
			layer_opt.add_item(FREEFORM_LAYERS[i], i)
		layer_opt.select(maxi(0, FREEFORM_GROUPS.find(canvas.freeform_group)))
	elif stamps:
		for i in STAMP_LAYERS.size():
			layer_opt.add_item(STAMP_LAYERS[i], i)
		layer_opt.select(maxi(0, STAMP_GROUPS.find(canvas.stamp_group)))
	_filling = false

## The Freeform tool's Shape list also offers the scenery generators (Column, Arch...).
func _update_generator_shapes(freeform: bool) -> void:
	var has := shape_opt.get_item_index(MDSRoomCanvas.GENERATOR_BASE) >= 0
	if freeform and not has:
		shape_opt.add_separator("Scenery")
		for i in MDSShapeGenerators.NAMES.size():
			shape_opt.add_item(MDSShapeGenerators.NAMES[i], MDSRoomCanvas.GENERATOR_BASE + i)
			shape_opt.set_item_tooltip(shape_opt.item_count - 1, MDSShapeGenerators.TIPS[i] + ". Drag its box")
	elif not freeform and has:
		for i in range(shape_opt.item_count - 1, -1, -1):
			if shape_opt.get_item_id(i) >= MDSRoomCanvas.GENERATOR_BASE or shape_opt.is_item_separator(i):
				shape_opt.remove_item(i)
		if canvas.shape >= MDSRoomCanvas.GENERATOR_BASE:
			canvas.shape = MDSTerrainShapes.Shape.BRUSH
			shape_opt.select(0)
			_update_shape_controls()

func _on_layer_selected(idx: int) -> void:
	if _filling:
		return
	if canvas.tool == MDSRoomCanvas.Tool.FREEFORM:
		canvas.freeform_group = FREEFORM_GROUPS[idx]
		canvas.freeform_solid = idx == 0
		if is_instance_valid(canvas.selected) and painter and canvas.freeform_mode == MDSRoomCanvas.FreeformMode.EDIT:
			# Edit mode: move the selected shape to that layer.
			painter.checkpoint()
			var node := canvas.selected
			node.get_parent().remove_child(node)
			node.solid = canvas.freeform_solid
			painter.items_root.get_node(canvas.freeform_group).add_child(node)
			painter.dirty = true
	elif canvas.tool == MDSRoomCanvas.Tool.STAMP:
		canvas.stamp_group = STAMP_GROUPS[idx]

func _on_role_selected(idx: int) -> void:
	canvas.freeform_role = role_opt.get_item_id(idx)
	if is_instance_valid(canvas.selected) and painter and canvas.freeform_mode == MDSRoomCanvas.FreeformMode.EDIT:
		painter.checkpoint()
		MDSRoomCanvas.apply_role_choice(canvas.selected, canvas.freeform_role)
		painter.dirty = true
		_changed("%s: %s." % [canvas.selected.name, MDSRoomCanvas.ROLE_CHOICE_NAMES[canvas.freeform_role]])

func repair_selected() -> void:
	if not painter:
		return
	var f := canvas.selected
	if not is_instance_valid(f):
		status_message.emit("Select a shape first (Freeform > Edit, click it), or press Repair all.")
		return
	if f.is_outline_simple():
		status_message.emit("%s's outline is fine: nothing to repair." % f.name)
		return
	painter.checkpoint()
	var parts := painter.repair_freeform(f)
	canvas.selected = parts[0] if not parts.is_empty() else null
	_changed("Repaired %s: %s." % [f.name if not parts.is_empty() else "the shape", "%d shape(s)" % parts.size() if not parts.is_empty() else "only slivers were left, so it was removed"])

func repair_all_shapes() -> void:
	if not painter:
		return
	if painter.twisted_freeforms().is_empty():
		status_message.emit("No shape of %s crosses itself." % room_id)
		return
	painter.checkpoint()
	var r := painter.repair_all()
	if not is_instance_valid(canvas.selected):
		canvas.selected = null
	_changed("Repaired %d shape(s) into %d; %d removed (slivers only). Ctrl+Z undoes it." % [r.repaired, r.shapes, r.removed])

## Runs the physics checks (MDSRoomCheck) on the room as painted, and marks what it finds.
func check_room() -> Array:
	if not painter or not world:
		return []
	var c := MDSRoomCheck.new(world.get_setting("player", {}))
	c.room_rects = world.get_local_rects(room_id)
	c.passages = MDSRoomCheck.passages_from_world(world, room_id)
	c.build_from_painter(painter, _host())
	var issues := c.run()
	canvas.check_result = {"issues": issues.duplicate(true), "surfaces": c.surfaces.duplicate(true)}
	c.free_proxy()
	canvas._overlay.queue_redraw()
	var reachable: int = canvas.check_result.surfaces.filter(func(s: Dictionary) -> bool: return s.reachable).size()
	if issues.is_empty():
		status_message.emit("%s passes the room checks: gates open, platforms clear, objects grounded, exits reachable (%d of %d floors reachable)." % [room_id, reachable, c.surfaces.size()])
	else:
		status_message.emit("%d problem(s): %s" % [issues.size(), "; ".join(issues.slice(0, 3).map(func(i: Dictionary) -> String: return i.message))])
	return issues

func _host() -> Node:
	if not _check_host:
		_check_host = SubViewport.new()
		_check_host.disable_3d = true
		_check_host.size = Vector2i(4, 4)
		_check_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_check_host)
	return _check_host

## Stands the room's standing objects on the floor (undoable). Returns how many moved.
func fit_props_to_floor() -> int:
	if not painter or not world:
		return 0
	var c := MDSRoomDressing.ground_check(_host(), painter.root, painter, world.get_local_rects(room_id))
	var edits := MDSRoomDressing.fit_to_floor(painter.root, c, painter)
	c.free_proxy()
	if edits.is_empty():
		status_message.emit("Every object that stands is on the floor already (or has no floor under it).")
		return 0
	painter.checkpoint()
	MDSRoomDressing.apply(edits, painter)
	canvas.refresh_scene_edits()
	_changed("Stood %d object(s) on the floor: %s. Ctrl+Z undoes it; Save keeps it." % [edits.size(), ", ".join(edits.map(func(e: Dictionary) -> String: return String(e.node.name)))])
	return edits.size()

## Separates the room's objects that overlap (undoable). Returns the edits made.
func declutter_room() -> Array:
	if not painter or not world:
		return []
	var c := MDSRoomDressing.ground_check(_host(), painter.root, painter, world.get_local_rects(room_id))
	var edits := MDSRoomDressing.declutter(painter.root, c, painter)
	c.free_proxy()
	if edits.is_empty():
		status_message.emit("No objects stand in or behind each other.")
		return edits
	painter.checkpoint()
	MDSRoomDressing.apply(edits, painter)
	canvas.refresh_scene_edits()
	var moved := edits.filter(func(e: Dictionary) -> bool: return e.kind == "move").size()
	_changed("Decluttered: %d object(s) moved, %d decoration(s) with nowhere to go removed. Ctrl+Z undoes it; Save keeps it." % [moved, edits.size() - moved])
	return edits

func open_convert_dialog() -> void:
	if not painter:
		return
	if not _convert_dialog:
		_convert_dialog = MDSConvertDialog.new()
		add_child(_convert_dialog)
	_convert_dialog.open(self, _styles, canvas.freeform_style)

func open_decorate_dialog() -> void:
	if not painter:
		return
	if not _decorate_dialog:
		_decorate_dialog = MDSDecorateDialog.new()
		add_child(_decorate_dialog)
	_decorate_dialog.open(self, _styles, _stamp_sets)

## Opens Trace drawing for the room, with the drawing at [param path] if given.
func open_trace_dialog(path := "") -> void:
	if not painter:
		status_message.emit("Open a room first (double-click it on the map), then trace a drawing into it.")
		return
	if not _trace_dialog:
		_trace_dialog = MDSTraceDialog.new()
		add_child(_trace_dialog)
	_trace_dialog.open(self, _styles, path)

## Status after Trace drawing (or its preview).
func report_trace(r: Dictionary, preview: bool) -> void:
	canvas.selected = null
	if not str(r.get("error", "")).is_empty():
		_changed(r.error)
		return
	var parts: PackedStringArray = []
	var kinds := {"terrain": "terrain shape(s)", "platform": "one-way platform(s)", "background": "background shape(s)", "foreground": "foreground shape(s)"}
	for k in kinds:
		if int(r.get(k, 0)) > 0:
			parts.append("%d %s" % [r[k], kinds[k]])
	var text := "%s %s%s." % ["Preview:" if preview else "Traced the drawing into %s:" % room_id, ", ".join(parts) if not parts.is_empty() else "nothing", ", %d earlier traced shape(s) replaced" % r.removed if int(r.get("removed", 0)) > 0 else ""]
	if not preview:
		text += " Ctrl+Z undoes it; Check room checks it."
	_changed(text)

## The selected effect goes to the Inspector.
func _inspect_effect(e: MDSEnvironmentEffect) -> void:
	canvas._overlay.queue_redraw()
	if e and Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").inspect_object(e, "", true)

func _on_inspector_edited(_property: String) -> void:
	if not painter or not is_instance_valid(canvas.selected_effect):
		return
	var inspector: Object = Engine.get_singleton(&"EditorInterface").get_inspector()
	if inspector.get_edited_object() == canvas.selected_effect:
		painter.dirty = true
		canvas._overlay.queue_redraw()

## Shows the weather of the room (its own or its area's) again, after it changed.
func refresh_weather() -> void:
	canvas.refresh_weather()
	_update_weather_label()

func _update_weather_label() -> void:
	if not _weather_label:
		return
	var spec := MDSEnvironment.spec_for_room(world, room_id) if world and world.has_room(room_id) else ""
	var text := ""
	if spec.is_empty():
		text = "No weather for this room's area (set it in the Areas tab)."
	elif MDSEnvironment.is_none(spec):
		text = "Weather is off in this room."
	else:
		var problem := MDSEnvironment.check(spec)
		text = "Weather: %s%s" % [MDSEnvironment.summary(spec), " (%s)" % problem if not problem.is_empty() else ""]
	var p := MDSEnvironment.parallax_for_room(world, room_id) if world and world.has_room(room_id) else ""
	if not p.is_empty() and not MDSEnvironment.is_none(p):
		var p_problem := MDSEnvironment.check_parallax(p)
		text += "\nParallax background: %s%s" % [p, " (%s)" % p_problem if not p_problem.is_empty() else ""]
	_weather_label.text = text

## Status after Convert to freeform (or its preview).
func report_conversion(r: Dictionary, preview: bool) -> void:
	canvas.selected = null
	if r.is_empty():
		_changed("Converted %s to freeform. Ctrl+Z undoes it; Check room checks it." % room_id)
		return
	if not str(r.get("error", "")).is_empty():
		_changed(r.error)
		return
	var text := "%s %d rock shape(s), %d ledge(s)%s%s; %d opening(s) kept clear; %d old tile(s) and node(s) %s." % [
		"Preview:" if preview else "Converted:", r.rock, r.ledges,
		", %d background shape(s)" % r.back if r.back > 0 else "", ", %d foreground shape(s)" % r.front if r.front > 0 else "",
		r.openings, r.old, "taken out" if preview else "hidden or removed"]
	if not r.warnings.is_empty():
		text += " " + " ".join(r.warnings)
	_changed(text)

## The style picked for Fill outside shape.
func _fill_style() -> MDSFreeformStyle:
	var i := _fill_style_opt.selected
	return _styles[_fill_style_opt.get_item_id(i)] if i >= 0 and _fill_style_opt.get_item_id(i) < _styles.size() else MDSFreeform._default_style()

func fill_outside() -> void:
	if not painter:
		return
	var rects := world.get_local_rects(room_id)
	var map_shape := world.get_local_shape(room_id)
	if MDSNotchFill.outside_polygons(rects, MDSNotchFill.MARGIN, map_shape).is_empty() and MDSNotchFill.shapes_of(painter).is_empty():
		status_message.emit("%s's shape is its whole box: there is nothing outside it to fill." % room_id)
		return
	painter.checkpoint()
	var n := MDSNotchFill.fill(painter, rects, _fill_style(), MDSNotchFill.MARGIN, map_shape)
	_changed("Filled outside %s's shape: %d shape(s) of %s (decoration: no collision)." % [room_id, n, _fill_style().get_display_name()])

## A room whose shape changed on the map gets its outside fill redone (undoable).
func _refresh_outside_fill() -> void:
	var rects := world.get_local_rects(room_id)
	var map_shape := world.get_local_shape(room_id)
	if MDSNotchFill.shapes_of(painter).is_empty() or not MDSNotchFill.is_stale(painter, rects, map_shape):
		return
	var st: MDSFreeformStyle = MDSNotchFill.shapes_of(painter)[0].style
	painter.checkpoint()
	var n := MDSNotchFill.fill(painter, rects, st if st else _fill_style(), MDSNotchFill.MARGIN, map_shape)
	status_message.emit("%s's shape changed on the map: its outside fill was redone (%d shape(s)). Ctrl+Z undoes it." % [room_id, n])

func generate(new_variation: bool) -> void:
	if not painter:
		return
	var fills := generation_fills()
	if not painter.has_terrains() and str(fills.terrain.get("type", "")) == "terrain":
		status_message.emit("%s's tileset has no terrains: pick palette tiles or a solid color as the Terrain fill to generate with, or make a terrain from a 3x3 block in the palette." % room_id)
		return
	if new_variation:
		_variation += 1
	var terrain := _terrain_for_generation() if painter.has_terrains() else Vector2i.ZERO
	painter.checkpoint()
	painter.generate_cave(world, room_id, hash(room_id) + _variation * 7919, terrain.x, terrain.y, {}, fills)
	var made: PackedStringArray = ["terrain"]
	for k in ["background", "decor", "foreground", "stamps"]:
		if fills.has(k):
			made.append(k)
	_changed("Generated a cave from %s's shape on the map (%s; %d gate(s) joined both ways). Paint over it, then Save." % [room_id, ", ".join(made), world.get_gates(room_id).size()])

## What Generate cave makes, from the fills picked for each layer and the options (see
## [method MDSRoomPainter.generate_cave]).
func generation_fills() -> Dictionary:
	var fills := {"terrain": canvas.fills.get(MDSRoomCanvas.Tool.TERRAIN, {}), "paths": bool(generate_options.get("paths", true))}
	if fills.terrain.is_empty() or (str(fills.terrain.get("type", "")) == "terrain" and painter and painter.has_terrains()):
		var t := _terrain_for_generation() if painter else Vector2i.ZERO
		fills.terrain = {"type": "terrain", "set": t.x, "terrain": t.y}
	var layer_tools := {"background": MDSRoomCanvas.Tool.BACKGROUND, "decor": MDSRoomCanvas.Tool.DECOR, "foreground": MDSRoomCanvas.Tool.FOREGROUND}
	for k in layer_tools:
		if bool(generate_options.get(k, true)) and not canvas.fills.get(layer_tools[k], {}).is_empty():
			fills[k] = canvas.fills[layer_tools[k]]
	if bool(generate_options.get("stamps", true)) and canvas.stamp_set and not canvas.stamp_category.is_empty():
		fills.stamps = {"set": canvas.stamp_set, "category": canvas.stamp_category, "group": canvas.stamp_group, "scale": canvas.stamp_scale}
	return fills

## Shows the area bar for [param area]'s [param rooms] (the room open among them).
func set_area(area: String, rooms: Array[String]) -> void:
	_area = area
	_area_rooms = rooms
	_area_box.visible = not area.is_empty() and not rooms.is_empty()
	var i := rooms.find(room_id)
	_area_label.text = "Area %s: room %d of %d (%s)" % [area, i + 1, rooms.size(), room_id] if i >= 0 else "Area %s: %d rooms" % [area, rooms.size()]

func _area_step(d: int) -> void:
	if _area_rooms.is_empty():
		return
	var i := _area_rooms.find(room_id)
	room_requested.emit(_area_rooms[posmod(i + d, _area_rooms.size())])

## Removes every effect placed in the room (undoable).
func remove_all_effects() -> void:
	if not painter or painter.effects().is_empty():
		status_message.emit("No effects are placed in %s." % room_id)
		return
	painter.checkpoint()
	var n := painter.effects().size()
	for e in painter.effects():
		painter.remove_item(e)
	canvas.selected_effect = null
	_changed("Removed the %d effect(s) placed in %s. Ctrl+Z undoes it." % [n, room_id])

## No weather or effects from the room's area here (its weather: none), or its area's again.
func set_no_effects(on: bool) -> void:
	if not world or not world.has_room(room_id):
		return
	var now := MDSEnvironment.is_none(str(world.get_room_value(room_id, "weather", "")))
	if now == on:
		return
	world.checkpoint()
	world.set_room_value(room_id, "weather", "none" if on else "")
	refresh_weather()
	status_message.emit("%s: %s" % [room_id, "no weather or effects from its area here." if on else "its area's weather again."])

func fill_background() -> void:
	if not painter:
		return
	painter.checkpoint()
	painter.clear_layer("Background")
	painter.paint_fill("Background", painter.room_cells(world, room_id).keys(), canvas.fills[MDSRoomCanvas.Tool.BACKGROUND])
	_changed("Background filled.")

func _terrain_for_generation() -> Vector2i:
	var f: Dictionary = canvas.fills.get(MDSRoomCanvas.Tool.TERRAIN, {})
	if f.get("type", "") == "terrain":
		return Vector2i(f["set"], f.terrain)
	var t: Array = painter.get_terrains()[0]
	return Vector2i(t[0], t[1])

func _changed(message: String) -> void:
	canvas.check_result = {}
	canvas._overlay.queue_redraw()
	if painter and broken_button:
		broken_button.visible = not painter.broken_cells().is_empty() or painter.has_dropped_tiles()
	status_message.emit(message)

## Says which layers have tiles their tileset no longer has, and shows Remove broken tiles.
func _report_broken_tiles() -> void:
	var broken := painter.broken_cells() if painter else {}
	var dropped := painter.has_dropped_tiles() if painter else false
	broken_button.visible = not broken.is_empty() or dropped
	if broken.is_empty():
		if dropped:
			status_message.emit("%s's tileset has tiles that no longer fit their sheet (its tile size was made bigger, or the sheet smaller): Godot logs \"The TileSetAtlasSource atlas has no tile at ...\" for each of them whenever it loads the tileset. Remove broken tiles takes them out of it." % room_id)
		return
	var parts: PackedStringArray = []
	var at: Array = []
	for layer_name in broken:
		parts.append("%d on %s" % [broken[layer_name].size(), layer_name])
		for c in broken[layer_name].slice(0, 3 - at.size()):
			var a: Vector2i = painter.layers[layer_name].get_cell_atlas_coords(c)
			at.append("(%d, %d)" % [a.x, a.y])
	status_message.emit("%s has tiles that point at tiles its tileset no longer has (%s; atlas %s): they draw nothing and have no collision. Their sheet was removed, or its tile size made bigger so fewer tiles fit. Remove broken tiles erases them." % [room_id, ", ".join(parts), ", ".join(at)])

## Erases the painted tiles that point at tiles the tileset no longer has (undoable).
func remove_broken_tiles() -> int:
	if not painter:
		return 0
	painter.checkpoint()
	var dropped := painter.has_dropped_tiles()
	var n := painter.remove_broken_cells()
	if n == 0 and not dropped:
		_changed("No broken tiles in %s." % room_id)
	else:
		_changed("Removed %d broken tile(s)%s. Save writes the room%s; Ctrl+Z brings the tiles back." % [n, " and the tiles that no longer fit from the tileset" if dropped else "", " and the tileset, which then loads without errors" if dropped else ""])
	return n

func _update_shape_controls() -> void:
	var curved := MDSTerrainShapes.is_curved(canvas.shape) and canvas.shape < MDSRoomCanvas.GENERATOR_BASE
	curve_opt.disabled = not curved
	flip_check.disabled = not curved
	count_spin.editable = curved and canvas.curve in [MDSTerrainShapes.CurveType.WAVE, MDSTerrainShapes.CurveType.STEPS, MDSTerrainShapes.CurveType.SPIKES]
	rough_spin.editable = canvas.shape != Shape.BRUSH and canvas.shape != Shape.RECT and canvas.shape < MDSRoomCanvas.GENERATOR_BASE
	brush_spin.editable = canvas.shape == Shape.BRUSH

# --- Fills ---------------------------------------------------------------------------------------

## Fills the current tool can use, as [text, icon, fill].
func _fill_choices() -> Array:
	var out: Array = []
	for t in painter.get_terrains():
		var tname := str(t[2]) if not str(t[2]).is_empty() else "Terrain %d/%d" % [t[0], t[1]]
		out.append(["Terrain: %s" % tname, MDSUi.color_icon(painter.tile_set.get_terrain_color(t[0], t[1])), {"type": "terrain", "set": t[0], "terrain": t[1]}])
	var kinds := painter.get_decor_tiles()
	for kind in kinds:
		var tile: Array = kinds[kind][0]
		var src := painter.tile_set.get_source(tile[0]) as TileSetAtlasSource
		var icon := AtlasTexture.new()
		icon.atlas = src.texture
		icon.region = src.get_tile_texture_region(tile[1])
		out.append(["%s (random)" % str(kind).capitalize(), icon, {"type": "kind", "kind": kind}])
	out.append(["Palette tiles (%s)" % palette.describe_fill(), null, {"type": "stamp"}])
	out.append(["Solid color", MDSUi.color_icon(color_button.color), {"type": "color"}])
	return out

func _default_fill(t: int, choices: Array) -> Dictionary:
	var want := ""
	match t:
		MDSRoomCanvas.Tool.TERRAIN:
			want = "terrain"
		MDSRoomCanvas.Tool.BACKGROUND:
			for c in choices:
				if c[2].get("kind", "") == "foliage":
					return c[2]
			return {"type": "color", "color": color_button.color}
		MDSRoomCanvas.Tool.DECOR:
			for c in choices:
				if c[2].get("type") == "kind" and c[2].kind != "foliage":
					return c[2]
		MDSRoomCanvas.Tool.FOREGROUND:
			return {"type": "color", "color": Color("#03070a")}
	for c in choices:
		if c[2].get("type") == want:
			return c[2]
	return {"type": "color", "color": color_button.color}

func _same_fill(a: Dictionary, b: Dictionary) -> bool:
	if a.get("type") != b.get("type"):
		return false
	match str(a.get("type")):
		"terrain":
			return a["set"] == b["set"] and a.terrain == b.terrain
		"kind":
			return a.kind == b.kind
	return true

func _fill_valid(f: Dictionary, choices: Array) -> bool:
	if f.get("type") == "stamp":
		return painter.tile_set.has_source(int(f.get("source", -1)))
	if f.get("type") == "color":
		return true
	for c in choices:
		if _same_fill(c[2], f):
			return true
	return false

## Rebuilds the fill list for the current tool. With [param validate], fills that no
## longer exist in the tileset fall back to defaults.
func _fill_pickers(validate: bool) -> void:
	if not painter:
		return
	var choices := _fill_choices()
	if validate:
		for t in [MDSRoomCanvas.Tool.TERRAIN, MDSRoomCanvas.Tool.BACKGROUND, MDSRoomCanvas.Tool.DECOR, MDSRoomCanvas.Tool.FOREGROUND]:
			if not _fill_valid(canvas.fills.get(t, {}), choices):
				canvas.fills[t] = _default_fill(t, choices)
	if canvas.tool == MDSRoomCanvas.Tool.EFFECT:
		return
	_filling = true
	fill_opt.clear()
	var erase := canvas.tool == MDSRoomCanvas.Tool.ERASE
	fill_opt.disabled = false
	if canvas.tool == MDSRoomCanvas.Tool.FREEFORM:
		for i in _styles.size():
			fill_opt.add_item(_styles[i].get_list_name(), i)
		fill_opt.select(maxi(0, _styles.find(canvas.freeform_style)))
		fill_opt.tooltip_text = "Style of new freeform shapes (and of the selected one). Styles are *.freeform.tres files in the project"
		color_button.visible = false
		_filling = false
		return
	if canvas.tool == MDSRoomCanvas.Tool.STAMP:
		var k := 0
		for si in _stamp_sets.size():
			for cat in _stamp_sets[si].get_categories():
				fill_opt.add_item("%s: %s" % [_stamp_sets[si].get_display_name(), cat.capitalize()], k)
				fill_opt.set_item_metadata(fill_opt.item_count - 1, [si, cat])
				if _stamp_sets[si] == canvas.stamp_set and cat == canvas.stamp_category:
					fill_opt.select(fill_opt.item_count - 1)
				k += 1
		if fill_opt.item_count == 0:
			fill_opt.add_item("No stamp sets (add the Mossgrove pack)")
		fill_opt.tooltip_text = "Stamps placed by the brush. Stamp sets are *.stamps.tres files in the project"
		color_button.visible = false
		_filling = false
		return
	if erase:
		# The list chooses what Erase removes.
		for i in MDSRoomCanvas.ERASE_MODE_NAMES.size():
			fill_opt.add_item(MDSRoomCanvas.ERASE_MODE_NAMES[i], i)
		fill_opt.select(canvas.erase_mode)
		fill_opt.tooltip_text = "What Erase removes (Shift: background only)"
		color_button.visible = false
		_filling = false
		return
	fill_opt.tooltip_text = "What the current tool paints: a terrain (autotiled), random tiles of a kind, the tiles picked in the palette, or a solid color"
	var current: Dictionary = canvas.fills.get(canvas.tool, {})
	for c in choices:
		if c[1]:
			fill_opt.add_icon_item(c[1], c[0])
		else:
			fill_opt.add_item(c[0])
		fill_opt.set_item_metadata(fill_opt.item_count - 1, c[2])
		if not erase and _same_fill(c[2], current):
			fill_opt.select(fill_opt.item_count - 1)
	color_button.visible = not erase and current.get("type") == "color"
	if color_button.visible:
		color_button.color = current.get("color", color_button.color)
	_filling = false

func _on_fill_selected(idx: int) -> void:
	if _filling:
		return
	if canvas.tool == MDSRoomCanvas.Tool.ERASE:
		canvas.erase_mode = fill_opt.get_item_id(idx)
		return
	if canvas.tool == MDSRoomCanvas.Tool.FREEFORM:
		_set_freeform_style(_styles[fill_opt.get_item_id(idx)], true)
		return
	if canvas.tool == MDSRoomCanvas.Tool.STAMP:
		var meta: Variant = fill_opt.get_item_metadata(idx)
		if meta is Array:
			canvas.stamp_set = _stamp_sets[meta[0]]
			canvas.stamp_category = meta[1]
		return
	var f: Dictionary = fill_opt.get_item_metadata(idx)
	match str(f.type):
		"stamp":
			if not palette.has_selection():
				status_message.emit("Pick tiles in the palette first (drag over them), or add a spritesheet with + Sheet.")
				_fill_pickers(false)
				return
			f = palette.get_fill()
		"color":
			f = {"type": "color", "color": color_button.color}
	canvas.fills[canvas.tool] = f
	color_button.visible = f.type == "color"

## Picks a freeform style; its default layer is used for new shapes. With
## [param apply_to_selected] in Edit mode, the selected shape takes the style too.
func _set_freeform_style(st: MDSFreeformStyle, apply_to_selected: bool) -> void:
	canvas.freeform_style = st
	var idx := {"terrain": 0, "back": 1, "front": 2}.get(st.default_layer, 0)
	canvas.freeform_group = FREEFORM_GROUPS[idx]
	canvas.freeform_solid = st.solid and idx == 0 and st.get_role() != MDSFreeformStyle.Role.DECOR
	if apply_to_selected and is_instance_valid(canvas.selected) and painter and canvas.freeform_mode == MDSRoomCanvas.FreeformMode.EDIT:
		painter.checkpoint()
		canvas.selected.style = st
		painter.dirty = true
	_update_tool_controls()

## Freeform styles and stamp sets available: built-ins plus the project's files.
func _load_styles() -> void:
	_styles = MDSFreeformStyle.builtins()
	_styles.append_array(MDSFreeformStyle.find_in_project())
	_stamp_sets = MDSStampSet.find_in_project()
	var keep := _fill_style_opt.get_item_text(_fill_style_opt.selected) if _fill_style_opt.selected >= 0 else ""
	var preset_path := str(world.get_setting("notch_fill_style", "")) if world else ""
	var preset: MDSFreeformStyle = load(preset_path) as MDSFreeformStyle if not preset_path.is_empty() and ResourceLoader.exists(preset_path) else null
	if keep.is_empty() and preset:
		keep = preset.get_display_name()
	_fill_style_opt.clear()
	var deep := 0
	for i in _styles.size():
		_fill_style_opt.add_item(_styles[i].get_display_name(), i)
		var lower := _styles[i].get_display_name().to_lower()
		if (keep.is_empty() and (lower.contains("deep") or lower.contains("dark"))) or _styles[i].get_display_name() == keep:
			deep = _fill_style_opt.item_count - 1
	_fill_style_opt.select(deep)
	if not canvas.freeform_style or not canvas.freeform_style in _styles:
		# Prefer a textured style from the project (a mossy one if there is).
		var pick := _styles[0]
		for st in _styles.slice(MDSFreeformStyle.BUILTIN_COUNT):
			if pick == _styles[0] or st.get_display_name().to_lower().contains("moss"):
				pick = st
		_set_freeform_style(pick, false)
	if (not canvas.stamp_set or not canvas.stamp_set in _stamp_sets) and not _stamp_sets.is_empty():
		canvas.stamp_set = _stamp_sets[0]
		var cats := canvas.stamp_set.get_categories()
		canvas.stamp_category = cats[0] if not cats.is_empty() else ""

## Tiles picked in the palette: the current tool paints them (Erase, Freeform and Stamps
## switch to Terrain).
func _on_palette_picked() -> void:
	if not palette.has_selection():
		return
	if canvas.tool in [MDSRoomCanvas.Tool.ERASE, MDSRoomCanvas.Tool.FREEFORM, MDSRoomCanvas.Tool.STAMP, MDSRoomCanvas.Tool.EFFECT]:
		set_tool(MDSRoomCanvas.Tool.TERRAIN)
	canvas.fills[canvas.tool] = palette.get_fill()
	_fill_pickers(false)
	status_message.emit("%s brush paints the palette tiles (%s)." % [TOOL_LAYERS[canvas.tool], palette.describe_fill()])
