// Owner: Role 2 - Kyle. Stable ground contact absorbs residual angular motion.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ground_angular_impact_tb;
    reg clk=0,reset=1,init=0,step=0,release_step=0,accept_move=0,response=0;
    reg [2:0] state=`LP_BUILD;
    reg contact=0,span_valid=0,unstable=0,fan=0;
    reg [3:0] balloons=0;
    reg signed [1:0] tip=0;
    reg signed [9:0] span_left=-32,span_right=32;
    reg [26:0] grid=0;
    reg [8:0] alive=9'b000010000;
    reg [7:0] mass=4;
    wire valid,committed;
    wire signed [19:0] nx,ny,x,y;
    wire signed [15:0] vx,vy;
    wire signed [4:0] nt,tilt;
    integer waited,cases=0,sign;
    always #5 clk=~clk;
    physics_engine dut(
        .clk(clk),.reset(reset),.run_init(init),.game_state(state),
        .spawn_x(20'sd8192),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
        .wheel_count(4'd0),.engine_count(4'd0),.balloon_count(balloons),.mass_units(mass),
        .engine_enabled(1'b0),.engine_reverse(1'b0),
        .moments_enabled(1'b1),.build_grid(grid),.build_frames(9'b000010000),
        .intact_mask(alive),.frame_intact_mask(9'b000010000),.build_facing_left(9'd0),
        .rocket_vertical_mask(9'd0),.fan_balance(5'sd1),.fan_enabled(fan),
        .rocket_balance(5'sd0),.rocket_count(4'd0),.rocket_req(1'b0),
        .move_valid(valid),.move_ready(accept_move),.proposed_x(nx),.proposed_y(ny),
        .proposed_vx(vx),.proposed_vy(vy),.proposed_tilt(nt),.vehicle_tilt(tilt),
        .response_valid(response),.response_ready(),.corrected_x(nx),.corrected_y(ny),
        .corrected_vx(vx),.corrected_vy(contact ? 16'sd0 : vy),.corrected_tilt(nt),
        .grounded(contact),.ground_slope(8'sd0),.ground_slope_valid(1'b1),
        .support_span_valid(span_valid),.support_wheel_count(4'd0),
        .support_left_q2(span_left),.support_right_q2(span_right),.support_y_q2(10'sd48),
        .support_unstable(unstable),.tip_dir(tip),.movement_committed(committed),.vehicle_x(x),.vehicle_y(y));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task begin_step;begin
        step=1;clocks(1);step=0;waited=0;
        while(!valid && waited<3000) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Angular impact request timeout");
    end endtask
    task finish_step;begin
        accept_move=1;clocks(1);accept_move=0;response=1;clocks(1);response=0;
        if(!committed) $fatal(1,"Angular impact commit missing");
        release_step=1;clocks(1);release_step=0;
    end endtask
    task seed_ground;
        input integer signed_speed,actual_span,overhang,with_fan,narrow_span;
        begin
            reset=1;state=`LP_BUILD;contact=0;span_valid=actual_span;unstable=overhang;
            tip=overhang ? 1 : 0;fan=0;balloons=0;
            grid=0;grid[4*3 +: 3]=`LP_PART_PIG;alive=9'b000010000;mass=4;
            if(with_fan) begin grid[1*3 +: 3]=`LP_PART_FAN;alive[1]=1;mass=6;end
            span_left=narrow_span ? -4 : -32;span_right=narrow_span ? 4 : 32;
            if(overhang) begin span_left=-20;span_right=-8;end
            clocks(2);reset=0;state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;
            // Establish a real accepted contact before injecting residual spin.
            contact=1;begin_step();finish_step();
            // There is no gameplay port for an angular impact. Seed only the
            // angular initial conditions while idle; responses remain public.
            dut.angular_velocity_q8=signed_speed;
            dut.moment_angle_remainder=signed_speed>0 ? 13'sd3584 : -13'sd3584;
            fan=with_fan;
        end
    endtask
    task check_stopped;begin
        begin_step();
        if(nt!=0 || dut.angular_velocity_q8!=0 || dut.moment_angle_remainder!=0)
            $fatal(1,"Stable contact retained impact spin: angle%0d omega%0d remainder%0d",nt,dut.angular_velocity_q8,dut.moment_angle_remainder);
        finish_step();cases=cases+1;
    end endtask
    task check_spinning;begin
        begin_step();
        if(dut.angular_velocity_q8==0) $fatal(1,"Non-settling state incorrectly killed angular motion");
        finish_step();cases=cases+1;
    end endtask
    initial begin
        clocks(3);reset=0;
        for(sign=-1;sign<=1;sign=sign+2) begin
            seed_ground(sign*4096,1,0,0,0);check_stopped();
            // A powered fan whose moment is fully supported also rests.
            seed_ground(sign*4096,1,0,1,0);check_stopped();
            // Legacy callers without an actual span keep their old damping.
            seed_ground(sign*4096,0,0,0,0);check_spinning();
            // A genuine lift-off must not inherit ground angular locking.
            seed_ground(sign*4096,1,0,0,0);balloons=2;begin_step();
            if(vy>=0 || dut.angular_velocity_q8==0) $fatal(1,"Balloon lift lost angular motion");
            contact=0;finish_step();cases=cases+1;
            seed_ground(sign*4096,1,1,0,0);check_spinning();
            // An actuator moment exceeding the support capacity may still tip.
            seed_ground(sign*4096,1,0,1,1);check_spinning();
        end
        $display("PASS ground_angular_impact_tb: %0d mirrored impact states settle supported bodies while preserving lift-off, overhangs, unbalanced torque and legacy damping",cases);$finish;
    end
    initial begin #1000000;$fatal(1,"Angular impact test timeout");end
endmodule
