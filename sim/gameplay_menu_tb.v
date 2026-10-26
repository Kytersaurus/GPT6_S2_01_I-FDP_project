// Owner: Role 1 - Kaushal. Real construction, direction and menu integration.
`timescale 1ns / 1ps
`include "game_defs.vh"
module gameplay_menu_tb;
    reg clk=0,btnD=1,btnC=0,btnU=0;
    reg [15:0] sw=1;
    reg [11:0] mx=0,my=0;
    reg ml=0,mr=0,me=0;
    tri1 PS2Clk,PS2Data;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames,saved_direction;
    integer n;
    always #5 clk=~clk;
    My_Top_Module #(.ENABLE_BGM(0),.PHYSICS_CYCLES(1000000),.BUTTON_DEBOUNCE_CYCLES(2),
        .BUTTON_RELEASE_CYCLES(2),.AUDIO_NOTE_CYCLES(1024),.AUDIO_FADE_CYCLES(8)) dut (
        .clk(clk),.btnD(btnD),.btnC(btnC),.btnU(btnU),.btnR(1'b0),.btnL(1'b0),.sw(sw),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.JXADC(),.seg(),.an(),.dp(),.led());
    initial begin
        force dut.mouse_x=mx;force dut.mouse_y=my;
        force dut.mouse_left=ml;force dut.mouse_right=mr;force dut.mouse_event=me;
    end
    task clocks;input integer count;begin repeat(count) @(negedge clk);end endtask
    task packet;input integer x,y;input l,right;
        begin mx=x;my=y;ml=l;mr=right;me=1;clocks(1);me=0;clocks(3);end
    endtask
    task click;input integer x,y;
        begin packet(x,y,0,0);packet(x,y,1,0);packet(x,y,0,0);end
    endtask
    task place;input integer row,cell_id;
        begin packet(74,8+10*row,1,0);packet(12+16*(cell_id%3),12+16*(cell_id/3),0,0);end
    endtask
    task move;input integer from_cell,to_cell;
        begin packet(12+16*(from_cell%3),12+16*(from_cell/3),1,0);
        packet(12+16*(to_cell%3),12+16*(to_cell/3),0,0);end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(300);
        place(0,3);place(0,4);place(0,1);place(1,4);
        // Select engine, choose left, then place it in an existing frame.
        click(74,38);click(12,28);click(12,28);
        if(dut.engines_left!=0) $fatal(1,"Flip charged engine stock");
        click(12,28);click(12,28);
        if(dut.build_grid[11:9]!=`LP_PART_ENGINE || !dut.build_facing_left[3] || dut.engine_balance!=-1)
            $fatal(1,"Left-facing engine selection was not saved");
        move(3,1);
        if(!dut.build_frames[3] || dut.build_grid[11:9]!=0 || dut.build_grid[5:3]!=`LP_PART_ENGINE ||
           !dut.build_facing_left[1] || dut.frames_left!=2 || dut.engines_left!=0)
            $fatal(1,"Contents-first move lost its frame, direction or stock");
        saved_grid=dut.build_grid;move(4,1);
        if(dut.build_grid!==saved_grid || !dut.build_frames[4]) $fatal(1,"Rejected occupied move changed its source");
        move(3,8);move(8,3);
        if(!dut.build_frames[3] || dut.build_frames[8]) $fatal(1,"Empty frame did not move independently");
        place(2,6);place(2,7);place(4,0);
        click(40,59);
        if(!dut.inventory_page) $fatal(1,"Extra inventory page did not open");
        click(74,8);click(44,28);click(44,28);
        if(!dut.build_facing_left[5]) $fatal(1,"Rocket click did not flip");
        click(44,28);
        if(dut.build_grid[17:15]!=`LP_PART_BOOSTER || dut.build_facing_left[5] || dut.rockets_left!=0)
            $fatal(1,"Right-facing side rocket not placed/accounted");
        click(54,59);place(0,2);
        if(dut.fan_count!=1 || dut.fans_left!=0 || !dut.build_valid) $fatal(1,"Side fan placement failed");
        // Side attachment cannot wrap from the end of one row to the next.
        saved_grid=dut.build_grid;move(2,8);
        if(dut.build_grid!==saved_grid) $fatal(1,"Unsupported fan move accepted");
        saved_frames=dut.build_frames;saved_direction=dut.build_facing_left;
        click(8,59);clocks(30);
        if(dut.game_state!=`LP_RUN || dut.run_page!=0 || !dut.engine_reverse || dut.drive_engines!=1)
            $fatal(1,"DRIVE default or left-engine physics contract incorrect");
        sw=5;clocks(5);if(dut.engine_reverse) $fatal(1,"SW2 failed to reverse saved engine direction");sw=1;clocks(5);
        click(20,16);if(dut.engine_enabled) $fatal(1,"Engine OFF menu missing");
        packet(20,16,1,0);packet(20,16,1,0);packet(20,16,0,0);
        if(!dut.engine_enabled) $fatal(1,"Held engine menu repeated");
        if(dut.balloon_count!=1) $fatal(1,"DRIVE clicks reached balloon controls");
        click(48,59);if(dut.run_page!=1) $fatal(1,"POP page did not open");
        click(12,12);clocks(3);
        if(dut.balloon_count!=0 || dut.balloons_left!=1) $fatal(1,"POP did not use the vehicle view");
        click(80,59);click(20,35);
        if(dut.run_page!=2 || dut.master_volume!=3) $fatal(1,"RUN sound controls missing");
        click(86,4);clocks(40);
        if(dut.game_state!=`LP_RUN || dut.run_page!=0 || dut.balloon_count!=1 || dut.master_volume!=3 ||
           dut.build_facing_left!==saved_direction || dut.build_frames!==saved_frames)
            $fatal(1,"Round-arrow retry lost build, controls or volume");
        click(55,4);clocks(3);
        if(dut.game_state!=`LP_BUILD || dut.level_index!=0 || dut.balloon_count!=1)
            $fatal(1,"RUN edit changed level or failed to restore construction");
        btnC=1;clocks(14);btnC=0;clocks(30);
        btnC=1;clocks(14);btnC=0;clocks(30);
        if(dut.game_state!=`LP_RUN || dut.run_page!=0) $fatal(1,"Physical retry shortcut removed");
        btnU=1;clocks(14);btnU=0;clocks(5);
        if(dut.game_state!=`LP_BUILD) $fatal(1,"Physical edit shortcut removed");
        $display("PASS gameplay_menu_tb: contents-first moves, engine/rocket facing, side attachments/stock, SW2, DRIVE/POP/SOUND, retry/edit and physical shortcuts");
        $finish;
    end
    initial begin #300000;$fatal(1,"Gameplay menu test timed out");end
endmodule
