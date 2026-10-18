# Gameplay Kit: decisions

Choices made where the design spec (MDS Gameplay Kit, Oct 17 2026) is silent or contradicts
itself, closest to how MDS already behaves. Newest at the bottom of each section.

## Conditions and data

- **Ids are lowercase, words joined by `_`.** Item ids, flag names and ability names are
  normalised (`"Red Key"` is `red_key`), as MDS already does for requirements typed in the panel
  (`MDSAnnotations.parse_list`). `MDSGameplay.normalize_id()`.
- **`parse_condition()` keeps returning `[kind, target]`.** For `item:health_fragment>=4` the
  target is `health_fragment>=4`; `MDSAnnotations.parse_item_requirement()` splits it into the id
  and the count, so existing callers that expect two elements are unchanged.
- **Map gate `requires` understand every condition.** `MDSWorldGame._on_gate_entered()` used
  `has_ability()` for gate requirements; it now uses `is_condition_met()`, so `item:` and `flag:`
  (and `boss:`, `object:`) block map gates too. Bare names are abilities, as before.
- **Equipment lends abilities to conditions too.** `MDSWorldGame.is_condition_met()` treats an
  ability lent by equipment worn (`MDSGameplay.has_equipped_ability()`) as met, so a charm's
  ability opens gates and barriers while it is worn. It is never written to
  `MDSWorldGame.abilities`.
- **Barriers re-check on the kit's changes.** `MDSGateBarrier` listened to `ability_gained` and
  `room_loaded` only; it now also listens to `MDSGameplay.item_changed`, `flag_changed` and
  `equipment_changed`, else an `item:` or `flag:` barrier would only open on the next room load.
- **The scanner counts grants.** `item:x>=n` needs `n` grants of `item:x`, and a scene's
  `grants` list is de-duplicated, so the scanner also records `grant_counts` (grant -> number of
  nodes). The analysis counts each room once per grant node.
- **"Required but never granted" matches grant keys.** The Issues check compared requirement
  strings with grant strings; `item:health_fragment>=4` is now satisfied by `item:health_fragment`
  grants and `ability:dash` by `dash` (`MDSAnalysis.grant_key()`).
- **`MIGRATIONS` is a static var, not a constant.** GDScript constants can't hold Callables.
- **Defaults:** the player starts with 5 health and 33 mana, mana full (the spec's save example
  shows 30 / 33); mana refills at benches.
- **`MDSGameplay.find(game)` only looks at the game's direct children** (and caches the result in
  the game's `mds_gameplay` metadata): the game calls it on every condition check.

## Setup

- **Setup runs whenever the editor starts, not only on enable.** `_enable_plugin()` is not called
  for a project that already had the plugin enabled, so `plugin.gd` runs
  `MDSGameplaySetup.ensure_input_actions()` and `ensure_layer_names()` in `_enter_tree()`. Both only
  add what is missing and save `project.godot` only when they did.
- **Special is V and grapple F.** The spec's default keys put special on A and grapple on S while
  also moving with WASD; A and S are WASD's left and down, so the action cluster keeps Z (jump),
  X (attack), C (dash) and takes V and F instead. Up (and W) is both move up and interact, as the
  bench expects.
- **A game run without the actions gets them at runtime.** A project made before the kit, a test or
  an exported game whose settings lack them: `MDSGameplaySetup.ensure_runtime_actions()` adds them
  to the running InputMap (never to the project).
- **Two more folders.** `MDSNPC` and `MDSShop` (an NPC) live in `gameplay/npc/` rather than
  `world/`, and the editor-facing `MDSMovementInspectorPlugin` and `MDSGameplayDebug` in
  `gameplay/editor/`.
- **Files changed beyond the spec's named hooks**, each only to add what the kit needs and with
  the old behaviour kept:
  - `scene_scanner.gd`: counts grants (`grant_counts`, for `item:x>=n`) and records the data of
    the new Issues checks.
  - `core/room_painter.gd`: `effects()`, `effect_at()` and `effects_at()` also return the gameplay
    objects the Room view placed (group `mds_gameplay_placed`), so their return type is `Node2D`
    instead of `MDSEnvironmentEffect`; environment effects come back as before.
  - `ui/room_canvas.gd`: places, selects and resizes the Room view's gameplay objects.
  - `world_panel.gd`: the Create game scene dialog with its **Include gameplay kit** checkbox.
  - `tests/run_all.gd`: unpauses the tree and resets the time scale between test scenes, so one
    scene's open menu or hit-stop can't stall the next.

## Player

- **Gates see the player's layer.** The player body is on the `player` layer (3), and `MDSGate`
  areas only look at layer 1 by default, so `MDSGameplay` adds the player's layer to the collision
  mask of every gate that enters the tree. Enemies and the player pass through each other (they
  only touch through hitboxes), as in Hollow Knight.
- **Interactables also see layer 1.** Pickups, switches, climbables and swim zones look for the
  `player` layer and layer 1 (`MDSGameplaySetup.player_detect_mask()`), so a player body of your own
  left on layer 1, as MDS's gates expect, can use them too. They only react to the `player` group.
- **The body is a 28 x 60 rectangle with its origin in the middle**, as `MDSBench.spawn_offset`
  (-32) and `MDSWorldGame._player_extent()` assume. A rectangle keeps ledge and wall checks exact.
- **Input is polled each physics frame** (`Input.is_action_pressed`, and an `MDSInputBuffer` noting
  presses), not taken from `_unhandled_input`: the bench and doors handle their own presses there,
  and nothing the player does consumes them.
- **Attacks run alongside movement.** `MDSAttackController` times attacks by frame data while the
  player keeps running and jumping (Hollow Knight's model); the `Attack` state is only used for
  the charged attack, which roots the player.
- **Slide is down + dash on the ground; ground pound is down + dash in the air.** The spec doesn't
  say which inputs; down + attack in the air is already the pogo attack, and `special` is spells.
- **Glide is jump held while falling.** A fresh jump press in the air is tried first (the double
  jump has a higher priority than the glide), so holding jump after an air jump glides.
- **Two more abilities ship as data:** `charge_attack` and `parry`, which the attack controller
  uses (Section 8 mentions both), beside the twelve movement and combat abilities.
- **Hit-stop ends by token.** Each hit-stop restores the time scale only if it is still the latest
  one asked for; comparing end times missed by a millisecond and left the game in slow motion.
- **Hold-to-toggle is for glide only.** The options' "Glide: press to toggle" sets
  `MDSPlayerGlideState.toggled`: a jump press while falling starts the glide (a double jump, when
  there is one, comes first) and the next press ends it. The spec also names dash, but the kit's dash
  is a single press, never held, so a toggle for it would change nothing.

## Combat

- **Damage is `max(1, round(amount × resistance × multiplier) − defense)`.** The spec names the
  inputs, not the order; defense is subtracted last so a resistance of 0.5 still halves a big hit,
  and every hit does at least 1 unless the resistance is 0.
- **Lava respawns.** `MDSLava` and `MDSLavaFall` hurting the player through `mds_environment_hurt`
  count as a pit: the player loses health and goes back to its last safe ground (or the room's
  checkpoint), like spikes in Hollow Knight. Other effects (steam vents, rockfall) only hurt.
- **A checkpoint's respawn point is 32 px above it**, so the player isn't put in the floor.
- **The projectile's fall is `drop`**, not `gravity`: Area2D already has a `gravity` property.
- **Hit flash is a shader** (`shaders/hit_flash.gdshader`) set on the body's visual while it flashes,
  turned off by the `feel/hit_flash` setting or the options' flash slider.
- **Pogo off hazards.** A hazard has no hurtbox (nothing to hurt), so the player's attack hitbox
  also looks at the `enemy_hitbox` layer and a hazard's hitbox is monitorable: an active down attack
  in the air that touches a HAZARD hitbox bounces the player, without hit-stop or mana. One bounce
  per swing, whatever it hit.
- **Damage numbers** are shown by `MDSHealth` for each hit that does damage (`MDSDamageNumber`, in
  the body's parent), while `feel/damage_numbers` is on. Breakables and switches take hits without
  health, so they show none.
- **Hitboxes and hurtboxes join the groups `mds_hitbox` and `mds_hurtbox`** (`MDSHitbox.GROUP`,
  `MDSHurtbox.GROUP`), for the F1 overlay.

## Enemies and bosses

- **Enemies come back after a rest by default** (`respawn = ON_REST`, Hollow Knight). The ones
  defeated since the last rest are kept in `ext.gameplay.rest_defeated` by object id, so a save
  and load doesn't bring them back early; NEVER uses MDS's `mark_defeated`.
- **A spawner's enemies are not saved**: they come back whenever their room loads.
- **Health comes from the data's stats.** An enemy built in code gets its stats before its health
  enters the tree (a health made first would keep its default 5).
- **The boss fight resets when the player dies**: the room is left, so the boss and arena load
  fresh; `boss_ended(boss, false)` is sent first, so the HUD and music know.
- **Boss music is the arena's `music`, else the boss's, else the area's `boss_music`**, played by
  `MDSMusic.play_boss()` when the fight starts.
- **Boss states are inner classes** (Dormant, Idle, Swipe, Charge, Slam, Volley, Stagger, Dead);
  a phase change staggers the boss, and its attacks speed up by the phase's `speed`.
- **`MDSGameplay` doesn't listen to `MDSWorldGame.defeated`.** An `MDSEnemy` rolls its own drops
  and reports its defeat (`record_defeat()`, the Bestiary and XP) as it dies, and arenas reset by
  being loaded again, so the signal would only repeat that. Ability popups (`ability_gained`) and
  rest-defeated enemies (`room_loaded`) work as the spec says.

## Items, economy and death

- **Equipment adds to `max_mana` too**, like `max_health` (`player_max_mana()`); mana is clamped
  when a charm comes off.
- **A shop's stock is kept per shop id and item id** (`ext.gameplay.shops[shop][item]`). A shop's
  id is its `shop_id`, else its object id. A bought UPGRADE item with an effect (a mask shard)
  applies it at once; other items go to the inventory.
- **Talking to a shop greets, then opens the shop screen** (the node in group
  `mds_shop_screen`); with none in the game it does nothing more.
- **An NPC with no dialogue box in the game still sets its lines' flags**, so story flags don't
  depend on the UI.
- **The corpse lies where the player died, or at its last safe ground when it died in the air**
  (falling into a pit), so it can always be reached.
- **With `death_reverts_to_save`, the penalty applies after the load**, to the saved currency;
  otherwise the corpse would hold currency the save gives back as well.
- **The death overview is off by default** (`MDSGameplay.death_overview_time = 0`): the spec
  makes it optional; with a time and an `MDSLevelOverview` child of the game, it pulls back for
  that long (skippable) instead of `death_delay`.

## Editor integration and Demo world

- **`MDSAnalysis` boss grants:** `MDSAnalysis` treats room `boss_names` from room meta as grants
  prefixed by `boss:` (`boss:<name>`), so progression analysis recognizes boss defeat as unlocking
  subsequent spheres (`boss:Warden` gating Grove_06).
- **Gameplay issue validators:** the Issues tab (`MDSValidator`, `MDSWorldValidator`) reports the
  spec's checks only: an ability pickup with no `MDSAbilityData`, an item or flag required (by a
  gate, a barrier or an objective) that nothing grants, a boss arena with no boss or no doors, and
  an `MDSBoss` whose `boss_name` differs from its room's `boss`. The scanner records what they need
  (`ability_pickups_without_data`, `invalid_boss_arenas`, `boss_nodes`).
- **Scene tree pause cleanup:** `MDSGameplayScreen` and `MDSAbilityPopup` clean up their pause state
  via `Engine.get_main_loop()` in `_exit_tree()`, ensuring tree pause never persists when rooms or
  game instances are freed dynamically.
- **Headless test camera cuts:** Scripted multi-room tests set `MDSRoomCamera.room_transition = CUT`
  and `transition_time = 0.0` so room load sequences execute without transition delay timers.
- **Room view enemies are the template scenes** (`enemies/templates/mds_<kind>.tscn`,
  `MDSRoomCanvas.enemy_template()`), standing on the floor where clicked (their origin is their
  middle); flyers hover 100 px above it.
- **F2 grants the abilities the world file names**: room grants and gate requirements
  (`MDSWorld.get_known_abilities()`) that are abilities, not items, flags, bosses or objects.
- **The title screen goes through the game's save API.** For each slot it points
  `save_file` at the slot's file, asks `has_save_game()` / `read_save_game()` /
  `delete_save_game()`, and puts the game's own file back; Continue and New game keep the slot's
  file, as the spec says.
- **Glyphs follow the options.** The ability popup shows gamepad buttons when the options' input
  glyphs say so (Auto: when a gamepad is connected); its `gamepad_glyphs` export forces them.
- **The demo is blocked out.** Its rooms are plain collision floors with the kit's objects, and its
  test drives the intended route room by room (`load_room()`, collecting, switching) rather than
  playing it with inputs; painting the rooms with the Mossgrove and Sunken Gardens packs and a
  fully played route test are still to do.
