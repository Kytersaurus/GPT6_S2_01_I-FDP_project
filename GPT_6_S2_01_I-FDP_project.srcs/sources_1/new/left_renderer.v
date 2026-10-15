// Owner: Role 4 - Marcus. Left OLED construction/status drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Role 4 starter: larger editor cells, status bars and surviving-part count.
// Detailed inventory, labels and cursor controls come later.
module left_renderer #(parameter EDITOR_CELL_PIXELS = 16) (
    input wire [12:0] pixel_index,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire build_valid,
    input wire [3:0] build_error,
    input wire engine_enabled,
    output reg [15:0] pixel_data
);
    wire [6:0] x = pixel_index % 96;
    wire [6:0] y = pixel_index / 96;
    wire [6:0] grid_size = EDITOR_CELL_PIXELS * 3;
    wire grid_pixel, valid_pixel, engine_pixel, number_pixel;
    reg [3:0] remaining_parts;
    integer index, cell_index;
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
        .x(x), .y(y), .pos_x(7'd68), .pos_y(7'd36), .number(remaining_parts),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(number_pixel)
    );

    always @* begin
        remaining_parts = 0;
        for (index = 0; index < 9; index = index + 1)
            if (intact_mask[index]) remaining_parts = remaining_parts + 1'b1;
    end

    always @* begin
        cell_index = 0;
        part = 0;
        pixel_data = 16'h0841;
        if (grid_pixel) begin
            cell_index = ((y-4)/EDITOR_CELL_PIXELS)*3 + (x-4)/EDITOR_CELL_PIXELS;
            // Shift the selected cell's three bits into the bottom of the vector.
            part = build_grid >> (cell_index*3);
            if ((x-4)%EDITOR_CELL_PIXELS == 0 || (y-4)%EDITOR_CELL_PIXELS == 0) pixel_data = 16'h7bef;
            else if (intact_mask[cell_index]) case (part)
                `LP_PART_FRAME: pixel_data = 16'ha285;
                `LP_PART_PIG: pixel_data = 16'h07e0;
                `LP_PART_WHEEL: pixel_data = 16'hffff;
                `LP_PART_ENGINE: pixel_data = 16'hf800;
                `LP_PART_BALLOON: pixel_data = 16'hf81f;
                default: pixel_data = 16'h0841;
            endcase
        end
        if (valid_pixel) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
        if (engine_pixel) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
        if (y >= 58 && y < 62 && x >= 4 && x < 4+game_state*12) pixel_data = 16'h07ff;
        if (build_error != 0 && x >= 56 && x < 92 && y >= 30 && y < 34) pixel_data = 16'hf800;
        if (number_pixel) pixel_data = 16'hffff;
    end
endmodule
