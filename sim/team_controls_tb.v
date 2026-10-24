// Owner: Shared integration - controls must coexist after merging all roles.
`timescale 1ns / 1ps
`include "game_defs.vh"
module team_controls_tb;
    reg clk=0,btnC=0,btnU=0,btnR=0,btnL=0,btnD=1;
    reg [2:0] sw=0;
    wire [15:0] led;
    wire [7:0] JA,JB;
    wire [3:0] JC;
    tri1 PS2Clk,PS2Data;
    integer jump_pulses=0,beep_pulses=0,waited;
    always #5 clk=~clk;
    My_Top_Module #(.PHYSICS_CYCLES(64),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2),
        .AUDIO_BEEP_CYCLES(1024),.AUDIO_NOTE_CYCLES(1024),.AUDIO_FADE_CYCLES(8)) dut (
        .clk(clk),.btnC(btnC),.btnU(btnU),.btnR(btnR),.btnL(btnL),.btnD(btnD),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.led(led),.JA(JA),.JB(JB),.JC(JC));
    always @(posedge clk) if(!dut.reset) begin
        if(dut.jump_press) jump_pulses=jump_pulses+1;
        if(dut.beep_press) beep_pulses=beep_pulses+1;
    end
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk);end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(280);
        sw=2;clocks(8);
        if(!dut.audio_muted || dut.engine_reverse || dut.engine_enabled) $fatal(1,"SW1 conflicts with movement");
        sw=4;clocks(8);
        if(dut.audio_muted || !dut.engine_reverse || dut.engine_enabled) $fatal(1,"SW2 does not independently reverse");
        btnR=1;clocks(16);btnR=0;clocks(16);
        if(beep_pulses!=1 || jump_pulses!=0) $fatal(1,"BTNR test also jumped");
        btnL=1;clocks(16);btnL=0;clocks(16);
        if(beep_pulses!=1 || jump_pulses!=1) $fatal(1,"BTNL jump also requested test audio");
        // Real reverse movement must use SW2, with audio unmuted.
        sw=5;clocks(8);btnC=1;clocks(16);btnC=0;
        waited=0;while(dut.vehicle_x>=1024 && waited<500) begin clocks(1);waited=waited+1;end
        if(dut.game_state!=`LP_RUN || dut.vehicle_x>=1024 || dut.audio_muted) $fatal(1,"Reverse did not drive left independently");
        // Restart forward, then hold jump: only one press pulse and one jump.
        btnD=1;clocks(10);btnD=0;sw=0;clocks(30);btnC=1;clocks(16);btnC=0;clocks(180);
        if(!dut.u_physics.was_grounded) $fatal(1,"Vehicle never established ground contact");
        jump_pulses=0;btnL=1;
        waited=0;while(dut.vehicle_y>=8192 && waited<300) begin clocks(1);waited=waited+1;end
        if(dut.vehicle_y>=8192 || jump_pulses!=1) $fatal(1,"BTNL did not jump once");
        clocks(200);
        if(jump_pulses!=1) $fatal(1,"Held jump repeated");
        btnL=0;
        $display("PASS team_controls_tb: independent SW0 engine/SW1 mute/SW2 reverse, BTNR test, BTNL jump, real reverse and held-jump suppression");
        $finish;
    end
    initial begin #100000; $fatal(1,"Merged controls test timed out");end
endmodule
