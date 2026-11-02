`timescale 1ns / 1ps
`include "game_defs.vh"
// Mass eight, zero corrected momentum: observe each update's applied force.
module air_propulsion_tb;
    reg clk=0, reset=1, init=0, step=0, release_step=0;
    reg [2:0] state=`LP_BUILD;
    reg signed [4:0] fans=0, rockets=0, vertical_rockets=0;
    reg [3:0] rocket_count=0;
    reg fan_on=0, fire=0, engine=0, contact=0, keep_vy=0;
    reg [7:0] mass=8;
    reg accept_move=0, response=0;
    wire valid, ready, committed, rocket_ready, active;
    wire signed [19:0] nx,ny;
    wire signed [15:0] vx,vy;
    integer waited,i;
    always #5 clk=~clk;
    physics_engine dut(.clk(clk),.reset(reset),.run_init(init),.game_state(state),
        .spawn_x(20'sd8192),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
        .wheel_count(4'd0),.engine_count(4'd1),.balloon_count(4'd0),.mass_units(mass),
        .engine_enabled(engine),.engine_reverse(1'b0),.jump_press(1'b0),.boost_req(1'b0),
        .rocket_vertical_balance(vertical_rockets),.fan_balance(fans),.rocket_balance(rockets),.rocket_count(rocket_count),
        .fan_enabled(fan_on),.rocket_req(fire),.rocket_ready(rocket_ready),.rocket_active(active),
        .move_valid(valid),.move_ready(accept_move),.proposed_x(nx),.proposed_y(ny),
        .proposed_vx(vx),.proposed_vy(vy),.response_valid(response),.response_ready(ready),
        .corrected_x(nx),.corrected_y(ny),.corrected_vx(16'sd0),.corrected_vy(keep_vy ? vy : 16'sd0),
        .grounded(contact),.ground_slope(8'sd0),.corrected_tilt(5'sd0),.movement_committed(committed));
    task clocks; input integer n; begin repeat(n) @(negedge clk); end endtask
    task restart; begin
        state=`LP_INIT_RUN; init=1; clocks(2); init=0; state=`LP_RUN; clocks(1);
    end endtask
    task begin_step; begin step=1;clocks(1);step=0;end endtask
    task request; begin
        waited=0;while(!valid && waited<80) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"No propulsion request");
    end endtask
    task finish_step; begin
        accept_move=1;clocks(1);accept_move=0;
        response=1;clocks(1);response=0;
        if(!committed) $fatal(1,"No movement commit");
        release_step=1;clocks(1);release_step=0;
    end endtask
    task check_step; input integer expected; begin
        begin_step();request();
        if(vx!=expected) $fatal(1,"Thrust vx=%0d expected=%0d",vx,expected);
        finish_step();
    end endtask
    initial begin
        clocks(3);reset=0;restart();
        fire=1;clocks(1);fire=0;
        if(rocket_ready || active) $fatal(1,"Missing rocket accepted a trigger");
        fans=1;fan_on=1;check_step(-8);check_step(-8);
        fans=-1;check_step(8);fans=2;check_step(-16);fans=-2;check_step(16);
        fans=0;check_step(0);fans=1;fan_on=0;check_step(0);
        fan_on=1;begin_step();fans=-1;fan_on=0;request();
        if(vx!=-8) $fatal(1,"Fan changed during an in-flight update");
        clocks(5);if(vx!=-8 || !valid) $fatal(1,"Stalled thrust request changed");
        finish_step();check_step(0);
        rockets=1;rocket_count=1;clocks(1);
        if(!rocket_ready) $fatal(1,"Intact rocket not ready");
        // Trigger while another movement is in flight; do not alter that step.
        begin_step();fire=1;clocks(1);fire=0;request();
        if(vx!=0 || !active || rocket_ready) $fatal(1,"Rocket request capture/sampling failed");
        finish_step();clocks(100);
        if(dut.rocket_fuel!=90) $fatal(1,"Idle clocks consumed rocket fuel");
        fire=1; // A held request must not refill or rearm an expended rocket.
        for(i=0;i<90;i=i+1) check_step(64);
        if(active || rocket_ready) $fatal(1,"Rocket did not expire");
        check_step(0);fire=0;
        restart();rockets=-1;fire=1;clocks(1);fire=0;check_step(-64);
        rockets=0;rocket_count=0;check_step(0);
        if(active) $fatal(1,"Destroyed rocket still active");
        // Retry restores fuel; engine, fan and rocket forces add before mass division.
        rockets=1;rocket_count=1;fans=1;fan_on=1;engine=1;contact=1;
        restart();check_step(-8); // Spawn support is not confirmed until the response.
        fire=1;clocks(1);fire=0;check_step(68);
        // Last tick, including a stalled response, still gets exactly one impulse.
        restart();fan_on=0;engine=0;fire=1;clocks(1);fire=0;
        for(i=0;i<89;i=i+1) check_step(64);
        begin_step();request();clocks(10);
        if(vx!=64 || dut.rocket_fuel!=0) $fatal(1,"Last rocket tick lost or refilled");
        finish_step();check_step(0);
        rockets=0;vertical_rockets=-1;contact=0;restart();
        fire=1;clocks(1);fire=0;begin_step();request();
        if(vx!=0 || vy!=-32) $fatal(1,"Up rocket did not overcome gravity: %0d %0d",vx,vy);
        finish_step();vertical_rockets=1;begin_step();request();
        if(vx!=0 || vy!=96) $fatal(1,"Down rocket force incorrect: %0d %0d",vx,vy);
        finish_step();rockets=1;vertical_rockets=-1;begin_step();request();
        if(vx!=64 || vy!=-32) $fatal(1,"Shared divider mixed horizontal and vertical forces");
        finish_step();rocket_count=0;vertical_rockets=0;rockets=0;
        check_step(0);if(vy!=32) $fatal(1,"Destroyed rocket retained vertical thrust");
        // Fractional vertical force survives responses that preserve velocity.
        mass=6;keep_vy=1;rocket_count=1;vertical_rockets=-1;restart();
        fire=1;clocks(1);fire=0;begin_step();request();
        if(vy!=-53) $fatal(1,"Vertical mass division lost sign");finish_step();
        begin_step();request();if(vy!=-106) $fatal(1,"Second vertical step incorrect");finish_step();
        begin_step();request();if(vy!=-160) $fatal(1,"Vertical force remainder was discarded");finish_step();
        for(i=0;i<12;i=i+1) begin begin_step();request();finish_step();end
        if(vy!=-512 || dut.remainder_y!=0) $fatal(1,"Vertical cap retained force remainder");
        state=`LP_BUILD;clocks(2);
        if(active || rocket_ready) $fatal(1,"Rocket status survived leaving RUN");
        $display("PASS air_propulsion_tb: signed fan forces, sampling, rocket capture, 90 ticks, expiry, damage, retry and combined thrust");
        $finish;
    end
    initial begin #500000;$fatal(1,"Air propulsion timed out");end
endmodule
