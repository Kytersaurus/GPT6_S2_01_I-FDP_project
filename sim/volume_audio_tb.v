// Owner: Role 1 - Kaushal. Real sound-page clicks and shared audio gain.
`timescale 1ns / 1ps
`include "game_defs.vh"
module volume_audio_tb;
    reg clk=0,btnD=1,btnC=0,btnR=0;
    reg [15:0] sw=0;
    reg [11:0] mx=0,my=0;
    reg ml=0,mr=0,me=0;
    tri1 PS2Clk,PS2Data;
    integer n,starts=0;
    My_Top_Module #(.PHYSICS_CYCLES(1000000),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2),
        .BGM_UNIT_CYCLES(4096),.AUDIO_NOTE_CYCLES(1024),.AUDIO_FADE_CYCLES(8)) dut (
        .clk(clk),.btnD(btnD),.btnC(btnC),.btnU(1'b0),.btnL(1'b0),.btnR(btnR),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.led(),.JXADC(),.seg(),.an(),.dp()
    );
    always #5 clk=~clk;
    always @(posedge clk) if(!dut.reset && dut.sound_start) starts=starts+1;
    initial begin
        force dut.mouse_x=mx; force dut.mouse_y=my;
        force dut.mouse_left=ml; force dut.mouse_right=mr; force dut.mouse_event=me;
    end
    task clocks;input integer c;begin repeat(c) @(negedge clk);end endtask
    task packet;input integer x,y;input l,right;
        begin mx=x;my=y;ml=l;mr=right;me=1;clocks(1);me=0;clocks(3);end
    endtask
    task click;input integer x,y;
        begin packet(x,y,0,0);packet(x,y,1,0);packet(x,y,0,0);end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(300);
        if(dut.master_volume!=2 || dut.u_bgm.volume!=2 || dut.u_bgm.bass_volume!=1)
            $fatal(1,"Half-volume melody/bass not available at startup");
        btnR=1;clocks(30);btnR=0;clocks(30);
        if(starts!=0 || dut.audio_busy) $fatal(1,"Removed test button still plays audio");
        click(88,59);click(30,18);
        if(dut.diary_page!=3 || dut.game_state!=`LP_GUIDE) $fatal(1,"Sound page unreachable");
        packet(20,35,1,0);clocks(100);packet(20,35,1,0);
        if(dut.master_volume!=1) $fatal(1,"Held volume button repeated");
        packet(20,35,0,0);
        for(n=0;n<5;n=n+1) click(20,35);
        clocks(300);
        if(dut.master_volume!=0 || dut.bgm_sample!=0 || dut.u_audio.pwm_level!=128)
            $fatal(1,"Volume lower bound or silent PWM incorrect");
        packet(70,35,1,1);packet(70,35,0,0);
        if(dut.master_volume!=0) $fatal(1,"Right click raised volume");
        for(n=0;n<6;n=n+1) click(70,35);
        clocks(300);
        if(dut.master_volume!=4 || dut.u_bgm.volume!=4 || dut.u_bgm.bass_volume!=2)
            $fatal(1,"Volume upper bound or audible diary preview incorrect");
        click(20,35);click(20,35);clocks(300);
        if(dut.master_volume!=2 || dut.u_bgm.volume!=2 || dut.u_bgm.bass_volume!=1)
            $fatal(1,"Music voices ignored selected volume");
        click(12,59);
        if(dut.game_state!=`LP_SETTINGS) $fatal(1,"Audio Back lost settings");
        click(12,59);
        dut.u_builder.build_grid={`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
            `LP_PART_ENGINE,`LP_PART_PIG,`LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY};
        dut.u_builder.build_frames=9'b000111000;clocks(3);
        btnC=1;clocks(14);btnC=0;clocks(150);
        if(dut.game_state!=`LP_RUN || dut.master_volume!=2 || !dut.u_bgm.fast ||
           dut.u_bgm.note_index!=0 || dut.u_bgm.half_cycles!=95556)
            $fatal(1,"Launch did not select Bad Piggies or preserve volume");
        if(!dut.audio_busy || dut.u_audio.volume!=6 || dut.bgm_sample!=0)
            $fatal(1,"Effect volume or two-voice effect priority incorrect");
        clocks(2500);
        if(dut.audio_busy || dut.u_bgm.volume!=1 || dut.u_bgm.bass_volume!=1)
            $fatal(1,"Gameplay melody and bass did not resume together");
        sw=2;clocks(300);
        if(dut.bgm_sample!=0 || dut.u_audio.pwm_level!=128 || dut.JXADC[3]!=0 || dut.master_volume!=2)
            $fatal(1,"Mute did not override/preserve volume");
        sw=0;clocks(300);
        if(dut.master_volume!=2 || dut.u_bgm.bass_volume!=1) $fatal(1,"Unmute lost volume/bass");
        btnD=1;clocks(12);btnD=0;clocks(300);
        if(dut.master_volume!=2 || dut.game_state!=`LP_BUILD) $fatal(1,"Reset did not restore default volume");
        $display("PASS volume_audio_tb: sound page, held/right clicks, limits, quiet zero, both voices, launch track, effect priority, removed BTNR, mute/reset");
        $finish;
    end
    initial begin #1000000;$fatal(1,"Volume audio test timed out");end
endmodule
