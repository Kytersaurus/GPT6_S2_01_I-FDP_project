`timescale 1ns/1ps
`include "game_defs.vh"

// Deterministic finish-path check for the tutorial.  The detailed movement
// and retry behavior is covered by the existing top-level tests; this check
// verifies that the rendered finish island and world-outcome goal agree, so a
// vehicle that follows the tutorial route can actually clear the course.
module tutorial_clear_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg run_init = 1'b0;
    reg [2:0] game_state = `LP_BUILD;
    reg movement_committed = 1'b0;
    reg world_ready = 1'b1;
    reg signed [`LP_COORD_BITS-1:0] vehicle_x = 20'sd0;
    reg signed [`LP_COORD_BITS-1:0] vehicle_y = 20'sd0;
    reg signed [`LP_TILT_BITS-1:0] vehicle_tilt = 5'sd0;
    reg [26:0] build_grid = {
        `LP_PART_WHEEL, `LP_PART_FAN, `LP_PART_WHEEL,
        `LP_PART_EMPTY, `LP_PART_PIG, `LP_PART_ENGINE,
        `LP_PART_EMPTY, `LP_PART_BOOSTER, `LP_PART_BALLOON
    };
    reg [8:0] intact_mask = 9'h1ff;
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
    wire init_ready, world_valid, goal_hit, hazard_hit, out_of_bounds, star_box_hit;
    integer cycles;

    always #5 clk = ~clk;

    level_data u_level (
        .level_index(`LP_LEVEL_TUTORIAL), .spawn_x(spawn_x), .spawn_y(spawn_y),
        .terrain_count(terrain_count), .terrain_rects(terrain_rects), .goal_rect(goal_rect),
        .tnt_count(tnt_count), .tnt_positions(tnt_positions), .par_time(par_time),
        .hazard_count(hazard_count), .hazard_rects(hazard_rects), .map_level(map_level),
        .map_id(map_id), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .star_box_x(star_box_x), .star_box_y(star_box_y)
    );

    world_outcomes dut (
        .clk(clk), .reset(reset), .run_init(run_init), .game_state(game_state),
        .init_ready(init_ready), .movement_committed(movement_committed),
        .vehicle_x(vehicle_x), .vehicle_y(vehicle_y), .vehicle_tilt(vehicle_tilt),
        .build_grid(build_grid), .intact_mask(intact_mask), .goal_rect(goal_rect),
        .map_level(map_level), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .star_box_x(star_box_x), .star_box_y(star_box_y),
        .hazard_count(hazard_count), .hazard_rects(hazard_rects),
        .world_valid(world_valid), .world_ready(world_ready), .goal_hit(goal_hit),
        .hazard_hit(hazard_hit), .star_box_hit(star_box_hit), .out_of_bounds(out_of_bounds)
    );

    task clock_n;
        input integer count;
        begin repeat (count) @(negedge clk); end
    endtask

    task sample_pose;
        input signed [`LP_COORD_BITS-1:0] x;
        input signed [`LP_COORD_BITS-1:0] y;
        begin
            vehicle_x = x;
            vehicle_y = y;
            movement_committed = 1'b1;
            clock_n(1);
            movement_committed = 1'b0;
            cycles = 0;
            while (!world_valid && cycles < 40) begin
                clock_n(1);
                cycles = cycles + 1;
            end
            if (!world_valid) $fatal(1, "World outcome response timed out");
            clock_n(1);
        end
    endtask

    initial begin
        clock_n(2);
        reset = 1'b0;
        run_init = 1'b1;
        game_state = `LP_INIT_RUN;
        clock_n(2);
        run_init = 1'b0;
        game_state = `LP_RUN;

        if (map_level || hazard_count != 0 || tnt_count != 1)
            $fatal(1, "Tutorial outcome data is not a clearable rectangle course");
        if (goal_rect !== {8'd16, 8'd32, 8'd104, 8'd216})
            $fatal(1, "Tutorial finish rectangle changed");

        // The start pose must not finish immediately.
        sample_pose(20'sd4096, 20'sd24576);
        if (goal_hit || hazard_hit || out_of_bounds)
            $fatal(1, "Tutorial start pose incorrectly ends the run");

        // Flying high above the finish line (x=216, y=72 -> pig_y=84) must NOT
        // trigger goal_hit until the vehicle lands on the ground!
        sample_pose(20'sd55296, 20'sd18432);
        if (goal_hit || hazard_hit || out_of_bounds)
            $fatal(1, "Airborne pose above finish line cleared before landing");

        // At x=216,y=96 (landed on y=120) the centered pig is inside the on-land
        // finish goal x=216..248, y=104..120.
        sample_pose(20'sd55296, 20'sd24576);
        if (!goal_hit || hazard_hit || out_of_bounds)
            $fatal(1, "Tutorial route cannot reach its finish island");

        $display("PASS tutorial_clear_tb: tutorial finish geometry produces a clear without hazards");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Tutorial clear test timed out");
    end
endmodule
