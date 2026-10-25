// Owner: Role 1 - Kaushal. Level menu with real top-level mouse and state wiring.
`timescale 1ns / 1ps
`include "game_defs.vh"
module level_selector_tb;
    reg clk=0,btnD=1,btnC=0,btnU=0;
    reg [11:0] mx=0,my=0;
    reg ml=0,mr=0,me=0;
    tri1 PS2Clk,PS2Data;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames;
    integer i;
    always #5 clk=~clk;
    My_Top_Module #(.ENABLE_BGM(0),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2)) dut (
        .clk(clk),.btnD(btnD),.btnC(btnC),.btnU(btnU),.btnL(1'b0),.btnR(1'b0),.sw(16'd0),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.led(),.JXADC(),.seg(),.an(),.dp());
    initial begin
        force dut.mouse_x=mx;force dut.mouse_y=my;
        force dut.mouse_left=ml;force dut.mouse_right=mr;force dut.mouse_event=me;
    end
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task packet;
        input integer x,y;input l,r;
        begin mx=x;my=y;ml=l;mr=r;me=1;clocks(1);me=0;clocks(3);end
    endtask
    task click;
        input integer x,y;
        begin packet(x,y,0,0);packet(x,y,1,0);packet(x,y,0,0);end
    endtask
    task open_menu;
        begin click(88,59);if(dut.game_state!==`LP_LEVEL_SELECT) $fatal(1,"Map icon did not open menu");end
    endtask
    task preserved;
        begin
            if(dut.build_grid!==saved_grid || dut.build_frames!==saved_frames ||
               dut.frames_left!==2 || dut.pigs_left!==0 || dut.engines_left!==0 || dut.wheels_left!==0)
                $fatal(1,"Menu changed saved build or inventory");
        end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(280);
        dut.u_builder.build_grid={`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
            `LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,`LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY};
        dut.u_builder.build_frames=9'b000111000;clocks(3);
        saved_grid=dut.build_grid;saved_frames=dut.build_frames;
        // Opening must not cycle; held movement over a tile must not select it.
        packet(88,59,1,0);packet(60,42,1,0);clocks(10);
        if(dut.game_state!==`LP_LEVEL_SELECT || dut.level_index!==0) $fatal(1,"Held icon click selected a level");
        packet(60,42,0,0);click(48,33);
        if(dut.game_state!==`LP_LEVEL_SELECT) $fatal(1,"Gap selected a level");
        packet(60,42,0,1);packet(60,42,0,0);
        if(dut.game_state!==`LP_LEVEL_SELECT) $fatal(1,"Right click selected a level");
        btnC=1;clocks(12);btnC=0;clocks(12);
        if(dut.game_state!==`LP_LEVEL_SELECT || dut.run_init) $fatal(1,"Launch started inside menu");
        click(10,59);if(dut.game_state!==`LP_BUILD || dut.level_index!==0) $fatal(1,"Back changed level");
        for(i=0;i<4;i=i+1) begin
            open_menu();click((i%2) ? 60 : 10,(i>=2) ? 42 : 20);
            if(dut.game_state!==`LP_BUILD || dut.level_index!==i) $fatal(1,"Wrong selected level %0d",i);
            preserved();
            if(dut.u_mouse_adapter.inventory_armed || dut.drag_active) $fatal(1,"Menu release armed a construction edit");
        end
        open_menu();btnU=1;clocks(12);btnU=0;clocks(12);
        if(dut.game_state!==`LP_BUILD || dut.level_index!==3) $fatal(1,"U did not cancel menu");
        open_menu();force dut.builder_input_enabled=1'b0;
        click(10,20);if(dut.game_state!==`LP_LEVEL_SELECT || dut.level_index!==3) $fatal(1,"Hidden menu accepted click");
        packet(10,20,1,0);release dut.builder_input_enabled;packet(10,20,1,0);
        if(dut.game_state!==`LP_LEVEL_SELECT) $fatal(1,"Hidden held press became fresh");
        packet(10,20,0,0);click(10,20);preserved();
        force dut.left_frame=1'b1;open_menu();clocks(400);
        if(dut.draw_state!==`LP_LEVEL_SELECT || dut.draw_level!==0) $fatal(1,"Menu state lost in display snapshot");
        btnD=1;clocks(20);btnD=0;clocks(280);
        if(dut.game_state!==`LP_BUILD || dut.level_index!==0 || dut.build_grid!==0) $fatal(1,"Menu reset failed");
        $display("PASS level_selector_tb: four maps, held/right/hidden clicks, gaps, launch guard, Back/U, snapshot, preserved build and inventory, reset");
        $finish;
    end
    initial begin #200000;$fatal(1,"Level selector timed out");end
endmodule
