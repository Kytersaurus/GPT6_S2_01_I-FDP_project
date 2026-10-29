// Owner: Shared integration - controls must coexist after merging all roles.
`timescale 1ns / 1ps
`include "game_defs.vh"
module team_controls_tb;
    reg clk=0,btnC=0,btnU=0,btnR=0,btnL=0,btnD=1;
    reg [15:0] sw=0;
    wire [15:0] led;
    wire [7:0] JA,JB;
    wire [3:0] JXADC;
    tri1 PS2Clk,PS2Data;
    integer jump_pulses=0,beep_pulses=0,waited;
    always #5 clk=~clk;
    My_Top_Module #(.PHYSICS_CYCLES(64),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2),
        .AUDIO_BEEP_CYCLES(1024),.AUDIO_NOTE_CYCLES(1024),.AUDIO_FADE_CYCLES(8)) dut (
        .clk(clk),.btnC(btnC),.btnU(btnU),.btnR(btnR),.btnL(btnL),.btnD(btnD),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.led(led),.JA(JA),.JB(JB),.JXADC(JXADC));
    always @(posedge clk) if(!dut.reset) begin
        if(dut.jump_press) jump_pulses=jump_pulses+1;
        if(dut.sound_start && dut.sound_id==`LP_SOUND_TEST) beep_pulses=beep_pulses+1;
    end
    // Test-only gameplay fixture; the hardware builder starts empty.
    task build_test_vehicle;
        begin
            dut.u_builder.build_grid = {
                `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
                `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
            };
            dut.u_builder.build_frames = 9'b000111000;
            clocks(2);
        end
    endtask
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk);end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(280);build_test_vehicle();
        sw=2;clocks(8);
        if(!dut.audio_muted || dut.engine_reverse || !dut.engine_enabled) $fatal(1,"SW1 conflicts with DRIVE control");
        sw=4;clocks(8);
        if(dut.audio_muted || !dut.engine_reverse || !dut.engine_enabled) $fatal(1,"SW2 does not independently reverse");
        btnR=1;clocks(16);btnR=0;clocks(16);
        if(beep_pulses!=0 || jump_pulses!=0) $fatal(1,"Reserved BTNR made a sound or jumped");
        btnL=1;clocks(16);btnL=0;clocks(16);
        if(beep_pulses!=0 || jump_pulses!=1) $fatal(1,"BTNL jump also requested test audio");
        // Real reverse movement must use SW2, with audio unmuted.
        sw=5;clocks(8);btnC=1;clocks(16);btnC=0;
        waited=0;while(dut.vehicle_x>=dut.level_spawn_x && waited<500000) begin clocks(1);waited=waited+1;end
        if(dut.game_state!=`LP_RUN || dut.vehicle_x>=dut.level_spawn_x || dut.audio_muted) $fatal(1,"Reverse did not drive left independently");
        // Restart forward, then hold jump: only one press pulse and one jump.
        btnD=1;clocks(10);btnD=0;sw=0;clocks(30);build_test_vehicle();btnC=1;clocks(16);btnC=0;
        waited=0;while(!dut.u_physics.was_grounded && waited<500000) begin clocks(1);waited=waited+1;end
        if(!dut.u_physics.was_grounded) $fatal(1,"Vehicle never established ground contact");
        jump_pulses=0;btnL=1;
        waited=0;while(dut.vehicle_y>=dut.level_spawn_y && waited<500000) begin clocks(1);waited=waited+1;end
        if(dut.vehicle_y>=dut.level_spawn_y || jump_pulses!=1) $fatal(1,"BTNL did not jump once");
        clocks(200);
        if(jump_pulses!=1) $fatal(1,"Held jump repeated");
        btnL=0;
        $display("PASS team_controls_tb: DRIVE engine, SW1 mute/SW2 reverse debug, BTNR silent, BTNL jump, real reverse and held-jump suppression");
        $finish;
    end
    initial begin #15000000; $fatal(1,"Merged controls test timed out");end
endmodule
