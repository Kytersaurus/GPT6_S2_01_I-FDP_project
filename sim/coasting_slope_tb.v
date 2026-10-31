// Owner: Role 2/3 integration. Engine-off momentum on real cave terrain.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Engine-off coasting must retain momentum down the real Cave Arch slope.
module coasting_slope_tb #(parameter TWO_SIDED=0, ENABLE_MOMENTS=0);
    localparam WHEEL_TORQUE_SHIFT=2;
    localparam [26:0] CART_GRID={(`LP_PART_WHEEL & {3{TWO_SIDED!=0}}),`LP_PART_EMPTY,(`LP_PART_WHEEL & {3{TWO_SIDED!=0}}),
        `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL};
    localparam [8:0] CART_PARTS=TWO_SIDED ? 9'b101011101 : 9'b101011000;
    reg clk=0, reset=1, run_init=0, step_start=0, update_release=0, engine_reverse=0;
    reg [2:0] game_state=`LP_BUILD;
    reg engine_on=1;
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
        .build_grid(CART_GRID),
        .build_frames(9'b000111000),.frame_intact_mask(9'b000111000),
        .intact_mask(CART_PARTS),.build_facing_left(9'd0),.rocket_vertical_mask(9'd0),
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(TWO_SIDED ? 4'd4 : 4'd2), .wheels_down(4'd2), .wheels_up(TWO_SIDED ? 4'd2 : 4'd0), .tip_dir(tip_dir), .support_unstable(unstable),
        .engine_count(4'd1), .balloon_count(4'd0), .mass_units(TWO_SIDED ? 8'd15 : 8'd13),
        .engine_enabled(engine_on), .engine_reverse(engine_reverse), .jump_press(1'b0), .boost_req(1'b0),
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
        .build_grid(CART_GRID),
        .part_intact_mask(CART_PARTS), .frame_intact_mask(9'b000111000),
        .collision_mask(CART_PARTS | 9'b000111000), .world_width(world_width), .world_height(world_height),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .ground_slope(ground_slope), .corrected_tilt(corrected_tilt), .tip_dir(tip_dir)
    );

    integer updates,waited,coast_updates=0,previous_speed,low_speed=256;
    reg lost_momentum=0;
    reg trace_collision;
    initial trace_collision=$test$plusargs("trace_collision");
    always @(posedge clk) begin
        if(trace_collision && updates>=244 && updates<=249 &&
           (u_collision.u_rotated_map.phase==4 || u_collision.u_rotated_map.phase==7 ||
            u_collision.u_rotated_map.phase==10 || u_collision.u_rotated_map.phase==26))
            $display("CONTACT update=%0d phase=%0d hit=%0b attempt=%0d allow_snap=%0b moving_up=%0b prev_y=%0d proposed_y=%0d proposed_vy=%0d old_tilt=%0d proposed_tilt=%0d work_x=%0d work_y=%0d candidate_y=%0d result_vx=%0d",
                updates,u_collision.u_rotated_map.phase,u_collision.u_rotated_map.scan_hit,
                u_collision.u_rotated_map.attempts,u_collision.u_rotated_map.allow_snap,
                u_collision.u_rotated_map.moving_up,previous_y,proposed_y,proposed_vy,
                previous_tilt,proposed_tilt,u_collision.u_rotated_map.work_x,
                u_collision.u_rotated_map.work_y,u_collision.u_rotated_map.candidate_y,
                u_collision.u_rotated_map.result_vx);
    end
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    initial begin
        clocks(3);reset=0;game_state=`LP_INIT_RUN;run_init=1;clocks(3);
        run_init=0;game_state=`LP_RUN;clocks(1);updates=0;previous_speed=0;
        while(vehicle_x<450*256 && updates<420) begin
            if(vehicle_x>=300*256) engine_on=0;
            previous_speed=u_physics.velocity_x;
            step_start=1;clocks(1);step_start=0;waited=0;
            while(!movement_committed && waited<300000) begin clocks(1);waited=waited+1;end
            if(!movement_committed) $fatal(1,"Coasting downhill movement stalled");
            if(!engine_on) begin
                coast_updates=coast_updates+1;
                if(u_physics.velocity_x<low_speed) low_speed=u_physics.velocity_x;
                $display("COAST %0d x=%0d y=%0d vx=%0d oldvx=%0d proposed=%0d tilt=%0d ground=%0b slope=%0d sampled_slope=%0d unstable=%0b tip=%0d sampled_tip=%0d gravity_force=%0d",
                    updates,vehicle_x,vehicle_y,u_physics.velocity_x,previous_speed,proposed_vx,vehicle_tilt,
                    grounded,ground_slope,u_physics.sampled_slope,unstable,tip_dir,u_physics.sampled_tip,u_physics.step_slope_force);
                // Two rolling wheels lose at most 2 Q8 velocity units to drag
                // at this mass. A non-uphill contact must not brake by >4.
                if(u_physics.sampled_slope>=0 && previous_speed>128 &&
                   u_physics.velocity_x<previous_speed-4) lost_momentum=1;
            end
            update_release=1;clocks(1);update_release=0;clocks(1);updates=updates+1;
            if(lost_momentum) $fatal(1,"Non-uphill contact killed engine-off momentum at update %0d",updates);
        end
        if(coast_updates<20 || vehicle_x<450*256 || vehicle_y<180*256)
            $fatal(1,"Unpowered cart failed downhill progress: x%0d y%0d vx%0d",vehicle_x,vehicle_y,u_physics.velocity_x);
        $display("PASS coasting_slope_tb: TWO_SIDED=%0d ENABLE_MOMENTS=%0d coasted downhill in %0d updates; minimum speed=%0d",TWO_SIDED,ENABLE_MOMENTS,coast_updates,low_speed);$finish;
    end
    initial begin #1000000000;$fatal(1,"Coasting slope timeout");end
endmodule
