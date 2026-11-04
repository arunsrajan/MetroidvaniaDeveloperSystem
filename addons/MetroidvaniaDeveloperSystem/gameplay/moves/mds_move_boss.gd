@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_boss.svg")
class_name MDSMoveBoss
extends MDSBoss
## A boss that fights with moves ([MDSMove]) instead of [MDSBoss]'s built-in attacks. Its
## [member MDSBoss.phases] are [MDSMovePhase]s, set in the inspector. Or name a [member recipe], a
## whole fight from [MDSMoveRecipes]. Or inherit it and override [method _make_phases]:
## [codeblock]
## class_name Hopper
## extends MDSMoveBoss
##
## func _make_phases() -> Array[MDSBossPhase]:
##     var hop := MDSMoveLeap.of(MDSMove.Anchor.PLAYER, 300.0)
##     return [MDSMovePhase.of(1.0, MDSMoveSequence.of([hop, MDSMoveWait.of(0.5)]))]
## [/codeblock]
##
## A stagger or a phase change stops what it was doing and clears what it left in the room, except a
## partner ([method add_partner]). The fight goes on until its partners have fallen too.

signal move_cue(cue: StringName)

## A fight from [MDSMoveRecipes], used when [member MDSBoss.phases] is empty.
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "swooper,twin_swooper,showman,duelist,possessed_duelist,hanging_matriarch") var recipe := ""
## It drops to the ground when staggered, and flies again after.
@export var falls_when_staggered := false
## Runs the moment it dies (a [MDSMoveSummon] partner it hadn't called yet).
@export var on_death: MDSMoveSummon

var fight: MDSMoveState
var partners: Array[MDSEnemy] = []
var _flying := false

func _ready() -> void:
	if not Engine.is_editor_hint():
		_apply_recipe()
		if phases.is_empty():
			phases = _make_phases()
	super()

func _apply_recipe() -> void:
	if recipe.is_empty() or not phases.is_empty():
		return
	MDSMoveRecipes.setup(self, recipe)

## Its phases, when [member MDSBoss.phases] is empty. A subclass builds its fight here.
func _make_phases() -> Array[MDSBossPhase]:
	return [MDSMovePhase.of(1.0, MDSMoveWait.of(0.5))]

func _make_states() -> Array[Node]:
	fight = MDSMoveState.make(&"Idle")
	var dormant := Dormant.new()
	dormant.name = "Dormant"
	var stagger := MoveStagger.new()
	stagger.name = "Stagger"
	var dead := BossDead.new()
	dead.name = "Dead"
	return [dormant, fight, stagger, dead]

## The state machine is about to fight (it starts the phase, or goes on with it).
func start_fight() -> void:
	if fighting or dying:
		return
	_enter_phase()
	super()

func _enter_phase() -> void:
	var p := get_phase() as MDSMovePhase
	if not p or not fight:
		return
	fight.moves = p.moves
	fight.reactions = p.reactions
	fight._context().speed_scale = p.speed_multiplier
	fight.pending(p.opening)

func _on_health_changed(current: int, maximum: int) -> void:
	var was := phase_index
	super(current, maximum)
	if phase_index != was:
		_after_stagger_start()
		_enter_phase()

func _on_staggered() -> void:
	super()
	_after_stagger_start()

func _after_stagger_start() -> void:
	if fight:
		fight._context().clear_spawned()
	if falls_when_staggered and not uses_gravity:
		_flying = true
		uses_gravity = true

## It flies again, if it was made to drop.
func stagger_over() -> void:
	if _flying:
		_flying = false
		uses_gravity = false

## [param partner] fights too: the fight goes on until it falls as well.
func add_partner(partner: MDSEnemy) -> void:
	if partner in partners:
		return
	partners.append(partner)
	var a := arena as MDSBossArena
	if a:
		a.add_partner(partner)
	if partner is MDSBoss:
		var b := partner as MDSBoss
		b.arena = arena
		if b.boss_name.is_empty():
			b.boss_name = boss_name
			b._update_meta()
		b.start_fight()
	# Each falls knowing about the other: only the last one settles the fight for good.
	if partner is MDSMoveBoss:
		(partner as MDSMoveBoss).partners.append(self)

func _on_died() -> void:
	if dying:
		return
	if on_death and fight:
		var c := fight._context()
		if not _all_partners_called():
			on_death.spawn_all(c, on_death.spots_now(c))
	if fight:
		fight._context().clear_spawned()
	# A partner still fights: whoever falls last settles it, so a loss brings this one back too.
	if _has_partner_alive():
		respawn = Respawn.ON_ROOM_LOAD
	super()

func _all_partners_called() -> bool:
	return not partners.is_empty()

func _has_partner_alive() -> bool:
	for p in partners:
		if is_instance_valid(p) and not p.dying:
			return true
	return false

## It reels for a moment, then fights on.
class MoveStagger extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		if not enemy.uses_gravity:
			enemy.velocity.y = move_toward(enemy.velocity.y, 0.0, 1800.0 * delta)
		enemy.move()
		var b := enemy as MDSMoveBoss
		if elapsed() >= b.stagger_left:
			b.stagger_over()
			go(&"Idle")
