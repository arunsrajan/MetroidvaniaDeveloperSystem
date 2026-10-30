@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_attack_data.svg")
class_name MDSAttackData
extends Resource
## One attack: its damage, its timing in frames at 60 fps (startup, then the hitbox is active,
## then recovery) and what it can follow into ([member cancel_into]: attack ids, for combos).
## [member breaks] lists the [MDSBreakable] kinds it breaks ([code]wall[/code],
## [code]cracked_floor[/code], [code]reinforced[/code]...).

enum Direction { FORWARD, UP, DOWN }

@export var id := "slash"
@export var damage := 1
## physical, fire, ice, shock, void, environment (or any name resistances use).
@export var damage_type := "physical"
## Push given to what it hits: x away from the attacker, y up (negative).
@export var knockback := Vector2(220, -140)
## How long the game freezes when it lands (ms; see the hit-stop feel setting).
@export var hitstop_ms := 60
@export var startup_frames := 3
@export var active_frames := 5
@export var recovery_frames := 10
## Attacks it can be cancelled into during its recovery, for combos.
@export var cancel_into: PackedStringArray = []
## Breakable kinds it breaks.
@export var breaks: PackedStringArray = ["wall"]
@export var direction: Direction = Direction.FORWARD
## The hitbox, from the attacker's middle, facing right (mirrored when facing left).
@export var hitbox_size := Vector2(56, 40)
@export var hitbox_offset := Vector2(40, 0)
## Mana it costs (spells).
@export var mana_cost := 0
## Fired as well as the hitbox (spells, sub-weapons): an [MDSProjectile] scene.
@export var projectile: PackedScene
## Hits each target once per swing.
@export var one_hit_per_target := true
## The effect played as it swings (an [constant MDSAttackFX.EFFECTS] id): empty picks one by how
## it goes ([method MDSAttackFX.swing_for]), "none" plays none.
@export var swing_fx := ""
## The effect played where it hits: empty picks one by its damage type
## ([method MDSAttackFX.hit_for]), "none" plays none.
@export var hit_fx := ""
## The hot middle of its effects and particles (transparent: the team's, or the effect's own; see
## [method MDSAttackFX.colors_for])...
@export var fx_color := Color(0, 0, 0, 0)
## ...and the light round it.
@export var fx_glow := Color(0, 0, 0, 0)
## How strongly its effects glow (their shaders' intensity: 1 as they are).
@export_range(0.0, 4.0, 0.05) var fx_intensity := 1.0
## The particles flying off what it hurts ([constant MDSHitParticles.PARTICLES]): empty, the hurt
## one's own or picked by the damage type ([method MDSHitParticles.particles_for]); "none", none.
@export var hit_particles := ""
## Their colors: each particle one of them, picked at random (one: all of it; empty: as they
## would be). A hurtbox's own win.
@export var particle_palette := PackedColorArray()
## How strongly they glow: 0 not at all, 1 glowing, more brighter; less than 0, as they would.
@export_range(-1.0, 3.0, 0.05) var particle_glow := -1.0

func startup_time() -> float:
	return startup_frames / 60.0

func active_time() -> float:
	return active_frames / 60.0

func recovery_time() -> float:
	return recovery_frames / 60.0

func total_time() -> float:
	return (startup_frames + active_frames + recovery_frames) / 60.0

## An attack of [param p_damage] (for code and tests).
static func make(p_id: String, p_damage := 1, p_breaks: PackedStringArray = ["wall"]) -> MDSAttackData:
	var a := MDSAttackData.new()
	a.id = p_id
	a.damage = p_damage
	a.breaks = p_breaks
	return a
