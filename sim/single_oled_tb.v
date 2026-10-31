// Owner: Shared integration - JA view selection and hidden input protection.
`timescale 1ns / 1ps
`include "game_defs.vh"
module single_oled_tb;
    reg clk=0, btnD=1;
    reg [15:0] sw=0;
    reg [11:0] mx=0, my=0;
    reg ml=0, mr=0, me=0;
    tri1 PS2Clk, PS2Data;
    wire [7:0] JA, JB;
    always #5 clk=~clk;
    My_Top_Module dut (
        .clk(clk),.btnC(1'b0),.btnU(1'b0),.btnR(1'b0),.btnL(1'b0),.btnD(btnD),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(JA),.JB(JB),.JXADC(),.led()
    );
    initial begin
        force dut.mouse_x=mx; force dut.mouse_y=my;
        force dut.mouse_left=ml; force dut.mouse_right=mr; force dut.mouse_event=me;
    end
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task packet;
        input [11:0] x,y;
        input held;
        begin mx=x;my=y;ml=held;me=1;clocks(1);me=0;clocks(2);end
    endtask
    task click;
        input [11:0] x,y;
        begin packet(x,y,0);packet(x,y,1);packet(x,y,0);end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(280);
        force dut.left_frame=1'b1;
        force dut.left_pixel_index=13'd5755; // Rotated physical location of logical (4,4).
        force dut.right_pixel_index=13'd0;
        clocks(400);
        if(dut.show_map || dut.u_left_oled.pixel_data!==16'h7bef)
            $fatal(1,"JA did not show the upright builder grid");
        force dut.left_frame=1'b0;
        sw=16'h8000;clocks(100);
        if(dut.show_map) $fatal(1,"View changed inside a frame");
        force dut.left_frame=1'b1;clocks(200);
        if(!dut.show_map || dut.u_left_oled.pixel_data!==16'h4af1 || dut.u_right_oled.pixel_data!==0)
            $fatal(1,"JA map selection, rotation or JB blanking incorrect");
        click(74,8);click(12,12);click(88,59);
        if(dut.build_frames!==0 || dut.level_index!==0 || dut.drag_active)
            $fatal(1,"Hidden builder/level controls accepted a click");
        packet(12,12,1);sw=0;clocks(200);packet(12,12,0);
        if(dut.show_map || !dut.builder_input_enabled || dut.build_frames!==0 ||
           dut.u_left_oled.pixel_data!==16'h7bef || dut.u_right_oled.pixel_data!==16'h4af1)
            $fatal(1,"Returning to the builder retained a stale press or wrong pixels");
        click(74,8);click(12,12);
        if(dut.build_frames!==9'b000000001) $fatal(1,"Visible builder did not accept placement");
        packet(74,8,1);packet(28,12,1);sw=16'h8000;clocks(200);packet(28,12,0);
        if(dut.build_frames!==9'b000000001 || dut.drag_active || dut.engine_enabled || dut.audio_muted)
            $fatal(1,"View change left a pending drag or interfered with engine/mute");
        if(!dut.u_bgm.enabled || dut.u_bgm.fast) $fatal(1,"Builder music was disabled by the map view");
        force dut.game_state=`LP_RUN;clocks(2);
        if(!dut.u_bgm.enabled || !dut.u_bgm.fast) $fatal(1,"Gameplay did not select the faster music tempo");
        sw=16'h8002;clocks(8);
        if(dut.u_bgm.enabled || dut.bgm_sample!=0 || dut.JXADC[3]!==0)
            $fatal(1,"Global mute did not stop background music and the amplifier");
        sw=16'h8000;force dut.game_state=`LP_SUCCESS;clocks(8);
        if(dut.u_bgm.enabled || dut.bgm_sample!=0) $fatal(1,"Result state did not stop background music");
        release dut.game_state;
        release dut.left_frame;release dut.left_pixel_index;release dut.right_pixel_index;
        $display("PASS single_oled_tb: frame-boundary SW15 selection, JA rotation, map pixels, JB blanking, hidden/stale inputs, independent controls and state/mute music wiring");
        $finish;
    end
    initial begin #100000; $fatal(1,"Single OLED test timed out");end
endmodule
