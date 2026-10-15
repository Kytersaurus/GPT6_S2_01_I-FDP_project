// Owner: Role 3 - Yap Ting. Goal and bounds checks after movement.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Role 3 starter: committed-pose goal and bounds checks; no TNT or hazards yet.
module world_outcomes (
    input wire clk, reset, run_init,
    input wire [2:0] game_state,
    output reg init_ready,
    input wire movement_committed,
    input wire signed [15:0] vehicle_x, vehicle_y,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [31:0] goal_rect,
    output reg world_valid,
    input wire world_ready,
    output reg goal_hit,
    output wire hazard_hit,
    output reg out_of_bounds
);
    integer index, pig_x, pig_y, gx, gy, gw, gh;
    reg pig_found, candidate_goal;
    assign hazard_hit = 1'b0;
    always @* begin
        pig_x = 0; pig_y = 0; pig_found = 0;
        gx = goal_rect[7:0]; gy = goal_rect[15:8]; gw = goal_rect[23:16]; gh = goal_rect[31:24];
        for (index = 0; index < 9; index = index + 1)
            if (intact_mask[index] && build_grid[index*3 +: 3] == `LP_PART_PIG) begin
                pig_found = 1;
                pig_x = $signed(vehicle_x) + ((index%3)*8+4)*256;
                pig_y = $signed(vehicle_y) + ((index/3)*8+4)*256;
            end
        candidate_goal = pig_found && pig_x >= gx*256 && pig_x < (gx+gw)*256 &&
                         pig_y >= gy*256 && pig_y < (gy+gh)*256;
    end
    always @(posedge clk) begin
        if (reset) begin init_ready <= 0; world_valid <= 0; goal_hit <= 0; out_of_bounds <= 0; end
        else begin
            if (!run_init) init_ready <= 0;
            if (run_init && !init_ready) begin
                init_ready <= 1; world_valid <= 0; goal_hit <= 0; out_of_bounds <= 0;
            end else begin
                if (world_valid && world_ready) world_valid <= 0;
                if (movement_committed && game_state == `LP_RUN && !world_valid) begin
                    goal_hit <= candidate_goal;
                    out_of_bounds <= ($signed(vehicle_x) >= 96*256) || ($signed(vehicle_x)+24*256 <= 0) ||
                                     ($signed(vehicle_y) >= 64*256) || ($signed(vehicle_y)+24*256 <= 0);
                    world_valid <= 1;
                end
            end
        end
    end
endmodule
