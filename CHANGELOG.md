# Changelog

All notable changes to the Metroidvania Developer System. Versions follow [Semantic Versioning](https://semver.org/): a new major version can need changes in your project (see the README's upgrading notes), a minor one only adds.

## [3.4.0] - 2026-10-18

### Added

- **Gameplay Kit** (`addons/MetroidvaniaDeveloperSystem/gameplay/`, see the README): the gameplay half of a Metroidvania, plugged into `MDSWorldGame`.
  - **Hub:** `MDSGameplay` under the game holds items, currency, equipment, story flags, health and mana, saved with the game in `ext.gameplay` (versioned, `MIGRATIONS`). `MDSGameplaySetup` adds the input actions, collision layer names and settings a project lacks.
  - **Conditions:** `item:<id>`, `item:<id>>=<n>` and `flag:<name>` work in gate and barrier `requires`, objectives, dialogue and shops, and in the Progress tab. `MDSGateBarrier.consume_items` uses the items up; the map gate behind the open barrier still lets the player through.
  - **Player:** `MDSPlayer` (`gameplay/player/mds_player.tscn`) on `MDSStateMachine` / `MDSState`, tuned by `MDSMovementConfig` (coyote time, jump buffer, jump cut, apex gravity, corner correction, slopes, one-way platforms), with `MDSInputBuffer`. It is `Locked` while rooms change and sits on benches.
  - **Abilities:** `MDSAbilityData` and twelve ability states (double jump, wall jump, dash, air dash, slide, ledge grab, climb, swim, glide, grapple, ground pound, super attack) plus charge attack and parry, each only while granted. `MDSAbilityPickup`, `MDSAbilityPopup`, `MDSClimbable`, `MDSGrapplePoint`, `MDSSwimZone` (`MDSWater.swimmable`).
  - **World objects:** `MDSPickup`, `MDSHealthUpgrade`, `MDSManaUpgrade`, `MDSSlotUpgrade`, `MDSCurrencyPickup`, `MDSBreakable`, `MDSSwitch`, `MDSCheckpoint`, `MDSLoreTablet`, all persistent through MDS's stored objects or flags.
  - **Combat:** `MDSHitbox`, `MDSHurtbox`, `MDSHealth`, `MDSKnockback`, `MDSDamageInfo`, `MDSAttackController` (combos, up and down attacks, pogo, charge, spells, parry), `MDSProjectile`, `MDSHazard`. Hit-stop, `MDSRoomCamera.shake()`, a hit flash shader, rumble and `MDSDamageNumber` (off by default), each a setting. MDS's lava and steam vents hurt the player as they are.
  - **Enemies and bosses:** `MDSEnemy` with `MDSEnemyData`, `MDSDropTable` and `MDSPlayerDetector`; templates `MDSWalker`, `MDSFlyer`, `MDSTurret`, `MDSCharger`, `MDSAmbusher`; `MDSSpawner`. `MDSBoss` with `MDSBossPhase`s, `MDSBossArena` and `MDSArenaDoor`, using MDS's boss music and camera director.
  - **Items and economy:** `MDSItemData` and its effects (`MDSHealEffect`, `MDSMaxHealthEffect`, `MDSManaEffect`, `MDSBuffEffect`), `MDSEquipmentData` charms, `MDSShop` and `MDSShopInventory`, currency, `MDSCorpse` (the death penalty), `MDSLevelCurve`.
  - **Dialogue:** the text comes in letter by letter (`MDSTextRevealLetters`, with a beat after punctuation), word by word (`MDSTextRevealWords`), at once, or in a style of your own (extend `MDSTextReveal`). Set it per line, per conversation or on the box, and the player's **Text speed** option (Slow, Normal, Fast, Instant) scales it. Lines `from_player` are the player's, named and pictured on the right. The other side is named after who speaks (`get_dialogue_name()`). `MDSDialogueTrigger` puts a conversation on any object (interact or touch, once, a condition, story alternatives; in the Effects tool's Gameplay Objects), and bosses say a `defeat_dialogue` as they fall.
  - **NPCs and UI:** `MDSNPC`, `MDSDialogueData` / `MDSDialogueLine`; `MDSHud`, `MDSToast`, `MDSPauseMenu` (Map, Inventory, Equipment, Journal, Bestiary, Options, Quit), `MDSInventoryScreen`, `MDSEquipmentScreen`, `MDSShopScreen`, `MDSDialogueBox`, `MDSTitleScreen` (3 save slots), `MDSOptionsMenu` and `MDSOptions` (volumes, rebinding, display, game speed, assist mode, shake and flash, camera motion, text size, glyphs, toggled glide), `mds_gameplay_theme.tres`.
  - **Editor:** Create game scene builds the kit's player, hub and UI (**Include gameplay kit**, on by default). The Room view's Effects tool has **Gameplay Objects**. New Issues checks: an ability pickup without data, an item no pickup grants, a boss arena without a boss or doors, a boss whose name differs from its room's. A jump-arc preview for `MDSMovementConfig` (`MDSMovementInspectorPlugin`), and debug keys F1–F7 (`MDSGameplayDebug`).
  - **Demo:** `examples/gameplay_demo/`, 12 rooms in two areas: double jump, the Warden, dash, the red key, the bridge switch, wall jump, the ending. Its rooms are built by MDS's own tools (Convert to freeform, Decorate freeform) with the Mossgrove and Sunken Gardens packs, and `build_gameplay_demo.gd` builds them again. Each ability is needed where the route says, and its test plays the whole route with simulated input.
  - **Tests:** `tests/test_gameplay_*` (conditions, save, movement, abilities, world objects, combat, enemies, boss, analysis, death, economy, player in a game, scene tools, demo).

- **Full view** (tool panel > View): every room of the layer where it is on the map, at its real size, with its scene. Each room's outline is in its area's color, with its name, its gates and the area names. It works on an empty world too.
  - **Draw rooms first:** Rectangle, Ellipse, Polygon and Curvy draw outlines at the rooms' real size, showing the paint cells they will take. **Generate map** makes them rooms on the map: one room each, or split into rooms with doors like a generated area, in a new area, none, or one of the world's. The rooms keep the outline's curves, and get doors to what they touch. **Caves too** makes their scenes and caves as well. One Ctrl+Z takes it back to the outlines.
  - **Rooms tool:** select rooms and outlines (click, Ctrl or Shift+click, a box), move them (rooms by paint cells, stopping against others, with doors where they touch), delete them, nudge them with the arrows. Ctrl+Z / Ctrl+Y undo on the map. A double-click, **Edit selected** or **Room view** edits the rooms selected in the Room view.
  - **Generate area** drags a box for the Generate area dialog.
  - **Painting:** a press in any room with a Room painting tool edits it, making a scene for it when it has none. Each room keeps its changes and undo, **Save** saves them all, and **Generate all** / **New variation for all** make caves in the rooms selected, or all of them.
  - Scenes dropped on it become rooms where they were dropped.
  - Big worlds open at once. Zoomed out, rooms show their pictures (read from the shared cache off the main thread, or drawn in the background the first time) and no scene. Zoomed in, the scenes of the rooms in view come in a few a frame, nearest the middle first, at most 40 at once, and rooms the view leaves let go of theirs.
  - Map: right-click a room > **Show in the Full view**.
  - In code: `MDSRoomSketches` (outlines kept in the world file as `"sketches"`, and `generate()`), `MDSRoomView.open_full()`, `MDSFullViewTools`.
- **Parallax foregrounds:** `MDSParallaxBackground.foreground` puts layers in front of the room and the player that move faster than the room: `foliage` (also hanging from the top edge), `cave_rocks`, `ruins`, `mist`, or your own `foreground_layers` (`MDSParallaxLayer.hang` hangs one from its line). They draw over the room's foreground and are see-through in the editor. Specs take them (`parallax(preset=misty_forest, foreground=foliage)`, `preset=none` for a foreground alone), and the Parallax fields' **+** menu has them under **In front of the room**.
- **Several rooms in the Room view:** an area, or the rooms selected on the map, show together where they are on the map. One is edited and the others show around it, dimmed.
  - A click in another one edits it, and the press goes on there. Each keeps its changes and its own undo meanwhile, and painting stops where another room starts.
  - **Save** saves them all, **<** and **>** go from one to the next, and **Generate all** / **New variation for all** make caves in every one, joined at their doors.
  - Changes made in the editor to any of their scenes show too.
  - In code: `MDSRoomView.open_rooms()`, `activate_room()`, `generate_all()`.
- **Several rooms selected on the map:** Ctrl+click adds a room or takes it out, Ctrl+drag on empty space selects a box of them, Ctrl+A selects all of the layer's and Esc none.
  - Dragging one moves them all: they stop against other rooms and get doors where they touch. The arrows nudge them and Delete deletes them, each with one undo.
  - Right-click: **Edit the N rooms in the Room view**, **Merge the N rooms into one...**; for the room's area, **Edit area X in the Room view** and **Merge area X's rooms into one...**.
  - In code: `MDSWorldCanvas.get_selected_rooms()`, `select_rooms()`, signal `selection_changed`.
- **Merge rooms:** rooms of the map become one (`MDSWorld.merge_rooms()`).
  - The kept room keeps its id, scene and settings; the others' rectangles, curved outlines and outer gates join it, renamed where a name is taken.
  - Gates, links, the start room and objectives that named them name it. The gates between them go, kept as doors between its parts.
  - Options: bring their scenes' tiles, items and nodes into its scene where they were (`MDSWorldSceneTools.combine_room_scenes()`, `prepare_merged_scene()`); generate its cave, with walls where the old rooms met and openings at their doors, and a variation of it; open it in the Room view.
  - Generate cave keeps those walls in merged rooms (the **Merged walls** option; `fills.parts`), and paths reach each old room through its doors.
- **Import map image** (World menu, a picture dropped on the map, or right-click on empty space): a picture of a map becomes rooms, areas and doors. That can be an MDS or MetSys export, another tool's map, a drawing or a screenshot (`MDSMapImageImporter`, `MDSMapImportDialog`).
  - The grid is found by itself, across and down on their own, or set by hand. Colors become areas, and wall lines part rooms.
  - Gaps in walls and gate markers become connected gates, and rooms no door reaches get one.
  - A preview shows what it found, and one undo takes it back.
- **Map image exports have a sidecar** (`<png>.mdsmap.json`) that says where the grid is, so Import map image puts the rooms back exactly where they were.

- **Machinery backgrounds** (`MDSMachineryBackground`): giant machinery far behind the room, soft and out of focus, one kind at a time, fixed in the world and moving by time alone: neither the player nor the camera moves them. They are laid out over the room in screen-sized cells.
  - **Gothic (20)**, for Castlevania-style castles: giant wheels, clockwork, clock faces, pendulums, bells, chandeliers, rose windows, hanging chains, candelabra, winches, spiked rollers, hourglasses, organ pipes, banners, astrolabes, torches, windmills, swinging axes, saw blades and castle spires.
  - **Sci-fi (20)**, for Metroid-style stations: turbines, reactor cores, gyro rings, pistons, energy conduits, radar dishes, holograms, ringed planets, robot arms, drills, tesla coils, exhaust fans, bio pods, specimen tanks, data streams, laser sweeps, warp portals, crystal pylons, press hammers and cargo lifts.
  - Each machine has its look and layout: hanging, standing, spread about, or one big one in front.
  - Background fields take `clockwork`, `turbines(count=8)` or `storm_clouds, castle_spires`; the **+** menu lists them.

- **Benches** (`MDSBench`): save points to rest on, after Silksong's benches.
  - An iron bench with a cushion and a lantern that flickers and lights it, motes drifting up, all drawn by a shader.
  - **Up** at it sits the player down: held still, healed, the game saved. The bench glows, threads of light rise and a ring of light spreads out.
  - Place it from the Room view's Effects tool.
- **Saving and continuing** in `MDSWorldGame`:
  - `save_game()` writes `save_file`; `load_on_start` continues from it on the bench it was saved at;
  - `return_to_save_point()` takes the player back after dying;
  - `new_game()`, `has_save_game()`, `load_game()` and `delete_save_game()` cover the rest;
  - new signals: `game_saved` and `game_loaded`.
- **The map remembers:** the exploration file keeps the benches found too, and a restarted game's map shows every room explored, also after the last save.
- **Minimap:** `MDSWorldMapView.follow_player`, with `view_span`. The map also marks benches, the last one rested on brighter. Created game scenes get a minimap and save files named after the world.
- **Big room scenes explained:** a room's scene over 512 KiB (Godot's editor then warns that it is "large on disk") makes the Room view say what is in it, when it opens or saves it. It lists the layers, the biggest first, and marks the hidden ones, whose tiles are saved all the same (`MDSRoomPainter.size_note()`).
- **Clear background** in the Room view, beside Fill background.
- **Big scenes are shown in sight:** a room's scene over 512 KiB makes the Room view show why, in orange above Generate cave.
  - With hidden layers to blame, **Clear hidden tiles** shows there too: it removes the tiles of the tile layers hidden in the scene (they never show) and saves. Ctrl+Z brings them back.
  - In code: `MDSRoomPainter.hidden_tiles()` and `MDSRoomView.clear_hidden_tiles()`.
- **Resize handles** in the Room view: eight of them, on the corners and the middles of the sides (left, top, right, bottom and the four corners).
  - They are on what the Select tool selected, on what the Place and Stamps tools placed last, on the Freeform tool's shape and on the selected effect (which had only a corner).
  - Dragging one moves its sides and the opposite ones stay. Shift on a corner keeps the shape; Snap to tiles puts the sides on the grid. The cursor shows which way a handle resizes.
  - Stamps, pictures and free tiles scale, freeform shapes scale their points, and grid tiles become scaled free tiles. A steam vent keeps its feet put.
  - In code: `MDSRoomCanvas.resize_selection()` and `resize_effect()`.
- **The Room view follows the editor:** changes made to the room's scene in Godot's editor show in the Room view a moment later. That covers nodes moved in the 2D editor, tiles painted there, settings changed in the Inspector, and nodes added or deleted.
  - It works from the scene open in the editor, changes not saved yet included.
  - The Room view's own changes not saved yet stay, merged tile by tile and item by item. Where both changed the same one, the editor's wins. Undo still undoes only the Room view's own changes.
  - Saving takes in the editor's changes first.
  - The Room view's items are changed in place and never leave the tree. The Inspector keeps what it shows, its sections unfolded as they were, and a change in the editor never takes it over. A click on the selected effect shows it in the Inspector again.
  - In code: `MDSRoomView.sync_from_scene()`, `MDSRoomPainter.open_packed()`, `rebase_onto()` and `merge_states()`.
- **Machinery backgrounds follow the camera when asked:** `scroll_scale` (1 by default: fixed in the world; less is farther away; 0 stays on the screen) and `follow_camera` (cover the whole view in the game; off by default), as on the other backgrounds.

### Changed

- Waterfalls, hot water falls and lava falls fall straight. Their sides are straight and their streaks run in straight lanes; the lava's crust rides down in straight strands. There are no ragged sides, bulges or curves any more.
- `MDSWorldGame.save_file` (`user://mds_save.json`), `exploration_file` (`user://mds_exploration.json`) and `load_on_start` are on by default. Clear the paths to turn them off.

### Fixed

- **A barrier that needs `boss:<name>` opens when the boss falls.** It opened only when its room loaded again.
- **The camera director no longer reports a negative `Rect2`** when the view is smaller than its on-screen inset (a headless run framing a boss).
- **Decorate freeform's ceiling corners hang from the ceiling.** The foreground mass looked for the ceiling upward from the middle of the room, 200 px in from each side: starting inside rock (a column, a thick wall) or under a ledge, it took that for the ceiling and hung from above the room all the way down to it, over doorways, ledges and open room. It now finds the ceiling's underside going down from the room's top (ledges aren't ceilings), follows it, and stops where the ceiling ends or steps, and short of doorways, objects, ledges and the room above them.
- **Generate caves for an area from the map works again.** With the Room view closed, it stopped before generating anything.
- **Saving one room in the Room view says it saved.** It went on to say "Could not save … (error 0)".
- **Markers on the map with a title and a description:** `MDSWorldGame.add_map_marker(where, kind, title, description, options)` marks a place (a world position, a node, or a room) on the game's maps, and `mark_boss_room()`, `mark_locked_door()` (saying what the gate needs), `mark_key()` and `mark_quest_target()` (one id, moved as the quest goes on) do the usual ones. Each kind has its icon in a badge: pin, boss (skull), locked_door (padlock), key, quest (star), danger, treasure, note, and kinds of your own (`MDSWorldMapView.define_marker_kind()`, with an icon or a texture); a marker can have a color and icon of its own. Pointed at (the mouse, or the middle of the map on a gamepad), its description shows in a box (`show_marker_info`, `marker_focused`, `focus_pin()`). They are kept and saved like the pins below, descriptions and looks too.
- **The pause menu's map zooms out below the whole map** (`min_zoom`, a quarter by default), the map small in the middle; zoomed out, only the marker pointed at shows its title.
- **Pins on the map while playing:** `MDSWorldGame.add_map_pin(world_pos, kind, label, id)` puts a pin on the map: the player's own, a quest's goal (the same id moves it), a danger. `pin_player_position()`, `remove_map_pin()` and `clear_map_pins(kind)` are there too, and `map_pin_added` / `map_pin_removed` tell when pins change. The game keeps them like the explored map (in the exploration file at once, and in the save) and shows them on its maps as flags in their kind's color, with their labels (`MDSWorldMapView.pin_colors`). On the pause menu's map a click puts a pin and a click on one of the player's own takes it away, and **Pin where I am** pins the player. A map of your own takes clicks with `pins_editable` (`pin_requested`, `pin_clicked`). The editor's World map shows the last playtest's pins with the rest of what it explored.
- **The pause menu's map zooms and moves** (`MDSWorldMapView.zoomable`): the mouse wheel zooms around the mouse, and so do `map_zoom_in` / `map_zoom_out` (RT / LT, = / -), up to `max_zoom`. A drag or `map_pan_*` (the right stick, I J K L) moves it, never off the rooms. It opens on the player. Marks and pins keep their size, and clicks put pins where they point at any zoom. The six new actions are in `MDSGameplaySetup.ACTIONS`, so the Options menu rebinds them.
- **Explored rooms have a marker on the maps.** The game's map (`MDSWorldMapView`) puts a check mark on each room explored (`show_explored_marks`) and a pin where the player is (`player_marker_color`), instead of a small dot. On the editor's World map, **Show on map... > Explored in the last playtest** shows what the last playtest explored: check marks on the rooms explored, the others dimmed, the benches found and a pin where the player was (`MDSWorldGame.read_exploration()`). The exploration file now says which world it belongs to and the room the player is in, and is written as each room is entered.
- **The Full view shows the tileset in the tile palette and the fills.** With no room edited, the tile palette was empty and so was the Fill list. Both now show the rooms' tileset (`room_tileset`), and tiles picked there become the Terrain brush's fill (`MDSRoomPainter.for_tile_set()`).
- **The Full view no longer hangs on big worlds.** Zoomed out to fit, it loaded every room's scene in one frame (1.7 s for 141 rooms), and each pan went through every scene's nodes again (100 ms). Asking whether each room's scene file is there was a file system call per room per frame: `MDSWorld.get_scene_path()` now remembers the answer for a couple of seconds, and forgets it as the world changes (`scene_file_exists()`). Opening that world now takes 90 ms, its worst frame 60 ms, a pan 11 ms.
- **No crash on quitting after room pictures were drawn.** `MDSRoomPictures` saved pictures on worker threads in script functions nobody waited for, and Godot crashed on quit. The saves now run an engine method, keep their image until it is saved, and are waited for as the Room view and the pictures node leave the tree.
- **Rooms shown together no longer hide each other.** Generate cave fills an L, T or U room's whole box with rock, and its rock in the notches covered the rooms there. Such a room's tiles now show only inside its rectangles, and the rest of it goes under the other rooms.
- **Only the view shown has its button pressed** in the tool panel's View section.
- **Links follow their gates.** Renaming or removing a gate left a link's gate end (`a_gate`, `b_gate`) naming the old gate.
- **Tilesets no longer embed images.** Godot writes an image embedded in a `.tres` out byte by byte, so the starter tileset was 850 KiB of text.
  - The starter tileset's atlas is now the PNG next to it (linked in the editor, packed without loss elsewhere), and the solid colors' tile is packed.
  - A tileset made by an older version is mended when a room opens with it: images of 64x64 or more become PNG files next to it, smaller ones are packed. Its tiles stay the same; a starter tileset with a sheet added went from 916 KiB to 70 KiB.
  - A packed image in a tileset loaded outside the editor (tests, tool scripts) lets go of its data. It is packed again before the tileset is saved, so it is never saved empty.
- **`follow_camera` off stops following the camera.** Unticked, creatures still moved with the camera, and so did animated backgrounds and parallax layers: it only kept them to their rectangle.
  - Off, every background now lies on its rectangle, fixed in the world: the camera moves nothing, whatever `scroll_scale` says. That covers animated backgrounds, creatures, parallax backgrounds and machinery.
  - Creatures not following the camera live all over their rectangle, and their size is in screens of the game's height (`MDSEnvironmentEffect.screen_height()`).
  - Vignettes darken the screen's corners, wherever the camera is.
- **Animated backgrounds and creatures move at the right pace with the camera.**
  - Their drift was measured in 648 px units, so it was only right in a view 648 px high at zoom 1. With another window size, a stretched view or a zoomed camera, they slid against the room.
  - Their drift is now measured in the view's height, so at `scroll_scale` 1 they are fixed in the world and at 0.5 they move half as fast as the room, whatever the view.
  - A test renders all four kinds of background and measures it.
- **No empty screen after a room change.** The room camera glides between the camera zones of an irregular room (`zone_blend_time`). A player who moved into another zone and went through a gate before that glide ended (down a hole from a room's lower part, often the first time) arrived in the new room with the camera still on the old one. The glide kept setting the old room's limits over the new room's, so the screen showed the old room, unloaded: nothing. `MDSRoomCamera.enter_room()` now ends any glide first, and zones don't change while the game changes rooms.
- **Going up into the room above, through a hole in its floor, works.** Coming up through a `bot` gate, the player arrived over the middle of the hole with nothing pushing it sideways. It rose, fell straight back through the hole, and landed in the room below again; a room was unreachable from below. It is now set down at the rim of the hole, on the nearest floor beside it (`MDSWorldGame.land_beside_holes`, `ledge_beside()`), and keeps its hop.
- **A gate entered just after arriving is no longer lost.** Gates are ignored for a moment after the player arrives (`gate_cooldown`). One gone into meanwhile, a hole dropped back into, was ignored for good, and the player fell out of the room forever. It is now taken once the cooldown ends, if the player is still in it or went through it.
- **Generate cave and New variation move the gate nodes onto the new doorways.** The gate nodes kept their old places and sizes, half a tile or more off the openings the cave carved. Each `MDSGate` now goes to its opening's middle on the room's edge, its collision box across it (128 x 48), as part of the generation's undo step. The Room view draws the gate boxes and names the map gates with no node. In code: `MDSRoomPainter.gate_openings`, `fit_gate_nodes()`, `gate_boxes()`; `MDSGate.get_opening_size()`.
- **Stamps and effects keep their names through undo.** Undone, they came back nameless, and were saved as new nodes named `_Sprite2D_…`.
- **Erased tiles are no longer saved.** A tile layer outside the scene tree keeps erased cells, and the cells its data replaced, as empty entries until it updates. Room scenes saved by MDS kept every tile they ever had, and never shrank. `MDSWorldSceneTools.repack_safely()` drops them (`drop_erased_cells()`).

## 3.3.0 (2026-10-13)

### Added

- **Trace drawing has four ways to draw.** **Draw with** picks one:
  - freeform styles, as before;
  - **solid colors**: shapes filled with the drawing's own colors, or ones you pick;
  - **tiles**: each color paints the room's grid with a terrain, tiles of a kind, palette tiles from a spritesheet, or solid tiles of its color;
  - **the drawing itself**, kept as it is drawn (`MDSDrawing`). It is split into pictures behind the terrain, at its depth and in front, with its paper cut out by a shader. **Collision for its terrain** gives it invisible freeform shapes that follow the drawing, like `CollisionPolygon2D`; platforms get one-way ones.
  - Replace the last trace replaces traced tiles and pictures too.
  - The room remembers how it was traced.
- **Turning palette tiles** anywhere from 0 to 360 degrees, and mirroring them.
  - The brushes paint them on the grid at the nearest right angle; the pattern and the tiles' collision turn with them.
- **Place tool:** puts the palette's tiles anywhere in the room, off the grid, at that angle.
  - These free tiles are small `TileMapLayer`s in the scene's `Tiles` node. They draw and collide like their layer's tiles, and Check room sees them.
- **Select tool:** select grid tiles, free tiles, stamps, pictures and freeform shapes. Click them, Shift+click to add, or drag a box.
  - Drag the selection to move it by pixels, or by whole tiles with **Snap to tiles**. Grid tiles moved off the grid become free tiles; **To grid** puts them back.
  - **R** / **Shift+R** turn the selection, the arrows nudge it, and **Delete** removes it.
- `MDSRoomPainter`:
  - `add_tile_piece()`, `lift_cells()`, `merge_piece()`, `is_piece_on_grid()`;
  - `item_at()`, `item_outline()`, `add_drawing()`;
  - `flags_basis()` and `basis_flags()`, for tile flip and transpose flags.
- Invisible freeform colliders (a style that draws nothing) are outlined in the editor.

## 3.2.0 (2026-10-12)

### Added

- **Creature backgrounds for boss rooms** (`MDSCreatures`). Twenty kinds of glowing creature, one kind per background: bees, wasps, lumaflies, moths, butterflies, dragonflies, small birds, crows, bats, firebirds, spiders, beetles, centipedes, snails, crabs, jellyfish, glowfish, eels, owls and worms.
  - Drawn soft and out of focus; each creature's light lights its habitat as it moves.
  - They react to the player: activity, jolts, `startle()` and `excitement`.
  - They never collide or hurt.
  - Background fields take `bats`, `owls(count=3)` or `blood_moon, bats`.
- **Ten Silksong-style effects:** silk threads, will-o'-wisps, a gnat swarm, dripping water, hanging moss, swaying grass, cobwebs, void tendrils, incense smoke and forge sparks.
  - Grass and moss part around the player, tendrils reach for it, gnats gather around it, webs tremble and slow it, and sparks and tendrils can hurt.
  - New weather presets: `weavenest`, `bilewater`, `wisp_thicket`, `deep_docks` and `wormways`.
- `MDSEnvironmentEffect.body_points()` and `send_bodies()`, for effects of your own that react to bodies.
- Continuous integration: the test suite runs on Godot 4.6.1 and 4.7.2 for every push and pull request.

### Changed

- The editor tab is now **MetDevSys** (it was Map Dev).
- The addon folder has a README of its own, and the README's screenshots are no longer imported into the project (`docs/.gdignore`).

## 3.1 (2026-10-10)

### Added

- **Animated backgrounds** (`MDSAnimatedBackground`): twenty soft, out-of-focus shader styles (bokeh, aurora, nebula, deep water, storm clouds, a starfield, your own picture blurred...). Five are made for boss rooms: void pulse, blood moon, arcane vortex, infection and holy light.
  - Set per room, per area, for the boss rooms, or for the world.

### Changed

- The plugin's data took MDS names too: `mds_*` metadata and groups, `*.mdsworld.json`, `MapData.mds.json`, `mds_kind` and the `metroidvania_developer_system/*` project settings.
  - The old `idp` names are still read (`MDSLegacy`).
  - The Room view renames them in the scenes it opens.

## 3.0 (2026-10-08)

### Added

- **Environment effects**, by area or by drag and drop: dust storms, rain, lightning, snow, fog, embers, fireflies, falling leaves, light shafts, heat haze, steam vents, lava, waterfalls and water.
- Later 3.0 updates added parallax backgrounds, hot water and lava falls, and falling rocks.
- **Trace drawing:** a picture's colors become freeform shapes.
- **Parallax backgrounds** and a hybrid **area map generator**: curved and slanted outlines split into rooms with doors.
- Caves that follow curved room outlines, with paths between all gates, backtracking included.
- Whole areas can be moved with the Select tool.
- The room camera zooms between rooms.

### Changed

- Every class and node was renamed from `IDP*` to `MDS*`.

## 2.2 (2026-10-05)

### Added

- The nineteen feature briefs from Lost in the Sky:
  - safe saving and broken-tile repair;
  - 2.5D depth and a camera director;
  - room dressing and room checks;
  - convert to freeform, decorate and fill outside the room's shape;
  - room pictures, and more.

## 2.1 (2026-10-03)

### Changed

- Packaged as the **Metroidvania Developer System** addon (`addons/MetroidvaniaDeveloperSystem/`).

## 2.0 (2026-09-30)

### Added

- MetSys mode and the **non-linear** world map mode, with painting, analysis and a game runtime.
- Shape brushes, a spritesheet tile palette and a MetSys-style tool panel.
- The room camera, a detachable panel and safer room loading.
- Freeform terrain, stamps and a foreground layer.
- The Mossgrove asset pack.

## 1.0 (2026-05-17)

### Added

- **Interactive Dev Panel**: a map overview of a MetSys project, with:
  - save points, collectibles and teleporters marked on it;
  - zoom and fit to view;
  - export to PNG.
