# Basys 3 Bitstream Archive (`bitstreams/`)

This directory organizes all verified programming bitstreams (`.bit`) generated for the **Digilent Basys 3 (`XC7A35T-1CPG236C`)** FPGA board.

---

## 📁 Directory Organization

* **`bad_piggies_top_latest.bit`** — Always points to a ready-to-flash copy of the most recent verified build.
* **`LATEST.txt`** — Machine- and human-readable metadata pointer for the latest build (timestamp, source commit, utilization, and timing).
* **`builds.json`** — Complete chronological manifest of all **52 archived builds** with ISO timestamps, source commits, descriptions, and SHA-256 checksums.
* **`YYYY-MM-DD/HHMMSS_My_Top_Module.bit`** — Date-indexed folders storing every historical build in `HHMMSS` chronological order.

---

## 🌟 Latest Recommended Build for Hardware Flashing

| Property | Value |
| :--- | :--- |
| **Quick-Flash File** | **[`bad_piggies_top_latest.bit`](bad_piggies_top_latest.bit)** |
| **Archived Path** | **[`2026-11-06/172639_My_Top_Module.bit`](2026-11-06/172639_My_Top_Module.bit)** |
| **Pointer Metadata** | [`LATEST.txt`](LATEST.txt) |
| **Source Commit** | `38d8512` / `b7f4f27` (`main`) |
| **Build Timestamp** | `2026-11-06 17:26:39 +08:00` |
| **Resource Utilization** | **17,199 / 20,800 Slice LUTs (82.69%)**, **48 / 50 Block RAM (`96.00%`)**, **16 / 90 DSP48E1 (`17.78%`)**, **WNS > `0.000 ns`** |
| **Key Highlights** | • **Interactive Guided Tutorial (`LP_LEVEL_TUTORIAL`):** Prebuilt tutorial contraption with `"CLICK GO TO PLAY"` prompt in `BUILD`, blinking target cell borders (`tutorial_target_cell`) in `RUN`, procedural `[ C ]` (`BTNC`) button prompt on Welcome/Retry screens, and floor-anchored tutorial camera (`world_height = 126`).<br>• **Ergonomic Switch Layout:** Left cluster for gameplay (`SW15` Engine Reverse, `SW14` Camera Zoom, `SW13` Free-Look Pan); right cluster for settings (`SW1` 1-OLED JA Map View, `SW0` Hardware Audio Mute); wheel engine is mouse-only on the 3×3 run diagram.<br>• **Tiered Fall Damage & On-Board TNT:** Medium falls break only the contact row's non-pig parts while preserving wood frames; high falls break all non-pig parts/frames; clickable on-board TNT crate detonates in-flight with radial blast masks and debris scatter.<br>• **Sub-Pixel Q12.1 Display Smoothing & Rotation Stability:** Half-pixel (`0.5 px`) sprite rendering with rocket exhaust flames, fan wind particles, wheel landing bounce, and 2-sample stationary hysteresis + anti-reversal lock preventing slope oscillation. |

---

## 🔌 Flashing & Hardware Setup Guide

1. **Power & USB:** Connect the **Basys 3** via USB (`PROG` port) and turn the power switch ON.
2. **Dual OLED Displays:**
   - **Left OLED (`PMOD JA`):** UI / Builder / Run Control Panel (or World Map when `SW1 = 1`).
   - **Right OLED (`PMOD JB`):** Follow-Camera World View (blanked on Title/Level Select and when `SW1 = 1`).
3. **PS/2 Mouse:** Connect to the **USB-HID Host** port (or `PMOD JC`).
4. **Audio (`Pmod AMP2` on `JXADC`):**
   > [!CAUTION]
   > Plug Pmod AMP2 into the **TOP ROW (`JXADC` pins 1–6) ONLY** (`Pin 1 = JXADC[0]` on the right-hand top pin). Do **NOT** plug into the bottom row (pins 7–12) or reverse polarity.
5. **Program via Vivado:**
   - Open **Vivado Hardware Manager** $\to$ **Open Target** $\to$ **Auto Connect** $\to$ **Program Device**.
   - Select **`bitstreams/bad_piggies_top_latest.bit`** and click **Program**.
6. **Build & Archive a Fresh Bitstream:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/build_and_archive.ps1
   ```

---

## 📅 Chronological Bitstream History

| Date | Time (SGT) | Bitstream File | Commit | Summary |
| :--- | :--- | :--- | :--- | :--- |
| **2026-11-06** | `17:26:39` | [`2026-11-06/172639_My_Top_Module.bit`](2026-11-06/172639_My_Top_Module.bit) | `38d8512` | **LATEST:** Guided Tutorial prompts & blinking target cells, remapped `SW15`–`SW13` / `SW1`–`SW0` switches, mouse-only engine, tiered fall damage, on-board TNT crate, Q12.1 half-pixel rendering & stationary slope anti-reversal lock. |
| **2026-11-06** | `07:14:29` | [`2026-11-06/071429_My_Top_Module.bit`](2026-11-06/071429_My_Top_Module.bit) | `08df53a` | Interactive Tutorial level integration, per-level par countdown timer (`25 s` / `45 s`), and updated Diary walkthrough. |
| **2026-11-05** | `16:17:45` | [`2026-11-05/161745_My_Top_Module.bit`](2026-11-05/161745_My_Top_Module.bit) | `089c399` | Fan/rocket arrow sync & mounting bracket, single-use rocket dimming, Diary pose/zoom/fan/frame fixes, bare-Pig rolling physics on TNT/high-fall frame break, Result Screen Settings icon (`17,200 LUTs` / `82.69%`, `48 BRAM`, `16 DSP`, `WNS +0.106 ns`). |
| **2026-11-05** | `14:22:00` | [`2026-11-05/142200_My_Top_Module.bit`](2026-11-05/142200_My_Top_Module.bit) | `5081b2d` | Renderer LUT sharing (`16,896 LUTs` / `81.23%`, `48 BRAM`, `16 DSP`), updated Diary contraptions, Settings `[ ? ]` guide, `LED[12:3]` launch/end flash animations, cleaned switches. |
| **2026-11-04** | `17:50:06` | [`2026-11-04/175006_My_Top_Module.bit`](2026-11-04/175006_My_Top_Module.bit) | `4b40b95` | 1–3 star rating, `GAME OVER` text, edit wrench icon, +1 Level 2 rocket/fan, horizontal rocket next to wheels, per-map fall damage (`20,334 LUTs`, `WNS +0.019 ns`). |
| **2026-11-04** | `17:14:38` | [`2026-11-04/171438_My_Top_Module.bit`](2026-11-04/171438_My_Top_Module.bit) | `37f11bb` | Consolidated UI sprite ROM lookups (`-1,002 LUTs` down to `19,962` / `95.97%`). |
| **2026-11-04** | `16:15:00` | [`2026-11-04/161500_My_Top_Module.bit`](2026-11-04/161500_My_Top_Module.bit) | `ec92669` | 3-star Right OLED ending card, TNT/fall/builder edge-case fixes. |
| **2026-11-04** | `15:17:00` | [`2026-11-04/151700_My_Top_Module.bit`](2026-11-04/151700_My_Top_Module.bit) | `dd9b379` | Auto-orient fan/rocket mounts, inventory drag cycling & down-arrow glyph fixes. |
| **2026-11-04** | `12:19:00` | [`2026-11-04/121900_My_Top_Module.bit`](2026-11-04/121900_My_Top_Module.bit) | `3579d38` | 4-directional rockets, downward fan sprite/physics, removed SPD setting, frame edit & pause menu fixes. |
| **2026-11-04** | `07:31:00` | [`2026-11-04/073100_My_Top_Module.bit`](2026-11-04/073100_My_Top_Module.bit) | `55dd7f9` | Merged `main` build with terrain following, TNT impact recovery, and updated UI/physics (`WNS +0.051 ns`, `19,613 LUTs`). |
| **2026-11-03** | `22:16:00` | [`2026-11-03/221600_My_Top_Module.bit`](2026-11-03/221600_My_Top_Module.bit) | `df4c7ee` | Full LUT division elimination (`18,992 LUTs`), actuators start OFF in `RUN`, downward fan lift (`+40`), independent fan toggles. |
| **2026-11-03** | `03:38:11` | [`2026-11-03/033811_My_Top_Module.bit`](2026-11-03/033811_My_Top_Module.bit) | `ad5a982` | Star boxes restored on both cave levels, Cave Flight first hump filled, 3 TNT slots (`WNS +0.014 ns`). |
| **2026-11-03** | `03:24:59` | [`2026-11-03/032459_My_Top_Module.bit`](2026-11-03/032459_My_Top_Module.bit) | `ad5a982` | Intermediate star-box and 3-TNT-slot build (superseded by `033811`). |
| **2026-11-03** | `00:25:00` | [`2026-11-03/002500_My_Top_Module.bit`](2026-11-03/002500_My_Top_Module.bit) | `df4c7ee` | Initial component state OFF upon `RUN` entry and directional fan lift. |
| **2026-11-03** | `00:09:54` | [`2026-11-03/000954_My_Top_Module.bit`](2026-11-03/000954_My_Top_Module.bit) | `3bd523c` | Map drawn on OLED clock (`SMOOTH_DRAW` off) fixing pixel flicker (`WNS +0.059 ns`). |
| **2026-11-02** | `23:30:28` | [`2026-11-02/233028_My_Top_Module.bit`](2026-11-02/233028_My_Top_Module.bit) | `48c4fe5` | Cave Flight gaps widened to 45 px, TNT on both cave levels (superseded by `000954`). |
| **2026-11-02** | `21:01:10` | [`2026-11-02/210110_My_Top_Module.bit`](2026-11-02/210110_My_Top_Module.bit) | `207dba0` | Directional fans with lift, support rules, discrete scroll, and UI polish. |
| **2026-11-02** | `18:10:25` | [`2026-11-02/181025_My_Top_Module.bit`](2026-11-02/181025_My_Top_Module.bit) | `69b4635` | Collision impact & TNT updates, pencil edit icon, circular refresh icon, 4 volume bars (`WNS +0.007 ns`). |
| **2026-11-02** | `17:19:24` | [`2026-11-02/171924_My_Top_Module.bit`](2026-11-02/171924_My_Top_Module.bit) | `a9b62fb` | Role 3 collision and TNT merge build 2. |
| **2026-11-02** | `16:08:44` | [`2026-11-02/160844_My_Top_Module.bit`](2026-11-02/160844_My_Top_Module.bit) | `a9b62fb` | Role 3 collision and TNT merge build 1. |
| **2026-11-02** | `13:11:00` | [`2026-11-02/131100_My_Top_Module.bit`](2026-11-02/131100_My_Top_Module.bit) | `81264b7` | Horizontal wall crash damage, punchy 3-stage collision SFX, 3 zoom levels (`WNS +0.007 ns`). |
| **2026-11-02** | `11:35:38` | [`2026-11-02/113538_My_Top_Module.bit`](2026-11-02/113538_My_Top_Module.bit) | `de54989` | Physics Rework PR #9, mouse sensitivity teleport fix, calibrated landing impact damage, icon UI glyphs. |
| **2026-11-02** | `02:47:10` | [`2026-11-02/024710_map-smooth-flight-route.bit`](2026-11-02/024710_map-smooth-flight-route.bit) | `fd60189` | Scale2x map smoothing, solid grass, widened Cave Flight route. |
| **2026-11-02** | `02:41:13` | [`2026-11-02/024113_My_Top_Module.bit`](2026-11-02/024113_My_Top_Module.bit) | `75b1c6e` | Collision velocity threshold tuning (build 2). |
| **2026-11-02** | `00:27:09` | [`2026-11-02/002709_My_Top_Module.bit`](2026-11-02/002709_My_Top_Module.bit) | `75b1c6e` | Collision velocity threshold tuning (build 1). |
| **2026-11-01** | `21:06:20` | [`2026-11-01/210620_My_Top_Module.bit`](2026-11-01/210620_My_Top_Module.bit) | `70f19c8` | Complete UI iconification, Piggy Island title screen, Result Screen Map Select, 20×20 Star Crate & Map TNT (`WNS +0.105 ns`). |
| **2026-11-01** | `20:49:00` | [`2026-11-01/204900_My_Top_Module.bit`](2026-11-01/204900_My_Top_Module.bit) | `ae7710c` | Physics stability and collision response bug fixes. |
| **2026-11-01** | `03:32:33` | [`2026-11-01/033233_My_Top_Module.bit`](2026-11-01/033233_My_Top_Module.bit) | `9bfc817` | Build menu and rotational moments physics fixes (build 2). |
| **2026-11-01** | `00:13:06` | [`2026-11-01/001306_My_Top_Module.bit`](2026-11-01/001306_My_Top_Module.bit) | `9bfc817` | Build menu and rotational moments physics fixes (build 1). |
| **2026-10-31** | `23:11:37` | [`2026-10-31/231137_My_Top_Module.bit`](2026-10-31/231137_My_Top_Module.bit) | `dae141a` | Merged `physics-moments` with start menu and builder improvements. |
| **2026-10-31** | `22:29:04` | [`2026-10-31/222904_My_Top_Module.bit`](2026-10-31/222904_My_Top_Module.bit) | `0cc4053` | Wheel and rocket rotational moments integration (build 4). |
| **2026-10-31** | `21:50:02` | [`2026-10-31/215002_My_Top_Module.bit`](2026-10-31/215002_My_Top_Module.bit) | `0cc4053` | Angular damping and torque scaling (build 3). |
| **2026-10-31** | `20:15:42` | [`2026-10-31/201542_My_Top_Module.bit`](2026-10-31/201542_My_Top_Module.bit) | `0cc4053` | Refined wheel and rocket rotational moments (build 2). |
| **2026-10-31** | `19:53:21` | [`2026-10-31/195321_My_Top_Module.bit`](2026-10-31/195321_My_Top_Module.bit) | `0cc4053` | Added angular torque/moment calculations for wheels and rockets (build 1). |
| **2026-10-31** | `16:56:01` | [`2026-10-31/165601_My_Top_Module.bit`](2026-10-31/165601_My_Top_Module.bit) | `98ca1e1` | Complete UX & Audio Overhaul: `"LAGGY PIGGIES"` bubble font, 20s 7-seg countdown timer, 16×16 interactive run grid (`WNS +0.142 ns`). |
| **2026-10-31** | `15:58:32` | [`2026-10-31/155832_My_Top_Module.bit`](2026-10-31/155832_My_Top_Module.bit) | `98ca1e1` | Animated moving cave Start Screen (Port B BRAM multiplexing at 0% extra BRAM), 135 BPM fanfare, division-free BCD timer. |
| **2026-10-31** | `14:22:36` | [`2026-10-31/142236_My_Top_Module.bit`](2026-10-31/142236_My_Top_Module.bit) | `98fd28f` | 16-cycle restoring physics divider, animated Start Screen, centered run damage diagram, rocket booster (`WNS +0.253 ns`). |
| **2026-10-30** | `12:41:52` | [`2026-10-30/124152_My_Top_Module.bit`](2026-10-30/124152_My_Top_Module.bit) | `64c496f` | 2 cave levels (Cave Arch 2× and Cave Flight), `display_y` alpha-beta camera smoothing, 360° flip physics (`WNS +0.154 ns`). |
| **2026-10-30** | `01:32:18` | [`2026-10-30/013218_cave-arch-smooth.bit`](2026-10-30/013218_cave-arch-smooth.bit) | `5668802` | Smoothed Cave Arch terrain, steady tilt, gliding display, steep-slope probe. |
| **2026-10-30** | `01:25:41` | [`2026-10-30/012541_two_cave_levels_stripped_rects.bit`](2026-10-30/012541_two_cave_levels_stripped_rects.bit) | `99bd13c` | Stripped placeholder maps & rectangle collision engine; Cave Arch 2× & Cave Flight. |
| **2026-10-30** | `00:20:02` | [`2026-10-30/002002_cave-arch-motion.bit`](2026-10-30/002002_cave-arch-motion.bit) | `5668802` | Intermediate Role 4 steady tilt and gliding display build. |
| **2026-10-29** | `22:14:20` | [`2026-10-29/221420_cave-arch-loop-physics.bit`](2026-10-29/221420_cave-arch-loop-physics.bit) | `cdac53e` | Cave Arch drivable end-to-end at 2×, 360° rotation, wheel sides, edge tipping. |
| **2026-10-29** | `15:10:47` | [`2026-10-29/151047_My_Top_Module.bit`](2026-10-29/151047_My_Top_Module.bit) | `4f1912b` | 32-angle rotation tables and SAT occupancy collision engine. |
| **2026-10-29** | `14:21:48` | [`2026-10-29/142148_My_Top_Module.bit`](2026-10-29/142148_My_Top_Module.bit) | `b7c525f` | Natural 45° settling and coherent CDC display transfer test. |
| **2026-10-28** | `15:36:41` | [`2026-10-28/153641_My_Top_Module.bit`](2026-10-28/153641_My_Top_Module.bit) | `aa0efb1` | Slope physics: downhill gravity, uphill climbing resistance, terrain ROM queries. |
| **2026-10-27** | `14:13:37` | [`2026-10-27/141337_My_Top_Module.bit`](2026-10-27/141337_My_Top_Module.bit) | `ce62986` | Map BRAM cascade prevention, builder validation updates, coordinate expansion. |
| **2026-10-26** | `23:54:39` | [`2026-10-26/235439_My_Top_Module.bit`](2026-10-26/235439_My_Top_Module.bit) | `e013816` | Directional part facing validation, in-cell flipping, mouse grid selection. |
| **2026-10-26** | `16:37:45` | [`2026-10-26/163745_My_Top_Module.bit`](2026-10-26/163745_My_Top_Module.bit) | `bab2d96` | Run controls (`DRIVE`, `POP`, `SOUND` tabs) and map camera navigation. |
| **2026-10-25** | `18:01:42` | [`2026-10-25/180142_map-view-12px.bit`](2026-10-25/180142_map-view-12px.bit) | `b79d73a` | 1.5× map view with 12×12 sprites, TNT rendering, zoom & free look. |
| **2026-10-25** | `17:30:35` | [`2026-10-25/173035_cave-arch-camera.bit`](2026-10-25/173035_cave-arch-camera.bit) | `3f58d16` | 16×16 sprites, Cave Arch map preview, following camera. |
| **2026-10-25** | `00:00:34` | [`2026-10-25/000034_all-role-merge.bit`](2026-10-25/000034_all-role-merge.bit) | `0e960d4` | Initial 4-role merge integrating builder, physics, TNT/collision, and audio. |
| **2026-10-24** | `22:59:54` | [`2026-10-24/225954_engine-boost-audio.bit`](2026-10-24/225954_engine-boost-audio.bit) | `9fd5776` | Engine boost and multi-note audio events. |
| **2026-10-24** | `20:08:20` | [`2026-10-24/200820_vivado-build.bit`](2026-10-24/200820_vivado-build.bit) | Baseline | Earlier Vivado baseline build. |
| **2026-10-21** | `19:11:39` | [`2026-10-21/191139_balloon-test.bit`](2026-10-21/191139_balloon-test.bit) | Baseline | Interactive balloon popping test build. |
| **2026-10-19** | `19:29:05` | [`2026-10-19/192905_oled-test.bit`](2026-10-19/192905_oled-test.bit) | Baseline | Dual-layer OLED builder and mouse test build. |
