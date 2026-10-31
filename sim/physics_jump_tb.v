// Owner: Role 2 - Kyle; shared integration checks for queued ground-only jumping.
`timescale 1ns / 1ps
`include "game_defs.vh"
module physics_jump_tb;
    reg clk=0,reset=1,run_init=0,step=0,release_step=0,jump=0,accept_move=0,response=0,contact=1;
    reg [2:0] state=`LP_BUILD;
    wire initialized,move_valid,response_ready,committed;
    wire signed [`LP_COORD_BITS-1:0] px,py,nx,ny,x,y;
    wire signed [15:0] nvx,nvy;
    integer waited;
    always #5 clk=~clk;
    physics_engine dut(.clk(clk),.reset(reset),.game_state(state),.run_init(run_init),.init_ready(initialized),
        .spawn_x(20'sd1024),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
        .wheel_count(4'd2),.engine_count(4'd1),.balloon_count(4'd0),.mass_units(8'd13),
        .engine_enabled(1'b0),.engine_reverse(1'b0),.jump_press(jump),
        .move_valid(move_valid),.move_ready(accept_move),.previous_x(px),.previous_y(py),
        .proposed_x(nx),.proposed_y(ny),.proposed_vx(nvx),.proposed_vy(nvy),
        .response_valid(response),.response_ready(response_ready),.corrected_x(nx),
        .corrected_y(contact?20'sd8192:ny),.corrected_vx(nvx),.corrected_vy(contact?16'sd0:nvy),
        .ground_slope(8'sd0), .grounded(contact),.movement_committed(committed),.vehicle_x(x),.vehicle_y(y));
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task begin_step;
        begin step=1;clocks(1);step=0;end
    endtask
    task wait_request;
        begin
            waited=0;while(!move_valid && waited<64) begin clocks(1);waited=waited+1;end
            if(!move_valid) $fatal(1,"Movement handshake missing");
        end
    endtask
    task finish_step;
        begin
            accept_move=1;clocks(1);accept_move=0;
            if(!response_ready) $fatal(1,"Collision response not ready");
            response=1;clocks(1);response=0;
            if(!committed) $fatal(1,"Jump position did not commit");
            release_step=1;clocks(1);release_step=0;
        end
    endtask
    initial begin
        clocks(3);reset=0;state=`LP_INIT_RUN;run_init=1;clocks(2);
        run_init=0;state=`LP_RUN;
        jump=1;begin_step();jump=0;wait_request();
        if(nvy!=32) $fatal(1,"Unconfirmed spawn contact allowed a jump");
        finish_step();
        jump=1;clocks(1);jump=0;clocks(3);begin_step();wait_request();
        if(nvy!=-512 || ny!=7680) $fatal(1,"Queued grounded jump was lost");
        // Keep contact asserted after firing: another press must not fire until release.
        finish_step();jump=1;begin_step();jump=0;wait_request();
        if(nvy!=32) $fatal(1,"Spring repeated during continuous contact");
        contact=0;finish_step();
        jump=1;begin_step();jump=0;wait_request();
        if(nvy!=64) $fatal(1,"Airborne jump reset vertical velocity");
        finish_step();
        begin_step();wait_request();contact=1;finish_step();
        // A grounded press arriving while arithmetic is busy is kept for the next update.
        begin_step();jump=1;clocks(1);jump=0;wait_request();
        if(nvy!=32) $fatal(1,"Late jump altered an already sampled update");
        finish_step();begin_step();wait_request();
        if(nvy!=-512) $fatal(1,"Late grounded jump was not queued");
        contact=0;finish_step();
        begin_step();clocks(5);state=`LP_INIT_RUN;run_init=1;clocks(3);
        if(!initialized || x!=1024 || y!=8192 || move_valid) $fatal(1,"Retry did not cancel active arithmetic/jump");
        run_init=0;state=`LP_RUN;begin_step();wait_request();
        if(nvy!=32) $fatal(1,"Retry retained jump or airborne velocity");
        $display("PASS physics_jump_tb: confirmed-ground jumps, queued/late input, airborne rejection, stable sampling and retry cancellation");
        $finish;
    end
    initial begin #50000; $fatal(1,"Jump test timed out"); end
endmodule
