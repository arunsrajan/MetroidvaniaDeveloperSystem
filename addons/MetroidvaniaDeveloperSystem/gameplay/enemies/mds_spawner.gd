@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_spawner.svg")
class_name MDSSpawner
extends Node2D
## Spawns waves of enemies (an arena's adds, a gauntlet): wave i brings [member waves][i] enemies,
## taken in turn from [member enemies] (scenes of [MDSEnemy]; empty: walkers), no more than
## [member max_alive] at once, within [member spread] px of it. The next wave starts when one is
## cleared. Spawned enemies come back whenever the room loads (ON_ROOM_LOAD): nothing is saved.
## It starts on its own ([member autostart]), when [member arena]'s fight starts, or by [method start].

signal wave_started(index: int)
signal wave_cleared(index: int)
signal finished

@export var enemies: Array[PackedScene] = []
@export var waves: PackedInt32Array = [3]
@export var max_alive := 3
@export var spread := 200.0
## Seconds between two spawns.
@export var interval := 0.6
@export var autostart := false
## Starts with this arena's fight.
@export var arena: MDSBossArena

var wave := -1
var running := false
var alive: Array[Node] = []
var _to_spawn := 0
var _wait := 0.0
var _count := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rng.seed = hash(name)
	if arena:
		arena.fight_started.connect(func(_b: Node) -> void: start())
	if autostart:
		start.call_deferred()

func start() -> void:
	if running:
		return
	running = true
	wave = -1
	_next_wave()

func _next_wave() -> void:
	wave += 1
	if wave >= waves.size():
		running = false
		finished.emit()
		return
	_to_spawn = waves[wave]
	_wait = 0.0
	wave_started.emit(wave)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not running:
		return
	alive = alive.filter(func(e: Node) -> bool: return is_instance_valid(e) and not (e is MDSEnemy and (e as MDSEnemy).dying))
	_wait -= delta
	if _to_spawn > 0 and alive.size() < max_alive and _wait <= 0.0:
		spawn_one()
		_to_spawn -= 1
		_wait = interval
	elif _to_spawn <= 0 and alive.is_empty():
		wave_cleared.emit(wave)
		_next_wave()

## Spawns one enemy now. Returns it.
func spawn_one() -> Node2D:
	var e: Node2D
	if enemies.is_empty():
		e = MDSWalker.new()
	else:
		var scene := enemies[_count % enemies.size()]
		e = scene.instantiate() as Node2D
	if not e:
		return null
	_count += 1
	if e is MDSEnemy:
		(e as MDSEnemy).respawn = MDSEnemy.Respawn.ON_ROOM_LOAD
	e.name = "%s_%d" % [name, _count]
	e.set_meta(&"mds_spawned", true)
	var parent := get_parent() if get_parent() else self
	parent.add_child(e)
	e.global_position = global_position + Vector2(_rng.randf_range(-spread, spread), 0)
	alive.append(e)
	return e
