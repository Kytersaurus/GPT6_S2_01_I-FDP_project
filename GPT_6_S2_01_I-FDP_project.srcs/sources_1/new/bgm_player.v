// Owner: Role 1 - Kaushal. Quiet looping single-voice background music.
`timescale 1ns / 1ps
// The Entertainer, Scott Joplin (1902): simplified melody from bars 5-12,
// with the pickup and upper chord notes moved into one comfortable octave.
// Public-domain score: Mutopia-2016/11/25-263, typeset by Chris Sawer.
// https://www.mutopiaproject.org/cgibin/make-table.cgi?searchingfor=the+entertainer
module bgm_player #(
    parameter integer UNIT_CYCLES = 15625000, // Sixteenth note at 96 beats/minute.
    parameter integer FADE_CYCLES = 50000
) (
    input wire clk, reset, enabled, pause, fast,
    output wire signed [3:0] audio_sample
);
    reg [5:0] note_index;
    reg [2:0] unit_index;
    reg [31:0] note_count, tone_count, fade_count;
    reg tone_high;
    reg [1:0] volume;
    reg [31:0] half_cycles;
    reg [2:0] units;
    localparam integer FAST_UNIT_CYCLES = UNIT_CYCLES*4/5;
    localparam integer SLOW_SOUND_CYCLES = UNIT_CYCLES-UNIT_CYCLES/8;
    localparam integer FAST_SOUND_CYCLES = FAST_UNIT_CYCLES-FAST_UNIT_CYCLES/8;
    wire [31:0] unit_cycles = fast ? FAST_UNIT_CYCLES : UNIT_CYCLES;
    wire [31:0] unit_last = fast ? FAST_UNIT_CYCLES-1 : UNIT_CYCLES-1;
    wire [31:0] sound_end = fast ? FAST_SOUND_CYCLES : SLOW_SOUND_CYCLES;
    wire [31:0] fade_start = fast ? FAST_SOUND_CYCLES-3*FADE_CYCLES-1 : SLOW_SOUND_CYCLES-3*FADE_CYCLES-1;
    wire last_unit = (unit_index+3'd1 >= units);
    wire note_finished = last_unit && note_count >= unit_last;
    wire playing = enabled && !pause && !reset && !(last_unit && note_count >= sound_end);
    assign audio_sample = !playing ? 4'sd0 :
                          tone_high ? $signed({2'b00, volume}) : -$signed({2'b00, volume});

    // Pitch and length table; only counters and a case statement are needed.
    always @* begin
        half_cycles = 170262; units = 1;
        case (note_index)
            0: begin half_cycles = 170262; units = 1; end // D4
            1: begin half_cycles = 160706; units = 1; end // DS4
            2: begin half_cycles = 151686; units = 1; end // E4
            3: begin half_cycles = 95556; units = 2; end // C5
            4: begin half_cycles = 151686; units = 1; end // E4
            5: begin half_cycles = 95556; units = 2; end // C5
            6: begin half_cycles = 151686; units = 1; end // E4
            7: begin half_cycles = 95556; units = 6; end // C5
            8: begin half_cycles = 95556; units = 1; end // C5
            9: begin half_cycles = 85131; units = 1; end // D5
            10: begin half_cycles = 80353; units = 1; end // DS5
            11: begin half_cycles = 75843; units = 1; end // E5
            12: begin half_cycles = 95556; units = 1; end // C5
            13: begin half_cycles = 85131; units = 1; end // D5
            14: begin half_cycles = 75843; units = 2; end // E5
            15: begin half_cycles = 101238; units = 1; end // B4
            16: begin half_cycles = 85131; units = 2; end // D5
            17: begin half_cycles = 95556; units = 6; end // C5
            18: begin half_cycles = 170262; units = 1; end // D4
            19: begin half_cycles = 160706; units = 1; end // DS4
            20: begin half_cycles = 151686; units = 1; end // E4
            21: begin half_cycles = 95556; units = 2; end // C5
            22: begin half_cycles = 151686; units = 1; end // E4
            23: begin half_cycles = 95556; units = 2; end // C5
            24: begin half_cycles = 151686; units = 1; end // E4
            25: begin half_cycles = 95556; units = 7; end // C5
            26: begin half_cycles = 113636; units = 1; end // A4
            27: begin half_cycles = 127553; units = 1; end // G4
            28: begin half_cycles = 135137; units = 1; end // FS4
            29: begin half_cycles = 113636; units = 1; end // A4
            30: begin half_cycles = 95556; units = 1; end // C5
            31: begin half_cycles = 75843; units = 2; end // E5
            32: begin half_cycles = 85131; units = 1; end // D5
            33: begin half_cycles = 95556; units = 1; end // C5
            34: begin half_cycles = 113636; units = 1; end // A4
            35: begin half_cycles = 85131; units = 6; end // D5
            36: begin half_cycles = 170262; units = 1; end // D4
            37: begin half_cycles = 160706; units = 1; end // DS4
            default: begin half_cycles = 170262; units = 1; end
        endcase
    end

    always @(posedge clk) begin
        if (reset || !enabled) begin
            note_index <= 0; unit_index <= 0; note_count <= 0; tone_count <= 0;
            fade_count <= 0; tone_high <= 0; volume <= 0;
        end else if (pause) begin
            // Sound effects own the output; resume this note afterwards.
            volume <= 0; fade_count <= 0;
        end else if (note_finished) begin
            note_index <= (note_index == 37) ? 6'd2 : note_index + 1'b1;
            unit_index <= 0; note_count <= 0; tone_count <= 0; fade_count <= 0;
            tone_high <= 0; volume <= 0;
        end else begin
            // Count fixed sixteenth-note units; long notes need no wide multiplication.
            if (note_count >= unit_last) begin note_count <= 0; unit_index <= unit_index + 1'b1; end
            else note_count <= note_count + 1'b1;
            if (tone_count == half_cycles-1) begin tone_count <= 0; tone_high <= !tone_high; end
            else tone_count <= tone_count + 1'b1;
            if (fade_count == FADE_CYCLES-1) begin
                fade_count <= 0;
                if (last_unit && note_count >= fade_start) begin
                    if (volume != 0) volume <= volume - 1'b1;
                end else if (volume < 3) volume <= volume + 1'b1;
            end else fade_count <= fade_count + 1'b1;
        end
    end
endmodule
