// Owner: Shared UI integration - Role 1 and Role 4. Export real renderer pixels for visual review.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_visual_tb;
    reg clk=0;
    reg [12:0] pixel=0;
    reg [2:0] state=`LP_BUILD;
    reg [1:0] page=0,death=0;
    reg go=0;
    reg [8:0] intact=9'b101011000;
    reg [26:0] grid=0;
    tri1 PS2Clk,PS2Data;
    integer p,left_file,right_file;
    My_Top_Module dut(.clk(clk),.btnD(1'b0),.btnC(1'b0),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),.sw(16'd1),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.JXADC(),.led(),.seg(),.an(),.dp());
    always #5 clk=~clk;
    initial begin
        force dut.left_pixel_index=13'd6143-pixel;force dut.right_pixel_index=pixel;
        force dut.draw_state=state;force dut.draw_guide_return=`LP_BUILD;
        force dut.draw_grid=grid;force dut.draw_saved_frames=9'b000111000;
        force dut.draw_frames=9'b000111000;force dut.draw_intact=intact;
        force dut.draw_valid=1'b1;force dut.draw_error=4'd0;force dut.draw_feedback_code=3'd0;
        force dut.draw_engine=1'b1;force dut.draw_boost_active=1'b0;
        force dut.draw_cursor_x=7'd90;force dut.draw_cursor_y=7'd53;
        force dut.draw_drag_active=1'b0;force dut.draw_selected_part=`LP_PART_FRAME;
        force dut.draw_frames_left=4'd2;force dut.draw_pigs_left=4'd0;force dut.draw_wheels_left=4'd0;
        force dut.draw_engines_left=4'd0;force dut.draw_balloons_left=4'd2;
        force dut.draw_level=1'b0;force dut.draw_seconds=7'd42;force dut.draw_diary_page=page;
        force dut.draw_x=16'sd5120;force dut.draw_y=16'sd8192;
        force dut.draw_death_phase=death;force dut.draw_death_x=16'sd8192;force dut.draw_death_y=16'sd11264;
        force dut.draw_launch_flash=go;force dut.draw_tnt_intact=4'b1111;force dut.draw_blast=8'd0;
        force dut.draw_fail_reason=`LP_FAIL_PIG;
    end
    task frame;
        input [255:0] name;
        begin
            left_file=$fopen({name,"_left.hex"},"w");right_file=$fopen({name,"_right.hex"},"w");
            for(p=0;p<6144;p=p+1) begin
                pixel=p;@(posedge dut.oled_clk);#1;
                if($isunknown(dut.left_pixel_data) || $isunknown(dut.right_pixel_data)) $fatal(1,"Unknown UI pixel");
                $fdisplay(left_file,"%h",dut.left_pixel_data);$fdisplay(right_file,"%h",dut.right_pixel_data);
            end
            $fclose(left_file);$fclose(right_file);
        end
    endtask
    initial begin
        grid={`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_PIG,`LP_PART_ENGINE,
              `LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY};
        repeat(320) @(negedge clk);
        frame("ui_build");
        state=`LP_GUIDE;frame("ui_diary_1");page=1;frame("ui_diary_2");page=2;frame("ui_diary_3");
        state=`LP_LEVEL_SELECT;frame("ui_levels");
        force dut.draw_level=2'd3;frame("ui_levels_l4");force dut.draw_level=2'd0;
        state=`LP_RUN;frame("ui_run");go=1;frame("ui_launch");go=0;
        state=`LP_FAIL;intact[4]=0;death=1;frame("ui_death_1");death=2;frame("ui_death_2");death=3;frame("ui_death_3");
        // The death effect uses world coordinates at either camera zoom.
        force dut.draw_level=2'd2;
        force dut.draw_x=16'sd26624;force dut.draw_y=16'sd6656;
        force dut.draw_death_x=16'sd30720;force dut.draw_death_y=16'sd10240;
        force dut.draw_free_look=1'b0;force dut.draw_zoomed_out=1'b0;
        death=1;pixel=36*96+54;@(posedge dut.oled_clk);#1;
        if(dut.right_pixel_data!==16'hffe0) $fatal(1,"Death burst did not follow 1.5x camera");
        force dut.draw_zoomed_out=1'b1;
        pixel=34*96+52;@(posedge dut.oled_clk);#1;
        if(dut.right_pixel_data!==16'hffe0) $fatal(1,"Death burst did not follow 1x camera");
        state=`LP_RUN;go=1;pixel=34;@(posedge dut.oled_clk);#1;
        if(dut.right_pixel_data!==16'h04b4) $fatal(1,"Launch banner moved with the camera");
        $display("PASS ui_visual_tb: build, diary, RUN controls, transition and death pixels exported without unknowns");
        $finish;
    end
    initial begin #20000000;$fatal(1,"UI pixel export timed out");end
endmodule
