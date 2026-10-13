# Metroidvania Developer System

Version 3.3.0, MIT license (see [LICENSE](LICENSE)).

A Godot editor plugin for designing and building a metroidvania's world:

- **Map:** draw irregular rooms on a world map, or generate whole areas that split into rooms with doors.
- **Rooms:** paint each room's terrain, freeform rock and decorations, or trace them from a drawing (as shapes, solid colors, tiles, or the drawing itself with collision). Place tiles anywhere at any angle, and select and move anything by pixels or by tiles.
- **Atmosphere:** add weather, hazards and scenery in motion (30 shader effects), and parallax, animated or creature backgrounds, for boss rooms too.
- **Checks:** check rooms with physics, and analyze progression and backtracking.
- **Play:** run the world with room-to-room transitions and a camera made for irregular rooms.

It works with or without [MetSys](https://github.com/KoBeWi/Metroidvania-System).

## Requirements

- Godot 4.6 or newer (tested on 4.6.1 and 4.7.2).
- MetSys 1.6, only for MetSys mode.

## Installing

1. Copy this folder to your project's `addons/MetroidvaniaDeveloperSystem/`, or install it from the Godot Asset Store.
2. Enable **Metroidvania Developer System** in **Project Settings > Plugins**.

A **MetDevSys** tab appears next to 2D / 3D / Script. Without MetSys, it starts in non-linear mode.

## Getting started

1. In the MetDevSys tab, choose **New world...** in the World section.
2. Press **R** and drag on the map to draw a room, or drop scenes on it.
3. Draw gates with **G** to connect the rooms.
4. Open a room with **Room view** to paint it, place effects or generate a cave.
5. **Scenes > Create game scene...** makes a runnable game scene (`MDSWorldGame`). **Play from here** starts it in the room under the mouse.

Every class and node starts with `MDS`. Add Child Node and search "MDS" to see them: `MDSWorldGame`, `MDSGate`, `MDSRoomCamera`, `MDSFreeform`, the effects (`MDSRain`, `MDSDustStorm`, `MDSCreatures`...) and more.

## Documentation

The full guide, with screenshots, is the project's README: <https://github.com/arunsrajan/MetroidvaniaDeveloperSystem#readme>.

What changed in each version: <https://github.com/arunsrajan/MetroidvaniaDeveloperSystem/blob/main/CHANGELOG.md>.

Upgrading from an older version (Interactive Dev Panel, IDP names, the Map Dev tab): see the README's "Upgrading" sections. Old projects keep loading.

Issues and ideas: <https://github.com/arunsrajan/MetroidvaniaDeveloperSystem/issues>.
