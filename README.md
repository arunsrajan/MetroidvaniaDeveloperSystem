# InteractiveDevPanel

A Godot 4 editor plugin that turns your metroidvania's world into a design workbench: room and boss labels, ability gates, progression and backtracking analysis, map validation, and exports you can share with your team.

It has two modes, switched from the first drop-down in the toolbar:

| | **MetSys mode** | **Non-linear mode** |
|---|---|---|
| Map | MetSys' grid map (`MapData.txt`) | Free-form world map, like Hollow Knight's |
| Rooms | Cells painted in the MetSys editor | Drawn on the map or dropped in as scenes, any size and shape |
| Connections | MetSys passages | Named gates (`left1`, `right1`, `door1`...) like Hollow Knight transitions |
| Saved in | `MapData.idp.json` (annotations next to `MapData.txt`) | `*.idpworld.json` |
| Game runtime | MetSys' `MetSysGame` | Built in: `IDPWorldGame`, `IDPGate`, `IDPWorldMapView` |
| Needs MetSys | Yes | No |

Both modes share the analysis: progression spheres, backtracking, save distance, routes, topology, validation, stats and exports.

## Requirements

- Godot 4.6 or newer (tested on 4.6.1 and 4.7.2; older 4.x versions are untested)
- **MetSys** 1.6 installed and enabled, for MetSys mode only

## Installation

Copy the `InteractiveDevPanel` folder into your project's `addons/` directory and enable **Interactive Dev Panel** in **Project Settings > Plugins**. A **Map Dev** tab appears at the top of the editor, next to 2D / 3D / Script.

Prefer a right-side dock? Set `interactive_dev_panel/use_main_screen` to `false` in Project Settings and re-enable the plugin.

---

## Non-linear mode

![Non-linear world map, colored by area](docs/nonlinear_map.png)

Draw the world the way it will be seen by the player: rooms of any size and shape, placed anywhere, grouped into colored areas, connected by named gates. There is no grid of cells to map rooms onto; each room *is* its scene, placed on the map at its real size.

### How the format works

The world file borrows proven designs:

- **Free world layout** (LDtk's *Free* layout, Tiled's `.world` files): every room is a scene at an x/y position in world pixels.
- **Hollow Knight transitions**: each room has named gates (`left1`, `right2`, `top1`, `bot1`, `door1`); each gate stores its target room and the entry gate there. A gate whose target doesn't lead back is a one-way transition (a drop, a collapsing floor).
- **Hollow Knight map zones**: rooms belong to named, colored areas.

```json
{
  "format": "idp_world", "version": 1, "name": "Pharloom",
  "settings": {"grid": 32, "default_room_size": [1152, 648], "save_distance_warn": 4},
  "layers": ["Main"],
  "areas": {"The Greenhouse": {"color": "#5b6fd6", "map_zone": "GREENHOUSE"}},
  "rooms": {
    "Greenhouse_01": {
      "scene": "uid://b3x...", "scene_path": "res://rooms/greenhouse_01.tscn",
      "area": "The Greenhouse", "layer": 0,
      "origin": [4608, 1296],
      "rects": [[0, 0, 1152, 648], [1152, 324, 576, 324]],
      "gates": {
        "right1": {"pos": [1728, 580], "side": "right", "to": "Greenhouse_02", "to_gate": "left1", "requires": ["dash"]}
      },
      "type": "boss", "boss": "Moss Mother", "status": "blockout", "grants": [], "notes": ""
    }
  },
  "links": [], "pins": [], "start_room": "Greenhouse_01"
}
```

- `origin` is where the scene's (0, 0) sits on the world map.
- `rects` and gate `pos` are in the scene's own coordinates, so they line up with the nodes in the scene.
- Scenes are stored by UID (with the path for readability), so moving files never breaks the map.
- It's plain JSON: easy to diff and merge, and your game can read it at runtime.

### Getting started

In the toolbar's world picker:

- **New world...** creates an empty `.idpworld.json`.
- **Import from MetSys map...** converts a MetSys map (with your annotations) into a world. Cells merge into rectangles, and passages become named, connected gates.
- To see a bigger example, copy [`examples/demo.idpworld.json`](examples/demo.idpworld.json) into your project and open it.

Then:

1. **Draw rooms** with the **Room** tool (`R`): drag a rectangle. It snaps to the world grid.
2. **Or place scenes**: drag `.tscn` files from the FileSystem dock onto the map. Each becomes a room sized to its terrain, and gate nodes in the scene become map gates. Dropping one scene on a room that has none assigns it.
3. **Shape rooms** with **Extend** (`E`) to add rectangles (L, T, U shapes...) and the resize handles.
4. **Connect rooms** with the **Gate** tool (`G`): click a room's edge to add a gate, then drag from one gate to another gate (or to a room edge, which creates the gate for you). **Scenes > Auto-connect facing gates** pairs every facing, unconnected gate that's close enough.
5. **Group rooms into areas** in the **Areas** tab: pick colors, map-zone ids, and which area new rooms join. Drag area names on the map to reposition them.
6. **Create the scenes**: double-click a room without a scene (or right-click > **Create scene...**). You get a new scene with `MapBounds` guides showing the room's shape and one `IDPGate` per gate, and it opens in the editor. **World settings** can point to your own scene template.

### Painting the map, then dropping scenes in

You can design the whole map before any scene exists, the way a hand-drawn metroidvania map is sketched, and fill it with scenes afterwards.

1. **Pick a style** in the toolbar's **Style** drop-down. This is the tileset rooms are drawn with, tinted by each area's color, and the in-game map (`IDPWorldMapView`) uses it too. The choices are:
   - **Hand-drawn (double line)**, the default: light border band, dark inner line, tinted fill.
   - **Blueprint**, **Chunky pixel**, or **Flat**.
   - **Any MetSys map theme** (Exquisite, SotN, AoS...). Walls and corners come from the theme, and gates show as the theme's passages.
   - **Custom tileset PNG...**: your own tileset (see below).
2. **Pick an area** in the Areas tab (**Use for new rooms**) so painted rooms get its color.
3. **Paint** with the brush (`B`), in cells of the world's paint grid, shown while painting:
   - drag on empty space to paint a new room;
   - start a stroke inside a room to grow it (L, T and U shapes are fine);
   - hold **Shift** to start a separate room next to another one;
   - the brush never paints over another room;
   - `[` and `]` (or **Brush** in the toolbar) change the brush size.
4. **Erase** (`X`) removes cells from any room. A room erased completely is deleted.
5. **Add doors:** **Scenes > Add doors between touching rooms** puts a connected gate pair on the longest shared edge of every pair of touching rooms.
6. **Drop scenes in:** drag scenes from the **Scenes** palette tab (with thumbnails, hiding scenes already placed) or from the FileSystem dock onto a painted room. The room keeps its painted shape, the scene's (0, 0) goes to the room's top-left corner, and a generated name (`Room_03`) becomes the scene's name. Dropped on empty space, a scene becomes a new room sized to its terrain. Rooms without a scene can also get a brand new one with **Create scene...**.

The paint grid defaults to a quarter of the default room size. Change it in **Scenes > World settings > Paint cell**. Painting stores ordinary rectangles, so painted and dragged rooms mix freely. Painting a room that was sized from an off-grid scene snaps its shape to the paint grid.

![Map styles](docs/map_styles.png)

![Hand-drawn style up close](docs/map_style_closeup.png)

**Custom tilesets.** **Style > Save tileset template PNG...** writes the current built-in tileset as a starting point. Edit it, then choose **Style > Custom tileset PNG...** to use it. The layout is 4 columns x 5 rows of square tiles:

- Tiles 0-15 are indexed by which sides of the cell are room edges: 1 = top, 2 = right, 4 = bottom, 8 = left. Tile 0 is a cell inside a room; tile 15 is a lone cell.
- Row 5 holds the inner corners of concave shapes: top-left, top-right, bottom-right, bottom-left.
- Draw in white and grays: tiles are multiplied by the area color.

### Room view: painting the room itself

The map is one view of a room; the **Room view** is the other. It shows the room at its real size and lets you paint what's inside it. Open it with **Room view** above the map, **Paint room** in the Inspector, or right-click > **Paint room (actual view)**. A room that has no scene yet gets one first.

![Map view and Room view](docs/map_and_room_view.png)

- **Brushes:**
  - **Terrain** paints autotiled ground and walls, using Godot's terrain system.
  - **Background** paints foliage behind the room.
  - **Decor** places grass, ferns, flowers, mushrooms, vines, stalactites or hanging moss.
  - **Erase** removes decorations and terrain; Shift+Erase removes background.
  - `[` and `]` change the brush size; the wheel zooms and middle/right drag pans.
- **Generate cave** builds a starting room from the room's shape on the map. It places rough cave walls, a floor and ledges jutting from the walls, keeps openings wherever the room has gates, then adds background foliage and decorations. **New variation** rerolls it and **Auto-decorate** redoes only the decorations. Everything stays inside the room's shape, and irregular rooms get rock in their notches.
- **Save** writes the tiles into the room scene's `Background`, `Terrain` and `Decor` TileMapLayers (creating the missing ones) and touches nothing else in the scene. A scene open in an editor tab is reloaded. The map's silhouette updates from the terrain, so the two views stay in sync. Leaving the Room view saves automatically.
- **Tiles:** with no tileset, IDP generates a starter pixel-art "mossy cave" set at `res://idp_tiles/idp_cave_tileset.tres`. It has moss-topped rock with collision and autotiling, a cave wall, teal foliage and decorations, and a PNG copy sits next to it for repainting. Rooms that already have a TileSet keep it: its terrains appear in the Terrain picker, and tiles with an `idp_kind` custom data string (`grass`, `vine_top`, `stalactite_small`, `foliage`...) are used by the Decor brush and Auto-decorate. Change the default in the world file's `settings.room_tileset`.

Only solid tiles (with collision) count as terrain for the map silhouette. Background and decoration layers never do.

### Editing

| Input | Action |
|---|---|
| `V` / `R` / `E` / `G` / `P` | Select, draw room, extend room, gate, pin tools |
| `B` / `X` | Paint brush, eraser (Shift+stroke: new room; `[` / `]`: brush size) |
| Drag room | Move (snaps its top-left corner to the grid) |
| Drag handle | Resize a rectangle of the selected room |
| Drag from a gate | Connect to another gate; `Shift`+drag moves the gate along the edges |
| Double-click | Open the room's scene (or create one) |
| `Shift`+click | Route from the selected room |
| `Delete` | Delete the selected gate, else the selected room |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo (100 steps) |
| `Ctrl+D` | Duplicate the room |
| Arrows | Nudge the room one grid step |
| Wheel, middle/right drag, drag on empty space | Zoom, pan |
| Right-click | Open/create/assign scene, play from here, fit to scene, add gate, set start, route, link, duplicate, delete, pins |

Everything saves automatically to the world file. It reloads if the file changes on disk (after a `git pull`, for example).

### Keeping map and scenes in sync (Inspect tab)

- **Fit to scene** resizes the room to the scene's terrain (TileMapLayers and static collision).
- **Import from scene** adds or moves map gates to match the scene's gate nodes. Any node named `left1`, `right2`, `top1`, `bot1` or `door1` counts, as do nodes in the `idp_gate` group and `IDPGate` nodes. Connections can come from `idp_to_room` / `idp_to_gate` node metadata.
- **Write to scene** adds an `IDPGate` node for every map gate the scene is missing. It never deletes nodes, and refuses to write a scene that's open in an editor tab.
- Each gate row has its name, its target, **requires** (abilities or keys), **One-way**, unlink and delete.
- **Room ID** is the id your game uses (Hollow Knight uses scene names like `Crossroads_01`). Renaming it updates every gate that points to it.
- Saving a room scene rescans it, so markers, terrain and gate checks stay current.

### At runtime: IDPWorldGame (no MetSys needed)

Non-linear mode comes with its own game runtime. **`IDPWorldGame`** is the counterpart of MetSys' `MetSysGame`, and it reads the same `.idpworld.json` you edit in the panel. **Scenes > Create game scene...** generates a runnable one: an `IDPWorldGame` root with a placeholder player, a following camera and an in-game map. Swap in your player and press F6.

```
Game (IDPWorldGame)     world_file, starting_room, starting_gate, player, camera, map_view
├── Player              any Node2D; CharacterBody2D velocity is reset on room changes
│   └── Camera2D        clamped to the current room on every room change
└── UI/Map (IDPWorldMapView)
```

It handles:

- **Rooms:** one room scene loaded at a time, placed at its world position, so world coordinates match the map in every room. It starts in `starting_room` (or the world's start room) at `starting_gate`, the room's save point, or its middle. There's an optional fade between rooms.
- **Transitions:** every `IDPGate` in a loaded room is wired up automatically. Entering one loads the target room and spawns the player just inside the entry gate. A short cooldown stops players bouncing straight back.
- **Seamless rooms** (`seamless_rooms`): walking into a touching room loads it without a gate.
- **Requirements** (`enforce_requirements`): gates whose map requirements the player lacks emit `transition_blocked(transition, missing)` instead.
- **Progress:** `grant_ability()` / `has_ability()`, `store_object()` / `is_object_stored()` for collected items and opened walls (`object_id(node)` gives stable ids), visited rooms and the current area.
- **Save data:** `get_save_data()` / `set_save_data()` restore room, position, abilities, visited rooms, stored objects and the map's reveal state. `set_save_data()` works before or after the game enters the tree.
- **Signals:** `room_changed(from, to)`, `area_changed(from, to)`, `room_loaded(room)` (emitted last), `transition_blocked(transition, missing)` and `ability_gained(ability)`.
- **Helpers:** `load_room(room_or_scene, entry_gate, world_position)`, `get_room_bounds()`, `apply_camera_limits(camera)`, `get_room_name()`.
- **Play from here** works automatically: the game implements `idp_play_from()`.

```gdscript
extends IDPWorldGame

func _ready() -> void:
    super()
    room_changed.connect(func(_from, to): print("Entered ", get_room_name(to)))
    area_changed.connect(func(_from, area): show_area_title(area))
    transition_blocked.connect(func(_t, missing): show_hint("Needs " + ", ".join(missing)))

func _on_dash_pickup_collected(pickup: Node) -> void:
    grant_ability("dash")
    store_object(pickup)            # stays collected after leaving the room and in saves
```

**`IDPGate`** is the transition node, the equivalent of Hollow Knight's TransitionPoint. It's an `Area2D` named like its map gate (`left1`, `door1`...); **Write to scene** adds them for you. `IDPWorldGame` handles it automatically. With your own game code, connect `player_entered(transition)`, which carries `{room, gate, scene_path, entry_pos, side, from_room, from_gate}`, or call `IDPWorld.get_cached(path).get_transition(room_id, gate_name)`.

**`IDPWorldMapView`** is an in-game map Control following Hollow Knight's rules: rooms appear once visited, or dimmed once the player owns the map of their area. `IDPWorldGame` updates it for you. On its own:

```gdscript
map_view.world_file = "res://world.idpworld.json"
map_view.mark_visited(room_id)
map_view.map_area("The Greenhouse")        # when the area map is bought
map_view.set_player(room_id, player.position)
```

### Non-linear checks (Issues tab)

On top of the shared progression and design checks:

- rooms without a scene, missing scenes, and scenes used by two rooms;
- unconnected gates, gates pointing to missing rooms or gates, and one-way transitions that aren't marked one-way;
- connected gates that are far apart on the map;
- overlapping rooms;
- scene terrain extending past the room drawn on the map;
- gate nodes in a scene that aren't on the map, and the reverse.

![Progression in non-linear mode](docs/nonlinear_progression.png)

---

## MetSys mode

![MetSys mode: map on the left, room inspector on the right](docs/panel.png)

MetSys mode works on the map painted in the MetSys editor.

1. Open the **Map Dev** tab. The map configured in MetSys Settings (`map_data_file`) loads automatically, and its room scenes are scanned in the background.
2. Click a room to inspect it; double-click to open its scene. Shift+click a second room to see the route between them.
3. Name rooms, set their type (boss, save, shop...), mark boss names and the abilities they grant in the **Inspect** tab.
4. Type the ability a door needs (for example `dash`) next to that exit.
5. Check the **Issues** tab.

What you type is saved to `MapData.idp.json` next to `MapData.txt`; MetSys' own file is never modified.

- **Exact room shapes.** Cells are grouped into rooms exactly like MetSys does it, so irregular rooms are drawn with their real outline and hit-tested per cell.
- **Doors.** Passages are gaps in the wall. Ability-gated doors show a colored lock, one-way doors an arrow, custom MetSys borders are orange, and a passage to nowhere is a red `?`.
- **Terrain silhouettes** from each room's TileMapLayers and static collision, or **live scene previews** (View menu).
- **Color modes:** MetSys colors, room type, area, progression, save distance, build status.
- **Right-click menu:** open scene, play from here, run the room scene, set start, route, link, pins, copy UID or cell.
- **Links** in the Inspector connect rooms MetSys can't: elevators, teleporters, layer transitions.
- **MetSys checks:** cells without a scene, unresolved UIDs, passages to nowhere, passages painted on one side, open edges, scenes split across regions, terrain outside the room's cells, empty cells, and scenes with a RoomInstance that aren't on the map (**Scan > Scan project folder**).

Mouse: wheel zooms, middle/right drag pans. Keys: `F` fits, `+`/`-` zoom, `Esc` clears.

---

## Shared features

### Progress tab
Randomizer-style progression from the start room (the first save room by default):

- **Spheres:** everything reachable with no abilities is sphere 0; the abilities found there unlock sphere 1, and so on.
- **Backtrack entries:** for each sphere, the exact door to go back to with the new ability.
- **Locked** rooms are never unlocked; **not connected** rooms have no path at all.
- **Abilities & keys:** where each is found and every door it opens. Select one to highlight it on the map.
- **Topology:** dead ends, chokepoints (rooms whose removal splits the map) and hubs.

### Issues tab
Clickable issues that jump to the room. Shared checks:

- **Progression:** locked and disconnected rooms, abilities required but never granted, and abilities granted but never required.
- **Design:** bosses more than 2 rooms from a save point, rooms far from any save, and dead ends with no reward.
- **Notes:** `todo` and `bug` pins, and TODO lines in room notes.

### Stats tab
Rooms, areas, bosses (with sphere and distance to a save) and build status progress.

### Scene metadata
The scanner detects features by group and node name (whole words, so `Walking` never counts as a `king`):

- **Collectibles:** groups `collectible`, `item`, `pickup` (and plurals)
- **Enemies:** groups `enemy`, `monster`, `hostile`
- **Save points:** groups `save_point`, `savepoint`, `save`, `checkpoint`, `bench`, or names containing `savepoint`/`bench`/`checkpoint`
- **Bosses:** groups `boss`, `mini_boss`, or names with the words `boss`, `king`, `queen`, `lord`, `guardian`
- **Shops:** groups `shop`, `merchant`, `vendor`, `trader`, or those names
- **Teleporters:** groups `teleporter`, `warp`, `portal`, `fast_travel`, or those names (gate nodes are never counted as teleporters)

| Metadata | On | Meaning |
|---|---|---|
| `idp_grants` | pickup node | Abilities or keys given here, for example `"dash"` |
| `idp_requires` | gate or breakable wall near an exit | The closest exit needs these abilities |
| `idp_boss_name` | boss node | Marks and names the boss |
| `idp_room_type` | scene root | Overrides the inferred room type |
| `idp_to_room`, `idp_to_gate` | gate node (non-linear) | Where the gate leads, used by **Import from scene** |

### Play from here
**Play from here** runs the game starting in the chosen room: the Inspector button starts at the room's save point (or its middle), the right-click menu at the exact spot you clicked. No game code is needed for MetSys-style games:

It works the same in both modes:

1. The panel picks the **game scene** that hosts the room: a scene whose root script extends `MetSysGame`, has a `starting_map` property, or has a `load_room(path)` method. With one such scene per level, the one closest to the room in the file tree wins (for example `levels/level2/main/scene_main.tscn` for rooms in `levels/level2/`).
2. It runs a small launcher scene (not your main menu). For `starting_map` games it sets `starting_map` to the room and `custom_run = true` (the MetSys template's flag that stops a save file from moving you elsewhere) before switching to the game scene; for `load_room` games it calls `load_room(room)` once the game is running.
3. Once the room is loaded, the player (the game's `player`, the `player` group, or a node named `Player`) is placed at the chosen spot, using the loaded room's transform, so it's right whether your game puts rooms at the origin (MetSys) or at their world position (non-linear streaming).

A non-linear world played through a `MetSysGame` host only works if its rooms are also on the MetSys map, because `MetSysGame.load_room` reads MetSys' room data; non-linear games usually have their own `load_room`.

To force a host scene, set **Project Settings > interactive_dev_panel/play_scene** (or **World settings > Play scene** in non-linear mode). With no game scene at all, the room scene runs on its own.

Games that load rooms their own way can add one method to the game scene's root script; the launcher then calls it and does nothing else:

```gdscript
func idp_play_from(request: Dictionary) -> void:
    await load_room(request.scene_path)
    player.position = request.position   # room-local position of the chosen spot
```

During such a run `IDPRuntime.active_request` holds the request (handy for skipping intros); in normal runs it's empty.

### Exports
**Export** writes to `res://idp_exports/`:

- **JSON:** map data and annotations (or the world), plus progression and the scan database
- **PNG:** the whole current layer at high resolution
- **Graphviz `.dot`:** the room graph clustered by area, with gated doors labeled and one-way doors as arrows (`dot -Tsvg map.dot -o map.svg`)
- **Markdown design document:** summary, progression, bosses, rooms by area, open issues

## Designing a Hollow Knight-style world

- **Block out first.** Draw rooms (non-linear) or paint cells (MetSys), set their status to `blockout`, and use the *Build status* color mode to see what still needs art.
- **Draw rooms any shape.** Layout issues tell you when a scene's terrain no longer matches the map.
- **Gate with abilities, then check the order.** Put requirements on gates and grants on pickups. The Progress tab proves every area is reachable and lists every backtracking moment.
- **Bench before the boss.** The Save distance mode and the boss check keep runbacks short.
- **Reward dead ends.** Dead ends without an item, NPC or shortcut are flagged.
- **Name areas like a cartographer would.** Areas drive map colors, stats, and the in-game map's "bought the area map" reveal.
- **Use one-way transitions on purpose.** Drops and collapsing floors are fine; the Issues tab only asks you to confirm them.
- **Leave notes on the map.** Pins (note / todo / secret / bug / idea) live in the data file and show up for the whole team.

## File structure

```
addons/InteractiveDevPanel/
├── plugin.gd              # EditorPlugin: main screen tab (or dock), scene-save hook
├── dock.gd / dock.tscn    # Mode host: switches between the two panels
├── metsys_panel.gd        # IDPMetSysPanel: MetSys mode
├── world_panel.gd         # IDPWorldPanel: non-linear mode
├── scene_scanner.gd       # IDPSceneScanner: features, gates, metadata, terrain (async)
├── idp_runtime.gd         # IDPRuntime: "Play from here" request (runtime)
├── play_here.gd           # IDPPlayHere: picks the host game scene, starts the launcher
├── core/
│   ├── map_model.gd       # IDPMapModel: MapData.txt parser, rooms, doors
│   ├── annotations.gd     # IDPAnnotations: MapData.idp.json
│   ├── world.gd           # IDPWorld: .idpworld.json (rooms, gates, areas, undo, runtime lookups)
│   ├── world_scene_tools.gd # IDPWorldSceneTools: place/create scenes, sync gates, fit rooms
│   ├── room_painter.gd    # IDPRoomPainter: paints a room scene's tile layers, generates caves
│   ├── tileset_factory.gd # IDPTilesetFactory: starter pixel-art "mossy cave" tileset
│   ├── graph.gd           # IDPGraph: mode-independent room graph
│   ├── analysis.gd        # IDPAnalysis: progression, save distance, topology, routes
│   ├── validator.gd       # IDPValidator: MetSys + shared checks
│   ├── world_validator.gd # IDPWorldValidator: non-linear checks
│   └── exporters.gd       # IDPExporters: JSON, Graphviz, Markdown
├── nodes/
│   ├── idp_world_game.gd  # IDPWorldGame: non-linear game runtime (MetSysGame counterpart)
│   ├── idp_gate.gd        # IDPGate: runtime room transition
│   └── idp_play_launcher.* # Boots the game scene in the chosen room
├── ui/
│   ├── map_canvas.gd      # IDPMapCanvas: MetSys map
│   ├── world_canvas.gd    # IDPWorldCanvas: free-form world editor
│   ├── world_map_view.gd  # IDPWorldMapView: in-game map
│   ├── map_style.gd       # IDPMapStyle: tilesets (built-in, custom PNG, MetSys themes)
│   ├── room_view.gd       # IDPRoomView: the Room view (actual view) and its toolbar
│   ├── room_canvas.gd     # IDPRoomCanvas: room painting surface (own SubViewport)
│   ├── analysis_views.gd  # Progress / Issues / Stats tabs
│   └── ui_util.gd
└── assets/
```

The `core/` classes have no editor dependencies, so you can use them from tool scripts or CI. For example, fail a build when `IDPWorldValidator.run()` reports errors.

## Upgrading from 1.x

- The panel is now a main screen tab with two modes; set `interactive_dev_panel/use_main_screen = false` to keep the dock.
- Room width and height fields are gone; MetSys mode takes the size from MetSys' `in_game_cell_size`.
- Scenes referenced by the map are scanned automatically. **Scan > Scan project folder** replaces **Open Project Folder**.
- The **Show** checkboxes control map markers; room list filtering is opt-in.
- `SceneScanner` is now `IDPSceneScanner`. `map_overlay.gd`, `draw_marker.gd` and `status_bar.gd` were replaced.
- Interior edges of multi-cell rooms are no longer drawn as passages.
