`timescale 1ns / 1ps
`include "game_defs.vh"
module wheel_stability_tb;
    reg clk=0,reset=1,init=0,step=0,release_step=0,accept_move=0,response=0,contact=0;
    reg [2:0] state=`LP_BUILD;
    wire [1:0] valid,committed;
    wire [31:0] vx_all;
    wire [27:0] spin_all;
    integer i,waited,raw_spin,stable_spin,raw_peak=0,stable_peak=0;
    always #5 clk=~clk;
    genvar n;
    generate for(n=0;n<2;n=n+1) begin: g
        wire signed [19:0] nx,ny;
        wire signed [15:0] vx,vy;
        physics_engine #(.ENGINE_FORCE(320),.WHEEL_TORQUE_SHIFT(n==0 ? 0 : 2)) dut(
            .clk(clk),.reset(reset),.run_init(init),.game_state(state),
            .spawn_x(20'sd8192),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
            .wheel_count(4'd1),.wheels_down(4'd1),.wheels_up(4'd0),.engine_count(4'd1),
            .balloon_count(4'd0),.mass_units(8'd10),.engine_enabled(1'b1),.engine_reverse(1'b0),
            .jump_press(1'b0),.boost_req(1'b0),.fan_balance(5'sd0),.fan_enabled(1'b0),
            .rocket_balance(5'sd0),.rocket_count(4'd0),.rocket_req(1'b0),.moments_enabled(1'b1),
            .build_grid({`LP_PART_EMPTY,`LP_PART_WHEEL,`LP_PART_EMPTY,
                         `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,
                         `LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY}),
            .build_frames(9'b000011000),.frame_intact_mask(9'b000011000),.intact_mask(9'b010011000),
            .build_facing_left(9'd0),.rocket_vertical_mask(9'd0),
            .move_valid(valid[n]),.move_ready(accept_move),.proposed_x(nx),.proposed_y(ny),
            .proposed_vx(vx),.proposed_vy(vy),.response_valid(response),.response_ready(),
            .corrected_x(nx),.corrected_y(ny),.corrected_vx(vx),.corrected_vy(16'sd0),
            .grounded(contact),.ground_slope(8'sd0),.corrected_tilt(5'sd0),.tip_dir(2'sd0),
            .movement_committed(committed));
        assign vx_all[n*16 +: 16]=vx;
        assign spin_all[n*14 +: 14]=dut.angular_velocity_q8;
    end endgenerate
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task update;begin
        step=1;clocks(1);step=0;waited=0;
        while(valid!=2'b11 && waited<1800) begin clocks(1);waited=waited+1;end
        if(valid!=2'b11) $fatal(1,"Wheel stability request timeout");
        if(vx_all[15:0]!=vx_all[31:16]) $fatal(1,"Stability gain changed linear drive or climbing force");
        raw_spin=$signed(spin_all[13:0]);stable_spin=$signed(spin_all[27:14]);
        if(raw_spin<0) raw_spin=-raw_spin;if(stable_spin<0) stable_spin=-stable_spin;
        if(raw_spin>raw_peak) raw_peak=raw_spin;if(stable_spin>stable_peak) stable_peak=stable_spin;
        accept_move=1;clocks(1);accept_move=0;response=1;clocks(1);response=0;
        if(committed!=2'b11) $fatal(1,"Wheel stability commit missing");
        release_step=1;clocks(1);release_step=0;
    end endtask
    initial begin
        clocks(3);reset=0;state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;
        update();contact=1;
        for(i=0;i<64;i=i+1) update();
        if(stable_peak!=0 || raw_peak!=0 || vx_all==0)
            $fatal(1,"Wheel drive created rotation: raw=%0d stable=%0d",raw_peak,stable_peak);
        $display("PASS wheel_stability_tb: single-wheel spin remains %0d / %0d with identical nonzero linear drive",raw_peak,stable_peak);
        $finish;
    end
    initial begin #1500000;$fatal(1,"Wheel stability test timeout");end
endmodule
