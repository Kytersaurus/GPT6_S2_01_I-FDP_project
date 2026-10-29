// Owner: Role 4 - Marcus. Left OLED construction/status drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Build view: grid, inventory icons/counts, selection, cursor, dragged part and level button.
// Run view: grid as a damage diagram, run timer and surviving-part count.
// Result view: damage diagram, final time, retry/next guidance and the result reason.
module left_renderer #(parameter EDITOR_CELL_PIXELS = 16) (
    input wire [12:0] pixel_index,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] build_frames, build_facing_left,
    input wire selected_left,
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
    input wire anim_phase,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"

    wire [6:0] x = pixel_index % 96;
    wire [6:0] y = pixel_index / 96;
    // BUILD keeps the detailed 16-pixel grid. RUN uses a compact 12-pixel diagram.
    wire compact_run = (game_state == `LP_RUN);
    wire [6:0] cell_pixels = compact_run ? 7'd12 : EDITOR_CELL_PIXELS;
    wire [6:0] grid_left = 7'd4;
    wire [6:0] grid_top = compact_run ? 7'd12 : 7'd4;
    wire [6:0] grid_size = cell_pixels * 3;
    wire grid_pixel, number_pixel, tens_pixel, seconds_pixel, seconds_tens_pixel;
    wire inventory_number_pixel;
    wire in_build = (game_state == `LP_BUILD);
    wire in_result = (game_state == `LP_SUCCESS || game_state == `LP_FAIL);
    reg [6:0] inventory_top;
    // Centre the 8 by 8 preview on the same cursor position, clamped to the OLED.
    wire [6:0] drag_left = (cursor_x < 4) ? 7'd0 : (cursor_x > 92) ? 7'd88 : cursor_x - 7'd4;
    wire [6:0] drag_top = (cursor_y < 4) ? 7'd0 : (cursor_y > 60) ? 7'd56 : cursor_y - 7'd4;
    reg [3:0] inventory_number;
    reg [2:0] inventory_part;
    reg [4:0] remaining_parts;
    wire [3:0] ones = remaining_parts % 10;
    wire [3:0] tens = remaining_parts / 10;
    wire [3:0] seconds_ones = run_seconds % 10;
    wire [3:0] seconds_tens = run_seconds / 10;
    integer index, cell_index, cell_x, cell_y;
    reg [2:0] part;
    reg [127:0] message;
    reg [15:0] message_colour;
    reg [7:0] letter;
    reg [34:0] letter_bits;
    integer text_column, text_row;
    wire level_button_pixel = x >= `LP_LEVEL_BUTTON_X && x < `LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W &&
                              y >= `LP_LEVEL_BUTTON_Y && y < `LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H;
    wire boost_button_pixel = x >= `LP_BOOST_BUTTON_X && x < `LP_BOOST_BUTTON_X+`LP_BOOST_BUTTON_W &&
                              y >= `LP_BOOST_BUTTON_Y && y < `LP_BOOST_BUTTON_Y+`LP_BOOST_BUTTON_H;

    // Inventory and drag preview use the same sprites as the grid and the right OLED.
    function [15:0] draw_part_icon;
        input [2:0] icon_part;
        input integer icon_x, icon_y;
        input [15:0] background;
        begin draw_part_icon = part_sprite_facing(icon_part, icon_x, icon_y, 8, 1'b0, 1'b0, background); end
    endfunction

    `include "ui_font.vh"

    always @* begin
        message_colour = 16'hf800;
        case (feedback_code)
            `LP_FEEDBACK_PLACED: begin message = "PLACED          "; message_colour = 16'h07e0; end
            `LP_FEEDBACK_REMOVED: begin message = "REMOVED         "; message_colour = 16'h07e0; end
            `LP_FEEDBACK_NO_STOCK: message = "NO STOCK        ";
            `LP_FEEDBACK_NEED_FRAME: message = "NEED FRAME      ";
            `LP_FEEDBACK_FRAME_ABOVE: message = "FRAME UP/DOWN   ";
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
        letter = message >> ((15-x/6)*8);
        letter_bits = letter_pixels(letter);
        text_column = x%6; text_row = y-56;
    end

    square u_grid_box (
        .x(x), .y(y), .pos_x(grid_left), .pos_y(grid_top),
        .width_x(grid_size), .length_y(grid_size), .is_in_square(grid_pixel)
    );
    seven_seg_oled u_seconds_tens (
        .x(x), .y(y), .pos_x(7'd56), .pos_y(7'd6), .number(seconds_tens),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(seconds_tens_pixel)
    );
    seven_seg_oled u_seconds (
        .x(x), .y(y), .pos_x(7'd68), .pos_y(7'd6), .number(seconds_ones),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(seconds_pixel)
    );
    seven_seg_oled u_part_count (
        .x(x), .y(y), .pos_x(7'd68), .pos_y(7'd36), .number(ones),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(number_pixel)
    );
    seven_seg_oled u_part_count_tens (
        .x(x), .y(y), .pos_x(7'd56), .pos_y(7'd36), .number(tens),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(tens_pixel)
    );
    seven_seg_oled u_inventory_number (
        .x(x), .y(y), .pos_x(7'd82), .pos_y(inventory_top+7'd1), .number(inventory_number),
        .line_thickness(7'd1), .height(7'd8), .width(7'd5), .isDrawn(inventory_number_pixel)
    );
    always @* begin
        // Fixed row boundaries avoid dividing and multiplying the pixel position by ten.
        inventory_number = frames_left; inventory_part = `LP_PART_FRAME; inventory_top = 4;
        if (y >= 14 && y < 24) begin
            inventory_number = pigs_left; inventory_part = `LP_PART_PIG; inventory_top = 14;
        end else if (y >= 24 && y < 34) begin
            inventory_number = wheels_left; inventory_part = `LP_PART_WHEEL; inventory_top = 24;
        end else if (y >= 34 && y < 44) begin
            inventory_number = engines_left; inventory_part = `LP_PART_ENGINE; inventory_top = 34;
        end else if (y >= 44 && y < 54) begin
            inventory_number = balloons_left; inventory_part = `LP_PART_BALLOON; inventory_top = 44;
        end
        if (inventory_page!=0) begin
            inventory_top=4;
            inventory_part=inventory_page==1 ? `LP_PART_BOOSTER : `LP_PART_FAN;
            inventory_number=inventory_page==1 ? rockets_left : fans_left;
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
        if (grid_pixel) begin
            cell_index = ((y-grid_top)/cell_pixels)*3 + (x-grid_left)/cell_pixels;
            cell_x = (x-grid_left)%cell_pixels;
            cell_y = (y-grid_top)%cell_pixels;
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
                    pixel_data = part_sprite_facing(part, cell_x, cell_y, compact_run ? 12 : 16, build_facing_left[cell_index], anim_phase, pixel_data);
            end
            if (feedback_code != `LP_FEEDBACK_NONE && feedback_cell < 9 &&
                cell_index == feedback_cell &&
                (cell_x == 0 || cell_y == 0 || cell_x == cell_pixels-1 || cell_y == cell_pixels-1) &&
                in_build) pixel_data = message_colour;
        end
        if (!in_build) begin
            // Run time in seconds, then surviving parts during RUN or guidance after a result.
            if (seconds_pixel || (run_seconds >= 10 && seconds_tens_pixel)) pixel_data = 16'h07ff;
            if (text_on("S               ", 82, 19, x, y)) pixel_data = 16'h07ff;
            if (in_result) begin
                if (text_on("C RETRY         ", 54, 32, x, y)) pixel_data = 16'hffff;
                if (text_on(game_state == `LP_SUCCESS ? "U NEXT          " : "U EDIT          ", 54, 42, x, y))
                    pixel_data = 16'hffe0;
            end else if (number_pixel || (remaining_parts >= 10 && tens_pixel)) pixel_data = 16'hffff;
        end else if (x >= 56 && x < 92 && y >= 4 && y < 54) begin
            pixel_data = 16'h18c3;
            if (selected_part == inventory_part &&
                (x == 56 || x == 91 || y == inventory_top || y == inventory_top+9)) pixel_data = 16'hffe0;
            pixel_data = draw_part_icon(inventory_part, x-60, y-inventory_top-1, pixel_data);
            if (inventory_number_pixel) pixel_data = (inventory_number == 0) ? 16'hf800 : 16'hffff;
        end
        if (in_build && x>=56 && x<92 && y<54 &&
            (inventory_page!=0 && y>=14)) pixel_data=16'h0841;
        if (in_build && x>=72 && x<79 && y>=inventory_top+2 && y<inventory_top+9 &&
            ((inventory_page==0 && y>=34) || (inventory_page==1 && y<14))) begin
            // Balloon always points up. Engine/rocket show the chosen facing before the count.
            if (text_on(inventory_part==`LP_PART_BALLOON ? "^               " :
                        selected_left ? "<               " : ">               ",72,inventory_top+2,x,y)) pixel_data=16'h07ff;
        end
        if (in_result || in_build) begin
            if (y >= 56 && y < 63) begin
                pixel_data = 16'h0841;
                if (text_column < 5 && letter_bits[34-(text_row*5+text_column)]) pixel_data = message_colour;
            end
            if (in_build && level_button_pixel) begin
                pixel_data = 16'h0010;
                if (x == `LP_LEVEL_BUTTON_X || x == `LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W-1 ||
                    y == `LP_LEVEL_BUTTON_Y || y == `LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H-1) pixel_data = 16'h7bef;
                else if (text_on(level_index == `LP_LEVEL_FLIGHT ? "L3              " :
                                 level_index == `LP_LEVEL_ARCH ? "L2              " : "L1              ",
                                 `LP_LEVEL_BUTTON_X+1, `LP_LEVEL_BUTTON_Y+1, x, y)) pixel_data = 16'hffff;
            end
        end else begin
            // Runtime indicators: build validity, engine switch, then game stage.
            if (y >= 57 && y < 63 && x >= 4 && x < 16) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
            if (y >= 57 && y < 63 && x >= 20 && x < 32) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
            if (y >= 58 && y < 62 && x >= 36 && x < 36+game_state*6) pixel_data = 16'h07ff;
        end
        // Draw a temporary copy above the interface; the builder changes only on release.
        if (in_build && cursor_visible && drag_active) begin
            pixel_data = part_sprite_facing(selected_part,x-drag_left,y-drag_top,8,selected_left,1'b0,pixel_data);

        end
        if (cursor_visible && (in_build || game_state == `LP_RUN) &&
            ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
             (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))) pixel_data = 16'hffff;
    end
endmodule
