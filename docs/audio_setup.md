# Audio Pipeline & Pmod AMP2 Setup Guide

This document describes the hardware wiring, switch/menu controls, dual-voice BGM synthesizer, and prioritized SFX engine for **Bad Piggies FPGA ("Laggy Piggies")**.

---

## 1. Pmod AMP2 Hardware Connection (`JXADC`)

Plug the **Digilent Pmod AMP2** into the **top row of the `JXADC` PMOD header** (`JA1–JA4` / `JXADC[3:0]`), and connect headphones or a speaker to the 3.5 mm audio jack on the Pmod AMP2.

| `JXADC` Pin | FPGA Package Pin | Signal Name | Function |
| :--- | :---: | :--- | :--- |
| **`JXADC[0]`** | `J3` | `JXADC[0]` (`AIN`) | **8-bit PWM Audio Stream** (~390.6 kHz carrier from `sound_generator.v` & `bgm_player.v`) |
| **`JXADC[1]`** | `L3` | `JXADC[1]` (`GAIN`) | **Digital Gain Select** (driven low `1'b0` for clean 6 dB gain) |
| **`JXADC[2]`** | `M2` | `JXADC[2]` (`NC`) | Unused (`1'b0`) |
| **`JXADC[3]`** | `N2` | `JXADC[3]` (`~SHUTDOWN`) | **Active-Low Shutdown:** Driven high (`1'b1`) when audio is enabled; pulled low (`1'b0`) during reset or when muted |

---

## 2. Hardware Mute Switch (`SW0`) & On-Screen Sound Mixer

Audio output is controlled by both the **hardware mute switch (`SW0`)** and the **on-screen Sound Menu (`LP_SOUND`)**:

* **`SW0` (`mute_switch`):**
  - `SW0 = 0` (Down): Audio follows the on-screen Sound Mixer setting.
  - `SW0 = 1` (Up): **Hardware Master Mute** — immediately silences all BGM and SFX, pulls `JXADC[3]` (`~SHUTDOWN`) low to power down the amplifier, and displays **`MUTED BY SW0`** on the Sound Settings screen.
* **On-Screen Sound Mixer (`[GEAR]` $\to$ `[SOUND]`):**
  - **`[BGM: ON / OFF]`:** Toggles background music (`bgm_enable`).
  - **`[SFX: ON / OFF]`:** Toggles gameplay sound effects (`sfx_enable`).
  - **`[TEST SFX]`:** Plays a test chime (`sfx_test_pulse`) to verify speaker output.

---

## 3. Background Music Synthesizer (`bgm_player.v`)

`bgm_player.v` synthesizes 3 mode-dependent background tracks using compact distributed-LUT note tables and a dual-voice square/pulse mixer:

| `bgm_mode` | Active Game States | Track & Tempo | Synthesis Notes |
| :---: | :--- | :--- | :--- |
| **`2'b10`** | `LP_TITLE`, `LP_LEVEL_SELECT` | **Title Screen Fanfare** (135 BPM) | Upbeat brass-style melody with harmonic accompaniment |
| **`2'b00`** | `LP_BUILD`, `LP_GUIDE`, `LP_SETTINGS`, `LP_SOUND` | ***The Entertainer*** — Scott Joplin (96 BPM) | Ragtime lead melody + walking bassline |
| **`2'b01`** | `LP_RUN`, `LP_SUCCESS`, `LP_FAIL` | ***Bad Piggies Theme*** (155 BPM) | Fast-tempo main theme with dual-voice bassline; attenuated by `-6 dB` (`>> 1`) so runtime SFX cut through clearly |

---

## 4. Prioritized Sound Effects (`sound_controller.v`, `sound_generator.v`)

When a gameplay event occurs, `sound_controller.v` arbitrates overlapping triggers according to strict priority:

$$\text{Failure} > \text{Success} > \text{TNT Explosion} > \text{Terrain Collision} > \text{Balloon Pop} > \text{Vehicle Launch} > \text{UI Test}$$

While a high-priority SFX phrase is playing (`sfx_active`), `My_Top_Module.v` automatically ducks the BGM volume (`bgm_sample >> 2`) before summing (`bgm_ducked + sfx_sample`) so explosions, pops, and victory fanfares remain crisp without clipping the 8-bit PWM DAC.
