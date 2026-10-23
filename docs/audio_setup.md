# First audio test: Pmod AMP2 on JC

Owner: Role 1 - Kaushal.

The first milestone is one short beep from the right button. Game-event sounds and their priority handling follow after this works on the board.

## Connect the hardware

Switch the Basys3 off before connecting the Pmod AMP2. Use JC pins 1-6, aligning the pin numbers and the GND/VCC labels. Connect the lab speaker to the AMP2 audio jack.

| AMP2 pin | Signal | Basys3 connection | Verilog connection |
| --- | --- | --- | --- |
| 1 | AIN | JC1, FPGA K17 | `JC[0]`: audio PWM |
| 2 | GAIN | JC2, FPGA M18 | `JC[1]`: high for lower 6 dB gain |
| 3 | NC | JC3, FPGA N17 | `JC[2]`: zero; AMP2 leaves this pin unconnected |
| 4 | Active-low shutdown | JC4, FPGA P18 | `JC[3]`: low during reset/mute, high otherwise |
| 5 | GND | JC5 | Ground supplied by the header |
| 6 | VCC | JC6 | 3.3 V supplied by the header |

The AMP2 accepts PWM through its input reconstruction filter. Its pin assignments, gain levels and shutdown polarity are specified in the [Digilent Pmod AMP2 reference manual](https://digilent.com/reference/_media/pmod:pmod:pmodAMP2_rm.pdf). FPGA package-pin mappings come from the existing Basys3 XDC. The change only uncomments existing mappings for BTNR, SW1 and JC1-JC4.

## Program and test

1. Reopen `GPT_6_S2_01_I-FDP_project.xpr` to load the new source registration, or use `source scripts/add_team_sources.tcl` with the project open.
2. Generate a fresh bitstream in Vivado, then program the Basys3. The previous balloon-test bitstream does not include audio.
3. Set SW1 to zero to unmute. Press BTNR once: expect a roughly 1 kHz beep lasting 0.2 seconds.
4. Hold BTNR: expect one beep. Release it before pressing again.
5. Set SW1 to one: the amplifier shuts down and a playing beep is cancelled. Unmuting must not resume the cancelled beep or replay a press made while muted.
6. Press BTND during a beep: playback stops and the game resets.

The test button works in any game state. SW0 continues to control the engine. This first audio stage does not yet play sounds automatically on launch, victory, failure, collisions or balloon popping.

## How the code works

`input_controller.v` uses the existing debouncer to produce one `beep_press` pulse and samples SW1 through two registers. `audio_beep.v` uses the shared 100 MHz clock for three counters:

- A tone counter changes the tone level every 50,000 cycles. Two halves form one period, giving `100000000 / (2 * 50000) = 1000 Hz`.
- A duration counter stops playback after 20,000,000 cycles, or 0.2 seconds.
- An eight-bit PWM counter repeats every 256 cycles, giving a 390.625 kHz PWM carrier. Comparing it with 120 or 136 makes a small square-wave audio signal after filtering. Idle/muted output uses 128, the centred 50% duty level.

The tone and PWM are data outputs; no extra clock is created. Requests while busy are ignored. Mute/reset cancel playback rather than pausing it. The AMP2 stays enabled between beeps while unmuted, and the PWM returns to its centred idle level.

`TONE_HALF_CYCLES` and `BEEP_CYCLES` are positive cycle-count parameters. The top exposes them as `AUDIO_TONE_HALF_CYCLES` and `AUDIO_BEEP_CYCLES`; the testbench shortens them for simulation.

## Validation and next stage

On 22 October 2026, all ten simulation benches passed. `sim/audio_beep_tb.v` checks output duty, tone timing, exact duration, busy requests, mute/reset, held-button suppression, JC control polarity and independence from engine/game controls. Hardware sound and a new routed build still need verification. The previous resource/timing reports predate this module.

After the beep works physically, extend the generator to accept a chosen tone/duration, then connect the existing launch/success/failure events through a small sound controller. Add event priority and duplicate suppression there; add collision/TNT events when their producers are ready.
