# Laggy Piggies FPGA project

The current UI uses a settings gear for Audio and Map Selection, a book-with-? diary icon, three numbered inventory pages, and click/release on an engine or rocket's own cell to flip it. Direction arrows appear before inventory counts; balloons show up. Placement feedback briefly replaces the toolbar. The wheel now steps in the corrected direction through four map scales, including a 192 by 128 world-pixel overview. See [current gameplay menu and controls](docs/gameplay_menu.md); older development notes below describe earlier layouts.

Owner: Shared - all roles. [File-by-file owners](docs/file_owners.md) are listed separately and labelled in the custom source files.

Build one shared Basys3 game by giving each member ownership of separate modules and agreeing the signals between them. The hardware top connects mouse construction, limited inventory, force/mass movement, reverse, ground-only jumping, balloon lift, provisional platform collision, game audio, two selectable maps and two OLED views. It is a baseline for team development, not the full proposal implementation.

## Try the starter

Open `GPT_6_S2_01_I-FDP_project.xpr` in Vivado. Sources, pin constraints and the default `game_baseline_tb` simulation top are registered. The left OLED uses JA: during BUILD it shows a 48 by 48 pixel grid, five inventory rows, selection and cursor; during RUN it shows the build, status and surviving-part count. The right OLED uses JB and shows the vehicle at eight pixels per cell, sprites, terrain, the goal and provisional TNT/spikes. The maps fit the fixed 96 by 64 view; there is no scrolling camera. Verify the physical connector arrangement before attaching displays with board power off.

One OLED is enough for the complete game: connect it to JA. SW15 down shows the builder/status view on JA and the normal map on JB. SW15 up shows the map on JA and blanks JB, reusing the existing map renderer. Changes happen at frame boundaries and both JA views retain the 180-degree mounting correction. Build with SW15 down, launch, then flip it up to watch the vehicle. Flip it down during gameplay to pop balloons; gameplay keeps running. Hidden grid/inventory/level-button actions are blocked, and changing views cancels a pending drag. A missing physical JB display does not stall the game.

| Control | Behaviour |
| --- | --- |
| Mouse left-click / drag | Select inventory and place on release; drag an existing grid part to another cell or back to any inventory row during BUILD |
| Mouse right-click | Remove contents first, then the empty frame on a second click during BUILD |
| Mouse left-click during RUN | Pop the surviving balloon in that cell on the left grid; release before clicking another balloon |
| SW0 | Enable ground-engine thrust |
| SW2 | Reverse engine thrust; SW1 remains audio mute |
| BTNL | Spring impulse using the former jump control; once per ground contact |
| SW15 | Down: builder on JA and map on JB. Up: map on JA for one-OLED play |
| SW1 | Audio mute: one mutes and cancels the current sound; zero enables audio |
| BTNC | Launch from BUILD; retry from SUCCESS/FAIL |
| BTNU | Return to BUILD; advance to the next level after SUCCESS, keep the level after FAIL |
| Left OLED map icon | Open the four-level selector during BUILD; choose a tile, or use Back/BTNU to cancel |
| BTNR | Reserved; no test sound |
| BTND | Reset the system |
| LED 2 through 0 | Game state: BUILD=0, INIT_RUN=1, RUN=2, SUCCESS=3, FAIL=4 |
| LED 3 | World result pending |
| LED 4 through 6 | Pig alive, build valid, engine enabled |
| LED 15 through 7 | Intact mask for cells 8 through 0 |

Startup and BTND reset show an empty grid with full inventory. JA's output is rotated 180 degrees for the upside-down builder OLED, including its cursor, text and sprites; JB keeps its original orientation. A simple test vehicle uses three frames across the middle row, a pig in the centre frame, an engine in the right frame and wheels in the bottom corners. A green right-screen border indicates success; red indicates failure.

BTNC, BTNU and BTNR use the user's `button_debouncer` approach: one immediate press pulse, a 200 ms lockout, then a required 20 ms stable release. Its timing counts use the shared 100 MHz clock. Reset clears the debouncers as well as the game.

The builder stores frames separately from cell contents. A frame holds either one pig or one engine; wheels occupy cells directly below frames and balloons directly above frames. Place/replace/remove actions work through the edit inputs during BUILD. Removal clears contents first, then the empty frame on the next action. Launch requires exactly one pig and valid attachments. Frames and contents have separate runtime damage flags, and retry restores both layers of the edited build. The OLED renderers draw frame borders around their contents and count both layers.

Inventory totals are five frames, one pig, two wheels, one engine and two balloons. They are parameters in `My_Top_Module`/`vehicle_builder`; all parts are available after reset. Remaining stock comes from the saved construction, so removal/replacement refunds the old item while runtime damage does not. An unaffordable replacement preserves the original cell. Replacing an item with itself does not charge it twice. The five inventory rows are frame, pig, wheel, engine and balloon; the selected row is yellow and zero counts are red.

The unchanged `MouseCtl`/`Ps2Interface` drivers feed `mouse_adapter`, which limits the cursor to 96 by 64 pixels. Left-button placement starts with a press in the inventory or grid and places one part at the release cell. An eight-pixel part preview is centred on the cursor while held and stays fully on the screen at the edges. Cursor, sprite, source-cell information and build state use the same display snapshot. The shared part sprites are used for inventory, construction and dragging. Holding or crossing cells does not place anything or consume stock; releasing outside the grid, pressing right-click or leaving BUILD cancels placement and clears the preview. Selecting a row and then clicking a cell still works. Dragging an existing frame carries its pig/engine too; wheel/balloon attachments remain in their own cells. The source sprite is hidden while held, but saved construction and stock change only on an accepted release. Occupied/unsupported destinations, outside drops and same-cell drops preserve the source. Returning a bundle to any inventory row refunds both its frame and contents. Moving a frame can leave attachments needing support, which build validation flags before launch. Right-click cancels a held drag; otherwise it removes once on press. The top connects these edits to the builder. The XDC enables the existing C17/B17 mouse pins with pull-ups. Mouse editing and inventory are tested with completed packet inputs; the game-loop bench also compiles/elaborates the real VHDL drivers. Kaushal reported that the construction/mouse/OLED checklist passed on the previous board build; the balloon controls, moving previews, construction feedback and manual speaker test were subsequently reported working on the board on 24 October 2026. The new automatic audio needs its own board test.

During RUN, a fresh left press on a surviving balloon queues its cell in `balloon_control`. Clicks wait until the current movement/world update finishes. The controller reserves an idle clock to apply them before another step; the builder clears only the balloon's runtime intact bit. Surviving balloon count and mass then decrease automatically. Holding or dragging does not pop other cells, and clicking other parts does nothing. Saved construction and inventory stay unchanged; retry or return to BUILD restores popped balloons. Result states and reset clear queued clicks. The left cursor is visible during both BUILD and RUN.

To test on JA, construct the simple test vehicle described above, then place two balloons above its middle-row frames, launch with SW0 off, then click each balloon in the left grid. Each should disappear and reduce the surviving-part count by one. Holding the button while moving over the other balloon must leave it intact. Turn SW0 on to reach the goal, then use BTNC to retry or BTNU to return to BUILD and check restoration. Generate a fresh bitstream in Vivado and program `GPT_6_S2_01_I-FDP_project.runs/impl_1/My_Top_Module.bit`. Hardware Manager can retain an older file selection: the files under `tmp/oled_board_test/` and `tmp/balloon_board_test/` do not contain the latest audio/feedback changes.

Background music is a quiet, single-voice adaptation of Scott Joplin's The Entertainer. The same roughly ten-second phrase plays at 96 BPM in BUILD and 120 BPM in RUN. Sound effects pause it and it resumes afterwards; results stop the music for the result jingle. SW1 mutes both. `ENABLE_BGM=0` disables only music at build time, and `BGM_UNIT_CYCLES` sets its base sixteenth-note duration. The note table cites the public-domain Mutopia score.

Game audio uses a Pmod AMP2 on JXADC pins 1-6. Accepted launch, balloon pop, landing, success and failure events play distinct short tones/sequences; TNT explosions also trigger their own sound and animation. Failure/success take priority over ordinary actions; held events do not repeat and lower-priority busy events are discarded. BTNR is silent; diary page SOUND 4/4 provides volume −/+ for music and effects. SW1 mutes/cancels, and reset/retry/edit clear old playback. Ordinary mouse edits and buttons have no generic click sound. Notes fade in/out and PWM duty changes only between carrier frames. See [audio setup](docs/audio_setup.md) for profiles and tests.

TNT damage, spike detection and wall/ceiling collisions are connected. TNT and queued balloon pops share the builder damage input; explosions can destroy contents and frames, update movement properties, and kill the pig before goal checks. Retry restores the saved build and TNT. Instructions, final level balancing and hardware verification remain. Balloon lift tuning is provisional; the engine boost control is available on the left RUN screen. Runtime movement treats the vehicle as one connected body, now tilting to match cave slopes in 11.25-degree steps up to 45 degrees each way. The sprite, terrain collision and pig/part interactions share the committed angle; airborne movement keeps its launch attitude. Detached-part motion and free spinning remain future work.

During BUILD, an accepted placement/removal gives its cell a green outline and shows PLACED/REMOVED along the bottom. A rejected drop gives a red outline and NO STOCK, NEED FRAME, FRAME ABOVE, FRAME BELOW or CELL OCCUPIED. The feedback lasts one second at 100 MHz (`FEEDBACK_CYCLES=100000000`), then returns to READY, ADD PIG, CHECK SUPPORT or CHECK STOCK for the saved build. A new reportable action restarts the timer; dropping the same part onto itself, removing an empty cell and cancelling outside the grid stay quiet. The builder uses one edit decision for both storage and feedback; rejected actions preserve stock and construction. Reset, launch and leaving BUILD clear transient feedback. The bottom strip replaces the small indicators during BUILD; runtime indicators remain. Text uses a small built-in 5 by 7 font that Marcus can replace later. This feedback was reported working on the physical OLED on 24 October 2026.

Kyle's movement uses a staged force calculation and a 16-clock signed divider for horizontal force/mass, retaining fractional remainders so weak forces accumulate. Ground engine force is 96 units per engine and resistance is 10 per wheel; SW2 reverses thrust. Jumping sets upward velocity to -512 (two pixels/update) after confirmed ground contact. Gravity adds 32 per update; provisional balloon lift is 24 per surviving balloon, so one slows a fall and two rise. On the cave maps, measured terrain slopes now add downhill gravity and brake uphill travel before wheel friction; balloon lift reduces this force and jumping detaches from it. Properties are captured once per update, and world checks complete before another movement step. See [integration review](docs/integration_review.md) for branch coverage and resolved issues.

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

Edit a valid vehicle with the mouse, check remaining stock, launch it on flat ground, show a result and retry with the saved construction. Then verify TNT damage, queued balloon pops, explosion audio and retry on both levels. Test both OLEDs, the actual mouse and an amplifier beep on the board early.

## Tool checks

Run `scripts/run_simulations.ps1` in PowerShell to compile the VHDL mouse drivers and run the regression benches. Pass `-VivadoBin` if Vivado is installed elsewhere, or `-Benches` to choose specific benches. The benches check mouse configuration/clicks, inventory limits/refunds, construction edits and edited-build restoration, queued balloon popping, PWM beep timing/mute/reset and AMP2 controls, the connected lifecycle, button bounce and release, held input, collision backpressure, damage/restoration, invalid launch, result priority, representative pixels, display snapshot transfer, signed balloon lift, movement handshakes and clock/reset behaviour.

Run `scripts/check_map_solidity.ps1` after map or collision-ROM changes. It synthesizes the collision query port and compares every map pixel against the colour-class assets. This checks actual block-RAM initialization, which ordinary RTL simulation does not verify. Map generation writes both `*_map.mem` colour files and explicit `*_solid.mem` collision files; keep all four registered in the project.

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

On 24 October 2026, all twelve simulation benches passed after replacing the one-off test beep with game-event audio. New checks cover seven profiles, note timing/pitches, volume fades, PWM frame integrity, priority/preemption, held/muted requests, silent ordinary controls and accepted launch/pop/landing/result events. Design-only synthesis passed with no unresolved black boxes or inferred latches: 3,395 LUTs (16.32%), 1,506 flip-flops (3.62%) and zero block RAM/DSP use. This is a net increase of 128 LUTs over the previous design-only estimate. Reports/logs are under `tmp/audio_events_review/`. No implementation, bitstream generation or new audio board verification was performed for this version.

On 24 October 2026, the published Role 1, Role 2 and Role 4 changes were combined and reviewed. Control conflicts, stale source registration, outdated movement tests and measured timing paths were corrected. All 19 benches passed on the final merged sources. Final routed use is 5,629 LUTs (27.06%), 2,060 flip-flops (4.95%), 13 DSPs (14.44%) and no block RAM. The constrained 100 MHz paths meet setup/hold timing, with 0.317 ns setup slack and 0.077 ns hold slack. DRC reports no error/critical-warning rules; the remaining DSP pipelining warnings concern performance/power suggestions. Divided-OLED-clock and external-I/O timing remain incompletely constrained, as before; physical board verification is still required. No bitstream was generated. See [the integration review](docs/integration_review.md) for scope, controls and remaining Role 3 work.

Develop the existing `.v` modules in the design source folder. Their ports and `docs/interfaces.md` define the current interfaces; the old interface-only template copies have been removed.

## Contribution records

Keep references and contribution records for the final report. `custom_clk_divider.v`, `square.v` and `seven_seg_oled.v` preserve the user's supplied logic and are connected to the starter. Each owner must review, understand, extend and test their contribution; supplied drivers retain their original attribution.

`button_debouncer.v` adapts the user's supplied three-state debouncer and optional release check. The integration adds reset handling and makes the release interval a parameter for the 100 MHz clock and short simulations. The optional hold timer is omitted because these controls need only press pulses.

On 24 October, the one-OLED SW15 selector, centred existing-part/bundle dragging and inventory returns, and quiet Entertainer BGM were added. All 22 simulation benches passed; audio and view checks passed again after simplifying the music timing counter. The final local routed check uses 6,003 LUTs (28.86%), 2,193 flip-flops (5.27%), 13 DSPs (14.44%) and no block RAM, with constrained 100 MHz setup/hold slack of 0.055/0.078 ns. The divided OLED clock and external I/O remain incompletely constrained, and the new features need a fresh bitstream and hardware check. Reports are in `tmp/player_features_review/`; no bitstream was generated by this check.

## Programming files

Completed bitstreams are organised by build date under [`bitstreams/`](bitstreams/README.md). Check [`LATEST.txt`](bitstreams/LATEST.txt) for the current archived file and select it in Vivado Hardware Manager. Reopen the saved project to enable automatic timestamped archiving after future Generate Bitstream runs.

## Level selector

During BUILD, click the folded-map icon at the bottom right of the left OLED. The menu allows toggling between Level 0 (Cave Arch at 2x scale) and Level 1 (Cave Flight). Click a tile to select it and return to construction. A green outline marks the current level. Back or BTNU closes the menu without changing the level. Saved construction and inventory are preserved, launch is blocked while the menu is open, and hidden or held mouse clicks cannot select a tile. The right OLED retains the current level's spawn preview while the menu is open.

The current audio source includes melody plus bass, a longer BUILD arrangement, and a roughly 50-second Bad Piggies main-theme loop that starts on RUN. Diary page SOUND 4/4 provides five settings (OFF and levels 1..4); retry preserves the selection and reset restores level 4. See [audio setup](docs/audio_setup.md). A fresh bitstream and a physical listening test are still needed for these changes.

The current source replaces the RUN status panel with **DRIVE / POP / SOUND** pages, with a round-arrow retry and EDIT control. Physical controls remain: SW0 acts as a toggle synchronization input alongside the on-screen DRIVE button. Construction has P1/P2 inventory pages, left/right engine, rocket and fan orientation, side-mounted rocket/fan stock, contents-first dragging from filled frames, and flipping orientation for engines, rockets and fans. Guide / Diary page 1 features a clear visual example build with validity guidelines. See [gameplay menu and construction controls](docs/gameplay_menu.md), including the [rendered preview](docs/images/gameplay_menu_preview.png). Generate a fresh bitstream to use these changes.

Regression status (30 October 2026): all 51 simulation benches pass cleanly in `scripts/run_simulations.ps1`, including exhaustive map solidity, vehicle drive tests on 2x Cave Arch, 360° flip physics, and occupied-cell geometry/handshake cases. Legacy placeholder rectangle maps and unused rectangle collision logic have been removed, streamlining resource utilization and timing.

## Cave boundary and goal integration

World checks now use each level's dimensions: 956 by 582 for Cave Arch (2x scale) and 890 by 213 for Cave Flight. Positions remain signed 20-bit Q12.8 through spawn, physics, collision, TNT pose checks, death effects and display transfer, so Cave Flight starts at y=178 without wrapping. A vehicle fails once its rotated outer 24 by 24 envelope leaves the world; partial overlap is allowed. Both cave flags have 16 by 24 pig-centre goal entry zones above their supporting surfaces. See `docs/interfaces.md` for the exact zones.

Cave collision now uses the actual terrain ROM with independent draw/query map selection. Explicit one-bit `*_solid.mem` files are generated alongside the colour maps and preserve their solidity in synthesized block RAM. Sky and dark green cave background are open; rock, grass, road and underground are solid. The live cave checker tests only surviving occupied 8 by 8 cells, using `collision_mask = intact_mask | frame_intact_mask` captured with each movement request. All nine tilt angles retain the fixed grid-centre pivot at (x+12,y+12). Movement sweeps in one-pixel axis steps and checks intersecting terrain pixel areas, including fractional edges. Grounded movement can step up three pixels or snap down three pixels after a small drop; jumps and upward balloon motion disable stepping/snapping. Walls and ceilings stop the affected velocity component. Outside-map pixels are ignored by collision so world-bound failure remains reachable. Rectangle-level collision, hazards and world bounds retain their outer vehicle envelope.

The photographed green obstruction in Cave Arch's first valley has been removed: exactly 53 isolated GRASS pixels at x=225..231, y=92..100 become open CAVE background. The actual grass road below is preserved. The former whole-grid collision body also blocked empty cells against nearby rock, which could appear to be background collision. Occupied-cell collision removes that limitation for sparse builds. Earlier analysis found the Arch goal passage impossible for the full 24 by 24 hull; that is a historical limitation of the full hull, and a complete playable route with the current collision has not yet been validated. The Flight goal has a clear supported full-hull pose at vehicle origin (757,32). An audit confirmed the user's 15:10:47 bitstream already contains the collision-ROM repair; these new bush and occupied-cell changes still require a fresh bitstream.

`map_collision_tb` covers synthetic geometry, registered ROM latency, step/snap limits, jumping, fast thin-obstacle crossings, reset and response backpressure. `map_rom_collision_tb` validates real-map spawns, movement and a Flight goal ledge against independent ROM copies while draw/query select different maps. `occupied_map_collision_tb` passes 25 cases covering the actual valley obstruction and roof clearance, all nine tilt angles against independent occupied-cell geometry, all four corner cells at both 45-degree angles, real floor/wall/ceiling contact, an empty mask, request capture and response backpressure. Its longest request is 410,151 clocks (4.102 ms at 100 MHz), including a 40-pixel stress sweep beyond the normal movement cap; the initial 17 normal fixtures peak at 136,364 clocks (1.364 ms). `world_outcomes_tb`, `cave_coordinates_tb` and `cave_map_integration_tb` retain bounds/goals, coordinate, result-wiring and display-transfer checks. Teleported goal fixtures are not recorded gameplay solutions. A fresh hardware build and board validation remain pending for the occupied-cell changes.


Fan and rocket physics are connected to the existing runtime DRIVE page controls.
FAN ON supplies continuous horizontal force 64 per surviving fan; ROCKET FIRE
starts one 90-update burn per run at force 1024 per surviving rocket. Fan force
uses the corrected sign relative to its legacy facing balance. Rocket thrust follows body rotation, so a tilted side rocket also supplies
vertical force. Physics also accepts a signed `rocket_vertical_balance` (down minus up) for future placement
logic; the editor and placement wiring are unchanged. Retry restores rocket fuel. Both work airborne using
the existing mass divider. BTNL now serves as the spring trigger through the
existing `jump_press` input: a grounded upward impulse of 512, rearmed after
contact releases. The spring item will be added separately. See
[the physics interface notes](docs/interfaces.md#fan-rocket-and-spring-physics-2026-10-31).


Rigid-body moments are enabled by `ENABLE_MOMENTS=1`. Surviving part masses
set a quarter-pixel centre of mass. Fans/rockets turn the vehicle according to
force times perpendicular distance; engine drive and wheel drag act at grounded
tyre contacts. Fractional angular velocity accumulates, with a bounded spin rate
and COM-preserving origin correction during rotation. The implementation uses
serial arithmetic and an approximate mass-scaled rotational inertia. Set
`ENABLE_MOMENTS=0` for the earlier turning model. See
[the moments interface notes](docs/interfaces.md#rigid-body-moments-2026-10-31)
for equations, assumptions and checks.


For steadier driving, the game uses `WHEEL_TORQUE_SHIFT=2` (quarter-strength
wheel-to-body turning response), 25% grounded spin damping, and gentler edge
tipping. Linear engine/wheel force is preserved. Rocket force and torque share
`ROCKET_FORCE_SHIFT=10` (1024); set 9 for the older 512 strength. Rocket direction
now rotates with the vehicle, matching the visible sprite and moment calculation.
