# Bad Piggies FPGA Project

A hardware-accelerated clone of *Bad Piggies* running entirely in Verilog/VHDL on the **Digilent Basys 3** FPGA (Xilinx Artix-7 `XC7A35T-1CPG236C`).

The design integrates interactive mouse-driven vehicle construction, a 3×3 grid with physical mounting constraints, a Newtonian physics engine with 32-angle quantized rotation, a Separating Axis Theorem (SAT) raster terrain collision engine, swept-AABB TNT explosions, dynamic vertical and horizontal crash damage, dual 96×64 RGB OLED displays with follower camera zoom, an active-low 7-segment run timer, and a real-time dual-voice audio synthesizer driving a Pmod AMP2 speaker.

---

## 1. Hardware Architecture & System Specifications

* **Target Device:** Digilent Basys 3 (`XC7A35T-1CPG236C`)
* **Logic Clock:** 100 MHz onboard oscillator
* **Dual OLED Displays:** Two 96×64 RGB OLEDs (SSD1331 controller via SPI at 6.25 MHz)
  - **Left OLED (PMOD JA):** Builder grid, inventory pages, minimal run-screen damage diagram, action buttons, and animated Title Screen. Rotated 180° in hardware (`95 - x`, `63 - y`) to compensate for the Basys 3 upside-down PMOD JA socket.
  - **Right OLED (PMOD JB):** World follower camera with 3 zoom levels (1.5x, 1.0x, 0.5x), terrain rendering, vehicle rotation, dynamic smoke/explosion particles, and goal flag. Blanked on Title Screen and Level Select.
* **Audio:** 8-bit PWM driving Pmod AMP2 on header JXADC (gain on `JXADC[1]`, active shutdown on `JXADC[3]`).
* **Input Interface:** Standard PS/2 streaming mouse on PMOD JC (scaled coordinate clamping $[0..95, 0..63]$).
* **Onboard I/O:** 4-digit active-low 7-segment display (M.SS run timer), slide switches (SW0–SW4, SW15), pushbuttons (BTNC, BTNU, BTNL, BTNR, BTND), and 16 LEDs.

---

## 2. Team Ownership & Responsibilities

The codebase is organized into modular subsystems developed by four team members:

| Role & Owner | Primary Subsystems | Owned Source Modules |
| :--- | :--- | :--- |
| **Role 1 (Kaushal)** | Vehicle Builder, Inventory/Stock, Mouse Input & Drag-and-Drop, Audio Pipeline (BGM + SFX), 7-Segment Timer, Left OLED UI | `vehicle_builder.v`, `mouse_adapter.v`, `sound_controller.v`, `sound_generator.v`, `bgm_player.v`, `seven_seg_timer.v`, `left_renderer.v`, `ui_renderer.v`, `balloon_control.v` |
| **Role 2 (Kyle)** | Newtonian Physics Engine, Fixed-Point Kinematics (Q12.8), 16-Cycle Signed Divider, Tilt Dynamics & Settling | `physics_engine.v`, `signed_divider16.v`, `rotation_geometry.vh` |
| **Role 3 (Yap Ting)** | Terrain Collision Engine (SAT Raster Scanner), TNT Explosions & Damage Masks, World Outcomes (Goal, Hazards, Death) | `rotating_map_collision_engine.v`, `tnt_controller.v`, `world_outcomes.v`, `pig_death_effect.v` |
| **Role 4 (Marcus)** | Master Game Controller FSM, Level Data, Dual-OLED Renderers (Follow-Camera, Viewports), CDC Display Snapshot | `game_controller.v`, `display_snapshot.v`, `right_renderer.v`, `level_map.v`, `level_button.v`, `zoom_control.v` |

---

## 3. Game Controls & Input Mapping

### 3.1 Basys 3 Board Controls
| Control | Function | Description |
| :--- | :--- | :--- |
| **Mouse Left-Click / Drag** | Part Placement / Balloon Pop | During **BUILD**: Drag parts from inventory pages or grid onto 3×3 cells. Releasing drops the part.<br>During **RUN**: Click surviving balloons on the Left OLED diagram or action bar to pop them. |
| **Mouse Right-Click** | Part Removal | During **BUILD**: First click clears cell contents (pig, engine, wheel, etc.); second click clears the wooden frame. Cancels active drag. |
| **Mouse Scroll Wheel** | Follow-Camera Zoom | Steps through 3 zoom levels: Close (1.5x) $\leftrightarrow$ Normal (1.0x) $\leftrightarrow$ Overview (0.5x). |
| **SW0** | Engine Throttle | Enables ground wheel motor thrust. |
| **SW1** | Audio Mute | `1` mutes all BGM and sound effects instantly; `0` enables audio. |
| **SW2** | Engine Reverse | Reverses engine drive torque (`1` = reverse, `0` = forward). |
| **SW3** | Zoom Toggle | Hardware switch shortcut for toggling camera zoom without a wheel mouse. |
| **SW4** | Free Look Mode | Enables mouse-controlled camera panning across the terrain. |
| **SW15** | Single-OLED Mode | `0`: Normal dual-OLED mode (JA = UI/Builder, JB = Follow-Camera).<br>`1`: Single-OLED mode (JA displays camera/world view; JB blanked). |
| **BTNC** | Launch / Retry | Launches vehicle from BUILD mode; retries current level after SUCCESS or FAIL. |
| **BTNU** | Edit / Next Level | Returns to BUILD from RUN/FAIL; advances to the next level after SUCCESS. |
| **BTNL** | Spring Impulse | Triggers a vertical impulse jump (+512 Q8 velocity) when grounded. |
| **BTNR** | Reserved | Debounced input; reserved for future controls (silent). |
| **BTND** | Master Reset | Resets entire game state, inventory, and hardware pipelines. |

### 3.2 Onboard Indicators
* **7-Segment Display:** Formatted as active-low `M.SS` elapsed run timer (e.g., `0.15` for 15 seconds) with decimal point lit on Digit 2 (`an = 4'b1011, dp = 0`). Uses a hardware subtraction ladder to avoid runtime division.
* **LEDs [2:0]:** Game State (`000` = BUILD, `001` = INIT_RUN, `010` = RUN, `011` = SUCCESS, `100` = FAIL).
* **LED 3:** World outcome pending.
* **LED 4:** Pig alive flag (`1` = alive, `0` = pig knocked out).
* **LED 5:** Build validity flag (`1` = valid build with 1 pig and supported attachments).
* **LED 6:** Engine active flag.
* **LEDs [15:7]:** 9-bit runtime intact mask for vehicle cells 8 down to 0.

---

## 4. Subsystem Highlights & Engineering Innovations

### 4.1 Zero Extra BRAM Architecture (48 / 50 Tiles — 96.00%)
* The Basys 3 FPGA contains exactly 50 Block RAM tiles (`RAMB36E1`), of which 48 are utilized for cave terrain maps and solid collision tables.
* **Port B Multiplexing for Animated Title Screen:** During the Title Screen, the Right OLED (JB) is completely blanked. Port B of the terrain BRAM (`level_map.v`) is multiplexed into the Left OLED raster pipeline with an offset scroll counter. This produces an animated, live parallax cave background on the Title Screen at **0% additional Block RAM cost**.
* All UI glyphs, start screen buttons, 5×7 font characters, star badges, and part sprites are rendered via distributed logic (LUT ROMs).

### 4.2 Minimalist Left OLED UI Layout
* **Title Screen:** Live animated cave background, Bad Piggies title logo, Play button, and Settings icon.
* **Build Screen:** 16-pixel cell grid, numbered inventory pages (P1/P2), part orientation flip, live drag preview, Go/Launch button, and level selector menu (Cave Arch 2x vs Cave Flight).
* **Run Screen:** Centered 12px vehicle damage diagram, interactive click-to-pop balloons, top action bar (`[RETRY]`, `[GEAR]`, `[EDIT]`), and bottom squarish action buttons (`ENG`, `FAN`, `RCKT`, `BOOST`). Fully backward-compatible with legacy testbench click coordinates.

### 4.3 Rigid Body Physics & Newtonian Kinematics
* Vehicle state represented in signed Q12.8 fixed-point coordinates (`velocity_x`, `velocity_y`, `pos_x`, `pos_y`).
* Quantized rotation into 32 discrete angular steps (11.25° increments) covering -16..+15 tilt values via [`rotation_geometry.vh`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/rotation_geometry.vh).
* Mass-based force division ($a = F / m$) calculated via a sequential 16-cycle restoring divider ([`signed_divider16.v`](file:///c:/Users/kaush/EE2026Labs/GPT6_S2_01_I-FDP_project/GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/signed_divider16.v)) to eliminate combinational divider trees.
* Slope acceleration dynamically sampled from terrain gradient $dy/dx$ (Q4.4).
* Alpha-beta smoothing on `display_y` removes discrete 2-pixel terrain step jitter.

### 4.4 Swept-AABB TNT & Realistic Crash Damage
* **Tunneling Prevention:** Swept-AABB bounding box between current and previous frame coordinates guarantees fast-moving vehicles never tunnel through TNT blocks.
* **Radial Explosion Damage:** Exploding TNT calculates radial squared distance to each cell, blowing off components, destroying wooden frames, kicking vehicle velocity outward, and spawning visual smoke particles.
* **Hard Vertical Landings:** Falling at excessive downward velocity ($v_y \ge 768$ Q8/frame) damages bottom-row cells (or top-row cells if flipped).
* **Horizontal Wall Ramming:** Ramming into solid cliff faces at high speed ($|v_x| \ge 768$ Q8/frame stopped by terrain) knocks out the leading column (cells 2, 5, 8 for right wall; cells 0, 3, 6 for left wall).
* **Frame Durability:** Wooden frames survive moderate collisions ($768 \le |v| < 1280$), but catastrophic terminal velocity impacts ($|v| \ge 1280$) completely demolish all parts and wooden frames (`9'b111_111_111`).

### 4.5 Dual-Voice BGM & Instant-Attack SFX
* **Immediate Sound Attack:** Removed sluggish amplitude fading counters; all sound effects trigger with instantaneous full-volume attack.
* **Dynamic SFX Profiles:**
  - `LAUNCH`: Rising fanfare (660 Hz $\to$ 990 Hz).
  - `POP`: Crisp high-frequency pop (1600 Hz).
  - `COLLISION`: 3-stage mechanical downward pitch crunch (400 Hz $\to$ 200 Hz $\to$ 100 Hz in 60 ms).
  - `EXPLOSION`: Low-frequency rumble (160 Hz $\to$ 110 Hz $\to$ 70 Hz).
  - `SUCCESS`: Victorious arpeggio (660 Hz $\to$ 880 Hz $\to$ 1320 Hz).
  - `FAILURE`: Descending sad trombone (440 Hz $\to$ 330 Hz $\to$ 220 Hz).
* **Dual-Voice Synthesizer:**
  - Build Mode: *The Entertainer* by Scott Joplin (96 BPM).
  - Run Mode: *Bad Piggies Theme* (155 BPM dual-voice bassline, attenuated for SFX headroom).
  - Title Mode: *Start Screen Fanfare* (135 BPM upbeat title melody).

---

## 5. Verification & Regression Testing

The test suite contains **74 automated testbenches** covering every module, interface handshake, and physical invariant.

### 5.1 Running the Regression Suite
Run all testbenches in PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_simulations.ps1
```

Or run an individual testbench using Vivado `xvlog`/`xelab`/`xsim`:
```powershell
xvlog --sv -i GPT_6_S2_01_I-FDP_project.srcs/sources_1/new sim/crash_impact_tb.v GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/*.v
xelab work.crash_impact_tb -s crash_impact_sim
xsim crash_impact_sim -runall
```

### 5.2 Building Bitstream
Run synthesis, placement, routing, and bitstream generation via Vivado batch mode:
```powershell
vivado -mode batch -source scripts/build_bitstream.tcl
```

Resource reports and timing closure results will be output to `tmp/bitstream_build/`:
- `utilization_routed.rpt`
- `timing_routed.rpt`

### 5.3 Hardware Budgets & Timing Constraints
* **Slice LUTs:** $\le 20,800$ (Current utilization: ~16,500 / 79.34%)
* **Block RAM Tiles:** $\le 48 / 50$ (Strict 0 extra BRAM rule)
* **Worst Negative Slack (WNS):** $> 0.000\text{ ns}$ (Clean timing closure at 100 MHz logic / 6.25 MHz SPI)
