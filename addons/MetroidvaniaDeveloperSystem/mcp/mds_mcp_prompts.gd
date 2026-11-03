@tool
class_name MDSMcpPrompts
extends RefCounted
## The MCP prompts: ways of working the user can pick from the client, each walking an agent
## through the tools.

const PROMPTS := {
	"build_area": {
		"description": "Build a new area: tileset, rooms, gates, caves, checks, game scene",
		"arguments": [["theme", true, "What it looks and feels like"], ["rooms", true, "How many rooms"], ["style", false, "cave, linear, outdoor or arena"], ["world", false, "World file"]],
		"text": """Build a Metroidvania area with the mds_ tools. Theme: {theme}. Rooms: {rooms}. Style: {style}. World: {world}.

1. mds_status, then mds_world_list. Use the world given, or make one with mds_world_create.
2. mds_tileset_create if the world has no room_tileset, and set it with mds_world_update.
3. mds_area_set with a title and color that fit the theme.
4. mds_area_generate (try dry_run first) for the rooms and doors, or mds_room_add, mds_gate_add and mds_gate_connect in an mds_batch to lay them out by hand.
5. mds_area_generate_caves with a fixed seed. Look at a room or two with mds_room_ascii or mds_room_preview.
6. mds_validate and mds_room_check. Fix what they report.
7. mds_game_scene_create, once the area works. Report what was built and what still needs a person's eye.""",
	},
	"add_encounter": {
		"description": "Put enemies in a room, with their hits and hurts set",
		"arguments": [["room", true, "Room id"], ["difficulty", false, "easy, normal or hard"], ["element", false, "A damage type"]],
		"text": """Add an encounter to room {room}. Difficulty: {difficulty}. Element: {element}.

1. mds_room_ascii to see the room, and mds_catalog for enemy_templates, damage_types and hit_particles.
2. mds_room_place the enemies on open floor (pos in scene pixels), then mds_room_fit_objects with mode floor.
3. mds_enemy_configure each: damage_type, attack_color, attack_glow, hurt_particles, particle_palette. Keep the colors of one encounter related.
4. mds_room_check on the room. Report what you placed.""",
	},
	"gated_progression": {
		"description": "Lock a route behind an ability, and check the world still works",
		"arguments": [["ability", true, "The ability"], ["area", false, "Where to use it"]],
		"text": """Gate progression with the ability {ability}, in area {area}.

1. mds_analysis kind progression, to see what is reached now.
2. Pick doors worth locking, with an alternative route to where {ability} is found. mds_gate_update or mds_gate_connect with requires: ["{ability}"].
3. Make sure a room grants it (mds_room_update can't set this: say so if none does).
4. mds_analysis kinds progression and backtracking, then mds_validate. Nothing should be locked forever. Report what opens up when.""",
	},
	"audit_world": {
		"description": "Check a world and propose fixes, changing nothing",
		"arguments": [["world", false, "World file"]],
		"text": """Audit world {world}. Do not change anything.

1. mds_validate, every page.
2. mds_room_check on all rooms with scenes.
3. mds_analysis kinds progression and backtracking.
4. Report the problems by importance, each with the room it concerns and the fix you propose, then ask which to make.""",
	},
	"combat_fx_pass": {
		"description": "Give an area's enemies a consistent look when they hit and hurt",
		"arguments": [["area", true, "The area"], ["palette", false, "Colors to use"]],
		"text": """Give the enemies of area {area} a consistent combat look. Palette: {palette}.

1. mds_world_get for the area's rooms, mds_room_items in each for its enemies.
2. mds_catalog for attack_fx, damage_types and hit_particles.
3. In one mds_batch, mds_enemy_configure every enemy: related damage_type, attack_color and attack_glow, hurt_particles and particle_palette for what each is made of.
4. Report what each kind of enemy now has. How it looks can only be judged by playing it, so say so.""",
	},
}

func list() -> Array:
	var out := []
	for prompt_name: String in PROMPTS:
		var p: Dictionary = PROMPTS[prompt_name]
		var arguments := []
		for a: Array in p.arguments:
			arguments.append({"name": a[0], "required": a[1], "description": a[2]})
		out.append({"name": prompt_name, "description": p.description, "arguments": arguments})
	return out

## The prompt with its arguments filled in, or {_rpc_error}.
func get_prompt(prompt_name: String, arguments: Variant) -> Dictionary:
	if not PROMPTS.has(prompt_name):
		return {"_rpc_error": "Unknown prompt: %s" % prompt_name}
	var args: Dictionary = arguments if arguments is Dictionary else {}
	var p: Dictionary = PROMPTS[prompt_name]
	var values := {}
	for a: Array in p.arguments:
		if a[1] and not args.has(a[0]):
			return {"_rpc_error": "Prompt %s needs %s." % [prompt_name, a[0]]}
		values[a[0]] = str(args.get(a[0], "(not given: choose, or ask)"))
	return {"description": p.description, "messages": [{"role": "user", "content": {"type": "text", "text": str(p.text).format(values)}}]}
