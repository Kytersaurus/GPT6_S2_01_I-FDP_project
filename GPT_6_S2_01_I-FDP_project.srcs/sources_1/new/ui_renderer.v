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
    input wire [2:0] master_volume, input wire [1:0] mouse_speed,
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    input wire build_valid, engine_enabled, boost_active,
    input wire engine_available,
    input wire fan_available, fan_on, rocket_available, rocket_ready, balloon_available,
    input wire anim_phase,
    input wire [6:0] cursor_x, cursor_y,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input wire [8:0] build_facing_left,
    input wire sw0_engine,
    output reg [15:0] pixel_data
);
    `include "ui_font.vh"
    `include "part_sprites.vh"

    integer example_local_x, example_local_y, example_row, example_col;

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
            is_border = (!is_hub && !is_hole && (r2 >= 20 || (is_tooth && (r2 >= 36 || dx == -1 || dx == 1 || dx == 4 || dx == 6 || dx == -4 || dx == -6))));
            is_sparkle = ((dx == -2 && dy == -3) || (dx == 3 && dy == 2));

            if (is_sparkle) cartoon_gear = 16'hffff; // White glint
            else if (is_hole) cartoon_gear = 16'h6210; // Purple center hole
            else if (is_hub) cartoon_gear = 16'hfed0; // Golden yellow hub
            else if (is_border) cartoon_gear = 16'h6210; // Dark purple border
            else if (is_body || is_tooth) begin
                if (r2 >= 9 && r2 <= 15) cartoon_gear = 16'h8a95; // Accent ring
                else cartoon_gear = 16'hbdf7; // Soft lavender body
            end else cartoon_gear = bg;
        end
    endfunction

    // Run grid coordinates: 16x16 cells using shifts and masks (Rule 2: zero division/modulo)
    wire [1:0] run_col = (x - 7'd24) >> 4;
    wire [1:0] run_row = (y - 6'd2) >> 4;
    wire [3:0] run_cell_index = ((run_row << 1) + run_row) + run_col;
    wire [3:0] run_cell_x = (x - 7'd24) & 4'd15;
    wire [3:0] run_cell_y = (y - 6'd2) & 4'd15;
    reg [2:0] run_part;
    reg [15:0] run_spr;

    always @* begin
        pixel_data = base_pixel;

        if (start_screen_active) begin
            // -----------------------------------------------------------------
            // START SCREEN (OPTION B): Authentic Bad Piggies Title Screen
            // -----------------------------------------------------------------
            // 1. Tropical landscape background
            if (y < 46) begin
                pixel_data = (y < 14) ? 16'h24a5 : (y < 28) ? 16'h3567 : 16'h4609;
            end else if (y < 53) begin
                pixel_data = 16'hed30; // Sandy yellow beach
            end else if (y < 56) begin
                pixel_data = 16'hffff; // White ocean surf
            end else begin
                pixel_data = 16'h1c76; // Turquoise ocean wave
            end

            // 2. Title Bubble Font: "LAGGY PIGGIES"
            // Row 1: "LAGGY" centered at y: 4..13, x: 23..65 (5 letters x 8px)
            // Row 2: "PIGGIES" centered at y: 16..25, x: 16..77 (7 letters x 8px)
            if (y >= 4 && y <= 13 && x >= 23 && x <= 65) begin
                // Draw bold lime-green letters with dark green outline
                if (text_on("LAGGY           ", 24, 5, x, y) ||
                    text_on("LAGGY           ", 23, 5, x, y) ||
                    text_on("LAGGY           ", 24, 6, x, y)) begin
                    pixel_data = (y == 5 || y == 6) ? 16'ha7e0 : 16'h5fe0; // Lime green with top highlight
                end else if (text_on("LAGGY           ", 24, 4, x, y) ||
                             text_on("LAGGY           ", 24, 7, x, y) ||
                             text_on("LAGGY           ", 22, 5, x, y) ||
                             text_on("LAGGY           ", 25, 5, x, y)) begin
                    pixel_data = 16'h0200; // Dark green outline
                end
            end else if (y >= 16 && y <= 25 && x >= 16 && x <= 77) begin
                if (text_on("PIGGIES         ", 17, 17, x, y) ||
                    text_on("PIGGIES         ", 16, 17, x, y) ||
                    text_on("PIGGIES         ", 17, 18, x, y)) begin
                    // Snout nostrils in P and G loops
                    if ((x == 19 && y == 19) || (x == 37 && y == 19) || (x == 46 && y == 19))
                        pixel_data = 16'h0200;
                    else
                        pixel_data = (y == 17 || y == 18) ? 16'ha7e0 : 16'h5fe0;
                end else if (text_on("PIGGIES         ", 17, 16, x, y) ||
                             text_on("PIGGIES         ", 17, 19, x, y) ||
                             text_on("PIGGIES         ", 15, 17, x, y) ||
                             text_on("PIGGIES         ", 18, 17, x, y)) begin
                    pixel_data = 16'h0200; // Dark green outline
                end
            end

            // 3. Centered Circular Play Button at (48, 38), Radius 9
            if ((x-7'd48)*(x-7'd48) + (y-6'd38)*(y-6'd38) <= 81) begin
                if ((x-7'd48)*(x-7'd48) + (y-6'd38)*(y-6'd38) >= 64) begin
                    pixel_data = 16'h0280; // Dark rim
                end else begin
                    // White play triangle pointing right inside circle
                    if (x >= 45 && x <= 52 &&
                        y >= (34 + (x - 45)) &&
                        y <= (42 - (x - 45))) begin
                        pixel_data = 16'hffff; // White triangle
                    end else begin
                        if (cursor_x >= 38 && cursor_x <= 58 && cursor_y >= 28 && cursor_y <= 48)
                            pixel_data = 16'h0360; // Hover pulse
                        else if (y < 36 && x < 48)
                            pixel_data = 16'h7fe0; // Specular crescent
                        else
                            pixel_data = 16'h4fe0; // Vibrant lime green
                    end
                end
            end

            // 4. Cartoon Settings Gear in Bottom-Left (Center at 12, 54)
            if (x >= 4 && x <= 20 && y >= 46 && y <= 62) begin
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
                    pixel_data = (level_index == 0) ? 16'h07e0 : 16'h04b4;
                else if (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 12 && cursor_y <= 30)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
            end
            if (text_on("CAVE ARCH       ", 10, 14, x, y)) pixel_data = 16'hffff;
            if (text_on("MAP 1           ", 10, 22, x, y)) pixel_data = 16'h07ff;

            // Map 2: Cave Flight
            if (x >= 4 && x <= 91 && y >= 34 && y <= 52) begin
                if (x == 4 || x == 91 || y == 34 || y == 52)
                    pixel_data = (level_index == 1) ? 16'h07e0 : 16'h04b4;
                else if (cursor_x >= 4 && cursor_x <= 91 && cursor_y >= 34 && cursor_y <= 52)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
            end
            if (text_on("CAVE FLIGHT     ", 10, 36, x, y)) pixel_data = 16'hffff;
            if (text_on("MAP 2           ", 10, 44, x, y)) pixel_data = 16'h07ff;

            // Bottom toolbar: [ BACK ]
            if (y >= 55) begin
                if (x <= 27) begin
                    if (x == 0 || x == 27 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on("BACK            ", 2, 56, x, y)) pixel_data = 16'hffff;
                end else if (text_on("PICK A MAP      ", 32, 56, x, y)) pixel_data = 16'h7bef;
            end
        end else if (game_state == `LP_SETTINGS) begin
            // -----------------------------------------------------------------
            // SETTINGS SCREEN: 3 Centered Icon Boxes (Sound, Map, Mouse)
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;
            if (audio_muted) begin
                if (text_on("MUTED VIA SW1   ", 10, 2, x, y)) pixel_data = 16'hffe0;
            end else begin
                if (text_on("SETTINGS        ", 24, 2, x, y)) pixel_data = 16'h07ff;
            end

            // Box 1: SOUND SETTINGS (x: 6..30, y: 12..48)
            if (x >= 6 && x <= 30 && y >= 12 && y <= 48) begin
                if (x == 6 || x == 30 || y == 12 || y == 48) pixel_data = 16'h04b4;
                else if (cursor_x >= 6 && cursor_x <= 30 && cursor_y >= 12 && cursor_y <= 48) pixel_data = 16'h0351;
                else pixel_data = 16'h18e5;

                // Speaker Icon (x: 11..25, y: 17..27)
                if ((x >= 11 && x <= 13 && y >= 20 && y <= 24) ||
                    (x == 14 && y >= 19 && y <= 25) ||
                    (x == 15 && y >= 18 && y <= 26) ||
                    (x == 16 && y >= 17 && y <= 27) ||
                    (x == 19 && y >= 19 && y <= 25) ||
                    (x == 20 && (y == 20 || y == 24)) ||
                    (x == 23 && y >= 18 && y <= 26) ||
                    (x == 24 && (y == 19 || y == 25)))
                    pixel_data = 16'hffe0;

                // Red mute slash across speaker if muted (Rule 2: zero division)
                if (audio_muted && ((x == 11 && y == 17) || (x == 12 && y == 18) || (x == 13 && y == 19) ||
                                    (x == 14 && y == 20) || (x == 15 && y == 21) || (x == 16 && y == 21) ||
                                    (x == 17 && y == 22) || (x == 18 && y == 23) || (x == 19 && y == 24) ||
                                    (x == 20 && y == 24) || (x == 21 && y == 25) || (x == 22 && y == 26) ||
                                    (x == 23 && y == 27) || (x == 24 && y == 28)))
                    pixel_data = 16'hf800;
            end
            if (text_on("SND             ", 9, 31, x, y)) pixel_data = 16'hffff;
            if (audio_muted) begin
                if (text_on("MUTE            ", 8, 39, x, y)) pixel_data = 16'hf800;
            end else begin
                case (master_volume)
                    0: if (text_on(" 0/4            ", 8, 39, x, y)) pixel_data = 16'h07ff;
                    1: if (text_on(" 1/4            ", 8, 39, x, y)) pixel_data = 16'h07ff;
                    2: if (text_on(" 2/4            ", 8, 39, x, y)) pixel_data = 16'h07ff;
                    3: if (text_on(" 3/4            ", 8, 39, x, y)) pixel_data = 16'h07ff;
                    default: if (text_on(" 4/4            ", 8, 39, x, y)) pixel_data = 16'h07ff;
                endcase
            end

            // Box 2: MAP SELECTOR (x: 36..60, y: 12..48)
            if (x >= 36 && x <= 60 && y >= 12 && y <= 48) begin
                if (x == 36 || x == 60 || y == 12 || y == 48) pixel_data = 16'h04b4;
                else if (cursor_x >= 36 && cursor_x <= 60 && cursor_y >= 12 && cursor_y <= 48) pixel_data = 16'h0351;
                else pixel_data = 16'h18e5;

                // Folded Parchment Map Icon (x: 41..55, y: 17..27)
                if (x >= 41 && x <= 55 && y >= 17 && y <= 27) begin
                    if (y == 17 || y == 27 || x == 41 || x == 55) pixel_data = 16'h8a22;
                    else if (x == 45 || x == 51) pixel_data = 16'hb530;
                    else if ((x == 43 && y == 24) || (x == 47 && y == 21) || (x == 53 && y == 19)) pixel_data = 16'hf800;
                    else pixel_data = 16'hffdf;
                end
            end
            if (text_on("MAP             ", 39, 31, x, y)) pixel_data = 16'hffff;
            if (level_index == 0) begin
                if (text_on("ARCH            ", 38, 39, x, y)) pixel_data = 16'h07ff;
            end else begin
                if (text_on("FLGT            ", 38, 39, x, y)) pixel_data = 16'h07ff;
            end

            // Box 3: MOUSE SENSITIVITY (x: 66..90, y: 12..48)
            if (x >= 66 && x <= 90 && y >= 12 && y <= 48) begin
                if (x == 66 || x == 90 || y == 12 || y == 48) pixel_data = 16'h04b4;
                else if (cursor_x >= 66 && cursor_x <= 90 && cursor_y >= 12 && cursor_y <= 48) pixel_data = 16'h0351;
                else pixel_data = 16'h18e5;

                // Mouse Icon (x: 73..83, y: 17..27)
                if ((x >= 74 && x <= 82 && y >= 18 && y <= 26) || (x >= 75 && x <= 81 && (y == 17 || y == 27))) begin
                    if (x == 78 && y >= 19 && y <= 21) pixel_data = 16'h0000;
                    else if (x == 78 && y >= 17 && y <= 22) pixel_data = 16'h036a;
                    else pixel_data = 16'hffff;
                end else if ((y == 17 && (x == 75 || x == 81)) || (y == 27 && (x == 75 || x == 81)) || ((x == 73 || x == 83) && y >= 19 && y <= 25)) begin
                    pixel_data = 16'h036a;
                end
            end
            case (mouse_speed)
                0: begin
                    if (text_on("SLOW            ", 68, 31, x, y)) pixel_data = 16'hffe0;
                    if (text_on("0.5X            ", 68, 39, x, y)) pixel_data = 16'h7bef;
                end
                1: begin
                    if (text_on("NORM            ", 68, 31, x, y)) pixel_data = 16'hffe0;
                    if (text_on("1.0X            ", 68, 39, x, y)) pixel_data = 16'h7bef;
                end
                default: begin
                    if (text_on("FAST            ", 68, 31, x, y)) pixel_data = 16'hffe0;
                    if (text_on("2.5X            ", 68, 39, x, y)) pixel_data = 16'h7bef;
                end
            endcase

            // Bottom Centered [ BACK ] Button (x: 28..68, y: 52..62)
            if (x >= 28 && x <= 68 && y >= 52 && y <= 62) begin
                if (x == 28 || x == 68 || y == 52 || y == 62) pixel_data = 16'h04b4;
                else if (cursor_x >= 28 && cursor_x <= 68 && cursor_y >= 52 && cursor_y <= 62) pixel_data = 16'h0351;
                else pixel_data = 16'h18e5;
            end
            if (text_on("BACK            ", 40, 54, x, y)) pixel_data = 16'hffff;

        end else if (game_state == `LP_GUIDE) begin
            // -----------------------------------------------------------------
            // GUIDE / DIARY SCREEN
            // -----------------------------------------------------------------
            pixel_data = 16'h0841;
            case (diary_page)
                0: begin
                    if (text_on("CONTROLS     1/3", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("DRAG: PLACE PART", 2, 12, x, y)) pixel_data = 16'hffff;
                    if (text_on("R-CLK: REMOVE   ", 2, 22, x, y)) pixel_data = 16'hffff;
                    if (text_on("L-CLK: ROTATE   ", 2, 32, x, y)) pixel_data = 16'hffff;
                    if (text_on("SW0: MOTOR DRIVE", 2, 42, x, y)) pixel_data = 16'h07e0;
                end
                1: begin
                    if (text_on("BLUEPRINT    2/3", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("MOTOR CART      ", 44, 12, x, y)) pixel_data = 16'h07e0;
                    if (text_on("1 PIG           ", 44, 21, x, y)) pixel_data = 16'hffff;
                    if (text_on("1 MOTOR         ", 44, 29, x, y)) pixel_data = 16'hffff;
                    if (text_on("2 WHEELS        ", 44, 37, x, y)) pixel_data = 16'hffff;
                    if (text_on("3 FRAMES        ", 44, 45, x, y)) pixel_data = 16'h7bef;
                    if (x >= 4 && x < 40 && y >= 12 && y < 48) begin
                        if (x < 16) begin example_col = 0; example_local_x = x - 4; end
                        else if (x < 28) begin example_col = 1; example_local_x = x - 16; end
                        else begin example_col = 2; example_local_x = x - 28; end
                        if (y < 24) begin example_row = 0; example_local_y = y - 12; end
                        else if (y < 36) begin example_row = 1; example_local_y = y - 24; end
                        else begin example_row = 2; example_local_y = y - 36; end
                        pixel_data = 16'h0841;
                        if (example_local_x == 0 || example_local_y == 0 ||
                            example_local_x == 11 || example_local_y == 11) pixel_data = 16'h7bef;
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
                    if (text_on("PARTS & TIPS 3/3", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (x >= 4 && x < 12 && y >= 11 && y < 19)
                        pixel_data = part_sprite(`LP_PART_PIG, x - 4, y - 11, 1'b0, pixel_data);
                    if (text_on("PIG: KEEP ALIVE ", 16, 12, x, y)) pixel_data = 16'hffff;

                    if (x >= 4 && x < 12 && y >= 21 && y < 29)
                        pixel_data = tnt_sprite(x - 4, y - 21, pixel_data);
                    if (text_on("TNT: AVOID BLAST", 16, 22, x, y)) pixel_data = 16'hf800;

                    if (x >= 4 && x < 12 && y >= 31 && y < 39)
                        pixel_data = part_sprite(`LP_PART_ENGINE, x - 4, y - 31, 1'b0, pixel_data);
                    if (text_on("ENG: MOTOR DRIVE", 16, 32, x, y)) pixel_data = 16'h07e0;

                    if (x >= 4 && x < 12 && y >= 41 && y < 49)
                        pixel_data = part_sprite(`LP_PART_WHEEL, x - 4, y - 41, 1'b0, pixel_data);
                    if (text_on("WHL: GROUND GRIP", 16, 42, x, y)) pixel_data = 16'hffe0;
                end
                default: begin
                    // Sound Settings Page (diary_page == 3)
                    if (text_on("SOUND SETTINGS  ", 6, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("MASTER VOLUME   ", 6, 13, x, y)) pixel_data = 16'hffff;

                    // Button [-]: x: 8..28, y: 24..37
                    if (x >= 8 && x <= 28 && y >= 24 && y <= 37) begin
                        if (x == 8 || x == 28 || y == 24 || y == 37) pixel_data = 16'h04b4;
                        else if (cursor_x >= 8 && cursor_x <= 28 && cursor_y >= 24 && cursor_y <= 37) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end
                    if (text_on(" -              ", 12, 28, x, y)) pixel_data = 16'hffff;

                    // Volume readout: wide layout x: 38..56, y: 28
                    case (master_volume)
                        0: if (text_on("0/4             ", 40, 28, x, y)) pixel_data = 16'h07ff;
                        1: if (text_on("1/4             ", 40, 28, x, y)) pixel_data = 16'h07ff;
                        2: if (text_on("2/4             ", 40, 28, x, y)) pixel_data = 16'h07ff;
                        3: if (text_on("3/4             ", 40, 28, x, y)) pixel_data = 16'h07ff;
                        default: if (text_on("4/4             ", 40, 28, x, y)) pixel_data = 16'h07ff;
                    endcase

                    // Button [+]: x: 64..84, y: 24..37 (never overlaps 4/4 readout)
                    if (x >= 64 && x <= 84 && y >= 24 && y <= 37) begin
                        if (x == 64 || x == 84 || y == 24 || y == 37) pixel_data = 16'h04b4;
                        else if (cursor_x >= 64 && cursor_x <= 84 && cursor_y >= 24 && cursor_y <= 37) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end
                    if (text_on(" +              ", 68, 28, x, y)) pixel_data = 16'hffff;

                    // Audio Mute Status Banner (x: 8..87, y: 41..51)
                    if (audio_muted) begin
                        if (x >= 8 && x <= 87 && y >= 41 && y <= 51) begin
                            if (x == 8 || x == 87 || y == 41 || y == 51) pixel_data = 16'hf800;
                            else pixel_data = 16'h3000;
                        end
                        if (text_on("MUTED VIA SW1   ", 12, 43, x, y)) pixel_data = 16'hffe0;
                    end else begin
                        if (text_on("SW1: MUTE SOUND ", 12, 43, x, y)) pixel_data = 16'h7bef;
                    end
                end
            endcase

            // Bottom toolbar: [BACK] [ 1 ] [ 2 ] [ 3 ]
            if (y >= 55) begin
                if (x <= 27) begin
                    if (x == 0 || x == 27 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on("BACK            ", 2, 56, x, y)) pixel_data = 16'hffff;
                end else if (diary_page != 3) begin
                    if (x >= 32 && x <= 51) begin
                        if (x == 32 || x == 51 || y == 55 || y == 63)
                            pixel_data = (diary_page == 0) ? 16'hffe0 : 16'h04b4;
                        else pixel_data = 16'h18e5;
                        if (text_on("1               ", 40, 56, x, y)) pixel_data = (diary_page == 0) ? 16'hffe0 : 16'hffff;
                    end else if (x >= 53 && x <= 72) begin
                        if (x == 53 || x == 72 || y == 55 || y == 63)
                            pixel_data = (diary_page == 1) ? 16'hffe0 : 16'h04b4;
                        else pixel_data = 16'h18e5;
                        if (text_on("2               ", 61, 56, x, y)) pixel_data = (diary_page == 1) ? 16'hffe0 : 16'hffff;
                    end else if (x >= 74 && x <= 93) begin
                        if (x == 74 || x == 93 || y == 55 || y == 63)
                            pixel_data = (diary_page == 2) ? 16'hffe0 : 16'h04b4;
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
                        pixel_data = build_valid ? 16'h07e0 : 16'h4208;
                    else pixel_data = build_valid ? 16'h18e5 : 16'h18c3;
                    if (text_on("GO              ", 4, 56, x, y)) pixel_data = build_valid ? 16'hffff : 16'h7bef;
                end
                // Inventory Page 1 / 2 Buttons
                else if (x >= 20 && x < 62) begin
                    if (x == 20 || x == 40 || x == 41 || x == 61 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on("1               ", 28, 56, x, y)) pixel_data = (inventory_page == 0) ? 16'hffe0 : 16'hffff;
                    if (text_on("2               ", 49, 56, x, y)) pixel_data = (inventory_page == 1) ? 16'hffe0 : 16'hffff;
                end
                // Open Book Diary Icon (x: 64..79)
                else if (x >= 64 && x < 80) begin
                    if (x == 64 || x == 79 || y == 55 || y == 63) pixel_data = 16'h04b4;
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
                    if (x == 80 || x == 95 || y == 55 || y == 63) pixel_data = 16'h04b4;
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
                if (engine_available) begin
                    if (!sw0_engine) begin
                        // Warning Box: Engine OFF by SW0
                        if (x >= 1 && x <= 22 && y >= 10 && y <= 42) begin
                            if (x == 1 || x == 22 || y == 10 || y == 42) pixel_data = 16'hf800;
                            else pixel_data = 16'h3000;
                        end
                        if (text_on("ENG             ", 3, 13, x, y)) pixel_data = 16'hf800;
                        if (text_on("OFF             ", 3, 23, x, y)) pixel_data = 16'hffe0;
                        if (text_on("SW0             ", 3, 33, x, y)) pixel_data = 16'hffff;
                    end else begin
                        // Active Box: Engine ON by SW0
                        if (x >= 1 && x <= 22 && y >= 10 && y <= 42) begin
                            if (x == 1 || x == 22 || y == 10 || y == 42) pixel_data = 16'h07e0;
                            else pixel_data = 16'h0200;
                        end
                        if (text_on("ENG             ", 3, 13, x, y)) pixel_data = 16'h07e0;
                        if (text_on(" ON             ", 3, 23, x, y)) pixel_data = 16'h07e0;
                        if (text_on("SW0             ", 3, 33, x, y)) pixel_data = 16'h7bef;
                    end
                end
            end

            // 2. Middle Panel (x: 24..71, y: 2..49): Big 16x16 Interactive Vehicle Grid
            if (x >= 24 && x <= 71 && y >= 2 && y <= 49) begin
                run_part = build_grid >> (run_cell_index * 3);

                // Grid cell borders
                if (run_cell_x == 0 || run_cell_y == 0 || x == 71 || y == 49) begin
                    pixel_data = 16'h4208;
                end else begin
                    // Damage cross under destroyed elements
                    if ((!intact_mask[run_cell_index] && run_part != `LP_PART_EMPTY) ||
                        (frame_intact_mask[run_cell_index] == 0 && frame_intact_mask != 9'd0)) begin
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
                            if (fan_on) begin
                                pixel_data = part_sprite_facing(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], anim_phase, pixel_data);
                            end else begin
                                // Grayed out / dimmed inactive fan
                                run_spr = part_sprite_facing(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], 1'b0, pixel_data);
                                pixel_data = (run_spr != pixel_data) ? ((run_spr & 16'hf7de) >> 1) : pixel_data;
                            end
                        end else begin
                            pixel_data = part_sprite_facing(run_part, run_cell_x, run_cell_y, 16, build_facing_left[run_cell_index], anim_phase, pixel_data);
                        end
                    end
                end
            end

            // 3. Right Panel (x: 72..95, y: 0..50): Clean background (Timer removed from OLED!)
            if (x >= 72 && y <= 50) begin
                pixel_data = 16'h0841;
            end

            // 4. Bottom Action Bar (y: 52..63): [ RTRY ] | [ END ] | [ EDIT ] | [ GEAR ]
            if (y >= 52) begin
                if (y == 52) pixel_data = 16'h04b4; // Separator line
                else begin
                    // Button 1: [ RETRY ] (x: 2..22)
                    if (x >= 2 && x <= 22) begin
                        if (x == 2 || x == 22 || y == 53 || y == 63) pixel_data = 16'h04b4;
                        else if (cursor_x >= 2 && cursor_x <= 22 && cursor_y >= 54 && cursor_y <= 63) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("RTRY            ", 4, 55, x, y)) pixel_data = 16'hffff;
                    end

                    // Button 2: [ END TRY ] (x: 26..44)
                    else if (x >= 26 && x <= 44) begin
                        if (x == 26 || x == 44 || y == 53 || y == 63) pixel_data = 16'h04b4;
                        else if (cursor_x >= 26 && cursor_x <= 44 && cursor_y >= 54 && cursor_y <= 63) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("END             ", 30, 55, x, y)) pixel_data = 16'hf800; // Red text
                    end

                    // Button 3: [ EDIT ] (x: 52..70)
                    else if (x >= 52 && x <= 70) begin
                        if (x == 52 || x == 70 || y == 53 || y == 63) pixel_data = 16'h04b4;
                        else if (cursor_x >= 52 && cursor_x <= 70 && cursor_y >= 54 && cursor_y <= 63) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("EDIT            ", 53, 55, x, y)) pixel_data = 16'h07ff;
                    end

                    // Button 4: [ GEAR ] (x: 74..94)
                    else if (x >= 74 && x <= 94) begin
                        if (x == 74 || x == 94 || y == 53 || y == 63) pixel_data = 16'h04b4;
                        else if (cursor_x >= 74 && cursor_x <= 94 && cursor_y >= 54 && cursor_y <= 63) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        pixel_data = cartoon_gear(7'd84, 6'd58, x, y, pixel_data);
                    end
                end
            end
        end else if (game_state == `LP_SUCCESS || game_state == `LP_FAIL) begin
            // -----------------------------------------------------------------
            // RESULT SCREEN
            // -----------------------------------------------------------------
            if (y >= 55) begin
                pixel_data = 16'h0841;
                // TRY button
                if (x < 28) begin
                    if (x == 0 || x == 27 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on("TRY             ", 2, 56, x, y)) pixel_data = 16'hffff;
                end
                // NEXT / EDIT button
                else if (x >= 32 && x < 60) begin
                    if (x == 32 || x == 59 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on(game_state == `LP_SUCCESS ? "NEXT            " : "EDIT            ", 34, 56, x, y)) pixel_data = 16'hffff;
                end
                // DIARY button
                else if (x >= 64) begin
                    if (x == 64 || x == 95 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on("DIARY           ", 65, 56, x, y)) pixel_data = 16'hffff;
                end
            end
        end

        // Mouse pointer overlay (topmost layer)
        if ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
            (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))
            pixel_data = 16'hffff;
    end
endmodule
