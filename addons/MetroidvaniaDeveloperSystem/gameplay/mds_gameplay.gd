@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_gameplay.svg")
class_name MDSGameplay
extends Node
## The Gameplay Kit's hub: a child of the [MDSWorldGame] root that owns everything the kit adds to
## a game's progress (items, currency, equipment, story flags, health and mana, enemies that come
## back after a rest, shops' stock, the corpse, play time and deaths). [MDSWorldGame] stays the
## one source of rooms, abilities, stored objects and defeats; this node is saved with it (in
## [code]ext.gameplay[/code] of the save, see [method mds_get_save_data]) and answers its
## [code]item:[/code] and [code]flag:[/code] conditions ([method is_condition_met]):
## [codeblock]
## item:red_key               the player has a red_key
## item:health_fragment>=4    at least 4 health fragments
## flag:bridge_lowered        the flag is set (truthy)
## [/codeblock]
## Those work wherever MDS takes a condition: gate [code]requires[/code], [MDSGateBarrier],
## area objectives, dialogue lines and shop entries. Every change emits its signal and lets the
## game check its objectives.
##
## Kit nodes find it with [method find] (or [method find_from]); it finds the game as its parent,
## else [member MDSWorldGame.instance]. There are no autoloads.

signal item_changed(id: String, count: int)
signal currency_changed(total: int)
signal flag_changed(flag: String, value: Variant)
signal equipment_changed
signal player_health_changed(current: int, max: int)
signal player_mana_changed(current: int, max: int)
signal player_died
signal boss_started(boss: String)
signal boss_ended(boss: String, won: bool)
## Something worth a short notice ([MDSToast] shows it): an item picked up, a gate that needs
## something, the map updated.
signal notice(text: String)
## An experience level was reached (LEVELS progression).
signal level_up(level: int)

## The key of its data in the save's [code]ext[/code].
const SAVE_KEY := "gameplay"
## The version of its save data. Older data is brought up to it by [constant MIGRATIONS].
const VERSION := 1
## Where the built-in abilities are ([MDSAbilityData] .tres files).
const DATA_DIR := "res://addons/MetroidvaniaDeveloperSystem/gameplay/data/"

## Save data version -> Callable(data: Dictionary) -> Dictionary that turns data of that version
## into the next one. They run in order on load.
static var MIGRATIONS: Dictionary = {
	0: func(d: Dictionary) -> Dictionary:
		# Saves from before versions: the same fields, numbered.
		d["version"] = 1
		return d,
}

## The game. Empty: the parent, else [member MDSWorldGame.instance].
@export var game: MDSWorldGame
## The player's base health and mana (empty: 5 health, 33 mana).
@export var stats: MDSCombatStats
## Equipment slots a new game starts with ([MDSEquipmentData], [MDSSlotUpgrade] adds more).
@export var starting_equip_slots := 3
## Health fragments ([MDSHealthUpgrade]) that make one more health.
@export var fragments_per_upgrade := 4
## Mana fragments ([MDSManaUpgrade]) that make more mana, and how much.
@export var mana_fragments_per_upgrade := 3
@export var mana_per_upgrade := 33
## Items and abilities known by id (their names, icons and effects for the HUD, the inventory,
## popups and "Requires ..." notices). Items picked up are added, and the built-in abilities
## ([constant DATA_DIR]) are always known.
@export var items_database: Array[MDSItemData] = []
@export var abilities_database: Array[MDSAbilityData] = []
## Experience levels, with the LEVELS progression.
@export var level_curve: MDSLevelCurve
## Show [MDSAbilityPopup] when an ability is gained.
@export var show_ability_popups := true
## Seconds between the player's death and the trip back to its bench.
@export var death_delay := 1.2
## Seconds an [MDSLevelOverview] child of the game pulls back over the level after a death
## (skippable; 0: none).
@export var death_overview_time := 0.0

## Item id -> count.
var items: Dictionary = {}
var currency := 0
## Ids of the equipment worn.
var equipped: Array[String] = []
var equip_slots := 3
## Flag name -> value.
var flags: Dictionary = {}
var health := 5
var max_health := 5
var mana := 33
var max_mana := 33
## Object ids of enemies defeated since the last rest (ON_REST respawn, see [MDSEnemy]).
var rest_defeated: Dictionary = {}
## Shop id -> {entry index (as text): stock left}.
var shops: Dictionary = {}
## Where the player last died with currency on them (CORPSE penalty): {room, position, currency}.
var corpse: Dictionary = {}
var play_time := 0.0
var deaths := 0
## Experience (LEVELS progression).
var xp := 0
## Enemy id -> how many were defeated (the Bestiary).
var bestiary: Dictionary = {}
## The boss fought now ("" when none), and its node (for the HUD's boss bar).
var current_boss := ""
var boss_node: Node

var _items_db: Dictionary = {}
var _abilities_db: Dictionary = {}
var _enemies_db: Dictionary = {}
var _builtins_loaded := false
var _time_scale_before := 1.0
var _hitstop_token := 0 ## the hit-stop running now (0: none)
var _hitstop_serial := 0

func _init() -> void:
	add_to_group(&"mds_save_extension")
	add_to_group(&"mds_gameplay")

## The game's MDSGameplay (its first child in the [code]mds_gameplay[/code] group), or null.
## Cheap: the game asks it on every condition check.
static func find(p_game: Node) -> MDSGameplay:
	if not is_instance_valid(p_game):
		return null
	if p_game.has_meta(&"mds_gameplay"):
		var known: Variant = p_game.get_meta(&"mds_gameplay")
		if is_instance_valid(known) and known is MDSGameplay and (known as Node).get_parent() == p_game:
			return known
	for c in p_game.get_children():
		if c.is_in_group(&"mds_gameplay") and c is MDSGameplay:
			p_game.set_meta(&"mds_gameplay", c)
			return c
	return null

## The MDSGameplay of the game [param node] is in (or of the running game).
static func find_from(node: Node) -> MDSGameplay:
	var n := node
	while n:
		if n is MDSWorldGame:
			return find(n)
		n = n.get_parent()
	return find(MDSWorldGame.instance) if MDSWorldGame.instance else null

## The game this node serves.
func get_game() -> MDSWorldGame:
	if is_instance_valid(game):
		return game
	if get_parent() is MDSWorldGame:
		return get_parent()
	return MDSWorldGame.instance

func _ready() -> void:
	game = get_game()
	for d in items_database:
		register_item(d)
	for d in abilities_database:
		register_ability(d)
	if not game:
		return
	if not game.room_loaded.is_connected(_on_room_loaded):
		game.room_loaded.connect(_on_room_loaded)
	if not game.ability_gained.is_connected(_on_ability_gained):
		game.ability_gained.connect(_on_ability_gained)
	if not game.transition_blocked.is_connected(_on_transition_blocked):
		game.transition_blocked.connect(_on_transition_blocked)
	# MDSGate areas look at layer 1 only: the player's own layer is added to each as it comes.
	get_tree().node_added.connect(_on_node_added)
	for n in game.find_children("*", "Area2D", true, false):
		_on_node_added(n)
	if OS.is_debug_build() and bool(MDSGameplaySetup.setting("debug_keys", true)):
		var debug_node := MDSGameplayDebug.new()
		debug_node.name = "GameplayDebug"
		add_child(debug_node)

func _on_node_added(n: Node) -> void:
	if n is MDSGate and is_instance_valid(game) and game.is_ancestor_of(n):
		(n as MDSGate).collision_mask |= MDSGameplaySetup.bit("player")

func _process(delta: float) -> void:
	if not get_tree().paused:
		play_time += delta

## Ids are lowercase, words joined by underscores ("Red Key" is "red_key").
static func normalize_id(id: String) -> String:
	return id.strip_edges().to_lower().replace(" ", "_")

func _changed() -> void:
	var g := get_game()
	if g:
		g.check_objectives()

# --- Databases -------------------------------------------------------------------------------

func register_item(data: MDSItemData) -> void:
	if data and not data.id.is_empty():
		_items_db[normalize_id(data.id)] = data

## The item known as [param id] (the built-ins included), or null.
func get_item_data(id: String) -> MDSItemData:
	_load_builtins()
	return _items_db.get(normalize_id(id))

func register_ability(data: MDSAbilityData) -> void:
	if data and not data.id.is_empty():
		_abilities_db[normalize_id(data.id)] = data

## The ability known as [param id] (the built-ins included), or null.
func get_ability_data(id: String) -> MDSAbilityData:
	_load_builtins()
	return _abilities_db.get(normalize_id(id))

## The enemy known as [param id], or null.
func get_enemy_data(id: String) -> MDSEnemyData:
	_load_builtins()
	return _enemies_db.get(normalize_id(id))

func register_enemy_data(d: MDSEnemyData) -> void:
	if d and not d.id.is_empty():
		_enemies_db[normalize_id(d.id)] = d

## The built-in abilities ([constant DATA_DIR]).
func _load_builtins() -> void:
	if _builtins_loaded:
		return
	_builtins_loaded = true
	for f in DirAccess.get_files_at(DATA_DIR):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var r := load(DATA_DIR + file)
		if r is MDSAbilityData and not _abilities_db.has(normalize_id(r.id)):
			_abilities_db[normalize_id(r.id)] = r
		elif r is MDSItemData and not _items_db.has(normalize_id(r.id)):
			_items_db[normalize_id(r.id)] = r
		elif r is MDSEnemyData and not _enemies_db.has(normalize_id(r.id)):
			_enemies_db[normalize_id(r.id)] = r

## A readable name for a requirement or condition ("dash" -> "Dash", "item:red_key" -> "Red Key").
func describe_requirement(requirement: String) -> String:
	var c := MDSAnnotations.parse_condition(requirement)
	match c[0]:
		"item":
			var req := MDSAnnotations.parse_item_requirement(str(c[1]))
			var d := get_item_data(req[0])
			var n: String = d.get_display_name() if d else str(req[0]).capitalize()
			return n if int(req[1]) <= 1 else "%d %s" % [req[1], n]
		"flag":
			return str(c[1]).capitalize()
		"boss":
			return "defeating %s" % c[1]
		"object":
			return str(c[1]).get_file().capitalize()
	var a := get_ability_data(str(c[1]))
	return a.get_display_name() if a else str(c[1]).capitalize()

# --- Items -----------------------------------------------------------------------------------

## Adds [param n] of item [param id] (up to its max_stack). Returns how many there are now.
func add_item(id: String, n := 1) -> int:
	id = normalize_id(id)
	if id.is_empty() or n <= 0:
		return get_item_count(id)
	var d := get_item_data(id)
	var cap := d.max_stack if d else 999999
	var now := mini(get_item_count(id) + n, cap)
	items[id] = now
	item_changed.emit(id, now)
	_changed()
	return now

## Takes [param n] of item [param id]. Returns false (taking none) when there are fewer.
func remove_item(id: String, n := 1) -> bool:
	id = normalize_id(id)
	var have := get_item_count(id)
	if n <= 0 or have < n:
		return false
	if have - n <= 0:
		items.erase(id)
		if equipped.has(id):
			unequip(id)
	else:
		items[id] = have - n
	item_changed.emit(id, have - n)
	_changed()
	return true

func get_item_count(id: String) -> int:
	return int(items.get(normalize_id(id), 0))

func has_item(id: String, n := 1) -> bool:
	return get_item_count(id) >= n

## Uses one item [param id]: its effect is applied to the player and, when it did something, the
## item is used up (unless it is a KEY or EQUIPMENT). Returns whether it was used.
func use_item(id: String) -> bool:
	var d := get_item_data(id)
	if not d or not d.effect or not has_item(id):
		return false
	if not d.effect.apply(_player()):
		return false
	if d.category != MDSItemData.Category.KEY and d.category != MDSItemData.Category.EQUIPMENT:
		remove_item(id)
	return true

## Item ids carried, with [param category] only when given (-1: all).
func get_items(category := -1) -> Array[String]:
	var out: Array[String] = []
	for id in items:
		var d := get_item_data(id)
		if category < 0 or (d and d.category == category):
			out.append(str(id))
	out.sort()
	return out

# --- Currency --------------------------------------------------------------------------------

func add_currency(n: int) -> void:
	if n == 0:
		return
	currency = maxi(0, currency + n)
	currency_changed.emit(currency)
	_changed()

## Takes [param n] currency. Returns false (taking none) when there is less.
func spend_currency(n: int) -> bool:
	if n < 0 or currency < n:
		return false
	currency -= n
	currency_changed.emit(currency)
	_changed()
	return true

# --- Flags -----------------------------------------------------------------------------------

func set_flag(flag: String, value: Variant = true) -> void:
	flag = normalize_id(flag)
	if flag.is_empty():
		return
	if flags.has(flag) and typeof(flags[flag]) == typeof(value) and flags[flag] == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)
	_changed()

func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(normalize_id(flag), default)

## Whether [param v] counts as set: not null, false, 0 or empty.
static func truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		TYPE_STRING, TYPE_STRING_NAME:
			return not str(v).is_empty() and str(v) != "false"
	return true

# --- Conditions --------------------------------------------------------------------------------

## Whether an [code]item:[/code] or [code]flag:[/code] condition is met ([param kind] "item" or
## "flag", [param value] what follows the colon). [MDSWorldGame.is_condition_met] asks it.
func is_condition_met(kind: String, value: String) -> bool:
	match kind:
		"item":
			var req := MDSAnnotations.parse_item_requirement(value)
			return get_item_count(req[0]) >= int(req[1])
		"flag":
			return truthy(get_flag(value))
	return false

## Whether every condition in [param conditions] is met (in the running game; empty: true).
func are_met(conditions: PackedStringArray) -> bool:
	var g := get_game()
	for c in conditions:
		if c.strip_edges().is_empty():
			continue
		if not g or not g.is_condition_met(c):
			return false
	return true

# --- Equipment ---------------------------------------------------------------------------------

## The equipment known as [param id], or null when it isn't equipment.
func get_equipment_data(id: String) -> MDSEquipmentData:
	return get_item_data(id) as MDSEquipmentData

## Slots the equipment worn takes.
func get_used_slots() -> int:
	var n := 0
	for id in equipped:
		var d := get_equipment_data(id)
		n += d.slot_cost if d else 1
	return n

func get_equipped() -> Array[String]:
	return equipped.duplicate()

func is_equipped(id: String) -> bool:
	return equipped.has(normalize_id(id))

## Whether equipment can be changed now: always, or only while resting on a bench
## (project setting [code]equip_at_bench_only[/code]).
func can_change_equipment() -> bool:
	if not bool(MDSGameplaySetup.setting("equip_at_bench_only")):
		return true
	var g := get_game()
	if not g:
		return true
	for b in MDSWorldGame.find_save_points(g.room_node):
		if b.has_method(&"is_resting") and b.call(&"is_resting"):
			return true
	return false

## Wears equipment [param id] (owned, not worn yet, fitting the free slots, at a bench when the
## setting asks). Returns whether it is worn now.
func equip(id: String) -> bool:
	id = normalize_id(id)
	var d := get_equipment_data(id)
	if not d or not has_item(id) or equipped.has(id) or not can_change_equipment():
		return false
	if get_used_slots() + d.slot_cost > equip_slots:
		return false
	equipped.append(id)
	_equipment_changed()
	equipment_changed.emit()
	_changed()
	return true

## Every listener hears of new equipment; mana keeps within its maximum.
func _equipment_changed() -> void:
	mana = mini(mana, player_max_mana())
	player_mana_changed.emit(mana, player_max_mana())

func unequip(id: String) -> void:
	id = normalize_id(id)
	if equipped.has(id):
		equipped.erase(id)
		_equipment_changed()
		equipment_changed.emit()
		_changed()

## Stat -> amount added by the equipment worn (summed).
func equipment_mods() -> Dictionary:
	var out: Dictionary = {}
	for id in equipped:
		var d := get_equipment_data(id)
		if not d:
			continue
		for k in d.stat_mods:
			out[k] = out.get(k, 0.0) + float(d.stat_mods[k])
	return out

## Whether equipment worn lends ability [param ability].
func has_equipped_ability(ability: String) -> bool:
	ability = normalize_id(ability)
	for id in equipped:
		var d := get_equipment_data(id)
		if d and d.grants.has(ability):
			return true
	return false

# --- Health and mana ----------------------------------------------------------------------------

## The player's base stats.
func get_stats() -> MDSCombatStats:
	if not stats:
		stats = MDSCombatStats.make(5)
		stats.max_mana = 33
	return stats

## Records the player's health ([MDSHealth] of the player reports it here).
func set_health(current: int, maximum := -1) -> void:
	if maximum > 0:
		max_health = maximum
	health = clampi(current, 0, player_max_health())
	player_health_changed.emit(health, player_max_health())

## The player's maximum health: [member max_health] (the upgrades), with what equipment and
## levels add.
func player_max_health() -> int:
	return max_health + int(equipment_mods().get("max_health", 0.0)) + level_health_bonus()

## Raises maximum health by [param n] (an upgrade) and fills it.
func raise_max_health(n := 1) -> void:
	max_health += n
	var h := MDSHealth.of(_player())
	if h:
		h.set_max(player_max_health(), true)
	else:
		set_health(max_health)
	player_health_changed.emit(player_max_health(), player_max_health())
	_changed()

## The player's maximum mana: [member max_mana] (the upgrades), with what equipment adds.
func player_max_mana() -> int:
	return maxi(0, max_mana + int(equipment_mods().get("max_mana", 0.0)))

func set_mana(value: int) -> void:
	var now := clampi(value, 0, player_max_mana())
	if now == mana:
		return
	mana = now
	player_mana_changed.emit(mana, player_max_mana())

## Takes [param n] mana. Returns false (taking none) when there is less.
func spend_mana(n: int) -> bool:
	if mana < n:
		return false
	set_mana(mana - n)
	return true

func raise_max_mana(n: int) -> void:
	max_mana += n
	mana = player_max_mana()
	player_mana_changed.emit(mana, player_max_mana())
	_changed()

## Health and mana to full (a bench rest, a respawn).
func refill() -> void:
	var h := MDSHealth.of(_player())
	if h:
		h.heal_full()
	else:
		set_health(max_health)
	set_mana(player_max_mana())

## The player (the game's), or null.
func _player() -> Node:
	var g := get_game()
	return g.player if g else null

# --- Levels (LEVELS progression) ------------------------------------------------------------------

## Whether experience levels are on (project setting [code]progression[/code]).
func uses_levels() -> bool:
	return int(MDSGameplaySetup.setting("progression")) == MDSGameplaySetup.Progression.LEVELS

func get_level() -> int:
	return level_curve.level_for(xp) if level_curve and uses_levels() else 1

## Adds experience (an enemy defeated, with LEVELS); a new level fills health.
func add_xp(n: int) -> void:
	if n <= 0 or not uses_levels() or not level_curve:
		return
	var before := get_level()
	xp += n
	var now := get_level()
	if now > before:
		level_up.emit(now)
		notice.emit("Level %d" % now)
		var h := MDSHealth.of(_player())
		if h:
			h.set_max(player_max_health(), true)
	_changed()

func level_health_bonus() -> int:
	return (get_level() - 1) * level_curve.health_per_level if level_curve and uses_levels() else 0

func level_damage_bonus() -> float:
	return (get_level() - 1) * level_curve.damage_per_level if level_curve and uses_levels() else 0.0

# --- Death ----------------------------------------------------------------------------------------

## The player died ([MDSPlayer] calls it):
## [br]1. [signal player_died], one more death;
## [br]2. the death penalty (project setting [code]death_penalty[/code], [method apply_death_penalty]);
## [br]3. [member death_overview_time] seconds of the game's [MDSLevelOverview], if it has one,
## else [member death_delay];
## [br]4. back to the last bench ([method MDSWorldGame.return_to_save_point]), or with the setting
## [code]death_reverts_to_save[/code] the save is loaded (the penalty then applies to it);
## [br]5. health and mana full. Enemies that come back on a room load do; a boss fight lost resets.
## [br]Progress since the last save is kept, as MDS keeps the explored map.
func on_player_died(player: Node) -> void:
	deaths += 1
	player_died.emit()
	var g := get_game()
	var room := g.current_room if g else ""
	var at := _corpse_position(player)
	var reverts := g != null and bool(MDSGameplaySetup.setting("death_reverts_to_save")) and g.has_save_game()
	if not reverts:
		apply_death_penalty(room, at)
	if current_boss != "":
		var boss := current_boss
		current_boss = ""
		boss_node = null
		boss_ended.emit(boss, false)
	if not g or not is_inside_tree():
		return
	var overview := _level_overview(g)
	if overview and death_overview_time > 0.0:
		await overview.show_for(death_overview_time)
	else:
		await get_tree().create_timer(death_delay).timeout
	if not is_instance_valid(g) or not is_instance_valid(player):
		return
	if reverts:
		var kept_deaths := deaths
		if g.load_game():
			await g.room_loaded
		deaths = kept_deaths
		apply_death_penalty(room, at)
		_place_corpse()
	else:
		await g.return_to_save_point()
	if overview and is_instance_valid(overview):
		overview.close()
	if not is_instance_valid(player):
		return
	if player.has_method(&"revive"):
		player.call(&"revive")
	refill()

func _level_overview(g: MDSWorldGame) -> MDSLevelOverview:
	for c in g.get_children():
		if c is MDSLevelOverview:
			return c
	return null

## Where a corpse goes: where the player died, or its last safe ground when it died in the air
## (falling into a pit).
func _corpse_position(player: Node) -> Vector2:
	if player is CharacterBody2D and not (player as CharacterBody2D).is_on_floor() and "safe_position" in player:
		var safe: Vector2 = player.get("safe_position")
		if safe != Vector2.INF:
			return safe
	return (player as Node2D).global_position if player is Node2D else Vector2.ZERO

## Takes the currency the setting says: none (NONE), a share ([code]death_penalty_share[/code],
## LOSE_PERCENT), or all of it, left in an [MDSCorpse] at [param at] in [param room] (CORPSE):
## touching the corpse gets it back, dying again first loses it.
func apply_death_penalty(room: String, at: Vector2) -> void:
	match int(MDSGameplaySetup.setting("death_penalty")):
		MDSGameplaySetup.DeathPenalty.LOSE_PERCENT:
			var lost := int(floor(currency * float(MDSGameplaySetup.setting("death_penalty_share"))))
			if lost > 0:
				spend_currency(lost)
		MDSGameplaySetup.DeathPenalty.CORPSE:
			corpse.clear()
			if currency > 0 and not room.is_empty():
				corpse = {"room": room, "position": [at.x, at.y], "currency": currency}
				currency = 0
				currency_changed.emit(currency)

## The corpse was touched: its currency comes back.
func recover_corpse() -> void:
	if corpse.is_empty():
		return
	var amount := int(corpse.get("currency", 0))
	corpse.clear()
	add_currency(amount)
	notice.emit("Recovered %d" % amount)

## Puts the corpse in the room shown, when it lies there (and takes away one that doesn't).
func _place_corpse() -> void:
	var g := get_game()
	if not g or not g.room_node:
		return
	for c in g.room_node.get_children():
		if c is MDSCorpse:
			c.queue_free()
	if corpse.is_empty() or str(corpse.get("room", "")) != g.current_room:
		return
	var p: Array = corpse.get("position", [0, 0])
	if p.size() == 2:
		MDSCorpse.spawn(g.room_node, Vector2(float(p[0]), float(p[1])), int(corpse.get("currency", 0)))

# --- Feel ---------------------------------------------------------------------------------------

## Freezes the game for [param ms] milliseconds (hit-stop), if the feel setting is on: the time
## scale drops to [code]feel/hitstop_time_scale[/code] and comes back on a real-time timer.
func hitstop(ms: int) -> void:
	if ms <= 0 or not bool(MDSGameplaySetup.setting("feel/hitstop")) or not is_inside_tree():
		return
	if _hitstop_token == 0:
		_time_scale_before = Engine.time_scale
	_hitstop_serial += 1
	var mine := _hitstop_serial
	_hitstop_token = mine
	Engine.time_scale = float(MDSGameplaySetup.setting("feel/hitstop_time_scale"))
	await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
	# The last hit-stop asked for ends it (a later one may still be running).
	if is_instance_valid(self) and _hitstop_token == mine:
		_end_hitstop()

func _end_hitstop() -> void:
	if _hitstop_token != 0:
		Engine.time_scale = _time_scale_before
		_hitstop_token = 0

func _exit_tree() -> void:
	_end_hitstop()

# --- Rooms ----------------------------------------------------------------------------------------

## A new ability: a notice, and the popup (when the game has an [MDSAbilityPopup]).
func _on_ability_gained(ability: String) -> void:
	var data := get_ability_data(ability)
	if not data:
		data = MDSAbilityData.new()
		data.id = ability
	notice.emit("%s gained" % data.get_display_name())
	if not show_ability_popups or not get_game():
		return
	for n in get_tree().get_nodes_in_group(&"mds_ability_popup"):
		if get_game().is_ancestor_of(n) and n.has_method(&"show_ability"):
			n.call(&"show_ability", data)
			return

## A gate that needs something: "Requires Dash".
func _on_transition_blocked(_transition: Dictionary, missing: PackedStringArray) -> void:
	var names: PackedStringArray = []
	for r in missing:
		names.append(describe_requirement(r))
	notice.emit("Requires %s" % ", ".join(names))

## Enemies defeated since the last rest are gone again when their room loads; the corpse lies
## in its room.
func _on_room_loaded(_room: String) -> void:
	_place_corpse()
	var g := get_game()
	if not g or not g.room_node or rest_defeated.is_empty():
		return
	for n in g.room_node.find_children("*", "", true, false):
		if is_instance_valid(n) and n.owner == g.room_node and rest_defeated.has(g.object_id(n)):
			n.queue_free()

## An enemy fell ([MDSEnemy] calls it): it counts for the bestiary, and gives its XP.
func record_defeat(enemy: Node) -> void:
	var d: MDSEnemyData = enemy.get("data") if "data" in enemy else null
	var id := MDSGameplay.normalize_id(d.id) if d and not d.id.is_empty() else String(enemy.name).to_snake_case()
	if d:
		register_enemy_data(d)
	bestiary[id] = int(bestiary.get(id, 0)) + 1
	if d:
		add_xp(d.xp)

## Records enemy [param id] (an object id) as defeated until the next rest.
func defeat_until_rest(id: String) -> void:
	rest_defeated[id] = true

## A rest on a bench brings the ON_REST enemies back.
func on_rested() -> void:
	rest_defeated.clear()

# --- Save data ------------------------------------------------------------------------------------

func mds_save_key() -> String:
	return SAVE_KEY

## The kit's part of the save ([code]ext.gameplay[/code]).
func mds_get_save_data() -> Dictionary:
	return {
		"version": VERSION,
		"items": items.duplicate(),
		"currency": currency,
		"equipped": equipped.duplicate(),
		"equip_slots": equip_slots,
		"flags": flags.duplicate(true),
		"health": health,
		"max_health": max_health,
		"mana": mana,
		"max_mana": max_mana,
		"rest_defeated": rest_defeated.keys(),
		"shops": shops.duplicate(true),
		"corpse": corpse.duplicate(true),
		"play_time": play_time,
		"deaths": deaths,
		"xp": xp,
		"bestiary": bestiary.duplicate(),
	}

## Restores the kit's part of a save; empty data (a new game, a save made before the kit) starts
## from the defaults. Older versions are migrated first ([constant MIGRATIONS]).
func mds_set_save_data(data: Dictionary) -> void:
	_reset()
	if data.is_empty():
		_after_load()
		return
	var d := migrate(data.duplicate(true))
	for k in d.get("items", {}):
		items[normalize_id(str(k))] = int(d.items[k])
	currency = int(d.get("currency", 0))
	equipped.clear()
	for id in d.get("equipped", []):
		equipped.append(normalize_id(str(id)))
	equip_slots = int(d.get("equip_slots", starting_equip_slots))
	flags = (d.get("flags", {}) as Dictionary).duplicate(true) if d.get("flags", {}) is Dictionary else {}
	max_health = int(d.get("max_health", max_health))
	health = clampi(int(d.get("health", max_health)), 0, max_health)
	max_mana = int(d.get("max_mana", max_mana))
	mana = clampi(int(d.get("mana", max_mana)), 0, max_mana)
	for id in d.get("rest_defeated", []):
		rest_defeated[str(id)] = true
	shops = (d.get("shops", {}) as Dictionary).duplicate(true) if d.get("shops", {}) is Dictionary else {}
	corpse = (d.get("corpse", {}) as Dictionary).duplicate(true) if d.get("corpse", {}) is Dictionary else {}
	play_time = float(d.get("play_time", 0.0))
	deaths = int(d.get("deaths", 0))
	xp = int(d.get("xp", 0))
	bestiary = (d.get("bestiary", {}) as Dictionary).duplicate() if d.get("bestiary", {}) is Dictionary else {}
	_after_load()

## [param data] brought up to [constant VERSION] by [constant MIGRATIONS].
static func migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	while v < VERSION and MIGRATIONS.has(v):
		data = (MIGRATIONS[v] as Callable).call(data)
		var next := int(data.get("version", v + 1))
		v = next if next > v else v + 1
	return data

func _reset() -> void:
	items.clear()
	currency = 0
	equipped.clear()
	equip_slots = starting_equip_slots
	flags.clear()
	var s := get_stats()
	max_health = s.max_health
	health = max_health
	max_mana = s.max_mana
	mana = max_mana
	rest_defeated.clear()
	shops.clear()
	corpse.clear()
	play_time = 0.0
	deaths = 0
	xp = 0
	bestiary.clear()
	current_boss = ""

## The player takes the loaded health; every listener hears of the change.
func _after_load() -> void:
	var h := MDSHealth.of(_player())
	if h:
		h.set_max(player_max_health(), false)
		h.set_current(health)
	player_health_changed.emit(health, player_max_health())
	player_mana_changed.emit(mana, player_max_mana())
	currency_changed.emit(currency)
	equipment_changed.emit()
