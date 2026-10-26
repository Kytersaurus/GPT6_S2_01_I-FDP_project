// Owner: Role 1 - Kaushal. Mouse packets through editing, inventory and OLED feedback.
`timescale 1ns / 1ps
`include "game_defs.vh"
module construction_controls_tb;
    reg clk=0, reset=1, run_init=0;
    reg [2:0] game_state=`LP_BUILD;
    reg [11:0] mouse_x=0, mouse_y=0;
    reg mouse_left=0, mouse_right=0, mouse_event=0;
    wire [11:0] mouse_value;
    wire setx, sety, setmax_x, setmax_y, edit_valid, drag_active;
    wire [6:0] cursor_x, cursor_y;
    wire [2:0] selected, edit_part;
    wire [1:0] edit_op;
    wire [3:0] edit_cell, edit_source, drag_source;
    wire drag_from_grid;
    wire [2:0] drag_contents;
    reg [11:0] configured_max_x=0, configured_max_y=0, configured_x=0, configured_y=0;
    wire [26:0] grid;
    wire [8:0] frames, intact, frame_intact;
    reg damage_valid=0;
    reg [8:0] damage_mask=0;
    wire valid, pig_alive, init_ready;
    wire [3:0] error, wheels, engines, balloons, frames_left, pigs_left, wheels_left, engines_left, balloons_left;
    wire [7:0] mass;
    wire [2:0] feedback_code;
    wire [3:0] feedback_cell;
    reg [12:0] pixel=0;
    wire [15:0] colour;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames;
    reg previous_edit=0;
    integer edit_count=0, saved_edit_count=0;
    wire low_stock_valid;
    wire [3:0] low_stock_error, low_stock_frames_left;
    reg launch=0;
    wire [2:0] guarded_state;
    always #5 clk=~clk;

    mouse_adapter input_actions (
        .build_facing_left(9'd0), .run_page(2'd1),
        .input_enabled(1'b1),.build_grid(grid),.build_frames(frames),
        .clk(clk),.reset(reset),.game_state(game_state),.mouse_x(mouse_x),.mouse_y(mouse_y),
        .mouse_left(mouse_left),.mouse_right(mouse_right),.mouse_event(mouse_event),
        .mouse_value(mouse_value),.setx(setx),.sety(sety),.setmax_x(setmax_x),.setmax_y(setmax_y),
        .cursor_x(cursor_x),.cursor_y(cursor_y),.selected_part(selected),
        .drag_active(drag_active),.drag_from_grid(drag_from_grid),.drag_source(drag_source),.drag_contents(drag_contents),
        .edit_valid(edit_valid),.edit_op(edit_op),.edit_cell(edit_cell),.edit_source(edit_source),.edit_part(edit_part)
    );
    vehicle_builder builder (
        .edit_facing_left(1'b0),
        .clk(clk),.reset(reset),.game_state(game_state),.run_init(run_init),.init_ready(init_ready),
        .edit_valid(edit_valid),.edit_op(edit_op),.edit_cell(edit_cell),.edit_source(edit_source),.edit_part(edit_part),
        .damage_valid(damage_valid),.damage_ready(),.damage_mask(damage_mask),.damage_frame_mask(9'd0),
        .build_grid(grid),.build_frames(frames),.intact_mask(intact),.frame_intact_mask(frame_intact),
        .build_valid(valid),.build_error(error),.pig_alive(pig_alive),.wheel_count(wheels),
        .feedback_code(feedback_code),.feedback_cell(feedback_cell),
        .engine_count(engines),.balloon_count(balloons),.mass_units(mass),
        .frames_left(frames_left),.pigs_left(pigs_left),.wheels_left(wheels_left),
        .engines_left(engines_left),.balloons_left(balloons_left)
    );
    // A smaller configured inventory must also start empty without wrapping stock.
    vehicle_builder #(.FRAME_LIMIT(2)) low_stock (
        .edit_facing_left(1'b0),
        .clk(clk),.reset(reset),.game_state(`LP_BUILD),.run_init(1'b0),.init_ready(),
        .edit_valid(1'b0),.edit_op(`LP_EDIT_PLACE),.edit_cell(4'd0),.edit_source(4'd15),.edit_part(`LP_PART_EMPTY),
        .damage_valid(1'b0),.damage_ready(),.damage_mask(9'd0),.damage_frame_mask(9'd0),
        .build_valid(low_stock_valid),.build_error(low_stock_error),.frames_left(low_stock_frames_left)
    );
    left_renderer view (
        .build_facing_left(9'd0), .selected_left(1'b0), .inventory_page(1'b0), .rockets_left(4'd1), .fans_left(4'd1),
        .pixel_index(pixel),.game_state(game_state),.build_grid(grid),.intact_mask(intact),
        .frame_intact_mask(frame_intact),.build_valid(valid),.build_error(error),.engine_enabled(1'b1),
        .feedback_code(feedback_code),.feedback_cell(feedback_cell),
        .frames_left(frames_left),.pigs_left(pigs_left),.wheels_left(wheels_left),
        .engines_left(engines_left),.balloons_left(balloons_left),.selected_part(selected),
        .drag_active(drag_active),.drag_from_grid(drag_from_grid),.drag_source(drag_source),.drag_contents(drag_contents),
        .cursor_x(cursor_x),.cursor_y(cursor_y),.cursor_visible(1'b1),.pixel_data(colour)
    );
    game_controller launch_guard (
        .clk(clk),.reset(reset),.launch_req(launch),.retry_req(1'b0),.edit_req(1'b0),
        .guide_open_req(1'b0),.guide_close_req(1'b0),.level_next_req(1'b0),.build_valid(valid && !edit_valid),.pig_alive(pig_alive),
        .init_ready(3'd0),.physics_tick(1'b0),.world_valid(1'b0),.world_ready(),
        .gameplay_pending(1'b0),.gameplay_ready(),
        .goal_hit(1'b0),.hazard_hit(1'b0),.out_of_bounds(1'b0),.game_state(guarded_state),
        .run_init(),.step_start(),.update_release(),.launch_event(),.success_event(),.failure_event()
    );
    always @(posedge clk) begin
        if (reset) edit_count <= 0;
        else if (edit_valid) edit_count <= edit_count + 1;
        if (!reset) begin
            if (setmax_x) configured_max_x<=mouse_value;
            if (setmax_y) configured_max_y<=mouse_value;
            if (setx) configured_x<=mouse_value;
            if (sety) configured_y<=mouse_value;
        end
    end
    always @(negedge clk) begin
        if (reset) previous_edit=0;
        else begin
            if (edit_valid && previous_edit) $fatal(1,"Mouse edit lasted more than one clock");
            previous_edit=edit_valid;
        end
    end
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
    task packet;
        input [11:0] x,y;
        input left_button,right_button;
        begin
            mouse_x=x; mouse_y=y; mouse_left=left_button; mouse_right=right_button;
            mouse_event=1; clocks(1); mouse_event=0; clocks(2);
        end
    endtask
    task left_click;
        input [11:0] x,y;
        begin packet(x,y,0,0); packet(x,y,1,0); packet(x,y,0,0); end
    endtask
    task right_click;
        input [11:0] x,y;
        begin packet(x,y,0,0); packet(x,y,0,1); packet(x,y,0,0); end
    endtask
    task expect_pixel;
        input integer x,y;
        input [15:0] expected;
        begin
            pixel=y*96+x; #1;
            if (colour!==expected)
                $fatal(1,"Pixel (%0d,%0d): expected %h, got %h",x,y,expected,colour);
        end
    endtask

    initial begin
        clocks(4); reset=0; clocks(6);
        if (configured_max_x!=95 || configured_max_y!=63 || configured_x!=24 || configured_y!=24)
            $fatal(1,"Mouse OLED bounds/start position not configured");
        if (grid!==0 || frames!==0 || valid || frames_left!=5 || pigs_left!=1 ||
            wheels_left!=2 || engines_left!=1 || balloons_left!=2)
            $fatal(1,"Blank startup inventory accounting incorrect");
        build_test_vehicle();
        if (low_stock_valid || low_stock_error!=`LP_BUILD_ERR_PIG || low_stock_frames_left!=2)
            $fatal(1,"Empty smaller inventory or missing-pig status incorrect");
        pixel=5*96+84; #1; if (colour!=16'hffff) $fatal(1,"Available stock digit missing");
        pixel=35*96+84; #1; if (colour!=16'hf800) $fatal(1,"Zero stock not shown red");
        pixel=4*96+56; #1; if (colour!=16'hffe0) $fatal(1,"Selected row not highlighted");
        pixel=24*96+24; #1; if (colour!=16'hffff) $fatal(1,"Mouse cursor missing");
        clocks(1);

        // Each part follows the cursor as a preview, without consuming any stock.
        saved_grid=grid; saved_frames=frames;
        packet(74,8,1,0); packet(12,12,1,0);
        if (!drag_active) $fatal(1,"Held construction drag has no preview");
        expect_pixel(8,8,16'ha285); expect_pixel(10,9,16'h0841);
        expect_pixel(12,12,16'hffff);
        packet(28,12,1,0);
        expect_pixel(24,8,16'ha285); expect_pixel(8,8,16'h0841);
        packet(54,55,0,0);
        if (drag_active) $fatal(1,"Outside release left the preview active");
        expect_pixel(24,8,16'h0841);
        packet(74,18,1,0); packet(12,12,1,0);
        expect_pixel(10,10,16'h07e0); expect_pixel(10,11,16'h0000);
        packet(54,55,0,0);
        packet(74,28,1,0); packet(12,12,1,0);
        expect_pixel(10,10,16'hffff); expect_pixel(8,8,16'h0841);
        packet(54,55,0,0);
        packet(74,38,1,0); packet(12,12,1,0);
        expect_pixel(10,11,16'hc618); expect_pixel(13,11,16'h0000); expect_pixel(10,9,16'h5ae9);
        packet(54,55,0,0);
        packet(74,48,1,0); packet(12,12,1,0);
        expect_pixel(10,8,16'hf81f); expect_pixel(12,15,16'hffff);
        // Clamp the whole preview at the screen edge, without wrapping coordinates.
        packet(4095,4095,1,0);
        expect_pixel(90,56,16'hf81f); expect_pixel(91,62,16'hffff);
        expect_pixel(95,63,16'hffff); expect_pixel(16,15,16'h0841);
        packet(0,0,1,0); expect_pixel(5,3,16'hf81f);
        packet(54,55,0,0);
        if (drag_active || grid!==saved_grid || frames!==saved_frames || edit_count!=0 ||
            frames_left!=2 || pigs_left!=0 || wheels_left!=0 || engines_left!=0 || balloons_left!=2)
            $fatal(1,"Preview/cancel changed construction or inventory");

        left_click(74,28); left_click(28,44);
        if (selected!=`LP_PART_WHEEL || grid[23:21]!=`LP_PART_EMPTY || wheels_left!=0)
            $fatal(1,"Out-of-stock wheel accepted");
        left_click(74,38); left_click(44,28);
        if (engines_left!=0 || engines!=1) $fatal(1,"Same engine placement charged twice");
        saved_grid=grid; left_click(28,28);
        if (grid!==saved_grid || pigs_left!=0) $fatal(1,"Unaffordable replacement lost the pig");

        packet(74,8,1,0); packet(12,12,1,0); packet(12,12,1,0);
        if (frames[0]) $fatal(1,"Held selection click painted the grid");
        packet(12,12,0,0);
        if (!frames[0] || frames_left!=1) $fatal(1,"Inventory drag did not place on release");
        left_click(12,12); left_click(44,12);
        if (!frames[0] || !frames[2] || frames_left!=0) $fatal(1,"Frame placement accounting failed");
        left_click(28,12);
        if (frames[1] || frames_left!=0) $fatal(1,"Excess frame accepted");
        right_click(12,12);
        if (frames[0] || frames_left!=1) $fatal(1,"Frame removal did not refund stock");
        right_click(28,28);
        if (!frames[4] || pigs_left!=1 || frames_left!=1 || valid)
            $fatal(1,"Removing contents refunded frame or retained validity");
        left_click(74,18); left_click(12,28);
        if (!valid || grid[11:9]!=`LP_PART_PIG || pigs_left!=0) $fatal(1,"Pig did not move into another frame");
        right_click(44,28);
        if (!frames[5] || engines_left!=1) $fatal(1,"Engine removal lost its frame or refund");
        left_click(74,38); left_click(12,28);
        if (grid[11:9]!=`LP_PART_ENGINE || engines_left!=0 || pigs_left!=1)
            $fatal(1,"Replacement did not refund old contents");
        left_click(74,18); left_click(44,12);
        if (!valid || pigs_left!=0) $fatal(1,"Refunded pig could not be reused");
        saved_grid=grid; saved_frames=frames;
        left_click(52,12); right_click(0,0); left_click(92,48); left_click(74,54);
        if (grid!==saved_grid || frames!==saved_frames || selected!=`LP_PART_PIG)
            $fatal(1,"Out-of-bounds click edited grid or selected a row");
        packet(200,90,0,0);
        if (cursor_x!=95 || cursor_y!=63) $fatal(1,"Cursor did not clamp at screen edge");

        // Drag across several cells: change nothing until release, then place once.
        reset=1; clocks(3); reset=0; clocks(6); build_test_vehicle();
        saved_frames=frames; saved_grid=grid; saved_edit_count=edit_count;
        packet(74,8,1,0); packet(12,12,1,0); packet(28,12,1,0);
        if (frames!==saved_frames || grid!==saved_grid || frames_left!=2 || edit_count!=saved_edit_count)
            $fatal(1,"Dragging placed parts or charged stock before release");
        packet(44,12,0,0);
        if (drag_active || frames!==(saved_frames | 9'b000000100) || frames_left!=1 || edit_count!=saved_edit_count+1)
            $fatal(1,"Drop did not use the final release cell exactly once");
        packet(44,12,0,0); packet(12,12,0,0);
        if (frames_left!=1 || edit_count!=saved_edit_count+1) $fatal(1,"Released mouse repeated a drop");

        // Outside drops and presses that began outside the controls do nothing.
        saved_frames=frames; saved_edit_count=edit_count;
        packet(74,8,1,0); packet(12,12,1,0); packet(52,12,0,0); packet(12,12,0,0);
        packet(54,12,1,0); packet(12,12,1,0); packet(12,12,0,0);
        if (frames!==saved_frames || frames_left!=1 || edit_count!=saved_edit_count)
            $fatal(1,"Outside/cancelled drag edited the grid");

        // Invalid attachments and unavailable stock still reject a dropped part.
        saved_grid=grid;
        packet(74,48,1,0); packet(28,44,0,0);
        packet(74,28,1,0); packet(28,44,0,0);
        if (drag_active || grid!==saved_grid || balloons_left!=2 || wheels_left!=0)
            $fatal(1,"Drop bypassed attachment or inventory checks");

        // Right-click cancels a pending drop; holding it cannot also remove the frame.
        packet(74,48,1,0); packet(12,12,1,0); packet(12,12,1,1); packet(12,12,0,0);
        if (drag_active || grid!==saved_grid || balloons_left!=2) $fatal(1,"Right-click did not cancel a drag");
        packet(44,28,1,1); packet(44,28,1,1); packet(44,28,0,0);
        if (grid[17:15]!=`LP_PART_EMPTY || !frames[5] || engines_left!=1)
            $fatal(1,"Simultaneous/held buttons repeated removal or placed contents");

        // A drag cannot survive leaving BUILD, even without a packet in between.
        saved_grid=grid; saved_edit_count=edit_count;
        packet(74,48,1,0); packet(12,12,1,0);
        game_state=`LP_RUN; clocks(2);
        if (drag_active) $fatal(1,"Preview survived leaving construction");
        game_state=`LP_BUILD; clocks(2);
        packet(12,12,0,0);
        game_state=`LP_RUN; packet(74,48,1,0); game_state=`LP_BUILD;
        packet(12,12,0,0);
        if (grid!==saved_grid || balloons_left!=2 || edit_count!=saved_edit_count)
            $fatal(1,"Gameplay mouse input or stale drag edited construction");

        // Crossing inventory rows while held must keep the originally selected part.
        packet(74,48,1,0); packet(74,38,1,0); packet(12,12,0,0);
        if (selected!=`LP_PART_BALLOON || grid[2:0]!=`LP_PART_BALLOON || balloons_left!=1)
            $fatal(1,"Drag changed selection or lost a valid balloon drop");
        // Once frame stock is exhausted, another drop must leave the build unchanged.
        packet(74,8,1,0); packet(28,12,0,0);
        saved_frames=frames; saved_grid=grid;
        packet(74,8,1,0); packet(28,44,0,0);
        if (frames_left!=0 || frames!==saved_frames || grid!==saved_grid)
            $fatal(1,"Out-of-stock frame drop changed the build");

        // Reset cancels a drag as well as restoring the initial inventory.
        packet(74,8,1,0); packet(12,12,1,0);
        reset=1; clocks(3); reset=0; clocks(6); packet(12,12,0,0);
        if (drag_active || grid!==0 || frames!==0 || frames_left!=5 || pigs_left!=1 ||
            wheels_left!=2 || engines_left!=1 || balloons_left!=2 || edit_count!=0)
            $fatal(1,"Reset left a drag or failed to restore empty construction/full stock");
        build_test_vehicle();
        left_click(74,48); left_click(12,12); left_click(28,12);
        saved_grid=grid; left_click(44,12);
        if (balloons_left!=0 || balloons!=2 || grid!==saved_grid) $fatal(1,"Balloon limit exceeded");
        left_click(12,12);
        if (balloons_left!=0 || balloons!=2) $fatal(1,"Same balloon charged twice");
        right_click(28,12); left_click(44,12);
        if (balloons_left!=0 || grid[8:6]!=`LP_PART_BALLOON) $fatal(1,"Balloon refund/reuse failed");
        game_state=`LP_RUN; right_click(12,12);
        if (!intact[0]) $fatal(1,"Mouse edited construction during gameplay");
        damage_mask=9'b000000001; damage_valid=1; clocks(1); damage_valid=0; clocks(1);
        if (balloons!=1 || balloons_left!=0) $fatal(1,"Damage refunded construction stock");
        game_state=`LP_INIT_RUN; run_init=1; clocks(2);
        if (!init_ready || balloons!=2 || balloons_left!=0) $fatal(1,"Retry changed stock or lost balloon");
        run_init=0; game_state=`LP_BUILD; clocks(2); right_click(12,12);
        if (balloons_left!=1) $fatal(1,"Post-retry edit did not refund stock");
        // Apply removal of the pig on the same clock as a launch request.
        packet(28,28,0,0); mouse_right=1; mouse_event=1; clocks(1);
        mouse_event=0; launch=1; clocks(1); launch=0; clocks(2);
        if (valid || guarded_state!=`LP_BUILD) $fatal(1,"Concurrent edit launched using old build validity");

        // A left-button drop must also block launch on the edit-acceptance edge.
        reset=1; clocks(3); reset=0; clocks(6); build_test_vehicle();
        right_click(44,28); packet(74,38,1,0);
        mouse_x=28; mouse_y=28; mouse_left=0; mouse_event=1; clocks(1);
        mouse_event=0; launch=1; clocks(1); launch=0; clocks(2);
        if (grid[14:12]!=`LP_PART_ENGINE || valid || guarded_state!=`LP_BUILD)
            $fatal(1,"Concurrent drop launched using old build validity");
        $display("PASS construction_controls_tb: moving part previews, edge clamping, clicks/drag-and-drop, cancellation, stock limits, refunds, replacement, damage, retry and launch protection");
        $finish;
    end
    initial begin #30000; $fatal(1,"Construction controls test timed out"); end
endmodule
