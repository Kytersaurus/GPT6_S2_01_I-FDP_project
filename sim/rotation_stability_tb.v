`timescale 1ns / 1ps
`include "game_defs.vh"
module rotation_stability_tb #(parameter ENABLE_MOMENTS=1);
    reg clk=0,reset=1,init=0,step=0,release_step=0,accept_move=0,response=0;
    reg [2:0] state=`LP_BUILD;
    reg signed [7:0] slope=16;
    reg contact=1;
    reg signed [4:0] stopped_tilt;
    wire valid,committed;
    wire signed [19:0] nx,ny;
    wire signed [15:0] vx,vy;
    wire signed [4:0] nt,tilt;
    integer i,j,waited;
    always #5 clk=~clk;
    physics_engine dut(.clk(clk),.reset(reset),.run_init(init),.game_state(state),
        .spawn_x(20'sd8192),.spawn_y(20'sd8192),.step_start(step),.update_release(release_step),
        .wheel_count(4'd0),.engine_count(4'd0),.balloon_count(4'd0),.mass_units(8'd4),
        .engine_enabled(1'b0),.engine_reverse(1'b0),.jump_press(1'b0),.boost_req(1'b0),
        .moments_enabled(ENABLE_MOMENTS!=0),.build_grid({12'd0,`LP_PART_PIG,12'd0}),
        .build_frames(9'b000010000),.intact_mask(9'b000010000),.frame_intact_mask(9'b000010000),
        .build_facing_left(9'd0),.rocket_vertical_mask(9'd0),.fan_balance(5'sd0),.fan_enabled(1'b0),
        .rocket_balance(5'sd0),.rocket_count(4'd0),.rocket_req(1'b0),
        .move_valid(valid),.move_ready(accept_move),.proposed_x(nx),.proposed_y(ny),
        .proposed_vx(vx),.proposed_vy(vy),.proposed_tilt(nt),.vehicle_tilt(tilt),
        .response_valid(response),.response_ready(),.corrected_x(nx),.corrected_y(ny),
        .corrected_vx(vx),.corrected_vy(16'sd0),.corrected_tilt(nt),.grounded(contact),.ground_slope(slope),
        .movement_committed(committed));
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task update;begin
        step=1;clocks(1);step=0;waited=0;
        while(!valid && waited<2000) begin clocks(1);waited=waited+1;end
        if(!valid) $fatal(1,"Rotation stability request timeout");
        accept_move=1;clocks(1);accept_move=0;response=1;clocks(1);response=0;
        if(!committed) $fatal(1,"Rotation stability commit missing");
        release_step=1;clocks(1);release_step=0;
    end endtask
    initial begin
        clocks(3);reset=0;state=`LP_INIT_RUN;init=1;clocks(2);init=0;state=`LP_RUN;
        repeat(20) update();if(tilt!=4) $fatal(1,"Initial constant slope did not align");
        for(i=0;i<8;i=i+1) begin
            slope=i[0] ? 16 : 12;
            for(j=0;j<8;j=j+1) begin update();if(tilt!=4) $fatal(1,"Adjacent slope bins changed resting tilt");end
        end
        slope=5;repeat(20) update();if(tilt!=2) $fatal(1,"Larger slope change did not align");
        slope=-2;repeat(20) update();if(tilt!= -1) $fatal(1,"Negative slope did not align");
        slope=0;repeat(20) update();if(tilt!=0) $fatal(1,"Flat floor did not settle fully level");
        if (ENABLE_MOMENTS==0) begin
            // Seed residual angular motion after takeoff; both signs must stop.
            contact=0;update();
            dut.spin=16;dut.spin_frac=0;
            repeat(32) update();
            if(dut.spin!=0 || dut.spin_frac!=0) $fatal(1,"Positive legacy spin did not stop");
            stopped_tilt=tilt;
            repeat(12) begin update();if(tilt!=stopped_tilt) $fatal(1,"Stopped legacy angle changed");end
            dut.spin=-16;dut.spin_frac=0;
            repeat(32) update();
            if(dut.spin!=0 || dut.spin_frac!=0) $fatal(1,"Negative legacy spin did not stop");
            stopped_tilt=tilt;
            repeat(12) begin update();if(tilt!=stopped_tilt) $fatal(1,"Stopped legacy angle changed");end
        end
        $display("PASS rotation_stability_tb: ENABLE_MOMENTS=%0d neighboring bins hold, larger grade changes align, flat floor levels",ENABLE_MOMENTS);$finish;
    end
    initial begin #3000000;$fatal(1,"Rotation stability timeout");end
endmodule
