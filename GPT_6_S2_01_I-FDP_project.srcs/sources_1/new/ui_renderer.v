// Owner: Role 1 - Kaushal; shared left-screen layout with Role 4 - Marcus.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_renderer (
    input wire [6:0] x,
    input wire [5:0] y,
    input wire [15:0] base_pixel,
    input wire [2:0] game_state, feedback_code,
    input wire start_screen_active,
    input wire [1:0] diary_page,
    input wire audio_muted,
    input wire [2:0] master_volume,
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    input wire build_valid,
    input wire [6:0] cursor_x, cursor_y,
    input tri0 [6:0] cloud_scroll_fg,
    input tri0 [6:0] cloud_scroll_bg,
    // Tutorial: flashes the RUN screen's retry button while the lesson asks for it.
    input tri0 retry_glow,
    output reg [15:0] pixel_data
);
    `include "ui_font.vh"
    `include "part_sprites.vh"

    reg [3:0] example_local_x, example_local_y;
    reg [1:0] example_row, example_col;
    reg [2:0] example_part;
    reg example_draw, example_has_frame;

    // Helper function to evaluate 2x comic bubble title font ("LAGGY PIGGIES")
    // Glyphs: 0:L, 1:A, 2:G, 3:Y, 4:P, 5:I, 6:E, 7:S
    function is_title_char;
        input [6:0] px;
        input [5:0] py;
        reg [2:0] gid;
        reg [3:0] lx, ly;
        reg in_char;
        reg [2:0] fcol, frow;
        reg [34:0] glyph;
        begin
            gid = 0; lx = 0; ly = 0; in_char = 0; glyph = 0;
            if (py >= 3 && py <= 16) begin
                ly = py - 6'd3;
                if (px >= 18 && px <= 27)      begin gid = 3'd0; lx = px - 7'd18; in_char = 1; end
                else if (px >= 30 && px <= 39) begin gid = 3'd1; lx = px - 7'd30; in_char = 1; end
                else if (px >= 42 && px <= 51) begin gid = 3'd2; lx = px - 7'd42; in_char = 1; end
                else if (px >= 54 && px <= 63) begin gid = 3'd2; lx = px - 7'd54; in_char = 1; end
                else if (px >= 66 && px <= 75) begin gid = 3'd3; lx = px - 7'd66; in_char = 1; end
            end else if (py >= 18 && py <= 31) begin
                ly = py - 6'd18;
                if (px >= 7 && px <= 16)       begin gid = 3'd4; lx = px - 7'd7;  in_char = 1; end
                else if (px >= 19 && px <= 28) begin gid = 3'd5; lx = px - 7'd19; in_char = 1; end
                else if (px >= 31 && px <= 40) begin gid = 3'd2; lx = px - 7'd31; in_char = 1; end
                else if (px >= 43 && px <= 52) begin gid = 3'd2; lx = px - 7'd43; in_char = 1; end
                else if (px >= 55 && px <= 64) begin gid = 3'd5; lx = px - 7'd55; in_char = 1; end
                else if (px >= 67 && px <= 76) begin gid = 3'd6; lx = px - 7'd67; in_char = 1; end
                else if (px >= 79 && px <= 88) begin gid = 3'd7; lx = px - 7'd79; in_char = 1; end
            end
            if (in_char) begin
                fcol = lx >> 1;
                frow = ly >> 1;
                case (gid)
                    3'd0: glyph = {5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b11111}; // L
                    3'd1: glyph = {5'b01110, 5'b10001, 5'b10001, 5'b11111, 5'b10001, 5'b10001, 5'b10001}; // A
                    3'd2: glyph = {5'b01111, 5'b10000, 5'b10000, 5'b10111, 5'b10001, 5'b10001, 5'b01111}; // G
                    3'd3: glyph = {5'b10001, 5'b10001, 5'b01010, 5'b00100, 5'b00100, 5'b00100, 5'b00100}; // Y
                    3'd4: glyph = {5'b11110, 5'b11111, 5'b11111, 5'b11110, 5'b10000, 5'b10000, 5'b10000}; // P (snout loop filled)
                    3'd5: glyph = {5'b11111, 5'b01110, 5'b01110, 5'b01110, 5'b01110, 5'b01110, 5'b11111}; // I
                    3'd6: glyph = {5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b10000, 5'b10000, 5'b11111}; // E
                    3'd7: glyph = {5'b01111, 5'b10000, 5'b10000, 5'b01110, 5'b00001, 5'b00001, 5'b11110}; // S
                endcase
                is_title_char = glyph[((6 - frow) << 2) + (6 - frow) + (4 - fcol)];
            end else begin
                is_title_char = 1'b0;
            end
        end
    endfunction

    // Helper function to draw an Apple-style metallic 8-tooth settings gear
    function [1:0] gear_shade_at;
        input signed [6:0] center_x, center_y, px, py;
        reg signed [6:0] lx, ly;
        reg [8:0] row;
        reg lit;
        begin
            lx = px - center_x;
            ly = py - center_y;
            row = 9'd0;
            lit = 1'b0;
            if (center_y == 7'sd59) begin
                // 7x7 gear for the 9px-tall BUILD toolbar button (y=55..63):
                // eight teeth around a solid ring with a small round hole.
                if (lx >= -3 && lx <= 3 && ly >= -3 && ly <= 3) begin
                    case (ly)
                        -7'sd3,  7'sd3: row = 9'b001001001;
                        -7'sd2,  7'sd2: row = 9'b000111110;
                        -7'sd1,  7'sd1: row = 9'b000110110;
                         7'sd0:         row = 9'b001100011;
                        default:        row = 9'd0;
                    endcase
                    lit = row[3 - lx];
                end
            end else if (lx >= -4 && lx <= 4 && ly >= -4 && ly <= 4) begin
                // 9x9 gear: wide teeth on the four sides, narrow teeth on the
                // diagonals, and a round hole showing the button face behind it.
                case (ly)
                    -7'sd4,  7'sd4: row = 9'b000111000;
                    -7'sd3,  7'sd3: row = 9'b010111010;
                    -7'sd2,  7'sd2: row = 9'b001111100;
                    -7'sd1,  7'sd1: row = 9'b111101111;
                     7'sd0:         row = 9'b111000111;
                    default:        row = 9'd0;
                endcase
                lit = row[4 - lx];
            end
            // Light falls from the top-left: 0 is empty, then highlight, body and shadow.
            if (!lit) gear_shade_at = 2'd0;
            else if (lx + ly <= -7'sd2) gear_shade_at = 2'd1;
            else if (lx + ly <= 7'sd2) gear_shade_at = 2'd2;
            else gear_shade_at = 2'd3;
        end
    endfunction

    function [15:0] gear_shade_colour;
        input [1:0] shade;
        begin
            case (shade)
                2'd1: gear_shade_colour = 16'hffff; // Specular white-silver
                2'd2: gear_shade_colour = 16'hd69a; // Brushed light silver
                default: gear_shade_colour = 16'h7bef; // Metallic slate shading
            endcase
        end
    endfunction

    // Helper function for realistic 3-panel accordion-folded terrain/treasure map icon (11x7)
    function [15:0] draw_map_icon;
        input signed [6:0] cx, cy, px, py;
        input [15:0] bg;
        reg signed [4:0] lx, ly, top_y, bot_y;
        reg in_mid;
        begin
            lx = px - cx;
            ly = py - cy;
            draw_map_icon = bg;
            if (lx >= -5 && lx <= 5 && ly >= -3 && ly <= 3) begin
                in_mid = (lx >= -1 && lx <= 1);
                top_y = in_mid ? -5'sd2 : -5'sd3;
                bot_y = in_mid ?  5'sd3 :  5'sd2;
                if (ly >= top_y && ly <= bot_y) begin
                    if (lx == -5 || lx == 5 || ly == top_y || ly == bot_y)
                        draw_map_icon = in_mid ? 16'h9c45 : 16'hc588; // Tan map border (shaded on middle fold)
                    else if ((lx <= -2 && ly <= 0) || (lx == 0 && ly == -1) || (lx >= 2 && ly <= -1))
                        draw_map_icon = 16'h2684; // Green continents across left, middle, and right panels
                    else if ((lx == -2 && ly == 1) || (lx == -1 && ly >= 0) || (lx == 0 && ly >= 1) || (lx >= 2 && ly >= 1))
                        draw_map_icon = 16'h1d9f; // Winding blue river and eastern ocean bay
                    else
                        draw_map_icon = in_mid ? 16'hd632 : 16'hffdf; // Parchment paper with 3D fold shadow
                end
            end
        end
    endfunction

    // Helper function for realistic open book / diary icon with curved pages & red bookmark (13x7)
    // Returns {lit, colour}; where lit is 0 the button background shows through.
    function [16:0] draw_diary_icon;
        input signed [6:0] cx, cy, px, py;
        reg signed [4:0] lx, ly;
        reg [4:0] alx;
        begin
            lx = px - cx;
            ly = py - cy;
            alx = (lx < 0) ? -lx : lx;
            draw_diary_icon = 17'd0;
            if (lx >= -6 && lx <= 6 && ly >= -3 && ly <= 3) begin
                if (lx == 0 && ly >= 1)
                    draw_diary_icon = {1'b1, 16'hf800}; // Red ribbon bookmark hanging at bottom spine
                else if (lx == 0) begin
                    if (ly >= -2) draw_diary_icon = {1'b1, 16'h8a22}; // V-dip at top of center spine
                end else if (alx == 6 || ly == 3)
                    draw_diary_icon = {1'b1, 16'h9182}; // Mahogany hardcover binding
                else if (ly == -3) begin
                    if (alx >= 2 && alx <= 5) draw_diary_icon = {1'b1, 16'hd69a}; // Curved top page edge
                end else if (alx == 1)
                    draw_diary_icon = {1'b1, 16'hd69a}; // Inner page crease shadow next to spine
                else if ((ly == -1 || ly == 1) && alx >= 2 && alx <= 4)
                    draw_diary_icon = {1'b1, 16'h4a69}; // Neat indented slate ink text lines
                else
                    draw_diary_icon = {1'b1, 16'hffff}; // Crisp white pages
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // Icon Glyph Helpers (Pure distributed logic / LUT ROMs - 0 BRAM, Rule 3)
    // -------------------------------------------------------------------------
    function is_back_arrow;
        input signed [6:0] cx, cy, px, py;
        reg signed [4:0] lx, ly;
        reg [3:0] aly;
        begin
            lx = px - cx;
            ly = py - cy;
            aly = (ly < 0) ? -ly[3:0] : ly[3:0];
            is_back_arrow = (lx >= -3 + $signed({1'b0, aly}) && lx <= 0 && aly <= 3) ||
                            (lx >= 0 && lx <= 3 && aly <= 1);
        end
    endfunction

    function is_home_icon;
        input signed [6:0] cx, cy, px, py;
        reg signed [4:0] lx, ly;
        begin
            lx = px - cx;
            ly = py - cy;
            is_home_icon = (ly == -3 && lx == 0) ||
                           (ly == -2 && lx >= -1 && lx <= 1) ||
                           (ly == -1 && lx >= -2 && lx <= 2) ||
                           (ly == 0  && lx >= -3 && lx <= 3) ||
                           (ly >= 1 && ly <= 3 && lx >= -3 && lx <= 3 && !(lx == 0 && ly >= 2));
        end
    endfunction

    function is_checkmark_icon;
        input signed [6:0] cx, cy, px, py;
        reg signed [6:0] lx, ly;
        begin
            lx = px - cx;
            ly = py - cy;
            is_checkmark_icon = (lx == -3 && (ly == -1 || ly == 0)) ||
                                (lx == -2 && (ly == 0  || ly == 1)) ||
                                (lx == -1 && (ly == 1  || ly == 2)) ||
                                (lx == 0  && (ly == 0  || ly == 1)) ||
                                (lx == 1  && (ly == -1 || ly == 0)) ||
                                (lx == 2  && (ly == -2 || ly == -1)) ||
                                (lx == 3  && (ly == -3 || ly == -2));
        end
    endfunction

    function is_retry_icon;
        input signed [6:0] cx, cy, px, py;
        reg signed [6:0] lx, ly;
        reg [8:0] row;
        begin
            lx = px - cx;
            ly = py - cy;
            row = 9'd0;
            is_retry_icon = 1'b0;
            // Clean 9x9 clockwise circular refresh arrow with 2-o'clock corner arrowhead (◢) & wide open gap
            if (lx >= -4 && lx <= 4 && ly >= -4 && ly <= 4) begin
                case (ly)
                    -7'sd4: row = 9'b001111001; // Top 2px arc (lx = -2..+1) + upper arrowhead tip (lx = +4)
                    -7'sd3: row = 9'b011111111; // Top 2px arc (lx = -3..+2) + arrowhead (lx = +3..+4)
                    -7'sd2: row = 9'b110000111; // Left 2px arc (lx = -4..-3) + arrowhead body (lx = +2..+4)
                    -7'sd1: row = 9'b110001111; // Left 2px arc (lx = -4..-3) + arrowhead base (lx = +1..+4)
                     7'sd0: row = 9'b110000000; // Left 2px arc (lx = -4..-3) + wide open gap on right
                     7'sd1: row = 9'b110000000; // Left 2px arc (lx = -4..-3) + wide open gap on right
                     7'sd2: row = 9'b111000110; // Bottom-left arc (lx = -4..-2) + bottom-right tail (lx = +2..+3)
                     7'sd3: row = 9'b011111110; // Bottom 2px arc (lx = -3..+3)
                     7'sd4: row = 9'b001111100; // Bottom 2px arc (lx = -2..+2)
                    default: row = 9'd0;
                endcase
                is_retry_icon = row[4 - lx];
            end
        end
    endfunction

    function is_stop_icon;
        input signed [6:0] cx, cy, px, py;
        reg signed [4:0] lx, ly;
        begin
            lx = px - cx;
            ly = py - cy;
            is_stop_icon = (lx >= -2 && lx <= 2 && ly >= -2 && ly <= 2);
        end
    endfunction

    // Returns {lit, colour}; where lit is 0 the button background shows through.
    function [16:0] cartoon_wrench;
        input signed [6:0] cx, cy, px, py;
        reg signed [4:0] lx, ly;
        reg [8:0] row;
        begin
            lx = px - cx;
            ly = py - cy;
            row = 9'd0;
            cartoon_wrench = 17'd0;
            if (lx >= -4 && lx <= 4 && ly >= -4 && ly <= 4) begin
                case (ly)
                    -5'sd4: row = 9'b000001100; // Upper jaw tip
                    -5'sd3: row = 9'b000011000; // Upper jaw
                    -5'sd2: row = 9'b000011011; // Jaw base + lower jaw tip (open C-mouth)
                    -5'sd1: row = 9'b000111110; // Neck + lower jaw
                     5'sd0: row = 9'b001110000; // Diagonal shaft
                     5'sd1: row = 9'b011100000; // Diagonal shaft
                     5'sd2: row = 9'b111000000; // Handle
                     5'sd3: row = 9'b110000000; // Handle end
                    default: row = 9'd0;
                endcase
                if (row[4 - lx])
                    cartoon_wrench = (lx + ly <= -1) ? {1'b1, 16'hffff} : {1'b1, 16'hc618};
            end
        end
    endfunction

    function is_play_icon;
        input signed [6:0] cx, cy, px, py;
        reg signed [4:0] lx, ly;
        begin
            lx = px - cx;
            ly = py - cy;
            is_play_icon = (lx == -3 && ly >= -3 && ly <= 3) ||
                           (lx == -2 && ly >= -3 && ly <= 3) ||
                           (lx == -1 && ly >= -2 && ly <= 2) ||
                           (lx == 0  && ly >= -2 && ly <= 2) ||
                           (lx == 1  && ly >= -1 && ly <= 1) ||
                           (lx == 2  && ly >= -1 && ly <= 1) ||
                           (lx == 3  && ly == 0);
        end
    endfunction

    wire title_lit = is_title_char(x, y);
    wire title_outline = !title_lit && (
        is_title_char(x + 7'd1, y) ||
        (x > 0 && is_title_char(x - 7'd1, y)) ||
        is_title_char(x, y + 6'd1) ||
        (y > 0 && is_title_char(x, y - 6'd1))
    );

    // -------------------------------------------------------------------------
    // START SCREEN: Lively Dual-Layer 2-Tone Animated Cloud Parallax
    // Right-to-left drift matches Bad Piggies title camera pan and map flow.
    // -------------------------------------------------------------------------
    wire [6:0] fg_x = (x + cloud_scroll_fg >= 7'd96) ? (x + cloud_scroll_fg - 7'd96) : (x + cloud_scroll_fg);
    wire [6:0] bg_x = (x + cloud_scroll_bg >= 7'd96) ? (x + cloud_scroll_bg - 7'd96) : (x + cloud_scroll_bg);

    // Foreground Cloud 1 (Center ~23, Y 8..16, width 23)
    wire fg_c1_base = (fg_x >= 7'd12 && fg_x <= 7'd34 && y >= 6'd12 && y <= 6'd16 &&
                       !((fg_x == 7'd12 || fg_x == 7'd34) && y == 6'd16));
    wire fg_c1_mid  = (fg_x >= 7'd15 && fg_x <= 7'd31 && y >= 6'd10 && y <= 6'd11);
    wire fg_c1_top  = (fg_x >= 7'd19 && fg_x <= 7'd27 && y >= 6'd8  && y <= 6'd9 &&
                       !((fg_x == 7'd19 || fg_x == 7'd27) && y == 6'd8));
    wire fg_c1 = fg_c1_base || fg_c1_mid || fg_c1_top;
    wire fg_c1_shade = fg_c1 && (y >= 6'd15);

    // Foreground Cloud 2 (Center ~71, Y 7..15, width 23)
    wire fg_c2_base = (fg_x >= 7'd60 && fg_x <= 7'd82 && y >= 6'd11 && y <= 6'd15 &&
                       !((fg_x == 7'd60 || fg_x == 7'd82) && y == 6'd15));
    wire fg_c2_mid  = (fg_x >= 7'd63 && fg_x <= 7'd79 && y >= 6'd9  && y <= 6'd10);
    wire fg_c2_top  = (fg_x >= 7'd67 && fg_x <= 7'd75 && y >= 6'd7  && y <= 6'd8 &&
                       !((fg_x == 7'd67 || fg_x == 7'd75) && y == 6'd7));
    wire fg_c2 = fg_c2_base || fg_c2_mid || fg_c2_top;
    wire fg_c2_shade = fg_c2 && (y >= 6'd14);

    wire fg_cloud = fg_c1 || fg_c2;
    wire fg_cloud_shade = fg_c1_shade || fg_c2_shade;

    // Distant Background Cloud 1 (Center ~45, Y 4..9, width 17)
    wire bg_c1_base = (bg_x >= 7'd37 && bg_x <= 7'd53 && y >= 6'd6 && y <= 6'd9 &&
                       !((bg_x == 7'd37 || bg_x == 7'd53) && (y == 6'd6 || y == 6'd9)));
    wire bg_c1_top  = (bg_x >= 7'd41 && bg_x <= 7'd49 && y >= 6'd4 && y <= 6'd5 &&
                       !((bg_x == 7'd41 || bg_x == 7'd49) && y == 6'd4));
    wire bg_c1 = bg_c1_base || bg_c1_top;
    wire bg_c1_shade = bg_c1 && (y >= 6'd8);

    // Distant Background Cloud 2 (Center ~88, Y 3..8, width 15)
    wire bg_c2_base = (bg_x >= 7'd81 && bg_x <= 7'd95 && y >= 6'd5 && y <= 6'd8 &&
                       !((bg_x == 7'd81 || bg_x == 7'd95) && (y == 6'd5 || y == 6'd8)));
    wire bg_c2_top  = (bg_x >= 7'd84 && bg_x <= 7'd92 && y >= 6'd3 && y <= 6'd4 &&
                       !((bg_x == 7'd84 || bg_x == 7'd92) && y == 6'd3));
    wire bg_c2 = bg_c2_base || bg_c2_top;
    wire bg_c2_shade = bg_c2 && (y >= 6'd7);

    wire bg_cloud = bg_c1 || bg_c2;
    wire bg_cloud_shade = bg_c1_shade || bg_c2_shade;

    // Play button distance from its centre (48, 40). Every pixel of the disc is within 9 pixels
    // on each axis, so the squares stay small instead of being 32-bit products.
    wire [6:0] play_abs_x = (x >= 7'd48) ? (x - 7'd48) : (7'd48 - x);
    wire [5:0] play_abs_y = (y >= 6'd40) ? (y - 6'd40) : (6'd40 - y);
    wire play_near_centre = (play_abs_x <= 7'd9) && (play_abs_y <= 6'd9);
    wire [7:0] play_distance_sq = play_abs_x[3:0] * play_abs_x[3:0] + play_abs_y[3:0] * play_abs_y[3:0];

    // Each drawing helper below is evaluated once: only one screen is visible at a time, so the
    // screen picks the icon's centre. Every extra call would be another copy of its logic.
    wire on_build_screen = (game_state == `LP_BUILD);
    wire on_run_screen = (game_state == `LP_RUN);
    reg [6:0] gear_centre_x, gear_centre_y;
    always @* begin
        if (start_screen_active) begin
            gear_centre_x = 7'd12; gear_centre_y = 7'd54;
        end else if (on_build_screen) begin
            gear_centre_x = 7'd87; gear_centre_y = 7'd59;
        end else begin
            gear_centre_x = 7'd84; gear_centre_y = 7'd58;
        end
    end
    wire [1:0] gear_shade = gear_shade_at(gear_centre_x, gear_centre_y, x, y);
    wire gear_lit = (gear_shade != 2'd0);
    wire [15:0] gear_colour = gear_shade_colour(gear_shade);

    wire [16:0] diary_icon = draw_diary_icon(on_build_screen ? 7'd71 : 7'd60, on_build_screen ? 7'd59 : 7'd58, x, y);
    wire [16:0] wrench_icon = cartoon_wrench(on_run_screen ? 7'd60 : 7'd74, on_run_screen ? 7'd58 : 7'd16, x, y);
    wire retry_lit = is_retry_icon(on_run_screen ? 7'd12 : 7'd74, on_run_screen ? 7'd58 : 7'd40, x, y);
    wire back_arrow_lit = is_back_arrow((game_state == `LP_SETTINGS) ? 7'd48 : 7'd14, (game_state == `LP_SETTINGS) ? 6'd57 : 6'd58, x, y);
    wire home_icon_lit  = is_home_icon((game_state == `LP_SETTINGS) ? 7'd82 : 7'd12, (game_state == `LP_SETTINGS) ? 6'd57 : 6'd58, x, y);

    // One text line per pixel: the screen and pixel row choose which string can be lit here.
    // Strings on the same screen never share a row band, or are told apart by a column.
    reg [127:0] line_text;
    reg [6:0] line_left;
    reg [5:0] line_top;
    reg [15:0] line_colour;
    always @* begin
        line_text = "                "; line_left = 7'd0; line_top = 6'd0; line_colour = 16'hffff;
        if (!start_screen_active) begin
            if (game_state == `LP_LEVEL_SELECT) begin
                if (y < 6'd12) begin
                    line_text = "SELECT MAP      "; line_left = 7'd18; line_top = 6'd2; line_colour = 16'h07ff;
                end else if (y < 6'd24) begin
                    line_text = "MAP 1: ARCH     "; line_left = 7'd10; line_top = 6'd12; line_colour = 16'h07ff;
                end else if (y < 6'd38) begin
                    line_text = "MAP 2: FLIGHT   "; line_left = 7'd10; line_top = 6'd26; line_colour = 16'h07ff;
                end else if (y < 6'd52) begin
                    line_text = "TUTORIAL        "; line_left = 7'd10; line_top = 6'd40; line_colour = 16'hffe0;
                end else begin
                    line_text = "PICK A MAP      "; line_left = 7'd32; line_top = 6'd56; line_colour = 16'h7bef;
                end
            end else if (game_state == `LP_SETTINGS) begin
                if (y < 6'd11) begin
                    line_top = 6'd2; line_colour = 16'h07ff;
                    if (diary_page == 2'd1) begin
                        line_text = "MOUSE CTRL  1/2 "; line_left = 7'd2;
                    end else if (diary_page == 2'd2) begin
                        line_text = "BOARD SW    2/2 "; line_left = 7'd2;
                    end else begin
                        line_text = "SETTINGS        "; line_left = 7'd24;
                    end
                end else if (diary_page == 2'd0) begin
                    if (y >= 6'd36 && y <= 6'd42) begin
                        line_top = 6'd36;
                        if (x < 7'd46 && audio_muted) begin
                            line_text = "MUTE            "; line_left = 7'd16; line_colour = 16'hf800;
                        end else if (x >= 7'd55) begin
                            line_text = "1 2             "; line_left = 7'd61; line_colour = 16'hffff;
                        end
                    end
                end else if (diary_page == 2'd1) begin
                    line_left = 7'd56;
                    if (y >= 6'd12 && y <= 6'd19) begin
                        line_top = 6'd12; line_text = "DRAG            "; line_colour = 16'h07e0;
                    end else if (y >= 6'd20 && y <= 6'd27) begin
                        line_top = 6'd20; line_text = "PLACE           "; line_colour = 16'hffff;
                    end else if (y >= 6'd32 && y <= 6'd39) begin
                        line_top = 6'd32; line_text = "PUT             "; line_colour = 16'hf800;
                    end else if (y >= 6'd40 && y <= 6'd47) begin
                        line_top = 6'd40; line_text = "BACK            "; line_colour = 16'hffff;
                    end
                end else if (diary_page == 2'd2) begin
                    if (y >= 6'd38 && y <= 6'd45) begin
                        line_top = 6'd38; line_colour = 16'hffff;
                        if (x < 7'd22)                  begin line_text = "15              "; line_left = 7'd8;  end
                        else if (x < 7'd38)             begin line_text = "14              "; line_left = 7'd24; end
                        else if (x >= 7'd59 && x < 7'd74) begin line_text = "1               "; line_left = 7'd64; end
                        else if (x >= 7'd75)            begin line_text = "0               "; line_left = 7'd80; end
                    end
                end
            end else if (game_state == `LP_GUIDE) begin
                if (y >= 6'd52) begin
                    // Toolbar page numbers; the current page is highlighted gold. The sound
                    // page has no number buttons, so its toolbar line stays blank.
                    if (diary_page != 2'd3) begin
                        line_top = 6'd56;
                        if (x < 7'd53) begin
                            line_text = "1               "; line_left = 7'd40;
                            if (diary_page == 2'd0) line_colour = 16'hffe0;
                        end else if (x < 7'd74) begin
                            line_text = "2               "; line_left = 7'd61;
                            if (diary_page == 2'd1) line_colour = 16'hffe0;
                        end else begin
                            line_text = "3               "; line_left = 7'd82;
                            if (diary_page == 2'd2) line_colour = 16'hffe0;
                        end
                    end
                end else case (diary_page)
                    2'd0: begin
                        if (y < 6'd12) begin
                            line_text = "1 LAUNCH    1/3 "; line_left = 7'd2; line_top = 6'd2; line_colour = 16'h07ff;
                        end else if (y >= 6'd34 && y <= 6'd42) begin
                            line_left = 7'd47; line_top = 6'd35;
                            if (level_index == 0) begin line_text = "ENG ON          "; line_colour = 16'h07e0; end
                            else                  begin line_text = "ENG+FAN         "; line_colour = 16'h07ff; end
                        end
                    end
                    2'd1: begin
                        if (y < 6'd12) begin
                            line_text = "2 STAR      2/3 "; line_left = 7'd2; line_top = 6'd2; line_colour = 16'hffe0;
                        end else if (y >= 6'd34 && y <= 6'd42) begin
                            line_left = 7'd47; line_top = 6'd35;
                            if (level_index == 0) begin line_text = "ROCKET!         "; line_colour = 16'hfd20; end
                            else                  begin line_text = "2 FANS!         "; line_colour = 16'h07ff; end
                        end
                    end
                    2'd2: begin
                        if (y < 6'd12) begin
                            line_text = "3 FINISH    3/3 "; line_left = 7'd2; line_top = 6'd2; line_colour = 16'h07e0;
                        end else if (y >= 6'd34 && y <= 6'd42) begin
                            line_left = 7'd47; line_top = 6'd35;
                            if (level_index == 0) begin line_text = "ENG ->          "; line_colour = 16'h07e0; end
                            else                  begin line_text = "FAN+ENG         "; line_colour = 16'h07ff; end
                        end
                    end
                    default: begin
                        if (y < 6'd12) begin
                            line_text = "SOUND SETTINGS  "; line_left = 7'd6; line_top = 6'd2; line_colour = 16'h07ff;
                        end else if (y < 6'd22) begin
                            line_text = "MASTER VOLUME   "; line_left = 7'd6; line_top = 6'd13;
                        end else if (y < 6'd40) begin
                            line_top = 6'd28;
                            if (x < 7'd60) begin line_text = " -              "; line_left = 7'd12; end
                            else begin line_text = " +              "; line_left = 7'd68; end
                        end else if (audio_muted) begin
                            // Switch 0 (Mute) status banner: only shown when muted.
                            line_text = "MUTED BY SW0    "; line_left = 7'd10; line_top = 6'd43; line_colour = 16'hf800;
                        end
                    end
                endcase
            end
        end
    end
    wire line_lit = text_on(line_text, line_left, line_top, x, y);


    always @* begin
        pixel_data = base_pixel;
        example_draw = 1'b0; example_has_frame = 1'b0; example_part = `LP_PART_EMPTY;
        example_local_x = 4'd0; example_local_y = 4'd0; example_row = 2'd0; example_col = 2'd0;

        if (start_screen_active) begin
            // -----------------------------------------------------------------
            // START SCREEN: Authentic Bad Piggies "Piggy Island" Meadow & Sky
            // -----------------------------------------------------------------
            // 1. Piggy Island cartoon sky and rolling meadow
            if (y < 36) begin
                // Lively dual-layer 2-tone clouds over azure cartoon sky
                if (fg_cloud) begin
                    pixel_data = fg_cloud_shade ? 16'had9f : 16'hffff; // 2-tone foreground cloud
                end else if (bg_cloud) begin
                    pixel_data = bg_cloud_shade ? 16'had9f : 16'hffff; // 2-tone distant cloud
                end else begin
                    pixel_data = 16'h5ddf; // Azure cartoon sky
                end
            end else if (y < 44) begin
                pixel_data = 16'h24a5; // Distant rolling green hills
            end else if (y < 50) begin
                pixel_data = (y == 44) ? 16'h87e0 : 16'h5fe0; // Vivid grass with lime highlight
            end else begin
                pixel_data = (y == 50) ? 16'h4a42 : 16'h7344; // Rich cartoon dirt bed
            end

            // 2. Title Bubble Font: "LAGGY PIGGIES" with Snout & Ears
            if (title_lit) begin
                // Nostrils inside the loop of 'P'
                if (y == 22 && (x == 11 || x == 14)) begin
                    pixel_data = 16'h0200; // Dark green nostril holes
                end else begin
                    // Lime green letters with specular highlight on upper rows
                    pixel_data = (y == 4 || y == 5 || y == 19 || y == 20) ? 16'ha7e0 : 16'h5fe0;
                end
            end else if (title_outline) begin
                pixel_data = 16'h0200; // Bold 1px dark green comic border
            end

            // 3. Centered Circular Play Button at (48, 40), Radius 9
            if (play_near_centre && play_distance_sq <= 8'd81) begin
                if (play_distance_sq >= 8'd64) begin
                    pixel_data = (cursor_x >= 38 && cursor_x <= 58 && cursor_y >= 30 && cursor_y <= 50) ? 16'hffe0 : 16'h0280; // Gold hover rim / dark rim
                end else begin
                    // White symmetric play triangle pointing right inside circle
                    if (x >= 44 && x <= 52 &&
                        y >= (36 + ((x - 44) >> 1)) &&
                        y <= (44 - ((x - 44) >> 1))) begin
                        pixel_data = 16'hffff; // White triangle
                    end else begin
                        if (cursor_x >= 38 && cursor_x <= 58 && cursor_y >= 30 && cursor_y <= 50)
                            pixel_data = 16'h0360; // Hover pulse
                        else if (y != 6'd38 && y != 6'd39 && play_distance_sq < 8'd49)
                            pixel_data = 16'h7fe0; // Specular shine
                        else
                            pixel_data = 16'h4fe0; // Vibrant lime green
                    end
                end
            end

            // 4. Frameless Settings Gear Icon in Bottom-Left (x: 4..20, y: 47..61, Center at 12, 54)
            if (x >= 4 && x <= 20 && y >= 47 && y <= 61 && gear_lit) begin
                pixel_data = (cursor_x >= 4 && cursor_x <= 20 && cursor_y >= 46 && cursor_y <= 62) ? 16'hffe0 : gear_colour;
            end
        end else if (game_state == `LP_LEVEL_SELECT) begin
            // -----------------------------------------------------------------
            // LEVEL SELECT SCREEN (Maps 1 and 2, plus the tutorial)
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;

            // Map 1: Cave Arch
            if (x >= 4 && x <= 91 && y >= 10 && y <= 21) begin
                if (x == 4 || x == 91 || y == 10 || y == 21)
                    pixel_data = (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 10 && cursor_y <= 21) ? 16'hffe0 : ((level_index == `LP_LEVEL_ARCH) ? 16'h07e0 : 16'h04b4);
                else if (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 10 && cursor_y <= 21)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
            end

            // Map 2: Cave Flight (x: 4..91, y: 24..35)
            if (x >= 4 && x <= 91 && y >= 24 && y <= 35) begin
                if (x == 4 || x == 91 || y == 24 || y == 35)
                    pixel_data = (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 24 && cursor_y <= 35) ? 16'hffe0 : ((level_index == `LP_LEVEL_FLIGHT) ? 16'h07e0 : 16'h04b4);
                else if (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 24 && cursor_y <= 35)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
            end

            // Tutorial: guided rectangle course (x: 4..91, y: 38..49)
            if (x >= 4 && x <= 91 && y >= 38 && y <= 49) begin
                if (x == 4 || x == 91 || y == 38 || y == 49)
                    pixel_data = (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 38 && cursor_y <= 49) ? 16'hffe0 : ((level_index == `LP_LEVEL_TUTORIAL) ? 16'h07e0 : 16'h04b4);
                else if (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 38 && cursor_y <= 49)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
            end

            // Bottom toolbar: [ BACK ]
            if (y >= 52) begin
                if (x <= 27) begin
                    if (x == 0 || x == 27 || y == 52 || y == 63)
                        pixel_data = (cursor_x <= 27 && cursor_y >= 52) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x <= 27 && cursor_y >= 52)
                        pixel_data = 16'h0432; // Ocean teal hover glow
                    else
                        pixel_data = 16'h18e5;
                    if (back_arrow_lit) pixel_data = 16'hffff;
                end
            end
        end else if (game_state == `LP_SETTINGS) begin
            // -----------------------------------------------------------------
            // SETTINGS SCREEN: Page 0 = Sound & Map | Page 1 = Mouse | Page 2 = Switches
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;

            if (diary_page == 2'd1) begin
                // --- PAGE 1/2: DEDICATED MOUSE CONTROLS SCREEN (diary_page == 1) ---
                // Top Card (x: 4..91, y: 11..29): Left-Click = Drag & Place into Grid
                if (x >= 4 && x <= 91 && y >= 11 && y <= 29) begin
                    if (x == 4 || x == 91 || y == 11 || y == 29) pixel_data = 16'h04b4;
                    else pixel_data = 16'h1082;
                    // Mouse Cord at top (x=12, y:12..14)
                    if (x == 12 && y >= 12 && y <= 14) pixel_data = 16'h7bef;
                    // Curved Mouse Body (x: 7..17, y: 15..26)
                    if (x >= 7 && x <= 17 && y >= 15 && y <= 26 &&
                        !((x <= 8 || x >= 16) && y == 15) &&
                        !((x == 7 || x == 17) && (y == 16 || y == 26))) begin
                        if (y == 15 || y == 26 || x == 7 || x == 17 || y == 20 ||
                            (y == 16 && (x == 8 || x == 16)) ||
                            (x == 12 && y >= 16 && y <= 19))
                            pixel_data = 16'hffff;
                        else if (y < 20)
                            pixel_data = (x < 12) ? 16'h07e0 : 16'h4208; // Bright GREEN Left Button!
                        else
                            pixel_data = 16'hd69a; // Silver palm rest
                    end
                    // 12x12 Wheel Part being dragged (x: 20..31, y: 14..25) via shared part_sprite12
                    if (x >= 20 && x < 32 && y >= 14 && y < 26) begin
                        example_draw = 1'b1;
                        example_local_x = x - 7'd20;
                        example_local_y = y - 6'd14;
                        example_part = `LP_PART_WHEEL;
                        example_row = 2'd3;
                        example_col = 2'd0;
                    end
                    // Green Drag Arrow -> (x: 33..40, y: 18..22) pointing into Grid
                    if ((y == 20 && x >= 33 && x <= 40) ||
                        ((x == 38 || x == 39) && y >= 18 && y <= 22) ||
                        (x == 37 && (y == 17 || y == 23)))
                        pixel_data = 16'h07e0;
                    // Mini 3x3 Build Grid (x: 42..51, y: 15..24) with target cell lit Green
                    if (x >= 42 && x <= 51 && y >= 15 && y <= 24) begin
                        if (x >= 45 && x <= 48 && y >= 21 && y <= 24)
                            pixel_data = (x == 45 || x == 48 || y == 21 || y == 24) ? 16'h07e0 : 16'h03a0;
                        else if (x == 42 || x == 45 || x == 48 || x == 51 ||
                                 y == 15 || y == 18 || y == 21 || y == 24)
                            pixel_data = 16'h7bef;
                        else
                            pixel_data = 16'h0841;
                    end
                end

                // Bottom Card (x: 4..91, y: 31..49): Right-Click = Put Back from Grid
                if (x >= 4 && x <= 91 && y >= 31 && y <= 49) begin
                    if (x == 4 || x == 91 || y == 31 || y == 49) pixel_data = 16'h04b4;
                    else pixel_data = 16'h1082;
                    // Mouse Cord at top (x=12, y:32..34)
                    if (x == 12 && y >= 32 && y <= 34) pixel_data = 16'h7bef;
                    // Curved Mouse Body (x: 7..17, y: 35..46)
                    if (x >= 7 && x <= 17 && y >= 35 && y <= 46 &&
                        !((x <= 8 || x >= 16) && y == 35) &&
                        !((x == 7 || x == 17) && (y == 36 || y == 46))) begin
                        if (y == 35 || y == 46 || x == 7 || x == 17 || y == 40 ||
                            (y == 36 && (x == 8 || x == 16)) ||
                            (x == 12 && y >= 36 && y <= 39))
                            pixel_data = 16'hffff;
                        else if (y < 40)
                            pixel_data = (x > 12) ? 16'hf800 : 16'h4208; // Bright RED Right Button!
                        else
                            pixel_data = 16'hd69a; // Silver palm rest
                    end
                    // 12x12 Wheel Part returned to stock (x: 20..31, y: 34..45) via shared part_sprite12
                    if (x >= 20 && x < 32 && y >= 34 && y < 46) begin
                        example_draw = 1'b1;
                        example_local_x = x - 7'd20;
                        example_local_y = y - 6'd34;
                        example_part = `LP_PART_WHEEL;
                        example_row = 2'd3;
                        example_col = 2'd1;
                    end
                    // Red Return Arrow <- (x: 33..40, y: 38..42) pointing back from Grid
                    if ((y == 40 && x >= 33 && x <= 40) ||
                        ((x == 34 || x == 35) && y >= 38 && y <= 42) ||
                        (x == 36 && (y == 37 || y == 43)))
                        pixel_data = 16'hf800;
                    // Mini 3x3 Build Grid (x: 42..51, y: 35..44) with removed cell lit Red
                    if (x >= 42 && x <= 51 && y >= 35 && y <= 44) begin
                        if (x >= 45 && x <= 48 && y >= 41 && y <= 44)
                            pixel_data = (x == 45 || x == 48 || y == 41 || y == 44) ? 16'hf800 : 16'h3800;
                        else if (x == 42 || x == 45 || x == 48 || x == 51 ||
                                 y == 35 || y == 38 || y == 41 || y == 44)
                            pixel_data = 16'h7bef;
                        else
                            pixel_data = 16'h0841;
                    end
                end
            end else if (diary_page == 2'd2) begin
                // --- PAGE 2/2: DEDICATED BOARD SWITCHES SCREEN (diary_page == 2) ---
                if (x >= 4 && x <= 91 && y >= 11 && y <= 49) begin
                    if (x == 4 || x == 91 || y == 11 || y == 49) pixel_data = 16'h04b4;
                    else if (y >= 30) begin
                        // Dark green Basys 3 PCB bottom strip where physical switches sit
                        pixel_data = (y == 30) ? 16'h03a0 : 16'h01c0;
                    end else begin
                        pixel_data = 16'h1082;
                    end

                    // Spacious Visual Icons directly above each switch (y: 14..26):
                    // Gameplay switches sit on the left cluster and settings
                    // switches on the right cluster of the Basys 3 board.
                    // 1) Above SW15 (x: 7..20, center 13): Cyan Reverse Double-Arrow <->
                    if ((y == 20 && x >= 8 && x <= 19) ||
                        ((x == 9 || x == 18) && (y == 19 || y == 21)) ||
                        ((x == 10 || x == 17) && (y == 18 || y == 22)))
                        pixel_data = 16'h07ff;

                    // 2) Above SW14 (x: 23..36, center 29): 4-Way Free-Look Pan Compass Crosshair (+)
                    if ((y == 20 && x >= 24 && x <= 34) ||
                        (x == 29 && y >= 15 && y <= 25) ||
                        (y == 16 && x >= 28 && x <= 30) ||
                        (y == 24 && x >= 28 && x <= 30) ||
                        (x == 25 && y >= 19 && y <= 21) ||
                        (x == 33 && y >= 19 && y <= 21))
                        pixel_data = 16'hffe0;

                    // 3) Above SW1 (x: 60..73, center 66): 1-OLED Screen Monitor Icon
                    if (x >= 61 && x <= 72 && y >= 15 && y <= 23) begin
                        if (x == 61 || x == 72 || y == 15 || y == 23)
                            pixel_data = 16'h07ff; // Cyan OLED screen bezel
                        else if ((x == 67 && y >= 17 && y <= 21) || (x == 66 && y == 18) || (x >= 66 && x <= 68 && y == 21))
                            pixel_data = 16'hffff; // White '1' inside screen
                        else
                            pixel_data = 16'h0210; // Dark screen fill
                    end else if (y == 24 && x >= 65 && x <= 68) begin
                        pixel_data = 16'h07ff; // Monitor stand base
                    end

                    // 4) Above SW0 (x: 76..89, center 82): Gold Speaker + Red Mute 'X'
                    if ((x >= 77 && x <= 78 && y >= 19 && y <= 21) ||
                        (x == 79 && y >= 18 && y <= 22) ||
                        (x == 80 && y >= 17 && y <= 23) ||
                        (x == 81 && y >= 16 && y <= 24))
                        pixel_data = 16'hffe0;
                    if (x >= 83 && x <= 87 && y >= 18 && y <= 22 &&
                        (x - 83 == y - 18 || 87 - x == y - 18))
                        pixel_data = 16'hf800; // Red mute 'X' next to speaker

                    // 4 Highlighted Slide Switches on the Basys 3 bottom edge:
                    // SW15 (x:7..20), SW14 (x:23..36), SW1 (x:60..73), SW0 (x:76..89)
                    if (y >= 32 && y <= 47) begin
                        if ((x >= 7  && x <= 20) || (x >= 23 && x <= 36) ||
                            (x >= 60 && x <= 73) || (x >= 76 && x <= 89)) begin
                            if (y == 32 || y == 47 ||
                                x == 7  || x == 20 || x == 23 || x == 36 ||
                                x == 60 || x == 73 || x == 76 || x == 89)
                                pixel_data = 16'h7bef; // Metallic switch housing
                            else if (y <= 35)
                                pixel_data = 16'hffe0; // Gold actuator lever at top
                            else
                                pixel_data = 16'h2104; // Dark switch slot behind number
                        end
                    end
                end
            end else begin
                // --- MAIN SETTINGS VIEW (diary_page == 0): Sound & Map Cards ---
                // Box 1: SOUND SETTINGS (x: 8..44, y: 12..48)
                if (x >= 8 && x <= 44 && y >= 12 && y <= 48) begin
                    if (x == 8 || x == 44 || y == 12 || y == 48)
                        pixel_data = (cursor_x >= 8 && cursor_x <= 44 && cursor_y >= 12 && cursor_y <= 48) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 8 && cursor_x <= 44 && cursor_y >= 12 && cursor_y <= 48)
                        pixel_data = 16'h0432; // Ocean teal hover glow
                    else
                        pixel_data = 16'h18e5;

                    // Speaker Icon centered at x=26 (x: 19..32, y: 17..27)
                    if ((x >= 19 && x <= 21 && y >= 20 && y <= 24) ||
                        (x == 22 && y >= 19 && y <= 25) ||
                        (x == 23 && y >= 18 && y <= 26) ||
                        (x == 24 && y >= 17 && y <= 27) ||
                        (x == 27 && y >= 19 && y <= 25) ||
                        (x == 28 && (y == 20 || y == 24)) ||
                        (x == 31 && y >= 18 && y <= 26) ||
                        (x == 32 && (y == 19 || y == 25)))
                        pixel_data = 16'hffe0;

                    // Red mute slash across speaker if muted (4-pixel thick diagonal slash)
                    if (audio_muted && (x >= 18 && x <= 33 && y >= 16 && y <= 29 &&
                                        (x - y - 2 >= 0 && x - y - 2 <= 3)))
                        pixel_data = 16'hf800;

                    // 4 Stepped Volume Bars centered in card (x: 16..34, y: 33..44)
                    if (y >= 33 && y <= 44) begin
                        if (x >= 16 && x <= 19 && y >= 42)
                            pixel_data = (!audio_muted && master_volume >= 1) ? 16'h07e0 : 16'h2945;
                        else if (x >= 21 && x <= 24 && y >= 39)
                            pixel_data = (!audio_muted && master_volume >= 2) ? 16'h07e0 : 16'h2945;
                        else if (x >= 26 && x <= 29 && y >= 36)
                            pixel_data = (!audio_muted && master_volume >= 3) ? 16'h07e0 : 16'h2945;
                        else if (x >= 31 && x <= 34 && y >= 33)
                            pixel_data = (!audio_muted && master_volume >= 4) ? 16'h07e0 : 16'h2945;
                    end
                end

                // Box 2: MAP SELECTOR (x: 51..87, y: 12..48)
                if (x >= 51 && x <= 87 && y >= 12 && y <= 48) begin
                    if (x == 51 || x == 87 || y == 12 || y == 48)
                        pixel_data = (cursor_x >= 51 && cursor_x <= 87 && cursor_y >= 12 && cursor_y <= 48) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 51 && cursor_x <= 87 && cursor_y >= 12 && cursor_y <= 48)
                        pixel_data = 16'h0432; // Ocean teal hover glow
                    else
                        pixel_data = 16'h18e5;

                    // Realistic 3-Panel Accordion Folded Terrain Map Icon centered at (69, 22)
                    if (x >= 61 && x <= 77 && y >= 16 && y <= 28) begin
                        if (x >= 67 && x <= 71) begin
                            // Middle panel shifted down 1px for 3D accordion fold
                            if (y >= 17 && y <= 28) begin
                                if (y == 17 || y == 28) pixel_data = 16'h9c45;
                                else if (y <= 21) pixel_data = 16'h2684; // Green highland hills
                                else if (y >= 24 && x >= 68 && x <= 70) pixel_data = 16'h1d9f; // Blue river & bay
                                else if (x == 68 && y >= 22) pixel_data = 16'h1d9f; // River channel
                                else pixel_data = 16'hd632; // Shaded fold parchment coastline
                            end
                        end else if (y >= 16 && y <= 27) begin
                            // Left (61..66) and Right (72..77) panels
                            if (x == 61 || x == 77 || y == 16 || y == 27) pixel_data = 16'hc588;
                            else if (x <= 66 && y <= 22) pixel_data = 16'h2684; // West green continent
                            else if (x >= 64 && x <= 66 && y >= 24) pixel_data = 16'h1d9f; // West sea / river mouth
                            else if (x >= 72 && y <= 20) pixel_data = 16'h2684; // East green continent
                            else if (x >= 73 && x <= 75 && y == 21) pixel_data = 16'h3f07; // Bright green coastal ridge
                            else if (x >= 72 && y >= 23) pixel_data = 16'h1d9f; // East ocean bay
                            else pixel_data = 16'hffdf; // Sandy parchment coastline
                        end
                    end

                    // Map Indicator Boxes (Map 1 vs Map 2) centered at y: 35..43
                    if (y >= 35 && y <= 43) begin
                        if (x >= 59 && x <= 67) begin
                            if (x == 59 || x == 67 || y == 35 || y == 43) pixel_data = (level_index == `LP_LEVEL_ARCH) ? 16'hffe0 : 16'h2945;
                            else pixel_data = (level_index == `LP_LEVEL_ARCH) ? 16'h07e0 : 16'h18e5;
                        end else if (x >= 71 && x <= 79) begin
                            if (x == 71 || x == 79 || y == 35 || y == 43) pixel_data = (level_index == `LP_LEVEL_FLIGHT) ? 16'hffe0 : 16'h2945;
                            else pixel_data = (level_index == `LP_LEVEL_FLIGHT) ? 16'h07e0 : 16'h18e5;
                        end
                    end
                end
            end

            // Bottom Left [ ? ] Controls Toggle Button (x: 2..25, y: 52..62)
            if (x >= 2 && x <= 25 && y >= 52 && y <= 62) begin
                if (x == 2 || x == 25 || y == 52 || y == 62)
                    pixel_data = (cursor_x >= 2 && cursor_x <= 25 && cursor_y >= 52 && cursor_y <= 62) ? 16'hffe0 : ((diary_page == 2'd1 || diary_page == 2'd2) ? 16'h07ff : 16'h04b4);
                else if (cursor_x >= 2 && cursor_x <= 25 && cursor_y >= 52 && cursor_y <= 62)
                    pixel_data = 16'h0432;
                else
                    pixel_data = (diary_page == 2'd1 || diary_page == 2'd2) ? 16'h0351 : 16'h18e5;
                // Pixel-art '?' icon centered at (13, 57)
                if ((y == 54 && x >= 12 && x <= 15) ||
                    (y == 55 && (x == 11 || x == 15 || x == 16)) ||
                    (y == 56 && (x == 14 || x == 15)) ||
                    (y == 57 && (x == 13 || x == 14)) ||
                    (y == 58 && (x == 13 || x == 14)) ||
                    (y == 60 && (x == 13 || x == 14)))
                    pixel_data = (diary_page == 2'd1 || diary_page == 2'd2) ? 16'hffe0 : 16'h07ff;
            end

            // Bottom Centered [ BACK ] Button (x: 28..68, y: 52..62)
            if (x >= 28 && x <= 68 && y >= 52 && y <= 62) begin
                if (x == 28 || x == 68 || y == 52 || y == 62)
                    pixel_data = (cursor_x >= 28 && cursor_x <= 68 && cursor_y >= 52 && cursor_y <= 62) ? 16'hffe0 : 16'h04b4;
                else if (cursor_x >= 28 && cursor_x <= 68 && cursor_y >= 52 && cursor_y <= 62)
                    pixel_data = 16'h0432;
                else
                    pixel_data = 16'h18e5;
                if (back_arrow_lit) pixel_data = 16'hffff;
            end

            // Bottom Right [ HOME ] Button (x: 70..95, y: 52..62)
            if (x >= 70 && x <= 95 && y >= 52 && y <= 62) begin
                if (x == 70 || x == 95 || y == 52 || y == 62)
                    pixel_data = (cursor_x >= 70 && cursor_x <= 95 && cursor_y >= 52 && cursor_y <= 62) ? 16'hffe0 : 16'h04b4;
                else if (cursor_x >= 70 && cursor_x <= 95 && cursor_y >= 52 && cursor_y <= 62)
                    pixel_data = 16'h0432;
                else
                    pixel_data = 16'h18e5;
                if (home_icon_lit) pixel_data = 16'hffff;
            end

        end else if (game_state == `LP_GUIDE) begin
            // -----------------------------------------------------------------
            // GUIDE / DIARY SCREEN: 3-Scene Interactive Map Checkpoint Walkthrough
            //   - Left OLED shows 3x3 Vehicle Grid (with active part highlighted) + Action Card
            //   - Right OLED live camera jumps to Checkpoint 1, 2, or 3 with posed vehicle!
            // -----------------------------------------------------------------
            pixel_data = (y < 10) ? 16'h18e5 : ((y == 10) ? 16'h04b4 : 16'h0841);

            if (diary_page != 2'd3) begin
                // --- TABS 1, 2, 3: INTERACTIVE CHECKPOINT WALKTHROUGH ---
                // 1. Left Half (x: 4..39, y: 12..47): 36x36 Vehicle Grid using shared part_sprite12
                if (x >= 4 && x < 40 && y >= 12 && y < 48) begin
                    if (x < 16)      begin example_col = 0; example_local_x = x - 4;  end
                    else if (x < 28) begin example_col = 1; example_local_x = x - 16; end
                    else             begin example_col = 2; example_local_x = x - 28; end
                    if (y < 24)      begin example_row = 0; example_local_y = y - 12; end
                    else if (y < 36) begin example_row = 1; example_local_y = y - 24; end
                    else             begin example_row = 2; example_local_y = y - 36; end
                    example_draw = 1'b1;
                    // Map 1: [Empty, Up-Rocket, Empty] / [Frame, Pig, Engine] / [Wheel, Empty, Wheel].
                    // Map 2: [Left-Fan, Frame, Balloon] / [Frame, Pig, Engine] / [Wheel, Down-Fan, Wheel].
                    example_has_frame = (example_row == 1) || (level_index != 0 && example_row == 0 && example_col == 1);
                    if (example_row == 0 && example_col == 1 && level_index == 0)
                        example_part = `LP_PART_BOOSTER;
                    else if (example_row == 0 && example_col == 0 && level_index != 0)
                        example_part = `LP_PART_FAN;
                    else if (example_row == 0 && example_col == 2 && level_index != 0)
                        example_part = `LP_PART_BALLOON;
                    else if (example_row == 1 && example_col == 1)
                        example_part = `LP_PART_PIG;
                    else if (example_row == 1 && example_col == 2)
                        example_part = `LP_PART_ENGINE;
                    else if (example_row == 2 && example_col == 1 && level_index != 0)
                        example_part = `LP_PART_FAN;
                    else if (example_row == 2 && (example_col == 0 || example_col == 2))
                        example_part = `LP_PART_WHEEL;
                    else
                        example_part = `LP_PART_EMPTY;
                end

                // 2. Right Half (x: 43..92, y: 12..47): Checkpoint Action Card
                if (x >= 43 && x <= 92 && y >= 12 && y <= 47) begin
                    if (x == 43 || x == 92 || y == 12 || y == 47) pixel_data = 16'h04b4;
                    else pixel_data = 16'h1082;
                end

                // Active 12x12 Part Sprite inside Action Card (x: 47..58, y: 15..26)
                if (x >= 47 && x < 59 && y >= 15 && y < 27) begin
                    example_draw = 1'b1;
                    example_local_x = x - 7'd47;
                    example_local_y = y - 6'd15;
                    example_row = 2'd3; // Tag as Action Card icon
                    if (diary_page == 2'd0) begin
                        example_has_frame = (level_index == 0); // Only Engine sits inside a frame; Fan does not
                        example_part = (level_index == 0) ? `LP_PART_ENGINE : `LP_PART_FAN;
                    end else if (diary_page == 2'd1) begin
                        example_has_frame = 1'b0;
                        example_part = (level_index == 0) ? `LP_PART_BOOSTER : `LP_PART_FAN;
                    end else begin
                        example_has_frame = (level_index == 0);
                        example_part = (level_index == 0) ? `LP_PART_ENGINE : `LP_PART_FAN;
                    end
                end

                // Action Vector Pictogram & Target Icon (x: 62..89, y: 15..27)
                if (diary_page == 2'd0) begin
                    if (level_index == 0) begin
                        // Map 1 Step 1: Green Drive Right Arrow -> (x: 63..86, y: 18..24)
                        if ((y >= 20 && y <= 22 && x >= 63 && x <= 84) ||
                            ((x == 82 || x == 83) && y >= 18 && y <= 24) ||
                            (x == 81 && (y == 17 || y == 25)))
                            pixel_data = 16'h07e0;
                    end else begin
                        // Map 2 Step 1: Cyan Float Up-Right Arrow ^> (x: 65..82, y: 15..26)
                        if ((x >= 66 && x <= 76 && (x - 7'd66 == 6'd26 - y || x - 7'd67 == 6'd26 - y)) ||
                            (y == 16 && x >= 72 && x <= 77) || (x == 77 && y >= 16 && y <= 21))
                            pixel_data = 16'h07ff;
                    end
                end else if (diary_page == 2'd1) begin
                    // Target Star Crate Icon on Right of Card (x: 78..88, y: 16..26)
                    if (x >= 78 && x <= 88 && y >= 16 && y <= 26) begin
                        if (x == 78 || x == 88 || y == 16 || y == 26) pixel_data = 16'hc4a3;
                        else if ((y == 17 && x == 83) ||
                                 (y == 18 && x >= 82 && x <= 84) ||
                                 (y == 19 && x >= 79 && x <= 87) ||
                                 (y == 20 && x >= 80 && x <= 86) ||
                                 (y == 21 && x >= 81 && x <= 85) ||
                                 (y == 22 && ((x >= 80 && x <= 82) || (x >= 84 && x <= 86))) ||
                                 (y == 23 && ((x >= 80 && x <= 81) || (x >= 85 && x <= 86))) ||
                                 (y == 24 && (x == 79 || x == 87)))
                            pixel_data = 16'hffe0;
                        else pixel_data = 16'h7261;
                    end
                    if (level_index == 0) begin
                        // Map 1 Step 2: Cyan Reverse + Rocket Up Arrow <^ (x: 62..74, y: 16..24)
                        if ((x >= 63 && x <= 73 && (x - 7'd63 == y - 6'd16 || x - 7'd64 == y - 6'd16)) ||
                            (y == 16 && x >= 63 && x <= 68) || (x == 63 && y >= 16 && y <= 21))
                            pixel_data = 16'h07ff;
                    end else begin
                        // Map 2 Step 2: Cyan Lift Fan Control Arrow v (x: 65..71, y: 16..25)
                        if ((x == 68 && y >= 16 && y <= 25) ||
                            (y == 23 && x >= 66 && x <= 70) ||
                            (y == 22 && (x == 65 || x == 71)))
                            pixel_data = 16'h07ff;
                    end
                end else begin
                    // Step 3: Checkered Finish Flag on Right (x: 78..88, y: 16..26) + Boost Arrow
                    if (x == 78 && y >= 16 && y <= 26) pixel_data = 16'hffff;
                    else if (x >= 79 && x <= 88 && y >= 16 && y <= 21)
                        pixel_data = (((x >> 1) + (y >> 1)) & 1'b1) ? 16'hffff : 16'hf800;
                    // Orange Boost Arrow -> (x: 62..74, y: 19..23)
                    if ((y == 21 && x >= 62 && x <= 74) ||
                        ((x == 72 || x == 73) && y >= 19 && y <= 23))
                        pixel_data = 16'hfd20;
                end
            end else begin
                // --- SOUND SETTINGS PAGE (diary_page == 3) ---
                // Button [-]: x: 8..28, y: 24..37
                if (x >= 8 && x <= 28 && y >= 24 && y <= 37) begin
                    if (x == 8 || x == 28 || y == 24 || y == 37)
                        pixel_data = (cursor_x >= 8 && cursor_x <= 28 && cursor_y >= 24 && cursor_y <= 37) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 8 && cursor_x <= 28 && cursor_y >= 24 && cursor_y <= 37) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                end

                // 4 Stepped Volume Indicator Bars (x: 34..58, y: 25..37)
                if (x >= 34 && x <= 37 && y >= 34 && y <= 37)
                    pixel_data = (!audio_muted && master_volume >= 1) ? 16'h07e0 : 16'h2945;
                else if (x >= 41 && x <= 44 && y >= 31 && y <= 37)
                    pixel_data = (!audio_muted && master_volume >= 2) ? 16'h07e0 : 16'h2945;
                else if (x >= 48 && x <= 51 && y >= 28 && y <= 37)
                    pixel_data = (!audio_muted && master_volume >= 3) ? 16'h07e0 : 16'h2945;
                else if (x >= 55 && x <= 58 && y >= 25 && y <= 37)
                    pixel_data = (!audio_muted && master_volume >= 4) ? 16'h07e0 : 16'h2945;

                // Button [+]: x: 64..84, y: 24..37
                if (x >= 64 && x <= 84 && y >= 24 && y <= 37) begin
                    if (x == 64 || x == 84 || y == 24 || y == 37)
                        pixel_data = (cursor_x >= 64 && cursor_x <= 84 && cursor_y >= 24 && cursor_y <= 37) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 64 && cursor_x <= 84 && cursor_y >= 24 && cursor_y <= 37) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                end
            end

            // Bottom toolbar: [BACK] [ 1 ] [ 2 ] [ 3 ]
            if (y >= 52) begin
                if (x <= 27) begin
                    if (x == 0 || x == 27 || y == 52 || y == 63)
                        pixel_data = (cursor_x <= 27 && cursor_y >= 52) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x <= 27 && cursor_y >= 52)
                        pixel_data = 16'h0432; // Ocean teal hover glow
                    else
                        pixel_data = 16'h18e5;
                    if (back_arrow_lit) pixel_data = 16'hffff;
                end else if (diary_page != 3 && y >= 55) begin
                    if (x >= 32 && x <= 51) begin
                        if (x == 32 || x == 51 || y == 55 || y == 63)
                            pixel_data = ((diary_page == 0) || (cursor_x >= 32 && cursor_x <= 51 && cursor_y >= 55)) ? 16'hffe0 : 16'h04b4;
                        else if (cursor_x >= 32 && cursor_x <= 51 && cursor_y >= 55)
                            pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end else if (x >= 53 && x <= 72) begin
                        if (x == 53 || x == 72 || y == 55 || y == 63)
                            pixel_data = ((diary_page == 1) || (cursor_x >= 53 && cursor_x <= 72 && cursor_y >= 55)) ? 16'hffe0 : 16'h04b4;
                        else if (cursor_x >= 53 && cursor_x <= 72 && cursor_y >= 55)
                            pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end else if (x >= 74 && x <= 93) begin
                        if (x == 74 || x == 93 || y == 55 || y == 63)
                            pixel_data = ((diary_page == 2) || (cursor_x >= 74 && cursor_x <= 93 && cursor_y >= 55)) ? 16'hffe0 : 16'h04b4;
                        else if (cursor_x >= 74 && cursor_x <= 93 && cursor_y >= 55)
                            pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end
                end
            end
        end else if (game_state == `LP_BUILD) begin
            // -----------------------------------------------------------------
            // BUILD SCREEN: Centralized GO and Authentic Icons
            // -----------------------------------------------------------------
            if (y >= 55 && feedback_code == `LP_FEEDBACK_NONE) begin
                pixel_data = 16'h0841;
                // GO Button (x: 0..17, centered text at x=4)
                if (x < 18) begin
                    if (x == 0 || x == 17 || y == 55 || y == 63)
                        pixel_data = (cursor_x < 18 && cursor_y >= 55) ? (build_valid ? 16'hffe0 : 16'hf800) : (build_valid ? 16'h07e0 : 16'h4208);
                    else if (cursor_x < 18 && cursor_y >= 55)
                        pixel_data = build_valid ? 16'h0351 : 16'h2945;
                    else pixel_data = build_valid ? 16'h18e5 : 16'h18c3;
                    if (is_checkmark_icon(7'd8, 6'd59, x, y)) pixel_data = build_valid ? 16'h07e0 : 16'h7bef;
                end
                // Open Book Diary Icon (x: 64..79)
                else if (x >= 64 && x < 80) begin
                    if (x == 64 || x == 79 || y == 55 || y == 63)
                        pixel_data = (cursor_x >= 64 && cursor_x < 80 && cursor_y >= 55) ? 16'hffe0 : 16'h04b4;
                    else begin
                        pixel_data = (cursor_x >= 64 && cursor_x < 80 && cursor_y >= 55) ? 16'h0351 : 16'h18e5;
                        if (diary_icon[16]) pixel_data = diary_icon[15:0];
                    end
                end
                // Settings Gear Icon (x: 80..95)
                else if (x >= 80 && x < 96) begin
                    if (x == 80 || x == 95 || y == 55 || y == 63)
                        pixel_data = (cursor_x >= 80 && cursor_y >= 55) ? 16'hffe0 : 16'h04b4;
                    else begin
                        pixel_data = (cursor_x >= 80 && cursor_y >= 55) ? 16'h0351 : 16'h18e5;
                        if (gear_lit) pixel_data = gear_colour;
                    end
                end
            end
        end else if (game_state == `LP_RUN) begin
            // -----------------------------------------------------------------
            // RUN SCREEN: Big 16x16 Interactive Grid, Clean Layout
            // -----------------------------------------------------------------
            // Middle Panel (x: 24..71, y: 2..49) is rendered by left_renderer via base_pixel.
            if (x >= 24 && x <= 71 && y >= 2 && y <= 49) begin
                pixel_data = base_pixel;
            end else begin
                pixel_data = 16'h0841;
            end

            // Bottom Action Bar (y: 53..63): [ TRY ] | [ END ] | [ EDIT ] | [ GEAR ]
            if (y >= 53) begin
                // Button 1: [ TRY ] (x: 2..22)
                if (x >= 2 && x <= 22) begin
                    if (x == 2 || x == 22 || y == 53 || y == 63)
                        pixel_data = ((cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) || retry_glow) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (retry_lit) pixel_data = retry_glow ? 16'hffe0 : 16'hffff;
                end

                // Button 2: [ END TRY ] (x: 26..46, center 36)
                else if (x >= 26 && x <= 46) begin
                    if (x == 26 || x == 46 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 26 && cursor_x <= 46 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 26 && cursor_x <= 46 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (is_stop_icon(7'd36, 6'd58, x, y)) pixel_data = 16'hf800; // Red stop icon
                end

                // Button 3: [ EDIT ] (x: 50..70, center 60) - Wrench Icon
                else if (x >= 50 && x <= 70) begin
                    if (x == 50 || x == 70 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (wrench_icon[16]) pixel_data = wrench_icon[15:0];
                end

                // Button 4: [ GEAR ] (x: 74..94)
                else if (x >= 74 && x <= 94) begin
                    if (x == 74 || x == 94 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (gear_lit) pixel_data = gear_colour;
                end
            end
        end else if (game_state == `LP_SUCCESS || game_state == `LP_FAIL) begin
            // -----------------------------------------------------------------
            // RESULT SCREEN (Option A): Big Stacked [NEXT/EDIT] + [RETRY] on Right,
            //                           [HOME] | [MAP SELECT] | [GUIDE] on Bottom
            // -----------------------------------------------------------------
            if (x >= 54 && y < 53) begin
                pixel_data = 16'h0841;
                // Big Button 1: [ NEXT / EDIT ] (x: 56..92, y: 6..26, center 74, 16)
                if (x >= 56 && x <= 92 && y >= 6 && y <= 26) begin
                    if (x == 56 || x == 92 || y == 6 || y == 26)
                        pixel_data = ((cursor_x >= 56 && cursor_x <= 92 && cursor_y >= 6 && cursor_y <= 26) || retry_glow) ? 16'hffe0 : ((game_state == `LP_SUCCESS) ? 16'h07e0 : 16'h04b4);
                    else if ((cursor_x >= 56 && cursor_x <= 92 && cursor_y >= 6 && cursor_y <= 26) || retry_glow)
                        pixel_data = 16'h0351;
                    else
                        pixel_data = 16'h18e5;
                    if (game_state == `LP_SUCCESS) begin
                        if (is_play_icon(7'd74, 6'd16, x, y)) pixel_data = retry_glow ? 16'hffe0 : 16'h07e0; // Bright green / blinking gold play triangle
                    end else begin
                        if (wrench_icon[16]) pixel_data = wrench_icon[15:0];
                    end
                end
                // Big Button 2: [ RETRY ] (x: 56..92, y: 30..50, center 74, 40)
                else if (x >= 56 && x <= 92 && y >= 30 && y <= 50) begin
                    if (x == 56 || x == 92 || y == 30 || y == 50)
                        pixel_data = (cursor_x >= 56 && cursor_x <= 92 && cursor_y >= 30 && cursor_y <= 50) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 56 && cursor_x <= 92 && cursor_y >= 30 && cursor_y <= 50)
                        pixel_data = 16'h0351;
                    else
                        pixel_data = 16'h18e5;
                    if (retry_lit) pixel_data = 16'hffff;
                end
            end
            if (y >= 53) begin
                pixel_data = 16'h0841;
                // Button 1: [ HOME ] (x: 2..22, center 12, 58)
                if (x >= 2 && x <= 22) begin
                    if (x == 2 || x == 22 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (home_icon_lit) pixel_data = 16'hffff;
                end
                // Button 2: [ MAP SELECT ] (x: 26..46, center 36, 58)
                else if (x >= 26 && x <= 46) begin
                    if (x == 26 || x == 46 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 26 && cursor_x <= 46 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 26 && cursor_x <= 46 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    pixel_data = draw_map_icon(7'd36, 6'd58, x, y, pixel_data);
                end
                // Button 3: [ GUIDE ] (x: 50..70, center 60, 58)
                else if (x >= 50 && x <= 70) begin
                    if (x == 50 || x == 70 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (diary_icon[16]) pixel_data = diary_icon[15:0];
                end
                // Button 4: [ SETTINGS GEAR ] (x: 74..94, center 84, 58)
                else if (x >= 74 && x <= 94) begin
                    if (x == 74 || x == 94 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (gear_lit) pixel_data = gear_colour;
                end
            end
        end

        // Shared single part_sprite12 evaluator for Guide Grid, Action Card, and Mouse Tutorial Screen
        if (example_draw) begin
            pixel_data = 16'h0841;
            if (!example_has_frame && (example_local_x == 0 || example_local_y == 0 ||
                example_local_x == 11 || example_local_y == 11)) begin
                pixel_data = 16'h2945;
            end
            if (example_has_frame)
                pixel_data = part_sprite12(`LP_PART_FRAME, example_local_x, example_local_y, 1'b0, pixel_data);
            if (example_part != `LP_PART_EMPTY)
                pixel_data = part_sprite12(example_part,
                    (example_part == `LP_PART_BOOSTER && level_index == 0) ? ((example_local_x >= 4'd9) ? 4'd15 : (4'd11 - example_local_y)) :
                    (example_part == `LP_PART_FAN && (example_row == 2'd2 || (example_row == 2'd3 && diary_page != 2'd0))) ? example_local_y :
                    (example_part == `LP_PART_FAN) ? (4'd11 - example_local_x) : example_local_x,
                    (example_part == `LP_PART_BOOSTER && level_index == 0) ? example_local_x :
                    (example_part == `LP_PART_FAN && (example_row == 2'd2 || (example_row == 2'd3 && diary_page != 2'd0))) ? (4'd11 - example_local_x) :
                    example_local_y,
                    1'b0, pixel_data);
            // Drawn AFTER part_sprite12 so gold/red/green active border highlights wood-framed parts too!
            if (example_local_x == 0 || example_local_y == 0 ||
                example_local_x == 11 || example_local_y == 11) begin
                if (game_state == `LP_SETTINGS) begin
                    pixel_data = (example_col == 2'd1) ? 16'hf800 : 16'h07e0;
                end else if (example_row == 2'd3) begin
                    pixel_data = 16'hffe0;
                end else if ((diary_page == 2'd0 && level_index == 0 && ((example_row == 1 && example_col == 2) || (example_row == 2 && example_col != 1))) ||
                             (diary_page == 2'd0 && level_index != 0 && ((example_row == 0 && example_col == 0) || (example_row == 1 && example_col == 2) || (example_row == 2 && example_col == 1))) ||
                             (diary_page == 2'd1 && level_index == 0 && (example_row == 0 && example_col == 1)) ||
                             (diary_page == 2'd1 && level_index != 0 && ((example_row == 0 && example_col == 0) || (example_row == 2 && example_col == 1))) ||
                             (diary_page == 2'd2 && level_index == 0 && ((example_row == 1 && example_col == 2) || (example_row == 2 && example_col != 1))) ||
                             (diary_page == 2'd2 && level_index != 0 && ((example_row == 1 && example_col == 2) || (example_row == 2 && example_col == 1)))) begin
                    pixel_data = 16'hffe0; // Active part gold border
                end
            end
        end

        // The shared text line sits above each screen's panels; no drawing overlaps its letters.
        if (line_lit) pixel_data = line_colour;

        // Mouse pointer overlay (topmost layer)
        if ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
            (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))
            pixel_data = 16'hffff;
    end
endmodule
