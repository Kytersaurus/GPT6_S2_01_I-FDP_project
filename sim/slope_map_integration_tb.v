// Owner: Shared. Real terrain slope forces through the movement handshake.
`timescale 1ns / 1ps
`include "game_defs.vh"

module slope_map_integration_tb;
    reg clk=0, reset=1, run_init=0, step_start=0, update_release=0;
    reg [2:0] state=`LP_BUILD;
    reg map_id=0, engine_enabled=0, engine_reverse=0;
    reg [3:0] engines=0, balloons=0;
    reg [7:0] mass=11;
    reg signed [`LP_COORD_BITS-1:0] spawn_x=150*256, spawn_y=44*256;
    wire initialized, move_valid, move_ready, response_valid, response_ready, grounded, committed;
    wire signed [`LP_COORD_BITS-1:0] px, py, nx, ny, cx, cy, x, y;
    wire signed [15:0] nvx, nvy, cvx, cvy;
    wire signed [7:0] slope;
    wire signed [10:0] qx, qy;
    wire query_solid;
    wire [2:0] query_class=query_solid ? `LP_MAP_ROCK : `LP_MAP_SKY;
    wire [9:0] width=map_id ? `LP_FLIGHT_WIDTH : `LP_MAP_WIDTH;
    wire [9:0] height=map_id ? `LP_FLIGHT_HEIGHT : `LP_MAP_HEIGHT;
    wire collision_reset=reset || run_init || state!=`LP_RUN;
    reg [2:0] arch[0:512*`LP_MAP_HEIGHT-1];
    reg [2:0] flight[0:1024*`LP_FLIGHT_HEIGHT-1];
    integer waited, max_latency=0, updates=0, steps, expected_vx;
    integer xx, yy, left_pixel, right_pixel, top_pixel, bottom_pixel, support;
    always #5 clk=~clk;
    initial begin
        $readmemh("cave_arch_map.mem",arch);
        $readmemh("cave_flight_map.mem",flight);
    end

    physics_engine physics (
        .clk(clk), .reset(reset), .game_state(state), .run_init(run_init), .init_ready(initialized),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(4'd0), .engine_count(engines), .balloon_count(balloons), .mass_units(mass),
        .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(1'b0),
        .boost_req(1'b0), .boost_active(), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(nvx), .proposed_vy(nvy), .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy),
        .grounded(grounded), .ground_slope(slope), .movement_committed(committed),
        .vehicle_x(x), .vehicle_y(y)
    );
    collision_engine collision (
        .clk(clk), .reset(collision_reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(nvx), .proposed_vy(nvy), .terrain_count(3'd0), .terrain_rects(128'd0),
        .map_level(1'b1), .world_width(width), .world_height(height),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy),
        .grounded(grounded), .ground_slope(slope)
    );
    level_map rom (
        .map_id(!map_id), .draw_clk(clk), .draw_x(11'sd0), .draw_y(11'sd0), .draw_class(),
        .query_clk(clk), .query_map_id(map_id), .query_x(qx), .query_y(qy),
        .query_class(), .query_solid(query_solid)
    );

    function is_solid;
        input integer test_x, test_y;
        reg [2:0] value;
        begin
            value=0;
            if(test_x>=0 && test_x<width && test_y>=0 && test_y<height)
                value=map_id ? flight[test_y*1024+test_x] : arch[test_y*512+test_x];
            is_solid=value>=`LP_MAP_ROCK && value<=`LP_MAP_DARK;
        end
    endfunction
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task initialize_run;
        begin
            reset=1; run_init=0; state=`LP_BUILD; step_start=0; update_release=0;
            clocks(3); reset=0; state=`LP_INIT_RUN; run_init=1; clocks(2);
            if(!initialized || x!==spawn_x || y!==spawn_y)
                $fatal(1,"Real-map slope initialization failed");
            run_init=0; state=`LP_RUN; clocks(1);
        end
    endtask
    task validate_pose;
        begin
            left_pixel=$signed(x) >>> 8; right_pixel=($signed(x)+6143) >>> 8;
            top_pixel=$signed(y) >>> 8; bottom_pixel=($signed(y)+6143) >>> 8;
            for(yy=top_pixel; yy<=bottom_pixel; yy=yy+1)
                for(xx=left_pixel; xx<=right_pixel; xx=xx+1)
                    if(is_solid(xx,yy))
                        $fatal(1,"Connected vehicle penetrated map %0d at (%0d,%0d), update %0d",map_id,xx,yy,updates);
            if(grounded) begin
                support=0;
                for(xx=left_pixel; xx<=right_pixel; xx=xx+1)
                    if(is_solid(xx,($signed(y)+6144) >>> 8)) support=1;
                if(!support || cvy!==0 || y[7:0]!==0)
                    $fatal(1,"Connected slope vehicle grounded without exact terrain support");
            end else if(slope!==0)
                $fatal(1,"Connected airborne response retained terrain slope");
        end
    endtask
    task do_step;
        begin
            step_start=1; clocks(1); step_start=0;
            waited=0;
            while(!committed && waited<30000) begin clocks(1); waited=waited+1; end
            if(!committed) $fatal(1,"Connected slope update exceeded movement budget");
            if(waited>max_latency) max_latency=waited;
            updates=updates+1;
            validate_pose;
            update_release=1; clocks(1); update_release=0;
        end
    endtask

    initial begin
        // This section of the actual Arch road descends one pixel per pixel.
        // No engines, wheels or testbench-written velocity can initiate motion.
        initialize_run;
        do_step;
        if(!grounded || slope!==8'sd16 || cvx!==0 || x!==150*256 || y!==44*256)
            $fatal(1,"Actual Arch ramp did not establish a stationary 1:1 slope");
        for(steps=1; steps<=24; steps=steps+1) begin
            do_step;
            expected_vx=steps<16 ? steps*16 : 256;
            if(!grounded || slope!==8'sd16 || $signed(cvx)!==expected_vx || cvy!==0)
                $fatal(1,"Downhill update %0d: vx=%0d slope=%0d ground=%b expected vx=%0d",steps,cvx,slope,grounded,expected_vx);
        end
        if(x<=165*256 || y<=59*256)
            $fatal(1,"Engine-free vehicle failed to follow the actual descending road");

        // Reverse thrust can drive uphill when it exceeds slope gravity.
        engines=1; engine_enabled=1; engine_reverse=1; mass=4;
        initialize_run;
        do_step;
        for(steps=1; steps<=12; steps=steps+1) begin
            do_step;
            if(!grounded || slope!==8'sd16 || $signed(cvx)!==-8*steps)
                $fatal(1,"Uphill engine update %0d failed: vx=%0d slope=%0d ground=%b",steps,cvx,slope,grounded);
        end
        if(x>=spawn_x || y>=spawn_y) $fatal(1,"Powered vehicle failed to climb actual Arch road");

        // Flight's spawn is a ledge, whose irregular edges must not invent a
        // downhill gradient. Then real balloon lift must clear ground contact.
        map_id=1; spawn_x=68*256; spawn_y=178*256;
        engines=0; engine_enabled=0; engine_reverse=0; mass=11;
        initialize_run;
        for(steps=0; steps<4; steps=steps+1) begin
            do_step;
            if(!grounded || slope!==0 || cvx!==0 || x!==spawn_x || y!==spawn_y)
                $fatal(1,"Flight ledge manufactured sliding: x=%0d y=%0d vx=%0d slope=%0d",x,y,cvx,slope);
        end
        balloons=2;
        for(steps=0; steps<4; steps=steps+1) begin
            do_step;
            if(grounded || slope!==0 || cvx!==0 || x!==spawn_x || y>=spawn_y || cvy>=0)
                $fatal(1,"Balloon ascent retained slope contact or failed to rise");
        end
        $display("PASS slope_map_integration_tb: %0d connected real-map updates, engine-free downhill, powered uphill, full footprint, ledge rejection, balloon detachment; max latency=%0d clocks",updates,max_latency);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Connected slope test timed out"); end
endmodule
