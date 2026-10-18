extends "res://tests/test_case.gd"
## Gameplay Kit, phase 5: enemies. Respawn modes (NEVER stays dead through mark_defeated, ON_REST
## comes back after a rest on a bench, ON_ROOM_LOAD whenever the room loads, also after a save and
## a load), drops (currency and items, never persistent), the bestiary and the defeated signal,
## contact damage, and the five templates' behaviour: a walker turns at a wall, a flyer swoops at the
## player, a turret fires at it, a charger is stunned by a wall, an ambusher bursts out near it.

const Fixture := preload("res://tests/game_fixture.gd")

var game: MDSWorldGame
var kit: MDSGameplay
var player: MDSPlayer

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	Fixture.build()
	_add_enemies()
	game = _game()
	add_child(game)
	await game.room_loaded
	await physics_frames(5)
	await _respawn_modes()
	await _templates()
	game.queue_free()
	await get_tree().process_frame

func _game() -> MDSWorldGame:
	var g := Fixture.make_game()
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	g.add_child(kit)
	g.remove_child(g.player)
	g.player.free()
	player = load(MDSPlayer.SCENE).instantiate()
	g.add_child(player)
	g.player = player
	return g

func _data(id: String) -> MDSEnemyData:
	var d := MDSEnemyData.new()
	d.id = id
	d.stats = MDSCombatStats.make(3)
	d.currency_drop = Vector2i(7, 7)
	var key := MDSItemData.new()
	key.id = "bone"
	key.display_name = "Bone"
	key.category = MDSItemData.Category.COLLECTIBLE
	d.drops = MDSDropTable.new()
	d.drops.entries = [{"item": key, "chance": 1.0, "min": 1, "max": 1}]
	return d

## Garden_01 gets three walkers, one of each respawn mode, far from where the player starts.
func _add_enemies() -> void:
	var path := Fixture.DIR + "/garden_01.tscn"
	var root: Node = (load(path) as PackedScene).instantiate()
	var modes := {"Never": MDSEnemy.Respawn.NEVER, "Rest": MDSEnemy.Respawn.ON_REST, "Load": MDSEnemy.Respawn.ON_ROOM_LOAD}
	var x := 760.0
	for n: String in modes:
		var w := MDSWalker.new()
		w.name = n
		w.respawn = modes[n]
		w.data = _data("crawler")
		w.position = Vector2(x, 540)
		root.add_child(w)
		x += 120.0
	check(save_scene(root, path) == OK, "Garden_01 saved with three walkers")
	root.free()
	load_fresh(path)

func _enemy(n: String) -> MDSEnemy:
	var e := game.room_node.get_node_or_null(n) as MDSEnemy
	return e if e and not e.is_queued_for_deletion() and not e.dying else null

func _kill(e: MDSEnemy) -> void:
	var hit := MDSDamageInfo.make(99)
	hit.ignores_iframes = true
	e.health.apply_damage(hit)

func _go(room: String, gate: String) -> void:
	game.load_room(room, gate)
	await game.room_loaded
	await physics_frames(4)

func _respawn_modes() -> void:
	player.global_position = Vector2(200, 540)
	check(_enemy("Never") and _enemy("Rest") and _enemy("Load"), "the three walkers are there")
	var defeated: Array = []
	game.defeated.connect(func(id: String, _boss: String) -> void: defeated.append(id))
	for n in ["Never", "Rest", "Load"]:
		_kill(_enemy(n))
	await physics_frames(3)
	check(defeated == ["Garden_01/Never"], "only the NEVER one is recorded as defeated (%s)" % [defeated])
	check(int(kit.bestiary.get("crawler", 0)) == 3, "the bestiary counts the three")
	var coins := game.room_node.get_children().filter(func(n: Node) -> bool: return n is MDSCurrencyPickup)
	var bones := game.room_node.get_children().filter(func(n: Node) -> bool: return n is MDSPickup and not n is MDSCurrencyPickup and (n as MDSPickup).get_item_id() == "bone")
	var total := 0
	for c in coins:
		total += (c as MDSCurrencyPickup).amount
	check(total == 21 and bones.size() == 3, "they drop their currency (%d) and loot (%d)" % [total, bones.size()])
	check(bones.all(func(b: Node) -> bool: return not (b as MDSPickup).persistent and not b.has_meta(&"mds_grants")), "drops are not persistent")
	for c in coins:
		(c as MDSCurrencyPickup).collect()
	(bones[0] as MDSPickup).collect()
	check(kit.currency == 21 and kit.get_item_count("bone") == 1, "collected: currency and the bone")
	await physics_frames(int(0.8 * Engine.physics_ticks_per_second))
	await _go("Garden_02", "left1")
	await _go("Garden_01", "right1")
	check(_enemy("Never") == null, "NEVER stays dead when the room loads again")
	check(_enemy("Rest") == null, "ON_REST stays dead until a rest")
	check(_enemy("Load") != null, "ON_ROOM_LOAD is back")
	player.mds_bench_rest(null)
	player.mds_bench_leave(null)
	await _go("Garden_02", "left1")
	await _go("Garden_01", "right1")
	check(_enemy("Rest") != null and _enemy("Never") == null, "after a rest ON_REST is back; NEVER still isn't")
	var save := game.get_save_data()
	_kill(_enemy("Rest"))
	await physics_frames(2)
	var after_kill := game.get_save_data()
	game.set_save_data(after_kill)
	await game.room_loaded
	await physics_frames(3)
	check(_enemy("Rest") == null and _enemy("Never") == null and _enemy("Load") != null, "a save and a load keep NEVER and (until a rest) ON_REST gone")
	game.set_save_data(save)
	await game.room_loaded
	await physics_frames(3)
	check(_enemy("Rest") != null, "an older save has it back")
	check(_enemy("Rest").health.get_max() == 3, "its health comes from its data's stats")
	# Contact damage (away from the gate the save put the player in).
	player.global_position = Vector2(200, 540)
	player.health.heal_full()
	await physics_frames(int(1.0 * Engine.physics_ticks_per_second))
	var w := _enemy("Load")
	player.global_position = w.global_position
	await physics_frames(3)
	check(player.health.current == player.health.get_max() - 1, "touching a walker hurts the player")
	await physics_frames(60)

func _templates() -> void:
	# The knockback may have thrown the player through a gate: back to Garden_01.
	game.load_room("Garden_01", "", Vector2(150, 540))
	await game.room_loaded
	await physics_frames(3)
	player.health.invulnerable = true
	var room := game.room_node
	for n in room.get_children():
		if n is MDSEnemy:
			n.queue_free()
	# A walker against a wall turns.
	var wall := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(40, 300)
	cs.shape = r
	wall.add_child(cs)
	wall.position = Vector2(1100, 430)
	room.add_child(wall)
	var walker := MDSWalker.new()
	walker.facing = 1
	walker.position = Vector2(1000, 540)
	room.add_child(walker)
	await physics_frames(90)
	check(walker.facing == -1, "a walker turns at a wall")
	walker.queue_free()
	# A charger charges into the wall and is stunned.
	var charger := MDSCharger.new()
	charger.position = Vector2(900, 540)
	room.add_child(charger)
	await physics_frames(2)
	charger.facing = 1
	charger.machine.force(&"Charge")
	var stunned := false
	for i in 120:
		await get_tree().physics_frame
		stunned = stunned or charger.machine.is_in(&"Stunned")
	check(stunned, "a charger running into a wall is stunned")
	charger.queue_free()
	# A turret fires at the player in sight.
	var turret := MDSTurret.new()
	turret.position = Vector2(600, 500)
	room.add_child(turret)
	player.global_position = Vector2(400, 540)
	var shots := 0
	for i in 120:
		await get_tree().physics_frame
		shots = room.get_children().filter(func(n: Node) -> bool: return n is MDSProjectile).size()
		if shots > 0:
			break
	check(shots > 0 and turret.aim.x < 0.0, "a turret aims at the player and fires")
	turret.queue_free()
	# A flyer swoops at the player.
	var flyer := MDSFlyer.new()
	flyer.position = Vector2(500, 350)
	flyer.swoop_cooldown = 0.1
	room.add_child(flyer)
	var swooped := false
	for i in 90:
		await get_tree().physics_frame
		if flyer.machine.is_in(&"Swoop"):
			await physics_frames(2)
			swooped = (player.global_position - flyer.global_position).dot(flyer.velocity) > 0.0
			break
	check(swooped, "a flyer swoops toward the player")
	flyer.queue_free()
	# An ambusher waits hidden, then bursts out near the player.
	var amb := MDSAmbusher.new()
	amb.position = Vector2(800, 540)
	room.add_child(amb)
	await physics_frames(5)
	check(amb.machine.is_in(&"Hidden") and not amb.hurtbox.enabled, "an ambusher waits hidden, unhittable")
	player.global_position = Vector2(720, 540)
	var revealed := false
	for i in 30:
		await get_tree().physics_frame
		revealed = revealed or (amb.machine.is_in(&"Reveal") and amb.hurtbox.enabled)
	check(revealed, "and bursts out when the player comes near")
	amb.queue_free()
	player.health.invulnerable = false
	await physics_frames(2)
