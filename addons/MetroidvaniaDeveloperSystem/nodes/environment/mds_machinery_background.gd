@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/machinery.svg")
class_name MDSMachineryBackground
extends MDSEnvironmentEffect
## A background of giant machinery, soft and out of focus as if far behind the room: one kind
## of machine at a time ([member machine]), several of them at different depths, turning,
## swinging, pumping and glowing. They move by time alone, and they are fixed in the world: each
## stands at its own place in the room, so the camera pans over them as over the room. Nothing
## the player or anyone else does moves them.
##
## Forty kinds, drawn by two shaders:
## - gothic castle machinery, for Castlevania-style castles ([constant GOTHIC_IDS],
##   shaders/environment/machinery_gothic.gdshader): giant wheels, clockwork, clock faces,
##   pendulums, bells, chandeliers, rose windows, hanging chains, candelabra, winches, spiked
##   rollers, hourglasses, organ pipes, banners, astrolabes, torches, windmills, swinging axes,
##   saw blades and castle spires;
## - alien and space-station machinery, for Metroid-style worlds ([constant SCIFI_IDS],
##   machinery_scifi.gdshader): turbines, reactor cores, gyro rings, pistons, energy conduits,
##   radar dishes, holograms, ringed planets, robot arms, drills, tesla coils, exhaust fans, bio
##   pods, specimen tanks, data streams, laser sweeps, warp portals, crystal pylons, press hammers
##   and cargo lifts.
## Picking a machine gives the background its colors, numbers and layout (hanging from above,
## standing along the bottom, spread about, or one big one in front); change them after.
##
## By default it stays fixed in the world: [member scroll_scale] 1, so the camera pans over it as
## over the room. Less makes it far away, moving slower than the room (0 stays on the screen),
## and [member follow_camera] makes it cover the whole view in the game, wherever the camera
## goes (in the editor and the Room view it covers its rectangle, and scrolls as you pan).
##
## It covers its rectangle, in the game as in the editor and the Room view: given to a room (the
## "Animated bg" fields of an area, a room, the world or the boss rooms), the whole room. The
## rectangle is cut into screen-sized cells (about 1152 x 648 px, [constant CELL_SIZE]), each
## with [member count] machines of its own laid out on it, so a big room has machinery all over
## and every screen of it looks like one. Values: [code]clockwork[/code],
## [code]turbines(count=8)[/code], or after a style ([code]storm_clouds, castle_spires[/code]:
## then it draws no backdrop of its own).

enum Machine {
	GIANT_WHEELS, CLOCKWORK, CLOCK_FACES, PENDULUMS, BELLS, CHANDELIERS, ROSE_WINDOWS, HANGING_CHAINS, CANDELABRA, WINCHES,
	SPIKED_ROLLERS, HOURGLASSES, ORGAN_PIPES, BANNERS, ASTROLABES, TORCHES, WINDMILLS, SWINGING_AXES, SAW_BLADES, CASTLE_SPIRES,
	TURBINES, REACTOR_CORES, GYRO_RINGS, PISTONS, ENERGY_CONDUITS, RADAR_DISHES, HOLOGRAMS, RINGED_PLANETS, ROBOT_ARMS, DRILLS,
	TESLA_COILS, EXHAUST_FANS, BIO_PODS, SPECIMEN_TANKS, DATA_STREAMS, LASER_SWEEPS, WARP_PORTALS, CRYSTAL_PYLONS, PRESS_HAMMERS, CARGO_LIFTS,
}
## Ids of the machines (as the background fields write them), in [enum Machine] order.
const MACHINE_IDS: PackedStringArray = [
	"giant_wheels", "clockwork", "clock_faces", "pendulums", "bells", "chandeliers", "rose_windows", "hanging_chains", "candelabra", "winches",
	"spiked_rollers", "hourglasses", "organ_pipes", "banners", "astrolabes", "torches", "windmills", "swinging_axes", "saw_blades", "castle_spires",
	"turbines", "reactor_cores", "gyro_rings", "pistons", "energy_conduits", "radar_dishes", "holograms", "ringed_planets", "robot_arms", "drills",
	"tesla_coils", "exhaust_fans", "bio_pods", "specimen_tanks", "data_streams", "laser_sweeps", "warp_portals", "crystal_pylons", "press_hammers", "cargo_lifts",
]
const MACHINE_NAMES: PackedStringArray = [
	"Giant wheels", "Clockwork gears", "Clock faces", "Pendulums", "Bells", "Chandeliers", "Rose windows", "Hanging chains", "Candelabra", "Winches",
	"Spiked rollers", "Hourglasses", "Organ pipes", "Banners", "Astrolabes", "Torches", "Windmills", "Swinging axes", "Saw blades", "Castle spires",
	"Turbines", "Reactor cores", "Gyro rings", "Pistons", "Energy conduits", "Radar dishes", "Holograms", "Ringed planets", "Robot arms", "Drills",
	"Tesla coils", "Exhaust fans", "Bio pods", "Specimen tanks", "Data streams", "Laser sweeps", "Warp portals", "Crystal pylons", "Press hammers", "Cargo lifts",
]
const MACHINE_INFO: PackedStringArray = [
	"Huge spoked wheels with paddles round their rims, turning slowly",
	"Toothed cogwheels with windows cut in them, turning on their axles: a clock tower's works",
	"Clock faces lit from behind, their hands going round",
	"Pendulums swinging from above, some with a bob, some with a blade",
	"Great bells swinging in their yokes, their clappers swinging after them",
	"Chandeliers swaying on their chains, their candles flickering",
	"Rose windows: stone tracery, the stained glass glowing and shimmering",
	"Chains hanging from above, swaying, hooks at their ends",
	"Candelabra on the floor, their candles flickering",
	"Winches: spoked wheels turning drums, chains winding up",
	"Spiked rollers turning on their beams",
	"Hourglasses running out, then turned over",
	"Organ pipes along the floor, sound pulsing up them",
	"Banners hanging from their rods, waving, tattered at the bottom",
	"Astrolabes: nested rings turning about a glowing core",
	"Torches in wall sconces, their flames flickering",
	"Windmills on their towers, their latticed sails turning",
	"Great axe blades swinging from above",
	"Saw blades spinning fast, sliding along their slots",
	"Castle spires: towers, pointed roofs, lit windows, a flag flying",
	"Turbines spinning in their housings, hubs glowing",
	"Reactor cores pulsing inside counter-turning shield rings, energy arcing off them",
	"Gyro rings turning about each other round a glowing orb",
	"Hydraulic pistons pumping up and down, venting at the bottom of their stroke",
	"Pipes with pulses of energy racing along them",
	"Radar dishes on their masts, turning, feed lights blinking",
	"Holograms of worlds turning above their projectors, scanlines rolling",
	"Ringed planets seen through the station's windows, their bands drifting, moons going round",
	"Robot arms reaching and turning, claws opening and closing",
	"Giant drills boring down, spirals turning, tips glowing hot",
	"Tesla coils, lightning crackling off their crowns",
	"Exhaust fans spinning behind their grilles, lit from behind",
	"Organic pods breathing, their nuclei pulsing with light",
	"Specimen tanks: glowing fluid, bubbles rising, a creature floating in each",
	"Data panels, columns of glowing blocks streaming down them",
	"Security emitters sweeping their laser beams back and forth",
	"Warp portals: rings of runes round swirling vortices",
	"Crystal pylons floating and turning over their pedestals",
	"Press hammers rising slowly, then slamming down in a flash",
	"Cargo lifts riding up and down their rails, lamps blinking",
]
## How many of [constant MACHINE_IDS] are gothic (the first ones); the rest are sci-fi.
const GOTHIC_COUNT := 20
## The gothic castle machines (Castlevania-style castles).
static var GOTHIC_IDS: PackedStringArray = MACHINE_IDS.slice(0, GOTHIC_COUNT)
## The alien and space-station machines (Metroid-style worlds).
static var SCIFI_IDS: PackedStringArray = MACHINE_IDS.slice(GOTHIC_COUNT)
## The most machines a background draws, all its cells together (a big room gets fewer a cell).
const MAX_COUNT := 32
## The size of a cell of the layout (a screen): the rectangle is cut into cells about this big.
const CELL_SIZE := Vector2(1152, 648)

## How each machine is laid out: [placement, smallest size, biggest size (view heights)].
## Placements: "scatter" (spread about), "hero" (one big one in front, the others smaller and
## farther, to its sides), "hang" (from the top of the view), "dangle" (lower down, on ropes or
## chains running up out of sight), "stand" (along its bottom), "row" (side by side across it).
const LAYOUTS := {
	"giant_wheels": ["scatter", 0.18, 0.45], "clockwork": ["scatter", 0.1, 0.36], "clock_faces": ["hero", 0.12, 0.42], "pendulums": ["hang", 0.2, 0.34],
	"bells": ["dangle", 0.16, 0.32], "chandeliers": ["dangle", 0.2, 0.38], "rose_windows": ["hero", 0.15, 0.42], "hanging_chains": ["hang", 0.2, 0.42],
	"candelabra": ["stand", 0.2, 0.36], "winches": ["scatter", 0.16, 0.32], "spiked_rollers": ["scatter", 0.12, 0.3], "hourglasses": ["scatter", 0.12, 0.28],
	"organ_pipes": ["stand", 0.22, 0.42], "banners": ["hang", 0.18, 0.34], "astrolabes": ["hero", 0.14, 0.4], "torches": ["scatter", 0.1, 0.22],
	"windmills": ["stand", 0.22, 0.4], "swinging_axes": ["hang", 0.2, 0.36], "saw_blades": ["scatter", 0.12, 0.3], "castle_spires": ["stand", 0.25, 0.5],
	"turbines": ["scatter", 0.14, 0.4], "reactor_cores": ["hero", 0.14, 0.42], "gyro_rings": ["hero", 0.15, 0.4], "pistons": ["stand", 0.16, 0.3],
	"energy_conduits": ["scatter", 0.08, 0.16], "radar_dishes": ["stand", 0.26, 0.42], "holograms": ["stand", 0.2, 0.4], "ringed_planets": ["hero", 0.12, 0.38],
	"robot_arms": ["stand", 0.22, 0.38], "drills": ["hang", 0.2, 0.38], "tesla_coils": ["stand", 0.2, 0.36], "exhaust_fans": ["scatter", 0.12, 0.26],
	"bio_pods": ["scatter", 0.12, 0.3], "specimen_tanks": ["stand", 0.22, 0.36], "data_streams": ["row", 0.18, 0.34], "laser_sweeps": ["hang", 0.25, 0.45],
	"warp_portals": ["hero", 0.2, 0.45], "crystal_pylons": ["stand", 0.14, 0.3], "press_hammers": ["stand", 0.22, 0.38], "cargo_lifts": ["row", 0.2, 0.35],
}
## Machines that may turn either way (the others always go forward: clocks, hourglasses...).
const REVERSIBLE: PackedStringArray = ["giant_wheels", "clockwork", "spiked_rollers", "turbines", "exhaust_fans", "gyro_rings", "astrolabes", "windmills", "reactor_cores"]
## Machines never mirrored (a clock's hands would go backwards).
const NO_MIRROR: PackedStringArray = ["clock_faces"]

## Colors and settings of each machine: id -> {property: value}.
const LOOKS := {
	"giant_wheels": {"back_top": Color("#05070f"), "back_bottom": Color("#18202e"), "metal_color": Color("#3a3030"), "light_color": Color("#ffb060"), "accent_color": Color("#6a4a2a"), "count": 5},
	"clockwork": {"back_top": Color("#0a0705"), "back_bottom": Color("#2a1c0c"), "metal_color": Color("#3a2a18"), "light_color": Color("#ffd27a"), "accent_color": Color("#8a6a34"), "count": 10},
	"clock_faces": {"back_top": Color("#04060c"), "back_bottom": Color("#1a2238"), "metal_color": Color("#1c1a22"), "light_color": Color("#e8f0ff"), "accent_color": Color("#b08a4a"), "count": 4},
	"pendulums": {"back_top": Color("#08050a"), "back_bottom": Color("#241018"), "metal_color": Color("#3a3238"), "light_color": Color("#ff9a50"), "accent_color": Color("#8a3a3a"), "count": 5},
	"bells": {"back_top": Color("#070608"), "back_bottom": Color("#221c14"), "metal_color": Color("#201c1c"), "light_color": Color("#ffd890"), "accent_color": Color("#8a6a30"), "count": 5},
	"chandeliers": {"back_top": Color("#060405"), "back_bottom": Color("#1e1210"), "metal_color": Color("#3a2e26"), "light_color": Color("#ffb04a"), "accent_color": Color("#9a7a40"), "count": 4},
	"rose_windows": {"back_top": Color("#05030a"), "back_bottom": Color("#160c1e"), "metal_color": Color("#18141c"), "light_color": Color("#ff4a6a"), "accent_color": Color("#4a8aff"), "count": 3},
	"hanging_chains": {"back_top": Color("#050406"), "back_bottom": Color("#1c1416"), "metal_color": Color("#3a3438"), "light_color": Color("#ff8a4a"), "accent_color": Color("#5a5458"), "count": 8},
	"candelabra": {"back_top": Color("#070404"), "back_bottom": Color("#22120c"), "metal_color": Color("#4a3a26"), "light_color": Color("#ffb44a"), "accent_color": Color("#a8884a"), "count": 6},
	"winches": {"back_top": Color("#060506"), "back_bottom": Color("#1e1814"), "metal_color": Color("#3a322c"), "light_color": Color("#ff9a50"), "accent_color": Color("#6a4a2c"), "count": 4},
	"spiked_rollers": {"back_top": Color("#080404"), "back_bottom": Color("#2a0e0e"), "metal_color": Color("#363034"), "light_color": Color("#ff5a3a"), "accent_color": Color("#9a9aa0"), "count": 5},
	"hourglasses": {"back_top": Color("#070608"), "back_bottom": Color("#1e1a24"), "metal_color": Color("#241c14"), "light_color": Color("#ffe0a0"), "accent_color": Color("#d8b46a"), "count": 4},
	"organ_pipes": {"back_top": Color("#050308"), "back_bottom": Color("#1a1028"), "metal_color": Color("#1e1a1c"), "light_color": Color("#b48aff"), "accent_color": Color("#9a8a6a"), "count": 5},
	"banners": {"back_top": Color("#060407"), "back_bottom": Color("#1c1018"), "metal_color": Color("#1e1a18"), "light_color": Color("#ffb45a"), "accent_color": Color("#7a1420"), "count": 6},
	"astrolabes": {"back_top": Color("#04050c"), "back_bottom": Color("#141a30"), "metal_color": Color("#1e1a20"), "light_color": Color("#9ad0ff"), "accent_color": Color("#a8843e"), "count": 3},
	"torches": {"back_top": Color("#050303"), "back_bottom": Color("#1e0e08"), "metal_color": Color("#221a14"), "light_color": Color("#ff9a3a"), "accent_color": Color("#4a3626"), "count": 8},
	"windmills": {"back_top": Color("#0a1020"), "back_bottom": Color("#2a3448"), "metal_color": Color("#1a161a"), "light_color": Color("#ffc46a"), "accent_color": Color("#5a4a3a"), "count": 4},
	"swinging_axes": {"back_top": Color("#080306"), "back_bottom": Color("#26080e"), "metal_color": Color("#3a3036"), "light_color": Color("#ff6a3a"), "accent_color": Color("#a8aeb6"), "count": 5},
	"saw_blades": {"back_top": Color("#060405"), "back_bottom": Color("#1e1210"), "metal_color": Color("#2e2a2e"), "light_color": Color("#ffb46a"), "accent_color": Color("#b8bcc4"), "count": 6},
	"castle_spires": {"back_top": Color("#0a1024"), "back_bottom": Color("#3a2c4a"), "metal_color": Color("#0e0c14"), "light_color": Color("#ffcf6a"), "accent_color": Color("#6a1a24"), "count": 6},
	"turbines": {"back_top": Color("#02060a"), "back_bottom": Color("#0c1c28"), "metal_color": Color("#2c3c4c"), "light_color": Color("#6af0ff"), "accent_color": Color("#4a5c6c"), "count": 5},
	"reactor_cores": {"back_top": Color("#010508"), "back_bottom": Color("#0a2220"), "metal_color": Color("#1a2028"), "light_color": Color("#7affd0"), "accent_color": Color("#ffcf4a"), "count": 3},
	"gyro_rings": {"back_top": Color("#04030c"), "back_bottom": Color("#140c2a"), "metal_color": Color("#222a36"), "light_color": Color("#9a7aff"), "accent_color": Color("#8a9ab0"), "count": 3},
	"pistons": {"back_top": Color("#030807"), "back_bottom": Color("#0e2018"), "metal_color": Color("#2e3840"), "light_color": Color("#5aff9a"), "accent_color": Color("#9aa4ac"), "count": 7},
	"energy_conduits": {"back_top": Color("#02040a"), "back_bottom": Color("#0e1424"), "metal_color": Color("#1c2430"), "light_color": Color("#4df2ff"), "accent_color": Color("#ff5ad0"), "count": 6},
	"radar_dishes": {"back_top": Color("#03070c"), "back_bottom": Color("#122030"), "metal_color": Color("#2e3c48"), "light_color": Color("#ff4a4a"), "accent_color": Color("#c8d0d8"), "count": 4},
	"holograms": {"back_top": Color("#010409"), "back_bottom": Color("#081624"), "metal_color": Color("#26323e"), "light_color": Color("#4dd8ff"), "accent_color": Color("#3a4a5a"), "count": 3},
	"ringed_planets": {"back_top": Color("#010208"), "back_bottom": Color("#0c0a1c"), "metal_color": Color("#2a2038"), "light_color": Color("#ffd8a0"), "accent_color": Color("#c88a5a"), "count": 3},
	"robot_arms": {"back_top": Color("#050607"), "back_bottom": Color("#1a1c20"), "metal_color": Color("#2e363e"), "light_color": Color("#ff5a3a"), "accent_color": Color("#d8a43a"), "count": 4},
	"drills": {"back_top": Color("#070403"), "back_bottom": Color("#24120a"), "metal_color": Color("#2e2a24"), "light_color": Color("#ff7a2a"), "accent_color": Color("#8a7a6a"), "count": 4},
	"tesla_coils": {"back_top": Color("#020309"), "back_bottom": Color("#0e1430"), "metal_color": Color("#2a3040"), "light_color": Color("#b0d8ff"), "accent_color": Color("#9ab0d8"), "count": 5},
	"exhaust_fans": {"back_top": Color("#040405"), "back_bottom": Color("#161414"), "metal_color": Color("#2a2c30"), "light_color": Color("#ff7a3a"), "accent_color": Color("#3a3e44"), "count": 6},
	"bio_pods": {"back_top": Color("#020803"), "back_bottom": Color("#0c2410"), "metal_color": Color("#1a2a14"), "light_color": Color("#b8ff5a"), "accent_color": Color("#3a6a2a"), "count": 7},
	"specimen_tanks": {"back_top": Color("#02070a"), "back_bottom": Color("#0a1c1e"), "metal_color": Color("#1a2228"), "light_color": Color("#ff5a6a"), "accent_color": Color("#3ae0b0"), "count": 5},
	"data_streams": {"back_top": Color("#01040a"), "back_bottom": Color("#06121e"), "metal_color": Color("#141c24"), "light_color": Color("#4aff8a"), "accent_color": Color("#4af0ff"), "count": 8},
	"laser_sweeps": {"back_top": Color("#040306"), "back_bottom": Color("#140c14"), "metal_color": Color("#1c2028"), "light_color": Color("#ffd04a"), "accent_color": Color("#ff3a4a"), "count": 5},
	"warp_portals": {"back_top": Color("#030210"), "back_bottom": Color("#120a2a"), "metal_color": Color("#1c1a2c"), "light_color": Color("#e8d8ff"), "accent_color": Color("#b46bff"), "count": 2},
	"crystal_pylons": {"back_top": Color("#02040c"), "back_bottom": Color("#0a1430"), "metal_color": Color("#1a1a24"), "light_color": Color("#e8faff"), "accent_color": Color("#6ad8ff"), "count": 6},
	"press_hammers": {"back_top": Color("#060504"), "back_bottom": Color("#1e1810"), "metal_color": Color("#3a3630"), "light_color": Color("#ffa04a"), "accent_color": Color("#8a7a5a"), "count": 4},
	"cargo_lifts": {"back_top": Color("#030507"), "back_bottom": Color("#10161c"), "metal_color": Color("#1e2228"), "light_color": Color("#ff4a3a"), "accent_color": Color("#c8a43a"), "count": 5},
}
## The settings a machine sets.
const LOOK_KEYS: PackedStringArray = ["back_top", "back_bottom", "metal_color", "light_color", "accent_color", "count"]

## The kind of machine: picking one gives the background its colors, numbers and layout.
@export var machine: Machine = Machine.CLOCKWORK:
	set(v):
		if v == machine:
			return
		machine = v
		apply_look(v)
		_laid_out = false
		_rebuild_for_theme()
		_changed()
## How many on each screen-sized cell of the rectangle (up to 12).
@export_range(1, 12) var count := 10:
	set(v):
		count = clampi(v, 1, 12)
		_laid_out = false
		_changed()
@export_group("Look")
@export var back_top := Color("#0a0705"):
	set(v):
		back_top = v
		_changed()
## The bottom of the backdrop, and the haze the far machines fade into.
@export var back_bottom := Color("#2a1c0c"):
	set(v):
		back_bottom = v
		_changed()
## The machines' iron, stone or steel.
@export var metal_color := Color("#3a2a18"):
	set(v):
		metal_color = v
		_changed()
## Their lights: flames, lit windows, energy.
@export var light_color := Color("#ffd27a"):
	set(v):
		light_color = v
		_changed()
## Their other material (bronze, cloth, crystal) and second light.
@export var accent_color := Color("#8a6a34"):
	set(v):
		accent_color = v
		_changed()
## How out of focus they are (0 sharp, 1 very soft).
@export_range(0.0, 1.0, 0.01) var blur := 0.55:
	set(v):
		blur = v
		_changed()
## How fast they move (0: still).
@export_range(0.0, 4.0, 0.01) var speed := 1.0:
	set(v):
		speed = v
		_changed()
@export_range(0.0, 2.0, 0.01) var brightness := 1.0:
	set(v):
		brightness = v
		_changed()
## How much the far ones fade into the haze.
@export_range(0.0, 1.0, 0.01) var haze := 0.6:
	set(v):
		haze = v
		_changed()
@export_range(0.0, 1.0, 0.01) var vignette := 0.4:
	set(v):
		vignette = v
		_changed()
@export_range(0.0, 1.0, 0.01) var grain := 0.25:
	set(v):
		grain = v
		_changed()
## Draw a backdrop of its own (off: only the machines, over whatever is behind, an animated
## background's style for one).
@export var backdrop := true:
	set(v):
		backdrop = v
		_changed()
@export_group("Camera")
## How much it moves with the room as the camera moves: 1 (the default) is fixed in the world,
## the camera panning over it as over the room; less is farther away, moving slower; 0 stays
## on the screen.
@export var scroll_scale := Vector2.ONE:
	set(v):
		scroll_scale = v
		_changed()
## On: it moves with the camera as [member scroll_scale] says, and in the game covers the whole
## view, wherever the camera goes. Off (the default): it covers its rectangle, fixed in the
## world: the camera moves nothing.
@export var follow_camera := false:
	set(v):
		follow_camera = v
		_changed()
var _mat: ShaderMaterial
var _quad: Polygon2D
var _laid_out := false
var _laid_for := Rect2()
var _a := PackedVector4Array()
var _b := PackedVector4Array()

func _init() -> void:
	z_index = -108
	# Nothing reacts to bodies: the machines move by time alone.
	affect_groups = PackedStringArray()

# The machine and its settings are also saved together, as "look" (see MDSAnimatedBackground).
func _get_property_list() -> Array[Dictionary]:
	return [{"name": "look", "type": TYPE_DICTIONARY, "usage": PROPERTY_USAGE_STORAGE}]

func _get(property: StringName) -> Variant:
	if property == &"look":
		var d: Dictionary = {"machine": int(machine)}
		for k in LOOK_KEYS:
			d[k] = get(k)
		return d
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property != &"look" or not value is Dictionary:
		return false
	if value.has("machine"):
		machine = int(value.machine) as Machine
	for k in value:
		if LOOK_KEYS.has(str(k)):
			set(str(k), value[k])
	return true

func get_effect_id() -> String:
	return "machinery"

## Makes it [param id] (see [constant MACHINE_IDS]). Returns false for an unknown one.
func use_machine(id: String) -> bool:
	var i := MACHINE_IDS.find(id.strip_edges().to_lower().replace(" ", "_"))
	if i < 0:
		return false
	machine = i as Machine
	return true

## Sets the colors and numbers of [param m] (see [constant LOOKS]).
func apply_look(m: Machine) -> void:
	var look: Dictionary = LOOKS.get(MACHINE_IDS[m], {})
	for k in look:
		set(k, look[k])

## Whether [param id] is a gothic castle machine (else a sci-fi one).
static func is_gothic(id: String) -> bool:
	return MACHINE_IDS.find(id.strip_edges().to_lower()) in range(GOTHIC_COUNT)

## "gothic" or "scifi": the shader that draws [member machine].
func get_theme_name() -> String:
	return "gothic" if int(machine) < GOTHIC_COUNT else "scifi"

func _build() -> void:
	_mat = add_quad(shader("machinery_" + get_theme_name()), get_effect_rect())
	_quad = _quads[_quads.size() - 1] as Polygon2D
	_laid_out = false
	_tick(0.0)

func _rebuild_for_theme() -> void:
	if _mat and not (_mat.shader.resource_path.ends_with("machinery_%s.gdshader" % get_theme_name())):
		_queue_rebuild()

func _update_params() -> void:
	if not _mat:
		return
	_mat.set_shader_parameter("kind", int(machine) % GOTHIC_COUNT)
	_mat.set_shader_parameter("back_top", back_top)
	_mat.set_shader_parameter("back_bottom", back_bottom)
	_mat.set_shader_parameter("metal_color", metal_color)
	_mat.set_shader_parameter("light_color", light_color)
	_mat.set_shader_parameter("accent_color", accent_color)
	_mat.set_shader_parameter("blur", blur)
	_mat.set_shader_parameter("speed", speed)
	_mat.set_shader_parameter("brightness", brightness)
	_mat.set_shader_parameter("haze", haze)
	_mat.set_shader_parameter("vignette", vignette)
	_mat.set_shader_parameter("grain", grain)
	_mat.set_shader_parameter("backdrop", backdrop)
	_laid_out = false

# --- Layout ------------------------------------------------------------------------------------

## The machines of one cell of the layout, on the cell (its middle at (0, 0), its height 1,
## [param aspect] wide): [inst_a, inst_b] (see machinery.gdshaderinc), the far ones first.
## [param cell] picks the cell, so each has a layout of its own. The same seed, machine, count,
## aspect and cell always give the same layout.
func layout(aspect: float, cell := Vector2i.ZERO, per_cell := -1) -> Array:
	var id := MACHINE_IDS[machine]
	var rule: Array = LAYOUTS.get(id, ["scatter", 0.15, 0.35])
	var place: String = rule[0]
	var lo: float = rule[1]
	var hi: float = rule[2]
	var n := count if per_cell < 0 else per_cell
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, id, n, cell])
	var half_w := aspect * 0.5
	var items: Array = []
	for i in n:
		var size := lerpf(lo, hi, rng.randf())
		if place == "hero":
			size = hi if i == 0 else lerpf(lo, lerpf(lo, hi, 0.55), rng.randf())
		# Bigger ones are nearer; the depth decides the order and the haze.
		var depth := clampf(1.0 - (size - lo) / maxf(hi - lo, 0.001) * 0.85 + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
		# Spread across the cell in strips, so they don't all bunch up.
		var x := lerpf(-half_w * 1.02, half_w * 1.02, (i + rng.randf_range(0.15, 0.85)) / n)
		var y := rng.randf_range(-0.38, 0.38)
		match place:
			"hero":
				if i == 0:
					x = rng.randf_range(-0.2, 0.2) * half_w
					y = rng.randf_range(-0.08, 0.04)
					depth = 0.3
			"hang":
				y = -0.5 + size * rng.randf_range(0.82, 1.0)
			"dangle":
				y = -0.5 + size * rng.randf_range(1.0, 2.1)
			"stand":
				y = 0.5 - size * rng.randf_range(0.9, 1.0)
			"row":
				x = lerpf(-half_w, half_w, (i + 0.5) / n) + rng.randf_range(-0.03, 0.03)
				y = rng.randf_range(-0.12, 0.12)
				size = lerpf(lo, hi, 0.4 + 0.6 * rng.randf())
		if place == "hero" and i > 0 and not items.is_empty():
			# Clear of the big one: off to its sides.
			var hero: Vector4 = items[0][0]
			if absf(x - hero.x) < hero.z * 1.3:
				x = hero.x + signf(x - hero.x + 0.001) * hero.z * rng.randf_range(1.35, 2.1)
				if absf(x) > half_w * 1.05:
					x = hero.x - signf(x - hero.x) * hero.z * rng.randf_range(1.35, 2.1)
		var pace := rng.randf_range(0.75, 1.25) * (-1.0 if REVERSIBLE.has(id) and rng.randf() < 0.5 else 1.0)
		var mirror := -1.0 if not NO_MIRROR.has(id) and rng.randf() < 0.5 else 1.0
		items.append([Vector4(x, y, size, depth), Vector4(rng.randf() * 100.0, pace, rng.randf(), mirror)])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0].w > b[0].w)
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for it in items:
		a.append(it[0])
		b.append(it[1])
	return [a, b]

## The part of the rectangle the machines are laid out on (its own coordinates): all of it, or,
## sized to a room ([member MDSEnvironmentEffect.fit_room]), the room (without the margin
## [MDSEnvironment] adds around it, out of sight), so the standing ones stand on its floor.
func layout_rect() -> Rect2:
	var r := get_effect_rect()
	var m := MDSEnvironment.ROOM_MARGIN
	if fit_room and r.size.x > m * 3.0 and r.size.y > m * 3.0:
		return r.grow(-m)
	return r

## How [method layout_rect] is cut into cells, about [constant CELL_SIZE] each: columns, rows.
func cell_grid() -> Vector2i:
	var r := layout_rect()
	return Vector2i(maxi(1, roundi(r.size.x / CELL_SIZE.x)), maxi(1, roundi(r.size.y / CELL_SIZE.y)))

## The machines' places in the rectangle (inst_a: x, y and size in px of its own coordinates
## divided by a cell's height; depth), the far ones first, for tests and tools. They never change
## unless the background's settings or size do.
func machine_places() -> PackedVector4Array:
	return _a.duplicate()

## The height of a cell (px): the shader's unit.
func cell_height() -> float:
	return layout_rect().size.y / cell_grid().y

func _send_layout() -> void:
	var r := layout_rect()
	var grid := cell_grid()
	var cell := Vector2(r.size.x / grid.x, r.size.y / grid.y)
	var unit := cell.y
	var per_cell := clampi(count, 1, maxi(1, MAX_COUNT / (grid.x * grid.y)))
	var items: Array = []
	for cy in grid.y:
		for cx in grid.x:
			var l := layout(cell.x / cell.y, Vector2i(cx, cy), per_cell)
			var origin := r.position + Vector2(cx, cy) * cell + cell * 0.5
			for k in (l[0] as PackedVector4Array).size():
				var p: Vector4 = l[0][k]
				var at := origin + Vector2(p.x, p.y) * unit
				items.append([Vector4(at.x / unit, at.y / unit, p.z, p.w), l[1][k]])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0].w > b[0].w)
	if items.size() > MAX_COUNT:
		items.resize(MAX_COUNT)
	_a = PackedVector4Array()
	_b = PackedVector4Array()
	for it in items:
		_a.append(it[0])
		_b.append(it[1])
	var a := _a.duplicate()
	var b := _b.duplicate()
	a.resize(MAX_COUNT)
	b.resize(MAX_COUNT)
	_mat.set_shader_parameter("inst_a", a)
	_mat.set_shader_parameter("inst_b", b)
	_mat.set_shader_parameter("count", _a.size())
	_mat.set_shader_parameter("unit", unit)
	_mat.set_shader_parameter("layout_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_laid_for = get_effect_rect()
	_laid_out = true

# --- Running ------------------------------------------------------------------------------------

## What the camera sees, in this node's coordinates (its rectangle when there is no viewport).
func view_rect() -> Rect2:
	var vp := get_viewport()
	if not vp or not is_inside_tree():
		return get_effect_rect()
	var inv := get_global_transform_with_canvas().affine_inverse()
	var seen := vp.get_visible_rect()
	var a := inv * seen.position
	var b := inv * seen.end
	return Rect2(a, b - a).abs()

## How far the machines are moved for the camera at [param cam] (local, px): the share of the
## camera's way from the layout's middle that they stay behind (none at [member scroll_scale] 1).
func camera_offset(cam: Vector2) -> Vector2:
	return (cam - layout_rect().get_center()) * (Vector2.ONE - scroll_scale)

func _tick(_delta: float) -> void:
	if not _mat or not _quad:
		return
	var view := view_rect()
	var following := follow_camera and not Engine.is_editor_hint()
	# Its own rectangle, or (following the camera, in the game) the whole view.
	var cover := view.grow(4.0) if following else get_effect_rect()
	var poly := PackedVector2Array([cover.position, Vector2(cover.end.x, cover.position.y), cover.end, Vector2(cover.position.x, cover.end.y)])
	if _quad.polygon != poly:
		_quad.polygon = poly
		_mat.set_shader_parameter("rect_origin", cover.position)
		_mat.set_shader_parameter("rect_size", cover.size)
		_mat.set_shader_parameter("edge_fade", 0.0 if following else 24.0)
	if not _laid_out or _laid_for != get_effect_rect():
		_send_layout()
	# Fixed in the world (not following, or at scroll_scale 1), this stays zero whatever the
	# camera does.
	_mat.set_shader_parameter("offset", camera_offset(view.get_center()) if follow_camera else Vector2.ZERO)
