// Owner: Role 1 - Kaushal. Existing-part moves and inventory returns through the real mouse path.
`timescale 1ns / 1ps
`include "game_defs.vh"
module grid_moves_tb;
    reg clk=0,btnD=1;
    reg [11:0] mx=0,my=0;
    reg ml=0,mr=0,me=0;
    tri1 PS2Clk,PS2Data;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames;
    always #5 clk=~clk;
    My_Top_Module #(.ENABLE_BGM(0),.WHEEL_LIMIT(2)) dut (
        .clk(clk),.btnC(1'b0),.btnU(1'b0),.btnR(1'b0),.btnL(1'b0),.btnD(btnD),.sw(16'd0),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.JA(),.JB(),.JXADC(),.led()
    );
    initial begin
        force dut.mouse_x=mx;force dut.mouse_y=my;
        force dut.mouse_left=ml;force dut.mouse_right=mr;force dut.mouse_event=me;
    end
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk);end
    endtask
    task packet;
        input [11:0] x,y;
        input left_button,right_button;
        begin mx=x;my=y;ml=left_button;mr=right_button;me=1;clocks(1);me=0;clocks(2);end
    endtask
    task place;
        input integer row,target;
        begin
            packet(74,8+row*10,1,0);
            packet(12+(target%3)*16,12+(target/3)*16,0,0);
        end
    endtask
    task save_build;
        begin saved_grid=dut.build_grid;saved_frames=dut.build_frames;end
    endtask
    task unchanged;
        begin if(dut.build_grid!==saved_grid || dut.build_frames!==saved_frames)
            $fatal(1,"Rejected/cancelled move changed saved construction");end
    endtask
    initial begin
        clocks(20);btnD=0;clocks(280);
        // Construct through normal inventory drags, with exactly one pig and engine.
        place(0,3);place(0,4);place(0,5);place(1,4);place(3,5);place(2,6);place(2,8);
        if(!dut.build_valid || dut.mass_units!=13) $fatal(1,"Mouse setup did not create the test vehicle");
        save_build();packet(28,28,1,0);
        if(!dut.drag_from_grid || dut.drag_source!=4 || dut.drag_contents!=0 ||
           dut.selected_part!=`LP_PART_PIG) $fatal(1,"Filled frame did not pick its contents first");
        unchanged();
        force dut.left_frame=1'b1;
        force dut.left_pixel_index=13'd4106;
        clocks(400);
        if(dut.draw_selected_part!=`LP_PART_PIG || !dut.draw_saved_frames[4])
            $fatal(1,"Contents preview lost the stationary frame");
        packet(12,28,1,0);unchanged();packet(12,28,0,0);
        if(!dut.build_frames[4] || !dut.build_frames[3] || dut.build_grid[14:12]!=0 ||
           dut.build_grid[11:9]!=`LP_PART_PIG || dut.mass_units!=13 || dut.frames_left!=2 || dut.pigs_left!=0)
            $fatal(1,"Contents move changed frames, stock or mass");
        save_build();packet(12,28,1,0);packet(44,28,0,0);unchanged();
        if(dut.feedback_code!=`LP_FEEDBACK_OCCUPIED) $fatal(1,"Occupied content destination accepted");
        packet(12,28,1,0);packet(54,55,0,0);unchanged();
        packet(12,28,1,0);packet(12,28,0,0);unchanged();
        packet(12,28,1,0);packet(12,28,1,1);packet(12,28,0,0);unchanged();
        packet(12,28,1,0);packet(74,8,0,0);
        if(!dut.build_frames[3] || dut.build_grid[11:9]!=0 || dut.frames_left!=2 || dut.pigs_left!=1 || dut.build_valid)
            $fatal(1,"Returning contents refunded or removed the frame");
        place(0,0);packet(12,12,1,0);packet(44,12,0,0);
        if(dut.build_frames[0] || !dut.build_frames[2] || dut.frames_left!=1)
            $fatal(1,"Empty frame move failed");
        place(0,4);
        packet(12,44,1,0);packet(28,44,0,0);
        if(dut.build_grid[20:18]!=0 || dut.build_grid[23:21]!=`LP_PART_WHEEL || dut.wheels_left!=0)
            $fatal(1,"Wheel move charged stock or lost its source");
        // Remove the lower support: a top wheel is now legal when that frame exists.
        packet(12,28,0,1);packet(12,28,0,0);
        save_build();packet(28,44,1,0);packet(12,12,0,0);unchanged();
        if(dut.feedback_code!=`LP_FEEDBACK_FRAME_ABOVE) $fatal(1,"Unsupported wheel drop was accepted");
        place(0,3);place(4,0);packet(12,12,1,0);packet(28,12,0,0);
        if(dut.build_grid[2:0]!=0 || dut.build_grid[5:3]!=`LP_PART_BALLOON || dut.balloons_left!=1)
            $fatal(1,"Balloon move failed");
        save_build();packet(28,12,1,0);packet(12,44,0,0);unchanged();
        if(dut.feedback_code!=`LP_FEEDBACK_FRAME_BELOW) $fatal(1,"Unsupported balloon drop was accepted");
        packet(28,12,1,0);packet(74,48,0,0);
        if(dut.balloons_left!=2 || dut.balloon_count!=0) $fatal(1,"Balloon return did not refund stock");
        packet(44,28,1,0);packet(74,38,0,0);
        if(!dut.build_frames[5] || dut.build_grid[17:15]!=0 || dut.engines_left!=1 || dut.frames_left!=1)
            $fatal(1,"Engine contents return removed its frame");
        place(1,4);save_build();
        force dut.game_state=`LP_RUN;packet(28,28,1,0);packet(74,8,0,0);unchanged();
        force dut.game_state=`LP_INIT_RUN;clocks(3);
        if(dut.intact_mask[4]!==1 || dut.frame_intact_mask!==saved_frames)
            $fatal(1,"Retry did not restore the moved construction");
        release dut.game_state;release dut.left_frame;release dut.left_pixel_index;
        $display("PASS grid_moves_tb: mouse-built setup, contents-first preview, atomic moves, full-stock moves, occupied/unsupported/outside/same-cell/right-click cancellation, refunds and retry");
        $finish;
    end
    initial begin #100000; $fatal(1,"Grid move test timed out");end
endmodule
