// Owner: Role 1 - Kaushal. Short tone sequences and quiet PWM audio on JXADC.
`timescale 1ns / 1ps
`include "game_defs.vh"
module sound_generator #(
    parameter integer TONE_HALF_CYCLES = 50000, // BTNR test: 1 kHz at 100 MHz.
    parameter integer BEEP_CYCLES = 20000000,
    parameter integer NOTE_CYCLES = 8000000,    // Base game note: 80 ms.
    parameter integer FADE_CYCLES = 50000      // Eight 0.5 ms volume steps.
) (
    input wire clk, reset, mute, cancel, start,
    input wire [2:0] sound_id, master_volume,
    input wire signed [3:0] bgm_sample,
    output reg busy,
    output reg [2:0] active_sound,
    output wire audio_pwm
);
    reg [1:0] note_index;
    reg [31:0] tone_count, duration_count, fade_count;
    reg tone_high;
    reg [3:0] volume;
    wire [3:0] max_volume = master_volume==0 ? 0 : master_volume==1 ? 3 :
                                 master_volume==2 ? 6 : master_volume==3 ? 8 : 11;
    reg [7:0] pwm_count, pwm_level;
    reg [31:0] half_cycles, note_cycles;
    reg [1:0] last_note;
    wire signed [8:0] music_level = 9'sd128 + bgm_sample;
    wire [7:0] requested_level = (mute || reset || cancel) ? 8'd128 :
                                busy ? (tone_high ? 8'd128+volume : 8'd128-volume) : music_level[7:0];
    assign audio_pwm = (pwm_count < pwm_level);

    // Each row describes a sound using ordinary counters and a short case table.
    // Constant parameter divisions below do not create runtime dividers.
    always @* begin
        half_cycles = TONE_HALF_CYCLES; note_cycles = BEEP_CYCLES; last_note = 0;
        case (active_sound)
            `LP_SOUND_LAUNCH: begin
                last_note = 1; note_cycles = NOTE_CYCLES;
                half_cycles = (note_index == 0) ? 75758 : 50505; // 660 -> 990 Hz.
            end
            `LP_SOUND_POP: begin
                note_cycles = NOTE_CYCLES/2; half_cycles = 31250; // 1600 Hz.
            end
            `LP_SOUND_COLLISION: begin
                note_cycles = NOTE_CYCLES*3/4; half_cycles = 227273; // 220 Hz.
            end
            `LP_SOUND_EXPLOSION: begin
                last_note = 2; note_cycles = NOTE_CYCLES;
                case (note_index)
                    0: half_cycles = 312500; // 160 -> 110 -> 70 Hz.
                    1: half_cycles = 454545;
                    default: half_cycles = 714286;
                endcase
            end
            `LP_SOUND_SUCCESS: begin
                last_note = 2; note_cycles = NOTE_CYCLES*5/4;
                case (note_index)
                    0: half_cycles = 75758; // 660 -> 880 -> 1320 Hz.
                    1: half_cycles = 56818;
                    default: half_cycles = 37879;
                endcase
            end
            `LP_SOUND_FAILURE: begin
                last_note = 2; note_cycles = NOTE_CYCLES*7/4;
                case (note_index)
                    0: half_cycles = 113636; // 440 -> 330 -> 220 Hz.
                    1: half_cycles = 151515;
                    default: half_cycles = 227273;
                endcase
            end
            default: begin end // NONE or the original BTNR test tone.
        endcase
    end

    // Keep the carrier running in silence. Change duty only between PWM frames,
    // avoiding short extra pulses when the tone/volume changes mid-frame.
    always @(posedge clk) begin
        if (reset) begin pwm_count <= 0; pwm_level <= 128; end
        else begin
            pwm_count <= pwm_count + 1'b1;
            if (pwm_count == 255) pwm_level <= requested_level;
        end
    end

    always @(posedge clk) begin
        if (reset || mute || cancel) begin
            busy <= 0; active_sound <= `LP_SOUND_NONE; note_index <= 0;
            tone_count <= 0; duration_count <= 0; fade_count <= 0;
            tone_high <= 0; volume <= 0;
        end else if (start && sound_id != `LP_SOUND_NONE) begin
            // The controller only sends an idle request or a higher-priority one.
            busy <= 1; active_sound <= sound_id; note_index <= 0;
            tone_count <= 0; duration_count <= 0; fade_count <= 0;
            tone_high <= 0; volume <= 0;
        end else if (busy) begin
            if (duration_count == note_cycles-1) begin
                tone_count <= 0; duration_count <= 0; fade_count <= 0;
                tone_high <= 0; volume <= 0;
                if (note_index == last_note) begin busy <= 0; active_sound <= `LP_SOUND_NONE; end
                else note_index <= note_index + 1'b1;
            end else begin
                duration_count <= duration_count + 1'b1;
                if (tone_count == half_cycles-1) begin tone_count <= 0; tone_high <= !tone_high; end
                else tone_count <= tone_count + 1'b1;
                // Fade each note from silence and back to silence in eight steps.
                // Keep every note longer than 16*FADE_CYCLES when changing settings.
                if (fade_count == FADE_CYCLES-1) begin
                    fade_count <= 0;
                    if (duration_count >= note_cycles-11*FADE_CYCLES-1) begin
                        if (volume != 0) volume <= volume - 1'b1;
                    end else if (volume < max_volume) volume <= volume + 1'b1;
                    else if (volume > max_volume) volume <= volume - 1'b1;
                end else fade_count <= fade_count + 1'b1;
            end
        end
    end
endmodule
