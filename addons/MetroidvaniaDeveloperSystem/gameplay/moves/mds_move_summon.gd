@tool
class_name MDSMoveSummon
extends MDSMove
## It calls others into the fight: adds that drop from the ceiling, or a partner, a second boss the
## fight won't end without ([member partner]).

## What comes: a scene of an [MDSEnemy]...
@export var scene: PackedScene
## ...or a script of one, like [MDSFlyer].
@export var enemy_script: Script
## Set on each as it comes: its exports by name ([code]{"recipe": "swooper"}[/code]).
@export var properties: Dictionary = {}
@export_range(1, 32, 1, "or_greater") var count := 1
## None come while this many it summoned are alive (0: no limit).
@export var max_alive := 0
@export var at: MDSMove.Anchor = MDSMove.Anchor.CEILING_ABOVE_PLAYER
## Each comes up to this far to either side, at random.
@export var scatter := 200.0
@export var offset := Vector2.ZERO
## A mark shown where each comes, for this long first.
@export_range(0.0, 10.0, 0.05, "or_greater") var marker_time := 0.4
@export var marker_color := Color(1, 1, 1, 0.5)
## It waits until they are dead, or until [member wait_seconds].
@export var wait_for_them := false
@export_range(0.0, 60.0, 0.1, "or_greater") var wait_seconds := 8.0
## The fight goes on until it falls too, and a stagger doesn't kill it.
@export var partner := false

func _start(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m[&"spawned"] = false
	var alive := ctx.summons_alive()
	var n := mini(count, maxi(0, max_alive - alive)) if max_alive > 0 else count
	m[&"n"] = n
	m[&"spots"] = []
	for i in n:
		var spot := ctx.point(at, offset) + Vector2(ctx.rng.randf_range(-scatter, scatter), 0)
		m[&"spots"].append(spot)
		if marker_time > 0.0:
			var mark := MDSCombatZone.marker(spot, Vector2(ctx.enemy.body_size.x, 16.0), marker_time / ctx.speed(), marker_color)
			ctx.spawn_parent().add_child(mark)
			mark.global_position = spot
			ctx.track(mark)

func _update(ctx: MDSMoveContext, _delta: float) -> Status:
	var m := mem(ctx)
	var t := elapsed(ctx)
	if not m[&"spawned"]:
		if t < marker_time:
			return Status.RUNNING
		m[&"spawned"] = true
		spawn_all(ctx, m[&"spots"])
		m[&"since"] = t
	if not wait_for_them or ctx.summons_alive() <= 0:
		return Status.DONE
	return Status.DONE if t - float(m[&"since"]) >= wait_seconds else Status.RUNNING

## Brings them all at [param spots], now.
func spawn_all(ctx: MDSMoveContext, spots: Array) -> void:
	for spot: Vector2 in spots:
		var e := _make()
		if not e:
			continue
		for key: Variant in properties:
			e.set(StringName(key), properties[key])
		if e.respawn != MDSEnemy.Respawn.NEVER:
			e.respawn = MDSEnemy.Respawn.ON_ROOM_LOAD
		e.name = "Summon%d" % ctx.rng.randi_range(1000, 9999)
		ctx.spawn_parent().add_child(e)
		e.global_position = spot
		e.home = spot
		ctx.track(e)
		if partner:
			e.set_meta(&"mds_stays", true)
			ctx.enemy.call(&"add_partner", e) if ctx.enemy.has_method(&"add_partner") else null

func _make() -> MDSEnemy:
	if scene:
		return scene.instantiate() as MDSEnemy
	if enemy_script:
		return enemy_script.new() as MDSEnemy
	return MDSFlyer.new()

## Spots for now, without a mark (the moment it dies).
func spots_now(ctx: MDSMoveContext) -> Array:
	var out := []
	for i in count:
		out.append(ctx.point(at, offset) + Vector2(ctx.rng.randf_range(-scatter, scatter), 0))
	return out

## A summon (for code).
static func of(p_script: Script, p_count := 1, p_at := MDSMove.Anchor.CEILING_ABOVE_PLAYER) -> MDSMoveSummon:
	var s := MDSMoveSummon.new()
	s.enemy_script = p_script
	s.count = p_count
	s.at = p_at
	return s
