// Owner: Role 4 - Marcus. 8 by 8 part sprites shared by both renderers.
// Include inside a module body. Each row is eight 4-bit palette entries, left pixel in the top nibble.
// Palette 0 is transparent and returns the supplied background. Frame contents (pig, engine)
// leave their outer ring transparent so a frame drawn underneath stays visible.
// Include once per module: it declares a function, so it has no include guard.

function [15:0] part_sprite;
    input [2:0] sprite_part;
    input integer sprite_x, sprite_y;
    input [15:0] background;
    reg [31:0] row;
    reg [3:0] entry;
    begin
        row = 0;
        if (sprite_x >= 0 && sprite_x < 8 && sprite_y >= 0 && sprite_y < 8) begin
            case (sprite_part)
                `LP_PART_FRAME: case (sprite_y)       // Wooden box with corner braces
                    0, 7: row = 32'h11111111;
                    1, 6: row = 32'h11000011;
                    2, 5: row = 32'h10200201;
                    default: row = 32'h10022001;
                endcase
                `LP_PART_PIG: case (sprite_y)         // Ears, eyes and snout
                    1: row = 32'h04000040;
                    3: row = 32'h03533530;
                    4: row = 32'h03366330;
                    5: row = 32'h03655630;
                    2, 6: row = 32'h03333330;
                    default: row = 0;
                endcase
                `LP_PART_WHEEL: case (sprite_y)       // Tyre, rim and hub
                    0, 7: row = 32'h00777700;
                    1, 6: row = 32'h07777770;
                    2, 5: row = 32'h77888877;
                    default: row = 32'h77855877;
                endcase
                `LP_PART_ENGINE: case (sprite_y)      // Casing around a glowing core
                    1, 6: row = 32'h07777770;
                    2, 5: row = 32'h07999970;
                    3, 4: row = 32'h079AA970;
                    default: row = 0;
                endcase
                `LP_PART_BALLOON: case (sprite_y)     // Balloon, highlight and string
                    0: row = 32'h00BBBB00;
                    1: row = 32'h0BB8BBB0;
                    2, 3: row = 32'h0BBBBBB0;
                    4: row = 32'h00BBBB00;
                    5: row = 32'h000BB000;
                    6: row = 32'h00080000;
                    default: row = 32'h00008000;
                endcase
                default: row = 0;
            endcase
        end
        entry = row >> ((7-sprite_x)*4);
        case (entry)
            4'h1: part_sprite = 16'ha285;  // Wood
            4'h2: part_sprite = 16'h7a00;  // Dark wood
            4'h3: part_sprite = 16'h07e0;  // Pig green
            4'h4: part_sprite = 16'h03e0;  // Dark green
            4'h5: part_sprite = 16'h0000;  // Black
            4'h6: part_sprite = 16'hfd18;  // Snout pink
            4'h7: part_sprite = 16'h4208;  // Dark grey
            4'h8: part_sprite = 16'hffff;  // White
            4'h9: part_sprite = 16'hf800;  // Red
            4'hA: part_sprite = 16'hffe0;  // Yellow
            4'hB: part_sprite = 16'hf81f;  // Balloon magenta
            default: part_sprite = background;
        endcase
    end
endfunction
