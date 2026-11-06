// Owner: Role 4 - Marcus. Shared map, spawn, goal, TNT and hazard data.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Level 1 (Cave Arch) and Level 2 (Cave Flight) are block-RAM maps in level_map;
// map_level selects drawing from the ROM and map_id picks which map. The
// playable tutorial deliberately uses the rectangle path, so it needs no new
// terrain ROM or BRAM.
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
        // Defaults: rectangle elements cleared; ordinary levels are map levels.
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
            // Only levels 0..2 exist; any other index falls back to Cave Arch
            // so every output is driven without a separate unused level.
            default: begin
                // Level 1, Cave Arch, in world pixels: level_map shows the map twice as
                // large (map pixel = world/2). Start on the flat plateau (map top y=50,
                // x=98..128; world top y=100, x=196..257); the finish flag stands on the cave
                // road (map top y=243 at x=300; world top y=486 at x=600).
                // Collision queries the terrain ROM; goals derive from the flag position.
                spawn_x = 20'sd53248;   // x=208
                spawn_y = 20'sd19456;   // y=76: the 24-pixel vehicle rests on y=100
                map_id = 1'b0;
                par_time = 8'd25;
                world_width = `LP_MAP_WORLD_WIDTH;
                world_height = `LP_MAP_WORLD_HEIGHT;
                flag_x = 10'd600;
                // Star box top-left: on the second arch's far-left bump, 6 px right of TNT 2.
                star_box_x = 10'd170; star_box_y = 10'd391;
                flag_y = 10'd472;   // 14-pixel pole ends on the road at y=486
                // TNT {y, x} top-left in world pixels, resting on the floor:
                //  0: on the start plateau 6 px behind the spawn (vehicle x=208..231), floor
                //     y=100, so reversing is caught.
                //  1: up the right wall of the first (moon) arch, wedged against the curve where
                //     it steepens (wall x~598 at y=260), so a cart that climbs too far right and
                //     high is caught.
                //  2: on the bump in the far-left pocket of the second arch, floor y=398, past
                //     the drop at x~200, so a cart that goes too far left is caught.
                tnt_count = 3'd3;
                tnt_positions = {10'd390, 10'd116, 10'd260, 10'd588, 10'd92, 10'd194};
            end
            2'd1: begin
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
                // Star box top-left: on the top deck of the middle ledge between the gaps.
                star_box_x = 10'd541; star_box_y = 10'd103;
                flag_y = 10'd50;    // 14-pixel pole ends on the ledge at y=64
                // TNT {y, x} top-left in world pixels, resting on the floor:
                //  0: in the ditch between the first hill and the climb into the cave, floor y=199.
                //  1: in the second flight's lower gap, on its floor (y=166) under the middle of
                //     the rock ledge (x 521..569) that splits it from the upper gap.
                //  2: halfway up the grass slope to the finish ledge, floor y=76..79 (resting uphill).
                tnt_count = 3'd3;
                tnt_positions = {10'd68, 10'd710, 10'd158, 10'd541, 10'd191, 10'd316};
            end
            2'd2: begin
                // Playable tutorial: an independent rectangle course, not Map 1.
                // It has a flat floor, a star marker, one optional TNT
                // encounter, a low propulsion step and a finish island.
                map_level = 1'b0;
                // Keep the complete 24-pixel vehicle clear of the route start.
                spawn_x = 20'sd4096;    // x=16
                spawn_y = 20'sd24576;   // y=96; 24-pixel body rests at y=120
                map_id = 1'b0;          // unused in rectangle mode
                par_time = 8'd30;
                world_width = 10'd248;
                world_height = 10'd160;
                terrain_count = 3'd4;
                // Each rect is {height, width, y, x}; the values are shared
                // with the top-level collision decode through game_defs.vh.
                terrain_rects = {
                    8'd`LP_TUT_FINISH_H, 8'd`LP_TUT_FINISH_W, 8'd`LP_TUT_FINISH_Y, 8'd`LP_TUT_FINISH_X,
                    8'd`LP_TUT_PAD_H,    8'd`LP_TUT_PAD_W,    8'd`LP_TUT_PAD_Y,    8'd`LP_TUT_PAD_X,
                    // Reserved empty slot: the engine lesson stays flat.
                    8'd0,                8'd48,               8'd120,              8'd40,
                    8'd`LP_TUT_FLOOR_H,  8'd248,              8'd`LP_TUT_FLOOR_Y,  8'd0
                };
                goal_rect = {8'd40, 8'd32, 8'd80, 8'd216};
                flag_x = 10'd0;
                flag_y = 10'd0;
                star_box_x = 10'd80;
                star_box_y = 10'd112;
                tnt_count = 3'd1;
                // One crate sits on the route after the star. The first pass
                // lets the player deliberately touch it once. After retry,
                // the course pauses at a visible TNT warning; the player can
                // then avoid it and continue to the later rocket lesson.
                // The retry stop is x=88, with TNT beginning at x=128.
                tnt_positions = {40'd0, 10'd112, 10'd128};
                hazard_count = 2'd0;
                hazard_rects = 0;
            end
        endcase
    end
endmodule

