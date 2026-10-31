`timescale 1ns / 1ps
`include "game_defs.vh"
module rocket_game_integration_tb;
    reg clk=0,board_reset=1,init=0,step=0,fire=0;
    reg [2:0] state=`LP_BUILD;
    tri1 PS2Clk,PS2Data;
    integer waited;
    always #5 clk=~clk;
    My_Top_Module #(.PHYSICS_CYCLES(1000000),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2)) dut(
        .clk(clk),.btnD(board_reset),.btnC(1'b0),.btnU(1'b0),.btnR(1'b0),.btnL(1'b0),
        .sw(16'd0),.PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.JXADC(),.led(),.seg(),.an(),.dp());
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    initial begin
        force dut.game_state=state;force dut.run_init=init;force dut.step_start=step;
        force dut.update_release=1'b0;force dut.physics_tick=1'b0;
        force dut.ui_rocket_req=fire;force dut.ui_engine_on=1'b0;
        clocks(20);board_reset=0;clocks(300);
        dut.u_builder.build_grid={`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
            `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,`LP_PART_BOOSTER,`LP_PART_EMPTY,`LP_PART_EMPTY};
        dut.u_builder.build_frames=9'b000111011;dut.u_builder.build_facing_left=0;clocks(3);
        if(!dut.build_valid || dut.mass_units!=19 || dut.rocket_count!=1)
            $fatal(1,"Loaded rocket cart fixture is not valid");
        state=`LP_INIT_RUN;init=1;clocks(3);init=0;state=`LP_RUN;clocks(3);
        // A side rocket rotates upward with the body; vertical placement remains zero.
        force dut.u_physics.vehicle_tilt=-5'sd8;
        fire=1;clocks(1);fire=0;clocks(1);step=1;clocks(1);step=0;
        waited=0;while(!dut.move_valid && waited<2000) begin clocks(1);waited=waited+1;end
        if(!dut.move_valid) $fatal(1,"Game rocket movement request missing");
        if(dut.u_physics.rocket_vertical_balance!=0 || dut.u_physics.rocket_vertical_mask!=0)
            $fatal(1,"Test accidentally bypassed the real game's vertical placement wiring");
        if(dut.u_physics.step_vertical_force!=-1024 || dut.proposed_vx!=0 || dut.proposed_vy!=-21)
            $fatal(1,"Real game wiring lost upward thrust: Fx=%0d Fy=%0d vx=%0d vy=%0d",
                dut.u_physics.rocket_force_x,dut.u_physics.step_vertical_force,dut.proposed_vx,dut.proposed_vy);
        release dut.u_physics.vehicle_tilt;
        $display("PASS rocket_game_integration_tb: real game wiring gives a rotated side rocket upward force and lifts a valid 19-unit cart");
        $finish;
    end
    initial begin #200000;$fatal(1,"Game rocket integration timeout");end
endmodule
