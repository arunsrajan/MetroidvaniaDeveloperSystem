@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player.svg")
class_name MDSPlayer
extends CharacterBody2D
## The Gameplay Kit's player: a CharacterBody2D with components (composition), in the
## [code]player[/code] group so [MDSGate], [MDSBench], [MDSWorldMapView], [MDSRoomCamera] and dark
## rooms' lights find it. [code]gameplay/player/mds_player.tscn[/code] is the ready-made one:
## [codeblock]
## Player (MDSPlayer)
##   CollisionShape2D, Visual, StateMachine (Idle, Run, Jump, Fall, Crouch, WallSlide, WallJump,
##   Dash, AirDash, Slide, LedgeGrab, LedgeClimb, Climb, Swim, Glide, Grapple, GroundPound,
##   Attack, Hurt, Dead, Rest, Locked), Health, Hurtbox, Knockback, Attacks, InputBuffer,
##   WallCheckL, WallCheckR, LedgeCheck, CeilingCheck, InteractArea
## [/codeblock]
## Missing parts are made when it starts, so a bare MDSPlayer works too.
##
## How it moves is [member movement] ([MDSMovementConfig]): run and air control, a jump that is cut
## short when released, coyote time, a jump buffer, lighter gravity at the apex, corner correction,
## slopes, moving platforms, dropping through one-way platforms (down + jump). Each movement
## ability is a state that can only be entered while the player has it ([method has_ability]).
##
## With [MDSWorldGame] it keeps its velocity through gates (the game restores it on arrival), and
## while the game changes rooms it is Locked (no input, no gravity, velocity untouched). On a bench
## it sits ([method mds_bench_rest]) and is healed ([method heal_full]). Hits from MDS's environment
## effects reach its [MDSHealth] ([method mds_environment_hurt], [method take_damage]).

signal landed
signal jumped
signal died
## Back on safe ground after a hazard (spikes, a pit, lava).
signal respawned
signal state_changed(from: StringName, to: StringName)

const SCENE := "res://addons/MetroidvaniaDeveloperSystem/gameplay/player/mds_player.tscn"
const STATE_DIR := "res://addons/MetroidvaniaDeveloperSystem/gameplay/player/states/"
## The states the ready-made player has, in order.
const STATE_NAMES: PackedStringArray = ["Idle", "Run", "Jump", "Fall", "Crouch", "WallSlide", "WallJump", "Dash", "AirDash", "Slide", "LedgeGrab", "LedgeClimb", "Climb", "Swim", "Glide", "Grapple", "GroundPound", "Attack", "Hurt", "Dead", "Rest", "Locked"]

## How the player moves. Empty: the defaults.
@export var movement: MDSMovementConfig
## Health, mana and defense (its [MDSHealth] uses them). Empty: the game's ([MDSGameplay]), else
## 5 health.
@export var stats: MDSCombatStats
## The size of the body standing (its collision rectangle; the origin is its middle).
@export var body_size := Vector2(28, 60)
@export var input_enabled := true
## Abilities the player has when there is no [MDSWorldGame] (a room scene played on its own).
@export var abilities_without_game: PackedStringArray = []
## Seconds standing on terrain before the spot counts as safe ground (where hazards send it back).
@export var safe_ground_time := 0.2

## The movement in effect: [member movement] with equipment and buffs added.
var config: MDSMovementConfig
var machine: MDSStateMachine
var health: MDSHealth
var buffer: MDSInputBuffer
var hurtbox: Node
var knockback: Node
var attacks: Node
var visual: Node
var interact_area: Area2D
var wall_check_left: RayCast2D
var wall_check_right: RayCast2D
var ledge_check: RayCast2D
var ceiling_check: RayCast2D
## 1 facing right, -1 left.
var facing := 1
var air_jumps_left := 0
var air_dashes_left := 0
var dash_cooldown_left := 0.0
## Time left to jump after walking off a ledge.
var coyote_left := 0.0
## Time left before steering works again (after a wall jump).
var steer_lock_left := 0.0
## Where hazards send the player back to: the last safe ground ([member safe_ground_time]).
var safe_position := Vector2.INF
## A checkpoint touched in this room ([MDSCheckpoint]): hazards send the player there instead.
var checkpoint_position := Vector2.INF
## Water and climbables the player is in (swim zones, ladders and vines).
var water_zones: Array[Node] = []
var climbables: Array[Node] = []
## Hazards touched now (no safe ground while in one).
var hazards_touching := 0
var game: MDSWorldGame
var gameplay: MDSGameplay

var _shape: CollisionShape2D
var _rect: RectangleShape2D
var _height := 1.0
var _safe_timer := 0.0
var _exceptions: Dictionary = {} ## one-way platform -> seconds left of dropping through it
var _buffs: Array = [] ## {stat, amount, left}

func _init() -> void:
	add_to_group(&"player")

func _ready() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	_build_missing()
	collision_layer = MDSGameplaySetup.bit("player")
	collision_mask = MDSGameplaySetup.bit("world")
	machine.self_driven = false
	if not machine.state_changed.is_connected(_on_state_changed):
		machine.state_changed.connect(_on_state_changed)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	_refresh_config()
	_bind_game()

## The ready-made player ([constant SCENE]), or one built in code when the scene isn't there.
static func instantiate_default() -> MDSPlayer:
	if ResourceLoader.exists(SCENE):
		var p := (load(SCENE) as PackedScene).instantiate() as MDSPlayer
		if p:
			return p
	return build()

## A player with every part, built in code ([member owner] of the parts: [param scene_owner], for
## saving it as a scene).
static func build(scene_owner: Node = null) -> MDSPlayer:
	var p := MDSPlayer.new()
	p.name = "Player"
	p._build_missing(scene_owner)
	return p

## Makes the parts the player lacks (see the class description).
func _build_missing(scene_owner: Node = null) -> void:
	var own := scene_owner if scene_owner else null
	_shape = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if not _shape:
		_shape = CollisionShape2D.new()
		_shape.name = "CollisionShape2D"
		_add(_shape, own)
	_rect = _shape.shape as RectangleShape2D
	if not _rect:
		_rect = RectangleShape2D.new()
		_rect.size = body_size
		_shape.shape = _rect
	elif not own:
		# Its own copy: crouching and sliding change its height.
		_rect = _rect.duplicate()
		_shape.shape = _rect
	visual = get_node_or_null(^"Visual")
	if not visual:
		visual = MDSPlayerVisual.new()
		visual.name = "Visual"
		_add(visual, own)
	machine = get_node_or_null(^"StateMachine") as MDSStateMachine
	if not machine:
		machine = MDSStateMachine.new()
		machine.name = "StateMachine"
		machine.initial_state = &"Fall"
		_add(machine, own)
	for n in STATE_NAMES:
		if not machine.has_node(NodePath(n)):
			var path := STATE_DIR + "mds_player_%s_state.gd" % n.to_snake_case()
			if not ResourceLoader.exists(path):
				continue
			var s: Node = (load(path) as Script).new()
			s.name = n
			machine.add_child(s)
			if own:
				s.owner = own
	health = get_node_or_null(^"Health") as MDSHealth
	if not health:
		health = MDSHealth.new()
		health.name = "Health"
		_add(health, own)
	buffer = get_node_or_null(^"InputBuffer") as MDSInputBuffer
	if not buffer:
		buffer = MDSInputBuffer.new()
		buffer.name = "InputBuffer"
		_add(buffer, own)
	hurtbox = get_node_or_null(^"Hurtbox")
	if not hurtbox and ResourceLoader.exists("res://addons/MetroidvaniaDeveloperSystem/gameplay/combat/mds_hurtbox.gd"):
		hurtbox = MDSHurtbox.make(MDSHurtbox.Team.PLAYER, body_size * Vector2(0.8, 0.9))
		hurtbox.name = "Hurtbox"
		_add(hurtbox, own)
	knockback = get_node_or_null(^"Knockback")
	if not knockback:
		knockback = MDSKnockback.new()
		knockback.name = "Knockback"
		_add(knockback, own)
	attacks = get_node_or_null(^"Attacks")
	if not attacks:
		attacks = MDSAttackController.new()
		attacks.name = "Attacks"
		_add(attacks, own)
	wall_check_left = _ray("WallCheckL", Vector2(0, 4), Vector2(-body_size.x * 0.5 - 6, 0), own)
	wall_check_right = _ray("WallCheckR", Vector2(0, 4), Vector2(body_size.x * 0.5 + 6, 0), own)
	ledge_check = _ray("LedgeCheck", Vector2(0, -body_size.y * 0.5 - 6), Vector2(body_size.x * 0.5 + 10, 0), own)
	ceiling_check = _ray("CeilingCheck", Vector2.ZERO, Vector2(0, -body_size.y * 0.5 - 30), own)
	interact_area = get_node_or_null(^"InteractArea") as Area2D
	if not interact_area:
		interact_area = Area2D.new()
		interact_area.name = "InteractArea"
		interact_area.monitorable = true
		var cs := CollisionShape2D.new()
		cs.name = "Shape"
		var r := RectangleShape2D.new()
		r.size = body_size + Vector2(16, 8)
		cs.shape = r
		interact_area.add_child(cs)
		_add(interact_area, own)
		if own:
			cs.owner = own
	interact_area.collision_layer = MDSGameplaySetup.bit("interact")
	interact_area.collision_mask = MDSGameplaySetup.bit("interact")

func _add(n: Node, own: Node) -> void:
	add_child(n)
	if own:
		n.owner = own

func _ray(n: String, from: Vector2, to: Vector2, own: Node) -> RayCast2D:
	var r := get_node_or_null(NodePath(n)) as RayCast2D
	if not r:
		r = RayCast2D.new()
		r.name = n
		r.position = from
		r.target_position = to
		_add(r, own)
	r.collision_mask = MDSGameplaySetup.bit("world")
	return r

## The game and the kit, once they are there; the kit's health and equipment come in.
func _bind_game() -> void:
	game = MDSWorldGame.instance if MDSWorldGame.instance and MDSWorldGame.instance.is_ancestor_of(self) else null
	if not game:
		var n := get_parent()
		while n and not n is MDSWorldGame:
			n = n.get_parent()
		game = n as MDSWorldGame
	gameplay = MDSGameplay.find(game) if game else null
	if game and not game.room_loaded.is_connected(_on_room_loaded):
		game.room_loaded.connect(_on_room_loaded)
	if gameplay:
		if not stats:
			stats = gameplay.get_stats()
		if not gameplay.equipment_changed.is_connected(_refresh_config):
			gameplay.equipment_changed.connect(_refresh_config)
		health.health_changed.connect(func(c: int, _m: int) -> void: gameplay.set_health(c))
	_apply_stats()
	if gameplay:
		health.set_max(gameplay.player_max_health(), false)
		health.set_current(gameplay.health)

# --- Every frame ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick(delta)
	buffer.record(delta, can_take_input())
	if game and game.changing_room and machine.has_state(&"Locked") and not machine.is_in(&"Locked") and not machine.is_in(&"Dead"):
		machine.force(&"Locked")
	machine.physics_step(delta)
	# Standing up again after a crouch or a slide, once there is room.
	if _height < 1.0 and not machine.is_in(&"Crouch") and not machine.is_in(&"Slide") and can_stand():
		set_body_height(1.0)
	_track_safe_ground(delta)
	_update_visual()

func _tick(delta: float) -> void:
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	coyote_left = maxf(0.0, coyote_left - delta)
	steer_lock_left = maxf(0.0, steer_lock_left - delta)
	for b: Object in _exceptions.keys():
		_exceptions[b] = float(_exceptions[b]) - delta
		if _exceptions[b] <= 0.0 or not is_instance_valid(b):
			if is_instance_valid(b):
				remove_collision_exception_with(b)
			_exceptions.erase(b)
	if not _buffs.is_empty():
		var expired := false
		for b in _buffs:
			b.left -= delta
			expired = expired or b.left <= 0.0
		if expired:
			_buffs = _buffs.filter(func(b: Dictionary) -> bool: return b.left > 0.0)
			_refresh_config()

# --- Input ---------------------------------------------------------------------------------------

## Whether the player listens to its controls now (not locked, resting, dead or paused).
func can_take_input() -> bool:
	if not input_enabled or not is_inside_tree() or get_tree().paused:
		return false
	return not (machine.is_in(&"Locked") or machine.is_in(&"Rest") or machine.is_in(&"Dead"))

## Left / right input, -1 to 1.
func input_x() -> float:
	return Input.get_axis(&"move_left", &"move_right") if can_take_input() else 0.0

## Up / down input, -1 (up) to 1 (down).
func input_y() -> float:
	return Input.get_axis(&"move_up", &"move_down") if can_take_input() else 0.0

## Whether [param action] is held.
func held(action: StringName) -> bool:
	return can_take_input() and InputMap.has_action(action) and Input.is_action_pressed(action)

## Whether [param action] was pressed in the last [param window] s and not used yet.
func pressed(action: String, window := -1.0) -> bool:
	return buffer.has(action, window)

# --- Abilities -------------------------------------------------------------------------------------

## Whether the player has [param ability]: granted ([method MDSWorldGame.has_ability]) or lent by
## equipment worn; without a game, [member abilities_without_game].
func has_ability(ability: String) -> bool:
	if ability.is_empty():
		return true
	if game:
		return game.has_ability(ability) or (gameplay != null and gameplay.has_equipped_ability(ability))
	return abilities_without_game.has(ability)

# --- Movement helpers ---------------------------------------------------------------------------

## Runs toward the input (ground or air acceleration), facing it.
func steer(delta: float) -> void:
	var x := input_x()
	if absf(x) > 0.01 and steer_lock_left <= 0.0:
		facing = 1 if x > 0.0 else -1
	if steer_lock_left > 0.0:
		return
	var target := x * config.max_run_speed
	if in_water() and not has_ability("swim"):
		target *= 0.6
	var ground := is_on_floor()
	var accel := (config.ground_accel if ground else config.air_accel) if absf(x) > 0.01 else (config.ground_decel if ground else config.air_decel)
	velocity.x = move_toward(velocity.x, target, accel * delta)

## Gravity: heavier falling, lighter at the apex while jump is held.
func apply_gravity(delta: float, multiplier := 1.0) -> void:
	var g := config.gravity * multiplier
	if in_water() and not has_ability("swim"):
		# Without swim, water only slows the fall: the player sinks.
		velocity.y = minf(velocity.y + config.swim_gravity * multiplier * delta, config.swim_speed)
		return
	if velocity.y > 0.0:
		g *= config.fall_gravity_multiplier
	elif absf(velocity.y) < config.apex_threshold and held(&"jump"):
		g *= config.apex_gravity_multiplier
	velocity.y = minf(velocity.y + g * delta, config.max_fall_speed)

## Moves (move_and_slide), first sliding past a ceiling corner it would bump into.
func move() -> void:
	_correct_corner(get_physics_process_delta_time())
	move_and_slide()
	if is_on_ceiling() and velocity.y < 0.0:
		velocity.y = 0.0

func _correct_corner(delta: float) -> void:
	if velocity.y >= 0.0 or config.corner_correction_px <= 0.0:
		return
	var motion := Vector2(0, velocity.y * delta)
	if not test_move(global_transform, motion):
		return
	for k in range(1, int(config.corner_correction_px) + 1):
		for dir: int in [1, -1] if velocity.x >= 0.0 else [-1, 1]:
			var side := Vector2(dir * k, 0)
			if not test_move(global_transform, side) and not test_move(global_transform.translated(side), motion):
				global_position.x += dir * k
				return

## A jump up at [param speed] (0: the configured jump).
func jump(speed := 0.0) -> void:
	velocity.y = -(speed if speed > 0.0 else config.jump_velocity)
	coyote_left = 0.0
	buffer.consume("jump")
	jumped.emit()

## Whether a jump from the ground (or coyote time) can happen now.
func can_ground_jump() -> bool:
	return is_on_floor() or coyote_left > 0.0

## Back on the ground: air jumps and air dashes are back.
func on_landed() -> void:
	air_jumps_left = config.max_air_jumps if has_ability("double_jump") else 0
	air_dashes_left = config.air_dashes
	landed.emit()

## States of the machine whose trigger includes [param where], highest priority first.
func _moves(where: int) -> Array[MDSPlayerState]:
	var out: Array[MDSPlayerState] = []
	for s in machine.states.values():
		if s is MDSPlayerState and ((s as MDSPlayerState).trigger == where or (s as MDSPlayerState).trigger == MDSPlayerState.Trigger.ANY):
			out.append(s)
	out.sort_custom(func(a: MDSPlayerState, b: MDSPlayerState) -> bool: return a.priority > b.priority)
	return out

## Tries the moves that start from the ground (dash, jump, crouch...). Returns whether one did.
func try_ground_moves() -> bool:
	if try_drop_through():
		return true
	for s in _moves(MDSPlayerState.Trigger.GROUND):
		if s != machine.current and machine.transition_to(StringName(s.name)):
			return true
	return false

## Tries the moves that start in the air (air dash, wall slide, glide, a double jump...).
func try_air_moves() -> bool:
	for s in _moves(MDSPlayerState.Trigger.AIR):
		if s != machine.current and machine.transition_to(StringName(s.name)):
			return true
	return false

## Down + jump on a one-way platform: falls through it. Returns whether it did.
func try_drop_through() -> bool:
	if not is_on_floor() or input_y() < 0.5 or not pressed("jump"):
		return false
	var dropped := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y > -0.6 or not c.get_collider() is CollisionObject2D:
			continue
		var body := c.get_collider() as CollisionObject2D
		var owner_id := body.shape_find_owner(c.get_collider_shape_index())
		var shape_owner := body.shape_owner_get_owner(owner_id)
		if ("one_way_collision" in shape_owner) and shape_owner.get("one_way_collision"):
			add_collision_exception_with(body)
			_exceptions[body] = 0.3
			dropped = true
	if dropped:
		buffer.consume("jump")
		global_position.y += 2.0
		velocity.y = maxf(velocity.y, 60.0)
		machine.transition_to(&"Fall")
	return dropped

## Whether the player touches a wall on side [param dir] (-1 left, 1 right).
func touching_wall(dir: int) -> bool:
	var r := wall_check_left if dir < 0 else wall_check_right
	r.force_raycast_update()
	return r.is_colliding() or (is_on_wall() and signf(get_wall_normal().x) == -dir)

## Which side a wall is touched on (-1, 1; 0 none).
func wall_side() -> int:
	if touching_wall(-1):
		return -1
	if touching_wall(1):
		return 1
	return 0

## The body's height as a share of standing (crouch and slide halve it), keeping the feet where
## they are.
func set_body_height(share: float) -> void:
	share = clampf(share, 0.2, 1.0)
	if is_equal_approx(share, _height) or not _rect:
		return
	_height = share
	_rect.size = Vector2(body_size.x, body_size.y * share)
	_shape.position = Vector2(0, body_size.y * (1.0 - share) * 0.5)

func get_body_height() -> float:
	return _height

## Whether there is room to stand up (from a crouch or a slide).
func can_stand() -> bool:
	if _height >= 1.0:
		return true
	return not test_move(global_transform, Vector2(0, -body_size.y * (1.0 - _height) - 1.0))

## Half the body standing (px, global), for [MDSWorldGame] to place it beside holes.
func get_spawn_extent() -> Vector2:
	return body_size * 0.5 * global_scale.abs()

## Whether the player is in water (a swim zone).
func in_water() -> bool:
	water_zones = water_zones.filter(func(z: Node) -> bool: return is_instance_valid(z) and z.is_inside_tree())
	return not water_zones.is_empty()

## The climbable (ladder, vine) the player overlaps, or null.
func get_climbable() -> Node:
	climbables = climbables.filter(func(z: Node) -> bool: return is_instance_valid(z) and z.is_inside_tree())
	return climbables[0] if not climbables.is_empty() else null

# --- Config, stats and buffs --------------------------------------------------------------------

## The movement in effect is rebuilt: [member movement] plus equipment and buffs.
func _refresh_config() -> void:
	if not movement:
		movement = MDSMovementConfig.new()
	config = movement.duplicate()
	var mods := _all_mods()
	for k in mods:
		if k in config and typeof(config.get(k)) in [TYPE_FLOAT, TYPE_INT]:
			config.set(k, config.get(k) + mods[k])
	floor_max_angle = deg_to_rad(config.max_floor_angle)
	floor_snap_length = config.floor_snap_length
	if is_inside_tree():
		_apply_stats()

## Stat -> amount from equipment worn and buffs.
func _all_mods() -> Dictionary:
	var out: Dictionary = gameplay.equipment_mods() if gameplay else {}
	for b in _buffs:
		out[b.stat] = out.get(b.stat, 0.0) + float(b.amount)
	return out

## Health's stats: the base ones with equipment (defense, max_health) added.
func _apply_stats() -> void:
	if not health:
		return
	var base := stats if stats else (gameplay.get_stats() if gameplay else MDSCombatStats.make(5))
	var s := base.duplicate() as MDSCombatStats
	var mods := _all_mods()
	s.defense += int(mods.get("defense", 0))
	health.stats = s
	var m := gameplay.player_max_health() if gameplay else s.max_health
	if m != health.get_max():
		health.set_max(m, not gameplay)

## For [param duration] s, adds [param amount] to [param stat] (damage, defense, a movement field).
func add_buff(stat: String, amount: float, duration: float) -> void:
	_buffs.append({"stat": stat, "amount": amount, "left": duration})
	_refresh_config()

## Extra damage of attacks: equipment, buffs and levels.
func get_damage_bonus() -> int:
	var bonus := float(_all_mods().get("damage", 0.0))
	if gameplay:
		bonus += gameplay.level_damage_bonus()
	return int(bonus)

# --- Safe ground, hazards, checkpoints -------------------------------------------------------------

func _track_safe_ground(delta: float) -> void:
	if not is_on_floor() or hazards_touching > 0 or not machine.current or machine.is_in(&"Locked"):
		_safe_timer = 0.0
		return
	var on_terrain := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if c.get_normal().y < -0.6 and col is CollisionObject2D and ((col as CollisionObject2D).collision_layer & MDSGameplaySetup.bit("world")) and not col is AnimatableBody2D:
			on_terrain = true
	if not on_terrain:
		_safe_timer = 0.0
		return
	_safe_timer += delta
	if _safe_timer >= safe_ground_time:
		safe_position = global_position

## Back to the checkpoint touched in this room, else the last safe ground (after a hazard).
func respawn_to_safe_ground() -> void:
	var at := checkpoint_position if checkpoint_position != Vector2.INF else safe_position
	if at == Vector2.INF:
		return
	global_position = at
	velocity = Vector2.ZERO
	health.grant_iframes(maxf(health.iframe_time, 1.0))
	if machine.has_state(&"Fall"):
		machine.force(&"Fall")
	respawned.emit()

## A checkpoint ([MDSCheckpoint]) touched: hazards send the player there in this room.
func set_checkpoint(at: Vector2) -> void:
	checkpoint_position = at

func _on_room_loaded(_room: String) -> void:
	checkpoint_position = Vector2.INF
	safe_position = global_position
	hazards_touching = 0
	water_zones.clear()
	climbables.clear()

# --- Health ---------------------------------------------------------------------------------------

func get_health_component() -> MDSHealth:
	return health

## Restores health (a bench calls it).
func heal_full() -> void:
	health.heal_full()

func take_damage(amount: float) -> int:
	return health.take_damage(amount)

## Hurt by an MDS environment effect (lava, steam vents, rockfall...).
func mds_environment_hurt(amount: float, effect: Node) -> int:
	return health.mds_environment_hurt(amount, effect)

func _on_damaged(info: MDSDamageInfo) -> void:
	if health.is_dead():
		return
	if gameplay:
		gameplay.hitstop(info.hitstop_ms if info.hitstop_ms > 0 else 40)
	if game and game.room_camera and game.room_camera.has_method(&"shake"):
		game.room_camera.call(&"shake", 6.0, 0.25)
	if bool(MDSGameplaySetup.setting("feel/rumble")):
		Input.start_joy_vibration(0, 0.3, 0.6, 0.2)
	if info.respawn:
		respawn_to_safe_ground()
		return
	if machine.has_state(&"Hurt"):
		machine.force(&"Hurt", {"info": info})

func _on_died() -> void:
	if machine.has_state(&"Dead"):
		machine.force(&"Dead")
	died.emit()
	if gameplay:
		gameplay.on_player_died(self)

## Back up after dying (the game moved it to the bench).
func revive() -> void:
	health.revive()
	velocity = Vector2.ZERO
	if machine.has_state(&"Fall"):
		machine.force(&"Fall")

# --- Benches -----------------------------------------------------------------------------------

## Sits down on [param bench] ([MDSBench] calls it): the Rest state; mana fills, enemies that come
## back after a rest come back.
func mds_bench_rest(bench: Node) -> void:
	velocity = Vector2.ZERO
	if machine.has_state(&"Rest"):
		machine.force(&"Rest", {"bench": bench})
	if gameplay:
		gameplay.on_rested()

## Gets up from [param bench].
func mds_bench_leave(_bench: Node) -> void:
	if machine.is_in(&"Rest"):
		machine.force(&"Idle")

# --- Look ----------------------------------------------------------------------------------------

func _on_state_changed(from: StringName, to: StringName) -> void:
	var s := machine.current as MDSPlayerState
	if visual is AnimatedSprite2D and s:
		var frames := (visual as AnimatedSprite2D).sprite_frames
		if frames and frames.has_animation(s.get_animation()):
			(visual as AnimatedSprite2D).play(s.get_animation())
	elif visual and visual.has_method(&"play") and not visual is AnimatedSprite2D and s:
		visual.call(&"play", s.get_animation())
	state_changed.emit(from, to)

func _update_visual() -> void:
	if not visual:
		return
	if visual is AnimatedSprite2D:
		(visual as AnimatedSprite2D).flip_h = facing < 0
	elif visual.has_method(&"set_pose"):
		visual.call(&"set_pose", machine.get_state(), facing, velocity, _height)
