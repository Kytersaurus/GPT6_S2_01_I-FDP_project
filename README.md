# Laggy Piggies FPGA project

Owner: Shared - all roles. [File-by-file owners](docs/file_owners.md) are listed separately and labelled in the custom source files.

Build one shared Basys3 game by giving each member ownership of separate modules and agreeing the signals between them. The hardware top now connects a starter game loop: a fixed nine-cell build, engine movement, gravity, flat-ground collision, a goal, retry and two basic OLED views. It is a baseline for team development, not the full proposal implementation.

## Try the starter

Open `GPT_6_S2_01_I-FDP_project.xpr` in Vivado. Sources, pin constraints and the default `game_baseline_tb` simulation top are registered. The left OLED uses JA and shows a 48 by 48 pixel build grid, validity/engine status bars and the surviving-part count. The right OLED uses JB and shows the vehicle at eight pixels per cell, ground and green goal area. Verify the physical connector arrangement before attaching displays with board power off.

| Control | Behaviour |
| --- | --- |
| SW0 | Enable the engine; turn on before launching to reach the goal |
| BTNC | Launch from BUILD; retry from SUCCESS/FAIL |
| BTNU | Return to BUILD after a result |
| BTND | Reset the system |
| LED 2 through 0 | Game state: BUILD=0, INIT_RUN=1, RUN=2, SUCCESS=3, FAIL=4 |
| LED 3 | World result pending |
| LED 4 through 6 | Pig alive, build valid, engine enabled |
| LED 15 through 7 | Intact mask for cells 8 through 0 |

The fixed build is empty/empty/empty on the top row, frame/pig/engine in the middle, and wheel/frame/wheel on the bottom. A green right-screen border indicates success; red indicates failure.

BTNC and BTNU use the user's `button_debouncer` approach: one immediate press pulse, a 200 ms lockout, then a required 20 ms stable release. Its timing counts use the shared 100 MHz clock. Reset clears the debouncer as well as the game.

Editing, inventory accounting, mouse controls, TNT, walls/ceilings, audio, instructions and the two final maps remain to be implemented. The builder's edit inputs are intentionally inactive. Its damage interface is implemented and tested separately, but tied inactive in the hardware top until TNT is connected. Balloon lift is a provisional movement calculation; the fixed build has no balloons and no balloon-popping control yet.

## Start together

1. Read [file owners](docs/file_owners.md), [the current connections](docs/connections.md), [team setup](docs/team_setup.md) and [draft interfaces](docs/interfaces.md). Agree the remaining decisions before extending the modules.
2. Everyone develops their owned modules in the existing `GPT_6_S2_01_I-FDP_project.srcs/sources_1/new/` folder, alongside `My_Top_Module.v`. Preserve the supplied OLED and mouse drivers.
3. Open `GPT_6_S2_01_I-FDP_project.xpr` in Vivado. From the repository root, run `source scripts/add_team_sources.tcl` in the Vivado Tcl Console whenever new design source files are added.
4. Work on separate branches and merge small changes with a clear test result. One coordinator edits the hardware top, pin constraints and project registration at a time.

## Source ownership

All game modules share the existing design source folder. Ownership is by module, without separate role folders.

| Modules | Owner | Work |
| --- | --- | --- |
| `game_defs.vh` | Shared | Constants agreed by producers and consumers |
| Builder, input, status and audio modules | Kaushal | Input, construction, inventory, damage state and audio |
| Physics and movement parameter modules | Kyle | Movement, balloon lift, engine behaviour and numerical tuning |
| Collision, TNT and outcome modules | Yap Ting | Collision, TNT damage calculations and world outcomes |
| Renderers, game controller and level data | Marcus | Both OLED views, instructions, game control and level data |

Keep testbenches in `sim/` and interface examples in `templates/`; neither folder is added to the hardware build by the registration script.

The existing `.srcs` folder retains the supplied drivers, hardware top and constraints. Do not move those files independently of the Vivado project.

## First shared milestone

Launch a fixed valid vehicle, move it on flat ground, show a result and retry. Then replace the fixed build with the editor and add balloons, TNT, controls and audio in small steps. Test both OLEDs, mouse clicks and an amplifier beep independently early.

## Tool checks

Run `scripts/run_simulations.ps1` in PowerShell to compile and run the six regression benches. Pass `-VivadoBin` if Vivado is installed elsewhere, or `-Benches` to choose specific benches. The benches check the connected lifecycle, button bounce and release, held input, collision backpressure, damage/restoration, invalid launch, result priority, representative pixels, display snapshot transfer, signed balloon lift, movement handshakes and clock/reset behaviour.

From the repository root in PowerShell, run `vivado -mode batch -source (Join-Path (Get-Location).Path 'scripts/check_baseline.tcl')` to synthesise the baseline without changing the saved project. Passing the absolute script path avoids depending on Vivado's working directory. Reports go into `tmp/baseline_synthesis/`. Synthesis checks do not establish routed timing or board behaviour; test the generated design on the actual hardware before claiming features in the report.

The simulation benches passed on 15 October 2026. The synthesis attempt stopped before reading the design because the local Vivado Tcl Store could not load `::tclapp::support::appinit 1.2`; synthesis and hardware checks remain pending.

`templates/` retains interface-only references. Develop the real `.v` modules already in the design source folder rather than copying a duplicate module into the project.

## Contribution records

Keep references and contribution records for the final report. `custom_clk_divider.v`, `square.v` and `seven_seg_oled.v` preserve the user's supplied logic and are connected to the starter. Each owner must review, understand, extend and test their contribution; supplied drivers retain their original attribution.

`button_debouncer.v` adapts the user's supplied three-state debouncer and optional release check. The integration adds reset handling and makes the release interval a parameter for the 100 MHz clock and short simulations. The optional hold timer is omitted because these controls need only press pulses.
