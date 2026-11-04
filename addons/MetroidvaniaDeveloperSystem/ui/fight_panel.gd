@tool
class_name MDSFightPanel
extends Control
## The Fight editor, a mode of the MetDevSys panel: a fight's moves as a graph. Select an
## [MDSMoveBoss] or [MDSMoveEnemy] in the scene (or open a .tres of a phase or move) and it shows up,
## a tab for each phase. Drag a line from a move's port to another to put it there, drag a move up or
## down among its siblings to reorder it, and edit the selected one on the right. Everything is one
## undo step and goes straight into the resources, so nothing in the game depends on this panel.
##
## While the game runs, what each fighter is doing lights up, reported through the debugger.

const NODE_GAP := Vector2(70, 14)
const COLOR_PATTERN := Color(0.62, 0.78, 1.0)
const COLOR_ACTION := Color(1, 1, 1)
const COLOR_ROOT := Color(0.8, 1.0, 0.8)
const COLOR_LIVE := Color(1.0, 0.82, 0.3)
const COLOR_ERROR := Color(1.0, 0.45, 0.4)
const COLOR_WARNING := Color(1.0, 0.8, 0.45)
## Seconds without news before a running fighter is forgotten.
const LIVE_TIMEOUT := 2.0

var doc := MDSFightDocument.new()
var side_panel: MDSSidePanel
## Where the host puts the mode switch.
var toolbar: Container
var graph: GraphEdit
var phase_tabs: TabBar
var banner: HBoxContainer
var banner_text: Label
var issues: ItemList
var fields: VBoxContainer
var status: Label
var fighter_picker: OptionButton
var recipe_picker: OptionButton
var add_where: OptionButton
var add_box: Container
var live_picker: OptionButton
var live_text: RichTextLabel

## The path of the selected move ("": the root).
var selected_path := ""
## Name of each GraphNode -> its path.
var node_paths: Dictionary = {}
## Each path -> its GraphNode.
var nodes_by_path: Dictionary = {}
## Running fighters: id -> their last snapshot, with the time it came.
var live: Dictionary = {}
var live_id := 0
var live_follow := true

var _findings: Array[Dictionary] = []
var _fighters: Array[Node] = []
var _scene_seen := 0
var _dialog: FileDialog

func _ready() -> void:
	if is_part_of_edited_scene():
		return
	_build()
	doc.changed.connect(_refresh)
	doc.values_changed.connect(_refresh_graph_only)
	if Engine.is_editor_hint():
		EditorInterface.get_selection().selection_changed.connect(_on_editor_selection)
		visibility_changed.connect(_on_shown)
		_on_shown()
	_refresh()

func _process(_delta: float) -> void:
	_forget_stale_fighters()
	# Watched rather than told: the editor sends no scene_changed for a scene opened in its empty tab.
	if graph and Engine.is_editor_hint() and is_visible_in_tree():
		var root := EditorInterface.get_edited_scene_root()
		if (root.get_instance_id() if root else 0) != _scene_seen:
			on_scene_changed(root)

# --- Building it ---------------------------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var main := HBoxContainer.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main)
	side_panel = MDSSidePanel.new()
	main.add_child(side_panel)
	_build_side()
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(split)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(middle)
	_build_middle(middle)
	var right := ScrollContainer.new()
	right.custom_minimum_size.x = 300.0 * MDSUi.editor_scale()
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	fields = VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(fields)
	resized.connect(func() -> void:
		if side_panel:
			side_panel.fit_width(size.x, (MDSSidePanel.WIDTH + 620.0) * MDSUi.editor_scale()))

func _build_side() -> void:
	toolbar = side_panel.add_section("Fight")
	fighter_picker = OptionButton.new()
	fighter_picker.clip_text = true
	fighter_picker.fit_to_longest_item = false
	fighter_picker.tooltip_text = "The bosses and enemies with moves in the open scene"
	fighter_picker.item_selected.connect(func(i: int) -> void:
		var at := fighter_picker.get_item_id(i)
		if at < _fighters.size() and is_instance_valid(_fighters[at]):
			set_target(_fighters[at]))
	toolbar.add_child(fighter_picker)
	var open := MDSUi.button("Open .tres…", "Open a phase or a move saved in a file of its own")
	open.pressed.connect(_open_dialog)
	var inspect := MDSUi.button("Inspect", "Show the selected move in the editor's inspector")
	inspect.pressed.connect(func() -> void:
		MDSFightFields.inspect(doc.entry(selected_path).get("res")))
	MDSSidePanel.row(toolbar, [open, inspect])
	recipe_picker = OptionButton.new()
	recipe_picker.name = "RecipePicker"
	recipe_picker.clip_text = true
	recipe_picker.tooltip_text = "Replace the boss's fight with a recipe, to change. Undo brings back what it had"
	recipe_picker.add_item("Start from a recipe…")
	for r: String in MDSMoveRecipes.RECIPES:
		recipe_picker.add_item(r)
	recipe_picker.item_selected.connect(func(i: int) -> void:
		if i > 0:
			doc.start_from_recipe(recipe_picker.get_item_text(i))
		recipe_picker.select(0))
	toolbar.add_child(recipe_picker)
	var phase_box := side_panel.add_section("Phases")
	var add_phase := MDSUi.button("Add", "Add a phase, starting at half the health of the last")
	add_phase.pressed.connect(func() -> void: doc.add_phase())
	var cut_phase := MDSUi.button("Remove", "Remove this phase")
	cut_phase.pressed.connect(func() -> void: doc.remove_phase(doc.phase_index))
	MDSSidePanel.row(phase_box, [add_phase, cut_phase])
	var edit := side_panel.add_section("Selected move")
	var up := MDSUi.button("Up", "Move it before the one above it")
	up.pressed.connect(func() -> void: _shift(-1))
	var down := MDSUi.button("Down", "Move it after the one below it")
	down.pressed.connect(func() -> void: _shift(1))
	MDSSidePanel.row(edit, [up, down])
	var copy := MDSUi.button("Duplicate", "A copy of it and everything in it, right after it")
	copy.pressed.connect(func() -> void: doc.duplicate_at(selected_path))
	var unique := MDSUi.button("Make unique", "It is used in more than one place: give this place a copy of its own")
	unique.pressed.connect(func() -> void: doc.make_unique(selected_path))
	MDSSidePanel.row(edit, [copy, unique])
	var cut := MDSUi.button("Remove", "Take it out, and everything in it")
	cut.pressed.connect(func() -> void: doc.remove(selected_path))
	edit.add_child(cut)
	add_box = side_panel.add_section("Add a move")
	add_where = OptionButton.new()
	add_where.name = "AddWhere"
	add_where.clip_text = true
	add_where.tooltip_text = "Where a new move goes"
	add_box.add_child(add_where)
	_build_add_buttons()
	var live_box := side_panel.add_section("While playing")
	live_picker = OptionButton.new()
	live_picker.clip_text = true
	live_picker.tooltip_text = "Which running fighter the graph follows"
	live_picker.item_selected.connect(func(i: int) -> void:
		live_id = live_picker.get_item_id(i)
		live_follow = false
		_show_live())
	live_box.add_child(live_picker)
	live_text = RichTextLabel.new()
	live_text.fit_content = true
	live_text.bbcode_enabled = true
	live_text.text = "[i]Run the game to see the fight here.[/i]"
	live_box.add_child(live_text)

## A button for every kind of move, those of your own too.
func _build_add_buttons() -> void:
	for c in add_box.get_children():
		if c is Button and not c is OptionButton:
			c.queue_free()
	MDSMoveTree.forget_classes()
	var classes: Array[Dictionary] = []
	for c: Dictionary in ProjectSettings.get_global_class_list():
		var name := String(c["class"])
		if name != "MDSMove" and MDSMoveTree.is_move_class(name):
			classes.append(c)
	classes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["class"]) < String(b["class"]))
	for c in classes:
		var name := String(c["class"])
		var button := MDSUi.button(name.trim_prefix("MDSMove"), "Add a %s" % name)
		button.name = "Add_%s" % name
		var script_path := String(c["path"])
		button.pressed.connect(func() -> void: add_new(script_path))
		add_box.add_child(button)

func _build_middle(middle: VBoxContainer) -> void:
	banner = HBoxContainer.new()
	banner_text = Label.new()
	banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.add_child(banner_text)
	var editable := MDSUi.button("Make editable", "Copy these phases onto the boss, to change. Undo takes it back")
	editable.name = "MakeEditable"
	editable.pressed.connect(func() -> void: doc.make_editable())
	banner.add_child(editable)
	middle.add_child(banner)
	phase_tabs = TabBar.new()
	phase_tabs.tab_changed.connect(func(i: int) -> void:
		if i != doc.phase_index:
			selected_path = ""
			doc.set_phase(i))
	middle.add_child(phase_tabs)
	graph = GraphEdit.new()
	graph.name = "Graph"
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	graph.show_arrange_button = false
	graph.connection_request.connect(_on_connect)
	graph.disconnection_request.connect(_on_disconnect)
	graph.delete_nodes_request.connect(_on_delete)
	graph.duplicate_nodes_request.connect(func() -> void: doc.duplicate_at(selected_path))
	graph.node_selected.connect(_on_node_selected)
	graph.end_node_move.connect(_on_nodes_moved)
	middle.add_child(graph)
	status = Label.new()
	status.clip_text = true
	middle.add_child(status)
	issues = ItemList.new()
	issues.custom_minimum_size.y = 80.0 * MDSUi.editor_scale()
	issues.allow_reselect = true
	issues.item_selected.connect(_on_issue_selected)
	middle.add_child(issues)

# --- What it shows -------------------------------------------------------------------------------

## Opens [param obj]: an [MDSMoveBoss], an [MDSMoveEnemy], or a phase or move.
func set_target(obj: Object) -> void:
	if obj == doc.target:
		return
	selected_path = ""
	doc.open(obj)
	_show_picked()

func _refresh() -> void:
	if not graph:
		return
	if not doc.is_open() and not doc.entries().is_empty():
		doc.open(null) # what it showed is gone (its scene closed)
		return
	_refresh_tabs()
	_refresh_banner()
	_rebuild_graph()
	_refresh_issues()
	_refresh_add_where()
	_rebuild_fields()
	_show_live()

## After a value changed: the graph says what the fields don't, the fields stay where they are.
func _refresh_graph_only() -> void:
	_rebuild_graph()
	_refresh_issues()
	_show_live()

func _refresh_tabs() -> void:
	phase_tabs.visible = doc.has_phases()
	phase_tabs.set_block_signals(true)
	var list := doc.phases()
	phase_tabs.tab_count = list.size()
	for i in list.size():
		phase_tabs.set_tab_title(i, "Phase %d (%d%%)" % [i + 1, roundi(list[i].health_threshold * 100.0)])
	if list.size() > 0:
		phase_tabs.current_tab = doc.phase_index
	phase_tabs.set_block_signals(false)

func _refresh_banner() -> void:
	banner.visible = doc.read_only or not doc.is_open()
	banner.get_node(^"MakeEditable").visible = doc.read_only and not doc.phases().is_empty()
	if not doc.is_open():
		banner_text.text = "Select an MDSMoveBoss or an MDSMoveEnemy in the scene, or open a .tres of a phase or a move."
	else:
		banner_text.text = doc.read_only_reason
	recipe_picker.disabled = not doc.has_phases()

func _rebuild_graph() -> void:
	graph.clear_connections()
	for c in graph.get_children():
		if c is GraphNode:
			graph.remove_child(c)
			c.queue_free()
	node_paths.clear()
	nodes_by_path.clear()
	_findings = MDSFightCheck.check(doc.phases() if doc.has_phases() else [], doc.root() if not doc.has_phases() else null)
	var entries := doc.entries()
	for i in entries.size():
		var node := _make_node(entries[i], i)
		graph.add_child(node)
		node_paths[node.name] = entries[i]["path"]
		nodes_by_path[entries[i]["path"]] = node
	for e in entries:
		if e["path"].is_empty():
			continue
		var from: GraphNode = nodes_by_path[e["parent"]]
		graph.connect_node(from.name, _port_of(doc.entry(e["parent"])["res"], e["slot"]), nodes_by_path[e["path"]].name, 0)
	_layout()
	if not nodes_by_path.has(selected_path):
		selected_path = ""
	if nodes_by_path.has(selected_path):
		graph.set_selected(nodes_by_path[selected_path])

func _port_of(res: Object, slot: StringName) -> int:
	var slots := MDSMoveTree.slots_of(res)
	for i in slots.size():
		if slots[i]["name"] == slot:
			return i
	return 0

func _make_node(e: Dictionary, index: int) -> GraphNode:
	var res: Object = e["res"]
	var node := GraphNode.new()
	node.name = "N%d" % index
	var kind := MDSFightDocument.short_name(res)
	var own_title := String(res.get(&"title")) if res is MDSMove else ""
	node.title = own_title if not own_title.is_empty() else kind
	node.resizable = false
	var slots := MDSMoveTree.slots_of(res)
	var tint := COLOR_ROOT if e["path"].is_empty() else (COLOR_PATTERN if not slots.is_empty() else COLOR_ACTION)
	node.self_modulate = tint
	node.set_meta(&"tint", tint)
	node.set_meta(&"title", node.title)
	var head := Label.new()
	head.text = kind if not own_title.is_empty() else ""
	head.custom_minimum_size.x = 120.0
	head.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	node.add_child(head)
	var left: bool = not e["path"].is_empty()
	node.set_slot(0, left, 0, Color.WHITE, false, 0, Color.WHITE)
	for text in _lines_of(res):
		var line := Label.new()
		line.text = text
		line.add_theme_font_size_override("font_size", 12)
		node.add_child(line)
	for s in slots:
		var row := Label.new()
		row.name = "Slot_%s" % s["name"]
		row.text = "%s ▸" % String(s["name"]).replace("_", " ")
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		node.add_child(row)
		node.set_slot(node.get_child_count() - 1, false, 0, Color.WHITE, true, 0, COLOR_PATTERN if s["array"] else COLOR_ROOT)
	var uses := doc.uses_of(res)
	if uses > 1:
		var shared := Label.new()
		shared.text = "shared: used %d times" % uses
		shared.add_theme_font_size_override("font_size", 12)
		shared.add_theme_color_override("font_color", COLOR_WARNING)
		node.add_child(shared)
	for f in _findings:
		if f["phase"] == (doc.phase_index if doc.has_phases() else 0) and f["path"] == e["path"] and f["level"] != MDSFightCheck.Level.INFO:
			var problem := Label.new()
			problem.name = "Problem"
			problem.text = "⚠ see below"
			problem.tooltip_text = f["text"]
			problem.mouse_filter = Control.MOUSE_FILTER_PASS
			problem.add_theme_font_size_override("font_size", 12)
			problem.add_theme_color_override("font_color", COLOR_ERROR if f["level"] == MDSFightCheck.Level.ERROR else COLOR_WARNING)
			node.add_child(problem)
			break
	return node

## The lines a move shows: its values and when it runs.
func _lines_of(res: Object) -> PackedStringArray:
	var out := MDSFightDocument.summary(res)
	if res is MDSMove:
		var move := res as MDSMove
		for c: MDSMoveCondition in move.when:
			if c:
				out.append("when " + MDSFightDocument.describe(c))
		for c: MDSMoveCondition in move.cancel_when:
			if c:
				out.append("stops if " + MDSFightDocument.describe(c))
	return out

## Lays the tree out left to right. Positions are never saved: the order of the moves is the layout.
func _layout() -> void:
	var widths := {}
	for e in doc.entries():
		var node: GraphNode = nodes_by_path[e["path"]]
		widths[e["depth"]] = maxf(float(widths.get(e["depth"], 0.0)), node.get_combined_minimum_size().x)
	var cursor := [0.0]
	if not doc.entries().is_empty():
		_place("", 0.0, 0, widths, cursor)

func _place(path: String, x: float, depth: int, widths: Dictionary, cursor: Array) -> float:
	var node: GraphNode = nodes_by_path[path]
	var height := node.get_combined_minimum_size().y
	var next_x := x + float(widths.get(depth, 0.0)) + NODE_GAP.x
	var ys: Array[float] = []
	for e in doc.entries():
		if e["parent"] == path and not e["path"].is_empty():
			ys.append(_place(e["path"], next_x, depth + 1, widths, cursor))
	var y: float
	if ys.is_empty():
		y = cursor[0]
	else:
		y = (ys[0] + ys[-1]) * 0.5
	node.position_offset = Vector2(x, y - height * 0.5 if not ys.is_empty() else y)
	if ys.is_empty():
		cursor[0] = y + height + NODE_GAP.y
		return y + height * 0.5
	return y

func _refresh_issues() -> void:
	issues.clear()
	for f in _findings:
		var prefix := "Phase %d: " % (int(f["phase"]) + 1) if doc.has_phases() else ""
		var i := issues.add_item(prefix + String(f["text"]))
		issues.set_item_metadata(i, f)
		match int(f["level"]):
			MDSFightCheck.Level.ERROR:
				issues.set_item_custom_fg_color(i, COLOR_ERROR)
			MDSFightCheck.Level.WARNING:
				issues.set_item_custom_fg_color(i, COLOR_WARNING)
	issues.visible = issues.item_count > 0

func _refresh_add_where() -> void:
	add_where.clear()
	var e := doc.entry(selected_path)
	if e.is_empty():
		return
	for s in MDSMoveTree.slots_of(e["res"]):
		if doc.has_room(selected_path, s["name"]):
			add_where.add_item("In %s" % String(s["name"]).replace("_", " "))
			add_where.set_item_metadata(add_where.item_count - 1, [selected_path, s["name"], -1])
	if int(e["index"]) >= 0:
		add_where.add_item("After this move")
		add_where.set_item_metadata(add_where.item_count - 1, [e["parent"], e["slot"], int(e["index"]) + 1])

func _rebuild_fields() -> void:
	for c in fields.get_children():
		fields.remove_child(c)
		c.queue_free()
	var e := doc.entry(selected_path)
	if e.is_empty():
		return
	var res: Object = e["res"]
	fields.add_child(MDSUi.title(MDSFightDocument.short_name(res), 14))
	if res is Node:
		MDSFightFields.build(fields, doc, res, MDSFightDocument.ENEMY_FIELDS)
	else:
		MDSFightFields.build(fields, doc, res)
	if res is MDSMove:
		MDSFightFields.build_conditions(fields, doc, res)
	if doc.has_phases():
		fields.add_child(HSeparator.new())
		fields.add_child(MDSUi.title(MDSFightDocument.short_name(doc.target), 14))
		MDSFightFields.build(fields, doc, doc.target, MDSFightDocument.BOSS_FIELDS)
	_set_fields_enabled(fields, not doc.read_only)

func _set_fields_enabled(at: Node, on: bool) -> void:
	for c in at.get_children():
		if c is BaseButton:
			(c as BaseButton).disabled = not on
		elif c is LineEdit:
			(c as LineEdit).editable = on
		elif c is SpinBox:
			(c as SpinBox).editable = on
		_set_fields_enabled(c, on)

func say(text: String) -> void:
	status.text = text

# --- What you do with it -------------------------------------------------------------------------

func _on_node_selected(node: Node) -> void:
	var path: Variant = node_paths.get(node.name)
	if path == null or path == selected_path:
		return
	selected_path = path
	_refresh_add_where()
	_rebuild_fields()

## A line dragged from a move's port to another move: the other goes there.
func _on_connect(from_node: StringName, from_port: int, to_node: StringName, _to_port: int) -> void:
	if doc.read_only or not node_paths.has(from_node) or not node_paths.has(to_node):
		return
	var parent_path: String = node_paths[from_node]
	var slots := MDSMoveTree.slots_of(doc.entry(parent_path)["res"])
	if from_port >= slots.size():
		return
	var slot: StringName = slots[from_port]["name"]
	if not doc.has_room(parent_path, slot):
		say("%s already holds a move. Take it out first." % String(slot).replace("_", " "))
		return
	if not doc.move_to(node_paths[to_node], parent_path, slot):
		say("A move can't go inside itself.")

## A line pulled off a move: it is taken out. Undo brings it back.
func _on_disconnect(_from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	if node_paths.has(to_node):
		doc.remove(node_paths[to_node])

func _on_delete(names: Array[StringName]) -> void:
	var paths: Array[String] = []
	for n in names:
		if node_paths.has(n) and not String(node_paths[n]).is_empty():
			paths.append(node_paths[n])
	# The last first, so the rest keep their places.
	paths.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) > 0)
	for p in paths:
		doc.remove(p)

## Moves dragged: among siblings, height is their order. They then settle back into the layout.
func _on_nodes_moved() -> void:
	var seen := {}
	for e in doc.entries():
		var node: GraphNode = nodes_by_path[e["path"]]
		if node.selected and int(e["index"]) >= 0:
			seen["%s|%s" % [e["parent"], e["slot"]]] = e
	var changed_order := false
	for key: String in seen:
		var e: Dictionary = seen[key]
		var siblings := doc.entries().filter(func(o: Dictionary) -> bool:
			return o["parent"] == e["parent"] and o["slot"] == e["slot"] and int(o["index"]) >= 0)
		siblings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (nodes_by_path[a["path"]] as GraphNode).position_offset.y < (nodes_by_path[b["path"]] as GraphNode).position_offset.y)
		var order: Array = siblings.map(func(o: Dictionary) -> int: return o["index"])
		if doc.reorder(e["parent"], e["slot"], order):
			changed_order = true
	if not changed_order:
		_layout()

func _shift(by: int) -> void:
	var e := doc.entry(selected_path)
	if e.is_empty() or int(e["index"]) < 0:
		return
	var to := int(e["index"]) + by
	var size_of: int = (doc.entry(e["parent"])["res"].get(e["slot"]) as Array).size()
	if to < 0 or to >= size_of:
		return
	var parent: String = e["parent"]
	var slot: StringName = e["slot"]
	if doc.move_to(selected_path, parent, slot, to):
		selected_path = MDSMoveTree.child_path(parent, slot, to)
		_refresh()

## Adds a new move of the script at [param script_path] where "Add a move" says.
func add_new(script_path: String) -> bool:
	if doc.read_only or not doc.is_open():
		return false
	if add_where.selected < 0:
		say("Select where it goes first: a move with room in it, or one to add after.")
		return false
	var where: Array = add_where.get_item_metadata(add_where.selected)
	var script := load(script_path) as Script
	var move := script.new() as Resource if script and script.can_instantiate() else null
	if not move:
		say("Couldn't make one: its script needs @tool.")
		return false
	var ok := doc.add_move(move, where[0], where[1], where[2])
	if ok:
		var index: int = where[2]
		var parent: String = where[0]
		var slot: StringName = where[1]
		var held: Variant = doc.entry(parent)["res"].get(slot)
		if held is Array:
			selected_path = MDSMoveTree.child_path(parent, slot, index if index >= 0 else (held as Array).size() - 1)
		else:
			selected_path = MDSMoveTree.child_path(parent, slot)
		_refresh()
	return ok

func _on_issue_selected(index: int) -> void:
	var f: Dictionary = issues.get_item_metadata(index)
	if doc.has_phases() and f["phase"] != doc.phase_index:
		doc.set_phase(f["phase"])
	if nodes_by_path.has(f["path"]):
		selected_path = f["path"]
		_refresh()

func _open_dialog() -> void:
	if not Engine.is_editor_hint():
		return
	if not _dialog:
		_dialog = EditorFileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.add_filter("*.tres,*.res", "Phases and moves")
		_dialog.file_selected.connect(open_file)
		add_child(_dialog)
	_dialog.popup_file_dialog()

## Opens the phase or move saved at [param path].
func open_file(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res is MDSMove or res is MDSMovePhase:
		set_target(res)
	else:
		say("%s isn't a phase or a move." % path.get_file())

# --- The editor around it ------------------------------------------------------------------------

func _on_shown() -> void:
	if not is_visible_in_tree():
		return
	on_scene_changed(EditorInterface.get_edited_scene_root())
	_build_add_buttons()
	_on_editor_selection()

func _on_editor_selection() -> void:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is MDSMoveBoss or n is MDSMoveEnemy:
			set_target(n)
			return

## Another scene is showing: a fighter of the last one can no longer be edited from here. A file
## opened in the panel stays, since it belongs to no scene.
func on_scene_changed(root: Node) -> void:
	_scene_seen = root.get_instance_id() if root else 0
	refresh_fighters(root)
	var shown: Node = doc.target as Node if doc.is_open() else null
	var elsewhere := shown != null and (root == null or not (root == shown or root.is_ancestor_of(shown)))
	if elsewhere or not doc.is_open():
		selected_path = ""
		doc.open(_fighters[0] if not _fighters.is_empty() else null)
	_show_picked()

## Lists the fighters in [param root], or by default in the open scene.
func refresh_fighters(root: Node = null) -> void:
	_fighters.clear()
	fighter_picker.clear()
	if not root and Engine.is_editor_hint():
		root = EditorInterface.get_edited_scene_root()
	if root:
		_collect(root)
	for i in _fighters.size():
		fighter_picker.add_item(String(_fighters[i].name), i)
	if _fighters.is_empty():
		fighter_picker.add_item("No fighters in this scene")
		fighter_picker.set_item_disabled(0, true)
	_show_picked()

# The picker shows what is open, or nothing, so that choosing the only fighter still opens it.
func _show_picked() -> void:
	fighter_picker.select(-1)
	if doc.is_open() and doc.target is Node:
		var at := _fighters.find(doc.target)
		if at >= 0:
			fighter_picker.select(at)

func _collect(at: Node) -> void:
	if at is MDSMoveBoss or at is MDSMoveEnemy:
		_fighters.append(at)
	for c in at.get_children():
		_collect(c)

## Forwarded by the host when a scene is saved.
func on_scene_saved(_path: String) -> void:
	if is_visible_in_tree():
		refresh_fighters()

# --- While the game runs -------------------------------------------------------------------------

## News of a running fighter ([method MDSMoveTree.snapshot]).
func apply_live(snapshot: Dictionary) -> void:
	var known: bool = live.has(snapshot["id"])
	snapshot["at"] = Time.get_ticks_msec()
	live[snapshot["id"]] = snapshot
	if not known:
		_list_live()
	_show_live()

## The game stopped.
func clear_live() -> void:
	live.clear()
	live_id = 0
	live_follow = true
	_list_live()
	_show_live()

func _forget_stale_fighters() -> void:
	var now := Time.get_ticks_msec()
	var gone := false
	for id: int in live.keys():
		if now - int(live[id]["at"]) > LIVE_TIMEOUT * 1000.0:
			live.erase(id)
			gone = true
	if gone:
		if not live.has(live_id):
			live_id = 0
			live_follow = true
		_list_live()
		_show_live()

func _list_live() -> void:
	live_picker.clear()
	for id: int in live:
		live_picker.add_item(String(live[id]["name"]), id)
	if live_id != 0 and live.has(live_id):
		live_picker.select(live_picker.get_item_index(live_id))

## Which running fighter the graph follows: the one picked, one named like the open one, or any.
func _chosen_live() -> Dictionary:
	if not live_follow and live.has(live_id):
		return live[live_id]
	var name := String((doc.target as Node).name) if is_instance_valid(doc.target) and doc.target is Node else ""
	for id: int in live:
		if live[id]["name"] == name:
			live_id = id
			return live[id]
	return {}

func _show_live() -> void:
	if not live_text:
		return
	var s := _chosen_live()
	if s.is_empty():
		live_text.text = "[i]Run the game to see the fight here.[/i]" if live.is_empty() else "[i]Pick a running fighter above.[/i]"
		_light_nodes(PackedStringArray(), {})
		return
	if s["kind"] == "boss" and doc.has_phases() and live_follow:
		var tab := doc.tab_of_live_phase(s["phase"], s["threshold"])
		if tab != doc.phase_index:
			doc.set_phase(tab)
			return # refreshing shows it again
	var flags := PackedStringArray()
	for f: Variant in s["flags"]:
		if s["flags"][f]:
			flags.append(String(f))
	live_text.text = "%s\n%s, health %d/%d%s" % [s["name"], s["state"], s["health"], s["max_health"], "\nflags: " + ", ".join(flags) if not flags.is_empty() else ""]
	_light_nodes(s["active"], s["cooling"])

func _light_nodes(active: PackedStringArray, cooling: Dictionary) -> void:
	for path: String in nodes_by_path:
		var node: GraphNode = nodes_by_path[path]
		var on := path in active
		node.self_modulate = COLOR_LIVE if on else node.get_meta(&"tint")
		node.set_meta(&"live", on)
		var title: String = node.get_meta(&"title")
		node.title = "▶ " + title if on else ("%s (%.1fs)" % [title, cooling[path]] if cooling.has(path) else title)
