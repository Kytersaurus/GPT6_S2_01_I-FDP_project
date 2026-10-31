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
    input wire fan_available, fan_on, rocket_available, rocket_ready, balloon_available,
    input wire anim_phase,
    input wire [6:0] cursor_x, cursor_y,
    output reg [15:0] pixel_data
);
    `include "ui_font.vh"
    `include "part_sprites.vh"

    integer example_local_x, example_local_y, example_row, example_col;

    always @* begin
        pixel_data = base_pixel;

        if (start_screen_active) begin
            // 1. Moving cave background from map_draw_class
            case (map_draw_class)
                3'd0: pixel_data = 16'h0825; // Dark indigo cave air
                3'd1: pixel_data = 16'h4a49; // Stone wall
                3'd2: pixel_data = 16'h8281; // Dirt
                3'd3: pixel_data = 16'h2945; // Dark rock
                3'd4: pixel_data = 16'h6201; // Mud
                3'd5: pixel_data = 16'hc980; // TNT block
                default: pixel_data = 16'h0825;
            endcase

            // 2. Title Banner: "BAD PIGGIES"
            if (x >= 6 && x <= 89 && y >= 3 && y <= 13) begin
                if (x == 6 || x == 89 || y == 3 || y == 13) pixel_data = 16'hffe0;
                else pixel_data = 16'h0000;
            end
            if (text_on("  BAD PIGGIES   ", 6, 5, x, y)) pixel_data = 16'h07e0;

            // 3. Centered Pig face (16x16)
            if (x >= 40 && x <= 55 && y >= 16 && y <= 31) begin
                pixel_data = part_sprite16(`LP_PART_PIG, x-40, y-16, 1'b0, pixel_data);
            end

            // 4. Pulsating [ PLAY ] button
            if (x >= 24 && x <= 71 && y >= 36 && y <= 48) begin
                if (x == 24 || x == 71 || y == 36 || y == 48)
                    pixel_data = anim_phase ? 16'hffe0 : 16'h07e0;
                else if (cursor_x >= 24 && cursor_x <= 71 && cursor_y >= 36 && cursor_y <= 48)
                    pixel_data = 16'h0360;
                else
                    pixel_data = 16'h01e0;
            end
            if (text_on("    PLAY        ", 24, 39, x, y)) pixel_data = 16'hffff;

            // 5. Settings [ GEAR ] in top-right corner
            if (x >= 82 && x <= 94 && y >= 2 && y <= 14) begin
                if (x == 82 || x == 94 || y == 2 || y == 14) pixel_data = 16'h7bef;
                else if (cursor_x >= 82 && cursor_x <= 94 && cursor_y >= 2 && cursor_y <= 14)
                    pixel_data = 16'h0351;
                else
                    pixel_data = 16'h18e5;
                // Gear teeth
                if ((x >= 87 && x <= 89 && y >= 6 && y <= 10) ||
                    (x == 86 && y >= 7 && y <= 9) ||
                    (x == 90 && y >= 7 && y <= 9) ||
                    (x == 88 && (y == 5 || y == 11)) ||
                    ((x == 85 || x == 91) && y == 8)) begin
                    if (x == 88 && y == 8) pixel_data = 16'h18e5;
                    else pixel_data = 16'hffff;
                end
            end
        end else if (game_state == `LP_LEVEL_SELECT) begin
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
            pixel_data = 16'h0841;
            if (text_on("SETTINGS        ", 24, 2, x, y)) pixel_data = 16'h07ff;

            // Row 1: Sound Settings button (opens diary_page=3 sound page)
            if (x >= 8 && x <= 87 && y >= 12 && y <= 24) begin
                if (x == 8 || x == 87 || y == 12 || y == 24) pixel_data = 16'h04b4;
                else if (cursor_x >= 8 && cursor_x <= 87 && cursor_y >= 12 && cursor_y <= 24) pixel_data = 16'h0351;
                else pixel_data = 16'h18e5;
            end
            if (text_on("SOUND SETTINGS >", 10, 15, x, y)) pixel_data = 16'hffff;

            // Row 2: Map Selector button
            if (x >= 8 && x <= 87 && y >= 30 && y <= 43) begin
                if (x == 8 || x == 87 || y == 30 || y == 43) pixel_data = 16'h04b4;
                else if (cursor_x >= 8 && cursor_x <= 87 && cursor_y >= 30 && cursor_y <= 43) pixel_data = 16'h0351;
                else pixel_data = 16'h18e5;
            end
            if (text_on("MAP SELECTOR    ", 12, 34, x, y)) pixel_data = 16'hffff;

            // Row 3: Navigation: [ BACK ] and [ SPEED ]
            if (y >= 53) begin
                // [ BACK ]
                if (x >= 2 && x <= 32) begin
                    if (x == 2 || x == 32 || y == 53 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on("BACK            ", 4, 55, x, y)) pixel_data = 16'hffff;
                end
                // [ SPEED ]
                if (x >= 38 && x <= 92) begin
                    if (x == 38 || x == 92 || y == 53 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    case (mouse_speed)
                        0: if (text_on("SPD: SLOW       ", 40, 55, x, y)) pixel_data = 16'hffe0;
                        1: if (text_on("SPD: NORM       ", 40, 55, x, y)) pixel_data = 16'hffe0;
                        default: if (text_on("SPD: FAST       ", 40, 55, x, y)) pixel_data = 16'hffe0;
                    endcase
                end
            end
        end else if (game_state == `LP_GUIDE) begin
            pixel_data = 16'h0841;
            case (diary_page)
                0: begin
                    if (text_on("HOW TO PLAY 1/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("DRAG: ADD PART  ", 2, 11, x, y)) pixel_data = 16'hffff;
                    if (text_on("R-CLICK: REMOVE ", 2, 20, x, y)) pixel_data = 16'hffff;
                    if (text_on("CLICK: ROTATE   ", 2, 29, x, y)) pixel_data = 16'hffff;
                    if (text_on("SW0/ENG: DRIVE  ", 2, 38, x, y)) pixel_data = 16'hffff;
                    if (text_on("FLAG = LEVEL WIN", 2, 47, x, y)) pixel_data = 16'h07e0;
                end
                1: begin
                    if (text_on("LEGAL BUILD 2/3 ", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("VALID           ", 48, 14, x, y)) pixel_data = 16'h07e0;
                    if (text_on("1 PIG           ", 48, 24, x, y)) pixel_data = 16'hffff;
                    if (text_on("3 FRAMES        ", 48, 34, x, y)) pixel_data = 16'hffff;
                    if (text_on("2 WHEELS        ", 48, 44, x, y)) pixel_data = 16'hffff;
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
                        if (example_row == 1 && example_col == 1)
                            pixel_data = part_sprite12(`LP_PART_PIG, example_local_x, example_local_y, 1'b0, pixel_data);
                        if (example_row == 2 && (example_col == 0 || example_col == 2))
                            pixel_data = part_sprite12(`LP_PART_WHEEL, example_local_x, example_local_y, 1'b0, pixel_data);
                    end
                end
                2: begin
                    if (text_on("MISSION TIPS 3/3", 2, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("PROTECT THE PIG ", 2, 11, x, y)) pixel_data = 16'hffff;
                    if (text_on("TNT BREAKS PARTS", 2, 20, x, y)) pixel_data = 16'hffff;
                    if (text_on("WHEELS GIVE GRIP", 2, 29, x, y)) pixel_data = 16'hffff;
                    if (text_on("STAR BOX = BONUS", 2, 38, x, y)) pixel_data = 16'hffe0;
                    if (text_on("SURVIVE TO WIN  ", 2, 47, x, y)) pixel_data = 16'h07e0;
                end
                default: begin
                    if (text_on("SOUND SETTINGS  ", 6, 2, x, y)) pixel_data = 16'h07ff;
                    if (text_on("MASTER VOLUME   ", 6, 14, x, y)) pixel_data = 16'hffff;
                    // Button [-]: x: 8..35, y: 28..43
                    if (x >= 8 && x <= 35 && y >= 28 && y <= 43) begin
                        if (x == 8 || x == 35 || y == 28 || y == 43) pixel_data = 16'h04b4;
                        else if (cursor_x >= 8 && cursor_x <= 35 && cursor_y >= 28 && cursor_y <= 43) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end
                    if (text_on(" -              ", 14, 33, x, y)) pixel_data = 16'hffff;
                    // Volume readout: x: 42..54, y: 33
                    case (master_volume)
                        0: if (text_on("0/4             ", 42, 33, x, y)) pixel_data = 16'h07ff;
                        1: if (text_on("1/4             ", 42, 33, x, y)) pixel_data = 16'h07ff;
                        2: if (text_on("2/4             ", 42, 33, x, y)) pixel_data = 16'h07ff;
                        3: if (text_on("3/4             ", 42, 33, x, y)) pixel_data = 16'h07ff;
                        default: if (text_on("4/4             ", 42, 33, x, y)) pixel_data = 16'h07ff;
                    endcase
                    // Button [+]: x: 60..87, y: 28..43
                    if (x >= 60 && x <= 87 && y >= 28 && y <= 43) begin
                        if (x == 60 || x == 87 || y == 28 || y == 43) pixel_data = 16'h04b4;
                        else if (cursor_x >= 60 && cursor_x <= 87 && cursor_y >= 28 && cursor_y <= 43) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                    end
                    if (text_on(" +              ", 66, 33, x, y)) pixel_data = 16'hffff;
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
            // Upper area uses base_pixel
            if (y >= 55 && feedback_code == `LP_FEEDBACK_NONE) begin
                pixel_data = 16'h0841;
                // GO button
                if (x < 18) begin
                    if (x == 0 || x == 17 || y == 55 || y == 63)
                        pixel_data = build_valid ? 16'h07e0 : 16'h4208;
                    else pixel_data = build_valid ? 16'h18e5 : 16'h18c3;
                    if (text_on("GO              ", 2, 56, x, y)) pixel_data = build_valid ? 16'hffff : 16'h7bef;
                end
                // Inventory 1/2 buttons
                else if (x >= 20 && x < 62) begin
                    if (x == 20 || x == 40 || x == 41 || x == 61 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (text_on("1               ", 28, 56, x, y)) pixel_data = (inventory_page == 0) ? 16'hffe0 : 16'hffff;
                    if (text_on("2               ", 49, 56, x, y)) pixel_data = (inventory_page == 1) ? 16'hffe0 : 16'hffff;
                end
                // Diary button (Book icon)
                else if (x >= 64 && x < 80) begin
                    if (x == 64 || x == 79 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if (x >= 68 && x <= 75 && y >= 57 && y <= 61) begin
                        if (y == 57 || y == 61 || x == 68 || x == 75 || x == 71) pixel_data = 16'hffff;
                        else pixel_data = 16'ha145;
                    end
                end
                // Settings button (Gear icon)
                else if (x >= 80 && x < 96) begin
                    if (x == 80 || x == 95 || y == 55 || y == 63) pixel_data = 16'h04b4;
                    else pixel_data = 16'h18e5;
                    if ((x >= 86 && x <= 89 && y >= 57 && y <= 61) ||
                        (x == 85 && (y == 58 || y == 59 || y == 60)) ||
                        (x == 90 && (y == 58 || y == 59 || y == 60)) ||
                        ((x == 87 || x == 88) && (y == 56 || y == 62)) ||
                        ((x == 84 || x == 91) && y == 59)) begin
                        if (x >= 87 && x <= 88 && y >= 58 && y <= 60) pixel_data = 16'h18e5;
                        else pixel_data = 16'hffff;
                    end
                end
            end
        end else if (game_state == `LP_RUN) begin
            if (y < 48) begin
                // Left & Center (x < 70) retains base_pixel: timer & centered vehicle!
                if (x >= 70) begin
                    pixel_data = 16'h0841;
                    // [ EDIT ] button (x: 70..94, y: 2..12)
                    if (y >= 2 && y <= 12 && x <= 94) begin
                        if (x == 70 || x == 94 || y == 2 || y == 12) pixel_data = 16'h04b4;
                        else if (cursor_x >= 70 && cursor_x <= 94 && cursor_y >= 2 && cursor_y <= 12) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("RETRY           ", 71, 4, x, y)) pixel_data = 16'hffff;
                    end
                    // [ GEAR ] Settings button (x: 76..88, y: 16..28)
                    if (x >= 76 && x <= 88 && y >= 16 && y <= 28) begin
                        if (x == 76 || x == 88 || y == 16 || y == 28) pixel_data = 16'h04b4;
                        else if (cursor_x >= 76 && cursor_x <= 88 && cursor_y >= 16 && cursor_y <= 28) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        // Gear glyph
                        if ((x >= 81 && x <= 83 && y >= 20 && y <= 24) ||
                            (x == 80 && y >= 21 && y <= 23) ||
                            (x == 84 && y >= 21 && y <= 23) ||
                            (x == 82 && (y == 19 || y == 25)) ||
                            ((x == 79 || x == 85) && y == 22)) begin
                            if (x == 82 && y == 22) pixel_data = 16'h18e5;
                            else pixel_data = 16'hffff;
                        end
                    end
                    // [ RETRY ] button (x: 70..94, y: 32..42)
                    if (y >= 32 && y <= 42 && x <= 94) begin
                        if (x == 70 || x == 94 || y == 32 || y == 42) pixel_data = 16'h04b4;
                        else if (cursor_x >= 70 && cursor_x <= 94 && cursor_y >= 32 && cursor_y <= 42) pixel_data = 16'h0351;
                        else pixel_data = 16'h18e5;
                        if (text_on("EDIT            ", 73, 34, x, y)) pixel_data = 16'hffff;
                    end
                end
            end else begin
                // Bottom Action Bar (y: 48..63)
                pixel_data = 16'h0841;
                if (y == 54) pixel_data = 16'h04b4; // dividing separator line

                // Slot 0: ENGINE (x: 2..18, y: 55..63)
                if (x >= 2 && x <= 18 && y >= 55) begin
                    if (x == 2 || x == 18 || y == 55 || y == 63)
                        pixel_data = engine_enabled ? 16'h07e0 : 16'h4208;
                    else if (cursor_x >= 2 && cursor_x <= 18 && cursor_y >= 55 && cursor_y <= 63)
                        pixel_data = 16'h0351;
                    else
                        pixel_data = engine_enabled ? 16'h03e0 : 16'h18c3;
                    if (text_on("ENG             ", 4, 56, x, y))
                        pixel_data = engine_enabled ? 16'hffff : 16'h7bef;
                end

                // Slot 1: FAN (x: 21..37, y: 55..63)
                if (x >= 21 && x <= 37 && y >= 55) begin
                    if (fan_available) begin
                        if (x == 21 || x == 37 || y == 55 || y == 63)
                            pixel_data = fan_on ? 16'h07ff : 16'h4208;
                        else if (cursor_x >= 21 && cursor_x <= 37 && cursor_y >= 55 && cursor_y <= 63)
                            pixel_data = 16'h0351;
                        else
                            pixel_data = fan_on ? 16'h02ef : 16'h18c3;
                        if (text_on("FAN             ", 23, 56, x, y))
                            pixel_data = fan_on ? 16'hffff : 16'h7bef;
                    end else begin
                        pixel_data = 16'h0421;
                    end
                end

                // Slot 2: ROCKET (x: 40..56, y: 55..63)
                if (x >= 40 && x <= 56 && y >= 55) begin
                    if (rocket_available) begin
                        if (x == 40 || x == 56 || y == 55 || y == 63)
                            pixel_data = rocket_ready ? 16'hffe0 : 16'h4208;
                        else if (cursor_x >= 40 && cursor_x <= 56 && cursor_y >= 55 && cursor_y <= 63)
                            pixel_data = 16'h0351;
                        else
                            pixel_data = rocket_ready ? 16'hfc00 : 16'h18c3;
                        if (text_on("RKT             ", 42, 56, x, y))
                            pixel_data = rocket_ready ? 16'h0000 : 16'h7bef;
                    end else begin
                        pixel_data = 16'h0421;
                    end
                end

                // Slot 3: BALLOON (x: 59..75, y: 55..63)
                if (x >= 59 && x <= 75 && y >= 55) begin
                    if (balloon_available) begin
                        if (x == 59 || x == 75 || y == 55 || y == 63)
                            pixel_data = 16'h7bef;
                        else if (cursor_x >= 59 && cursor_x <= 75 && cursor_y >= 55 && cursor_y <= 63)
                            pixel_data = 16'h0351;
                        else
                            pixel_data = 16'h2945;
                        if (text_on("POP             ", 61, 56, x, y))
                            pixel_data = 16'hffff;
                    end else begin
                        pixel_data = 16'h0421;
                    end
                end

                // Slot 4: BOOST / JUMP (x: 78..93, y: 55..63)
                if (x >= 78 && x <= 93 && y >= 55) begin
                    if (x == 78 || x == 93 || y == 55 || y == 63)
                        pixel_data = boost_active ? 16'hffff : 16'h780f;
                    else if (cursor_x >= 78 && cursor_x <= 93 && cursor_y >= 55 && cursor_y <= 63)
                        pixel_data = 16'h0351;
                    else
                        pixel_data = boost_active ? 16'hf81f : 16'h3010;
                    if (text_on("BST             ", 80, 56, x, y))
                        pixel_data = 16'hffff;
                end
            end
        end else if (game_state == `LP_SUCCESS || game_state == `LP_FAIL) begin
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
