// Owner: Role 4 - Marcus. Left OLED construction/status drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Build view: grid, inventory icons/counts, selection and mouse cursor.
// Run view: grid, status bars and surviving-part count.
module left_renderer #(parameter EDITOR_CELL_PIXELS = 16) (
    input wire [12:0] pixel_index,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input wire build_valid,
    input wire [3:0] build_error,
    input wire engine_enabled,
    input wire [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left,
    input wire [2:0] selected_part,
    input wire [6:0] cursor_x, cursor_y,
    input wire cursor_visible,
    output reg [15:0] pixel_data
);
    wire [6:0] x = pixel_index % 96;
    wire [6:0] y = pixel_index / 96;
    wire [6:0] grid_size = EDITOR_CELL_PIXELS * 3;
    wire grid_pixel, valid_pixel, engine_pixel, number_pixel, tens_pixel;
    wire inventory_number_pixel;
    wire [2:0] inventory_row = (y >= 4 && y < 54) ? (y-4)/10 : 0;
    wire [6:0] inventory_top = 4 + inventory_row*10;
    reg [3:0] inventory_number;
    reg [2:0] inventory_part;
    reg [4:0] remaining_parts;
    wire [3:0] ones = remaining_parts % 10;
    wire [3:0] tens = remaining_parts / 10;
    integer index, cell_index, cell_x, cell_y, icon_x, icon_y;
    reg [2:0] part;

    square u_grid_box (
        .x(x), .y(y), .pos_x(7'd4), .pos_y(7'd4),
        .width_x(grid_size), .length_y(grid_size), .is_in_square(grid_pixel)
    );
    square u_valid_box (
        .x(x), .y(y), .pos_x(7'd56), .pos_y(7'd6),
        .width_x(7'd36), .length_y(7'd8), .is_in_square(valid_pixel)
    );
    square u_engine_box (
        .x(x), .y(y), .pos_x(7'd56), .pos_y(7'd20),
        .width_x(7'd36), .length_y(7'd8), .is_in_square(engine_pixel)
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
        inventory_number = 0; inventory_part = `LP_PART_EMPTY;
        case (inventory_row)
            0: begin inventory_number = frames_left; inventory_part = `LP_PART_FRAME; end
            1: begin inventory_number = pigs_left; inventory_part = `LP_PART_PIG; end
            2: begin inventory_number = wheels_left; inventory_part = `LP_PART_WHEEL; end
            3: begin inventory_number = engines_left; inventory_part = `LP_PART_ENGINE; end
            4: begin inventory_number = balloons_left; inventory_part = `LP_PART_BALLOON; end
            default: begin end
        endcase
    end

    always @* begin
        remaining_parts = 0;
        for (index = 0; index < 9; index = index + 1) begin
            if (intact_mask[index]) remaining_parts = remaining_parts + 1'b1;
            if (frame_intact_mask[index]) remaining_parts = remaining_parts + 1'b1;
        end
    end

    always @* begin
        cell_index = 0; cell_x = 0; cell_y = 0; icon_x = 0; icon_y = 0;
        part = 0;
        pixel_data = 16'h0841;
        if (grid_pixel) begin
            cell_index = ((y-4)/EDITOR_CELL_PIXELS)*3 + (x-4)/EDITOR_CELL_PIXELS;
            cell_x = (x-4)%EDITOR_CELL_PIXELS;
            cell_y = (y-4)%EDITOR_CELL_PIXELS;
            // Shift the selected cell's three bits into the bottom of the vector.
            part = build_grid >> (cell_index*3);
            if (cell_x == 0 || cell_y == 0 || x == 4+grid_size-1 || y == 4+grid_size-1) pixel_data = 16'h7bef;
            else begin
                // Draw the frame border, then its contents in the centre.
                if (frame_intact_mask[cell_index] &&
                    (cell_x < 3 || cell_x >= EDITOR_CELL_PIXELS-2 ||
                     cell_y < 3 || cell_y >= EDITOR_CELL_PIXELS-2)) pixel_data = 16'ha285;
                if (intact_mask[cell_index] && cell_x >= 3 && cell_x < EDITOR_CELL_PIXELS-2 &&
                    cell_y >= 3 && cell_y < EDITOR_CELL_PIXELS-2) case (part)
                    `LP_PART_PIG: pixel_data = 16'h07e0;
                    `LP_PART_WHEEL: pixel_data = 16'hffff;
                    `LP_PART_ENGINE: pixel_data = 16'hf800;
                    `LP_PART_BALLOON: pixel_data = 16'hf81f;
                    default: begin end
                endcase
            end
        end
        if (game_state != `LP_BUILD) begin
            if (valid_pixel) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
            if (engine_pixel) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
            if (build_error != 0 && x >= 56 && x < 92 && y >= 30 && y < 34) pixel_data = 16'hf800;
            if (number_pixel || (remaining_parts >= 10 && tens_pixel)) pixel_data = 16'hffff;
        end else if (x >= 56 && x < 92 && y >= 4 && y < 54) begin
            pixel_data = 16'h18c3;
            if (selected_part == inventory_part &&
                (x == 56 || x == 91 || y == inventory_top || y == inventory_top+9)) pixel_data = 16'hffe0;
            icon_x = x-60; icon_y = y-inventory_top-1;
            if (icon_x >= 0 && icon_x < 8 && icon_y >= 0 && icon_y < 8) begin
                case (inventory_part)
                    `LP_PART_FRAME:
                        if (icon_x == 0 || icon_x == 7 || icon_y == 0 || icon_y == 7) pixel_data = 16'ha285;
                    `LP_PART_PIG: begin
                        pixel_data = 16'h07e0;
                        if (icon_y == 2 && (icon_x == 2 || icon_x == 5)) pixel_data = 16'h0000;
                    end
                    `LP_PART_WHEEL:
                        if (icon_x == 0 || icon_x == 7 || icon_y == 0 || icon_y == 7) pixel_data = 16'hffff;
                    `LP_PART_ENGINE: begin
                        pixel_data = 16'hf800;
                        if (icon_x >= 2 && icon_x < 6 && icon_y >= 3 && icon_y < 5) pixel_data = 16'hffe0;
                    end
                    `LP_PART_BALLOON: begin
                        if (icon_y < 6 && icon_x >= 1 && icon_x < 7) pixel_data = 16'hf81f;
                        if (icon_y >= 6 && icon_x == 3) pixel_data = 16'hffff;
                    end
                    default: begin end
                endcase
            end
            if (inventory_number_pixel) pixel_data = (inventory_number == 0) ? 16'hf800 : 16'hffff;
        end
        // Bottom indicators: build validity, engine switch, then game stage.
        if (y >= 57 && y < 63 && x >= 4 && x < 16) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
        if (y >= 57 && y < 63 && x >= 20 && x < 32) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
        if (y >= 58 && y < 62 && x >= 36 && x < 36+game_state*6) pixel_data = 16'h07ff;
        if (cursor_visible && (game_state == `LP_BUILD || game_state == `LP_RUN) &&
            ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
             (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))) pixel_data = 16'hffff;
    end
endmodule
