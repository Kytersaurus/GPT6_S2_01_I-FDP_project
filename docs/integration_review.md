# Team integration review - 24 October 2026

Owner: Shared integration - all roles review their own behaviour and ports.

## Included work

| Branch / commit | Contribution | Review outcome |
| --- | --- | --- |
| `role1-builder`, `e622708` | Construction, inventory, damage/retry state, mouse dragging, feedback, balloon popping and prioritised game audio | Existing behaviour retained and checked against the merged movement/display modules |
| `role4`, `6cba213` | Shared sprites, two provisional maps, level selection, timer, damage diagram, results and explosion drawing | Display snapshot and game-event wiring combined with Role 1 audio; both levels checked with the new physics |
| `Physics-rework`, `c300e3a` | Staged force/mass calculation, signed divider, friction, reverse and jumping | Input conflicts resolved and tests updated for sequential arithmetic and current force constants |
| Role 3 | Current starter collision/world checks only | Kaushal confirmed that Yap Ting's new work has not been pushed; TNT/hazard/wall/ceiling work is not included |

The older starter branch is already part of this history. `main`'s existing commits are retained through the physics branch. Teammates' branch histories and authors are preserved by merge commits.

## Resolved issues

- Kyle used SW1 for reverse and BTNR for jump, overlapping mute and the speaker test. Integrated controls are SW0 engine, SW1 mute, SW2 reverse, BTNL jump, BTNR test, BTNC launch/retry, BTNU edit/next and BTND reset. Only the original SW2 and BTNL pin lines were uncommented in the constraints.
- The physics tests assumed a one-clock movement result and older friction/thrust values. They now wait for valid/ready transfers and check the actual force constants, signed fractional carry, coasting without reversal and stable requests. Other fixtures explicitly drive the new controls, including the full three-bit switch bus.
- Lift was 10 per balloon against gravity 32; with the inventory capped at two, no legal build could rise. The provisional value is now 24 per balloon. One slows a fall; two rise. Final gameplay tuning remains Kyle's responsibility.
- The level button now respects the mouse adapter's right-click priority. Simultaneous left/right input cannot select a level, and releasing right while holding left does not create a deferred selection.
- Automatic audio replaces the obsolete manual-only module. Launch, success and failure come from accepted game events; popping uses accepted non-empty damage, and landing uses a new grounded impact. The explosion sound waits for Role 3's actual trigger.
- The `.xpr` source list was regenerated from real source files, with header/include settings and SystemVerilog test types. Obsolete audio paths and generated incremental-checkpoint references were removed. Vivado's generated `utils_1` directory is ignored. The local pre-merge project/checkpoint was preserved under `tmp/team_integration_review/`.

The first routed check found -2.807 ns setup slack in the starter's chained four-platform collision calculation. It was split into capture, parallel checks and surface selection, retaining the same ports and landing rules; this adds two calculation clocks per collision rather than changing the game clock or ignoring timing paths. Subsequent smaller violations came from using builder counts directly in the physics mass/lift formulas. Counts and controls are now captured before a separate force-calculation clock, and the fractional-carry comparison uses the captured mass. Movement still samples one coherent set of properties per update.

The supplied OLED/mouse drivers and user-provided divider/drawing helpers were preserved. No explicit FPGA clock-buffer primitives, placement attributes or separate OLED generated-clock constraint were introduced.

## Validation

All 19 simulation benches passed on the final integrated sources:

- Existing game, module contracts, display transfer, clock/reset and debounce checks.
- Construction storage, stock/refunds, drag/drop, feedback and queued balloon controls.
- Sound profiles, PWM/fades, priority/preemption and real game-event connections.
- Marcus's display/game-flow checks and both recorded level solutions.
- Kyle's updated friction test plus new signed-divider, jump and integrated-control checks.
- A staged collision test for signed bounds, strict overlap, four-platform choice, captured payloads, backpressure and reset.

The divider check includes signed extremes and random operands, quotient/remainder, exact latency, busy requests, captured operands, zero mass and cancellation. Jump checks cover grounded/airborne behaviour, input queued during arithmetic and retry. The top-level controls check exercises actual reverse movement and one jump from a held BTNL press.

Logs and local implementation reports are in `tmp/team_integration_review/`; these generated files are excluded from Git. All 19 benches passed on the final merged sources. Final routed use is 5,629 LUTs (27.06%), 2,060 flip-flops (4.95%), 13 DSPs (14.44%) and no block RAM. The constrained 100 MHz paths meet setup/hold timing, with 0.317 ns setup slack and 0.077 ns hold slack. DRC reports no error/critical-warning rules; the remaining DSP pipelining warnings concern performance/power suggestions. Divided-OLED-clock and external-I/O timing remain incompletely constrained, as before; physical board verification is still required. No bitstream was generated.

Subsequent local hardware adjustments make startup/reset construction empty with full stock and rotate the complete JA view by 180 degrees for its mounting orientation. Retry still restores the player's saved build. All 19 simulations passed again, including blank-build launch rejection, inventory/reset checks and the rotated cursor/drag/feedback pixels; see `tmp/hardware_adjustments_sim.log`. The AMP2 then moved from JC to JXADC pins 1-6, with its four output constraints using J3/L3/M2/N2 and the JC lines commented out. The audio and shared-control benches passed again after this pin change (`tmp/jxadc_audio_sim.log`). The routed resource/timing figures above predate these adjustments. No new bitstream was generated.

## Remaining integration work

Instruction screens, final level balancing and board testing remain. TNT damage, spike detection and wall/ceiling collision are now connected; see the Role 3 integration below. The fixed 96 by 64 maps do not scroll or zoom. Physical audio quality and the reported unwanted speaker click still need a fresh hardware test.

## Player features added after the merge

- SW15 permanently selects JA's view: down keeps builder on JA/map on JB; up shows the map on JA and blanks JB. The map renderer is reused. Both JA views keep the 180-degree mounting correction and change only at frame boundaries. Hidden grid/inventory/level actions are blocked; stale drags are cancelled; gameplay continues. The top now exposes all 16 switches, with their existing board pin lines enabled; only SW0/1/2/15 are used.
- The cursor and preview use the same snapshot and the preview is centred at the cursor. An occupied grid cell can be picked up, moved to a valid free target or returned to any inventory row. Frames carry their pig/engine. Saved construction is committed atomically on release, so rejected/outside/same-cell/cancelled drops do not lose parts. Inventory is unchanged for moves and refunded for returns. Wheels and balloons stay in their cells when frames move; existing validation flags any missing support. Snapshot width is 170 bits.
- A quiet 38-note single-voice adaptation of The Entertainer plays at 96 BPM in BUILD and 120 BPM in RUN. Effects pause/resume the melody through the existing PWM output. Mute/results/reset stop it. The public-domain Mutopia source is credited in the module and audio guide. A timing failure in a wide note-duration calculation was resolved by counting fixed sixteenth-note units instead of multiplying note lengths at runtime.

All 22 benches passed in `tmp/player_features_review/full_simulations.log`. Following the music-counter timing fix, the melody, single-OLED/state wiring and game-audio checks passed again in `music_counter_checks.log`; `melody_loop_check.log` additionally verifies the exact complete-loop length. The `.xpr` includes the new music module and three benches. Supplied OLED/mouse drivers and the main clock/divider are unchanged.

The final routed design uses **6,003 LUTs (28.86%)**, **2,193 flip-flops (5.27%)**, **13 DSPs (14.44%)** and **no block RAM**. Constrained 100 MHz setup/hold timing passes with **0.055 ns setup slack** and **0.078 ns hold slack**. DRC has no error/critical-warning rules; only the existing DSP pipelining suggestions remain. Divided-OLED and external-I/O timing remain incompletely constrained. Reports and the local routed checkpoint are in `tmp/player_features_review/`; **no bitstream was generated**. Physical verification of both JA views, centred dragging, returns and audible BGM/effects is still required. These changes remain local and uncommitted.

## Role 3 merge integration — 24 October 2026

The Role 3 merge is connected to the actual hardware top. A committed movement first captures every contacted TNT. Each explosion supplies separate frame/content masks to the builder, an audio pulse to the sound controller, and intact-state changes to the animation/display snapshot. Balloon clicks queue during movement and apply after its world response; both valid content masks are combined if they coincide. The world checks run only after all TNT damage transfers have settled, so a pig destroyed on goal entry fails instead of winning. A movement without TNT also completes normally. BUILD and retry restore TNT; runtime damage does not change the saved build or refund stock.

The first integration timing check found the parallel blast calculation too long for 100 MHz. The controller now shares a small distance lookup and checks one cell at a time across several clocks. It captures the committed pose and drains all contacted TNT before releasing world checks. This preserves the circular 12-pixel radius without wide per-cell multipliers.

The side collision checks use the previous vertical span: a small gravity proposal cannot turn the far floor edge of the Level 2 gap into a wall during landing. The recorded solution puts the engine in rear cell 3 and the pig in cell 4. It clears both provisional levels; on Level 2 it loses front wheel 8 and frame 5 to TNT while the engine and pig survive. This is a reachability check, not final level balancing.

The existing boost test exposed a missing mouse request: the RUN boost button was drawn but never pulsed `boost_req`. That pulse is now connected, and its test waits for the shared startup reset with a bounded timeout. The default runner includes the boost test and the new top-level TNT integration test. Vivado registers all tests for simulation, restores the baseline simulation top, and no longer refers to a generated incremental checkpoint.

Hardware testing: reopen the current project, generate a new bitstream and program that exact file. Check the Level 2 blast removes the front wheel/frame, updates left-side status, plays explosion audio and animates the TNT. Check pig death, queued balloon popping, retry restoration, boost, SW1 mute and SW15 single-OLED view. The checked-in bitstream predates this integration and was intentionally not regenerated.

The routed check then exposed a small construction-editor path violation (-0.212 ns). BUILD intact masks now derive directly from the saved content/frame layers, with separate runtime mask registers for damage. This removes duplicate per-edit mask updates and their long acceptance path while keeping a restored runtime copy ready for launch. The focused construction, module-contract and drag/drop tests pass with unchanged expectations.

Final validation: all 26 benches in the default runner pass (`tmp/role3_builder_final_simulations.log`). The final fully routed design uses 6,729 LUTs (32.35%), 2,375 registers (5.71%), 13 DSPs (14.44%) and no block RAM. Constrained 100 MHz setup/hold checks pass with +0.020 ns setup and +0.035 ns hold slack; setup margin is small and future edits must be rechecked. DRC has no error/critical-warning rules; its 49 warnings are DSP pipeline suggestions. The divided OLED clock and external I/O retain their existing incomplete timing coverage, with no added generated-clock constraint. Reports are under `tmp/role3_validation/`. No bitstream was generated.
