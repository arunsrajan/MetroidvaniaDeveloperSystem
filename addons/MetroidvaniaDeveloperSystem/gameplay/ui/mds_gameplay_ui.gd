@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_gameplay_ui.svg")
class_name MDSGameplayUi
extends RefCounted
## What the kit's screens share: the theme ([constant THEME_PATH], a [Theme] a developer can swap
## for their own), text sizes scaled by the options, small widget builders, finding the game and the
## kit from a UI node, and [method add_to], which puts every kit screen under a game's UI layer
## (Create game scene uses it).

const THEME_PATH := "res://addons/MetroidvaniaDeveloperSystem/gameplay/ui/mds_gameplay_theme.tres"
const BASE_FONT_SIZE := 18
const GOLD := Color(0.95, 0.82, 0.5)
const INK := Color(0.07, 0.07, 0.1, 0.94)
const TEXT := Color(0.93, 0.91, 0.86)
const DIM := Color(0.62, 0.6, 0.56)

static var _theme: Theme

## The kit's theme: [constant THEME_PATH], else one built now.
static func get_theme() -> Theme:
	if not _theme:
		_theme = load(THEME_PATH) as Theme if ResourceLoader.exists(THEME_PATH) else build_theme()
	return _theme

## [param size] scaled by the options' text size.
static func font(size: int) -> int:
	return int(round(size * MDSOptions.text_scale()))

## The theme the kit ships ([constant THEME_PATH] is made from it): dark panels with a gold
## rim, and a gold outline around whatever has the focus (gamepad and keyboard navigation).
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = BASE_FONT_SIZE
	var panel := _box(INK, Color(GOLD, 0.55), 2, 8, 16)
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	t.set_stylebox(&"panel", &"Panel", panel)
	var normal := _box(Color(0.16, 0.15, 0.2, 0.95), Color(1, 1, 1, 0.08), 1, 5, 8)
	var hover := _box(Color(0.24, 0.22, 0.28, 0.98), Color(GOLD, 0.4), 1, 5, 8)
	var pressed := _box(Color(0.32, 0.27, 0.2, 1.0), GOLD, 1, 5, 8)
	var disabled := _box(Color(0.12, 0.12, 0.14, 0.8), Color(1, 1, 1, 0.04), 1, 5, 8)
	var focus := _box(Color(0, 0, 0, 0), GOLD, 2, 5, 8)
	focus.draw_center = false
	for type in [&"Button", &"OptionButton", &"CheckButton", &"CheckBox"]:
		t.set_stylebox(&"normal", type, normal)
		t.set_stylebox(&"hover", type, hover)
		t.set_stylebox(&"pressed", type, pressed)
		t.set_stylebox(&"hover_pressed", type, pressed)
		t.set_stylebox(&"disabled", type, disabled)
		t.set_stylebox(&"focus", type, focus)
		t.set_color(&"font_color", type, TEXT)
		t.set_color(&"font_hover_color", type, Color.WHITE)
		t.set_color(&"font_focus_color", type, Color.WHITE)
		t.set_color(&"font_pressed_color", type, GOLD)
		t.set_color(&"font_disabled_color", type, DIM)
	t.set_color(&"font_color", &"Label", TEXT)
	t.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0.85))
	t.set_constant(&"outline_size", &"Label", 4)
	var track := _box(Color(0.12, 0.11, 0.14), Color(1, 1, 1, 0.12), 1, 3, 0)
	var fill := _box(GOLD.darkened(0.15), Color(0, 0, 0, 0), 0, 3, 0)
	t.set_stylebox(&"background", &"ProgressBar", track)
	t.set_stylebox(&"fill", &"ProgressBar", fill)
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	t.set_stylebox(&"focus", &"HSlider", focus)
	t.set_stylebox(&"panel", &"TabContainer", panel)
	t.set_stylebox(&"tab_selected", &"TabContainer", _box(Color(0.24, 0.21, 0.16), GOLD, 2, 5, 10))
	t.set_stylebox(&"tab_unselected", &"TabContainer", _box(Color(0.12, 0.12, 0.15), Color(1, 1, 1, 0.08), 1, 5, 10))
	t.set_stylebox(&"tab_hovered", &"TabContainer", _box(Color(0.18, 0.17, 0.2), Color(GOLD, 0.4), 1, 5, 10))
	t.set_stylebox(&"tab_focus", &"TabContainer", focus)
	t.set_color(&"font_selected_color", &"TabContainer", GOLD)
	t.set_color(&"font_unselected_color", &"TabContainer", DIM)
	t.set_stylebox(&"panel", &"ScrollContainer", StyleBoxEmpty.new())
	return t

static func _box(bg: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	return b

## The game [param node] belongs to: its [MDSWorldGame] ancestor, else [member MDSWorldGame.instance].
static func game_for(node: Node) -> MDSWorldGame:
	var n := node
	while n:
		if n is MDSWorldGame:
			return n
		n = n.get_parent()
	return MDSWorldGame.instance if is_instance_valid(MDSWorldGame.instance) else null

## The kit of [param node]'s game, or null.
static func kit_for(node: Node) -> MDSGameplay:
	var g := game_for(node)
	return MDSGameplay.find(g) if g else null

# --- Widgets ----------------------------------------------------------------------------------------

static func label(parent: Node, text := "", size := BASE_FONT_SIZE, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", font(size))
	l.add_theme_color_override(&"font_color", color)
	if parent:
		parent.add_child(l)
	return l

static func button(parent: Node, text: String, on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override(&"font_size", font(BASE_FONT_SIZE))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	if parent:
		parent.add_child(b)
	return b

## A VBox in a ScrollContainer that keeps the focused control in view.
static func scroll_list(parent: Node) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	parent.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 6)
	sc.add_child(box)
	return box

## Frees [param node]'s children now (lists rebuilt on refresh).
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

## The first control under [param root] that can take the focus (visible, enabled), or null.
static func first_focusable(root: Node) -> Control:
	for c in root.get_children():
		if c is Control and not (c as Control).is_visible_in_tree():
			continue
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
			return c
		var inner := first_focusable(c)
		if inner:
			return inner
	return null

## Gives the focus to the first focusable control under [param root]. Returns it.
static func focus_first(root: Node) -> Control:
	var c := first_focusable(root)
	if c:
		c.grab_focus()
	return c

## A duration as h:mm:ss (or m:ss).
static func format_time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]

# --- Setup -------------------------------------------------------------------------------------

## Puts the kit's screens under [param ui] (a game's UI CanvasLayer): Hud, Toast, AbilityPopup,
## PauseMenu, DialogueBox and ShopScreen (the ones it lacks), owned by [param owner] when given
## (a scene being built). Returns them by name.
static func add_to(ui: Node, owner: Node = null) -> Dictionary:
	var out: Dictionary = {}
	var specs := [["Hud", MDSHud], ["Toast", MDSToast], ["AbilityPopup", MDSAbilityPopup], ["PauseMenu", MDSPauseMenu], ["DialogueBox", MDSDialogueBox], ["ShopScreen", MDSShopScreen]]
	for spec in specs:
		var n: Node = ui.get_node_or_null(NodePath(spec[0]))
		if not n:
			n = (spec[1] as GDScript).new()
			n.name = spec[0]
			ui.add_child(n)
			if owner:
				n.owner = owner
		out[spec[0]] = n
	return out
