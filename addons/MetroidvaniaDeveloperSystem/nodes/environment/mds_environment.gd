@tool
class_name MDSEnvironment
extends RefCounted
## The environment effects ([MDSEnvironmentEffect]) and weather presets, and the weather of
## areas and rooms.
##
## Weather is written as a comma-separated list of:
## - effects, by id ([constant EFFECTS]): [code]rain[/code], [code]fog[/code], with settings in
##   parentheses if you like: [code]rain(angle=-20, density=0.8)[/code],
##   [code]dust_storm(blows_toward=left)[/code], [code]fog(color=#3a4350)[/code];
## - presets ([constant PRESETS]): [code]storm[/code], [code]sandstorm[/code],
##   [code]blizzard[/code]...;
## - scenes of effect nodes: [code]res://weather/my_storm.tscn[/code] (effects in it with
##   [member MDSEnvironmentEffect.fit_room] are sized to the room).
## [code]none[/code] means no weather.
##
## In the world file, an area's weather ([code]areas[name].weather[/code], set in the Areas
## tab) covers every room of the area; a room's ([code]rooms[id].weather[/code], Inspect tab)
## replaces it ([code]none[/code]: a room under cover); the world setting [code]weather[/code]
## is the default. [MDSWorldGame] adds it to each room as the room loads:
## [codeblock]
## var spec := MDSEnvironment.spec_for_room(world, "Karak_03")   # "sandstorm"
## var weather := MDSEnvironment.build(spec, room_rect)
## room.add_child(weather)
## [/codeblock]

const SCRIPT_DIR := "res://addons/MetroidvaniaDeveloperSystem/nodes/environment/"
const ICON_DIR := "res://addons/MetroidvaniaDeveloperSystem/assets/environment/"
## Name of the node [method build] makes.
const NODE_NAME := "MDSWeather"
## How far (px) room-wide effects reach past the room's edges, so their soft edges stay out of
## sight.
const ROOM_MARGIN := 192.0

## id -> [name, script, covers a whole room well, what it is]. In palette order.
const EFFECTS := {
	"dust_storm": ["Dust storm", "mds_dust_storm.gd", true, "Banks of dust blown from one side in gusts, grit and motes driven along; the wind shoves the player downwind"],
	"rain": ["Rain", "mds_rain.gd", true, "Slanting rain at three depths, splashes along the ground and a low mist"],
	"lightning": ["Lightning", "mds_lightning.gd", true, "Forked bolts behind the terrain, the sky flashing, thunder"],
	"snow": ["Snowfall", "mds_snowfall.gd", true, "Soft flakes drifting down; turn up Blizzard for driven snow"],
	"fog": ["Fog / mist", "mds_fog.gd", true, "Drifting fog, or mist lying along the ground"],
	"embers": ["Embers / ash", "mds_embers.gd", true, "Embers rising and flickering out, ash drifting down, or sparks"],
	"fireflies": ["Fireflies / spores", "mds_fireflies.gd", true, "Glowing motes wandering and blinking: fireflies, spores, glitter"],
	"leaves": ["Falling leaves", "mds_falling_leaves.gd", true, "Leaves or petals tumbling down on the breeze"],
	"light_shafts": ["Light shafts", "mds_light_shafts.gd", true, "God rays slanting down from above, dust motes in them"],
	"heat_haze": ["Heat haze", "mds_heat_haze.gd", true, "Everything behind it shimmers, rippling upward"],
	"steam_vent": ["Steam vent", "mds_steam_vent.gd", false, "A vent forcing out hot steam: wisps, a warning glow, then a jet that throws and scalds"],
	"lava": ["Lava pool", "mds_lava.gd", false, "Molten rock (or acid, cursed ooze) with crust, bubbles, a glow and embers; it hurts"],
	"waterfall": ["Waterfall", "mds_waterfall.gd", false, "A sheet of falling water, white water at its lip and foot, mist"],
	"water": ["Water", "mds_water.gd", false, "A pool: waves, what is behind bent and tinted, caustics, bubbles"],
}

## id -> [name, what it is, its weather]. In menu order.
const PRESETS := {
	"sandstorm": ["Sandstorm", "A dust storm blowing toward the right over a low haze of sand", "dust_storm(blows_toward=right), fog(color=#a39a88, density=0.35, ground=0.7, drift=60)"],
	"sandstorm_left": ["Sandstorm, blowing left", "A dust storm blowing toward the left over a low haze of sand", "dust_storm(blows_toward=left), fog(color=#a39a88, density=0.35, ground=0.7, drift=-60)"],
	"storm": ["Thunderstorm", "Heavy slanting rain, lightning and a dark mist", "rain(density=0.85, angle=16, mist=0.35), lightning, fog(color=#3a4350, density=0.3)"],
	"drizzle": ["Drizzle", "Light rain and mist", "rain(density=0.3, fall_speed=850, drop_length=24, splashes=0.3, mist=0.3)"],
	"blizzard": ["Blizzard", "Driven snow and a white-out haze", "snow(blizzard=0.8, wind=140, density=0.75), fog(color=#e6edf5, density=0.4, drift=90)"],
	"snowfall": ["Snowfall", "Gentle snow", "snow"],
	"volcanic": ["Volcanic", "Embers rising, ash falling, heat haze and a red smoky haze", "embers, embers(kind=ash, density=0.3), heat_haze(strength=2.5, rise=0.8), fog(color=#5a2a1e, density=0.3, ground=0.5)"],
	"ashfall": ["Ashfall", "Ash drifting down through a grey haze", "embers(kind=ash, density=0.6), fog(color=#5b5b60, density=0.35)"],
	"cave_mist": ["Cave mist", "Mist along the floor, shafts of light from above", "fog(ground=1, density=0.6, drift=10), light_shafts(color=Color(0.75, 0.9, 1.0, 0.45))"],
	"firefly_grove": ["Firefly grove", "Fireflies, soft light and a little mist", "fireflies, light_shafts(color=Color(0.85, 1.0, 0.7, 0.35), motes=0.6), fog(ground=1, density=0.3, color=#7fa58a)"],
	"spore_cavern": ["Spore cavern", "Teal spores drifting slowly in a green haze", "fireflies(color=#5fe8d0, color_b=#a6ffcf, speed=0.4, blink=0.3, density=0.5), fog(color=#2f6b5a, density=0.35)"],
	"autumn": ["Autumn wind", "Leaves tumbling down on a breeze", "leaves"],
	"petals": ["Petals", "Pink petals drifting down", "leaves(color_a=#f2a7c3, color_b=#e57fa8, color_c=#fbd3e0, leaf_size=6, fall_speed=40)"],
	"glitter": ["Glitter", "Pink and white glitter twinkling in the air (a stage, a fairy grove)", "fireflies(color=#ffb3d1, color_b=#ffffff, mote_size=1.4, glow_radius=5, spacing=60, density=0.5, blink=1)"],
}

# --- The catalog -------------------------------------------------------------------------------

static func effect_ids() -> PackedStringArray:
	return PackedStringArray(EFFECTS.keys())

## Effects that cover a whole room well (weather), for area and room weather.
static func ambient_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for id in EFFECTS:
		if EFFECTS[id][2]:
			out.append(id)
	return out

static func preset_ids() -> PackedStringArray:
	return PackedStringArray(PRESETS.keys())

## "Dust storm", "Thunderstorm" (effects and presets), else the id itself.
static func display_name(id: String) -> String:
	if EFFECTS.has(id):
		return EFFECTS[id][0]
	if PRESETS.has(id):
		return PRESETS[id][0]
	return id

static func describe(id: String) -> String:
	if EFFECTS.has(id):
		return EFFECTS[id][3]
	if PRESETS.has(id):
		return "%s: %s" % [PRESETS[id][1], PRESETS[id][2]]
	return ""

## The effect's icon (presets: a cloud).
static func icon(id: String) -> Texture2D:
	var p := ICON_DIR + (id if EFFECTS.has(id) else "weather") + ".svg"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

## A new effect of [param id] with [param settings] (name -> value, or text such as "0.8",
## "left", "#ff8800"), or null for an unknown id.
static func create(id: String, settings: Dictionary = {}) -> MDSEnvironmentEffect:
	if not EFFECTS.has(id):
		return null
	var script := load(SCRIPT_DIR + EFFECTS[id][1]) as Script
	if not script:
		return null
	var e: MDSEnvironmentEffect = script.new()
	e.name = str(EFFECTS[id][0]).get_slice(" /", 0).to_pascal_case()
	for k in settings:
		if not set_setting(e, k, settings[k]):
			push_warning("MDS weather: %s has no setting '%s' (or '%s' doesn't fit it)." % [id, k, settings[k]])
	return e

## Sets [param key] of [param e] from a value, or from text ("0.8", "true", "left" for an enum,
## "#ff8800" or "Color(1, 0.5, 0)" for a color). Returns false when there is no such setting
## or the text doesn't fit it.
static func set_setting(e: Object, key: String, value: Variant) -> bool:
	for p in e.get_property_list():
		if p.name != key or not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = _coerce(p, value) if value is String else value
		if v == null:
			return false
		e.set(key, type_convert(v, p.type))
		return true
	return false

static func _coerce(p: Dictionary, text: String) -> Variant:
	var s := text.strip_edges()
	if p.hint == PROPERTY_HINT_ENUM:
		var names := String(p.hint_string).split(",")
		var want := s.to_lower().replace(" ", "_")
		for i in names.size():
			var parts := names[i].split(":")
			if parts[0].strip_edges().to_lower().replace(" ", "_") == want:
				return int(parts[1]) if parts.size() > 1 else i
	if p.type == TYPE_COLOR and (s.begins_with("#") or (not s.begins_with("Color") and Color.html_is_valid(s))):
		return Color.html(s)
	if p.type == TYPE_STRING or p.type == TYPE_STRING_NAME:
		return s.trim_prefix("\"").trim_suffix("\"")
	var v: Variant = str_to_var(s)
	if v == null:
		return null
	if typeof(v) == p.type or (p.type == TYPE_FLOAT and v is int) or (p.type == TYPE_INT and v is float) or (p.type == TYPE_BOOL and (v is int or v is bool)):
		return v
	return null

# --- Weather -----------------------------------------------------------------------------------

## Whether [param spec] turns weather off ("none").
static func is_none(spec: String) -> bool:
	return spec.strip_edges().to_lower() == "none"

## The entries of a weather spec, presets expanded: [{effect, settings}], [{scene}], and
## [{unknown}] for what isn't an effect, a preset or a scene.
static func parse(spec: String) -> Array:
	return _parse(spec, 0)

static func _parse(spec: String, depth: int) -> Array:
	var out: Array = []
	for token in split_list(spec):
		var t := token.strip_edges()
		if t.is_empty() or is_none(t):
			continue
		if t.begins_with("res://") or t.begins_with("uid://"):
			out.append({"scene": t})
			continue
		var head := t
		var args := ""
		var open := t.find("(")
		if open > 0 and t.ends_with(")"):
			head = t.substr(0, open)
			args = t.substr(open + 1, t.length() - open - 2)
		var id := head.strip_edges().to_lower().replace(" ", "_")
		if EFFECTS.has(id):
			var settings: Dictionary = {}
			for a in split_list(args):
				var eq := a.find("=")
				if eq > 0:
					settings[a.substr(0, eq).strip_edges()] = a.substr(eq + 1).strip_edges()
			out.append({"effect": id, "settings": settings})
		elif PRESETS.has(id) and depth < 4:
			out.append_array(_parse(PRESETS[id][2], depth + 1))
		else:
			out.append({"unknown": t})
	return out

## Splits [param text] at the commas outside parentheses.
static func split_list(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var depth := 0
	var start := 0
	for i in text.length():
		var c := text[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth = maxi(depth - 1, 0)
		elif c == "," and depth == 0:
			out.append(text.substr(start, i - start))
			start = i + 1
	if start < text.length():
		out.append(text.substr(start))
	return out

## What is wrong with [param spec] ("" when nothing): unknown names, missing scenes.
static func check(spec: String) -> String:
	var problems: PackedStringArray = []
	for e in parse(spec):
		if e.has("unknown"):
			problems.append("'%s' is not an effect or a preset" % e.unknown)
		elif e.has("scene") and not ResourceLoader.exists(_path_of(e.scene)):
			problems.append("%s doesn't exist" % e.scene)
	return "; ".join(problems)

## A short description of [param spec]: "Rain, Lightning, Fog / mist".
static func summary(spec: String) -> String:
	if is_none(spec):
		return "none"
	var names: PackedStringArray = []
	for e in parse(spec):
		if e.has("effect"):
			names.append(display_name(e.effect))
		elif e.has("scene"):
			names.append(str(e.scene).get_file())
	return ", ".join(names)

## The weather of a room: its own ([code]rooms[id].weather[/code]), else its area's, else the
## world's ([code]settings.weather[/code]). "none" when it is turned off, "" when there is none.
static func spec_for_room(world: MDSWorld, id: String) -> String:
	var s := str(world.get_room_value(id, "weather", "")).strip_edges()
	if s.is_empty():
		s = str(world.get_areas().get(world.get_room_area(id), {}).get("weather", "")).strip_edges()
	if s.is_empty():
		s = str(world.get_setting("weather", "")).strip_edges()
	return s

## The weather of [param spec] as a node to add to a room, its effects covering
## [param bounds] (the room's rectangle, in the coordinates of the node it goes in) and
## [constant ROOM_MARGIN] past it. Null when there is no weather.
static func build(spec: String, bounds: Rect2) -> Node2D:
	var entries := parse(spec)
	if entries.is_empty():
		return null
	var area := bounds.grow(ROOM_MARGIN)
	var root := Node2D.new()
	root.name = NODE_NAME
	for e in entries:
		if e.has("effect"):
			var fx := create(e.effect, e.settings)
			if fx:
				fx.fit_room = true
				fx.fit_to(area)
				root.add_child(fx, true)
		elif e.has("scene"):
			var path := _path_of(e.scene)
			var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
			if not packed:
				push_warning("MDS weather: %s doesn't exist or isn't a scene." % e.scene)
				continue
			var inst := packed.instantiate()
			root.add_child(inst, true)
			fit_effects(inst, area, root)
		else:
			push_warning("MDS weather: '%s' is not an effect or a preset (see MDSEnvironment)." % e.unknown)
	if root.get_child_count() == 0:
		root.free()
		return null
	return root

## Moves and sizes the effects under [param node] (itself included) that have
## [member MDSEnvironmentEffect.fit_room] to cover [param rect], given in [param space]'s
## coordinates ([param node] is inside [param space]).
static func fit_effects(node: Node, rect: Rect2, space: Node) -> void:
	for fx in effects_in(node):
		if fx.fit_room:
			fx.fit_to(_to_local(fx.get_parent(), space) * rect)

## Every effect under [param root], [param root] included, in tree order.
static func effects_in(root: Node) -> Array[MDSEnvironmentEffect]:
	var out: Array[MDSEnvironmentEffect] = []
	if not root:
		return out
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MDSEnvironmentEffect:
			out.append(n)
		var children := n.get_children()
		children.reverse()
		stack.append_array(children)
	return out

## The transform from [param space]'s coordinates to [param node]'s.
static func _to_local(node: Node, space: Node) -> Transform2D:
	var xform := Transform2D.IDENTITY
	var n := node
	while n and n != space:
		if n is Node2D:
			xform = (n as Node2D).transform * xform
		n = n.get_parent()
	return xform.affine_inverse()

static func _path_of(scene: String) -> String:
	if scene.begins_with("uid://"):
		var id := ResourceUID.text_to_id(scene)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	return scene
