# File owners — Lab Group S2-01 (GPT 6)

Owner: Shared - all four members keep this list current:
- **Student A (Role 1):** Kaushal Rajesh (`A0315560L`)
- **Student B (Role 2):** Kyle Lee Yao Yu (`A0322756B`)
- **Student C (Role 3):** Lam Yap Ting (`A0320434U`)
- **Student D (Role 4):** Marcus Lim (`A0271977L`)

These labels identify who maintains and extends each file. They do not claim that the starter code was independently written by that member. The contribution record in `README.md` identifies the supplied code. Agree changes to shared ports with the members consuming them.

---

## Design Sources

All design files below are located in `GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/`.

| Design file | Owner | Purpose |
| :--- | :--- | :--- |
| `vehicle_builder.v` | Role 1 - Kaushal (`A0315560L`) | Frame/content editing, attachment/stock validation, timed edit feedback, inventory, runtime masks, counts, mass, and wheel side detection (`wheels_down`/`wheels_up`) |
| `mouse_adapter.v` | Role 1 - Kaushal (`A0315560L`) | Driver coordinate setup, cursor tracking, inventory selection, click/drag-and-drop placement, right-click removal, in-cell part flipping, and RUN cell click requests |
| `balloon_control.v` | Role 1 - Kaushal (`A0315560L`) | Queue valid balloon clicks and apply content damage between movement/world updates |
| `input_controller.v` | Role 1 - Kaushal (`A0315560L`) | Launch/edit/right button actions, reverse switch (`SW15`), and audio mute (`SW0`); `BTNL` is reserved |
| `ui_controller.v` | Role 1 - Kaushal (`A0315560L`) | Diary/guide navigation, left-OLED action buttons, cell-click runtime part controls, boost controls, and level selection requests |
| `ui_renderer.v` | Role 1 - Kaushal; shared with Role 4 | Left-screen layout for Title, Level Select, Build, Run, Settings/`[ ? ]` guide, diary pages, inventory boxes, and feedback overlays |
| `ui_font.vh` | Shared - Role 1 and Role 4 | Built-in 5x7 bitmap font definitions for on-screen text and feedback messages |
| `seven_seg_timer.v` | Role 1 - Kaushal (`A0315560L`) | Basys3 active-low 4-digit 7-segment display driver formatting countdown/overtime run time (`M.SS` / `SS` / `-SS`) |
| `pig_death_effect.v` | Role 1 - Kaushal; drawn by Role 4 | Two-phase cartoon death puff effect triggered upon pig mortality |
| `sound_controller.v` | Role 1 - Kaushal (`A0315560L`) | Event priorities (launch, pop, landing, explosion, win, fail), edge detection, duplicate suppression, and preemption |
| `bgm_player.v` | Role 1 - Kaushal (`A0315560L`) | Multi-voice BGM synthesizer (*The Entertainer* in BUILD, *Bad Piggies Theme* in RUN, *Start Screen Fanfare* on Title), quiet sample scaling, and SFX pause/resume |
| `sound_generator.v` | Role 1 - Kaushal (`A0315560L`) | Seven tone profiles, note sequencing, volume fades, frame-aligned PWM carrier generation, volume scaling, and hardware mute |
| `button_debouncer.v` | Role 1 - Kaushal (`A0315560L`) | User's debouncer adapted with reset, stable release interval, and 100 MHz timing |
| `custom_clk_divider.v` | Role 1 - Kaushal; shared helper | User's divider for the 6.25 MHz OLED SPI clock |
| `clock_control.v` | Shared; Role 1 maintains starter | Clock routing, 60 Hz physics tick enable, and debounced reset distribution |
| `square.v` | Role 1 - Kaushal; used by Role 4 | User's rectangle drawing helper |
| `seven_seg_oled.v` | Role 1 - Kaushal; used by Role 4 | User's on-screen 7-segment digit drawing helper |
| `physics_engine.v` | Role 2 - Kyle (`A0322756B`) | Staged force/mass movement, friction, reverse, balloon/fan lift, rocket thrust, slope/support dynamics, damping and COM moments (appended `vehicle_moments` helper), and sub-pixel camera smoothing |
| `signed_divider16.v` | Role 2 - Kyle (`A0322756B`) | 16-clock sequential signed 16-bit force divided by unsigned 8-bit mass |
| `rotation_geometry.vh` | Shared - Roles 2, 3, and 4 | 32-angle (-16..15) trigonometric quarter-turn tables, vector rotation, and separating-axis extent functions |
| `collision_engine.v` | Role 3 - Yap Ting (`A0320434U`) | Top-level collision selector; delegates live cave levels to `rotating_map_collision_engine` and reports hard-contact impact directions |
| `rotating_map_collision_engine.v` | Role 3 - Yap Ting; Role 2/3 integration | Swept occupied-cell 360-degree rotated collision against terrain BRAM ROM, 45-degree slope probes, step-up/snapping, and edge tip direction reporting |
| `tnt_controller.v` | Role 3 - Yap Ting; shared integration with Role 1 | Swept TNT contact detection, queued explosions, non-pig frame/content blast masks, and explosion sound triggers |
| `world_outcomes.v` | Role 3 - Yap Ting (`A0320434U`) | Rotated pig-centre goal entry, out-of-bounds hull checks, hazard collisions, and prioritized fail reason encoding |
| `game_controller.v` | Role 4 - Marcus (`A0271977L`) | BUILD, INIT_RUN, RUN, SUCCESS, FAIL, GUIDE, LEVEL_SELECT state machine and update sequencing |
| `level_data.v` | Role 4 - Marcus (`A0271977L`) | Cave Arch (`25 s` par), Cave Flight (`45 s` par), and interactive Tutorial (`30 s` par): spawn coordinates, world dimensions, flag goals, star boxes, TNT locations, and map ROM IDs |
| `level_map.v` | Role 4 - Marcus (`A0271977L`) | Dual-port Block-RAM terrain ROM: draw port for OLED renderer and query port for collision engine |
| `cave_arch_map.mem`, `cave_arch_solid.mem` | Role 4 - Marcus; Role 3 solidity | 956x582 Cave Arch colour palette indices and synthesized 1-bit collision solidity memory (smoothed terrain) |
| `cave_flight_map.mem`, `cave_flight_solid.mem`, `cave_flight_colour_*.mem` | Role 4 - Marcus; Role 3 solidity | 890x213 Cave Flight colour palette indices, split colour banks, and synthesized 1-bit collision solidity memory |
| `zoom_control.v` | Role 4 - Marcus (`A0271977L`) | Map camera zoom decoding (`1.5x` close, `1.0x` normal, `0.5x` overview) from `SW14` and mouse wheel |
| `level_button.v` | Role 4 - Marcus (`A0271977L`) | Left-OLED level button click detection, reading shared mouse coordinates |
| `explosion_fx.v` | Role 4 - Marcus (`A0271977L`) | Three-phase TNT blast animation (flash, fireball, smoke) when a TNT intact bit falls |
| `part_sprites.vh` | Role 4 - Marcus (`A0271977L`) | Shared 8x8 (1x zoom), 12x12 (1.5x zoom), and 16x16 (editor) part, TNT, rocket, and fan sprites with per-part palettes |
| `left_renderer.v` | Role 4 - Marcus (`A0271977L`) | Left OLED grid, inventory/counts, cursor, moving preview, feedback text/outlines, tutorial prompts, and runtime menu rendering |
| `right_renderer.v` | Role 4 - Marcus (`A0271977L`) | Right OLED world/vehicle rendering with camera following (`display_x`/`display_y`), full-turn rotation, zoom scales, and `SW13` free look |
| `display_snapshot.v` | Role 4 - Marcus (`A0271977L`) | Coherent 319-bit snapshot transfer bridging 100 MHz logic and 6.25 MHz OLED clock domains |
| `game_defs.vh` | Shared - all roles | Global constants: part IDs, state IDs, coordinate bits (Q12.8), tilt bits, and audio profiles |
| `My_Top_Module.v` | Shared; Role 4 - Marcus coordinates | Top-level pin wiring, clock division, and module interconnects |
| `Oled_Display.v` | Supplied driver; Role 4 integrates | Digilent RGB OLED SPI controller (preserved with original attribution) |
| `Mouse_Control.vhd` | Supplied driver; Role 1 integrates | Digilent PS/2 Mouse Controller in VHDL (preserved with original attribution) |
| `Ps2Interface.vhd` | Supplied driver; Role 1 integrates | Digilent PS/2 lower-level interface in VHDL (preserved with original attribution) |

---

## Simulation Testbenches

All 55 simulation benches are located in `sim/` and pass through `scripts/run_simulations.ps1`.

### Role 1 - Kaushal (Builder, Input, UI & Audio)
| Testbench file | Purpose |
| :--- | :--- |
| `sim/balloon_controls_tb.v` | Connected top-level balloon clicks, queue timing, mass/count reduction, RUN pixels, retry, and reset |
| `sim/bgm_player_tb.v` | Background music melody sequencing, shared PWM output, SFX preemption/resume, and mute/reset |
| `sim/boost_controls_tb.v` | On-screen engine boost button, mouse click detection, and timed thrust application |
| `sim/button_debouncer_tb.v` | Button bounce, holding, lockout timing, release verification, and reset checks |
| `sim/clock_control_tb.v` | Clock divider, 60 Hz physics tick enable, and reset distribution checks |
| `sim/construction_controls_tb.v` | Mouse packet processing through editing, inventory limits, drag-and-drop, and OLED feedback |
| `sim/construction_feedback_tb.v` | Edit outcomes (PLACED, REMOVED, errors), exact 1-second feedback duration, cell outlines, and text messages |
| `sim/directional_parts_tb.v` | Direction balance (`engine_balance`), damage/retry facing preservation, and side attachment geometry |
| `sim/game_audio_tb.v` | Sound effect priorities, preemption, duplicate suppression, real game events, and mute/reset |
| `sim/gameplay_menu_tb.v` | Full construction integration, directional parts, in-run menu tabs (DRIVE/POP/SOUND), and volume controls |
| `sim/grid_moves_tb.v` | Existing-part moves, bundle moves, rejected/cancelled drops, and inventory returns with refunds |
| `sim/level_selector_tb.v` | Level selection menu with real top-level mouse, tile click selection, and state wiring |
| `sim/sound_generator_tb.v` | Seven sound profiles, note frequencies, volume fades, carrier frame integrity, and cancellation |
| `sim/timer_death_tb.v` | 7-segment display digit scanning (M.SS) and cartoon pig death puff effect |
| `sim/ui_air_controls_tb.v` | Prepared fan and rocket controls, UI readiness gating, and top-level wire contracts |
| `sim/ui_controls_tb.v` | Real mouse diary navigation, engine buttons, and volume click targets |
| `sim/ui_visual_tb.v` | Visual OLED pixel exports for DRIVE, POP, and SOUND screens across zoom scales |
| `sim/vehicle_builder_tb.v` | Frame/content layers, attachment rules, independent layer damage, counts, and edited-build restoration |
| `sim/volume_audio_tb.v` | Real sound-page volume clicks and shared audio gain attenuation |

### Role 2 - Kyle (Physics & Movement)
| Testbench file | Purpose |
| :--- | :--- |
| `sim/map_slope_tb.v` | Terrain-gradient slope calculation, slope force translation, and movement handshake integration |
| `sim/physics_engine_tb.v` | Core movement arithmetic, sequential calculation sequencing, and handshake checks |
| `sim/physics_friction_tb.v` | Force-based wheel friction, fractional remainder carry, coast-to-stop, reverse, and clamping |
| `sim/physics_jump_tb.v` | Retired jump input stays inert at spawn, on ground, in air, during repeated/late presses, and after retry |
| `sim/physics_slope_tb.v` | Slope-force arithmetic, downhill acceleration, uphill braking, and accepted-contact checks |
| `sim/signed_divider16_tb.v` | 16-clock signed divider latency, extreme/random operands, zero mass handling, and cancellation |

### Role 3 - Yap Ting (Collision, TNT & World Outcomes)
| Testbench file | Purpose |
| :--- | :--- |
| `sim/collision_engine_tb.v` | Collision proposal capture, platform/slope response, signed coordinate boundaries, and backpressure |
| `sim/collision_impact_tb.v` | Hard landing, left/right wall, ceiling, corner and impact-threshold checks |
| `sim/map_collision_tb.v` | Synthetic registered-ROM fixtures isolating terrain geometry and read latency |
| `sim/map_rom_collision_tb.v` | Real map ROM query verification against independent ROM models with independent draw/query |
| `sim/occupied_map_collision_tb.v` | Occupied-cell terrain collision verifying empty cells do not snag against nearby terrain/roofs |
| `sim/tnt_controller_tb.v` | Standalone swept TNT trigger detection and frame/content damage mask generation |
| `sim/world_outcomes_tb.v` | Rotated pig-centre goal detection, out-of-bounds hull checking, and prioritized failure reason codes |

### Role 4 - Marcus (Rendering, Levels, Camera & Maps)
| Testbench file | Purpose |
| :--- | :--- |
| `sim/cave_arch_drive_tb.v` | Autonomous traversal of Cave Arch 2x from spawn to finish flag through real physics and collision |
| `sim/display_snapshot_tb.v` | Coherent display snapshot transfer across clock domains and frame-boundary publication |
| `sim/flip_physics_tb.v` | 32-angle rotation tables, upside-down driving on top wheels, wheel-less scraping, and edge tipping |
| `sim/level_map_tb.v` | Dual-port ROM verification for Cave Arch and Cave Flight against original map binary assets |
| `sim/role4_game_display_tb.v` | Level data, level selector transitions, fail reasons, timer, explosions, and renderer pixels |
| `sim/role4_level_solutions_tb.v` | Recorded solutions: prepared test vehicles clearing levels through the full hardware top |
| `sim/zoom_controls_tb.v` | Map camera zoom decoding from `SW14` switch and mouse wheel deltas |

### Shared Integration Tests (All Roles)
| Testbench file | Purpose |
| :--- | :--- |
| `sim/cave_coordinates_tb.v` | Wide signed Q12.8 spawns, physics clamping, collision, and world outcomes on large cave maps |
| `sim/cave_map_integration_tb.v` | Connected top-level checks: real cave spawn, TNT/world sequencing, and display transfer |
| `sim/game_baseline_tb.v` | Connected game loop lifecycle (BUILD, RUN, SUCCESS, FAIL, RETRY, EDIT, RESET) |
| `sim/map_solidity_tb.v` | Exhaustive check of all 328,668 map pixels verifying synthesized BRAM solidity matches color assets |
| `sim/module_contracts_tb.v` | Multi-role interface contracts between builder, collision, controller, and renderers |
| `sim/rotating_collision_tb.v` | Independent 4-axis separating-axis occupied-cell rotation geometry and collision handshakes |
| `sim/rotation_interactions_tb.v` | Committed vehicle orientation agreement across goals, hazards, TNT, and death effects |
| `sim/rotation_map_integration_tb.v` | Connected slope forces, tilt settling, lift/airborne attitude, and Flight balloon ascent in real maps |
| `sim/single_oled_tb.v` | `SW1` frame-boundary JA view switching, 180-degree rotation, hidden input protection, and music |
| `sim/slope_map_integration_tb.v` | Real terrain slope forces, downhill rolling, uphill climbing, and balloon detachment |
| `sim/team_controls_tb.v` | Coexistence of physical switches/buttons and retired BTNL jump suppression after full role merge |
| `sim/tnt_integration_tb.v` | Role 1 damage/audio with Role 3 TNT damage and Role 4 outcome sequencing |
| `sim/vehicle_rotation_renderer_tb.v` | Rotated vehicle rasterization, inverse mapping, zoom scaling, facing, and damage masks |
| `sim/vehicle_rotation_top_tb.v` | Connected top-level natural map tilt settling and frame-coherent pose/angle publication |

---

## Project Configuration & Documentation

| File | Owner | Purpose |
| :--- | :--- | :--- |
| `GPT_6_S2_01_I-FDP_project.xpr` | Shared; Role 4 coordinates | Vivado project configuration, file sets, and run configurations |
| `GPT_6_S2_01_I-FDP_project.srcs/constrs_1/new/Basys3_Master.xdc` | Shared; Role 4 coordinates | Pin constraints for Basys3 (OLED JA/JB, mouse PS/2, switches, buttons, LEDs, 7-seg, AMP2 JXADC) |
| `.gitignore` | Shared - all roles | Excludes temporary Vivado artifacts while whitelisting archived `.bit` files |
| `README.md` | Shared - all roles | Project overview, control mappings, architecture summary, and contribution history |
| `docs/file_owners.md` | Shared - all roles | File-by-file ownership registry and module responsibilities (this document) |
| `docs/team_setup.md` | Shared - all roles | Team collaboration guidelines, branch workflows, and coding conventions |
| `docs/interfaces.md` | Shared - all roles | Detailed hardware interface contracts, signal definitions, and handshake timing protocols |
| `docs/connections.md` | Shared; Role 4 coordinates | Module port-level interconnect wiring reference |
| `docs/audio_setup.md` | Role 1 - Kaushal | Pmod AMP2 pin mapping, audio profiles, volume tables, and listening test procedures |
| `docs/gameplay_menu.md` | Role 1 - Kaushal | Specification for directional construction, in-run menus, and diary pages |
| `docs/map_interface_proposal.md` | Role 4 - Marcus | Original proposal and architectural design for Cave Arch and Cave Flight |
| `scripts/add_team_sources.tcl` | Shared; Role 4 coordinates | Vivado Tcl script to register all design files into the `.xpr` project |
| `scripts/rebuild_bitstream.tcl` | Shared integration | Batch Vivado rebuild script ensuring clean synthesis, implementation, and bitstream generation |
| `scripts/run_simulations.ps1` | Shared - all roles | Automated regression runner executing all 55 simulation testbenches |
| `scripts/check_map_solidity.ps1` | Role 3 / 4 | Exhaustive verification script testing synthesized Block-RAM solidity against all map pixels |
| `scripts/archive_bitstream.tcl` | Shared integration | Hook archiving completed bitstreams into `bitstreams/` with timestamp and metadata |
| `bitstreams/README.md` | Shared integration | Bitstream catalog, hardware setup instructions, and chronological milestone history |
| `bitstreams/builds.json` | Shared integration | Machine-readable metadata and SHA256 hashes for all archived bitstream builds |
| `bitstreams/LATEST.txt` | Shared integration | Single-line pointer file referencing the latest active verified bitstream |
