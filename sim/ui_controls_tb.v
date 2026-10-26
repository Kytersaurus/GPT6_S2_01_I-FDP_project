// Owner: Role 1 - Kaushal. Real mouse diary/engine controls and future air-control contract.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_controls_tb;
    reg clk=0,btnD=1,btnC=0,btnU=0;
    reg [15:0] sw=1;
    reg [11:0] mx=24,my=24;
    reg ml=0,mr=0,me=0;
    tri1 PS2Clk,PS2Data;
    integer waited;
    My_Top_Module #(.ENABLE_BGM(0),.PHYSICS_CYCLES(24),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2)) dut (
        .clk(clk),.btnD(btnD),.btnC(btnC),.btnU(btnU),.btnL(1'b0),.btnR(1'b0),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.led(),.JXADC(),.seg(),.an(),.dp()
    );
    initial begin
        force dut.mouse_x=mx; force dut.mouse_y=my;
        force dut.mouse_left=ml; force dut.mouse_right=mr; force dut.mouse_event=me;
    end
    always #5 clk=~clk;
    task clocks; input integer n; begin repeat(n) @(negedge clk); end endtask
    task packet;
        input integer x,y; input l,r;
        begin mx=x; my=y; ml=l; mr=r; me=1; clocks(1); me=0; clocks(3); end
    endtask
    task click;
        input integer x,y;
        begin packet(x,y,0,0); packet(x,y,1,0); packet(x,y,0,0); end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(280);
        click(70,59);
        if(dut.game_state!=`LP_GUIDE || dut.diary_page!=0) $fatal(1,"Diary did not open");
        packet(78,59,1,0); clocks(20);
        if(dut.diary_page!=2) $fatal(1,"Held next press repeated");
        packet(78,59,0,0);click(78,59);click(78,59);
        if(dut.diary_page!=2) $fatal(1,"Diary page bounds failed");
        click(60,59);
        if(dut.diary_page!=1) $fatal(1,"Diary previous failed");
        click(12,59);
        if(dut.game_state!=`LP_BUILD || dut.build_grid!=0) $fatal(1,"Diary changed construction");
        // The board U key also opens/closes the diary without changing levels.
        btnU=1;clocks(12);btnU=0;clocks(12);
        if(dut.game_state!=`LP_GUIDE) $fatal(1,"U diary shortcut missing");
        btnU=1;clocks(12);btnU=0;clocks(12);
        if(dut.game_state!=`LP_BUILD || dut.level_index!=0) $fatal(1,"U diary back failed");
        dut.u_builder.build_grid={`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
            `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,`LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY};
        dut.u_builder.build_frames=9'b000111000;clocks(3);
        click(8,59);clocks(8);
        if(dut.game_state!=`LP_RUN || !dut.engine_enabled) $fatal(1,"Mouse GO failed");
        click(64,16);
        if(dut.engine_enabled) $fatal(1,"Engine mouse OFF failed");
        packet(64,16,1,0);clocks(15);
        if(!dut.engine_enabled) $fatal(1,"Engine mouse ON failed");
        packet(64,16,1,0);clocks(15);
        if(!dut.engine_enabled) $fatal(1,"Held engine press repeated");
        packet(64,16,0,0);
        sw=0;clocks(5);
        if(!dut.engine_enabled) $fatal(1,"SW0 changed on-screen engine setting");
        sw=1;clocks(5);
        if(!dut.engine_enabled) $fatal(1,"Master switch did not restore engine");
        click(64,24);click(64,48);
        if(dut.u_ui_control.fan_on || dut.u_ui_control.rocket_req) $fatal(1,"Unavailable air control activated");
        // Simulate result arrival; the diary must return to FAIL, not restart BUILD.
        force dut.u_game.game_state=`LP_FAIL;clocks(2);release dut.u_game.game_state;
        click(78,59);
        if(dut.game_state!=`LP_GUIDE || dut.guide_return_state!=`LP_FAIL) $fatal(1,"Result diary origin lost");
        click(10,59);
        if(dut.game_state!=`LP_FAIL) $fatal(1,"Diary did not restore result");
        $display("PASS ui_controls_tb: diary bounds/back, board shortcut, mouse launch, master engine power, held clicks and unavailable air controls");
        $finish;
    end
    initial begin #500000; $fatal(1,"UI controls timed out"); end
endmodule
