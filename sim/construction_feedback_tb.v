// Owner: Role 1 - Kaushal. Construction outcomes, feedback timing and OLED messages.
`timescale 1ns / 1ps
`include "game_defs.vh"
module construction_feedback_tb;
    reg clk=0, reset=1, run_init=0, edit_valid=0;
    reg [2:0] state=`LP_BUILD;
    reg [1:0] operation=`LP_EDIT_PLACE;
    reg [3:0] cell_id=0;
    reg [2:0] part=`LP_PART_FRAME;
    wire [26:0] grid;
    wire [8:0] frames, intact, frame_intact;
    wire valid;
    wire [3:0] error, frames_left, pigs_left, wheels_left, engines_left, balloons_left;
    wire [2:0] feedback;
    wire [3:0] feedback_cell;
    reg [12:0] pixel=0;
    wire [15:0] colour;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames;
    reg [31:0] saved_count;
    integer file_handle, p;
    always #5 clk=~clk;

    vehicle_builder #(.FEEDBACK_CYCLES(1000)) builder (
        .edit_facing_left(1'b0),
        .clk(clk),.reset(reset),.game_state(state),.run_init(run_init),.init_ready(),
        .edit_valid(edit_valid),.edit_op(operation),.edit_cell(cell_id),.edit_source(4'd15),.edit_part(part),
        .damage_valid(1'b0),.damage_ready(),.damage_mask(9'd0),.damage_frame_mask(9'd0),
        .build_grid(grid),.build_frames(frames),.intact_mask(intact),.frame_intact_mask(frame_intact),
        .build_valid(valid),.build_error(error),.feedback_code(feedback),.feedback_cell(feedback_cell),
        .frames_left(frames_left),.pigs_left(pigs_left),.wheels_left(wheels_left),
        .engines_left(engines_left),.balloons_left(balloons_left)
    );
    left_renderer view (
        .build_facing_left(9'd0), .selected_left(1'b0), .inventory_page(1'b0), .rockets_left(4'd1), .fans_left(4'd1),
        .pixel_index(pixel),.game_state(state),.build_grid(grid),.intact_mask(intact),
        .frame_intact_mask(frame_intact),.build_valid(valid),.build_error(error),
        .feedback_code(feedback),.feedback_cell(feedback_cell),.engine_enabled(1'b0),
        .frames_left(frames_left),.pigs_left(pigs_left),.wheels_left(wheels_left),
        .engines_left(engines_left),.balloons_left(balloons_left),.selected_part(part),
        .drag_active(1'b0),.drag_from_grid(1'b0),.drag_source(4'd9),.drag_contents(3'd0),.cursor_x(7'd0),.cursor_y(7'd0),.cursor_visible(1'b0),.pixel_data(colour)
    );
    // Test-only gameplay fixture; the hardware builder starts empty.
    task build_test_vehicle;
        begin
            builder.build_grid = {
                `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
                `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
            };
            builder.build_frames = 9'b000111000;
            clocks(2);
        end
    endtask
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task act;
        input [1:0] op;
        input [3:0] target;
        input [2:0] item;
        begin
            operation=op; cell_id=target; part=item; edit_valid=1;
            clocks(1); edit_valid=0; clocks(1);
        end
    endtask
    task expect_feedback;
        input [2:0] expected;
        input [3:0] target;
        input [127:0] text;
        begin
            if (feedback!==expected || feedback_cell!==target || view.message!==text)
                $fatal(1,"Feedback incorrect: code=%0d cell=%0d message=%s",feedback,feedback_cell,view.message);
            pixel=(4+(target/3)*16)*96+4+(target%3)*16; #1;
            if (colour!==((expected==`LP_FEEDBACK_PLACED || expected==`LP_FEEDBACK_REMOVED) ? 16'h07e0 : 16'hf800))
                $fatal(1,"Target cell outline has the wrong colour");
            pixel=(4+(((target+1)%9)/3)*16)*96+4+((target+1)%3)*16; #1;
            if (colour!==16'h7bef) $fatal(1,"Feedback outline leaked into another cell");
        end
    endtask
    task save_build;
        begin saved_grid=grid; saved_frames=frames; end
    endtask
    task unchanged;
        begin
            if (grid!==saved_grid || frames!==saved_frames)
                $fatal(1,"Rejected edit changed saved construction");
        end
    endtask
    task save_frame;
        input [255:0] filename;
        begin
            // 6,144 ns is shorter than this fixture's 10,000 ns feedback duration.
            file_handle=$fopen(filename,"w");
            if (!file_handle) $fatal(1,"Could not save OLED preview");
            for (p=0; p<6144; p=p+1) begin
                pixel=p; #1; $fdisplay(file_handle,"%h",colour);
            end
            $fclose(file_handle); clocks(1);
        end
    endtask

    initial begin
        clocks(3); reset=0; clocks(2);
        if (feedback!=`LP_FEEDBACK_NONE || view.message!="ADD PIG         " || valid)
            $fatal(1,"Blank builder did not show ADD PIG");
        build_test_vehicle();
        if (feedback!=`LP_FEEDBACK_NONE || view.message!="READY           ") $fatal(1,"Initial READY status missing");
        pixel=56*96; #1; if (colour!==16'h07e0) $fatal(1,"READY text pixel missing");
        pixel=56*96+5; #1; if (colour!==16'h0841) $fatal(1,"Character spacing missing");
        save_frame("feedback_ready.hex");
        save_build(); act(`LP_EDIT_PLACE,4,`LP_PART_FRAME); unchanged();
        if (feedback!=`LP_FEEDBACK_NONE) $fatal(1,"Already-present frame produced feedback");

        // Exact duration: the accepting clock starts a full 1,000-clock interval.
        operation=`LP_EDIT_PLACE; cell_id=0; part=`LP_PART_FRAME; edit_valid=1;
        clocks(1); edit_valid=0;
        if (feedback!=`LP_FEEDBACK_PLACED) $fatal(1,"Placement feedback missing");
        clocks(999);
        if (feedback!=`LP_FEEDBACK_PLACED) $fatal(1,"Feedback expired early");
        clocks(1);
        if (feedback!=`LP_FEEDBACK_NONE || view.message!="READY           ") $fatal(1,"Feedback did not expire to READY");

        act(`LP_EDIT_PLACE,2,`LP_PART_FRAME);
        expect_feedback(`LP_FEEDBACK_PLACED,2,"PLACED          ");
        if (frames_left!=0) $fatal(1,"Successful placement did not consume stock");
        save_frame("feedback_placed.hex");
        save_build(); act(`LP_EDIT_PLACE,1,`LP_PART_FRAME);
        expect_feedback(`LP_FEEDBACK_NO_STOCK,1,"NO STOCK        "); unchanged();
        if (!valid || frames_left!=0) $fatal(1,"Rejected edit changed overall validity or stock");
        pixel=56*96; #1; if (colour!==16'hf800) $fatal(1,"Error text is not red");
        save_frame("feedback_no_stock.hex");

        act(`LP_EDIT_PLACE,7,`LP_PART_PIG);
        expect_feedback(`LP_FEEDBACK_NEED_FRAME,7,"NEED FRAME      "); unchanged();
        save_frame("feedback_need_frame.hex");
        act(`LP_EDIT_PLACE,1,`LP_PART_WHEEL);
        expect_feedback(`LP_FEEDBACK_NO_STOCK,1,"NO STOCK        "); unchanged();
        act(`LP_EDIT_PLACE,7,`LP_PART_BALLOON);
        expect_feedback(`LP_FEEDBACK_FRAME_BELOW,7,"FRAME BELOW     "); unchanged();
        act(`LP_EDIT_PLACE,4,`LP_PART_BALLOON);
        expect_feedback(`LP_FEEDBACK_OCCUPIED,4,"CELL OCCUPIED   "); unchanged();
        act(`LP_EDIT_PLACE,6,`LP_PART_FRAME);
        expect_feedback(`LP_FEEDBACK_OCCUPIED,6,"CELL OCCUPIED   "); unchanged();
        act(`LP_EDIT_PLACE,7,`LP_PART_WHEEL);
        expect_feedback(`LP_FEEDBACK_NO_STOCK,7,"NO STOCK        "); unchanged();

        // A new action, including the same error twice, restarts the full interval.
        clocks(990); act(`LP_EDIT_PLACE,7,`LP_PART_WHEEL); clocks(20);
        if (feedback!=`LP_FEEDBACK_NO_STOCK) $fatal(1,"Repeated rejection did not restart feedback");
        act(`LP_EDIT_REMOVE,6,`LP_PART_EMPTY);
        expect_feedback(`LP_FEEDBACK_REMOVED,6,"REMOVED         ");
        if (wheels_left!=1) $fatal(1,"Removal feedback changed inventory refunds");
        save_build(); saved_count=builder.feedback_count;
        act(`LP_EDIT_REMOVE,6,`LP_PART_EMPTY); unchanged();
        if (feedback!=`LP_FEEDBACK_REMOVED || feedback_cell!=6 || builder.feedback_count<=saved_count)
            $fatal(1,"Removing an empty cell restarted feedback");
        act(`LP_EDIT_PLACE,7,`LP_PART_WHEEL);
        expect_feedback(`LP_FEEDBACK_PLACED,7,"PLACED          ");
        save_build(); saved_count=builder.feedback_count;
        act(`LP_EDIT_PLACE,7,`LP_PART_WHEEL); unchanged();
        if (builder.feedback_count<=saved_count || wheels_left!=0) $fatal(1,"Same-part drop restarted feedback or charged stock");

        // Rejection preserves the pig; a later affordable replacement refunds it.
        save_build(); act(`LP_EDIT_PLACE,4,`LP_PART_ENGINE);
        expect_feedback(`LP_FEEDBACK_NO_STOCK,4,"NO STOCK        "); unchanged();
        act(`LP_EDIT_REMOVE,5,`LP_PART_EMPTY); act(`LP_EDIT_PLACE,4,`LP_PART_ENGINE);
        expect_feedback(`LP_FEEDBACK_PLACED,4,"PLACED          ");
        clocks(1000);
        if (feedback!=`LP_FEEDBACK_NONE || valid || pigs_left!=1 || view.message!="ADD PIG         ")
            $fatal(1,"Placement did not return to missing-pig status");
        act(`LP_EDIT_PLACE,2,`LP_PART_PIG);
        if (!valid || pigs_left!=0) $fatal(1,"Pig placement did not restore validity");
        act(`LP_EDIT_REMOVE,4,`LP_PART_EMPTY); act(`LP_EDIT_REMOVE,4,`LP_PART_EMPTY);
        expect_feedback(`LP_FEEDBACK_REMOVED,4,"REMOVED         ");
        clocks(1000);
        if (valid || error!=`LP_BUILD_ERR_ATTACHMENT || view.message!="CHECK SUPPORT   ")
            $fatal(1,"Removing support did not return to attachment status");
        save_frame("feedback_support.hex");
        save_build(); act(`LP_EDIT_PLACE,7,`LP_PART_WHEEL);
        if (feedback!=`LP_FEEDBACK_NONE) $fatal(1,"Same unsupported part produced feedback");
        unchanged(); act(`LP_EDIT_PLACE,4,`LP_PART_WHEEL);
        expect_feedback(`LP_FEEDBACK_NO_STOCK,4,"NO STOCK        "); unchanged();
        act(`LP_EDIT_PLACE,4,`LP_PART_BALLOON);
        expect_feedback(`LP_FEEDBACK_FRAME_BELOW,4,"FRAME BELOW     "); unchanged();
        act(`LP_EDIT_PLACE,4,`LP_PART_FRAME);
        if (!valid) $fatal(1,"Restoring support did not repair the build");

        // Invalid protocol inputs are quiet; other modes and reset clear feedback.
        saved_count=builder.feedback_count; save_build();
        act(`LP_EDIT_PLACE,15,`LP_PART_FRAME); act(`LP_EDIT_PLACE,0,3'd7); act(2'd3,0,`LP_PART_FRAME);
        unchanged();
        if (builder.feedback_count<=saved_count) $fatal(1,"Invalid request restarted feedback");
        state=`LP_INIT_RUN; run_init=1; clocks(2);
        if (feedback!=`LP_FEEDBACK_NONE) $fatal(1,"Run initialisation retained feedback");
        run_init=0; state=`LP_RUN; act(`LP_EDIT_REMOVE,2,`LP_PART_EMPTY); unchanged();
        if (feedback!=`LP_FEEDBACK_NONE) $fatal(1,"Gameplay edit created construction feedback");
        state=`LP_BUILD; clocks(2); act(`LP_EDIT_REMOVE,2,`LP_PART_EMPTY);
        reset=1; clocks(2);
        if (feedback!=`LP_FEEDBACK_NONE || frames!==0 || grid!==0 || valid ||
            frames_left!=5 || pigs_left!=1 || view.message!="ADD PIG         ")
            $fatal(1,"Reset retained feedback or failed to clear construction");
        $display("PASS construction_feedback_tb: all edit results, outline/text pixels, exact duration, replacement, no-ops, stock/refunds, build status and mode/reset clearing");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Construction feedback test timed out"); end
endmodule
