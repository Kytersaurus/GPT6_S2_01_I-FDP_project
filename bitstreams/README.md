# Basys3 bitstream archive

Latest published integrated build: **[2026-10-30/124152_My_Top_Module.bit](2026-10-30/124152_My_Top_Module.bit)**, built from source commit `64c496f`. Features 2-cave levels with smoothed Cave Arch terrain, alpha-beta camera smoothing (`display_y`), 3-update tilt hold stabilization, steep-slope tip guard, and pruned rectangle collisions. All simulations passed; 100 MHz timing met with +0.154 ns WNS and 82.00% LUTs.

Open Vivado **Hardware Manager > Program Device > Browse** and select this file. `LATEST.txt` identifies the newest archived file. Times below are Singapore local time.

| Build time | File | Contents |
| --- | --- | --- |
| 2026-10-30 12:41:52 | [2026-10-30/124152_My_Top_Module.bit](2026-10-30/124152_My_Top_Module.bit) | Official integrated build (commit `64c496f`): Smoothed Cave Arch terrain, display_y camera smoothing, tilt hold, steep-slope tip guard, 2 cave levels. Timing cleanly met: WNS +0.154 ns, 82.00% LUTs. |
| 2026-10-30 01:25:41 | [2026-10-30/012541_two_cave_levels_stripped_rects.bit](2026-10-30/012541_two_cave_levels_stripped_rects.bit) | Official 2-cave levels build (commit `e64b434`): Stripped placeholder maps & rectangle collisions, Cave Arch 2x scale & Cave Flight, 360° flip physics. 51 simulations passed; 0 hold violations. |
| 2026-10-29 22:14:20 | [2026-10-29/221420_cave-arch-loop-physics.bit](2026-10-29/221420_cave-arch-loop-physics.bit) | Role 4 test build (`role4`, commit `cdac53e`): Cave Arch drivable end to end at 2x, full-turn rotation, wheels on both sides, edge tipping, stronger engine. 51 simulations passed; 100 MHz timing misses by 0.021 ns on one rectangle-collision path |
| 2026-10-25 18:01:42 | [2026-10-25/180142_map-view-12px.bit](2026-10-25/180142_map-view-12px.bit) | Latest Role 4 test build (`role4`): 1.5x map view with 12x12 sprites, red/white/black TNT, Cave Arch level 3 (view only), SW3/wheel zoom, SW4 free look. 26 simulations and 100 MHz timing passed |
| 2026-10-25 17:30:35 | [2026-10-25/173035_cave-arch-camera.bit](2026-10-25/173035_cave-arch-camera.bit) | Role 4 test build (uncommitted changes on `role4`): 16x16 sprites, Cave Arch level 3 (view only), following camera, SW3/wheel zoom, SW4 free look. 26 simulations and 100 MHz timing passed |
| 2026-10-25 00:00:34 | [2026-10-25/000034_all-role-merge.bit](2026-10-25/000034_all-role-merge.bit) | All four roles merged, integrated TNT/collision/audio |
| 2026-10-24 22:59:54 | [2026-10-24/225954_engine-boost-audio.bit](2026-10-24/225954_engine-boost-audio.bit) | Engine boost and audio, before TNT integration |
| 2026-10-24 20:08:20 | [2026-10-24/200820_vivado-build.bit](2026-10-24/200820_vivado-build.bit) | Earlier Vivado output; source revision not recorded |
| 2026-10-21 19:11:39 | [2026-10-21/191139_balloon-test.bit](2026-10-21/191139_balloon-test.bit) | Earlier balloon/control test |
| 2026-10-19 19:29:05 | [2026-10-19/192905_oled-test.bit](2026-10-19/192905_oled-test.bit) | Earlier OLED construction test |

## Future Vivado builds

The project runs `scripts/archive_bitstream.tcl` after Write Bitstream. It copies each completed `.bit` into `bitstreams/YYYY-MM-DD/HHMMSS_My_Top_Module.bit` and updates `LATEST.txt`. The original Vivado output remains in its run directory. Reopen the saved project to load this setting. Archives are included by Git, but generating a build does not commit or upload it automatically.

Older files are retained as historical builds; their features differ from the current game.
