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

    integer example_local_x, example_local_y, example_row, example_col;

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

    // Helper function to draw cartoon settings gear matching reference artwork
    function [15:0] cartoon_gear;
        input signed [6:0] center_x, center_y, px, py;
        input [15:0] bg;
        reg signed [6:0] dx, dy;
        reg [7:0] r2;
        reg is_tooth, is_body, is_border, is_hub, is_hole, is_sparkle;
        begin
            dx = px - center_x;
            dy = py - center_y;
            r2 = dx*dx + dy*dy;

            // 6 outer teeth (top, bottom, and 4 corners)
            is_tooth = ((dx >= -1 && dx <= 1 && (dy <= -5 && dy >= -7 || dy >= 5 && dy <= 7)) ||
                        ((dx >= 4 && dx <= 6 || dx <= -4 && dx >= -6) &&
                         (dy >= 3 && dy <= 5 || dy <= -3 && dy >= -5)));
            is_body = (r2 <= 25);
            is_hub = (r2 <= 4);
            is_hole = (r2 <= 1);
            is_border = (!is_hub && !is_hole && ((r2 >= 20 && r2 <= 25) || (is_tooth && (r2 >= 36 || dx == -1 || dx == 1 || dx == 4 || dx == 6 || dx == -4 || dx == -6))));
            is_sparkle = ((dx == -2 && dy == -3) || (dx == 3 && dy == 2));

            if (!is_body && !is_tooth) cartoon_gear = bg;
            else if (is_sparkle) cartoon_gear = 16'hffff; // White glint
            else if (is_hole) cartoon_gear = 16'h6210; // Purple center hole
            else if (is_hub) cartoon_gear = 16'hfed0; // Golden yellow hub
            else if (is_border) cartoon_gear = 16'h6210; // Dark purple border
            else if (r2 >= 9 && r2 <= 15) cartoon_gear = 16'h8a95; // Accent ring
            else cartoon_gear = 16'hbdf7; // Soft lavender body
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
        reg signed [4:0] lx, ly;
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
        reg signed [4:0] lx, ly;
        begin
            lx = px - cx;
            ly = py - cy;
            // Clean, uncluttered circular refresh arrow
            is_retry_icon = (ly == -3 && lx >= -1 && lx <= 1) ||
                            (lx == -3 && ly >= -1 && ly <= 1) ||
                            (ly == 3  && lx >= -1 && lx <= 1) ||
                            (lx == 3  && ly >= 0  && ly <= 1) ||
                            ((lx == -2 || lx == 2) && (ly == -2 || ly == 2) && !(lx == 2 && ly == -2)) ||
                            (lx == 2 && ly == -3) ||
                            (lx == 1 && (ly == -4 || ly == -2));
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

    function [15:0] cartoon_pencil;
        input signed [6:0] cx, cy, px, py;
        input [15:0] bg;
        reg signed [4:0] lx, ly;
        begin
            lx = px - cx;
            ly = py - cy;
            // 45-degree angled pencil: graphite tip at (-3, 3), pink eraser at (3, -3)
            if (lx == -3 && ly == 3)
                cartoon_pencil = 16'h0000; // Graphite lead tip
            else if ((lx == -2 && ly == 2) || (lx == -3 && ly == 2) || (lx == -2 && ly == 3))
                cartoon_pencil = 16'hfdf0; // Wood sharpened collar
            else if ((lx == -1 && (ly == 0 || ly == 1)) ||
                     (lx == 0  && (ly == -1 || ly == 0 || ly == 1)) ||
                     (lx == 1  && (ly == -2 || ly == -1 || ly == 0)) ||
                     (lx == 2  && (ly == -2 || ly == -1)))
                cartoon_pencil = 16'hffe0; // Yellow pencil shaft
            else if ((lx == 2 && ly == -3) || (lx == 3 && ly == -2))
                cartoon_pencil = 16'hc618; // Silver ferrule band
            else if (lx == 3 && ly == -3)
                cartoon_pencil = 16'hfcee; // Pink eraser
            else
                cartoon_pencil = bg;
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

    // Run grid coordinates: 16x16 cells using shifts and masks (Rule 2: zero division/modulo)
    wire [1:0] run_col = (x - 7'd24) >> 4;
    wire [1:0] run_row = (y - 6'd2) >> 4;
    wire [3:0] run_cell_index = ((run_row << 1) + run_row) + run_col;
    wire [3:0] run_cell_x = (x - 7'd24) & 4'd15;
    wire [3:0] run_cell_y = (y - 6'd2) & 4'd15;
    wire run_cell_hovered = (cursor_x >= 7'd24 && cursor_x <= 7'd71 &&
                             cursor_y >= 6'd2 && cursor_y <= 6'd49 &&
                             run_col == ((cursor_x - 7'd24) >> 4) &&
                             run_row == ((cursor_y - 6'd2) >> 4));
    reg [2:0] run_part;
    reg [15:0] run_spr;
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

            // 4. Cartoon Settings Gear in Bottom-Left (Center at 12, 54)
            if (x >= 4 && x <= 20 && y >= 46 && y <= 62) begin
                pixel_data = cartoon_gear(7'd12, 6'd54, x, y, pixel_data);
                if (cursor_x >= 4 && cursor_x <= 20 && cursor_y >= 46 && cursor_y <= 62 && pixel_data == 16'hbdf7)
                    pixel_data = 16'hffe0; // Bright gold hover highlight on gear body
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

                // Folded Parchment Map Icon centered at x=69 (x: 62..76, y: 16..29)
                if (x >= 62 && x <= 76 && y >= 16 && y <= 29) begin
                    if (y == 16 || y == 29 || x == 62 || x == 76) pixel_data = 16'h8a22;
                    else if (x == 66 || x == 72) pixel_data = 16'hb530;
                    else if ((x == 64 && y == 25) || (x == 65 && y == 24) || (x == 68 && y == 20) || (x == 69 && y == 21) || (x == 74 && y == 18)) pixel_data = 16'hf800;
                    else if (x == 73 && y == 26) pixel_data = 16'hfed0;
                    else pixel_data = 16'hffdf;
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
            // GUIDE / DIARY SCREEN
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;
            case (diary_page)
                0: begin
                    if (text_on("CONTROLS    1/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("L-DRAG: PLACE   ", 4, 12, x, y)) pixel_data = 16'hffff;
                    if (text_on("R-CLK:  DELETE  ", 4, 22, x, y)) pixel_data = 16'hffe0;
                    if (text_on("SW0:    MOTOR   ", 4, 32, x, y)) pixel_data = 16'h07e0;
                    if (text_on("SW2:    REVERSE ", 4, 42, x, y)) pixel_data = 16'h07ff;
                end
                1: begin
                    if (text_on("BLUEPRINT   2/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("CART            ", 44, 12, x, y)) pixel_data = 16'h07e0;
                    if (text_on("TOP: -          ", 44, 21, x, y)) pixel_data = 16'h7bef;
                    if (text_on("ENG+PIG         ", 44, 29, x, y)) pixel_data = 16'hffff;
                    if (text_on("2 WHEELS        ", 44, 37, x, y)) pixel_data = 16'hffe0;
                    if (text_on("SW0 ON          ", 44, 45, x, y)) pixel_data = 16'h07e0;
                    if (x >= 4 && x < 40 && y >= 12 && y < 48) begin
                        if (x < 16) begin example_col = 0; example_local_x = x - 4; end
                        else if (x < 28) begin example_col = 1; example_local_x = x - 16; end
                        else begin example_col = 2; example_local_x = x - 28; end
                        if (y < 24) begin example_row = 0; example_local_y = y - 12; end
                        else if (y < 36) begin example_row = 1; example_local_y = y - 24; end
                        else begin example_row = 2; example_local_y = y - 36; end
                        pixel_data = 16'h0841;
                        if (example_local_x == 0 || example_local_y == 0 ||
                            example_local_x == 11 || example_local_y == 11) pixel_data = (example_row == 0) ? 16'h2945 : 16'h7bef;
                        if (example_row == 1)
                            pixel_data = part_sprite12(`LP_PART_FRAME, example_local_x, example_local_y, 1'b0, pixel_data);
                        if (example_row == 1 && example_col == 0)
                            pixel_data = part_sprite12(`LP_PART_ENGINE, example_local_x, example_local_y, 1'b0, pixel_data);
                        if (example_row == 1 && example_col == 1)
                            pixel_data = part_sprite12(`LP_PART_PIG, example_local_x, example_local_y, 1'b0, pixel_data);
                        if (example_row == 2 && (example_col == 0 || example_col == 2))
                            pixel_data = part_sprite12(`LP_PART_WHEEL, example_local_x, example_local_y, 1'b0, pixel_data);
                    end
                end
                2: begin
                    if (text_on("PARTS TIPS 3/3  ", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (x >= 4 && x < 12 && y >= 11 && y < 19)
                        pixel_data = part_sprite(`LP_PART_PIG, x - 4, y - 11, 1'b0, pixel_data);
                    if (text_on("KEEP PIG SAFE   ", 16, 12, x, y)) pixel_data = 16'hffff;

                    if (x >= 4 && x < 12 && y >= 21 && y < 29)
                        pixel_data = tnt_sprite(x - 4, y - 21, pixel_data);
                    if (text_on("AVOID TNT       ", 16, 22, x, y)) pixel_data = 16'hf800;

                    if (x >= 4 && x < 12 && y >= 31 && y < 39)
                        pixel_data = part_sprite(`LP_PART_ENGINE, x - 4, y - 31, 1'b0, pixel_data);
                    if (text_on("MOTOR DRIVE     ", 16, 32, x, y)) pixel_data = 16'h07e0;

                    if (x >= 4 && x < 12 && y >= 41 && y < 49)
                        pixel_data = part_sprite(`LP_PART_WHEEL, x - 4, y - 41, 1'b0, pixel_data);
                    if (text_on("GROUND GRIP     ", 16, 42, x, y)) pixel_data = 16'hffe0;
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

                    // Switch 1 (Mute) Status Banner: only show when muted
                    if (audio_muted) begin
                        if (text_on("MUTED BY SW1    ", 10, 43, x, y)) pixel_data = 16'hf800; // Red
                    end
                end
            endcase

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
                // Inventory Page 1 / 2 Buttons
                else if (x >= 20 && x <= 40) begin
                    if (x == 20 || x == 40 || y == 55 || y == 63)
                        pixel_data = (cursor_x >= 20 && cursor_x <= 40 && cursor_y >= 55) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 20 && cursor_x <= 40 && cursor_y >= 55)
                        pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (text_on("1               ", 28, 56, x, y)) pixel_data = (inventory_page == 0) ? 16'hffe0 : 16'hffff;
                end
                else if (x >= 41 && x < 62) begin
                    if (x == 41 || x == 61 || y == 55 || y == 63)
                        pixel_data = (cursor_x >= 41 && cursor_x < 62 && cursor_y >= 55) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 41 && cursor_x < 62 && cursor_y >= 55)
                        pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (text_on("2               ", 49, 56, x, y)) pixel_data = (inventory_page == 1) ? 16'hffe0 : 16'hffff;
                end
                // Open Book Diary Icon (x: 64..79)
                else if (x >= 64 && x < 80) begin
                    if (x == 64 || x == 79 || y == 55 || y == 63)
                        pixel_data = (cursor_x >= 64 && cursor_x < 80 && cursor_y >= 55) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 64 && cursor_x < 80 && cursor_y >= 55)
                        pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    // Realistic open book with spine at x=71 and white pages
                    if (x >= 66 && x <= 76 && y >= 56 && y <= 62) begin
                        if (x == 71) pixel_data = 16'h8a22; // Brown spine
                        else if (y == 56 || y == 62 || x == 66 || x == 76) pixel_data = 16'h8a22; // Cover
                        else if (y == 58 || y == 60) pixel_data = 16'h0010; // Page text lines
                        else pixel_data = 16'hffff; // White pages
                    end
                end
                // Settings Gear Icon (x: 80..95)
                else if (x >= 80 && x < 96) begin
                    if (x == 80 || x == 95 || y == 55 || y == 63)
                        pixel_data = (cursor_x >= 80 && cursor_y >= 55) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 80 && cursor_y >= 55)
                        pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    pixel_data = cartoon_gear(7'd87, 6'd59, x, y, pixel_data);
                end
            end
        end else if (game_state == `LP_RUN) begin
            // -----------------------------------------------------------------
            // RUN SCREEN: Big 16x16 Interactive Grid, SW0 Engine Banner, Clean Layout
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;

            // 1. Left Panel (x: 0..23, y: 0..50): Engine SW0 Status Banner
            if (x < 24 && y <= 50) begin
                if (engine_available && !sw0_engine) begin
                    // Warning Box: Engine OFF by SW0
                    if (x >= 1 && x <= 22 && y >= 10 && y <= 42) begin
                        if (x == 1 || x == 22 || y == 10 || y == 42) pixel_data = 16'hf800;
                        else pixel_data = 16'h3000;
                    end
                    if (text_on("ENG             ", 3, 13, x, y)) pixel_data = 16'hf800;
                    if (text_on("OFF             ", 3, 23, x, y)) pixel_data = 16'hffe0;
                    if (text_on("SW0             ", 3, 33, x, y)) pixel_data = 16'hffff;
                end else begin
                    pixel_data = 16'h0841;
                end
            end

            // 2. Middle Panel (x: 24..71, y: 2..49): Big 16x16 Interactive Vehicle Grid
            if (x >= 24 && x <= 71 && y >= 2 && y <= 49) begin
                run_part = build_grid >> (run_cell_index * 3);

                // Grid cell borders (glows bright green when an intact actuator in this cell is active, or bright gold when hovered)
                if (run_cell_x == 0 || run_cell_y == 0 || run_cell_x == 15 || run_cell_y == 15 || x == 71 || y == 49) begin
                    if (intact_mask[run_cell_index] &&
                        ((run_part == `LP_PART_ENGINE && engine_enabled && sw0_engine) ||
                         (run_part == `LP_PART_FAN && (fan_on || active_fans[run_cell_index])) ||
                         (run_part == `LP_PART_BOOSTER && boost_active)))
                        pixel_data = 16'h07e0;
                    else if (run_cell_hovered)
                        pixel_data = 16'hffe0;
                    else
                        pixel_data = 16'h4208;
                end else begin
                    if (run_cell_hovered)
                        pixel_data = 16'h0351;

                    // Damage cross under destroyed elements: only if cell had a part or frame
                    if ((!intact_mask[run_cell_index] && run_part != `LP_PART_EMPTY) ||
                        (!frame_intact_mask[run_cell_index] && build_frames[run_cell_index])) begin
                        if ((run_cell_x >= 3 && run_cell_x <= 12) &&
                            (run_cell_x == run_cell_y || run_cell_x + run_cell_y == 15))
                            pixel_data = 16'h8000;
                    end

                    // Wood frame layer
                    if (frame_intact_mask[run_cell_index]) begin
                        pixel_data = part_sprite16(`LP_PART_FRAME, run_cell_x, run_cell_y, 1'b0, pixel_data);
                    end

                    // Part sprite layer with active / dimmed rendering
                    if (intact_mask[run_cell_index] && run_part != `LP_PART_EMPTY) begin
                        if (run_part == `LP_PART_ENGINE) begin
                            if (engine_enabled && sw0_engine) begin
                                pixel_data = part_sprite_facing(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], anim_phase, pixel_data);
                            end else begin
                                // Grayed out / dimmed inactive engine
                                run_spr = part_sprite_facing(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], 1'b0, pixel_data);
                                pixel_data = (run_spr != pixel_data) ? ((run_spr & 16'hf7de) >> 1) : pixel_data;
                            end
                        end else if (run_part == `LP_PART_FAN) begin
                            if (fan_on || active_fans[run_cell_index]) begin
                                pixel_data = part_sprite_facing_dir(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], build_facing_down[run_cell_index], anim_phase, pixel_data);
                            end else begin
                                // Grayed out / dimmed inactive fan
                                run_spr = part_sprite_facing_dir(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], build_facing_down[run_cell_index], 1'b0, pixel_data);
                                pixel_data = (run_spr != pixel_data) ? ((run_spr & 16'hf7de) >> 1) : pixel_data;
                            end
                        end else if (run_part == `LP_PART_BOOSTER) begin
                            if (boost_active || rocket_ready) begin
                                pixel_data = part_sprite_facing_dir(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], build_facing_down[run_cell_index], boost_active ? anim_phase : 1'b0, pixel_data);
                            end else begin
                                // Grayed out / dimmed spent rocket
                                run_spr = part_sprite_facing_dir(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], build_facing_down[run_cell_index], 1'b0, pixel_data);
                                pixel_data = (run_spr != pixel_data) ? ((run_spr & 16'hf7de) >> 1) : pixel_data;
                            end
                        end else begin
                            pixel_data = part_sprite_facing_dir(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], build_facing_down[run_cell_index], anim_phase, pixel_data);
                        end
                    end
                end
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

                // Button 3: [ EDIT ] (x: 50..70, center 60) - Pencil Icon
                else if (x >= 50 && x <= 70) begin
                    if (x == 50 || x == 70 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    pixel_data = cartoon_pencil(7'd60, 6'd58, x, y, pixel_data);
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
            // RESULT SCREEN: Pure Icon Toolbar
            // -----------------------------------------------------------------
            // Clear right panel to avoid background text bleed (dark navy matching screen background)
            if (x >= 54 && y >= 30 && y < 53) begin
                pixel_data = 16'h0841;
            end
            if (y >= 53) begin
                pixel_data = 16'h0841;
                // Button 1: [ HOME ] (x: 2..22)
                if (x >= 2 && x <= 22) begin
                    if (x == 2 || x == 22 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (is_home_icon(7'd12, 6'd58, x, y)) pixel_data = 16'hffff;
                end
                // Button 2: [ MAP SELECT ] (x: 26..46)
                else if (x >= 26 && x <= 46) begin
                    if (x == 26 || x == 46 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 26 && cursor_x <= 46 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 26 && cursor_x <= 46 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    // Folded Parchment Map Icon at center (36, 58)
                    if (x >= 32 && x <= 40 && y >= 55 && y <= 61) begin
                        if (y == 55 || y == 61 || x == 32 || x == 40) pixel_data = 16'h8a22;
                        else if (x == 35 || x == 37) pixel_data = 16'hb530;
                        else if (x == 36 && y == 58) pixel_data = 16'hf800;
                        else pixel_data = 16'hffdf;
                    end
                end
                // Button 3: [ NEXT / EDIT ] (x: 50..70) - Pencil Icon on Fail
                else if (x >= 50 && x <= 70) begin
                    if (x == 50 || x == 70 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 50 && cursor_x <= 70 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    if (game_state == `LP_SUCCESS) begin
                        if (is_play_icon(7'd60, 6'd58, x, y)) pixel_data = 16'h07e0; // Bright green play triangle
                    end else begin
                        pixel_data = cartoon_pencil(7'd60, 6'd58, x, y, pixel_data);
                    end
                end
                // Button 4: [ GUIDE ] (x: 74..94)
                else if (x >= 74 && x <= 94) begin
                    if (x == 74 || x == 94 || y == 53 || y == 63)
                        pixel_data = (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) ? 16'hffe0 : 16'h04b4;
                    else if (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 53 && cursor_y <= 63) pixel_data = 16'h0351;
                    else pixel_data = 16'h18e5;
                    // Open Book Icon at center (84, 58)
                    if (x >= 79 && x <= 89 && y >= 55 && y <= 61) begin
                        if (x == 84) pixel_data = 16'h8a22; // Spine
                        else if (y == 55 || y == 61 || x == 79 || x == 89) pixel_data = 16'h8a22; // Cover
                        else if (y == 57 || y == 59) pixel_data = 16'h0010; // Text lines
                        else pixel_data = 16'hffff; // Pages
                    end
                end
            end
        end

        // Mouse pointer overlay (topmost layer)
        if ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
            (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))
            pixel_data = 16'hffff;
    end
endmodule
