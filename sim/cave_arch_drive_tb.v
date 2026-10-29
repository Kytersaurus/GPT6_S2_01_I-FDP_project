// Owner: Role 4 - Marcus. Drives Cave Arch from its spawn to the finish flag.
`timescale 1ns / 1ps
`include "game_defs.vh"
// The real level data, scaled map ROM, physics and rotated collision engines run
// update after update with the engine on, exactly as game_controller sequences them;
// the vehicle is never moved by hand. The test vehicle is frames in cells 3-5, pig
// in 4, engine in 3, and wheels under the frames (6, 8) and on top of them (0, 2),
// so it can drive either way up. The driver behaves like a player with one rule and
// no knowledge of the map: hold the engine on, and press reverse whenever the cart has
// made no new progress in its current direction for 4 seconds of updates. Success uses
// world_outcomes' map goal: the pig (centre cell) inside the box from the flag pole.
// Each update must commit; the run fails if the vehicle leaves the world or stops
// moving for 10 seconds of updates.
module cave_arch_drive_tb;
    reg clk=0, reset=1, run_init=0, step_start=0, update_release=0, engine_reverse=0;
    reg [2:0] game_state=`LP_BUILD;
    always #5 clk=~clk;
    wire signed [19:0] spawn_x, spawn_y;
    wire map_level, map_id;
    wire [9:0] world_width, world_height, flag_x, flag_y;
    level_data u_level (
        .level_index(`LP_LEVEL_ARCH), .spawn_x(spawn_x), .spawn_y(spawn_y), .terrain_count(), .terrain_rects(),
        .goal_rect(), .tnt_count(), .tnt_positions(), .hazard_count(), .hazard_rects(),
        .map_level(map_level), .map_id(map_id), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y)
    );
    wire move_valid, move_ready, response_valid, response_ready, grounded, movement_committed, init_ready;
    wire signed [19:0] previous_x, previous_y, proposed_x, proposed_y, corrected_x, corrected_y, vehicle_x, vehicle_y;
    wire signed [15:0] proposed_vx, proposed_vy, corrected_vx, corrected_vy;
    wire signed [7:0] ground_slope;
    wire signed [`LP_TILT_BITS-1:0] previous_tilt, proposed_tilt, corrected_tilt, vehicle_tilt;
    wire signed [1:0] tip_dir;
    wire signed [10:0] qx, qy;
    wire [2:0] query_class;
    wire query_solid;
    level_map u_map (
        .map_id(map_id), .draw_clk(clk), .draw_x(11'sd0), .draw_y(11'sd0), .draw_class(),
        .query_clk(clk), .query_map_id(map_id), .query_x(qx), .query_y(qy), .query_class(), .query_solid(query_solid)
    );
    // The game feeds collision the solid mask as ROCK/SKY, as My_Top_Module does.
    assign query_class = query_solid ? `LP_MAP_ROCK : `LP_MAP_SKY;
    // The game's engine strength (My_Top_Module ENGINE_FORCE).
    physics_engine #(.ENGINE_FORCE(320)) u_physics (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(4'd4), .wheels_down(4'd2), .wheels_up(4'd2), .tip_dir(tip_dir),
        .engine_count(4'd1), .balloon_count(4'd0), .mass_units(8'd15),
        .engine_enabled(1'b1), .engine_reverse(engine_reverse), .jump_press(1'b0), .boost_req(1'b0),
        .boost_active(), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .response_valid(response_valid),
        .response_ready(response_ready), .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded), .ground_slope(ground_slope),
        .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt), .corrected_tilt(corrected_tilt),
        .vehicle_tilt(vehicle_tilt), .movement_committed(movement_committed),
        .vehicle_x(vehicle_x), .vehicle_y(vehicle_y)
    );
    collision_engine #(.ROTATION_ONLY(1)) u_collision (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .terrain_count(3'd0), .terrain_rects(128'd0),
        .map_level(map_level), .rotation_enabled(1'b1), .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt),
        .collision_mask(9'b101111101), .world_width(world_width), .world_height(world_height),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .ground_slope(ground_slope), .corrected_tilt(corrected_tilt), .tip_dir(tip_dir)
    );

    integer steps, still_steps, max_x, last_x, last_y, waited, pig_x, pig_y;
    integer best_x, stalled, reversals;
    reg trace;
    initial trace=$test$plusargs("trace");
    reg goal, outside;
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    initial begin
        clocks(3); reset=0; clocks(2);
        game_state=`LP_INIT_RUN; run_init=1; clocks(3); run_init=0; game_state=`LP_RUN; clocks(2);
        steps=0; still_steps=0; max_x=vehicle_x; last_x=vehicle_x; last_y=vehicle_y; goal=0; outside=0;
        best_x=vehicle_x; stalled=0; reversals=0;
        while (!goal && !outside && steps<20000 && still_steps<600) begin
            step_start=1; clocks(1); step_start=0;
            waited=0;
            while (!movement_committed && waited<3000000) begin clocks(1); waited=waited+1; end
            if (!movement_committed) $fatal(1,"Update %0d did not commit",steps);
            clocks(1); update_release=1; clocks(1); update_release=0; clocks(1);
            steps=steps+1;
            // world_outcomes: the pig centre in [flag_x, +16) x [flag_y-10, flag_y+14).
            pig_x=vehicle_x+3072; pig_y=vehicle_y+3072;
            goal = pig_x>=flag_x*256 && pig_x<flag_x*256+4096 && pig_y>=flag_y*256-2560 && pig_y<flag_y*256+3584;
            outside = vehicle_x>=world_width*256 || vehicle_x+6144<=0 || vehicle_y>=world_height*256 || vehicle_y+6144<=0;
            if (vehicle_x>max_x) max_x=vehicle_x;
            if (vehicle_x==last_x && vehicle_y==last_y) still_steps=still_steps+1; else still_steps=0;
            last_x=vehicle_x; last_y=vehicle_y;
            // The player: progress is a new furthest x in the driving direction.
            if (engine_reverse ? vehicle_x<best_x : vehicle_x>best_x) begin best_x=vehicle_x; stalled=0; end
            else stalled=stalled+1;
            if (stalled>=240) begin
                engine_reverse=!engine_reverse; best_x=vehicle_x; stalled=0; reversals=reversals+1;
                $display("step %0d: reverse=%b at x=%0d y=%0d",steps,engine_reverse,vehicle_x/256,vehicle_y/256);
            end
            // +trace logs every update, for measuring how smooth the motion is.
            if (trace)
                $display("T %0d %0d %0d %0d %b %0d",steps,vehicle_x,vehicle_y,vehicle_tilt,grounded,u_physics.display_y);
            if (steps%50==0)
                $display("step %0d: x=%0d y=%0d vx=%0d vy=%0d tilt=%0d grounded=%b tip=%0d",steps,
                         vehicle_x/256,vehicle_y/256,u_physics.velocity_x,u_physics.velocity_y,vehicle_tilt,grounded,tip_dir);
        end
        $display("RESULT goal=%b outside=%b steps=%0d x=%0d y=%0d max_x=%0d still=%0d",
                 goal,outside,steps,vehicle_x/256,vehicle_y/256,max_x/256,still_steps);
        if (!goal)
            $fatal(1,"Cave Arch not finished by driving: at (%0d,%0d) tilt %0d, furthest x=%0d, outside=%b",
                   vehicle_x/256,vehicle_y/256,vehicle_tilt,max_x/256,outside);
        $display("PASS cave_arch_drive_tb: driven from spawn to the flag in %0d updates (%0d s at 60 Hz, %0d reversals)",steps,steps/60,reversals);
        $finish;
    end
endmodule
