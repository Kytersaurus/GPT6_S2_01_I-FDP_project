// Owner: Role 4 - Marcus. Shared map, spawn and goal data.
`timescale 1ns / 1ps
// Role 4 starter: one flat test map, not the two final playable levels.
module level_data (
    output wire signed [15:0] spawn_x, spawn_y,
    output wire [2:0] terrain_count,
    output wire [127:0] terrain_rects,
    output wire [31:0] goal_rect
);
    assign spawn_x = 16'sd1024; // x=4
    assign spawn_y = 16'sd8192; // y=32; 24px footprint rests on ground y=56
    assign terrain_count = 3'd1;
    assign terrain_rects = {96'd0, 8'd8, 8'd96, 8'd56, 8'd0};
    assign goal_rect = {8'd24, 8'd16, 8'd32, 8'd80};
endmodule
