// Committed orientation must agree across goals, hazards, TNT and death effects.
`timescale 1ns / 1ps
`include "game_defs.vh"
module rotation_interactions_tb;
    reg clk=0, reset=1, run_init=0, committed=0;
    reg [2:0] state=`LP_BUILD;
    reg signed [19:0] x=40*256, y=40*256;
    reg signed [3:0] tilt=0, previous_tilt=0;
    reg [26:0] grid=0;
    reg [8:0] intact=9'h1ff;
    reg [31:0] goal=0;
    reg [63:0] hazards=0;
    reg [1:0] hazard_count=0;
    reg world_ready=0;
    wire world_valid, goal_hit, hazard_hit, bounds;
    reg pig_alive=1;
    wire [1:0] death_phase;
    wire signed [19:0] death_x, death_y;
    reg tnt_committed=0, damage_ready=0;
    wire damage_valid, damage_complete, explosion_event;
    wire [8:0] damage_mask, frame_mask;
    wire [3:0] tnt_intact;
    integer cases=0, waited;
    reg [2:0] held_flags;
    always #5 clk=~clk;

    world_outcomes world (
        .clk(clk),.reset(reset),.run_init(run_init),.game_state(state),.init_ready(),
        .movement_committed(committed),.vehicle_x(x),.vehicle_y(y),.vehicle_tilt(tilt),
        .build_grid(grid),.intact_mask(intact),.goal_rect(goal),
        .map_level(1'b0),.world_width(10'd96),.world_height(10'd96),.flag_x(10'd0),.flag_y(10'd0),
        .hazard_count(hazard_count),.hazard_rects(hazards),.world_valid(world_valid),
        .world_ready(world_ready),.goal_hit(goal_hit),.hazard_hit(hazard_hit),.out_of_bounds(bounds)
    );
    pig_death_effect death (
        .clk(clk),.reset(reset),.run_init(run_init),.physics_tick(1'b0),.pig_alive(pig_alive),
        .game_state(state),.build_grid(grid),.vehicle_x(x),.vehicle_y(y),.vehicle_tilt(tilt),
        .death_phase(death_phase),.death_x(death_x),.death_y(death_y)
    );
    tnt_controller tnt (
        .clk(clk),.reset(reset),.run_init(run_init),.game_state(state),.init_ready(),
        .movement_committed(tnt_committed),.previous_x(x),.previous_y(y),.vehicle_x(x),.vehicle_y(y),
        .previous_tilt(previous_tilt),.vehicle_tilt(tilt),
        .tnt_count(3'd1),.tnt_positions({48'd0,8'd48,8'd60}),
        .build_grid({9{`LP_PART_ENGINE}}),.build_frames(9'h1ff),
        .intact_mask(9'h1ff),.frame_intact_mask(9'h1ff),.tnt_intact(tnt_intact),
        .damage_valid(damage_valid),.damage_ready(damage_ready),.damage_mask(damage_mask),
        .damage_frame_mask(frame_mask),.explosion_event(explosion_event),.damage_complete(damage_complete)
    );
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task start_run;
        begin
            state=`LP_INIT_RUN; run_init=1; pig_alive=1; clocks(2);
            state=`LP_RUN; run_init=0; clocks(1);
        end
    endtask
    task check_world;
        input expected_goal, expected_hazard, expected_bounds;
        begin
            committed=1; clocks(1); committed=0;
            waited=0;
            while(!world_valid && waited<32) begin clocks(1); waited=waited+1; end
            if(!world_valid || goal_hit!==expected_goal || hazard_hit!==expected_hazard || bounds!==expected_bounds)
                $fatal(1,"Rotation world case %0d: goal=%b hazard=%b bounds=%b expected %b%b%b",cases,
                    goal_hit,hazard_hit,bounds,expected_goal,expected_hazard,expected_bounds);
            held_flags={goal_hit,hazard_hit,bounds}; clocks(3);
            if(!world_valid || {goal_hit,hazard_hit,bounds}!==held_flags)
                $fatal(1,"World rotation response did not survive backpressure");
            world_ready=1; clocks(1); world_ready=0; cases=cases+1;
        end
    endtask
    task check_tnt;
        input signed [3:0] angle;
        input [8:0] expected_mask;
        begin
            x=40*256; y=40*256; tilt=angle; previous_tilt=angle;
            start_run;
            tnt_committed=1; clocks(1); tnt_committed=0;
            // An idle orientation bus cannot alter an in-flight blast.
            tilt=-angle; previous_tilt=-angle;
            waited=0;
            while(!damage_valid && waited<80) begin clocks(1); waited=waited+1; end
            if(!damage_valid || damage_mask!==expected_mask || frame_mask!==expected_mask || tnt_intact[0])
                $fatal(1,"TNT angle %0d mask=%b frame=%b expected=%b",angle,damage_mask,frame_mask,expected_mask);
            clocks(3);
            if(!damage_valid || damage_mask!==expected_mask)
                $fatal(1,"Rotated TNT mask changed during backpressure");
            damage_ready=1; clocks(1); damage_ready=0; clocks(1);
            if(!damage_complete) $fatal(1,"Rotated TNT update did not complete");
            cases=cases+1;
        end
    endtask
    initial begin
        grid[2*3 +: 3]=`LP_PART_PIG;
        clocks(3); reset=0; start_run;
        // Top-right pig rotates to (63.3125,52) and (52,40.6875).
        tilt=4; goal={8'd1,8'd1,8'd52,8'd63}; check_world(1,0,0);
        tilt=-4; goal={8'd1,8'd1,8'd40,8'd52}; check_world(1,0,0);
        tilt=0; check_world(0,0,0);
        goal={8'd1,8'd1,8'd44,8'd60}; check_world(1,0,0);
        intact=0; check_world(0,0,0); intact=9'h1ff;
        // A rotated diamond rejects an empty AABB corner and reaches a side tip.
        tilt=4; goal=0; hazard_count=1;
        hazards={32'd0,8'd1,8'd1,8'd67,8'd67}; check_world(0,0,0);
        hazards={32'd0,8'd2,8'd1,8'd51,8'd68}; check_world(0,1,0);
        tilt=0; check_world(0,0,0);
        hazard_count=0;
        // Bounds use the true rotated extent; partial overlap remains playable.
        tilt=4; x=-26*256; check_world(0,0,0);
        x=-29*256; check_world(0,0,1);
        tilt=0; x=-24*256; check_world(0,0,1);
        tilt=4; check_world(0,0,0);
        x=96*256; check_world(0,0,0);
        x=101*256; check_world(0,0,1);
        // Disconnected legacy/invalid tilt inputs retain the level behavior.
        tilt=4'bzzzz; x=40*256; goal={8'd1,8'd1,8'd44,8'd60}; check_world(1,0,0);
        tilt=7; check_world(1,0,0);

        x=40*256; y=40*256; tilt=4; start_run;
        pig_alive=0; clocks(1);
        if(death_phase!==1 || death_x!==20'sd16208 || death_y!==20'sd13312)
            $fatal(1,"Rotated pig burst wrong: (%0d,%0d)",death_x,death_y);
        tilt=-4; x=0; y=0; clocks(2);
        if(death_x!==20'sd16208 || death_y!==20'sd13312)
            $fatal(1,"Pig burst moved after death");
        cases=cases+1;
        check_tnt(4,9'b000110110);
        check_tnt(-4,9'b110110000);
        check_tnt(0,9'b100110100);
        $display("PASS rotation_interactions_tb: %0d rotated goal, SAT hazard, bounds, death, TNT capture/damage and backpressure cases",cases);
        $finish;
    end
    initial begin #100000; $fatal(1,"Rotation interactions test timed out"); end
endmodule
