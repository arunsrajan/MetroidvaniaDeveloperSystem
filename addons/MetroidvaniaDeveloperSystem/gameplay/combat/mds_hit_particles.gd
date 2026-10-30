class_name MDSHitParticles
extends CPUParticles2D
## Particles flying off whoever is hurt, player or enemy: blood or ink thrown the way the blow
## went, sparks off armour, embers from a burn, ice chips, feathers, coins of light... Thirty kinds
## ([constant PARTICLES]), each a burst of [CPUParticles2D] (so it runs on every renderer) with a
## small texture drawn in code, that frees itself when the last particle is gone.
##
## Colors, one or many. In one color, every particle goes from it to a second one as it fades:
## the colors of the one hurt ([member team]), the player's or an enemy's, set in the Project
## Settings (fx/player_color, fx/player_glow, fx/enemy_color, fx/enemy_glow), unless they have an
## element's own (ice chips are ice blue). In several (a palette), each particle is one of them,
## picked at random, fading out: some kinds have one of their own (embers yellow, orange and red;
## petals pink, white and gold). And they glow or not, as strongly as asked ([method glow_for]: 0
## none, 1 glowing, more brighter). All of it can be set, the first given winning:
## - one burst's [code]colors[/code], [code]palette[/code] and [code]glow[/code] ([method burst]);
## - the hurt one's hurtbox: [member MDSHurtbox.particle_color], [member MDSHurtbox.particle_fade],
##   [member MDSHurtbox.particle_palette], [member MDSHurtbox.particle_glow];
## - the attack's: [member MDSAttackData.fx_color], [member MDSAttackData.fx_glow],
##   [member MDSAttackData.particle_palette], [member MDSAttackData.particle_glow];
## - from code, by kind: [member palettes], [member glows], [member MDSAttackFX.effect_colors];
## - the Project Settings: the teams' colors, and fx/particle_glow (how strongly all glow).
##
## With the kit's feel setting [code]feel/hurt_particles[/code] on (the default) they fly by
## themselves from every hit of a hitbox or projectile ([method on_hurt]), picked by the attack's
## [member MDSAttackData.hit_particles], else the hurtbox's [member MDSHurtbox.hurt_particles],
## else the damage type. From code:
## [codeblock]
## MDSHitParticles.burst("feathers", room, bird.global_position, Vector2.UP)
## MDSHitParticles.burst("blood_spray", room, at, hit_dir, MDSAttackFX.Team.ENEMY, [Color.DARK_GREEN, Color.BLACK])
## MDSHitParticles.burst("star_burst", room, at, Vector2.UP, MDSAttackFX.Team.ENEMY, [], 1.0, PackedColorArray([Color.GOLD, Color.HOT_PINK, Color.CYAN]), 2.0)
## [/codeblock]

const SETTING := "feel/hurt_particles"
## How big the particles are drawn (their textures are 16 px or so), over their own scale.
const SIZE := 1.8

## id -> its settings: tex (the particle's shape: dot, soft, spark, shard, square, ring, star,
## flake, leaf, feather), amount, life (s), speed [min, max] (px/s), spread (degrees round the
## hit's way), gravity (px/s², down), damping, scale [min, max], spin (degrees/s), grow (they swell
## as they fade, like smoke), add (they glow: added to what is behind), along (turned the way they
## fly), radial (pulled in, less than 0, or pushed out), swirl (round the hit), colors ([] the
## team's, or [color, fade-to color]), palette (several colors, one each), info.
const PARTICLES := {
	"blood_spray": {"tex": "dot", "amount": 18, "life": 0.6, "speed": [120, 320], "spread": 40, "gravity": 900, "scale": [0.25, 0.6], "info": "Drops thrown the way the blow went, falling"},
	"ink_drops": {"tex": "dot", "amount": 14, "life": 0.8, "speed": [80, 240], "spread": 60, "gravity": 700, "scale": [0.35, 0.9], "info": "Blots of ink splattering out and dropping"},
	"sparks": {"tex": "spark", "amount": 20, "life": 0.35, "speed": [200, 480], "spread": 70, "gravity": 400, "scale": [0.4, 0.8], "add": true, "along": true, "info": "Sparks off armour or a blade, streaking"},
	"metal_shards": {"tex": "shard", "amount": 10, "life": 0.6, "speed": [150, 350], "spread": 80, "gravity": 900, "scale": [0.35, 0.7], "spin": 720, "colors": [Color("#e6ecf2"), Color("#6b7686")], "info": "Bits of metal knocked off, tumbling"},
	"bone_chips": {"tex": "square", "amount": 8, "life": 0.7, "speed": [120, 260], "spread": 60, "gravity": 1000, "scale": [0.3, 0.6], "spin": 540, "colors": [Color("#f4ecd6"), Color("#b8a682")], "info": "Chips of bone flying and tumbling down"},
	"dust_puff": {"tex": "soft", "amount": 12, "life": 0.8, "speed": [30, 110], "spread": 180, "gravity": -20, "damping": 60, "scale": [1.2, 2.2], "grow": true, "colors": [Color("#d9cdb4"), Color(0.6, 0.55, 0.45, 0.0)], "info": "A puff of dust swelling and settling"},
	"smoke": {"tex": "soft", "amount": 10, "life": 1.1, "speed": [20, 70], "spread": 40, "gravity": -60, "damping": 10, "scale": [1.4, 2.4], "grow": true, "up": true, "colors": [Color("#8a8a90"), Color(0.2, 0.2, 0.22, 0.0)], "info": "Smoke curling up from the wound"},
	"embers": {"tex": "dot", "amount": 16, "life": 1.0, "speed": [40, 160], "spread": 180, "gravity": -120, "damping": 30, "scale": [0.12, 0.3], "add": true, "colors": [Color("#ffe39a"), Color("#ff4a12")], "palette": [Color("#fff1a8"), Color("#ffb03a"), Color("#ff5a1a"), Color("#e8261a")], "info": "Embers rising and drifting from a burn"},
	"ash": {"tex": "square", "amount": 16, "life": 1.4, "speed": [30, 100], "spread": 180, "gravity": 60, "damping": 40, "scale": [0.2, 0.4], "spin": 360, "colors": [Color("#9a928a"), Color(0.15, 0.14, 0.13, 0.0)], "info": "Flakes of ash drifting down"},
	"ice_chips": {"tex": "shard", "amount": 12, "life": 0.6, "speed": [140, 300], "spread": 70, "gravity": 900, "scale": [0.3, 0.6], "spin": 540, "colors": [Color("#f2fdff"), Color("#6fc8ff")], "info": "Chips of ice breaking off"},
	"snowflakes": {"tex": "flake", "amount": 14, "life": 1.2, "speed": [30, 110], "spread": 180, "gravity": 60, "damping": 50, "scale": [0.3, 0.55], "spin": 180, "colors": [Color("#ffffff"), Color("#a8dcff")], "info": "Snowflakes spinning out and drifting"},
	"frost_mist": {"tex": "soft", "amount": 12, "life": 0.9, "speed": [30, 90], "spread": 180, "damping": 30, "scale": [1.2, 2.0], "grow": true, "add": true, "colors": [Color(0.8, 0.95, 1.0, 0.7), Color(0.4, 0.75, 1.0, 0.0)], "info": "A cold mist breathed out"},
	"electric_sparks": {"tex": "spark", "amount": 20, "life": 0.4, "speed": [200, 420], "spread": 180, "damping": 120, "scale": [0.3, 0.7], "add": true, "along": true, "colors": [Color("#ffffff"), Color("#7fd2ff")], "info": "Crackling sparks of electricity"},
	"static_flicker": {"tex": "dot", "amount": 24, "life": 0.4, "speed": [40, 120], "spread": 180, "damping": 40, "scale": [0.08, 0.18], "add": true, "flicker": true, "colors": [Color("#f6f4ff"), Color("#8a7dff")], "info": "Specks of static flickering about"},
	"poison_droplets": {"tex": "dot", "amount": 14, "life": 0.8, "speed": [80, 200], "spread": 50, "gravity": 600, "scale": [0.25, 0.55], "up": true, "colors": [Color("#d9ff7a"), Color("#4f9a1a")], "info": "Poison spattering up and falling"},
	"acid_bubbles": {"tex": "ring", "amount": 12, "life": 1.0, "speed": [30, 90], "spread": 50, "gravity": -80, "scale": [0.2, 0.45], "grow": true, "up": true, "colors": [Color("#efffb0"), Color(0.5, 0.85, 0.2, 0.0)], "info": "Bubbles of acid rising and popping"},
	"void_motes": {"tex": "dot", "amount": 16, "life": 0.9, "speed": [60, 140], "spread": 180, "damping": 20, "radial": -260, "swirl": 220, "scale": [0.12, 0.3], "add": true, "colors": [Color("#ffd2ff"), Color("#7a2cff")], "info": "Motes of void pulled back into the wound, swirling"},
	"shadow_wisps": {"tex": "soft", "amount": 12, "life": 1.0, "speed": [40, 110], "spread": 60, "gravity": -60, "swirl": 120, "scale": [0.8, 1.4], "up": true, "colors": [Color(0.2, 0.05, 0.25, 0.9), Color(0.05, 0.0, 0.08, 0.0)], "info": "Wisps of shadow curling away"},
	"holy_motes": {"tex": "star", "amount": 14, "life": 1.0, "speed": [30, 120], "spread": 180, "gravity": -50, "damping": 20, "scale": [0.25, 0.5], "spin": 90, "add": true, "colors": [Color("#fffbe8"), Color("#ffd35a")], "palette": [Color("#ffffff"), Color("#fff1b0"), Color("#ffd35a")], "info": "Little stars of light rising"},
	"feathers": {"tex": "feather", "amount": 8, "life": 1.4, "speed": [60, 160], "spread": 120, "gravity": 120, "damping": 60, "scale": [0.45, 0.8], "spin": 240, "colors": [Color("#ffffff"), Color("#c8c2b8")], "info": "Feathers knocked loose, drifting down"},
	"leaves": {"tex": "leaf", "amount": 10, "life": 1.3, "speed": [60, 180], "spread": 120, "gravity": 160, "damping": 50, "scale": [0.45, 0.8], "spin": 300, "colors": [Color("#9fe05a"), Color("#3e7a22")], "palette": [Color("#9fe05a"), Color("#5aa83a"), Color("#d8e05a"), Color("#e09a3a")], "info": "Leaves torn off a plant creature"},
	"petals": {"tex": "leaf", "amount": 12, "life": 1.4, "speed": [50, 150], "spread": 150, "gravity": 90, "damping": 50, "scale": [0.3, 0.5], "spin": 300, "colors": [Color("#ffd6ea"), Color("#ff7ab8")], "palette": [Color("#ffd6ea"), Color("#ff7ab8"), Color("#ffffff"), Color("#ffe07a")], "info": "Petals scattering"},
	"slime_blobs": {"tex": "dot", "amount": 8, "life": 0.8, "speed": [100, 240], "spread": 60, "gravity": 900, "scale": [0.5, 1.0], "up": true, "info": "Blobs of slime flung off"},
	"water_droplets": {"tex": "dot", "amount": 18, "life": 0.7, "speed": [120, 300], "spread": 50, "gravity": 900, "scale": [0.15, 0.35], "up": true, "colors": [Color("#e8fbff"), Color("#3aa8ff")], "info": "Droplets of water splashing up"},
	"crystal_shards": {"tex": "shard", "amount": 12, "life": 0.8, "speed": [120, 280], "spread": 90, "gravity": 500, "scale": [0.3, 0.6], "spin": 600, "add": true, "palette": [Color("#8ff4ff"), Color("#b78cff"), Color("#ff9ae0")], "info": "Glowing crystal shards breaking off a crystal creature"},
	"soul_orbs": {"tex": "soft", "amount": 7, "life": 1.2, "speed": [30, 80], "spread": 60, "gravity": -100, "scale": [0.6, 1.0], "up": true, "add": true, "colors": [Color("#e6fffb"), Color("#3fe8c8")], "info": "Orbs of soul light rising out"},
	"rock_debris": {"tex": "square", "amount": 12, "life": 0.8, "speed": [120, 300], "spread": 70, "gravity": 1100, "scale": [0.25, 0.6], "spin": 540, "colors": [Color("#a89a88"), Color("#5a5048")], "palette": [Color("#a89a88"), Color("#7a6e62"), Color("#c4b8a4")], "info": "Bits of rock knocked off a stone creature"},
	"sand_spray": {"tex": "dot", "amount": 30, "life": 0.6, "speed": [80, 220], "spread": 50, "gravity": 700, "scale": [0.06, 0.14], "colors": [Color("#f0d9a0"), Color("#b8945a")], "info": "A spray of sand"},
	"star_burst": {"tex": "star", "amount": 10, "life": 0.5, "speed": [120, 260], "spread": 180, "damping": 300, "scale": [0.3, 0.6], "spin": 360, "add": true, "palette": [Color("#fff27a"), Color("#ff9ad8"), Color("#8ae8ff")], "info": "Stars knocked out of the one hit, cartoon-style"},
	"heart_shards": {"tex": "shard", "amount": 6, "life": 0.9, "speed": [100, 200], "spread": 60, "gravity": 800, "scale": [0.35, 0.6], "spin": 360, "up": true, "info": "Shards of a lost heart (a mask of health) breaking off"},
}
## The particles of a hit by its damage type (see [method particles_for]).
const BY_TYPE := {
	"fire": "embers", "ice": "ice_chips", "shock": "electric_sparks", "lightning": "electric_sparks",
	"poison": "poison_droplets", "acid": "acid_bubbles", "void": "void_motes", "holy": "holy_motes",
	"light": "holy_motes", "wind": "leaves", "water": "water_droplets", "shadow": "shadow_wisps",
	"dark": "shadow_wisps", "soul": "soul_orbs", "earth": "rock_debris",
}

## Palettes of your own, by kind: id -> colors (each particle one of them; one color: all of it).
static var palettes: Dictionary = {}
## How strongly kinds glow, of your own: id -> strength (0 none, 1 glowing, more brighter).
static var glows: Dictionary = {}

## Which particles (an id of [constant PARTICLES]).
var particles := ""
## Whose colors they take (the one hurt).
var team: MDSAttackFX.Team = MDSAttackFX.Team.ENEMY
var _left := 1.0

static var _textures: Dictionary = {}

## Bursts particles [param id] at [param at] (global) under [param parent], flying the way
## [param direction] goes (the way the blow went; spread round it), in [param p_team]'s colors
## (the one hurt) or [param colors] ([color, fade-to color]; see [method MDSAttackFX.colors_for]),
## [param size] times as big; [param palette] several colors, each particle one of them (one: all
## that color); [param glow] how strongly they glow (less than 0: as they would, see
## [method glow_for]). Returns them (null: no such particles, or no parent).
static func burst(id: String, parent: Node, at: Vector2, direction := Vector2.UP, p_team: MDSAttackFX.Team = MDSAttackFX.Team.ENEMY, colors: Array = [], size := 1.0, palette := PackedColorArray(), glow := -1.0) -> MDSHitParticles:
	if not PARTICLES.has(id):
		push_warning("MDSHitParticles: no particles '%s' (%s)." % [id, ", ".join(PARTICLES.keys())])
		return null
	if not is_instance_valid(parent):
		return null
	var p := MDSHitParticles.new()
	p.setup(id, p_team, colors, size, direction, palette, glow)
	parent.add_child(p)
	p.global_position = at
	p.restart()
	return p

## Makes these particles [param id] (see [method burst]); they burst once in the tree.
func setup(id: String, p_team: MDSAttackFX.Team = MDSAttackFX.Team.ENEMY, colors: Array = [], size := 1.0, way := Vector2.UP, palette := PackedColorArray(), glow := -1.0) -> void:
	var s: Dictionary = PARTICLES[id]
	particles = id
	team = p_team
	name = "Particles_" + id
	z_index = 41
	one_shot = true
	explosiveness = 0.92
	randomness = 0.3
	local_coords = false
	amount = int(s.amount)
	lifetime = float(s.life)
	_left = lifetime * 1.4 + 0.1
	texture = texture_for(str(s.tex))
	var dir := way.normalized() if way.length() > 0.001 else Vector2.UP
	if s.get("up", false):
		# Thrown upward, leaning the way the blow went.
		dir = (Vector2.UP * 1.5 + Vector2(dir.x, 0.0)).normalized()
	direction = dir
	spread = float(s.spread)
	initial_velocity_min = float(s.speed[0]) * size
	initial_velocity_max = float(s.speed[1]) * size
	gravity = Vector2(0, float(s.get("gravity", 0)))
	damping_min = float(s.get("damping", 0)) * 0.6
	damping_max = float(s.get("damping", 0))
	scale_amount_min = float(s.scale[0]) * size * SIZE
	scale_amount_max = float(s.scale[1]) * size * SIZE
	var spin := float(s.get("spin", 0))
	angular_velocity_min = -spin
	angular_velocity_max = spin
	angle_min = 0.0 if s.get("along", false) else -180.0
	angle_max = 0.0 if s.get("along", false) else 180.0
	particle_flag_align_y = bool(s.get("along", false))
	radial_accel_min = float(s.get("radial", 0)) * 0.7
	radial_accel_max = float(s.get("radial", 0))
	tangential_accel_min = float(s.get("swirl", 0)) * 0.6
	tangential_accel_max = float(s.get("swirl", 0))
	emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 6.0 * size
	var curve := Curve.new()
	if s.get("grow", false):
		curve.add_point(Vector2(0.0, 0.5))
		curve.add_point(Vector2(1.0, 1.0))
	else:
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(0.7, 0.85))
		curve.add_point(Vector2(1.0, 0.2))
	scale_amount_curve = curve
	var c := MDSAttackFX.colors_for(id, p_team, s.get("colors", []), colors)
	color_ramp = _ramp(c[0], c[1], bool(s.get("flicker", false)))
	var given := colors.any(func(k: Variant) -> bool: return k is Color and (k as Color).a > 0.0)
	var pal := palette_for(id, palette, given)
	if not pal.is_empty():
		set_palette(pal)
	set_glow(glow_for(id, glow))
	emitting = false

## Sets their colors ([param from], fading to [param to]), for the next burst.
func set_colors(from: Color, to: Color) -> void:
	color_initial_ramp = null
	color_ramp = _ramp(from, to, bool(PARTICLES.get(particles, {}).get("flicker", false)))

## Sets their colors to [param colors]: each particle one of them, picked at random (one color: all
## of it), fading out.
func set_palette(colors: PackedColorArray) -> void:
	var flicker := bool(PARTICLES.get(particles, {}).get("flicker", false))
	if colors.size() == 1:
		set_colors(colors[0], colors[0].darkened(0.3))
		return
	if colors.is_empty():
		return
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.set_color(0, colors[0])
	g.set_offset(0, 0.0)
	g.set_color(1, colors[colors.size() - 1])
	g.set_offset(1, (colors.size() - 1.0) / colors.size())
	for i in range(1, colors.size() - 1):
		g.add_point(float(i) / colors.size(), colors[i])
	color_initial_ramp = g
	# Their own color all their life, fading out at the end.
	color_ramp = _ramp(Color.WHITE, Color(0.85, 0.85, 0.85), flicker)

## How strongly they glow: 0 not at all (drawn over what is behind), 1 glowing (added to it), more
## brighter still.
func set_glow(strength: float) -> void:
	if strength <= 0.0:
		material = null
		color = Color.WHITE
		return
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	var b := 1.0 + maxf(strength - 1.0, 0.0) * 0.8
	color = Color(b, b, b, clampf(strength, 0.0, 1.0))

## The palette particles [param id] burst in: [param palette] if given, else none when
## [param colors_given] (one burst's colors, they win), else [member palettes]' for it, else none
## when [member MDSAttackFX.effect_colors] has its colors, else the kind's own, else none (one
## color, see [method MDSAttackFX.colors_for]).
static func palette_for(id: String, palette := PackedColorArray(), colors_given := false) -> PackedColorArray:
	if not palette.is_empty():
		return palette
	if colors_given:
		return PackedColorArray()
	if palettes.has(id):
		return PackedColorArray(palettes[id])
	if MDSAttackFX.effect_colors.has(id):
		return PackedColorArray()
	return PackedColorArray(PARTICLES.get(id, {}).get("palette", []))

## How strongly particles [param id] glow: [param strength] if 0 or more, else [member glows]' for
## it, else 1 for the kinds that glow (embers, sparks, motes...) and 0 for the rest; times the
## Project Settings' fx/particle_glow.
static func glow_for(id: String, strength := -1.0) -> float:
	var g := strength
	if g < 0.0:
		g = float(glows[id]) if glows.has(id) else (1.0 if PARTICLES.get(id, {}).get("add", false) else 0.0)
	return g * float(MDSGameplaySetup.setting("fx/particle_glow", 1.0))

func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()

## A particle's colors over its life: [param from], to [param to], gone at the end (blinking on
## and off with [param flicker]).
static func _ramp(from: Color, to: Color, flicker: bool) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, Color(to, 0.0))
	if flicker:
		for k in 6:
			var t := 0.1 + k * 0.14
			g.add_point(t, Color(from, 1.0 if k % 2 == 0 else 0.15).lerp(Color(to, 0.0), t * 0.5))
	else:
		# Most of the way there, still showing; gone only at the end.
		g.add_point(0.6, Color(from.lerp(to, 0.7), from.a * 0.85))
	return g

# --- Played by themselves ------------------------------------------------------------------------

## Whether they fly by themselves (the kit's [code]feel/hurt_particles[/code] setting).
static func enabled() -> bool:
	return bool(MDSGameplaySetup.setting(SETTING, true))

## The particles of hit [param info] on [param hurtbox] with [param attack]: the attack's own
## [member MDSAttackData.hit_particles], else the hurtbox's [member MDSHurtbox.hurt_particles],
## else by the damage type ([constant BY_TYPE]), else a plain blow's: sparks off armour for a
## heavy one (3 or more), drops of the player's or an enemy's color for the rest. "" for none.
static func particles_for(info: MDSDamageInfo, hurtbox: MDSHurtbox = null, attack: MDSAttackData = null) -> String:
	if attack and not attack.hit_particles.is_empty():
		return "" if attack.hit_particles == "none" else attack.hit_particles
	if hurtbox and not hurtbox.hurt_particles.is_empty():
		return "" if hurtbox.hurt_particles == "none" else hurtbox.hurt_particles
	if not info:
		return ""
	var t := info.damage_type.to_lower()
	if BY_TYPE.has(t):
		return BY_TYPE[t]
	if t == "environment":
		return ""
	if info.amount >= 3:
		return "sparks"
	return "blood_spray" if hurtbox and hurtbox.team == MDSHurtbox.Team.PLAYER else "ink_drops"

## Hit [param info] of [param hitbox] landed on [param target] ([param hurtbox], where): its
## particles fly off the target the way the blow went, in the target's colors (its hurtbox's own,
## the attack's, else its team's).
static func on_hurt(hitbox: MDSHitbox, target: Node, info: MDSDamageInfo, hurtbox: MDSHurtbox = null) -> MDSHitParticles:
	if not enabled() or not is_instance_valid(hitbox) or not hitbox.is_inside_tree():
		return null
	var body := target as Node2D
	if not body or not body.is_inside_tree():
		return null
	var id := particles_for(info, hurtbox, hitbox.attack)
	if id.is_empty():
		return null
	var from := info.origin if info and info.origin != Vector2.INF else hitbox.global_position
	var way := body.global_position - from
	way = Vector2(signf(way.x) if absf(way.x) > 0.5 else 0.0, -0.35)
	var p_team := MDSAttackFX.Team.PLAYER if hurtbox and hurtbox.team == MDSHurtbox.Team.PLAYER else MDSAttackFX.Team.ENEMY
	var attack := hitbox.attack
	var colors: Array = MDSAttackFX.attack_colors(attack)
	var palette := attack.particle_palette if attack else PackedColorArray()
	var glow := attack.particle_glow if attack else -1.0
	if hurtbox:
		# The hurt one's own win over the attack's.
		if hurtbox.particle_color.a > 0.0:
			colors = [hurtbox.particle_color, colors[1] if colors.size() > 1 else Color(0, 0, 0, 0)]
		if hurtbox.particle_fade.a > 0.0:
			colors = [colors[0] if not colors.is_empty() else Color(0, 0, 0, 0), hurtbox.particle_fade]
		if not hurtbox.particle_palette.is_empty():
			palette = hurtbox.particle_palette
		elif hurtbox.particle_color.a > 0.0:
			palette = PackedColorArray()
		if hurtbox.particle_glow >= 0.0:
			glow = hurtbox.particle_glow
	var at := hitbox.global_position.lerp(body.global_position, 0.7)
	var parent: Node = body.get_parent() if body.get_parent() else body
	return burst(id, parent, at, way, p_team, colors, 1.0, palette, glow)

# --- Textures --------------------------------------------------------------------------------------

## The white texture of a particle's shape (see [constant PARTICLES]' tex), drawn once.
static func texture_for(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var size := Vector2i(16, 16)
	match kind:
		"spark", "feather":
			size = Vector2i(6, 18)
		"shard":
			size = Vector2i(8, 16)
		"leaf":
			size = Vector2i(10, 14)
		"square":
			size = Vector2i(8, 8)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var mid := Vector2(size) * 0.5
	for y in size.y:
		for x in size.x:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - mid) / mid
			var a := 0.0
			match kind:
				"dot":
					a = clampf((1.0 - p.length()) * 6.0, 0.0, 1.0)
				"soft":
					a = clampf(exp(-p.length_squared() * 3.0) - 0.05, 0.0, 1.0)
				"spark":
					a = clampf(1.0 - absf(p.x) * 1.2, 0.0, 1.0) * clampf(1.0 - absf(p.y), 0.0, 1.0) * 1.6
				"shard":
					a = 1.0 if absf(p.x) + absf(p.y) * 0.9 < 0.95 else 0.0
				"square":
					a = 1.0
				"ring":
					a = clampf(1.0 - absf(p.length() - 0.75) * 7.0, 0.0, 1.0)
				"star":
					var arm := minf(absf(p.x), absf(p.y))
					a = clampf((0.22 - arm) * 8.0 * (1.0 - p.length()), 0.0, 1.0) + clampf((0.35 - p.length()) * 5.0, 0.0, 1.0)
				"flake":
					var d := minf(minf(absf(p.x), absf(p.y)), minf(absf(p.x - p.y), absf(p.x + p.y)) * 0.7071)
					a = clampf((0.14 - d) * 10.0, 0.0, 1.0) * float(p.length() < 0.95)
				"leaf":
					a = 1.0 if (p.x * p.x) / maxf(0.0001, 1.0 - absf(p.y)) + p.y * p.y * 0.2 < 0.75 else 0.0
				"feather":
					var vane := 1.0 if p.x * p.x / maxf(0.0001, 1.0 - p.y * p.y) < 0.8 else 0.0
					a = maxf(vane * 0.8, 1.0 if absf(p.x) < 0.12 else 0.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_textures[kind] = tex
	return tex
