// Owner: Role 4 - Marcus. Left OLED construction/status drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Build view: grid, inventory icons/counts, selection, cursor, dragged part and level button.
// Run view: grid as a damage diagram, run timer and surviving-part count.
// Result view: damage diagram, final time, retry/next guidance and the result reason.
module left_renderer #(
    parameter EDITOR_CELL_PIXELS = 16,
    parameter USE_PIXEL_INDEX = 1,
    parameter ENABLE_COMPACT_RUN_SPRITES = 1
) (
    input wire [12:0] pixel_index,
    input wire [6:0] in_x,
    input wire [5:0] in_y,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] build_frames, build_facing_left,
    input tri0 [8:0] build_facing_down,
    input wire selected_left,
    input tri0 selected_down,
    input tri0 inv_engine_left,
    input tri0 inv_fan_left,
    input tri0 inv_fan_down,
    input tri0 inv_rocket_left,
    input wire [1:0] inventory_page,
    input wire [3:0] rockets_left, fans_left,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input wire build_valid,
    input wire [3:0] build_error,
    input wire [2:0] feedback_code,
    input wire [3:0] feedback_cell,
    input wire engine_enabled,
    input wire boost_active,
    input wire [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left,
    input wire [2:0] selected_part,
    input wire drag_active,
    input wire drag_from_grid,
    input wire [3:0] drag_source,
    input wire [2:0] drag_contents,
    input wire [6:0] cursor_x, cursor_y,
    input wire cursor_visible,
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    input wire [1:0] fail_reason,
    input wire [7:0] run_seconds,
    input wire star_box_collected,
    input wire anim_phase,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"
    wire [5:0] raw_pi_y = ({12'd0, pixel_index} * 25'd2731) >> 18;
    wire [6:0] raw_pi_x = pixel_index - (raw_pi_y << 6) - (raw_pi_y << 5);
    wire [6:0] x = USE_PIXEL_INDEX ? raw_pi_x : in_x;
    wire [5:0] y = USE_PIXEL_INDEX ? raw_pi_y : in_y;

        // BUILD keeps the detailed 16-pixel grid. RUN uses a compact 12-pixel diagram.
    wire compact_run = ENABLE_COMPACT_RUN_SPRITES && (game_state == `LP_RUN);
    wire [6:0] cell_pixels = compact_run ? 7'd12 : EDITOR_CELL_PIXELS;
    wire [6:0] grid_left = 7'd4;
    wire [6:0] grid_top = compact_run ? 7'd12 : 7'd4;
    wire [6:0] grid_size = cell_pixels * 3;
    wire grid_pixel, number_pixel, tens_pixel, seconds_pixel, seconds_tens_pixel;
    wire inventory_number_pixel;
    reg [2:0] inventory_part;
    wire row_engine_left = inv_engine_left | (selected_part == `LP_PART_ENGINE && selected_left);
    wire row_rocket_left = inv_rocket_left | (selected_part == `LP_PART_BOOSTER && selected_left);
    wire row_fan_left    = inv_fan_left    | (selected_part == `LP_PART_FAN && selected_left);
    wire row_fan_down    = inv_fan_down    | (selected_part == `LP_PART_FAN && selected_down);
    wire inv_row_left = (inventory_part == `LP_PART_ENGINE) ? row_engine_left :
                        (inventory_part == `LP_PART_BOOSTER) ? row_rocket_left :
                        (inventory_part == `LP_PART_FAN) ? row_fan_left : 1'b0;
    wire inv_row_down = (inventory_part == `LP_PART_FAN) ? row_fan_down : 1'b0;

    wire in_build = (game_state == `LP_BUILD);
    wire in_result = (game_state == `LP_SUCCESS || game_state == `LP_FAIL);
    wire [6:0] sec_pos_y = in_result ? 7'd4 : 7'd6;
    wire [6:0] sec_height = in_result ? 7'd12 : 7'd20;
    wire [6:0] sec_width = in_result ? 7'd7 : 7'd10;
    wire [6:0] sec_thick = in_result ? 7'd1 : 7'd2;
    wire [6:0] sec_tens_x = in_result ? 7'd58 : 7'd56;
    wire [6:0] sec_ones_x = in_result ? 7'd68 : 7'd68;
    reg [6:0] inventory_top, inventory_content_top, inventory_bottom;
    // Centre the 8 by 8 preview on the same cursor position, clamped to the OLED.
    wire [6:0] drag_left = (cursor_x < 4) ? 7'd0 : (cursor_x > 92) ? 7'd88 : cursor_x - 7'd4;
    wire [6:0] drag_top = (cursor_y < 4) ? 7'd0 : (cursor_y > 60) ? 7'd56 : cursor_y - 7'd4;
    reg [3:0] inventory_number;
    reg [4:0] remaining_parts;
    wire [3:0] tens = (remaining_parts >= 10) ? 1 : 0;
    wire [3:0] ones = (remaining_parts >= 10) ? remaining_parts - 10 : remaining_parts;
    reg [3:0] seconds_tens;
    reg [3:0] seconds_ones;
    reg [7:0] tmp_s;
    always @* begin
        seconds_tens = 0;
        tmp_s = run_seconds;
        if (tmp_s >= 90) begin seconds_tens = 9; tmp_s = tmp_s - 90; end
        else if (tmp_s >= 80) begin seconds_tens = 8; tmp_s = tmp_s - 80; end
        else if (tmp_s >= 70) begin seconds_tens = 7; tmp_s = tmp_s - 70; end
        else if (tmp_s >= 60) begin seconds_tens = 6; tmp_s = tmp_s - 60; end
        else if (tmp_s >= 50) begin seconds_tens = 5; tmp_s = tmp_s - 50; end
        else if (tmp_s >= 40) begin seconds_tens = 4; tmp_s = tmp_s - 40; end
        else if (tmp_s >= 30) begin seconds_tens = 3; tmp_s = tmp_s - 30; end
        else if (tmp_s >= 20) begin seconds_tens = 2; tmp_s = tmp_s - 20; end
        else if (tmp_s >= 10) begin seconds_tens = 1; tmp_s = tmp_s - 10; end
        seconds_ones = tmp_s[3:0];
    end
    integer index, cell_index, cell_x, cell_y;
    reg [5:0] grid_dx, grid_dy;
    reg [1:0] grid_col, grid_row;
    integer stars;
    reg [2:0] part;
    reg [127:0] message;
    reg [15:0] message_colour;
    reg [7:0] letter;
    reg [34:0] letter_bits;
    integer text_column, text_row;
    reg [3:0] text_char_idx;
    wire level_button_pixel = x >= `LP_LEVEL_BUTTON_X && x < `LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W &&
                              y >= `LP_LEVEL_BUTTON_Y && y < `LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H;
    wire boost_button_pixel = x >= `LP_BOOST_BUTTON_X && x < `LP_BOOST_BUTTON_X+`LP_BOOST_BUTTON_W &&
                              y >= `LP_BOOST_BUTTON_Y && y < `LP_BOOST_BUTTON_Y+`LP_BOOST_BUTTON_H;

    // Inventory and drag preview use the same sprites as the grid and the right OLED.
    function [15:0] draw_part_icon;
        input [2:0] icon_part;
        input integer icon_x, icon_y;
        input icon_facing_left, icon_facing_down;
        input [15:0] background;
        begin draw_part_icon = part_sprite_facing_dir(icon_part, icon_x, icon_y, 8, icon_facing_left, icon_facing_down, 1'b0, background); end
    endfunction

    `include "ui_font.vh"

    always @* begin
        message_colour = 16'hf800;
        case (feedback_code)
            `LP_FEEDBACK_PLACED: begin message = "PLACED          "; message_colour = 16'h07e0; end
            `LP_FEEDBACK_REMOVED: begin message = "REMOVED         "; message_colour = 16'h07e0; end
            `LP_FEEDBACK_NO_STOCK: message = "NO STOCK        ";
            `LP_FEEDBACK_NEED_FRAME: message = "NEED FRAME      ";
            `LP_FEEDBACK_FRAME_ABOVE: message = "ADJACENT FRAME  ";
            `LP_FEEDBACK_FRAME_BELOW: message = "FRAME BELOW     ";
            `LP_FEEDBACK_OCCUPIED: message = "CELL OCCUPIED   ";
            default: begin
                if (game_state == `LP_SUCCESS) begin message = "LEVEL CLEAR     "; message_colour = 16'h07e0; end
                else if (game_state == `LP_FAIL) case (fail_reason)
                    `LP_FAIL_PIG: message = "PIG LOST        ";
                    `LP_FAIL_HAZARD: message = "HAZARD HIT      ";
                    default: message = "OUT OF BOUNDS   ";
                endcase
                else if (build_valid) begin message = "READY           "; message_colour = 16'h07e0; end
                else case (build_error)
                    `LP_BUILD_ERR_PIG: message = "ADD PIG         ";
                    `LP_BUILD_ERR_INVENTORY: message = "CHECK STOCK     ";
                    default: message = "CHECK SUPPORT   ";
                endcase
            end
        endcase
        // Six pixels per character: five drawing columns, then a blank column.
        text_char_idx = ({9'd0, x} * 16'd43) >> 8;
        letter = message >> ((15 - text_char_idx) * 8);
        letter_bits = letter_pixels(letter);
        text_column = x - ((text_char_idx << 2) + (text_char_idx << 1));
        text_row = y - 56;
    end

    square u_grid_box (
        .x(x), .y({1'b0, y}), .pos_x(grid_left), .pos_y(grid_top),
        .width_x(grid_size), .length_y(grid_size), .is_in_square(grid_pixel)
    );
    seven_seg_oled u_seconds_tens (
        .x(x), .y({1'b0, y}), .pos_x(sec_tens_x), .pos_y(sec_pos_y), .number(seconds_tens),
        .line_thickness(sec_thick), .height(sec_height), .width(sec_width), .isDrawn(seconds_tens_pixel)
    );
    seven_seg_oled u_seconds (
        .x(x), .y({1'b0, y}), .pos_x(sec_ones_x), .pos_y(sec_pos_y), .number(seconds_ones),
        .line_thickness(sec_thick), .height(sec_height), .width(sec_width), .isDrawn(seconds_pixel)
    );
    seven_seg_oled u_part_count (
        .x(x), .y({1'b0, y}), .pos_x(7'd68), .pos_y(7'd36), .number(ones),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(number_pixel)
    );
    seven_seg_oled u_part_count_tens (
        .x(x), .y({1'b0, y}), .pos_x(7'd56), .pos_y(7'd36), .number(tens),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(tens_pixel)
    );
    seven_seg_oled u_inventory_number (
        .x(x), .y({1'b0, y}), .pos_x(7'd82), .pos_y(inventory_content_top), .number(inventory_number),
        .line_thickness(7'd1), .height(7'd8), .width(7'd5), .isDrawn(inventory_number_pixel)
    );
    always @* begin
        // Fixed row boundaries avoid dividing and multiplying the pixel position by ten.
        inventory_number = frames_left; inventory_part = `LP_PART_FRAME; inventory_top = 4;
        inventory_content_top = 5; inventory_bottom = 13;
        if (y >= 14 && y < 24) begin
            inventory_number = pigs_left; inventory_part = `LP_PART_PIG; inventory_top = 14; inventory_content_top = 15; inventory_bottom = 23;
        end else if (y >= 24 && y < 34) begin
            inventory_number = wheels_left; inventory_part = `LP_PART_WHEEL; inventory_top = 24; inventory_content_top = 25; inventory_bottom = 33;
        end else if (y >= 34 && y < 44) begin
            inventory_number = engines_left; inventory_part = `LP_PART_ENGINE; inventory_top = 34; inventory_content_top = 35; inventory_bottom = 43;
        end else if (y >= 44 && y < 54) begin
            inventory_number = balloons_left; inventory_part = `LP_PART_BALLOON; inventory_top = 44; inventory_content_top = 45; inventory_bottom = 53;
        end
        if (inventory_page==1) begin
            if (y < 28) begin
                inventory_top=4; inventory_bottom=27; inventory_content_top=12;
                inventory_part=`LP_PART_BOOSTER; inventory_number=rockets_left;
            end else begin
                inventory_top=29; inventory_bottom=53; inventory_content_top=37;
                inventory_part=`LP_PART_FAN; inventory_number=fans_left;
            end
        end
    end

    always @* begin
        remaining_parts = 0;
        for (index = 0; index < 9; index = index + 1) begin
            if (intact_mask[index]) remaining_parts = remaining_parts + 1'b1;
            if (frame_intact_mask[index]) remaining_parts = remaining_parts + 1'b1;
        end
    end

    always @* begin
        cell_index = 0; cell_x = 0; cell_y = 0;
        part = 0;
        pixel_data = 16'h0841;
        grid_dx = 0; grid_dy = 0;
        grid_col = 0; grid_row = 0;
        if (grid_pixel) begin
            if (compact_run) begin
                grid_dx = x - 7'd4;
                grid_dy = y - 7'd12;
                grid_col = (grid_dx < 6'd12) ? 2'd0 : ((grid_dx < 6'd24) ? 2'd1 : 2'd2);
                grid_row = (grid_dy < 6'd12) ? 2'd0 : ((grid_dy < 6'd24) ? 2'd1 : 2'd2);
                cell_index = {grid_row, 1'b0} + grid_row + grid_col;
                cell_x = (grid_col == 2'd0) ? grid_dx : ((grid_col == 2'd1) ? (grid_dx - 6'd12) : (grid_dx - 6'd24));
                cell_y = (grid_row == 2'd0) ? grid_dy : ((grid_row == 2'd1) ? (grid_dy - 6'd12) : (grid_dy - 6'd24));
            end else begin
                grid_dx = x - 7'd4;
                grid_dy = y - 7'd4;
                cell_index = {grid_dy[5:4], 1'b0} + grid_dy[5:4] + grid_dx[5:4];
                cell_x = grid_dx[3:0];
                cell_y = grid_dy[3:0];
            end
            // Shift the selected cell's three bits into the bottom of the vector.
            part = build_grid >> (cell_index*3);
            if (cell_x == 0 || cell_y == 0 || x == grid_left+grid_size-1 || y == grid_top+grid_size-1) pixel_data = 16'h7bef;
            else begin
                // Damage diagram: a dim red cross under any destroyed part; survivors cover it.
                if (!in_build && cell_x >= 3 && cell_x < cell_pixels-3 && (cell_x == cell_y || cell_x+cell_y == cell_pixels-1) &&
                    ((part != `LP_PART_EMPTY && !intact_mask[cell_index]) ||
                     (build_frames[cell_index] && !frame_intact_mask[cell_index]))) pixel_data = 16'h8000;
                // Full-resolution build sprites; RUN uses compact 12-pixel sprites.
                if (frame_intact_mask[cell_index] && !(in_build && drag_active && drag_from_grid && selected_part==`LP_PART_FRAME && drag_source == cell_index))
                    pixel_data = compact_run ? part_sprite12(`LP_PART_FRAME, cell_x, cell_y, 1'b0, pixel_data) : part_sprite16(`LP_PART_FRAME, cell_x, cell_y, 1'b0, pixel_data);
                if (intact_mask[cell_index] && !(in_build && drag_active && drag_from_grid && drag_source == cell_index))
                    pixel_data = part_sprite_facing_dir(part, cell_x, cell_y, compact_run ? 12 : 16, build_facing_left[cell_index], build_facing_down[cell_index], anim_phase, pixel_data);
            end
            if (feedback_code != `LP_FEEDBACK_NONE && feedback_cell < 9 &&
                cell_index == feedback_cell &&
                (cell_x == 0 || cell_y == 0 || cell_x == cell_pixels-1 || cell_y == cell_pixels-1) &&
                in_build) pixel_data = message_colour;
        end
        if (!in_build) begin
            // Run time in seconds, then surviving parts during RUN or guidance after a result.
            if (seconds_pixel || (run_seconds >= 10 && seconds_tens_pixel)) pixel_data = 16'h07ff;
            if (in_result) begin
                if (text_on("S               ", 7'd78, 6'd8, x, y)) pixel_data = 16'h07ff;
                stars = 1 + (star_box_collected ? 1 : 0) + ((run_seconds <= 30 && remaining_parts >= 2) ? 1 : 0);
                // 3 Stars centered at x=59, 71, 83, y=25 (radiant gold fill, amber rim, white glint; unearned = slate/bronze outline)
                if (y >= 22 && y <= 28) begin
                    // Star 1 (cx = 59)
                    if (x >= 56 && x <= 62) begin
                        if ((x >= 59 ? x - 59 : 59 - x) + (y >= 25 ? y - 25 : 25 - y) == 3)
                            pixel_data = (game_state == `LP_SUCCESS && stars >= 1) ? 16'hfed0 : 16'h4208;
                        else if ((x >= 59 ? x - 59 : 59 - x) + (y >= 25 ? y - 25 : 25 - y) < 3) begin
                            if (game_state == `LP_SUCCESS && stars >= 1)
                                pixel_data = (x == 58 && y == 24) ? 16'hffff : 16'hffe0;
                            else
                                pixel_data = 16'h18c3;
                        end
                    end
                    // Star 2 (cx = 71)
                    if (x >= 68 && x <= 74) begin
                        if ((x >= 71 ? x - 71 : 71 - x) + (y >= 25 ? y - 25 : 25 - y) == 3)
                            pixel_data = (game_state == `LP_SUCCESS && stars >= 2) ? 16'hfed0 : 16'h4208;
                        else if ((x >= 71 ? x - 71 : 71 - x) + (y >= 25 ? y - 25 : 25 - y) < 3) begin
                            if (game_state == `LP_SUCCESS && stars >= 2)
                                pixel_data = (x == 70 && y == 24) ? 16'hffff : 16'hffe0;
                            else
                                pixel_data = 16'h18c3;
                        end
                    end
                    // Star 3 (cx = 83)
                    if (x >= 80 && x <= 86) begin
                        if ((x >= 83 ? x - 83 : 83 - x) + (y >= 25 ? y - 25 : 25 - y) == 3)
                            pixel_data = (game_state == `LP_SUCCESS && stars >= 3) ? 16'hfed0 : 16'h4208;
                        else if ((x >= 83 ? x - 83 : 83 - x) + (y >= 25 ? y - 25 : 25 - y) < 3) begin
                            if (game_state == `LP_SUCCESS && stars >= 3)
                                pixel_data = (x == 82 && y == 24) ? 16'hffff : 16'hffe0;
                            else
                                pixel_data = 16'h18c3;
                        end
                    end
                end
            end else begin
                if (text_on("S               ", 7'd82, 6'd19, x, y)) pixel_data = 16'h07ff;
                if (number_pixel || (remaining_parts >= 10 && tens_pixel)) pixel_data = 16'hffff;
            end
        end else if (x >= 56 && x < 92 && y >= 4 && y < 54) begin
            pixel_data = 16'h18c3;
            if (selected_part == inventory_part &&
                (x == 56 || x == 91 || y == inventory_top || y == inventory_bottom)) pixel_data = 16'hffe0;
            pixel_data = draw_part_icon(inventory_part, x-60, y-inventory_content_top,
                                        inv_row_left, inv_row_down, pixel_data);
            if (inventory_number_pixel) pixel_data = (inventory_number == 0) ? 16'hf800 : 16'hffff;
        end
        if (in_build && inventory_page==1 && x>=56 && x<92 && y==28) pixel_data=16'h7bef;
        if (in_build && x>=72 && x<79 && y>=inventory_content_top+1 && y<inventory_content_top+8 &&
            (inventory_part == `LP_PART_ENGINE || inventory_part == `LP_PART_BOOSTER ||
             inventory_part == `LP_PART_FAN || inventory_part == `LP_PART_BALLOON)) begin
            // Show the current facing for engine, rocket and fan; balloons point up.
            if (text_on(inventory_part==`LP_PART_BALLOON ? "^               " :
                        (inventory_part==`LP_PART_FAN) ? (row_fan_down ? "v               " : (row_fan_left ? "<               " : ">               ")) :
                        (inventory_part==`LP_PART_BOOSTER) ? (row_rocket_left ? "<               " : ">               ") :
                        (row_engine_left ? "<               " : ">               "), 72, inventory_content_top+1, x, y)) pixel_data=16'h07ff;
        end
        if (in_build) begin
            if (y >= 56 && y < 63 && !(feedback_code == `LP_FEEDBACK_NONE && x >= `LP_LEVEL_BUTTON_X)) begin
                pixel_data = 16'h0841;
                if (text_column < 5 && letter_bits[34-(text_row*5+text_column)]) pixel_data = message_colour;
            end
            if (in_build && level_button_pixel && feedback_code == `LP_FEEDBACK_NONE) begin
                pixel_data = 16'h0010;
                if (x == `LP_LEVEL_BUTTON_X || x == `LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W-1 ||
                    y == `LP_LEVEL_BUTTON_Y || y == `LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H-1) pixel_data = 16'h7bef;
                else if (text_on(level_index == 3 ? "L4              " : level_index == 2 ? "L3              " :
                                 level_index == 1 ? "L2              " : "L1              ",
                                 `LP_LEVEL_BUTTON_X+1, `LP_LEVEL_BUTTON_Y+1, x, y)) pixel_data = 16'hffff;
            end
        end else if (game_state == `LP_RUN) begin
            // Runtime indicators: build validity, engine switch, then game stage.
            if (y >= 57 && y < 63 && x >= 4 && x < 16) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
            if (y >= 57 && y < 63 && x >= 20 && x < 32) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
            if (y >= 58 && y < 62 && x >= 36 && x < 36+game_state*6) pixel_data = 16'h07ff;
        end
        // Draw a temporary copy above the interface; the builder changes only on release.
        if (in_build && cursor_visible && drag_active) begin
            pixel_data = part_sprite_facing_dir(selected_part,x-drag_left,y-drag_top,8,selected_left,selected_down,1'b0,pixel_data);

        end
        if (cursor_visible && (in_build || game_state == `LP_RUN) &&
            ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
             (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))) pixel_data = 16'hffff;
    end
endmodule


