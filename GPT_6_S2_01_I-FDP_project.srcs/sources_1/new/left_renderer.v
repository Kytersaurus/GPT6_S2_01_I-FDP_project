// Owner: Role 4 - Marcus. Left OLED construction/status drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Build view: grid, inventory icons/counts, selection, cursor, dragged part and level button.
// Run view: grid as a damage diagram and surviving-part count.
// Result view: damage diagram, retry/next guidance and the result reason.
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
    input tri0 inv_rocket_down,
    input wire [1:0] inventory_page,
    input wire [3:0] rockets_left, fans_left,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input wire build_valid,
    input wire [3:0] build_error,
    input wire [2:0] feedback_code,
    input wire [3:0] feedback_cell,
    input wire engine_enabled,
    input tri0 wheel_moving,
    input wire boost_active,
    input tri0 [8:0] active_fans,
    input tri0 rocket_ready,
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
    // Tutorial-only display state. These inputs are optional for standalone
    // renderer benches (tri0 defaults keep ordinary maps unchanged).
    input tri0 signed [19:0] vehicle_x,
    input tri0 tutorial_tnt_seen,
    input tri0 tutorial_tnt_landed,
    input tri0 tutorial_fan_tested,
    input tri0 tutorial_tnt_intact,
    input wire anim_phase,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"
    wire [5:0] raw_pi_y = ({12'd0, pixel_index} * 25'd2731) >> 18;
    wire [6:0] raw_pi_x = pixel_index - (raw_pi_y << 6) - (raw_pi_y << 5);
    wire [6:0] x = USE_PIXEL_INDEX ? raw_pi_x : in_x;
    wire [5:0] y = USE_PIXEL_INDEX ? raw_pi_y : in_y;

        // BUILD keeps the detailed 16-pixel grid. RUN uses either a compact 12-pixel diagram
        // (for standalone testbenches) or the centered 16-pixel interactive RUN grid at (24, 2).
    wire compact_run = ENABLE_COMPACT_RUN_SPRITES && (game_state == `LP_RUN);
    wire full_run = !ENABLE_COMPACT_RUN_SPRITES && (game_state == `LP_RUN);
    wire [6:0] cell_pixels = compact_run ? 7'd12 : EDITOR_CELL_PIXELS;
    wire [6:0] grid_left = full_run ? 7'd24 : 7'd4;
    wire [6:0] grid_top = compact_run ? 7'd12 : (full_run ? 7'd2 : 7'd4);
    wire [6:0] grid_size = cell_pixels * 3;
    wire grid_pixel;
    wire inventory_number_pixel;
    reg [2:0] inventory_part;
    wire row_engine_left = inv_engine_left | (selected_part == `LP_PART_ENGINE && selected_left);
    wire row_rocket_left = inv_rocket_left | (selected_part == `LP_PART_BOOSTER && selected_left);
    wire row_rocket_down = inv_rocket_down | (selected_part == `LP_PART_BOOSTER && selected_down);
    wire row_fan_left    = inv_fan_left    | (selected_part == `LP_PART_FAN && selected_left);
    wire row_fan_down    = inv_fan_down    | (selected_part == `LP_PART_FAN && selected_down);
    wire inv_row_left = (inventory_part == `LP_PART_ENGINE) ? row_engine_left :
                        (inventory_part == `LP_PART_BOOSTER) ? row_rocket_left :
                        (inventory_part == `LP_PART_FAN) ? row_fan_left : 1'b0;
    wire inv_row_down = (inventory_part == `LP_PART_FAN) ? row_fan_down :
                        (inventory_part == `LP_PART_BOOSTER) ? row_rocket_down : 1'b0;

    wire in_build = (game_state == `LP_BUILD);
    wire has_placed_tnt = (build_grid[2:0] == `LP_PART_FRAME) || (build_grid[5:3] == `LP_PART_FRAME) || (build_grid[8:6] == `LP_PART_FRAME) ||
                          (build_grid[11:9] == `LP_PART_FRAME) || (build_grid[14:12] == `LP_PART_FRAME) || (build_grid[17:15] == `LP_PART_FRAME) ||
                          (build_grid[20:18] == `LP_PART_FRAME) || (build_grid[23:21] == `LP_PART_FRAME) || (build_grid[26:24] == `LP_PART_FRAME);
    wire [3:0] tnts_left = has_placed_tnt ? 4'd0 : 4'd1;
    reg [6:0] inventory_top, inventory_content_top, inventory_bottom;
    // Centre the 8 by 8 preview on the same cursor position, clamped to the OLED.
    wire [6:0] drag_left = (cursor_x < 4) ? 7'd0 : (cursor_x > 92) ? 7'd88 : cursor_x - 7'd4;
    wire [6:0] drag_top = (cursor_y < 4) ? 7'd0 : (cursor_y > 60) ? 7'd56 : cursor_y - 7'd4;
    reg [3:0] inventory_number;
    reg [3:0] cell_index, cell_x, cell_y;
    reg [5:0] grid_dx, grid_dy;
    reg [1:0] grid_col, grid_row;
    reg [2:0] part;
    reg part_anim, part_dim;
    reg [15:0] spr_pixel;
    reg cell_hovered;
    reg [127:0] message;
    reg [15:0] message_colour;
    reg [7:0] letter, arrow_letter;
    reg [34:0] letter_bits;
    reg [2:0] text_column, text_row;
    reg [3:0] text_char_idx;
    wire [6:0] message_column = x - ((text_char_idx << 2) + (text_char_idx << 1));
    wire [6:0] arrow_column = x - 7'd72;
    wire [6:0] arrow_row = y - inventory_content_top - 7'd1;
    wire [5:0] message_row = y - 6'd56;
    wire text_lit = (text_column < 3'd5) && letter_bits[34 - (text_row * 5 + text_column)];
    // Blink the exact tile needed for each tutorial action:
    // engine = cell 3, rocket = cell 1, fan = cell 7.
    wire [3:0] tutorial_target_cell =
        (level_index != `LP_LEVEL_TUTORIAL || !full_run) ? 4'd15 :
        (!engine_enabled && $signed(vehicle_x) < 20'sd10240) ? 4'd3 :
        (tutorial_tnt_seen && tutorial_tnt_intact && !tutorial_tnt_landed &&
         rocket_ready && $signed(vehicle_x) >= 20'sd22528 &&
         $signed(vehicle_x) < 20'sd36864) ? 4'd1 :
        // After the guided rocket has fired, rocket_ready is low. That is a
        // more reliable phase marker than the TNT mask because the tutorial's
        // safety corridor may deliberately leave the crate intact.
        (tutorial_tnt_seen && !tutorial_fan_tested && !rocket_ready &&
         $signed(vehicle_x) >= 20'sd49152 && $signed(vehicle_x) < 20'sd55296) ? 4'd7 :
        4'd15;

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
                else if (game_state == `LP_BUILD && level_index == `LP_LEVEL_TUTORIAL) begin
                    message = "CLICK GO TO PLAY"; message_colour = 16'hffe0;
                end
                else if (build_valid) begin message = "READY           "; message_colour = 16'h07e0; end
                else case (build_error)
                    `LP_BUILD_ERR_PIG: message = "ADD PIG         ";
                    `LP_BUILD_ERR_INVENTORY: message = "CHECK STOCK     ";
                    default: message = "CHECK SUPPORT   ";
                endcase
            end
        endcase
        // The facing arrow shows the part's direction: engine, rocket and fan; balloons point up.
        case (inventory_part)
            `LP_PART_BALLOON: arrow_letter = "^";
            `LP_PART_FAN: begin
                if (row_fan_down) arrow_letter = "v";
                else arrow_letter = row_fan_left ? "<" : ">";
            end
            `LP_PART_BOOSTER: begin
                if (row_rocket_down) arrow_letter = row_rocket_left ? "v" : "^";
                else arrow_letter = row_rocket_left ? "<" : ">";
            end
            default: arrow_letter = row_engine_left ? "<" : ">";
        endcase
        // Six pixels per character: five drawing columns, then a blank column.
        text_char_idx = ({9'd0, x} * 16'd43) >> 8;
        // Inventory arrows end above the status message's rows, so both share one font lookup.
        if (y < 6'd55) begin
            letter = arrow_letter;
            text_column = (arrow_column < 7'd5) ? arrow_column[2:0] : 3'd5;
            text_row = arrow_row[2:0];
        end else begin
            letter = message >> ((15 - text_char_idx) * 8);
            text_column = message_column[2:0];
            text_row = message_row[2:0];
        end
        letter_bits = letter_pixels(letter);
    end

    square u_grid_box (
        .x(x), .y({1'b0, y}), .pos_x(grid_left), .pos_y(grid_top),
        .width_x(grid_size), .length_y(grid_size), .is_in_square(grid_pixel)
    );
    seven_seg_oled u_inventory_number (
        .x(x), .y({1'b0, y}), .pos_x(7'd82), .pos_y(inventory_content_top), .number(inventory_number),
        .line_thickness(7'd1), .height(7'd8), .width(7'd5), .isDrawn(inventory_number_pixel)
    );
    always @* begin
        // Fixed row boundaries avoid dividing and multiplying the pixel position by ten.
        // Both inventory pages use uniform 10-pixel rows (Row 0: y=4..13, Row 1: y=14..23, etc.).
        inventory_top = 4; inventory_content_top = 5; inventory_bottom = 13;
        inventory_number = (inventory_page == 1) ? rockets_left : frames_left;
        inventory_part   = (inventory_page == 1) ? `LP_PART_BOOSTER : `LP_PART_FRAME;
        if (y >= 14 && y < 24) begin
            inventory_top = 14; inventory_content_top = 15; inventory_bottom = 23;
            inventory_number = (inventory_page == 1) ? fans_left : pigs_left;
            inventory_part   = (inventory_page == 1) ? `LP_PART_FAN : `LP_PART_PIG;
        end else if (y >= 24 && y < 34) begin
            inventory_top = 24; inventory_content_top = 25; inventory_bottom = 33;
            inventory_number = (inventory_page == 1) ? tnts_left : wheels_left;
            inventory_part   = (inventory_page == 1) ? `LP_PART_FRAME : `LP_PART_WHEEL;
        end else if (y >= 34 && y < 44) begin
            inventory_top = 34; inventory_content_top = 35; inventory_bottom = 43;
            inventory_number = engines_left;
            inventory_part   = (inventory_page == 1) ? `LP_PART_EMPTY : `LP_PART_ENGINE;
        end else if (y >= 44 && y < 54) begin
            inventory_top = 44; inventory_content_top = 45; inventory_bottom = 53;
            inventory_number = balloons_left;
            inventory_part   = (inventory_page == 1) ? `LP_PART_EMPTY : `LP_PART_BALLOON;
        end
    end

    always @* begin
        cell_index = 0; cell_x = 0; cell_y = 0;
        part = 0; part_anim = anim_phase; part_dim = 1'b0; spr_pixel = 16'h0841; cell_hovered = 1'b0;
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
                grid_dx = x - grid_left;
                grid_dy = y - grid_top;
                cell_index = {grid_dy[5:4], 1'b0} + grid_dy[5:4] + grid_dx[5:4];
                cell_x = grid_dx[3:0];
                cell_y = grid_dy[3:0];
            end
            // Shift the selected cell's three bits into the bottom of the vector.
            part = build_grid >> (cell_index*3);
            cell_hovered = cursor_visible && cursor_x >= grid_left && cursor_x < grid_left + grid_size &&
                           cursor_y >= grid_top && cursor_y < grid_top + grid_size &&
                           grid_dx[5:4] == ((cursor_x - grid_left) >> 4) &&
                           grid_dy[5:4] == ((cursor_y - grid_top) >> 4);
            if (cell_x == 0 || cell_y == 0 || (full_run && (cell_x == 15 || cell_y == 15)) || x == grid_left+grid_size-1 || y == grid_top+grid_size-1) begin
                if (in_build && cell_hovered)
                    pixel_data = 16'h07ff;
                else if (full_run) begin
                    if (tutorial_target_cell < 4'd9 && cell_index == tutorial_target_cell && anim_phase)
                        pixel_data = 16'hffe0;
                    else if (intact_mask[cell_index] &&
                        ((part == `LP_PART_ENGINE && engine_enabled) ||
                         (part == `LP_PART_FAN && active_fans[cell_index]) ||
                         (part == `LP_PART_BOOSTER && boost_active)))
                        pixel_data = 16'h07e0;
                    else if (cell_hovered)
                        pixel_data = 16'hffe0;
                    else
                        pixel_data = 16'h4208;
                end else
                    pixel_data = 16'h7bef;
            end else begin
                if (in_build && cell_hovered) begin
                    if (cell_x == cell_pixels-1 || cell_y == cell_pixels-1) pixel_data = 16'h07ff;
                    else if (!drag_active) pixel_data = 16'h0351;
                end else if (full_run && cell_hovered) begin
                    pixel_data = 16'h0351;
                end
                // Damage diagram: a dim red cross under any destroyed part; survivors cover it.
                if (!in_build && cell_x >= 3 && cell_x < cell_pixels-3 && (cell_x == cell_y || cell_x+cell_y == cell_pixels-1) &&
                    ((part != `LP_PART_EMPTY && !intact_mask[cell_index]) ||
                     (build_frames[cell_index] && !frame_intact_mask[cell_index]))) pixel_data = 16'h8000;
                // Full-resolution 16-pixel sprites (or compact 12-pixel sprites when ENABLE_COMPACT_RUN_SPRITES=1).
                if (frame_intact_mask[cell_index] && !(in_build && drag_active && drag_from_grid && selected_part==`LP_PART_FRAME && !selected_down && drag_source == cell_index))
                    pixel_data = compact_run ? part_sprite12(`LP_PART_FRAME, cell_x, cell_y, 1'b0, pixel_data) : part_sprite16(`LP_PART_FRAME, cell_x, cell_y, 1'b0, pixel_data);
                if (intact_mask[cell_index] && !(in_build && drag_active && drag_from_grid && drag_source == cell_index)) begin
                    if (full_run) begin
                        if (part == `LP_PART_ENGINE) begin
                            part_anim = engine_enabled ? anim_phase : 1'b0;
                            part_dim  = !engine_enabled;
                        end else if (part == `LP_PART_FAN) begin
                            part_anim = active_fans[cell_index] ? anim_phase : 1'b0;
                            part_dim  = !active_fans[cell_index];
                        end else if (part == `LP_PART_BOOSTER) begin
                            part_anim = boost_active ? anim_phase : 1'b0;
                            part_dim  = !(boost_active || rocket_ready);
                        end else if (part == `LP_PART_WHEEL) begin
                            part_anim = wheel_moving ? anim_phase : 1'b0;
                        end
                    end
                    if (part == `LP_PART_FRAME)
                        spr_pixel = compact_run ? tnt_sprite(cell_x - 2, cell_y - 2, pixel_data) : tnt_sprite12(cell_x - 2, cell_y - 2, pixel_data);
                    else
                        spr_pixel = part_sprite_mounted(part, cell_x, cell_y, compact_run ? 12 : 16, build_facing_left[cell_index], build_facing_down[cell_index], frame_intact_mask, cell_index, part_anim, pixel_data);
                    pixel_data = (part_dim && spr_pixel != pixel_data) ? ((spr_pixel & 16'hf7de) >> 1) : spr_pixel;
                end
            end
            if (feedback_code != `LP_FEEDBACK_NONE && feedback_cell < 9 &&
                cell_index == feedback_cell &&
                (cell_x == 0 || cell_y == 0 || cell_x == cell_pixels-1 || cell_y == cell_pixels-1) &&
                in_build) pixel_data = message_colour;
        end
        if (in_build && x >= 56 && x < 92 && y >= 4 && (inventory_page == 1 ? y < 34 : y < 54)) begin
            if (cursor_visible && cursor_x >= 56 && cursor_x < 92 && cursor_y >= inventory_top && cursor_y <= inventory_bottom)
                pixel_data = 16'h0351;
            else
                pixel_data = 16'h18c3;
            if ((x == 56 || x == 91 || y == inventory_top || y == inventory_bottom)) begin
                if (selected_part == inventory_part && (inventory_part != `LP_PART_FRAME || selected_down == (inventory_page == 1))) pixel_data = 16'hffe0;
                else if (cursor_visible && cursor_x >= 56 && cursor_x < 92 && cursor_y >= inventory_top && cursor_y <= inventory_bottom)
                    pixel_data = 16'h07ff;
            end
            if (inventory_page == 1 && y >= 24)
                pixel_data = tnt_sprite(x-60, y-inventory_content_top, pixel_data);
            else
                pixel_data = draw_part_icon(inventory_part, x-60, y-inventory_content_top,
                                            inv_row_left, inv_row_down, pixel_data);
            if (inventory_number_pixel) pixel_data = (inventory_number == 0) ? 16'hf800 : 16'hffff;
        end
        if (in_build && x>=72 && x<79 && y>=inventory_content_top+1 && y<inventory_content_top+8 &&
            (inventory_part == `LP_PART_ENGINE || inventory_part == `LP_PART_BOOSTER ||
             inventory_part == `LP_PART_FAN || inventory_part == `LP_PART_BALLOON)) begin
            if (text_lit) pixel_data=16'h07ff;
        end
        if (in_build) begin
            if (y >= 56 && y < 63 && !(feedback_code == `LP_FEEDBACK_NONE && x >= `LP_LEVEL_BUTTON_X)) begin
                pixel_data = 16'h0841;
                if (text_lit) pixel_data = message_colour;
            end
        end else if (compact_run) begin
            // Runtime indicators for standalone compact_run testbenches.
            if (y >= 57 && y < 63 && x >= 4 && x < 16) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
            if (y >= 57 && y < 63 && x >= 20 && x < 32) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
            if (y >= 58 && y < 62 && x >= 36 && x < 36+game_state*6) pixel_data = 16'h07ff;
        end
        // Draw a temporary copy above the interface; the builder changes only on release.
        if (in_build && cursor_visible && drag_active) begin
            if (selected_part == `LP_PART_FRAME && selected_down)
                pixel_data = tnt_sprite(x-drag_left, y-drag_top, pixel_data);
            else
                pixel_data = part_sprite_facing_dir(selected_part,x-drag_left,y-drag_top,8,selected_left,selected_down,1'b0,pixel_data);
        end
        if (cursor_visible && (in_build || compact_run) &&
            ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
             (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))) pixel_data = 16'hffff;
    end
endmodule
