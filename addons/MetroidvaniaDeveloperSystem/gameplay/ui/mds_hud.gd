@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_hud.svg")
class_name MDSHud
extends Control
## The heads-up display, in the game's UI layer: the player's health as masks, its mana as a bar,
## its currency (and level, with LEVELS progression) top left, and the boss's name and health at
## the bottom while a boss fight is on ([signal MDSGameplay.boss_started] to
## [signal MDSGameplay.boss_ended]). MDS's minimap stays where Create game scene put it.
## It reads the game through [method MDSGameplayUi.game_for]; delete it to use your own.

@export var mask_size := 26.0
@export var mask_gap := 6.0
@export var full_color := Color(0.95, 0.93, 0.88)
@export var empty_color := Color(0.25, 0.24, 0.28, 0.8)
@export var mana_color := Color(0.55, 0.7, 1.0)
## Mana bar width per point of mana.
@export var mana_px := 1.6
@export var margin := Vector2(24, 20)
@export var boss_bar_size := Vector2(560, 14)

var currency_label: Label
var level_label: Label
var boss_label: Label
var boss_bar: ProgressBar
var _health := Vector2i(-1, -1)
var _mana := Vector2i(-1, -1)
var _kit: MDSGameplay
var _game: MDSWorldGame
var _boss_box: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not theme:
		theme = MDSGameplayUi.get_theme()
	currency_label = MDSGameplayUi.label(self, "", 20, MDSGameplayUi.GOLD)
	level_label = MDSGameplayUi.label(self, "", 16, MDSGameplayUi.DIM)
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_box)
	boss_label = MDSGameplayUi.label(_boss_box, "", 20)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = ProgressBar.new()
	boss_bar.show_percentage = false
	boss_bar.custom_minimum_size = boss_bar_size
	_boss_box.add_child(boss_bar)
	_boss_box.visible = false
	_connect.call_deferred()

func _connect() -> void:
	_game = MDSGameplayUi.game_for(self)
	_kit = MDSGameplay.find(_game) if _game else null
	if not _kit:
		return
	_kit.boss_started.connect(func(_b: String) -> void: _update_boss())
	_kit.boss_ended.connect(func(_b: String, _won: bool) -> void: _update_boss())
	_kit.currency_changed.connect(func(_c: int) -> void: _update_labels())
	_kit.level_up.connect(func(_l: int) -> void: _update_labels())
	_update_labels()
	_update_boss()

## The player's health now: (current, max).
func get_health() -> Vector2i:
	var h := MDSHealth.of(_game.player) if _game and is_instance_valid(_game.player) else null
	if h:
		return Vector2i(h.current, h.get_max())
	return Vector2i(_kit.health, _kit.player_max_health()) if _kit else Vector2i.ZERO

## The player's mana now: (current, max).
func get_mana() -> Vector2i:
	return Vector2i(_kit.mana, _kit.player_max_mana()) if _kit else Vector2i.ZERO

## Whether the boss bar shows.
func is_boss_bar_shown() -> bool:
	return _boss_box.visible

func _process(_delta: float) -> void:
	if not _kit:
		return
	var h := get_health()
	var m := get_mana()
	if h != _health or m != _mana:
		_health = h
		_mana = m
		queue_redraw()
	if _boss_box.visible:
		var b := MDSHealth.of(_kit.boss_node) if is_instance_valid(_kit.boss_node) else null
		if b:
			boss_bar.max_value = b.get_max()
			boss_bar.value = b.current

func _update_labels() -> void:
	if not _kit:
		return
	currency_label.text = "◆ %d" % _kit.currency
	var y := margin.y + mask_size + 18.0
	currency_label.position = Vector2(margin.x, y)
	level_label.visible = _kit.uses_levels()
	level_label.text = "Lv %d" % _kit.get_level()
	level_label.position = Vector2(margin.x + 120.0, y + 2.0)

func _update_boss() -> void:
	var on := _kit != null and not _kit.current_boss.is_empty()
	_boss_box.visible = on
	if on:
		boss_label.text = _kit.current_boss
		_boss_box.reset_size()
		_boss_box.position = Vector2((size.x - _boss_box.size.x) * 0.5, size.y - _boss_box.size.y - 28.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _boss_box and _boss_box.visible:
		_update_boss()

func _draw() -> void:
	if not _kit:
		return
	var h := _health
	for i in h.y:
		var c := Vector2(margin.x + mask_size * 0.5 + i * (mask_size + mask_gap), margin.y + mask_size * 0.5)
		_draw_mask(c, i < h.x)
	var m := _mana
	if m.y > 0:
		var r := Rect2(margin.x, margin.y + mask_size + 6.0, m.y * mana_px, 8.0)
		draw_rect(r, empty_color)
		draw_rect(Rect2(r.position, Vector2(r.size.x * float(m.x) / m.y, r.size.y)), mana_color)

func _draw_mask(c: Vector2, full: bool) -> void:
	var s := mask_size * 0.5
	var pts := PackedVector2Array([c + Vector2(-s, -s * 0.6), c + Vector2(0, -s), c + Vector2(s, -s * 0.6), c + Vector2(s * 0.8, s * 0.4), c + Vector2(0, s), c + Vector2(-s * 0.8, s * 0.4)])
	draw_colored_polygon(pts, full_color if full else empty_color)
	if full:
		for x in [-0.35, 0.35]:
			draw_circle(c + Vector2(s * x, -s * 0.1), s * 0.16, Color(0.1, 0.1, 0.14))
