# Game audio: Pmod AMP2 on JC

Owner: Role 1 - Kaushal.

## Hardware and programming

With the Basys3 off, connect the AMP2 to JC pins 1-6, aligning pin numbers and GND/VCC. Connect the speaker to the AMP2 jack. OLED construction uses JA; one OLED is enough for audio/control tests.

| AMP2 pin | Signal | Basys3 connection |
| --- | --- | --- |
| 1 | AIN | JC1 / `JC[0]`: PWM |
| 2 | GAIN | JC2 / `JC[1]`: high, lower 6 dB gain |
| 3 | NC | JC3 / `JC[2]`: zero, unused by AMP2 |
| 4 | Active-low shutdown | JC4 / `JC[3]`: low during reset/mute |
| 5 | GND | JC5 |
| 6 | VCC | JC6, 3.3 V |

Pinout, PWM support, gain and shutdown polarity follow the [Digilent AMP2 reference manual](https://digilent.com/reference/_media/pmod:pmod:pmodAMP2_rm.pdf). No new XDC mappings or clock constraints are needed for game audio.

Reopen the saved project to load the new source names, or run `source scripts/add_team_sources.tcl` in the open project's Tcl Console and remove the obsolete `audio_beep.v` reference if still shown. Generate a fresh bitstream yourself. In Hardware Manager's Program Device dialog, explicitly choose `GPT_6_S2_01_I-FDP_project.runs/impl_1/My_Top_Module.bit`. Generating a new bitstream does not replace a previously selected `tmp/oled_board_test/` file in that dialog. The 24 October manual-beep/feedback hardware build predates these automatic sounds.

## Sounds and priorities

| Event | Sound | Total length | Connection |
| --- | --- | --- | --- |
| Failure / pig death | 440, 330, 220 Hz falling sequence | 420 ms | Accepted `failure_event` |
| Success | 660, 880, 1320 Hz rising sequence | 300 ms | Accepted `success_event` |
| Explosion | 160, 110, 70 Hz low falling sequence | 240 ms | Prepared; Role 3 must drive `explosion_sound_event` |
| Landing | 220 Hz low bump | 60 ms | First accepted grounded response after airborne, impact >=0.5 pixel/update |
| Balloon pop | 1600 Hz short tone | 40 ms | Non-empty pop mask accepted by builder |
| Launch / retry | 660, 990 Hz rising pair | 160 ms | Accepted `launch_event` |
| BTNR speaker test | Original 1000 Hz beep | 200 ms | Debounced right button |

Higher rows have higher priority. A new higher-priority event interrupts the current sound. Equal/lower requests while busy are discarded, including another pop; there is no backlog to play after a result. A held event plays once and must go low before another trigger. A batch of accepted balloon pops makes one cue. Muted events are consumed rather than replayed on unmute.

Mouse selection, dragging, placement/removal, invalid launch, BTNU and SW0 do not have generic click sounds. BTNC only sounds when the game actually accepts a launch/retry. TNT damage/explosion triggering and wall/ceiling impacts remain Role 3 integrations, not test stubs in the hardware design.

## Implementation

`sound_controller.v` selects a three-bit ID using `if/else` and edge-detection registers. `sound_generator.v` replaces the one-off `audio_beep.v`; it uses a `case` table and counters for frequency, note duration, note index, volume and PWM. All use the shared 100 MHz clock. IDs 1..7 are in increasing priority order; zero means no sound.

The carrier stays at 390.625 kHz, with 128/256 duty for silence. Tone amplitude rises from zero to eight in eight steps, giving a maximum duty range of 120..136/256, then fades back down. `AUDIO_FADE_CYCLES=50000` gives four-millisecond fades. Duty changes only between complete carrier frames. These measures soften deliberate note boundaries; they cannot prove that noise from wiring, power, programming or amplifier switching has disappeared. Higher-priority preemption and mute/reset are immediate cancellations and can still produce an audible transition.

The AMP2 remains enabled between sounds; `JC[3]` changes only for reset/mute, not for each game event. Retry/run initialisation and return to construction cancel old sounds without resetting the PWM carrier. Positive `AUDIO_NOTE_CYCLES=8000000` sets the base 80 ms note, with constant multiples for each profile. Keep the shortest note (`AUDIO_NOTE_CYCLES/2`) and test beep longer than `16*AUDIO_FADE_CYCLES`. `AUDIO_TONE_HALF_CYCLES` and `AUDIO_BEEP_CYCLES` retain the manual test settings. Shorter legal parameters are used by simulation.

## Board checklist

1. Set SW1 off. In BUILD, move/select/drag/remove parts and toggle SW0/BTNU. Expect silence. Note whether the previously reported unwanted speaker click still occurs.
2. Press and hold BTNR: hear one test beep. Release before a new test. SW1 on cancels a beep; off must not resume it. BTND stops audio and resets the game.
3. With the preset build and SW0 on, launch: hear the rising pair, then the success sequence at the goal. Staying on the result screen must not repeat it. Retry should produce a fresh launch cue, and BTNU should stop any old result sound.
4. Add two balloons above the preset frames and launch with SW0 off. Wait for the launch cue to finish, then click each balloon separately. Expect one short pop per accepted action. Clicking the pig, an empty cell or a popped balloon stays silent. A pop during a higher-priority sound may be intentionally inaudible.
5. To exercise failure, add two balloons above the preset middle-row frames. With integrated lift (24 per balloon, gravity 32), the valid vehicle rises even with all preset parts. Launch with SW0 off and let it rise out of bounds to hear the falling failure sequence. Retry/edit must restore the original construction.
6. A landing cue needs a genuine fall/landing, not gentle spawn contact. Launch the preset without balloons and with SW0 off, wait for ground contact, then press BTNL to jump. Expect one low bump when it lands. Holding BTNL must not repeatedly jump. SW2 reverses engine thrust independently of SW1 mute; BTNR remains the test beep.
7. Explosion playback is simulation-tested. Physical explosions need Role 3's trigger. Do not claim TNT audio integration until that signal is connected.

`sound_generator_tb` checks every profile's pitch table, exact note lengths, fades, complete PWM frames and cancellation. `game_audio_tb` checks priority/preemption, simultaneous and held events, muted/drop behaviour, silent ordinary controls, accepted launch/pop/landing/results, retry/edit, BTNR and physical JC mute/reset wiring. New automatic audio still needs board verification and a fresh routed build.

On 24 October 2026, all twelve simulation benches and design-only synthesis passed. The full design estimate is 3,395 LUTs (16.32%), 1,506 flip-flops (3.62%) and zero block RAM/DSP use. Reports are in `tmp/audio_events_review/`. These results do not establish routed timing or physical sound quality.
