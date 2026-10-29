// Owner: Role 4 - Marcus. Part sprites shared by both renderers.
// Include inside a module body. Rows hold 4-bit palette entries, left pixel in the top nibble.
// part_sprite is 8 by 8 (zoomed-out map, inventory icons, drag preview); part_sprite12 is 12 by 12
// (map view); part_sprite16 is 16 by 16 (editor grid).
// Each part has its own 15-colour palette; entry 0 is transparent and returns the supplied background.
// Frame contents (pig, engine) leave the frame's outer ring transparent so it stays visible.
// sprite_phase selects the second animation frame: engine pulleys/belt and fan blades.
// Include once per module: it declares functions, so it has no include guard.

`ifndef LP_PALETTE_TNT
`define LP_PALETTE_TNT 4'd8
`endif

function [15:0] sprite_colour;
    input [3:0] palette;  // Part ID, or LP_PALETTE_TNT
    input [3:0] entry;
    input [15:0] background;
    begin
        sprite_colour = background;
        case (palette)
            `LP_PART_FRAME: case (entry)
                4'h1: sprite_colour = 16'ha285;  // Wood
                4'h2: sprite_colour = 16'h7a00;  // Dark wood
                4'h3: sprite_colour = 16'hdd0c;  // Light wood
            endcase
            `LP_PART_PIG: case (entry)
                4'h1: sprite_colour = 16'haff5;  // Light green
                4'h2: sprite_colour = 16'hc30e;  // Nostril
                4'h3: sprite_colour = 16'h07e0;  // Pig green
                4'h4: sprite_colour = 16'h03e0;  // Dark green
                4'h5: sprite_colour = 16'h0000;  // Black
                4'h6: sprite_colour = 16'hfd18;  // Snout pink
                4'h8: sprite_colour = 16'hffff;  // White
            endcase
            `LP_PART_WHEEL: case (entry)
                4'h1: sprite_colour = 16'h2945;  // Tyre
                4'h2: sprite_colour = 16'h52aa;  // Tyre shine
                4'h3: sprite_colour = 16'hc618;  // Rim
                4'h4: sprite_colour = 16'h8410;  // Spoke
                4'h5: sprite_colour = 16'h0000;  // Hub
                4'h7: sprite_colour = 16'h4208;  // Dark grey
                4'h8: sprite_colour = 16'hffff;  // White
            endcase
            `LP_PART_ENGINE: case (entry)
                4'h1: sprite_colour = 16'h5ae9;  // Casing outline
                4'h2: sprite_colour = 16'h9d11;  // Olive casing
                4'h3: sprite_colour = 16'hc635;  // Casing highlight
                4'h4: sprite_colour = 16'h7b2c;  // Shadow
                4'h5: sprite_colour = 16'h0000;  // Belt
                4'h6: sprite_colour = 16'hc618;  // Pulley
                4'h7: sprite_colour = 16'h6b4d;  // Pulley rim
                4'h8: sprite_colour = 16'hffff;  // Glint
                4'h9: sprite_colour = 16'h4208;  // Hub and belt mark
            endcase
            `LP_PART_BOOSTER: case (entry)
                4'h1: sprite_colour = 16'h3194;  // Dark blue
                4'h2: sprite_colour = 16'h5adc;  // Blue
                4'h3: sprite_colour = 16'h9cdf;  // Light blue
                4'h4: sprite_colour = 16'h8410;  // Post
                4'h5: sprite_colour = 16'hc618;  // Joint
                4'h6: sprite_colour = 16'h4208;  // Base
                4'h7: sprite_colour = 16'hffff;  // White
            endcase
            `LP_PART_BALLOON: case (entry)
                4'h1: sprite_colour = 16'ha091;  // Outline
                4'h3: sprite_colour = 16'hfc7e;  // Highlight
                4'h5: sprite_colour = 16'hc618;  // String
                4'h8: sprite_colour = 16'hffff;  // White
                4'hB: sprite_colour = 16'hf81f;  // Balloon magenta
            endcase
            `LP_PART_FAN: case (entry)
                4'h1: sprite_colour = 16'h1ac3;  // Guard outline
                4'h2: sprite_colour = 16'h5dcb;  // Guard green
                4'h3: sprite_colour = 16'ha734;  // Guard highlight
                4'h4: sprite_colour = 16'hc618;  // Blade
                4'h5: sprite_colour = 16'h4208;  // Hub and motor end
                4'h7: sprite_colour = 16'h8410;  // Motor
            endcase
            `LP_PALETTE_TNT: case (entry)
                4'h1: sprite_colour = 16'hf1c5;  // Red
                4'h2: sprite_colour = 16'hb144;  // Stripe
                4'h3: sprite_colour = 16'hffff;  // White middle
                4'h4: sprite_colour = 16'h18c3;  // Black letters
            endcase
        endcase
    end
endfunction

function [15:0] part_sprite;
    input [2:0] sprite_part;
    input integer sprite_x, sprite_y;
    input sprite_phase;
    input [15:0] background;
    reg [31:0] row;
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
                `LP_PART_ENGINE: case (sprite_y)      // Casing with a pulley whose spoke turns
                    1, 6: row = 32'h01111110;
                    2: row = sprite_phase ? 32'h01332910 : 32'h01332610;
                    3: row = sprite_phase ? 32'h01666910 : 32'h01666510;
                    4: row = sprite_phase ? 32'h01996210 : 32'h01696210;
                    5: row = 32'h01666410;
                    default: row = 0;
                endcase
                `LP_PART_BOOSTER: case (sprite_y)     // Arrow rocket on a post
                    1: row = 32'h00000010;
                    2, 5: row = 32'h11111221;
                    3: row = 32'h63333222;
                    4: row = 32'h62252222;
                    6: row = 32'h00040010;
                    7: row = 32'h00666000;
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
                `LP_PART_FAN: case (sprite_y)         // Side-on guard; the blades move outward per phase
                    0, 7: row = 32'h00011000;
                    1, 6: row = sprite_phase ? 32'h00144100 : 32'h00122100;
                    2, 5: row = sprite_phase ? 32'h00122100 : 32'h00144100;
                    default: row = 32'h77155100;
                endcase
                default: row = 0;
            endcase
        end
        part_sprite = sprite_colour(sprite_part, row >> ((7-sprite_x)*4), background);
    end
endfunction

function [15:0] part_sprite16;
    input [2:0] sprite_part;
    input integer sprite_x, sprite_y;
    input sprite_phase;
    input [15:0] background;
    reg [63:0] row;
    begin
        row = 0;
        if (sprite_x >= 0 && sprite_x < 16 && sprite_y >= 0 && sprite_y < 16) begin
            case (sprite_part)
                `LP_PART_FRAME: case (sprite_y)       // Planked border with corner braces
                    0, 15: row = 64'h2222222222222222;
                    1: row = 64'h2333333333333332;
                    2, 13, 14: row = 64'h2111111111111112;
                    3, 12: row = 64'h2112222222222112;
                    4, 11: row = 64'h2112100000012112;
                    5, 10: row = 64'h2112010000102112;
                    default: row = 64'h2112000000002112;
                endcase
                `LP_PART_PIG: case (sprite_y)         // Ears, eyes, snout and nostrils
                    2: row = 64'h0000440000440000;
                    3: row = 64'h0004334444334000;
                    4, 11: row = 64'h0043333333333400;
                    5: row = 64'h0041333333333400;
                    6: row = 64'h0043853333583400;
                    7: row = 64'h0043883333883400;
                    8, 10: row = 64'h0043366666633400;
                    9: row = 64'h0043362662633400;
                    12: row = 64'h0004333333334000;
                    13: row = 64'h0000444444440000;
                    default: row = 0;
                endcase
                `LP_PART_WHEEL: case (sprite_y)       // Tyre, spoked rim and hub
                    0, 15: row = 64'h0000011111100000;
                    1: row = 64'h0001122222211000;
                    2: row = 64'h0012111111111100;
                    3: row = 64'h0121113333111110;
                    4, 11: row = 64'h0111343333431110;
                    5, 10: row = 64'h1113343333433111;
                    6, 9: row = 64'h1113334334333111;
                    7, 8: row = 64'h1113333553333111;
                    12: row = 64'h0111113333111110;
                    13: row = 64'h0011111111111100;
                    default: row = 64'h0001111111111000;
                endcase
                // Casing with a belt between a large and a small pulley; the glints and belt marks move.
                `LP_PART_ENGINE: case (sprite_y)
                    2, 13: row = 64'h0001111111111000;
                    3: row = 64'h0013332222278100;
                    4: row = sprite_phase ? 64'h0013222225797100 : 64'h0013222225767100;
                    5: row = sprite_phase ? 64'h0012222294472100 : 64'h0012222254472100;
                    6: row = 64'h0012422544452100;
                    7: row = 64'h0012277744522100;
                    8: row = sprite_phase ? 64'h0012766679222100 : 64'h0012768675222100;
                    9: row = 64'h0012769672222100;
                    10: row = sprite_phase ? 64'h0012766872224100 : 64'h0012766672224100;
                    11: row = 64'h0012277722222100;
                    12: row = 64'h0014222222222100;
                    default: row = 0;
                endcase
                `LP_PART_BOOSTER: case (sprite_y)     // Arrow rocket on a post and base
                    2: row = 64'h0000000000010000;
                    3: row = 64'h0000000000021000;
                    4, 9: row = 64'h0111111111122100;
                    5: row = 64'h1633333333322210;
                    6: row = 64'h1622225522222221;
                    7: row = 64'h1622225722222221;
                    8: row = 64'h1622222222222210;
                    10: row = 64'h0000004400021000;
                    11: row = 64'h0000004400010000;
                    12, 13: row = 64'h0000004500000000;
                    14: row = 64'h0000666666660000;
                    15: row = 64'h0006666666666000;
                    default: row = 0;
                endcase
                `LP_PART_BALLOON: case (sprite_y)     // Balloon, highlight, knot and string
                    0: row = 64'h0000011111100000;
                    1: row = 64'h00011BBBBBB11000;
                    2: row = 64'h00133BBBBBBBB100;
                    3: row = 64'h013831BBBBBBBB10;
                    4: row = 64'h0133BBBBBBBBBB10;
                    5, 6, 7: row = 64'h01BBBBBBBBBBBB10;
                    8, 9: row = 64'h001BBBBBBBBBB100;
                    10: row = 64'h0001BBBBBBBB1000;
                    11: row = 64'h00001BBBBBB10000;
                    12: row = 64'h0000011BB1100000;
                    13: row = 64'h0000000110000000;
                    14: row = 64'h0000000050000000;
                    default: row = 64'h0000000500000000;
                endcase
                `LP_PART_FAN: case (sprite_y)         // Side-on guard and motor; blades swing to the edges
                    0, 15: row = 64'h0000001111000000;
                    1: row = 64'h0000012332100000;
                    2, 13: row = 64'h0000122222210000;
                    3, 5, 10, 12: row = sprite_phase ? 64'h0000140000410000 : 64'h0000100440010000;
                    4, 11: row = sprite_phase ? 64'h0000142222410000 : 64'h0000122442210000;
                    6, 9: row = 64'h5777122552210000;
                    7, 8: row = 64'h5777104554010000;
                    default: row = 64'h0000012222100000;
                endcase
                default: row = 0;
            endcase
        end
        part_sprite16 = sprite_colour(sprite_part, row >> ((15-sprite_x)*4), background);
    end
endfunction


// TNT block, 8 by 8 (zoomed out): red with a white middle and black TNT letters sharing strokes.
function [15:0] tnt_sprite;
    input integer sprite_x, sprite_y;
    input [15:0] background;
    reg [31:0] row;
    begin
        row = 0;
        if (sprite_x >= 0 && sprite_x < 8 && sprite_y >= 0 && sprite_y < 8) case (sprite_y)
            2, 6: row = 32'h33333333;
            3: row = 32'h44434444;
            4: row = 32'h34344443;
            5: row = 32'h34343443;
            default: row = 32'h11111111;
        endcase
        tnt_sprite = sprite_colour(`LP_PALETTE_TNT, row >> ((7-sprite_x)*4), background);
    end
endfunction

// TNT block, 12 by 12 (map view): red with a white middle and black TNT letters.
function [15:0] tnt_sprite12;
    input integer sprite_x, sprite_y;
    input [15:0] background;
    reg [47:0] row;
    begin
        row = 0;
        if (sprite_x >= 0 && sprite_x < 12 && sprite_y >= 0 && sprite_y < 12) case (sprite_y)
            3, 8: row = 48'h333333333333;
            4: row = 48'h444343343444;
            5: row = 48'h343344343343;
            6: row = 48'h343343443343;
            7: row = 48'h343343343343;
            11: row = 48'h222222222222;
            default: row = 48'h111111111111;
        endcase
        tnt_sprite12 = sprite_colour(`LP_PALETTE_TNT, row >> ((11-sprite_x)*4), background);
    end
endfunction

// 12 by 12 parts for the map view (1.5x): the same designs as the 16 by 16 editor sprites.
function [15:0] part_sprite12;
    input [2:0] sprite_part;
    input integer sprite_x, sprite_y;
    input sprite_phase;
    input [15:0] background;
    reg [47:0] row;
    begin
        row = 0;
        if (sprite_x >= 0 && sprite_x < 12 && sprite_y >= 0 && sprite_y < 12) begin
            case (sprite_part)
                `LP_PART_FRAME: case (sprite_y)
                    0, 11: row = 48'h222222222222;
                    1: row = 48'h233333333332;
                    2, 9: row = 48'h212222222212;
                    3, 8: row = 48'h212100001212;
                    10: row = 48'h211111111112;
                    default: row = 48'h212000000212;
                endcase
                `LP_PART_PIG: case (sprite_y)
                    1: row = 48'h004400004400;
                    2: row = 48'h043344443340;
                    3, 5, 8: row = 48'h043333333340;
                    4: row = 48'h043853358340;
                    6: row = 48'h043366663340;
                    7: row = 48'h043362263340;
                    9: row = 48'h004333333400;
                    10: row = 48'h000444444000;
                    default: row = 0;
                endcase
                `LP_PART_WHEEL: case (sprite_y)
                    0, 11: row = 48'h000111111000;
                    1: row = 48'h011222222110;
                    2: row = 48'h012111111110;
                    3, 8: row = 48'h111133331111;
                    4, 7: row = 48'h111343343111;
                    5, 6: row = 48'h111335533111;
                    default: row = 48'h011111111110;
                endcase
                `LP_PART_ENGINE: case (sprite_y)
                    1, 10: row = 48'h001111111100;
                    2: row = 48'h013322277710;
                    3: row = sprite_phase ? 48'h013222976710 : 48'h013222579710;
                    4: row = 48'h012225477710;
                    5: row = sprite_phase ? 48'h012774492210 : 48'h012774452210;
                    6: row = sprite_phase ? 48'h017667522210 : 48'h017687522210;
                    7: row = sprite_phase ? 48'h017897222410 : 48'h017697222410;
                    8: row = 48'h012772222210;
                    9: row = 48'h014222222210;
                    default: row = 0;
                endcase
                `LP_PART_BOOSTER: case (sprite_y)
                    1: row = 48'h000000001000;
                    2: row = 48'h000000002100;
                    3, 8: row = 48'h111111112210;
                    4: row = 48'h163333333221;
                    5: row = 48'h162255222222;
                    6: row = 48'h162257222222;
                    7: row = 48'h162222222221;
                    9: row = 48'h000044002100;
                    10: row = 48'h000045001000;
                    11: row = 48'h006666666600;
                    default: row = 0;
                endcase
                `LP_PART_BALLOON: case (sprite_y)
                    0: row = 48'h000111111000;
                    1: row = 48'h0013BBBBB100;
                    2: row = 48'h0138BBBBBB10;
                    3: row = 48'h013BBBBBBB10;
                    4, 5: row = 48'h01BBBBBBBB10;
                    6: row = 48'h001BBBBBB100;
                    7: row = 48'h0001BBBB1000;
                    8: row = 48'h00001BB10000;
                    9: row = 48'h000001100000;
                    10: row = 48'h000000500000;
                    default: row = 48'h000005000000;
                endcase
                `LP_PART_FAN: case (sprite_y)
                    0, 11: row = 48'h000001100000;
                    1: row = 48'h000013310000;
                    2, 9: row = 48'h000122221000;
                    3, 8: row = sprite_phase ? 48'h000140041000 : 48'h000104401000;
                    4, 7: row = sprite_phase ? 48'h000142241000 : 48'h000124421000;
                    5, 6: row = 48'h777105501000;
                    default: row = 48'h000012210000;
                endcase
                default: row = 0;
            endcase
        end
        part_sprite12 = sprite_colour(sprite_part, row >> ((11-sprite_x)*4), background);
    end
endfunction
// Direction is a separate saved bit. Rotate the upward rocket to point horizontally.
function [15:0] part_sprite_facing;
    input [2:0] part;
    input signed [7:0] x, y;
    input integer size;
    input facing_left, phase;
    input [15:0] background;
    reg signed [7:0] ix, iy;
    begin
        ix=x; iy=y;
        if (part==`LP_PART_BOOSTER) begin
            ix=facing_left ? size-1-y : y;
            iy=facing_left ? x : size-1-x;
        end else if ((part==`LP_PART_ENGINE || part==`LP_PART_FAN) && facing_left) ix=size-1-x;
        if (size==16) part_sprite_facing=part_sprite16(part,ix,iy,phase,background);
        else if (size==12) part_sprite_facing=part_sprite12(part,ix,iy,phase,background);
        else part_sprite_facing=part_sprite(part,ix,iy,phase,background);
    end
endfunction
