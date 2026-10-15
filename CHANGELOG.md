# Changelog

All notable changes to the Metroidvania Developer System. Versions follow [Semantic Versioning](https://semver.org/): a new major version can need changes in your project (see the README's upgrading notes), a minor one only adds.

## Unreleased

### Added

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
