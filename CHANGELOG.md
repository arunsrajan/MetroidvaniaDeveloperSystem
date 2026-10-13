# Changelog

All notable changes to the Metroidvania Developer System. Versions follow [Semantic Versioning](https://semver.org/): a new major version can need changes in your project (see the README's upgrading notes), a minor one only adds.

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
