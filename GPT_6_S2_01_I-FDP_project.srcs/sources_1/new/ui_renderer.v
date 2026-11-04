// Owner: Role 1 - Kaushal; shared left-screen layout with Role 4 - Marcus.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_renderer (
    input wire [6:0] x,
    input wire [5:0] y,
    input wire [15:0] base_pixel,
    input wire [2:0] game_state, feedback_code,
    input wire start_screen_active,
    input wire [2:0] map_draw_class,
    input wire [1:0] diary_page, run_page,
    input wire [1:0] inventory_page,
    input wire selected_left, audio_muted,
    input wire [2:0] selected_part,
    input wire [2:0] master_volume,
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    input wire build_valid, engine_enabled, boost_active,
    input wire engine_available,
    input wire fan_available, fan_on, rocket_available, rocket_ready, balloon_available,
    input wire anim_phase,
    input wire [6:0] cursor_x, cursor_y,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input tri0 [8:0] build_frames,
    input wire [8:0] build_facing_left,
    input tri0 [8:0] build_facing_down,
    input tri0 [8:0] active_fans,
    input wire sw0_engine,
    input tri0 [6:0] cloud_scroll_fg,
    input tri0 [6:0] cloud_scroll_bg,
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
    function [15:0] cartoon_gear;
        input signed [6:0] center_x, center_y, px, py;
        input [15:0] bg;
        reg signed [6:0] lx, ly;
        reg [1:0] pix_code; // 0: bg/valley, 1: bright white-silver, 2: brushed light silver, 3: metallic slate bevel
        begin
            lx = px - center_x;
            ly = py - center_y;
            pix_code = 2'd0;
            cartoon_gear = bg;
            if (center_y == 7'sd59) begin
                // Compact 7x7 8-tooth metallic gear for 9px-tall BUILD toolbar button (y=55..63)
                if (lx >= -3 && lx <= 3 && ly >= -3 && ly <= 3) begin
                    case (ly)
                        -7'sd3: case (lx)  7'sd0: pix_code = 2'd1; default: pix_code = 2'd0; endcase
                        -7'sd2: case (lx) -7'sd2,  7'sd0,  7'sd2: pix_code = 2'd1; default: pix_code = 2'd0; endcase
                        -7'sd1: case (lx) -7'sd1,  7'sd0: pix_code = 2'd1;  7'sd1: pix_code = 2'd2; default: pix_code = 2'd0; endcase
                         7'sd0: case (lx) -7'sd3, -7'sd2, -7'sd1: pix_code = 2'd1;  7'sd1,  7'sd2: pix_code = 2'd2;  7'sd3: pix_code = 2'd3; default: pix_code = 2'd0; endcase
                         7'sd1: case (lx) -7'sd1: pix_code = 2'd1;  7'sd0,  7'sd1: pix_code = 2'd2; default: pix_code = 2'd0; endcase
                         7'sd2: case (lx) -7'sd2: pix_code = 2'd2;  7'sd0,  7'sd2: pix_code = 2'd3; default: pix_code = 2'd0; endcase
                         7'sd3: case (lx)  7'sd0: pix_code = 2'd3; default: pix_code = 2'd0; endcase
                        default: pix_code = 2'd0;
                    endcase
                end
            end else if (lx >= -4 && lx <= 4 && ly >= -4 && ly <= 4) begin
                // 9x9 8-tooth metallic settings gear: distinct N/S/E/W + NW/NE/SW/SE teeth, silver ring, round center hole
                case (ly)
                    -7'sd4: case (lx)  7'sd0: pix_code = 2'd1; default: pix_code = 2'd0; endcase
                    -7'sd3: case (lx) -7'sd3, -7'sd1,  7'sd0,  7'sd1: pix_code = 2'd1;  7'sd3: pix_code = 2'd2; default: pix_code = 2'd0; endcase
                    -7'sd2: case (lx) -7'sd2, -7'sd1,  7'sd0: pix_code = 2'd1;  7'sd1,  7'sd2: pix_code = 2'd2; default: pix_code = 2'd0; endcase
                    -7'sd1: case (lx) -7'sd3, -7'sd2: pix_code = 2'd1; -7'sd1,  7'sd1: pix_code = 2'd3;  7'sd2,  7'sd3: pix_code = 2'd2; default: pix_code = 2'd0; endcase
                     7'sd0: case (lx) -7'sd4, -7'sd3, -7'sd2: pix_code = 2'd1;  7'sd2,  7'sd3: pix_code = 2'd2;  7'sd4: pix_code = 2'd3; default: pix_code = 2'd0; endcase
                     7'sd1: case (lx) -7'sd3, -7'sd2: pix_code = 2'd1; -7'sd1,  7'sd1: pix_code = 2'd3;  7'sd2,  7'sd3: pix_code = 2'd2; default: pix_code = 2'd0; endcase
                     7'sd2: case (lx) -7'sd2, -7'sd1: pix_code = 2'd1;  7'sd0,  7'sd1,  7'sd2: pix_code = 2'd2; default: pix_code = 2'd0; endcase
                     7'sd3: case (lx) -7'sd3: pix_code = 2'd2; -7'sd1,  7'sd0,  7'sd1: pix_code = 2'd2;  7'sd3: pix_code = 2'd3; default: pix_code = 2'd0; endcase
                     7'sd4: case (lx)  7'sd0: pix_code = 2'd3; default: pix_code = 2'd0; endcase
                    default: pix_code = 2'd0;
                endcase
            end
            case (pix_code)
                2'd1: cartoon_gear = 16'hffff; // Specular white-silver
                2'd2: cartoon_gear = 16'hd69a; // Brushed light silver
                2'd3: cartoon_gear = 16'h7bef; // Metallic slate shading
                default: cartoon_gear = bg;
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
                    else if (lx <= -2 && ly <= 0)
                        draw_map_icon = 16'h2684; // Green continent on upper-left panel
                    else if (lx == 0 && ly == -1)
                        draw_map_icon = 16'h2684; // Green continent continuing onto middle panel
                    else if ((lx == -2 && ly == 1) || (lx == -1 && ly >= 0) || (lx == 0 && ly >= 1))
                        draw_map_icon = 16'h1d9f; // Winding blue river across the fold
                    else if (lx == 3 && (ly == -1 || ly == 0))
                        draw_map_icon = 16'hf800; // Red destination pin on right panel
                    else
                        draw_map_icon = in_mid ? 16'hd632 : 16'hffdf; // Parchment paper with 3D fold shadow
                end
            end
        end
    endfunction

    // Helper function for realistic open book / diary icon with curved pages & red bookmark (13x7)
    function [15:0] draw_diary_icon;
        input signed [6:0] cx, cy, px, py;
        input [15:0] bg;
        reg signed [4:0] lx, ly;
        reg [4:0] alx;
        begin
            lx = px - cx;
            ly = py - cy;
            alx = (lx < 0) ? -lx : lx;
            draw_diary_icon = bg;
            if (lx >= -6 && lx <= 6 && ly >= -3 && ly <= 3) begin
                if (lx == 0 && ly >= 1)
                    draw_diary_icon = 16'hf800; // Red ribbon bookmark hanging at bottom spine
                else if (lx == 0)
                    draw_diary_icon = (ly >= -2) ? 16'h8a22 : bg; // V-dip at top of center spine
                else if (alx == 6 || ly == 3)
                    draw_diary_icon = 16'h9182; // Mahogany hardcover binding
                else if (ly == -3)
                    draw_diary_icon = (alx >= 2 && alx <= 5) ? 16'hd69a : bg; // Curved top page edge
                else if (alx == 1)
                    draw_diary_icon = 16'hd69a; // Inner page crease shadow next to spine
                else if ((ly == -1 || ly == 1) && alx >= 2 && alx <= 4)
                    draw_diary_icon = 16'h4a69; // Neat indented slate ink text lines
                else
                    draw_diary_icon = 16'hffff; // Crisp white pages
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

    function [15:0] cartoon_wrench;
        input signed [6:0] cx, cy, px, py;
        input [15:0] bg;
        reg signed [4:0] lx, ly;
        reg [8:0] row;
        begin
            lx = px - cx;
            ly = py - cy;
            row = 9'd0;
            cartoon_wrench = bg;
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
                    cartoon_wrench = (lx + ly <= -1) ? 16'hffff : 16'hc618;
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


    always @* begin
        pixel_data = base_pixel;

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
            if ((x-7'd48)*(x-7'd48) + (y-6'd40)*(y-6'd40) <= 81) begin
                if ((x-7'd48)*(x-7'd48) + (y-6'd40)*(y-6'd40) >= 64) begin
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
                        else if ((y - 6'd40) < -2 && ((x-7'd48)*(x-7'd48) + (y-6'd40)*(y-6'd40)) < 49)
                            pixel_data = 16'h7fe0; // Specular shine
                        else
                            pixel_data = 16'h4fe0; // Vibrant lime green
                    end
                end
            end

            // 4. Settings Button in Bottom-Left (x: 4..20, y: 47..61, Center at 12, 54)
            if (x >= 4 && x <= 20 && y >= 47 && y <= 61) begin
                if (x == 4 || x == 20 || y == 47 || y == 61)
                    pixel_data = (cursor_x >= 4 && cursor_x <= 20 && cursor_y >= 46 && cursor_y <= 62) ? 16'hffe0 : 16'h04b4;
                else if (cursor_x >= 4 && cursor_x <= 20 && cursor_y >= 46 && cursor_y <= 62)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
                pixel_data = cartoon_gear(7'd12, 6'd54, x, y, pixel_data);
            end
        end else if (game_state == `LP_LEVEL_SELECT) begin
            // -----------------------------------------------------------------
            // LEVEL SELECT SCREEN (Maps 1 and 2)
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;
            if (text_on("SELECT MAP      ", 18, 2, x, y)) pixel_data = 16'h07ff;

            // Map 1: Cave Arch
            if (x >= 4 && x <= 91 && y >= 12 && y <= 30) begin
                if (x == 4 || x == 91 || y == 12 || y == 30)
                    pixel_data = (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 12 && cursor_y <= 30) ? 16'hffe0 : ((level_index == 0) ? 16'h07e0 : 16'h04b4);
                else if (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 12 && cursor_y <= 30)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
            end
            if (text_on("CAVE ARCH       ", 10, 14, x, y)) pixel_data = 16'hffff;
            if (text_on("MAP 1           ", 10, 22, x, y)) pixel_data = 16'h07ff;

            // Map 2: Cave Flight (x: 4..91, y: 34..50)
            if (x >= 4 && x <= 91 && y >= 34 && y <= 50) begin
                if (x == 4 || x == 91 || y == 34 || y == 50)
                    pixel_data = (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 34 && cursor_y <= 50) ? 16'hffe0 : ((level_index == 1) ? 16'h07e0 : 16'h04b4);
                else if (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 34 && cursor_y <= 50)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
            end
            if (text_on("CAVE FLIGHT     ", 10, 36, x, y)) pixel_data = 16'hffff;
            if (text_on("MAP 2           ", 10, 43, x, y)) pixel_data = 16'h07ff;

            // Bottom toolbar: [ BACK ]
            if (y >= 52) begin
                if (x <= 27) begin
                    if (x == 0 || x == 27 || y == 52 || y == 63)
                        pixel_data = (cursor_x <= 27 && cursor_y >= 52) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x <= 27 && cursor_y >= 52)
                        pixel_data = 16'h0432; // Ocean teal hover glow
                    else
                        pixel_data = 16'h18e5;
                    if (is_back_arrow(7'd14, 6'd58, x, y)) pixel_data = 16'hffff;
                end else if (text_on("PICK A MAP      ", 32, 56, x, y)) pixel_data = 16'h7bef;
            end
        end else if (game_state == `LP_SETTINGS) begin
            // -----------------------------------------------------------------
            // SETTINGS SCREEN: 100% Visual Glyphs & Stepped Bars (Zero Text Clutter)
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;
            if (text_on("SETTINGS        ", 24, 2, x, y)) pixel_data = 16'h07ff;

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

                // Realistic 3-Panel Accordion Folded Map Icon centered at (69, 22)
                if (x >= 61 && x <= 77 && y >= 16 && y <= 28) begin
                    if (x >= 67 && x <= 71) begin
                        // Middle panel shifted down 1px for 3D accordion fold
                        if (y >= 17 && y <= 28) begin
                            if (y == 17 || y == 28) pixel_data = 16'h9c45;
                            else if (y <= 21 && x <= 69) pixel_data = 16'h2684; // Green hills
                            else if (x == 68 && y >= 22) pixel_data = 16'h1d9f; // Blue river
                            else pixel_data = 16'hd632; // Shaded fold parchment
                        end
                    end else if (y >= 16 && y <= 27) begin
                        // Left (61..66) and Right (72..77) panels
                        if (x == 61 || x == 77 || y == 16 || y == 27) pixel_data = 16'hc588;
                        else if (x <= 66 && y <= 22) pixel_data = 16'h2684; // Green continent
                        else if (x >= 65 && x <= 66 && y >= 23) pixel_data = 16'h1d9f; // River mouth
                        else if (x >= 73 && x <= 75 && y >= 20 && y <= 22 && ((x - 74 == y - 21) || (x - 74 == 21 - y)))
                            pixel_data = 16'hf800; // Red 3x3 'X' treasure marker
                        else pixel_data = 16'hffdf; // Bright parchment
                    end
                end

                // Map Indicator Boxes (Map 1 vs Map 2) centered at y: 35..43
                if (y >= 35 && y <= 43) begin
                    if (x >= 59 && x <= 67) begin
                        if (x == 59 || x == 67 || y == 35 || y == 43) pixel_data = (level_index == 0) ? 16'hffe0 : 16'h2945;
                        else pixel_data = (level_index == 0) ? 16'h07e0 : 16'h18e5;
                    end else if (x >= 71 && x <= 79) begin
                        if (x == 71 || x == 79 || y == 35 || y == 43) pixel_data = (level_index != 0) ? 16'hffe0 : 16'h2945;
                        else pixel_data = (level_index != 0) ? 16'h07e0 : 16'h18e5;
                    end
                end
            end

            // Bottom Centered [ BACK ] Button (x: 28..68, y: 52..62)
            if (x >= 28 && x <= 68 && y >= 52 && y <= 62) begin
                if (x == 28 || x == 68 || y == 52 || y == 62)
                    pixel_data = (cursor_x >= 28 && cursor_x <= 68 && cursor_y >= 52 && cursor_y <= 62) ? 16'hffe0 : 16'h04b4;
                else if (cursor_x >= 28 && cursor_x <= 68 && cursor_y >= 52 && cursor_y <= 62)
                    pixel_data = 16'h0432;
                else
                    pixel_data = 16'h18e5;
                if (is_back_arrow(7'd48, 6'd57, x, y)) pixel_data = 16'hffff;
            end

            // Bottom Right [ HOME ] Button (x: 70..95, y: 52..62)
            if (x >= 70 && x <= 95 && y >= 52 && y <= 62) begin
                if (x == 70 || x == 95 || y == 52 || y == 62)
                    pixel_data = (cursor_x >= 70 && cursor_x <= 95 && cursor_y >= 52 && cursor_y <= 62) ? 16'hffe0 : 16'h04b4;
                else if (cursor_x >= 70 && cursor_x <= 95 && cursor_y >= 52 && cursor_y <= 62)
                    pixel_data = 16'h0432;
                else
                    pixel_data = 16'h18e5;
                if (is_home_icon(7'd82, 6'd57, x, y)) pixel_data = 16'hffff;
            end

        end else if (game_state == `LP_GUIDE) begin
            // -----------------------------------------------------------------
            // GUIDE / DIARY SCREEN (100% Visual 3-Tab Field Manual + Sound Settings)
            // -----------------------------------------------------------------
            pixel_data = (y < 10) ? 16'h18e5 : ((y == 10) ? 16'h04b4 : 16'h0841);
            example_draw = 1'b0;
            example_has_frame = 1'b0;
            example_local_x = 4'd0;
            example_local_y = 4'd0;
            example_part = `LP_PART_EMPTY;
            case (diary_page)
                0: begin
                    // Tab 1: Visual Mounting Rules ([Pig in Frame][Eng in Frame][Wheel] -> [OK] vs [Loose Pig] -> [X])
                    //        & 3 Visual Star Goal Cards ([★ + Flag], [★ + Crate], [★ + 20S])
                    if (text_on("RULES       1/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;

                    // Top Half (y: 13..24): Visual Mounting Diagram using shared 12x12 part sprites
                    if (y >= 13 && y < 25) begin
                        example_local_y = y - 6'd13;
                        if (x >= 4 && x < 16) begin
                            example_draw = 1'b1; example_has_frame = 1'b1; example_part = `LP_PART_PIG;
                            example_local_x = x - 7'd4;
                        end else if (x >= 18 && x < 30) begin
                            example_draw = 1'b1; example_has_frame = 1'b1; example_part = `LP_PART_ENGINE;
                            example_local_x = x - 7'd18;
                        end else if (x >= 32 && x < 44) begin
                            example_draw = 1'b1; example_has_frame = 1'b0; example_part = `LP_PART_WHEEL;
                            example_local_x = x - 7'd32;
                        end else if (x >= 64 && x < 76) begin
                            example_draw = 1'b1; example_has_frame = 1'b0; example_part = `LP_PART_PIG;
                            example_local_x = x - 7'd64;
                        end
                    end
                    // Green Checkmark Badge (x: 46..56, y: 14..23)
                    if (x >= 46 && x <= 56 && y >= 14 && y <= 23) begin
                        pixel_data = (x == 46 || x == 56 || y == 14 || y == 23) ? 16'h07e0 : 16'h0280;
                        if (is_checkmark_icon(7'd51, 6'd19, x, y)) pixel_data = 16'hffff;
                    end
                    // Vertical separator (x = 60) & Horizontal separator (y = 28)
                    if (x == 60 && y >= 13 && y <= 25) pixel_data = 16'h04b4;
                    if (y == 28 && x >= 4 && x <= 91)  pixel_data = 16'h04b4;
                    // Red Cross Badge (x: 78..88, y: 14..23) next to unframed Pig
                    if (x >= 78 && x <= 88 && y >= 14 && y <= 23) begin
                        pixel_data = (x == 78 || x == 88 || y == 14 || y == 23) ? 16'hf800 : 16'h3800;
                        if (x >= 80 && x <= 86 && y >= 16 && y <= 21 &&
                            ((x - 7'd83 == y - 6'd19) || (x - 7'd83 == 6'd19 - y)))
                            pixel_data = 16'hffff;
                    end

                    // Bottom Half (y: 31..48): 3 Side-by-Side Visual Star Cards
                    if (y >= 31 && y <= 48) begin
                        // Card 1 (x: 4..30), Card 2 (x: 35..61), Card 3 (x: 66..92)
                        if ((x >= 4 && x <= 30) || (x >= 35 && x <= 61) || (x >= 66 && x <= 92)) begin
                            if (y == 31 || y == 48 || x == 4 || x == 30 || x == 35 || x == 61 || x == 66 || x == 92)
                                pixel_data = 16'h04b4;
                            else
                                pixel_data = 16'h1082;
                        end
                        // Gold Star Icon in each card (centers: x = 10, 41, 71 at y = 40)
                        if (((x >= 7 && x <= 13) && ((x > 10 ? x - 10 : 10 - x) + (y > 40 ? y - 40 : 40 - y) <= 3)) ||
                            ((x >= 38 && x <= 44) && ((x > 41 ? x - 41 : 41 - x) + (y > 40 ? y - 40 : 40 - y) <= 3)) ||
                            ((x >= 68 && x <= 74) && ((x > 71 ? x - 71 : 71 - x) + (y > 40 ? y - 40 : 40 - y) <= 3)))
                            pixel_data = 16'hffe0;
                        // Card 1 Icon: Checkered Finish Flag (x: 17..26, y: 34..45)
                        if (x == 17 && y >= 34 && y <= 45) pixel_data = 16'hffff;
                        else if (x >= 18 && x <= 26 && y >= 34 && y <= 40)
                            pixel_data = (((x >> 1) + (y >> 1)) & 1'b1) ? 16'hffff : 16'hf800;
                        // Card 2 Icon: Wooden Star Crate (x: 47..57, y: 34..44)
                        if (x >= 47 && x <= 57 && y >= 34 && y <= 44) begin
                            if (x == 47 || x == 57 || y == 34 || y == 44) pixel_data = 16'hc4a3;
                            else if ((x > 52 ? x - 52 : 52 - x) + (y > 39 ? y - 39 : 39 - y) <= 2) pixel_data = 16'hffe0;
                            else pixel_data = 16'h7261;
                        end
                        // Card 3 Icon: "20S" Time Target (x: 75..91, y: 37..43)
                        if (text_on("20S             ", 74, 36, x, y)) pixel_data = 16'h07ff;
                    end
                end
                1: begin
                    // Tab 2: Visual Hardware Controls (Pixel-Art Mouse + 2x2 Switch Cards)
                    if (text_on("CONTROLS    2/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;

                    // Left Card (x: 4..35, y: 12..49): Graphical PS/2 Mouse Diagram
                    if (x >= 4 && x <= 35 && y >= 12 && y <= 49) begin
                        if (x == 4 || x == 35 || y == 12 || y == 49) pixel_data = 16'h04b4;
                        else pixel_data = 16'h1082;
                        // Mouse cord (x = 19..20, y = 13..15)
                        if ((x == 19 || x == 20) && y >= 13 && y <= 15) pixel_data = 16'h7bef;
                        // Mouse body (x: 12..27, y: 16..37)
                        if (x >= 12 && x <= 27 && y >= 16 && y <= 37 &&
                            !((x == 12 || x == 27) && (y == 16 || y == 37))) begin
                            if (x == 12 || x == 27 || y == 16 || y == 37 || y == 25)
                                pixel_data = 16'hffff; // Outer shell & button seam
                            else if (y < 25) begin
                                if (x >= 19 && x <= 20) pixel_data = (y >= 18 && y <= 23) ? 16'h07ff : 16'h4208; // Cyan scroll wheel
                                else if (x < 19)        pixel_data = 16'h07e0; // Green Left-Click (Drag / Toggle)
                                else                    pixel_data = 16'hf800; // Red Right-Click (Delete)
                            end else begin
                                pixel_data = 16'hd69a; // Silver palm rest
                            end
                        end
                        // Mini visual legend below mouse: Green ✓ (left) and Red ✗ (right)
                        if (is_checkmark_icon(7'd13, 6'd43, x, y)) pixel_data = 16'h07e0;
                        if (x >= 23 && x <= 27 && y >= 41 && y <= 45 &&
                            ((x - 7'd25 == y - 6'd43) || (x - 7'd25 == 6'd43 - y)))
                            pixel_data = 16'hf800;
                    end

                    // Right 2x2 Switch Cards: (x: 39..64 and 67..92, y: 12..29 and 32..49)
                    if (((x >= 39 && x <= 64) || (x >= 67 && x <= 92)) &&
                        ((y >= 12 && y <= 29) || (y >= 32 && y <= 49))) begin
                        if (x == 39 || x == 64 || x == 67 || x == 92 || y == 12 || y == 29 || y == 32 || y == 49)
                            pixel_data = 16'h04b4;
                        else
                            pixel_data = 16'h1082;
                    end
                    // Switch numbers: 15 (Mute), 14 (Rev), 13 (Zoom), 12 (Cam)
                    if (text_on("15              ", 41, 17, x, y)) pixel_data = 16'hffff;
                    if (text_on("14              ", 69, 17, x, y)) pixel_data = 16'hffff;
                    if (text_on("13              ", 41, 37, x, y)) pixel_data = 16'hffff;
                    if (text_on("12              ", 69, 37, x, y)) pixel_data = 16'hffff;
                    // Switch 15 Icon: Gold Speaker (x: 54..61, y: 16..24)
                    if ((x >= 54 && x <= 55 && y >= 19 && y <= 21) ||
                        (x == 56 && y >= 18 && y <= 22) ||
                        (x == 57 && y >= 17 && y <= 23) ||
                        (x == 59 && (y == 18 || y == 20 || y == 22)) ||
                        (x == 61 && (y == 17 || y == 23)))
                        pixel_data = 16'hffe0;
                    // Switch 14 Icon: Cyan Reverse Arrows <-> (x: 81..90, y: 18..22)
                    if ((y == 20 && x >= 81 && x <= 90) ||
                        ((x == 82 || x == 89) && (y == 19 || y == 21)) ||
                        ((x == 83 || x == 88) && (y == 18 || y == 22)))
                        pixel_data = 16'h07ff;
                    // Switch 13 Icon: Green Magnifier / Zoom (x: 54..61, y: 36..43)
                    if ((x >= 55 && x <= 57 && (y == 36 || y == 40)) ||
                        (y >= 37 && y <= 39 && (x == 54 || x == 58)) ||
                        (x == 59 && y == 41) || (x == 60 && y == 42) || (x == 61 && y == 43))
                        pixel_data = 16'h07e0;
                    // Switch 12 Icon: Yellow Camera / Viewfinder (x: 82..90, y: 37..43)
                    if ((x >= 82 && x <= 90 && (y == 38 || y == 43)) ||
                        (y >= 38 && y <= 43 && (x == 82 || x == 90)) ||
                        (x >= 84 && x <= 88 && y == 37) ||
                        (x >= 85 && x <= 87 && y >= 39 && y <= 42))
                        pixel_data = 16'hffe0;
                end
                2: begin
                    // Tab 3: Context-Aware 3x3 Vehicle Blueprint (Left) + 3 Visual Pictogram Steps (Right)
                    if (level_index == 0) begin
                        if (text_on("MAP 1 PLAN  3/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;
                    end else begin
                        if (text_on("MAP 2 PLAN  3/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;
                    end
                    // Step numbers 1, 2, 3 on right panel (x = 44)
                    if (text_on("1               ", 44, 15, x, y)) pixel_data = 16'hffff;
                    if (text_on("2               ", 44, 27, x, y)) pixel_data = 16'hffe0;
                    if (text_on("3               ", 44, 39, x, y)) pixel_data = 16'h07e0;

                    // Left 36x36 Blueprint Grid (x: 4..39, y: 12..47)
                    if (x >= 4 && x < 40 && y >= 12 && y < 48) begin
                        if (x < 16) begin example_col = 0; example_local_x = x - 4; end
                        else if (x < 28) begin example_col = 1; example_local_x = x - 16; end
                        else begin example_col = 2; example_local_x = x - 28; end
                        if (y < 24) begin example_row = 0; example_local_y = y - 12; end
                        else if (y < 36) begin example_row = 1; example_local_y = y - 24; end
                        else begin example_row = 2; example_local_y = y - 36; end
                        example_draw = 1'b1;
                        example_has_frame = (example_row == 1);
                        if (level_index == 0) begin
                            if (example_row == 1 && example_col == 0) example_part = `LP_PART_ENGINE;
                            else if (example_row == 1 && example_col == 1) example_part = `LP_PART_PIG;
                            else if (example_row == 1 && example_col == 2) example_part = `LP_PART_BOOSTER;
                            else if (example_row == 2 && (example_col == 0 || example_col == 2)) example_part = `LP_PART_WHEEL;
                            else example_part = `LP_PART_EMPTY;
                        end else begin
                            if (example_row == 0 && (example_col == 0 || example_col == 2)) example_part = `LP_PART_BALLOON;
                            else if (example_row == 1 && example_col == 0) example_part = `LP_PART_FAN;
                            else if (example_row == 1 && example_col == 1) example_part = `LP_PART_PIG;
                            else if (example_row == 1 && example_col == 2) example_part = `LP_PART_BOOSTER;
                            else if (example_row == 2 && (example_col == 0 || example_col == 2)) example_part = `LP_PART_WHEEL;
                            else if (example_row == 2 && example_col == 1) example_part = `LP_PART_ENGINE;
                            else example_part = `LP_PART_EMPTY;
                        end
                    end
                    // Right Step Part Icons (x: 52..63, y: 12..47) sharing the same part_sprite12!
                    else if (x >= 52 && x < 64 && y >= 12 && y < 48) begin
                        example_draw = 1'b1;
                        example_local_x = x - 7'd52;
                        if (y < 24) begin
                            example_row = 0; example_local_y = y - 6'd12;
                            example_part = (level_index == 0) ? `LP_PART_ENGINE : `LP_PART_BALLOON;
                        end else if (y < 36) begin
                            example_row = 1; example_local_y = y - 6'd24;
                            example_part = (level_index == 0) ? `LP_PART_BOOSTER : `LP_PART_BALLOON;
                        end else begin
                            example_row = 2; example_local_y = y - 6'd36;
                            example_part = (level_index == 0) ? `LP_PART_WHEEL : `LP_PART_BOOSTER;
                        end
                    end

                    // Right Action Pictograms (x: 68..90)
                    // Step 1 Action (y: 14..22): Drive Right Arrow (Map 1) or Float Up Arrow (Map 2)
                    if (level_index == 0) begin
                        if ((y == 18 && x >= 70 && x <= 84) ||
                            ((x == 82 || x == 83) && (y >= 16 && y <= 20)) ||
                            (x == 81 && (y == 15 || y == 21)))
                            pixel_data = 16'h07e0;
                    end else begin
                        if ((x == 77 && y >= 14 && y <= 22) ||
                            (y == 15 && x >= 75 && x <= 79) ||
                            (y == 16 && (x == 74 || x == 80)))
                            pixel_data = 16'h07ff;
                    end
                    // Step 2 Action (y: 26..34): Boost Up-Right (Map 1) or Pop Red X + Drop (Map 2)
                    if (level_index == 0) begin
                        if ((x >= 72 && x <= 82 && (x - 7'd72 == 6'd34 - y || x - 7'd73 == 6'd34 - y)) ||
                            (x >= 79 && x <= 83 && y == 25) || (x == 83 && y >= 25 && y <= 29))
                            pixel_data = 16'hffe0;
                    end else begin
                        if ((x == 77 && y >= 26 && y <= 34) ||
                            (y == 33 && x >= 75 && x <= 79) ||
                            (y == 32 && (x == 74 || x == 80)))
                            pixel_data = 16'hf800;
                    end
                    // Step 3 Action (y: 37..46): Checkered Finish Flag Icon (x: 73..84)
                    if (x == 73 && y >= 37 && y <= 46) pixel_data = 16'hffff;
                    else if (x >= 74 && x <= 83 && y >= 37 && y <= 42)
                        pixel_data = (((x >> 1) + (y >> 1)) & 1'b1) ? 16'hffff : 16'hf800;
                end
                default: begin
                    // Sound Settings Page (diary_page == 3)
                    if (text_on("SOUND SETTINGS  ", 6, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("MASTER VOLUME   ", 6, 13, x, y)) pixel_data = 16'hffff;

                    // Button [-]: x: 8..28, y: 24..37
                    if (x >= 8 && x <= 28 && y >= 24 && y <= 37) begin
                        if (x == 8 || x == 28 || y == 24 || y == 37)
                            pixel_data = (cursor_x >= 8 && cursor_x <= 28 && cursor_y >= 24 && cursor_y <= 37) ? 16'hffe0 : 16'h04b4;
                        else if (cursor_x >= 8 && cursor_x <= 28 && cursor_y >= 24 && cursor_y <= 37) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end
                    if (text_on(" -              ", 12, 28, x, y)) pixel_data = 16'hffff;

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
                    if (text_on(" +              ", 68, 28, x, y)) pixel_data = 16'hffff;

                    // Switch 15 (Mute) Status Banner: only show when muted
                    if (audio_muted) begin
                        if (text_on("MUTED BY SW15   ", 10, 43, x, y)) pixel_data = 16'hf800; // Red
                    end
                end
            endcase

            // Shared single part_sprite12 evaluator for Tab 1 (Mounting Rules) & Tab 3 (Blueprint + Step Icons)
            if (example_draw) begin
                pixel_data = 16'h0841;
                if (example_local_x == 0 || example_local_y == 0 ||
                    example_local_x == 11 || example_local_y == 11) begin
                    if (diary_page == 0 && x >= 64)
                        pixel_data = 16'hf800; // Red border around unframed Pig
                    else if (diary_page == 2 && x < 40 && example_row == 0 && level_index == 0)
                        pixel_data = 16'h2945;
                    else
                        pixel_data = 16'h7bef;
                end
                if (example_has_frame)
                    pixel_data = part_sprite12(`LP_PART_FRAME, example_local_x, example_local_y, 1'b0, pixel_data);
                if (example_part != `LP_PART_EMPTY)
                    pixel_data = part_sprite12(example_part, example_local_x, example_local_y, 1'b0, pixel_data);
                // Red pop 'X' over Step 2 Balloon on Map 2
                if (diary_page == 2 && level_index != 0 && x >= 52 && example_row == 1 &&
                    example_local_x >= 2 && example_local_x <= 9 &&
                    (example_local_x == example_local_y || example_local_x + example_local_y == 11))
                    pixel_data = 16'hf800;
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
                    if (is_back_arrow(7'd14, 6'd58, x, y)) pixel_data = 16'hffff;
                end else if (diary_page != 3 && y >= 55) begin
                    if (x >= 32 && x <= 51) begin
                        if (x == 32 || x == 51 || y == 55 || y == 63)
                            pixel_data = ((diary_page == 0) || (cursor_x >= 32 && cursor_x <= 51 && cursor_y >= 55)) ? 16'hffe0 : 16'h04b4;
                        else if (cursor_x >= 32 && cursor_x <= 51 && cursor_y >= 55)
                            pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("1               ", 40, 56, x, y)) pixel_data = (diary_page == 0) ? 16'hffe0 : 16'hffff;
                    end else if (x >= 53 && x <= 72) begin
                        if (x == 53 || x == 72 || y == 55 || y == 63)
                            pixel_data = ((diary_page == 1) || (cursor_x >= 53 && cursor_x <= 72 && cursor_y >= 55)) ? 16'hffe0 : 16'h04b4;
                        else if (cursor_x >= 53 && cursor_x <= 72 && cursor_y >= 55)
                            pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("2               ", 61, 56, x, y)) pixel_data = (diary_page == 1) ? 16'hffe0 : 16'hffff;
                    end else if (x >= 74 && x <= 93) begin
                        if (x == 74 || x == 93 || y == 55 || y == 63)
                            pixel_data = ((diary_page == 2) || (cursor_x >= 74 && cursor_x <= 93 && cursor_y >= 55)) ? 16'hffe0 : 16'h04b4;
                        else if (cursor_x >= 74 && cursor_x <= 93 && cursor_y >= 55)
                            pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("3               ", 82, 56, x, y)) pixel_data = (diary_page == 2) ? 16'hffe0 : 16'hffff;
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
                        pixel_data = draw_diary_icon(7'd71, 6'd59, x, y, pixel_data);
                    end
                end
                // Settings Gear Icon (x: 80..95)
                else if (x >= 80 && x < 96) begin
                    if (x == 80 || x == 95 || y == 55 || y == 63)
                        pixel_data = (cursor_x >= 80 && cursor_y >= 55) ? 16'hffe0 : 16'h04b4;
                    else begin
                        pixel_data = (cursor_x >= 80 && cursor_y >= 55) ? 16'h0351 : 16'h18e5;
                        pixel_data = cartoon_gear(7'd87, 6'd59, x, y, pixel_data);
                    end
                end
            end
        end else if (game_state == `LP_RUN) begin
            // -----------------------------------------------------------------
            // RUN SCREEN: Big 16x16 Interactive Grid, Clean Layout
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;

            // 1. Left Panel (x: 0..23, y: 0..50): Clean background
            if (x < 24 && y <= 50) begin
                pixel_data = 16'h0841;
            end

            // 2. Middle Panel (x: 24..71, y: 2..49): Big 16x16 Interactive Vehicle Grid
            // Rendered by left_renderer and passed through base_pixel to share a single 16x16 sprite ROM.
            if (x >= 24 && x <= 71 && y >= 2 && y <= 49) begin
                pixel_data = base_pixel;
            end

            // 3. Right Panel (x: 72..95, y: 0..50): Clean background (Timer removed from OLED!)
            if (x >= 72 && y <= 50) begin
                pixel_data = 16'h0841;
            end

            // 4. Bottom Action Bar (y: 53..63): [ TRY ] | [ END ] | [ EDIT ] | [ GEAR ]
            if (y >= 53) begin
                // Button 1: [ TRY ] (x: 2..22)
                if (x >= 2 && x <= 22) begin
                    if (x == 2 || x == 22 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (is_retry_icon(7'd12, 6'd58, x, y)) pixel_data = 16'hffff;
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
                    pixel_data = cartoon_wrench(7'd60, 6'd58, x, y, pixel_data);
                end

                // Button 4: [ GEAR ] (x: 74..94)
                else if (x >= 74 && x <= 94) begin
                    if (x == 74 || x == 94 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    pixel_data = cartoon_gear(7'd84, 6'd58, x, y, pixel_data);
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
                        pixel_data = (cursor_x >= 56 && cursor_x <= 92 && cursor_y >= 6 && cursor_y <= 26) ? 16'hffe0 : ((game_state == `LP_SUCCESS) ? 16'h07e0 : 16'h04b4);
                    else if (cursor_x >= 56 && cursor_x <= 92 && cursor_y >= 6 && cursor_y <= 26)
                        pixel_data = 16'h0351;
                    else
                        pixel_data = 16'h18e5;
                    if (game_state == `LP_SUCCESS) begin
                        if (is_play_icon(7'd74, 6'd16, x, y)) pixel_data = 16'h07e0; // Bright green play triangle
                    end else begin
                        pixel_data = cartoon_wrench(7'd74, 6'd16, x, y, pixel_data);
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
                    if (is_retry_icon(7'd74, 6'd40, x, y)) pixel_data = 16'hffff;
                end
            end
            if (y >= 53) begin
                pixel_data = 16'h0841;
                // Button 1: [ HOME ] (x: 2..28, center 15, 58)
                if (x >= 2 && x <= 28) begin
                    if (x == 2 || x == 28 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 2 && cursor_x <= 28 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 2 && cursor_x <= 28 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (is_home_icon(7'd15, 6'd58, x, y)) pixel_data = 16'hffff;
                end
                // Button 2: [ MAP SELECT ] (x: 35..61, center 48, 58)
                else if (x >= 35 && x <= 61) begin
                    if (x == 35 || x == 61 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 35 && cursor_x <= 61 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 35 && cursor_x <= 61 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    pixel_data = draw_map_icon(7'd48, 6'd58, x, y, pixel_data);
                end
                // Button 3: [ GUIDE ] (x: 68..94, center 81, 58)
                else if (x >= 68 && x <= 94) begin
                    if (x == 68 || x == 94 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 68 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 68 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    pixel_data = draw_diary_icon(7'd81, 6'd58, x, y, pixel_data);
                end
            end
        end

        // Mouse pointer overlay (topmost layer)
        if ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
            (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))
            pixel_data = 16'hffff;
    end
endmodule
