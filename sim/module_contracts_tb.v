// Owner: Shared - Roles 1, 3 and 4 maintain their checks.
`timescale 1ns / 1ps
`include "game_defs.vh"
module module_contracts_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [2:0] builder_state=`LP_BUILD;
    reg builder_init=0, damage_valid=0;
    reg [8:0] damage_mask=0;
    wire builder_ready, damage_ready, valid, pig_alive;
    wire [26:0] grid;
    wire [8:0] frames, intact, frame_intact;
    wire [3:0] error, wheels, engines, balloons;
    wire [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left;
    wire [7:0] mass;
    vehicle_builder builder (
        .clk(clk),.reset(reset),.game_state(builder_state),.run_init(builder_init),.init_ready(builder_ready),
        .edit_valid(1'b0),.edit_op(2'd0),.edit_cell(4'd0),.edit_source(4'd15),.edit_part(3'd0),
        .damage_valid(damage_valid),.damage_ready(damage_ready),.damage_mask(damage_mask),.damage_frame_mask(9'd0),
        .build_grid(grid),.build_frames(frames),.intact_mask(intact),.frame_intact_mask(frame_intact),
        .build_valid(valid),.build_error(error),.pig_alive(pig_alive),
        .wheel_count(wheels),.engine_count(engines),.balloon_count(balloons),.mass_units(mass),
        .frames_left(frames_left),.pigs_left(pigs_left),.wheels_left(wheels_left),
        .engines_left(engines_left),.balloons_left(balloons_left)
    );
    reg move_valid=0, response_ready=0;
    wire move_ready, response_valid, grounded;
    reg signed [15:0] px=1024, py=7936, nx=1024, ny=8704, nvx=0, nvy=512;
    wire signed [15:0] cx,cy,cvx,cvy;
    collision_engine collision (
        .clk(clk),.reset(reset),.move_valid(move_valid),.move_ready(move_ready),
        .previous_x(px),.previous_y(py),.proposed_x(nx),.proposed_y(ny),.proposed_vx(nvx),.proposed_vy(nvy),
        .terrain_count(3'd1),.terrain_rects({96'd0,8'd8,8'd96,8'd56,8'd0}),
        .response_valid(response_valid),.response_ready(response_ready),.corrected_x(cx),.corrected_y(cy),
        .corrected_vx(cvx),.corrected_vy(cvy),.grounded(grounded)
    );
    reg launch=0, retry=0, build_valid=0, live=1, tick=0, world_valid=0, goal=0;
    reg [2:0] ready=0;
    wire [2:0] state;
    wire run_init, world_ready, step, release_step, launch_event, success_event, failure_event;
    game_controller control (
        .clk(clk),.reset(reset),.launch_req(launch),.retry_req(retry),.edit_req(1'b0),
        .guide_open_req(1'b0),.guide_close_req(1'b0),.level_next_req(1'b0),.build_valid(build_valid),.pig_alive(live),.init_ready(ready),
        .physics_tick(tick),.world_valid(world_valid),.world_ready(world_ready),.goal_hit(goal),
        .gameplay_pending(1'b0),.gameplay_ready(),
        .hazard_hit(1'b0),.out_of_bounds(1'b0),.game_state(state),.run_init(run_init),
        .step_start(step),.update_release(release_step),.launch_event(launch_event),
        .success_event(success_event),.failure_event(failure_event)
    );
    reg [12:0] pixel=0;
    wire [15:0] left_colour, right_colour;
    left_renderer left_view (
        .pixel_index(pixel),.game_state(builder_state),.build_grid(grid),.intact_mask(intact),.frame_intact_mask(frame_intact),
        .build_valid(valid),.build_error(error),.engine_enabled(1'b1),
        .feedback_code(`LP_FEEDBACK_NONE),.feedback_cell(4'd0),
        .frames_left(frames_left),.pigs_left(pigs_left),.wheels_left(wheels_left),
        .engines_left(engines_left),.balloons_left(balloons_left),.selected_part(`LP_PART_FRAME),
        .drag_active(1'b0),.drag_from_grid(1'b0),.drag_source(4'd9),.drag_contents(3'd0),
        .cursor_x(7'd0),.cursor_y(7'd0),.cursor_visible(1'b0),.pixel_data(left_colour)
    );
    right_renderer right_view (
        .pixel_index(pixel),.game_state(builder_state),.build_grid(grid),.intact_mask(intact),.frame_intact_mask(frame_intact),
        .vehicle_x(16'sd1024),.vehicle_y(16'sd8192),.terrain_count(3'd1),
        .terrain_rects({96'd0,8'd8,8'd96,8'd56,8'd0}),.goal_rect({8'd24,8'd16,8'd32,8'd80}),
        .spawn_x(16'sd1024),.spawn_y(16'sd8192),.tnt_count(3'd0),.tnt_positions(64'd0),.tnt_intact(4'd0),
        .hazard_count(2'd0),.hazard_rects(64'd0),.pixel_data(right_colour)
    );
    // Test-only gameplay fixture; the hardware builder starts empty.
    task build_test_vehicle;
        begin
            builder.build_grid = {
                `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
                `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
            };
            builder.build_frames = 9'b000111000;
            clocks(2);
        end
    endtask
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    initial begin
        clocks(3); reset=0; clocks(2); build_test_vehicle();
        if (!valid || !pig_alive || wheels!=2 || engines!=1 || mass!=13) $fatal(1,"Initial properties incorrect");
        pixel=24*96+24; #1; if (left_colour != 16'h07e0) $fatal(1,"Left pig inside frame incorrect");
        pixel=24*96+21; #1; if (left_colour != 16'ha285) $fatal(1,"Left frame border missing");
        pixel=5*96+84; #1; if (left_colour != 16'hffff) $fatal(1,"Remaining frame count not drawn");
        pixel=42*96+14; #1; if (right_colour != 16'h07e0) $fatal(1,"Right pig inside frame incorrect");
        pixel=42*96+12; #1; if (right_colour != 16'ha285) $fatal(1,"Right frame border missing");
        pixel=60*96+40; #1; if (right_colour != 16'h8320) $fatal(1,"Terrain pixel incorrect");
        pixel=40*96+85; #1; if (right_colour != 16'h0320) $fatal(1,"Goal rectangle helper not connected");
        clocks(1); // Return to a falling edge after the pixel checks before driving requests.
        builder_state=`LP_RUN; damage_mask=9'b000100000; damage_valid=1; clocks(1); damage_valid=0; clocks(1);
        if (engines!=0 || mass!=10 || grid[17:15]!=`LP_PART_ENGINE) $fatal(1,"Damage corrupted original build/properties");
        damage_mask=9'b000010000; damage_valid=1; clocks(3); damage_valid=0;
        if (pig_alive) $fatal(1,"Pig destruction not applied");
        builder_state=`LP_INIT_RUN; builder_init=1; clocks(2);
        if (!builder_ready || !pig_alive || engines!=1 || intact!=9'b101110000 ||
            frame_intact!=9'b000111000) $fatal(1,"Retry did not restore build");
        builder_init=0;

        move_valid=1; clocks(1); move_valid=0; clocks(2);
        if (!response_valid || !grounded || cy!=8192 || cvy!=0) $fatal(1,"Platform crossing failed");
        ny=12000; clocks(5);
        if (!response_valid || move_ready || cy!=8192) $fatal(1,"Collision response changed under backpressure");
        response_ready=1; clocks(1); response_ready=0;
        nx=24576; move_valid=1; clocks(1); move_valid=0; clocks(2);
        if (grounded || cy!=12000) $fatal(1,"Non-overlapping vehicle landed on ground");
        response_ready=1; clocks(1);

        launch=1; clocks(1); launch=0; clocks(2);
        if (state!=`LP_BUILD) $fatal(1,"Invalid build launched");
        build_valid=1; launch=1; clocks(1); launch=0; ready=3'b001; clocks(3);
        if (state!=`LP_INIT_RUN) $fatal(1,"Controller ignored delayed readiness");
        ready=3'b111; clocks(2);
        if (state!=`LP_RUN) $fatal(1,"Ready modules did not start RUN");
        tick=1; clocks(1); tick=0; clocks(1);
        goal=1; live=0; world_valid=1; clocks(1); world_valid=0;
        if (state!=`LP_FAIL || !failure_event || success_event) $fatal(1,"Goal incorrectly outranked pig death");
        clocks(1); if (failure_event) $fatal(1,"Result audio event repeated");
        $display("PASS module_contracts_tb: damage/retry, pixels, landing, backpressure, invalid launch, readiness, failure priority");
        $finish;
    end
    initial begin #10000; $fatal(1,"Module contracts test timed out"); end
endmodule
