# Draft game module interfaces

Owner: Shared - all four roles agree interface changes.

The grid size and screen arrangement follow the current team proposal. The connected starter uses the port names, eight-pixel cells, numerical format and terrain encoding below. These are starting contracts for team review. Real implementations live beside `My_Top_Module.v`; the `.v.example` files retain port references only.

The current baseline has a fixed build and flat test map. Damage is supported by the builder but tied inactive in the hardware top. TNT, mouse editing, inventory, instruction content, audio and final level designs remain future work. The engine switch is sampled by movement at the start of a step; it does not change an already published proposal. World checks currently cover the committed pig centre and bounds, without TNT or hazards.

## Shared data

| Item | Draft representation |
| --- | --- |
| Game clock | 100 MHz `clk` for game logic, with clock enables for slower updates |
| Reset | `reset`, synchronous and active high for new game modules; hardware inputs require synchronisation |
| Grid | 3 columns by 3 rows, nine cells, three bits per part, 27 bits total |
| Ordering | Row major: cells 0, 1, 2 at top; 3, 4, 5 middle; 6, 7, 8 bottom |
| Packed grid | Cell 0 is bits 2:0; cell n is `build_grid[3*n +: 3]` |
| Intact and damage | Nine bits; bit n refers to cell n; a damage bit requests destruction |
| Cell index | Four bits; indices 9 through 15 are invalid and must be rejected |
| Part counts | Four bits per type, allowing counts from zero to nine |
| Position and velocity | Signed 16-bit values, eight fractional bits; 256 units is one pixel |
| Axes and origin | Positive x right, positive y down; vehicle position is the top-left grid origin |
| Terrain | Up to four rectangles; each is `{height[7:0], width[7:0], y[7:0], x[7:0]}` in whole pixels |
| Rectangle packing | Rectangle 0 occupies bits 31:0 of `terrain_rects`; only entries below `terrain_count` are active |
| Rectangle edges | Left/top inclusive, right/bottom exclusive; zero width/height disables a rectangle |

Part IDs are empty=0, frame=1, pig=2, wheel=3, engine=4, reserved booster=5, balloon=6. Part ID 7 is invalid. Reserve the booster ID without committing to implementing that part.

State IDs are BUILD=0, INIT_RUN=1, RUN=2, SUCCESS=3, FAIL=4 and GUIDE=5. The reset state is BUILD. Role 4 owns transitions; GUIDE returns to its agreed previous non-running screen.

At eight pixels per cell, the grid spans 24 by 24 pixels. Decide whether balloon artwork stays inside those cells before fixing the collision footprint. Inventory limits, mass weights, total-mass range, lift/thrust values, clickable rectangles and build-error meanings remain to be agreed. Widen arithmetic before narrowing to 16 bits and clamp the movement range to prevent overflow.

The editor has a separate `EDITOR_CELL_PIXELS=16` parameter in `left_renderer`, giving a 48 by 48 pixel construction grid. Gameplay remains eight pixels per cell with the existing 24 by 24 collision footprint. The left renderer uses the user's rectangle helper for its grid/status areas and the number helper for the surviving-part count. This is status information, not the unfinished construction inventory.

## Ownership and connections

| Producer | Consumer | Signals or data |
| --- | --- | --- |
| Role 1 builder | Roles 2 and 4 | Surviving counts, `mass_units`, `build_valid`, `build_error`, `pig_alive` |
| Role 1 builder | Roles 3 and 4 | `build_grid`, `intact_mask` |
| Role 1 input | Role 4 game control | Launch, retry, edit and guide requests |
| Role 1 input/control | Role 2 | Engine enabled state; balloon popping must update Role 1's intact state |
| Role 4 | Role 1 | Game state and left-screen clickable layout |
| Role 4 level data | Roles 2 and 3 | Spawn, terrain, TNT, goal and hazard geometry; same source feeds drawing |
| Role 2 | Role 3 collision | Previous/proposed movement with valid/ready handshake |
| Role 3 collision | Role 2 | Corrected movement and grounded flag with valid/ready handshake |
| Role 2 | Roles 3 and 4 | Committed position and `movement_committed` pulse |
| Role 3 TNT | Role 1 | Damage mask with valid/ready handshake |
| Role 3 outcomes | Role 4 | `world_valid`, goal/hazard/out-of-bounds flags; hold until `world_ready` |
| Roles 2, 3 and 4 | Role 1 audio | Accepted action, explosion and result events; exact audio event ports to be agreed |

All same-clock user actions are one-clock pulses. Filter held clicks into press events. Role 4 draws click targets and supplies their coordinates; Role 1 decodes them. Keep all clickable controls on the left OLED. The right OLED shows the map and vehicle movement; the left shows construction/inventory, then component status and controls during a run.

`mass_units` is the total mass of surviving occupied parts, not a second independently maintained build. Role 1 may derive it and the counts through `vehicle_status`; Role 2 alone turns those properties into movement. Do not count destroyed parts.

## Handshake rules

For each valid/ready channel, transfer occurs only on a rising clock edge where both are high. The producer asserts valid and holds the payload stable until transfer. The consumer processes each transfer exactly once. A consumer can assert ready before valid; neither side should wait for the other to assert first.

After a damage transfer, clear only occupied intact bits selected by the mask. Counts and `pig_alive` must reflect that change by the next cycle. The TNT controller must not announce a completed world update on the damage-transfer edge; allow at least the following cycle so Role 4 sees updated properties. Damage never refunds inventory. Combine simultaneous blast masks into one request.

`edit_valid` is a one-cycle action accepted only in BUILD. Place includes replacement; refund the old part before charging for the new part, and reject an unaffordable edit without any state change. Unknown part IDs and invalid cell indices are rejected. Editing is frozen during RUN. The agreed validity rules include exactly one pig.

## One movement update

1. Role 4 selects the level, freezes its geometry and enters INIT_RUN. Assert `run_init` throughout INIT_RUN. Each receiving module initialises once on entry, then holds `init_ready` high until `run_init` goes low. It must not initialise again on every clock while `run_init` is high. Role 1 restores intact parts, Role 2 loads spawn/clears velocity, and Role 3 rearms TNT.
2. Once all three ready bits are high, Role 4 enters RUN. On a physics tick while no update is outstanding, it pulses `step_start`. Role 2 samples vehicle properties and holds a movement request for Role 3.
3. Role 3 accepts the request, calculates corrections and holds a response. Role 2 accepts it, commits position/velocity once and pulses `movement_committed`. Previous movement must remain available through the world checks.
4. Role 3 checks TNT, hazards and goal using the previous-to-committed path and agreed committed pose. It holds any damage request until Role 1 accepts it. It then waits for damage-derived properties to settle.
5. Role 3 raises `world_valid` with final flags, including all interactions, and holds them until Role 4 asserts `world_ready`. Role 4 evaluates pig death, hazard and out-of-bounds before goal success, then pulses `update_release` to Role 2. It may start another step only after releasing the previous one. Ignore physics ticks while busy rather than stacking updates.

Engine toggles and balloon popping received during a movement update should be queued by Role 1 and applied after `update_release`, before another `step_start`. This prevents properties changing halfway through a transaction. Final input queue/arbitration ports must be agreed between Roles 1, 2 and 4. A popped balloon clears its intact bit without refunding inventory; retry restores it. Engine toggling does not destroy the engine.

## Displays and audio

Role 4 uses two separate OLED driver instances and separate pixel buses. Render from coherent committed snapshots. If the driver and game logic use different clocks, transfer the snapshot using a proper handshake; synchronising each bit independently does not preserve a multi-bit state. Rendering must not block physics.

Role 1 owns sound scheduling through amplifier output. Role 4 emits accepted launch/success/failure events; Role 3 emits explosion events; any agreed movement cue comes from Role 2. Result sounds take priority over explosions, then ordinary action sounds. Clear pending audio on reset/mute/run initialisation. Keep sound playback independent of game progress. Exact hardware pins must be verified against the actual amplifier and connector placement before changing constraints.

## First tests with neighbouring modules unfinished

Use testbench-only fixtures: a fixed valid nine-cell build for movement, an accept-all collision responder for arithmetic checks, scripted movement for collision tests, and fake outcome/audio events for game control and sound tests. Exercise held requests and delayed ready responses, not just immediate acceptance. Replace fixtures with the real module one boundary at a time.
