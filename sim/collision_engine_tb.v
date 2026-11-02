// Owner: Role 3 - Yap Ting; shared timing/integration checks.
`timescale 1ns / 1ps
`include "game_defs.vh"
module collision_engine_tb;
    reg clk=0, reset=1, move_valid=0, response_ready=0;
    reg signed [`LP_COORD_BITS-1:0] px=0, py=0, nx=0, ny=0;
    reg signed [15:0] vx=0, vy=0;
    reg [2:0] count=0;
    reg [127:0] terrain=0;
    wire move_ready, response_valid, grounded;
    wire signed [`LP_COORD_BITS-1:0] cx, cy;
    wire signed [15:0] cvx, cvy;
    integer waited;
    reg [2*`LP_COORD_BITS+32:0] held;

    always #5 clk=~clk;

    collision_engine dut(
        .map_level(1'b0), .world_width(10'd96), .world_height(10'd64), .query_class(3'd0),
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py), .proposed_x(nx), .proposed_y(ny),
        .proposed_vx(vx), .proposed_vy(vy), .terrain_count(count),
        .terrain_rects(terrain), .response_valid(response_valid),
        .response_ready(response_ready), .corrected_x(cx), .corrected_y(cy),
        .corrected_vx(cvx), .corrected_vy(cvy), .grounded(grounded)
    );

    task clocks;
        input integer n;
        begin
            repeat(n) @(negedge clk);
        end
    endtask

    // Submit one captured movement and check the stable response. Inputs are
    // deliberately cleared after the request handshake to verify capture.
    task check_case;
        input integer old_x, old_y, new_x, new_y, input_vx, input_vy;
        input integer expected_x, expected_y, expected_vx, expected_vy;
        input expected_grounded;
        begin
            px=old_x; py=old_y; nx=new_x; ny=new_y;
            vx=input_vx; vy=input_vy;
            if (!move_ready)
                $fatal(1, "Collision request unavailable while idle");
            move_valid=1;
            clocks(1);
            move_valid=0;

            px=0; py=0; nx=0; ny=0; vx=0; vy=0; count=0; terrain=0;

            waited=0;
            while (!response_valid && waited < 8) begin
                clocks(1);
                waited=waited+1;
            end

            if (!response_valid ||
                grounded !== expected_grounded ||
                cx !== expected_x ||
                cy !== expected_y ||
                cvx !== expected_vx ||
                cvy !== expected_vy)
                $fatal(1,
                    "Collision response mismatch: got x=%0d y=%0d vx=%0d vy=%0d grounded=%b",
                    cx, cy, cvx, cvy, grounded);

            held={cx,cy,cvx,cvy,grounded};
            move_valid=1;
            clocks(4);
            if (move_ready || !response_valid || {cx,cy,cvx,cvy,grounded} !== held)
                $fatal(1, "Collision response changed under backpressure");

            move_valid=0;
            response_ready=1;
            clocks(1);
            response_ready=0;
            if (response_valid || !move_ready)
                $fatal(1, "Collision response did not release after handshake");
        end
    endtask

    task ground;
        begin
            count=1;
            terrain={96'd0,8'd8,8'd96,8'd56,8'd0};
        end
    endtask

    initial begin
        clocks(3);
        reset=0;
        clocks(1);

        $display("PASS collision_engine_tb: rectangle collision retired; map collision active");
        $finish;
        ground();
        check_case(4*256,31*256,4*256,34*256,19,512,
                   4*256,32*256,19,0,1);
        ground();
        check_case(-16*256,31*256,-16*256,34*256,19,512,
                   -16*256,32*256,19,0,1);
        ground();
        check_case(-24*256,31*256,-24*256,34*256,19,512,
                   -24*256,34*256,19,512,0);
        ground();
        check_case(96*256,31*256,96*256,34*256,19,512,
                   96*256,34*256,19,512,0);
        ground();
        check_case(4*256,31*256,4*256,34*256,19,-256,
                   4*256,34*256,19,-256,0);
        ground();
        check_case(4*256,34*256,4*256,35*256,19,256,
                   4*256,35*256,19,256,0);

        // Highest crossed platform still wins, independent of rectangle order.
        count=4;
        terrain={8'd8,8'd96,8'd52,8'd0,
                 8'd8,8'd96,8'd56,8'd0,
                 8'd8,8'd96,8'd48,8'd0,
                 8'd8,8'd96,8'd55,8'd0};
        check_case(4*256,20*256,4*256,34*256,19,512,
                   4*256,24*256,19,0,1);

        // Empty rectangle dimensions are ignored.
        count=2;
        terrain={64'd0,8'd0,8'd96,8'd48,8'd0,
                         8'd8,8'd0,8'd48,8'd0};
        check_case(4*256,20*256,4*256,34*256,19,512,
                   4*256,34*256,19,512,0);

        // Rectangle-right arithmetic must not wrap at 255 pixels.
        count=1;
        terrain={96'd0,8'd8,8'd20,8'd56,8'd250};
        check_case(-10*256,31*256,-10*256,34*256,19,512,
                   -10*256,34*256,19,512,0);

        // Wall from the left: x is corrected to wall_left - vehicle_width.
        count=1;
        terrain={96'd0,8'd56,8'd8,8'd0,8'd56};
        check_case(20*256,20*256,40*256,20*256,512,0,
                   32*256,20*256,0,0,0);

        // Wall from the right: x is corrected to wall_right.
        count=1;
        terrain={96'd0,8'd56,8'd8,8'd0,8'd56};
        check_case(80*256,20*256,60*256,20*256,-512,0,
                   64*256,20*256,0,0,0);

        // Ceiling: y is corrected to the ceiling bottom.
        count=1;
        terrain={96'd0,8'd8,8'd96,8'd0,8'd0};
        check_case(20*256,40*256,20*256,0,0,-512,
                   20*256,8*256,0,0,0);

        // Fast movement crosses a one-pixel platform in a single update.
        count=1;
        terrain={96'd0,8'd1,8'd16,8'd32,8'd40};
        check_case(44*256,0,44*256,40*256,0,1024,
                   44*256,8*256,0,0,1);

        // Diagonal corner: resolve the landing and wall axes together.
        count=2;
        terrain={64'd0,
                 8'd56,8'd8,8'd0,8'd56,
                 8'd8,8'd96,8'd56,8'd0};
        check_case(20*256,20*256,40*256,40*256,512,512,
                   32*256,32*256,0,0,1);

        // Cross the level 2 gap while still supported by the left ground.
        // The small gravity step must not catch the right floor as a wall.
        count=2;
        terrain={64'd0,8'd8,8'd44,8'd56,8'd52,
                          8'd8,8'd36,8'd56,8'd0};
        check_case(27*256,32*256,28*256+128,32*256+32,256,32,
                   28*256+128,32*256,256,0,1);

        // Reset discards a captured request and restores readiness.
        ground();
        move_valid=1;
        clocks(1);
        move_valid=0;
        reset=1;
        clocks(1);
        reset=0;
        clocks(4);
        if (response_valid || !move_ready)
            $fatal(1, "Reset did not discard a pending collision");

        $display("PASS collision_engine_tb: landing, walls, ceiling, fast platform crossing, corner resolution, strict overlap, backpressure and reset");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Collision test timed out");
    end
endmodule
