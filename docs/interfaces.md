# Module Interfaces & Shared Header Definitions

This document specifies the shared constants (`game_defs.vh`) and module port contracts across the 100 MHz logic domain and 6.25 MHz display domain.

---

## 1. Shared Constants (`game_defs.vh`)

### 1.1 Game FSM States (`3-bit`)
* `LP_BUILD = 3'd0`: Vehicle construction & inventory drag-and-drop.
* `LP_RUN = 3'd1`: Active physics, SAT terrain collision, TNT & par timer countdown.
* `LP_SUCCESS = 3'd2`: Goal flag reached; awards up to 3 stars (`star_goal`, `star_time`, `star_part`).
* `LP_FAIL = 3'd3`: Pig killed by hazard/out-of-bounds or vehicle destroyed.
* `LP_GUIDE = 3'd4`: Dual-OLED 3-page Field Diary (`Left OLED` text + `Right OLED` visual diagrams).
* `LP_SETTINGS = 3'd5`: Settings menu (`Mouse Speed`, `Sound`, `Levels`, `Title`, and `[ ? ]` Switch Guide).
* `LP_SOUND = 3'd6`: Audio mixer (`BGM ON/OFF`, `SFX ON/OFF`, `TEST SFX`, `SW15 MUTE` indicator).
* `LP_TITLE = 3'd7`: Animated `"LAGGY PIGGIES"` Start Screen (with `LP_LEVEL_SELECT` sub-mode).

### 1.2 Part Encodings (`3-bit` per cell, `27-bit` packed 3×3 grid)
* `LP_PART_EMPTY = 3'd0`
* `LP_PART_FRAME = 3'd1` (also tracked as an underlying bitmask in `build_frames[8:0]` / `active_frames[8:0]`)
* `LP_PART_PIG = 3'd2`
* `LP_PART_WHEEL = 3'd3`
* `LP_PART_ENGINE = 3'd4`
* `LP_PART_BALLOON = 3'd5`
* `LP_PART_BOOSTER = 3'd6` (Rocket Booster)
* `LP_PART_FAN = 3'd7` (Propeller Fan)

---

## 2. Core Subsystem Interfaces

### 2.1 `input_controller.v` & Top-Level Switch Signals
* **Inputs:** `clk`, `reset`, `btnU`, `btnD`, `btnL`, `btnR`, `btnC`, `sw[15:0]`, mouse coordinates & button signals.
* **Active Switch Signals (`SW3`–`SW12` are unused/disconnected):**
  - `show_map = sw[0]` (`SW0` 1-Screen / 2-Screen Mode toggle on PMOD JA)
  - `engine_switch = sw[1]` (`SW1` Engine Switch)
  - `reverse_switch = sw[2]` (`SW2` Wheel Engine Reverse)
  - `free_look = sw[13]` (`SW13` Mouse Free-Look Camera Pan)
  - `zoom_switch = sw[14]` (`SW14` Camera Zoom `1.5×` / `1.0×`)
  - `mute_switch = sw[15]` (`SW15` Hardware Audio Mute)

### 2.2 `vehicle_builder.v`
* **Inputs:** `clk`, `reset`, `clear_build`, `game_state`, `cursor_cell[3:0]`, `edit_valid`, `edit_action[1:0]`, `edit_part[2:0]`, `edit_cell[3:0]`, `edit_source[3:0]`, `edit_facing_left`, `edit_facing_down`, `damage_mask[8:0]`, `damage_frame_mask[8:0]`, per-level stock limits (`max_frames`, `max_pigs`, `max_wheels`, `max_engines`, `max_balloons`, `max_rockets`, `max_fans`).
* **Outputs:**
  - `build_grid[26:0]`, `build_frames[8:0]`: Saved player blueprint.
  - `active_grid[26:0]`, `active_frames[8:0]`: Live runtime grid after masking out `damage_mask` and `damage_frame_mask` during `RUN` / `FAIL`.
  - `build_facing_left[8:0]`, `build_facing_down[8:0]`: Per-cell orientation flags for directional parts (Engines, Rockets, Fans).
  - `frames_left`, `pigs_left`, `wheels_left`, `engines_left`, `balloons_left`, `rockets_left`, `fans_left`: Remaining stock counts.
  - `build_valid`: High when at least one Pig is placed and all cells satisfy structural mounting rules.
  - `edit_result[1:0]`: `LP_EDIT_RES_OK`, `LP_EDIT_RES_MOUNT`, or `LP_EDIT_RES_STOCK`.

### 2.3 `physics_engine.v` & `rotating_map_collision_engine.v`
* **Fixed-Point Coordinates:** Signed Q12.8 format (`vehicle_x`, `vehicle_y`, `vel_x`, `vel_y`).
* **Rotation:** 6-bit signed `vehicle_tilt` (`-16..15`, $11.25^\circ$ per step).
* **Collision Handshake:** `collision_req` $\to$ `collision_done` evaluates rotated vehicle pixels against `level_map.v` solidity BRAM, returning `res_x`, `res_y`, `res_grounded`, `res_hit_wall`, `res_slope`, `res_tip_dir`, and `impact_speed`.

### 2.4 `display_snapshot.v` (318-Bit CDC Bridge)
* Captures all rendering state in the 100 MHz domain (`vehicle_x`, `vehicle_y`, `display_y`, `vehicle_tilt`, `active_grid`, `active_frames`, `build_facing_left`, `build_facing_down`, `balloon_popped_mask`, `fan_active_mask`, `cursor_x`, `cursor_y`, `game_state`, `level_id`, `zoom_mode`, star flags, stock counts, and UI flags) and transfers it atomically into the 6.25 MHz display domain on `frame_begin`.
