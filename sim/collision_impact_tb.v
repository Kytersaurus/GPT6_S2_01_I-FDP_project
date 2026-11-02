// Owner: Role 3 - Yap Ting; hard-impact direction and threshold checks.
`timescale 1ns / 1ps
`include "game_defs.vh"

module collision_impact_tb;
    reg clk=0, reset=1, move_valid=0, response_ready=0;
    reg signed [`LP_COORD_BITS-1:0] previous_x=0, previous_y=0;
    reg signed [`LP_COORD_BITS-1:0] proposed_x=0, proposed_y=0;
    reg signed [15:0] proposed_vx=0, proposed_vy=0;
    reg [3:0] scene=0;
    reg [2:0] query_class=0;
    wire move_ready, response_valid, grounded, impact_valid;
    wire [3:0] impact_flags;
    wire signed [10:0] query_x, query_y;
    wire signed [`LP_COORD_BITS-1:0] corrected_x, corrected_y;
    wire signed [15:0] corrected_vx, corrected_vy;
    wire signed [7:0] ground_slope;
    integer waited;

    always #5 clk=~clk;

    // Small registered terrain fixture: a floor, vertical wall, ceiling, or
    // floor+wall corner.  It exercises the same query handshake as level_map.
    function [2:0] terrain_at;
        input integer x, y;
        begin
            terrain_at=`LP_MAP_SKY;
            if (x<0 || x>=96 || y<0 || y>=96)
                terrain_at=`LP_MAP_DARK;
            else case (scene)
                0: if (y>=50) terrain_at=`LP_MAP_ROCK;
                1: if (x==50) terrain_at=`LP_MAP_ROCK;
                2: if (y<=10) terrain_at=`LP_MAP_ROCK;
                3: if (y>=50 || x==50) terrain_at=`LP_MAP_ROCK;
                default: terrain_at=`LP_MAP_SKY;
            endcase
        end
    endfunction

    always @(posedge clk)
        query_class <= terrain_at($signed(query_x),$signed(query_y));

    collision_engine #(.IMPACT_THRESHOLD(512)) dut (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y),
        .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy),
        .terrain_count(3'd0), .terrain_rects(128'd0), .map_level(1'b1),
        .rotation_enabled(1'b0), .previous_tilt(5'sd0), .proposed_tilt(5'sd0),
        .collision_mask(9'h1ff), .world_width(10'd96), .world_height(10'd96),
        .query_x(query_x), .query_y(query_y), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy),
        .grounded(grounded), .ground_slope(ground_slope),
        .corrected_tilt(), .tip_dir(),
        .impact_valid(impact_valid), .impact_flags(impact_flags)
    );

    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask

    task check_case;
        input integer old_x, old_y, new_x, new_y, input_vx, input_vy;
        input [3:0] expected_flags;
        begin
            previous_x=old_x; previous_y=old_y;
            proposed_x=new_x; proposed_y=new_y;
            proposed_vx=input_vx; proposed_vy=input_vy;
            if (!move_ready) $fatal(1,"Impact request unavailable");
            move_valid=1; clocks(1); move_valid=0;
            waited=0;
            while (!response_valid && waited<100000) begin clocks(1); waited=waited+1; end
            if (!response_valid) $fatal(1,"Impact response timed out");
            clocks(2);
            response_ready=1; clocks(1); response_ready=0;
            if (impact_valid !== (expected_flags != 0) ||
                (impact_valid && impact_flags !== expected_flags))
                $fatal(1,"Impact flags=%b expected=%b",impact_flags,expected_flags);
            clocks(1);
        end
    endtask

    initial begin
        clocks(3); reset=0; clocks(1);

        scene=0;
        check_case(10*256,26*256,10*256,34*256,0,1024,`LP_IMPACT_FLOOR);

        scene=1;
        check_case(20*256,20*256,40*256,20*256,1024,0,`LP_IMPACT_RIGHT);
        check_case(70*256,20*256,50*256,20*256,-1024,0,`LP_IMPACT_LEFT);

        scene=2;
        check_case(20*256,20*256,20*256,0,0,-1024,`LP_IMPACT_CEILING);

        scene=3;
        check_case(20*256,20*256,40*256,40*256,1024,1024,
                   `LP_IMPACT_FLOOR | `LP_IMPACT_RIGHT);

        // A normal landing below the hard-impact threshold remains harmless.
        scene=0;
        check_case(10*256,26*256,10*256,27*256,0,256,4'b0);

        $display("PASS collision_impact_tb: hard landing, left/right walls, ceiling, corner and threshold");
        $finish;
    end

    initial begin
        #30000000; $fatal(1,"Collision impact test timed out");
    end
endmodule
