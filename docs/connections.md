# Hardware Connections, Switches & Subsystem Integration

This document summarizes the hardware pinouts, switch/button assignments, and top-level integration for **Bad Piggies FPGA ("Laggy Piggies")** on the Digilent Basys 3 (`XC7A35T-1CPG236C`).

---

## 1. PMOD & Peripheral Connections

| Peripheral | Basys 3 Connector | Signal Pins | Notes |
| :--- | :--- | :--- | :--- |
| **Left OLED (`left_oled`)** | **PMOD JA** | `JA[7:0]` (`cs`, `sdin`, `sclk`, `d_cn`, `resn`, `vccen`, `pmoden`) | 96×64 SSD1331 RGB OLED at 6.25 MHz SPI; rotated 180° inside RTL (`95 - x`, `63 - y`) because PMOD JA is mounted upside-down |
| **Right OLED (`right_oled`)** | **PMOD JB** | `JB[7:0]` (`cs`, `sdin`, `sclk`, `d_cn`, `resn`, `vccen`, `pmoden`) | 96×64 SSD1331 RGB OLED at 6.25 MHz SPI; displays world follow-camera or Diary walkthrough diagrams |
| **Audio Amplifier (`Pmod AMP2`)** | **JXADC** | `JXADC[0]` = `AIN` (PWM), `JXADC[1]` = `GAIN`, `JXADC[3]` = `~SHUTDOWN` | 8-bit PWM audio output with dual-voice BGM + prioritized SFX |
| **USB / PS/2 Mouse** | **USB Host (`PS2Clk`, `PS2Data`)** | `C17` (`PS2Clk`), `B17` (`PS2Data`) | PS/2 streaming mode (`0xF4`) with scroll-wheel Z packet support |
| **7-Segment Display** | **Onboard (`seg`, `an`, `dp`)** | 4-digit active-low anodes (`an[3:0]`), segments (`seg[6:0]`), decimal (`dp`) | Per-level par countdown timer (`par_time`: 25 s on Cave Arch, 45 s on Cave Flight) in `M.SS` / `SS` format with negative overtime (`-01`, `-02`, ...); blanked (`an = 4'b1111`) during Tutorial (`LP_LEVEL_TUTORIAL`) |

---

## 2. Basys 3 Slide Switches & LEDs

Gameplay switches sit on the **Left Cluster (`SW14`, `SW15`)** and settings switches on the **Right Cluster (`SW0`–`SW1`)**. Middle switches `SW2`–`SW13` are disconnected in RTL. The camera zoom is on the mouse wheel.

| Switch | RTL Signal | `0` (Down / OFF) | `1` (Up / ON) |
| :--- | :--- | :--- | :--- |
| **`SW15`** | `reverse_switch` (`sw[15]`) | **Forward Engine Drive:** Wheel engines push right (`+X`) | **Reverse Engine Drive:** Wheel engines push left (`-X`). *Only affects wheel engines, never fans or rockets* |
| **`SW14`** | `free_look` (`sw[14]`) | **Follow Camera:** Viewport automatically tracks the vehicle with alpha-beta vertical smoothing | **Free-Look Camera:** Mouse cursor `X/Y` pans the viewport across the entire cave map |
| **`SW1`** | `show_map` (`sw[1]`) | **2-Screen Dual-OLED Mode:** Left OLED (`JA`) shows UI/Builder/Run Grid; Right OLED (`JB`) shows World Map | **1-Screen Mode:** Left OLED (`JA`) renders the World Map directly; Right OLED (`JB`) is blanked (`16'h0000`) |
| **`SW0`** | `mute_switch` (`sw[0]`) | **Audio Enabled:** Follows the on-screen Sound menu | **Hardware Audio Mute:** Mutes all BGM and SFX immediately, displays `MUTED BY SW0` in the Sound menu, and pulls `JXADC[3]` low |

The wheel engine has no switch: it starts OFF every run and is toggled only by clicking the Engine cell on the run diagram.

### Onboard LED Indicators (`LED[15:0]`)
* **`LED[15:14]` & `LED[1:0]`:** Mirror the active slide switches `SW[15:14]` and `SW[1:0]`. `LED[13]` and `LED[2]` stay off.
* **`LED[12:3]` (Middle 10 LEDs):** Flash dynamically during gameplay events:
  - **When `GO` / Launch is called (`launch_flash`):** Rapid strobe across `LED[12:3]`.
  - **On Level Victory (`LP_SUCCESS`):** Alternating odd/even celebration marquee across `LED[12:3]`.
  - **On Crash / Game Over (`LP_FAIL`):** Synchronized alert blink across `LED[12:3]`.
  - **Idle (`BUILD` / normal `RUN`):** `LED[12:3]` remain OFF (`10'd0`).

---

## 3. Basys 3 Pushbuttons (`BTNC`, `BTNU`, `BTNR`, `BTNL`, `BTND`)

| Button | RTL Signal | Function |
| :--- | :--- | :--- |
| **`BTNC`** | `btnC` (`center_press`) | **Launch / Retry:** Launches the vehicle from `BUILD` (when build is valid); retries the current level from `RUN`, `SUCCESS`, or `FAIL` |
| **`BTNU`** | `btnU` (`up_press`) | **Edit / Guide / Back:** Opens/closes the Field Diary (`GUIDE`) when in `BUILD`; returns to `BUILD` from `RUN`, `SUCCESS`, or `FAIL`; backs out of `LEVEL_SELECT` or `SETTINGS` |
| **`BTNR`** | `btnR` | **Reserved:** Not connected to any game action. Each rocket fires by clicking its own cell |
| **`BTNL`** | `btnL` | **Reserved:** Not connected to any game action |
| **`BTND`** | `btnD` (`reset`) | **Master Hardware Reset:** Synchronized active-high reset via `clock_control.v` |

---

## 4. Top-Level Module Interconnect (`My_Top_Module.v`)

1. **`clock_control` (`u_clocks`):** Generates the 6.25 MHz SPI display clock (`clk_6p25m`), 1 kHz physics/UI tick (`physics_tick`), 10 Hz tenths tick (`timer_tick`), and synchronized system reset (`sys_reset`).
2. **`input_controller` (`u_input`) & `mouse_adapter` (`u_mouse_adapter`):** Debounces physical buttons, synchronizes slide switches, and clamps PS/2 mouse coordinates into `[0..95, 0..63]` cursor positions plus click/drag/scroll events.
3. **`ui_controller` (`u_ui_controller`):** Translates mouse clicks, drags, and button presses across all UI screens (`TITLE`, `BUILD`, `GUIDE`, `SETTINGS`, `SOUND`, `LEVEL_SELECT`, `RUN`, `SUCCESS`, `FAIL`) into builder edit commands and runtime action triggers.
4. **`vehicle_builder` (`u_builder`):** Maintains the 3×3 vehicle grid (`build_grid`, `build_frames`, `build_facing_left`, `build_facing_down`), enforces stock limits and structural mounting rules, and produces `active_grid` / `active_frames` during `RUN` mode by masking out damaged cells (`damage_mask`, `damage_frame_mask`).
5. **`game_controller` (`u_game`) & `level_data` (`u_level_data`):** Drives the master game FSM, star ratings (`star_goal`, `star_time`, `star_part`), and per-level spawn/goal/TNT/part-limit configurations for Maps 1, 2, and 3.
6. **`physics_engine` (`u_physics`), `rotating_map_collision_engine` (`u_collision`), `tnt_controller` (`u_tnt`), & `world_outcomes` (`u_outcomes`):** Computes Q12.8 rigid-body kinematics, 16-cycle signed mass division, 32-step vehicle rotation, SAT raster terrain collision, swept-AABB TNT explosions, and win/loss outcomes.
7. **`display_snapshot` (`u_snapshot`), `left_renderer`, `ui_renderer`, & `right_renderer`:** Transfers a 318-bit coherent game snapshot from the 100 MHz logic domain to the 6.25 MHz display domain on `frame_begin` and renders the Dual-OLED viewports.
