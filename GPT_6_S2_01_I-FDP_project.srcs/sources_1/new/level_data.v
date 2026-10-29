// Owner: Role 4 - Marcus. Shared map, spawn, goal, TNT and hazard data.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Levels 1 and 2 are provisional rectangle layouts in a 96 by 64 world.
// Levels 3 (Cave Arch) and 4 (Cave Flight) are block-RAM maps in level_map; map_level
// selects drawing from the ROM and map_id picks which map.
// Rectangles are {height, width, y, x} in whole pixels, rectangle 0 in the lowest bits.
// TNT entries are {y, x} for an 8 by 8 block, entry 0 in the lowest bits.
// Unused entries are zero and lie above the matching count.
module level_data (
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    // Signed Q12.8 spawn, preserved by physics and collision.
    output reg signed [19:0] spawn_x, spawn_y,
    output reg [2:0] terrain_count,
    output reg [127:0] terrain_rects,
    output reg [31:0] goal_rect,
    output reg [2:0] tnt_count,
    output reg [`LP_TNT_BITS-1:0] tnt_positions,
    output reg [1:0] hazard_count,
    output reg [`LP_HAZARD_BITS-1:0] hazard_rects,
    // Drawing: world size for the camera, and the finish flag's top-left on map levels.
    output reg map_level,
    output reg map_id,
    output reg [9:0] world_width, world_height,
    output reg [9:0] flag_x, flag_y
);
    always @* begin
        // Levels 1 and 2 start at x=4, y=32 so the 24 pixel vehicle rests on ground at y=56.
        spawn_x = 20'sd1024;
        spawn_y = 20'sd8192;
        goal_rect = {8'd24, 8'd16, 8'd32, 8'd80};
        map_level = 1'b0;
        map_id = 1'b0;
        world_width = 10'd96;
        world_height = 10'd64;
        flag_x = 10'd0;
        flag_y = 10'd0;
        tnt_count = 3'd0;
        tnt_positions = 0;
        hazard_count = 2'd0;
        hazard_rects = 0;
        case (level_index)
            2'd0: begin
                // Level 1: flat ground to the goal, with a TNT on a ledge above the path.
                terrain_count = 3'd2;
                terrain_rects = {64'd0,
                                 8'd4, 8'd24, 8'd20, 8'd36,   // Ledge
                                 8'd8, 8'd96, 8'd56, 8'd0};   // Ground
                tnt_count = 3'd1;
                tnt_positions = {48'd0, 8'd12, 8'd44};
            end
            2'd1: begin
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
            2'd2: begin
                // Level 3, Cave Arch: start on the flat plateau (top y=50, x=97..128);
                // the finish flag stands on the cave road (top y=243) at x=300.
                // Collision queries the terrain ROM; goals derive from the flag position.
                spawn_x = 20'sd26624;   // x=104
                spawn_y = 20'sd6656;    // y=26
                terrain_count = 3'd0;
                terrain_rects = 128'd0;
                goal_rect = 32'd0; // Map goals use flag_x/flag_y, not the 8-bit rectangle.
                map_level = 1'b1;
                world_width = `LP_MAP_WIDTH;
                world_height = `LP_MAP_HEIGHT;
                flag_x = 10'd300;
                flag_y = 10'd229;   // 14-pixel pole ends on the road at y=243
            end
            default: begin
                // Level 4, Cave Flight: a flying level. Start on the ground at the bottom left
                // (surface y=202..205 for x=60..96); the flag stands on the grassy ledge at the
                // top right (surface y=64). The car must fly up through the cave tunnels.
                // Collision queries the terrain ROM, including cave walls and ceilings.
                spawn_x = 20'sd17408;   // x=68
                spawn_y = 20'sd45568;   // y=178
                terrain_count = 3'd0;
                terrain_rects = 128'd0;
                goal_rect = 32'd0; // Map goals use flag_x/flag_y, not the 8-bit rectangle.
                map_level = 1'b1;
                map_id = 1'b1;
                world_width = `LP_FLIGHT_WIDTH;
                world_height = `LP_FLIGHT_HEIGHT;
                flag_x = 10'd769;
                flag_y = 10'd50;    // 14-pixel pole ends on the ledge at y=64
            end
        endcase
    end
endmodule
