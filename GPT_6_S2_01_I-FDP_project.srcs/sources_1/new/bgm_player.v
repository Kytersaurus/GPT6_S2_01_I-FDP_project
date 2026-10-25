// Owner: Role 1 - Kaushal. Looping background music:
// - BUILD mode: The Entertainer, Scott Joplin (1902), extended melody (peak volume 4).
// - RUN mode: original gentle 16-note loop with rests (peak volume 2).
`timescale 1ns / 1ps
module bgm_player #(
    parameter integer UNIT_CYCLES = 15625000, // Sixteenth note at 96 beats/minute.
    parameter integer FADE_CYCLES = 50000
) (
    input wire clk, reset, enabled, pause, fast,
    output wire signed [3:0] audio_sample
);
    reg [6:0] note_index;
    reg [2:0] unit_index;
    reg [31:0] note_count, tone_count, fade_count;
    reg tone_high;
    reg [2:0] volume;
    reg [31:0] half_cycles;
    reg [2:0] units;
    reg last_fast;

    localparam integer FAST_UNIT_CYCLES = UNIT_CYCLES;
    localparam integer SLOW_SOUND_CYCLES = UNIT_CYCLES-UNIT_CYCLES/8;
    localparam integer FAST_SOUND_CYCLES = FAST_UNIT_CYCLES-FAST_UNIT_CYCLES/8;
    wire [31:0] unit_cycles = fast ? FAST_UNIT_CYCLES : UNIT_CYCLES;
    wire [31:0] unit_last = fast ? FAST_UNIT_CYCLES-1 : UNIT_CYCLES-1;
    wire [31:0] sound_end = fast ? FAST_SOUND_CYCLES : SLOW_SOUND_CYCLES;
    wire [31:0] fade_start = fast ? FAST_SOUND_CYCLES-4*FADE_CYCLES-1 : SLOW_SOUND_CYCLES-4*FADE_CYCLES-1;
    wire last_unit = (unit_index+3'd1 >= units);
    wire note_finished = last_unit && note_count >= unit_last;
    wire playing = enabled && !pause && !reset && half_cycles != 0 && !(last_unit && note_count >= sound_end);

    wire [2:0] max_volume = fast ? 3'd2 : 3'd4; // Softer in RUN so game SFX stand out!

    assign audio_sample = !playing ? 4'sd0 :
                          tone_high ? $signed({1'b0, volume}) : -$signed({1'b0, volume});

    // Pitch constants (100MHz / (2 * freq))
    localparam B3  = 202470,
               C4  = 191113, CS4 = 180387, D4  = 170262, DS4 = 160706,
               E4  = 151686, F4  = 143173, FS4 = 135135, G4  = 127551,
               GS4 = 120395, A4  = 113636, AS4 = 107259, B4  = 101235,
               C5  = 95556,  CS5 = 90193,  D5  = 85131,  DS5 = 80353,
               E5  = 75843,  F5  = 71586,  FS5 = 67568,  G5  = 63776,
               GS5 = 60197,  A5  = 56818,  AS5 = 53629,  B5  = 50618,
               C6  = 47778;

    always @* begin
        half_cycles = C5; units = 1;
        if (!fast) begin
            // BUILD MODE: The Entertainer (Scott Joplin) - Extended melody
            case (note_index)
                // Intro / Pickup
                0: begin half_cycles = D4; units = 1; end
                1: begin half_cycles = DS4; units = 1; end
                2: begin half_cycles = E4; units = 1; end
                3: begin half_cycles = C5; units = 2; end
                4: begin half_cycles = E4; units = 1; end
                5: begin half_cycles = C5; units = 2; end
                6: begin half_cycles = E4; units = 1; end
                7: begin half_cycles = C5; units = 6; end
                // Theme A - phrase 1
                8: begin half_cycles = C5; units = 1; end
                9: begin half_cycles = D5; units = 1; end
                10: begin half_cycles = DS5; units = 1; end
                11: begin half_cycles = E5; units = 1; end
                12: begin half_cycles = C5; units = 1; end
                13: begin half_cycles = D5; units = 1; end
                14: begin half_cycles = E5; units = 2; end
                15: begin half_cycles = B4; units = 1; end
                16: begin half_cycles = D5; units = 2; end
                17: begin half_cycles = C5; units = 4; end
                // Theme A - phrase 2
                18: begin half_cycles = D4; units = 1; end
                19: begin half_cycles = DS4; units = 1; end
                20: begin half_cycles = E4; units = 1; end
                21: begin half_cycles = C5; units = 2; end
                22: begin half_cycles = E4; units = 1; end
                23: begin half_cycles = C5; units = 2; end
                24: begin half_cycles = E4; units = 1; end
                25: begin half_cycles = C5; units = 6; end
                26: begin half_cycles = A4; units = 1; end
                27: begin half_cycles = G4; units = 1; end
                28: begin half_cycles = FS4; units = 1; end
                29: begin half_cycles = A4; units = 1; end
                30: begin half_cycles = C5; units = 1; end
                31: begin half_cycles = E5; units = 2; end
                32: begin half_cycles = D5; units = 1; end
                33: begin half_cycles = C5; units = 1; end
                34: begin half_cycles = A4; units = 1; end
                35: begin half_cycles = D5; units = 4; end
                // Theme A - phrase 3
                36: begin half_cycles = D4; units = 1; end
                37: begin half_cycles = DS4; units = 1; end
                38: begin half_cycles = E4; units = 1; end
                39: begin half_cycles = C5; units = 2; end
                40: begin half_cycles = E4; units = 1; end
                41: begin half_cycles = C5; units = 2; end
                42: begin half_cycles = E4; units = 1; end
                43: begin half_cycles = C5; units = 6; end
                // Theme A - phrase 4 (ending)
                44: begin half_cycles = C5; units = 1; end
                45: begin half_cycles = D5; units = 1; end
                46: begin half_cycles = DS5; units = 1; end
                47: begin half_cycles = E5; units = 1; end
                48: begin half_cycles = C5; units = 1; end
                49: begin half_cycles = D5; units = 1; end
                50: begin half_cycles = E5; units = 2; end
                51: begin half_cycles = B4; units = 1; end
                52: begin half_cycles = D5; units = 2; end
                53: begin half_cycles = C5; units = 4; end
                // Theme B - The rising stride section
                54: begin half_cycles = C5; units = 1; end
                55: begin half_cycles = D5; units = 1; end
                56: begin half_cycles = E5; units = 2; end
                57: begin half_cycles = C5; units = 1; end
                58: begin half_cycles = D5; units = 1; end
                59: begin half_cycles = E5; units = 2; end
                60: begin half_cycles = C5; units = 2; end
                61: begin half_cycles = D5; units = 1; end
                62: begin half_cycles = E5; units = 1; end
                63: begin half_cycles = C5; units = 1; end
                64: begin half_cycles = D5; units = 1; end
                65: begin half_cycles = C5; units = 1; end
                66: begin half_cycles = E5; units = 1; end
                67: begin half_cycles = G5; units = 4; end
                68: begin half_cycles = G5; units = 1; end
                69: begin half_cycles = A5; units = 1; end
                70: begin half_cycles = G5; units = 1; end
                71: begin half_cycles = E5; units = 1; end
                72: begin half_cycles = F5; units = 1; end
                73: begin half_cycles = D5; units = 2; end
                74: begin half_cycles = C5; units = 4; end
                default: begin half_cycles = C5; units = 1; end
            endcase
        end else begin
            // Original RUN melody. Zero pitch is a silent rest.
            case (note_index)
                0: begin half_cycles = C4; units = 2; end
                1: begin half_cycles = E4; units = 2; end
                2: begin half_cycles = G4; units = 2; end
                3: begin half_cycles = E4; units = 2; end
                4: begin half_cycles = A4; units = 2; end
                5: begin half_cycles = G4; units = 2; end
                6: begin half_cycles = D4; units = 2; end
                7: begin half_cycles = 0; units = 2; end
                8: begin half_cycles = F4; units = 2; end
                9: begin half_cycles = A4; units = 2; end
                10: begin half_cycles = G4; units = 2; end
                11: begin half_cycles = E4; units = 2; end
                12: begin half_cycles = D4; units = 2; end
                13: begin half_cycles = E4; units = 2; end
                14: begin half_cycles = C4; units = 2; end
                15: begin half_cycles = 0; units = 2; end
                default: begin half_cycles = 0; units = 2; end
            endcase
        end
    end

    wire [6:0] loop_limit = fast ? 7'd15 : 7'd74;
    wire [6:0] loop_start = fast ? 7'd0 : 7'd2; // The Entertainer loops back to the main theme after intro

    always @(posedge clk) begin
        if (reset || !enabled) begin
            note_index <= 0; unit_index <= 0; note_count <= 0; tone_count <= 0;
            fade_count <= 0; tone_high <= 0; volume <= 0; last_fast <= fast;
        end else if (fast != last_fast) begin
            // Mode switch between BUILD and RUN starts the new song from note 0
            last_fast <= fast;
            note_index <= 0; unit_index <= 0; note_count <= 0; tone_count <= 0;
            fade_count <= 0; tone_high <= 0; volume <= 0;
        end else if (pause) begin
            volume <= 0; fade_count <= 0;
        end else if (note_finished) begin
            note_index <= (note_index >= loop_limit) ? loop_start : note_index + 1'b1;
            unit_index <= 0; note_count <= 0; tone_count <= 0; fade_count <= 0;
            tone_high <= 0; volume <= 0;
        end else begin
            if (note_count >= unit_last) begin note_count <= 0; unit_index <= unit_index + 1'b1; end
            else note_count <= note_count + 1'b1;
            if (tone_count == half_cycles-1) begin tone_count <= 0; tone_high <= !tone_high; end
            else tone_count <= tone_count + 1'b1;
            if (fade_count == FADE_CYCLES-1) begin
                fade_count <= 0;
                if (last_unit && note_count >= fade_start) begin
                    if (volume != 0) volume <= volume - 1'b1;
                end else if (volume < max_volume) volume <= volume + 1'b1;
            end else fade_count <= fade_count + 1'b1;
        end
    end
endmodule
