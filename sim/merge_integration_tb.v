`timescale 1ns / 1ps
`include "game_defs.vh"
// Integration contracts shared by the UI and physics branches.
module merge_integration_tb;
    reg clk=0,reset_board=1;
    reg [2:0] state=`LP_RUN;
    reg title=1,fan_on=1,star=1,ready=0,rocket_active=0;

    reg mouse_boost=0;
    tri1 PS2Clk,PS2Data;
    always #5 clk=~clk;
    My_Top_Module #(.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2)) dut(
        .clk(clk),.btnD(reset_board),.btnC(1'b0),.btnU(1'b0),.btnR(1'b0),.btnL(1'b0),
        .sw(16'd0),.PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.JXADC(),.led(),.seg(),.an(),.dp());
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    initial begin
        force dut.game_state=state;force dut.step_start=1'b0;force dut.physics_tick=1'b0;
        force dut.start_screen_active=title;force dut.fan_available=1'b1;force dut.ui_fan_on=fan_on;
        force dut.star_box_collected=star;force dut.rocket_available=1'b1;force dut.rocket_ready=ready;
        // Real surviving parts keep availability true while readiness changes.
        force dut.build_grid={`LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY,
            `LP_PART_FAN,`LP_PART_PIG,`LP_PART_EMPTY,`LP_PART_BOOSTER,`LP_PART_EMPTY,`LP_PART_EMPTY};
        force dut.intact_mask=9'b000110100;
        force dut.build_frames=9'b000010010;force dut.frame_intact_mask=9'b000010010;
        force dut.rocket_active=rocket_active;force dut.left_frame=1'b1;
        force dut.mouse_boost_req=mouse_boost;
        clocks(20);reset_board=0;clocks(500);
        // 376 bits with four TNT slots; each slot carries an intact bit and a 2-bit blast phase.
        if(dut.SNAPSHOT_WIDTH!=376+3*(`LP_MAX_TNT-4)) $fatal(1,"Merged snapshot field width is incorrect");
        if(dut.draw_start_screen_active!==1'b1 ||
           dut.draw_fan_on!==1'b1 || dut.draw_star_box_collected!==1'b1)
            $fatal(1,"Merged high snapshot fields were truncated or misordered");
        if(dut.u_ui_control.rocket_ready!==1'b0)
            $fatal(1,"UI did not use physics rocket readiness");
        title=0;fan_on=0;star=0;ready=1;rocket_active=1;clocks(500);
        if(dut.draw_start_screen_active!==1'b0 ||
           dut.draw_fan_on!==1'b0 || dut.draw_star_box_collected!==1'b0 ||
           dut.draw_boost_active!==1'b1)
            $fatal(1,"Merged display flags failed to update coherently");
        if(dut.u_ui_control.rocket_ready!==1'b1)
            $fatal(1,"Engine boost incorrectly gated independent rocket fuel readiness");
        ready=0;rocket_active=0;clocks(500);
        if(dut.u_ui_control.rocket_ready!==1'b0)
            $fatal(1,"Expended rocket became ready merely because boost ended");
        if(dut.ui_rocket_req!==1'b0) $fatal(1,"Idle rocket request net has multiple drivers");
        mouse_boost=1;clocks(2);if(dut.ui_rocket_req!==1'b0) $fatal(1,"Expended rocket allowed second boost");
        mouse_boost=0;ready=1;clocks(2);
        mouse_boost=1;clocks(1);mouse_boost=0;
        if(dut.ui_rocket_req!==1'b1) $fatal(1,"Mouse rocket boost disconnected");
        clocks(2);if(dut.ui_rocket_req!==1'b0) $fatal(1,"Rocket boost stuck after request release");
        $display("PASS merge_integration_tb: complete CDC snapshot, physics-owned rocket readiness, and mouse rocket request");
        $finish;
    end
    initial begin #200000;$fatal(1,"Merge integration timeout");end
endmodule
