# Gameplay Menu, Vehicle Builder & Dual-OLED UI Guide

This document details the user interface layouts, PS/2 mouse drag-and-drop builder rules, directional part mounting, runtime action controls, and Dual-OLED Field Diary implemented in `ui_controller.v`, `vehicle_builder.v`, `ui_renderer.v`, `left_renderer.v`, and `right_renderer.v`.

---

## 1. Screen Flow & Master Game States

* **Title Screen (`LP_TITLE`):**
  - **Left OLED (`JA`):** Animated scrolling clouds over Piggy Island meadow, `"LAGGY PIGGIES"` banner, centered **`[PLAY]`** button, and bottom-left **`[GEAR]`** Settings button.
  - **Right OLED (`JB`):** Blanked (`16'h0000`).
  - **1-Screen Mode (`SW1`):** Toggling `SW1 = 1` routes the Right OLED World Map directly onto Left OLED (`JA`) and blanks Right OLED (`JB`).
* **Build Screen (`LP_BUILD`):**
  - **Left OLED (`JA`):**
    - **Left Strip (`x = 1..15`):** 3 stacked part slots (`15×15` px each) with live stock badges, plus a bottom page-cycle arrow (`[v]` on Page 1, `[^]` on Page 2).
      - **Page 1:** Wood Frame, Pig Pilot, Wheel, Engine, Balloon (first 3 visible slots + page toggle).
      - **Page 2:**Engine/Balloon/Rocket Booster/Propeller Fan slots depending on level stock.
    - **Center 3×3 Build Grid (`x = 20..67, y = 8..55`):** Nine `16×16` px cells with cursor hover highlight, green/red placement validity outline, and ghost drag preview.
    - **Right Action Column (`x = 71..94`):** Top **`[BOOK]`** (Field Diary) and **`[GEAR]`** (Settings) buttons, level indicator, and bottom **`[GO]`** launch button (green when `build_valid`, red/locked when invalid).
  - **Right OLED (`JB`):** Live world preview with vehicle at spawn, zoomable via `SW14` or mouse scroll wheel (`1.5×`, `1.0×`, `0.5×`) and pannable via `SW13` Free Look.

---

## 2. Vehicle Construction & Directional Mounting Rules (`vehicle_builder.v`)

1. **Contents-First Drag & Removal:**
   - **Left-Click / Drag from Inventory:** Places a part into a target 3×3 cell.
   - **Left-Click / Drag Inside Grid:** Moves the top-most part (contents first; if empty, moves the underlying wood frame) to another cell.
   - **Right-Click Inside Grid:** Refunds the top-most part in that cell back to inventory stock (removes contents first, then removes the underlying wood frame on a second right-click).
2. **Part Mounting Requirements:**
   - **`LP_PART_FRAME` (Wood Crate):** Can be placed in any cell within stock limits (`FRAME_LIMIT`).
   - **`LP_PART_PIG` (Pig Pilot) & `LP_PART_ENGINE` (Engine):** Require a `FRAME` in the **same cell**. At least one Pig is required for `build_valid`.
   - **`LP_PART_WHEEL` (Wheel):** Requires a supporting `FRAME` in the same cell, directly above, or directly below.
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
   - **Rocket Booster:** Fires a high-impulse burst (`+X` when horizontal, `-Y` when vertical).

---

## 3. Interactive Run Screen (`LP_RUN`)

* **Top Control Bar (`y = 1..10`):**
  - **`[RETRY]` (`x = 2..31`):** Resets the vehicle to spawn with all parts restored (shortcut: `BTNC`).
  - **`[GEAR]` (`x = 41..54`):** Opens Settings menu.
  - **`[EDIT]` (`x = 64..93`):** Returns to `BUILD` mode with the saved blueprint intact (shortcut: `BTNU`).
* **Centered 3×3 Interactive Vehicle Diagram (`x = 24..71, y = 11..50`):**
  - Renders the 3×3 vehicle at **16×16 px per cell** with live damage masks (destroyed frames/parts disappear or show damage upon TNT/terrain impact).
  - **Direct Cell Clicks:**
    - Clicking an intact **Balloon cell** pops that specific balloon.
    - Clicking an intact **Engine cell** toggles wheel drive (`ui_engine_on`). This is the only engine control.
    - Clicking an intact **Fan cell** toggles **only that specific fan (`fan_manual_mask[cell]`)**, allowing individual fans to be turned on/off independently.
    - Clicking an intact **Rocket cell** triggers a rocket boost pulse.
* **Bottom Action Bar (`y = 52..62`):**
  - **`[ENG]`**, **`[FAN]`** (toggles all intact fans together), **`[RCKT]` / `[BOOST]`** (fires rocket booster; shortcut: `BTNR`).
* **7-Segment Countdown Timer:**
  - The 20.0-second par countdown (`20.0` $\to$ `0.0` and negative overtime `-0.1`, `-0.2`, ...) is displayed exclusively on the Basys 3 4-digit 7-segment display (`seven_seg_timer.v`).

---

## 4. Dual-OLED Field Diary (`LP_GUIDE`) & Settings `[ ? ]` Switch Guide

1. **Dual-OLED Field Diary (`[BOOK]` / `BTNU` from Build):**
   - **Left OLED (`JA`):** Displays 3 concise pages (`1/3 GOAL`, `2/3 BUILD`, `3/3 RUN`) with `[BACK]`, `[<]`, and `[>]` navigation buttons.
   - **Right OLED (`JB`):** Synchronized visual walkthrough diagrams:
     - **Page 1 (`GOAL`):** Animated Pig Pilot $\to$ Goal Flag & 3-Star criteria diagram.
     - **Page 2 (`BUILD`):** Left Inventory $\to$ 3×3 Build Grid $\to$ `[GO]` button diagram.
     - **Page 3 (`RUN`):** Interactive 3×3 Click Diagram + Bottom Action Bar diagram.
2. **Settings Menu & `[ ? ]` Controls / Switch Guide (`[GEAR]`):**
   - **Main Settings View (`diary_page == 0`):**
     - **Sound Settings Card (`x = 8..44, y = 12..48`):** Opens Master Volume (`[-]` / `[+]` with 4 stepped bars and `MUTED BY SW0` banner).
     - **Map Select Card (`x = 51..87, y = 12..48`):** Opens the Map 1 / Map 2 selector (`LP_LEVEL_SELECT`).
     - **`[ ? ]` (Bottom-Left Button, `x = 2..25, y = 52..62`):** Cycles through **Mouse Controls (`1/2`: Left-Click Drag & Right-Click Remove)** and **Board Switches (`2/2`: visual icons over `SW15` Reverse, `SW14` Zoom, `SW13` Free-Look Pan, `SW1` 1-OLED Mode, and `SW0` Mute)**.
     - **`[BACK]` (`x = 28..68, y = 52..62`):** Returns to the previous screen.
     - **`[HOME]` (`x = 70..95, y = 52..62`):** Returns to the `"LAGGY PIGGIES"` Start Screen.
