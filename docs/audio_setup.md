# Game audio: Pmod AMP2 on JXADC

Owner: Role 1 - Kaushal.

## Hardware and programming

With the Basys3 off, connect the AMP2 to JXADC pins 1-6, aligning pin numbers and GND/VCC. Connect the speaker to the AMP2 jack. OLED construction uses JA; one OLED is enough for audio/control tests.

| AMP2 pin | Signal | Basys3 connection |
| --- | --- | --- |
| 1 | AIN | JXADC1 / `JXADC[0]`: PWM |
| 2 | GAIN | JXADC2 / `JXADC[1]`: high, lower 6 dB gain |
| 3 | NC | JXADC3 / `JXADC[2]`: zero, unused by AMP2 |
| 4 | Active-low shutdown | JXADC4 / `JXADC[3]`: low during reset/mute |
| 5 | GND | JXADC5 |
| 6 | VCC | JXADC6, 3.3 V |

Pinout, PWM support, gain and shutdown polarity follow the [Digilent AMP2 reference manual](https://digilent.com/reference/_media/pmod:pmod:pmodAMP2_rm.pdf). The XDC enables the existing JXADC pin lines for J3, L3, M2 and N2 and comments out the former JC mappings. Clock constraints are unchanged.

Reopen the saved project to load the new source names, or run `source scripts/add_team_sources.tcl` in the open project's Tcl Console and remove the obsolete `audio_beep.v` reference if still shown. Generate a fresh bitstream yourself. In Hardware Manager's Program Device dialog, explicitly choose `GPT_6_S2_01_I-FDP_project.runs/impl_1/My_Top_Module.bit`. Generating a new bitstream does not replace a previously selected `tmp/oled_board_test/` file in that dialog. The 24 October manual-beep/feedback hardware build predates these automatic sounds.

## Background music

`bgm_player.v` plays a quiet 38-note single-voice adaptation of **The Entertainer** by Scott Joplin (1902), using the pickup and bars 5-12. The upper chord notes are moved down an octave for a simple melody. Source: [Mutopia's public-domain edition, Mutopia-2016/11/25-263](https://www.mutopiaproject.org/cgibin/make-table.cgi?searchingfor=the+entertainer), typeset by Chris Sawer. This recreates note pitches/durations rather than playing a recording.

BUILD plays at 96 BPM; RUN uses the same melody at 120 BPM. Effects take over the shared PWM output and pause the melody, which resumes after the effect. Result states stop BGM for the result jingle. SW1 mutes/reset-clears both. Background amplitude is three PWM steps compared with eight for effects. `ENABLE_BGM=0` disables just the music at build time. `BGM_UNIT_CYCLES=15625000` is the base sixteenth-note period at 100 MHz; a small unit counter describes longer notes.

## Sounds and priorities

| Event | Sound | Total length | Connection |
| --- | --- | --- | --- |
| Failure / pig death | 440, 330, 220 Hz falling sequence | 420 ms | Accepted `failure_event` |
| Success | 660, 880, 1320 Hz rising sequence | 300 ms | Accepted `success_event` |
| Explosion | 160, 110, 70 Hz low falling sequence | 240 ms | Connected to accepted TNT explosions |
| Landing | 220 Hz low bump | 60 ms | First accepted grounded response after airborne, impact >=0.5 pixel/update |
| Balloon pop | 1600 Hz short tone | 40 ms | Non-empty pop mask accepted by builder |
| Launch / retry | 660, 990 Hz rising pair | 160 ms | Accepted `launch_event` |
| BTNR speaker test | Original 1000 Hz beep | 200 ms | Debounced right button |

Higher rows have higher priority. A new higher-priority event interrupts the current sound. Equal/lower requests while busy are discarded, including another pop; there is no backlog to play after a result. A held event plays once and must go low before another trigger. A batch of accepted balloon pops makes one cue. Muted events are consumed rather than replayed on unmute.

Mouse selection, dragging, placement/removal, invalid launch, BTNU and SW0 do not add generic click sounds over BGM. BTNC only sounds when the game actually accepts a launch/retry. TNT damage and explosion audio are connected. Landing impacts have audio; separate wall/ceiling impact sounds remain future work.

## Implementation

`sound_controller.v` selects a three-bit ID using `if/else` and edge-detection registers. `sound_generator.v` replaces the one-off `audio_beep.v`; it uses a `case` table and counters for frequency, note duration, note index, volume and PWM. All use the shared 100 MHz clock. IDs 1..7 are in increasing priority order; zero means no sound.

The carrier stays at 390.625 kHz, with 128/256 duty for silence. Tone amplitude rises from zero to eight in eight steps, giving a maximum duty range of 120..136/256, then fades back down. `AUDIO_FADE_CYCLES=50000` gives four-millisecond fades. Duty changes only between complete carrier frames. These measures soften deliberate note boundaries; they cannot prove that noise from wiring, power, programming or amplifier switching has disappeared. Higher-priority preemption and mute/reset are immediate cancellations and can still produce an audible transition.

The AMP2 remains enabled between sounds; `JXADC[3]` changes only for reset/mute, not for each game event. Retry/run initialisation and return to construction cancel old sounds without resetting the PWM carrier. Positive `AUDIO_NOTE_CYCLES=8000000` sets the base 80 ms note, with constant multiples for each profile. Keep the shortest note (`AUDIO_NOTE_CYCLES/2`) and test beep longer than `16*AUDIO_FADE_CYCLES`. `AUDIO_TONE_HALF_CYCLES` and `AUDIO_BEEP_CYCLES` retain the manual test settings. Shorter legal parameters are used by simulation.

## Board checklist

1. Set SW1 off. In BUILD, move/select/drag/remove parts and toggle SW0/BTNU. Expect the background melody with no extra click/beep effect. Note whether the previously reported unwanted speaker click still occurs.
2. Press and hold BTNR: hear one test beep. Release before a new test. SW1 on cancels a beep; off must not resume it. BTND stops audio and resets the game.
3. Construct three middle-row frames with a pig in the centre, an engine on the right and wheels in the bottom corners. With SW0 on, launch: hear the rising pair, then the success sequence at the goal. Staying on the result screen must not repeat it. Retry should produce a fresh launch cue, and BTNU should stop any old result sound.
4. Add two balloons above that vehicle's frames and launch with SW0 off. Wait for the launch cue to finish, then click each balloon separately. Expect one short pop per accepted action. Clicking the pig, an empty cell or a popped balloon stays silent. A pop during a higher-priority sound may be intentionally inaudible.
5. To exercise failure, add two balloons above that vehicle's middle-row frames. With integrated lift (24 per balloon, gravity 32), the valid vehicle rises even with all of those parts. Launch with SW0 off and let it rise out of bounds to hear the falling failure sequence. Retry/edit must restore the original construction.
6. A landing cue needs a genuine fall/landing, not gentle spawn contact. Launch that vehicle without balloons and with SW0 off, wait for ground contact, then press BTNL to jump. Expect one low bump when it lands. Holding BTNL must not repeatedly jump. SW2 reverses engine thrust independently of SW1 mute; BTNR remains the test beep.
7. Contact a TNT in RUN: verify damage and the explosion animation/sound. Pig death can interrupt the explosion tone because failure has higher priority. Retry restores the vehicle and TNT.

`sound_generator_tb` checks every profile's pitch table, exact note lengths, fades, complete PWM frames and cancellation. `bgm_player_tb` checks the melody, loop, quiet shared PWM, effect pause/resume, mute and reset. `single_oled_tb` checks BUILD/RUN/result tempo/enable wiring and global mute. With BGM disabled for isolation, `game_audio_tb` checks priority/preemption, simultaneous and held events, muted/drop behaviour, silent ordinary controls, accepted launch/pop/landing/results, retry/edit, BTNR and physical JXADC mute/reset wiring. New automatic audio still needs board verification and a fresh routed build.

On 24 October 2026, all twelve simulation benches and design-only synthesis passed. The full design estimate is 3,395 LUTs (16.32%), 1,506 flip-flops (3.62%) and zero block RAM/DSP use. Reports are in `tmp/audio_events_review/`. These results do not establish routed timing or physical sound quality.
