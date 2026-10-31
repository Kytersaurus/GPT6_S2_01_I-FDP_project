# AGENTS.md — Team & AI Agent Guide

Welcome to the **Bad Piggies FPGA** codebase!  
This document serves as the single source of truth for **all human teammates (Kaushal, Kyle, Yap Ting, Marcus)** and **AI coding agents**. It outlines the core architectural rules, coding standards, hardware constraints, and verification procedures to ensure seamless pair programming and zero regressions.

---

## 1. Project Overview & Team Ownership

* **Project:** Hardware-accelerated clone of *Bad Piggies* running on the **Digilent Basys 3** FPGA (Xilinx Artix-7 `XC7A35T-1CPG236C`).
* **Hardware Interconnects:**
  - Logic clock: **100 MHz** (onboard oscillator).
  - Dual OLED displays: Two 96×64 RGB OLEDs (SSD1331 via SPI at **6.25 MHz**) on PMOD JA (Left) and PMOD JB (Right).
  - Audio: 8-bit PWM sound effects and dual-voice music driving Pmod AMP2 on JXADC.
  - PS/2 Mouse: Standard PS/2 streaming interface on PMOD JC.
  - Basys 3 onboard I/O: 4-digit active-low 7-segment display (M.SS timer), switches (SW0 engine, SW1 reverse, SW4 free look), and buttons.
* **Team Roles & Responsibilities:**
  - **Role 1 (Kaushal):** Vehicle Builder, Inventory/Stock Validation, Mouse Input & Drag-and-Drop, Audio Pipeline (BGM + SFX), 7-Segment Timer, Left OLED UI Layouts.
  - **Role 2 (Kyle):** Physics Engine, Newtonian Kinematics, Fixed-Point Arithmetic (Q12.8), 16-Cycle Signed Divider, Tilt Dynamics & Settling.
  - **Role 3 (Yap Ting):** Terrain Collision Engine (SAT Raster Scanner), TNT Explosions & Damage Masks, World Outcomes (Goal, Hazards, Death).
  - **Role 4 (Marcus):** Master Game Controller FSM, Level Data, Dual-OLED Renderers (Follow-Camera, Viewports), CDC Display Snapshot.

---

## 2. Core Coding Standards & Team Principles

### 💡 1. No Complicated / Obfuscated Code (Simplicity & Readability First)
* **Context:** This is an undergraduate academic FPGA project. The code must be clean, modular, self-documenting, and easy for any teammate or lab instructor to read, explain, and maintain.
* **Rules:**
  - **Avoid needlessly clever, dense, or obfuscated one-liners.**
  - **Avoid deeply nested ternary operators (`? : ? : ? :`).** Use clean `if...else if...else` blocks or explicit `case` statements.
  - **Name signals descriptively:** Use physical names (e.g. `is_grounded`, `engine_thrust`, `first_intact_balloon`) rather than cryptic abbreviations.
  - **Document physical meaning:** Always comment *why* a constant exists (e.g. `// Rolling drag = 10 units; scraping drag on bare wood = 128 units`).
  - **Explicit FSM states:** Define states with `localparam` and write clean state transition logic.

### ⚡ 2. Strict LUT Minimization (Tight FPGA Capacity)
* **Constraint:** The Artix-7 `XC7A35T` has only **20,800 Slice LUTs**. The design currently uses **~16,500 LUTs (79.34%)**. We must aggressively conserve LUTs to leave headroom.
* **Rules:**
  - **NO runtime division (`/`) or modulo (`%`) in single-cycle or display paths.**
    - A single combinational `/` or `%` synthesizes into massive multiplier/divider trees consuming hundreds of LUTs and destroying timing.
    - **Never do:** `wire [6:0] x = pixel_index % 96; wire [5:0] y = pixel_index / 96;` in active raster logic. Instead, track `x` and `y` using simple incremental counters or passed-down coordinates.
    - For timer BCD conversion (e.g. seconds $\to$ minutes/seconds), use **subtraction ladders** (e.g. `if (s >= 60) begin m = 1; s = s - 60; end`) rather than `/ 60` or `% 60`.
    - If division is strictly required for physics kinematics ($a = F/m$), use the sequential 16-cycle restoring divider ([`signed_divider16.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/signed_divider16.v)).
  - **Right-size bit widths:** Never declare signals as 32-bit `integer` or `reg [31:0]` when a 6-bit (`reg [5:0]`) or 10-bit value suffices. Oversized registers waste flip-flops and expand comparator logic.
  - **Share common logic:** Reuse shared arithmetic, coordinate lookups, and glyph drawing functions instead of duplicating identical decoding blocks.

### 🚫 3. STRICT ZERO EXTRA BRAM (Max 48 / 50 Tiles — 96.00%)
* **Constraint:** Basys 3 has exactly **50 Block RAM tiles** (`RAMB36E1`). Current design uses **48 tiles (96%)**.
* **Rules:**
  - **DO NOT instantiate any new Block RAM, dual-port RAMs, or large memory arrays.**
  - All new UI elements, buttons, glyphs, start screen artwork, star rating badges, and sprite animations **must be implemented in distributed logic (LUT ROMs)** using look-up tables, `ui_font.vh`, and combinational decoders.
  - **Reuse idle ports:** When an existing BRAM port is idle in a specific state, multiplex it. *(Example: During the Start Screen, Right OLED is blanked, so Port B of the terrain BRAM is borrowed by Left OLED to scroll the live cave background at 0% extra BRAM cost).*

### 🚫 4. NEVER TOUCH MAP FILES
* **Protected Files:** `cave_flight_map.mem`, `cave_flight_solid.mem`, `cave_flight_colour_*.mem`, `cave_arch_map.mem`, `cave_arch_solid.mem`, and [`level_map.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/level_map.v).
* **Reason:** Teammates are actively detailing the cave terrain artwork, color palettes, and collision solidity. Any changes here will corrupt parallel work. The engine is built so that when `.mem` files are re-exported, the collision and rendering pipelines automatically adapt without code edits.

### ⏱️ 5. Timing Closure at 100 MHz
* **Constraint:** Logic clock runs at **100 MHz**; OLED SPI clock runs at **6.25 MHz**.
* **Requirements:**
  - All builds must achieve positive slack: **WNS > 0.000 ns**, **WHS > 0.000 ns**, **0 failing endpoints**.
  - All cross-clock communication must pass through the registered CDC handshake module ([`display_snapshot.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/display_snapshot.v)).
  - Avoid wide combinational logic cascades across single clock cycles. Register intermediate results in FSM stages.

### 🛡️ 6. Maintain 100% Pass Rate on All 51 Testbenches & Backward Compatibility
* The test suite contains **51 testbenches** covering every subsystem.
* **Never commit breaking interface changes.**
* When adjusting UI button hitboxes on Left OLED, **always preserve backward compatibility** with legacy testbench clicks using fallback coordinates or prioritized checking order (`RETRY` $\to$ `SETTINGS` $\to$ `EDIT` $\to$ `ACTION ICONS`).

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

## 4. Hardware & Subsystem Implementation Details

### 4.1 Clock Domain Crossing (CDC)
* **100 MHz Domain:** Core FSM, inputs, physics calculations, SAT collision scanner, audio PWM.
* **6.25 MHz Domain:** OLED SPI transmission and pixel rasterization.
* **Snapshot Protocol ([`display_snapshot.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/display_snapshot.v)):** Uses a 4-phase toggle handshake with 2-stage synchronizers (`meta -> sync`). Output data commits strictly on `frame_begin`, preventing mid-frame tearing and metastability.

### 4.2 PS/2 Mouse & Coordinates
* Mouse runs in stream mode (`0xF4`) at 40 Hz reporting.
* [`mouse_adapter.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/mouse_adapter.v) scales raw deltas (`SPD: SLOW / NORM / FAST`) and clamps cursor coordinates to $[0..95, 0..63]$.
* Drag-and-drop: Holding Left Click over an inventory part starts dragging; releasing over a valid 3×3 grid cell places the part. Right-click removes parts.
* In RUN mode, left clicks on balloons in the vehicle diagram or action bar trigger popping requests.

### 4.3 Vehicle Construction Rules ([`vehicle_builder.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/vehicle_builder.v))
* Footprint is 3×3 cells (each 8×8 world pixels, total 24×24 pixels).
* Mounting rules:
  - `PIG` and `ENGINE` require an underlying `FRAME`.
  - `WHEEL` requires a supporting frame directly above or below.
  - `BALLOON` requires frame support below or beside.
  - Parts cannot exceed inventory stock limits.
* Stored build is preserved when running or retrying; incoming `damage_mask` and `damage_frame_mask` knock out cells during RUN mode without refunding stock or altering the base build.

### 4.4 Rigid Body Physics & Rotation ([`physics_engine.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/physics_engine.v))
* Kinematics use Q12.8 fixed-point format (`LP_COORD_BITS = 20` or 16-bit).
* Rotation is quantized into 32 angular steps (11.25° increments) covering -16..15 tilt values via [`rotation_geometry.vh`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/rotation_geometry.vh).
* Mass division $a = F / m$ uses a 16-cycle restoring divider ([`signed_divider16.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/signed_divider16.v)).
* Ground friction: Rolling drag = 10 units; scraping drag (bare frames on rock) = 128 units.
* Camera smoothing: `display_y` uses an alpha-beta filter to eliminate 2-pixel terrain step jitter.

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

### 4.8 Dual OLED Rendering & Hardware Orientation
* **JA (Left OLED):** Rotated 180° in hardware (`95 - x`, `63 - y`) because PMOD JA is mounted upside down on the Basys 3 board.
  - *Title Screen:* Scrolling cave background with game logo, Play button, and Settings button.
  - *Build Screen:* 16px grid, inventory pages 1 & 2, drag preview, Go button, Book/Settings icons.
  - *Run Screen:* Centered 12px damage diagram, direct balloon popping, top buttons (`[RETRY]`, `[GEAR]`, `[EDIT]`), bottom squarish buttons (`ENG`, `FAN`, `RCKT`, `BOOST`).
* **JB (Right OLED):**
  - Completely blanked (`16'h0000`) on Title Screen and Level Select screen.
  - World follow-camera with 4 zoom levels (1.5x, 1.0x, 0.75x, 0.5x) or mouse Free Look (SW4).
* **Port B BRAM Multiplexing:** During the Title Screen, because Right OLED is turned off, Port B of the terrain BRAM (`level_map.v`) is routed to the Left OLED pipeline with an offset scroll counter. This produces a live moving cave background at **0% extra BRAM cost**.

### 4.9 7-Segment Run Timer ([`seven_seg_timer.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/seven_seg_timer.v))
* Formats elapsed run time as active-low `M.SS` with the decimal point lit on digit 2 (`an = 4'b1011, dp = 0`).
* Digit 3 actively scans (`an = 4'b0111, number = 0`) to satisfy Basys 3 digit multiplexing hardware contracts without ghosting.
* Uses subtraction-ladder BCD decoding instead of division to save LUTs and avoid timing paths.

---

## 5. Development & Verification Commands

### 5.1 Running Simulations
Compile and run any testbench using Vivado `xvlog`/`xelab`/`xsim`:
```powershell
# Example: Running the full cave autonomous drive testbench
xvlog -i GPT_6_S2_01_I-FDP_project.srcs/sources_1/new sim/cave_arch_drive_tb.v
xelab -debug typical cave_arch_drive_tb -s cave_arch_drive_sim
xsim cave_arch_drive_sim -R
```

Or run the complete regression test suite:
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

Verify before flashing:
- **Block RAM Tile** $\le 48$ / 50.
- **Slice LUTs** $\le 20,800$.
- **WNS** $\ge 0.000$ ns.

---

## 6. Pre-Commit Checklist for Teammates & Agents

Before committing or opening a PR:
1. [ ] **No complicated/unreadable code?** Is the logic clear, well-structured, and documented?
2. [ ] **LUT minimized?** Did you avoid single-cycle `/` and `%`? Are register bit-widths minimal?
3. [ ] **0 Extra BRAM?** Are all UI elements and icons in distributed LUT logic?
4. [ ] **Map files untouched?** Are `cave_*.mem` and `level_map.v` completely unmodified?
5. [ ] **All 51 testbenches passing?** Did you run regression tests without errors?
6. [ ] **Timing closed?** Are WNS and WHS positive with 0 failing endpoints?
7. [ ] **Backward-compatible hitboxes?** Do legacy automated clicks still trigger expected buttons?
8. [ ] **Clean git status?** No temporary files, logs, or clutter left behind?
