@tool
class_name IDPWorldPanel
extends Control
## Non-linear mode: draw rooms freely on a world map, place scenes on it, connect them
## with Hollow Knight-style gates and group them into areas. Data lives in a
## [code].idpworld.json[/code] file ([IDPWorld]); MetSys is not needed.

const DEFAULT_FILTERS: PackedStringArray = ["Save Points", "Bosses", "Collectibles", "Teleporters", "Shops", "Enemies"]
const DEFAULT_FILTERS_ON: PackedStringArray = ["Save Points", "Bosses"]
const EXPORT_DIR := "res://idp_exports"
const SETTING_WORLD_FILE := "interactive_dev_panel/world_file"

const SECTION_TOOLS := "Map tools"
const SECTION_DISPLAY := "Map display"
const SECTION_MARKERS := "Markers"
const SECTION_ROOM := "Room painting"

enum WorldItem { NEW = 1000, OPEN, IMPORT_METSYS, RELOAD }
enum ViewItem { LABELS, AREA_LABELS, TERRAIN, PREVIEWS, GATES, MARKERS, PINS, ISSUES, GRID, LEGEND }
enum ExportItem { JSON, PNG, DOT, MARKDOWN }
enum ScenesItem { RESCAN, ADD_SCENES, AUTO_CONNECT, SETTINGS, GAME_SCENE, AUTO_DOORS }
enum ContextItem { OPEN, PLAY_HERE, RUN_SCENE, CREATE_SCENE, ASSIGN_SCENE, FIT, SET_START, ROUTE, LINK, DUPLICATE, DELETE, ADD_ROOM, ADD_PIN, REMOVE_PIN, ADD_GATE, COPY_ID, PAINT_ROOM }

# Data
var world_path := ""
var world: IDPWorld
var analysis: IDPAnalysis
var graph: IDPGraph
var scene_database: Dictionary = {}
var issues: Array = []
var current_filters: Dictionary = {}

# UI
## The host inserts the mode switch at the start of this box (the World section).
var toolbar: Container
var side_panel: IDPSidePanel
var side_tabs_check: CheckBox
var canvas: IDPWorldCanvas
var world_picker: OptionButton
var tool_buttons: Array[Button] = []
var layer_picker: OptionButton
var color_picker: OptionButton
var style_picker: OptionButton
var brush_spin: SpinBox
var palette: ItemList
var palette_folder: LineEdit
var palette_hide_placed: CheckBox
var view_menu: MenuButton
var scenes_menu: MenuButton
var export_menu: MenuButton
var zoom_label: Label
var route_button: Button
var undo_button: Button
var redo_button: Button
var filter_box: HFlowContainer
var sidebar: TabContainer
var room_search: LineEdit
var room_tree: Tree
var inspector_scroll: ScrollContainer
var inspector: VBoxContainer
var area_tree: Tree
var area_box: VBoxContainer
var views: IDPAnalysisViews
var status_label: Label
var progress_bar: ProgressBar
var context_menu: PopupMenu
var file_dialog: EditorFileDialog
var pin_dialog: ConfirmationDialog
var pin_text: LineEdit
var pin_kind: OptionButton
var settings_dialog: AcceptDialog

# State
var _scanner: IDPSceneScanner
var _save_timer: Timer
var _refresh_timer: Timer
var _file_timer: Timer
var _last_modified := 0
var _dialog_action := ""
var _dialog_room := ""
var _context_room := ""
var _context_pos := Vector2.ZERO
var _pending_pin_pos := Vector2.ZERO
var _link_source := ""
var _inspector_room := ""
var _inspector_signature := ""
var _inspector_info: RichTextLabel
var _selected_area := ""
var _filling_list := false
var _export_viewport: SubViewport
var room_view: IDPRoomView
var map_view_button: Button
var room_view_button: Button

func _ready() -> void:
	if is_part_of_edited_scene():
		return
	_build_ui()
	_setup_filters()
	_save_timer = _make_timer(0.5, _save_world)
	_refresh_timer = _make_timer(0.2, _refresh)
	_file_timer = _make_timer(1.5, _check_world_file_changed)
	_file_timer.one_shot = false
	_file_timer.start()
	_refresh_world_list()
	var last: String = ProjectSettings.get_setting(SETTING_WORLD_FILE, "")
	if not last.is_empty() and FileAccess.file_exists(last):
		load_world(last)
	elif world_picker.get_item_count() > 0 and world_picker.get_item_metadata(0) is String and not str(world_picker.get_item_metadata(0)).is_empty():
		load_world(world_picker.get_item_metadata(0))
	else:
		_rebuild_inspector()
		_set_status("No world yet. Use the world picker: New world... or Import from MetSys map...")

func _make_timer(wait: float, callback: Callable) -> Timer:
	var t := Timer.new()
	t.wait_time = wait
	t.one_shot = true
	t.timeout.connect(callback)
	add_child(t)
	return t

# --- UI ----------------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# Like MetSys' editor: tools on the left, the map in the middle, tabs on the right.
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	side_panel = IDPSidePanel.new()
	main.add_child(side_panel)

	# World: mode switch (added by the host), world file, scenes, export.
	toolbar = side_panel.add_section("World")
	world_picker = OptionButton.new()
	world_picker.fit_to_longest_item = false
	world_picker.clip_text = true
	world_picker.tooltip_text = "World file (.idpworld.json)"
	world_picker.item_selected.connect(_on_world_picked)
	toolbar.add_child(world_picker)

	scenes_menu = IDPUi.menu_button("Scenes", "Scan, place and connect scenes")
	var sp := scenes_menu.get_popup()
	sp.add_item("Rescan world scenes", ScenesItem.RESCAN)
	sp.add_item("Add scenes to map...", ScenesItem.ADD_SCENES)
	sp.add_item("Add doors between touching rooms", ScenesItem.AUTO_DOORS)
	sp.add_item("Auto-connect facing gates", ScenesItem.AUTO_CONNECT)
	sp.add_separator()
	sp.add_item("Create game scene (IDPWorldGame)...", ScenesItem.GAME_SCENE)
	sp.add_item("World settings...", ScenesItem.SETTINGS)
	sp.id_pressed.connect(_on_scenes_menu)
	export_menu = IDPUi.menu_button("Export")
	var ep := export_menu.get_popup()
	ep.add_item("World + analysis (JSON)", ExportItem.JSON)
	ep.add_item("Map image (PNG)", ExportItem.PNG)
	ep.add_item("Room graph (Graphviz .dot)", ExportItem.DOT)
	ep.add_item("Design document (Markdown)", ExportItem.MARKDOWN)
	ep.id_pressed.connect(_on_export_menu)
	IDPSidePanel.row(toolbar, [scenes_menu, export_menu])

	# View: map or the selected room's actual contents.
	var view_section := side_panel.add_section("View")
	var view_group := ButtonGroup.new()
	map_view_button = IDPUi.button("Map view", "The world map")
	map_view_button.toggle_mode = true
	map_view_button.button_group = view_group
	map_view_button.button_pressed = true
	map_view_button.pressed.connect(show_map_view)
	room_view_button = IDPUi.button("Room view", "Paint the selected room's actual contents (terrain, background, decorations)")
	room_view_button.toggle_mode = true
	room_view_button.button_group = view_group
	room_view_button.pressed.connect(func() -> void: show_room_view(canvas.selected_room))
	IDPSidePanel.row(view_section, [map_view_button, room_view_button])
	side_tabs_check = CheckBox.new()
	side_tabs_check.text = "Side tabs"
	side_tabs_check.button_pressed = true
	side_tabs_check.tooltip_text = "Show the Rooms / Scenes / Inspect... tabs on the right. Hide them for a bigger map"
	side_tabs_check.toggled.connect(func(on: bool) -> void: sidebar.visible = on)
	view_section.add_child(side_tabs_check)

	# Map tools.
	var tools := side_panel.add_section(SECTION_TOOLS)
	var tool_grid := IDPSidePanel.grid(tools, 2)
	var group := ButtonGroup.new()
	var short_names := ["Select", "Room", "Extend", "Gate", "Pin", "Paint", "Erase"]
	for i in IDPWorldCanvas.TOOL_NAMES.size():
		var b := IDPUi.button(short_names[i], IDPWorldCanvas.TOOL_NAMES[i] + "\n" + IDPWorldCanvas.TOOL_HINTS[i])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.pressed.connect(func() -> void:
			canvas.set_tool(i)
			canvas.grab_focus())
		tool_buttons.append(b)
		tool_grid.add_child(IDPSidePanel.fill(b))
	brush_spin = SpinBox.new()
	brush_spin.min_value = 1
	brush_spin.max_value = 8
	brush_spin.value = 1
	brush_spin.prefix = "Brush"
	brush_spin.tooltip_text = "Brush size in paint cells ([ and ] on the map)"
	brush_spin.value_changed.connect(func(v: float) -> void:
		if int(v) != canvas.brush_size:
			canvas.set_brush_size(int(v)))
	tool_grid.add_child(IDPSidePanel.fill(brush_spin))
	undo_button = IDPUi.button("Undo", "Undo (Ctrl+Z on the map)")
	undo_button.pressed.connect(func() -> void:
		if world:
			world.undo())
	redo_button = IDPUi.button("Redo", "Redo (Ctrl+Y on the map)")
	redo_button.pressed.connect(func() -> void:
		if world:
			world.redo())
	IDPSidePanel.row(tools, [undo_button, redo_button])

	# Map display.
	var display := side_panel.add_section(SECTION_DISPLAY)
	layer_picker = OptionButton.new()
	layer_picker.item_selected.connect(func(idx: int) -> void:
		var id := layer_picker.get_item_id(idx)
		if id == 9999:
			_add_layer()
		else:
			_set_layer(id))
	IDPSidePanel.field(display, "Layer", layer_picker)
	style_picker = OptionButton.new()
	style_picker.tooltip_text = "Tileset used to draw rooms (also used by the in-game IDPWorldMapView)"
	style_picker.item_selected.connect(_on_style_picked)
	IDPSidePanel.field(display, "Style", style_picker)
	color_picker = OptionButton.new()
	var modes := [[IDPMapCanvas.ColorMode.AREA, "Area"], [IDPMapCanvas.ColorMode.ROOM_TYPE, "Room type"], [IDPMapCanvas.ColorMode.PROGRESSION, "Progression"], [IDPMapCanvas.ColorMode.SAVE_DISTANCE, "Save distance"], [IDPMapCanvas.ColorMode.STATUS, "Build status"]]
	for m in modes:
		color_picker.add_item(m[1], m[0])
	color_picker.item_selected.connect(func(idx: int) -> void:
		canvas.color_mode = color_picker.get_item_id(idx)
		canvas.redraw())
	IDPSidePanel.field(display, "Color", color_picker)

	view_menu = IDPUi.menu_button("Show on map...")
	var vp := view_menu.get_popup()
	vp.hide_on_checkable_item_selection = false
	var view_items := [
		[ViewItem.LABELS, "Room labels", "labels"], [ViewItem.AREA_LABELS, "Area names", "area_labels"],
		[ViewItem.TERRAIN, "Terrain silhouettes", "terrain"], [ViewItem.PREVIEWS, "Live scene previews (slow)", "previews"],
		[ViewItem.GATES, "Gates && connections", "gates"], [ViewItem.MARKERS, "Markers", "markers"],
		[ViewItem.PINS, "Pins", "pins"], [ViewItem.ISSUES, "Issue badges", "issues"],
		[ViewItem.GRID, "Grid", "grid"], [ViewItem.LEGEND, "Legend", "legend"],
	]
	for item in view_items:
		vp.add_check_item(item[1], item[0])
		vp.set_item_metadata(vp.get_item_index(item[0]), item[2])
	vp.id_pressed.connect(func(id: int) -> void:
		var idx := vp.get_item_index(id)
		vp.set_item_checked(idx, not vp.is_item_checked(idx))
		canvas.set_show(vp.get_item_metadata(idx), vp.is_item_checked(idx)))
	display.add_child(IDPSidePanel.fill(view_menu))

	var zoom_out := IDPUi.button("-", "Zoom out")
	zoom_out.pressed.connect(func() -> void: canvas.set_zoom(canvas.zoom / 1.25))
	zoom_label = IDPUi.label("")
	zoom_label.custom_minimum_size.x = 44
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var zoom_in := IDPUi.button("+", "Zoom in (or mouse wheel over the map)")
	zoom_in.pressed.connect(func() -> void: canvas.set_zoom(canvas.zoom * 1.25))
	var fit := IDPUi.button("Fit", "Fit the layer in view (F)")
	fit.pressed.connect(func() -> void: canvas.fit_to_layer())
	IDPSidePanel.row(display, [zoom_out, zoom_label, zoom_in, fit])
	route_button = IDPUi.button("Clear route", "Clear the highlighted route / highlight (Esc)")
	route_button.visible = false
	route_button.pressed.connect(_clear_route_and_highlight)
	display.add_child(route_button)

	# Marker filters.
	filter_box = HFlowContainer.new()
	side_panel.add_section(SECTION_MARKERS, filter_box)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(split)
	canvas = IDPWorldCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(200, 200)
	canvas.room_selected.connect(_on_canvas_room_selected)
	canvas.room_activated.connect(_on_room_activated)
	canvas.route_requested.connect(_show_route)
	canvas.context_requested.connect(_on_canvas_context)
	canvas.hovered_changed.connect(_on_canvas_hover)
	canvas.pin_requested.connect(_request_pin)
	canvas.scenes_dropped.connect(_on_scenes_dropped)
	canvas.status_message.connect(_set_status)
	canvas.tool_changed.connect(func(t: int) -> void: tool_buttons[t].button_pressed = true)
	canvas.brush_size_changed.connect(func(n: int) -> void: brush_spin.set_value_no_signal(n))
	canvas.view_changed.connect(func() -> void: zoom_label.text = "%d%%" % roundi(canvas.zoom * 100.0 / 0.06))
	# Map view (the world map) and Room view (the room's actual contents) share this spot.
	var view_box := VBoxContainer.new()
	view_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(view_box)
	view_box.add_child(canvas)
	room_view = IDPRoomView.new()
	room_view.visible = false
	room_view.saved.connect(_on_room_saved)
	room_view.status_message.connect(_set_status)
	view_box.add_child(room_view)
	# The Room view's brushes and actions live in the tool panel too, shown with it.
	side_panel.add_section(SECTION_ROOM, room_view.controls)
	side_panel.set_section_visible(SECTION_ROOM, false)

	sidebar = TabContainer.new()
	sidebar.custom_minimum_size.x = 300
	split.add_child(sidebar)
	_build_rooms_tab()
	_build_palette_tab()
	_build_inspector_tab()
	_build_areas_tab()
	views = IDPAnalysisViews.new(self, sidebar)
	# The Room view's tile palette is a tab, shown with the Room view.
	room_view.palette.name = "Tiles"
	sidebar.add_child(room_view.palette)
	sidebar.set_tab_hidden(sidebar.get_tab_idx_from_control(room_view.palette), true)
	room_view.palette_requested.connect(func() -> void:
		side_tabs_check.button_pressed = true
		sidebar.current_tab = sidebar.get_tab_idx_from_control(room_view.palette))

	var status := HBoxContainer.new()
	root.add_child(status)
	status_label = IDPUi.label("")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(160, 0)
	progress_bar.visible = false
	status.add_child(progress_bar)

	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context_menu)
	add_child(context_menu)
	file_dialog = EditorFileDialog.new()
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.file_selected.connect(_on_file_dialog_file)
	file_dialog.files_selected.connect(_on_file_dialog_files)
	file_dialog.dir_selected.connect(func(d: String) -> void:
		if _dialog_action == "palette_folder" and world:
			world.set_setting("scene_folder", d)
			palette_folder.text = d
			_refresh_palette())
	add_child(file_dialog)
	_build_pin_dialog()
	_build_settings_dialog()
	for i in vp.item_count:
		var key = vp.get_item_metadata(i)
		if key is String:
			vp.set_item_checked(i, canvas.show.get(key, false))

func _build_rooms_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Rooms"
	sidebar.add_child(box)
	room_search = LineEdit.new()
	room_search.placeholder_text = "Search rooms, areas, bosses, abilities..."
	room_search.clear_button_enabled = true
	room_search.text_changed.connect(func(_t: String) -> void: _refresh_room_list())
	box.add_child(room_search)
	room_tree = Tree.new()
	room_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_tree.hide_root = true
	room_tree.columns = 3
	room_tree.column_titles_visible = true
	room_tree.set_column_title(0, "Room")
	room_tree.set_column_title(1, "Area")
	room_tree.set_column_title(2, "Sphere")
	room_tree.set_column_expand(2, false)
	room_tree.set_column_custom_minimum_width(2, 60)
	room_tree.item_selected.connect(func() -> void:
		if not _filling_list:
			select_room(room_tree.get_selected().get_metadata(0), true))
	room_tree.item_activated.connect(func() -> void: _on_room_activated(room_tree.get_selected().get_metadata(0)))
	box.add_child(room_tree)
	var add := IDPUi.button("Add scenes to map...", "Pick .tscn files to place on the map (or drag them from the FileSystem dock)")
	add.pressed.connect(func() -> void: _on_scenes_menu(ScenesItem.ADD_SCENES))
	box.add_child(add)

func _build_palette_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Scenes"
	sidebar.add_child(box)
	box.add_child(IDPUi.hint("Drag scenes onto the map: onto a painted room without a scene to fill it, or onto empty space to place it at its own size. Double-click places a scene in the middle of the view."))
	var row := HBoxContainer.new()
	box.add_child(row)
	palette_folder = LineEdit.new()
	palette_folder.placeholder_text = "res://rooms"
	palette_folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	IDPUi.commit_line(palette_folder, func(t: String) -> void:
		if world:
			world.set_setting("scene_folder", t.strip_edges())
			_refresh_palette())
	row.add_child(palette_folder)
	var browse := IDPUi.button("...", "Pick the scene folder")
	browse.pressed.connect(func() -> void: _open_file_dialog("palette_folder", EditorFileDialog.FILE_MODE_OPEN_DIR, []))
	row.add_child(browse)
	var refresh := IDPUi.button("Refresh", "Reload the scene list")
	refresh.pressed.connect(_refresh_palette)
	row.add_child(refresh)
	palette_hide_placed = CheckBox.new()
	palette_hide_placed.text = "Hide scenes already on the map"
	palette_hide_placed.button_pressed = true
	palette_hide_placed.toggled.connect(func(_on: bool) -> void: _refresh_palette())
	box.add_child(palette_hide_placed)
	palette = ItemList.new()
	palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette.select_mode = ItemList.SELECT_MULTI
	palette.fixed_icon_size = Vector2i(48, 48)
	palette.set_drag_forwarding(_palette_get_drag, Callable(), Callable())
	palette.item_activated.connect(func(i: int) -> void:
		_on_scenes_dropped(PackedStringArray([palette.get_item_metadata(i)]), canvas.screen_to_world(canvas.size / 2.0)))
	box.add_child(palette)

func _refresh_palette() -> void:
	if not palette:
		return
	palette.clear()
	if not world:
		return
	var folder: String = world.get_setting("scene_folder", "res://rooms")
	palette_folder.text = folder
	if not DirAccess.dir_exists_absolute(folder):
		return
	var files: Array[String] = []
	IDPSceneScanner.new().find_scene_files(folder, files)
	var placed: Dictionary = {}
	for id in world.get_room_ids():
		placed[world.get_scene_path(id)] = true
	var previewer := EditorInterface.get_resource_previewer()
	for f in files:
		if palette_hide_placed.button_pressed and placed.has(f):
			continue
		var i := palette.add_item(f.get_file().get_basename())
		palette.set_item_metadata(i, f)
		palette.set_item_tooltip(i, f + (" (already on the map)" if placed.has(f) else ""))
		previewer.queue_resource_preview(f, self, &"_on_palette_preview", f)

func _on_palette_preview(path: String, preview: Texture2D, _thumbnail: Texture2D, _userdata: Variant) -> void:
	if not preview or not palette:
		return
	for i in palette.item_count:
		if palette.get_item_metadata(i) == path:
			palette.set_item_icon(i, preview)

func _palette_get_drag(at_position: Vector2) -> Variant:
	var idx := palette.get_item_at_position(at_position, true)
	if idx < 0:
		return null
	if not palette.is_selected(idx):
		palette.select(idx)
	var files: PackedStringArray = []
	for i in palette.get_selected_items():
		files.append(palette.get_item_metadata(i))
	# Only valid while Godot is starting a drag (not when called directly).
	if palette.get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = ", ".join(Array(files).map(func(f: String) -> String: return f.get_file().get_basename()))
		palette.set_drag_preview(preview)
	return {"type": "files", "files": files}

func _rebuild_style_picker() -> void:
	style_picker.clear()
	var current: String = world.get_setting("map_style", "handdrawn") if world else "handdrawn"
	var ids: PackedStringArray = []
	ids.append_array(IDPMapStyle.BUILTIN)
	for t in IDPMapStyle.find_metsys_themes():
		ids.append("metsys:" + t)
	if not current in ids:
		ids.append(current)
	for sid in ids:
		style_picker.add_item(IDPMapStyle.style_display_name(sid))
		style_picker.set_item_metadata(style_picker.item_count - 1, sid)
		if sid == current:
			style_picker.select(style_picker.item_count - 1)
	style_picker.add_separator()
	style_picker.add_item("Custom tileset PNG...")
	style_picker.set_item_metadata(style_picker.item_count - 1, "__custom__")
	style_picker.add_item("Save tileset template PNG...")
	style_picker.set_item_metadata(style_picker.item_count - 1, "__template__")

func _on_style_picked(idx: int) -> void:
	var sid: String = style_picker.get_item_metadata(idx)
	if not world:
		return
	match sid:
		"__custom__":
			_rebuild_style_picker()
			_open_file_dialog("tileset", EditorFileDialog.FILE_MODE_OPEN_FILE, ["*.png ; Tileset (4 x 5 tiles)"])
		"__template__":
			_rebuild_style_picker()
			_open_file_dialog("template", EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.png ; PNG"], world.path.get_base_dir().path_join("map_tileset.png"))
		_:
			world.checkpoint()
			world.set_setting("map_style", sid)
			canvas.redraw()
			_set_status("Map style: %s" % IDPMapStyle.style_display_name(sid))

func _build_inspector_tab() -> void:
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.name = "Inspect"
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(inspector_scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector)

func _build_areas_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Areas"
	sidebar.add_child(box)
	box.add_child(IDPUi.hint("Areas are map zones (Hollow Knight: Crossroads, Greenpath...). Rooms take their color; new rooms drawn with the Room tool join the area marked \"new rooms\"."))
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "New area name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	var add := IDPUi.button("Add", "Create an area")
	var create := func() -> void:
		if world and not name_edit.text.strip_edges().is_empty():
			world.checkpoint()
			world.add_area(name_edit.text.strip_edges())
			_selected_area = name_edit.text.strip_edges()
			name_edit.text = ""
	add.pressed.connect(create)
	name_edit.text_submitted.connect(func(_t: String) -> void: create.call())
	row.add_child(add)
	area_tree = Tree.new()
	area_tree.hide_root = true
	area_tree.custom_minimum_size.y = 160
	area_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area_tree.item_selected.connect(func() -> void:
		_selected_area = area_tree.get_selected().get_metadata(0)
		_rebuild_area_editor()
		canvas.highlight_rooms.clear()
		for id in world.get_area_rooms(_selected_area):
			canvas.highlight_rooms[id] = true
		route_button.visible = true
		canvas.redraw())
	box.add_child(area_tree)
	area_box = VBoxContainer.new()
	box.add_child(area_box)

func _build_pin_dialog() -> void:
	pin_dialog = ConfirmationDialog.new()
	pin_dialog.title = "Add map pin"
	var box := VBoxContainer.new()
	pin_text = LineEdit.new()
	pin_text.placeholder_text = "Pin text"
	pin_text.custom_minimum_size.x = 320
	pin_text.text_submitted.connect(func(_t: String) -> void:
		pin_dialog.hide()
		_confirm_pin())
	pin_kind = OptionButton.new()
	for k in IDPAnnotations.PIN_KINDS:
		pin_kind.add_item(k.capitalize())
	box.add_child(pin_text)
	box.add_child(pin_kind)
	pin_dialog.add_child(box)
	pin_dialog.confirmed.connect(_confirm_pin)
	add_child(pin_dialog)

func _build_settings_dialog() -> void:
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "World settings"
	add_child(settings_dialog)

func _setup_filters() -> void:
	for child in filter_box.get_children():
		child.queue_free()
	for category in DEFAULT_FILTERS:
		var cb := CheckBox.new()
		cb.text = category
		var on: bool = current_filters.get(category, category in DEFAULT_FILTERS_ON)
		cb.button_pressed = on
		current_filters[category] = on
		cb.toggled.connect(func(pressed: bool) -> void:
			current_filters[category] = pressed
			canvas.redraw())
		filter_box.add_child(cb)
	canvas.marker_filters = current_filters

# --- World files ------------------------------------------------------------------------

func _refresh_world_list() -> void:
	var found: PackedStringArray = []
	_find_world_files("res://", found, 0)
	if not world_path.is_empty() and not world_path in found:
		found.append(world_path)
	world_picker.clear()
	for p in found:
		world_picker.add_item(p.trim_prefix("res://"), world_picker.item_count)
		world_picker.set_item_metadata(world_picker.item_count - 1, p)
	world_picker.add_separator()
	world_picker.add_item("New world...", WorldItem.NEW)
	world_picker.add_item("Open world...", WorldItem.OPEN)
	world_picker.add_item("Import from MetSys map...", WorldItem.IMPORT_METSYS)
	world_picker.add_item("Reload", WorldItem.RELOAD)
	_select_world_in_picker()

func _find_world_files(dir_path: String, out: PackedStringArray, depth: int) -> void:
	if depth > 6:
		return
	for f in DirAccess.get_files_at(dir_path):
		if IDPWorld.is_world_file(f):
			out.append(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		if not d.begins_with(".") and d != "addons" and d != EXPORT_DIR.get_file():
			_find_world_files(dir_path.path_join(d), out, depth + 1)

func _select_world_in_picker() -> void:
	for i in world_picker.item_count:
		if world_picker.get_item_metadata(i) is String and world_picker.get_item_metadata(i) == world_path:
			world_picker.select(i)
			return
	world_picker.select(-1)
	world_picker.text = "(no world)" if world_path.is_empty() else world_path.get_file()

func _on_world_picked(idx: int) -> void:
	var id := world_picker.get_item_id(idx)
	_select_world_in_picker()
	match id:
		WorldItem.NEW:
			_open_file_dialog("new_world", EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.idpworld.json ; IDP World"], "res://world.idpworld.json")
		WorldItem.OPEN:
			_open_file_dialog("open_world", EditorFileDialog.FILE_MODE_OPEN_FILE, ["*.idpworld.json ; IDP World"])
		WorldItem.IMPORT_METSYS:
			_open_file_dialog("import_metsys", EditorFileDialog.FILE_MODE_OPEN_FILE, ["*.txt ; MetSys map data"], _metsys_map_path())
		WorldItem.RELOAD:
			load_world(world_path)
		_:
			load_world(world_picker.get_item_metadata(idx))

func _open_file_dialog(action: String, mode: int, filters: PackedStringArray, current_path := "") -> void:
	_dialog_action = action
	file_dialog.file_mode = mode
	file_dialog.clear_filters()
	for f in filters:
		file_dialog.add_filter(f.get_slice(";", 0).strip_edges(), f.get_slice(";", 1).strip_edges())
	if not current_path.is_empty():
		file_dialog.current_path = current_path
	file_dialog.popup_file_dialog()

func _on_file_dialog_file(p: String) -> void:
	match _dialog_action:
		"new_world":
			create_world(p)
		"open_world":
			load_world(p)
		"import_metsys":
			import_metsys_map(p)
		"assign_scene":
			if world.has_room(_dialog_room):
				world.checkpoint()
				world.set_room_scene(_dialog_room, p)
				_scan_paths([p])
		"create_scene":
			create_scene_for_room(_dialog_room, p)
		"game_scene":
			create_game_scene(p)
		"add_scenes":
			_on_file_dialog_files(PackedStringArray([p]))
		"tileset":
			IDPMapStyle.clear_cache()
			world.checkpoint()
			world.set_setting("map_style", "tileset:" + p)
			_rebuild_style_picker()
			canvas.redraw()
			_set_status("Map style: %s. Layout: 4 x 5 square tiles (16 edge masks + 4 inner corners), drawn in white/gray to be tinted by area color." % p.get_file())
		"template":
			var current: String = world.get_setting("map_style", "handdrawn")
			var err := IDPMapStyle.save_template(current, p)
			EditorInterface.get_resource_filesystem().scan()
			_set_status("Saved %s. Edit it, then pick it with Style > Custom tileset PNG..." % p if err == OK else "Could not save %s (error %d)" % [p, err])

func _on_file_dialog_files(paths: PackedStringArray) -> void:
	if _dialog_action == "add_scenes":
		_on_scenes_dropped(paths, canvas.screen_to_world(canvas.size / 2.0))

func create_world(p: String) -> void:
	if not IDPWorld.is_world_file(p):
		p = p.get_basename().get_basename() + IDPWorld.EXTENSION
	var w := IDPWorld.new()
	w.path = p
	w.data.name = p.get_file().trim_suffix(IDPWorld.EXTENSION).capitalize()
	w.save()
	load_world(p)
	_set_status("Created %s. Press R and drag to draw a room, or drop scenes on the map." % p)

## Converts a MetSys MapData.txt (and its panel annotations) into a world file next to it.
func import_metsys_map(map_path: String) -> void:
	var model := IDPMapModel.load_file(map_path)
	if model.rooms.is_empty():
		_set_status("No rooms found in %s" % map_path)
		return
	var ann := IDPAnnotations.load_for_map(map_path)
	var w := IDPWorld.from_metsys(model, ann, _metsys_cell_size())
	var target := map_path.get_basename() + IDPWorld.EXTENSION
	var n := 2
	while FileAccess.file_exists(target):
		target = "%s_%d%s" % [map_path.get_basename(), n, IDPWorld.EXTENSION]
		n += 1
	w.path = target
	w.save()
	load_world(target)
	_set_status("Imported %d rooms from %s into %s" % [w.get_room_ids().size(), map_path.get_file(), target])

func _metsys_node() -> Node:
	return get_tree().root.get_node_or_null(^"MetSys") if get_tree() else null

func _metsys_map_path() -> String:
	var ms := _metsys_node()
	return ms.settings.map_data_file if ms and ms.get("settings") else "res://MapData.txt"

func _metsys_cell_size() -> Vector2:
	var ms := _metsys_node()
	return ms.settings.in_game_cell_size if ms and ms.get("settings") else Vector2(1152, 648)

func load_world(p: String) -> void:
	if p.is_empty() or not FileAccess.file_exists(p):
		_set_status("World file not found: %s" % p)
		return
	var same := p == world_path
	if world and world.changed.is_connected(_on_world_changed):
		if _save_timer.time_left > 0:
			_save_world()
		world.changed.disconnect(_on_world_changed)
	world_path = p
	world = IDPWorld.load_world(p)
	world.changed.connect(_on_world_changed)
	_last_modified = FileAccess.get_modified_time(p)
	if ProjectSettings.get_setting(SETTING_WORLD_FILE, "") != p:
		ProjectSettings.set_setting(SETTING_WORLD_FILE, p)
		ProjectSettings.save()
	_refresh_world_list()
	_rebuild_layer_picker()
	_rebuild_style_picker()
	_refresh_palette()
	if not same:
		canvas.selected_room = ""
		canvas.route.clear()
		canvas.highlight_rooms.clear()
		canvas.layer = world.get_layers()[0] if not world.get_layers().is_empty() else 0
		_select_layer_in_picker(canvas.layer)
		scene_database = {}
	_refresh()
	if not same:
		_fit_when_ready()
	_rescan_world_scenes(not same)
	_set_status("Opened %s: %d rooms, %d areas" % [p.get_file(), world.get_room_ids().size(), world.get_areas().size()])

func _fit_when_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	canvas.fit_to_layer()

func _check_world_file_changed() -> void:
	if world_path.is_empty() or not FileAccess.file_exists(world_path) or not is_visible_in_tree():
		return
	var m := FileAccess.get_modified_time(world_path)
	if m != _last_modified and _save_timer.time_left <= 0:
		_last_modified = m
		load_world(world_path)
		_set_status("World file changed on disk, reloaded.")

func _on_world_changed() -> void:
	_save_timer.start()
	_refresh_timer.start()
	canvas.redraw()

func _save_world() -> void:
	if not world:
		return
	var err := world.save()
	if err != OK:
		_set_status("Could not save %s (error %d)" % [world.path, err])
	_last_modified = FileAccess.get_modified_time(world_path)

func _rebuild_layer_picker() -> void:
	layer_picker.clear()
	for l in world.get_layers():
		layer_picker.add_item("%d: %s" % [l, world.get_layer_name(l)], l)
	layer_picker.add_item("+ Add layer", 9999)
	_select_layer_in_picker(canvas.layer)

func _select_layer_in_picker(l: int) -> void:
	var idx := layer_picker.get_item_index(l)
	if idx >= 0:
		layer_picker.select(idx)

func _set_layer(l: int) -> void:
	canvas.set_layer(l)
	_select_layer_in_picker(l)
	_refresh_room_list()

func _add_layer() -> void:
	world.checkpoint()
	var names := world.get_layer_names()
	names.append("Layer %d" % names.size())
	world.data.layers = Array(names)
	world._touch()
	_rebuild_layer_picker()
	_set_layer(names.size() - 1)

# --- Scanning ----------------------------------------------------------------------------

func _rescan_world_scenes(full: bool) -> void:
	if not world:
		return
	var paths: Array[String] = []
	for id in world.get_room_ids():
		var p := world.get_scene_path(id)
		if not p.is_empty() and not p in paths and (full or not scene_database.has(p)):
			paths.append(p)
	if not paths.is_empty():
		_scan_paths(paths)

func _scan_paths(paths: Array) -> void:
	var typed: Array[String] = []
	typed.assign(paths)
	if _scanner and _scanner.is_scanning:
		_scanner.cancel()
	_scanner = IDPSceneScanner.new(world.get_default_room_size() if world else Vector2(1152, 648))
	_scanner.require_room_instance = false
	_scanner.scan_progress_updated.connect(func(current: int, total: int, file: String) -> void:
		progress_bar.visible = true
		progress_bar.max_value = total
		progress_bar.value = current
		_set_status("Scanning %d/%d: %s" % [current, total, file]))
	var scanner := _scanner
	var db: Dictionary = await scanner.scan_paths(typed)
	if scanner != _scanner:
		return
	progress_bar.visible = false
	var merged := scene_database.duplicate()
	for p in typed:
		if db.has(p):
			merged[p] = db[p]
		else:
			merged.erase(p)
	scene_database = merged
	canvas.refresh_previews()
	_refresh()
	_set_status("Scanned %d scene(s)." % typed.size())

func on_scene_saved(p: String) -> void:
	if world and not world.find_room_by_scene(p).is_empty():
		_scan_paths([p])

# --- Map view / Room view --------------------------------------------------------------------

func show_map_view() -> void:
	if room_view.visible:
		room_view.close_room(true)
	room_view.visible = false
	canvas.visible = true
	map_view_button.set_pressed_no_signal(true)
	_show_room_sections(false)
	canvas.redraw()

## Paints the room's actual contents. A room without a scene gets one first.
func show_room_view(id: String) -> void:
	if not world or not world.has_room(id):
		_set_status("Select a room on the map first, then open the Room view.")
		map_view_button.set_pressed_no_signal(true)
		return
	if world.get_scene_path(id).is_empty():
		world.checkpoint()
		var path := _default_scene_path(id)
		var err := IDPWorldSceneTools.create_scene_for_room(world, id, path)
		if err != OK:
			_set_status("Could not create a scene for %s (error %d)." % [id, err])
			map_view_button.set_pressed_no_signal(true)
			return
		EditorInterface.get_resource_filesystem().update_file(path)
	var error := room_view.open_room(world, id)
	if not error.is_empty():
		_set_status(error)
		map_view_button.set_pressed_no_signal(true)
		return
	canvas.visible = false
	room_view.visible = true
	room_view_button.set_pressed_no_signal(true)
	_show_room_sections(true)
	_set_status("Room view: %s. Paint terrain, or press Generate cave to start from the room's shape on the map." % id)

## The tool panel shows the map tools with the Map view and the room brushes with the
## Room view.
func _show_room_sections(room: bool) -> void:
	for section in [SECTION_TOOLS, SECTION_DISPLAY, SECTION_MARKERS]:
		side_panel.set_section_visible(section, not room)
	side_panel.set_section_visible(SECTION_ROOM, room)
	var tiles := sidebar.get_tab_idx_from_control(room_view.palette)
	sidebar.set_tab_hidden(tiles, not room)
	if room:
		sidebar.current_tab = tiles
	elif sidebar.current_tab == tiles:
		sidebar.current_tab = 0

func _on_room_saved(path: String) -> void:
	EditorInterface.get_resource_filesystem().update_file(path)
	if path in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(path)
	_scan_paths([path])

# --- Refresh -------------------------------------------------------------------------------

func _refresh() -> void:
	if not world:
		return
	graph = IDPGraph.from_world(world, scene_database)
	analysis = IDPAnalysis.new(graph, world, scene_database).run()
	issues = IDPWorldValidator.run(world, analysis, scene_database)
	canvas.issue_rooms.clear()
	for issue in issues:
		if not issue.room_id.is_empty():
			canvas.issue_rooms[issue.room_id] = maxi(canvas.issue_rooms.get(issue.room_id, 0), issue.severity)
	canvas.set_data(world, analysis, scene_database)
	# Style may change through undo/redo or the file on disk.
	var shown_style = style_picker.get_item_metadata(style_picker.selected) if style_picker.selected >= 0 else null
	if shown_style != world.get_setting("map_style", "handdrawn"):
		_rebuild_style_picker()
	undo_button.disabled = not world.can_undo()
	redo_button.disabled = not world.can_redo()
	_refresh_room_list()
	_refresh_area_list()
	views.refresh(analysis, issues, not scene_database.is_empty())
	var sig := _inspector_sig(canvas.selected_room)
	if _inspector_room != canvas.selected_room or sig != _inspector_signature:
		_rebuild_inspector()
	else:
		_update_inspector_info()

func _refresh_room_list() -> void:
	room_tree.clear()
	if not world or not analysis:
		return
	var root := room_tree.create_item()
	var search := room_search.text.strip_edges().to_lower()
	var ids := world.get_room_ids()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var la := world.get_room_layer(a)
		var lb := world.get_room_layer(b)
		if la != lb:
			return la < lb
		if world.get_room_area(a) != world.get_room_area(b):
			return world.get_room_area(a) < world.get_room_area(b)
		return a.naturalnocasecmp_to(b) < 0)
	for id in ids:
		var info := analysis.get_info(id)
		if not search.is_empty():
			var hay := " ".join([id, info.name, info.area, info.type, world.get_scene_path(id), ", ".join(info.boss_names), ", ".join(info.grants)]).to_lower()
			if not hay.contains(search):
				continue
		var item := room_tree.create_item(root)
		var text: String = info.name
		if world.get_room_layer(id) != canvas.layer:
			text += "  [L%d]" % world.get_room_layer(id)
		if not world.has_scene_reference(id):
			text += "  (no scene)"
		item.set_text(0, text)
		item.set_icon(0, IDPUi.type_icon(info.type))
		item.set_tooltip_text(0, "%s\n%s" % [id, world.get_scene_path(id)])
		item.set_text(1, info.area)
		if not str(info.area).is_empty():
			item.set_custom_color(1, world.get_area_color(info.area).lightened(0.3))
		var sphere: int = analysis.sphere_of.get(id, -1)
		item.set_text(2, str(sphere) if sphere >= 0 else ("locked" if id in analysis.locked else "-"))
		item.set_metadata(0, id)
		if id == canvas.selected_room:
			_filling_list = true
			item.select(0)
			_filling_list = false

func _refresh_area_list() -> void:
	area_tree.clear()
	var root := area_tree.create_item()
	for a in world.get_areas():
		var item := area_tree.create_item(root)
		var n := world.get_area_rooms(a).size()
		item.set_text(0, "%s  (%d room%s)%s" % [a, n, "" if n == 1 else "s", "  - new rooms" if a == canvas.new_room_area else ""])
		item.set_icon(0, IDPUi.color_icon(world.get_area_color(a), 14))
		item.set_metadata(0, a)
		if a == _selected_area:
			item.select(0)
	if not world.has_area(_selected_area):
		_selected_area = ""
	_rebuild_area_editor()

func _rebuild_area_editor() -> void:
	for c in area_box.get_children():
		c.queue_free()
	if _selected_area.is_empty() or not world.has_area(_selected_area):
		return
	var a := _selected_area
	var grid := GridContainer.new()
	grid.columns = 2
	area_box.add_child(grid)
	var name_edit := IDPUi.field_line(grid, "Name", a, "")
	IDPUi.commit_line(name_edit, func(t: String) -> void:
		world.checkpoint()
		if canvas.new_room_area == a:
			canvas.new_room_area = t.strip_edges()
		_selected_area = t.strip_edges()
		world.rename_area(a, t.strip_edges()))
	grid.add_child(IDPUi.label("Color"))
	var picker := ColorPickerButton.new()
	picker.color = world.get_area_color(a)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(60, 24)
	picker.popup_closed.connect(func() -> void:
		world.checkpoint()
		world.set_area_value(a, "color", "#" + picker.color.to_html(false)))
	grid.add_child(picker)
	var zone := IDPUi.field_line(grid, "Map zone", str(world.get_areas()[a].get("map_zone", "")), "e.g. GREENHOUSE")
	zone.tooltip_text = "Id your game uses for this area (Hollow Knight calls these map zones)."
	IDPUi.commit_line(zone, func(t: String) -> void: world.set_area_value(a, "map_zone", t.strip_edges()))
	var row := HFlowContainer.new()
	area_box.add_child(row)
	var for_new := IDPUi.button("Use for new rooms", "Rooms drawn with the Room tool join this area")
	for_new.pressed.connect(func() -> void:
		canvas.new_room_area = a
		_refresh_area_list())
	row.add_child(for_new)
	var assign := IDPUi.button("Assign selected room", "Move the selected room into this area")
	assign.disabled = not world.has_room(canvas.selected_room)
	assign.pressed.connect(func() -> void:
		world.checkpoint()
		world.set_room_value(canvas.selected_room, "area", a))
	row.add_child(assign)
	var reset_label := IDPUi.button("Reset label position", "Place the area name automatically again")
	reset_label.pressed.connect(func() -> void:
		world.checkpoint()
		world.data.areas[a].erase("label_pos")
		world._touch())
	row.add_child(reset_label)
	var remove := IDPUi.button("Delete area", "Rooms keep existing but leave the area")
	remove.pressed.connect(func() -> void:
		world.checkpoint()
		world.remove_area(a))
	row.add_child(remove)

# --- Selection & canvas callbacks -----------------------------------------------------------

func select_room(id: String, center := false) -> void:
	if not world or not world.has_room(id):
		return
	if world.get_room_layer(id) != canvas.layer:
		_set_layer(world.get_room_layer(id))
	canvas.selected_room = id
	canvas.selected_gate = ""
	if center:
		canvas.center_on_room(id)
	canvas.redraw()
	_rebuild_inspector()
	_set_status("%s  %s" % [id, world.get_scene_path(id)])

func _on_canvas_room_selected(id: String) -> void:
	if not _link_source.is_empty():
		if not id.is_empty() and id != _link_source:
			world.checkpoint()
			world.add_link(_link_source, id, "")
			_set_status("Linked %s <-> %s" % [_link_source, id])
		var src := _link_source
		_link_source = ""
		canvas.selected_room = src
		_rebuild_inspector()
		return
	if id.is_empty():
		_clear_route_and_highlight()
		_rebuild_inspector()
		return
	_rebuild_inspector()
	sidebar.current_tab = inspector_scroll.get_index()
	if room_tree.get_root():
		_filling_list = true
		for item in room_tree.get_root().get_children():
			if item.get_metadata(0) == id:
				item.select(0)
		_filling_list = false

func _on_room_activated(id: String) -> void:
	var p := world.get_scene_path(id)
	if not p.is_empty():
		EditorInterface.open_scene_from_path(p)
		_set_status("Opened %s" % p)
	else:
		_dialog_room = id
		_open_file_dialog("create_scene", EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.tscn ; Scene"], _default_scene_path(id))

func _on_canvas_hover(id: String, world_pos: Vector2) -> void:
	if not _link_source.is_empty():
		return
	var text := "x %d, y %d" % [world_pos.x, world_pos.y]
	if not id.is_empty():
		text += "  |  %s" % id
		var area := world.get_room_area(id)
		if not area.is_empty():
			text += "  (%s)" % area
		var local := world_pos - world.get_origin(id)
		text += "  |  scene-local %d, %d" % [local.x, local.y]
	_set_status(text)

func _show_route(from_id: String, to_id: String) -> void:
	var path := analysis.find_path(from_id, to_id)
	if path.is_empty():
		_set_status("No route between %s and %s." % [from_id, to_id])
		return
	canvas.route = path
	route_button.visible = true
	canvas.redraw()
	_set_status("Route %s -> %s: %d transitions" % [from_id, to_id, path.size() - 1])

func _clear_route_and_highlight() -> void:
	canvas.route.clear()
	canvas.highlight_rooms.clear()
	route_button.visible = false
	canvas.redraw()

func _request_pin(world_pos: Vector2) -> void:
	_pending_pin_pos = world_pos
	pin_text.text = ""
	pin_dialog.popup_centered()
	pin_text.grab_focus()

func _confirm_pin() -> void:
	var text := pin_text.text.strip_edges()
	if text.is_empty() or not world:
		return
	world.checkpoint()
	world.add_pin(canvas.layer, _pending_pin_pos, text, IDPAnnotations.PIN_KINDS[pin_kind.selected])
	pin_text.text = ""

func _nearest_pin(world_pos: Vector2) -> int:
	var best := -1
	var best_d := 24.0 / canvas.zoom
	var pins := world.get_pins()
	for i in pins.size():
		if int(pins[i].layer) != canvas.layer:
			continue
		var d := Vector2(float(pins[i].x), float(pins[i].y)).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = i
	return best

## Drop: onto a room without a scene assigns it; elsewhere each scene becomes a new room.
func _on_scenes_dropped(files: PackedStringArray, world_pos: Vector2) -> void:
	if not world:
		_set_status("Create or open a world first.")
		return
	world.checkpoint()
	var target := world.room_at(world_pos, canvas.layer)
	if files.size() == 1 and not target.is_empty() and not world.has_scene_reference(target):
		# Fill a painted room: the scene's (0, 0) goes to the room's top-left corner, the room
		# takes the scene's name if it still has a generated one, and the scene's own gate
		# nodes are added when the room has no gates yet.
		world.rebase_origin(target, world.get_room_bounds(target).position)
		world.set_room_scene(target, files[0])
		if RegEx.create_from_string("^Room(_[0-9]+)?$").search(target):
			target = world.rename_room(target, files[0].get_file().get_basename())
		var meta := IDPSceneScanner.new(world.get_default_room_size()).analyze_scene_any(files[0])
		if world.get_gates(target).is_empty():
			IDPWorldSceneTools.import_gates(world, target, meta)
		canvas.selected_room = target
		_scan_paths([files[0]])
		_refresh_palette()
		_set_status("Filled painted room %s with %s." % [target, files[0].get_file()])
		return
	var scanner := IDPSceneScanner.new(world.get_default_room_size())
	var pos := world_pos
	var created: Array[String] = []
	for f in files:
		var meta := scanner.analyze_scene_any(f)
		scene_database[f] = meta
		var id := IDPWorldSceneTools.place_scene(world, f, meta, pos, canvas.layer, canvas.new_room_area)
		created.append(id)
		pos.x = world.get_room_bounds(id).end.x + world.get_grid() * 2
	scene_database = scene_database.duplicate()
	if not created.is_empty():
		canvas.selected_room = created[-1]
	_refresh()
	_refresh_palette()
	_set_status("Placed %d scene(s): %s. Gates found in the scenes were added." % [created.size(), ", ".join(created)])

# --- Inspector --------------------------------------------------------------------------------

func _inspector_sig(id: String) -> String:
	if not world or not world.has_room(id):
		return ""
	var room: Dictionary = world.data.rooms[id]
	return JSON.stringify([room.get("gates", {}), room.get("rects", []), room.get("scene", ""), room.get("area", ""), world.get_links().size(), world.get_areas().keys(), id == analysis.start_room_id if analysis else false])

func _rebuild_inspector() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	_inspector_info = null
	_inspector_room = canvas.selected_room
	_inspector_signature = _inspector_sig(_inspector_room)
	if not world:
		inspector.add_child(IDPUi.hint("Non-linear mode: draw rooms freely and connect them with gates, like a Hollow Knight map.\n\nOpen the world picker in the tool panel on the left:\n- New world... starts an empty map.\n- Import from MetSys map... converts a MetSys MapData.txt."))
		return
	if not world.has_room(_inspector_room):
		inspector.add_child(IDPUi.hint("Select a room to edit it.\n\nR: draw a room, E: extend the selected room, G: add gates, P: pins.\nDrag .tscn files from the FileSystem dock onto the map to place scenes.\nDrag from a gate to another gate to connect rooms.\nDouble-click a room to open (or create) its scene. Right-click for more."))
		return
	var id := _inspector_room
	if not analysis or not analysis.room_info.has(id):
		# Room created or renamed since the last (debounced) refresh: refresh now, which
		# rebuilds the inspector with up-to-date analysis.
		_refresh()
		return
	var info := analysis.get_info(id)
	var meta: Dictionary = scene_database.get(world.get_scene_path(id), {})

	inspector.add_child(IDPUi.title(id, 18))
	var scene_path := world.get_scene_path(id)
	var path_label := IDPUi.label(scene_path if not scene_path.is_empty() else ("Missing scene: " + str(world.data.rooms[id].get("scene", "")) if world.has_scene_reference(id) else "No scene assigned"))
	path_label.modulate.a = 0.65
	path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inspector.add_child(path_label)

	var actions := HFlowContainer.new()
	inspector.add_child(actions)
	if scene_path.is_empty():
		var create := IDPUi.button("Create scene...", "Create a new scene for this room with bounds guides and one IDPGate per gate")
		create.pressed.connect(func() -> void:
			_dialog_room = id
			_open_file_dialog("create_scene", EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.tscn ; Scene"], _default_scene_path(id)))
		actions.add_child(create)
		var pick := IDPUi.button("Assign scene...", "Use an existing scene for this room")
		pick.pressed.connect(func() -> void:
			_dialog_room = id
			_open_file_dialog("assign_scene", EditorFileDialog.FILE_MODE_OPEN_FILE, ["*.tscn, *.scn ; Scenes"]))
		actions.add_child(pick)
	else:
		var open := IDPUi.button("Open scene", "Open the room scene in the editor")
		open.pressed.connect(func() -> void: EditorInterface.open_scene_from_path(scene_path))
		actions.add_child(open)
		var play := IDPUi.button("Play from here", "Run the game starting in this room, at its save point if it has one. Right-click the map to start at an exact spot.")
		play.pressed.connect(func() -> void: _play_from(id, world.get_room_label_pos(id), true))
		actions.add_child(play)
	var start := IDPUi.button("Start room" if id == analysis.start_room_id else "Set as start", "Progression is computed from the start room")
	start.disabled = id == analysis.start_room_id
	start.pressed.connect(func() -> void:
		world.checkpoint()
		world.set_start_room(id))
	actions.add_child(start)
	var paint_room := IDPUi.button("Paint room", "Open the Room view to paint this room's terrain, background and decorations")
	paint_room.pressed.connect(func() -> void: show_room_view(id))
	actions.add_child(paint_room)
	var center := IDPUi.button("Center", "Center the map on this room")
	center.pressed.connect(func() -> void: canvas.center_on_room(id))
	actions.add_child(center)
	var dup := IDPUi.button("Duplicate", "Copy this room's shape and gates (Ctrl+D)")
	dup.pressed.connect(func() -> void:
		world.checkpoint()
		canvas.selected_room = world.duplicate_room(id))
	actions.add_child(dup)
	var del := IDPUi.button("Delete", "Delete this room (Ctrl+Z to undo)")
	del.pressed.connect(func() -> void:
		canvas.selected_gate = ""
		canvas.delete_selection())
	actions.add_child(del)

	inspector.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	inspector.add_child(grid)
	var id_edit := IDPUi.field_line(grid, "Room ID", id, "")
	id_edit.tooltip_text = "Unique id used by gates and at runtime (Hollow Knight uses scene names like Crossroads_01)."
	IDPUi.commit_line(id_edit, func(t: String) -> void:
		world.checkpoint()
		canvas.selected_room = world.rename_room(id, t))
	var name_edit := IDPUi.field_line(grid, "Name", world.get_room_value(id, "name", ""), id)
	IDPUi.commit_line(name_edit, func(t: String) -> void:
		world.checkpoint()
		world.set_room_value(id, "name", t.strip_edges()))
	grid.add_child(IDPUi.label("Area"))
	var area_opt := OptionButton.new()
	area_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area_opt.add_item("(none)")
	area_opt.set_item_metadata(0, "")
	for a in world.get_areas():
		area_opt.add_icon_item(IDPUi.color_icon(world.get_area_color(a)), a)
		area_opt.set_item_metadata(area_opt.item_count - 1, a)
		if a == world.get_room_area(id):
			area_opt.select(area_opt.item_count - 1)
	area_opt.item_selected.connect(func(idx: int) -> void:
		world.checkpoint()
		world.set_room_value(id, "area", area_opt.get_item_metadata(idx)))
	grid.add_child(area_opt)
	var type_opt := IDPUi.field_option(grid, "Type", IDPAnnotations.ROOM_TYPES, world.get_room_value(id, "type", ""), "(auto: %s)" % (str(info.type).capitalize() if not str(info.type).is_empty() else "normal"))
	type_opt.item_selected.connect(func(idx: int) -> void:
		world.checkpoint()
		world.set_room_value(id, "type", IDPAnnotations.ROOM_TYPES[idx]))
	var status_opt := IDPUi.field_option(grid, "Status", IDPAnnotations.STATUSES, world.get_room_value(id, "status", ""), "(none)")
	status_opt.item_selected.connect(func(idx: int) -> void:
		world.checkpoint()
		world.set_room_value(id, "status", IDPAnnotations.STATUSES[idx]))
	var scanned_boss: PackedStringArray = []
	for b in meta.get("bosses", []):
		scanned_boss.append(b.name)
	var boss_edit := IDPUi.field_line(grid, "Boss", world.get_room_value(id, "boss", ""), ", ".join(scanned_boss) if not scanned_boss.is_empty() else "boss name (marks a boss room)")
	IDPUi.commit_line(boss_edit, func(t: String) -> void:
		world.checkpoint()
		world.set_room_value(id, "boss", t.strip_edges())
		if not t.strip_edges().is_empty() and str(world.get_room_value(id, "type", "")).is_empty():
			world.set_room_value(id, "type", "boss"))
	var scanned_grants: PackedStringArray = meta.get("grants", PackedStringArray())
	var grants_edit := IDPUi.field_line(grid, "Grants", ", ".join(world.get_room_grants(id)), ("scanned: " + ", ".join(scanned_grants)) if not scanned_grants.is_empty() else "abilities/keys found here, e.g. dash")
	IDPUi.commit_line(grants_edit, func(t: String) -> void:
		world.checkpoint()
		world.set_room_value(id, "grants", Array(IDPAnnotations.parse_list(t))))
	grid.add_child(IDPUi.label("Layer"))
	var layer_spin := SpinBox.new()
	layer_spin.min_value = 0
	layer_spin.max_value = 64
	layer_spin.value = world.get_room_layer(id)
	layer_spin.value_changed.connect(func(v: float) -> void:
		world.checkpoint()
		world.data.rooms[id].layer = int(v)
		world._touch()
		_rebuild_layer_picker())
	grid.add_child(layer_spin)

	inspector.add_child(IDPUi.label("Notes (TODO lines show up in Issues)"))
	var notes := TextEdit.new()
	notes.custom_minimum_size.y = 60
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.text = world.get_room_value(id, "notes", "")
	notes.focus_exited.connect(func() -> void:
		if notes.text != world.get_room_value(id, "notes", ""):
			world.checkpoint()
			world.set_room_value(id, "notes", notes.text))
	inspector.add_child(notes)

	# Shape.
	inspector.add_child(HSeparator.new())
	var rects := world.get_local_rects(id)
	var bounds := world.get_room_bounds(id)
	inspector.add_child(IDPUi.title("Shape: %d x %d px, %d rectangle(s)" % [bounds.size.x, bounds.size.y, rects.size()]))
	var shape_row := HFlowContainer.new()
	inspector.add_child(shape_row)
	var fit := IDPUi.button("Fit to scene", "Resize the room to the scene's terrain")
	fit.disabled = not meta.get("content_rect", Rect2()).has_area()
	fit.pressed.connect(func() -> void:
		world.checkpoint()
		IDPWorldSceneTools.fit_room_to_scene(world, id, meta))
	shape_row.add_child(fit)
	var extend := IDPUi.button("Extend (E)", "Drag on the map to add a rectangle to this room")
	extend.pressed.connect(func() -> void:
		canvas.set_tool(IDPWorldCanvas.Tool.RECT)
		canvas.grab_focus())
	shape_row.add_child(extend)
	for i in rects.size():
		var row := HBoxContainer.new()
		inspector.add_child(row)
		var r := rects[i]
		var l := IDPUi.label("  #%d  %d,%d  %dx%d" % [i + 1, r.position.x, r.position.y, r.size.x, r.size.y])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if rects.size() > 1:
			var rm := IDPUi.button("x", "Remove this rectangle")
			rm.pressed.connect(func() -> void:
				world.checkpoint()
				world.remove_rect(id, i))
			row.add_child(rm)

	_build_gate_section(id, meta)
	_build_link_section(id)

	inspector.add_child(HSeparator.new())
	_inspector_info = RichTextLabel.new()
	_inspector_info.bbcode_enabled = true
	_inspector_info.fit_content = true
	_inspector_info.selection_enabled = true
	_inspector_info.meta_clicked.connect(func(m: Variant) -> void:
		if str(m).begins_with("room:"):
			select_room(str(m).trim_prefix("room:"), true))
	inspector.add_child(_inspector_info)
	_update_inspector_info()

func _build_gate_section(id: String, meta: Dictionary) -> void:
	inspector.add_child(HSeparator.new())
	var gates := world.get_gates(id)
	inspector.add_child(IDPUi.title("Gates (%d)" % gates.size()))
	var row := HFlowContainer.new()
	inspector.add_child(row)
	var add := IDPUi.menu_button("Add gate", "Add a transition on a side of the room")
	for s in IDPWorld.SIDES:
		add.get_popup().add_item(s.capitalize())
	add.get_popup().index_pressed.connect(func(idx: int) -> void:
		var side: String = IDPWorld.SIDES[idx]
		var b := world.get_room_bounds(id)
		var p: Vector2 = {"left": Vector2(b.position.x, b.get_center().y), "right": Vector2(b.end.x, b.get_center().y), "top": Vector2(b.get_center().x, b.position.y), "bot": Vector2(b.get_center().x, b.end.y), "door": b.get_center()}[side]
		world.checkpoint()
		canvas.selected_gate = world.add_gate(id, p, side if side == "door" else "", "", side != "door"))
	row.add_child(add)
	var has_transitions: bool = not meta.get("transitions", []).is_empty()
	var imp := IDPUi.button("Import from scene", "Add/move map gates to match the scene's gate nodes (left1, right1, IDPGate...)")
	imp.disabled = not has_transitions
	imp.pressed.connect(func() -> void:
		world.checkpoint()
		var n := IDPWorldSceneTools.import_gates(world, id, meta)
		_set_status("Imported %d gate(s) from the scene." % n))
	row.add_child(imp)
	var write := IDPUi.button("Write to scene", "Add an IDPGate node to the scene for every map gate it's missing (never deletes)")
	write.disabled = world.get_scene_path(id).is_empty() or gates.is_empty()
	write.pressed.connect(func() -> void: _write_gates_to_scene(id))
	row.add_child(write)
	for gate_name in gates:
		_add_gate_row(id, gate_name)

func _add_gate_row(id: String, gate_name: String) -> void:
	var gate := world.get_gate(id, gate_name)
	var box := VBoxContainer.new()
	inspector.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_edit := LineEdit.new()
	name_edit.text = gate_name
	name_edit.custom_minimum_size.x = 70
	name_edit.tooltip_text = "Gate name (Hollow Knight style: left1, right1, top1, bot1, door1)"
	IDPUi.commit_line(name_edit, func(t: String) -> void:
		world.checkpoint()
		world.rename_gate(id, gate_name, t))
	head.add_child(name_edit)
	var to: String = gate.get("to", "")
	var target := LinkButton.new()
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if world.has_gate(to, gate.get("to_gate", "")):
		target.text = "-> %s.%s" % [to, gate.to_gate]
		target.pressed.connect(func() -> void:
			select_room(to, true)
			canvas.selected_gate = gate.to_gate)
	else:
		target.text = "not connected" if to.is_empty() else "-> missing %s.%s" % [to, gate.get("to_gate", "")]
		target.modulate = Color(1, 0.55, 0.55)
		target.tooltip_text = "Drag from this gate on the map to another gate to connect."
	head.add_child(target)
	if not to.is_empty():
		var disc := IDPUi.button("Unlink", "Disconnect this gate")
		disc.pressed.connect(func() -> void:
			world.checkpoint()
			world.disconnect_gate(id, gate_name))
		head.add_child(disc)
	var rm := IDPUi.button("x", "Delete this gate")
	rm.pressed.connect(func() -> void:
		world.checkpoint()
		world.remove_gate(id, gate_name))
	head.add_child(rm)
	var fields := HBoxContainer.new()
	box.add_child(fields)
	var req := LineEdit.new()
	req.placeholder_text = "requires (e.g. dash)"
	req.text = ", ".join(gate.get("requires", []))
	req.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	IDPUi.commit_line(req, func(t: String) -> void:
		world.checkpoint()
		world.set_gate_value(id, gate_name, "requires", Array(IDPAnnotations.parse_list(t))))
	fields.add_child(req)
	var one_way := CheckBox.new()
	one_way.text = "One-way"
	one_way.tooltip_text = "Players can leave through this gate but not come back (drops, collapsing floors)"
	one_way.button_pressed = gate.get("one_way", false)
	one_way.toggled.connect(func(on: bool) -> void:
		world.checkpoint()
		world.set_gate_value(id, gate_name, "one_way", on))
	fields.add_child(one_way)

func _build_link_section(id: String) -> void:
	inspector.add_child(HSeparator.new())
	inspector.add_child(IDPUi.title("Links (elevators, stag stations, cross-layer)"))
	var links := world.get_links()
	for i in links.size():
		if links[i].a != id and links[i].b != id:
			continue
		var other: String = links[i].b if links[i].a == id else links[i].a
		var row := HBoxContainer.new()
		inspector.add_child(row)
		var lb := LinkButton.new()
		lb.text = "<-> %s" % other
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.pressed.connect(func() -> void: select_room(other, true))
		row.add_child(lb)
		var note := LineEdit.new()
		note.placeholder_text = "note"
		note.text = links[i].get("note", "")
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index := i
		IDPUi.commit_line(note, func(t: String) -> void: world.set_link_value(index, "note", t.strip_edges()))
		row.add_child(note)
		var req := LineEdit.new()
		req.placeholder_text = "requires"
		req.text = ", ".join(links[i].get("requires", []))
		req.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		IDPUi.commit_line(req, func(t: String) -> void: world.set_link_value(index, "requires", Array(IDPAnnotations.parse_list(t))))
		row.add_child(req)
		var rm := IDPUi.button("x", "Remove link")
		rm.pressed.connect(func() -> void:
			world.checkpoint()
			world.remove_link(index))
		row.add_child(rm)
	var add := IDPUi.button("Add link... (then click the target room)", "Connect rooms that have no gate between them on the map")
	add.pressed.connect(func() -> void:
		_link_source = id
		canvas.grab_focus()
		_set_status("Click the room to link with %s (switch layers if needed). Esc cancels." % id))
	inspector.add_child(add)

func _update_inspector_info() -> void:
	if not _inspector_info or not world.has_room(_inspector_room):
		return
	var id := _inspector_room
	var info := analysis.get_info(id)
	var meta: Dictionary = scene_database.get(world.get_scene_path(id), {})
	var t := ""
	var o := world.get_origin(id)
	t += "[b]World position:[/b] %d, %d (scene origin)\n" % [o.x, o.y]
	var sphere: int = analysis.sphere_of.get(id, -1)
	if sphere >= 0:
		t += "[b]Progression:[/b] sphere %d%s\n" % [sphere, " (start)" if id == analysis.start_room_id else ""]
	elif id in analysis.locked:
		t += "[b]Progression:[/b] [color=#ff7070]locked[/color]\n"
	else:
		t += "[b]Progression:[/b] [color=#ff7070]not connected to the start[/color]\n"
	var sd: int = analysis.save_distance.get(id, -1)
	t += "[b]Nearest save:[/b] %s\n" % ("this room" if sd == 0 else ("%d room(s) away" % sd if sd > 0 else "none reachable"))
	var roles: PackedStringArray = []
	if id in analysis.dead_ends:
		roles.append("dead end")
	if id in analysis.chokepoints:
		roles.append("chokepoint")
	if id in analysis.hubs:
		roles.append("hub")
	if not roles.is_empty():
		t += "[b]Topology:[/b] %s\n" % ", ".join(roles)
	var touching := world.get_touching_rooms(id)
	if not touching.is_empty():
		t += "[b]Touching on the map:[/b] %s\n" % ", ".join(touching.map(func(r: String) -> String: return "[url=room:%s]%s[/url]" % [r, r]))
	if meta.is_empty():
		t += "[i]Scene not scanned yet.[/i]\n"
	else:
		t += "[b]Contents:[/b] %d collectibles, %d enemies, %d save points, %d gate node(s)\n" % [meta.collectibles.size(), meta.enemies.size(), meta.save_points.size(), meta.get("transitions", []).size()]
		var c: Rect2 = meta.get("content_rect", Rect2())
		if c.has_area():
			t += "[b]Scene terrain:[/b] %d x %d px at %d, %d\n" % [c.size.x, c.size.y, c.position.x, c.position.y]
	_inspector_info.text = t

func _default_scene_path(id: String) -> String:
	var folder: String = world.get_setting("scene_folder", "res://rooms")
	return folder.path_join(id.to_snake_case() + ".tscn")

func create_scene_for_room(id: String, scene_path: String) -> void:
	if not scene_path.ends_with(".tscn") and not scene_path.ends_with(".scn"):
		scene_path += ".tscn"
	world.checkpoint()
	var err := IDPWorldSceneTools.create_scene_for_room(world, id, scene_path)
	if err != OK:
		_set_status("Could not create %s (error %d)" % [scene_path, err])
		return
	EditorInterface.get_resource_filesystem().update_file(scene_path)
	_scan_paths([scene_path])
	EditorInterface.open_scene_from_path(scene_path)
	_set_status("Created %s with %d gate(s); MapBounds shows the room's shape." % [scene_path, world.get_gates(id).size()])

## Generates a runnable IDPWorldGame scene for this world and makes it the Play-from-here host.
func create_game_scene(scene_path: String) -> void:
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	var err := IDPWorldSceneTools.create_game_scene(world, scene_path)
	if err != OK:
		_set_status("Could not create %s (error %d)" % [scene_path, err])
		return
	world.set_setting("play_scene", scene_path)
	EditorInterface.get_resource_filesystem().update_file(scene_path)
	EditorInterface.open_scene_from_path(scene_path)
	_set_status("Created %s: replace the placeholder Player with yours, then press F6 or use Play from here." % scene_path)

func _write_gates_to_scene(id: String) -> void:
	var p := world.get_scene_path(id)
	if p in EditorInterface.get_open_scenes():
		_set_status("Close %s first (or add the gates there by hand): writing to an open scene would be overwritten when you save it." % p.get_file())
		return
	var n := IDPWorldSceneTools.write_gates(world, id)
	if n < 0:
		_set_status("Could not write gates to %s" % p)
		return
	EditorInterface.get_resource_filesystem().update_file(p)
	_scan_paths([p])
	_set_status("Wrote %d gate(s) to %s" % [n, p.get_file()])

# --- Context menu, play ------------------------------------------------------------------------

func _on_canvas_context(room_id: String, world_pos: Vector2, local_pos: Vector2) -> void:
	_context_room = room_id
	_context_pos = world_pos
	context_menu.clear()
	if not world:
		return
	if not room_id.is_empty():
		var has_scene := not world.get_scene_path(room_id).is_empty()
		if has_scene:
			context_menu.add_item("Open scene", ContextItem.OPEN)
			context_menu.add_item("Play from here", ContextItem.PLAY_HERE)
			context_menu.add_item("Run this room scene only", ContextItem.RUN_SCENE)
			context_menu.add_item("Fit room to scene", ContextItem.FIT)
		else:
			context_menu.add_item("Create scene...", ContextItem.CREATE_SCENE)
		context_menu.add_item("Paint room (actual view)", ContextItem.PAINT_ROOM)
		context_menu.add_item("Assign scene...", ContextItem.ASSIGN_SCENE)
		context_menu.add_separator()
		context_menu.add_item("Add gate here", ContextItem.ADD_GATE)
		context_menu.add_item("Set as start room", ContextItem.SET_START)
		if world.has_room(canvas.selected_room) and canvas.selected_room != room_id:
			context_menu.add_item("Route from selected room to here", ContextItem.ROUTE)
			context_menu.add_item("Link selected room to this room", ContextItem.LINK)
		context_menu.add_item("Duplicate room", ContextItem.DUPLICATE)
		context_menu.add_item("Delete room", ContextItem.DELETE)
		context_menu.add_separator()
		context_menu.add_item("Copy room id", ContextItem.COPY_ID)
	else:
		context_menu.add_item("New room here", ContextItem.ADD_ROOM)
	context_menu.add_item("Add pin here...", ContextItem.ADD_PIN)
	if _nearest_pin(world_pos) >= 0:
		context_menu.add_item("Remove nearest pin", ContextItem.REMOVE_PIN)
	context_menu.reset_size()
	context_menu.position = Vector2i(canvas.get_screen_position() + local_pos)
	context_menu.popup()

func _on_context_menu(item: int) -> void:
	var id := _context_room
	match item:
		ContextItem.OPEN:
			EditorInterface.open_scene_from_path(world.get_scene_path(id))
		ContextItem.PLAY_HERE:
			_play_from(id, _context_pos)
		ContextItem.RUN_SCENE:
			EditorInterface.play_custom_scene(world.get_scene_path(id))
		ContextItem.CREATE_SCENE:
			_dialog_room = id
			_open_file_dialog("create_scene", EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.tscn ; Scene"], _default_scene_path(id))
		ContextItem.ASSIGN_SCENE:
			_dialog_room = id
			_open_file_dialog("assign_scene", EditorFileDialog.FILE_MODE_OPEN_FILE, ["*.tscn, *.scn ; Scenes"])
		ContextItem.PAINT_ROOM:
			show_room_view(id)
		ContextItem.FIT:
			world.checkpoint()
			if not IDPWorldSceneTools.fit_room_to_scene(world, id, scene_database.get(world.get_scene_path(id), {})):
				_set_status("The scene has no terrain to fit to (TileMapLayer or StaticBody2D shapes).")
		ContextItem.ADD_GATE:
			world.checkpoint()
			canvas.selected_room = id
			canvas.selected_gate = world.add_gate(id, _context_pos)
		ContextItem.SET_START:
			world.checkpoint()
			world.set_start_room(id)
		ContextItem.ROUTE:
			_show_route(canvas.selected_room, id)
		ContextItem.LINK:
			world.checkpoint()
			world.add_link(canvas.selected_room, id, "")
		ContextItem.DUPLICATE:
			world.checkpoint()
			canvas.selected_room = world.duplicate_room(id)
		ContextItem.DELETE:
			canvas.selected_room = id
			canvas.selected_gate = ""
			canvas.delete_selection()
		ContextItem.COPY_ID:
			DisplayServer.clipboard_set(id)
		ContextItem.ADD_ROOM:
			world.checkpoint()
			var s := world.get_default_room_size()
			var new_id := world.add_room("Room_01", Rect2(world.snap(_context_pos - s / 2.0), s), canvas.layer, canvas.new_room_area)
			canvas.selected_room = new_id
			_rebuild_inspector()
		ContextItem.ADD_PIN:
			_request_pin(_context_pos)
		ContextItem.REMOVE_PIN:
			world.checkpoint()
			world.remove_pin(_nearest_pin(_context_pos))

## Runs the game starting in this room (see IDPPlayHere). With [param prefer_save_point]
## the player starts at the room's save point when it has one.
func _play_from(id: String, world_pos: Vector2, prefer_save_point := false) -> void:
	var p := world.get_scene_path(id)
	if p.is_empty():
		return
	var uid: String = world.data.rooms[id].get("scene", "")
	var local := world_pos - world.get_origin(id)
	var saves: Array = scene_database.get(p, {}).get("save_points", [])
	if prefer_save_point and not saves.is_empty():
		local = saves[0].position
	_set_status(IDPPlayHere.play(p, uid, world.get_room_layer(id), local, world.get_setting("play_scene", "")))

func _on_scenes_menu(item: int) -> void:
	if not world:
		_set_status("Create or open a world first.")
		return
	match item:
		ScenesItem.RESCAN:
			_rescan_world_scenes(true)
		ScenesItem.ADD_SCENES:
			_open_file_dialog("add_scenes", EditorFileDialog.FILE_MODE_OPEN_FILES, ["*.tscn, *.scn ; Scenes"])
		ScenesItem.AUTO_DOORS:
			world.checkpoint()
			var n := world.auto_gates_between_touching()
			_set_status("Added %d door(s): a connected gate pair on the longest shared edge of every touching room pair." % n)
		ScenesItem.AUTO_CONNECT:
			world.checkpoint()
			var n := world.auto_connect_gates()
			_set_status("Connected %d facing gate pair(s) within %d px." % [n, world.get_grid() * 3])
		ScenesItem.SETTINGS:
			_show_settings()
		ScenesItem.GAME_SCENE:
			_open_file_dialog("game_scene", EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.tscn ; Scene"], world_path.get_base_dir().path_join("game.tscn"))

func _show_settings() -> void:
	for c in settings_dialog.get_children():
		if c is GridContainer:
			c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	settings_dialog.add_child(grid)
	var name_edit := IDPUi.field_line(grid, "World name", world.get_world_name(), "")
	IDPUi.commit_line(name_edit, func(t: String) -> void:
		world.data.name = t
		world._touch())
	var grid_edit := IDPUi.field_line(grid, "Grid (px)", str(int(world.get_grid())), "32")
	grid_edit.tooltip_text = "Rooms, rects and gates snap to this. Use your tile size or a multiple of it."
	IDPUi.commit_line(grid_edit, func(t: String) -> void: world.set_setting("grid", maxi(1, t.to_int())))
	var s := world.get_default_room_size()
	var size_edit := IDPUi.field_line(grid, "Default room size", "%dx%d" % [s.x, s.y], "1152x648")
	IDPUi.commit_line(size_edit, func(t: String) -> void:
		var parts := t.split("x")
		if parts.size() == 2:
			world.set_setting("default_room_size", [parts[0].to_float(), parts[1].to_float()]))
	var cell := world.get_paint_cell()
	var cell_edit := IDPUi.field_line(grid, "Paint cell", "%dx%d" % [cell.x, cell.y], "e.g. 288x162")
	cell_edit.tooltip_text = "Size of one brush cell in world pixels. Default: a quarter of the default room size."
	IDPUi.commit_line(cell_edit, func(t: String) -> void:
		var parts := t.split("x")
		if parts.size() == 2 and parts[0].to_float() > 0 and parts[1].to_float() > 0:
			world.set_setting("paint_cell", [parts[0].to_float(), parts[1].to_float()])
			canvas.redraw())
	var folder_edit := IDPUi.field_line(grid, "New scene folder", world.get_setting("scene_folder", "res://rooms"), "res://rooms")
	IDPUi.commit_line(folder_edit, func(t: String) -> void: world.set_setting("scene_folder", t.strip_edges()))
	var template_edit := IDPUi.field_line(grid, "Scene template", world.get_setting("scene_template", ""), "optional .tscn used by Create scene")
	IDPUi.commit_line(template_edit, func(t: String) -> void: world.set_setting("scene_template", t.strip_edges()))
	var play_edit := IDPUi.field_line(grid, "Play scene", world.get_setting("play_scene", ""), "auto: game scene hosting the room")
	play_edit.tooltip_text = "Scene that Play from here boots with the room as its start. Empty: detected automatically."
	IDPUi.commit_line(play_edit, func(t: String) -> void: world.set_setting("play_scene", t.strip_edges()))
	var warn_edit := IDPUi.field_line(grid, "Save distance warning", str(world.get_setting("save_distance_warn", 4)), "4")
	IDPUi.commit_line(warn_edit, func(t: String) -> void: world.set_setting("save_distance_warn", maxi(1, t.to_int())))
	var layers_edit := IDPUi.field_line(grid, "Layer names", ", ".join(world.get_layer_names()), "Main, Dream")
	IDPUi.commit_line(layers_edit, func(t: String) -> void:
		var names: Array = []
		for n in t.split(","):
			names.append(n.strip_edges())
		world.data.layers = names
		world._touch()
		_rebuild_layer_picker())
	settings_dialog.popup_centered(Vector2i(460, 0))

# --- Export ----------------------------------------------------------------------------------

func _on_export_menu(item: int) -> void:
	if not world:
		return
	var base := "%s/%s_%s" % [EXPORT_DIR, world_path.get_file().trim_suffix(IDPWorld.EXTENSION), Time.get_datetime_string_from_system().replace(":", "-")]
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	match item:
		ExportItem.JSON:
			var out := {
				"world": world.data,
				"progression": IDPExporters.progression_to_dict(analysis),
				"issues": issues.map(func(i: Dictionary) -> Dictionary: return {"severity": i.severity, "category": i.category, "message": i.message, "room": i.room_id}),
				"scene_database": IDPExporters.sanitize_scene_db(scene_database),
			}
			_write_export(base + ".json", JSON.stringify(out, "\t"))
		ExportItem.DOT:
			var colors := {}
			for a in world.get_areas():
				colors[a] = world.get_area_color(a)
			_write_export(base + ".dot", IDPExporters.to_dot(analysis, colors))
		ExportItem.MARKDOWN:
			var connected := 0
			var total := 0
			for id in world.get_room_ids():
				for g in world.get_gates(id).values():
					total += 1
					if not str(g.get("to", "")).is_empty():
						connected += 1
			var summary := {"Rooms": world.get_room_ids().size(), "Areas": world.get_areas().size(), "Gates": "%d/%d connected" % [connected, total], "Layers": world.get_layers().size(), "Start room": analysis.start_room_id}
			var size_of := func(id: String) -> String:
				var b := world.get_room_bounds(id)
				return "%dx%d px" % [b.size.x, b.size.y]
			_write_export(base + ".md", IDPExporters.to_markdown(world.get_world_name(), summary, world, analysis, issues, size_of))
		ExportItem.PNG:
			_export_png(base + ".png")

func _write_export(p: String, content: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if not f:
		_set_status("Export failed: %s" % p)
		return
	f.store_string(content)
	f.close()
	_finish_export(p)

func _finish_export(p: String) -> void:
	_set_status("Exported %s" % p)
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.get_file_system_dock().navigate_to_path(p)

func _export_png(p: String) -> void:
	if _export_viewport:
		return
	var b := world.get_layer_bounds(canvas.layer)
	if not b.has_area():
		_set_status("Export failed: empty layer")
		return
	var clone := IDPWorldCanvas.new()
	clone.color_mode = canvas.color_mode
	clone.show = canvas.show.duplicate()
	clone.show.previews = false
	clone.marker_filters = canvas.marker_filters
	clone.issue_rooms = canvas.issue_rooms
	clone.route = canvas.route.duplicate()
	clone.layer = canvas.layer
	var margin := Vector2(260, 60)
	clone.zoom = clampf(7000.0 / maxf(b.size.x, b.size.y), 0.02, 0.5)
	var img_size := b.size * clone.zoom + margin * 2.0
	img_size.y += 20.0 + (17.0 * canvas.get_legend().size() + 12.0 if canvas.show.legend else 0.0)
	clone.pan = margin + Vector2(0, 20) - b.position * clone.zoom
	_export_viewport = SubViewport.new()
	_export_viewport.size = Vector2i(img_size)
	_export_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	clone.size = img_size
	_export_viewport.add_child(clone)
	add_child(_export_viewport)
	clone.set_data(world, analysis, scene_database)
	_set_status("Rendering map image...")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _export_viewport.get_texture().get_image()
	var err := img.save_png(p) if img else ERR_CANT_CREATE
	_export_viewport.queue_free()
	_export_viewport = null
	if err == OK:
		_finish_export(p)
	else:
		_set_status("PNG export failed (error %d)" % err)

# --- IDPAnalysisViews host callbacks ---------------------------------------------------------

func ui_select_room(id: String) -> void:
	canvas.highlight_rooms.clear()
	select_room(id, true)

func ui_focus_rooms(ids: Array, route: Array) -> void:
	canvas.highlight_rooms.clear()
	for id in ids:
		canvas.highlight_rooms[id] = true
	if route.size() == 2:
		canvas.route.assign(analysis.find_path(route[0], route[1]))
	route_button.visible = true
	var counts: Dictionary = {}
	for id in ids:
		if world.has_room(id):
			counts[world.get_room_layer(id)] = counts.get(world.get_room_layer(id), 0) + 1
	if not counts.is_empty() and not counts.has(canvas.layer):
		_set_layer(counts.keys()[0])
	canvas.redraw()

func ui_jump_to_issue(issue: Dictionary) -> void:
	if issue.get("pos", Vector2.INF) != Vector2.INF:
		_set_layer(int(issue.get("layer", canvas.layer)))
		if not issue.room_id.is_empty():
			canvas.selected_room = issue.room_id
			_rebuild_inspector()
		canvas.center_on(issue.pos)
	elif not issue.get("room_id", "").is_empty():
		select_room(issue.room_id, true)

func ui_set_start_from_selection() -> void:
	if world and world.has_room(canvas.selected_room):
		world.checkpoint()
		world.set_start_room(canvas.selected_room)

func ui_area_color(area: String) -> Color:
	return world.get_area_color(area) if world else IDPMapCanvas.area_color(area)

func ui_stats_header() -> String:
	var connected := 0
	var total := 0
	var no_scene := 0
	for id in world.get_room_ids():
		if not world.has_scene_reference(id):
			no_scene += 1
		for g in world.get_gates(id).values():
			total += 1
			if not str(g.get("to", "")).is_empty():
				connected += 1
	var t := "[b]%s[/b]  (%s)\n" % [world.get_world_name(), world_path]
	t += "%d rooms (%d without scene), %d areas, %d/%d gates connected, %d layer(s)\n" % [world.get_room_ids().size(), no_scene, world.get_areas().size(), connected, total, world.get_layers().size()]
	return t

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
