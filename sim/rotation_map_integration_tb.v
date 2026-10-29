// Owner: Shared. Real terrain slope forces through the movement handshake.
`timescale 1ns / 1ps
`include "game_defs.vh"

module rotation_map_integration_tb;
    reg clk=0, reset=1, run_init=0, step_start=0, update_release=0;
    reg [2:0] state=`LP_BUILD;
    reg map_id=0, engine_enabled=0, engine_reverse=0;
    reg [3:0] engines=0, balloons=0;
    reg [7:0] mass=11;
    reg jump=0;
    wire signed [3:0] old_tilt, wanted_tilt, tilt, result_tilt;
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
        .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(jump),
        .boost_req(1'b0), .boost_active(), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(nvx), .proposed_vy(nvy), .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy),
        .grounded(grounded), .ground_slope(slope), .corrected_tilt(result_tilt), .movement_committed(committed),
        .vehicle_x(x), .vehicle_y(y), .vehicle_tilt(tilt), .previous_tilt(old_tilt), .proposed_tilt(wanted_tilt)
    );
    collision_engine collision (
        .clk(clk), .reset(collision_reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(nvx), .proposed_vy(nvy), .terrain_count(3'd0), .terrain_rects(128'd0),
        .rotation_enabled(1'b1), .previous_tilt(old_tilt), .proposed_tilt(wanted_tilt),
        .map_level(1'b1), .world_width(width), .world_height(height),
        .query_x(qx), .query_y(qy), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy),
        .grounded(grounded), .ground_slope(slope), .corrected_tilt(result_tilt)
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
    function integer coeff_c;
        input integer angle;
        begin case(angle<0 ? -angle : angle)
            0:coeff_c=256;1:coeff_c=251;2:coeff_c=237;3:coeff_c=213;default:coeff_c=181;
        endcase end
    endfunction
    function integer coeff_s;
        input integer angle;
        integer v;
        begin case(angle<0 ? -angle : angle)
            0:v=0;1:v=50;2:v=98;3:v=142;default:v=181;
        endcase coeff_s=angle<0 ? -v : v; end
    endfunction
    function overlap_pixel;
        input integer bx,by,angle,px,py;
        integer c,s,a,dx,dy,u,v,lim,ext;
        begin
            c=coeff_c(angle);s=coeff_s(angle);a=s<0 ? -s : s;
            dx=px*256+128-bx-3072;dy=py*256+128-by-3072;
            u=dx*c+dy*s;v=-dx*s+dy*c;lim=786432+128*(c+a);ext=(12*(c+a)*65536+(c*c+s*s)-1)/(c*c+s*s)+128;
            overlap_pixel=dx<ext && dx>-ext && dy<ext && dy>-ext && u<lim && u>-lim && v<lim && v>-lim;
        end
    endfunction
    task validate_pose;
        begin
            support=0;
            // Whole rotated hull may extend beyond the original24px square.
            for(yy=($signed(y)>>>8)-6;yy<=($signed(y)>>>8)+30;yy=yy+1)
                for(xx=($signed(x)>>>8)-6;xx<=($signed(x)>>>8)+30;xx=xx+1)
                    if(is_solid(xx,yy)) begin
                        if(overlap_pixel(x,y,tilt,xx,yy))
                            $fatal(1,"Rotated hull penetrated map%0d at(%0d,%0d) pose(%0d,%0d) tilt%0d update%0d",map_id,xx,yy,x,y,tilt,updates);
                        if(overlap_pixel(x,y+1,tilt,xx,yy)) support=1;
                    end
            if(grounded && (!support || cvy!==0)) $fatal(1,"Rotated hull grounded without exact support");
            if(!grounded && slope!==0) $fatal(1,"Airborne rotation retained slope force");
            if(tilt>4 || tilt< -4) $fatal(1,"Rotation exceeded supported angle");
        end
    endtask
    task do_step;
        begin
            step_start=1; clocks(1); step_start=0;
            waited=0;
            while(!committed && waited<200000) begin clocks(1); waited=waited+1; end
            if(!committed) $fatal(1,"Connected slope update exceeded movement budget");
            if(waited>max_latency) max_latency=waited;
            updates=updates+1;
            validate_pose;
            update_release=1; clocks(1); update_release=0;
        end
    endtask

    initial begin
        initialize_run;
        do_step;
        if(!grounded || slope!==16 || tilt!==0) $fatal(1,"Ramp spawn did not establish contact");
        for(steps=1;steps<=24;steps=steps+1) begin
            do_step;
            if(steps>=8 && tilt!==4) $fatal(1,"Vehicle failed to align to actual1:1 ramp");
            if(cvx<=0) $fatal(1,"Rotated vehicle failed downhill movement");
        end
        if(x<=165*256 || y<=spawn_y) $fatal(1,"Rotated vehicle failed to follow ramp");
        jump=1;do_step;jump=0;
        if(grounded || tilt!==4 || cvy!==-512) $fatal(1,"Jump did not preserve rotated launch attitude");
        do_step;
        if(grounded || tilt!==4) $fatal(1,"Airborne attitude was lost");

        map_id=1;spawn_x=68*256;spawn_y=178*256;initialize_run;
        if(tilt!==0) $fatal(1,"Retry retained tilt");
        for(steps=0;steps<4;steps=steps+1) begin
            do_step;
            if(!grounded || slope!==0 || tilt!==0 || cvx!==0 || x!==spawn_x || y!==spawn_y)
                $fatal(1,"Flight spawn manufactured rotation or sliding");
        end
        balloons=2;
        for(steps=0;steps<4;steps=steps+1) begin
            do_step;
            if(grounded || slope!==0 || tilt!==0 || y>=spawn_y || cvy>=0) $fatal(1,"Balloon detachment failed");
        end
        $display("PASS rotation_map_integration_tb: %0d actual-map rotated updates, downhill contact, jump/airborne attitude, retry, Flight ledge, balloon lift; max latency=%0d clocks",updates,max_latency);
        $finish;
    end
    initial begin #300000000; $fatal(1,"Connected slope test timed out"); end
endmodule
