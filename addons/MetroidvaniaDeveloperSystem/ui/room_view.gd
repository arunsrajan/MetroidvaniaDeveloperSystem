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
## room's area over it. Trace drawing turns a picture of the room into freeform shapes, solid
## colors or tiles, or keeps the picture itself with collision for its terrain.
##
## The Place tool puts the tiles picked in the palette anywhere, at any angle (the palette turns
## them 0 to 360 degrees), off the grid. The Select tool selects tiles, free tiles, stamps,
## pictures and freeform shapes (one by one or in a box) and moves them by pixels, or by whole
## tiles with Snap to tiles, and turns them.
##
## The Full view ([method open_full]) shows every room of a layer where it is on the map, at its
## real size, none of them edited until a press in one (a room without a scene gets one). Its own
## tools ([member full_controls], see [MDSFullViewTools]) draw rooms (rectangles, ellipses,
## polygons, curvy outlines) for Generate map to make rooms of, select and move rooms, and open
## the rooms selected in the Room view; scenes dropped on it are placed as rooms. The painting
## tools work in any room, as with rooms shown together.
##
## Its buttons are in [member controls], a narrow column that MetDevSys puts in its left
## tool panel, and MetDevSys shows the [member palette] as a tab. Used on its own, the view
## shows the column on its left and the palette on its right.

signal saved(scene_path: String)
signal status_message(text: String)
## The Tile palette button was pressed while the palette lives elsewhere (MetDevSys shows it
## as a tab).
signal palette_requested
## The area bar asks for another room of the area.
signal room_requested(room_id: String)
## Generate caves in all the rooms of [param area] ([param rooms]) was pressed.
signal area_caves_requested(area: String, rooms: Array[String])
## Rooms shown together (see [method open_rooms]): [param room_id] is the one edited now.
signal room_activated(room_id: String)
## The Full view asks to edit rooms [param ids] in the Room view (a double-click on one).
signal rooms_requested(ids: Array[String])
## Scene files dropped on the Full view at [param world_pos] (world px), to place as rooms.
signal scenes_dropped(files: PackedStringArray, world_pos: Vector2)
## The Full view's Generate area tool: a box of paint cells for the Generate area dialog.
signal generate_area_requested(box: Rect2i)

const DEFAULT_TILESET := MDSTilesetFactory.DEFAULT_PATH
const Shape := MDSTerrainShapes.Shape
const TOOL_LAYERS: PackedStringArray = ["Terrain", "Background", "Decor", "Erase", "Foreground", "Freeform", "Stamps", "Effects", "Place", "Select"]
## The tile layers the Place tool puts tiles at the depth of.
const PLACE_LAYERS: PackedStringArray = ["Background", "Terrain", "Decor", "Foreground"]
const FREEFORM_LAYERS: PackedStringArray = ["Terrain (solid)", "Background", "Foreground"]
const FREEFORM_GROUPS: PackedStringArray = ["Freeform", "FreeformBack", "FreeformFront"]
const STAMP_LAYERS: PackedStringArray = ["Behind terrain", "In front of terrain", "Foreground"]
const STAMP_GROUPS: PackedStringArray = ["StampsBack", "StampsFront", "StampsForeground"]
## The most paint cells a passage Generate all makes between rooms far apart may take.
const PASSAGE_CELLS := 16

var canvas: MDSRoomCanvas
var palette: MDSTilePalette
var painter: MDSRoomPainter
var world: MDSWorld
var room_id := ""
var tool_buttons: Array[Button] = []
## The room's scene open in the editor (its root's instance id) and its undo history's version,
## when the Room view last took them in (see [method sync_from_editor]).
var _editor_seen: Array = []
var _sync_timer: Timer
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
var generate_options := {"background": true, "decor": true, "foreground": true, "stamps": true, "paths": true, "parts": true}
## Rooms shown together (see [method open_rooms]), [member room_id] the one edited. Empty: one.
var _session: Array[String] = []
## Their painters opened so far: id -> MDSRoomPainter ([member painter] among them). Each keeps
## its changes and its undo history while another is edited.
var _painters: Dictionary = {}
var _session_label := ""
## Scene path -> [method _history_mark] of the rooms shown together not edited now.
var _editor_marks: Dictionary = {}
var _session_row: Control
var _area_caves_button: Button
var _area := ""
var _area_rooms: Array[String] = []
var _area_box: VBoxContainer
var _area_label: Label
var _weather_label: Label
## Shown while the room has cells pointing at tiles its tileset no longer has.
var broken_button: Button
## Shown when the room's scene is big enough for Godot to warn about it: what makes it big, and
## Clear hidden tiles when hidden layers do.
var size_box: VBoxContainer
var size_label: Label
var clear_hidden_button: Button
## Place and Select: move by whole tiles instead of pixels.
var snap_check: CheckBox
## Place and Select: how far the turn buttons (and R) turn.
var turn_spin: SpinBox
var _turn_row: Control
var _select_row: Control
var _select_hint: Label
var _tool_group: ButtonGroup
## The Full view (see [method open_full]): its tools, and their column for a side panel.
var full_tools: MDSFullViewTools
var full_controls: VBoxContainer
var full_tool_buttons: Array[Button] = []
var _full := false
var _kind_opt: OptionButton
var _area_opt: OptionButton
var _full_caves: CheckBox
var _full_hint: Label
var _full_refresh_pending := false
## The Full view with no room edited: a painter of the rooms' tileset alone, so the tile palette
## and the fills show it (see [method tile_painter]).
var _tiles_painter: MDSRoomPainter
## The path of the scene a room clicked in the Full view gets when it has none (id -> path).
var scene_path_for: Callable

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
	_tool_group = group
	var names := ["Terrain", "Background", "Decor", "Erase", "Foreground", "Freeform", "Stamps", "Effects", "Place", "Select"]
	var tips := ["Paint the Terrain layer (solid ground: autotiled terrain, palette tiles or colors)", "Paint the Background layer (foliage, palette tiles or a solid color)", "Paint the Decor layer (grass, vines, stalactites, palette tiles...)", "Erase the top item under the brush: a stamp or free tiles, else foreground, decoration, terrain, then background (palette tiles and colors too). Pick one layer or all layers in the list next to it; Shift erases background only. Works with shapes too, to carve curved caves",
		"Paint the Foreground layer, drawn in front of everything (dark silhouettes framing the room)",
		"Freeform terrain: smooth curvy shapes instead of tiles (rounded ledges, bulging moss walls), with textured edges, clumps and exact collision. Draw by clicking points or dragging freehand, or pick a shape and drag its box. Edit mode reshapes them",
		"Place large clumps freely (moss bubbles, leaves, ferns, hanging moss, background bubbles, foreground silhouettes). Click or drag; Shift removes",
		"Environment effects: rain, snow, dust storms, lightning, fog, steam vents, lava, waterfalls, water, light shafts, embers, fireflies, leaves, heat haze. Drag one from the list onto the room (or pick one and click), drag to move, drag the corner to resize; the selected effect's settings are in the Inspector. Delete removes it",
		"Place the tiles picked in the tile palette anywhere in the room, off the grid, at the angle picked there (0 to 360 degrees; R / Shift+R turn them). Click to place, drag right away to move; Shift+click removes free tiles. They draw and collide like the tiles of the layer picked below",
		"Select tiles, free tiles, stamps, pictures and freeform shapes: click (Shift or Ctrl adds or removes) or drag a box around them, then drag to move them by pixels (Snap to tiles: by whole tiles). Tiles moved off the grid become free tiles. R / Shift+R turn the selection, the arrows nudge it, Delete removes it"]
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
	# Place and Select.
	turn_spin = SpinBox.new()
	turn_spin.min_value = 1
	turn_spin.max_value = 180
	turn_spin.step = 1
	turn_spin.value = 15
	turn_spin.suffix = "°"
	turn_spin.tooltip_text = "How far the turn buttons and R / Shift+R turn: the palette's tiles under Place, the selection under Select (the palette turns its tiles to any angle, 0 to 360 degrees)"
	turn_spin.value_changed.connect(func(v: float) -> void: canvas.turn_step = v)
	var turn_back := MDSUi.button("−", "Turn back (Shift+R)")
	turn_back.pressed.connect(func() -> void: turn(-turn_spin.value))
	var turn_on := MDSUi.button("+", "Turn clockwise (R)")
	turn_on.pressed.connect(func() -> void: turn(turn_spin.value))
	_turn_row = MDSSidePanel.field(controls, "Turn", turn_spin)
	_turn_row.add_child(turn_back)
	_turn_row.add_child(turn_on)
	snap_check = CheckBox.new()
	snap_check.text = "Snap to tiles"
	snap_check.tooltip_text = "Place, move and turn by whole tiles, on the grid. Off: by pixels, anywhere in the room (grid tiles moved off the grid become free tiles; To grid puts free tiles back on it)"
	snap_check.toggled.connect(func(on: bool) -> void:
		canvas.snap_to_grid = on
		canvas._overlay.queue_redraw())
	controls.add_child(snap_check)
	var to_grid := MDSUi.button("To grid", "Put the selected free tiles back on their layer's grid, turned to the nearest right angle (Ctrl+Z undoes it)")
	to_grid.pressed.connect(func() -> void:
		if painter:
			canvas.merge_selection_to_grid())
	var remove := MDSUi.button("Delete", "Remove the selected tiles and items (Delete key; Ctrl+Z undoes it)")
	remove.pressed.connect(func() -> void:
		if painter:
			canvas.delete_selection())
	_select_row = MDSSidePanel.row(controls, [to_grid, remove])
	_select_hint = MDSUi.hint("")
	_select_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(_select_hint)
	_effect_box = VBoxContainer.new()
	controls.add_child(_effect_box)

	var effect_category := OptionButton.new()
	effect_category.add_item("Environment Effects")
	effect_category.add_item("Gameplay Objects")
	_effect_box.add_child(effect_category)

	effect_list = EffectList.new()
	effect_list.custom_minimum_size.y = 230 * MDSUi.editor_scale()
	effect_list.fixed_icon_size = Vector2i(16, 16) * int(maxf(1.0, MDSUi.editor_scale()))
	effect_list.tooltip_text = "Drag an effect onto the room, or pick one and click in the room: it is placed, and clicks then select, move and resize effects again (the new one too). Ctrl+click keeps it picked, to place several. Click a selected effect again for the next one under it"

	var fill_effect_list := func(cat: int) -> void:
		effect_list.clear()
		if cat == 0:
			effect_list.add_item("No effect (select and move)")
			effect_list.set_item_metadata(0, "")
			effect_list.set_item_tooltip(0, "Place nothing: click an effect in the room to select it, drag it to move it, drag the handles on its sides and corners to resize it")
			for id in MDSEnvironment.EFFECTS:
				effect_list.add_item(MDSEnvironment.display_name(id), MDSEnvironment.icon(id))
				effect_list.set_item_metadata(effect_list.item_count - 1, id)
				effect_list.set_item_tooltip(effect_list.item_count - 1, MDSEnvironment.describe(id))
		else:
			effect_list.add_item("No object (select and move)")
			effect_list.set_item_metadata(0, "")
			effect_list.set_item_tooltip(0, "Place nothing: click an object in the room to select it, drag it to move it, drag the handles on its sides and corners to resize it")
			const GAMEPLAY_ITEMS: Array = [
				["Ability pickup", "gameplay:ability_pickup", "mds_ability_pickup.svg", "MDSAbilityPickup: grants an ability on touch and persists"],
				["Item pickup", "gameplay:item_pickup", "mds_pickup.svg", "MDSPickup: item or collectible"],
				["Health fragment", "gameplay:health_fragment", "mds_health_upgrade.svg", "MDSPickup: health fragment"],
				["Breakable wall", "gameplay:breakable_wall", "mds_breakable.svg", "MDSBreakable: wall that breaks on attack"],
				["Cracked floor", "gameplay:cracked_floor", "mds_breakable.svg", "MDSBreakable: floor that breaks on ground pound"],
				["Switch", "gameplay:switch", "mds_switch.svg", "MDSSwitch: sets a flag on hit or interact"],
				["Hazard (spikes)", "gameplay:hazard", "mds_hazard.svg", "MDSHazard: spikes/thorns that hurt and respawn"],
				["Checkpoint", "gameplay:checkpoint", "mds_checkpoint.svg", "MDSCheckpoint: respawn point in hazard rooms"],
				["Grapple point", "gameplay:grapple_point", "mds_grapple_point.svg", "MDSGrapplePoint: anchor for the grapple hook"],
				["Enemy (Walker)", "gameplay:enemy_walker", "mds_walker.svg", "Walker template enemy"],
				["Enemy (Flyer)", "gameplay:enemy_flyer", "mds_flyer.svg", "Flyer template enemy"],
				["Enemy (Turret)", "gameplay:enemy_turret", "mds_turret.svg", "Turret template enemy"],
				["Enemy (Charger)", "gameplay:enemy_charger", "mds_charger.svg", "Charger template enemy"],
				["Enemy (Ambusher)", "gameplay:enemy_ambusher", "mds_ambusher.svg", "Ambusher template enemy"],
				["Boss arena", "gameplay:boss_arena", "mds_boss_arena.svg", "MDSBossArena: locks doors during boss fight"],
				["NPC", "gameplay:npc", "mds_npc.svg", "MDSNPC: dialogue and interaction"],
				["Dialogue trigger", "gameplay:dialogue_trigger", "mds_dialogue_trigger.svg", "MDSDialogueTrigger: a conversation with anything (a door, a sign, a statue), on interact or on touch"],
			]
			for item in GAMEPLAY_ITEMS:
				var icon_path: String = "res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/" + str(item[2])
				var icon: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
				effect_list.add_item(item[0], icon)
				effect_list.set_item_metadata(effect_list.item_count - 1, item[1])
				effect_list.set_item_tooltip(effect_list.item_count - 1, item[3])
		effect_list.select(0)
		if canvas:
			canvas.effect_id = ""

	effect_category.item_selected.connect(fill_effect_list)
	fill_effect_list.call(0)

	# Clicking an entry picks it, the one already selected too (to place another).
	effect_list.item_clicked.connect(func(i: int, _at: Vector2, button: int) -> void:
		if button != MOUSE_BUTTON_LEFT:
			return
		canvas.effect_id = str(effect_list.get_item_metadata(i))
		if canvas.effect_id.is_empty():
			status_message.emit("No effect: click an effect in the room to select, move or resize it.")
		else:
			status_message.emit("Click in the room to place %s, then drag it into place (Ctrl+click to place several)." % effect_list.get_item_text(i)))
	effect_list.item_selected.connect(func(i: int) -> void:
		canvas.effect_id = str(effect_list.get_item_metadata(i)))
	_effect_box.add_child(effect_list)
	var clear_effects := MDSUi.button("Remove all", "Remove every effect placed in this room (Ctrl+Z undoes it)")
	clear_effects.pressed.connect(remove_all_effects)
	no_effects_check = CheckBox.new()
	no_effects_check.text = "No effects here"
	no_effects_check.tooltip_text = "No weather or effects from the room's area (or the world) in this room: its weather is set to none (Inspect tab). Effects placed in the room itself stay"
	no_effects_check.toggled.connect(set_no_effects)
	MDSSidePanel.row(_effect_box, [clear_effects, no_effects_check])
	_effect_box.add_child(MDSUi.hint("Drag onto the room. Click one in the room to edit it in the Inspector; drag its handles to resize it. Drop an image on a parallax background to add it as a layer, or on an animated background to show it blurred."))
	var weather_check := CheckBox.new()
	weather_check.text = "Show the area's weather"
	weather_check.button_pressed = true
	weather_check.tooltip_text = "Show the weather of the room's area (Areas tab > Weather), or of the room itself (Inspect tab), as the game adds it to every room of the area. Only a preview: it isn't saved into the scene"
	weather_check.toggled.connect(func(on: bool) -> void:
		canvas.set_weather_preview(on)
		_update_weather_label())
	_effect_box.add_child(weather_check)
	var parallax_check := CheckBox.new()
	parallax_check.text = "Show the backgrounds"
	parallax_check.button_pressed = true
	parallax_check.tooltip_text = "Show the parallax and animated backgrounds of the room's area (Areas tab > Parallax, Animated bg), of the boss rooms or of the room itself, behind the room as the game adds them; pan the view to see them move. Only a preview: they aren't saved into the scene"
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
	size_box = VBoxContainer.new()
	size_box.visible = false
	generation.add_child(size_box)
	size_label = MDSUi.hint("")
	size_label.modulate.a = 1.0
	size_label.add_theme_color_override(&"font_color", Color(1.0, 0.75, 0.4))
	size_box.add_child(size_label)
	clear_hidden_button = MDSUi.button("Clear hidden tiles", "Remove the tiles of the tile layers hidden in the scene (their eye shut in the Scene dock, or Visible off in the Inspector): they never show, but every one of them is saved in the scene. Then save. Ctrl+Z undoes it")
	clear_hidden_button.pressed.connect(clear_hidden_tiles)
	size_box.add_child(clear_hidden_button)
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
	_area_caves_button = area_caves
	MDSSidePanel.row(_area_box, [prev, next, area_caves])
	var gen_all := MDSUi.button("Generate all", "Generate a cave in every room shown, with the fills and options here, each joined to its neighbours at their doors. Ctrl+Z undoes it room by room (in the room edited); Save writes them all")
	gen_all.pressed.connect(func() -> void: generate_all(false))
	var vary_all := MDSUi.button("New variation for all", "Generate the caves of every room shown again, with another random layout")
	vary_all.pressed.connect(func() -> void: generate_all(true))
	_session_row = MDSSidePanel.row(_area_box, [gen_all, vary_all])
	var gen := MDSUi.button("Generate cave", "Replace the tiles with a cave built from the room's shape on the map: walls, floor, ledges, openings at its gates, paths between them, then background, decorations, foreground and stamps. Uses the fills picked for each layer (and the stamps picked for the Stamps tool), as the options below say")
	gen.pressed.connect(func() -> void: generate(false))
	generate_button = gen
	generation.add_child(gen)
	var again := MDSUi.button("New variation", "Generate again with another random layout")
	again.pressed.connect(func() -> void: generate(true))
	generation.add_child(again)
	var options := HFlowContainer.new()
	generation.add_child(options)
	for o in [["background", "Background", "Paint the Background fill behind the cave"], ["decor", "Decor", "Decorations on floors and under ceilings; most floor ones of the Decor fill"], ["foreground", "Foreground", "The Foreground fill in front: a solid color or a terrain darkens the rock deep in the walls; tiles hang from ceilings and edge floors"], ["stamps", "Stamps", "Stamps of the set and category picked for the Stamps tool along the floors"], ["paths", "Paths", "Every gate reaches every other one and back: tunnels and shafts with ledges are carved where the cave doesn't allow it"], ["parts", "Merged walls", "A room merged from several on the map keeps walls where its old rooms met, with openings where their doors were (off: one open cave)"]]:
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
	var clear_back := MDSUi.button("Clear background", "Remove every tile of the Background layer. A room filled from edge to edge takes many, and a hidden layer's tiles are saved in the scene all the same")
	clear_back.pressed.connect(clear_background)
	MDSSidePanel.row(generation, [back, clear_back])
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
	var fit_props := MDSUi.button("Fit props to floor", "Stand every object that stands (save points, shops, NPCs, benches, spawn points: see the mds_stands group) on the floor under it, or lift it out of the ground it is sunk in, then step it along its floor out of any platform. Ctrl+Z undoes it")
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
			if _session.size() >= 2:
				_revert_active()
			else:
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
	canvas.effect_pick_changed.connect(func(id: String) -> void:
		for i in effect_list.item_count:
			if str(effect_list.get_item_metadata(i)) == id:
				effect_list.select(i)
				break)
	canvas.image_dropped.connect(func(path: String) -> void: open_trace_dialog(path))
	canvas.picked_changed.connect(_update_select_hint)
	canvas.turn_requested.connect(func(degrees: float) -> void: turn(degrees))
	canvas.room_pressed.connect(func(id: String) -> void: activate_room(id))
	canvas.before_effect_drop = func() -> void:
		if canvas.tool != MDSRoomCanvas.Tool.EFFECT:
			set_tool(MDSRoomCanvas.Tool.EFFECT)
	_split.add_child(canvas)
	palette = MDSTilePalette.new()
	palette.status_message.connect(func(t: String) -> void: status_message.emit(t))
	palette.selection_changed.connect(_on_palette_picked)
	palette.turn_changed.connect(_on_palette_turned)
	palette.tileset_changed.connect(func() -> void:
		_fill_pickers(true)
		canvas._overlay.queue_redraw())
	_build_full_controls()
	_update_shape_controls()
	_update_tool_controls()

## The Full view's column: its tools, what an outline makes and where, Generate map.
func _build_full_controls() -> void:
	full_tools = MDSFullViewTools.new(canvas)
	canvas.full_tools = full_tools
	full_tools.status_message.connect(func(t: String) -> void: status_message.emit(t))
	full_tools.rooms_requested.connect(func(ids: Array[String]) -> void: rooms_requested.emit(ids))
	full_tools.generate_requested.connect(func(box: Rect2i) -> void: generate_area_requested.emit(box))
	full_tools.selection_changed.connect(_update_session_bar)
	canvas.scenes_dropped.connect(func(files: PackedStringArray, at: Vector2) -> void: scenes_dropped.emit(files, at))
	full_controls = VBoxContainer.new()
	full_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := MDSSidePanel.grid(full_controls, 2)
	for i in MDSFullViewTools.TOOL_NAMES.size():
		var b := MDSUi.button(MDSFullViewTools.TOOL_NAMES[i], MDSFullViewTools.TOOL_TIPS[i])
		b.toggle_mode = true
		b.button_group = _tool_group
		b.pressed.connect(func() -> void: set_full_tool(i))
		full_tool_buttons.append(b)
		grid.add_child(MDSSidePanel.fill(b))
	_kind_opt = OptionButton.new()
	_kind_opt.add_item("One room each", 0)
	_kind_opt.set_item_tooltip(0, "Each outline drawn becomes one room, its rectangles on the paint cells it covers and its outline on the map the shape drawn. Outlines that overlap are one room")
	_kind_opt.add_item("Split into rooms", 1)
	_kind_opt.set_item_tooltip(1, "Each outline drawn is split into rooms like a generated area (rectangles, L, T and U shapes, shafts) with doors between them; those on its edge keep its curves")
	_kind_opt.tooltip_text = "What Generate map makes of an outline drawn (and of the outlines selected, when changed)"
	_kind_opt.item_selected.connect(func(idx: int) -> void:
		full_tools.kind = MDSRoomSketches.ROOMS if idx == 1 else MDSRoomSketches.ROOM
		_apply_to_outlines())
	MDSSidePanel.field(full_controls, "Make", _kind_opt)
	_area_opt = OptionButton.new()
	_area_opt.tooltip_text = "The area of the rooms of an outline drawn (and of the outlines selected, when changed): a new area (outlines that touch share it), none, or one of the world's"
	_area_opt.item_selected.connect(func(idx: int) -> void:
		full_tools.area = str(_area_opt.get_item_metadata(idx))
		_apply_to_outlines())
	MDSSidePanel.field(full_controls, "Area", _area_opt)
	var size_x := SpinBox.new()
	size_x.min_value = 1
	size_x.max_value = 12
	size_x.value = full_tools.sketches.room_max.x
	size_x.prefix = "Up to"
	size_x.tooltip_text = "Split into rooms: the widest room, in paint cells"
	size_x.value_changed.connect(func(v: float) -> void: full_tools.sketches.room_max.x = int(v))
	var size_y := SpinBox.new()
	size_y.min_value = 1
	size_y.max_value = 12
	size_y.value = full_tools.sketches.room_max.y
	size_y.prefix = "x"
	size_y.tooltip_text = "Split into rooms: the tallest room, in paint cells"
	size_y.value_changed.connect(func(v: float) -> void: full_tools.sketches.room_max.y = int(v))
	MDSSidePanel.row(full_controls, [size_x, size_y])
	var snap := CheckBox.new()
	snap.text = "Snap to cells"
	snap.button_pressed = true
	snap.tooltip_text = "Rectangles and ellipses on the paint cells' corners, polygon corners on the world grid, outlines moved by the grid. Rooms and scenes dragged in move smoothly, to the pixel, stopping against their neighbours"
	snap.toggled.connect(func(on: bool) -> void: full_tools.snap = on)
	var at_once := CheckBox.new()
	at_once.text = "At once"
	at_once.tooltip_text = "Each outline drawn becomes rooms on the map right away (off: draw them all first, then Generate map)"
	at_once.toggled.connect(func(on: bool) -> void: full_tools.right_away = on)
	MDSSidePanel.row(full_controls, [snap, at_once])
	var gen_map := MDSUi.button("Generate map", "Make rooms on the map of the outlines selected, or of every outline drawn: their paint cells (those no room has yet), their curves as the rooms' outlines, doors between them and to the rooms they touch, in the areas picked. One Ctrl+Z takes it back")
	gen_map.pressed.connect(func() -> void: generate_map(_full_caves.button_pressed))
	var clear := MDSUi.button("Clear outlines", "Remove every outline drawn on this layer (Ctrl+Z undoes it)")
	clear.pressed.connect(func() -> void:
		full_tools.clear_outlines()
		canvas._overlay.queue_redraw())
	MDSSidePanel.row(full_controls, [gen_map, clear])
	_full_caves = CheckBox.new()
	_full_caves.text = "Caves too"
	_full_caves.tooltip_text = "Generate map also makes a scene for each new room and a cave in it, joined at their doors, with the fills and Generate options below (Save writes them)"
	var edit := MDSUi.button("Edit selected", "Edit the rooms selected (Rooms tool) in the Room view")
	edit.pressed.connect(func() -> void:
		var ids := full_tools.selected_rooms()
		if ids.is_empty():
			status_message.emit("Select rooms first with the Rooms tool (click, Ctrl+click, or drag a box).")
		else:
			rooms_requested.emit(ids))
	MDSSidePanel.row(full_controls, [_full_caves, edit])
	_full_hint = MDSUi.hint("")
	_full_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	full_controls.add_child(_full_hint)
	full_controls.add_child(HSeparator.new())

## The Full view's tool [param t] (see [enum MDSFullViewTools.Tool]), in place of the painting tools.
func set_full_tool(t: int) -> void:
	full_tools.set_tool(t)
	if t >= 0 and t < full_tool_buttons.size():
		_press_tool(full_tool_buttons[t])
	_update_full_hint()
	canvas.grab_focus()

## What the Make and Area pickers say goes for the outlines selected.
func _apply_to_outlines() -> void:
	var n := full_tools.apply_to_selected()
	if n > 0:
		status_message.emit("%d outline(s) selected changed." % n)
	canvas._overlay.queue_redraw()

func _update_full_hint() -> void:
	if not _full_hint:
		return
	var t := full_tools.tool
	if t < 0:
		_full_hint.text = "Painting: click a room to paint it (one without a scene gets one). Pick a tool above to draw or move rooms."
	elif t == MDSFullViewTools.Tool.ROOMS:
		_full_hint.text = "Click or box-select rooms and outlines, drag to move them, Delete removes them. Double-click a room (or Edit selected) for the Room view."
	elif t == MDSFullViewTools.Tool.GENERATE:
		_full_hint.text = "Drag a box: the Generate area dialog makes an area of rooms in it."
	else:
		_full_hint.text = "Draw at the rooms' real size, then Generate map. Overlapping outlines of one kind and area are one; cells rooms have are left out."

## The area picker: a new area, none, the world's areas.
func _fill_area_picker() -> void:
	_area_opt.clear()
	_area_opt.add_item("New area")
	_area_opt.set_item_metadata(0, MDSRoomSketches.NEW_AREA)
	_area_opt.add_item("No area")
	_area_opt.set_item_metadata(1, "")
	if world:
		var names: Array = world.get_areas().keys()
		names.sort()
		for a in names:
			_area_opt.add_item(str(a))
			_area_opt.set_item_metadata(_area_opt.item_count - 1, str(a))
	for i in _area_opt.item_count:
		if str(_area_opt.get_item_metadata(i)) == full_tools.area:
			_area_opt.select(i)
			return
	full_tools.area = MDSRoomSketches.NEW_AREA
	_area_opt.select(0)

# --- Full view --------------------------------------------------------------------------------

## Opens the Full view of [param p_world]'s [param layer]: every room of it where it is on the
## map, at its real size. None is edited until a press in one with a painting tool (a room without
## a scene gets one, see [member scene_path_for]); each keeps its changes and undo meanwhile, and
## Save saves them all. The Full view's tools draw rooms and move them. [param picked]: rooms to
## select. Returns an error message, or "" on success.
func open_full(p_world: MDSWorld, layer: int, picked: Array = []) -> String:
	if not p_world:
		return "No world."
	if has_unsaved():
		save()
	close_room(false)
	world = p_world
	room_id = ""
	_full = true
	canvas.full = true
	canvas.full_layer = layer
	canvas.world = world
	canvas.room_id = ""
	canvas._frame = Vector2.ZERO
	_session_label = "Full view"
	full_tools.reset()
	_full_session()
	canvas.session = _session
	canvas.session_painters = _painters
	full_tools.select(picked)
	_fill_area_picker()
	_tiles_painter = null
	palette.set_painter(tile_painter())
	set_area("", [])
	# Nothing on the layer yet: drawing rooms is the first thing to do.
	set_full_tool(MDSFullViewTools.Tool.ROOMS if not _session.is_empty() else MDSFullViewTools.Tool.RECTANGLE)
	canvas.refresh_context()
	_update_session_bar()
	_fit_later()
	return ""

## Whether the Full view is open (see [method open_full]).
func is_full() -> bool:
	return _full

## The rooms selected in the Full view.
func full_selection() -> Array[String]:
	if not _full:
		var none: Array[String] = []
		return none
	return full_tools.selected_rooms()

## Every room of the Full view's layer, in the map's order, is shown.
func _full_session() -> void:
	var list: Array[String] = []
	for id in world.get_room_ids():
		if world.get_room_layer(id) == canvas.full_layer:
			list.append(id)
	_session.assign(list)

## The Full view after the world changed (rooms drawn, moved, removed, undone), a moment later.
func refresh_full_later() -> void:
	if _full and not _full_refresh_pending:
		_full_refresh_pending = true
		_refresh_full_deferred.call_deferred()

func _refresh_full_deferred() -> void:
	_full_refresh_pending = false
	refresh_full()

## The Full view after the world changed: every room of the layer shown again. A room no longer
## there (or now with another scene) is let go, its changes saved first.
func refresh_full() -> void:
	if not _full or not world:
		return
	_full_session()
	for id: String in _painters.keys():
		var p: MDSRoomPainter = _painters[id]
		if world.has_room(id) and world.get_room_layer(id) == canvas.full_layer and world.get_scene_path(id) == p.scene_path:
			continue
		if p == painter:
			_let_go()
		canvas.release_painter(id)
		if p.dirty and p.save() == OK:
			saved.emit(p.scene_path)
		p.free_instance()
		_painters.erase(id)
	full_tools.invalidate()
	canvas.refresh_context()
	_fill_area_picker()
	_update_session_bar()
	canvas._overlay.queue_redraw()

## The Full view: no room edited any more (its painter stays with its changes, shown with the
## others, unless it is let go too).
func _let_go() -> void:
	if not painter:
		return
	_editor_marks[painter.scene_path] = _editor_seen
	canvas.close()
	painter = null
	room_id = ""
	canvas.room_id = ""
	palette.set_painter(tile_painter())
	_fill_pickers(true)

## Makes a scene for room [param id] of the Full view (see [member scene_path_for]). Returns
## whether it has one now.
func _make_scene(id: String) -> bool:
	var path := str(scene_path_for.call(id)) if scene_path_for.is_valid() else str(world.get_setting("scene_folder", "res://rooms")).path_join(id.to_snake_case() + ".tscn")
	world.checkpoint()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := MDSWorldSceneTools.create_scene_for_room(world, id, path)
	if err != OK:
		status_message.emit(MDSWorldSceneTools.last_error if not MDSWorldSceneTools.last_error.is_empty() else "Could not create a scene for %s (error %d)." % [id, err])
		return false
	saved.emit(path)
	return true

## Generate map in the Full view (see [method MDSFullViewTools.generate_map]); with
## [param caves], the new rooms get scenes and caves too (Save writes them).
func generate_map(caves := false) -> Dictionary:
	var r := full_tools.generate_map()
	if r.is_empty():
		return r
	refresh_full()
	if caves and not r.rooms.is_empty():
		var ids: Array[String] = []
		ids.assign(r.rooms)
		generate_all(false, ids)
	return r

## Opens the room for painting. Returns an error message, or "" on success.
func open_room(p_world: MDSWorld, id: String) -> String:
	if has_unsaved():
		save()
	close_room(false)
	world = p_world
	room_id = id
	var path := world.get_scene_path(id)
	if path.is_empty():
		return "%s has no scene." % id
	var tiles := _room_tiles()
	# Open in the editor, the scene there (with the changes not saved yet) is the one painted.
	var live := live_scene_root(path)
	painter = _open_from(live, path, tiles) if live else MDSRoomPainter.open(path, tiles)
	_editor_seen = _history_mark(live) if live else []
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
	var note := painter.size_note()
	if not note.is_empty():
		status_message.emit(note)
	_report_size()
	_report_broken_tiles()
	_fit_later()
	return ""

## The tileset room scenes without one paint with (the world's "room_tileset").
func _room_tiles() -> TileSet:
	var tiles_path := str(world.get_setting("room_tileset", "")) if world else ""
	var tiles := MDSTilesetFactory.get_or_create(tiles_path if not tiles_path.is_empty() else DEFAULT_TILESET)
	var moved := MDSRoomPainter.externalize_sheets(tiles) if tiles else 0
	if moved > 0:
		status_message.emit("Took %d image(s) embedded in %s out of it (PNG files next to it, or packed), so it saves and loads fast." % [moved, tiles.resource_path.get_file()])
	return tiles

## Opens rooms [param ids] together, where they are on the map (an area, the rooms selected on
## the map): [param active] (the first by default) is edited, the others show around it,
## dimmed. A press in one of them edits that one (see [method activate_room]); each keeps its
## changes and undo history meanwhile, and Save saves them all. [param label] names them in the
## bar ("Area Caves", "3 rooms"). Rooms without a scene are left out. Returns an error message,
## or "" on success.
func open_rooms(p_world: MDSWorld, ids: Array, active := "", label := "") -> String:
	var list: Array[String] = []
	for v in ids:
		var id := str(v)
		if p_world.has_room(id) and not list.has(id) and not p_world.get_scene_path(id).is_empty():
			list.append(id)
	if list.is_empty():
		return "None of these rooms has a scene."
	if active.is_empty() or not list.has(active):
		active = list[0]
	var err := open_room(p_world, active)
	if not err.is_empty() or list.size() < 2:
		return err
	_session.assign(list)
	_session_label = label if not label.is_empty() else "%d rooms" % list.size()
	_painters[active] = painter
	canvas.session = _session
	canvas.session_painters = _painters
	canvas.refresh_context()
	_update_session_bar()
	canvas._overlay.queue_redraw()
	return ""

## Whether several rooms are shown together (see [method open_rooms]).
func is_session() -> bool:
	return _session.size() >= 2

## The rooms shown together (none: one room).
func session_rooms() -> Array[String]:
	return _session.duplicate()

## Edits room [param id] of the rooms shown together (see [method open_rooms]); the one edited so
## far stays open, with its changes and its undo history, shown around it. The view stays where
## it is. Returns whether [param id] is the one edited now.
func activate_room(id: String) -> bool:
	if not _session.has(id) or not world or not world.has_room(id) or (not painter and not _full):
		return false
	if id == room_id and painter:
		return true
	if canvas.is_busy():
		return false
	# The Full view: a room without a scene gets one.
	if _full and world.get_scene_path(id).is_empty() and not _make_scene(id):
		return false
	var fresh := not _painters.has(id)
	var p := _session_painter(id)
	if not p:
		return false
	if painter:
		_editor_marks[painter.scene_path] = _editor_seen
	# The same place on the map stays where it is on screen.
	canvas.pan += (world.get_origin(id) - canvas.frame_origin()) * canvas.zoom
	painter = p
	room_id = id
	_editor_seen = _editor_marks.get(p.scene_path, [])
	canvas.check_result = {}
	canvas.open(world, id, painter, true)
	palette.set_painter(painter)
	_load_styles()
	_fill_pickers(true)
	if fresh:
		_refresh_outside_fill()
	_update_weather_label()
	no_effects_check.set_pressed_no_signal(MDSEnvironment.is_none(str(world.get_room_value(id, "weather", ""))))
	_update_session_bar()
	_report_size()
	_report_broken_tiles()
	sync_from_editor()
	room_activated.emit(id)
	status_message.emit("Editing %s (%s). Its neighbours keep their changes; Save writes them all." % [id, _session_label])
	return true

## The painter of room [param id] of the rooms shown together, opened now if it wasn't.
func _session_painter(id: String) -> MDSRoomPainter:
	if _painters.has(id):
		return _painters[id]
	var path := world.get_scene_path(id)
	if path.is_empty():
		status_message.emit("%s has no scene." % id)
		return null
	var live := live_scene_root(path)
	var p := _open_from(live, path, _room_tiles()) if live else MDSRoomPainter.open(path, _room_tiles())
	if not p:
		status_message.emit("Could not open %s." % path)
		return null
	_editor_marks[path] = _history_mark(live) if live else []
	_painters[id] = p
	return p

## The bar of the rooms shown together: which one is edited, and buttons for all of them.
func _update_session_bar() -> void:
	var on := _session.size() >= 2 or _full
	_session_row.visible = on
	_area_caves_button.visible = not on
	if not on:
		return
	_area_box.visible = true
	var unsaved := 0
	for p: MDSRoomPainter in _painters.values():
		if p.dirty:
			unsaved += 1
	if _full:
		var picked := full_tools.selected_rooms().size()
		_area_label.text = "Full view: %d room(s)%s%s. Generate all makes caves in %s." % [_session.size(), ", editing %s" % room_id if painter else "", ", %d unsaved" % unsaved if unsaved > 0 else "",
			"the %d selected" % picked if picked > 0 else "all of them"]
		return
	_area_label.text = "%s: room %d of %d (%s)%s. Click another one to edit it." % [_session_label, _session.find(room_id) + 1, _session.size(), room_id, ", %d unsaved" % unsaved if unsaved > 0 else ""]

## Generate cave in every room shown together (see [method open_rooms]), with the fills and
## options here, or New variation of them all ([param new_variation]). Each room can be undone
## on its own (Ctrl+Z in it); Save writes them. Returns the number of rooms generated.
func generate_all(new_variation: bool, ids: Array[String] = []) -> int:
	if _session.size() < 2 and not _full:
		generate(new_variation)
		return 1 if painter else 0
	if canvas.is_busy():
		return 0
	if new_variation:
		_variation += 1
	var fills := generation_fills()
	var done := 0
	var failed: PackedStringArray = []
	var stuck: PackedStringArray = []
	# The Full view: the rooms selected, else all of them; rooms without a scene get one.
	var targets: Array[String] = ids.duplicate()
	if targets.is_empty() and _full:
		targets = full_tools.selected_rooms()
	if targets.is_empty():
		targets = _session.duplicate()
	# Rooms (areas) no door joins are joined first, by a door where they touch or a passage where
	# they don't, so the caves can be crossed and backtracked from one end to the other.
	var joins: Dictionary = {"doors": [], "rooms": []}
	if targets.size() >= 2 and MDSAreaTools.pieces(world, targets) > 1:
		world.checkpoint()
		joins = MDSAreaTools.link_apart(world, targets, PASSAGE_CELLS)
		if not joins.rooms.is_empty():
			targets.append_array(joins.rooms)
			refresh_full()
	for id in targets:
		if _full and world.has_room(id) and world.get_scene_path(id).is_empty() and not _make_scene(id):
			failed.append(id)
			continue
		var p := _session_painter(id)
		if not p:
			failed.append(id)
			continue
		var room_fills := fills.duplicate()
		var rock: Dictionary = room_fills.get("terrain", {})
		var terrain := Vector2i.ZERO
		if rock.is_empty() or str(rock.get("type", "")) == "terrain":
			if not p.has_terrains():
				failed.append(id)
				continue
			if rock.is_empty() or int(rock.get("set", 0)) >= p.tile_set.get_terrain_sets_count():
				var first: Array = p.get_terrains()[0]
				rock = {"type": "terrain", "set": first[0], "terrain": first[1]}
				room_fills.terrain = rock
			terrain = Vector2i(int(rock.get("set", 0)), int(rock.get("terrain", 0)))
		p.checkpoint()
		p.generate_cave(world, id, hash(id) + _variation * 7919, terrain.x, terrain.y, {}, room_fills)
		if not p.paths_joined:
			stuck.append(id)
		done += 1
	canvas.refresh_context()
	_update_session_bar()
	var text := "Generated caves in %d of %d rooms, joined at their doors. Ctrl+Z undoes it in the room edited; Save writes them all." % [done, targets.size()]
	if not joins.doors.is_empty():
		text += " Joined the rooms no door led to: %d door(s)%s." % [joins.doors.size(), " and passage(s) %s" % ", ".join(joins.rooms) if not joins.rooms.is_empty() else ""]
	var apart := MDSAreaTools.pieces(world, targets)
	if apart > 1:
		text += " The rooms are still in %d pieces no door joins (too far apart): draw a room between them." % apart
	if not failed.is_empty():
		text += " Not in %s (no terrains in its tileset: pick palette tiles or a color as the Terrain fill)." % ", ".join(failed)
	if not stuck.is_empty():
		text += " %s: not every gate could be joined to the others (too thin on the map for a path to climb): make it taller or wider there, or move its gates, then New variation." % ", ".join(stuck)
	_changed(text)
	return done

## Revert for the room edited among the rooms shown together: it is opened anew from its scene,
## the others keep their changes.
func _revert_active() -> void:
	var path := painter.scene_path
	var live := live_scene_root(path)
	var fresh := _open_from(live, path, _room_tiles()) if live else MDSRoomPainter.open(path, _room_tiles())
	if not fresh:
		return
	var old := painter
	painter = fresh
	_painters[room_id] = fresh
	canvas.open(world, room_id, painter, true)
	old.free_instance()
	palette.set_painter(painter)
	_editor_seen = _history_mark(live) if live else []
	_update_session_bar()
	_changed("Reverted %s." % room_id)

## Whether a room shown has changes not saved.
func has_unsaved() -> bool:
	if painter and painter.dirty:
		return true
	for p: MDSRoomPainter in _painters.values():
		if p.dirty:
			return true
	return false

func _ready() -> void:
	_adopt_controls.call_deferred()
	# Changes made to the room's scene in the editor (the 2D editor, the Inspector) show here.
	if not _sync_timer:
		_sync_timer = Timer.new()
		_sync_timer.one_shot = true
		_sync_timer.wait_time = 0.3
		_sync_timer.timeout.connect(sync_from_editor)
		add_child(_sync_timer, false, Node.INTERNAL_MODE_BACK)
		canvas.mouse_entered.connect(sync_from_editor)
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var ur: Object = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
		if ur and not ur.history_changed.is_connected(_on_editor_history):
			ur.history_changed.connect(_on_editor_history)
			ur.version_changed.connect(_on_editor_history)
	# Effects are edited in the Inspector: changes there are changes to the room.
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var inspector: Object = Engine.get_singleton(&"EditorInterface").get_inspector()
		if inspector and not inspector.property_edited.is_connected(_on_inspector_edited):
			inspector.property_edited.connect(_on_inspector_edited)

## Used on its own (not in MetDevSys), the button column goes on the left of the view and
## the palette on its right.
func _adopt_controls() -> void:
	if palette and not palette.get_parent():
		_split.add_child(palette)
	if full_controls and not full_controls.get_parent():
		controls.add_child(full_controls)
		controls.move_child(full_controls, 0)
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
		for p: MDSRoomPainter in _painters.values():
			if p != painter and is_instance_valid(p.root):
				p.root.free()
		if is_instance_valid(full_controls) and not full_controls.get_parent():
			full_controls.free()
		if is_instance_valid(controls) and not controls.get_parent():
			controls.free()
		if is_instance_valid(palette) and not palette.get_parent():
			palette.free()

func close_room(auto_save := true) -> void:
	if auto_save and has_unsaved():
		save()
	canvas.close()
	# The other rooms shown with it.
	_session.clear()
	canvas.refresh_context()
	for p: MDSRoomPainter in _painters.values():
		if p != painter:
			p.free_instance()
	_painters.clear()
	_editor_marks.clear()
	if _session_row:
		_update_session_bar()
	if painter:
		painter.free_instance()
	painter = null
	palette.set_painter(null)
	_tiles_painter = null
	# The Full view ends with it: the painting tools are the tools again.
	if _full:
		_full = false
		canvas.full = false
		full_tools.reset()
		full_tools.set_tool(-1)
		_press_tool(tool_buttons[canvas.tool])
		canvas.refresh_context()

func save() -> Error:
	if not painter and not (_full and has_unsaved()):
		return ERR_UNCONFIGURED
	# What changed in the editor first, so saving never writes over it.
	sync_from_editor()
	var err := painter.save() if painter else OK
	if painter and err == OK:
		saved.emit(painter.scene_path)
		# The editor reloaded it: that is no change to take in.
		var live := live_scene_root(painter.scene_path)
		_editor_seen = _history_mark(live) if live else []
		var note := painter.size_note()
		status_message.emit("Saved. " + note if not note.is_empty() else "Saved %s." % painter.scene_path.get_file())
		_report_size()
	elif painter and not MDSWorldSceneTools.last_error.is_empty():
		status_message.emit(MDSWorldSceneTools.last_error)
	elif painter:
		status_message.emit("Could not save %s (error %d)." % [painter.scene_path, err])
	# The other rooms shown with it that changed.
	var others := 0
	for id: String in _painters:
		var p: MDSRoomPainter = _painters[id]
		if p == painter or not p.dirty:
			continue
		var e := p.save()
		if e == OK:
			others += 1
			saved.emit(p.scene_path)
			var their_live := live_scene_root(p.scene_path)
			_editor_marks[p.scene_path] = _history_mark(their_live) if their_live else []
		else:
			if err == OK:
				err = e
			status_message.emit("Could not save %s: %s" % [p.scene_path.get_file(), MDSWorldSceneTools.last_error if not MDSWorldSceneTools.last_error.is_empty() else "error %d" % e])
	if others > 0 and err == OK:
		status_message.emit("Saved %s and %d other room(s) shown." % [painter.scene_path.get_file(), others] if painter else "Saved %d room(s)." % others)
	if _session_row and (_session.size() >= 2 or _full):
		_update_session_bar()
		canvas.refresh_context()
	canvas._overlay.queue_redraw()
	return err

# --- Changes made in the editor -------------------------------------------------------------

## The root of the scene [param path] as it is open in the editor (with its changes not saved
## yet), or null when it is not open (or there is no editor).
static func live_scene_root(path: String) -> Node:
	if path.is_empty() or not Engine.is_editor_hint() or not Engine.has_singleton(&"EditorInterface"):
		return null
	var ei: Object = Engine.get_singleton(&"EditorInterface")
	var edited: Node = ei.get_edited_scene_root()
	if edited and edited.scene_file_path == path:
		return edited
	for r: Node in ei.get_open_scene_roots():
		if is_instance_valid(r) and r.scene_file_path == path:
			return r
	return null

## [param live]'s root and the version of its undo history: it changes with every change made to
## the scene in the editor. A scene in a tab not being edited changes not (its root asks the
## editor for the history of everything else).
static func _history_mark(live: Node) -> Array:
	if not is_instance_valid(live) or not Engine.has_singleton(&"EditorInterface"):
		return []
	if live != Engine.get_singleton(&"EditorInterface").get_edited_scene_root():
		return [live.get_instance_id(), -1]
	var ur: Object = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
	var history: UndoRedo = ur.get_history_undo_redo(ur.get_object_history_id(live))
	return [live.get_instance_id(), history.get_version() if history else -1]

## A painter for the scene as [param live] has it, packed.
static func _open_from(live: Node, path: String, tiles: TileSet) -> MDSRoomPainter:
	var packed := PackedScene.new()
	if packed.pack(live) != OK:
		return MDSRoomPainter.open(path, tiles)
	return MDSRoomPainter.open_packed(packed, path, tiles)

func _on_editor_history() -> void:
	if (painter or (_full and not _painters.is_empty())) and _sync_timer and is_inside_tree():
		_sync_timer.start()

## Takes in the changes made to the room's scene in the editor since the Room view last did (it
## does after every change there, a moment later, and before saving): see
## [method sync_from_scene]. Returns whether there were any.
func sync_from_editor() -> bool:
	if not painter and not _full:
		return false
	var others := false
	for id: String in _painters.keys():
		if id != room_id or not painter:
			others = _sync_other(id) or others
	if not painter:
		return others
	var live := live_scene_root(painter.scene_path)
	if not live:
		return others
	var mark := _history_mark(live)
	if mark == _editor_seen:
		return others
	if canvas.is_busy():
		# Mid-stroke: once it is done.
		_sync_timer.start()
		return others
	_editor_seen = mark
	return sync_from_scene(live) or others

## Takes in what changed in the editor in the scene of room [param id], one of the rooms shown
## together not edited now (see [method sync_from_scene]). Returns whether it had changed.
func _sync_other(id: String) -> bool:
	var p: MDSRoomPainter = _painters[id]
	var live := live_scene_root(p.scene_path)
	if not live:
		return false
	var mark := _history_mark(live)
	if mark == _editor_marks.get(p.scene_path, []):
		return false
	_editor_marks[p.scene_path] = mark
	var theirs := _open_from(live, p.scene_path, p.tile_set)
	if not theirs:
		return false
	if MDSRoomPainter.same_state(theirs.base_state(), p.base_state()) and MDSRoomPainter.scene_fingerprint(theirs.root) == MDSRoomPainter.scene_fingerprint(p.root):
		theirs.free_instance()
		return false
	canvas.release_painter(id)
	var rebased := p.rebase_onto(theirs)
	_painters[id] = rebased
	p.free_instance()
	canvas.refresh_context()
	return true

## Goes on from the room's scene as [param live] has it (the scene open in the editor, changed
## there): what changed there shows here, and the Room view's own changes not saved yet stay,
## merged with them tile by tile and item by item (where both changed the same one, the
## scene's change wins; see [method MDSRoomPainter.rebase_onto]). The view, the tool and the
## selection stay. Returns whether the scene had changed.
func sync_from_scene(live: Node) -> bool:
	if not painter or not is_instance_valid(live):
		return false
	var theirs := _open_from(live, painter.scene_path, painter.tile_set)
	if not theirs:
		return false
	if MDSRoomPainter.same_state(theirs.base_state(), painter.base_state()) and MDSRoomPainter.scene_fingerprint(theirs.root) == MDSRoomPainter.scene_fingerprint(painter.root):
		theirs.free_instance()
		return false
	var keep := canvas.selection_names()
	var had := painter.dirty
	var old := painter
	painter = old.rebase_onto(theirs)
	if _painters.has(room_id):
		_painters[room_id] = painter
	# The same items go on, changed in place: the Inspector keeps showing what it shows (with
	# its sections as they were), and is not taken from what the user edits there.
	painter.keep_items_of(old)
	canvas.open(world, room_id, painter, true)
	old.free_instance()
	palette.set_painter(painter)
	canvas.select_names(keep, true)
	_report_broken_tiles()
	_report_size()
	_changed("%s changed in the editor: the Room view shows it now%s." % [painter.scene_path.get_file(), ", with its own changes not saved yet" if had else ""])
	return true

## Shows [param button] pressed and the other tool buttons (painting and Full view) not: a button
## group only does that for clicks.
func _press_tool(button: Button) -> void:
	for b in tool_buttons + full_tool_buttons:
		b.set_pressed_no_signal(b == button)

func set_tool(t: int) -> void:
	canvas.tool = t
	_press_tool(tool_buttons[t])
	if full_tools and full_tools.tool >= 0:
		full_tools.set_tool(-1)
		_update_full_hint()
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
	var place := t == MDSRoomCanvas.Tool.PLACE
	var select := t == MDSRoomCanvas.Tool.SELECT
	# Tools that paint the grid with brushes and shapes.
	var brushes := not (stamps or effects or place or select)
	fill_opt.get_parent().visible = not (effects or place or select)
	_effect_box.visible = effects
	layer_opt.get_parent().visible = freeform or stamps or place or select
	mode_opt.get_parent().visible = freeform
	role_opt.get_parent().visible = freeform
	repair_row.visible = freeform
	_update_generator_shapes(freeform)
	size_spin.visible = stamps
	brush_spin.visible = brushes and not freeform
	shape_opt.get_parent().visible = brushes
	curve_opt.get_parent().visible = brushes
	rough_spin.visible = brushes
	flip_check.get_parent().visible = brushes
	_turn_row.visible = place or select
	snap_check.visible = place or select
	_select_row.visible = select
	_select_hint.visible = place or select
	_filling = true
	layer_opt.clear()
	layer_opt.tooltip_text = "Layer of new freeform shapes or stamps"
	if freeform:
		for i in FREEFORM_LAYERS.size():
			layer_opt.add_item(FREEFORM_LAYERS[i], i)
		layer_opt.select(maxi(0, FREEFORM_GROUPS.find(canvas.freeform_group)))
	elif stamps:
		for i in STAMP_LAYERS.size():
			layer_opt.add_item(STAMP_LAYERS[i], i)
		layer_opt.select(maxi(0, STAMP_GROUPS.find(canvas.stamp_group)))
	elif place:
		for i in PLACE_LAYERS.size():
			layer_opt.add_item(PLACE_LAYERS[i], i)
		layer_opt.select(maxi(0, PLACE_LAYERS.find(canvas.place_layer)))
		layer_opt.tooltip_text = "Depth of the placed tiles: they draw and collide like the tiles of this layer"
	elif select:
		for i in MDSRoomCanvas.PICK_LAYER_NAMES.size():
			layer_opt.add_item(MDSRoomCanvas.PICK_LAYER_NAMES[i], i)
		layer_opt.select(canvas.pick_layer)
		layer_opt.tooltip_text = "What clicks and boxes select: everything, the tiles of one layer (on the grid and free), or only items"
	_filling = false
	_update_select_hint()

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
	elif canvas.tool == MDSRoomCanvas.Tool.PLACE:
		canvas.place_layer = PLACE_LAYERS[idx]
	elif canvas.tool == MDSRoomCanvas.Tool.SELECT:
		canvas.pick_layer = idx
		canvas._overlay.queue_redraw()

## Turns by [param degrees]: the palette's tiles under the Place tool, else the selection.
func turn(degrees: float) -> void:
	if canvas.tool == MDSRoomCanvas.Tool.PLACE:
		palette.set_turn(palette.turn_degrees + degrees)
	elif painter:
		canvas.rotate_selection(degrees)

## The Place and Select tools' hint: what a click does, what is selected.
func _update_select_hint() -> void:
	if not _select_hint:
		return
	if canvas.tool == MDSRoomCanvas.Tool.PLACE:
		var what := "the palette's tiles (%s)" % palette.describe_fill() if not canvas.place_fill.is_empty() else "the tiles picked in the tile palette (pick some there first)"
		_select_hint.text = "Click to place %s, off the grid; drag right away to move them, drag their handles to resize them. R / Shift+R turn the tiles, Shift+click removes free tiles." % what
	else:
		var n := canvas.selection_counts()
		_select_hint.text = "Click or drag a box to select (Shift adds), drag to move, drag the handles to resize (Shift keeps the shape), R turns, the arrows nudge, Delete removes. Selected: %d tile(s), %d item(s)." % [n.y, n.x]

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
	var kinds := {"terrain": "terrain shape(s)", "platform": "one-way platform(s)", "background": "background shape(s)", "foreground": "foreground shape(s)",
		"tiles": "tile(s)", "pictures": "picture(s) of the drawing", "collision": "collision shape(s)"}
	for k in kinds:
		if int(r.get(k, 0)) > 0:
			parts.append("%d %s" % [r[k], kinds[k]])
	var replaced: PackedStringArray = []
	if int(r.get("removed", 0)) > 0:
		replaced.append("%d shape(s) and picture(s)" % r.removed)
	if int(r.get("removed_tiles", 0)) > 0:
		replaced.append("%d tile(s)" % r.removed_tiles)
	var text := "%s %s%s." % ["Preview:" if preview else "Traced the drawing into %s:" % room_id, ", ".join(parts) if not parts.is_empty() else "nothing", "; the earlier trace replaced (%s)" % ", ".join(replaced) if not replaced.is_empty() else ""]
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
	var bg := MDSEnvironment.background_for_room(world, room_id) if world and world.has_room(room_id) else ""
	if not bg.is_empty() and not MDSEnvironment.is_none(bg):
		var bg_problem := MDSEnvironment.check_background(bg)
		text += "\nAnimated background: %s%s" % [bg, " (%s)" % bg_problem if not bg_problem.is_empty() else ""]
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
	# The Full view: the rooms selected (Rooms tool), else the room edited.
	if _full and (not painter or not full_tools.selected_rooms().is_empty()):
		if full_tools.selected_rooms().is_empty():
			status_message.emit("Click a room to edit it, or select rooms with the Rooms tool (click, Ctrl+click, a box), then Generate cave. Generate all does every room.")
			return
		generate_all(new_variation, full_tools.selected_rooms())
		return
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
	# Its gate nodes moved onto the new openings, their collision across them.
	var nodes := painter.gate_nodes()
	var missing: PackedStringArray = []
	for g in painter.gate_openings:
		if not nodes.has(g):
			missing.append(g)
	var gates := "%d gate(s) joined both ways, their gate nodes on the new openings" % world.get_gates(room_id).size()
	if not missing.is_empty():
		gates += "; no gate node for %s yet (Inspect > Write to scene adds it)" % ", ".join(missing)
	if not painter.paths_joined:
		gates += "; not every gate could be joined to the others (the room is too thin on the map for a path to climb there: make it taller or wider, or move its gates)"
	_changed("Generated a cave from %s's shape on the map (%s; %s). Paint over it, then Save." % [room_id, ", ".join(made), gates])

## What Generate cave makes, from the fills picked for each layer and the options (see
## [method MDSRoomPainter.generate_cave]).
func generation_fills() -> Dictionary:
	var fills := {"terrain": canvas.fills.get(MDSRoomCanvas.Tool.TERRAIN, {}), "paths": bool(generate_options.get("paths", true)), "parts": bool(generate_options.get("parts", true))}
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
	if _session.size() >= 2 or _full:
		_update_session_bar()
		return
	_area_box.visible = not area.is_empty() and not rooms.is_empty()
	var i := rooms.find(room_id)
	_area_label.text = "Area %s: room %d of %d (%s)" % [area, i + 1, rooms.size(), room_id] if i >= 0 else "Area %s: %d rooms" % [area, rooms.size()]

func _area_step(d: int) -> void:
	# Rooms shown together: the next one is edited, in the middle of the view.
	if _session.size() >= 2:
		if activate_room(_session[posmod(_session.find(room_id) + d, _session.size())]):
			canvas.fit(false)
		return
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

func clear_background() -> void:
	if not painter:
		return
	painter.checkpoint()
	painter.clear_layer("Background")
	_changed("Background cleared.")

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

## Shows [member size_box] when the room's scene is big enough for Godot's editor to warn that
## it is large on disk ([method MDSRoomPainter.size_note]), with Clear hidden tiles when hidden
## layers hold tiles.
func _report_size() -> void:
	var note := painter.size_note() if painter else ""
	size_box.visible = not note.is_empty()
	if note.is_empty():
		return
	size_label.text = "Big scene: " + note
	var n := 0
	var hidden := painter.hidden_tiles()
	for layer_name in hidden:
		n += int(hidden[layer_name])
	clear_hidden_button.visible = n > 0
	clear_hidden_button.text = "Clear %d hidden tiles (%s)" % [n, ", ".join(PackedStringArray(hidden.keys()))]

## Removes the tiles of the tile layers hidden in the scene (see
## [method MDSRoomPainter.hidden_tiles]), then saves, so the scene is small again. Returns how
## many tiles went. Ctrl+Z undoes it.
func clear_hidden_tiles() -> int:
	if not painter:
		return 0
	var hidden := painter.hidden_tiles()
	if hidden.is_empty():
		return 0
	painter.checkpoint()
	var n := 0
	for layer_name in hidden:
		painter.clear_layer(layer_name)
		n += int(hidden[layer_name])
	if save() == OK:
		var kib := ceili(FileAccess.get_file_as_bytes(painter.scene_path).size() / 1024.0)
		status_message.emit("Cleared %d tiles that never showed (hidden: %s) and saved: %s is %d KiB now. Ctrl+Z undoes it." % [n, ", ".join(PackedStringArray(hidden.keys())), painter.scene_path.get_file(), kib])
	return n

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

## The painter whose tileset the palette and the fills show: the room edited's, else (the Full
## view with no room edited) one of the rooms' tileset alone ([method _room_tiles]).
func tile_painter() -> MDSRoomPainter:
	if painter:
		return painter
	if not _full or not world:
		return null
	if not _tiles_painter:
		_tiles_painter = MDSRoomPainter.for_tile_set(_room_tiles())
	return _tiles_painter

## Fills the current tool can use, as [text, icon, fill].
func _fill_choices() -> Array:
	var out: Array = []
	var tp := tile_painter()
	for t in tp.get_terrains():
		var tname := str(t[2]) if not str(t[2]).is_empty() else "Terrain %d/%d" % [t[0], t[1]]
		out.append(["Terrain: %s" % tname, MDSUi.color_icon(tp.tile_set.get_terrain_color(t[0], t[1])), {"type": "terrain", "set": t[0], "terrain": t[1]}])
	var kinds := tp.get_decor_tiles()
	for kind in kinds:
		var tile: Array = kinds[kind][0]
		var src := tp.tile_set.get_source(tile[0]) as TileSetAtlasSource
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
		return tile_painter().tile_set.has_source(int(f.get("source", -1)))
	if f.get("type") == "color":
		return true
	for c in choices:
		if _same_fill(c[2], f):
			return true
	return false

## Rebuilds the fill list for the current tool. With [param validate], fills that no
## longer exist in the tileset fall back to defaults.
func _fill_pickers(validate: bool) -> void:
	if not tile_painter():
		return
	var choices := _fill_choices()
	if validate:
		for t in [MDSRoomCanvas.Tool.TERRAIN, MDSRoomCanvas.Tool.BACKGROUND, MDSRoomCanvas.Tool.DECOR, MDSRoomCanvas.Tool.FOREGROUND]:
			if not _fill_valid(canvas.fills.get(t, {}), choices):
				canvas.fills[t] = _default_fill(t, choices)
	if canvas.tool in [MDSRoomCanvas.Tool.EFFECT, MDSRoomCanvas.Tool.PLACE, MDSRoomCanvas.Tool.SELECT]:
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
	canvas.place_fill = palette.get_fill()
	if not palette.has_selection():
		return
	if canvas.tool == MDSRoomCanvas.Tool.PLACE:
		_update_select_hint()
		canvas._overlay.queue_redraw()
		status_message.emit("Place puts the palette's tiles (%s): click in the room." % palette.describe_fill())
		return
	if canvas.tool in [MDSRoomCanvas.Tool.ERASE, MDSRoomCanvas.Tool.FREEFORM, MDSRoomCanvas.Tool.STAMP, MDSRoomCanvas.Tool.EFFECT, MDSRoomCanvas.Tool.SELECT]:
		set_tool(MDSRoomCanvas.Tool.TERRAIN)
	canvas.fills[canvas.tool] = palette.get_fill()
	_fill_pickers(false)
	status_message.emit("%s brush paints the palette tiles (%s)." % [TOOL_LAYERS[canvas.tool], palette.describe_fill()])

## The palette's tiles were turned or mirrored: the Place tool and the brushes painting palette
## tiles take the new angle (the brushes on the grid, turned to the nearest right angle).
func _on_palette_turned() -> void:
	canvas.place_fill = palette.get_fill()
	for t in canvas.fills:
		var f: Dictionary = canvas.fills[t]
		if str(f.get("type", "")) == "stamp":
			f.rotation = palette.turn_degrees
			f.flip = palette.mirror
	canvas._overlay.queue_redraw()
	_update_select_hint()
	var grid := MDSRoomPainter.quarter_turns(palette.turn_degrees) * 90
	var note := "" if is_zero_approx(fposmod(palette.turn_degrees, 90.0)) else " (the brushes paint them on the grid at %d°, the nearest right angle)" % grid
	status_message.emit("Palette tiles turned %d°%s: Place puts them at that angle%s." % [roundi(palette.turn_degrees), ", mirrored" if palette.mirror else "", note])
