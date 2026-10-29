// Shared integration: wide spawns, movement, collision and world outcomes.
`timescale 1ns / 1ps
`include "game_defs.vh"
module cave_coordinates_tb;
    reg clk=0, reset=1, run_init=0, step_start=0;
    reg [2:0] game_state=`LP_BUILD;
    reg [1:0] level_index=2;
    reg custom_spawn=0;
    reg signed [19:0] test_x=0, test_y=0;
    wire signed [19:0] spawn_x, spawn_y, x, y, px, py, nx, ny, cx, cy;
    wire signed [15:0] nvx, nvy, cvx, cvy;
    wire [2:0] terrain_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire map_level;
    wire [9:0] world_width, world_height, flag_x, flag_y;
    wire move_valid, move_ready, response_valid, response_ready, grounded;
    wire signed [7:0] ground_slope;
    wire committed, world_valid, goal_hit, hazard_hit, out_of_bounds;
    reg world_ready=0;
    reg [26:0] grid=0;
    integer waited;
    always #5 clk=~clk;
    level_data level (
        .level_index(level_index), .spawn_x(spawn_x), .spawn_y(spawn_y),
        .terrain_count(terrain_count), .terrain_rects(terrain_rects),
        .goal_rect(goal_rect), .map_level(map_level),
        .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y)
    );
    physics_engine physics (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init),
        .spawn_x(custom_spawn ? test_x : spawn_x), .spawn_y(custom_spawn ? test_y : spawn_y),
        .step_start(step_start), .update_release(world_valid && world_ready),
        .wheel_count(4'd0), .engine_count(4'd0), .balloon_count(4'd0),
        .mass_units(8'd2), .engine_enabled(1'b0), .engine_reverse(1'b0),
        .jump_press(1'b0), .boost_req(1'b0),
        .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(nvx), .proposed_vy(nvy), .response_valid(response_valid),
        .response_ready(response_ready), .corrected_x(cx), .corrected_y(cy),
        .corrected_vx(cvx), .corrected_vy(cvy), .grounded(grounded), .ground_slope(ground_slope),
        .movement_committed(committed), .vehicle_x(x), .vehicle_y(y)
    );
    collision_engine collision (
        .map_level(1'b0), .world_width(10'd96), .world_height(10'd64), .query_class(3'd0),
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(nvx), .proposed_vy(nvy),
        .terrain_count(3'd1), .terrain_rects(level_index==2 ? {96'd0,8'd8,8'd32,8'd50,8'd97} : {96'd0,8'd8,8'd36,8'd202,8'd60}),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy),
        .grounded(grounded), .ground_slope(ground_slope)
    );
    world_outcomes world (
        .clk(clk), .reset(reset), .run_init(run_init), .game_state(game_state),
        .movement_committed(committed), .vehicle_x(x), .vehicle_y(y),
        .build_grid(grid), .intact_mask(9'b000010000), .goal_rect(goal_rect),
        .map_level(map_level), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .hazard_count(2'd0), .hazard_rects(64'd0),
        .world_valid(world_valid), .world_ready(world_ready),
        .goal_hit(goal_hit), .hazard_hit(hazard_hit), .out_of_bounds(out_of_bounds)
    );
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task check_step;
        input integer expected_x, expected_y;
        input expected_ground, expected_goal, expected_bounds;
        begin
            game_state=`LP_INIT_RUN; run_init=1; clocks(2);
            if (x !== (custom_spawn ? test_x : spawn_x) ||
                y !== (custom_spawn ? test_y : spawn_y))
                $fatal(1,"Wide spawn was truncated");
            run_init=0; game_state=`LP_RUN; clocks(1);
            step_start=1; clocks(1); step_start=0;
            waited=0;
            while (!world_valid && waited<100) begin clocks(1); waited=waited+1; end
            if (!world_valid || x !== expected_x || y !== expected_y ||
                grounded !== expected_ground || goal_hit !== expected_goal ||
                out_of_bounds !== expected_bounds || hazard_hit)
                $fatal(1,"Wide movement mismatch x=%0d y=%0d ground=%b goal=%b bounds=%b",
                       x,y,grounded,goal_hit,out_of_bounds);
            clocks(4);
            if (!world_valid || x !== expected_x || y !== expected_y)
                $fatal(1,"Pose or result changed under world backpressure");
            world_ready=1; clocks(1); world_ready=0; clocks(1);
        end
    endtask
    initial begin
        grid[4*3 +: 3]=`LP_PART_PIG;
        clocks(3); reset=0; clocks(1);
        // Synthetic rectangle fixtures isolate coordinate range from ROM geometry.
        check_step(104*256,26*256,1,0,0);
        level_index=3;
        check_step(68*256,178*256,1,0,0);
        // Movement and collision preserve distant coordinates and remove old clamps.
        custom_spawn=1; test_x=769*256; test_y=40*256;
        check_step(769*256,40*256+32,0,1,0);
        level_index=2; test_x=300*256; test_y=219*256;
        check_step(300*256,219*256+32,0,1,0);
        test_x=478*256; test_y=100*256;
        check_step(478*256,100*256+32,0,0,1);
        level_index=3; test_x=890*256; test_y=100*256;
        check_step(890*256,100*256+32,0,0,1);
        // Signed positions still work above/left of the world.
        test_x=-25*256; test_y=-25*256;
        check_step(-25*256,-25*256+32,0,0,1);
        // Saturation protects arithmetic at the numeric limit, not the viewport.
        test_x=100*256; test_y=524287;
        check_step(100*256,524287,0,0,1);
        $display("PASS cave_coordinates_tb: wide spawns, collision, cave goals, bounds and backpressure");
        $finish;
    end
    initial begin #100000; $fatal(1,"Cave coordinates test timed out"); end
endmodule
