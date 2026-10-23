# Draft game module interfaces

Owner: Shared - all four roles agree interface changes.

The grid size and screen arrangement follow the current team proposal. The connected starter uses the port names, eight-pixel cells, numerical format and terrain encoding below. These are starting contracts for team review. Implementations and their current ports live beside `My_Top_Module.v`.

The hardware baseline starts with a preset build and flat test map. The builder supports mouse-driven placement, replacement, removal, limited inventory and runtime damage. Mouse edits and queued balloon pops are connected in the top. A manual audio test beep is connected to Pmod AMP2 on JC; game-event sounds remain to be added. Further gameplay controls, TNT, instruction content and final level designs remain future work. The engine switch is sampled by movement at the start of a step; it does not change an already published proposal. World checks currently cover the committed pig centre and bounds, without TNT or hazards.

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
| Cell index | Four bits; indices 9 through 15 are invalid and must be rejected |
| Part counts | Four bits per type, allowing counts from zero to nine |
| Position and velocity | Signed 16-bit values, eight fractional bits; 256 units is one pixel |
| Axes and origin | Positive x right, positive y down; vehicle position is the top-left grid origin |
| Terrain | Up to four rectangles; each is `{height[7:0], width[7:0], y[7:0], x[7:0]}` in whole pixels |
| Rectangle packing | Rectangle 0 occupies bits 31:0 of `terrain_rects`; only entries below `terrain_count` are active |
| Rectangle edges | Left/top inclusive, right/bottom exclusive; zero width/height disables a rectangle |

Part IDs are empty=0, frame=1, pig=2, wheel=3, engine=4, reserved=5, balloon=6. Frame is an edit selection only: it sets `build_frames` and is never stored in `build_grid`. Each frame holds one pig or engine, or remains empty. Wheels occupy their own cells directly below frames; balloons occupy their own cells directly above frames. Wheels and balloons cannot share a cell with a frame. IDs 5 and 7 are rejected. Boost is planned as a temporary engine ability rather than a separate construction item; its controls and timing remain to be implemented.

State IDs are BUILD=0, INIT_RUN=1, RUN=2, SUCCESS=3, FAIL=4 and GUIDE=5. The reset state is BUILD. Role 4 owns transitions; GUIDE returns to its agreed previous non-running screen.

At eight pixels per cell, the grid spans 24 by 24 pixels. The starter treats it as one upright body; artwork extending outside these cells and detached-part collision geometry need coordination. Mass weights and lift/thrust values remain provisional. Widen arithmetic before narrowing to 16 bits and clamp movement to prevent overflow.

The editor has `EDITOR_CELL_PIXELS=16` in `left_renderer`, giving a 48 by 48 pixel grid. The mouse adapter uses the same 16-pixel cell layout; coordinate changes require updating both modules. Gameplay remains eight pixels per cell with the existing 24 by 24 collision footprint. The left renderer uses the user's rectangle and number helpers for construction inventory and runtime status.

## Ownership and connections

| Producer | Consumer | Signals or data |
| --- | --- | --- |
| Role 1 builder | Roles 2 and 4 | Surviving counts, `mass_units`, `build_valid`, `build_error`, `pig_alive` |
| Role 1 builder | Role 4 drawing | Five four-bit stock outputs: `frames_left`, `pigs_left`, `wheels_left`, `engines_left`, `balloons_left` |
| Role 1 builder | Role 3 outcomes and Role 4 drawing | `build_grid`, `intact_mask` locate surviving contents; drawing also receives `frame_intact_mask` |
| Role 1 builder | Shared construction/geometry consumers | `build_frames` is the saved frame layout |
| Role 1 input | Role 4 game control | Launch, retry, edit and guide requests |
| Role 1 balloon control | Role 4 game control | `pop_pending` connects to `gameplay_pending`; reserve idle clocks for queued actions before starting another step |
| Role 4 game control | Role 1 balloon control | `gameplay_ready` is high only in RUN with no outstanding movement/world update |
| Role 1 input/control | Role 2 | Engine enabled state; balloon popping must update Role 1's intact state |
| Role 4 | Role 1 | Game state and left-screen clickable layout |
| Role 4 level data | Roles 2 and 3 | Spawn, terrain, TNT, goal and hazard geometry; same source feeds drawing |
| Role 4 game control | Roles 1, 3 and drawing | One-bit `level_index`, changed only in BUILD; two-bit `fail_reason` after FAIL |
| Role 2 | Role 3 collision | Previous/proposed movement with valid/ready handshake |
| Role 3 collision | Role 2 | Corrected movement and grounded flag with valid/ready handshake |
| Role 2 | Roles 3 and 4 | Committed position and `movement_committed` pulse |
| Role 3 TNT | Role 1 | Separate content/frame damage masks under one `damage_valid`/`damage_ready` handshake |
| Role 3 outcomes | Role 4 | `world_valid`, goal/hazard/out-of-bounds flags; hold until `world_ready` |
| Roles 2, 3 and 4 | Role 1 audio | Accepted action, explosion and result events; exact audio event ports to be agreed |

All same-clock user actions are one-clock pulses. Decode held buttons into single press/release actions so dragging does not repeat edits. Role 4 draws click targets and supplies their coordinates; Role 1 decodes them. Keep all clickable controls on the left OLED. The right OLED shows the map and vehicle movement; the left shows construction/inventory, then component status and controls during a run.

`mass_units` is the total mass of surviving occupied parts, not a second independently maintained build. Role 1 may derive it and the counts through `vehicle_status`; Role 2 alone turns those properties into movement. Do not count destroyed parts.

## Handshake rules

For each valid/ready channel, transfer occurs only on a rising clock edge where both are high. The producer asserts valid and holds the payload stable until transfer. The consumer processes each transfer exactly once. A consumer can assert ready before valid; neither side should wait for the other to assert first.

After a damage transfer, clear content bits selected by `damage_mask` and frame bits selected by `damage_frame_mask`. Both masks share one transfer; either can be zero. Frame damage alone does not destroy the pig or engine inside it. Counts, mass and `pig_alive` reflect the cleared flags by the next cycle. The starter continues moving surviving parts as one body; support loss does not yet produce separate falling parts. The TNT controller must not announce a completed world update on the damage-transfer edge; allow at least the following cycle so Role 4 sees updated properties. Damage never refunds inventory. Combine simultaneous blast masks for each layer into one request.

`edit_valid` is a one-cycle action accepted only in BUILD, with `run_init` low. `LP_EDIT_PLACE` adds a frame only where content is empty, places/replaces a pig or engine only inside an existing frame, and places/replaces an external wheel or balloon only in a frameless cell with the required neighbouring frame. A wheel's supporting frame is at cell n-3, so the wheel cannot occupy the top row. A balloon's supporting frame is at n+3, so it cannot occupy the bottom row. `LP_EDIT_REMOVE` removes contents first; when contents are empty it removes the frame. It ignores `edit_part`.

Removing a frame can leave an external wheel/balloon unsupported. This temporary construction is permitted, but launch is blocked until support is restored or the external part is removed. Place with empty/reserved/unknown part IDs, unsupported actions, impossible placements, insufficient stock or cell indices 9 through 15 leaves both layers unchanged. `build_error=1` means the saved grid does not contain exactly one pig, 2 means invalid attachments/overlap and 3 means the saved build exceeds stock; zero means valid. Errors are prioritised in that order. Other states ignore edits.

The builder decides each edit once, then uses that result for both storage and temporary feedback. Three-bit `feedback_code` is 0=none, 1=placed, 2=removed, 3=no stock, 4=need frame, 5=frame above, 6=frame below and 7=cell occupied. Four-bit `feedback_cell` identifies the target. Occupancy/support checks precede stock checks. Same-part drops, already-present frames, empty-cell removals and invalid protocol payloads are quiet; they do not restart an existing message. A reportable result replaces the old message and restarts the 32-bit counter. Positive parameter `FEEDBACK_CYCLES` defaults to 100000000 for one second at 100 MHz. Expiry sets the code to zero; reset, run initialisation and leaving BUILD clear it. These fields cross the coherent display snapshot together.

The left view gives the target cell a green outline for placed/removed and a red outline for rejection. BUILD uses y=56 through 62 for a 5 by 7 text message, with one blank column between characters. The messages are PLACED, REMOVED, NO STOCK, NEED FRAME, FRAME ABOVE, FRAME BELOW and CELL OCCUPIED. With no temporary feedback it shows READY or the saved-build reason ADD PIG, CHECK SUPPORT or CHECK STOCK. Runtime indicators are unchanged. The drag icon and cursor overlay this feedback as before.

For Marcus's sprite integration, `left_renderer.draw_part_icon` supplies both inventory and drag-preview icons, while the construction-grid shapes and `right_renderer` vehicle graphics are drawn separately. Replace these temporary visuals with the final sprites; the existing feedback text/outlines can stay or be restyled. Preserve `drag_active`, three-bit `feedback_code`, four-bit `feedback_cell` and the snapshot wiring (now 162 bits, adding `level_index`, `fail_reason`, `tnt_intact`, saved `build_frames`, `run_seconds` and `blast_phase`). Keep feedback decisions and the timer in the builder. If grid/inventory positions or cell sizes change, update the matching hit regions in `mouse_adapter` together. Instructions and the two final levels remain Role 4's planned work.

`build_grid` and `build_frames` store the saved construction; their two intact masks describe runtime survivors. Damage changes only the masks. Retry and return to BUILD restore both layers of the edited construction; reset reloads the preset. Both layers contribute independently to mass: frame=2, pig=2, wheel=1, engine=3, balloon=1. The preset has three frames, one pig, one engine and two wheels, for mass 13.

Inventory totals are parameters: `FRAME_LIMIT=5`, `PIG_LIMIT=1`, `WHEEL_LIMIT=2`, `ENGINE_LIMIT=1`, `BALLOON_LIMIT=2`. The top exposes the same parameters. Remaining counts are derived from the saved layers and clamp to zero if the preset exceeds a configured limit; such a preset is invalid. A same-kind replacement is permitted at zero remaining stock because it reuses that item. Other replacements require available stock for the new kind, and update the grid only after checking; removing the old kind from the saved grid refunds it automatically. Damage/retry never changes stock. Runtime per-level inventory selection is not yet connected; parameters configure this first-map version.

## Mouse construction layout

`MouseCtl` runs on the shared 100 MHz clock unchanged. `mouse_adapter` sets maximum coordinates to x=95 and y=63, and starts both positions at 24. The adapter samples buttons/position only on `new_event`. A left press in the inventory selects a part and starts a pending placement; a left press in the grid starts placement of the existing selection. Release over a grid cell emits one place action using that release position. Holding or crossing cells never paints. Release outside the grid, right-click, reset or leaving BUILD cancels the pending placement. Right-click takes priority over simultaneous buttons and removes once on its press.

`drag_active` exposes the pending placement only during BUILD. It crosses the display snapshot together with the selected part and cursor coordinates. While active, `left_renderer` draws an 8 by 8 temporary part icon three pixels to the right/below the cursor, clamping its top-left position to x=88 and y=56 near the screen edges. The preview overlays the interface, with the cursor drawn last. Preview movement does not edit the build or inventory. Release, cancellation and reset clear it; unavailable parts may still be previewed, but the builder rejects unaffordable drops as before.

The inventory and drag preview share `draw_part_icon`, a small combinational function returning the pixel colour for a part and relative position. Transparent pixels return the supplied background colour. The inventory uses fixed row boundaries instead of dividing pixel coordinates by ten, and the mouse adapter calculates the hovered grid cell once for all mouse actions.

Grid hit bounds are x=[4,52), y=[4,52), with row-major 16-pixel cells. Inventory hit bounds are x=[56,92), y=[4,54), with five 10-pixel rows: frame, pig, wheel, engine, balloon. Both select-then-click and inventory-to-grid drag-and-drop place one part on release. Selection stays fixed while dragging past other inventory rows. A press that began outside the inventory/grid cannot place a part when released inside. A right click in the grid requests content-first removal. Only BUILD accepts these edits. During RUN a fresh left press in the grid emits `pop_req` with four-bit `pop_cell`; right-click suppresses a simultaneous left press. Holding or dragging cannot pop another cell. Other states update button history without emitting actions, so a held construction click cannot pop a balloon on launch. The cursor is clamped and drawn on the left view in BUILD and RUN. The selected inventory row is yellow; zero stock digits are red. The BUILD bottom strip shows construction feedback/status; runtime indicators show build validity and engine state. Button-based launch/retry/edit/reset remain separate.

## Levels

`level_data` takes `level_index` (0 = level 1, 1 = level 2) and returns spawn, up to four terrain rectangles, the goal, up to `LP_MAX_TNT=4` TNT blocks and up to `LP_MAX_HAZARDS=2` hazard rectangles. TNT entries are 16-bit `{y[7:0], x[7:0]}` top-left corners of 8 by 8 blocks, packed entry 0 lowest in 64-bit `tnt_positions`, with `tnt_count` active. Hazards use the terrain rectangle packing in 64-bit `hazard_rects`, with `hazard_count` active. Unused entries are zero. Both layouts are provisional.

Level 1 keeps the flat baseline path (ground y=56 across the screen) with one TNT on a ledge above the path. Level 2 has a 16-pixel spiked pit, narrower than the 24-pixel vehicle, a TNT on the path at x=60 and one on a ledge. Both spawn at x=4, y=32 and share the goal at x=80.

`game_controller` owns `level_index`. A `level_next_req` pulse toggles it only in BUILD, and a launch on the same clock wins, so geometry cannot change during INIT_RUN, RUN or a result. `level_button` creates that pulse on a fresh left press inside the left OLED button at x=[82,95), y=[55,64), reading the same mouse coordinates as `mouse_adapter`; the button lies outside the grid and inventory hit regions. On FAIL, `fail_reason` records 1=pig lost, 2=hazard, 3=out of bounds, in the same priority as the failure check; INIT_RUN and edit clear it. BTNU (edit) after SUCCESS returns to BUILD on the next level, wrapping from level 2 to level 1; after FAIL it keeps the level. `run_seconds` counts whole seconds of RUN (`TICKS_PER_SECOND=60` physics ticks), stops at 99, freezes on a result and clears in INIT_RUN. `launch_event`, `success_event` and `failure_event` are one-clock pulses wired as top-level nets for Role 1 audio; Role 4 does not schedule sounds.

The top passes `tnt_count`, `tnt_positions`, `hazard_count` and `hazard_rects` as wires for Role 3; `world_outcomes` does not read them yet and `hazard_hit` remains zero. `tnt_intact` (one bit per TNT, 1 = still present) is tied high until Role 3 drives it; the right renderer hides cleared blocks. `explosion_fx` turns each falling `tnt_intact` bit into a two-bit `blast_phase` (1 flash, 2 fireball, 3 smoke, each `PHASE_TICKS=8` physics ticks); run initialisation clears it. Explosions are drawing only. Both renderers draw parts from `part_sprites.vh`: 8 by 8 sprites at single size on the right OLED and double size in the 16-pixel editor cells, also used for inventory and drag icons. During RUN and results the left grid is a damage diagram: a dim red cross marks a destroyed frame or part, and survivors are drawn over it. The left status column shows the run timer, then surviving parts during RUN or "C RETRY" and "U NEXT"/"U EDIT" after a result.

Recorded solutions (`sim/role4_level_solutions_tb.v`): the preset build with SW0 on clears level 1 and level 2 by driving right along y=56; on level 2 the 24-pixel body spans the 16-pixel pit. Recheck when Role 3 adds TNT and hazard checks.

The renderers use a second `level_data` instance indexed by the snapshot copy of `level_index`, so the drawn map always matches the drawn state.

## One movement update

1. Role 4 selects the level, freezes its geometry and enters INIT_RUN. Assert `run_init` throughout INIT_RUN. Each receiving module initialises once on entry, then holds `init_ready` high until `run_init` goes low. It must not initialise again on every clock while `run_init` is high. Role 1 restores intact parts, Role 2 loads spawn/clears velocity, and Role 3 rearms TNT.
2. Once all three ready bits are high, Role 4 enters RUN. On a physics tick while no update is outstanding, it pulses `step_start`. Role 2 samples vehicle properties on that clock, then calculates forces, velocity and position on separate following clocks before holding a movement request for Role 3. Consumers wait for `move_valid`; they must not assume the request appears immediately after `step_start`.
3. Role 3 accepts the request, calculates corrections and holds a response. Role 2 accepts it, commits position/velocity once and pulses `movement_committed`. Previous movement must remain available through the world checks.
4. Role 3 checks TNT, hazards and goal using the previous-to-committed path and agreed committed pose. It holds any damage request until Role 1 accepts it. It then waits for damage-derived properties to settle.
5. Role 3 raises `world_valid` with final flags, including all interactions, and holds them until Role 4 asserts `world_ready`. Role 4 evaluates pig death, hazard and out-of-bounds before goal success, then pulses `update_release` to Role 2. It may start another step only after releasing the previous one. Ignore physics ticks while busy rather than stacking updates.

`balloon_control` keeps a nine-bit pending mask. It accepts only cells 0 through 8 containing a surviving balloon, and coalesces repeated requests for that cell. While movement/world checks are busy, counts and mass remain unchanged. `game_controller` exposes `gameplay_ready` in RUN when idle and blocks `step_start` whenever `gameplay_pending` is high. The balloon module then asserts `pop_valid` for the idle clock and passes its pending content mask to the builder's damage inputs; the builder is always damage-ready in RUN. It clears the applied pending bits, preserving a different new click arriving on that same edge. Result states, run initialisation and reset clear the queue. Requests reaching the queue on a step-start edge wait until that update finishes. The next step after application samples the reduced balloon count and mass. A popped balloon clears only its content intact bit without refunding inventory or changing saved construction; retry and return to BUILD restore it.

The top currently connects only balloon pops to the damage channel, with zero frame damage. When TNT is added, Roles 1 and 3 must combine/arbitrate content/frame requests and acknowledge each source without losing masks. TNT damage still belongs inside the current world update; queued player pops wait until it finishes. Engine toggles currently come directly from SW0 and are sampled by physics at `step_start`; they do not destroy the engine. Additional mouse engine/boost controls remain future work.

## Displays and audio

Role 4 uses two separate OLED driver instances and separate pixel buses. Render from coherent committed snapshots. If the driver and game logic use different clocks, transfer the snapshot using a proper handshake; synchronising each bit independently does not preserve a multi-bit state. Rendering must not block physics.

The initial hardware test uses `audio_beep(clk, reset, start, mute, busy, audio_pwm)`. `start` is a one-clock request, currently the debounced BTNR `beep_press`; requests while busy or muted are discarded. Positive parameters `TONE_HALF_CYCLES=50000` and `BEEP_CYCLES=20000000` give 1 kHz for 0.2 seconds at 100 MHz. Mute/reset clear playback. SW1 is synchronised into `audio_muted`; the top exposes SW0/SW1 as `sw[1:0]`. Pmod AMP2 on JC was confirmed by Kaushal: `JC[0]` is audio, `JC[1]=1` selects lower gain, `JC[2]=0` is unused, and `JC[3]=!reset && !audio_muted` enables the amplifier. Physical pins 5/6 provide ground/power. See [audio setup](audio_setup.md) and its manufacturer reference.

Role 1 owns the following sound-scheduling stage. Role 4 emits accepted launch/success/failure events; Role 3 will emit explosion events; any agreed movement cue comes from Role 2. Result sounds should take priority over explosions, then ordinary action sounds. Clear pending scheduled audio on reset/mute/run initialisation and keep playback independent of game progress. This event router and its run-initialisation behaviour are not implemented by the manual beep test.

## First tests with neighbouring modules unfinished

Use testbench-only fixtures: a fixed valid nine-cell build for movement, an accept-all collision responder for arithmetic checks, scripted movement for collision tests, and fake outcome/audio events for game control and sound tests. Exercise held requests and delayed ready responses, not just immediate acceptance. Replace fixtures with the real module one boundary at a time.
