// Owner: Role 4 - Marcus. Drives Cave Arch from its spawn to the finish flag.
`timescale 1ns / 1ps
`include "game_defs.vh"
// A powered cart must traverse the first Cave Arch downhill without rolling onto its back.
module first_map_slope_tb #(parameter TWO_SIDED=0);
    localparam ENABLE_MOMENTS=0, WHEEL_TORQUE_SHIFT=2;
    localparam [26:0] CART_GRID={(`LP_PART_WHEEL & {3{TWO_SIDED!=0}}),`LP_PART_EMPTY,(`LP_PART_WHEEL & {3{TWO_SIDED!=0}}),
        `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL};
    localparam [8:0] CART_PARTS=TWO_SIDED ? 9'b101011101 : 9'b101011000;
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
        .build_grid(CART_GRID),
        .build_frames(9'b000111000),.frame_intact_mask(9'b000111000),
        .intact_mask(CART_PARTS),.build_facing_left(9'd0),.rocket_vertical_mask(9'd0),
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(TWO_SIDED ? 4'd4 : 4'd2), .wheels_down(4'd2), .wheels_up(TWO_SIDED ? 4'd2 : 4'd0), .tip_dir(tip_dir), .support_unstable(unstable),
        .engine_count(4'd1), .balloon_count(4'd0), .mass_units(TWO_SIDED ? 8'd15 : 8'd13),
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
        .cg_enabled(1'b1), .support_unstable(unstable),
        .build_grid(CART_GRID),
        .part_intact_mask(CART_PARTS), .frame_intact_mask(9'b000111000),
        .collision_mask(CART_PARTS | 9'b000111000), .world_width(world_width), .world_height(world_height),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .ground_slope(ground_slope), .corrected_tilt(corrected_tilt), .tip_dir(tip_dir)
    );

    integer updates,waited,peak_tilt=0,angle;
    reg last_air=0;
    reg signed [4:0] air_tilt=0;
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    initial begin
        clocks(3);reset=0;game_state=`LP_INIT_RUN;run_init=1;clocks(3);
        run_init=0;game_state=`LP_RUN;clocks(1);updates=0;
        while(vehicle_x<450*256 && updates<420) begin
            step_start=1;clocks(1);step_start=0;waited=0;
            while(!movement_committed && waited<300000) begin clocks(1);waited=waited+1;end
            if(!movement_committed) $fatal(1,"First-map slope movement stalled");
            angle=vehicle_tilt;if(angle<0) angle=-angle;
            if(angle>peak_tilt) peak_tilt=angle;
            if(angle>=8) $fatal(1,"Cart flipped on first downhill: step%0d x%0d y%0d tilt%0d spin%0d",updates,vehicle_x,vehicle_y,vehicle_tilt,u_physics.spin);
            if(!grounded && last_air && vehicle_tilt!=air_tilt)
                $fatal(1,"Ledge-induced spin continued in flight: tilt%0d -> %0d",air_tilt,vehicle_tilt);
            last_air=!grounded;air_tilt=vehicle_tilt;
            update_release=1;clocks(1);update_release=0;clocks(1);updates=updates+1;
        end
        if(vehicle_x<450*256 || vehicle_y<180*256) $fatal(1,"Cart failed downhill progress: x%0d y%0d",vehicle_x,vehicle_y);
        $display("PASS first_map_slope_tb: TWO_SIDED=%0d downhill completed in %0d updates; peak tilt=%0d",TWO_SIDED,updates,peak_tilt);$finish;
    end
    initial begin #1000000000;$fatal(1,"First-map slope timeout");end
endmodule
