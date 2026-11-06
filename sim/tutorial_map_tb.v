`timescale 1ns / 1ps
`include "game_defs.vh"

// Focused regression for the title-screen playable tutorial.  The tutorial
// is an independent rectangle course with visible star/TNT teaching objects.
module tutorial_map_tb;
    reg [`LP_LEVEL_BITS-1:0] level_index;
    wire signed [19:0] spawn_x, spawn_y;
    wire [2:0] terrain_count, tnt_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire [`LP_TNT_BITS-1:0] tnt_positions;
    wire [7:0] par_time;
    wire [1:0] hazard_count;
    wire [`LP_HAZARD_BITS-1:0] hazard_rects;
    wire map_level, map_id;
    wire [9:0] world_width, world_height, flag_x, flag_y, star_box_x, star_box_y;

    level_data dut (
        .level_index(level_index), .spawn_x(spawn_x), .spawn_y(spawn_y),
        .terrain_count(terrain_count), .terrain_rects(terrain_rects), .goal_rect(goal_rect),
        .tnt_count(tnt_count), .tnt_positions(tnt_positions), .par_time(par_time),
        .hazard_count(hazard_count), .hazard_rects(hazard_rects), .map_level(map_level),
        .map_id(map_id), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .star_box_x(star_box_x), .star_box_y(star_box_y)
    );

    initial begin
        level_index = `LP_LEVEL_TUTORIAL;
        #1;
        if (map_level || map_id !== 1'b0) $fatal(1, "Tutorial did not select rectangle mode");
        if (spawn_x !== 20'sd4096 || spawn_y !== 20'sd24576)
            $fatal(1, "Tutorial spawn changed");
        if (terrain_count != 3'd4 || terrain_rects !== {
                8'd8,  8'd32, 8'd120, 8'd216,
                8'd2,  8'd48, 8'd118, 8'd144,
                8'd0,  8'd48, 8'd120, 8'd40,
                8'd32, 8'd248,8'd120, 8'd0
            })
            $fatal(1, "Tutorial course rectangles changed");
        if (tnt_count != 3'd1 || tnt_positions !== {40'd0, 10'd112, 10'd128})
            $fatal(1, "Tutorial TNT teaching prop changed");
        if (hazard_count != 0 || hazard_rects != 0)
            $fatal(1, "Tutorial unexpectedly contains hazards");
        if (goal_rect !== {8'd16, 8'd32, 8'd104, 8'd216})
            $fatal(1, "Tutorial goal rectangle changed");
        if (flag_x != 10'd228 || flag_y != 10'd106)
            $fatal(1, "Tutorial finish flag changed");
        if (star_box_x != 10'd80 || star_box_y != 10'd112)
            $fatal(1, "Tutorial star checkpoint changed");
        $display("PASS tutorial_map_tb: expanded tutorial has visible star/TNT and no hazards");
        $finish;
    end
endmodule
