// Owner: Role 2 - Kyle.
`timescale 1ns / 1ps
`include "game_defs.vh"
module physics_engine_tb;
    reg clk=0, reset=1, run_init=0, step_start=0, update_release=0;
    reg [2:0] game_state=`LP_BUILD;
    reg [3:0] balloons=2;
    reg move_ready=0, response_valid=0;
    wire init_ready, move_valid, response_ready, committed;
    integer wait_cycles;
    wire signed [`LP_COORD_BITS-1:0] px,py,nx,ny,x,y;
    wire signed [15:0] nvx,nvy;
    always #5 clk=~clk;
    physics_engine dut (
        .clk(clk),.reset(reset),.game_state(game_state),.run_init(run_init),.init_ready(init_ready),
        .spawn_x(20'sd1024),.spawn_y(20'sd8192),.step_start(step_start),.update_release(update_release),
        .wheel_count(4'd0),.engine_count(4'd0),.balloon_count(balloons),.mass_units(8'd2),.engine_enabled(1'b0),.engine_reverse(1'b0),.jump_press(1'b0),
        .move_valid(move_valid),.move_ready(move_ready),.previous_x(px),.previous_y(py),
        .proposed_x(nx),.proposed_y(ny),.proposed_vx(nvx),.proposed_vy(nvy),
        .response_valid(response_valid),.response_ready(response_ready),
        .corrected_x(nx),.corrected_y(ny),.corrected_vx(nvx),.corrected_vy(nvy),.grounded(1'b0),
        .movement_committed(committed),.vehicle_x(x),.vehicle_y(y)
    );
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    initial begin
        clocks(3); reset=0; game_state=`LP_INIT_RUN; run_init=1; clocks(2);
        if (!init_ready) $fatal(1,"Movement did not initialise");
        run_init=0; game_state=`LP_RUN; step_start=1; clocks(1); step_start=0;
        // Properties are sampled before the force, velocity and position clocks.
        balloons=0;
        if (move_valid) $fatal(1,"Movement published before calculation finished");
        wait_cycles=0;
        while (!move_valid && wait_cycles<64) begin clocks(1); wait_cycles=wait_cycles+1; end
        if (!move_valid || nvy!=-16 || ny!=8176) $fatal(1,"Initial balloon lift incorrect");
        balloons=0; clocks(4);
        if (!move_valid || nvy!=-16 || y!=8192) $fatal(1,"Movement request changed while stalled");
        move_ready=1; clocks(1); move_ready=0; clocks(4);
        if (!response_ready || y!=8192) $fatal(1,"Position committed before response");
        response_valid=1; clocks(1); response_valid=0;
        if (!committed || y!=8176) $fatal(1,"Accepted movement not committed once");
        step_start=1; clocks(3); step_start=0;
        if (move_valid || committed) $fatal(1,"Movement ran before world completion");
        update_release=1; clocks(1); update_release=0;
        balloons=2; step_start=1; clocks(1); step_start=0;
        wait_cycles=0;
        while (!move_valid && wait_cycles<64) begin clocks(1); wait_cycles=wait_cycles+1; end
        if (!move_valid || nvy!=-32 || ny!=8144) $fatal(1,"Negative vertical velocity lost its sign");
        $display("PASS physics_engine_tb: lift, signed arithmetic, stable requests, delayed response, world-release gating");
        $finish;
    end
    initial begin #10000; $fatal(1,"Physics test timed out"); end
endmodule
