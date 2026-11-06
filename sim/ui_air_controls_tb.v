// Owner: Role 1 - Kaushal. Prepared fan/rocket controls, independently of Kyle's physics.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_air_controls_tb;
    reg clk=0,reset=1,enabled=1,init=0,launch=0,tick=0;
    reg [2:0] state=`LP_RUN;
    reg [11:0] x=20,y=24;
    reg left=0,right=0,event_in=0,fan_available=0,rocket_available=0,ready=0;
    reg fan_toggle_req=0, rocket_toggle_req=0;
    wire fan,rocket,engine,flash;
    integer fires=0;
    always #5 clk=~clk;
    always @(posedge clk) if(rocket) fires=fires+1;
    ui_controller dut(.clk(clk),.reset(reset),.input_enabled(enabled),.run_init(init),.physics_tick(tick),
        .launch_event(launch),.game_state(state),.mouse_x(x),.mouse_y(y),.mouse_left(left),.mouse_right(right),
        .mouse_event(event_in),.next_press(1'b0),
        .fan_toggle_req(fan_toggle_req),.rocket_toggle_req(rocket_toggle_req),
        .fan_available(fan_available),.rocket_available(rocket_available),
        .rocket_ready(ready),.launch_req(),.edit_req(),.guide_open_req(),.guide_close_req(),.diary_page(),
        .engine_on(engine),.fan_on(fan),.rocket_req(rocket),.launch_flash(flash));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task pulse_fan;begin fan_toggle_req=1;clocks(1);fan_toggle_req=0;clocks(2);end endtask
    task pulse_rocket;begin rocket_toggle_req=1;clocks(1);rocket_toggle_req=0;clocks(2);end endtask
    initial begin
        clocks(2);reset=0;clocks(2);
        pulse_fan();
        if(fan || fires) $fatal(1,"Unavailable fan was enabled");
        fan_available=1;pulse_fan();if(!fan) $fatal(1,"Fan ON missing");
        pulse_fan();if(fan) $fatal(1,"Fan toggle OFF failed");
        rocket_available=1;ready=0;pulse_rocket();if(fires) $fatal(1,"Unready rocket fired");
        ready=1;pulse_rocket();
        if(fires!=1) $fatal(1,"Rocket press was lost or repeated");
        pulse_fan();if(!fan) $fatal(1,"Second fan enable missing");
        init=1;clocks(1);init=0;if(fan || engine) $fatal(1,"Retry left stale control state");
        launch=1;clocks(1);launch=0;tick=1;clocks(29);if(!flash) $fatal(1,"GO ended early");clocks(1);tick=0;
        if(flash) $fatal(1,"GO transition did not finish");
        $display("PASS ui_air_controls_tb: capability gates, fan toggle, one-shot rocket, retry and GO transition");
        $finish;
    end
    initial begin #10000;$fatal(1,"Air controls timed out");end
endmodule
