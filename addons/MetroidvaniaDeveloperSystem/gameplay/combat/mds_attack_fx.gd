class_name MDSAttackFX
extends Node2D
## An attack's effect, played once: a blade's arc as the player swings, a flash and sparks where
## a blow lands, fire, ice or lightning for a hit of that type, a body flickering or freezing as it
## is hit. Thirty of them ([constant EFFECTS]), each a shader in
## [code]gameplay/shaders/attacks/[/code], drawn on a quad that faces the way the attack goes and
## frees itself when done.
##
## Each takes the colors of who attacks ([member team]): the player's (warm white and sky blue) or
## an enemy's (pale rose and red), unless it has an element's own (fire is orange whoever throws
## it). Every color can be changed (see [method colors_for]): the teams' in the Project Settings
## ([code]metroidvania_developer_system/gameplay/fx/player_color[/code], [code]player_glow[/code],
## [code]enemy_color[/code], [code]enemy_glow[/code]), one effect's in [member effect_colors], an
## attack's with [member MDSAttackData.fx_color] and [member MDSAttackData.fx_glow], one play's
## with [method play]'s [code]colors[/code]. Where they hit, [MDSHitParticles] fly off the one hurt. With the kit's feel setting [code]feel/attack_fx[/code] on (the default), they play by
## themselves: the player's swings ([method on_swing]), every hit of a player or enemy hitbox and
## projectile ([method on_hit]) and parries. An attack picks its own with
## [member MDSAttackData.swing_fx] and [member MDSAttackData.hit_fx]. From code:
## [codeblock]
## MDSAttackFX.play("lightning_strike", room, enemy.global_position)
## MDSAttackFX.play("slash_arc", room, boss.global_position, -1.0, MDSAttackFX.Team.ENEMY)
## MDSAttackFX.play("freeze_overlay", player, player.global_position, 1.0, MDSAttackFX.Team.ENEMY, 1.0, player)
## [/codeblock]

## Whose colors: the player's, or an enemy's.
enum Team { PLAYER, ENEMY }

const SHADER_DIR := "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/"
## The kit's feel setting that plays them by themselves.
const SETTING := "feel/attack_fx"

## id -> [kind, size (px), seconds, colors ([] the team's, or [core, glow]), what it is]. Kinds:
## "swing" (at the attacker, facing its way), "impact" (where a blow lands), "body" (over the one
## hit, following it: it changes how the body looks under it).
const EFFECTS := {
	"slash_arc": ["swing", Vector2(170, 170), 0.26, [], "A blade's arc swept from above down to the front"],
	"crescent_wave": ["swing", Vector2(320, 140), 0.5, [], "A crescent of light thrown forward (a sword beam)"],
	"thrust": ["swing", Vector2(240, 90), 0.24, [], "A stab: a straight streak shooting forward"],
	"overhead_cleave": ["swing", Vector2(190, 190), 0.32, [], "A heavy cleave brought down from overhead"],
	"spin_slash": ["swing", Vector2(200, 200), 0.45, [], "A whirlwind: the blade swept round twice"],
	"claw_rake": ["swing", Vector2(150, 150), 0.32, [], "Three claw marks torn across one after another"],
	"uppercut_arc": ["swing", Vector2(170, 170), 0.3, [], "A rising slash throwing sparks upward"],
	"ground_slam": ["swing", Vector2(320, 150), 0.5, [], "A dome of force bursting up off the ground, dust flying"],
	"charge_burst": ["swing", Vector2(170, 170), 0.6, [], "Motes gathering in, then a burst of light let loose"],
	"dash_streak": ["swing", Vector2(260, 110), 0.3, [], "Speed lines streaming out behind a dash"],
	"impact_star": ["impact", Vector2(110, 110), 0.2, [], "The flash where a blow lands: a four-pointed star"],
	"spark_burst": ["impact", Vector2(140, 140), 0.35, [], "Sparks thrown out from the hit, arcing down"],
	"shockwave_ring": ["impact", Vector2(220, 220), 0.45, [], "A ring racing outward, bending what is behind it"],
	"ink_splash": ["impact", Vector2(140, 140), 0.55, [], "A splash of ink thrown from the wound"],
	"crit_flash": ["impact", Vector2(200, 200), 0.3, [], "A critical hit: a blinding cross flare"],
	"parry_flash": ["impact", Vector2(150, 150), 0.3, [], "A diamond of light snapping out from a parry"],
	"shield_ripple": ["impact", Vector2(150, 150), 0.45, [], "A blocked hit: a shield's hexagons lit by a ripple"],
	"fire_burst": ["impact", Vector2(160, 170), 0.55, [Color("#fff1a8"), Color("#ff6a1a")], "Fire licking up and out, embers flying"],
	"ice_shatter": ["impact", Vector2(160, 160), 0.5, [Color("#f2fdff"), Color("#6fc8ff")], "Crystal shards flung out, frost glittering"],
	"lightning_strike": ["impact", Vector2(120, 240), 0.4, [Color("#f6f4ff"), Color("#8a7dff")], "A jagged bolt cracking down onto the hit"],
	"poison_cloud": ["impact", Vector2(170, 160), 0.8, [Color("#e8ffb0"), Color("#7ccf2c")], "A sickly cloud welling up, bubbles rising"],
	"void_rift": ["impact", Vector2(150, 150), 0.6, [Color("#ffd2ff"), Color("#9a3cff")], "A rift torn open, swirling into darkness"],
	"holy_burst": ["impact", Vector2(170, 170), 0.5, [Color("#fffbe8"), Color("#ffd35a")], "A radiant burst with rays fanning out"],
	"wind_cut": ["impact", Vector2(220, 140), 0.4, [Color("#ffffff"), Color("#a8ffd8")], "Thin blades of air whipping across"],
	"water_splash": ["impact", Vector2(150, 160), 0.6, [Color("#e8fbff"), Color("#3aa8ff")], "A crown of spray and drops falling back"],
	"shadow_bite": ["impact", Vector2(150, 150), 0.45, [Color("#ffd0d6"), Color("#d0203c")], "Dark jaws snapping shut on the hit"],
	"soul_drain": ["impact", Vector2(170, 170), 0.6, [Color("#e6fffb"), Color("#3fe8c8")], "Wisps spiralling in to the one who hit"],
	"chromatic_hit": ["body", Vector2(110, 140), 0.3, [], "The body's picture split red, green and blue and shaken"],
	"freeze_overlay": ["body", Vector2(110, 140), 1.2, [Color("#ffffff"), Color("#8fd8ff")], "The body frozen: icy, frost at its edges, thawing"],
	"electrocute": ["body", Vector2(110, 140), 0.7, [Color("#ffffff"), Color("#7fd2ff")], "Arcs crawling over the body, flickering"],
}
## The team colors by default: [core, glow] (the Project Settings' fx/ colors change them).
const PLAYER_COLORS := [Color("#fff7e6"), Color("#6fd8ff")]
const ENEMY_COLORS := [Color("#ffe3dc"), Color("#ff3b4e")]

## Colors of your own: id -> [core, glow], over the Project Settings and the effects' own. An
## effect's id, a hurt particles' id ([constant MDSHitParticles.PARTICLES]), or a team's:
## "player", "enemy".
static var effect_colors: Dictionary = {}
## The effect of a hit by its damage type (see [method hit_for]).
const BY_TYPE := {
	"fire": "fire_burst", "ice": "ice_shatter", "shock": "lightning_strike", "lightning": "lightning_strike",
	"poison": "poison_cloud", "void": "void_rift", "holy": "holy_burst", "light": "holy_burst",
	"wind": "wind_cut", "water": "water_splash", "shadow": "shadow_bite", "dark": "shadow_bite",
	"soul": "soul_drain",
}
## What a hit of a type does to the body hit, as well (see [method body_for]).
const BODY_BY_TYPE := {"ice": "freeze_overlay", "shock": "electrocute", "lightning": "electrocute"}

## Which effect (an id of [constant EFFECTS]).
var effect := ""
var team: Team = Team.PLAYER
## Seconds it plays for.
var duration := 0.3
## How far it has played (0..1).
var progress := 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		if _mat:
			_mat.set_shader_parameter("progress", progress)

var _mat: ShaderMaterial
var _time := 0.0

## Plays effect [param id] at [param at] (global) under [param parent] (the room, or the body it
## follows), facing right ([param facing] 1) or left (-1), in [param p_team]'s colors, [param size]
## times its size. A "body" effect, or any with [param follow], goes on [param follow] (a body)
## and moves with it. [param colors] ([core, glow]) colors this play (see [method colors_for]).
## Returns it (null: no such effect, or no parent).
static func play(id: String, parent: Node, at: Vector2, facing := 1.0, p_team: Team = Team.PLAYER, size := 1.0, follow: Node2D = null, colors: Array = []) -> MDSAttackFX:
	if not EFFECTS.has(id):
		push_warning("MDSAttackFX: no effect '%s' (%s)." % [id, ", ".join(EFFECTS.keys())])
		return null
	var host: Node = follow if follow else parent
	if not is_instance_valid(host):
		return null
	var fx := MDSAttackFX.new()
	fx.setup(id, p_team, size, colors)
	fx.scale = Vector2(-1.0 if facing < 0.0 else 1.0, 1.0)
	host.add_child(fx)
	fx.global_position = at
	return fx

## Makes this effect [param id] in [param p_team]'s colors (or [param colors]: [core, glow]),
## [param size] times its size (not yet playing: it plays once in the tree).
func setup(id: String, p_team: Team = Team.PLAYER, size := 1.0, colors: Array = []) -> void:
	var e: Array = EFFECTS[id]
	effect = id
	team = p_team
	name = "FX_" + id
	duration = float(e[2])
	z_index = 40
	var quad_size: Vector2 = e[1] * size
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_DIR + id + ".gdshader")
	var c := colors_for(id, p_team, e[3], colors)
	_mat.set_shader_parameter("core_color", c[0])
	_mat.set_shader_parameter("glow_color", c[1])
	_mat.set_shader_parameter("rect_size", quad_size)
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_mat.set_shader_parameter("progress", 0.0)
	var quad := Polygon2D.new()
	quad.name = "Quad"
	var h := quad_size * 0.5
	quad.polygon = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	quad.material = _mat
	add_child(quad)

## The effect's shader material (for its colors, intensity...).
func get_material_fx() -> ShaderMaterial:
	return _mat

## Sets its colors now, while it plays.
func set_colors(core: Color, glow: Color) -> void:
	_mat.set_shader_parameter("core_color", core)
	_mat.set_shader_parameter("glow_color", glow)

## How strongly it glows (its shader's intensity: 1 as it is, 0 gone, more brighter).
func set_intensity(value: float) -> void:
	_mat.set_shader_parameter("intensity", value)

# --- Colors ----------------------------------------------------------------------------------------

## [core, glow] of a team: [member effect_colors]' "player" / "enemy", else the Project Settings'
## (fx/player_color, fx/player_glow, fx/enemy_color, fx/enemy_glow), else the defaults.
static func team_colors(p_team: Team) -> Array:
	var key := "player" if p_team == Team.PLAYER else "enemy"
	if effect_colors.has(key):
		return effect_colors[key]
	var d: Array = PLAYER_COLORS if p_team == Team.PLAYER else ENEMY_COLORS
	return [MDSGameplaySetup.setting("fx/%s_color" % key, d[0]), MDSGameplaySetup.setting("fx/%s_glow" % key, d[1])]

## The colors effect (or particles) [param id] plays in for [param p_team]: [param override]
## where given ([core, glow]; a transparent one is left as it would be), else
## [member effect_colors]' for it, else its own [param own] (an element's), else the team's
## ([method team_colors]).
static func colors_for(id: String, p_team: Team, own: Array = [], override: Array = []) -> Array:
	var c: Array = team_colors(p_team)
	if not own.is_empty():
		c = own
	if effect_colors.has(id):
		c = effect_colors[id]
	c = c.duplicate()
	for i in mini(override.size(), 2):
		if override[i] is Color and (override[i] as Color).a > 0.0:
			c[i] = override[i]
	return c

## An attack's colors ([member MDSAttackData.fx_color], [member MDSAttackData.fx_glow]) as an
## override for [method colors_for] (transparent: none).
static func attack_colors(attack: MDSAttackData) -> Array:
	return [attack.fx_color, attack.fx_glow] if attack else []

func _process(delta: float) -> void:
	_time += delta
	progress = _time / maxf(duration, 0.001)
	if _time >= duration:
		queue_free()

# --- Played by themselves ------------------------------------------------------------------------

## Whether they play by themselves (the kit's [code]feel/attack_fx[/code] setting).
static func enabled() -> bool:
	return bool(MDSGameplaySetup.setting(SETTING, true))

## The effect of a swing of [param attack]: its own [member MDSAttackData.swing_fx], else by how
## it goes (up: an uppercut, down: a cleave, a charged one: a burst, a ground pound: a slam, the
## rest: an arc). "" for none.
static func swing_for(attack: MDSAttackData) -> String:
	if not attack:
		return ""
	if not attack.swing_fx.is_empty():
		return "" if attack.swing_fx == "none" else attack.swing_fx
	var id := attack.id.to_lower()
	if id.contains("pound") or id.contains("slam"):
		return "ground_slam"
	if id.contains("charge"):
		return "charge_burst"
	if id.contains("spin"):
		return "spin_slash"
	match attack.direction:
		MDSAttackData.Direction.UP:
			return "uppercut_arc"
		MDSAttackData.Direction.DOWN:
			return "overhead_cleave"
	return "slash_arc"

## The effect of hit [param info] landed by [param p_team] with [param attack]: the attack's own
## [member MDSAttackData.hit_fx], else by its damage type ([constant BY_TYPE]), else a star (a
## heavy blow: a critical flash) for the player's, sparks for an enemy's. "" for none.
static func hit_for(info: MDSDamageInfo, p_team: Team, attack: MDSAttackData = null) -> String:
	if attack and not attack.hit_fx.is_empty():
		return "" if attack.hit_fx == "none" else attack.hit_fx
	if not info:
		return ""
	var t := info.damage_type.to_lower()
	if BY_TYPE.has(t):
		return BY_TYPE[t]
	if t == "environment":
		return ""
	if p_team == Team.PLAYER:
		return "crit_flash" if info.amount >= 3 else "impact_star"
	return "spark_burst"

## What hit [param info] does to the body hit as well: frozen by ice, electrocuted by shock, the
## player's picture split when an enemy hits it hard. "" for nothing.
static func body_for(info: MDSDamageInfo, p_team: Team) -> String:
	if not info:
		return ""
	var t := info.damage_type.to_lower()
	if BODY_BY_TYPE.has(t):
		return BODY_BY_TYPE[t]
	if p_team == Team.ENEMY and t == "physical":
		return "chromatic_hit"
	return ""

## A swing of [param attack] by [param attacker] facing [param facing]: its effect, at it.
static func on_swing(attack: MDSAttackData, attacker: Node2D, facing: float, p_team: Team = Team.PLAYER) -> MDSAttackFX:
	if not enabled() or not is_instance_valid(attacker) or not attacker.is_inside_tree():
		return null
	var id := swing_for(attack)
	if id.is_empty():
		return null
	var at := attacker.global_position
	var fx := play(id, attacker, at, facing, p_team, 1.0, null, attack_colors(attack))
	if fx and attack:
		fx.set_intensity(attack.fx_intensity)
		match attack.direction:
			MDSAttackData.Direction.UP:
				fx.position = Vector2(0, -24)
			MDSAttackData.Direction.DOWN:
				fx.position = Vector2(0, 30)
				fx.rotation = PI * 0.5 * signf(facing)
			_:
				fx.position = Vector2(attack.hitbox_offset.x * 0.6 * signf(facing), attack.hitbox_offset.y)
	return fx

## Hit [param info] of [param hitbox] landed on [param target]: the hit's effect where it struck
## (between the hitbox and the target), what it does to the target's body, and the particles
## flying off it ([method MDSHitParticles.on_hurt]).
static func on_hit(hitbox: MDSHitbox, target: Node, info: MDSDamageInfo, hurtbox: MDSHurtbox = null) -> void:
	MDSHitParticles.on_hurt(hitbox, target, info, hurtbox)
	_effects_on_hit(hitbox, target, info)

static func _effects_on_hit(hitbox: MDSHitbox, target: Node, info: MDSDamageInfo) -> void:
	if not enabled() or not is_instance_valid(hitbox) or not hitbox.is_inside_tree() or hitbox.team == MDSHitbox.Team.HAZARD:
		return
	var p_team := Team.PLAYER if hitbox.team == MDSHitbox.Team.PLAYER else Team.ENEMY
	var body := target as Node2D
	var at := hitbox.global_position
	if body and body.is_inside_tree():
		at = at.lerp(body.global_position, 0.6)
	var world: Node = body.get_parent() if body and body.get_parent() else hitbox.get_tree().current_scene
	var facing := signf(at.x - (info.origin.x if info.origin != Vector2.INF else hitbox.global_position.x))
	var id := hit_for(info, p_team, hitbox.attack)
	var colors := attack_colors(hitbox.attack)
	var shine := hitbox.attack.fx_intensity if hitbox.attack else 1.0
	if not id.is_empty():
		var fx := play(id, world, at, facing if facing != 0.0 else 1.0, p_team, 1.0, null, colors)
		if fx:
			fx.set_intensity(shine)
	var on_body := body_for(info, p_team)
	if not on_body.is_empty() and body and body.is_inside_tree():
		var fx := play(on_body, world, body.global_position, 1.0, p_team, 1.0, body, colors)
		if fx:
			fx.set_intensity(shine)
