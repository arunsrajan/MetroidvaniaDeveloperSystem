@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_pause_menu.svg")
class_name MDSPauseMenu
extends MDSGameplayScreen
## The pause menu: [code]pause[/code] (Esc, Start) opens it and closes it, [code]map[/code] (Tab,
## Back) opens it on the map. Its tabs, switched with [code]menu_prev[/code] and
## [code]menu_next[/code] (Q / E, LB / RB): Map (a full-screen [MDSWorldMapView] of what was
## explored, [member MDSWorldMapView.follow_player] off), Inventory ([MDSInventoryScreen]),
## Equipment ([MDSEquipmentScreen]), Journal (lore tablets read: flags [code]journal_<id>[/code]),
## Bestiary (enemies defeated), Options ([MDSOptionsMenu]) and Quit. The game is paused while it
## is open. It opens only while nothing else holds the game (no other screen, not between rooms).
##
## On the map the player writes pins of their own ([member pin_editor], an [MDSMapPinEditor]: a
## title, a short description, a kind): a click on the map opens it for a pin there, Pin where I am
## (a gamepad's way) for one where the player stands, and a click on one of their own pins to change
## it or Remove it. Markers the game put (a boss room, a quest's target) only show.
## The map zooms and moves ([member MDSWorldMapView.zoomable]): the wheel or RT / LT zoom (out
## below the whole map too), a drag or the right stick moves it, and it opens on the player. A
## marker pointed at (the mouse over it, or in the middle of the map) shows its description.

enum Tab { MAP, INVENTORY, EQUIPMENT, JOURNAL, BESTIARY, OPTIONS, QUIT }
const TAB_NAMES: PackedStringArray = ["Map", "Inventory", "Equipment", "Journal", "Bestiary", "Options", "Quit"]

## The scene Quit goes to (a title scene). Empty: the game's [MDSTitleScreen], else quit the game.
@export_file("*.tscn") var quit_scene := ""

var tabs: TabContainer
var map: MDSWorldMapView
var inventory: MDSInventoryScreen
var equipment: MDSEquipmentScreen
var options: MDSOptionsMenu
var _journal_list: VBoxContainer
var _journal_text: Label
var _bestiary_list: VBoxContainer
var _quit_box: VBoxContainer
## Pin where I am, under the map.
var pin_here: Button
## The box the player writes a pin in, over the map.
var pin_editor: MDSMapPinEditor

func _init() -> void:
	super()
	close_actions = ["ui_cancel", "pause"]

func _ready() -> void:
	super()
	add_to_group(&"mds_pause_menu")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	tabs = TabContainer.new()
	tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		tabs.set("offset_" + ["left", "top", "right", "bottom"][side], [40.0, 32.0, -40.0, -32.0][side])
	tabs.tab_changed.connect(_on_tab_changed)
	add_child(tabs)
	var map_box := VBoxContainer.new()
	map = MDSWorldMapView.new()
	map.follow_player = false
	map.pins_editable = true
	map.zoomable = true
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(200, 120)
	map.pin_requested.connect(func(at: Vector2, map_layer: int) -> void:
		if not pin_editor.is_open():
			pin_editor.open_new(at, map_layer)
			map.pins_editable = false)
	map.pin_clicked.connect(func(id: String) -> void:
		var game := MDSGameplayUi.game_for(self)
		# The player's own pins open to be changed; the game's markers only show.
		if game and not pin_editor.is_open() and MDSWorldGame.is_player_marker(game.map_pins.get(id, {})):
			pin_editor.open_edit(id, game.map_pins[id])
			map.pins_editable = false)
	map_box.add_child(map)
	pin_editor = MDSMapPinEditor.new()
	pin_editor.confirmed.connect(_on_pin_written)
	pin_editor.removed.connect(func() -> void:
		var game := MDSGameplayUi.game_for(self)
		if game:
			game.remove_map_pin(pin_editor.pin_id)
		_pin_editor_closed())
	pin_editor.cancelled.connect(_pin_editor_closed)
	map.add_child(pin_editor)
	var pin_row := HBoxContainer.new()
	pin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pin_here = MDSGameplayUi.button(pin_row, "Pin where I am", func() -> void:
		var game := MDSGameplayUi.game_for(self)
		if game and game.player and not pin_editor.is_open():
			var here := game.world.get_room_layer(game.current_room) if game.world and game.world.has_room(game.current_room) else map.layer
			pin_editor.open_new(game.player.global_position, here)
			map.pins_editable = false)
	MDSGameplayUi.label(pin_row, "Click: write a pin, or change yours   Point at a marker to read it   Wheel, LT / RT: zoom   Drag, right stick: move", 14, MDSGameplayUi.DIM)
	map_box.add_child(pin_row)
	_add_tab(map_box, Tab.MAP)
	inventory = MDSInventoryScreen.new()
	_add_tab(inventory, Tab.INVENTORY)
	equipment = MDSEquipmentScreen.new()
	_add_tab(equipment, Tab.EQUIPMENT)
	var journal := HBoxContainer.new()
	journal.add_theme_constant_override(&"separation", 18)
	_journal_list = MDSGameplayUi.scroll_list(journal)
	_journal_text = MDSGameplayUi.label(journal, "", 16, MDSGameplayUi.DIM)
	_journal_text.custom_minimum_size = Vector2(360, 0)
	_journal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_tab(journal, Tab.JOURNAL)
	var bestiary := VBoxContainer.new()
	_bestiary_list = MDSGameplayUi.scroll_list(bestiary)
	_add_tab(bestiary, Tab.BESTIARY)
	options = MDSOptionsMenu.new()
	_add_tab(options, Tab.OPTIONS)
	_quit_box = VBoxContainer.new()
	_quit_box.alignment = BoxContainer.ALIGNMENT_CENTER
	MDSGameplayUi.button(_quit_box, "Resume", close)
	MDSGameplayUi.button(_quit_box, "Quit to title" if not quit_scene.is_empty() else "Quit", quit)
	_add_tab(_quit_box, Tab.QUIT)

func _add_tab(c: Control, tab: Tab) -> void:
	c.name = TAB_NAMES[tab]
	tabs.add_child(c)

## Opens it on [param tab].
func open(tab: Tab = Tab.INVENTORY) -> void:
	open_screen()
	tabs.current_tab = tab
	_on_tab_changed(tab)

## The tab shown.
func get_tab() -> Tab:
	return tabs.current_tab as Tab

## Shows the tab [param step] after (or before) the one shown, wrapping around.
func step_tab(step: int) -> void:
	tabs.current_tab = posmod(tabs.current_tab + step, tabs.get_tab_count())

func _on_tab_changed(tab: int) -> void:
	if not is_open():
		return
	match tab:
		Tab.MAP:
			_refresh_map()
		Tab.INVENTORY:
			inventory.refresh()
		Tab.EQUIPMENT:
			equipment.refresh()
		Tab.JOURNAL:
			_refresh_journal()
		Tab.BESTIARY:
			_refresh_bestiary()
		Tab.OPTIONS:
			options.refresh()
	_focus_tab.call_deferred()

func _focus_tab() -> void:
	var c := tabs.get_current_tab_control()
	if not c or not MDSGameplayUi.focus_first(c):
		# Nothing to focus (the map): the tab bar keeps the gamepad's place.
		tabs.get_tab_bar().grab_focus()

func focus_first() -> void:
	if is_open():
		_focus_tab()

## The pin written in [member pin_editor]: put on the map as the player's own (a pin being changed
## keeps its id, place and layer).
func _on_pin_written(title: String, description: String, kind: String) -> void:
	var game := MDSGameplayUi.game_for(self)
	if game:
		var id := game.add_map_marker(pin_editor.world_pos, kind, title, description, {"id": pin_editor.pin_id, "layer": pin_editor.map_layer, "player": true})
		_refresh_map()
		map.focus_pin(id)
	_pin_editor_closed()

func _on_close() -> void:
	# A pin being written when the menu closes is let go.
	if pin_editor and pin_editor.is_open():
		pin_editor.cancel()

func _pin_editor_closed() -> void:
	map.pins_editable = true
	_refresh_map()
	if is_open() and get_tab() == Tab.MAP:
		pin_here.grab_focus()

## The map shows what the game's own map knows.
func _refresh_map() -> void:
	var game := MDSGameplayUi.game_for(self)
	if not game:
		return
	if map.world_file != game.world_file:
		map.world_file = game.world_file
	if game.map_view and game.map_view.has_method(&"get_save_data"):
		map.set_save_data(game.map_view.get_save_data())
	for id in game.visited_rooms:
		map.mark_visited(id)
	if game.player and not game.current_room.is_empty() and game.world:
		map.set_player(game.current_room, game.player.global_position - game.world.get_origin(game.current_room))
		# Zoomed in, it opens on the player.
		map.center_on(game.player.global_position)
	map.set_pins(game.map_pins)
	map.objective = game.get_objective(game.current_area) if game.has_method(&"get_objective") else ""
	map.objective_done = game.is_objective_complete(game.current_area)

## Journal entries: the flags [code]journal_<id>[/code] set by lore tablets ({title, text}).
func get_journal() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kit := MDSGameplayUi.kit_for(self)
	if not kit:
		return out
	var ids: Array = kit.flags.keys()
	ids.sort()
	for f in ids:
		if not str(f).begins_with("journal_") or not MDSGameplay.truthy(kit.flags[f]):
			continue
		var v: Variant = kit.flags[f]
		var e: Dictionary = v if v is Dictionary else {"title": str(f).trim_prefix("journal_").capitalize(), "text": str(v) if v is String else ""}
		out.append(e)
	return out

func _refresh_journal() -> void:
	MDSGameplayUi.clear(_journal_list)
	_journal_text.text = ""
	var entries := get_journal()
	if entries.is_empty():
		MDSGameplayUi.label(_journal_list, "No entries yet.", 16, MDSGameplayUi.DIM)
	for e in entries:
		var b := MDSGameplayUi.button(_journal_list, str(e.get("title", "?")))
		b.focus_entered.connect(func() -> void: _journal_text.text = str(e.get("text", "")))

func _refresh_bestiary() -> void:
	MDSGameplayUi.clear(_bestiary_list)
	var kit := MDSGameplayUi.kit_for(self)
	if not kit or kit.bestiary.is_empty():
		MDSGameplayUi.label(_bestiary_list, "No enemies defeated yet.", 16, MDSGameplayUi.DIM)
		return
	var ids: Array = kit.bestiary.keys()
	ids.sort()
	for id in ids:
		var d: MDSEnemyData = kit.get_enemy_data(str(id))
		var title: String = d.display_name if d and not d.display_name.is_empty() else str(id).capitalize()
		var b := MDSGameplayUi.button(_bestiary_list, "%s   ×%d" % [title, int(kit.bestiary[id])])
		if d and not d.bestiary_text.is_empty():
			b.tooltip_text = d.bestiary_text

## Leaves the game: [member quit_scene], else the game's title screen, else quits.
func quit() -> void:
	close()
	if not quit_scene.is_empty():
		get_tree().paused = false
		get_tree().change_scene_to_file(quit_scene)
		return
	var title := get_tree().get_first_node_in_group(&"mds_title_screen") as MDSTitleScreen
	if title:
		title.show_title()
		return
	get_tree().quit()

## Whether it may open now: no other screen open, the game not changing rooms or paused.
func can_open() -> bool:
	if is_open() or not is_inside_tree() or get_tree().paused:
		return false
	var game := MDSGameplayUi.game_for(self)
	return not (game and game.changing_room)

func _unhandled_input(event: InputEvent) -> void:
	if is_open() and pin_editor and pin_editor.is_open():
		# Writing a pin: Esc (B) puts the box away, not the menu; tabs and the map key wait.
		for a in [&"ui_cancel", &"pause"]:
			if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
				get_viewport().set_input_as_handled()
				pin_editor.cancel()
				return
		for a in [&"menu_prev", &"menu_next", &"map"]:
			if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
				get_viewport().set_input_as_handled()
				return
		return
	if is_open():
		if InputMap.has_action(&"menu_prev") and event.is_action_pressed(&"menu_prev", false, true):
			get_viewport().set_input_as_handled()
			step_tab(-1)
			return
		if InputMap.has_action(&"menu_next") and event.is_action_pressed(&"menu_next", false, true):
			get_viewport().set_input_as_handled()
			step_tab(1)
			return
		if InputMap.has_action(&"map") and event.is_action_pressed(&"map", false, true) and get_tab() == Tab.MAP:
			get_viewport().set_input_as_handled()
			close()
			return
		super(event)
		return
	if not can_open():
		return
	if InputMap.has_action(&"pause") and event.is_action_pressed(&"pause", false, true):
		get_viewport().set_input_as_handled()
		open(Tab.INVENTORY)
	elif InputMap.has_action(&"map") and event.is_action_pressed(&"map", false, true):
		get_viewport().set_input_as_handled()
		open(Tab.MAP)
