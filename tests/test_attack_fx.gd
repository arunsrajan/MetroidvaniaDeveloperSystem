extends "res://tests/test_case.gd"
## Attack effects (MDSAttackFX): the thirty shaders, played once and gone, facing the attack, in
## the player's or the enemy's colors (an element in its own), picked by themselves for swings
## and hits (by the attack, its direction, its damage type), and what a hit does to the body hit;
## the feel setting turns them off. Their colors, set at every level: the Project Settings' team
## colors, an effect's, an attack's, one play's. And the thirty hurt particles (MDSHitParticles)
## flying off whoever is hurt, in its colors, picked the same ways.

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
	_color_settings()
	await _particles()
	_palettes_and_glow()
	_dropdowns_and_size()
	await _hurt_particles()
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

## The colors at every level.
func _color_settings() -> void:
	var key := "metroidvania_developer_system/gameplay/fx/player_glow"
	ProjectSettings.set_setting(key, Color.ORANGE)
	var fx := MDSAttackFX.new()
	fx.setup("slash_arc", MDSAttackFX.Team.PLAYER)
	check(fx.get_material_fx().get_shader_parameter("glow_color") == Color.ORANGE, "the Project Settings' team color")
	fx.free()
	ProjectSettings.set_setting(key, null)
	MDSAttackFX.effect_colors["slash_arc"] = [Color.WHITE, Color.GREEN]
	MDSAttackFX.effect_colors["enemy"] = [Color.BLACK, Color.PURPLE]
	var mine := MDSAttackFX.new()
	mine.setup("slash_arc", MDSAttackFX.Team.ENEMY)
	var theirs := MDSAttackFX.new()
	theirs.setup("thrust", MDSAttackFX.Team.ENEMY)
	check(mine.get_material_fx().get_shader_parameter("glow_color") == Color.GREEN and theirs.get_material_fx().get_shader_parameter("glow_color") == Color.PURPLE, "one effect's own colors, and a team's, from code")
	mine.free()
	theirs.free()
	MDSAttackFX.effect_colors.clear()
	var a := MDSAttackData.make("slash")
	a.fx_glow = Color.YELLOW
	check(MDSAttackFX.colors_for("fire_burst", MDSAttackFX.Team.PLAYER, MDSAttackFX.EFFECTS.fire_burst[3], MDSAttackFX.attack_colors(a)) == [MDSAttackFX.EFFECTS.fire_burst[3][0], Color.YELLOW], "an attack's glow over fire's own, its unset core left as fire's")
	var one := MDSAttackFX.play("impact_star", level, Vector2.ZERO, 1.0, MDSAttackFX.Team.PLAYER, 1.0, null, [Color.RED, Color.BLUE])
	check(one.get_material_fx().get_shader_parameter("core_color") == Color.RED, "one play's colors")
	one.set_colors(Color.CYAN, Color.MAGENTA)
	check(one.get_material_fx().get_shader_parameter("glow_color") == Color.MAGENTA, "and changed while it plays")
	one.free()

func _particles() -> void:
	check(MDSHitParticles.PARTICLES.size() == 30, "thirty hurt particles (%d)" % MDSHitParticles.PARTICLES.size())
	var bad: Array = []
	for id: String in MDSHitParticles.PARTICLES:
		var p := MDSHitParticles.new()
		p.setup(id)
		if p.amount <= 0 or p.lifetime <= 0.0 or not p.texture or not p.color_ramp or not p.one_shot:
			bad.append(id)
		p.free()
	check(bad.is_empty(), "each a one-shot burst with its texture and colors (%s)" % [bad])
	var ink := MDSHitParticles.burst("ink_drops", level, Vector2(200, 100), Vector2.RIGHT, MDSAttackFX.Team.ENEMY)
	check(ink and ink.get_parent() == level and ink.global_position == Vector2(200, 100) and ink.emitting and ink.direction.x > 0.0, "a burst where asked, flying the way the blow went")
	check(ink.color_ramp.get_color(0) == MDSAttackFX.ENEMY_COLORS[0], "in the enemy's colors")
	var embers := MDSHitParticles.burst("embers", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.PLAYER)
	var pal: Gradient = embers.color_initial_ramp
	check(pal and pal.get_point_count() == 4 and pal.interpolation_mode == Gradient.GRADIENT_INTERPOLATE_CONSTANT and embers.material is CanvasItemMaterial, "embers in their own palette, each one of its colors, glowing")
	var ice := MDSHitParticles.burst("ice_chips", level, Vector2.ZERO)
	check(ice.color_initial_ramp == null and ice.color_ramp.get_color(0) == MDSHitParticles.PARTICLES.ice_chips.colors[0] and ice.material == null, "ice chips in one color, not glowing")
	ice.free()
	var green := MDSHitParticles.burst("blood_spray", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.ENEMY, [Color.GREEN, Color.DARK_GREEN])
	check(green.color_ramp.get_color(0) == Color.GREEN, "colors of one's own")
	MDSAttackFX.effect_colors["feathers"] = [Color.GOLD, Color.ORANGE]
	var gold := MDSHitParticles.burst("feathers", level, Vector2.ZERO)
	check(gold.color_ramp.get_color(0) == Color.GOLD, "a kind's colors set from code")
	MDSAttackFX.effect_colors.clear()
	check(MDSHitParticles.burst("no_such", level, Vector2.ZERO) == null, "an unknown one: none")
	await get_tree().create_timer(gold.lifetime * 1.4 + 0.25).timeout
	check(not is_instance_valid(gold) and not is_instance_valid(ink), "they free themselves when done")
	for n in [embers, green]:
		if is_instance_valid(n):
			n.free()

func _hurt_particles() -> void:
	var hb := MDSHurtbox.make(MDSHurtbox.Team.ENEMY, Vector2(10, 10))
	check(MDSHitParticles.particles_for(MDSDamageInfo.make(1), hb) == "ink_drops" and MDSHitParticles.particles_for(MDSDamageInfo.make(1, "fire"), hb) == "embers" and MDSHitParticles.particles_for(MDSDamageInfo.make(5), hb) == "sparks", "an enemy hurt: ink, embers for a burn, sparks for a heavy blow")
	hb.team = MDSHurtbox.Team.PLAYER
	check(MDSHitParticles.particles_for(MDSDamageInfo.make(1), hb) == "blood_spray", "the player hurt: drops")
	hb.hurt_particles = "feathers"
	check(MDSHitParticles.particles_for(MDSDamageInfo.make(1, "fire"), hb) == "feathers", "a hurtbox's own first")
	var a := MDSAttackData.make("x")
	a.hit_particles = "none"
	check(MDSHitParticles.particles_for(MDSDamageInfo.make(1), hb, a) == "", "an attack's own before it (none)")
	hb.free()
	# A real hit: off the enemy, in its colors, its hurtbox's own when set.
	var enemy := _dummy(MDSHurtbox.Team.ENEMY, Vector2(500, 300))
	var hurt := enemy.get_node(^"Hurtbox") as MDSHurtbox
	hurt.particle_color = Color.LIME
	var hero := Node2D.new()
	level.add_child(hero)
	hero.global_position = Vector2(440, 300)
	var blade := MDSHitbox.make(MDSHitbox.Team.PLAYER, Vector2(40, 40), MDSAttackData.make("slash", 1))
	hero.add_child(blade)
	blade.try_hit(hurt)
	var parts := level.get_children().filter(func(n: Node) -> bool: return n is MDSHitParticles)
	check(parts.size() == 1 and (parts[0] as MDSHitParticles).particles == "ink_drops" and (parts[0] as MDSHitParticles).team == MDSAttackFX.Team.ENEMY, "a hit: ink flies off the enemy (%s)" % [parts.map(func(n: MDSHitParticles) -> String: return n.particles)])
	check(parts.size() == 1 and (parts[0] as MDSHitParticles).color_ramp.get_color(0) == Color.LIME and (parts[0] as MDSHitParticles).direction.x > 0.0, "in its hurtbox's color, away from the blow")
	for n in level.get_children():
		if n is MDSHitParticles or n is MDSAttackFX:
			n.free()
	ProjectSettings.set_setting("metroidvania_developer_system/gameplay/feel/hurt_particles", false)
	blade.reset_hits()
	blade.try_hit(hurt)
	check(not level.get_children().any(func(n: Node) -> bool: return n is MDSHitParticles), "feel/hurt_particles off: none")
	ProjectSettings.set_setting("metroidvania_developer_system/gameplay/feel/hurt_particles", null)
	await get_tree().process_frame

## One color or several, and how strongly they glow, set at every level.
func _palettes_and_glow() -> void:
	var three := PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var p := MDSHitParticles.burst("ink_drops", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.ENEMY, [], 1.0, three)
	var g: Gradient = p.color_initial_ramp
	var seen := [g.sample(0.1), g.sample(0.5), g.sample(0.9)]
	check(seen == [Color.RED, Color.GREEN, Color.BLUE], "a palette: each particle one of its colors (%s)" % [seen])
	check(p.color_ramp.get_color(0) == Color.WHITE and p.color_ramp.get_color(p.color_ramp.get_point_count() - 1).a == 0.0, "keeping it, fading out")
	p.set_palette(PackedColorArray([Color.ORANGE]))
	check(p.color_initial_ramp == null and p.color_ramp.get_color(0) == Color.ORANGE, "one color: all of it")
	p.free()
	var plain := MDSHitParticles.burst("embers", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.ENEMY, [Color.CYAN, Color.BLUE])
	check(plain.color_initial_ramp == null and plain.color_ramp.get_color(0) == Color.CYAN, "colors given win over a kind's own palette")
	plain.free()
	MDSHitParticles.palettes["sparks"] = [Color.GOLD, Color.WHITE]
	var mine := MDSHitParticles.burst("sparks", level, Vector2.ZERO)
	check(mine.color_initial_ramp and mine.color_initial_ramp.get_point_count() == 2, "a kind's palette set from code")
	mine.free()
	MDSHitParticles.palettes.clear()
	# Glow.
	var none := MDSHitParticles.burst("sparks", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.ENEMY, [], 1.0, PackedColorArray(), 0.0)
	check(none.material == null and none.color == Color.WHITE, "glow 0: none")
	var bright := MDSHitParticles.burst("ink_drops", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.ENEMY, [], 1.0, PackedColorArray(), 2.0)
	check(bright.material is CanvasItemMaterial and (bright.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and bright.color.r > 1.0, "glow 2: glowing, brighter (%s)" % bright.color)
	var half := MDSHitParticles.burst("ink_drops", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.ENEMY, [], 1.0, PackedColorArray(), 0.5)
	check(is_equal_approx(half.color.a, 0.5), "glow 0.5: half")
	none.free()
	bright.free()
	half.free()
	MDSHitParticles.glows["ink_drops"] = 1.5
	check(is_equal_approx(MDSHitParticles.glow_for("ink_drops"), 1.5) and is_equal_approx(MDSHitParticles.glow_for("sparks"), 1.0) and is_equal_approx(MDSHitParticles.glow_for("ice_chips"), 0.0), "a kind's glow from code; the glowing kinds 1, the rest 0")
	MDSHitParticles.glows.clear()
	ProjectSettings.set_setting("metroidvania_developer_system/gameplay/fx/particle_glow", 2.0)
	check(is_equal_approx(MDSHitParticles.glow_for("sparks"), 2.0), "the Project Settings' fx/particle_glow: all twice as strong")
	ProjectSettings.set_setting("metroidvania_developer_system/gameplay/fx/particle_glow", null)
	# An attack's effects' glow.
	var a := MDSAttackData.make("slash")
	a.fx_intensity = 2.5
	var hero := Node2D.new()
	level.add_child(hero)
	var fx := MDSAttackFX.on_swing(a, hero, 1.0)
	check(is_equal_approx(float(fx.get_material_fx().get_shader_parameter("intensity")), 2.5), "an attack's fx_intensity: its effects glow that strongly")
	hero.free()
	# From a hit: the hurtbox's palette and glow, then the attack's.
	var enemy := _dummy(MDSHurtbox.Team.ENEMY, Vector2(800, 300))
	var hurt := enemy.get_node(^"Hurtbox") as MDSHurtbox
	var blade := MDSHitbox.make(MDSHitbox.Team.PLAYER, Vector2(40, 40), MDSAttackData.make("slash", 1))
	blade.attack.particle_palette = PackedColorArray([Color.WHITE, Color.BLACK])
	blade.attack.particle_glow = 0.0
	var foe := Node2D.new()
	level.add_child(foe)
	foe.global_position = Vector2(740, 300)
	foe.add_child(blade)
	blade.try_hit(hurt)
	var got := level.get_children().filter(func(n: Node) -> bool: return n is MDSHitParticles)
	check(got.size() == 1 and (got[0] as MDSHitParticles).color_initial_ramp.get_point_count() == 2 and (got[0] as MDSHitParticles).material == null, "an attack's palette and glow on what it hurts")
	for n in got:
		n.free()
	hurt.particle_palette = PackedColorArray([Color.YELLOW, Color.ORANGE, Color.RED])
	hurt.particle_glow = 1.0
	blade.reset_hits()
	blade.try_hit(hurt)
	got = level.get_children().filter(func(n: Node) -> bool: return n is MDSHitParticles)
	check(got.size() == 1 and (got[0] as MDSHitParticles).color_initial_ramp.get_point_count() == 3 and (got[0] as MDSHitParticles).material is CanvasItemMaterial, "the hurtbox's own win")
	for n in level.get_children():
		if n is MDSHitParticles or n is MDSAttackFX:
			n.free()
	enemy.free()
	foe.free()

## Damage types and particles picked from dropdowns; how big the particles are, set at every level.
func _dropdowns_and_size() -> void:
	var kinds := MDSHitParticles.KINDS.split(",")
	check(kinds.size() == 31 and kinds[0] == "none" and Array(kinds.slice(1)) == MDSHitParticles.PARTICLES.keys(), "the particles' dropdown: none and every kind")
	for t: String in MDSHitParticles.BY_TYPE.keys() + MDSAttackFX.BY_TYPE.keys() + ["physical", "environment"]:
		if not MDSDamageInfo.TYPES.split(",").has(t):
			check(false, "the damage types' dropdown has %s" % t)
	var hints := {}
	for o: Object in [MDSHurtbox.new(), MDSAttackData.new(), MDSEnemy.new()]:
		for prop in o.get_property_list():
			if prop.name in ["hurt_particles", "hit_particles", "damage_type"]:
				hints["%s.%s" % [o.get_script().get_global_name(), prop.name]] = [prop.hint, prop.hint_string]
		if o is Node:
			o.free()
	var want := {
		"MDSHurtbox.hurt_particles": MDSHitParticles.KINDS, "MDSAttackData.hit_particles": MDSHitParticles.KINDS,
		"MDSEnemy.hurt_particles": MDSHitParticles.KINDS, "MDSAttackData.damage_type": MDSDamageInfo.TYPES,
		"MDSEnemy.damage_type": MDSDamageInfo.TYPES,
	}
	var ok := true
	for k: String in want:
		ok = ok and hints.has(k) and hints[k] == [PROPERTY_HINT_ENUM_SUGGESTION, want[k]]
	check(ok, "damage types and particles are dropdowns in the inspector (%s)" % [hints.keys()])
	# Size.
	var plain := MDSHitParticles.burst("sparks", level, Vector2.ZERO)
	var big := MDSHitParticles.burst("sparks", level, Vector2.ZERO, Vector2.UP, MDSAttackFX.Team.ENEMY, [], 1.0, PackedColorArray(), -1.0, 2.0)
	check(is_equal_approx(big.scale_amount_max, plain.scale_amount_max * 2.0) and is_equal_approx(big.initial_velocity_max, plain.initial_velocity_max), "particle_size 2: twice as big, flying as far")
	big.set_particle_size(0.5)
	check(is_equal_approx(big.scale_amount_max, plain.scale_amount_max * 0.5), "set_particle_size()")
	big.free()
	MDSHitParticles.sizes["sparks"] = 3.0
	check(is_equal_approx(MDSHitParticles.size_for("sparks"), 3.0) and is_equal_approx(MDSHitParticles.size_for("embers"), 1.0), "a kind's size from code")
	MDSHitParticles.sizes.clear()
	ProjectSettings.set_setting("metroidvania_developer_system/gameplay/fx/particle_size", 1.5)
	check(is_equal_approx(MDSHitParticles.size_for("sparks", 2.0), 3.0), "the Project Settings' fx/particle_size: all of them bigger")
	ProjectSettings.set_setting("metroidvania_developer_system/gameplay/fx/particle_size", null)
	# From a hit: the attack's size times the hurtbox's.
	var enemy := _dummy(MDSHurtbox.Team.ENEMY, Vector2(800, 300))
	var hurt := enemy.get_node(^"Hurtbox") as MDSHurtbox
	hurt.hurt_particles = "sparks"
	hurt.particle_size = 2.0
	var hero := Node2D.new()
	level.add_child(hero)
	var blade := MDSHitbox.make(MDSHitbox.Team.PLAYER, Vector2(40, 40), MDSAttackData.make("slash", 1))
	blade.attack.particle_size = 1.5
	hero.add_child(blade)
	hero.global_position = enemy.global_position
	blade.try_hit(hurt)
	var got := level.get_children().filter(func(n: Node) -> bool: return n is MDSHitParticles and n != plain)
	check(got.size() == 1 and is_equal_approx((got[0] as MDSHitParticles).scale_amount_max, plain.scale_amount_max * 3.0), "a hit: the attack's size times the hurtbox's")
	plain.free()
	for n in level.get_children():
		if n is MDSHitParticles or n is MDSAttackFX:
			n.free()
	hero.free()
	enemy.free()
