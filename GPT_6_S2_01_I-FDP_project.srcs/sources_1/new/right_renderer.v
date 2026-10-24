// Owner: Role 4 - Marcus. Right OLED map and vehicle drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Drawing order: sky, terrain, hazards, goal, TNT, vehicle, explosions, then the result border.
// Before launch the vehicle is drawn at the level's spawn point.
module right_renderer (
    input wire [12:0] pixel_index,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input wire signed [15:0] vehicle_x, vehicle_y,
    input wire signed [15:0] spawn_x, spawn_y,
    input wire [2:0] terrain_count,
    input wire [127:0] terrain_rects,
    input wire [31:0] goal_rect,
    input wire [2:0] tnt_count,
    input wire [`LP_TNT_BITS-1:0] tnt_positions,
    input wire [`LP_MAX_TNT-1:0] tnt_intact,
    input wire [1:0] hazard_count,
    input wire [`LP_HAZARD_BITS-1:0] hazard_rects,
    input wire [2*`LP_MAX_TNT-1:0] blast_phase,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"

    wire goal_pixel;
    integer x, y, vx, vy, index, rx, ry, rw, rh, cell_index, cell_x, cell_y, tx, ty, distance, radius;
    reg [2:0] part;
    reg [31:0] rectangle;
    wire before_launch = (game_state == `LP_BUILD || game_state == `LP_GUIDE);

    square u_goal_box (
        .x(x[6:0]), .y(y[6:0]), .pos_x(goal_rect[6:0]), .pos_y(goal_rect[14:8]),
        .width_x(goal_rect[22:16]), .length_y(goal_rect[30:24]), .is_in_square(goal_pixel)
    );

    always @* begin
        x = pixel_index % 96;
        y = pixel_index / 96;
        vx = $signed(before_launch ? spawn_x : vehicle_x) >>> 8;
        vy = $signed(before_launch ? spawn_y : vehicle_y) >>> 8;
        rx = 0; ry = 0; rw = 0; rh = 0; cell_index = 0; cell_x = 0; cell_y = 0;
        tx = 0; ty = 0; distance = 0; radius = 0; part = 0; rectangle = 0;
        pixel_data = 16'h0010;
        for (index = 0; index < 4; index = index + 1) begin
            rectangle = terrain_rects >> (index*32);
            rx = rectangle[7:0]; ry = rectangle[15:8];
            rw = rectangle[23:16]; rh = rectangle[31:24];
            if (index < terrain_count && x >= rx && x < rx+rw && y >= ry && y < ry+rh) pixel_data = 16'h8320;
        end
        // Spikes: four-pixel teeth, pointed in their outer columns.
        for (index = 0; index < `LP_MAX_HAZARDS; index = index + 1) begin
            rectangle = hazard_rects >> (index*32);
            rx = rectangle[7:0]; ry = rectangle[15:8];
            rw = rectangle[23:16]; rh = rectangle[31:24];
            if (index < hazard_count && x >= rx && x < rx+rw && y >= ry && y < ry+rh &&
                ((x-rx)%4 == 1 || (x-rx)%4 == 2 || y-ry >= rh/2)) pixel_data = 16'hc618;
        end
        if (goal_pixel) pixel_data = 16'h0320;
        // TNT: red block with a white band and a yellow fuse.
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            tx = x - tnt_positions[index*16 +: 8];
            ty = y - tnt_positions[index*16+8 +: 8];
            if (index < tnt_count && tnt_intact[index] &&
                tx >= 0 && tx < `LP_TNT_PIXELS && ty >= 0 && ty < `LP_TNT_PIXELS) begin
                if (ty == 0) begin if (tx == 4) pixel_data = 16'hffe0; end
                else if (ty == 3 || ty == 4) pixel_data = 16'hffff;
                else pixel_data = 16'hf800;
            end
        end
        if (x >= vx && x < vx+24 && y >= vy && y < vy+24) begin
            cell_index = ((y-vy)/8)*3 + (x-vx)/8;
            cell_x = (x-vx)%8; cell_y = (y-vy)%8;
            part = build_grid >> (cell_index*3);
            if (frame_intact_mask[cell_index]) pixel_data = part_sprite(`LP_PART_FRAME, cell_x, cell_y, pixel_data);
            if (intact_mask[cell_index]) pixel_data = part_sprite(part, cell_x, cell_y, pixel_data);
        end
        // Explosions grow over three phases: yellow flash, orange fireball, grey smoke.
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            tx = x - tnt_positions[index*16 +: 8] - `LP_TNT_PIXELS/2;
            ty = y - tnt_positions[index*16+8 +: 8] - `LP_TNT_PIXELS/2;
            distance = tx*tx + ty*ty;
            radius = 2 + 3*blast_phase[index*2 +: 2];
            if (index < tnt_count && blast_phase[index*2 +: 2] != 0 && distance <= radius*radius) case (blast_phase[index*2 +: 2])
                2'd1: pixel_data = 16'hffe0;
                2'd2: pixel_data = (distance <= 9) ? 16'hffe0 : 16'hfd20;
                default: pixel_data = 16'h8410;
            endcase
        end
        if (x == 0 || x == 95 || y == 0 || y == 63) begin
            if (game_state == `LP_SUCCESS) pixel_data = 16'h07e0;
            else if (game_state == `LP_FAIL) pixel_data = 16'hf800;
        end
    end
endmodule
