`timescale 1ns / 1ps
`include "game_defs.vh"
// Synthetic registered-ROM fixtures isolate terrain geometry and read latency.
module map_collision_tb;
    reg clk=0, reset=1, move_valid=0, response_ready=0, map_level=1;
    reg signed [19:0] px=0, py=0, nx=0, ny=0;
    reg signed [15:0] vx=0, vy=0;
    reg [9:0] world_width=96, world_height=96;
    wire move_ready, response_valid, grounded;
    wire signed [19:0] cx, cy;
    wire signed [15:0] cvx, cvy;
    wire signed [10:0] qx, qy;
    reg [2:0] terrain_class=0;
    reg [3:0] scene=0, step_height=3;
    reg [72:0] held;
    integer waited, cases=0;
    always #5 clk=~clk;
    function [2:0] terrain;
        input integer x,y;
        begin
            terrain=`LP_MAP_CAVE;
            if (x<0 || x>=96 || y<0 || y>=96) terrain=`LP_MAP_DARK;
            else case (scene)
                0: if (y>=50) terrain=`LP_MAP_ROCK;
                1: if (y >= (x>=40 ? 50-step_height : 50)) terrain=`LP_MAP_GRASS;
                2: if (y>=50 || x>=40) terrain=`LP_MAP_ROAD;
                3: if (y==50) terrain=`LP_MAP_DARK;
                4: if (y==10 || y>=80) terrain=`LP_MAP_ROCK;
                5: if (y>=50 || (x==30 && y==35)) terrain=`LP_MAP_ROCK;
                6: if (y >= (x<40 ? 47 : 50)) terrain=`LP_MAP_GRASS;
                7: if (y>=50 && x<40) terrain=`LP_MAP_ROCK;
                8: if (y >= (x<40 ? 50 : 52)) terrain=`LP_MAP_ROCK;
                9: if (x==39 || y>=80) terrain=`LP_MAP_ROCK;
                10: if (y==23 || y >= (x>=40 ? 47 : 50)) terrain=`LP_MAP_ROCK;
                11: terrain=`LP_MAP_SKY;
                default: terrain=`LP_MAP_CAVE;
            endcase
        end
    endfunction
    always @(posedge clk) terrain_class <= terrain($signed(qx),$signed(qy));
    collision_engine dut (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(vx), .proposed_vy(vy), .terrain_count(3'd0), .terrain_rects(128'd0),
        .map_level(map_level), .world_width(world_width), .world_height(world_height),
        .query_x(qx), .query_y(qy), .query_class(terrain_class),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy), .grounded(grounded)
    );
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task check_case;
        input integer old_x, old_y, new_x, new_y, input_vx, input_vy;
        input integer expected_x, expected_y, expected_vx, expected_vy;
        input expected_ground;
        begin
            map_level=1; world_width=96; world_height=96;
            px=old_x; py=old_y; nx=new_x; ny=new_y; vx=input_vx; vy=input_vy;
            if (!move_ready) $fatal(1,"Map checker unavailable");
            move_valid=1; clocks(1); move_valid=0;
            // All movement properties and the route must have been captured.
            px=0; py=0; nx=0; ny=0; vx=0; vy=0;
            map_level=0; world_width=1; world_height=1;
            waited=0;
            while (!response_valid && waited<100000) begin clocks(1); waited=waited+1; end
            if (!response_valid || cx!==expected_x || cy!==expected_y ||
                cvx!==expected_vx || cvy!==expected_vy || grounded!==expected_ground)
                $fatal(1,"Case %0d scene %0d: x=%0d y=%0d vx=%0d vy=%0d ground=%b latency=%0d expected x=%0d y=%0d vx=%0d vy=%0d g=%b",
                    cases,scene,cx,cy,cvx,cvy,grounded,waited,expected_x,expected_y,expected_vx,expected_vy,expected_ground);
            held={cx,cy,cvx,cvy,grounded}; move_valid=1; clocks(5);
            if (move_ready || !response_valid || {cx,cy,cvx,cvy,grounded}!==held)
                $fatal(1,"Map response changed under backpressure");
            move_valid=0; response_ready=1; clocks(1); response_ready=0;
            if (!move_ready || response_valid) $fatal(1,"Map response did not release");
            cases=cases+1;
        end
    endtask
    initial begin
        clocks(3); reset=0; clocks(1);
        check_case(10*256,26*256,10*256,26*256+32,0,32,10*256,26*256,0,0,1);
        check_case(10*256,20*256,10*256,28*256,0,2048,10*256,26*256,0,0,1);
        check_case(10*256,25*256,10*256,26*256,0,256,10*256,26*256,0,0,1);
        check_case(10*256,26*256,11*256,24*256,256,-512,11*256,24*256,256,-512,0);
        // Recover shallow initial penetration without moving deeper.
        check_case(10*256,27*256,10*256,27*256+32,0,32,10*256,26*256,0,0,1);
        scene=1;
        step_height=1; check_case(15*256,26*256,18*256,26*256+32,768,32,18*256,25*256,768,0,1);
        step_height=2; check_case(15*256,26*256,18*256,26*256+32,768,32,18*256,24*256,768,0,1);
        step_height=3; check_case(15*256,26*256,18*256,26*256+32,768,32,18*256,23*256,768,0,1);
        step_height=4; check_case(15*256,26*256,18*256,26*256+32,768,32,16*256,26*256,0,0,1);
        step_height=3; check_case(17*256,23*256,15*256,23*256+32,-512,32,15*256,26*256,-512,0,1);
        // An upward jump must not gain the grounded step-up allowance.
        check_case(15*256,26*256,18*256,24*256,768,-512,16*256,24*256,0,-512,0);
        step_height=4; check_case(17*256,22*256,15*256,22*256+32,-512,32,15*256,22*256+32,-512,32,0);
        scene=6; check_case(40*256,26*256,39*256,26*256+32,-256,32,39*256,23*256,-256,0,1);
        scene=8; check_case(39*256,26*256,40*256,26*256+32,256,32,40*256,28*256,256,0,1);
        check_case(39*256,26*256,40*256,24*256,256,-512,40*256,24*256,256,-512,0);
        scene=7; check_case(39*256,26*256,40*256,26*256+32,256,32,40*256,26*256+32,256,32,0);
        scene=2; check_case(15*256+128,20*256,18*256+128,21*256,768,256,16*256,21*256,0,256,0);
        scene=9; check_case(40*256+128,20*256,36*256,20*256,-1152,0,40*256,20*256,0,0,0);
        scene=3; check_case(10*256,10*256,10*256,40*256,0,7680,10*256,26*256,0,0,1);
        scene=4; check_case(10*256,12*256,10*256,6*256,0,-1536,10*256,11*256,0,0,0);
        scene=10; check_case(15*256,26*256,18*256,26*256+32,768,32,16*256,26*256,0,0,1);
        // A protrusion between sparse wheel probes must still block the body.
        scene=5; check_case(0,26*256,10*256,26*256+32,2560,32,6*256,26*256,0,0,1);
        scene=0;
        check_case(1024*256,26*256,1025*256,27*256,256,256,1025*256,27*256,256,256,0);
        check_case(10*256,100*256,10*256,102*256,0,512,10*256,102*256,0,512,0);
        check_case(-25*256,-25*256,-24*256,-24*256,256,256,-24*256,-24*256,256,256,0);
        scene=11; check_case(10*256,26*256,11*256,27*256,256,256,11*256,27*256,256,256,0);
        scene=12; check_case(10*256,26*256,11*256,27*256,256,256,11*256,27*256,256,256,0);
        // Reset must cancel a pending read and its response route.
        map_level=1; world_width=96; world_height=96;
        px=10*256; py=26*256; nx=11*256; ny=27*256;
        move_valid=1; clocks(1); move_valid=0; clocks(10);
        reset=1; clocks(1); reset=0; clocks(3);
        if (!move_ready || response_valid) $fatal(1,"Reset left a map transaction pending");
        scene=0; check_case(10*256,26*256,10*256,26*256+32,0,32,10*256,26*256,0,0,1);
        $display("PASS map_collision_tb: %0d cases, swept floors/walls/ceilings, step/snap, jumps, bounds, route capture, reset and backpressure",cases);
        $finish;
    end
    initial begin #30000000; $fatal(1,"Map collision test timed out"); end
endmodule
