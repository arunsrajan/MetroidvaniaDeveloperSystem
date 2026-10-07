@tool
class_name MDSMetSysPanel
extends Control
## MetSys mode: map viewer, room annotator and progression analyzer for MetSys'
## grid-based MapData.txt.
##
## Layout: a tool panel on the left (like MetSys' editor), the map canvas in the middle and a sidebar
## with Rooms / Inspect / Progress / Issues / Stats tabs.

const DEFAULT_FILTERS: PackedStringArray = ["Save Points", "Bosses", "Collectibles", "Teleporters", "Shops", "Enemies"]
const DEFAULT_FILTERS_ON: PackedStringArray = ["Save Points", "Bosses"]
const EXPORT_DIR := "res://idp_exports"
const SETTING_AUTO_SCAN := "interactive_dev_panel/auto_scan_map_scenes"

enum ViewItem { LABELS, TERRAIN, PREVIEWS, DOORS, MARKERS, ELEMENTS, PINS, ISSUES, GRID, LEGEND, AUTO_SCAN = 100 }
enum ExportItem { JSON, PNG, DOT, MARKDOWN }
enum ScanItem { RESCAN_MAP, SCAN_FOLDER, FIND_MAPS, PLAYER, GEOMETRY }
enum ContextItem { OPEN, PLAY_HERE, RUN_SCENE, SET_START, ADD_PIN, REMOVE_PIN, ROUTE, LINK, COPY_UID, COPY_CELL }

# Data
var map_data_path := ""
var model: MDSMapModel
var annotations: MDSAnnotations
var analysis: MDSAnalysis
var scene_database: Dictionary = {}
var scanned_paths: Array = []
var issues: Array = []
var current_filters: Dictionary = {}
var filter_categories: Array = []

# UI
var canvas: MDSMapCanvas
var map_picker: OptionButton
var layer_picker: OptionButton
var color_picker: OptionButton
var view_menu: MenuButton
var scan_menu: MenuButton
var export_menu: MenuButton
var zoom_label: Label
var route_button: Button
var filter_box: HFlowContainer
## The host inserts the mode switch at the start of this box (the Map section).
var toolbar: Container
var side_panel: MDSSidePanel
var side_tabs_check: CheckBox
var sidebar: TabContainer
var room_search: LineEdit
var room_filter_toggle: CheckBox
var room_tree: Tree
var inspector_scroll: ScrollContainer
var inspector: VBoxContainer
var views: MDSAnalysisViews
var status_label: Label
var progress_bar: ProgressBar
var context_menu: PopupMenu
var folder_dialog: EditorFileDialog
var map_dialog: EditorFileDialog
var pin_dialog: ConfirmationDialog
var pin_text: LineEdit
var pin_kind: OptionButton

# State
var _scanner: MDSSceneScanner
var _save_timer: Timer
var _refresh_timer: Timer
var _file_timer: Timer
var _last_modified := 0
var _context_room := ""
var _context_cell := Vector2.ZERO
var _link_source := ""
var _pending_pin_cell := Vector2.ZERO
var _inspector_room := ""
var _filling_room_list := false
var _inspector_info: RichTextLabel
var _export_viewport: SubViewport
## Physics checks of the room scenes (Issues > Geometry), in the background.
var geometry_checker: MDSGeometryChecker
var _player_dialog: AcceptDialog

func _ready() -> void:
	if is_part_of_edited_scene():
		return
	_build_ui()
	_setup_filters()
	geometry_checker = MDSGeometryChecker.new()
	add_child(geometry_checker)
	geometry_checker.progress.connect(func(current: int, total: int, path: String) -> void:
		_set_status("Checking room geometry %d/%d: %s" % [current, total, path.get_file()]))
	geometry_checker.finished.connect(func(paths: Array) -> void:
		_refresh_timer.start()
		_set_status("Checked the geometry of %d room(s): see Issues > Geometry." % paths.size()))
	_save_timer = _make_timer(0.6, _save_annotations)
	_refresh_timer = _make_timer(0.25, _refresh_analysis)
	_file_timer = _make_timer(1.5, _check_map_file_changed)
	_file_timer.one_shot = false
	_file_timer.start()
	if not ProjectSettings.has_setting(SETTING_AUTO_SCAN):
		ProjectSettings.set_setting(SETTING_AUTO_SCAN, true)
		ProjectSettings.set_initial_value(SETTING_AUTO_SCAN, true)
	_refresh_map_list()
	var default_map := _get_metsys_map_path()
	if not default_map.is_empty() and FileAccess.file_exists(default_map):
		load_map(default_map)
	elif map_picker.item_count > 1:
		load_map(map_picker.get_item_metadata(0))
	else:
		_set_status("No MapData.txt found. Use the map picker to browse for one.")

func _make_timer(wait: float, callback: Callable) -> Timer:
	var t := Timer.new()
	t.wait_time = wait
	t.one_shot = true
	t.timeout.connect(callback)
	add_child(t)
	return t

# --- MetSys access (resolved at runtime so the panel parses even without MetSys) --------

func _metsys() -> Node:
	var tree := get_tree()
	return tree.root.get_node_or_null(^"MetSys") if tree else null

func _get_metsys_map_path() -> String:
	var ms := _metsys()
	if ms and ms.get("settings"):
		return ms.settings.map_data_file
	return "res://MapData.txt"

func _get_cell_size() -> Vector2:
	var ms := _metsys()
	if ms and ms.get("settings"):
		return ms.settings.in_game_cell_size
	return Vector2(1152, 648)

func _get_metsys_default_color() -> Color:
	var ms := _metsys()
	if ms and ms.get("settings") and ms.settings.theme:
		return ms.settings.theme.default_center_color
	return Color(0.4, 0.45, 0.55)

# --- UI construction ------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(300, 300)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# Like MetSys' editor: tools on the left, the map in the middle, tabs on the right.
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	side_panel = MDSSidePanel.new()
	main.add_child(side_panel)

	# Map file ---------------------------------------------------------------------------
	toolbar = side_panel.add_section("Map")
	map_picker = OptionButton.new()
	map_picker.tooltip_text = "MapData file to show"
	map_picker.fit_to_longest_item = false
	map_picker.clip_text = true
	map_picker.item_selected.connect(_on_map_picked)
	toolbar.add_child(map_picker)

	var reload := MDSUi.button("Reload", "Reload the map file and re-run analysis")
	reload.pressed.connect(func() -> void: load_map(map_data_path))
	scan_menu = MenuButton.new()
	scan_menu.text = "Scan"
	scan_menu.flat = false
	scan_menu.tooltip_text = "Scan room scenes for features and terrain"
	var sp := scan_menu.get_popup()
	sp.add_item("Rescan map scenes", ScanItem.RESCAN_MAP)
	sp.add_item("Scan project folder (finds unplaced rooms)...", ScanItem.SCAN_FOLDER)
	sp.add_item("Find MapData files", ScanItem.FIND_MAPS)
	sp.add_separator()
	sp.add_check_item("Check room geometry (physics)", ScanItem.GEOMETRY)
	sp.add_item("Player settings for the checks...", ScanItem.PLAYER)
	sp.id_pressed.connect(_on_scan_menu)
	MDSSidePanel.row(toolbar, [reload, scan_menu])
	export_menu = MenuButton.new()
	export_menu.text = "Export"
	export_menu.flat = false
	var ep := export_menu.get_popup()
	ep.add_item("Map data (JSON)", ExportItem.JSON)
	ep.add_item("Map image (PNG)", ExportItem.PNG)
	ep.add_item("Room graph (Graphviz .dot)", ExportItem.DOT)
	ep.add_item("Design document (Markdown)", ExportItem.MARKDOWN)
	ep.id_pressed.connect(_on_export_menu)
	toolbar.add_child(MDSSidePanel.fill(export_menu))
	side_tabs_check = CheckBox.new()
	side_tabs_check.text = "Side tabs"
	side_tabs_check.button_pressed = true
	side_tabs_check.tooltip_text = "Show the Rooms / Inspect / Progress... tabs on the right. Hide them for a bigger map"
	side_tabs_check.toggled.connect(func(on: bool) -> void: sidebar.visible = on)
	toolbar.add_child(side_tabs_check)

	# Display ----------------------------------------------------------------------------
	var display := side_panel.add_section("Map display")
	layer_picker = OptionButton.new()
	layer_picker.item_selected.connect(func(idx: int) -> void: _set_layer(layer_picker.get_item_id(idx)))
	MDSSidePanel.field(display, "Layer", layer_picker)
	color_picker = OptionButton.new()
	for i in MDSMapCanvas.COLOR_MODE_NAMES.size():
		color_picker.add_item(MDSMapCanvas.COLOR_MODE_NAMES[i], i)
	color_picker.select(MDSMapCanvas.ColorMode.ROOM_TYPE)
	color_picker.item_selected.connect(func(idx: int) -> void:
		canvas.color_mode = idx
		canvas.redraw())
	MDSSidePanel.field(display, "Color", color_picker)

	view_menu = MenuButton.new()
	view_menu.text = "Show on map..."
	view_menu.flat = false
	var vp := view_menu.get_popup()
	vp.hide_on_checkable_item_selection = false
	var view_items := [
		[ViewItem.LABELS, "Room labels", "labels"], [ViewItem.TERRAIN, "Terrain silhouettes", "terrain"],
		[ViewItem.PREVIEWS, "Live scene previews (slow)", "previews"], [ViewItem.DOORS, "Doors, gates && one-ways", "doors"],
		[ViewItem.MARKERS, "Markers", "markers"], [ViewItem.ELEMENTS, "Custom elements", "elements"],
		[ViewItem.PINS, "Pins", "pins"], [ViewItem.ISSUES, "Issue badges", "issues"],
		[ViewItem.GRID, "Grid", "grid"], [ViewItem.LEGEND, "Legend", "legend"],
	]
	for item in view_items:
		vp.add_check_item(item[1], item[0])
		vp.set_item_metadata(vp.get_item_index(item[0]), item[2])
	vp.add_separator()
	vp.add_check_item("Auto-scan map scenes on load", ViewItem.AUTO_SCAN)
	vp.id_pressed.connect(_on_view_menu)
	display.add_child(MDSSidePanel.fill(view_menu))

	var zoom_out := MDSUi.button("-", "Zoom out")
	var zoom_in := MDSUi.button("+", "Zoom in (or mouse wheel over the map)")
	var fit := MDSUi.button("Fit", "Fit the layer in view (F)")
	zoom_out.pressed.connect(func() -> void: canvas.set_zoom(canvas.zoom / 1.25))
	zoom_in.pressed.connect(func() -> void: canvas.set_zoom(canvas.zoom * 1.25))
	fit.pressed.connect(func() -> void: canvas.fit_to_layer())
	zoom_label = MDSUi.label("100%")
	zoom_label.custom_minimum_size.x = 44
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MDSSidePanel.row(display, [zoom_out, zoom_label, zoom_in, fit])

	route_button = MDSUi.button("Clear route", "Clear the highlighted route / selection highlight (Esc)")
	route_button.visible = false
	route_button.pressed.connect(_clear_route_and_highlight)
	display.add_child(route_button)

	# Marker filters ------------------------------------------------------------------------
	filter_box = HFlowContainer.new()
	filter_box.tooltip_text = "Show markers on the map and filter the room list"
	side_panel.add_section("Markers", filter_box)

	# Map + sidebar ---------------------------------------------------------------------
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(split)

	canvas = MDSMapCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(200, 200)
	canvas.room_selected.connect(_on_canvas_room_selected)
	canvas.room_activated.connect(_open_room_scene)
	canvas.route_requested.connect(_show_route)
	canvas.context_requested.connect(_on_canvas_context)
	canvas.hovered_changed.connect(_on_canvas_hover)
	canvas.view_changed.connect(func() -> void: zoom_label.text = "%d%%" % roundi(canvas.zoom * 100))
	canvas.gui_input.connect(_on_canvas_gui_input)
	split.add_child(canvas)

	sidebar = TabContainer.new()
	sidebar.custom_minimum_size.x = 300
	split.add_child(sidebar)
	_build_rooms_tab()
	_build_inspector_tab()
	views = MDSAnalysisViews.new(self, sidebar)

	# Status bar -------------------------------------------------------------------------
	var status := HBoxContainer.new()
	root.add_child(status)
	status_label = MDSUi.label("")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(160, 0)
	progress_bar.visible = false
	status.add_child(progress_bar)

	# Popups ------------------------------------------------------------------------------
	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context_menu)
	add_child(context_menu)

	folder_dialog = EditorFileDialog.new()
	folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	folder_dialog.dir_selected.connect(_scan_folder)
	add_child(folder_dialog)

	map_dialog = EditorFileDialog.new()
	map_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	map_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	map_dialog.add_filter("*.txt", "MetSys map data")
	map_dialog.file_selected.connect(func(path: String) -> void:
		_add_map_to_picker(path)
		load_map(path))
	add_child(map_dialog)

	pin_dialog = ConfirmationDialog.new()
	pin_dialog.title = "Add map pin"
	var pin_box := VBoxContainer.new()
	pin_text = LineEdit.new()
	pin_text.placeholder_text = "Pin text, e.g. \"Hidden wall to the secret room\""
	pin_text.custom_minimum_size.x = 320
	pin_text.text_submitted.connect(func(_t: String) -> void:
		pin_dialog.hide()
		_confirm_pin())
	pin_kind = OptionButton.new()
	for k in MDSAnnotations.PIN_KINDS:
		pin_kind.add_item(k.capitalize())
	pin_box.add_child(pin_text)
	pin_box.add_child(pin_kind)
	pin_dialog.add_child(pin_box)
	pin_dialog.confirmed.connect(_confirm_pin)
	add_child(pin_dialog)

	_sync_view_menu()

func _build_rooms_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Rooms"
	sidebar.add_child(box)
	room_search = LineEdit.new()
	room_search.placeholder_text = "Search rooms, areas, bosses, abilities..."
	room_search.clear_button_enabled = true
	room_search.text_changed.connect(func(_t: String) -> void: _refresh_room_list())
	room_search.text_submitted.connect(func(_t: String) -> void:
		var first := room_tree.get_root().get_first_child() if room_tree.get_root() else null
		if first:
			first.select(0))
	box.add_child(room_search)
	room_filter_toggle = CheckBox.new()
	room_filter_toggle.text = "Only rooms matching the Show filters"
	room_filter_toggle.toggled.connect(func(_on: bool) -> void: _refresh_room_list())
	box.add_child(room_filter_toggle)
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
		if not _filling_room_list:
			select_room(room_tree.get_selected().get_metadata(0), true))
	room_tree.item_activated.connect(func() -> void: _open_room_scene(room_tree.get_selected().get_metadata(0)))
	box.add_child(room_tree)
	var hint := MDSUi.label("Click: select   Double-click: open scene")
	hint.modulate.a = 0.6
	box.add_child(hint)

func _build_inspector_tab() -> void:
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.name = "Inspect"
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(inspector_scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector)
	_rebuild_inspector()

func _sync_view_menu() -> void:
	var vp := view_menu.get_popup()
	for i in vp.item_count:
		var key = vp.get_item_metadata(i)
		if key is String and canvas.show.has(key):
			vp.set_item_checked(i, canvas.show[key])
	vp.set_item_checked(vp.get_item_index(ViewItem.AUTO_SCAN), ProjectSettings.get_setting(SETTING_AUTO_SCAN, true))

func _on_view_menu(id: int) -> void:
	var vp := view_menu.get_popup()
	var idx := vp.get_item_index(id)
	var checked := not vp.is_item_checked(idx)
	vp.set_item_checked(idx, checked)
	if id == ViewItem.AUTO_SCAN:
		ProjectSettings.set_setting(SETTING_AUTO_SCAN, checked)
		ProjectSettings.save()
		return
	canvas.set_show(vp.get_item_metadata(idx), checked)

# --- Filters --------------------------------------------------------------------------

func _setup_filters() -> void:
	for child in filter_box.get_children():
		child.queue_free()
	filter_categories = Array(DEFAULT_FILTERS)
	var element_names: PackedStringArray = []
	var ms := _metsys()
	if ms and ms.get("map_data"):
		for coords in ms.map_data.custom_elements:
			element_names.append(ms.map_data.custom_elements[coords].name)
	if model:
		element_names.append_array(model.get_custom_element_names())
	for element in element_names:
		var category := element.capitalize()
		if not category in filter_categories:
			filter_categories.append(category)
	for category in filter_categories:
		var checkbox := CheckBox.new()
		checkbox.text = category
		var on: bool = current_filters.get(category, category in DEFAULT_FILTERS_ON or not category in DEFAULT_FILTERS)
		checkbox.button_pressed = on
		current_filters[category] = on
		checkbox.toggled.connect(_on_filter_toggled.bind(category))
		filter_box.add_child(checkbox)
	canvas.marker_filters = current_filters

func _on_filter_toggled(checked: bool, category: String) -> void:
	current_filters[category] = checked
	canvas.marker_filters = current_filters
	canvas.redraw()
	_refresh_room_list()

## Same rule as the original panel: with no filter active every room passes, otherwise a
## room must match at least one active category. Only applies when the Rooms tab asks.
func _passes_filters(room: MDSMapModel.Room) -> bool:
	var any_active := current_filters.values().has(true)
	if not any_active or not room_filter_toggle.button_pressed:
		return true
	var info := analysis.get_info(room.id)
	var meta: Dictionary = scene_database.get(room.scene_path, {})
	if current_filters.get("Bosses", false) and info.get("is_boss", false):
		return true
	if current_filters.get("Save Points", false) and info.get("is_save", false):
		return true
	if current_filters.get("Collectibles", false) and not meta.get("collectibles", []).is_empty():
		return true
	if current_filters.get("Teleporters", false) and info.get("is_teleporter", false):
		return true
	if current_filters.get("Shops", false) and info.get("is_shop", false):
		return true
	if current_filters.get("Enemies", false) and not meta.get("enemies", []).is_empty():
		return true
	for e in model.custom_elements:
		if current_filters.get(e.name.capitalize(), false):
			var r := Rect2i(Vector2i(e.coords.x, e.coords.y), e.size)
			if e.coords.z == room.layer and room.cells.any(func(c: Vector3i) -> bool: return r.has_point(Vector2i(c.x, c.y))):
				return true
	return false

# --- Map loading ----------------------------------------------------------------------

func _refresh_map_list() -> void:
	var found: PackedStringArray = []
	var configured := _get_metsys_map_path()
	if FileAccess.file_exists(configured):
		found.append(configured)
	_find_map_files("res://", found, 0)
	if not map_data_path.is_empty() and not map_data_path in found:
		found.append(map_data_path)
	map_picker.clear()
	for path in found:
		map_picker.add_item(path.trim_prefix("res://"))
		map_picker.set_item_metadata(map_picker.item_count - 1, path)
	map_picker.add_item("Browse...")
	map_picker.set_item_metadata(map_picker.item_count - 1, "")
	_select_map_in_picker(map_data_path)

func _find_map_files(dir_path: String, out: PackedStringArray, depth: int) -> void:
	if depth > 6:
		return
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with("MapData.txt"):
			var p := dir_path.path_join(f)
			if not p in out:
				out.append(p)
	for d in DirAccess.get_directories_at(dir_path):
		if d.begins_with(".") or d == "addons" or d == EXPORT_DIR.get_file():
			continue
		_find_map_files(dir_path.path_join(d), out, depth + 1)

func _add_map_to_picker(path: String) -> void:
	for i in map_picker.item_count:
		if map_picker.get_item_metadata(i) == path:
			return
	map_picker.add_item(path.trim_prefix("res://"))
	map_picker.set_item_metadata(map_picker.item_count - 1, path)
	map_picker.move_item(map_picker.item_count - 1, map_picker.item_count - 2)

func _select_map_in_picker(path: String) -> void:
	for i in map_picker.item_count:
		if map_picker.get_item_metadata(i) == path:
			map_picker.select(i)
			return

func _on_map_picked(idx: int) -> void:
	var path: String = map_picker.get_item_metadata(idx)
	if path.is_empty():
		_select_map_in_picker(map_data_path)
		map_dialog.popup_file_dialog()
	else:
		load_map(path)

## Loads (or reloads) a MapData file with its annotations, then scans its scenes.
func load_map(path: String) -> void:
	if path.is_empty():
		return
	if not FileAccess.file_exists(path):
		_set_status("Map file not found: %s" % path)
		return
	var same_map := path == map_data_path
	var previous_layer := canvas.layer
	if annotations and annotations.changed.is_connected(_on_annotations_changed):
		if _save_timer.time_left > 0:
			_save_annotations()
		annotations.changed.disconnect(_on_annotations_changed)
	map_data_path = path
	_last_modified = FileAccess.get_modified_time(path)
	model = MDSMapModel.load_file(path)
	annotations = MDSAnnotations.load_for_map(path)
	_sync_scan_menu()
	annotations.changed.connect(_on_annotations_changed)
	canvas.in_game_cell_size = _get_cell_size()
	canvas.metsys_default_color = _get_metsys_default_color()
	_select_map_in_picker(path)
	_setup_filters()

	layer_picker.clear()
	for l in model.layers:
		layer_picker.add_item("%d: %s" % [l, model.get_layer_name(l)], l)
	var layer: int = previous_layer if same_map and previous_layer in model.layers else (model.layers[0] if not model.layers.is_empty() else 0)
	canvas.layer = layer
	_select_layer_in_picker(layer)

	if not same_map:
		canvas.selected_room = ""
		canvas.route.clear()
		canvas.highlight_rooms.clear()
	_refresh_analysis()
	if not same_map:
		_fit_when_ready()
	_set_status("Loaded %s: %d rooms, %d cells, %d layer(s)" % [path.get_file(), model.rooms.size(), model.cells.size(), model.layers.size()])
	if ProjectSettings.get_setting(SETTING_AUTO_SCAN, true):
		if not same_map or scene_database.is_empty():
			_scan_map_scenes()
		else:
			# Map edited in MetSys: only scan rooms that are new since the last scan.
			var missing: Array[String] = []
			for room: MDSMapModel.Room in model.rooms.values():
				if not room.scene_path.is_empty() and not scene_database.has(room.scene_path) and not room.scene_path in missing:
					missing.append(room.scene_path)
			if not missing.is_empty():
				_run_scan(missing, false, true)

func _fit_when_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	canvas.fit_to_layer()

func _check_map_file_changed() -> void:
	if map_data_path.is_empty() or not FileAccess.file_exists(map_data_path) or not is_visible_in_tree():
		return
	var modified := FileAccess.get_modified_time(map_data_path)
	if modified != _last_modified:
		_last_modified = modified
		load_map(map_data_path)
		_set_status("Map file changed on disk, reloaded.")

func _set_layer(layer: int) -> void:
	canvas.set_layer(layer)
	_select_layer_in_picker(layer)
	_refresh_room_list()

func _select_layer_in_picker(layer: int) -> void:
	var idx := layer_picker.get_item_index(layer)
	if idx >= 0:
		layer_picker.select(idx)

# --- Scanning -------------------------------------------------------------------------

func _on_scan_menu(id: int) -> void:
	match id:
		ScanItem.RESCAN_MAP:
			_scan_map_scenes()
		ScanItem.SCAN_FOLDER:
			folder_dialog.popup_file_dialog()
		ScanItem.FIND_MAPS:
			_refresh_map_list()
			_set_status("Found %d map file(s)." % (map_picker.item_count - 1))
		ScanItem.GEOMETRY:
			if annotations:
				annotations.set_setting("geometry_checks", not geometry_checks_enabled())
				_sync_scan_menu()
		ScanItem.PLAYER:
			_show_player_settings()

func _sync_scan_menu() -> void:
	var sp := scan_menu.get_popup()
	sp.set_item_checked(sp.get_item_index(ScanItem.GEOMETRY), geometry_checks_enabled())

func geometry_checks_enabled() -> bool:
	return annotations != null and bool(annotations.get_setting("geometry_checks", true))

## One room check per room with a scanned scene (see MDSGeometryChecker).
func geometry_jobs() -> Array:
	var jobs: Array = []
	var cell := _get_cell_size()
	for room: MDSMapModel.Room in model.rooms.values():
		if room.scene_path.is_empty() or not scene_database.has(room.scene_path):
			continue
		jobs.append({"path": room.scene_path, "name": analysis.get_room_name(room.id) if analysis else room.id, "rects": MDSRoomCheck.rects_from_metsys(room, cell),
			"passages": MDSRoomCheck.passages_from_metsys(model, room, cell), "player": annotations.get_setting("player", {}), "cell_size": cell})
	return jobs

func _show_player_settings() -> void:
	if not annotations:
		return
	if not _player_dialog:
		_player_dialog = AcceptDialog.new()
		_player_dialog.title = "Player for the room checks"
		add_child(_player_dialog)
	for c in _player_dialog.get_children():
		if c is GridContainer:
			c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	_player_dialog.add_child(grid)
	MDSUi.player_fields(grid, annotations.get_setting("player", {}), func(d: Dictionary) -> void: annotations.set_setting("player", d))
	_player_dialog.popup_centered(Vector2i(380, 0))

func _scan_map_scenes() -> void:
	if not model:
		return
	var paths: Array[String] = []
	for room: MDSMapModel.Room in model.rooms.values():
		if not room.scene_path.is_empty() and not room.scene_path in paths:
			paths.append(room.scene_path)
	_run_scan(paths, false)

## Called by the plugin when a scene is saved, so edited rooms refresh their markers,
## terrain and gates without a full rescan.
func on_scene_saved(path: String) -> void:
	if model and model.find_room_by_scene_path(path):
		var paths: Array[String] = [path]
		_run_scan(paths, false, true)

func _scan_folder(dir: String) -> void:
	var finder := MDSSceneScanner.new(_get_cell_size())
	var files: Array[String] = []
	finder.scan_map_data_txt_completed.connect(func(p: String) -> void: _add_map_to_picker(p))
	finder.find_scene_files(dir, files)
	_run_scan(files, true)

## [param merge] updates only [param paths] in the existing database instead of replacing it.
func _run_scan(paths: Array[String], remember_paths: bool, merge := false) -> void:
	if _scanner and _scanner.is_scanning:
		if merge:
			return # a full scan is already running and will include these scenes
		_scanner.cancel()
	_scanner = MDSSceneScanner.new(_get_cell_size())
	_scanner.scan_progress_updated.connect(func(current: int, total: int, file: String) -> void:
		progress_bar.visible = true
		progress_bar.max_value = total
		progress_bar.value = current
		_set_status("Scanning %d/%d: %s" % [current, total, file]))
	var scanner := _scanner
	var db: Dictionary = await scanner.scan_paths(paths)
	if scanner != _scanner:
		return # superseded by a newer scan
	progress_bar.visible = false
	if merge:
		var merged := scene_database.duplicate()
		for p in paths:
			if db.has(p):
				merged[p] = db[p]
			else:
				merged.erase(p)
		db = merged
	scene_database = db
	if remember_paths:
		scanned_paths = paths.filter(func(p: String) -> bool: return db.has(p))
	_refresh_analysis()
	if merge:
		_set_status("Rescanned %s" % ", ".join(paths.map(func(p: String) -> String: return p.get_file())))
		return
	var stats := scanner.get_stats()
	_set_status("Scan complete: %d room scenes, %d collectibles, %d enemies, %d save points" % [db.size(), stats.total_collectibles, stats.total_enemies, stats.total_save_points])

# --- Analysis & refresh ----------------------------------------------------------------

func _on_annotations_changed() -> void:
	_save_timer.start()
	_refresh_timer.start()

func _save_annotations() -> void:
	if not annotations:
		return
	var err := annotations.save()
	if err != OK:
		_set_status("Could not save annotations to %s (error %d)" % [annotations.path, err])
	else:
		# Keep the file-change watcher from treating our own writes as map edits.
		_last_modified = FileAccess.get_modified_time(map_data_path)

func _refresh_analysis() -> void:
	if not model:
		return
	var geometry_on := geometry_checks_enabled()
	for p in scene_database:
		scene_database[p].geometry = geometry_checker.issues_of(p) if geometry_on else []
	analysis = MDSAnalysis.new(MDSGraph.from_metsys(model, scene_database, _get_cell_size()), annotations, scene_database).run()
	issues = MDSValidator.run(model, annotations, analysis, scene_database, scanned_paths)
	canvas.issue_cells.clear()
	for issue in issues:
		var cell: Vector3i = issue.cell
		if cell == Vector3i.MAX and not issue.room_id.is_empty() and model.rooms.has(issue.room_id):
			cell = model.get_room(issue.room_id).cells[0]
		if cell != Vector3i.MAX:
			canvas.issue_cells[cell] = maxi(canvas.issue_cells.get(cell, 0), issue.severity)
	canvas.set_data(model, annotations, analysis, scene_database)
	_refresh_room_list()
	views.refresh(analysis, issues, not scene_database.is_empty())
	if _inspector_room != canvas.selected_room or not model.rooms.has(_inspector_room):
		_rebuild_inspector()
	else:
		_update_inspector_info()
	if geometry_on and not scene_database.is_empty() and not (_scanner and _scanner.is_scanning):
		geometry_checker.check(geometry_jobs())

func _refresh_room_list() -> void:
	room_tree.clear()
	if not model or not analysis:
		return
	var root := room_tree.create_item()
	var search := room_search.text.strip_edges().to_lower()
	var rooms: Array = model.rooms.values()
	rooms.sort_custom(func(a: MDSMapModel.Room, b: MDSMapModel.Room) -> bool:
		if a.layer != b.layer:
			return a.layer < b.layer
		return analysis.get_room_name(a.id).naturalnocasecmp_to(analysis.get_room_name(b.id)) < 0)
	for room: MDSMapModel.Room in rooms:
		if room.scene_uid.is_empty() or not _passes_filters(room):
			continue
		var info := analysis.get_info(room.id)
		if not search.is_empty():
			var haystack := " ".join([info.name, info.area, info.type, room.scene_path, ", ".join(info.boss_names), ", ".join(info.grants)]).to_lower()
			if not haystack.contains(search):
				continue
		var item := room_tree.create_item(root)
		var label: String = info.name
		if room.layer != canvas.layer:
			label += "  [L%d]" % room.layer
		item.set_text(0, label)
		item.set_icon(0, MDSUi.type_icon(info.type))
		item.set_tooltip_text(0, "%s\n%s" % [str(info.type).capitalize() if not str(info.type).is_empty() else "Normal", room.scene_path])
		item.set_text(1, info.area)
		var sphere: int = analysis.sphere_of.get(room.id, -1)
		item.set_text(2, str(sphere) if sphere >= 0 else ("locked" if room.id in analysis.locked else "-"))
		item.set_metadata(0, room.id)
		if room.id == canvas.selected_room:
			# Programmatic selection must not re-trigger select_room (it would switch layers).
			_filling_room_list = true
			item.select(0)
			_filling_room_list = false

# --- Selection ----------------------------------------------------------------------------

func select_room(id: String, center := false) -> void:
	if not model or not model.rooms.has(id):
		return
	var room := model.get_room(id)
	if room.layer != canvas.layer:
		_set_layer(room.layer)
	canvas.selected_room = id
	canvas.redraw()
	if center:
		canvas.center_on_room(id)
	_rebuild_inspector()
	_set_status("%s  %s" % [analysis.get_room_name(id), room.scene_path])

func _on_canvas_room_selected(id: String) -> void:
	if not _link_source.is_empty():
		if not id.is_empty() and id != _link_source:
			annotations.add_link(_link_source, id, "")
			_set_status("Linked %s <-> %s" % [analysis.get_room_name(_link_source), analysis.get_room_name(id)])
			var src := _link_source
			_link_source = ""
			select_room(src)
		else:
			_link_source = ""
			_set_status("Link cancelled.")
		return
	if id.is_empty():
		canvas.selected_room = ""
		_clear_route_and_highlight()
		_rebuild_inspector()
		return
	select_room(id)
	sidebar.current_tab = inspector_scroll.get_index()

func _on_canvas_hover(id: String, cell: Vector3i) -> void:
	if not _link_source.is_empty() or cell == Vector3i.MAX or not model:
		return
	var text := "Cell (%d, %d)  layer %d" % [cell.x, cell.y, cell.z]
	if not id.is_empty():
		var info := analysis.get_info(id)
		text += "  |  %s" % info.get("name", id)
		if not str(info.get("type", "")).is_empty():
			text += "  (%s)" % str(info.type).capitalize()
		var groups := model.get_cell_groups(cell)
		if not groups.is_empty():
			text += "  |  groups: %s" % ", ".join(Array(groups).map(func(g: int) -> String: return model.get_group_name(g)))
	_set_status(text)

func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_link_source = ""
		_clear_route_and_highlight()
		canvas.accept_event()

func _show_route(from_id: String, to_id: String) -> void:
	var path := analysis.find_path(from_id, to_id)
	if path.is_empty():
		_set_status("No route between %s and %s." % [analysis.get_room_name(from_id), analysis.get_room_name(to_id)])
		return
	canvas.route = path
	var reqs: PackedStringArray = []
	for i in path.size() - 1:
		var door := canvas._door_between(path[i], path[i + 1])
		if door:
			for r in analysis.get_door_requires(door.key):
				if not r in reqs:
					reqs.append(r)
	route_button.visible = true
	canvas.redraw()
	_set_status("Route %s -> %s: %d room transitions%s" % [analysis.get_room_name(from_id), analysis.get_room_name(to_id), path.size() - 1, (", needs " + ", ".join(reqs)) if not reqs.is_empty() else ""])

func _clear_route_and_highlight() -> void:
	canvas.route.clear()
	canvas.highlight_rooms.clear()
	route_button.visible = false
	canvas.redraw()

# --- Inspector ------------------------------------------------------------------------------

func _rebuild_inspector() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	_inspector_info = null
	_inspector_room = canvas.selected_room if canvas else ""
	var room := model.get_room(_inspector_room) if model else null
	if not room:
		var hint := MDSUi.label("Select a room on the map to inspect and annotate it.\n\nRight-click the map for more actions: pins, play from here, routes, links.\nShift+click a second room to show the route between them.")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspector.add_child(hint)
		return
	var id := room.id
	var info := analysis.get_info(id)
	var meta: Dictionary = scene_database.get(room.scene_path, {})

	var title := MDSUi.label(info.get("name", room.get_display_name()))
	title.add_theme_font_size_override("font_size", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inspector.add_child(title)
	var path_label := MDSUi.label(room.scene_path if not room.scene_path.is_empty() else room.scene_uid)
	path_label.modulate.a = 0.6
	path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inspector.add_child(path_label)

	var actions := HFlowContainer.new()
	inspector.add_child(actions)
	var open_btn := MDSUi.button("Open scene", "Open the room scene in the editor")
	open_btn.pressed.connect(_open_room_scene.bind(id))
	open_btn.disabled = room.scene_path.is_empty()
	actions.add_child(open_btn)
	var play_btn := MDSUi.button("Play from here", "Run the game starting in this room, at its save point if it has one. Right-click the map to start at an exact spot.")
	play_btn.pressed.connect(func() -> void: _play_from(id, Vector2(room.get_label_cell()) + Vector2(0.5, 0.5), true))
	play_btn.disabled = room.scene_path.is_empty()
	actions.add_child(play_btn)
	var start_btn := MDSUi.button("Start room" if id == analysis.start_room_id else "Set as start", "Progression spheres are computed from the start room")
	start_btn.disabled = id == analysis.start_room_id
	start_btn.pressed.connect(func() -> void: annotations.set_start_room(id))
	actions.add_child(start_btn)
	var center_btn := MDSUi.button("Center", "Center the map on this room")
	center_btn.pressed.connect(func() -> void: canvas.center_on_room(id))
	actions.add_child(center_btn)

	inspector.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	inspector.add_child(grid)

	var name_edit := MDSUi.field_line(grid, "Name", annotations.get_room_value(id, "name", ""), room.get_display_name())
	MDSUi.commit_line(name_edit, func(t: String) -> void: annotations.set_room_value(id, "name", t.strip_edges()))

	var type_opt := MDSUi.field_option(grid, "Type", MDSAnnotations.ROOM_TYPES, annotations.get_room_value(id, "type", ""), "(auto: %s)" % (str(info.type).capitalize() if not str(info.type).is_empty() else "normal"))
	type_opt.item_selected.connect(func(idx: int) -> void: annotations.set_room_value(id, "type", MDSAnnotations.ROOM_TYPES[idx]))

	var status_opt := MDSUi.field_option(grid, "Status", MDSAnnotations.STATUSES, annotations.get_room_value(id, "status", ""), "(none)")
	status_opt.item_selected.connect(func(idx: int) -> void: annotations.set_room_value(id, "status", MDSAnnotations.STATUSES[idx]))

	var groups := model.get_room_group_names(room)
	var area_edit := MDSUi.field_line(grid, "Area", annotations.get_room_value(id, "area", ""), groups[0] if not groups.is_empty() else "e.g. Mossy Hollows")
	MDSUi.commit_line(area_edit, func(t: String) -> void: annotations.set_room_value(id, "area", t.strip_edges()))

	var scanned_boss: PackedStringArray = []
	for b in meta.get("bosses", []):
		scanned_boss.append(b.name)
	var boss_edit := MDSUi.field_line(grid, "Boss", annotations.get_room_value(id, "boss", ""), ", ".join(scanned_boss) if not scanned_boss.is_empty() else "boss name (marks a boss room)")
	MDSUi.commit_line(boss_edit, func(t: String) -> void:
		annotations.set_room_value(id, "boss", t.strip_edges())
		if not t.strip_edges().is_empty() and str(annotations.get_room_value(id, "type", "")).is_empty():
			annotations.set_room_value(id, "type", "boss"))

	var scanned_grants: PackedStringArray = meta.get("grants", PackedStringArray())
	var grants_edit := MDSUi.field_line(grid, "Grants", ", ".join(annotations.get_room_grants(id)), ("scanned: " + ", ".join(scanned_grants)) if not scanned_grants.is_empty() else "abilities/keys found here, e.g. dash")
	grants_edit.tooltip_text = "Comma separated. Abilities from idp_grants node metadata are added automatically."
	MDSUi.commit_line(grants_edit, func(t: String) -> void: annotations.set_room_value(id, "grants", Array(MDSAnnotations.parse_list(t))))

	inspector.add_child(MDSUi.label("Notes (TODO lines show up in Issues)"))
	var notes := TextEdit.new()
	notes.custom_minimum_size.y = 70
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.text = annotations.get_room_value(id, "notes", "")
	notes.focus_exited.connect(func() -> void:
		if notes.text != annotations.get_room_value(id, "notes", ""):
			annotations.set_room_value(id, "notes", notes.text))
	inspector.add_child(notes)

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

	# Exits: one row per door, with ability requirement and one-way flag.
	inspector.add_child(HSeparator.new())
	var exits_title := MDSUi.label("Exits (%d)" % room.doors.size())
	exits_title.add_theme_font_size_override("font_size", 15)
	inspector.add_child(exits_title)
	for door in room.doors:
		_add_exit_row(room, door)
	if room.doors.is_empty():
		inspector.add_child(MDSUi.label("No passages. Paint passages in the MetSys editor."))

	# Links: elevators, teleporters, cross-layer transitions MetSys can't express.
	inspector.add_child(HSeparator.new())
	var links_title := MDSUi.label("Links (elevators, teleports, layer transitions)")
	links_title.add_theme_font_size_override("font_size", 15)
	links_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(links_title)
	var links := annotations.get_links()
	for i in links.size():
		if links[i].a == id or links[i].b == id:
			_add_link_row(id, i)
	var add_link := MDSUi.button("Add link... (then click the target room)", "Connect this room to another room, e.g. on another layer")
	add_link.pressed.connect(func() -> void:
		_link_source = id
		canvas.grab_focus()
		_set_status("Click the room to link with %s (switch layers with the Layer picker). Esc cancels." % info.name))
	inspector.add_child(add_link)

func _update_inspector_info() -> void:
	if not _inspector_info:
		return
	var room := model.get_room(_inspector_room)
	if not room:
		return
	var id := room.id
	var info := analysis.get_info(id)
	var meta: Dictionary = scene_database.get(room.scene_path, {})
	var r := room.get_rect()
	var t := ""
	t += "[b]Shape:[/b] %d cell(s), %dx%d%s, layer %d at (%d,%d)\n" % [room.cells.size(), r.size.x, r.size.y, " [color=#ffd479]irregular[/color]" if room.is_irregular() else "", room.layer, room.min_cell.x, room.min_cell.y]
	var groups := model.get_room_group_names(room)
	if not groups.is_empty():
		t += "[b]MetSys groups:[/b] %s\n" % ", ".join(groups)
	var sphere: int = analysis.sphere_of.get(id, -1)
	if sphere >= 0:
		t += "[b]Progression:[/b] sphere %d%s\n" % [sphere, " (start)" if id == analysis.start_room_id else ""]
	elif id in analysis.locked:
		t += "[b]Progression:[/b] [color=#ff7070]locked[/color], requirements are never met\n"
	else:
		t += "[b]Progression:[/b] [color=#ff7070]not connected to the start[/color]\n"
	var sd: int = analysis.save_distance.get(id, -1)
	t += "[b]Nearest save:[/b] %s\n" % ("this room" if sd == 0 else ("%d room(s) away" % sd if sd > 0 else "none reachable"))
	var st: int = analysis.start_distance.get(id, -1)
	if st >= 0:
		t += "[b]From start:[/b] %d room(s)\n" % st
	var roles: PackedStringArray = []
	if id in analysis.dead_ends:
		roles.append("dead end")
	if id in analysis.chokepoints:
		roles.append("chokepoint")
	if id in analysis.hubs:
		roles.append("hub")
	if not roles.is_empty():
		t += "[b]Topology:[/b] %s\n" % ", ".join(roles)
	if not info.get("grants", PackedStringArray()).is_empty():
		t += "[b]Grants:[/b] %s\n" % ", ".join(info.grants)
	if meta.is_empty():
		t += "[i]Not scanned yet (Scan > Rescan map scenes).[/i]\n"
	else:
		t += "[b]Contents:[/b] %d collectibles, %d enemies, %d save points%s%s%s\n" % [meta.collectibles.size(), meta.enemies.size(), meta.save_points.size(), ", shop" if meta.has_shopkeeper else "", ", teleporter" if meta.has_teleporter else "", ", breakables" if meta.has_breakable_walls else ""]
		if not meta.bosses.is_empty():
			t += "[b]Bosses:[/b] %s\n" % ", ".join(meta.bosses.map(func(b: Dictionary) -> String: return b.name))
	var neighbors := room.get_neighbor_rooms()
	if not neighbors.is_empty():
		t += "[b]Neighbors:[/b] %s" % ", ".join(neighbors.map(func(n: MDSMapModel.Room) -> String: return "[url=room:%s]%s[/url]" % [n.id, analysis.get_room_name(n.id)]))
	_inspector_info.text = t

func _add_exit_row(room: MDSMapModel.Room, door: MDSMapModel.Door) -> void:
	var box := VBoxContainer.new()
	inspector.add_child(box)
	var other := door.other(room)
	var c := door.cell_of(room)
	var head := HBoxContainer.new()
	box.add_child(head)
	var text := "%s at (%d,%d) -> " % [MDSMapModel.DIR_NAMES[door.dir_of(room)], c.x, c.y]
	var link := LinkButton.new()
	if other:
		link.text = text + analysis.get_room_name(other.id)
		link.pressed.connect(func() -> void: select_room(other.id, true))
	else:
		link.text = text + "nowhere!"
		link.modulate = Color(1, 0.5, 0.5)
		link.disabled = true
	link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(link)
	if other:
		var one_way := CheckBox.new()
		one_way.text = "One-way out"
		one_way.tooltip_text = "Players can leave %s through here but not come back (drop-downs, one-sided breakable walls)" % analysis.get_room_name(room.id)
		one_way.button_pressed = annotations.get_door_one_way_from(door.key) == room.id
		one_way.toggled.connect(func(on: bool) -> void: annotations.set_door_value(door.key, "one_way_from", room.id if on else ""))
		head.add_child(one_way)
		var req := LineEdit.new()
		req.placeholder_text = "requires (e.g. dash, red_key)"
		req.text = ", ".join(annotations.get_door_requires(door.key))
		var gate_sources: Array = analysis.door_gate_sources.get(door.key, [])
		if not gate_sources.is_empty():
			var scanned := analysis.get_door_requires(door.key)
			req.placeholder_text = "scanned gate: " + ", ".join(scanned)
			req.tooltip_text = "Gate node(s) %s set idp_requires = %s" % [", ".join(gate_sources), ", ".join(scanned)]
		MDSUi.commit_line(req, func(t: String) -> void: annotations.set_door_value(door.key, "requires", Array(MDSAnnotations.parse_list(t))))
		box.add_child(req)
	if door.is_one_sided() and annotations.get_door_one_way_from(door.key).is_empty():
		var warn := MDSUi.label("Passage only painted on one side.")
		warn.modulate = Color(1, 0.8, 0.3)
		box.add_child(warn)

func _add_link_row(id: String, index: int) -> void:
	var link: Dictionary = annotations.get_links()[index]
	var other_id: String = link.b if link.a == id else link.a
	var row := HBoxContainer.new()
	inspector.add_child(row)
	var target := LinkButton.new()
	var other := model.get_room(other_id)
	target.text = "<-> %s%s" % [analysis.get_room_name(other_id), " [L%d]" % other.layer if other else " (missing)"]
	target.pressed.connect(func() -> void: select_room(other_id, true))
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(target)
	var remove := MDSUi.button("x", "Remove link")
	remove.pressed.connect(func() -> void: annotations.remove_link(index))
	row.add_child(remove)
	var fields := HBoxContainer.new()
	inspector.add_child(fields)
	var note := LineEdit.new()
	note.placeholder_text = "note (Elevator...)"
	note.text = link.get("note", "")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MDSUi.commit_line(note, func(t: String) -> void: annotations.set_link_value(index, "note", t.strip_edges()))
	fields.add_child(note)
	var req := LineEdit.new()
	req.placeholder_text = "requires"
	req.text = ", ".join(link.get("requires", []))
	req.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MDSUi.commit_line(req, func(t: String) -> void: annotations.set_link_value(index, "requires", Array(MDSAnnotations.parse_list(t))))
	fields.add_child(req)

# --- MDSAnalysisViews host callbacks ---------------------------------------------------

func ui_select_room(id: String) -> void:
	canvas.highlight_rooms.clear()
	select_room(id, true)

func ui_focus_rooms(ids: Array, route: Array) -> void:
	canvas.highlight_rooms.clear()
	for id in ids:
		canvas.highlight_rooms[id] = true
	if route.size() == 2:
		canvas.route.assign(analysis.find_path(route[0], route[1]))
	route_button.visible = not canvas.highlight_rooms.is_empty() or not canvas.route.is_empty()
	# Jump to the layer holding most of the highlighted rooms.
	var counts: Dictionary = {}
	for id in canvas.highlight_rooms:
		var room := model.get_room(id)
		if room:
			counts[room.layer] = counts.get(room.layer, 0) + 1
	if not counts.is_empty() and not counts.has(canvas.layer):
		var best: int = counts.keys()[0]
		for l in counts:
			if counts[l] > counts[best]:
				best = l
		_set_layer(best)
	canvas.redraw()

func ui_jump_to_issue(issue: Dictionary) -> void:
	if not issue.get("room_id", "").is_empty():
		select_room(issue.room_id, true)
	elif issue.cell != Vector3i.MAX:
		_set_layer(issue.cell.z)
		canvas.pan = canvas.size / 2.0 - (Vector2(issue.cell.x, issue.cell.y) + Vector2(0.5, 0.5)) * canvas.get_cell_px()
		canvas._after_view_change()

func ui_set_start_from_selection() -> void:
	if not canvas.selected_room.is_empty():
		annotations.set_start_room(canvas.selected_room)

func ui_area_color(area: String) -> Color:
	return MDSMapCanvas.area_color(area)

func ui_stats_header() -> String:
	var assigned := model.rooms.values().filter(func(r: MDSMapModel.Room) -> bool: return not r.scene_uid.is_empty())
	var irregular := assigned.filter(func(r: MDSMapModel.Room) -> bool: return r.is_irregular())
	var t := "[b]%s[/b]\n" % map_data_path
	t += "%d rooms (%d irregular), %d cells, %d doors, %d layer(s)\n" % [assigned.size(), irregular.size(), model.cells.size(), model.doors.size(), model.layers.size()]
	for l in model.layers:
		var rooms := model.get_rooms_on_layer(l)
		var cells := 0
		for r in rooms:
			cells += r.cells.size()
		t += "  %d: %s: %d rooms, %d cells\n" % [l, model.get_layer_name(l), rooms.size(), cells]
	return t

# --- Context menu, pins, play -----------------------------------------------------------------

func _on_canvas_context(room_id: String, cell_pos: Vector2, local_pos: Vector2) -> void:
	_context_room = room_id
	_context_cell = cell_pos
	context_menu.clear()
	var room := model.get_room(room_id) if model else null
	var has_scene := room != null and not room.scene_path.is_empty()
	if room:
		context_menu.add_item("Open scene", ContextItem.OPEN)
		context_menu.set_item_disabled(context_menu.get_item_index(ContextItem.OPEN), not has_scene)
		context_menu.add_item("Play from here", ContextItem.PLAY_HERE)
		context_menu.set_item_disabled(context_menu.get_item_index(ContextItem.PLAY_HERE), not has_scene)
		context_menu.add_item("Run this room scene only", ContextItem.RUN_SCENE)
		context_menu.set_item_disabled(context_menu.get_item_index(ContextItem.RUN_SCENE), not has_scene)
		context_menu.add_separator()
		context_menu.add_item("Set as start room", ContextItem.SET_START)
		if not canvas.selected_room.is_empty() and canvas.selected_room != room_id:
			context_menu.add_item("Route from selected room to here", ContextItem.ROUTE)
			context_menu.add_item("Link selected room to this room", ContextItem.LINK)
		context_menu.add_separator()
	context_menu.add_item("Add pin here...", ContextItem.ADD_PIN)
	if _nearest_pin(cell_pos) >= 0:
		context_menu.add_item("Remove nearest pin", ContextItem.REMOVE_PIN)
	if room:
		context_menu.add_separator()
		context_menu.add_item("Copy scene UID", ContextItem.COPY_UID)
	context_menu.add_item("Copy cell coordinates", ContextItem.COPY_CELL)
	context_menu.reset_size()
	context_menu.position = Vector2i(canvas.get_screen_position() + local_pos)
	context_menu.popup()

func _on_context_menu(id: int) -> void:
	var cell := Vector3i(floori(_context_cell.x), floori(_context_cell.y), canvas.layer)
	match id:
		ContextItem.OPEN:
			_open_room_scene(_context_room)
		ContextItem.PLAY_HERE:
			_play_from(_context_room, _context_cell)
		ContextItem.RUN_SCENE:
			var room := model.get_room(_context_room)
			if room:
				EditorInterface.play_custom_scene(room.scene_path)
		ContextItem.SET_START:
			annotations.set_start_room(_context_room)
		ContextItem.ROUTE:
			_show_route(canvas.selected_room, _context_room)
		ContextItem.LINK:
			annotations.add_link(canvas.selected_room, _context_room, "")
		ContextItem.ADD_PIN:
			_pending_pin_cell = _context_cell
			pin_text.text = ""
			pin_dialog.popup_centered()
			pin_text.grab_focus()
		ContextItem.REMOVE_PIN:
			annotations.remove_pin(_nearest_pin(_context_cell))
		ContextItem.COPY_UID:
			var room := model.get_room(_context_room)
			if room:
				DisplayServer.clipboard_set(room.scene_uid)
				_set_status("Copied %s" % room.scene_uid)
		ContextItem.COPY_CELL:
			DisplayServer.clipboard_set("%d,%d,%d" % [cell.x, cell.y, cell.z])
			_set_status("Copied %d,%d,%d" % [cell.x, cell.y, cell.z])

func _nearest_pin(cell_pos: Vector2) -> int:
	var best := -1
	var best_d := 0.6
	var pins := annotations.get_pins() if annotations else []
	for i in pins.size():
		if int(pins[i].layer) != canvas.layer:
			continue
		var d := Vector2(pins[i].x, pins[i].y).distance_to(cell_pos)
		if d < best_d:
			best_d = d
			best = i
	return best

func _confirm_pin() -> void:
	var text := pin_text.text.strip_edges()
	if text.is_empty():
		return
	annotations.add_pin(canvas.layer, _pending_pin_cell, text, MDSAnnotations.PIN_KINDS[pin_kind.selected])
	pin_text.text = ""

func _open_room_scene(id: String) -> void:
	var room := model.get_room(id) if model else null
	if not room or room.scene_path.is_empty():
		return
	EditorInterface.open_scene_from_path(room.scene_path)
	_set_status("Opened: %s" % room.scene_path.get_file())

## Runs the game starting in this room (see MDSPlayHere). With [param prefer_save_point]
## the player starts at the room's save point when it has one, else at [param cell_pos].
func _play_from(id: String, cell_pos: Vector2, prefer_save_point := false) -> void:
	var room := model.get_room(id)
	if not room or room.scene_path.is_empty():
		return
	var local := (cell_pos - Vector2(room.min_cell)) * _get_cell_size()
	var saves: Array = scene_database.get(room.scene_path, {}).get("save_points", [])
	if prefer_save_point and not saves.is_empty():
		local = saves[0].position
	_set_status(MDSPlayHere.play(room.scene_path, room.scene_uid, room.layer, local))

# --- Export -------------------------------------------------------------------------------------

func _on_export_menu(id: int) -> void:
	if not model:
		_set_status("Nothing to export: no map loaded.")
		return
	var base := "%s/%s_%s" % [EXPORT_DIR, map_data_path.get_file().get_basename(), Time.get_datetime_string_from_system().replace(":", "-")]
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	match id:
		ExportItem.JSON:
			_write_export(base + ".json", MDSExporters.to_json(model, annotations, analysis, scene_database, filter_categories))
		ExportItem.DOT:
			_write_export(base + ".dot", MDSExporters.to_dot(analysis))
		ExportItem.MARKDOWN:
			var assigned := model.rooms.values().filter(func(r: MDSMapModel.Room) -> bool: return not r.scene_uid.is_empty())
			var collectibles := 0
			for meta in scene_database.values():
				collectibles += meta.get("collectibles", []).size()
			var summary := {"Rooms": assigned.size(), "Cells": model.cells.size(), "Layers": model.layers.size(), "Doors": model.doors.size(), "Collectibles": collectibles, "Start room": analysis.get_room_name(analysis.start_room_id)}
			var size_of := func(id: String) -> String:
				var room := model.get_room(id)
				return "%d cells%s" % [room.cells.size(), " (irregular)" if room.is_irregular() else ""]
			_write_export(base + ".md", MDSExporters.to_markdown(map_data_path.get_file(), summary, annotations, analysis, issues, size_of))
		ExportItem.PNG:
			_export_png(base + ".png")

func _write_export(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		_set_status("Export failed: %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(content)
	file.close()
	_finish_export(path)

func _finish_export(path: String) -> void:
	_set_status("Exported %s" % path)
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()
	EditorInterface.get_file_system_dock().navigate_to_path(path)

## Renders the whole current layer off-screen at a fixed scale and saves it.
func _export_png(path: String) -> void:
	if _export_viewport:
		_set_status("Export already in progress...")
		return
	var bounds := model.get_layer_bounds(canvas.layer)
	if bounds.size == Vector2i.ZERO:
		_set_status("Export failed: empty layer")
		return
	var margin := 40.0
	var clone := MDSMapCanvas.new()
	clone.in_game_cell_size = canvas.in_game_cell_size
	clone.metsys_default_color = canvas.metsys_default_color
	clone.color_mode = canvas.color_mode
	clone.show = canvas.show.duplicate()
	clone.show.previews = false
	clone.marker_filters = canvas.marker_filters
	clone.issue_cells = canvas.issue_cells
	clone.selected_room = ""
	clone.route = canvas.route.duplicate()
	clone.layer = canvas.layer
	# Aim for ~160 px per cell, capped to a sane texture size.
	var cell_w := clampf(8192.0 / maxf(1.0, bounds.size.x), 24.0, 160.0)
	clone.zoom = cell_w / MDSMapCanvas.BASE_CELL_WIDTH
	var cell_px := clone.get_cell_px()
	var img_size := Vector2(bounds.size) * cell_px + Vector2(margin, margin) * 2.0
	img_size.y = minf(img_size.y, 8192.0)
	clone.pan = Vector2(margin, margin + 30.0) - Vector2(bounds.position) * cell_px
	# Room for the title above and the legend below, so neither covers the map.
	img_size.y += 30.0 + (17.0 * canvas.get_legend().size() + 12.0 if canvas.show.legend else 0.0)
	_export_viewport = SubViewport.new()
	_export_viewport.size = Vector2i(img_size)
	_export_viewport.transparent_bg = false
	_export_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	clone.size = img_size
	_export_viewport.add_child(clone)
	add_child(_export_viewport)
	clone.set_data(model, annotations, analysis, scene_database)
	_set_status("Rendering map image...")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _export_viewport.get_texture().get_image()
	var err := img.save_png(path) if img else ERR_CANT_CREATE
	_export_viewport.queue_free()
	_export_viewport = null
	if err == OK:
		_finish_export(path)
	else:
		_set_status("PNG export failed (error %d)" % err)

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
