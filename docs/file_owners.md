# File owners

Owner: Shared - all four members keep this list current.

These labels identify who maintains and extends each file. They do not claim that the starter code was independently written by that member. The contribution record in `README.md` identifies the supplied code. Agree changes to shared ports with the members consuming them.

All design files below are in `GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/`.

| Design file | Owner | Purpose |
| --- | --- | --- |
| `vehicle_builder.v` | Role 1 - Kaushal | Frame/content editing, attachment/stock validation, remaining inventory, two runtime intact masks, counts and mass |
| `mouse_adapter.v` | Role 1 - Kaushal | Driver coordinate setup, cursor, inventory selection, click/drag-and-drop placement, right-click removal and RUN pop requests |
| `balloon_control.v` | Role 1 - Kaushal | Queue valid balloon clicks and apply content damage between movement/world updates |
| `input_controller.v` | Role 1 - Kaushal | Button actions and engine switch; mouse actions use the separate adapter |
| `button_debouncer.v` | Role 1 - Kaushal | User's debouncer adapted with reset and stable release |
| `custom_clk_divider.v` | Role 1 - Kaushal; shared helper | User's divider for the OLED clock |
| `clock_control.v` | Shared; Role 1 - Kaushal maintains starter | Clock connections, physics enable and reset |
| `square.v` | Role 1 - Kaushal; used by Role 4 | User's rectangle drawing helper |
| `seven_seg_oled.v` | Role 1 - Kaushal; used by Role 4 | User's digit drawing helper |
| `physics_engine.v` | Role 2 - Kyle | Movement, gravity, engine acceleration, balloon lift and drag |
| `collision_engine.v` | Role 3 - Yap Ting | Starter platform landing; walls, ceilings and TNT remain to be added |
| `world_outcomes.v` | Role 3 - Yap Ting | Goal and bounds checks; hazards/TNT remain to be added |
| `game_controller.v` | Role 4 - Marcus | Build/run/result/retry states and update sequencing |
| `level_data.v` | Role 4 - Marcus | One flat test map; final two levels remain to be added |
| `left_renderer.v` | Role 4 - Marcus | Left OLED grid, inventory icons/counts, selection, cursor and runtime status; 16-pixel editor cells |
| `right_renderer.v` | Role 4 - Marcus | Right OLED world/vehicle drawing; 8-pixel gameplay cells |
| `display_snapshot.v` | Role 4 - Marcus | Transfers consistent game state to the OLED clock and publishes at frame start |
| `game_defs.vh` | Shared - all roles | Agreed part IDs, state IDs and dimensions |
| `My_Top_Module.v` | Shared; Role 4 - Marcus coordinates | Connections between everyone's modules |
| `Oled_Display.v` | Supplied driver; Role 4 integrates | Preserve the original driver and attribution |
| `Mouse_Control.vhd` | Supplied driver; Role 1 integrates | Original driver and attribution preserved; instantiated for mouse input |
| `Ps2Interface.vhd` | Supplied driver; Role 1 integrates | Unchanged mouse-driver dependency |

Future audio and gameplay input additions belong to Role 1. Future movement tuning belongs to Role 2, TNT/collision additions to Role 3, and instructions, levels and detailed display content to Role 4. These future features are not included in this starter.

| Project/support file | Owner | Purpose |
| --- | --- | --- |
| `GPT_6_S2_01_I-FDP_project.xpr` | Shared; Role 4 coordinates | Vivado source and simulation registration |
| `GPT_6_S2_01_I-FDP_project.srcs/constrs_1/new/Basys3_Master.xdc` | Shared; Role 4 coordinates | Board pins and clock constraints; coordinate future mouse/audio pins with Role 1 |
| `.gitignore` | Shared - all roles | Excludes generated outputs and scratch files |
| `README.md` | Shared - all roles | Current controls, limitations, setup and contribution record |
| `docs/file_owners.md` | Shared - all roles | This file-by-file ownership list |
| `docs/team_setup.md` | Shared - all roles | Collaboration workflow and coding preferences |
| `docs/interfaces.md` | Shared - all roles | Agreed/draft data formats, ports and handshakes |
| `docs/connections.md` | Shared; Role 4 coordinates | Actual starter wiring and pending connections |
| `scripts/add_team_sources.tcl` | Shared; Role 4 coordinates | Register design sources in Vivado |
| `scripts/check_baseline.tcl` | Shared - all roles | Synthesis and constraint checks |
| `scripts/run_simulations.ps1` | Shared - all roles | Runs the simulation benches |
| `sim/button_debouncer_tb.v` | Role 1 - Kaushal | Button bounce, holding, release and reset checks |
| `sim/vehicle_builder_tb.v` | Role 1 - Kaushal | Frame/content edits, attachments, independent damage, two-digit display count and edited-build restoration |
| `sim/construction_controls_tb.v` | Role 1 - Kaushal | Mouse configuration/clicks/drag-and-drop, stock/refund rules, inventory/cursor pixels, damage/retry and edit/launch arbitration |
| `sim/balloon_controls_tb.v` | Role 1 - Kaushal | Connected top-level balloon clicks, queue timing, mass/counts, no inventory refund, RUN pixels, retry/results/reset |
| `sim/clock_control_tb.v` | Shared; Role 1 maintains | Divider, physics-enable and reset checks |
| `sim/physics_engine_tb.v` | Role 2 - Kyle | Movement arithmetic and handshake checks |
| `sim/display_snapshot_tb.v` | Role 4 - Marcus | Snapshot transfer and frame-boundary checks |
| `sim/module_contracts_tb.v` | Shared - Roles 1, 3 and 4 | Builder, collision, controller and drawing checks |
| `sim/game_baseline_tb.v` | Shared - all roles | Connected starter game-loop checks |
| `templates/vehicle_builder.v.example` | Role 1 - Kaushal | Interface reference only; excluded from hardware build |
| `templates/physics_engine.v.example` | Role 2 - Kyle | Interface reference only; excluded from hardware build |
| `templates/collision_engine.v.example` | Role 3 - Yap Ting | Interface reference only; excluded from hardware build |
| `templates/game_controller.v.example` | Role 4 - Marcus | Interface reference only; excluded from hardware build |

Keep one coordinator at a time on the top module, project and constraints. Everyone extends their own existing modules, rather than compiling duplicate copies from `templates/`.
