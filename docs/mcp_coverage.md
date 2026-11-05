# What the MCP tools cover

Each feature of the plugin and the tool that does it. `tests/test_mcp_protocol.gd` checks that every tool is named here and that every tool named here exists.

Two kinds of tools do the work:

- **Specific tools** do what the panel's dialogs and buttons do.
- **Generic tools** build anything that is set up through exports. They read a class's exports when called, so a new export, a new class, or your own class extending one of the plugin's needs nothing added to the server. `mds_class_list` says what can be made, and `mds_class_info` what each holds.

## Generic: every class of the plugin

| What | Tools |
|---|---|
| What there is | `mds_class_list`, `mds_class_info`, `mds_catalog` |
| Resources in files: items, abilities, equipment, enemy data, attacks, dialogue, shops, movement, moves, styles, backdrops | `mds_resource_create`, `mds_resource_copy`, `mds_resource_get`, `mds_resource_update`, `mds_resource_find` |
| Scenes, and nodes in any scene: pickups, doors, NPCs, weather, backgrounds, cameras, 2.5D depth, the game's own nodes | `mds_scene_create`, `mds_scene_tree`, `mds_node_get`, `mds_node_add`, `mds_node_update`, `mds_node_remove` |

Scenes can inherit from others (`mds_scene_create` with `inherits`), which is how a project makes its own enemy from a template.

## Map: Map view and Full view

| In the panel | Tool |
|---|---|
| New world, Open world, World settings | `mds_world_create`, `mds_world_list`, `mds_world_get`, `mds_world_update`, `mds_editor_open` |
| New room here, Draw room, Delete room | `mds_room_add`, `mds_room_remove` |
| Paint and Erase cells | `mds_room_cells` |
| Duplicate room | `mds_room_duplicate` |
| Move rooms or an area, Extend room | `mds_rooms_move`, `mds_rooms_extend` |
| Inspect tab: type, status, boss, grants, notes, parallax, backdrop, background, weather, darkness | `mds_room_update` |
| Areas tab: all of an area's values, Rename, Delete | `mds_area_set`, `mds_area_remove` |
| Merge rooms, with its cave and walls options | `mds_room_merge` |
| Create scene | `mds_room_scene_create` |
| Add scenes to map, Assign scene | `mds_room_from_scene` |
| Fit room to scene, and bringing gates over either way | `mds_room_sync` |
| Add, move and connect gates, Auto-connect facing gates | `mds_gate_add`, `mds_gate_update`, `mds_gate_remove`, `mds_gate_connect`, `mds_gate_disconnect`, `mds_gates_auto` |
| Doors between touching rooms, joining parts apart | `mds_area_link` |
| Link rooms, links' values | `mds_link` |
| Pins | `mds_pin` |
| Add layer, layer names | `mds_layer` |
| Generate area | `mds_area_generate` |
| Generate caves for an area | `mds_area_generate_caves` |
| Full view's outlines, Generate map | `mds_sketch`, `mds_sketches_generate` |
| Import map image | `mds_map_import` |
| Import from MetSys map | `mds_world_from_metsys` |
| Map styles | `mds_catalog` with `map_styles`, the `map_style` setting of `mds_world_update`, `mds_map_style_template` |
| Create game scene, Gameplay Kit setup | `mds_game_scene_create`, `mds_gameplay_setup` |

## Rooms: Room view

| In the panel | Tool |
|---|---|
| Paint and Erase tools, Palette, starter tileset | `mds_room_paint`, `mds_tileset_create` |
| Shape brushes: rectangles, uneven shapes, curved faces (convex, concave, slope, rounded, quarter-pipe, S-curve, hill, mesa, wave, steps, spikes), mirror, rough | `mds_room_paint_shape` |
| Generate room | `mds_room_generate` |
| Decorate | `mds_room_decorate` |
| Freeform tool and its ready-made structures | `mds_room_freeform_add`, then `mds_node_update` for its points, style and role |
| Repair twisted shapes | `mds_room_freeform_repair` |
| Convert to freeform | `mds_room_convert` |
| Fill what is outside the room's shape | `mds_room_fill_outside` |
| Decorate freeform | `mds_room_decorate_freeform` |
| Trace drawing, with its colors, styles and outputs | `mds_room_trace` |
| Place tool: tiles off the grid | `mds_room_tile_piece` |
| Stamps, effects, enemies, scenes, Gameplay Objects list | `mds_room_place`, `mds_enemy_configure` |
| Items in the room, Delete | `mds_room_items`, `mds_room_remove_item` |
| Objects stood on the floor | `mds_room_fit_objects` |
| Clear hidden tiles, broken cells | `mds_room_tidy` |
| Add a spritesheet, collision, tile kinds, terrains from a block of tiles | `mds_tileset_get`, `mds_tileset_edit` |
| Seeing a room | `mds_room_ascii`, `mds_room_preview` |

## Fights: Fight editor

| In the panel | Tool |
|---|---|
| The graph, each move's fields, the checks | `mds_fight_get` |
| Add, move, reorder, copy, remove, conditions, phases, recipes, Make editable | `mds_fight_edit` |
| The running fight on the graph | `mds_fight_live` |

## Checks and exports

| In the panel | Tool |
|---|---|
| Issues tab | `mds_validate` |
| Progress and Stats tabs, routes | `mds_analysis` |
| Check room geometry | `mds_room_check` |
| Rescan, Scan project folder | `mds_scene_scan` |
| Export: JSON, dot, Markdown, PNG | `mds_export`, and `mds_map_preview` for a quick look |
| Play from here, Run this room scene only, Stop | `mds_play`, `mds_stop` |

## MetSys mode

The map file is MetSys', painted in its editor, and no tool writes it. What changes is the notes beside it, as in the panel.

| In the panel | Tool |
|---|---|
| Rooms, doors, start room | `mds_metsys_get` |
| Room notes, door requirements, one-way doors, start room, player for the checks | `mds_metsys_annotate` |
| Links and pins | `mds_link` and `mds_pin` with `map` |
| Issues, Progress, room checks | `mds_metsys_check` |
| Export | `mds_metsys_export` |
| Play from here | `mds_play` with `map` |

## The server itself

| What | Tool |
|---|---|
| State of the server | `mds_status` |
| Many edits as one step | `mds_batch` |
| Undo and what can be undone | `mds_undo`, `mds_history` |
| Saving scenes open in the editor | `mds_editor_save_scenes` |

## What needs the editor

These answer with an error when the server runs on its own, with the editor closed:

- `mds_play`, `mds_stop`: running a game is the editor's.
- `mds_fight_live`: the running game reports to the editor.
- `mds_editor_open`, `mds_editor_save_scenes`.

`mds_export` with `png` draws the map as the panel does only in the editor with a window, since Godot has no drawing headless. Otherwise it draws a plain map from the rooms, areas and gates, and says so in its result. Both have the sidecar, so `mds_map_import` reads either back exactly.

`mds_room_preview` draws the room's tile layers, freeform shapes, gates and enemies itself, so it isn't the game's rendering. Stamps, effects and pictures aren't in it: `mds_room_items` lists them.

## What has no tool

These only change how the panel looks, or are other ways of doing what a tool does directly:

- Zoom, pan, dock and floating window, tabs, keyboard shortcuts, snapping, Show filters and color modes, the 2.5D preview toggle, showing weather and backgrounds in the Room view.
- Selecting, dragging, resize handles, copy and paste on the canvas: `mds_node_update` and the paint tools take exact values.
- Copy room id, cell coordinates or scene UID: `mds_world_get` and `mds_metsys_get` return them.
- Painting in a MetSys map: MetSys' own editor does that.
- Which world the panel shows when it opens: the editor keeps that per user.

## Exceptions to "no tool runs code"

`mds_play` runs the project's game, so it is `full` tier and works only in the editor. No other tool starts the game. Loading a scene still runs its `@tool` scripts, as opening it in the editor does.
