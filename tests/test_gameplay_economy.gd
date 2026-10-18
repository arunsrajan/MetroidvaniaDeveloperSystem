extends "res://tests/test_case.gd"
## Gameplay Kit, phase 6: items, equipment, shops, NPCs and progression. Consumables are used up,
## keys are not, stacks cap; charms are put on only at a bench, cost slots, change stats and lend
## abilities only while worn, and are kept in the save; a shop sells by price and stock (kept in the
## save) and hides entries whose condition is unmet; an NPC's conversation follows the story
## (alt_dialogues) and sets flags; with LEVELS progression XP from enemies raises the level.

const Fixture := preload("res://tests/game_fixture.gd")
const P := MDSGameplaySetup.PREFIX

var game: MDSWorldGame
var kit: MDSGameplay
var player: MDSPlayer

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	Fixture.build()
	game = _game()
	add_child(game)
	await game.room_loaded
	await physics_frames(5)
	player.health.invulnerable = false
	_items()
	await _equipment()
	await _shop()
	await _npc()
	await _levels()
	game.queue_free()
	await get_tree().process_frame

func _game() -> MDSWorldGame:
	var g := Fixture.make_game()
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	g.add_child(kit)
	g.remove_child(g.player)
	g.player.free()
	player = load(MDSPlayer.SCENE).instantiate()
	g.add_child(player)
	g.player = player
	return g

func _item(id: String, category: MDSItemData.Category, effect: MDSItemEffect = null, value := 0) -> MDSItemData:
	var d := MDSItemData.new()
	d.id = id
	d.category = category
	d.effect = effect
	d.value = value
	kit.register_item(d)
	return d

func _items() -> void:
	var heal := MDSHealEffect.new()
	heal.amount = 2
	_item("potion", MDSItemData.Category.CONSUMABLE, heal)
	var key := _item("lamp", MDSItemData.Category.KEY, heal)
	key.max_stack = 1
	kit.add_item("potion", 2)
	check(not kit.use_item("potion") and kit.get_item_count("potion") == 2, "a potion does nothing at full health (kept)")
	player.health.take_damage(3)
	check(kit.use_item("potion") and kit.get_item_count("potion") == 1, "used: it heals and is used up")
	check(player.health.current == player.health.get_max() - 1, "healed by 2")
	kit.add_item("lamp", 3)
	check(kit.get_item_count("lamp") == 1, "max_stack caps a stack")
	check(kit.use_item("lamp") and kit.get_item_count("lamp") == 1, "a KEY is not used up")
	check(not kit.use_item("nothing"), "an unknown item can't be used")
	check(kit.get_items(MDSItemData.Category.CONSUMABLE) == ["potion"], "items by category")
	player.health.heal_full()

func _charm(id: String, cost: int, mods: Dictionary, grants: PackedStringArray = []) -> MDSEquipmentData:
	var d := MDSEquipmentData.new()
	d.id = id
	d.slot_cost = cost
	d.stat_mods = mods
	d.grants = grants
	kit.register_item(d)
	kit.add_item(id)
	return d

func _equipment() -> void:
	var base_speed := player.config.max_run_speed
	var base_health := player.health.get_max()
	var base_mana := kit.player_max_mana()
	_charm("swift", 1, {"max_run_speed": 100.0, "max_health": 2, "max_mana": 10, "damage": 1, "defense": 1}, ["dash"])
	_charm("heavy", 3, {"defense": 2})
	check(not kit.equip("swift"), "away from a bench a charm can't be put on (equip_at_bench_only)")
	var bench := MDSBench.new()
	bench.name = "Bench"
	bench.save_on_rest = false
	game.room_node.add_child(bench)
	bench.position = Vector2(300, 576)
	player.global_position = bench.global_position + Vector2(0, -40)
	await physics_frames(10)
	bench.rest(player)
	check(kit.can_change_equipment(), "resting on a bench it can")
	check(kit.equip("swift") and kit.is_equipped("swift"), "the swift charm is put on")
	await physics_frames(2)
	check_near(player.config.max_run_speed, base_speed + 100.0, 0.01, "it adds run speed (to a copy of the movement config)")
	check(player.movement.max_run_speed == base_speed, "the movement config itself is unchanged")
	check(player.health.get_max() == base_health + 2 and kit.player_max_mana() == base_mana + 10, "and health and mana")
	check(player.get_damage_bonus() == 1 and player.health.stats.defense == 1, "and damage and defense")
	check(game.is_condition_met("dash") and not game.has_ability("dash"), "it lends dash, not written to the game's abilities")
	check(player.has_ability("dash"), "the player can dash while it is worn")
	check(not kit.equip("heavy") and kit.get_used_slots() == 1, "a 3-slot charm doesn't fit with 1 of 3 used")
	var up := MDSSlotUpgrade.new()
	game.room_node.add_child(up)
	up.global_position = player.global_position
	await physics_frames(3)
	check(kit.equip_slots == 4 and kit.equip("heavy") and kit.get_used_slots() == 4, "a slot upgrade makes room")
	# Kept in the save.
	var data := game.get_save_data()
	kit.mds_set_save_data({})
	check(kit.get_equipped().is_empty() and not game.is_condition_met("dash"), "a new game wears nothing")
	kit.mds_set_save_data(data.ext.gameplay)
	await physics_frames(2)
	check(kit.get_equipped() == ["swift", "heavy"] and player.health.get_max() == base_health + 2, "a load wears them again")
	kit.unequip("swift")
	kit.unequip("heavy")
	await physics_frames(2)
	check_near(player.config.max_run_speed, base_speed, 0.01, "taken off: the speed is back")
	check(player.health.get_max() == base_health and kit.player_max_mana() == base_mana and player.health.stats.defense == 0, "and health, mana and defense")
	check(not game.is_condition_met("dash") and not player.has_ability("dash"), "and dash is gone")
	bench.leave()
	bench.queue_free()
	await physics_frames(2)

func _shop() -> void:
	var shop := MDSShop.new()
	shop.name = "Shop"
	shop.shop_id = "keeper"
	var inv := MDSShopInventory.new()
	var potion := kit.get_item_data("potion")
	var mapd := _item("map_scrap", MDSItemData.Category.COLLECTIBLE, null, 50)
	var shard := MDSMaxHealthEffect.new()
	var mask := _item("mask_shard", MDSItemData.Category.UPGRADE, shard, 0)
	var lantern := _item("lantern", MDSItemData.Category.KEY)
	inv.entries = [
		{"item": potion, "price": 30, "stock": 2},
		{"item": mapd, "stock": -1},
		{"item": mask, "price": 40, "stock": 1},
		{"item": lantern, "price": 5, "stock": 1, "condition": "flag:met_keeper"},
	]
	shop.inventory = inv
	game.room_node.add_child(shop)
	shop.position = Vector2(500, 560)
	kit.currency = 0
	kit.add_currency(150)
	var offers := shop.get_offers()
	check(offers.size() == 3, "3 on sale; the lantern waits for flag:met_keeper")
	check(shop.get_price(1) == 50, "a price of 0 is the item's value")
	var potions := kit.get_item_count("potion")
	check(shop.buy(0) and kit.currency == 120 and kit.get_item_count("potion") == potions + 1, "bought a potion for 30")
	check(shop.get_stock(0) == 1, "one left")
	var max_before := player.health.get_max()
	check(shop.buy(2) and player.health.get_max() == max_before + 1, "a mask shard (UPGRADE) raises max health at once")
	check(shop.buy(0) and shop.get_stock(0) == 0 and not shop.buy(0), "sold out after two")
	check(kit.currency == 50 and shop.buy(1) and kit.currency == 0 and not shop.buy(1), "endless stock, but no money left")
	kit.set_flag("met_keeper")
	check(shop.get_offers().size() == 4 and not shop.can_buy(3), "the lantern shows up; too dear now")
	var data := game.get_save_data()
	kit.mds_set_save_data({})
	check(shop.get_stock(0) == 2, "a new game restocks")
	kit.mds_set_save_data(data.ext.gameplay)
	check(shop.get_stock(0) == 0 and shop.get_stock(2) == 0 and shop.get_stock(1) == -1, "the stock is kept in the save")
	var opened := [false, false]
	shop.shop_opened.connect(func() -> void: opened[0] = true)
	shop.shop_closed.connect(func() -> void: opened[1] = true)
	await shop.talk()
	check(opened[0] and opened[1], "talking opens (and with no shop screen, closes) the shop")
	shop.queue_free()
	await physics_frames(2)

func _npc() -> void:
	var npc := MDSNPC.new()
	npc.name = "Elder"
	npc.npc_name = "Elder"
	npc.dialogue = MDSDialogueData.make("elder_hello", "Elder", ["Welcome, traveller."])
	npc.dialogue.lines[0].set_flag = "met_elder"
	var after := MDSDialogueData.make("elder_warden", "Elder", ["The Warden is gone.", "You have a lamp!"])
	after.lines[1].condition = "item:lamp"
	after.lines[1].set_flag = "elder_saw_lamp"
	var later := MDSDialogueData.make("elder_bye", "Elder", ["Farewell."])
	npc.alt_dialogues = [{"condition": "boss:Warden", "dialogue": after}, {"condition": "flag:met_elder", "dialogue": later}]
	game.room_node.add_child(npc)
	npc.position = Vector2(700, 545)
	check(npc.get_dialogue() == npc.dialogue, "first, its own dialogue")
	await npc.talk()
	check(MDSGameplay.truthy(kit.get_flag("met_elder")), "a line sets its flag (no dialogue box: at once)")
	check(npc.get_dialogue() == later, "then the alt dialogue whose condition is met")
	game.defeat_boss("Warden")
	check(npc.get_dialogue() == after, "the first met wins (boss:Warden)")
	check(npc.get_lines(after).size() == 2, "a line whose condition is met is said")
	kit.remove_item("lamp")
	check(npc.get_lines(after).size() == 1, "and skipped when it isn't")
	player.global_position = npc.global_position
	await physics_frames(3)
	check(npc.player_near() and npc._label != null and npc._label.visible, "standing at it shows its prompt")
	npc.queue_free()
	await physics_frames(2)

func _levels() -> void:
	var enemy_data := MDSEnemyData.new()
	enemy_data.id = "crawler"
	enemy_data.xp = 12
	var e := MDSWalker.new()
	e.data = enemy_data
	kit.add_xp(50)
	check(kit.xp == 0 and kit.get_level() == 1, "UPGRADES progression: no XP")
	ProjectSettings.set_setting(P + "progression", MDSGameplaySetup.Progression.LEVELS)
	var curve := MDSLevelCurve.new()
	curve.base_xp = 10
	curve.health_per_level = 1
	curve.damage_per_level = 1.0
	kit.level_curve = curve
	var max_before := player.health.get_max()
	var levels: Array = []
	kit.level_up.connect(func(l: int) -> void: levels.append(l))
	kit.record_defeat(e)
	check(kit.xp == 12 and kit.get_level() == 2 and levels == [2], "an enemy's XP raises the level (%d, level %d)" % [kit.xp, kit.get_level()])
	check(player.health.get_max() == max_before + 1 and player.health.current == player.health.get_max(), "a level fills health and adds to it")
	check(player.get_damage_bonus() >= 1, "and adds damage")
	var data := kit.mds_get_save_data()
	kit.mds_set_save_data({})
	kit.mds_set_save_data(data)
	check(kit.xp == 12 and kit.get_level() == 2, "XP is kept in the save")
	ProjectSettings.set_setting(P + "progression", null)
	e.free()
