`timescale 1ns / 1ps
`include "game_defs.vh"
// Body-mounted rocket force must rotate with its sprite, even with no explicit
// vertical placement input. Exercise every accepted angle and both facings.
module rocket_orientation_tb;
    reg clk=0,reset=1,init=0,step=0,release_step=0;
    reg [2:0] state=`LP_BUILD;
    reg [26:0] grid=0;
    reg [8:0] frames=9'b000010000,alive=9'b000011000,vertical=0,facing=0;
    reg [7:0] mass=6;
    reg signed [4:0] horizontal=1,up_down=0,seed_tilt=0;
    reg fire=0,accept_move=0,response=0;
    wire valid,committed;
    wire signed [19:0] nx,ny;
    wire signed [15:0] vx,vy;
    wire signed [4:0] nt;
    integer angle,axis,sign_case,sign_value,fx,fy,expected_vx,expected_vy,waited,cases=0;
    `include "rotation_geometry.vh"
    always #5 clk=~clk;
    physics_engine #(.ROCKET_FORCE_SHIFT(10)) dut(.clk(clk),.reset(reset),.run_init(init),.game_state(state),
        .spawn_x(20'sd8192),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
        .wheel_count(4'd0),.engine_count(4'd0),.balloon_count(4'd0),.mass_units(mass),
        .engine_enabled(1'b0),.engine_reverse(1'b0),.jump_press(1'b0),.boost_req(1'b0),
        .moments_enabled(1'b1),.build_grid(grid),.build_frames(frames),.frame_intact_mask(frames),
        .intact_mask(alive),.build_facing_left(facing),.rocket_vertical_mask(vertical),
        .fan_balance(5'sd0),.fan_enabled(1'b0),.rocket_balance(horizontal),.rocket_vertical_balance(up_down),
        .rocket_count(4'd1),.rocket_req(fire),.move_valid(valid),.move_ready(accept_move),
        .proposed_x(nx),.proposed_y(ny),.proposed_vx(vx),.proposed_vy(vy),.proposed_tilt(nt),
        .response_valid(response),.response_ready(),.corrected_x(nx),.corrected_y(ny),
        .corrected_vx(16'sd0),.corrected_vy(16'sd0),.grounded(1'b0),.ground_slope(8'sd0),
        .corrected_tilt(seed_tilt),.tip_dir(2'sd0),.movement_committed(committed));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task begin_step;begin
        step=1;clocks(1);step=0;waited=0;
        while(!valid && waited<1800) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Rocket orientation request timed out");
    end endtask
    task finish;begin
        accept_move=1;clocks(1);accept_move=0;response=1;clocks(1);response=0;
        if(!committed) $fatal(1,"Rocket orientation did not commit");
        release_step=1;clocks(1);release_step=0;
    end endtask
    task prime;begin
        state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;clocks(1);
        begin_step();finish(); // An accepted response supplies the initial body angle.
        fire=1;clocks(1);fire=0;
    end endtask
    initial begin
        grid[14:12]=`LP_PART_PIG;grid[11:9]=`LP_PART_BOOSTER;
        clocks(3);reset=0;
        for(axis=0;axis<2;axis=axis+1)
            for(sign_case=0;sign_case<2;sign_case=sign_case+1)
                for(angle=-16;angle<16;angle=angle+1) begin
                    seed_tilt=angle;sign_value=sign_case==0 ? 1 : -1;
                    horizontal=axis==0 ? sign_value : 0;
                    up_down=axis==1 ? sign_value : 0;
                    vertical=axis==1 ? 9'b000001000 : 9'd0;
                    facing=(axis==0 ? sign_value<0 : sign_value>0) ? 9'b000001000 : 9'd0;
                    prime();begin_step();
                    fx=4*(rotation_cos(seed_tilt)*horizontal-rotation_sin(seed_tilt)*up_down);
                    fy=4*(rotation_sin(seed_tilt)*horizontal+rotation_cos(seed_tilt)*up_down);
                    expected_vx=fx/6;expected_vy=32+fy/6;
                    if(vx!=expected_vx || vy!=expected_vy)
                        $fatal(1,"Rocket vector axis%0d sign%0d tilt%0d: (%0d,%0d), expected (%0d,%0d)",axis,sign_value,angle,vx,vy,expected_vx,expected_vy);
                    if(axis==0 && dut.u_moments.torque_q10!=0)
                        $fatal(1,"Body-attached force through COM gained torque when rotated");
                    if(axis==1 && dut.u_moments.torque_q10!= -22528*sign_value)
                        $fatal(1,"Rocket torque changed when force and arm rotated together");
                    finish();cases=cases+1;
                end
        // A valid loaded 19-unit cart, side rocket tilted 90 degrees upward.
        // No builder/editor change or explicit vertical placement is needed.
        grid=0;grid[8:6]=`LP_PART_BOOSTER;grid[11:9]=`LP_PART_ENGINE;grid[14:12]=`LP_PART_PIG;
        grid[20:18]=`LP_PART_WHEEL;grid[26:24]=`LP_PART_WHEEL;
        frames=9'b000111011;alive=9'b101011100;mass=19;vertical=0;facing=0;
        seed_tilt=-8;horizontal=1;up_down=0;prime();begin_step();
        if(vx!=0 || vy!=-21 || dut.rocket_force_y!=-1024)
            $fatal(1,"Upward-facing side rocket failed to lift loaded cart: %0d,%0d",vx,vy);
        finish();
        $display("PASS rocket_orientation_tb: %0d rotated/facing/axis vectors, invariant torque, and loaded-cart vertical lift",cases);
        $finish;
    end
    initial begin #3000000;$fatal(1,"Rocket orientation timeout");end
endmodule
