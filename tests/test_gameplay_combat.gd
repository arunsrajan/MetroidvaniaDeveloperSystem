extends "res://tests/test_case.gd"
## Gameplay Kit, phase 4: the damage formula and resistances, invulnerability frames (0.8 s), teams
## that never hurt themselves, knockback, the player's attacks hitting an enemy and the pogo bounce,
## MDS's lava and steam vents hurting the player through mds_environment_hurt (unchanged), hazards
## (DAMAGE knocks back, RESPAWN puts the player back on safe ground or at a checkpoint), hit-stop
## and the room camera's shake (skipped with the Cut camera motion).

var level: Node2D
var player: MDSPlayer

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	_formula()
	level = Node2D.new()
	add_child(level)
	_block(Rect2(-2000, 500, 8000, 100))
	player = load(MDSPlayer.SCENE).instantiate()
	level.add_child(player)
	player.global_position = Vector2(0, 450)
	await physics_frames(40)
	await _iframes()
	await _teams()
	await _damage_numbers()
	await _attacks()
	await _environment()
	await _hazards()
	await _feel()
	_release_all()
	level.queue_free()
	await get_tree().process_frame

func _block(r: Rect2) -> void:
	var b := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	b.add_child(cs)
	level.add_child(b)

func _release_all() -> void:
	for a in MDSGameplaySetup.ACTIONS:
		Input.action_release(a)

func _formula() -> void:
	var s := MDSCombatStats.make(10, 1)
	s.resistances = {"fire": 0.5, "ice": 2.0}
	check(MDSHealth.compute(5, "fire", s) == 2, "fire 5 at half, minus 1 defense: round(2.5) - 1 = 2 (%d)" % MDSHealth.compute(5, "fire", s))
	check(MDSHealth.compute(4, "ice", s, 1.5) == 11, "ice 4 doubled, a 1.5 weak spot, minus 1: 12 - 1 = 11")
	check(MDSHealth.compute(1, "physical", MDSCombatStats.make(5, 3)) == 1, "a hit always does at least 1")
	check(MDSHealth.compute(3, "void", null) == 3, "no stats: the amount itself")

## A target: an MDSHealth, an MDSHurtbox of [param team] and knockback, as a body.
func _dummy(team: MDSHurtbox.Team, at: Vector2, hp := 10) -> CharacterBody2D:
	var d := CharacterBody2D.new()
	d.collision_layer = 0
	d.collision_mask = 0
	var h := MDSHealth.new()
	h.name = "Health"
	h.stats = MDSCombatStats.make(hp)
	h.iframe_time = 0.0
	d.add_child(h)
	var hb := MDSHurtbox.make(team, Vector2(40, 60))
	hb.name = "Hurtbox"
	d.add_child(hb)
	var kb := MDSKnockback.new()
	kb.name = "Knockback"
	d.add_child(kb)
	level.add_child(d)
	d.global_position = at
	return d

func _iframes() -> void:
	var h := player.health
	h.heal_full()
	check(h.get_max() == 5 and h.current == 5, "the player starts with 5 health")
	var hit := MDSDamageInfo.make(1)
	check(h.apply_damage(hit) == 1 and h.current == 4, "a hit lands")
	check(h.apply_damage(MDSDamageInfo.make(1)) == 0 and h.current == 4, "another right after doesn't: invulnerable")
	await physics_frames(int(0.7 * Engine.physics_ticks_per_second))
	check(h.apply_damage(MDSDamageInfo.make(1)) == 0, "still invulnerable after 0.7 s")
	await physics_frames(int(0.15 * Engine.physics_ticks_per_second))
	check(h.apply_damage(MDSDamageInfo.make(1)) == 1 and h.current == 3, "hit again after 0.8 s")
	var pit := MDSDamageInfo.make(1)
	pit.ignores_iframes = true
	check(h.apply_damage(pit) == 1, "a hit that ignores invulnerability lands anyway")
	h.heal_full()
	await physics_frames(60)

func _teams() -> void:
	var ally := _dummy(MDSHurtbox.Team.PLAYER, Vector2(300, 440))
	var foe := _dummy(MDSHurtbox.Team.ENEMY, Vector2(300, 440))
	var friendly := MDSHitbox.make(MDSHitbox.Team.PLAYER, Vector2(80, 80), MDSAttackData.make("slash", 2))
	level.add_child(friendly)
	friendly.global_position = Vector2(300, 440)
	await physics_frames(4)
	check(MDSHealth.of(ally).current == 10, "a PLAYER hitbox never hurts a PLAYER hurtbox")
	check(MDSHealth.of(foe).current == 8, "it hurts an ENEMY one (%d)" % MDSHealth.of(foe).current)
	friendly.queue_free()
	var claw := MDSHitbox.make(MDSHitbox.Team.ENEMY, Vector2(80, 80), MDSAttackData.make("claw", 3))
	level.add_child(claw)
	claw.global_position = Vector2(300, 440)
	await physics_frames(4)
	check(MDSHealth.of(foe).current == 8, "an ENEMY hitbox never hurts an ENEMY hurtbox")
	check(MDSHealth.of(ally).current == 7, "it hurts the PLAYER team (%d)" % MDSHealth.of(ally).current)
	claw.queue_free()
	# Knockback: pushed away from the source, less with resistance.
	var src := Node2D.new()
	level.add_child(src)
	src.global_position = Vector2(250, 440)
	var push := MDSDamageInfo.make(1, "physical", src)
	push.knockback = Vector2(300, -200)
	(foe.get_node("Knockback") as MDSKnockback).resistance = 0.5
	(foe.get_node("Hurtbox") as MDSHurtbox).receive(push)
	check(foe.velocity.is_equal_approx(Vector2(150, -100)), "knockback pushes away from the hitter, halved by resistance (%s)" % foe.velocity)
	ally.queue_free()
	foe.queue_free()
	src.queue_free()
	await physics_frames(2)

## Off by default; with feel/damage_numbers on, a hit floats its damage up from the body.
func _damage_numbers() -> void:
	var key := MDSGameplaySetup.PREFIX + "feel/damage_numbers"
	var before: Variant = ProjectSettings.get_setting(key, false)
	var foe := _dummy(MDSHurtbox.Team.ENEMY, Vector2(300, 440))
	await physics_frames(1)
	var count := func() -> int: return level.get_children().filter(func(c: Node) -> bool: return c is MDSDamageNumber).size()
	MDSHealth.of(foe).apply_damage(MDSDamageInfo.make(2))
	check(count.call() == 0, "no damage numbers by default")
	ProjectSettings.set_setting(key, true)
	MDSHealth.of(foe).apply_damage(MDSDamageInfo.make(3))
	var shown := level.get_children().filter(func(c: Node) -> bool: return c is MDSDamageNumber)
	check(shown.size() == 1 and (shown[0] as MDSDamageNumber).amount == 3, "with feel/damage_numbers a hit shows its damage")
	ProjectSettings.set_setting(key, before)
	await get_tree().create_timer(1.0).timeout
	check(count.call() == 0, "and the number fades away")
	foe.queue_free()
	await physics_frames(2)

func _attacks() -> void:
	var foe := _dummy(MDSHurtbox.Team.ENEMY, player.global_position + Vector2(44, 0), 6)
	player.facing = 1
	player.velocity = Vector2.ZERO
	await physics_frames(2)
	player.buffer.press("attack")
	await physics_frames(16)
	check(MDSHealth.of(foe).current == 5, "the player's slash hits the enemy in front (%d)" % MDSHealth.of(foe).current)
	foe.queue_free()
	await physics_frames(30)
	# Pogo: a down attack in the air on something below bounces the player up.
	var spike := _dummy(MDSHurtbox.Team.ENEMY, Vector2(600, 470), 50)
	player.global_position = Vector2(600, 360)
	player.velocity = Vector2(0, 50)
	player.machine.force(&"Fall")
	Input.action_press(&"move_down")
	player.buffer.press("attack")
	var bounced := false
	for i in 30:
		await get_tree().physics_frame
		if player.velocity.y < -300.0:
			bounced = true
			break
	Input.action_release(&"move_down")
	check(bounced and MDSHealth.of(spike).current < 50, "a down attack on it bounces the player up (pogo)")
	spike.queue_free()
	await physics_frames(60)
	# Pogo off real spikes: a hazard has nothing to hurt, but a down attack still bounces off it.
	player.health.heal_full()
	var spikes := MDSHazard.new()
	spikes.size = Vector2(120, 30)
	spikes.position = Vector2(2500, 485)
	level.add_child(spikes)
	await physics_frames(2)
	player.global_position = Vector2(2500, 395)
	player.velocity = Vector2(0, 50)
	player.machine.force(&"Fall")
	Input.action_press(&"move_down")
	player.buffer.press("attack")
	bounced = false
	for i in 30:
		await get_tree().physics_frame
		if player.velocity.y < -300.0:
			bounced = true
			break
	Input.action_release(&"move_down")
	check(bounced and player.health.current == player.health.get_max(), "a down attack on MDSHazard spikes bounces the player up unhurt (pogo)")
	spikes.queue_free()
	await physics_frames(60)

func _environment() -> void:
	player.health.heal_full()
	# Safe ground first.
	player.global_position = Vector2(-600, 450)
	await physics_frames(30)
	var safe := player.safe_position
	check(safe != Vector2.INF and safe.distance_to(player.global_position) < 2.0, "standing on terrain makes safe ground")
	var lava := MDSLava.new()
	lava.damage = 1.0
	lava.size = Vector2(300, 200)
	lava.position = Vector2(-1500, 300)
	level.add_child(lava)
	await physics_frames(2)
	player.global_position = lava.global_position + Vector2(150, 100)
	player.velocity = Vector2.ZERO
	await physics_frames(3)
	check(player.health.current == 4, "MDSLava hurts the player through mds_environment_hurt (%d)" % player.health.current)
	check(player.global_position.distance_to(safe) < 2.0, "and lava sends it back to safe ground")
	lava.queue_free()
	await physics_frames(70)
	var vent := MDSSteamVent.new()
	vent.cycle = MDSSteamVent.Cycle.CONSTANT
	vent.damage = 1.0
	vent.launch_speed = 0.0
	vent.position = Vector2(-300, 500)
	level.add_child(vent)
	player.global_position = Vector2(-300, 450)
	var before := player.health.current
	await physics_frames(10)
	check(player.health.current == before - 1, "an MDSSteamVent's jet scalds it (%d -> %d)" % [before, player.health.current])
	vent.queue_free()
	await physics_frames(60)

func _hazards() -> void:
	player.health.heal_full()
	player.global_position = Vector2(1000, 450)
	await physics_frames(30)
	var spikes := MDSHazard.new()
	spikes.size = Vector2(120, 30)
	spikes.position = Vector2(1300, 485)
	level.add_child(spikes)
	var flag := MDSCheckpoint.new()
	flag.position = Vector2(1150, 500)
	level.add_child(flag)
	await physics_frames(2)
	player.global_position = Vector2(1150, 450)
	await physics_frames(4)
	check(player.checkpoint_position.distance_to(flag.global_position + flag.respawn_offset) < 1.0, "touching the checkpoint marks it")
	player.global_position = Vector2(1300, 460)
	await physics_frames(4)
	check(player.health.current == 4 and player.global_position.distance_to(player.checkpoint_position) < 4.0, "RESPAWN spikes hurt and send the player to the checkpoint (%s)" % player.global_position)
	await physics_frames(70)
	spikes.mode = MDSHazard.Mode.DAMAGE
	spikes.hitbox.respawn = false
	player.global_position = Vector2(1300 - 70, 460)
	player.velocity = Vector2.ZERO
	await physics_frames(1)
	player.global_position = Vector2(1300 - 50, 460)
	await physics_frames(3)
	check(player.health.current == 3 and player.velocity.x < 0.0 and player.machine.is_in(&"Hurt"), "DAMAGE spikes hurt and knock back (%s, %s)" % [player.velocity, player.machine.get_state()])
	spikes.queue_free()
	flag.queue_free()
	await physics_frames(60)

func _feel() -> void:
	var kit := MDSGameplay.new()
	add_child(kit)
	kit.hitstop(80)
	check(is_equal_approx(Engine.time_scale, float(MDSGameplaySetup.setting("feel/hitstop_time_scale"))), "hit-stop slows time")
	await get_tree().create_timer(0.2, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "and gives it back")
	kit.hitstop(50)
	kit.queue_free()
	await get_tree().process_frame
	check(is_equal_approx(Engine.time_scale, 1.0), "a hit-stop cut short by the kit going away gives the time back too")
	var cam := Camera2D.new()
	level.add_child(cam)
	var rc := MDSRoomCamera.new()
	rc.camera = cam
	level.add_child(rc)
	rc.shake(10.0, 0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	check(rc.is_shaking() and cam.offset != Vector2.ZERO, "the room camera shakes")
	await get_tree().create_timer(0.4).timeout
	check(not rc.is_shaking() and cam.offset == Vector2.ZERO, "and settles back")
	rc.transition_style = MDSRoomCamera.Motion.CUT
	rc.shake(10.0, 0.3)
	check(not rc.is_shaking(), "with the Cut camera motion it doesn't shake")
	rc.queue_free()
	cam.queue_free()
