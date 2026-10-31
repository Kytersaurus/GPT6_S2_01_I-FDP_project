// Owner: Role 4 - Marcus. Shared map, spawn, goal, TNT and hazard data.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Level 1 (Cave Arch) and Level 2 (Cave Flight) are block-RAM maps in level_map;
// map_level selects drawing from the ROM and map_id picks which map.
// Rectangle ports are retained for interface compatibility and set to 0.
module level_data (
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    // Signed Q12.8 spawn, preserved by physics and collision.
    output reg signed [19:0] spawn_x, spawn_y,
    output reg [2:0] terrain_count,
    output reg [127:0] terrain_rects,
    output reg [31:0] goal_rect,
    output reg [2:0] tnt_count,
    output reg [`LP_TNT_BITS-1:0] tnt_positions,
    output reg [7:0] par_time,
    output reg [1:0] hazard_count,
    output reg [`LP_HAZARD_BITS-1:0] hazard_rects,
    // Drawing: world size for the camera, and the finish flag's top-left on map levels.
    output reg map_level,
    output reg map_id,
    output reg [9:0] world_width, world_height,
    output reg [9:0] flag_x, flag_y,
    output reg [9:0] star_box_x, star_box_y
);
    always @* begin
        // Defaults: rectangle elements cleared; all levels are map levels.
        terrain_count = 3'd0;
        terrain_rects = 128'd0;
        goal_rect = 32'd0;
        tnt_count = 3'd0;
        tnt_positions = 0;
        hazard_count = 2'd0;
        hazard_rects = 0;
        map_level = 1'b1;
        par_time = 8'd25;
        case (level_index)
            2'd0: begin
                // Level 1, Cave Arch, in world pixels: level_map shows the map twice as
                // large (map pixel = world/2). Start on the flat plateau (map top y=50,
                // x=98..128; world top y=100, x=196..257); the finish flag stands on the cave
                // road (map top y=243 at x=300; world top y=486 at x=600).
                // Collision queries the terrain ROM; goals derive from the flag position.
                spawn_x = 20'sd53248;   // x=208
                spawn_y = 20'sd19456;   // y=76: the 24-pixel vehicle rests on y=100
                map_id = 1'b0;
                par_time = 8'd30;
                world_width = `LP_MAP_WORLD_WIDTH;
                world_height = `LP_MAP_WORLD_HEIGHT;
                flag_x = 10'd600;
                star_box_x = 10'd400; star_box_y = 10'd300;
                flag_y = 10'd472;   // 14-pixel pole ends on the road at y=486
            end
            default: begin
                // Level 2, Cave Flight: a flying level. Start on the ground at the bottom left
                // (surface y=202..205 for x=60..96); the flag stands on the grassy ledge at the
                // top right (surface y=64). The car must fly up through the cave tunnels.
                // Collision queries the terrain ROM, including cave walls and ceilings.
                spawn_x = 20'sd17408;   // x=68
                spawn_y = 20'sd45568;   // y=178
                map_id = 1'b1;
                par_time = 8'd45;
                world_width = `LP_FLIGHT_WIDTH;
                world_height = `LP_FLIGHT_HEIGHT;
                flag_x = 10'd769;
                star_box_x = 10'd400; star_box_y = 10'd150;
                flag_y = 10'd50;    // 14-pixel pole ends on the ledge at y=64
            end
        endcase
    end
endmodule

