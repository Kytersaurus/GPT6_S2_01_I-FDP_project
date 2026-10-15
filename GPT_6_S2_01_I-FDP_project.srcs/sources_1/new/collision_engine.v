// Owner: Role 3 - Yap Ting. Terrain collision response.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Role 3 starter: downward platform crossing. Walls/ceilings/TNT are future work.
module collision_engine (
    input wire clk, reset, move_valid,
    output wire move_ready,
    input wire signed [15:0] previous_x, previous_y,
    input wire signed [15:0] proposed_x, proposed_y, proposed_vx, proposed_vy,
    input wire [2:0] terrain_count,
    input wire [127:0] terrain_rects,
    output reg response_valid,
    input wire response_ready,
    output reg signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy,
    output reg grounded
);
    integer index, rx, ry, rw, rh, candidate_y, candidate_vy;
    reg candidate_grounded;
    localparam FOOTPRINT = `LP_GRID_ROWS * `LP_CELL_PIXELS * 256;
    localparam VEHICLE_WIDTH = `LP_GRID_COLS * `LP_CELL_PIXELS * 256;
    assign move_ready = !response_valid;
    always @* begin
        candidate_y = $signed(proposed_y); candidate_vy = $signed(proposed_vy);
        candidate_grounded = 0; rx = 0; ry = 0; rw = 0; rh = 0;
        for (index = 0; index < 4; index = index + 1) begin
            // [start +: 8] selects eight bits beginning at start.
            rx = terrain_rects[index*32 +: 8]; ry = terrain_rects[index*32+8 +: 8];
            rw = terrain_rects[index*32+16 +: 8]; rh = terrain_rects[index*32+24 +: 8];
            if (index < terrain_count && rw > 0 && rh > 0 && $signed(proposed_vy) >= 0 &&
                $signed(previous_y) + FOOTPRINT <= ry*256 &&
                $signed(proposed_y) + FOOTPRINT >= ry*256 &&
                $signed(proposed_x) + VEHICLE_WIDTH > rx*256 &&
                $signed(proposed_x) < (rx+rw)*256 &&
                (!candidate_grounded || ry*256-FOOTPRINT < candidate_y)) begin
                candidate_y = ry*256-FOOTPRINT; candidate_vy = 0; candidate_grounded = 1;
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            response_valid <= 0; grounded <= 0;
            corrected_x <= 0; corrected_y <= 0; corrected_vx <= 0; corrected_vy <= 0;
        end else begin
            if (response_valid && response_ready) response_valid <= 0;
            if (move_valid && move_ready) begin
                corrected_x <= proposed_x; corrected_y <= candidate_y[15:0];
                corrected_vx <= proposed_vx; corrected_vy <= candidate_vy[15:0];
                grounded <= candidate_grounded; response_valid <= 1;
            end
        end
    end
endmodule
