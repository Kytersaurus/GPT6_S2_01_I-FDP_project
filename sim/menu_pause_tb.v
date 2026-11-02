`timescale 1ns / 1ps
`include "game_defs.vh"
module menu_pause_tb;
    reg clk=0,reset=1,launch=0,tick=0,open=0,back=0,world=0;
    wire [2:0] state;
    wire step_start,world_ready,release_step;
    always #5 clk=~clk;
    game_controller dut(.clk(clk),.reset(reset),.launch_req(launch),.retry_req(1'b0),.edit_req(1'b0),
        .guide_open_req(1'b0),.guide_close_req(1'b0),.level_next_req(1'b0),.level_open_req(open),
        .level_close_req(back),.level_select_req(1'b0),.end_try_req(1'b0),.selected_level(2'd0),
        .build_valid(1'b1),.pig_alive(1'b1),.init_ready(3'b111),.physics_tick(tick),
        .world_valid(world),.world_ready(world_ready),.gameplay_pending(1'b0),.gameplay_ready(),
        .goal_hit(1'b0),.hazard_hit(1'b0),.out_of_bounds(1'b0),.star_box_hit(1'b0),
        .star_box_collected(),.enable_start_screen(1'b0),.start_screen_active(),.par_time(8'd20),
        .game_state(state),.guide_return_state(),.level_index(),.fail_reason(),.run_seconds(),
        .run_init(),.step_start(step_start),.update_release(release_step),.launch_event(),.success_event(),.failure_event());
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    initial begin
        clocks(2);reset=0;launch=1;clocks(1);launch=0;clocks(2);
        if(state!=`LP_RUN) $fatal(1,"Launch failed");
        tick=1;clocks(1);tick=0;
        if(!step_start || !world_ready) $fatal(1,"Update not started");
        open=1;clocks(1);open=0;clocks(4);
        if(state!=`LP_RUN || !world_ready) $fatal(1,"Settings abandoned in-flight collision");
        world=1;clocks(1);world=0;
        if(!release_step) $fatal(1,"Collision completion not released");
        clocks(1);if(state!=`LP_SETTINGS) $fatal(1,"Pending settings request lost");
        back=1;clocks(1);back=0;
        if(state!=`LP_RUN) $fatal(1,"Settings did not resume run");
        tick=1;clocks(1);tick=0;
        if(!step_start || !world_ready) $fatal(1,"Resumed run deadlocked");
        $display("PASS menu_pause_tb: settings waits for collision completion and resumes updates");$finish;
    end
    initial begin #10000;$fatal(1,"Menu pause timeout");end
endmodule
