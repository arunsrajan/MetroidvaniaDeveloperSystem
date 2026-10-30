extends "res://tests/test_case.gd"
## The combat effects demo (examples/combat_fx_demo, built by build_combat_fx_demo.gd), played: its
## enemies are set up with their own hits and hurts, the player's colors are set by its
## CombatColors node, and in the game the player's blow throws the enemy's particles off it in
## their palette, and the enemy's touch throws the player's heart shards off it, with the enemy's
## element's effect.

const DEMO := "res://examples/combat_fx_demo"

var game: MDSWorldGame

func _run() -> void:
	var world := MDSWorld.get_cached(DEMO + "/combat_fx_demo.mdsworld.json")
	check(world.get_room_ids().size() == 2, "two rooms")
	game = (load(DEMO + "/game.tscn") as PackedScene).instantiate() as MDSWorldGame
	game.load_on_start = false
	game.save_file = ""
	game.exploration_file = ""
	add_child(game)
	for i in 600:
		if game.current_room == "Prism_Arena" and not game.changing_room:
			break
		await get_tree().physics_frame
	await _frames(5)
	check(game.current_room == "Prism_Arena", "starts in the Prism Arena")
	var player := game.player as MDSPlayer
	var crawler := game.room_node.find_child("Ember_Crawler", true, false) as MDSEnemy
	var golem := game.room_node.find_child("Crystal_Golem", true, false) as MDSEnemy
	check(crawler and crawler.hurtbox.hurt_particles == "embers" and crawler.contact.attack.damage_type == "fire" and crawler.contact.attack.fx_glow == Color("#ff6a1a"), "the Ember Crawler: fire, its colors, embers when hurt")
	check(golem and golem.hurtbox.particle_palette.size() == 3 and is_equal_approx(golem.hurtbox.particle_glow, 2.0) and is_equal_approx(golem.hurtbox.particle_size, 1.6), "the Crystal Golem: a palette of three, glowing strongly, big shards")
	var hurt := player.find_children("*", "MDSHurtbox", true, false)[0] as MDSHurtbox
	var attacks := player.find_children("*", "MDSAttackController", true, false)[0] as MDSAttackController
	check(MDSAttackFX.effect_colors.get("player", []) == [Color("#fff4c2"), Color("#ffb020")] and hurt.hurt_particles == "heart_shards" and is_equal_approx(hurt.particle_size, 1.3) and attacks.ground_combo[0].particle_palette.size() == 3, "the player's colors set by CombatColors")
	# The player hits the crawler.
	crawler.set_physics_process(false)
	player.global_position = crawler.global_position + Vector2(-56, -10)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await _frames(6)
	Input.action_press(&"attack")
	await _frames(2)
	Input.action_release(&"attack")
	var embers: MDSHitParticles = null
	var swing: MDSAttackFX = null
	for i in 40:
		await _frames(1)
		for n in crawler.get_parent().get_children():
			if n is MDSHitParticles and (n as MDSHitParticles).particles == "embers":
				embers = n
		for n in player.get_children():
			if n is MDSAttackFX:
				swing = n
		if embers:
			break
	check(swing != null and swing.get_material_fx().get_shader_parameter("glow_color") == Color("#ffb020") and is_equal_approx(float(swing.get_material_fx().get_shader_parameter("intensity")), 1.4), "the player's swing: its arc in gold, glowing as set")
	check(embers != null and embers.color_initial_ramp and embers.color_initial_ramp.get_point_count() == 4 and embers.material is CanvasItemMaterial, "the blow lands: embers fly off the crawler in their palette, glowing")
	# The crawler hurts the player.
	await _frames(30)
	crawler.set_physics_process(true)
	player.global_position = crawler.global_position
	var shards: MDSHitParticles = null
	var fire := false
	for i in 90:
		await _frames(1)
		# The player's are beside it, in the game (its parent).
		for n in game.find_children("*", "", true, false):
			if n is MDSHitParticles and (n as MDSHitParticles).particles == "heart_shards":
				shards = n
			if n is MDSAttackFX and (n as MDSAttackFX).effect == "fire_burst":
				fire = true
		if shards:
			break
	check(shards != null and shards.color_initial_ramp and shards.color_initial_ramp.get_point_count() == 3 and shards.team == MDSAttackFX.Team.PLAYER, "touched, the player loses heart shards in its own palette")
	check(fire, "and the crawler's fire bursts where it struck")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not MDSAttackFX.effect_colors.has("player"), "the player's colors gone with the game")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
