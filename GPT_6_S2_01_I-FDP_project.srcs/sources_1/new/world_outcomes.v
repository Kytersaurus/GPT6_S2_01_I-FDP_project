// Owner: Role 3 - Yap Ting. Goal, hazard and bounds checks after movement.
`timescale 1ns / 1ps
`include "game_defs.vh"

// World results are sampled from the committed vehicle pose. The module
// holds its flags until Role 4 accepts the world_valid response.
module world_outcomes (
    input wire clk, reset, run_init,
    input wire [2:0] game_state,
    output reg init_ready,
    input wire movement_committed,
    input wire signed [15:0] vehicle_x, vehicle_y,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [31:0] goal_rect,
    input wire [1:0] hazard_count,
    input wire [63:0] hazard_rects,
    output reg world_valid,
    input wire world_ready,
    output reg goal_hit,
    output reg hazard_hit,
    output reg out_of_bounds
);
    localparam signed [31:0] VEHICLE_SIZE_FP = 32'sd6144; // 24 pixels * 256
    localparam integer WORLD_WIDTH_PIXELS = 96;
    localparam integer WORLD_HEIGHT_PIXELS = 64;

    integer index;
    integer pig_x, pig_y, gx, gy, gw, gh;
    integer hazard_x, hazard_y, hazard_w, hazard_h;
    integer vehicle_left, vehicle_top, vehicle_right, vehicle_bottom;
    reg pig_found, candidate_goal, candidate_hazard;

    always @* begin
        pig_x = 0;
        pig_y = 0;
        pig_found = 1'b0;
        gx = goal_rect[7:0];
        gy = goal_rect[15:8];
        gw = goal_rect[23:16];
        gh = goal_rect[31:24];

        // The pig centre is used for goal entry, matching the existing
        // renderer and game-controller contract.
        for (index = 0; index < 9; index = index + 1) begin
            if (intact_mask[index] &&
                build_grid[index*3 +: 3] == `LP_PART_PIG) begin
                pig_found = 1'b1;
                pig_x = $signed(vehicle_x) + ((index%3)*8+4)*256;
                pig_y = $signed(vehicle_y) + ((index/3)*8+4)*256;
            end
        end

        candidate_goal = pig_found &&
                         pig_x >= gx*256 &&
                         pig_x < (gx+gw)*256 &&
                         pig_y >= gy*256 &&
                         pig_y < (gy+gh)*256;

        vehicle_left = $signed(vehicle_x);
        vehicle_top = $signed(vehicle_y);
        vehicle_right = vehicle_left + VEHICLE_SIZE_FP;
        vehicle_bottom = vehicle_top + VEHICLE_SIZE_FP;
        candidate_hazard = 1'b0;

        // Hazard rectangles use the same {height,width,y,x} packing as
        // terrain. Strict inequalities implement left/top inclusive and
        // right/bottom exclusive rectangle edges.
        for (index = 0; index < 2; index = index + 1) begin
            hazard_x = hazard_rects[index*32 +: 8];
            hazard_y = hazard_rects[index*32+8 +: 8];
            hazard_w = hazard_rects[index*32+16 +: 8];
            hazard_h = hazard_rects[index*32+24 +: 8];

            if (index < hazard_count &&
                hazard_w != 0 && hazard_h != 0 &&
                vehicle_right > hazard_x*256 &&
                vehicle_left < (hazard_x+hazard_w)*256 &&
                vehicle_bottom > hazard_y*256 &&
                vehicle_top < (hazard_y+hazard_h)*256)
                candidate_hazard = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            init_ready <= 1'b0;
            world_valid <= 1'b0;
            goal_hit <= 1'b0;
            hazard_hit <= 1'b0;
            out_of_bounds <= 1'b0;
        end else begin
            if (!run_init)
                init_ready <= 1'b0;

            if (run_init && !init_ready) begin
                init_ready <= 1'b1;
                world_valid <= 1'b0;
                goal_hit <= 1'b0;
                hazard_hit <= 1'b0;
                out_of_bounds <= 1'b0;
            end else begin
                if (world_valid && world_ready)
                    world_valid <= 1'b0;

                if (movement_committed && game_state == `LP_RUN && !world_valid) begin
                    goal_hit <= candidate_goal;
                    hazard_hit <= candidate_hazard;
                    out_of_bounds <=
                        ($signed(vehicle_x) >= WORLD_WIDTH_PIXELS*256) ||
                        ($signed(vehicle_x) + VEHICLE_SIZE_FP <= 0) ||
                        ($signed(vehicle_y) >= WORLD_HEIGHT_PIXELS*256) ||
                        ($signed(vehicle_y) + VEHICLE_SIZE_FP <= 0);
                    world_valid <= 1'b1;
                end
            end
        end
    end
endmodule
