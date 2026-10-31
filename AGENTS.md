# AGENTS.md — Developer & AI Agent Guide

Welcome to the **Bad Piggies FPGA** codebase! This document provides complete architectural, operational, and development context for AI coding assistants and human developers working on this project.

---

## 1. Project Overview & Identity

* **Project:** Hardware-accelerated clone of *Bad Piggies* running on the **Digilent Basys 3** FPGA (Xilinx Artix-7 `XC7A35T-1CPG236C`).
* **Hardware Features:**
  - Rigid body physics engine with continuous 360° vehicle rotation and terrain-following dynamics.
  - Separating Axis Theorem (SAT) raster collision scanner against dual-port terrain Block RAM.
  - Swept-AABB TNT explosions, dynamic damage masks, and balloon buoyancy/popping.
  - Dual 96×64 RGB OLED displays (SSD1331 via SPI on PMOD JA and JB) with camera zoom and free look.
  - PS/2 mouse interface with drag-and-drop building, pan/zoom, and in-game balloon popping.
  - Dual-voice background music synthesis (The Entertainer, Bad Piggies Theme, Title Fanfare) and prioritized PWM sound effects (Pmod AMP2 on JXADC).
  - Basys 3 active-low 4-digit 7-segment display driver for M.SS run timer.
* **Team Roles & Ownership:**
  - **Role 1 (Kaushal):** Vehicle Builder, Inventory/Stock Validation, Mouse Input, Audio Pipeline (BGM + SFX), 7-Segment Timer, UI Layouts.
  - **Role 2 (Kyle):** Physics Engine, Newtonian Kinematics, Fixed-Point Arithmetic, 16-Cycle Signed Divider, Tilt Dynamics.
  - **Role 3 (Yap Ting):** Terrain Collision Engine (SAT Raster Scanner), TNT Explosions & Damage Masks, World Outcomes (Goal, Hazards, Death).
  - **Role 4 (Marcus):** Master Game Controller FSM, Level Data, Dual-OLED Renderers (Follow-Camera, Viewports), CDC Display Snapshot.

---

## 2. Critical Non-Negotiable Constraints

When working on this repository, **you must strictly adhere to the following rules**:

### 🚫 Constraint 1: NEVER TOUCH MAP FILES
- **Files:** `cave_flight_map.mem`, `cave_flight_solid.mem`, `cave_flight_colour_*.mem`, `cave_arch_map.mem`, `cave_arch_solid.mem`, and [`level_map.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/level_map.v).
- **Reason:** A teammate is actively detailing the terrain artwork, color palettes, and solidity maps. Any modification to these files will break concurrent work. The engine is designed so that when the `.mem` files are updated, collision and display pipelines automatically adapt.

### 🚫 Constraint 2: STRICT ZERO EXTRA BRAM (Max 48 / 50 Tiles)
- The Artix-7 `XC7A35T` on Basys 3 has exactly **50 Block RAM tiles** (`RAMB36E1`).
- The project currently uses **48 / 50 tiles (96.00%)**.
- **Rule:** **DO NOT instantiate any new Block RAM, dual-port RAMs, or large memory arrays.** All new UI elements, icons, bitmap fonts, start screens, and animations must be implemented as distributed logic ROMs (look-up tables, `ui_font.vh`, combinational decoders).

### 🚫 Constraint 3: TIMING CLOSURE AT 100 MHz
- Logic clock runs at **100 MHz**; OLED SPI clock runs at **6.25 MHz**.
- All PRs and modifications must achieve positive slack (**WNS > 0.000 ns**, **WHS > 0.000 ns**, **0 failing endpoints**).
- Avoid deep combinational dividers or wide nested arithmetic in single-cycle paths. Use pipelined dividers ([`signed_divider16.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/signed_divider16.v)) and registered FSM stages.

### 🚫 Constraint 4: MAINTAIN 100% PASS RATE ON ALL 51 TESTBENCHES
- The regression test suite contains **51 testbenches**.
- Before committing any change, all 51 testbenches must pass without regression.

### 🚫 Constraint 5: BACKWARD-COMPATIBLE HITBOXES
- When tweaking UI button coordinates or hitboxes on Left OLED, always maintain backward compatibility for existing testbenches using fallback conditions or prioritized evaluation order (`RETRY` $\to$ `SETTINGS` $\to$ `EDIT` $\to$ `ACTION ICONS`).

---

## 3. System Architecture & Interconnects

```mermaid
flowchart TD
    subgraph Inputs ["Input Subsystem (100 MHz)"]
        PS2[PS/2 Mouse] --> MA[mouse_adapter.v]
        BTNS[Basys 3 Buttons & Switches] --> BD[button_debouncer.v]
        MA --> IC[input_controller.v]
        BD --> IC
    end

    subgraph Core ["Game Core & Physics (100 MHz)"]
        IC --> VB[vehicle_builder.v]
        IC --> GC[game_controller.v]
        VB --> BC[balloon_control.v]
        GC --> PE[physics_engine.v]
        PE <-->|Handshake| CE[rotating_map_collision_engine.v]
        PE --> TC[tnt_controller.v]
        PE --> WO[world_outcomes.v]
        TC -->|Damage Masks| VB
        WO -->|Events / Outcomes| GC
    end

    subgraph Audio ["Audio Pipeline (100 MHz)"]
        GC --> SC[sound_controller.v]
        GC --> BP[bgm_player.v]
        SC --> SG[sound_generator.v]
        BP --> SG
        SG --> PWM[audio_pwm -> JXADC AMP2]
    end

    subgraph Display ["Display Pipeline (6.25 MHz)"]
        PE & VB & GC --> DS[display_snapshot.v (CDC)]
        DS --> LR[left_renderer.v]
        DS --> UR[ui_renderer.v]
        DS --> RR[right_renderer.v]
        LR --> UR
        UR --> OLED_L[left_oled - JA]
        RR --> OLED_R[right_oled - JB]
        LM[level_map.v (BRAM)] <--> CE
        LM <--> RR
        LM -.->|Title Cave Scroll| UR
    end
```

---

## 4. Key Subsystem Implementation Notes

### 4.1 Clocking & Clock Domain Crossing (CDC)
* **100 MHz Domain:** Inputs, physics, collision FSM, game state, audio PWM.
* **6.25 MHz Domain:** OLED SPI transmission and pixel rasterization.
* **CDC Module ([`display_snapshot.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/display_snapshot.v)):** Uses a 4-phase toggle handshake with 2-stage synchronizers (`meta -> sync`). The display domain registers snapshot data and only commits it to output on `frame_begin`. This guarantees tearing-free 60 fps rendering.

### 4.2 PS/2 Mouse & Coordinates
* Mouse is initialized to stream mode (`0xF4`) at 40 Hz reporting.
* [`mouse_adapter.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/mouse_adapter.v) maintains clamped cursor coordinates $(x, y) \in [0..95, 0..63]$ matching the 96×64 OLED resolution.
* Drag-and-drop: Left click down on inventory initiates drag; release over a 3×3 grid cell places the part. Right-click removes parts.
* In RUN mode, left clicks on balloons in the vehicle diagram or action bar trigger popping requests.

### 4.3 Vehicle Construction Rules ([`vehicle_builder.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/vehicle_builder.v))
* Vehicle footprint is 3×3 cells (each 8×8 world pixels, total 24×24 pixels).
* Structural rules:
  - `PIG` and `ENGINE` require an underlying `FRAME`.
  - `WHEEL` requires a supporting frame directly above or below.
  - `BALLOON` requires frame support below or beside.
  - Parts cannot exceed inventory stock limits.
* Stored build is preserved when running or retrying; incoming `damage_mask` and `damage_frame_mask` knock out cells during RUN mode without refunding stock or altering the base build.

### 4.4 Rigid Body Physics & Rotation ([`physics_engine.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/physics_engine.v))
* Kinematics use Q12.8 fixed-point format (`LP_COORD_BITS = 20` or 16-bit).
* Rotation is quantized into 32 angular steps (11.25° increments) covering -16..15 tilt values via [`rotation_geometry.vh`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/rotation_geometry.vh).
* Acceleration calculation $a = F / m$ uses a 16-cycle restoring divider ([`signed_divider16.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/signed_divider16.v)).
* Ground friction: Rolling drag = 10 units; scraping drag (bare frames on rock) = 128 units.
* Camera height smoothing: `display_y` uses an alpha-beta filter to eliminate 2-pixel terrain step jitter.

### 4.5 Terrain Collision & SAT ([`rotating_map_collision_engine.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/rotating_map_collision_engine.v))
* Evaluates rotated bounding pixel area against solidity RAM using Separating Axis Theorem (SAT).
* Performs floor snapping (up to 3px steps, 6px when turning) and horizontal obstacle blocking.
* Terrain gradient $dy/dx$ is sampled using left/right terrain probes and reported in Q4.4 format for downhill slope acceleration.
* Unsupported overhanging edges report `tip_dir` (+1 / -1) to torque the vehicle into a roll.

### 4.6 Explosions & TNT ([`tnt_controller.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/tnt_controller.v))
* Swept-AABB detection between previous and current vehicle poses guarantees high-speed movements never tunnel through TNT.
* Explosions calculate radial squared distance to each 8×8 cell, knocking out contents and wood frames, kicking up vehicle velocity, and triggering visual smoke particles and explosion audio.

### 4.7 Audio & BGM Synthesis ([`bgm_player.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/bgm_player.v), [`sound_generator.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/sound_generator.v))
* BGM Modes:
  - `2'b00`: BUILD mode (*The Entertainer* by Scott Joplin, 96 BPM).
  - `2'b01`: RUN mode (*Bad Piggies Theme*, 155 BPM fast tempo with dual-voice bassline, attenuated to leave headroom for SFX).
  - `2'b10`: TITLE mode (*Start Screen Fanfare*, 135 BPM upbeat title melody).
* SFX Priority: $\text{Failure} > \text{Success} > \text{Explosion} > \text{Collision} > \text{Pop} > \text{Launch} > \text{Test}$.
* Outputs 8-bit PWM on `JXADC[0]` with hardware gain on `JXADC[1]` and active shutdown on `JXADC[3]`.

### 4.8 Dual OLED Rendering & Port B Multiplexing
* **JA (Left OLED):** Rotated 180° in hardware (`95 - x`, `63 - y`) because PMOD JA is mounted upside down on the Basys 3 board.
  - *Title Screen:* Scrolling cave background with game logo, Play button, and Settings button.
  - *Build Screen:* 16px grid, inventory pages 1 & 2, drag preview, Go button, Book/Settings icons.
  - *Run Screen:* Centered 12px damage diagram, direct balloon popping, top buttons (`[RETRY]`, `[GEAR]`, `[EDIT]`), bottom squarish buttons (`ENG`, `FAN`, `RCKT`, `BOOST`).
* **JB (Right OLED):**
  - Completely blanked (`16'h0000`) on Title Screen and Level Select screen.
  - World follow-camera with 4 zoom levels (1.5x, 1.0x, 0.75x, 0.5x) or mouse Free Look (SW4).
* **Port B BRAM Multiplexing:** During the Title Screen, because Right OLED is turned off, Port B of the terrain BRAM (`level_map.v`) is routed to the Left OLED pipeline with an offset scroll counter. This produces a live moving cave background at **0% extra BRAM cost**.

---

## 5. Development & Verification Guide

### 5.1 Running Simulations
Simulations are located in `sim/`. You can compile and run any testbench using Vivado `xvlog`/`xelab`/`xsim`:

```powershell
# Example: Running the full cave autonomous drive testbench
xvlog -i GPT_6_S2_01_I-FDP_project.srcs/sources_1/new sim/cave_arch_drive_tb.v
xelab -debug typical cave_arch_drive_tb -s cave_arch_drive_sim
xsim cave_arch_drive_sim -R
```

Or run all testbenches using the PowerShell regression runner:
```powershell
.\scripts\run_all_tests.ps1
```

### 5.2 Building Bitstream
To run synthesis, implementation, and bitstream generation:
```powershell
vivado -mode batch -source scripts/build_bitstream.tcl
```
Check resource utilization and timing in:
- `tmp/bitstream_build/utilization_routed.rpt`
- `tmp/bitstream_build/timing_routed.rpt`

Verify that:
- **Block RAM Tile** $\le 48$ / 50.
- **Slice LUTs** $\le 20,800$.
- **WNS** $\ge 0.000$ ns.

---

## 6. Checklist for Future AI Agents

Before declaring any coding task complete:
1. [ ] Did you avoid touching `cave_*.mem` and `level_map.v`?
2. [ ] Did you ensure 0 additional Block RAM blocks were introduced?
3. [ ] Did all 51 testbenches pass cleanly?
4. [ ] Did timing close with positive WNS and WHS?
5. [ ] Are all UI hitboxes backward-compatible with legacy automated tests?
6. [ ] Are changes cleanly staged without leftover temporary files?
