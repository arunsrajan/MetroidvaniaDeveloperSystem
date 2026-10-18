extends SceneTree
## Writes the Gameplay Kit's ready-made scenes from the code that builds them (run it after
## changing the player's or a template's parts):
##   godot --headless --path . --script res://tests/make_gameplay_scenes.gd
## Not a test (run_all only runs test_*.tscn).

const GAMEPLAY := "res://addons/MetroidvaniaDeveloperSystem/gameplay/"

## The built-in abilities: id, name, input action, description.
const ABILITIES := [
	["double_jump", "Double Jump", "jump", "Jump again in the air.", 0],
	["wall_jump", "Wall Jump", "jump", "Slide down walls by pressing toward them, and jump off them.", 0],
	["dash", "Dash", "dash", "Dash along the ground.", 0],
	["air_dash", "Air Dash", "dash", "Dash in the air too.", 0],
	["slide", "Slide", "dash", "Hold down and dash to slide under low gaps.", 0],
	["ledge_grab", "Ledge Grab", "", "Catch the edges of ledges and climb up onto them.", 0],
	["climb", "Climb", "move_up", "Climb ladders and vines.", 0],
	["swim", "Swim", "move_up", "Swim freely in deep water instead of sinking.", 0],
	["glide", "Glide", "jump", "Hold jump while falling to glide down slowly.", 0],
	["grapple", "Grapple", "grapple", "Hook grapple points and pull yourself to them.", 2],
	["ground_pound", "Ground Pound", "dash", "Hold down and dash in the air to slam down and break cracked floors.", 1],
	["super_attack", "Super Attack", "attack", "Your attacks break reinforced walls.", 1],
	["charge_attack", "Charge Attack", "attack", "Hold attack, then let go for a heavy blow.", 1],
	["parry", "Parry", "attack", "Attack just as a hit lands to block it and stun the attacker.", 1],
]

func _initialize() -> void:
	var ok := true
	for a in ABILITIES:
		var d := MDSAbilityData.new()
		d.id = a[0]
		d.display_name = a[1]
		d.input_action = StringName(a[2])
		d.description = a[3]
		d.category = a[4]
		var path := GAMEPLAY + "data/%s.tres" % a[0]
		var err := ResourceSaver.save(d, path)
		ok = ok and err == OK
		print("  ", path)
	ok = _save(MDSPlayer.build(), GAMEPLAY + "player/mds_player.tscn") and ok
	var theme := MDSGameplayUi.build_theme()
	var theme_err := ResourceSaver.save(theme, GAMEPLAY + "ui/mds_gameplay_theme.tres")
	ok = ok and theme_err == OK
	print("  ", GAMEPLAY + "ui/mds_gameplay_theme.tres")
	for t in _templates():
		ok = _save(t[1], t[0]) and ok
	print("gameplay scenes written" if ok else "some scenes failed")
	quit(0 if ok else 1)

## [scene path, root] of the enemy templates (when their classes exist).
func _templates() -> Array:
	var out: Array = []
	for name in ["walker", "flyer", "turret", "charger", "ambusher"]:
		var script_path := GAMEPLAY + "enemies/templates/mds_%s.gd" % name
		if not ResourceLoader.exists(script_path):
			continue
		var script := load(script_path) as Script
		if not script.has_method("build"):
			continue
		var root: Node = script.call("build")
		out.append([GAMEPLAY + "enemies/templates/mds_%s.tscn" % name, root])
	return out

func _save(root: Node, path: String) -> bool:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("Could not save %s (%d)" % [path, err])
		return false
	print("  ", path)
	return true

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
