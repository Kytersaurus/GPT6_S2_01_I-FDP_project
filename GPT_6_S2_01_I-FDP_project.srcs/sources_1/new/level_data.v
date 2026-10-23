// Owner: Role 4 - Marcus. Shared map, spawn, goal, TNT and hazard data.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Two provisional levels; layouts are expected to change.
// Rectangles are {height, width, y, x} in whole pixels, rectangle 0 in the lowest bits.
// TNT entries are {y, x} for an 8 by 8 block, entry 0 in the lowest bits.
// Unused entries are zero and lie above the matching count.
module level_data (
    input wire level_index,
    output reg signed [15:0] spawn_x, spawn_y,
    output reg [2:0] terrain_count,
    output reg [127:0] terrain_rects,
    output reg [31:0] goal_rect,
    output reg [2:0] tnt_count,
    output reg [`LP_TNT_BITS-1:0] tnt_positions,
    output reg [1:0] hazard_count,
    output reg [`LP_HAZARD_BITS-1:0] hazard_rects
);
    always @* begin
        // Both levels start at x=4, y=32 so the 24 pixel vehicle rests on ground at y=56.
        spawn_x = 16'sd1024;
        spawn_y = 16'sd8192;
        goal_rect = {8'd24, 8'd16, 8'd32, 8'd80};
        if (level_index == 1'b0) begin
            // Level 1: flat ground to the goal, with a TNT on a ledge above the path.
            terrain_count = 3'd2;
            terrain_rects = {64'd0,
                             8'd4, 8'd24, 8'd20, 8'd36,   // Ledge
                             8'd8, 8'd96, 8'd56, 8'd0};   // Ground
            tnt_count = 3'd1;
            tnt_positions = {48'd0, 8'd12, 8'd44};
            hazard_count = 2'd0;
            hazard_rects = 64'd0;
        end else begin
            // Level 2: spiked pit narrower than the vehicle, TNT on the path and on a ledge.
            terrain_count = 3'd4;
            terrain_rects = {8'd4, 8'd24, 8'd22, 8'd20,   // Ledge
                             8'd2, 8'd16, 8'd62, 8'd36,   // Pit floor
                             8'd8, 8'd44, 8'd56, 8'd52,   // Right ground
                             8'd8, 8'd36, 8'd56, 8'd0};   // Left ground
            tnt_count = 3'd2;
            tnt_positions = {32'd0, 8'd14, 8'd28, 8'd48, 8'd60};
            hazard_count = 2'd1;
            hazard_rects = {32'd0, 8'd4, 8'd16, 8'd58, 8'd36}; // Spikes
        end
    end
endmodule
