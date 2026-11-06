# Module Interfaces & Shared Header Definitions

This document specifies the shared constants (`game_defs.vh`) and module port contracts across the 100 MHz logic domain and 6.25 MHz display domain.

---

## 1. Shared Constants (`game_defs.vh`)

### 1.1 Game FSM States (`3-bit`, plus `start_screen_active` overlay)
* `LP_BUILD = 3'd0`: Vehicle construction & inventory drag-and-drop (or Start Screen overlay when `start_screen_active = 1`).
* `LP_INIT_RUN = 3'd1`: Synchronous run initialization handshake across builder, physics, collision, TNT, and world outcomes.
* `LP_RUN = 3'd2`: Active physics, SAT terrain collision, TNT & par timer countdown.
* `LP_SUCCESS = 3'd3`: Goal flag reached; awards up to 3 stars (Goal, Star Box, and Par Time).
* `LP_FAIL = 3'd4`: Vehicle went out of bounds or hit a hazard.
* `LP_GUIDE = 3'd5`: Dual-OLED 3-page Field Diary (`diary_page = 0..2`) or Master Volume Mixer (`diary_page = 3`).
* `LP_LEVEL_SELECT = 3'd6`: 3-row Map Selector (`LP_LEVEL_ARCH = 2'd0`, `LP_LEVEL_FLIGHT = 2'd1`, `LP_LEVEL_TUTORIAL = 2'd2`).
* `LP_SETTINGS = 3'd7`: Settings menu (`Sound`, `Map Select`, `[BACK]`, `[HOME]`, and `[ ? ]` Controls/Switch Guide).

### 1.2 Part Encodings (`3-bit` per cell, `27-bit` packed 3×3 grid)
* `LP_PART_EMPTY = 3'd0`
* `LP_PART_FRAME = 3'd1`: Structural Wood Frame when placed into `build_frames[8:0]`; **On-Board TNT Crate** when stored as cell content inside `build_grid[cell*3 +: 3] == LP_PART_FRAME`.
* `LP_PART_PIG = 3'd2`: Pig Pilot (requires underlying `build_frames[cell]`).
* `LP_PART_WHEEL = 3'd3`: Wheel (requires orthogonal `wheel_support`).
* `LP_PART_ENGINE = 3'd4`: Wheel Engine (requires underlying `build_frames[cell]`).
* `LP_PART_BOOSTER = 3'd5`: Rocket Booster (side- or internal-mounted, finite burn).
* `LP_PART_BALLOON = 3'd6`: Balloon (requires supporting frame directly below).
* `LP_PART_FAN = 3'd7`: Propeller Fan (continuous horizontal or downward lift thrust).

---

## 2. Core Subsystem Interfaces

### 2.1 `input_controller.v` & Top-Level Switch Signals
* **Inputs:** `clk`, `reset`, `btnU`, `btnD`, `btnL`, `btnR`, `btnC`, `sw[15:0]`, mouse coordinates & button signals.
* **Active Switch Signals (`SW2`–`SW12` are unused/disconnected):**
  - `reverse_switch = sw[15]` (`SW15` Wheel Engine Reverse)
  - `zoom_switch = sw[14]` (`SW14` Camera Zoom `1.5×` / `1.0×`)
  - `free_look = sw[13]` (`SW13` Mouse Free-Look Camera Pan)
  - `show_map = sw[1]` (`SW1` 1-Screen / 2-Screen Mode toggle on PMOD JA)
  - `mute_switch = sw[0]` (`SW0` Hardware Audio Mute)
  - There is no engine switch: the engine starts OFF each run and is toggled only by clicking its run-diagram cell.

### 2.2 `vehicle_builder.v`
* **Inputs:** `clk`, `reset`, `game_state[2:0]`, `level_index[1:0]`, `run_init`, `edit_valid`, `edit_op[1:0]`, `edit_part[2:0]`, `edit_cell[3:0]`, `edit_source[3:0]`, `edit_facing_left`, `edit_facing_down`, `damage_valid`, `damage_mask[8:0]`, `damage_frame_mask[8:0]`.
* **Outputs:**
  - `build_grid[26:0]`, `build_frames[8:0]`: Saved player blueprint (or read-only tutorial contraption when `level_index == LP_LEVEL_TUTORIAL`; `stored_build_grid` automatically resets to `27'd0` upon leaving `LP_LEVEL_TUTORIAL`).
  - `intact_mask[8:0]`, `frame_intact_mask[8:0]`: Live runtime intact masks after applying `damage_mask` and `damage_frame_mask` during `LP_RUN` (while protecting the Pig Pilot and its frame).
  - `build_facing_left[8:0]`, `build_facing_down[8:0]`: Per-cell orientation flags for directional parts (Engines, Rockets, Fans).
  - `frames_left`, `pigs_left`, `wheels_left`, `engines_left`, `balloons_left`, `rockets_left`, `fans_left`: Remaining stock counts (with registered availability flags `has_*_stock` for 100 MHz timing closure).
  - `build_valid`, `build_error[3:0]`, `feedback_code[2:0]`, `feedback_cell[3:0]`: Construction validity and feedback status.

### 2.3 `physics_engine.v` & `rotating_map_collision_engine.v`
* **Fixed-Point Coordinates:** Signed Q12.8 format (`vehicle_x`, `vehicle_y`, `display_x`, `display_y`; signed Q8.8 `proposed_vx`, `proposed_vy`).
* **Rotation & Anti-Shake Stability:** 5-bit signed `vehicle_tilt` (`-16..15`, $11.25^\circ$ per step) with 2-sample stationary hysteresis (`held_count == 2'd2`), stationary anti-reversal lock (`last_turn_valid`, `unstable_settled_dir`, `stationary_anchor_x_px`), and tutorial airborne leveling (`air_leveling_active`).
* **Sub-Pixel Display Smoothing:** `display_x` and `display_y` filter 1–2 px slope stair-steps (`grounded_stair_step`) and add a 0.5 px wheel landing bounce (`wheel_landing_bounce`), rendered with `Q12.1` half-pixel interpolation in `right_renderer.v`.
* **Collision Handshake:** `move_valid` $\to$ `response_valid` evaluates rotated vehicle pixels against `level_map.v` solidity BRAM (or tutorial rectangles), returning `corrected_x`, `corrected_y`, `corrected_vx`, `corrected_vy`, `grounded`, `ground_slope`, `corrected_tilt`, `tip_dir`, and `impact_flags`.

### 2.4 `display_snapshot.v` (319-Bit CDC Bridge)
* Captures all rendering state in the 100 MHz domain (`display_x`, `display_y`, `vehicle_tilt`, `build_grid`, `intact_mask`, `frame_intact_mask`, `build_facing_left`, `cursor_x`, `cursor_y`, `game_state`, `level_index`, `star_box_collected`, `tnt_intact`, `tutorial_tnt_seen`, `tutorial_tnt_landed`, `tutorial_fan_tested`, `scatter_mask`, `scatter_x`, `scatter_y`, `scatter_phase`, stock counts, and UI flags) and transfers it atomically into the 6.25 MHz display domain on `frame_begin`.
