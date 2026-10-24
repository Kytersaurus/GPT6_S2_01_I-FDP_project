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

## Remaining integration work

TNT damage, spike detection, wall/ceiling collision, instruction screens, final level balancing and board testing remain. The recorded solutions currently prove reachability with the starter collision/world logic; they must be rechecked after real hazards are integrated. The fixed 96 by 64 maps do not scroll or zoom. Physical audio quality and the reported unwanted speaker click still need a fresh hardware test.
