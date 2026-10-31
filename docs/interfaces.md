# Draft game module interfaces

Owner: Shared - all four roles agree interface changes.

The grid size and screen arrangement follow the current team proposal. The connected starter uses the port names, eight-pixel cells, numerical format and terrain encoding below. These are starting contracts for team review. Implementations and their current ports live beside `My_Top_Module.v`.

The hardware baseline starts with an empty build and two provisional maps. The builder supports mouse-driven placement, replacement, removal, limited inventory and runtime damage. Mouse edits and queued balloon pops are connected in the top. Launch, balloon-pop, landing and result sounds are connected to Pmod AMP2 on JXADC; TNT explosions trigger the explosion profile and display animation. Reverse and jump controls are connected; Instruction content and final level balancing remain future work. The engine switch is sampled by movement at the start of a step; it does not change an already published proposal. Each committed pose passes through TNT damage before pig-centre goal, hazard and bounds checks. The committed pose stays fixed until the resulting world response is accepted.

## Shared data

| Item | Draft representation |
| --- | --- |
| Game clock | 100 MHz `clk` for game logic, with clock enables for slower updates |
| Reset | `reset`, synchronous and active high for new game modules; hardware inputs require synchronisation |
| Grid contents | 3 columns by 3 rows; nine three-bit content entries in the 27-bit `build_grid` |
| Frames | Separate nine-bit `build_frames`; bit n places a frame in cell n |
| Ordering | Row major: cells 0, 1, 2 at top; 3, 4, 5 middle; 6, 7, 8 bottom |
| Packed grid | Cell 0 is bits 2:0; cell n is `build_grid[3*n +: 3]` |
| Content intact/damage | Nine-bit `intact_mask` and `damage_mask`; bit n refers to the contents of cell n |
| Frame intact/damage | Nine-bit `frame_intact_mask` and `damage_frame_mask`; bit n refers to the frame in cell n |
| Cave collision occupancy | Nine-bit `collision_mask = intact_mask \| frame_intact_mask`; captured per movement request; bit n occupies that cell's 8 by 8 area |
| Cell index | Four bits; indices 9 through 15 are invalid and must be rejected |
| Part counts | Four bits per type, allowing counts from zero to nine |
| Position and velocity | Positions: signed 20-bit Q12.8 (`LP_COORD_BITS`); velocities: signed 16-bit with eight fractional bits. 256 units is one pixel |
| Axes and origin | Positive x right, positive y down; vehicle position is the unrotated top-left grid origin; rotation pivots about (x+12,y+12) |
| Orientation | Signed 5-bit index -16..15 (`LP_TILT_BITS`) in 11.25-degree steps; positive clockwise, the full turn (-16 is upside down) |
| Terrain | Up to four rectangles; each is `{height[7:0], width[7:0], y[7:0], x[7:0]}` in whole pixels |
| Rectangle packing | Rectangle 0 occupies bits 31:0 of `terrain_rects`; only entries below `terrain_count` are active |
| Rectangle edges | Left/top inclusive, right/bottom exclusive; zero width/height disables a rectangle |

Part IDs are empty=0, frame=1, pig=2, wheel=3, engine=4, reserved=5, balloon=6. Frame is an edit selection only: it sets `build_frames` and is never stored in `build_grid`. Each frame holds one pig or engine, or remains empty. Wheels occupy their own cells directly below frames; balloons occupy their own cells directly above frames. Wheels and balloons cannot share a cell with a frame. IDs 5 and 7 are rejected. Boost is a temporary engine ability controlled from the left RUN screen, rather than a separate construction item.

State IDs are BUILD=0, INIT_RUN=1, RUN=2, SUCCESS=3, FAIL=4, GUIDE=5 and LEVEL_SELECT=6. The reset state is BUILD. Role 4 owns transitions; GUIDE returns to its agreed previous non-running screen.

At eight pixels per cell, the grid spans 24 by 24 pixels. The live cave terrain path treats surviving occupied cells as one rotated body around the fixed grid centre, so empty cells do not block terrain. Rectangle test levels remain upright and retain the full outer footprint; hazards and world bounds also retain the outer envelope. Artwork extending outside these cells and detached-part collision geometry need coordination. Mass weights and lift/thrust values remain provisional. Widen arithmetic before narrowing to 16 bits and clamp movement to prevent overflow.

The editor has `EDITOR_CELL_PIXELS=16` in `left_renderer`, giving a 48 by 48 pixel grid. The mouse adapter uses the same 16-pixel cell layout; coordinate changes require updating both modules. Gameplay remains eight pixels per cell in the 24 by 24 grid, with occupied-cell cave terrain collision described below. The left renderer uses the user's rectangle and number helpers for construction inventory and runtime status.

## Ownership and connections

| Producer | Consumer | Signals or data |
| --- | --- | --- |
| Role 1 builder | Roles 2 and 4 | Surviving counts, `mass_units`, `build_valid`, `build_error`, `pig_alive` |
| Role 1 builder | Role 4 drawing | Five four-bit stock outputs: `frames_left`, `pigs_left`, `wheels_left`, `engines_left`, `balloons_left` |
| Role 1 builder | Role 3 outcomes and Role 4 drawing | `build_grid`, `intact_mask` locate surviving contents; drawing also receives `frame_intact_mask` |
| Role 1 builder | Role 3 cave terrain collision | `intact_mask \| frame_intact_mask` supplies `collision_mask`; surviving contents or frames occupy a cell |
| Role 1 builder | Shared construction/geometry consumers | `build_frames` is the saved frame layout |
| Role 1 input | Role 4 game control | Launch, retry, edit and guide requests |
| Role 1 balloon control | Role 4 game control | `pop_pending` connects to `gameplay_pending`; reserve idle clocks for queued actions before starting another step |
| Role 4 game control | Role 1 balloon control | `gameplay_ready` is high only in RUN with no outstanding movement/world update |
| Role 1 input/control | Role 2 | SW0 engine enable, SW2 engine reverse and a debounced BTNL `jump_press`; balloon popping updates Role 1's intact state |
| Role 4 | Role 1 | Game state and left-screen clickable layout |
| Role 4 level data | Roles 2 and 3 | Spawn, terrain, TNT, goal and hazard geometry; same source feeds drawing |
| Role 4 game control | Roles 1, 3 and drawing | Two-bit `level_index`, selected in LEVEL_SELECT or advanced after SUCCESS; two-bit `fail_reason` after FAIL |
| Role 2 | Role 3 collision | Previous/proposed movement with valid/ready handshake |
| Role 3 collision | Role 2 | Corrected movement and grounded flag with valid/ready handshake |
| Role 2 | Roles 3 and 4 | Committed position and `movement_committed` pulse |
| Role 3 TNT | Role 1 | Separate content/frame damage masks under one `damage_valid`/`damage_ready` handshake |
| Role 3 outcomes | Role 4 | `world_valid`, goal/hazard/out-of-bounds flags; hold until `world_ready` |
| Roles 2, 3 and 4 | Role 1 audio | Accepted action, TNT explosion and result events; connected in the top |

All same-clock user actions are one-clock pulses. Decode held buttons into single press/release actions so dragging does not repeat edits. Role 4 draws click targets and supplies their coordinates; Role 1 decodes them. Keep all clickable controls on the left OLED. The right OLED shows the map and vehicle movement; the left shows construction/inventory, then component status and controls during a run.

`mass_units` is the total mass of surviving occupied parts, not a second independently maintained build. Role 1 may derive it and the counts through `vehicle_status`; Role 2 alone turns those properties into movement. Do not count destroyed parts.

## Handshake rules

For each valid/ready channel, transfer occurs only on a rising clock edge where both are high. The producer asserts valid and holds the payload stable until transfer. The consumer processes each transfer exactly once. A consumer can assert ready before valid; neither side should wait for the other to assert first.

During BUILD, intact outputs reflect the saved content/frame layers directly. Separate runtime masks are restored for launch/retry. After a damage transfer, clear runtime content bits selected by `damage_mask` and frame bits selected by `damage_frame_mask`. Both masks share one transfer; either can be zero. Frame damage alone does not destroy the pig or engine inside it. Counts, mass and `pig_alive` reflect the cleared flags by the next cycle. The starter continues moving surviving parts as one body; support loss does not yet produce separate falling parts. The TNT controller must not announce a completed world update on the damage-transfer edge; allow at least the following cycle so Role 4 sees updated properties. Damage never refunds inventory. Combine simultaneous blast masks for each layer into one request.

`edit_valid` is a one-cycle action accepted only in BUILD, with `run_init` low. `LP_EDIT_PLACE` adds a frame only where content is empty, places/replaces a pig or engine only inside an existing frame, and places/replaces an external wheel or balloon only in a frameless cell with the required neighbouring frame. A wheel's supporting frame is at cell n-3, so the wheel cannot occupy the top row. A balloon's supporting frame is at n+3, so it cannot occupy the bottom row. `LP_EDIT_REMOVE` removes contents first; when contents are empty it removes the frame. It ignores `edit_part`.

Removing a frame can leave an external wheel/balloon unsupported. This temporary construction is permitted, but launch is blocked until support is restored or the external part is removed. Place with empty/reserved/unknown part IDs, unsupported actions, impossible placements, insufficient stock or cell indices 9 through 15 leaves both layers unchanged. `build_error=1` means the saved grid does not contain exactly one pig, 2 means invalid attachments/overlap and 3 means the saved build exceeds stock; zero means valid. Errors are prioritised in that order. Other states ignore edits.

The builder decides each edit once, then uses that result for both storage and temporary feedback. Three-bit `feedback_code` is 0=none, 1=placed, 2=removed, 3=no stock, 4=need frame, 5=frame above, 6=frame below and 7=cell occupied. Four-bit `feedback_cell` identifies the target. Occupancy/support checks precede stock checks. Same-part drops, already-present frames, empty-cell removals and invalid protocol payloads are quiet; they do not restart an existing message. A reportable result replaces the old message and restarts the 32-bit counter. Positive parameter `FEEDBACK_CYCLES` defaults to 100000000 for one second at 100 MHz. Expiry sets the code to zero; reset, run initialisation and leaving BUILD clear it. These fields cross the coherent display snapshot together.

The left view gives the target cell a green outline for placed/removed and a red outline for rejection. BUILD uses y=56 through 62 for a 5 by 7 text message, with one blank column between characters. The messages are PLACED, REMOVED, NO STOCK, NEED FRAME, FRAME ABOVE, FRAME BELOW and CELL OCCUPIED. With no temporary feedback it shows READY or the saved-build reason ADD PIG, CHECK SUPPORT or CHECK STOCK. Runtime indicators are unchanged. The drag icon and cursor overlay this feedback as before.

For Marcus's sprite integration, `left_renderer.draw_part_icon` supplies both inventory and drag-preview icons, while the construction-grid shapes and `right_renderer` vehicle graphics are drawn separately. Replace these temporary visuals with the final sprites; the existing feedback text/outlines can stay or be restyled. Preserve `drag_active`, three-bit `feedback_code`, four-bit `feedback_cell` and the snapshot wiring (now 170 bits, adding `level_index`, `fail_reason`, `tnt_intact`, saved `build_frames`, `run_seconds` and `blast_phase`). Keep feedback decisions and the timer in the builder. If grid/inventory positions or cell sizes change, update the matching hit regions in `mouse_adapter` together. Instructions and the two final levels remain Role 4's planned work.

`build_grid` and `build_frames` store the saved construction; their two intact masks describe runtime survivors. Damage changes only the masks. Retry and return to BUILD restore both layers of the edited construction; reset clears construction and restores all inventory. Both layers contribute independently to mass: frame=2, pig=2, wheel=1, engine=3, balloon=1. The simulation test vehicle has three frames, one pig, one engine and two wheels, for mass 13; it is not loaded by the hardware.

Inventory totals are parameters: `FRAME_LIMIT=5`, `PIG_LIMIT=1`, `WHEEL_LIMIT=4`, `ENGINE_LIMIT=1`, `BALLOON_LIMIT=2`. The top exposes the same parameters. Remaining counts are derived from the saved layers and start at the configured totals when the builder is empty. Counts clamp to zero for any saved build exceeding a configured limit, and such a build is invalid. A same-kind replacement is permitted at zero remaining stock because it reuses that item. Other replacements require available stock for the new kind, and update the grid only after checking; removing the old kind from the saved grid refunds it automatically. Damage/retry never changes stock. Runtime per-level inventory selection is not yet connected; parameters configure this first-map version.

## Mouse construction layout

The supplied `MouseCtl` remains unchanged. `mouse_adapter` configures x=0..95 and y=0..63, initially (24,24), and samples complete packets. Its `input_enabled` input blocks actions while the builder is hidden, while still tracking button releases. Hiding the view, leaving BUILD, reset or right-click cancels a held drag.

Grid bounds are x=[4,52), y=[4,52), with row-major 16-pixel cells. Inventory bounds are x=[56,92), y=[4,54), with five ten-pixel rows: frame, pig, wheel, engine and balloon. An inventory press selects a part and starts a placement. Clicking an inventory row also arms the next grid click for placement/replacement. Without that armed selection, pressing an occupied grid cell picks up its existing part; a frame carries its saved contents. Pressing an empty cell places the selected inventory part. Nothing is committed before release.

| Edit operation | Source and destination | Behaviour |
| --- | --- | --- |
| `LP_EDIT_PLACE=0` | `edit_cell` | Existing inventory/attachment checks and replacement refunds |
| `LP_EDIT_REMOVE=1` | `edit_cell` | Right-click: contents first, then empty frame |
| `LP_EDIT_MOVE=2` | `edit_source` to `edit_cell` | Atomic transfer; no stock charge. Occupied/unsupported targets reject the move |
| `LP_EDIT_RETURN=3` | `edit_source` | Drop on any inventory row; return part or frame-plus-contents and derive refunds |

`edit_source` is four bits; 0..8 name real cells and 9 means no picked-up source. Outside drops, same-cell releases and right-click cancellation preserve the original build. Wheels and balloons remain separate when a frame moves; the existing validation reports missing supports before launch. A source stays in saved construction until a successful move/return, so a rejected drop cannot lose it or duplicate stock. Runtime and retry storage use the resulting saved layout.

The snapshot is 170 bits. It carries `drag_active`, `drag_from_grid`, four-bit `drag_source`, three-bit `drag_contents`, the selected part and cursor together with the build. The left renderer hides a picked-up source and draws the carried frame/contents together. Its eight-pixel preview is centred at the cursor, with its top-left clamped to x=0..88 and y=0..56. Both cursor and preview are published from the same packet/frame snapshot; the cursor draws last. Inventory stock does not change while hovering or holding.

During RUN a fresh left press on a surviving balloon queues a pop; held/right clicks do not pop another cell. Mouse actions remain enabled only with the builder visible. Button engine, jump, retry and reset controls remain available in either view.

## Single-OLED play

SW15 down keeps the normal builder on JA and map on JB. SW15 up reuses the right renderer for the JA map and blanks JB. Both JA views reverse the pixel index as `6143 - left_pixel_index`, preserving its mounting correction. The switch is synchronised and the rendered selection changes only at a frame boundary. Builder input stays blocked until the builder view is visible again; stale holds/releases cannot place parts after a switch. The game and music continue while the view changes. No extra map renderer is instantiated.

## Levels

There are now four levels: two simple rectangle test maps (below) and two block-RAM maps traced from Bad Piggies screenshots: level 3, Cave Arch (478 by 291, shown twice as large as a 956 by 582 world, driving), and level 4, Cave Flight (890 by 213, a flying level from the bottom left up through cave tunnels to a ledge at the top right). `level_index` is two bits (`LP_LEVEL_BITS`); `level_data.map_id` picks the ROM. Level select and next-level cycle 1 to 4, then wrap to 1. The spawn and full movement/collision path use signed Q12.8 (20 bits), including TNT pose inputs, death effects and the display snapshot. The right OLED follows the vehicle with a camera: 1.5x with 12 by 12 sprites by default, 1x with 8 by 8 sprites when zoomed out (SW3 or mouse wheel). With SW4 up (free look) the camera ignores the vehicle and follows the mouse cursor instead: cursor x 0..95 and y 0..63 sweep the camera from one edge of the world to the other, so the whole map can be checked on the board before it is drivable. Zoom and free look change only at frame boundaries. The renderer registers each pixel beside its map read, so it has one clock of latency. Levels 3 and 4 use map-sized world bounds and flag-derived goals. Occupied-cell terrain collision, slope gravity and terrain-following rotation use the map ROM; complete playable cave routes remain unvalidated. The original plan is in [map_interface_proposal.md](map_interface_proposal.md).

`level_data` takes `level_index` (0 = level 1, 1 = level 2, 2 = Cave Arch, 3 = Cave Flight) and returns spawn, up to four terrain rectangles, the goal, up to `LP_MAX_TNT=4` TNT blocks and up to `LP_MAX_HAZARDS=2` hazard rectangles. TNT entries are 16-bit `{y[7:0], x[7:0]}` top-left corners of 8 by 8 blocks, packed entry 0 lowest in 64-bit `tnt_positions`, with `tnt_count` active. Hazards use the terrain rectangle packing in 64-bit `hazard_rects`, with `hazard_count` active. Unused entries are zero. Both layouts are provisional.

Level 1 keeps the flat baseline path (ground y=56 across the screen) with one TNT on a ledge above the path. Level 2 has a 16-pixel spiked pit, narrower than the 24-pixel vehicle, a TNT on the path at x=60 and one on a ledge. Both spawn at x=4, y=32 and share the goal at x=80.

`game_controller` owns `level_index`. A `level_next_req` pulse toggles it only in BUILD, and a launch on the same clock wins, so geometry cannot change during INIT_RUN, RUN or a result. `level_button` creates that pulse on a fresh left press inside the left OLED button at x=[82,95), y=[55,64), reading the same mouse coordinates as `mouse_adapter`; right-click suppresses simultaneous left selection, and the button lies outside the grid and inventory hit regions. On FAIL, `fail_reason` records 1=pig lost, 2=hazard, 3=out of bounds, in the same priority as the failure check; INIT_RUN and edit clear it. BTNU (edit) after SUCCESS returns to BUILD on the next level, wrapping from level 2 to level 1; after FAIL it keeps the level. `run_seconds` counts whole seconds of RUN (`TICKS_PER_SECOND=60` physics ticks), stops at 99, freezes on a result and clears in INIT_RUN. `launch_event`, `success_event` and `failure_event` are one-clock pulses wired as top-level nets for Role 1 audio; Role 4 does not schedule sounds.

The top passes `tnt_count`, `tnt_positions`, `hazard_count` and `hazard_rects` as wires for Role 3; `world_outcomes` does not read them yet and `hazard_hit` remains zero. `tnt_intact` (one bit per TNT, 1 = still present) is tied high until Role 3 drives it; the right renderer hides cleared blocks. `explosion_fx` turns each falling `tnt_intact` bit into a two-bit `blast_phase` (1 flash, 2 fireball, 3 smoke, each `PHASE_TICKS=8` physics ticks); run initialisation clears it. Explosions are drawing only. Both renderers draw parts from `part_sprites.vh`: 8 by 8 sprites at single size on the right OLED and double size in the 16-pixel editor cells, also used for inventory and drag icons. During RUN and results the left grid is a damage diagram: a dim red cross marks a destroyed frame or part, and survivors are drawn over it. The left status column shows the run timer, then surviving parts during RUN or "C RETRY" and "U NEXT"/"U EDIT" after a result.

Recorded solutions (`sim/role4_level_solutions_tb.v`): an explicitly constructed test vehicle with SW0 on clears level 1 and level 2 by driving right along y=56; on level 2 the 24-pixel body spans the 16-pixel pit. Recheck when Role 3 adds TNT and hazard checks.

The renderers use a second `level_data` instance indexed by the snapshot copy of `level_index`, so the drawn map always matches the drawn state.

## Integrated movement and controls

Kyle's engine captures mass, all part counts, engine/reverse and jump at `step_start`, then calculates forces on the following clock. Later property changes cannot alter a published request. Its sequential force/mass divider takes 16 calculation clocks; consumers and testbenches must wait for valid/ready handshakes, with no assumption of a one-clock or fixed three-clock movement calculation. Per-update horizontal thrust is `ENGINE_FORCE` per engine on the ground (`physics_engine` default 96, kept by the arithmetic benches; the game sets 320 in `My_Top_Module` so one engine pulls a 15-unit cart up about 40 degrees), reversed by SW2; wheel resistance is 10 per surviving wheel and cannot reverse a coasting body. Signed remainders accumulate small accelerations and are cleared on mass changes, clamping, collision correction and retry as appropriate.

Gravity adds 32 to vertical velocity. The provisional lift value was raised from 10 to 24 per balloon during integration: the maximum inventory of two balloons can now overcome gravity. One balloon slows a fall; two provide upward acceleration. A confirmed-ground jump sets vertical velocity to -512. `jump_pending` saves a grounded button pulse arriving between ticks or during arithmetic; it does not allow an airborne double jump. SW0 remains engine enable, SW1 remains mute, SW2 is reverse, BTNL is jump and BTNR remains the speaker test. The XDC only uncomments the existing SW2/BTNL pin assignments; it adds no divided-clock constraint.

The starter collision path now captures its proposal and terrain, checks up to four platforms in parallel, then selects the highest crossed surface over three clocks. Its valid/ready ports are unchanged, responses remain stable under backpressure, and downstream logic must wait for the handshake. This fixes a measured 100 MHz timing failure from evaluating all platforms in one clock. Wall and ceiling checks now run in the same staged path. Sideways checks use the previous vertical span so a small gravity proposal does not make a floor edge block driving. TNT uses a separate damage handshake before world outcomes.

## One movement update

1. Role 4 selects the level, freezes its geometry and enters INIT_RUN. Assert `run_init` throughout INIT_RUN. Each receiving module initialises once on entry, then holds `init_ready` high until `run_init` goes low. It must not initialise again on every clock while `run_init` is high. Role 1 restores intact parts, Role 2 loads spawn/clears velocity, and Role 3 rearms TNT.
2. Once all three ready bits are high, Role 4 enters RUN. On a physics tick while no update is outstanding, it pulses `step_start`. Role 2 samples vehicle properties on that clock, then calculates forces, velocity and position on separate following clocks before holding a movement request for Role 3. Consumers wait for `move_valid`; they must not assume the request appears immediately after `step_start`.
3. Role 3 accepts the request, calculates corrections and holds a response. Role 2 accepts it, commits position/velocity once and pulses `movement_committed`. Previous movement must remain available through the world checks.
4. Role 3 checks TNT, hazards and goal using the previous-to-committed path and agreed committed pose. It holds any damage request until Role 1 accepts it. It then waits for damage-derived properties to settle.
5. Role 3 raises `world_valid` with final flags, including all interactions, and holds them until Role 4 asserts `world_ready`. Role 4 evaluates pig death, hazard and out-of-bounds before goal success, then pulses `update_release` to Role 2. It may start another step only after releasing the previous one. Ignore physics ticks while busy rather than stacking updates.

`balloon_control` keeps a nine-bit pending mask. It accepts only cells 0 through 8 containing a surviving balloon, and coalesces repeated requests for that cell. While movement/world checks are busy, counts and mass remain unchanged. `game_controller` exposes `gameplay_ready` in RUN when idle and blocks `step_start` whenever `gameplay_pending` is high. The balloon module then asserts `pop_valid` for the idle clock and passes its pending content mask to the builder's damage inputs; the builder is always damage-ready in RUN. It clears the applied pending bits, preserving a different new click arriving on that same edge. Result states, run initialisation and reset clear the queue. Requests reaching the queue on a step-start edge wait until that update finishes. The next step after application samples the reduced balloon count and mass. A popped balloon clears only its content intact bit without refunding inventory or changing saved construction; retry and return to BUILD restore it.

The top combines valid balloon and TNT content masks with OR and forwards TNT frame masks. TNT holds each request until the builder accepts it; multiple touched TNT are processed before one `damage_complete` pulse starts world outcomes. A no-contact movement also produces completion. Queued player pops wait until that world update finishes. Engine toggles currently come directly from SW0 and are sampled by physics at `step_start`; they do not destroy the engine. Mouse boost requests are connected to the physics engine.

## Displays and audio

Role 4 uses two separate OLED driver instances and separate pixel buses. Render from coherent committed snapshots. If the driver and game logic use different clocks, transfer the snapshot using a proper handshake; synchronising each bit independently does not preserve a multi-bit state. Rendering must not block physics.

`sound_controller` receives seven event inputs, plus `busy` and `active_sound` from `sound_generator`. It outputs combinational `sound_start` and three-bit `sound_id`, captured by the generator together on the next clock edge. IDs in `game_defs.vh` are also priorities: 0=none, 1=BTNR test, 2=launch, 3=pop, 4=landing/collision, 5=explosion, 6=success, 7=failure. A higher ID interrupts a lower sound. Equal/lower requests while busy are discarded; there is no queue. Rising-edge detection prevents a held event repeating, and events are remembered while muted/cancelled so they cannot replay later.

The top connects accepted `launch_event`, `success_event` and `failure_event` from Role 4. Balloon audio uses `pop_valid && damage_ready && |pop_mask`, so rejected clicks do not sound. Landing uses an accepted collision response with `grounded`, a preceding airborne response and downward `proposed_vy >= 128` (0.5 pixel/update). Continuous rolling and gentle spawn contact stay silent. The TNT controller pulses `explosion_sound_event` for each actual explosion; its intact bits also drive the existing animation and display snapshot. Future wall/ceiling impacts can use the same collision event after agreeing the trigger with Role 3. Mouse selection, construction edits, invalid launch, BTNU and SW0 have no generic click effect.

The generator uses only the shared 100 MHz clock. `AUDIO_NOTE_CYCLES=8000000` is the 80 ms base duration; `AUDIO_FADE_CYCLES=50000` steps the amplitude from zero to eight and back over four milliseconds at each note boundary. Keep the shortest configured note and BTNR beep longer than 16 fade steps. The PWM carrier is 390.625 kHz with idle duty 128/256; tone amplitude stays within 120..136/256. Duty is held constant for a complete carrier frame. Mute/reset/run initialisation cancel playback; returning to BUILD also cancels any old result sound. Cancel does not reset the carrier or disable the amplifier. This smoothing addresses deliberate sound boundaries; stray hardware clicks still require a board check.

SW1 is synchronised into `audio_muted`. Pmod AMP2 pins are `JXADC[0]` PWM, `JXADC[1]=1` for lower gain, `JXADC[2]=0` unused, and `JXADC[3]=!reset && !audio_muted`. The amplifier stays enabled between sounds. `AUDIO_TONE_HALF_CYCLES=50000` and `AUDIO_BEEP_CYCLES=20000000` preserve the 1 kHz, 0.2-second BTNR test. See [audio setup](audio_setup.md) for profiles, manufacturer reference and board tests.

## First tests with neighbouring modules unfinished

Use testbench-only fixtures: a fixed valid nine-cell build for movement, an accept-all collision responder for arithmetic checks, scripted movement for collision tests, and fake outcome/audio events for game control and sound tests. Exercise held requests and delayed ready responses, not just immediate acceptance. Replace fixtures with the real module one boundary at a time.

## Background music

`bgm_player` outputs a signed four-bit sample with amplitude at most three. `sound_generator.bgm_sample` uses it when no sound effect is busy, through the existing PWM carrier. Effects retain amplitude eight and their existing priority order. The music pauses on `audio_busy || sound_start`, preserving note/tone counters and restarting its quiet fade when resumed. BUILD and RUN enable it, RUN selects 120 BPM instead of 96 BPM, and mute/result/reset/run initialisation stop/reset it. `ENABLE_BGM` and `BGM_UNIT_CYCLES` are top parameters; the separate effect tests disable music to isolate their silence checks. The 38-entry note/duration table is a single-voice octave adaptation of The Entertainer's opening strain from the public-domain Mutopia edition.

## Level-menu requests

`level_button.level_open_req` opens LEVEL_SELECT from BUILD. `ui_controller` sends one-cycle `level_select_req` with a two-bit `selected_level` (0 to 3), or `level_close_req` for Back. The game controller accepts these only in LEVEL_SELECT, returns to BUILD and preserves the construction. BTNU also cancels the selector. The existing `level_next_req` input remains available to game-control callers but is tied low in the hardware top; the map icon opens the menu instead of cycling. Selector state uses the existing three-bit snapshot field, so no snapshot expansion is needed. The right renderer receives BUILD while this menu is shown, keeping the selected map's spawn preview.

## Current gameplay menu and facing interface

The latest Role 1 menu/construction contract is described in [gameplay_menu.md](gameplay_menu.md). `vehicle_builder.build_facing_left[8:0]` is saved construction state (1=left, 0=right) for engines and rockets. `edit_facing_left` is sampled with an accepted PLACE; MOVE copies the source bit. The builder exposes signed five-bit `engine_balance` (surviving right engines minus left engines), total `engine_count`, `rocket_count`, `fan_count`, and remaining rocket/fan stock. Both new parts occupy an unframed cell beside a frame, with no horizontal row wrap. Default new inventory is one rocket and one fan. Fans and rockets each provisionally add two mass units.

The shared top passes the magnitude of `engine_balance` to the existing physics engine count and XORs its sign with the SW2 reverse input; the saved facing bits do not change when SW2 toggles. Kyle's force/division/handshake logic is unchanged. Fan/rocket thrust remains unconnected: keep their UI availability/readiness low until physics consumes `ui_fan_on` and the one-clock `ui_rocket_req`.

The left RUN menu uses `run_page` 0=DRIVE, 1=POP, 2=SOUND. `mouse_adapter` sends balloon requests only on POP. `ui_controller` owns DRIVE boost requests. Retry/edit are accepted during RUN through the existing INIT_RUN/BUILD paths; board C/U remain shortcuts. Each new run restores parts, selects DRIVE and resets engine/fan controls, while volume survives. The display snapshot is now 237 bits and includes facing, selected direction, inventory/menu pages, new stock values and mute state.

### Cave bounds and goals

`world_outcomes` receives `world_width`, `world_height`, `map_level`, and 10-bit `flag_x`/`flag_y` directly from the live `level_data` instance. Bounds use the 24 by 24 vehicle footprint: failure occurs when its left/top reaches the world right/bottom, or its right/bottom reaches zero. Partial overlap remains in bounds. Numeric saturation in physics is independent of gameplay bounds.

Rectangle levels retain their packed `goal_rect`. Cave goals use pig-centre entry into `[flag_x, flag_x+16)` by `[flag_y-10, flag_y+14)`, aligned to the 14-pixel pole and its supporting surface. Cave Arch uses `[300,316)` by `[219,243)`; Cave Flight uses `[769,785)` by `[40,64)`. A destroyed/missing pig cannot trigger a goal. World checks still follow TNT completion and hold results under backpressure. `cave_coordinates_tb` checks wide spawns and the physics/collision/world path; `world_outcomes_tb` checks exact cave goal/world edges. `cave_map_integration_tb` verifies the connected hardware top reaches SUCCESS at both cave goals, reports the bounds failure reason, and transfers distant vehicle coordinates to the display.

### Terrain-following rotation

`physics_engine.vehicle_tilt` is the committed signed `LP_TILT_BITS` (5-bit) orientation. Indices -16..15 cover the full turn in 11.25-degree increments (-16 is 180 degrees, upside down); positive is clockwise because screen y increases downward. Grounded responses provide the next slope target through `slope_to_tilt` (Q4.4 magnitude thresholds 2, 5, 9, 14). Each proposed movement changes at most one angle index. The collision response supplies `corrected_tilt` along with position, velocity and ground contact, so a blocked turn can retain the old safe angle. `previous_tilt` and `proposed_tilt` are captured and held with the request. Jumping and airborne motion preserve the launch angle; reset/retry clears it. Flat ground gradually returns the vehicle level (or level upside down, when it rests on its top). Edge tipping and flips are described under "Loop physics" below.

The hardware top sets `collision_engine.ROTATION_ONLY=1` to remove the unused upright checker and enables `rotation_enabled` for caves, selecting `rotating_map_collision_engine`; rectangle levels keep their existing response and angle 0. Leaving rotation disabled selects the upright reference checker for existing geometry/arithmetic benches. The top passes `collision_mask = intact_mask | frame_intact_mask`. The rotated checker captures this nine-bit mask with the accepted movement request, alongside previous/proposed poses and angles; later mask changes cannot alter an in-flight scan. A set bit occupies the corresponding complete 8 by 8 grid cell, whether it has surviving contents, a surviving frame, or both. Unconnected mask inputs default to all nine cells (`9'h1ff`) for legacy callers; a zero mask cannot contact or gain support from terrain.

The rotated checker sweeps one-pixel axis substeps and tests intersecting terrain pixel areas against the union of occupied cells at all 32 tilt indices (-16..15). Each occupied cell uses all four separating axes, including world x/y, with the quantized rotation's squared norm accounted for exactly. Empty cells contribute no terrain geometry. The pivot remains (x+12,y+12), including after damage; the body is not recentered around surviving parts. Floor/wall/ceiling collisions refine the last clear position to 1/256 pixel instead of applying an upright edge offset. Turns check the proposed occupied-cell body and may recover upward by 3 pixels; a turn blocked by nearby terrain retains its prior safe orientation. Ground following is 3 pixels, with an additional 3 pixels on an accepted turn to compensate for corner displacement. Large drops remain airborne. Query arithmetic and masks are staged beside registered ROM reads; all query/result state is captured and reset through the same movement handshake. Rectangle-level collision, world bounds, hazards and TNT swept triggers retain their existing outer envelopes.

`rotation_geometry.vh` shares quantized sine/cosine and inverse-raster bounding extents. The extent table [3072,3614,4006,4261,4345] in Q12.8 accounts for the coefficients' slightly non-unit norm, preventing fractional corner penetration or false support. The renderer inverse-maps the entire vehicle about its centre at all four zoom scales, including facing, damage masks and frame borders. Zero tilt preserves the old raster exactly. The four-bit angle is appended to the existing coherent display snapshot (259 bits total), so pose and angle publish together at frame boundaries. The builder/status grid stays upright for editing.

`world_outcomes` rotates the pig centre for goals and uses the rotated hull for world bounds and hazard overlap. `pig_death_effect` records the rotated pig location. TNT captures current/previous orientation, conservatively sweeps their bounding hulls to avoid missed triggers, and computes blast damage using rotated part centres. Its swept trigger may include empty corners, as in the prior conservative rectangle sweep. These modules consume committed angle and pose; no display state feeds physics. World checks now capture the committed pose and stage bounds/pig coordinates, shared hazard projections, sums and comparisons across clocks. TNT registers swept bounds before trigger comparisons and part coordinates before blast distances. Consumers must wait for `world_valid` and `damage_complete`, rather than assume one-clock results. Reset/retry cancels pending work; accepted results remain stable under backpressure.

### Cave terrain collision

`collision_engine` captures `map_level` with each request and holds that route until its response is accepted. It selects the original `rectangle_collision_engine` for levels 1/2 and the rotated occupied-cell path above for live cave movement. The upright reference `map_collision_engine` remains in `collision_engine.v` for callers that disable rotation. Map requests capture world size, previous/proposed pose, velocity and collision occupancy. The map query interface is signed 11-bit whole-pixel `query_x`/`query_y`. The hardware top consumes the registered `query_solid` bit and maps it to representative ROCK/SKY classes for the collision checker. `level_map` also retains the full registered 3-bit `query_class` output for clients needing exact classes; that output is unconnected and optimized away in the top. One-bit collision ROMs load explicit `cave_arch_solid.mem` and `cave_flight_solid.mem` assets generated alongside the colour maps. Both map generator scripts rebuild the colour and collision assets together. The collision memories use explicit packed one-bit words (`reg [0:0]`), so Vivado can initialize them reliably. `level_map.query_map_id` comes from live level data, independently of the draw port's snapshot-based `map_id`. Collision converts signed Q12.8 positions using arithmetic shifts; it rejects out-of-map query coordinates before narrowing to 11 bits.

The legacy `map_collision_engine` (used by upright reference benches) scans the complete upright 24 by 24 footprint (including fractional edge pixels), resolving horizontal then vertical motion in at most one-pixel substeps. Each scan holds its ROM address for ISSUE, then consumes the registered class in SAMPLE. Movement requests and result responses use the existing valid/ready contract; all corrected outputs remain stable while stalled. Collision is reset on run initialization and outside RUN, cancelling pending reads during retry/edit/reset.

A support probe at the previous pose enables up to three pixels of step-up and three pixels of downward ground following. Every raised/snapped candidate must clear terrain for the collision body: occupied cells in the live cave path, or the complete grid in the upright reference path. Upward movement disables both features; large drops leave the body airborne. Walls and ceilings cancel only the affected velocity component. Small initial penetration can recover upward by up to three pixels; deeper invalid placements remain at their previous pose with zero velocity. This is a fallback for malformed placements, not a route through terrain.

`collision_engine.ground_slope` accompanies the accepted response as signed 8-bit Q4.4 `dy/dx`: positive slopes descend to the right, negative slopes to the left, and zero is flat. Rectangle levels and airborne responses return zero. For grounded cave poses, two exposed-floor probes four pixels either side of the support contact estimate the slope over eight pixels, within a vertical window of eight pixels above/below contact. Missing floors, out-of-map probes, solid window tops, gradients steeper than 1:1, and a fitted midpoint more than one pixel from the actual contact return zero. The midpoint check prevents isolated Flight-map bumps from inventing a downhill force. Slope is measured even at rest and held with the rest of the response under backpressure.

`physics_engine` caches only an accepted grounded slope, samples it with each update, and clears contact on reset/retry/leaving RUN. With slope `s`, horizontal acceleration is approximately `max(32 - 24*balloons, 0) * s / (1+s*s)`. A small coefficient table and staged products avoid another divider; the acceleration magnitude is rounded down symmetrically, converted to force using captured mass, and combined with engine force before the existing friction and force/mass divider. Wheel friction can hold a shallow slope, downhill coasting accelerates, and uphill momentum slows/reverses. Jumps and net upward balloon lift suppress slope gravity. A 1:1 ramp adds 16 velocity units per update without balloons, or 4 with one balloon. Flat-map arithmetic and speed caps are unchanged. The live cave path additionally rotates the body as described below. It does not carry vertical tangent velocity off a ledge.

All outside-map pixels are open to collision, even though the ROM returns underground below the map for drawing. `world_outcomes` continues to own whole-body bounds failure. There is no extra invisible floor at map height. Terrain classes SKY/CAVE are open; ROCK/GRASS/ROAD/DARK are solid, except Cave Arch's decorative grass (below), which is drawn but open. Physics speed caps remain one pixel horizontally and two pixels vertically per update; the sequential scans fit comfortably within the normal 60 Hz update budget.

Earlier whole-grid collision analysis found no clear full 24 by 24 body pose that put a pig-cell centre inside Cave Arch's finish zone. Occupied-cell terrain collision now removes that empty-cell clearance limitation for sparse builds. A complete playable cave solution with the current collision has not yet been validated; the existing teleported goal-wiring test is not a playable level solution. `map_collision_tb` and `map_rom_collision_tb` exercise the reference collision rules and actual terrain separately from that goal fixture.

Validation on 28 October 2026: both new terrain benches and the connected cave bench pass. The synthetic bench covers 28 geometry/handshake cases; real-map checks verify full-body clearance, actual spawn floors, a Flight goal ledge and independent draw/query selection. Across the 39-bench regression set, 35 pass. `vehicle_builder_tb`, `balloon_controls_tb`, `role4_game_display_tb` and `timer_death_tb` fail with the same messages on the unchanged saved baseline. Design-only synthesis passes with no unresolved black boxes: 17,327 LUTs (83.30%) and 38.5 block RAM tiles (77%). No routed timing check, bitstream generation or board test was performed for this change.

Slope-force validation on 28 October 2026: `physics_slope_tb` passes 36 force/contact cases, `map_slope_tb` passes 20 geometry/handshake cases, and `slope_map_integration_tb` passes 46 connected updates against the actual ROMs. The connected bench verifies engine-free Arch downhill rolling, powered uphill travel, complete footprint clearance, stationary Flight ledge rejection and balloon detachment; its longest update is 6,048 clocks (60.48 microseconds at 100 MHz). Across 42 benches, 38 pass; the same four baseline failures listed above recur with identical messages. Synthesis passes with no black boxes or inferred latches: 17,607 LUTs (84.65%), 3,411 registers, 38.5 block RAM tiles and 34 DSPs. The post-synthesis timing estimate fails overall (worst setup slack -13.609 ns, mouse `ypos` to adapter `selected_part`); the separate post-synthesis estimates for paths launched by physics and map collision have positive setup slack (+1.627 ns and +1.860 ns respectively), while the rectangle collision path also has a -0.607 ns estimate. These are not routed timing signoff. No bitstream or board test was produced. Reports are under `tmp/slope_synthesis/`; combined simulation results are in `tmp/slope_test_summary.json`.

Rotation validation on 29 October 2026: `vehicle_rotation_renderer_tb` passes 52 complete rasters (319,488 pixels), `rotating_collision_tb` passes 30 independent separating-axis geometry/handshake cases, and `rotation_map_integration_tb` passes 35 real-map movement updates including slope settling, jump attitude, retry and Flight balloon ascent. `rotation_interactions_tb` passes 20 rotated goal/hazard/bounds/death/TNT cases; `vehicle_rotation_top_tb` verifies natural map-driven tilt and frame-coherent pose/angle publication in the connected hardware top. The longest geometry request is 82,065 clocks (0.821 ms at 100 MHz), below the 60 Hz movement budget.

Final rotation synthesis passes with no black boxes or inferred latches: 19,531 LUTs (93.90%),4,054 registers,38.5 block RAM tiles and42 DSPs. Staging projection arithmetic and sharing hazard hardware resolve the new long paths; removing the unused upright checker with `ROTATION_ONLY` avoids carrying two map colliders in hardware. Post-synthesis setup estimates for paths launched by physics and rotated map collision are +1.627 ns and +0.870 ns. Full-design timing still fails overall (worst setup slack -13.610 ns in the mouse input path), so these estimates are not routed timing signoff. No bitstream or board test was produced. Reports are under `tmp/rotation_synthesis/`.

Before the fixture repairs below, the rotation regression covered 47 benches: 43 passed. `vehicle_builder_tb`, `balloon_controls_tb`, `role4_game_display_tb` and `timer_death_tb` reproduce the same four earlier baseline failure messages; no new failures were introduced. World/TNT test waits now follow valid/completion handshakes after pipelining. Post-synthesis paths launched by world/TNT/death logic also meet the 10 ns estimate (worst setup slack +1.443 ns). Combined results and baseline failure comparisons are in `tmp/rotation_test_summary.json`.

Regression fixture repairs on 29 October 2026: all 47 simulation benches now pass through `scripts/run_simulations.ps1`. The four earlier failures came from stale test fixtures, not faults in the surviving-part, button or timer logic. `vehicle_builder_tb` and `balloon_controls_tb` now use the compact RUN diagram at (4,12) with 12-pixel cells, retain BUILD's 16-pixel layout, connect deterministic renderer inputs, and explicitly check surviving content/frame masks. `role4_game_display_tb` derives button-edge cases from the current shared hitbox, checks all edges plus held/right/hidden/SETTINGS input, and uses the current text/sprite positions. Its timer fixtures and `timer_death_tb` now match the full 8-bit interface; the timer scans known values 0, 9, 59, 60, 99, 127, 128 and 255 seconds with active-low digit/decimal checks. Gameplay RTL was unchanged for these repairs, so no new synthesis or bitstream was needed. Full log: `tmp/fixture_repairs_full_regression.log`; summary: `tmp/fixture_repairs_test_summary.json`.

Hardware collision-ROM repair (29 October 2026): post-synthesis inspection of the board build revealed that the derived scalar solidity memories did not preserve the RTL contents. The Flight in-map collision output was constant open. An exhaustive old-versus-fixed synthesized-ROM test reproduced 139,362 mismatched pixels, including 7,356 cave-background pixels incorrectly blocked and 93,991 Flight terrain pixels missing collision. Explicit packed one-bit ROM files now match all 328,668 in-map class pixels, including 43,326 open cave-background pixels and 3,306 solid grass pixels. The colour assets and spawn coordinates were unchanged. Run `scripts/check_map_solidity.ps1` for exhaustive post-synthesis verification; `map_solidity_tb` is also included in the ordinary RTL regression. Bitstreams from before this repair retain the faulty collision memory and need a fresh synthesis/implementation/bitstream.

Collision-ROM repair validation: all 48 RTL benches pass; `scripts/check_map_solidity.ps1` also passes exhaustive simulation of the synthesized ROM at all 328,668 map pixels. Both generators were rerun and reproduced identical colour-map and solidity words. The corrected full design passes synthesis with 19,541 LUTs (93.95%) and 48.5 block-RAM tiles (97%); the rotated collision path retains +0.870 ns post-synthesis setup slack. Existing mouse timing limitations remain. No new bitstream or board test was performed for this repair. Results: `tmp/map_solidity_fix_summary.json`. A later audit confirmed that the user's 15:10:47 bitstream already contains the repaired collision ROM. The bush and occupied-cell changes below still need a fresh synthesis, implementation and bitstream.

Occupied-cell cave repair (29 October 2026): the photographed green obstruction is an isolated 53-pixel GRASS patch at x=225..231, y=92..100 in Cave Arch's first valley. The generator replaced only those GRASS pixels with open CAVE background (superseded by the decorative grass rule below, which keeps the bush drawn but open); all other colour and solidity words, including the real grass road at y=117..124, are preserved. The live terrain checker uses the captured surviving-cell mask above, preventing the empty top row from hitting the nearby rock roof. Dark green CAVE background remains open under the explicit collision-ROM fix.

Cave Arch decorative grass (29 October 2026): bushes, tufts and floating or hanging grass blobs blocked or snagged the cart although they are scenery. `scripts/build_cave_arch_map.ps1` now leaves them out of `cave_arch_solid.mem` with one rule applied to every pixel; no area of the map is special-cased. (1) An 8-connected grass patch that touches no ROCK, ROAD or DARK is floating scenery and is open. (2) In a patch that touches ground, a vertical GRASS run of up to 5 pixels is the ground skin or a thin bridge and stays solid. (3) A taller run sitting on ground keeps its bottom 2 pixels, so a bush leaves the same skin as the grass around it; a taller run over open space (hanging) keeps nothing. (4) GRASS with ground within 2 pixels to the left or right is wall grass and stays solid. This replaces the hand-picked removal of the 53-pixel valley bush at x=225..231, y=92..100: that bush is drawn again and is open under rule 1. 620 of Cave Arch's 3,306 grass pixels are open: the bushes on the start hill, the arch top and the right plateau, the valley bush, the hanging blob at the right edge and the two blobs beside the finish flag. Small bumps on real ground, such as the lip where the start hill meets the grass road at (203,117), stay solid. `map_solidity_tb` carries an independent copy of the rule and checks it at every pixel. Cave Flight is unchanged.

Loop physics (29 October 2026): the vehicle can tip, tumble and drive upside down, so a build with wheels on both sides keeps moving whichever way up it lands (the Cave Arch route through the arch). Tilt is 5 bits (`LP_TILT_BITS`) and `rotation_geometry.vh` folds every angle into one quarter-turn table (`quarter_cos`, r=0..8), so the -4..4 values, extents and norms are unchanged; `tilt_flipped` is true beyond a quarter turn. `rotating_map_collision_engine` scans the support row of a grounded body (`SPAN`) and outputs `tip_dir`: +1 or -1 when every support contact lies on one side of the body centre and the slope probe did not find even ground both sides (an edge), else 0. `physics_engine` turns `tip_dir` into angular velocity (`TIP_ACCEL`, capped at `MAX_SPIN`, in 1/16 tilt steps per update); spin carries through the air until a turn is blocked, and settled ground returns to the slope angle the right way up. `vehicle_builder` reports `wheels_down` (an intact wheel under a frame) and `wheels_up` (above a frame); the side facing the ground gives grip and engine drive, and a side with no wheels scrapes (`scrape_drag`) and cannot drive. Builds with neither pattern (no wheel sides reported) keep the old wheel count and zero-wheel friction. `WHEEL_LIMIT` is 4 so a cart can carry wheels on both sides. Cave Arch is shown at 2x (`level_map` reads map pixel world/2, no extra block RAM) because its arch passage under the left leg is about 20 map pixels tall, too tight for the 24-pixel body once it pitches up the ramp; spawn is (208,76) and the flag (600,472). Raw-map asset benches instantiate `level_map #(.ARCH_SCALED(0))`. `flip_physics_tb` checks the 32-angle tables, flipped drive, wheel-less scraping, level rest, settling and edge tipping; `cave_arch_drive_tb` drives a two-sided cart (wheels in cells 0, 2, 6, 8, engine on) from spawn to the flag with the real map, physics and collision and no hand placement. Its driver acts like a player with one map-independent rule: engine on, and press reverse after 4 seconds without new progress in the current direction. The route needs that, because from the arch chute the way on is left through the lower cave, down a hole into the bottom corridor and right to the flag. Trace correction: smoothing had joined a rock horn to the upper end of the grass ramp under the arch (map x=205..222, y=153..167), closing the passage into the lower cave to 10 map pixels; `build_cave_arch_map.ps1` turns rock left of the ramp's grass edge in those rows into sky, for drawing and collision alike. With it, a 13-map-pixel (26 world pixel) box can travel from spawn to the flag.

Smooth motion (30 October 2026): at 2x every map pixel is a 2 by 2 block, so slopes are 2-pixel stairs, and the slope probe reads a different gradient (or none) from update to update. Two fixes, measured on the full Cave Arch drive: (1) `physics_engine` only settles toward a tilt target that has held for three grounded updates in a row (`held_target`, `held_count`), cutting back-and-forth tilt flicker from 162 to 6 events; (2) `physics_engine.display_y` is an alpha-beta filter of `vehicle_y` (a quarter of the error to the position, a sixteenth to its speed; errors over 12 pixels snap), and the display snapshot carries it in place of `vehicle_y`, so the drawn cart and camera glide over the stairs: drawn vertical jolts over 1 pixel fell from 242 to about 1, with a typical lag of 2 pixels. Collision, goals, hazards and TNT still use `vehicle_y`. Grass was not the cause (road jolted as often), so the decorative grass rule is unchanged. `cave_arch_drive_tb +trace` logs every update for these measurements.

Terrain smoothing (30 October 2026): the traced Cave Arch map had ragged floors, most visibly the bottom corridor's road (cave-background holes 2-3 map pixels deep and loose lumps), which at 2x became 4-6 pixel jolts. `build_cave_arch_map.ps1` now runs `Classify.SmoothTerrain` on the whole map after the decorative grass rule: twice, every floor top (solid with 4 solid pixels below, open above) moves to the median height of the floor tops within 4 columns either side, then a radius-3 closing fills notches and a radius-2 opening removes spikes; decorative grass stays open. Pixels whose solidity changes are recoloured from their original neighbours, so drawing and collision keep the same shape (1,631 pixels change; corridor height jumps of 2 or more map pixels fall from 16 to 2). `map_solidity_tb` now checks that agreement for Cave Arch (solid pixels are drawn rock/grass/road/underground, rock/road/underground are always solid, open grass is decoration) instead of re-deriving the rule; Cave Flight keeps the exact class check.

Steep slopes and tipping (30 October 2026): the rotating collision engine's slope probes look 12 pixels up and down and accept a rise of up to 12 over 8 pixels (reported as at most the 45-degree gradient), so a 45-degree slope drawn as 2x stairs reads as even ground instead of an edge. `physics_engine` stops adding tip spin to a grounded body that is already three steps past the ground's angle in the tip direction and lets it settle back (`tip_overdone`); before, the body could roll over on the start hill while sitting on it. Edges still tip the body up to three steps; airborne spin is unchanged. These two changes went to the board build of 30 October without a full simulation run.

Occupied-cell validation: all 49 simulation benches pass across the pipelined regression and isolated reruns. `occupied_map_collision_tb` passes 25 cases: actual-ROM movement through the removed bush at (201,93) to (202,93), roof clearance from (215,96) to (216,96) with a sparse car mask, independent four-axis occupied-cell geometry at all nine tilts, all four corner cells at both 45-degree angles, full-mask legacy contact, zero-mask falling, occupied floor/wall/ceiling contact, request capture and response backpressure. Its longest request is 410,151 clocks (4.102 ms at 100 MHz), including a 40-pixel stress sweep beyond the normal movement cap. The initial 17 normal fixtures peak at 136,364 clocks (1.364 ms). Earlier synthesis and bitstream figures above describe the earlier design; a fresh hardware build and board validation remain pending for this geometry change.

`vehicle_rotation_top_tb` previously waited 32 clocks after seeing physics idle before writing its slope pose. An update could capture the old spawn during that gap and later overwrite the fixture, causing the short cycle budget to expire with tilt and slope zero. The display wait now precedes the idle wait, and the fixture is written immediately while idle. Settling is bounded by 40 completed movement updates plus a global watchdog; the exact 45-degree, coherent pose/angle transfer, renderer and reset assertions are retained. The diagnostic trace reaches slope 16 then tilt 0, 1, 2, 3, 4 in five completed fixture updates; the actual bench passes at 8,727,540 ns. Logs: `tmp/occupied_pipelined_regression.log`, `tmp/occupied_pipelined_regression_remaining.log` and `tmp/rotation_top_latency/final_actual.log`.


## Fan, rocket and spring physics (2026-10-31)

The existing fan and rocket build items now drive physics through signed five-bit
`fan_balance` and `rocket_balance`: surviving right-facing parts minus surviving
left-facing parts. The builder computes them alongside `engine_balance`; damage
removes their contributions and retry restores saved directions. Opposing parts
cancel. Frame damage alone follows the existing independent content-mask rules.

`physics_engine.fan_enabled` connects to the existing runtime FAN ON/OFF control.
Each enabled intact fan supplies horizontal force 64, even airborne and without
wheels, with its legacy facing balance negated to correct the fan direction.
The game now supplies rocket force 1024 (`ROCKET_FORCE_SHIFT=10`); the standalone
physics default remains 512 (`ROCKET_FORCE_SHIFT=9`) for the legacy arithmetic
benches. The selected rocket axes are body-relative. Constant shifts and bounded serial additions
produce these forces, which are staged into the existing force/friction/mass
pipeline. They share the serial mass divider and existing velocity limits.
Rocket thrust rotates with the body: world `Fx = cos*Fx_body - sin*Fy_body`,
`Fy = sin*Fx_body + cos*Fy_body`. The accepted tilt is sampled once per movement.
A side-mounted rocket therefore produces vertical force when its sprite points
up or down, even while the future vertical-placement inputs are zero. Fan thrust
and wheel drive retain their existing world-horizontal convention.
`rocket_balance` supplies the horizontal signed rocket count (right minus left).
The new signed five-bit `rocket_vertical_balance` supplies down minus up, with
positive Y downward. It defaults to zero when unconnected. The current editor,
builder and top-level placement wiring are unchanged by this follow-up: future
placement logic must connect this input and exclude vertical rockets from the
horizontal balance. `rocket_count` must count intact rockets on both axes.
Vertical force uses a second transaction through the same serial mass divider,
then adds the acceleration to gravity/balloon lift or the spring launch velocity.
A separate vertical force remainder retains fractional acceleration. Collision
correction, mass changes, and velocity saturation discard inappropriate carry.
The existing vertical speed limit remains +/-512. Both axes share the existing
90-update rocket burn, readiness, sampling and retry behavior.

`rocket_req` captures the existing ROCKET FIRE pulse between movement updates.
`rocket_ready` requires RUN, an intact rocket and an unused burn. A request starts
a shared 90-update burn (about 1.5 seconds at the default 60 Hz). A request on the
same edge as `step_start` takes effect on the following update. Seven-bit
`rocket_fuel` decreases once per accepted step start; idle clocks, stalled requests
and delayed responses do not consume extra fuel. The final tick still contributes
thrust. Requests during or after the burn cannot refill it; reset, retry or leaving
RUN clears it. `rocket_active` also requires a surviving rocket. Counts/balances
are sampled once per movement, so damage takes effect on the next movement.
FAN availability/on and ROCKET availability/readiness cross the coherent OLED
snapshot, enabling the prepared runtime controls and labels.

As requested, the existing `jump_press` port and button are retained as the spring
trigger until a spring item is added. On confirmed ground contact, the queued
trigger sets vertical velocity to `-SPRING_IMPULSE` (512 in Q8.8, two pixels per
update upward). This uses the previous jump impulse logic, with no Hooke-law
calculation. A one-bit `spring_fired` latch blocks another impulse throughout the
same continuous ground contact; an accepted airborne response rearms it. Airborne
presses are ignored; late grounded presses are queued for the next update.
Reset/retry clears pending triggers and the latch. There is no spring part ID,
contacting-cell decoder, wall bounce, or new spring-contact port yet; the future
item can supply this trigger once its contact detection exists.

`air_propulsion_tb` covers signed forces, sampling/backpressure, trigger capture,
full fuel duration, expiry, damage, retry and combined engine/fan/rocket force.
`physics_jump_tb` also checks spring contact lockout and rearming.


Initial horizontal-thrust synthesis validation (before the vertical-input follow-up)
for `xc7a35tcpg236-1`, using the same Vivado 2025.2 flow
on a saved pre-change source snapshot and the updated sources:

| Resource | Before | After | Change |
| --- | ---: | ---: | ---: |
| Slice LUTs | 17,177 (82.58%) | 17,433 (83.81%) | +256 |
| Registers | 3,605 | 3,651 | +46 |
| DSPs | 23 | 23 | 0 |
| Block RAM tiles | 48.5 | 48.5 | 0 |

These are synthesized counts, before implementation optimizations, so compare
them to each other rather than a previous placed/routed utilization number.
No unresolved black boxes remain. All design Verilog sources also compile with
`xvlog` without `--sv`. Pre-route setup slack is -1.040 ns (before: -1.266 ns);
this check does not establish 100 MHz timing closure. Full placement/routing and
board testing are still required before hardware sign-off. Reports are in
`tmp/thrust_before/` and `tmp/thrust_after/`.


Initial horizontal-thrust regression result: 51 of 52 benches pass, including the added `air_propulsion_tb`
and extended spring/direction/damage checks. `occupied_map_collision_tb` fails
at its roof-fixture assertion (line 159): "Photographed empty-roof
fixture lost its geometry". The identical failure at 255770 ns was reproduced
using the saved, untouched pre-change collision/map sources and ROMs. The test
checks terrain geometry independently of physics. No map or collision changes
were made to mask this existing failure. Logs: `tmp/thrust_regression.log`,
`tmp/thrust_remaining.log`, and `tmp/thrust_fixture_baseline/baseline.log`.


The physics-only directional follow-up passes eight regression benches:
`air_propulsion_tb`, `physics_engine_tb`, `physics_friction_tb`,
`physics_slope_tb`, `physics_jump_tb`, `team_controls_tb`,
`directional_parts_tb` and `rotation_map_integration_tb`.
The extended propulsion bench tests corrected fan force, upward/downward rockets,
simultaneous axes, vertical mass division, retained fractional acceleration and
vertical saturation. Verilog compilation also passes without `--sv`.
Follow-up logs: `tmp/direction_physics.log` and
`tmp/directional_physics_synthesis/`.

Standalone synthesis of the follow-up physics engine, with both force axes live,
uses 1,063 LUTs and 779 flip-flops, zero block RAM, and the same two existing DSP
blocks. There is one `signed_divider16` instance, shared between both axes.
This standalone count is not a whole-game utilization figure. Pre-route setup
slack is -1.184 ns; 100 MHz timing closure is still outstanding.


## Rigid-body moments (2026-10-31)

`My_Top_Module.ENABLE_MOMENTS` defaults to 1. It enables the new
`vehicle_moments` calculation in physics; 0 retains the previous turning model.
This is read-only use of the saved grid and survivor masks. Construction rules,
mouse editing, sprites and inventory are unchanged.

Frames and surviving contents are point masses at cell centres, with the same
mass values as `vehicle_builder`. Relative to the grid centre, the three rows
and columns have coordinates -8, 0 and +8 pixels. The mass centre is
`COM = sum(mass * position) / sum(mass)`, represented in quarter pixels and
rounded toward zero. A serial divider calculates both coordinates. Reset/retry
cancels an unfinished calculation; every movement snapshots its part geometry,
orientation, active actuators and survivor masks once, so later damage affects
the following movement.

For each enabled, surviving fan/rocket, the force starts at its own cell centre.
Moment arms subtract the calculated COM. Fan/wheel arms rotate through the
accepted vehicle tilt using the existing Q8 sine/cosine table. Rocket force and
its arm rotate together, so their torque is calculated directly in body
coordinates using the invariant cross product. The calculation is
`torque = rx*Fy - ry*Fx`, with positive torque clockwise because screen Y points
down. Fans keep the corrected facing sign. Rockets share the existing burn and
readiness; horizontal and vertical rocket axes are now body-relative and their net force
is rotated into world coordinates for translation. Two opposing forces can produce a couple even when their net
translational force is zero. Force through COM produces no moment.

Engine drive and wheel resistance act at grounded wheel contacts, not at engine
cells. Only the currently supporting wheel side receives traction. Eligibility uses the
existing frame-attachment side and body-grounded convention, rather than a
separate terrain query for each tyre. Total drive
plus wheel drag is divided equally among those wheels, distributing any integer
remainder across contacts so no force is lost. The contact is four pixels beyond
the wheel's cell centre on its ground-facing side. Airborne wheels have no
traction. The game now sets `WHEEL_TORQUE_SHIFT=2`, applying one quarter of the
raw wheel-to-body torque as a conservative approximation of unresolved tyre and
ground reactions. Linear drive/braking force is unchanged. This tuning is not a
claim of exact suspension dynamics; 0 restores the unscaled wheel moment. With moments enabled, engine drive also requires contacting wheels;
legacy arithmetic mode retains its former fallback for old benches.

Torque uses Q10 (Q8 force times quarter-pixel arm). Angular acceleration in Q8
spin units is `torque_q10 / (8 * body_mass)`, a deliberately conservative,
fixed mass-scaled rotational-inertia approximation, rather than an inertia tensor
recomputed from every part. One spin unit is 1/16 of an 11.25-degree tilt step;
the gain corresponds approximately to inertia `163 * mass` in pixel-squared
units. The signed fractional angular velocity is integrated into a signed angle
remainder, so small positive and negative moments accumulate symmetrically.
Angular speed is limited to 11.25 degrees per movement update. The wheel footprint
also supplies a bounded normal-reaction moment. Contact locations are rotated
into world coordinates; a four-pixel contact half-width defines the support
interval about COM. If that interval brackets COM, weight times the available
horizontal support arm bounds the counter-moment. In the same angular units its
capacity is `arm_q2 * (32-24*balloons) / 8`, implemented as shifts for zero
balloons, identity for one, and zero for net upward lift. Stable ordinary drive
can therefore be balanced by ground reactions, while boost or off-centre thrust
can exceed that limit. Edge tipping and a spring launch bypass this static
support approximation. Grounded spin loses a quarter of its angular velocity each update even while a
motor is driving, and the moments-mode terrain-tip acceleration is one spin unit
per grounded update rather than three. Quiet grounded bodies settle onto terrain;
airborne angular velocity persists without torque.
Collision-blocked turns clear angular velocity, and existing terrain-edge tipping
is retained. This is not suspension, per-wheel deformation, detached debris, or
a complete rigid-body/contact solver. Balloon lift and gravity keep their
existing aggregate treatment; balloon-specific moments are not introduced.

A rotation also shifts the grid origin by `R(old)*COM - R(new)*COM`. This keeps
the mass centre on its translated trajectory while the existing renderer and
collision engine continue using their fixed grid-centre geometry. It prevents
rotation of an asymmetric build from adding unintended COM translation.

All work is sequential: one additional serial divider and one shared shift/add
multiplier handle the COM, wheel force sharing, rotated moment arms, acceleration
and pivot correction. Fan/rocket magnitude products are constant shifts. There
are no division/modulo operators, wide parallel variable multipliers, new DSP
instances, extra block RAMs, or independent-body physics in the new module.
The movement handshake waits for moments before publishing its request.
Future vertical-rocket building logic must supply both signed
`rocket_vertical_balance` and the per-cell `rocket_vertical_mask`. For a vertical
rocket, saved facing 0 means up and 1 means down. Current top-level vertical
placement wiring remains zero, as requested in the preceding physics-only work.

`vehicle_moments_tb` checks 22 analytic cases: COM/mass, centred and offset forces,
couples, vertical rockets, inertia scaling, wheel origins, exact force sharing,
reverse, rotated arms, COM pivot correction, ground reaction limits, balloon
weight relief, damage, snapshots and backpressure.
`physics_moments_tb` checks the connected integrator: visible spin, balanced
thrust, angular momentum, vertical rockets, wheel traction, COM motion,
collision-blocked turns and retry. Reports are in `tmp/moments_before/`,
`tmp/moments_after/` and `tmp/moments_all/`.


### Initial moments verification and budget (before rocket/wheel tuning)

The same Vivado 2025.2 synthesis flow on the saved pre-moments sources and the
final ground-supported model, for `xc7a35tcpg236-1`, reports:

| Resource | Before moments | Moments enabled | Difference |
| --- | ---: | ---: | ---: |
| Slice LUTs | 17,418 (83.74%) | 18,515 (89.01%) | +1,097 |
| Registers | 3,652 | 4,401 | +749 |
| DSPs | 23 | 23 | 0 |
| Block RAM tiles | 48.5 | 48.5 | 0 |

There are 2,285 LUTs left. The feature fits but consumes a significant 5.27
percentage points of device LUT capacity. Keeping it optional is recommended;
a full suspension, separate bodies or a more detailed contact solver would be
poor choices with this remaining budget. The fixed-point moment/inertia model
is explainable with weighted averages, force times distance, and angular
integration, though its serial FSM implementation is more involved than the
previous count-based forces.

The final model synthesizes successfully with no added DSP or memory blocks.
Pre-route setup slack is -1.297 ns (before: -1.040 ns); this is not timing closure
or board validation. The updated production modules also compile as Verilog
without `--sv` in the clean `tmp/moments_verilog2001` library. The maximum observed
request latency in `physics_moments_tb` was 335 clocks, or 3.35 microseconds at
100 MHz, well inside a 60 Hz update interval; this is the test's measured maximum,
not an exhaustive worst-case timing bound.

The regression run reports 53/54 passing. The only failure is the unchanged
`occupied_map_collision_tb` roof-fixture assertion at line 159, already reproduced
on the untouched pre-change sources. Additional final-model checks pass for the
22 analytic moment cases, spin/support/boost/fuel/pivot integration, game baseline,
board controls, connected rotation, balloons, audio, cave integration and level
solutions. The Cave Arch driving bench with `ENABLE_MOMENTS=1` reaches the flag
in 1,748 updates with two reversals (about 29 seconds at 60 Hz). Default
`cave_arch_drive_tb.ENABLE_MOMENTS=0` retains its legacy comparison; use an
elaboration override to run the moments version. Logs are
`tmp/moments_all_summary.log`, `tmp/moments_final_checks.log`,
`tmp/moments_support.log`, `tmp/moments_latency/latency.log` and
`tmp/moments_drive/drive.log`. The helper definition lives in the already-registered `physics_engine.v`, so an
open Vivado project's older source list can resolve it without adding a separate
`vehicle_moments.v` file. The simulation runner discovers both moment benches.


### Synthesis source-list repair

The saved/open project had omitted the new standalone helper file, causing
`Synth 8-439: module vehicle_moments not found`. The earlier all-files synthesis
check included it automatically and therefore did not catch that project-list
gap. The unchanged `vehicle_moments` module definition is now appended to
`physics_engine.v`, an existing registered design source. The separate helper
file is removed, avoiding duplicate definitions in flows that scan all `.v` files.
No force, torque, inertia or timing logic was altered by this packaging fix.
RTL elaboration using the exact 50-source saved-XPR list succeeds without helper
registration. Both moment benches also pass in a fresh Verilog-mode compilation
using only `physics_engine.v` and `signed_divider16.v` as design sources.
Verification logs: `tmp/moments_source_fix/`.


## Rocket direction and wheel stability follow-up

The prior rocket force was fixed to world X/Y while the sprite rotated with the
vehicle. It could rotate the cart without producing the expected vertical thrust.
Rocket force now follows body orientation, using the same sampled angle as the
moment geometry. Repeated per-rocket additions of the sine/cosine-based unit
vector avoid variable multipliers. Body-frame torque prevents a mismatch between
rotated force and rotated moment arm. The game preset is 1024 force units as
requested, enough to lift a 19-unit cart when pointed straight up; at 512, a
vehicle of mass 16 or more cannot overcome gravity without balloon assistance.
Both force and torque share `ROCKET_FORCE_SHIFT` so they cannot silently use
different rocket strengths. Fuel duration remains 90 accepted movement updates.
This does not add top/bottom placement or alter building controls.

Wheel stability uses quarter-strength wheel moment coupling, 25% grounded
angular damping on every grounded update (including powered drive), and gentler
terrain-tip acceleration. Fan and rocket moment magnitudes remain unscaled.
Linear wheel force, engine power, mass division, slope force and speed limits
are unchanged. Contact eligibility still uses the existing body-grounded and
frame-side convention, not an independent per-wheel terrain solver.

The one-wheel regression measures peak angular velocity of 642 Q8 spin units
with raw wheel moments versus 169 with the game's stability gain: 73.7% lower,
while horizontal drive velocities match at every step. `rocket_orientation_tb`
checks all 32 angles, both facings and both body axes (128 force-vector cases),
as well as body-frame torque invariance. `rocket_game_integration_tb` confirms
that the real top-level wiring, with vertical-placement inputs still zero,
supplies upward force -1024 and initial vertical velocity -21 to a valid 19-unit
cart with its side rocket rotated upward. The helper has 23 analytic cases.
Eleven focused benches pass in `tmp/rocket_wheel_checks.log`; production sources
also compile in Verilog mode without `--sv` in `tmp/rocket_wheel_verilog2001/`.


The updated complete design passes synthesis using the saved project's source
list: 18,762 LUTs (90.20%), 4,490 registers, 23 DSPs and 48.5 block-RAM tiles.
That is 247 more LUTs than the preceding 18,515-LUT moments build, leaving 2,038
LUTs free. No DSP or block RAM was added. Pre-route setup slack remains -1.297 ns;
100 MHz timing closure is still outstanding. Reports are under
`tmp/rocket_wheel_synthesis/`.


The final real-terrain check with moments enabled and `WHEEL_TORQUE_SHIFT=2`
completes Cave Arch in 1,730 updates with two automatic reversals. This confirms
the gentler turning response still traverses the course. Full trace:
`tmp/rocket_wheel_drive/drive.log`.
