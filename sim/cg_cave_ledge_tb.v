// Owner: Role 4 - Marcus. Drives Cave Arch from its spawn to the finish flag.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Real Cave Arch ROM regression for the formerly trapped (576,230), -22.5-degree pose.
module cg_cave_ledge_tb;
    localparam ENABLE_MOMENTS=0, WHEEL_TORQUE_SHIFT=2;
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
    wire unstable;
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
    physics_engine #(.ENGINE_FORCE(320),.WHEEL_TORQUE_SHIFT(WHEEL_TORQUE_SHIFT),.ROCKET_FORCE_SHIFT(10)) u_physics (
        .moments_enabled(ENABLE_MOMENTS != 0),
        .build_grid({`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
                     `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,
                     `LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL}),
        .build_frames(9'b000111000),.frame_intact_mask(9'b000111000),
        .intact_mask(9'b101011101),.build_facing_left(9'd0),.rocket_vertical_mask(9'd0),
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready),
        .spawn_x(20'sd147456), .spawn_y(20'sd58880), .step_start(step_start), .update_release(update_release),
        .wheel_count(4'd4), .wheels_down(4'd2), .wheels_up(4'd2), .tip_dir(tip_dir), .support_unstable(unstable),
        .engine_count(4'd1), .balloon_count(4'd0), .mass_units(8'd15),
        .engine_enabled(1'b0), .engine_reverse(engine_reverse), .jump_press(1'b0), .boost_req(1'b0),
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
        .cg_enabled(1'b1), .support_unstable(unstable),
        .build_grid({`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
                     `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,
                     `LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL}),
        .part_intact_mask(9'b101011101), .frame_intact_mask(9'b000111000),
        .collision_mask(9'b101111101), .world_width(world_width), .world_height(world_height),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .ground_slope(ground_slope), .corrected_tilt(corrected_tilt), .tip_dir(tip_dir)
    );

    integer updates,waited,saw_unstable;
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    initial begin
        clocks(3);reset=0;game_state=`LP_INIT_RUN;run_init=1;clocks(3);
        run_init=0;game_state=`LP_RUN;clocks(1);
        // Reproduce the previously trapped, accepted map pose. Do not force any
        // pose/velocity during subsequent updates; movement comes from physics.
        u_physics.vehicle_tilt=-5'sd2;
        updates=0;saw_unstable=0;
        // Wait for both drop and outward clearance; either may happen first.
        while((vehicle_y<234*256 || vehicle_x>=575*256) && updates<120) begin
            step_start=1;clocks(1);step_start=0;waited=0;
            while(!movement_committed && waited<200000) begin clocks(1);waited=waited+1;end
            if(!movement_committed) $fatal(1,"Real cave CG update timeout");
            if(unstable) saw_unstable=1;
            update_release=1;clocks(1);update_release=0;clocks(1);updates=updates+1;
        end
        if(!saw_unstable || vehicle_y<234*256 || vehicle_x>=575*256)
            $fatal(1,"Cave ledge still trapped: x%0d y%0d tilt%0d unstable%0b after%0d",vehicle_x,vehicle_y,vehicle_tilt,unstable,updates);
        $display("PASS cg_cave_ledge_tb: unpowered cart leaves real Arch ledge in %0d updates: x%0d y%0d",updates,vehicle_x,vehicle_y);$finish;
    end
    initial begin #200000000;$fatal(1,"Real cave CG ledge timeout");end
endmodule
