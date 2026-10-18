@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_health.svg")
class_name MDSHealth
extends Node
## Health of the player, an enemy, a boss or a breakable: a child of it. Hits come through its
## [MDSHurtbox] ([method apply_damage]), from MDS's environment effects (lava, steam vents,
## rockfall call [method mds_environment_hurt] or [method take_damage] on the body, which forward
## here) and from scripts. A hit does
## [code]max(1, round(amount * resistance(type) * multiplier) - defense)[/code], then makes the
## owner invulnerable for [member iframe_time] seconds and flashes its look white.

signal damaged(info: MDSDamageInfo)
signal healed(amount: int)
signal died
signal health_changed(current: int, max: int)

const FLASH_SHADER := "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/hit_flash.gdshader"

## Its maximum health, defense and resistances. Empty: 5 health, no defense.
@export var stats: MDSCombatStats
## Seconds of invulnerability after a hit (0: none, enemies usually).
@export var iframe_time := 0.8
## Flash the look white on a hit ([member visual], with the hit-flash shader).
@export var flash_on_hit := true
## What flashes. Empty: the owner's "Visual" child, else the owner.
@export var visual: CanvasItem
## Takes no damage at all (debug, cutscenes).
@export var invulnerable := false
## Damage taken is multiplied by this (the options' assist mode sets it on the player).
@export var damage_taken_multiplier := 1.0

## 0 to 1: how bright hit flashes are, for everyone (the options' flash slider; 0: none).
static var flash_scale := 1.0

var current := 5
var _max := 5
var _iframes := 0.0
var _flash := 0.0
var _dead := false

## The MDSHealth of [param node]: itself, a child, or what its get_health_component() returns.
static func of(node: Node) -> MDSHealth:
	if not is_instance_valid(node):
		return null
	if node is MDSHealth:
		return node
	if node.has_method(&"get_health_component"):
		var own: Variant = node.call(&"get_health_component")
		if own is MDSHealth:
			return own
	# A body not ready yet has no component to give: its child.
	for c in node.get_children():
		if c is MDSHealth:
			return c
	return null

## The damage a hit of [param amount] of [param damage_type] does against [param p_stats]
## (resistance, then [param multiplier], then defense; at least 1).
static func compute(amount: int, damage_type: String, p_stats: MDSCombatStats, multiplier := 1.0) -> int:
	var res := p_stats.resistance(damage_type) if p_stats else 1.0
	var defense := p_stats.defense if p_stats else 0
	return maxi(1, roundi(amount * res * multiplier) - defense)

func _ready() -> void:
	if not stats:
		stats = MDSCombatStats.make(5)
	_max = stats.max_health
	current = _max

## The owner (what the health belongs to).
func get_owner_body() -> Node:
	return get_parent()

func get_max() -> int:
	return _max

## Sets the maximum (filling up to it with [param fill]).
func set_max(value: int, fill := false) -> void:
	_max = maxi(1, value)
	current = _max if fill else mini(current, _max)
	health_changed.emit(current, _max)

func set_current(value: int) -> void:
	current = clampi(value, 0, _max)
	_dead = current <= 0
	health_changed.emit(current, _max)

func is_dead() -> bool:
	return _dead

## Whether a hit lands now (alive, not invulnerable, no invulnerability frames left).
func can_be_hurt(info: MDSDamageInfo = null) -> bool:
	if _dead or invulnerable:
		return false
	return _iframes <= 0.0 or (info != null and info.ignores_iframes)

func is_invincible() -> bool:
	return _iframes > 0.0

## Takes the hit [param info] ([param multiplier]: the hurtbox's). Returns the damage done (0:
## it didn't land).
func apply_damage(info: MDSDamageInfo, multiplier := 1.0) -> int:
	if not info or not can_be_hurt(info):
		return 0
	var dmg := compute(info.amount, info.damage_type, stats, multiplier * damage_taken_multiplier)
	if damage_taken_multiplier <= 0.0:
		dmg = 0
	current = maxi(0, current - dmg)
	_iframes = iframe_time
	if flash_on_hit and flash_scale > 0.0 and bool(MDSGameplaySetup.setting("feel/hit_flash")):
		_start_flash()
	damaged.emit(info)
	health_changed.emit(current, _max)
	if current <= 0 and not _dead:
		_dead = true
		died.emit()
	return dmg

## Physical damage from a script (and from environment effects that call it).
func take_damage(amount: float) -> int:
	return apply_damage(MDSDamageInfo.make(maxi(1, roundi(amount)), "physical"))

## Damage from an MDS environment effect ([param effect]: the lava, the steam vent...). Lava sends
## the player back to safe ground ([member MDSDamageInfo.respawn]).
func mds_environment_hurt(amount: float, effect: Node) -> int:
	var info := MDSDamageInfo.make(maxi(1, roundi(amount)), "environment", effect)
	info.respawn = effect is MDSLava or effect is MDSLavaFall
	return apply_damage(info)

func heal(amount: int) -> void:
	if _dead or amount <= 0 or current >= _max:
		return
	var before := current
	current = mini(_max, current + amount)
	healed.emit(current - before)
	health_changed.emit(current, _max)

func heal_full() -> void:
	_dead = false
	var before := current
	current = _max
	if current > before:
		healed.emit(current - before)
	health_changed.emit(current, _max)

## Back to life with full health (a respawn).
func revive() -> void:
	_dead = false
	_iframes = 0.0
	heal_full()

## Invulnerable for [param seconds] (dashing through, after a respawn).
func grant_iframes(seconds: float) -> void:
	_iframes = maxf(_iframes, seconds)

func _physics_process(delta: float) -> void:
	if _iframes > 0.0:
		_iframes = maxf(0.0, _iframes - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_set_flash(_flash)

func _start_flash() -> void:
	_flash = clampf(flash_scale, 0.0, 1.0)
	_set_flash(_flash)

## The look that flashes.
func get_visual() -> CanvasItem:
	if is_instance_valid(visual):
		return visual
	var o := get_parent()
	if o:
		var v := o.get_node_or_null(^"Visual")
		if v is CanvasItem:
			return v
		if o is CanvasItem:
			return o
	return null

static var _flash_shader: Shader

func _set_flash(amount: float) -> void:
	var v := get_visual()
	if not v:
		return
	if not _flash_shader and ResourceLoader.exists(FLASH_SHADER):
		_flash_shader = load(FLASH_SHADER)
	if _flash_shader and (not v.material or v.material is ShaderMaterial and (v.material as ShaderMaterial).shader == _flash_shader):
		if not v.material:
			var m := ShaderMaterial.new()
			m.shader = _flash_shader
			v.material = m
		(v.material as ShaderMaterial).set_shader_parameter(&"flash", amount)
	else:
		v.self_modulate = Color(1, 1, 1).lerp(Color(4, 4, 4), amount)
