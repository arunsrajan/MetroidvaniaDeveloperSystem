extends Node
## The combat demo's player colors, set at runtime as a game of your own might: its effects' colors
## and glow, the particles its blows throw off enemies that have none of their own, and the
## particles it throws off when hurt. A child of the game ([MDSWorldGame]).

## The player's effects: their hot middle...
@export var player_color := Color("#fff4c2")
## ...and the light round them.
@export var player_glow := Color("#ffb020")
## How strongly the player's effects glow.
@export_range(0.0, 4.0, 0.05) var player_intensity := 1.4
## The particles its blows throw off an enemy with no colors of its own: each one of these.
@export var blow_palette := PackedColorArray([Color("#ffe27a"), Color("#ffffff"), Color("#ffa53a")])
@export_range(-1.0, 3.0, 0.05) var blow_glow := 1.2
## How big each of them is (1 as they are).
@export_range(0.1, 4.0, 0.05) var blow_size := 1.0
## What flies off the player when hurt, in these colors, this bright.
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, MDSHitParticles.KINDS) var hurt_particles := "heart_shards"
@export var hurt_palette := PackedColorArray([Color("#ff4a6a"), Color("#ff9ab0"), Color("#ffffff")])
@export_range(-1.0, 3.0, 0.05) var hurt_glow := 1.0
@export_range(0.1, 4.0, 0.05) var hurt_size := 1.3

func _ready() -> void:
	MDSAttackFX.effect_colors["player"] = [player_color, player_glow]
	# After the player has made its attacks.
	_style_player.call_deferred()

func _exit_tree() -> void:
	# The colors are everyone's (static): gone with the game.
	MDSAttackFX.effect_colors.erase("player")

func _style_player() -> void:
	var game := get_parent() as MDSWorldGame
	var player := game.player if game else null
	if not player:
		return
	for n in player.find_children("*", "", true, false):
		if n is MDSAttackController:
			_style_attacks(n)
		elif n is MDSHurtbox:
			var hb := n as MDSHurtbox
			hb.hurt_particles = hurt_particles
			hb.particle_palette = hurt_palette
			hb.particle_glow = hurt_glow
			hb.particle_size = hurt_size

func _style_attacks(c: MDSAttackController) -> void:
	for list in [c.ground_combo, c.air_combo]:
		for i in list.size():
			list[i] = _styled(list[i])
	for key in ["up_attack", "down_attack", "charge_attack", "spell"]:
		var a: MDSAttackData = c.get(key)
		if a:
			c.set(key, _styled(a))

func _styled(attack: MDSAttackData) -> MDSAttackData:
	var a := attack.duplicate() as MDSAttackData
	a.fx_intensity = player_intensity
	a.particle_palette = blow_palette
	a.particle_glow = blow_glow
	a.particle_size = blow_size
	return a
