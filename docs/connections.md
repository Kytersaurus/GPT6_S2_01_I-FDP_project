# Starter module connections

Owner: Shared integration - all roles; Role 4 (Marcus) coordinates updates.

All game modules live beside `My_Top_Module.v` in the existing design source folder. The top module contains the named port connections below. Each owner can extend their module while coordinating interface changes with the receiving teammate.

## Connected game path

| From | To | Ports and meaning |
| --- | --- | --- |
| Basys3 `clk` input in the top | All game modules | The shared 100 MHz clock is connected directly as `.clk(clk)` |
| `clock_control` | All game modules | `reset` combines the synchronised reset button and power-on reset |
| `custom_clk_divider` inside `clock_control` | Both OLED drivers | The user's divider produces 6.25 MHz with `freq_count=7`, connected directly to `oled_clk` |
| `clock_control` | `game_controller` | `physics_tick` requests an update approximately 60 times per second |
| `input_controller` | `game_controller` | `start_press` connects to both `launch_req` and `retry_req`; the current state chooses the action. `edit_press` connects to `edit_req` |
| `input_controller` | `physics_engine` | `engine_enabled` is the synchronised SW0 state, sampled when a movement step starts |
| `input_controller`, accepted game events | `sound_controller` | BTNR test, launch, applied pop, landing, success and failure; SW1 supplies mute |
| `sound_controller` | `sound_generator` | Chosen three-bit sound ID and start; busy/active ID return for priority decisions |
| `sound_generator`, reset/mute wiring | Pmod AMP2 on JC | `JC[0]` PWM audio, `JC[1]` high for 6 dB gain, `JC[2]` zero/NC, `JC[3]` high only outside reset/mute |
| `vehicle_builder` | `physics_engine` | Four-bit `wheel_count`, `engine_count`, `balloon_count` and eight-bit `mass_units` describe surviving parts |
| `vehicle_builder` | `game_controller` | `build_valid` gates launch; the top masks it while `edit_valid` is high so concurrent edits cannot launch using old validity. `pig_alive` participates in the final outcome |
| `MouseCtl` | `mouse_adapter` | Completed `new_event` packets supply 12-bit x/y positions and held button levels |
| `mouse_adapter` | `MouseCtl` | `value`, `setx/y` and `setmax_x/y` configure 96 by 64 coordinates and the initial cursor |
| `mouse_adapter` | `vehicle_builder` | One-cycle `edit_valid` plus operation, cell and part; place on left release, remove on right press |
| `mouse_adapter` | `balloon_control` | One-cycle `pop_req` and four-bit `pop_cell` on a fresh left press in the RUN grid |
| `balloon_control` | `game_controller` | `pop_pending` connects to `gameplay_pending` and blocks a new movement step |
| `game_controller` | `balloon_control` | `gameplay_ready` is high in RUN when no movement/world update is outstanding |
| `balloon_control` | `vehicle_builder` | `pop_valid` and nine-bit `pop_mask` use the content damage channel during the reserved idle clock; frame damage stays zero |
| `vehicle_builder`, `mouse_adapter` | Left renderer through snapshot | Five stock counts, selected part, cursor position and `drag_active` for the moving part preview |
| `vehicle_builder` | Left renderer through snapshot | Three-bit `feedback_code` and four-bit `feedback_cell` describe the one-second edit result and target outline |
| `level_data` | `physics_engine` | Signed 16-bit `spawn_x` and `spawn_y` load the initial position |
| `game_controller` | Builder, physics, world outcomes | `run_init` stays high in INIT_RUN; each module returns one bit of the three-bit `init_ready` bus |
| `game_controller` | `physics_engine` | `step_start` samples properties, followed by separate force/velocity/position calculation clocks; `update_release` allows the following update after world checks finish |
| `physics_engine` | `collision_engine` | `move_valid`/`move_ready` transfer `previous_x/y`, `proposed_x/y` and `proposed_vx/vy` |
| `collision_engine` | `physics_engine` | `response_valid`/`response_ready` transfer `corrected_x/y`, `corrected_vx/vy` and `grounded` |
| `physics_engine` | `world_outcomes` | `movement_committed` pulses after `vehicle_x/y` have been updated; the world module samples those committed coordinates |
| `vehicle_builder`, `level_data` | `world_outcomes` | `build_grid`, `intact_mask` and `goal_rect` locate the surviving pig and test the goal |
| `world_outcomes` | `game_controller` | `world_valid`/`world_ready` transfer `goal_hit`, `hazard_hit` and `out_of_bounds`; failure outranks success |

Every movement coordinate and velocity is signed with eight fractional bits: 256 units equals one pixel. Valid/ready payloads stay unchanged until a rising-edge transfer. Physics waits for world completion before sampling properties for another step.

`input_controller` instantiates the user's `button_debouncer` for BTNC, BTNU and BTNR. Each uses the shared 100 MHz clock, `freq_count=19,999,999` for 200 ms of lockout, and `RELEASE_CYCLES=2,000,000` for a stable 20 ms release before rearming. The module adds reset handling to the user's code and includes the optional release check without the hold timer. The top exposes cycle-count parameters so simulations can use short intervals. SW1 uses two sampling registers, with mute asserted during reset. The hardware top now accepts `sw[1:0]`, BTNR and four JC outputs; test fixtures tie unused button/mute inputs low explicitly.

Audio uses accepted launch/pop/landing/success/failure events, with a prepared explosion input awaiting Role 3. Failure outranks success, explosion, landing, pop, launch and the BTNR test. Higher priority interrupts; held/equal/lower requests do not replay or queue. The generator plays short tone sequences with quiet amplitude fades and complete PWM frames. Mute/reset/retry/edit cancel old playback; the carrier and enabled amplifier remain running between sounds. XDC mappings are unchanged. See [audio setup](audio_setup.md).

## Connected drawing path

The top packs game state, content grid, content/frame intact masks, validation, vehicle position, engine status, five inventory counts, cursor coordinates, selected part, `drag_active`, three-bit `feedback_code` and four-bit `feedback_cell` into a 131-bit bus for `display_snapshot`. The snapshot module transfers a held payload from the game clock to the OLED clock, then publishes it at a frame boundary. Both renderers consume the same published snapshot. The saved `build_frames` need not cross this boundary because frame drawing uses `frame_intact_mask`. The left renderer draws the selected part beside the cursor while dragging, with no change to construction until release. BUILD also shows the builder's one-second green/red cell outline and bottom message, then returns to the saved build's overall status.

Each `Oled_Display` instance produces its own `pixel_index`; its renderer returns `pixel_data`. The left driver connects to JA and the right driver to JB. Both drivers share the 6.25 MHz clock and display reset, so their frame counters start together. `level_data` feeds the right renderer's terrain and goal directly because this starter map is constant.

A single physical OLED can be used on JA for construction/input tests while JB is empty. The SPI displays do not return acknowledgements, so the missing screen does not stall either driver or the game. Move the display only with board power off; programming must be repeated after a power cycle when using a volatile bitstream load.

`left_renderer` uses the user's `square` helper to draw its grid/status areas and two `seven_seg_oled` instances for the surviving-part count, including frames and contents (up to 18). Editor cells are 16 by 16 pixels; gameplay cells remain eight by eight. Both renderers draw frame borders with contents in the centre. `right_renderer` also uses `square` for the goal region. Screen geometry passed to these seven-bit helpers stays within the fixed 96 by 64 world.

During BUILD the left renderer shows five inventory rows at x=56..91 and y=4..53 instead of the runtime count/status area. A third number helper displays the row's remaining stock. The adapter and renderer share the documented 16-pixel grid/10-pixel inventory-row layout. Source mouse pins `PS2Clk`/`PS2Data` connect through the existing C17/B17 XDC assignments, now uncommented with their original pull-ups. Supplied VHDL driver contents are unchanged; simulation and synthesis scripts now include them.

`custom_clk_divider` preserves the user's supplied logic. It toggles after `freq_count+1` input cycles, so its output frequency is `input_frequency / (2*(freq_count+1))`. Hold the count at seven for the OLEDs. `clock_control` retains the physics-enable counter and reset handling; physics continues to use 100 MHz with an enable pulse rather than a separate slow clock. Custom modules use ordinary registers without explicit FPGA clock-buffer instances or placement attributes. The two-register synchronisers remain. At the user's request, the constraints contain no separate generated-clock declaration for the OLED divider. Timing analysis of the divided clock remains incomplete; clock routing and board operation still need verification.

## Boundaries reserved for the next stage

| Boundary | Current starter behaviour | Next owner task |
| --- | --- | --- |
| Builder edit inputs | Connected to mouse selection/place/remove actions with inventory checks | Role 1 adds later input refinements |
| Builder damage inputs | Content mask receives balloon pops; frame mask is zero | Role 3 produces TNT masks; Roles 1 and 3 combine/arbitrate both sources without losing requests |
| Game guide requests | Tied inactive | Roles 1 and 4 agree navigation inputs and instruction screens |
| Audio events | Launch, applied balloon pops, landing, success/failure and BTNR connected; priorities and duplicate suppression implemented | Role 3 supplies actual explosion events and future wall/ceiling impact cues |
| Mouse | Supplied controller unchanged; construction and balloon clicks connected | Role 1 adds guide controls and verifies new gameplay input on the Basys3 |
| Balloon popping | Fresh RUN clicks queue surviving balloons and clear their intact bits between updates | Hardware check with balloons added to the build; sound effects remain future work |
| Collision | Downward landing on rectangular platforms | Role 3 adds wall/ceiling/corner handling and TNT |
| Levels and sprites | One flat map and solid-colour parts | Role 4 supplies final maps, artwork, inventory/status details and instructions |

Cell contents are row-major in 27 bits, with cell zero in bits 2:0. Frames are stored separately in nine-bit `build_frames`. Each layer has its own nine-bit intact and damage mask. `world_outcomes` still finds the pig through the content grid/mask; physics still receives counts and total mass without a port change. Review the placement rules in `interfaces.md` before adding features.

## Validation status

On 24 October 2026, Kaushal reported the drag preview, construction feedback, inventory and manual AMP2 test working on the Basys3 after selecting the current bitstream instead of the older OLED-test file. Unwanted speaker clicks during ordinary actions were subsequently reported; the new audio keeps those actions deliberately silent and adds note fades/carrier-frame duty updates. Their effect on physical clicks still needs verification. The automatic game sounds added afterwards require a new hardware build; the previous bitstream does not include them.


On 22 October 2026, all ten simulation benches passed after adding the manual AMP2 beep, BTNR and SW1 mute. `audio_beep_tb` covers PWM duty/timing, duration, busy suppression, mute/reset, held-button behaviour and JC control polarity through the connected top. A fresh routed build/bitstream and physical speaker test remain pending; the 21 October resource/timing figures below predate audio.

On 21 October 2026, all nine simulation benches passed after connecting `balloon_control`, RUN mouse clicks and cursor drawing. The new top-level bench delays world completion to verify queued pops and movement-boundary timing, then checks counts/mass, inventory, saved construction, retry/results/reset and pixels. The previous construction/mouse/OLED hardware checklist was reported passing by Kaushal. A requested build of the balloon version then completed with zero reported design-rule violations and passing constrained 100 MHz setup/hold timing. Its bitstream and reports are in `tmp/balloon_board_test/`; routed usage is 3,064 LUTs (14.73%) and 1,270 flip-flops (3.05%). Divided-OLED-clock and external-I/O timing remain incompletely constrained. Physical balloon-control testing remains pending. The older `tmp/oled_board_test/` outputs describe the version without popping.

On 15 October 2026, the benches passed using Vivado Simulator 2025.2: `game_baseline_tb`, `module_contracts_tb`, `display_snapshot_tb`, `physics_engine_tb`, `clock_control_tb` and `button_debouncer_tb`. The game-loop bench was rerun after integrating the user's debouncer. The button bench checks press/release bounce, holding, rearming and reset using shorter timing counts. The clock bench checks counts zero, one and seven, physics-enable spacing and reset behaviour. The simulation runner checks each bench's PASS marker.

On 16 October, `vehicle_builder_tb` passed placement, replacement, removal, invalid-edit rejection, pig validation and restoration of an edited build after damage. `game_baseline_tb` and `module_contracts_tb` also passed again after the builder changes.

On 19 October, the two-layer builder, module-contract, game-loop and display-transfer checks passed. Coverage includes pig/engine inside frames, external attachments, removal order, unsupported-build rejection, independent frame/content damage, frame-border pixels, two-digit counts and restoring an edited build.

After connecting inventory and mouse editing, all eight benches passed. `construction_controls_tb` drives completed packet inputs through the adapter, builder and left renderer, checking stock limits, refunds, same-kind and cross-kind replacements, held clicks, geometry bounds, no refund on damage/retry and concurrent edit/launch protection. The top-level game test binds the real mouse VHDL drivers but does not emulate a physical mouse exchange. Hardware mouse/OLED operation remains unverified.

All eight benches passed again after adding drag-and-drop placement on left release. The mouse bench checks crossing cells without painting or charging stock, using the final release position exactly once, cancelling outside the grid/on right-click/reset/leaving BUILD, preserving the selected part while held, rejecting invalid or unavailable drops, and concurrent drop/launch protection.

The initial synthesis attempt stopped during project initialisation because the local Vivado installation could not load `::tclapp::support::appinit 1.2` from its Tcl Store. Session-only package paths and an explicit source list later allowed the 19 October hardware build to run without changing the installation.

The completed build exposed long movement, inventory-row decoding and reset paths. Movement now samples properties and calculates forces, velocity and position on separate clocks; inventory selection uses fixed Y-coordinate boundaries; reset is registered before distribution. All eight benches passed after these changes. Synthesis, placement, routing, design-rule checks and bitstream generation completed. The routed design uses 3,057 LUTs (14.70%) and 1,260 flip-flops (3.03%), with no block RAM or DSP use. Constrained 100 MHz setup/hold timing passes with 0.508 ns worst setup slack and 0.100 ns worst hold slack. The divided OLED clock and external I/O remain incompletely constrained under the current XDC, and physical OLED/mouse operation remains unverified. Local outputs are in `tmp/oled_board_test/` and are not tracked in Git.
