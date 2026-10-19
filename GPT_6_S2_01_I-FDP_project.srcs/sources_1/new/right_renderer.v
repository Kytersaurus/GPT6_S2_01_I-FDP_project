// Owner: Role 4 - Marcus. Right OLED map and vehicle drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
module right_renderer (
    input wire [12:0] pixel_index,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input wire signed [15:0] vehicle_x, vehicle_y,
    input wire [2:0] terrain_count,
    input wire [127:0] terrain_rects,
    input wire [31:0] goal_rect,
    output reg [15:0] pixel_data
);
    wire goal_pixel;
    integer x, y, vx, vy, index, rx, ry, rw, rh, cell_index, cell_x, cell_y;
    reg [2:0] part;
    reg [31:0] rectangle;

    square u_goal_box (
        .x(x[6:0]), .y(y[6:0]), .pos_x(goal_rect[6:0]), .pos_y(goal_rect[14:8]),
        .width_x(goal_rect[22:16]), .length_y(goal_rect[30:24]), .is_in_square(goal_pixel)
    );

    always @* begin
        x = pixel_index % 96;
        y = pixel_index / 96;
        vx = $signed(vehicle_x) >>> 8; vy = $signed(vehicle_y) >>> 8;
        rx = 0; ry = 0; rw = 0; rh = 0; cell_index = 0; cell_x = 0; cell_y = 0;
        part = 0; rectangle = 0;
        pixel_data = 16'h0010;
        for (index = 0; index < 4; index = index + 1) begin
            rectangle = terrain_rects >> (index*32);
            rx = rectangle[7:0]; ry = rectangle[15:8];
            rw = rectangle[23:16]; rh = rectangle[31:24];
            if (index < terrain_count && x >= rx && x < rx+rw && y >= ry && y < ry+rh) pixel_data = 16'h8320;
        end
        if (goal_pixel) pixel_data = 16'h0320;
        if (x >= vx && x < vx+24 && y >= vy && y < vy+24) begin
            cell_index = ((y-vy)/8)*3 + (x-vx)/8;
            cell_x = (x-vx)%8; cell_y = (y-vy)%8;
            part = build_grid >> (cell_index*3);
            if (frame_intact_mask[cell_index] && cell_x != 0 && cell_y != 0 &&
                (cell_x == 1 || cell_x == 7 || cell_y == 1 || cell_y == 7)) pixel_data = 16'ha285;
            if (intact_mask[cell_index] && cell_x >= 2 && cell_x < 7 &&
                cell_y >= 2 && cell_y < 7) case (part)
                `LP_PART_PIG: pixel_data = 16'h07e0;
                `LP_PART_WHEEL: pixel_data = 16'hffff;
                `LP_PART_ENGINE: pixel_data = 16'hf800;
                `LP_PART_BALLOON: pixel_data = 16'hf81f;
                default: begin end
            endcase
        end
        if (x == 0 || x == 95 || y == 0 || y == 63) begin
            if (game_state == `LP_SUCCESS) pixel_data = 16'h07e0;
            else if (game_state == `LP_FAIL) pixel_data = 16'hf800;
        end
    end
endmodule
