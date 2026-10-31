# Basys3 Bitstream Archive

This directory organizes all verified programming bitstreams generated for the Basys3 FPGA (`xc7a35tcpg236-1`).

---

## 🌟 Latest Recommended Build for Board Testing

| Property | Value |
| :--- | :--- |
| **Bitstream File** | **[`2026-10-31/155832_My_Top_Module.bit`](2026-10-31/155832_My_Top_Module.bit)** |
| **Pointer File** | [`LATEST.txt`](LATEST.txt) |
| **Source Commit** | `98ca1e1` (integrated on `feature-polish`) |
| **Build Timestamp**| 2026-10-31 15:58:32 (SGT) |
| **Timing Slack** | **WNS = +0.193 ns**, **WHS = +0.063 ns**, **TNS = 0.000 ns** (Timing cleanly MET at 100 MHz) |
| **Resource Utilization** | **79.87% LUTs** (16,613 / 20,800), **96.00% BRAM** (48.0 / 50), **18.89% DSPs** (17 / 90) |
| **Simulation Suite** | **51 / 51 testbenches passing (100%)** |
| **Key Features** | • **Bulletproof Dividers**: 7-seg timer subtractive comparator (100% match across all 256s), combinational OLED coordinate translation (0-latency phase-safe), and 16-cycle restoring physics divider.<br>• **Animated Start Screen**: Moving cave background on Left OLED with upbeat fanfare BGM and Settings button.<br>• **Right OLED Blanking**: Right OLED completely blanks (`16'h0000`) on Title Screen and Level Select.<br>• **Run Screen Redesign**: Centered 12px vehicle damage diagram with direct balloon popping, top header buttons (`[RETRY]`, `[GEAR]`, `[EDIT]`), and bottom squarish action buttons (`ENG`, `FAN`, `RCKT`, `BOOST`).<br>• **Zero Extra BRAM**: Strictly 48 / 50 tiles (96.00%), preserving all budget for level map art.<br>• **Clean 2-cave levels architecture**: Level 0: Cave Arch 2x, Level 1: Cave Flight with smoothed terrain and camera tracking. |

### How Teammates Can Test on the Hardware:
1. Connect your **Basys3 board** via USB and power it on.
2. Connect your **OLED display(s)**:
   - Left OLED to **Pmod JA** (pin 1 facing up).
   - Right OLED to **Pmod JB** (optional for dual-OLED mode; SW15 up enables single-OLED mode on JA).
3. Connect your **PS/2 Mouse** to the USB-HID port via adapter.
4. Connect the **Pmod AMP2 speaker** to **JXADC** (pins 1–6).
5. Open **Vivado > Hardware Manager > Open Target > Program Device**.
6. Select **`bitstreams/2026-10-31/155832_My_Top_Module.bit`** and click **Program**.

---

## 📅 Chronological Bitstream History

| Build Date & Time (SGT) | File Link | Source Commit | Description & Milestone |
| :--- | :--- | :--- | :--- |
| **2026-10-31 16:56:01** | [2026-10-31/165601_My_Top_Module.bit](2026-10-31/165601_My_Top_Module.bit) | 98ca1e1 | **LATEST ACTIVE BUILD**: Option B Bad Piggies title screen ('LAGGY PIGGIES' bubble font, Play & Gear buttons), Right OLED live world view, 20s negative countdown timer on 7-seg only, big 16x16 interactive grid with part toggles, SW0 engine status box, 3 centered icon boxes in Settings with mouse speed scaling, wide sound layout with SW1 mute banner, transposed static-free BGM with boosted gain, and LEDs tied to switches. WNS +0.142 ns, 90.89% LUTs, 48 BRAMs (96%). |
| **2026-10-31 15:58:32** | [2026-10-31/155832_My_Top_Module.bit](2026-10-31/155832_My_Top_Module.bit) | `98ca1e1` | **LATEST ACTIVE BUILD**: Bulletproof dividers, animated moving cave Start Screen, blanked Right OLED during Title, centered run damage diagram, squarish action buttons. WNS +0.253 ns, 79.87% LUTs, 48 BRAMs. |
| **2026-10-30 12:41:52** | [2026-10-30/124152_My_Top_Module.bit](2026-10-30/124152_My_Top_Module.bit) | `64c496f` | Smoothed Cave Arch terrain, display_y camera smoothing, tilt hold, steep-slope tip guard, 2 cave levels. WNS +0.154 ns, 82.00% LUTs. |
| **2026-10-30 01:25:41** | [2026-10-30/012541_two_cave_levels_stripped_rects.bit](2026-10-30/012541_two_cave_levels_stripped_rects.bit) | `99bd13c` | **2-Cave Levels Milestone**: Stripped placeholder maps & rectangle collision engine. Cave Arch 2x scale & Cave Flight. |
| **2026-10-29 22:14:20** | [2026-10-29/221420_cave-arch-loop-physics.bit](2026-10-29/221420_cave-arch-loop-physics.bit) | `cdac53e` | **Role 4 Test Build (Marcus)**: Cave Arch drivable end to end at 2x, 360-degree rotation, dual-sided wheel support, edge tipping. |
| **2026-10-29 15:10:47** | [2026-10-29/151047_My_Top_Module.bit](2026-10-29/151047_My_Top_Module.bit) | `4f1912b` | **Rotation Geometry (Kyle)**: 32-angle tables, separating-axis occupancy collision, and synthesized collision ROM repair. |
| **2026-10-29 14:21:48** | [2026-10-29/142148_My_Top_Module.bit](2026-10-29/142148_My_Top_Module.bit) | `b7c525f` | **Rotation Latency Test**: Natural 45-degree settling and coherent display transfer test. |
| **2026-10-28 15:36:41** | [2026-10-28/153641_My_Top_Module.bit](2026-10-28/153641_My_Top_Module.bit) | `aa0efb1` | **Slope Physics**: Downhill gravity, uphill climbing resistance, and terrain ROM query integration. |
| **2026-10-27 14:13:37** | [2026-10-27/141337_My_Top_Module.bit](2026-10-27/141337_My_Top_Module.bit) | `ce62986` | **Map BRAM Cascade Fix**: BRAM cascade fixes, builder validation updates, coordinate expansion. |
| **2026-10-26 23:54:39** | [2026-10-26/235439_My_Top_Module.bit](2026-10-26/235439_My_Top_Module.bit) | `e013816` | **Directional Construction**: In-cell engine/rocket flipping, facing validation, mouse grid optimizations. |
| **2026-10-26 16:37:45** | [2026-10-26/163745_My_Top_Module.bit](2026-10-26/163745_My_Top_Module.bit) | `bab2d96` | **UI & Run Controls**: Left OLED DRIVE / POP / SOUND tabs and map camera navigation. |
| **2026-10-25 18:01:42** | [2026-10-25/180142_map-view-12px.bit](2026-10-25/180142_map-view-12px.bit) | `b79d73a` | **Map View 12px**: 1.5x map view with 12x12 sprites, SW3/wheel zoom, SW4 free look. |
| **2026-10-25 17:30:35** | [2026-10-25/173035_cave-arch-camera.bit](2026-10-25/173035_cave-arch-camera.bit) | `3f58d16` | **Camera Following**: 16x16 sprites, Cave Arch preview, following camera. |
| **2026-10-25 00:00:34** | [2026-10-25/000034_all-role-merge.bit](2026-10-25/000034_all-role-merge.bit) | `0e960d4` | **All-Role Merge**: Initial 4-role merge with TNT damage, collision, and audio. |
| **2026-10-24 22:59:54** | [2026-10-24/225954_engine-boost-audio.bit](2026-10-24/225954_engine-boost-audio.bit) | `9fd5776` | **Engine Boost & Audio**: Multi-note audio events and engine boost controls. |
| **2026-10-24 20:08:20** | [2026-10-24/200820_vivado-build.bit](2026-10-24/200820_vivado-build.bit) | Baseline | Earlier Vivado baseline build before audio events. |
| **2026-10-21 19:11:39** | [2026-10-21/191139_balloon-test.bit](2026-10-21/191139_balloon-test.bit) | Baseline | Interactive balloon popping test build. |
