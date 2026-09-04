#!/usr/bin/env python3
"""Generate valley terrain heights for map_valley.json"""

import json
import math
import random

random.seed(42)  # deterministic output

GRID_SIZE = 64
MAP_SIZE = 1000.0
N = GRID_SIZE + 1  # 65
HALF = MAP_SIZE * 0.5
CELL = MAP_SIZE / GRID_SIZE

heights = []

for z in range(N):
    for x in range(N):
        # World coordinates
        wx = x * CELL - HALF  # -500 to 500
        wz = z * CELL - HALF  # -500 to 500

        # Normalized distance from valley center (X axis)
        # 0 at center, 1 at edges
        valley_dist = abs(wx) / HALF  # 0 to 1

        # Base valley shape: flat center, rising mountains on sides
        # Use a smooth curve: height = mountain_height * valley_dist^2
        mountain_height = 55.0
        base = mountain_height * (valley_dist**2.2)

        # Valley floor isn't perfectly flat - gentle rolling
        floor_noise = math.sin(wx * 0.008) * math.cos(wz * 0.01) * 2.0
        floor_noise += math.sin(wx * 0.02 + 1.5) * math.cos(wz * 0.015) * 1.5

        # Add mountain noise (more variation on the sides)
        if valley_dist > 0.3:
            mountain_noise = (random.random() - 0.5) * 8.0 * valley_dist
            mountain_noise += math.sin(wz * 0.03) * 5.0 * valley_dist
            mountain_noise += math.sin(wx * 0.025 + wz * 0.015) * 4.0 * valley_dist
        else:
            mountain_noise = (random.random() - 0.5) * 1.5

        # Create a narrower valley near the spawn points (Z edges)
        # to make teams fight through a narrow pass
        z_norm = abs(wz) / HALF  # 0 at center, 1 at edges
        narrow_factor = 1.0 + z_norm * 0.3  # mountains push in slightly at ends

        # Steepen mountains near the edges
        if valley_dist > 0.85:
            base *= 1.3  # steeper cliffs at the very edge

        h = base * narrow_factor + floor_noise + mountain_noise

        # Clamp
        h = max(-5.0, min(80.0, h))

        # Near spawn points, ensure relatively flat area
        spawn_z1 = 400  # team 1 spawn
        spawn_z2 = -400  # team 2 spawn
        for sz in [spawn_z1, spawn_z2]:
            dist_to_spawn = math.sqrt((wx - 0) ** 2 + (wz - sz) ** 2)
            if dist_to_spawn < 60:
                flatten = dist_to_spawn / 60.0
                h = h * flatten + 0.0 * (1.0 - flatten)

        heights.append(round(h, 4))

# Build the map JSON
map_data = {
    "id": "map_valley",
    "name": "山谷要塞",
    "source": "builtin",
    "description": "两侧高山夹峙的狭长山谷，中央低地适合交战，山坡提供制高点",
    "ground_color": [0.38, 0.42, 0.28],
    "sky_color": [0.45, 0.55, 0.7],
    "size": 1000,
    "terrain": {"grid_size": GRID_SIZE, "heights": heights},
    "spawn_points": [
        {"team": 1, "position": [0, 1, 400], "rotation": 0},
        {"team": 2, "position": [0, 1, -400], "rotation": 180},
    ],
    "obstacles": [
        {"type": "rock", "position": [80, 1, 100], "scale": [10, 8, 10]},
        {"type": "rock", "position": [-100, 1, -50], "scale": [8, 7, 8]},
        {"type": "rock", "position": [120, 1, -200], "scale": [12, 10, 12]},
        {"type": "rock", "position": [-150, 1, 250], "scale": [10, 8, 10]},
        {"type": "rock", "position": [50, 1, -350], "scale": [8, 7, 8]},
        {"type": "rock", "position": [-80, 1, 350], "scale": [9, 8, 9]},
        {"type": "building", "position": [60, 3, 0], "scale": [18, 12, 18]},
        {"type": "building", "position": [-70, 3, -100], "scale": [15, 12, 15]},
        {"type": "ramp", "position": [200, 0, 50], "scale": [3, 1, 4]},
        {"type": "ramp", "position": [-200, 0, -50], "scale": [3, 1, 4]},
    ],
    "grass_patches": [
        {"position": [30, 0, 50], "radius": 25, "density": 0.7},
        {"position": [-50, 0, -80], "radius": 20, "density": 0.6},
        {"position": [100, 0, -150], "radius": 30, "density": 0.65},
        {"position": [-120, 0, 200], "radius": 22, "density": 0.55},
        {"position": [0, 0, 0], "radius": 35, "density": 0.6},
    ],
    "bush_patches": [
        {"position": [60, 0, -30], "radius": 12, "density": 0.8},
        {"position": [-40, 0, 80], "radius": 10, "density": 0.75},
        {"position": [90, 0, 120], "radius": 14, "density": 0.7},
        {"position": [-110, 0, -180], "radius": 11, "density": 0.85},
    ],
}

output_path = r"D:\work\war_thunder_like\data\maps\map_valley.json"
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(map_data, f, ensure_ascii=False, indent="\t")

print(f"Generated map_valley.json with {len(heights)} terrain heights")
print(f"  Grid: {GRID_SIZE}x{GRID_SIZE}, Map size: {MAP_SIZE}m")
print(f"  Height range: {min(heights):.2f} to {max(heights):.2f}")
print(f"  Center height: {heights[32 * N + 32]:.2f}")
print(f"  Edge height: {heights[0]:.2f}")
