`timescale 1ns / 1ps
`include "game_defs.vh"
module vehicle_moments_tb;
    reg clk=0,reset=1,start=0,fan=0,rocket=0,grounded=0,force_valid=1;
    reg [26:0] grid=0;
    reg [8:0] frames=0,alive=0,frame_alive=0,facing=0,vertical=0;
    reg signed [4:0] tilt=0,next_tilt=0;
    reg signed [15:0] wheel_force=0;
    reg accept_result=0,pivot_start=0,pivot_ready=0;
    wire valid,pivot_valid;
    wire signed [15:0] accel;
    wire signed [6:0] comx,comy;
    wire signed [13:0] pdx,pdy;
    wire signed [23:0] torque;
    wire [7:0] mass;
    wire [15:0] support_neg,support_pos;
    integer waited,tests=0;
    reg signed [15:0] held_accel;
    always #5 clk=~clk;
    vehicle_moments dut(.clk(clk),.reset(reset),.start(start),.build_grid(grid),.build_frames(frames),
        .intact_mask(alive),.frame_intact_mask(frame_alive),.facing_left(facing),.rocket_vertical_mask(vertical),
        .fan_on(fan),.rocket_on(rocket),.grounded(grounded),.tilt(tilt),
        .wheel_force_valid(force_valid),.wheel_force(wheel_force),.result_valid(valid),.result_ready(accept_result),
        .angular_accel_q8(accel),.support_negative_q8(support_neg),.support_positive_q8(support_pos),.com_x_q2(comx),.com_y_q2(comy),.body_mass(mass),.torque_q10(torque),
        .pivot_start(pivot_start),.next_tilt(next_tilt),.pivot_valid(pivot_valid),.pivot_ready(pivot_ready),
        .pivot_dx(pdx),.pivot_dy(pdy));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task empty;begin
        grid=0;frames=0;alive=0;frame_alive=0;facing=0;vertical=0;
        tilt=0;next_tilt=0;fan=0;rocket=0;grounded=0;wheel_force=0;force_valid=1;
    end endtask
    task put;input integer cell_id;input [2:0] kind;begin
        grid[cell_id*3 +: 3]=kind;alive[cell_id]=1;
    end endtask
    task centre;begin empty();frames[4]=1;frame_alive[4]=1;put(4,`LP_PART_PIG);end endtask
    task begin_calc;begin start=1;clocks(1);start=0;end endtask
    task wait_calc;begin
        waited=0;while(!valid && waited<1500) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Moment calculation timeout");tests=tests+1;
    end endtask
    task finish;begin
        accept_result=1;clocks(1);accept_result=0;pivot_start=1;clocks(1);pivot_start=0;
        waited=0;while(!pivot_valid && waited<200) begin clocks(1);waited=waited+1;end
        if(!pivot_valid) $fatal(1,"COM pivot correction timeout");
        pivot_ready=1;clocks(1);pivot_ready=0;
    end endtask
    initial begin
        clocks(3);reset=0;
        centre();put(1,`LP_PART_FAN);fan=1;begin_calc();wait_calc();
        if(mass!=6 || comx!=0 || comy!=-10 || torque!=-1408 || accel!=-29)
            $fatal(1,"Offset fan mass/COM/torque wrong: %0d (%0d,%0d) %0d %0d",mass,comx,comy,torque,accel);
        held_accel=accel;clocks(5);if(!valid || accel!=held_accel) $fatal(1,"Stalled moment changed");
        next_tilt=8;finish();
        // COM offset (0,-2.5 px) rotates to (+2.5,0) at 90 degrees.
        if(pdx!=-640 || pdy!=-640) $fatal(1,"COM-preserving origin correction wrong: %0d,%0d",pdx,pdy);
        centre();put(7,`LP_PART_FAN);fan=1;begin_calc();wait_calc();
        if(torque!=1408 || accel!=29) $fatal(1,"Mirrored fan arm did not reverse moment");finish();
        centre();put(3,`LP_PART_FAN);fan=1;begin_calc();wait_calc();
        if(torque!=0 || accel!=0) $fatal(1,"Force through COM created torque");finish();
        centre();put(1,`LP_PART_FAN);put(7,`LP_PART_FAN);fan=1;facing[7]=1;
        begin_calc();wait_calc();if(comy!=0 || torque!=-4096 || accel!=-64)
            $fatal(1,"Pure couple incorrectly cancelled with net force");finish();
        centre();put(3,`LP_PART_BOOSTER);vertical[3]=1;rocket=1;
        begin_calc();wait_calc();if(torque!=11264 || accel!=234) $fatal(1,"Vertical left rocket moment wrong");finish();
        centre();put(5,`LP_PART_BOOSTER);vertical[5]=1;rocket=1;
        begin_calc();wait_calc();if(torque!=-11264 || accel!=-234) $fatal(1,"Vertical right rocket moment wrong");finish();
        centre();put(3,`LP_PART_BOOSTER);put(5,`LP_PART_BOOSTER);vertical=9'b000101000;rocket=1;
        begin_calc();wait_calc();if(torque!=0 || accel!=0) $fatal(1,"Symmetric rocket moments did not cancel");finish();
        centre();put(1,`LP_PART_BOOSTER);rocket=1;tilt=-8;next_tilt=-8;
        begin_calc();wait_calc();if(torque!=11264 || accel!=234)
            $fatal(1,"Rotating attached horizontal rocket changed its local moment");finish();
        // Drive acts at the wheel, irrespective of which side contains the engine.
        centre();frames[3]=1;frame_alive[3]=1;put(3,`LP_PART_ENGINE);put(7,`LP_PART_WHEEL);
        grounded=1;wheel_force=96;begin_calc();wait_calc();
        if(mass!=10 || comy!=3 || torque!=0 || accel!=0) $fatal(1,"Wheel contact force wrong");finish();
        centre();frames[5]=1;frame_alive[5]=1;put(5,`LP_PART_ENGINE);put(7,`LP_PART_WHEEL);
        grounded=1;wheel_force=96;begin_calc();wait_calc();
        if(torque!=0 || accel!=0) $fatal(1,"Engine position moved traction force off wheels");finish();
        grounded=0;begin_calc();wait_calc();if(torque!=0) $fatal(1,"Airborne wheel created traction");finish();
        centre();put(7,`LP_PART_WHEEL);grounded=1;wheel_force=96;tilt=8;next_tilt=8;
        begin_calc();wait_calc();if(torque!=0) $fatal(1,"Moment arm did not rotate with body");finish();
        centre();put(1,`LP_PART_FAN);fan=1;begin_calc();
        // Snapshot survives live damage and direction changes while busy.
        alive=0;facing=9'h1ff;wait_calc();if(torque!=-1408) $fatal(1,"Live changes corrupted moment snapshot");finish();
        centre();put(1,`LP_PART_FAN);fan=1;alive[1]=0;begin_calc();wait_calc();
        if(mass!=4 || comx!=0 || comy!=0 || torque!=0) $fatal(1,"Destroyed actuator retained mass or torque");finish();
        centre();put(1,`LP_PART_FAN);put(7,`LP_PART_FAN);fan=1;facing[7]=1;
        frames[3]=1;frames[5]=1;frame_alive=frames;
        begin_calc();wait_calc();if(mass!=12 || torque!=-4096 || accel!=-42)
            $fatal(1,"Greater mass did not reduce angular acceleration");finish();
        centre();frames=9'b000111000;frame_alive=frames;
        put(6,`LP_PART_WHEEL);put(7,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);grounded=1;wheel_force=95;
        begin_calc();wait_calc();if(mass!=11 || comy!=8 || torque!=0 || accel!=0)
            $fatal(1,"Wheel force sharing lost integer remainder");finish();
        wheel_force=-95;begin_calc();wait_calc();if(torque!=0 || accel!=0)
            $fatal(1,"Reverse wheel force sharing lost sign");finish();
        centre();frames=9'b000111000;frame_alive=frames;
        put(3,`LP_PART_ENGINE);put(0,`LP_PART_WHEEL);put(2,`LP_PART_WHEEL);
        put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);grounded=1;wheel_force=300;
        begin_calc();wait_calc();
        if(mass!=15 || accel!=0 || support_neg!=168 || support_pos!=216)
            $fatal(1,"Wheel normal reaction capacity wrong: %0d %0d %0d",accel,support_neg,support_pos);finish();
        wheel_force=0;begin_calc();wait_calc();
        if(accel!=0 || support_neg!=168 || support_pos!=216)
            $fatal(1,"Passive wheels lost normal reaction support");finish();
        put(1,`LP_PART_BALLOON);wheel_force=300;begin_calc();wait_calc();
        if(mass!=16 || support_neg!=42 || support_pos!=54)
            $fatal(1,"Balloon did not reduce normal reaction capacity");finish();
        centre();frames=9'b000111000;frame_alive=frames;put(3,`LP_PART_ENGINE);
        put(6,`LP_PART_WHEEL);put(8,`LP_PART_WHEEL);put(0,`LP_PART_BALLOON);put(1,`LP_PART_BALLOON);
        grounded=1;wheel_force=300;begin_calc();wait_calc();
        if(support_neg!=0 || support_pos!=0) $fatal(1,"Net upward lift retained ground normal reaction");finish();
        empty();begin_calc();wait_calc();if(mass!=0 || torque!=0 || accel!=0) $fatal(1,"Empty vehicle divided by zero incorrectly");finish();
        centre();put(1,`LP_PART_FAN);fan=1;force_valid=0;begin_calc();clocks(120);
        if(valid) $fatal(1,"Moment read unready wheel force");force_valid=1;wait_calc();finish();
        centre();begin_calc();clocks(4);reset=1;clocks(1);reset=0;clocks(2);
        if(valid || pivot_valid) $fatal(1,"Reset retained an incomplete result");
        $display("PASS vehicle_moments_tb: %0d COM, fan/rocket couples, wheel contacts, rotation, pivot, damage, snapshot and handshake cases",tests);
        $finish;
    end
    initial begin #1000000;$fatal(1,"Moment test timeout");end
endmodule
