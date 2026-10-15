# Team module setup

Owner: Shared - all roles. See [file owners](file_owners.md) for individual responsibilities.

Each person implements and tests their own modules against shared ports. The top module connects those ports; it should not accumulate everyone's game logic. Keep one owner for each state register so that movement, damage and retry cannot disagree.

## Keep the code at the course level

Use the Lab 1, Lab 2, Lab 4 and project manuals as the teaching baseline, together with the team's existing code. Prefer `reg`, `wire`, `assign`, `always`, counters, `if/else`, `case`, loops, arrays, signed arithmetic and straightforward module connections. Parameters are familiar. A short `localparam` declaration is acceptable when it simply gives a constant a clear name; explain any unfamiliar addition beside its use.

Avoid elaborate abstractions or automatic sizing when a fixed, clearly labelled counter is sufficient. Keep necessary timing/handshake logic in small modules with an explanation of each step. Reuse the user's `custom_clk_divider`, `square` and `seven_seg_oled` helpers. Preserve the supplied OLED and mouse drivers.

Reuse the user's `button_debouncer` three-state logic for button press pulses. Its optional stable-release check is included, with reset and timing parameters for the shared 100 MHz clock; the unused hold timer is omitted.

Do not explicitly instantiate FPGA clock-buffer primitives or add vendor placement attributes in the custom modules. Use the supplied divider and ordinary Verilog registers; preserve the synchroniser stages and review timing/clock routing during implementation.

Keep the OLED divider in Verilog. The user has requested removing the separate generated-clock constraint; do not reintroduce it without agreement. Divided-clock timing analysis remains pending.

The user has approved committing the reviewed starter files together, including ownership labels. For future changes, follow the user's current approval instructions. Use descriptive branch names such as `starter-module-wiring` or `role1-builder`.

Keep all game design files together in the existing `GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/` folder. Each person owns particular module files; separate role folders are unnecessary.

## Divide implementation work

| Role | Suggested modules | Owns the state |
| --- | --- | --- |
| 1 | `input_controller`, `mouse_adapter`, `vehicle_builder`, `vehicle_status`, `sound_event_router`, `sound_generator`, `audio_output` | Original build, inventory, intact mask, engine control state, audio playback |
| 2 | `physics_engine`, `movement_parameters` | Committed position, velocity and any agreed boost budget |
| 3 | `collision_engine`, `tnt_controller`, `world_outcomes` | TNT triggered flags and pending interaction results |
| 4 | `game_controller`, `level_data`, `left_renderer`, `right_renderer`, `display_snapshot`, `sprite_rom` | Game stage, active level and coherent drawing snapshots |

The real starter modules are now in the design source folder and connected in `My_Top_Module.v`. The four examples in `templates/` retain core port references; do not compile a duplicate copy alongside the real module. Members can split their internal logic further while preserving the external contract. Inventory display ports, mouse layout, audio ports and TNT/level geometry beyond terrain still need agreement before integration.

## Agree the draft interfaces

Review `docs/interfaces.md` together. Adopt the shared values in `game_defs.vh` in the design source folder, or change them before implementing the templates. In particular, decide inventory limits, part weights, balloon placement/footprint, error IDs and the mouse layout. The 3 by 3 grid supersedes the earlier six-cell plan.

## Add a module

1. Extend the existing module you own in `GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/`, or add a new uniquely named module there.
2. Preserve the agreed outputs, reset behaviour and handshakes. Coordinate port changes with their consumers.
3. Add a clearly named testbench under `sim/`, such as `vehicle_builder_tb.v`. Feed sample neighbouring inputs from the testbench, without creating a second hardware implementation of another member's module.
4. Register new source files using `scripts/add_team_sources.tcl`. It references the repository files in place; do not use a separate copied version of the same source in Vivado.
5. Run the relevant simulation and ask the receiving teammate to check names, widths and timing before integrating.

Add testbenches through Vivado's Add Simulation Sources. This keeps them out of synthesis. The default saved simulation top is `game_baseline_tb`; select `module_contracts_tb`, `display_snapshot_tb`, `physics_engine_tb`, `clock_control_tb` or `button_debouncer_tb` to run a different bench. The source-registration script does not select a testbench.

## Work in separate branches

Use branches such as `role1-builder`, `role2-movement`, `role3-collision` and `role4-rendering`. Each member starts from an updated `main`, commits their own files and opens a pull request with the behaviour and test result. The teammate consuming the outputs reviews interface changes.

One coordinator at a time updates `My_Top_Module.v`, the constraints and the `.xpr`; rotate that work. Register files after pulling changes, and avoid unrelated project-setting changes. Do not share a live cloud-synchronised Vivado workspace. Everyone uses their own local clone.

## Integrate in small steps

1. Show different colours on the two OLEDs, mouse-click LEDs and a short audio beep using explicit experiment wrappers.
2. Connect a fixed build, simple movement, flat-ground collision and build/run/result/retry control.
3. Replace the fixed build with real editing, inventory and validation. This is the first Week 10 integration target.
4. Add balloon lift and engine controls, then TNT and damage acknowledgement. Verify retry restores the build, movement state and TNT.
5. Connect sound events, instructions and detailed left-screen status, then finish the second map.

Keep experiment wrappers and test-only stubs out of the final source hierarchy. Record what is working at each checkpoint; shared completion means the real modules work together in one tested hardware build.
