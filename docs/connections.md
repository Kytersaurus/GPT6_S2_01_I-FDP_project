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
| `vehicle_builder` | `physics_engine` | Four-bit `wheel_count`, `engine_count`, `balloon_count` and eight-bit `mass_units` describe surviving parts |
| `vehicle_builder` | `game_controller` | `build_valid` gates launch; `pig_alive` participates in the final outcome |
| `level_data` | `physics_engine` | Signed 16-bit `spawn_x` and `spawn_y` load the initial position |
| `game_controller` | Builder, physics, world outcomes | `run_init` stays high in INIT_RUN; each module returns one bit of the three-bit `init_ready` bus |
| `game_controller` | `physics_engine` | `step_start` begins one update; `update_release` allows the following update after world checks finish |
| `physics_engine` | `collision_engine` | `move_valid`/`move_ready` transfer `previous_x/y`, `proposed_x/y` and `proposed_vx/vy` |
| `collision_engine` | `physics_engine` | `response_valid`/`response_ready` transfer `corrected_x/y`, `corrected_vx/vy` and `grounded` |
| `physics_engine` | `world_outcomes` | `movement_committed` pulses after `vehicle_x/y` have been updated; the world module samples those committed coordinates |
| `vehicle_builder`, `level_data` | `world_outcomes` | `build_grid`, `intact_mask` and `goal_rect` locate the surviving pig and test the goal |
| `world_outcomes` | `game_controller` | `world_valid`/`world_ready` transfer `goal_hit`, `hazard_hit` and `out_of_bounds`; failure outranks success |

Every movement coordinate and velocity is signed with eight fractional bits: 256 units equals one pixel. Valid/ready payloads stay unchanged until a rising-edge transfer. Physics waits for world completion before sampling properties for another step.

`input_controller` instantiates the user's `button_debouncer` for BTNC and BTNU. Each uses the shared 100 MHz clock, `freq_count=19,999,999` for 200 ms of lockout, and `RELEASE_CYCLES=2,000,000` for a stable 20 ms release before rearming. The module adds reset handling to the user's code and includes the optional release check without the hold timer. The top exposes cycle-count parameters so simulations can use short intervals.

## Connected drawing path

The top packs game state, build grid, intact mask, validation, vehicle position and engine status into a 77-bit bus for `display_snapshot`. The snapshot module transfers a held payload from the game clock to the OLED clock, then publishes it at a frame boundary. Both renderers consume the same published snapshot.

Each `Oled_Display` instance produces its own `pixel_index`; its renderer returns `pixel_data`. The left driver connects to JA and the right driver to JB. Both drivers share the 6.25 MHz clock and display reset, so their frame counters start together. `level_data` feeds the right renderer's terrain and goal directly because this starter map is constant.

`left_renderer` uses the user's `square` helper to draw its grid and status areas and `seven_seg_oled` to show the surviving-part count. Editor cells are 16 by 16 pixels; gameplay cells remain eight by eight. `right_renderer` also uses `square` for the goal region. Screen geometry passed to these seven-bit helpers stays within the fixed 96 by 64 world.

`custom_clk_divider` preserves the user's supplied logic. It toggles after `freq_count+1` input cycles, so its output frequency is `input_frequency / (2*(freq_count+1))`. Hold the count at seven for the OLEDs. `clock_control` retains the physics-enable counter and reset handling; physics continues to use 100 MHz with an enable pulse rather than a separate slow clock. Custom modules use ordinary registers without explicit FPGA clock-buffer instances or placement attributes. The two-register synchronisers remain, and the generated-clock constraint targets the divider's output register. Synthesis must confirm that register path and implementation must check clock routing/timing before board use.

## Boundaries reserved for the next stage

| Boundary | Current starter behaviour | Next owner task |
| --- | --- | --- |
| Builder edit inputs | Tied to zero; fixed original grid | Role 1 adds editor, inventory and validation rules |
| Builder damage input | Tied inactive in the top; exercised in the unit bench | Role 3 produces a TNT damage mask; Role 1 applies it through `damage_valid`/`damage_ready` |
| Game guide requests | Tied inactive | Roles 1 and 4 agree navigation inputs and instruction screens |
| Audio events | `launch_event`, `success_event`, `failure_event` generated but not connected to audio | Role 1 adds sound routing/output; Role 3 later supplies explosion events |
| Mouse | Supplied controller retained but not instantiated | Role 1 adds an adapter feeding the same actions as buttons |
| Balloon popping | No control connected; the fixed build has no balloons | Role 1 updates intact state, then publishes the surviving count for Role 2 |
| Collision | Downward landing on rectangular platforms | Role 3 adds wall/ceiling/corner handling and TNT |
| Levels and sprites | One flat map and solid-colour parts | Role 4 supplies final maps, artwork, inventory/status details and instructions |

The grid is stored row-major in 27 bits, with cell zero in bits 2:0. Intact/damage masks have nine bits. Review the remaining draft rules in `interfaces.md` before adding features.

## Validation status

On 15 October 2026, the benches passed using Vivado Simulator 2025.2: `game_baseline_tb`, `module_contracts_tb`, `display_snapshot_tb`, `physics_engine_tb`, `clock_control_tb` and `button_debouncer_tb`. The game-loop bench was rerun after integrating the user's debouncer. The button bench checks press/release bounce, holding, rearming and reset using shorter timing counts. The clock bench checks counts zero, one and seven, physics-enable spacing and reset behaviour. The simulation runner checks each bench's PASS marker.

The synthesis attempt stopped during project initialisation because the local Vivado installation could not load `::tclapp::support::appinit 1.2` from its Tcl Store. It did not reach design synthesis. FPGA resource use, routed timing, display hardware and board behaviour remain unverified.
