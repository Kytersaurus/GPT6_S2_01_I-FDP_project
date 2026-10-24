// Owner: Role 3 - Yap Ting; hazard, goal and bounds checks.
`timescale 1ns / 1ps
`include "game_defs.vh"

module world_outcomes_tb;
    reg clk=0, reset=1, run_init=0;
    reg [2:0] game_state=`LP_BUILD;
    wire init_ready;
    reg movement_committed=0;
    reg signed [15:0] vehicle_x=0, vehicle_y=0;
    reg [26:0] build_grid=0;
    reg [8:0] intact_mask=0;
    reg [31:0] goal_rect=0;
    reg [1:0] hazard_count=0;
    reg [63:0] hazard_rects=0;
    wire world_valid, goal_hit, hazard_hit, out_of_bounds;
    reg world_ready=0;
    integer waited;

    always #5 clk=~clk;

    world_outcomes dut(
        .clk(clk), .reset(reset), .run_init(run_init), .game_state(game_state),
        .init_ready(init_ready), .movement_committed(movement_committed),
        .vehicle_x(vehicle_x), .vehicle_y(vehicle_y), .build_grid(build_grid),
        .intact_mask(intact_mask), .goal_rect(goal_rect),
        .hazard_count(hazard_count), .hazard_rects(hazard_rects),
        .world_valid(world_valid), .world_ready(world_ready),
        .goal_hit(goal_hit), .hazard_hit(hazard_hit), .out_of_bounds(out_of_bounds)
    );

    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask

    task start_run;
        begin
            game_state=`LP_INIT_RUN;
            run_init=1;
            clocks(2);
            if (!init_ready)
                $fatal(1, "World module did not report init_ready");
            run_init=0;
            game_state=`LP_RUN;
            clocks(1);
        end
    endtask

    task check_pose;
        input integer x, y;
        input expected_goal, expected_hazard, expected_bounds;
        begin
            vehicle_x=x;
            vehicle_y=y;
            movement_committed=1;
            clocks(1);
            movement_committed=0;

            waited=0;
            while (!world_valid && waited < 4) begin
                clocks(1);
                waited=waited+1;
            end

            if (!world_valid ||
                goal_hit !== expected_goal ||
                hazard_hit !== expected_hazard ||
                out_of_bounds !== expected_bounds)
                $fatal(1,
                    "World result mismatch: goal=%b hazard=%b bounds=%b",
                    goal_hit, hazard_hit, out_of_bounds);

            world_ready=1;
            clocks(1);
            world_ready=0;
            if (world_valid)
                $fatal(1, "World result did not release after handshake");
        end
    endtask

    initial begin
        // Pig in cell 4: centre offset is (12,12) pixels.
        build_grid=0;
        build_grid[4*3 +: 3]=`LP_PART_PIG;
        intact_mask=9'b000010000;

        // Shared goal format is {height,width,y,x}.
        goal_rect={8'd24,8'd16,8'd32,8'd80};

        // Level 2 spike pit: x=36..52, y=58..62.
        hazard_count=1;
        hazard_rects={32'd0,8'd4,8'd16,8'd58,8'd36};

        clocks(3);
        reset=0;
        clocks(1);
        start_run();

        // Vehicle bottom is 56, so it is just above the hazard.
        check_pose(4*256,32*256,0,0,0);

        // Vehicle spans x=36..60 and y=40..64, intersecting the pit.
        check_pose(36*256,40*256,0,1,0);

        // Pig centre is x=92,y=44, inside the goal.
        check_pose(80*256,32*256,1,0,0);

        // Vehicle starts at the right world boundary.
        check_pose(96*256,32*256,0,0,1);

        $display("PASS world_outcomes_tb: goal, hazard and bounds checks with valid/ready response");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "World outcomes test timed out");
    end
endmodule
