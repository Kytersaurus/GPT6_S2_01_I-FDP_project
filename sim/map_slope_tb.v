// Owner: Role 2 - Kyle; terrain-gradient and movement handshake integration.
`timescale 1ns / 1ps
`include "game_defs.vh"
// One-cycle registered terrain fixtures exercise the same query timing as ROM.
module map_slope_tb;
    reg clk=0, reset=1, move_valid=0, response_ready=0, map_level=1;
    reg signed [`LP_COORD_BITS-1:0] px=0, py=0, nx=0, ny=0;
    reg signed [15:0] vx=0, vy=0;
    reg [9:0] world_width=192, world_height=192;
    reg [3:0] scene=0;
    reg [2:0] terrain_class=`LP_MAP_SKY;
    wire signed [10:0] query_x, query_y;
    wire signed [`LP_COORD_BITS-1:0] cx, cy;
    wire signed [15:0] cvx, cvy;
    wire signed [7:0] ground_slope;
    wire move_ready, response_valid, grounded;
    reg [80:0] held;
    integer waited, cases=0;
    always #5 clk=~clk;

    function [2:0] terrain;
        input integer x, y;
        integer floor_y;
        begin
            floor_y=80;
            case (scene)
                1: floor_y=80+x-40;             // Down to the right, gradient +1.
                2: floor_y=143-x;               // Up to the right, gradient -1.
                3: floor_y=80+((x-40) >>> 1);   // Gradient +1/2.
                4: floor_y=80+((63-x) >>> 1);   // Gradient -1/2.
                5: floor_y=80+2*(x-40);         // Too steep for supported slopes.
                7: floor_y=80+x-2;              // Left gradient probe is off map.
                8: floor_y=269-x;               // Right gradient probe is off map.
                9: floor_y=x<44 ? 80 : 100;     // Cliff beyond the local scan window.
                default: floor_y=80;
            endcase
            terrain=`LP_MAP_CAVE;
            if (x>=0 && x<192 && y>=0 && y<192) begin
                if (y>=floor_y) terrain=`LP_MAP_GRASS;
                // A solid at the top of a profile window is a wall, not floor.
                if (scene==6 && x==36 && y>=60) terrain=`LP_MAP_ROCK;
            end
        end
    endfunction
    always @(posedge clk) terrain_class<=terrain($signed(query_x),$signed(query_y));

    collision_engine dut (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(vx), .proposed_vy(vy), .terrain_count(3'd1),
        .terrain_rects({96'd0,8'd112,8'd192,8'd80,8'd0}),
        .map_level(map_level), .world_width(world_width), .world_height(world_height),
        .query_x(query_x), .query_y(query_y), .query_class(terrain_class),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy), .corrected_vx(cvx), .corrected_vy(cvy),
        .grounded(grounded), .ground_slope(ground_slope)
    );

    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task check_case;
        input integer old_x, old_y, new_x, new_y, input_vx, input_vy;
        input integer expected_x, expected_y, expected_vx, expected_vy;
        input expected_ground;
        input integer expected_slope;
        reg selected_map;
        begin
            selected_map=map_level;
            world_width=192; world_height=192;
            px=old_x; py=old_y; nx=new_x; ny=new_y; vx=input_vx; vy=input_vy;
            if (!move_ready) $fatal(1,"Slope checker unavailable");
            move_valid=1; clocks(1); move_valid=0;
            // Captured movement properties and route must survive changed inputs.
            px=0; py=0; nx=0; ny=0; vx=0; vy=0;
            map_level=!selected_map; world_width=1; world_height=1;
            waited=0;
            while (!response_valid && waited<30000) begin clocks(1); waited=waited+1; end
            if (!response_valid || cx!==expected_x || cy!==expected_y ||
                cvx!==expected_vx || cvy!==expected_vy || grounded!==expected_ground ||
                ground_slope!==expected_slope[7:0])
                $fatal(1,"Case %0d scene %0d: x=%0d y=%0d vx=%0d vy=%0d ground=%b slope=%0d latency=%0d; expected x=%0d y=%0d vx=%0d vy=%0d ground=%b slope=%0d",
                    cases,scene,cx,cy,cvx,cvy,grounded,ground_slope,waited,
                    expected_x,expected_y,expected_vx,expected_vy,expected_ground,expected_slope);
            held={cx,cy,cvx,cvy,grounded,ground_slope};
            move_valid=1; clocks(7);
            if (move_ready || !response_valid || {cx,cy,cvx,cvy,grounded,ground_slope}!==held)
                $fatal(1,"Slope response changed under backpressure");
            move_valid=0; response_ready=1; clocks(1); response_ready=0;
            map_level=selected_map;
            if (!move_ready || response_valid) $fatal(1,"Slope response did not release");
            cases=cases+1;
        end
    endtask

    initial begin
        clocks(3); reset=0; clocks(1);
        // A stationary vehicle needs a measured slope before it can roll away.
        scene=0;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,0);
        scene=1;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,16);
        // Downhill following, uphill step-up and a falling landing retain grade.
        check_case(40*256,56*256,41*256,56*256+32,256,32,41*256,57*256,256,0,1,16);
        check_case(40*256,56*256,39*256,56*256+32,-256,32,39*256,55*256,-256,0,1,16);
        check_case(40*256,50*256,40*256,58*256,0,2048,40*256,56*256,0,0,1,16);
        // Jumping and unsupported motion must publish zero slope.
        check_case(40*256,56*256,40*256,54*256,0,-512,40*256,54*256,0,-512,0,0);
        check_case(40*256,30*256,40*256,30*256+32,0,32,40*256,30*256+32,0,32,0,0);
        scene=2;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,-16);
        check_case(40*256,56*256,41*256,56*256+32,256,32,41*256,55*256,256,0,1,-16);
        check_case(40*256,56*256,39*256,56*256+32,-256,32,39*256,57*256,-256,0,1,-16);
        scene=3;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,8);
        check_case(40*256,56*256,41*256,56*256+32,256,32,41*256,56*256,256,0,1,8);
        scene=4;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,-8);
        // Invalid profiles remain ordinary grounded contacts with no slope force.
        scene=5;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,0);
        scene=6;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,0);
        scene=7;
        check_case(2*256,56*256,2*256,56*256,0,0,2*256,56*256,0,0,1,0);
        scene=8;
        check_case(166*256,56*256,166*256,56*256,0,0,166*256,56*256,0,0,1,0);
        scene=9;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,0);
        // The rectangle route must discard the last map's grade.
        scene=1;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,16);
        map_level=0;
        check_case(40*256,56*256,40*256,56*256,0,0,40*256,56*256,0,0,1,0);
        $display("PASS map_slope_tb: %0d graded terrain, stationary contact, step/snap, air/jump, invalid profiles and handshake cases",cases);
        $finish;
    end
    initial begin #15000000; $fatal(1,"Map slope test timed out"); end
endmodule
