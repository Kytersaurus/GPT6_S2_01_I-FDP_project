// Owner: Role 1 - Kaushal. Looping background music:
// - BUILD mode: The Entertainer, Scott Joplin (1902), extended melody (peak volume 4).
// - RUN mode: Bad Piggies main-theme opening, single voice, one octave lower.
// Melody reference: JarzaClay/wild-west-midi, Bad Piggies Theme.mid (track 0).
`timescale 1ns / 1ps
module bgm_player #(
    parameter integer UNIT_CYCLES = 15625000, // Sixteenth note at 96 beats/minute.
    parameter integer FADE_CYCLES = 50000
) (
    input wire clk, reset, enabled, pause, fast,
    input wire [2:0] master_volume,
    output wire signed [3:0] audio_sample
);
    reg [8:0] note_index;
    reg [3:0] unit_index;
    reg [31:0] note_count, tone_count, fade_count;
    reg tone_high;
    reg [2:0] volume;
    reg [31:0] half_cycles;
    reg [3:0] units;
    reg last_fast;

    localparam integer FAST_UNIT_CYCLES = UNIT_CYCLES*96/155; // Main theme: 155 BPM.
    localparam integer SLOW_SOUND_CYCLES = UNIT_CYCLES-UNIT_CYCLES/8;
    localparam integer FAST_SOUND_CYCLES = FAST_UNIT_CYCLES-FAST_UNIT_CYCLES/8;
    wire [31:0] unit_cycles = fast ? FAST_UNIT_CYCLES : UNIT_CYCLES;
    wire [31:0] unit_last = fast ? FAST_UNIT_CYCLES-1 : UNIT_CYCLES-1;
    wire [31:0] sound_end = fast ? FAST_SOUND_CYCLES : SLOW_SOUND_CYCLES;
    wire [31:0] fade_start = fast ? FAST_SOUND_CYCLES-4*FADE_CYCLES-1 : SLOW_SOUND_CYCLES-4*FADE_CYCLES-1;
    wire last_unit = (unit_index+4'd1 >= units);
    wire note_finished = last_unit && note_count >= unit_last;
    wire playing = enabled && !pause && !reset && half_cycles != 0 && !(last_unit && note_count >= sound_end);

    wire [2:0] max_volume = fast ? ((master_volume+1'b1)>>1) : master_volume; // Softer in RUN so game SFX stand out!

    wire [8:0] loop_limit = fast ? 9'd258 : 9'd106;
    wire [8:0] loop_start = fast ? 9'd0 : 9'd2; // The Entertainer loops back to the main theme after intro

    // Two small square-wave voices share one signed sample; no recorded audio RAM.
    reg [8:0] song_unit;
    reg [31:0] bass_count, bass_fade_count;
    reg bass_high;
    reg [1:0] bass_volume;
    reg [31:0] bass_half_cycles;
    wire [1:0] bass_max = master_volume<2 ? 0 : master_volume==4 ? 2 : 1;
    wire music_enabled = enabled && !pause && !reset;
    wire signed [3:0] melody_sample = !playing ? 4'sd0 :
                          tone_high ? $signed({1'b0, volume}) : -$signed({1'b0, volume});
    wire signed [3:0] bass_sample = !music_enabled ? 4'sd0 :
                          bass_high ? $signed({2'b0,bass_volume}) : -$signed({2'b0,bass_volume});
    assign audio_sample = melody_sample + bass_sample;

    // A bass note spans two sixteenth-note units and follows the song's beat.
    // Pause freezes both voices together; each note has a short attack/release.
    always @(posedge clk) begin
        if (reset || !enabled || fast!=last_fast) begin
            song_unit<=0; bass_count<=0; bass_fade_count<=0; bass_high<=0; bass_volume<=0;
        end else if (pause) begin bass_volume<=0; bass_fade_count<=0; end
        else begin
            if (note_count>=unit_last)
                song_unit<=note_finished && note_index>=loop_limit ? 0 : song_unit+1'b1;
            if (note_count==0 && !song_unit[0]) begin
                bass_count<=0; bass_high<=0; bass_volume<=0; bass_fade_count<=0;
            end else begin
                if (bass_count>=bass_half_cycles-1) begin bass_count<=0; bass_high<=!bass_high; end
                else bass_count<=bass_count+1'b1;
                if (bass_fade_count==FADE_CYCLES-1) begin
                    bass_fade_count<=0;
                    if (song_unit[0] && note_count>=fade_start) begin
                        if (bass_volume!=0) bass_volume<=bass_volume-1'b1;
                    end else if (bass_volume<bass_max) bass_volume<=bass_volume+1'b1;
                    else if (bass_volume>bass_max) bass_volume<=bass_volume-1'b1;
                end else bass_fade_count<=bass_fade_count+1'b1;
            end
        end
    end

    always @* begin
        bass_half_cycles=382226; // C3
        if (fast) begin
            // Single bass voice from the same main-theme MIDI accompaniment.
            case (song_unit[8:1])
                0: bass_half_cycles = 382226;
                1: bass_half_cycles = 321412;
                2: bass_half_cycles = 510210;
                3: bass_half_cycles = 321412;
                4: bass_half_cycles = 382226;
                5: bass_half_cycles = 321412;
                6: bass_half_cycles = 510210;
                7: bass_half_cycles = 321412;
                8: bass_half_cycles = 321412;
                9: bass_half_cycles = 255105;
                10: bass_half_cycles = 429034;
                11: bass_half_cycles = 255105;
                12: bass_half_cycles = 321412;
                13: bass_half_cycles = 255105;
                14: bass_half_cycles = 429034;
                15: bass_half_cycles = 255105;
                16: bass_half_cycles = 429034;
                17: bass_half_cycles = 340524;
                18: bass_half_cycles = 572691;
                19: bass_half_cycles = 340524;
                20: bass_half_cycles = 429034;
                21: bass_half_cycles = 340524;
                22: bass_half_cycles = 572691;
                23: bass_half_cycles = 340524;
                24: bass_half_cycles = 481574;
                25: bass_half_cycles = 382226;
                26: bass_half_cycles = 642824;
                27: bass_half_cycles = 382226;
                28: bass_half_cycles = 510210;
                29: bass_half_cycles = 404954;
                30: bass_half_cycles = 681049;
                31: bass_half_cycles = 404954;
                32: bass_half_cycles = 382226;
                33: bass_half_cycles = 321412;
                34: bass_half_cycles = 510210;
                35: bass_half_cycles = 321412;
                36: bass_half_cycles = 382226;
                37: bass_half_cycles = 321412;
                38: bass_half_cycles = 510210;
                39: bass_half_cycles = 321412;
                40: bass_half_cycles = 321412;
                41: bass_half_cycles = 255105;
                42: bass_half_cycles = 429034;
                43: bass_half_cycles = 255105;
                44: bass_half_cycles = 321412;
                45: bass_half_cycles = 255105;
                46: bass_half_cycles = 429034;
                47: bass_half_cycles = 255105;
                48: bass_half_cycles = 429034;
                49: bass_half_cycles = 340524;
                50: bass_half_cycles = 572691;
                51: bass_half_cycles = 340524;
                52: bass_half_cycles = 429034;
                53: bass_half_cycles = 340524;
                54: bass_half_cycles = 572691;
                55: bass_half_cycles = 340524;
                56: bass_half_cycles = 481574;
                57: bass_half_cycles = 382226;
                58: bass_half_cycles = 642824;
                59: bass_half_cycles = 382226;
                60: bass_half_cycles = 510210;
                61: bass_half_cycles = 404954;
                62: bass_half_cycles = 681049;
                63: bass_half_cycles = 404954;
                64: bass_half_cycles = 481574;
                65: bass_half_cycles = 382226;
                66: bass_half_cycles = 642824;
                67: bass_half_cycles = 382226;
                68: bass_half_cycles = 481574;
                69: bass_half_cycles = 382226;
                70: bass_half_cycles = 642824;
                71: bass_half_cycles = 382226;
                72: bass_half_cycles = 572691;
                73: bass_half_cycles = 481574;
                74: bass_half_cycles = 764451;
                75: bass_half_cycles = 481574;
                76: bass_half_cycles = 572691;
                77: bass_half_cycles = 481574;
                78: bass_half_cycles = 764451;
                79: bass_half_cycles = 481574;
                80: bass_half_cycles = 429034;
                81: bass_half_cycles = 340524;
                82: bass_half_cycles = 572691;
                83: bass_half_cycles = 340524;
                84: bass_half_cycles = 429034;
                85: bass_half_cycles = 340524;
                86: bass_half_cycles = 572691;
                87: bass_half_cycles = 340524;
                88: bass_half_cycles = 481574;
                89: bass_half_cycles = 382226;
                90: bass_half_cycles = 642824;
                91: bass_half_cycles = 382226;
                92: bass_half_cycles = 510210;
                93: bass_half_cycles = 404954;
                94: bass_half_cycles = 681049;
                95: bass_half_cycles = 404954;
                96: bass_half_cycles = 481574;
                97: bass_half_cycles = 382226;
                98: bass_half_cycles = 642824;
                99: bass_half_cycles = 382226;
                100: bass_half_cycles = 481574;
                101: bass_half_cycles = 382226;
                102: bass_half_cycles = 642824;
                103: bass_half_cycles = 382226;
                104: bass_half_cycles = 572691;
                105: bass_half_cycles = 481574;
                106: bass_half_cycles = 764451;
                107: bass_half_cycles = 481574;
                108: bass_half_cycles = 572691;
                109: bass_half_cycles = 481574;
                110: bass_half_cycles = 764451;
                111: bass_half_cycles = 481574;
                112: bass_half_cycles = 429034;
                113: bass_half_cycles = 340524;
                114: bass_half_cycles = 572691;
                115: bass_half_cycles = 340524;
                116: bass_half_cycles = 429034;
                117: bass_half_cycles = 340524;
                118: bass_half_cycles = 572691;
                119: bass_half_cycles = 340524;
                120: bass_half_cycles = 510210;
                121: bass_half_cycles = 382226;
                122: bass_half_cycles = 481574;
                123: bass_half_cycles = 382226;
                124: bass_half_cycles = 510210;
                125: bass_half_cycles = 382226;
                126: bass_half_cycles = 481574;
                127: bass_half_cycles = 382226;
                128: bass_half_cycles = 510210;
                129: bass_half_cycles = 481574;
                130: bass_half_cycles = 510210;
                131: bass_half_cycles = 481574;
                132: bass_half_cycles = 510210;
                133: bass_half_cycles = 481574;
                134: bass_half_cycles = 510210;
                135: bass_half_cycles = 481574;
                136: bass_half_cycles = 510210;
                137: bass_half_cycles = 481574;
                138: bass_half_cycles = 510210;
                139: bass_half_cycles = 481574;
                140: bass_half_cycles = 510210;
                141: bass_half_cycles = 481574;
                142: bass_half_cycles = 454545;
                143: bass_half_cycles = 404954;
                144: bass_half_cycles = 382226;
                145: bass_half_cycles = 321412;
                146: bass_half_cycles = 510210;
                147: bass_half_cycles = 321412;
                148: bass_half_cycles = 382226;
                149: bass_half_cycles = 321412;
                150: bass_half_cycles = 510210;
                151: bass_half_cycles = 321412;
                152: bass_half_cycles = 321412;
                153: bass_half_cycles = 255105;
                154: bass_half_cycles = 429034;
                155: bass_half_cycles = 255105;
                156: bass_half_cycles = 321412;
                157: bass_half_cycles = 255105;
                158: bass_half_cycles = 429034;
                159: bass_half_cycles = 255105;
                160: bass_half_cycles = 429034;
                161: bass_half_cycles = 340524;
                162: bass_half_cycles = 572691;
                163: bass_half_cycles = 340524;
                164: bass_half_cycles = 429034;
                165: bass_half_cycles = 340524;
                166: bass_half_cycles = 572691;
                167: bass_half_cycles = 340524;
                168: bass_half_cycles = 481574;
                169: bass_half_cycles = 382226;
                170: bass_half_cycles = 642824;
                171: bass_half_cycles = 382226;
                172: bass_half_cycles = 510210;
                173: bass_half_cycles = 404954;
                174: bass_half_cycles = 681049;
                175: bass_half_cycles = 404954;
                176: bass_half_cycles = 382226;
                177: bass_half_cycles = 321412;
                178: bass_half_cycles = 510210;
                179: bass_half_cycles = 321412;
                180: bass_half_cycles = 382226;
                181: bass_half_cycles = 321412;
                182: bass_half_cycles = 510210;
                183: bass_half_cycles = 321412;
                184: bass_half_cycles = 321412;
                185: bass_half_cycles = 255105;
                186: bass_half_cycles = 429034;
                187: bass_half_cycles = 255105;
                188: bass_half_cycles = 321412;
                189: bass_half_cycles = 255105;
                190: bass_half_cycles = 429034;
                191: bass_half_cycles = 255105;
                192: bass_half_cycles = 429034;
                193: bass_half_cycles = 340524;
                194: bass_half_cycles = 572691;
                195: bass_half_cycles = 340524;
                196: bass_half_cycles = 429034;
                197: bass_half_cycles = 340524;
                198: bass_half_cycles = 572691;
                199: bass_half_cycles = 340524;
                200: bass_half_cycles = 481574;
                201: bass_half_cycles = 382226;
                202: bass_half_cycles = 642824;
                203: bass_half_cycles = 382226;
                204: bass_half_cycles = 510210;
                205: bass_half_cycles = 404954;
                206: bass_half_cycles = 681049;
                207: bass_half_cycles = 404954;
                208: bass_half_cycles = 481574;
                209: bass_half_cycles = 382226;
                210: bass_half_cycles = 642824;
                211: bass_half_cycles = 382226;
                212: bass_half_cycles = 481574;
                213: bass_half_cycles = 382226;
                214: bass_half_cycles = 642824;
                215: bass_half_cycles = 382226;
                216: bass_half_cycles = 572691;
                217: bass_half_cycles = 481574;
                218: bass_half_cycles = 764451;
                219: bass_half_cycles = 481574;
                220: bass_half_cycles = 572691;
                221: bass_half_cycles = 481574;
                222: bass_half_cycles = 764451;
                223: bass_half_cycles = 481574;
                224: bass_half_cycles = 429034;
                225: bass_half_cycles = 340524;
                226: bass_half_cycles = 572691;
                227: bass_half_cycles = 340524;
                228: bass_half_cycles = 429034;
                229: bass_half_cycles = 340524;
                230: bass_half_cycles = 572691;
                231: bass_half_cycles = 340524;
                232: bass_half_cycles = 481574;
                233: bass_half_cycles = 382226;
                234: bass_half_cycles = 642824;
                235: bass_half_cycles = 382226;
                236: bass_half_cycles = 510210;
                237: bass_half_cycles = 404954;
                238: bass_half_cycles = 681049;
                239: bass_half_cycles = 404954;
                240: bass_half_cycles = 481574;
                241: bass_half_cycles = 382226;
                242: bass_half_cycles = 642824;
                243: bass_half_cycles = 382226;
                244: bass_half_cycles = 481574;
                245: bass_half_cycles = 382226;
                246: bass_half_cycles = 642824;
                247: bass_half_cycles = 382226;
                248: bass_half_cycles = 572691;
                249: bass_half_cycles = 481574;
                250: bass_half_cycles = 764451;
                251: bass_half_cycles = 481574;
                252: bass_half_cycles = 572691;
                253: bass_half_cycles = 481574;
                254: bass_half_cycles = 764451;
                255: bass_half_cycles = 481574;
                default: bass_half_cycles=382226;
            endcase
        end else begin
            // Simple C/F/G stride accompaniment for the BUILD arrangement.
            case (song_unit[5:4])
                0,3: bass_half_cycles=song_unit[2] ? 510204 : 382226; // G2 / C3
                1: bass_half_cycles=song_unit[2] ? 382226 : 286345;   // C3 / F3
                2: bass_half_cycles=song_unit[2] ? 340524 : 510204;   // D3 / G2
            endcase
        end
    end

    // Pitch constants (100MHz / (2 * freq))
    localparam B3  = 202470,
               C4  = 191113, CS4 = 180387, D4  = 170262, DS4 = 160706,
               E4  = 151686, F4  = 143173, FS4 = 135135, G4  = 127551,
               GS4 = 120395, A4  = 113636, AS4 = 107259, B4  = 101235,
               C5  = 95556,  CS5 = 90193,  D5  = 85131,  DS5 = 80353,
               E5  = 75843,  F5  = 71586,  FS5 = 67568,  G5  = 63776,
               GS5 = 60197,  A5  = 56818,  AS5 = 53629,  B5  = 50618,
               C6  = 47778;

    localparam A3 = 227273;
    localparam AS3 = 214517;
    localparam C3 = 382226;
    localparam D3 = 340524;
    localparam DS3 = 321412;
    localparam F3 = 286346;
    localparam G3 = 255105;
    localparam GS3 = 240787;

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
                // Original bridge for this single-voice ragtime arrangement.
                75: begin half_cycles = F4; units = 2; end
                76: begin half_cycles = A4; units = 1; end
                77: begin half_cycles = C5; units = 1; end
                78: begin half_cycles = E5; units = 2; end
                79: begin half_cycles = D5; units = 1; end
                80: begin half_cycles = C5; units = 1; end
                81: begin half_cycles = A4; units = 2; end
                82: begin half_cycles = F4; units = 2; end
                83: begin half_cycles = G4; units = 2; end
                84: begin half_cycles = B4; units = 1; end
                85: begin half_cycles = D5; units = 1; end
                86: begin half_cycles = F5; units = 2; end
                87: begin half_cycles = E5; units = 1; end
                88: begin half_cycles = D5; units = 1; end
                89: begin half_cycles = B4; units = 2; end
                90: begin half_cycles = G4; units = 2; end
                91: begin half_cycles = E4; units = 2; end
                92: begin half_cycles = G4; units = 1; end
                93: begin half_cycles = C5; units = 1; end
                94: begin half_cycles = E5; units = 2; end
                95: begin half_cycles = G5; units = 1; end
                96: begin half_cycles = E5; units = 1; end
                97: begin half_cycles = C5; units = 2; end
                98: begin half_cycles = A4; units = 2; end
                99: begin half_cycles = F4; units = 2; end
                100: begin half_cycles = A4; units = 1; end
                101: begin half_cycles = D5; units = 1; end
                102: begin half_cycles = FS5; units = 2; end
                103: begin half_cycles = G5; units = 2; end
                104: begin half_cycles = D5; units = 2; end
                105: begin half_cycles = B4; units = 2; end
                106: begin half_cycles = C5; units = 4; end
                default: begin half_cycles = C5; units = 1; end
            endcase
        end else begin
            // Main-theme lead, 32 bars (about 50 seconds), transposed down one octave.
            case (note_index)
                0: begin half_cycles = C5; units = 4; end
                1: begin half_cycles = C5; units = 3; end
                2: begin half_cycles = AS4; units = 1; end
                3: begin half_cycles = C5; units = 2; end
                4: begin half_cycles = AS4; units = 2; end
                5: begin half_cycles = GS4; units = 2; end
                6: begin half_cycles = G4; units = 2; end
                7: begin half_cycles = AS4; units = 1; end
                8: begin half_cycles = GS4; units = 1; end
                9: begin half_cycles = G4; units = 1; end
                10: begin half_cycles = F4; units = 1; end
                11: begin half_cycles = DS4; units = 2; end
                12: begin half_cycles = F4; units = 2; end
                13: begin half_cycles = G4; units = 8; end
                14: begin half_cycles = AS4; units = 4; end
                15: begin half_cycles = AS4; units = 3; end
                16: begin half_cycles = GS4; units = 1; end
                17: begin half_cycles = G4; units = 2; end
                18: begin half_cycles = F4; units = 2; end
                19: begin half_cycles = DS4; units = 2; end
                20: begin half_cycles = F4; units = 2; end
                21: begin half_cycles = G4; units = 1; end
                22: begin half_cycles = DS4; units = 1; end
                23: begin half_cycles = C4; units = 1; end
                24: begin half_cycles = DS4; units = 1; end
                25: begin half_cycles = G4; units = 2; end
                26: begin half_cycles = F4; units = 2; end
                27: begin half_cycles = DS4; units = 4; end
                28: begin half_cycles = D4; units = 4; end
                29: begin half_cycles = C5; units = 4; end
                30: begin half_cycles = C5; units = 3; end
                31: begin half_cycles = AS4; units = 1; end
                32: begin half_cycles = C5; units = 2; end
                33: begin half_cycles = AS4; units = 2; end
                34: begin half_cycles = GS4; units = 2; end
                35: begin half_cycles = G4; units = 2; end
                36: begin half_cycles = AS4; units = 1; end
                37: begin half_cycles = GS4; units = 1; end
                38: begin half_cycles = G4; units = 1; end
                39: begin half_cycles = F4; units = 1; end
                40: begin half_cycles = DS4; units = 2; end
                41: begin half_cycles = F4; units = 2; end
                42: begin half_cycles = G4; units = 8; end
                43: begin half_cycles = AS4; units = 4; end
                44: begin half_cycles = AS4; units = 3; end
                45: begin half_cycles = GS4; units = 1; end
                46: begin half_cycles = G4; units = 2; end
                47: begin half_cycles = F4; units = 2; end
                48: begin half_cycles = DS4; units = 2; end
                49: begin half_cycles = F4; units = 2; end
                50: begin half_cycles = G4; units = 1; end
                51: begin half_cycles = DS4; units = 1; end
                52: begin half_cycles = C4; units = 1; end
                53: begin half_cycles = DS4; units = 1; end
                54: begin half_cycles = G4; units = 2; end
                55: begin half_cycles = F4; units = 2; end
                56: begin half_cycles = DS4; units = 4; end
                57: begin half_cycles = D4; units = 6; end
                58: begin half_cycles = C4; units = 1; end
                59: begin half_cycles = D4; units = 1; end
                60: begin half_cycles = DS4; units = 2; end
                61: begin half_cycles = C4; units = 2; end
                62: begin half_cycles = F4; units = 2; end
                63: begin half_cycles = DS4; units = 2; end
                64: begin half_cycles = D4; units = 2; end
                65: begin half_cycles = C4; units = 2; end
                66: begin half_cycles = AS3; units = 3; end
                67: begin half_cycles = GS3; units = 1; end
                68: begin half_cycles = G3; units = 2; end
                69: begin half_cycles = GS3; units = 2; end
                70: begin half_cycles = AS3; units = 4; end
                71: begin half_cycles = F3; units = 6; end
                72: begin half_cycles = D3; units = 1; end
                73: begin half_cycles = DS3; units = 1; end
                74: begin half_cycles = F3; units = 2; end
                75: begin half_cycles = D3; units = 2; end
                76: begin half_cycles = G3; units = 2; end
                77: begin half_cycles = F3; units = 2; end
                78: begin half_cycles = DS3; units = 2; end
                79: begin half_cycles = D3; units = 2; end
                80: begin half_cycles = DS3; units = 4; end
                81: begin half_cycles = DS3; units = 4; end
                82: begin half_cycles = D3; units = 10; end
                83: begin half_cycles = C4; units = 1; end
                84: begin half_cycles = D4; units = 1; end
                85: begin half_cycles = DS4; units = 2; end
                86: begin half_cycles = C4; units = 2; end
                87: begin half_cycles = F4; units = 2; end
                88: begin half_cycles = DS4; units = 2; end
                89: begin half_cycles = D4; units = 2; end
                90: begin half_cycles = C4; units = 2; end
                91: begin half_cycles = AS3; units = 1; end
                92: begin half_cycles = GS3; units = 1; end
                93: begin half_cycles = G3; units = 1; end
                94: begin half_cycles = GS3; units = 1; end
                95: begin half_cycles = AS3; units = 2; end
                96: begin half_cycles = GS3; units = 2; end
                97: begin half_cycles = G3; units = 4; end
                98: begin half_cycles = DS3; units = 6; end
                99: begin half_cycles = D3; units = 1; end
                100: begin half_cycles = DS3; units = 1; end
                101: begin half_cycles = F3; units = 2; end
                102: begin half_cycles = D3; units = 2; end
                103: begin half_cycles = G3; units = 2; end
                104: begin half_cycles = F3; units = 2; end
                105: begin half_cycles = DS3; units = 2; end
                106: begin half_cycles = D3; units = 2; end
                107: begin half_cycles = D3; units = 2; end
                108: begin half_cycles = D3; units = 1; end
                109: begin half_cycles = DS3; units = 1; end
                110: begin half_cycles = D3; units = 2; end
                111: begin half_cycles = D3; units = 1; end
                112: begin half_cycles = DS3; units = 1; end
                113: begin half_cycles = D3; units = 2; end
                114: begin half_cycles = D3; units = 1; end
                115: begin half_cycles = DS3; units = 1; end
                116: begin half_cycles = D3; units = 2; end
                117: begin half_cycles = D3; units = 1; end
                118: begin half_cycles = DS3; units = 1; end
                119: begin half_cycles = D3; units = 1; end
                120: begin half_cycles = DS3; units = 1; end
                121: begin half_cycles = D3; units = 1; end
                122: begin half_cycles = DS3; units = 1; end
                123: begin half_cycles = D3; units = 1; end
                124: begin half_cycles = DS3; units = 1; end
                125: begin half_cycles = D3; units = 1; end
                126: begin half_cycles = DS3; units = 1; end
                127: begin half_cycles = D3; units = 1; end
                128: begin half_cycles = DS3; units = 1; end
                129: begin half_cycles = D3; units = 1; end
                130: begin half_cycles = DS3; units = 1; end
                131: begin half_cycles = D3; units = 1; end
                132: begin half_cycles = DS3; units = 1; end
                133: begin half_cycles = D3; units = 1; end
                134: begin half_cycles = DS3; units = 1; end
                135: begin half_cycles = G3; units = 1; end
                136: begin half_cycles = GS3; units = 1; end
                137: begin half_cycles = G3; units = 1; end
                138: begin half_cycles = GS3; units = 1; end
                139: begin half_cycles = G3; units = 1; end
                140: begin half_cycles = GS3; units = 1; end
                141: begin half_cycles = G3; units = 1; end
                142: begin half_cycles = GS3; units = 1; end
                143: begin half_cycles = G3; units = 1; end
                144: begin half_cycles = A3; units = 1; end
                145: begin half_cycles = B3; units = 1; end
                146: begin half_cycles = C4; units = 1; end
                147: begin half_cycles = D4; units = 1; end
                148: begin half_cycles = DS4; units = 1; end
                149: begin half_cycles = F4; units = 1; end
                150: begin half_cycles = G4; units = 1; end
                151: begin half_cycles = C5; units = 4; end
                152: begin half_cycles = C5; units = 3; end
                153: begin half_cycles = AS4; units = 1; end
                154: begin half_cycles = C5; units = 2; end
                155: begin half_cycles = AS4; units = 2; end
                156: begin half_cycles = GS4; units = 2; end
                157: begin half_cycles = G4; units = 2; end
                158: begin half_cycles = AS4; units = 1; end
                159: begin half_cycles = GS4; units = 1; end
                160: begin half_cycles = G4; units = 1; end
                161: begin half_cycles = F4; units = 1; end
                162: begin half_cycles = DS4; units = 2; end
                163: begin half_cycles = F4; units = 2; end
                164: begin half_cycles = G4; units = 8; end
                165: begin half_cycles = AS4; units = 4; end
                166: begin half_cycles = AS4; units = 3; end
                167: begin half_cycles = GS4; units = 1; end
                168: begin half_cycles = G4; units = 2; end
                169: begin half_cycles = F4; units = 2; end
                170: begin half_cycles = DS4; units = 2; end
                171: begin half_cycles = F4; units = 2; end
                172: begin half_cycles = G4; units = 1; end
                173: begin half_cycles = DS4; units = 1; end
                174: begin half_cycles = C4; units = 1; end
                175: begin half_cycles = DS4; units = 1; end
                176: begin half_cycles = G4; units = 2; end
                177: begin half_cycles = F4; units = 2; end
                178: begin half_cycles = DS4; units = 4; end
                179: begin half_cycles = D4; units = 2; end
                180: begin half_cycles = G4; units = 1; end
                181: begin half_cycles = B4; units = 1; end
                182: begin half_cycles = C5; units = 4; end
                183: begin half_cycles = C5; units = 3; end
                184: begin half_cycles = AS4; units = 1; end
                185: begin half_cycles = C5; units = 2; end
                186: begin half_cycles = AS4; units = 2; end
                187: begin half_cycles = GS4; units = 2; end
                188: begin half_cycles = G4; units = 2; end
                189: begin half_cycles = AS4; units = 1; end
                190: begin half_cycles = GS4; units = 1; end
                191: begin half_cycles = G4; units = 1; end
                192: begin half_cycles = F4; units = 1; end
                193: begin half_cycles = DS4; units = 2; end
                194: begin half_cycles = F4; units = 2; end
                195: begin half_cycles = G4; units = 8; end
                196: begin half_cycles = AS4; units = 4; end
                197: begin half_cycles = AS4; units = 3; end
                198: begin half_cycles = GS4; units = 1; end
                199: begin half_cycles = G4; units = 2; end
                200: begin half_cycles = F4; units = 2; end
                201: begin half_cycles = DS4; units = 2; end
                202: begin half_cycles = F4; units = 2; end
                203: begin half_cycles = G4; units = 1; end
                204: begin half_cycles = DS4; units = 1; end
                205: begin half_cycles = C4; units = 1; end
                206: begin half_cycles = DS4; units = 1; end
                207: begin half_cycles = G4; units = 2; end
                208: begin half_cycles = F4; units = 2; end
                209: begin half_cycles = DS4; units = 4; end
                210: begin half_cycles = D4; units = 6; end
                211: begin half_cycles = C4; units = 1; end
                212: begin half_cycles = D4; units = 1; end
                213: begin half_cycles = DS4; units = 2; end
                214: begin half_cycles = C4; units = 2; end
                215: begin half_cycles = F4; units = 2; end
                216: begin half_cycles = DS4; units = 2; end
                217: begin half_cycles = D4; units = 2; end
                218: begin half_cycles = C4; units = 2; end
                219: begin half_cycles = AS3; units = 3; end
                220: begin half_cycles = GS3; units = 1; end
                221: begin half_cycles = G3; units = 2; end
                222: begin half_cycles = GS3; units = 2; end
                223: begin half_cycles = AS3; units = 4; end
                224: begin half_cycles = F3; units = 6; end
                225: begin half_cycles = D3; units = 1; end
                226: begin half_cycles = DS3; units = 1; end
                227: begin half_cycles = F3; units = 2; end
                228: begin half_cycles = D3; units = 2; end
                229: begin half_cycles = G3; units = 2; end
                230: begin half_cycles = F3; units = 2; end
                231: begin half_cycles = DS3; units = 2; end
                232: begin half_cycles = D3; units = 2; end
                233: begin half_cycles = DS3; units = 4; end
                234: begin half_cycles = DS3; units = 4; end
                235: begin half_cycles = D3; units = 2; end
                236: begin half_cycles = C3; units = 1; end
                237: begin half_cycles = D3; units = 1; end
                238: begin half_cycles = DS3; units = 1; end
                239: begin half_cycles = G3; units = 1; end
                240: begin half_cycles = C4; units = 1; end
                241: begin half_cycles = D4; units = 1; end
                242: begin half_cycles = DS4; units = 2; end
                243: begin half_cycles = C4; units = 1; end
                244: begin half_cycles = D4; units = 1; end
                245: begin half_cycles = DS4; units = 2; end
                246: begin half_cycles = C4; units = 2; end
                247: begin half_cycles = F4; units = 2; end
                248: begin half_cycles = DS4; units = 2; end
                249: begin half_cycles = D4; units = 2; end
                250: begin half_cycles = C4; units = 2; end
                251: begin half_cycles = AS3; units = 1; end
                252: begin half_cycles = GS3; units = 1; end
                253: begin half_cycles = G3; units = 1; end
                254: begin half_cycles = GS3; units = 1; end
                255: begin half_cycles = AS3; units = 2; end
                256: begin half_cycles = GS3; units = 2; end
                257: begin half_cycles = G3; units = 4; end
                258: begin half_cycles = DS3; units = 4; end
                default: begin half_cycles = 0; units = 1; end
            endcase
        end
    end



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
                else if (volume > max_volume) volume <= volume - 1'b1;
            end else fade_count <= fade_count + 1'b1;
        end
    end
endmodule
