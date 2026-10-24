# Basys3 bitstream archive

Latest published integrated build: **[2026-10-25/000034_all-role-merge.bit](2026-10-25/000034_all-role-merge.bit)**, built from source commit `0e960d4`. All four roles are merged; TNT damage, collision fixes, audio and retry are integrated. All 26 simulations passed and the constrained 100 MHz timing checks passed before generation.

Open Vivado **Hardware Manager > Program Device > Browse** and select this file. `LATEST.txt` identifies the newest archived file. Times below are Singapore local time.

| Build time | File | Contents |
| --- | --- | --- |
| 2026-10-25 00:00:34 | [2026-10-25/000034_all-role-merge.bit](2026-10-25/000034_all-role-merge.bit) | Latest: all four roles merged, integrated TNT/collision/audio |
| 2026-10-24 22:59:54 | [2026-10-24/225954_engine-boost-audio.bit](2026-10-24/225954_engine-boost-audio.bit) | Engine boost and audio, before TNT integration |
| 2026-10-24 20:08:20 | [2026-10-24/200820_vivado-build.bit](2026-10-24/200820_vivado-build.bit) | Earlier Vivado output; source revision not recorded |
| 2026-10-21 19:11:39 | [2026-10-21/191139_balloon-test.bit](2026-10-21/191139_balloon-test.bit) | Earlier balloon/control test |
| 2026-10-19 19:29:05 | [2026-10-19/192905_oled-test.bit](2026-10-19/192905_oled-test.bit) | Earlier OLED construction test |

## Future Vivado builds

The project runs `scripts/archive_bitstream.tcl` after Write Bitstream. It copies each completed `.bit` into `bitstreams/YYYY-MM-DD/HHMMSS_My_Top_Module.bit` and updates `LATEST.txt`. The original Vivado output remains in its run directory. Reopen the saved project to load this setting. Archives are included by Git, but generating a build does not commit or upload it automatically.

Older files are retained as historical builds; their features differ from the current game.
