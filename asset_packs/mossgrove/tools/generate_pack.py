"""Generates the Mossgrove asset pack: tiles, characters, enemies, effects, props and
parallax backgrounds, plus pack.json (tile layout and animation frames) that
build_resources.gd turns into Godot resources.

    python tools/generate_pack.py

Needs numpy, scipy and Pillow. Takes about a minute.
"""
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from paint import down, save  # noqa: E402
import terrain  # noqa: E402
import decor  # noqa: E402
import characters as ch  # noqa: E402
import scenery  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))


def out(*parts):
    p = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def main():
    t0 = time.time()
    pack = {"name": "Mossgrove", "tile_size": 32, "terrains": [], "decor": [], "sprites": {}, "props": {}, "parallax": []}

    img, keys = terrain.sheet()
    save(down(img), out("tiles", "terrain.png"))
    for i, key in enumerate(keys):
        mat = terrain.MATERIALS[key]
        pack["terrains"].append({
            "name": mat["name"], "column": i * 5, "solid": not mat.get("background", False),
            "layout": "4x4 sides (index = 1 right + 2 bottom + 4 left + 8 top) + fill variants in column 4",
        })
    print("terrain", round(time.time() - t0, 1))

    img, kinds = decor.sheet()
    save(down(img), out("tiles", "decor.png"))
    pack["decor"] = kinds
    print("decor", round(time.time() - t0, 1))

    sheets = {
        "player": (ch.player_anims(), 64, 64, 8, "characters/player.png"),
        "crawler": ({"walk": ([ch.crawler(i) for i in range(4)], 8, True)}, 64, 48, 4, "enemies/crawler.png"),
        "moth": ({"fly": ([ch.moth(i) for i in range(4)], 10, True)}, 64, 64, 4, "enemies/moth.png"),
        "slash": ({"slash": ([ch.slash(i) for i in range(5)], 24, False)}, 96, 64, 5, "vfx/slash.png"),
        "spark": ({"spark": ([ch.spark(i) for i in range(4)], 20, False)}, 64, 64, 4, "vfx/spark.png"),
        "dust": ({"dust": ([ch.dust(i) for i in range(5)], 14, False)}, 48, 32, 5, "vfx/dust.png"),
    }
    for name, (anims, w, h, cols, path) in sheets.items():
        img, table = ch.strip_sheet(anims, w, h, cols)
        save(down(img), out(*path.split("/")))
        origin = {"player": [30, 60], "crawler": [32, 44], "moth": [32, 36]}.get(name, [w // 2, h // 2])
        pack["sprites"][name] = {"texture": path, "frame_size": [w, h], "origin": origin, "animations": table}
        print(name, round(time.time() - t0, 1))

    for name, (fn, w, h) in scenery.PROPS.items():
        save(down(fn()), out("props", name + ".png"))
        pack["props"][name] = {"texture": "props/%s.png" % name, "size": [w, h]}
    print("props", round(time.time() - t0, 1))

    for name, fn, scroll in (("far", scenery.far_layer, 0.2), ("mid", scenery.mid_layer, 0.5), ("near", scenery.near_layer, 1.3)):
        save(fn(), out("backgrounds", "parallax_%s.png" % name))
        pack["parallax"].append({"texture": "backgrounds/parallax_%s.png" % name, "scroll_scale": scroll})
        print("parallax", name, round(time.time() - t0, 1))

    with open(out("pack.json"), "w", encoding="utf-8") as f:
        json.dump(pack, f, indent=2)
    print("done in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
