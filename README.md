# Laggy Piggies FPGA project

Owner: Shared - all roles. [File-by-file owners](docs/file_owners.md) are listed separately and labelled in the custom source files.

Build one shared Basys3 game by giving each member ownership of separate modules and agreeing the signals between them. The hardware top connects mouse construction, limited inventory, engine movement, gravity, flat-ground collision, a goal, retry and two OLED views. It is a baseline for team development, not the full proposal implementation.

## Try the starter

Open `GPT_6_S2_01_I-FDP_project.xpr` in Vivado. Sources, pin constraints and the default `game_baseline_tb` simulation top are registered. The left OLED uses JA: during BUILD it shows a 48 by 48 pixel grid, five inventory rows, selection and cursor; during RUN it shows the build, status and surviving-part count. The right OLED uses JB and shows the vehicle at eight pixels per cell, ground and green goal area. Verify the physical connector arrangement before attaching displays with board power off.

One OLED is enough for construction testing: connect it to JA and leave JB empty. Both driver instances continue running, so a missing physical display does not block the game. To inspect the map instead, switch the board off, move the OLED to JB, then power on and program the board again.

| Control | Behaviour |
| --- | --- |
| Mouse left-click / drag | Select an inventory row, then click a grid cell or drag its moving preview and release over a cell to place/replace one part during BUILD |
| Mouse right-click | Remove contents first, then the empty frame on a second click during BUILD |
| Mouse left-click during RUN | Pop the surviving balloon in that cell on the left grid; release before clicking another balloon |
| SW0 | Enable the engine; turn on before launching to reach the goal |
| SW1 | Audio mute: one mutes and cancels the current beep; zero enables audio |
| BTNC | Launch from BUILD; retry from SUCCESS/FAIL |
| BTNU | Return to BUILD after a result |
| BTNR | Play one short audio test beep; release before pressing again |
| BTND | Reset the system |
| LED 2 through 0 | Game state: BUILD=0, INIT_RUN=1, RUN=2, SUCCESS=3, FAIL=4 |
| LED 3 | World result pending |
| LED 4 through 6 | Pig alive, build valid, engine enabled |
| LED 15 through 7 | Intact mask for cells 8 through 0 |

The preset has three frames across the middle row, with a pig in the centre frame and an engine in the right frame. Two wheels occupy the bottom corners; the other cells are empty. A green right-screen border indicates success; red indicates failure.

BTNC, BTNU and BTNR use the user's `button_debouncer` approach: one immediate press pulse, a 200 ms lockout, then a required 20 ms stable release. Its timing counts use the shared 100 MHz clock. Reset clears the debouncers as well as the game.

The builder stores frames separately from cell contents. A frame holds either one pig or one engine; wheels occupy cells directly below frames and balloons directly above frames. Place/replace/remove actions work through the edit inputs during BUILD. Removal clears contents first, then the empty frame on the next action. Launch requires exactly one pig and valid attachments. Frames and contents have separate runtime damage flags, and retry restores both layers of the edited build. The OLED renderers draw frame borders around their contents and count both layers.

Inventory totals are five frames, one pig, two wheels, one engine and two balloons. They are parameters in `My_Top_Module`/`vehicle_builder`; the preset already uses three frames, the pig, both wheels and the engine. Remaining stock comes from the saved construction, so removal/replacement refunds the old item while runtime damage does not. An unaffordable replacement preserves the original cell. Replacing an item with itself does not charge it twice. The five inventory rows are frame, pig, wheel, engine and balloon; the selected row is yellow and zero counts are red.

The unchanged `MouseCtl`/`Ps2Interface` drivers feed `mouse_adapter`, which limits the cursor to 96 by 64 pixels. Left-button placement starts with a press in the inventory or grid and places one part at the release cell. An eight-pixel part preview follows beside the cursor while held, staying fully on the screen at the edges. It uses the temporary inventory icons, ready for later sprite replacement. Holding or crossing cells does not place anything or consume stock; releasing outside the grid, pressing right-click or leaving BUILD cancels placement and clears the preview. Selecting a row and then clicking a cell still works. Right-click removes once on press. The top connects these edits to the builder. The XDC enables the existing C17/B17 mouse pins with pull-ups. Mouse editing and inventory are tested with completed packet inputs; the game-loop bench also compiles/elaborates the real VHDL drivers. Kaushal reported that the construction/mouse/OLED checklist passed on the previous board build; the new balloon controls and moving previews still need a board test.

During RUN, a fresh left press on a surviving balloon queues its cell in `balloon_control`. Clicks wait until the current movement/world update finishes. The controller reserves an idle clock to apply them before another step; the builder clears only the balloon's runtime intact bit. Surviving balloon count and mass then decrease automatically. Holding or dragging does not pop other cells, and clicking other parts does nothing. Saved construction and inventory stay unchanged; retry or return to BUILD restores popped balloons. Result states and reset clear queued clicks. The left cursor is visible during both BUILD and RUN.

To test on JA, place two balloons above the preset's middle-row frames, launch with SW0 off, then click each balloon in the left grid. Each should disappear and reduce the surviving-part count by one. Holding the button while moving over the other balloon must leave it intact. Turn SW0 on to reach the goal, then use BTNC to retry or BTNU to return to BUILD and check restoration. Use the 21 October bitstream at `tmp/balloon_board_test/My_Top_Module.bit`, or regenerate it in Vivado. The earlier `tmp/oled_board_test/` bitstream does not include this feature.

The first audio test uses a Pmod AMP2 on JC pins 1-6. BTNR requests a quiet 1 kHz, 0.2-second beep; SW1 mutes/cancels it. Gain is set to the lower 6 dB setting, and reset/mute disables the amplifier through its shutdown pin. See [audio setup](docs/audio_setup.md) for wiring and testing. The new source uses counters on the shared 100 MHz clock, with PWM centred around 50% duty. Generate a fresh bitstream before trying it; the earlier balloon build has no audio. Game-event sound routing and priority handling remain to be added after the beep is verified physically.

TNT, walls/ceilings, game-event sounds, instructions and the two final maps remain to be implemented. The builder's content damage channel currently carries balloon pops; its frame damage mask remains zero. When TNT is integrated, its masks need to be combined/arbitrated with pop requests without dropping either source. Balloon lift is provisional and temporary engine boost controls remain future work. Runtime movement still treats the vehicle as one upright body, without detached-part motion.

During BUILD, an accepted placement/removal gives its cell a green outline and shows PLACED/REMOVED along the bottom. A rejected drop gives a red outline and NO STOCK, NEED FRAME, FRAME ABOVE, FRAME BELOW or CELL OCCUPIED. The feedback lasts one second at 100 MHz (`FEEDBACK_CYCLES=100000000`), then returns to READY, ADD PIG, CHECK SUPPORT or CHECK STOCK for the saved build. A new reportable action restarts the timer; dropping the same part onto itself, removing an empty cell and cancelling outside the grid stay quiet. The builder uses one edit decision for both storage and feedback; rejected actions preserve stock and construction. Reset, launch and leaving BUILD clear transient feedback. The bottom strip replaces the small indicators during BUILD; runtime indicators remain. Text uses a small built-in 5 by 7 font that Marcus can replace later. This feedback still needs a physical OLED test.

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

Keep testbenches in `sim/`; the registration script adds only the design files beside `My_Top_Module.v` to the hardware build.

The existing `.srcs` folder retains the supplied drivers, hardware top and constraints. Do not move those files independently of the Vivado project.

## First shared milestone

Edit a valid vehicle with the mouse, check remaining stock, launch it on flat ground, show a result and retry with the saved construction. Then add TNT, gameplay controls and audio in small steps. Test both OLEDs, the actual mouse and an amplifier beep on the board early.

## Tool checks

Run `scripts/run_simulations.ps1` in PowerShell to compile the VHDL mouse drivers and run the eleven regression benches. Pass `-VivadoBin` if Vivado is installed elsewhere, or `-Benches` to choose specific benches. The benches check mouse configuration/clicks, inventory limits/refunds, construction edits and edited-build restoration, queued balloon popping, PWM beep timing/mute/reset and AMP2 controls, the connected lifecycle, button bounce and release, held input, collision backpressure, damage/restoration, invalid launch, result priority, representative pixels, display snapshot transfer, signed balloon lift, movement handshakes and clock/reset behaviour.

From the repository root in PowerShell, run `vivado -mode batch -source (Join-Path (Get-Location).Path 'scripts/check_baseline.tcl')` to synthesise the baseline without changing the saved project. Passing the absolute script path avoids depending on Vivado's working directory. Reports go into `tmp/baseline_synthesis/`. Synthesis checks do not establish routed timing or board behaviour; test the generated design on the actual hardware before claiming features in the report.

The original six simulation benches passed on 15 October 2026. On 16 October, the new construction bench and the affected game-loop and module-contract benches passed after adding grid editing. The initial synthesis attempt stopped before reading the design because the local Vivado Tcl Store could not load `::tclapp::support::appinit 1.2`.

On 19 October, the frame/content builder, module-contract, game-loop and display-transfer checks passed after the two-layer update. The new tests include placement rules, unsupported attachments, independent layer damage, a two-digit surviving-part count and edited-build restoration.

The subsequent `construction_controls_tb` passed mouse selection/held-click handling, geometry boundaries, inventory rejection/refunds, atomic replacement, cursor/inventory pixels and no stock refund on damage/retry. The mixed-language game-loop bench passed with the actual mouse drivers connected; no physical mouse exchange is simulated by that bench.

After adding release-based drag-and-drop, all eight benches passed again. The mouse checks cover one placement at the final release cell, no placement or stock charge while held, outside/right-click/reset/game-state cancellation, a fixed selection while dragging, rejected drops, and launch protection during a drop.

The 19 October board build completed synthesis, placement, routing, design-rule checks and bitstream generation. Timing fixes use fixed inventory-row comparisons, a registered reset output and separate property/force/velocity/position clocks within the movement state machine. All eight benches passed after these changes. The routed design uses 3,057 LUTs (14.70%) and 1,260 flip-flops (3.03%), with no block RAM or DSP use. The constrained 100 MHz paths meet setup/hold timing (worst setup slack 0.508 ns, hold slack 0.100 ns). Divided-OLED-clock and external-I/O timing remain incompletely constrained; actual OLED/mouse operation still needs a board test. The local bitstream and reports are under `tmp/oled_board_test/`, excluded from Git. Session-only package-path setup and an explicit source list were used for this machine's command-line build, without changing the Vivado installation.

On 21 October, all nine benches passed after adding balloon popping. `balloon_controls_tb` drives completed packets through the connected hardware top with controlled button/tick/world-result fixtures. It checks fresh/held/invalid clicks, deferred and simultaneous step/world-boundary clicks, RUN cursor/balloon pixels, reduced count/mass, unchanged inventory/construction, result cancellation, retry, return to BUILD and reset. The requested hardware build then completed synthesis, placement, routing and bitstream generation without source changes. Its outputs are under `tmp/balloon_board_test/`: 3,064 LUTs (14.73%), 1,270 flip-flops (3.05%), zero block RAM/DSP use and zero reported design-rule violations. Constrained 100 MHz timing passes with 0.563 ns setup slack and 0.113 ns hold slack. Divided-OLED-clock and external-I/O timing remain incompletely constrained. Balloon controls still need a physical board test. The 19 October reports/bitstream describe the earlier build.

On 22 October, all ten simulation benches passed after adding the AMP2 manual beep test, debounced BTNR and SW1 mute. The new bench checks PWM duty/tone timing, exact duration, ignored busy requests, cancellation on mute/reset, held-button suppression, JC gain/shutdown mapping and unchanged game controls. No new synthesis, routed timing or bitstream build was run for this audio stage; regenerate in Vivado and verify the physical speaker before claiming hardware audio operation. The 21 October utilisation/timing figures describe the pre-audio build.

All ten benches also passed after adding the moving construction preview. Checks cover all five part icons, cursor following, transparent icon areas, screen-edge clamping, unchanged inventory while held, accepted/rejected drops and cancellation. The connected top-level check transfers drag state, selection and cursor coordinates through the actual OLED snapshot and verifies preview drawing/removal. No new bitstream was generated; regenerate in Vivado and test the preview on JA.

The subsequent redundancy review consolidated inventory/preview icon drawing, shared the mouse grid-cell calculation, replaced inventory row arithmetic with fixed boundaries, combined switch reset handling and removed unused top-level connections. The four unused interface template copies were removed, and source registration now reads the flat design folder without a recursive helper. All ten simulation benches passed after cleanup. A separate before/after comparison matched 1,105,920 pixels across 180 full frames, and Vivado RTL elaboration passed. The source audit found 23 design/header files registered once and 20 unique Verilog modules, each instantiated; a Tcl test with mocked Vivado commands verified repeat registration, include-path handling, top selection and the missing-project guard. The supplied drivers/helpers, saved build, runtime damage masks, movement calculation stages and display transfer buffers were preserved. These checks do not replace a board test or produce new utilisation figures or a bitstream.

On 23 October 2026, all eleven simulation benches passed after adding construction feedback. The new bench checks all seven edit outcomes, exact display duration, replacement/repeated messages, quiet no-ops including unsupported existing parts, stock/refunds, persistent build status and mode/reset clearing. The connected top-level bench verifies that reason/cell cross the 131-bit display snapshot and produce a red outline without changing a rejected build. Five OLED frames exported from simulation were visually checked for readable text and correct outlines; the preview is in `tmp/feedback_review/oled_feedback_preview.png`. Physical testing and a fresh bitstream remain pending.

The same version also passed a design-only synthesis check with no unresolved black boxes or reported inferred latches. Its synthesis estimate is 3,267 LUTs (15.71%), 1,423 flip-flops (3.42%) and zero block RAM/DSP use for the whole current design, including audio and construction feedback. Reports are in `tmp/feedback_review/`. This temporary check did not load timing constraints or run placement/routing; it establishes synthesis and an area estimate, with no new routed timing result or bitstream.

Develop the existing `.v` modules in the design source folder. Their ports and `docs/interfaces.md` define the current interfaces; the old interface-only template copies have been removed.

## Contribution records

Keep references and contribution records for the final report. `custom_clk_divider.v`, `square.v` and `seven_seg_oled.v` preserve the user's supplied logic and are connected to the starter. Each owner must review, understand, extend and test their contribution; supplied drivers retain their original attribution.

`button_debouncer.v` adapts the user's supplied three-state debouncer and optional release check. The integration adds reset handling and makes the release interval a parameter for the 100 MHz clock and short simulations. The optional hold timer is omitted because these controls need only press pulses.
