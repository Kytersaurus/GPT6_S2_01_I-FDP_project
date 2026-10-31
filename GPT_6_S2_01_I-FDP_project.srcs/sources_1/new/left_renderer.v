// Owner: Role 4 - Marcus. Left OLED construction/status drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Build view: grid, inventory icons/counts, selection, cursor, dragged part and level button.
// Run view: grid as a damage diagram, run timer and surviving-part count.
// Result view: damage diagram, final time, retry/next guidance and the result reason.
module left_renderer #(parameter EDITOR_CELL_PIXELS = 16) (
    input wire [12:0] pixel_index,
    input wire [6:0] in_x,
    input wire [5:0] in_y,
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
    input wire star_box_collected,
    input wire anim_phase,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"
    wire [6:0] x = (pixel_index != 13'd0) ? (pixel_index % 96) : (in_x === 7'bzzzzzzz ? 7'd0 : in_x);
    wire [5:0] y = (pixel_index != 13'd0) ? (pixel_index / 96) : (in_y === 6'bzzzzzz ? 6'd0 : in_y);

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
    reg [6:0] inventory_top, inventory_content_top, inventory_bottom;
    // Centre the 8 by 8 preview on the same cursor position, clamped to the OLED.
    wire [6:0] drag_left = (cursor_x < 4) ? 7'd0 : (cursor_x > 92) ? 7'd88 : cursor_x - 7'd4;
    wire [6:0] drag_top = (cursor_y < 4) ? 7'd0 : (cursor_y > 60) ? 7'd56 : cursor_y - 7'd4;
    reg [3:0] inventory_number;
    reg [2:0] inventory_part;
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
    integer stars;
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
        input icon_facing_left;
        input [15:0] background;
        begin draw_part_icon = part_sprite_facing(icon_part, icon_x, icon_y, 8, icon_facing_left, 1'b0, background); end
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
        .x(x), .y({1'b0, y}), .pos_x(grid_left), .pos_y(grid_top),
        .width_x(grid_size), .length_y(grid_size), .is_in_square(grid_pixel)
    );
    seven_seg_oled u_seconds_tens (
        .x(x), .y({1'b0, y}), .pos_x(7'd56), .pos_y(7'd6), .number(seconds_tens),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(seconds_tens_pixel)
    );
    seven_seg_oled u_seconds (
        .x(x), .y({1'b0, y}), .pos_x(7'd68), .pos_y(7'd6), .number(seconds_ones),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(seconds_pixel)
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
            if (text_on("S               ", 7'd82, 6'd19, x, y)) pixel_data = 16'h07ff;
            if (in_result) begin
                stars = 1 + (star_box_collected ? 1 : 0) + ((run_seconds <= 30 && remaining_parts >= 2) ? 1 : 0);
                  if (game_state == `LP_SUCCESS) begin
                      if (stars >= 1 && ((x>=57 && x<=61 && y==24) || (x==59 && y>=22 && y<=26) || ((x==58||x==60)&&(y==23||y==25)))) pixel_data = 16'hffe0;
                      if (stars >= 2 && ((x>=67 && x<=71 && y==24) || (x==69 && y>=22 && y<=26) || ((x==68||x==70)&&(y==23||y==25)))) pixel_data = 16'hffe0;
                      if (stars >= 3 && ((x>=77 && x<=81 && y==24) || (x==79 && y>=22 && y<=26) || ((x==78||x==80)&&(y==23||y==25)))) pixel_data = 16'hffe0;
                  end
                  if (text_on("C RETRY         ", 54, 32, x, y)) pixel_data = 16'hffff;
                if (text_on(game_state == `LP_SUCCESS ? "U NEXT          " : "U EDIT          ", 54, 42, x, y))
                    pixel_data = 16'hffe0;
            end else if (number_pixel || (remaining_parts >= 10 && tens_pixel)) pixel_data = 16'hffff;
        end else if (x >= 56 && x < 92 && y >= 4 && y < 54) begin
            pixel_data = 16'h18c3;
            if (selected_part == inventory_part &&
                (x == 56 || x == 91 || y == inventory_top || y == inventory_bottom)) pixel_data = 16'hffe0;
            pixel_data = draw_part_icon(inventory_part, x-60, y-inventory_content_top,
                                        selected_part == inventory_part && selected_left, pixel_data);
            if (inventory_number_pixel) pixel_data = (inventory_number == 0) ? 16'hf800 : 16'hffff;
        end
        if (in_build && inventory_page==1 && x>=56 && x<92 && y==28) pixel_data=16'h7bef;
        if (in_build && x>=72 && x<79 && y>=inventory_content_top+1 && y<inventory_content_top+8 &&
            (inventory_part == `LP_PART_ENGINE || inventory_part == `LP_PART_BOOSTER ||
             inventory_part == `LP_PART_FAN || inventory_part == `LP_PART_BALLOON)) begin
            // Show the current facing for engine, rocket and fan; balloons point up.
            if (text_on(inventory_part==`LP_PART_BALLOON ? "^               " :
                        selected_left ? "<               " : ">               ",72,inventory_content_top+1,x,y)) pixel_data=16'h07ff;
        end
        if (in_result || in_build) begin
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


