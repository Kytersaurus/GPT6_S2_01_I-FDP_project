# Gameplay Menu, Vehicle Builder & Dual-OLED UI Guide

This document details the user interface layouts, PS/2 mouse drag-and-drop builder rules, directional part mounting, runtime action controls, and Dual-OLED Field Diary implemented in `ui_controller.v`, `vehicle_builder.v`, `ui_renderer.v`, `left_renderer.v`, and `right_renderer.v`.

---

## 1. Screen Flow & Master Game States

* **Title Screen (`start_screen_active`):**
  - **Left OLED (`JA`):** Animated dual-layer scrolling clouds over the live scrolling Cave Arch background (`level_map.v` Port B multiplexed at 0% extra BRAM), `"LAGGY PIGGIES"` banner, centered **`[PLAY]`** button (`x = 38..58, y = 30..50`, launching into `LP_LEVEL_TUTORIAL` on first play), and bottom-left **`[GEAR]`** Settings button (`x = 4..20, y = 46..62`).
  - **Right OLED (`JB`):** Blanked (`16'h0000`).
  - **1-Screen Mode (`SW1`):** Toggling `SW1 = 1` routes the Right OLED World Map directly onto Left OLED (`JA`) and blanks Right OLED (`JB`).
* **Interactive Tutorial Level (`LP_LEVEL_TUTORIAL = 2'd2`):**
  - **Read-Only Build View (`LP_BUILD`):** Displays the prebuilt tutorial contraption (`Pig + Engine + Booster + Fan + Balloon + 2 Wheels`) on the Left OLED 3×3 grid with editing locked (`build_locked = 1`), shows `"CLICK GO TO PLAY"` at `y = 56` (while hiding the Map 1/2 Diary button via `tutorial_mode`), renders a Welcome card with a procedural `[ C ]` (`BTNC`) button icon on Right OLED, and automatically clears `stored_build_grid` when switching to Map 1 or Map 2.
  - **Timer-Free Guided Practice & Blinking Tile Prompts (`LP_RUN`):** Blanks the 4-digit 7-segment timer (`an = 4'b1111`), anchors the camera to the floor (`world_height = 126`), blinks (`16'hffe0`) the exact target cell border on Left OLED (`tutorial_target_cell`: Engine cell 3, Rocket cell 1, Fan cell 7), immediately releases the initial pause when the Engine tile is clicked, displays the `[ C ]` (`BTNC`) icon for post-TNT retry, and ends on a flush on-land finish checkerboard (`x = 216..248, y = 120..125`) with a Finish Flag (`x = 228, y = 106..120`) and landing goal box (`x = 216..248, y = 104..120`).
* **Build Screen (`LP_BUILD`):**
  - **Left OLED (`JA`):**
    - **Left Inventory Strip (`x = 1..15`):** Stacked part slots with live stock badges, plus a bottom page-cycle arrow (`[v]` on Page 1, `[^]` on Page 2).
      - **Page 1:** Wood Frame, Pig Pilot, Wheel, Engine, Balloon.
      - **Page 2:** Rocket Booster, Propeller Fan, and On-Board TNT Crate.
    - **Center 3×3 Build Grid (`x = 20..67, y = 4..51`):** Nine `16×16` px cells with cursor hover highlight, green/red placement validity outline, and ghost drag preview.
    - **Bottom Action Bar (`y = 55..63`):** Bottom-left **`[GO]`** launch button (`x = 0..17`, green when `build_valid`, red/locked when invalid), **`[BOOK]`** Field Diary button (`x = 64..79`, hidden in Tutorial mode), and **`[GEAR]`** Settings button (`x = 80..95`).
  - **Right OLED (`JB`):** Live world preview with vehicle at spawn, zoomable via `SW14` or mouse scroll wheel (`1.5×`, `1.0×`, `0.5×`) and pannable via `SW13` Free Look.

---

## 2. Vehicle Construction & Directional Mounting Rules (`vehicle_builder.v`)

1. **Contents-First Drag & Removal:**
   - **Left-Click / Drag from Inventory:** Places a part into a target 3×3 cell.
   - **Left-Click / Drag Inside Grid:** Moves the top-most part (contents first; if empty, moves the underlying wood frame) to another cell.
   - **Right-Click Inside Grid:** Refunds the top-most part in that cell back to inventory stock (removes contents first, then removes the underlying wood frame on a second right-click).
2. **Part Mounting Requirements:**
   - **`LP_PART_FRAME` (Wood Crate / On-Board TNT Crate):** When selected on Inventory Page 1 (`clean_facing_down = 0`), places a structural Wood Frame into `build_frames[cell]` within `FRAME_LIMIT`. When selected on Inventory Page 2 (`clean_facing_down = 1`), places an **On-Board TNT Crate** (`LP_PART_FRAME` in `build_grid[cell*3 +: 3]`, limit 1), which requires an underlying Wood Frame in the same cell.
   - **`LP_PART_PIG` (Pig Pilot) & `LP_PART_ENGINE` (Engine):** Require a `FRAME` in the **same cell**. Exactly one Pig is required for `build_valid`.
   - **`LP_PART_WHEEL` (Wheel):** Requires a supporting `FRAME` above, below, left, or right (`wheel_support`) and an empty cell (`!build_frames[cell]`). Only wheels with a frame directly above or below count toward ground-contact `wheels_down` / `wheels_up`.
   - **`LP_PART_BALLOON` (Balloon):** Requires a supporting `FRAME` directly below it (it cannot share a cell with a frame).
   - **`LP_PART_FAN` (Propeller Fan) & `LP_PART_BOOSTER` (Rocket):**
     - Can be placed **inside a `FRAME` cell** or **attached externally** to an orthogonally adjacent `FRAME` (`wheel_support`: frame in cell, above, below, left, or right).
     - Requires **at least one clear exhaust/propulsion face not blocked by an adjacent `FRAME`** (`~frame_right`, `~frame_left`, `~frame_above`, `~frame_below`).
     - Non-frame neighbors (wheels, balloons, or another fan/rocket) **never block** fan or rocket placement and never invalidate `build_valid`.
     - **Auto-Orientation & Click-to-Flip:** External fans/rockets automatically orient away from the supporting frame (`resolve_direction`). Left-clicking an already-placed fan or rocket cycles its facing across all valid frame-clear directions.
3. **Propulsion & Reverse Rules:**
   - **Wheel Engine:** Drives right (`+X`) when `SW15 = 0`, or reverses left (`-X`) when `SW15 = 1`. It has no switch: it starts OFF each run and is toggled only by clicking the Engine cell.
   - **Propeller Fan:** Blows air in the direction it faces, pushing the vehicle in the **opposite** reaction direction:
     - **Fan pointing RIGHT** (`facing_left = 0`) blows air right $\to$ **pushes vehicle LEFT (`-X`)**.
     - **Fan pointing LEFT** (`facing_left = 1`) blows air left $\to$ **pushes vehicle RIGHT (`+X`)**.
     - **Fan pointing DOWN** (`facing_down = 1`) blows air down $\to$ **pushes vehicle UP (`-Y` lift)**.
     - Fan direction is fixed by its placement orientation and is **never inverted by `SW15`**, so players can combine or oppose engine and fan forces freely.
   - **Rocket Booster:** Fires a high-impulse burst (`+X` when horizontal right, `-X` when horizontal left, `-Y` when vertical up, `+Y` when vertical down).

---

## 3. Interactive Run Screen (`LP_RUN`) & Post-Run Results (`LP_SUCCESS` / `LP_FAIL`)

* **Centered 3×3 Interactive Vehicle Diagram (`x = 24..71, y = 2..49`):**
  - Renders the 3×3 vehicle at **16×16 px per cell** with live damage masks (destroyed frames/parts disappear upon TNT/terrain impact).
  - **Direct Cell Clicks:**
    - Clicking an intact **Balloon cell** pops that specific balloon.
    - Clicking an intact **On-Board TNT cell** detonates it in-flight (`onboard_tnt_detonate`), destroying orthogonal neighbor cells/frames, scattering debris (`scatter_mask`), and applying a directional velocity kick.
    - Clicking an intact **Engine cell** toggles wheel drive (`ui_engine_on`). This is the only engine control.
    - Clicking an intact **Fan cell** toggles **only that specific fan (`ui_active_fans[cell]`)**, allowing individual fans to be turned on/off independently.
    - Clicking an intact **Rocket cell** triggers a rocket boost pulse (shortcut: `BTNR`).
* **Bottom Navigation Bar (`y = 53..63`):**
  - **`[TRY]` (`x = 2..22`):** Resets the vehicle to spawn with all parts restored (shortcut: `BTNC`).
  - **`[END]` (`x = 26..46`):** Ends the current attempt (`end_try_req`).
  - **`[EDIT]` (`x = 50..70`):** Returns to `BUILD` mode with the saved blueprint intact (shortcut: `BTNU`).
  - **`[GEAR]` (`x = 74..94`):** Opens the Settings menu (`LP_SETTINGS`).
* **Victory / Game-Over Screens (`LP_SUCCESS` / `LP_FAIL`):**
  - Displays 3-Star rating badges (`Goal`, `Star Box`, `Par Time` on `LP_SUCCESS`) or crash banner (`LP_FAIL`) on the left panel, stacked **`[EDIT]`** (`x = 56..92, y = 6..26`) and **`[RETRY]`** (`x = 56..92, y = 30..50`) buttons on the right panel, and a bottom action bar (`y = 53..63`: `[HOME]`, `[MAP SELECT]`, `[GUIDE]`, `[SETTINGS]`).
* **7-Segment Countdown Timer:**
  - Counts down from the active level's `par_time` (`25 s` on Cave Arch, `45 s` on Cave Flight) in `M.SS` / `SS` seconds format down to `00` and negative overtime (`-01`, `-02`, ...) exclusively on the Basys 3 4-digit 7-segment display (`seven_seg_timer.v`). Blanked during `LP_LEVEL_TUTORIAL`.

---

## 4. Dual-OLED Field Diary (`LP_GUIDE`) & Settings `[ ? ]` Switch Guide

1. **Dual-OLED Field Diary (`[BOOK]` / `BTNU` from Build):**
   - **Left OLED (`JA`):** Displays 3 concise walkthrough pages (`diary_page = 0, 1, 2`) with `[BACK]` (`x = 0..27, y = 52..63`) and page selector buttons `[1]` (`x = 32..51`), `[2]` (`x = 53..72`), and `[3]` (`x = 74..93`) at `y = 55..63`.
   - **Right OLED (`JB`):** Synchronized **live checkpoint camera & demo contraption** (`in_diary_walkthrough`): pans the camera across 3 key level checkpoints (`diary_pose_x`, `diary_pose_y`) while posing the recommended demo vehicle (`diary_grid`) on the live cave terrain.
2. **Settings Menu & `[ ? ]` Controls / Switch Guide (`[GEAR]`):**
   - **Main Settings View (`diary_page == 0`):**
     - **Sound Settings Card (`x = 8..44, y = 12..48`):** Opens Master Volume (`diary_page = 3`: `[-]` at `x = 8..28, y = 24..37`, `[+]` at `x = 64..84, y = 24..37` with 4 stepped bars, `MUTED BY SW0` banner, and `[BACK]` at `x = 0..27, y = 52..63`).
     - **Map Select Card (`x = 51..87, y = 12..48`):** Opens the 3-row Map Selector (`LP_LEVEL_SELECT`: `Map 1: Cave Arch` at `y = 10..21`, `Map 2: Cave Flight` at `y = 24..35`, `Tutorial` at `y = 38..49`, and `[BACK]` at `x = 0..27, y = 52..63`).
     - **`[ ? ]` (Bottom-Left Button, `x = 2..25, y = 52..62`):** Cycles through **Mouse Controls (`1/2`: Left-Click Drag & Right-Click Remove)** and **Board Switches (`2/2`: visual icons over `SW15` Reverse, `SW14` Zoom, `SW13` Free-Look Pan, `SW1` 1-OLED Mode, and `SW0` Mute)**.
     - **`[BACK]` (`x = 28..68, y = 52..62`):** Returns to the previous screen.
     - **`[HOME]` (`x = 70..95, y = 52..62`):** Returns to the `"LAGGY PIGGIES"` Start Screen.
