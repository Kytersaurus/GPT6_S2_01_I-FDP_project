# Proposal: physics and collision for the Cave Arch and Cave Flight maps

Implementation status (28 October 2026): 20-bit positions, map-sized bounds, flag-derived goals and ROM terrain collision are connected. Collision supports an upright 24 by 24 swept footprint, three-pixel steps/snaps, walls and ceilings. The cave placeholder rectangles are removed. Slope gravity, uphill resistance and wheel friction are connected. Terrain-following rotation was added on 29 October 2026; passage clearance remains pending; the Cave Arch goal passage cannot currently fit the full footprint. The proposal below records the original plan; see `interfaces.md` for the current contract.

Owner: Role 4 - Marcus, for review by Role 2 (physics) and Role 3 (collision, TNT and world checks). Nothing here has been changed in Role 2 or Role 3 files; this lists what the new map needs from them.

## What Role 4 has added

- **Level 3, Cave Arch.** The map is traced from two Bad Piggies screenshots (`docs/maps/cave_arch_reference_top.png`, `_bottom.png`). It is 478 by 291 world pixels, about five screens wide and four and a half tall. The traced result is in `docs/maps/cave_arch_classes.png`.
- **`level_map.v`**: block-RAM ROM with one 3-bit class per world pixel (`LP_MAP_*` in `game_defs.vh`): 0 sky, 1 cave background, 2 rock, 3 grass, 4 road, 5 underground. Sky and cave background are open space; rock, grass, road and underground are solid. Grass marks the green track lines in the screenshots. It has two read ports with one clock of latency each. The draw port feeds the right renderer. **The query port is free for collision**: clock it with the 100 MHz `clk`, present signed world-pixel `query_x`/`query_y`, and read `query_class` on the next clock. Coordinates above or beside the map return sky; below it, underground.
- **Camera and zoom.** The right OLED follows the vehicle. The default 1.5x map view shows 64 by 43 world pixels with 12 by 12 part sprites; the zoomed-out 1x view shows 96 by 64 with 8 by 8 sprites. SW3 or the mouse wheel switches between them. With SW4 up, the camera follows the mouse cursor instead of the vehicle, so the whole map can be explored on the board. The renderer already takes **20-bit Q12.8 positions**; the top sign-extends today's 16-bit values.
- **Level 4, Cave Flight** (a flying level): traced from `docs/maps/cave_flight_reference_left.png` and `_right.png` into an 890 by 213 map (`cave_flight_map.mem`, 1024 entries per row; `map_id=1` selects it in `level_map`). Spawn (68, 178) on the ground at the bottom left; flag top-left (769, 50) on the grassy ledge at the top right. Its spawn y needs more than 16-bit positions, so `level_data` now outputs a Q12.8 spawn and the top passes the low 16 bits to physics. Positions up to x=890 and the flight itself (balloons/rockets) are part of items 1 and 2 below.
- `level_data` outputs for level 3: spawn (104, 26) on the flat start plateau (`spawn_x=26624`, `spawn_y=6656`), `map_level=1`, `world_width=478`, `world_height=291`, and the finish flag's top-left (300, 229). The flag stands on the cave road, whose surface is at y=243.
- Levels 1 and 2 are unchanged and stay as simple test maps. In the 1.5x view the camera already scrolls across them.

## What does not work yet on level 3

Running level 3 today fails immediately, by design, until the items below are agreed. Collision still reads rectangles; level 3 has one placeholder platform under the spawn (x=97..128, y=50), and `world_outcomes` reports out of bounds outside 96 by 64.

## Proposed changes

1. **Wider positions (Role 2, Role 3, shared).** Change positions from signed 16-bit Q8.8 to signed 20-bit Q12.8 (`LP_COORD_BITS 20`). Integer range is ±2048 pixels, enough for the 478 by 291 map with room for larger levels. This affects `physics_engine` (position registers and the `MAKE_REQUEST` clamps at 28672/24576), the collision request and response, `tnt_controller` and `world_outcomes`. Velocities can stay 16-bit.
2. **Map collision (Role 3).** Replace the rectangle checks with solid-pixel queries on the `level_map` query port when `map_level` is high. A sequential checker fits easily: one movement update arrives every 1/60 s, which is over a million clocks. For example:
   - **Floor/slope:** probe the column under the left, middle and right of the 24-pixel footprint, from the proposed bottom edge up to a step height (say 4 pixels), and lift the vehicle to the highest solid surface found; grounded if one was found.
   - **Walls:** a solid pixel in the leading column above the step height blocks horizontal motion.
   - **Ceilings:** probe the top edge when moving up.

   This gives the smooth slopes in the screenshots without upside-down physics. Rectangle levels can keep the existing path.
3. **World checks (Role 3).** Use `world_width`/`world_height` from `level_data` for the out-of-bounds test instead of the fixed 96 by 64. For the goal, widen `goal_rect` fields to 10 bits, or derive the goal from the flag (for example, pig centre with x >= 300 and y within 24 pixels above the road).
4. **TNT and hazards (Role 3/4).** Their `{y[7:0], x[7:0]}` packing tops out at 255. If the Cave Arch level gets TNT or hazards later, widen the fields to 10 bits together with item 1.
5. **Spawn (Role 2).** Level 3's spawn already fits in 16 bits; after item 1, sign-extend it as the top does for the renderer.

Once these land, Role 4 will remove the placeholder platform, connect the query port and record a level 3 solution in `role4_level_solutions_tb`.

## Regenerating the map

`scripts/build_cave_arch_map.ps1` rebuilds `cave_arch_map.mem` and the class preview from the two reference screenshots. Its helpers are in `scripts/map_tools/`. Edit the screenshots, or the clean-up steps in the script, to change the terrain; keep `LP_MAP_WIDTH`/`LP_MAP_HEIGHT` in step with the printed size. After adding new files, re-run `scripts/add_team_sources.tcl` in Vivado so the `.mem` file is part of the project.
