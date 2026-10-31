`timescale 1ns / 1ps
`include "game_defs.vh"
module menu_fixes_tb;
    reg clk=0, reset_button=1;
    reg [15:0] switches=0;
    reg [11:0] mx=0,my=0;
    reg ml=0,me=0;
    reg [12:0] pixel=0;
    reg [2:0] volume=0;
    integer i,j,v,edge_index;
    tri1 PS2Clk,PS2Data;
    wire [3:0] an;
    wire [6:0] seg;
    wire dp;
    `include "ui_font.vh"
    always #5 clk=~clk;
    My_Top_Module #(.ENABLE_START_SCREEN(1),.ENABLE_BGM(0),.PHYSICS_CYCLES(1000000),
        .BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_RELEASE_CYCLES(2)) dut(
        .clk(clk),.btnD(reset_button),.btnC(1'b0),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),
        .sw(switches),.PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.JXADC(),.led(),
        .an(an),.seg(seg),.dp(dp));
    initial begin
        force dut.mouse_x=mx;force dut.mouse_y=my;
        force dut.effective_mouse_x=mx;force dut.effective_mouse_y=my;
        force dut.mouse_left=ml;force dut.mouse_right=1'b0;force dut.mouse_event=me;
    end
    task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task packet;input integer x,y;input l;begin mx=x;my=y;ml=l;me=1;clocks(1);me=0;clocks(4);end endtask
    task click;input integer x,y;begin packet(x,y,0);packet(x,y,1);packet(x,y,0);end endtask
    task settings_checks;begin
        // Sound's entire old overlapping row must enter Sound, even while muted.
        for(edge_index=0;edge_index<4;edge_index=edge_index+1) begin
            click(edge_index[0] ? 30 : 6,edge_index[1] ? 48 : 12);
            if(dut.game_state!=`LP_GUIDE || dut.diary_page!=3) $fatal(1,"Sound edge misrouted");
            click(12,59);
            click(edge_index[0] ? 60 : 36,edge_index[1] ? 48 : 12);
            if(dut.game_state!=`LP_LEVEL_SELECT) $fatal(1,"Map edge not selectable");
            click(12,59);
        end
        switches[1]=1;click(20,35);
        if(dut.game_state!=`LP_GUIDE || dut.diary_page!=3) $fatal(1,"Muted Sound opened map");
        click(70,35);click(70,35);click(70,35);
        if(dut.master_volume!=4) $fatal(1,"4/4 volume unreachable");
        click(12,59);
        if(dut.game_state!=`LP_SETTINGS) $fatal(1,"Sound Back lost Settings");
        click(78,35);
        if(dut.game_state!=`LP_SETTINGS || dut.mouse_speed!=2) $fatal(1,"Sensitivity opened map");
        click(78,35);click(78,35);
        if(dut.mouse_speed!=1) $fatal(1,"Sensitivity cycle broken");
        click(48,35);
        if(dut.game_state!=`LP_LEVEL_SELECT) $fatal(1,"Map not reachable");
        click(12,59);
        if(dut.game_state!=`LP_SETTINGS || dut.start_screen_active) $fatal(1,"Map Back went Home");
    end endtask
    initial begin
        clocks(20);reset_button=0;clocks(300);
        if(dut.master_volume!=2) $fatal(1,"Volume must start at 2/4");
        if(an!=15 || seg!=127 || !dp) $fatal(1,"Timer lit on title");
        click(48,40);click(12,18); // Play, choose first map.
        if(dut.game_state!=`LP_BUILD || dut.start_screen_active) $fatal(1,"Play/map flow broken");
        click(88,59);settings_checks();click(40,59);
        if(dut.game_state!=`LP_BUILD || dut.start_screen_active) $fatal(1,"Build settings Back broken");
        force dut.build_valid=1'b1;force dut.pig_alive=1'b1;force dut.init_ready=3'b111;
        click(8,59);clocks(20);
        if(dut.game_state!=`LP_RUN || dut.engine_enabled || dut.ui_fan_on) $fatal(1,"Launch did not start with actuators OFF");
        click(48,59);if(dut.run_page!=0) $fatal(1,"Bottom gap activated hidden page");
        if(dut.u_physics.moments_enabled) $fatal(1,"Wheel-only cart did not restore original turning");
        force dut.fans_left=4'd0;clocks(1);
        if(!dut.u_physics.moments_enabled) $fatal(1,"Fitted fan did not enable COM moments");
        release dut.fans_left;force dut.rockets_left=4'd0;clocks(1);
        if(!dut.u_physics.moments_enabled) $fatal(1,"Fitted rocket did not enable COM moments");
        release dut.rockets_left;
        // SW0 must inhibit both software toggles and actual output.
        click(20,16);if(dut.engine_enabled || dut.ui_engine_on) $fatal(1,"SW0 OFF bypassed by icon");
        switches[0]=1;clocks(5);click(20,16);
        if(!dut.engine_enabled) $fatal(1,"Engine icon cannot enable with SW0 ON");
        click(20,16);if(dut.engine_enabled) $fatal(1,"Engine icon cannot disable");
        click(20,16);switches[0]=0;clocks(5);
        if(dut.engine_enabled || dut.ui_engine_on) $fatal(1,"SW0 did not inhibit engine");
        click(84,59);settings_checks();click(40,59);
        if(dut.game_state!=`LP_RUN) $fatal(1,"Run settings Back lost running page");
        click(84,59);click(82,59);
        if(!dut.start_screen_active || dut.game_state!=`LP_BUILD) $fatal(1,"Settings Home failed");
        if(an!=15 || !dp) $fatal(1,"Timer lit at Home");
        click(48,40);click(12,18);click(8,59);clocks(20);
        click(34,59);clocks(4);
        if(dut.game_state!=`LP_FAIL) $fatal(1,"End try did not reach result");
        click(12,59);
        if(!dut.start_screen_active) $fatal(1,"Result Home retried run");
        // Verify actual 4/4 glyph pixels, including the previously missing level.
        force dut.draw_start_screen_active=1'b0;force dut.draw_state=`LP_GUIDE;
        force dut.draw_diary_page=2'd3;force dut.draw_master_volume=volume;
        force dut.left_pixel_index=13'd6143-pixel;
        for(v=0;v<=4;v=v+1) begin
            volume=v;
            for(j=0;j<7;j=j+1) for(i=0;i<5;i=i+1) begin
                pixel=(28+j)*96+40+i;#1;
                if((dut.left_pixel_data==16'h07ff)!==text_on({8'd48+volume,"/4             "},40,28,40+i,28+j))
                    $fatal(1,"Volume glyph mismatch at level %0d",v);
            end
        end
        $display("PASS menu_fixes_tb: default/max volume, mute/sensitivity isolation, map Back, Home, SW0, launch and timer gating");$finish;
    end
    initial begin #200000;$fatal(1,"Menu fixes timeout");end
endmodule
