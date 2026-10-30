extends "res://tests/test_case.gd"
## Attack effects (MDSAttackFX): the thirty shaders, played once and gone, facing the attack, in
## the player's or the enemy's colors (an element in its own), picked by themselves for swings
## and hits (by the attack, its direction, its damage type), and what a hit does to the body hit;
## the feel setting turns them off.

const SETTING := "metroidvania_developer_system/gameplay/feel/attack_fx"

var level: Node2D

func _run() -> void:
	level = Node2D.new()
	add_child(level)
	_catalog()
	await _play()
	_colors()
	_choices()
	await _hits()
	_swings()
	level.queue_free()
	await get_tree().process_frame

func _catalog() -> void:
	check(MDSAttackFX.EFFECTS.size() == 30, "thirty effects (%d)" % MDSAttackFX.EFFECTS.size())
	var bad: Array = []
	var kinds := {}
	for id: String in MDSAttackFX.EFFECTS:
		var e: Array = MDSAttackFX.EFFECTS[id]
		kinds[e[0]] = int(kinds.get(e[0], 0)) + 1
		var path := MDSAttackFX.SHADER_DIR + id + ".gdshader"
		var sh := load(path) as Shader if ResourceLoader.exists(path) else null
		if not sh or not sh.code.contains("attack_fx.gdshaderinc") or not sh.code.contains("void fragment()") or not (e[1] is Vector2) or float(e[2]) <= 0.0:
			bad.append(id)
	check(bad.is_empty(), "each has its shader, played over the shared include (%s)" % [bad])
	check(int(kinds.get("swing", 0)) == 10 and int(kinds.get("impact", 0)) == 17 and int(kinds.get("body", 0)) == 3, "ten swings, seventeen impacts, three on the body (%s)" % [kinds])
	var inc := FileAccess.get_file_as_string(MDSAttackFX.SHADER_DIR + "attack_fx.gdshaderinc")
	check(inc.contains("uniform float progress") and inc.contains("uniform vec4 core_color") and inc.contains("uniform vec4 glow_color"), "they play by progress, in two colors")

func _play() -> void:
	var fx := MDSAttackFX.play("slash_arc", level, Vector2(300, 200), -1.0)
	check(fx != null and fx.get_parent() == level and fx.global_position == Vector2(300, 200) and fx.scale.x < 0.0, "played where asked, facing left")
	var quad := fx.get_node(^"Quad") as Polygon2D
	check(quad and quad.material == fx.get_material_fx() and (fx.get_material_fx().shader as Shader).resource_path.ends_with("slash_arc.gdshader"), "a quad drawn with its shader")
	var size: Vector2 = fx.get_material_fx().get_shader_parameter("rect_size")
	check(size == MDSAttackFX.EFFECTS.slash_arc[1], "the quad its size (%s)" % size)
	await get_tree().process_frame
	await get_tree().process_frame
	var mid := float(fx.get_material_fx().get_shader_parameter("progress"))
	check(mid > 0.0 and mid < 1.0, "it plays (%.2f)" % mid)
	await get_tree().create_timer(fx.duration + 0.15).timeout
	check(not is_instance_valid(fx), "and frees itself when done")
	var big := MDSAttackFX.play("impact_star", level, Vector2.ZERO, 1.0, MDSAttackFX.Team.PLAYER, 2.0)
	check(big.get_material_fx().get_shader_parameter("rect_size") == MDSAttackFX.EFFECTS.impact_star[1] * 2.0, "twice as big when asked")
	big.free()
	check(MDSAttackFX.play("no_such_fx", level, Vector2.ZERO) == null, "an unknown one: none")
	var body := Node2D.new()
	level.add_child(body)
	body.global_position = Vector2(50, 60)
	var on := MDSAttackFX.play("freeze_overlay", level, body.global_position, 1.0, MDSAttackFX.Team.ENEMY, 1.0, body)
	check(on.get_parent() == body and on.position == Vector2.ZERO, "one on a body goes with it")
	body.free()

func _colors() -> void:
	var p := MDSAttackFX.new()
	p.setup("slash_arc", MDSAttackFX.Team.PLAYER)
	var e := MDSAttackFX.new()
	e.setup("slash_arc", MDSAttackFX.Team.ENEMY)
	check(p.get_material_fx().get_shader_parameter("glow_color") == MDSAttackFX.PLAYER_COLORS[1] and e.get_material_fx().get_shader_parameter("glow_color") == MDSAttackFX.ENEMY_COLORS[1], "the player's colors, an enemy's")
	var f := MDSAttackFX.new()
	f.setup("fire_burst", MDSAttackFX.Team.ENEMY)
	check(f.get_material_fx().get_shader_parameter("glow_color") == MDSAttackFX.EFFECTS.fire_burst[3][1], "fire is fire's color, whoever throws it")
	p.free()
	e.free()
	f.free()

func _choices() -> void:
	var a := MDSAttackData.make("slash")
	check(MDSAttackFX.swing_for(a) == "slash_arc", "a swing forward: an arc")
	a.direction = MDSAttackData.Direction.UP
	check(MDSAttackFX.swing_for(a) == "uppercut_arc", "up: an uppercut")
	a.direction = MDSAttackData.Direction.DOWN
	check(MDSAttackFX.swing_for(a) == "overhead_cleave", "down: a cleave")
	check(MDSAttackFX.swing_for(MDSAttackData.make("charge_attack")) == "charge_burst" and MDSAttackFX.swing_for(MDSAttackData.make("ground_pound")) == "ground_slam", "a charged one bursts, a pound slams")
	a.swing_fx = "spin_slash"
	check(MDSAttackFX.swing_for(a) == "spin_slash", "an attack's own")
	a.swing_fx = "none"
	check(MDSAttackFX.swing_for(a) == "", "or none")
	var hit := MDSDamageInfo.make(1)
	check(MDSAttackFX.hit_for(hit, MDSAttackFX.Team.PLAYER) == "impact_star" and MDSAttackFX.hit_for(hit, MDSAttackFX.Team.ENEMY) == "spark_burst", "a blow: a star (the player's), sparks (an enemy's)")
	check(MDSAttackFX.hit_for(MDSDamageInfo.make(4), MDSAttackFX.Team.PLAYER) == "crit_flash", "a heavy one: a critical flash")
	var types := {"fire": "fire_burst", "ice": "ice_shatter", "shock": "lightning_strike", "void": "void_rift", "poison": "poison_cloud", "holy": "holy_burst", "wind": "wind_cut", "water": "water_splash", "shadow": "shadow_bite", "soul": "soul_drain"}
	var wrong: Array = []
	for t: String in types:
		if MDSAttackFX.hit_for(MDSDamageInfo.make(1, t), MDSAttackFX.Team.ENEMY) != types[t]:
			wrong.append(t)
	check(wrong.is_empty(), "each damage type its element (%s)" % [wrong])
	check(MDSAttackFX.hit_for(MDSDamageInfo.make(1, "environment"), MDSAttackFX.Team.ENEMY) == "", "lava and such: none")
	var own := MDSAttackData.make("x")
	own.hit_fx = "ink_splash"
	check(MDSAttackFX.hit_for(MDSDamageInfo.make(1, "fire"), MDSAttackFX.Team.PLAYER, own) == "ink_splash", "an attack's own hit effect first")
	check(MDSAttackFX.body_for(MDSDamageInfo.make(1, "ice"), MDSAttackFX.Team.PLAYER) == "freeze_overlay" and MDSAttackFX.body_for(MDSDamageInfo.make(1, "shock"), MDSAttackFX.Team.ENEMY) == "electrocute", "ice freezes the body hit, shock electrocutes it")
	check(MDSAttackFX.body_for(MDSDamageInfo.make(1), MDSAttackFX.Team.ENEMY) == "chromatic_hit" and MDSAttackFX.body_for(MDSDamageInfo.make(1), MDSAttackFX.Team.PLAYER) == "", "an enemy's blow shakes the player's picture")

## A body with health and a hurtbox of [param team] at [param at].
func _dummy(team: MDSHurtbox.Team, at: Vector2) -> Node2D:
	var d := Node2D.new()
	var h := MDSHealth.new()
	h.name = "Health"
	h.stats = MDSCombatStats.make(50)
	h.iframe_time = 0.0
	d.add_child(h)
	var hb := MDSHurtbox.make(team, Vector2(40, 60))
	hb.name = "Hurtbox"
	d.add_child(hb)
	level.add_child(d)
	d.global_position = at
	return d

func _fx_in(node: Node) -> Array:
	return node.get_children().filter(func(n: Node) -> bool: return n is MDSAttackFX and not n.is_queued_for_deletion())

func _hits() -> void:
	var enemy := _dummy(MDSHurtbox.Team.ENEMY, Vector2(400, 300))
	var player := Node2D.new()
	level.add_child(player)
	player.global_position = Vector2(340, 300)
	var hitbox := MDSHitbox.make(MDSHitbox.Team.PLAYER, Vector2(50, 40), MDSAttackData.make("slash", 1))
	player.add_child(hitbox)
	hitbox.position = Vector2(30, 0)
	var hurt := enemy.get_node(^"Hurtbox") as MDSHurtbox
	check(hitbox.try_hit(hurt) > 0, "the player's hit lands")
	var fx := _fx_in(level)
	check(fx.size() == 1 and (fx[0] as MDSAttackFX).effect == "impact_star" and (fx[0] as MDSAttackFX).team == MDSAttackFX.Team.PLAYER, "and its effect plays where it struck (%s)" % [fx.map(func(n: MDSAttackFX) -> String: return n.effect)])
	var at: Vector2 = (fx[0] as Node2D).global_position
	check(at.x > hitbox.global_position.x and at.x < enemy.global_position.x + 1.0, "between the blade and the enemy (%s)" % at)
	for n in fx:
		n.free()
	var zap := MDSAttackData.make("zap", 1)
	zap.damage_type = "shock"
	hitbox.attack = zap
	hitbox.reset_hits()
	hitbox.try_hit(hurt)
	check(_fx_in(level).any(func(n: MDSAttackFX) -> bool: return n.effect == "lightning_strike") and _fx_in(enemy).any(func(n: MDSAttackFX) -> bool: return n.effect == "electrocute"), "shock: lightning where it struck, the enemy electrocuted")
	for n in _fx_in(level) + _fx_in(enemy):
		n.free()
	# An enemy's claw on the player.
	var hero := _dummy(MDSHurtbox.Team.PLAYER, Vector2(600, 300))
	var claw := MDSHitbox.make(MDSHitbox.Team.ENEMY, Vector2(40, 40))
	enemy.add_child(claw)
	check(claw.try_hit(hero.get_node(^"Hurtbox")) > 0, "an enemy's hit lands")
	var mine := _fx_in(level)
	check(mine.size() == 1 and (mine[0] as MDSAttackFX).effect == "spark_burst" and (mine[0] as MDSAttackFX).team == MDSAttackFX.Team.ENEMY and _fx_in(hero).any(func(n: MDSAttackFX) -> bool: return n.effect == "chromatic_hit"), "in the enemy's colors, the player's picture shaken")
	for n in _fx_in(level) + _fx_in(hero):
		n.free()
	# Turned off.
	ProjectSettings.set_setting(SETTING, false)
	hitbox.attack = MDSAttackData.make("slash", 1)
	hitbox.reset_hits()
	hitbox.try_hit(hurt)
	check(_fx_in(level).is_empty() and not MDSAttackFX.enabled(), "feel/attack_fx off: none")
	ProjectSettings.set_setting(SETTING, null)
	check(MDSAttackFX.enabled(), "on by default")
	await get_tree().process_frame

func _swings() -> void:
	var hero := Node2D.new()
	level.add_child(hero)
	hero.global_position = Vector2(100, 100)
	var a := MDSAttackData.make("slash")
	var fx := MDSAttackFX.on_swing(a, hero, -1.0)
	check(fx and fx.get_parent() == hero and fx.effect == "slash_arc" and fx.scale.x < 0.0 and fx.position.x < 0.0, "a swing to the left: its arc in front of the attacker, facing left")
	a.direction = MDSAttackData.Direction.DOWN
	var down := MDSAttackFX.on_swing(a, hero, 1.0)
	check(down.effect == "overhead_cleave" and is_equal_approx(down.rotation, PI * 0.5) and down.position.y > 0.0, "a swing down: turned to face down, below")
	hero.free()
