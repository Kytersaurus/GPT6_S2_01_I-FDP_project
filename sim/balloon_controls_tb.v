// Owner: Role 1 - Kaushal. Gameplay mouse clicks through the connected hardware top.
`timescale 1ns / 1ps
`include "game_defs.vh"
module balloon_controls_tb;
    reg clk=0, btnD=1;
    reg [11:0] mouse_x=0, mouse_y=0;
    reg mouse_left=0, mouse_right=0, mouse_event=0;
    reg start=0, edit=0, tick=0, world_result=0, goal=0, hazard=0;
    tri1 PS2Clk, PS2Data;
    wire [15:0] led;
    wire [7:0] JA, JB;
    reg [12:0] pixel=0;
    wire [15:0] colour;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames;
    integer cycles, applications=0, previous_applications;
    always #5 clk=~clk;

    My_Top_Module #(.BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2), .WHEEL_LIMIT(2)) dut (
        .clk(clk), .btnC(1'b0), .btnU(1'b0), .btnR(1'b0), .btnL(1'b0),.btnD(btnD), .sw(16'd0),
        .PS2Clk(PS2Clk), .PS2Data(PS2Data), .led(led), .JA(JA), .JB(JB)
    );
    // Check renderer pixels directly without waiting for an entire OLED frame.
    left_renderer view (
        .build_facing_left(9'd0), .selected_left(1'b0), .inventory_page(1'b0), .rockets_left(4'd1), .fans_left(4'd1),
        .pixel_index(pixel), .game_state(dut.game_state), .build_grid(dut.build_grid), .build_frames(dut.build_frames),
        .run_seconds(8'd0), .anim_phase(1'b0), .level_index(dut.level_index), .fail_reason(dut.fail_reason), .boost_active(1'b0),
        .intact_mask(dut.intact_mask), .frame_intact_mask(dut.frame_intact_mask),
        .build_valid(dut.build_valid), .build_error(dut.build_error), .engine_enabled(1'b0),
        .feedback_code(dut.feedback_code), .feedback_cell(dut.feedback_cell),
        .frames_left(dut.frames_left), .pigs_left(dut.pigs_left), .wheels_left(dut.wheels_left),
        .engines_left(dut.engines_left), .balloons_left(dut.balloons_left),
        .selected_part(dut.selected_part), .cursor_x(dut.cursor_x), .cursor_y(dut.cursor_y),
        .drag_active(dut.drag_active),.drag_from_grid(dut.drag_from_grid),.drag_source(dut.drag_source),.drag_contents(dut.drag_contents),
        .cursor_visible(1'b1), .pixel_data(colour)
    );
    // Supply completed mouse packets, button pulses and delayed world results.
    // Physics, collision, builder and all new control connections remain real.
    initial begin
        force dut.mouse_x=mouse_x;
        force dut.mouse_y=mouse_y;
        force dut.mouse_left=mouse_left;
        force dut.mouse_right=mouse_right;
        force dut.mouse_event=mouse_event;
        force dut.start_press=start;
        force dut.edit_press=edit;
        force dut.physics_tick=tick;
        force dut.world_valid=world_result;
        force dut.goal_hit=goal;
        force dut.hazard_hit=hazard;
        force dut.out_of_bounds=1'b0;
    end
    always @(posedge clk) begin
        if (!dut.reset && dut.pop_valid) begin
            if (!dut.damage_ready || dut.world_ready || dut.step_start)
                $fatal(1,"Pop overlapped an update or unavailable builder");
            if (dut.pop_mask==0) $fatal(1,"Repeated/empty balloon pop");
            applications=applications+1;
        end
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
    task wait_run;
        begin
            cycles=0;
            while (dut.game_state!=`LP_RUN && cycles<20) begin clocks(1); cycles=cycles+1; end
            if (dut.game_state!=`LP_RUN) $fatal(1,"Launch/retry did not enter RUN");
            clocks(2);
        end
    endtask
    task launch_or_retry;
        begin start=1; clocks(1); start=0; wait_run(); left_click(48,59); end
    endtask
    task begin_update;
        begin
            tick=1; clocks(1); tick=0; clocks(1);
            if (!dut.world_ready) $fatal(1,"Movement update did not start");
        end
    endtask
    task wait_movement;
        begin
            cycles=0;
            while (!dut.movement_committed && cycles<100000) begin clocks(1); cycles=cycles+1; end
            if (!dut.movement_committed) $fatal(1,"Movement did not commit");
        end
    endtask
    task finish_world;
        input won,failed;
        begin
            goal=won; hazard=failed; world_result=1; clocks(1);
            world_result=0; goal=0; hazard=0;
        end
    endtask
    task complete_and_retry;
        begin
            begin_update(); wait_movement(); finish_world(1,0); clocks(2);
            if (dut.game_state!=`LP_SUCCESS) $fatal(1,"Expected success before retry");
            launch_or_retry();
            if (dut.balloon_count!=2 || dut.mass_units!=15 || dut.pop_pending)
                $fatal(1,"Retry did not restore both balloons or clear queued clicks");
        end
    endtask

    initial begin
        clocks(20); btnD=0; clocks(280); build_test_vehicle();
        // Exercise the real top-level preview bus across the OLED clock boundary.
        // Supply frame boundaries early, while the physical driver is still starting.
        force dut.left_frame=1'b1;
        force dut.left_pixel_index=pixel;
        packet(74,8,1,0); packet(12,12,1,0); clocks(400);
        if (!dut.draw_drag_active || dut.draw_cursor_x!=12 || dut.draw_cursor_y!=12 ||
            dut.draw_selected_part!=`LP_PART_FRAME)
            $fatal(1,"Preview state/cursor/selection did not cross the display snapshot");
        pixel=6143-(8*96+8); #1;
        if (dut.left_pixel_data!==16'ha285) $fatal(1,"Rotated JA renderer lost dragged frame");
        pixel=6143-(12*96+12); #1;
        if (dut.left_pixel_data!==16'hffff) $fatal(1,"Rotated JA cursor no longer aligns with mouse coordinates");
        packet(54,55,0,0); clocks(400);
        pixel=6143-(8*96+8); #1;
        if (dut.draw_drag_active || dut.left_pixel_data!==16'h0841 || dut.frames_left!=2)
            $fatal(1,"Cancelled preview persisted through the display snapshot");
        // A rejected drop must carry its reason and target through the same snapshot.
        left_click(74,18); left_click(12,12); clocks(400);
        if (dut.draw_feedback_code!=`LP_FEEDBACK_NEED_FRAME || dut.draw_feedback_cell!=0)
            $fatal(1,"Rejected placement feedback was lost in the display snapshot");
        pixel=6143-(4*96+4); #1;
        if (dut.left_pixel_data!==16'hf800 || dut.build_grid[2:0]!=`LP_PART_EMPTY || dut.pigs_left!=0)
            $fatal(1,"Connected feedback outline or rejected placement changed the build");
        release dut.left_frame;
        release dut.left_pixel_index;
        left_click(74,48); left_click(12,12); left_click(28,12);
        if (!dut.build_valid || dut.balloon_count!=2 || dut.balloons_left!=0 || dut.mass_units!=15)
            $fatal(1,"Could not construct two test balloons");
        saved_grid=dut.build_grid; saved_frames=dut.build_frames;

        // A construction drag held across launch must not turn into a pop.
        packet(12,12,1,0); start=1;clocks(1);start=0;wait_run(); packet(48,10,1,0); packet(48,10,0,0);
        if (dut.balloon_count!=2 || dut.pop_pending) $fatal(1,"Held launch click popped a balloon");
        left_click(48,59);
        left_click(48,26); left_click(64,26); left_click(32,26); left_click(64,10);
        left_click(74,48); left_click(90,46); left_click(4,48); left_click(4095,4095);
        packet(32,10,0,1); packet(32,10,0,0);
        packet(32,10,1,1); packet(32,10,1,0); packet(32,10,0,0);
        packet(90,46,1,0); packet(32,10,1,0); packet(32,10,0,0);
        if (dut.balloon_count!=2 || dut.pop_pending || applications!=0)
            $fatal(1,"Non-balloon, outside, right or held clicks caused a pop");

        // RUN cell0 centre is (32,10); cell1 centre is (48,10).
        // A fresh press pops once; dragging while held cannot pop another cell.
        packet(32,10,1,0);
        if (dut.balloon_count!=1 || dut.mass_units!=14 || dut.intact_mask[0] || !dut.intact_mask[1] || dut.balloons_left!=0)
            $fatal(1,"Idle click did not pop one balloon without refund");
        pixel=10*96+32; #1; if (colour!=16'hffff) $fatal(1,"RUN cursor missing");
        pixel=14*96+8; #1; if (colour!=16'h0841) $fatal(1,"Popped balloon still drawn");
        pixel=14*96+20; #1; if (colour!=16'hf81f) $fatal(1,"Other balloon disappeared");
        clocks(1); previous_applications=applications;
        packet(48,10,1,0); packet(48,10,1,0); packet(48,10,0,0); left_click(32,10);
        if (dut.balloon_count!=1 || applications!=previous_applications || dut.pop_pending)
            $fatal(1,"Held or already-popped balloon click repeated");
        if (dut.build_grid!==saved_grid || dut.build_frames!==saved_frames || dut.frame_intact_mask!==saved_frames)
            $fatal(1,"Popping changed saved construction or frames");
        complete_and_retry();

        // Hold the world result while both balloons are clicked. Properties and
        // the current physics sample must stay unchanged until world completion.
        begin_update(); wait_movement();
        packet(32,10,1,0); packet(48,10,1,0); packet(48,10,0,0);
        if (!dut.pop_pending || dut.u_balloons.pending_mask!=9'b000000001)
            $fatal(1,"Held drag queued more than the pressed balloon");
        left_click(48,10); left_click(32,10); tick=1; clocks(4);
        if (dut.balloon_count!=2 || dut.mass_units!=15 || dut.u_physics.sampled_balloons!=2 || dut.pop_valid)
            $fatal(1,"Queued pop changed an active movement update");
        previous_applications=applications;
        finish_world(0,0);
        if (!dut.update_release || dut.balloon_count!=2 || !dut.pop_valid)
            $fatal(1,"Pop was not reserved for after world completion");
        clocks(1);
        if (dut.balloon_count!=0 || dut.mass_units!=13 || dut.step_start || dut.pop_pending ||
            applications!=previous_applications+1 || dut.balloons_left!=0)
            $fatal(1,"Queued balloons did not pop together before the next update");
        clocks(2); tick=0;
        if (dut.u_physics.sampled_balloons!=0 || dut.u_physics.step_mass!=13)
            $fatal(1,"Following physics step did not sample the reduced lift/mass");
        wait_movement(); finish_world(0,0); clocks(2);
        complete_and_retry();

        // A request reaching the queue on the step-start edge belongs after that
        // update, not halfway through its property sampling.
        packet(32,10,0,0);
        mouse_left=1; mouse_event=1; clocks(1); mouse_event=0; tick=1; clocks(1); tick=0;
        if (!dut.step_start || !dut.pop_pending || dut.pop_valid || dut.balloon_count!=2)
            $fatal(1,"Simultaneous step/pop was not deferred");
        clocks(1);
        if (dut.u_physics.sampled_balloons!=2) $fatal(1,"Step/pop edge changed sampled properties");
        wait_movement(); finish_world(0,0); clocks(2); packet(32,10,0,0);
        if (dut.balloon_count!=1 || dut.pop_pending) $fatal(1,"Deferred boundary pop was lost");
        complete_and_retry();

        // A click on the world-completion edge still has priority over a new
        // physics tick once it reaches the pending queue.
        begin_update(); wait_movement();
        mouse_x=32; mouse_y=10; mouse_left=1; mouse_event=1; world_result=1;
        clocks(1); mouse_event=0; world_result=0; tick=1;
        clocks(1); tick=0;
        if (!dut.step_start || !dut.pop_pending || dut.balloon_count!=2)
            $fatal(1,"World-completion click was lost or changed the next step");
        clocks(1); wait_movement(); finish_world(0,0); clocks(2); packet(32,10,0,0);
        if (dut.balloon_count!=1) $fatal(1,"World-completion click never applied");
        complete_and_retry();

        // Result states discard queued clicks; retry cannot replay them.
        begin_update(); wait_movement(); left_click(32,10); finish_world(1,0); clocks(2);
        if (dut.game_state!=`LP_SUCCESS || dut.pop_pending || dut.balloon_count!=2)
            $fatal(1,"Success applied or retained a queued pop");
        left_click(48,10); launch_or_retry(); clocks(3);
        if (dut.balloon_count!=2 || dut.pop_pending) $fatal(1,"Result click leaked into retry");
        begin_update(); wait_movement(); left_click(48,10); finish_world(0,1); clocks(2);
        if (dut.game_state!=`LP_FAIL || dut.pop_pending || dut.balloon_count!=2)
            $fatal(1,"Failure applied or retained a queued pop");
        launch_or_retry(); left_click(32,10);
        begin_update(); wait_movement(); finish_world(1,0); clocks(2);
        edit=1; clocks(1); edit=0; clocks(2);
        if (dut.game_state!=`LP_BUILD || dut.balloon_count!=2 || dut.balloons_left!=0)
            $fatal(1,"Return to construction did not restore popped balloons");

        // Reset while a click is waiting also discards it and clears construction.
        launch_or_retry(); begin_update(); wait_movement(); left_click(48,10);
        btnD=1; clocks(10); btnD=0; clocks(20);
        if (dut.game_state!=`LP_BUILD || dut.pop_pending || dut.balloon_count!=0 ||
            dut.balloons_left!=2 || dut.build_grid!==0 || dut.build_frames!==0 ||
            dut.frames_left!=5 || dut.pigs_left!=1 || dut.wheels_left!=2 || dut.engines_left!=1)
            $fatal(1,"Reset retained a pop or failed to restore the blank builder/full inventory");
        if (dut.build_grid===saved_grid) $fatal(1,"Reset retained edited construction");
        $display("PASS balloon_controls_tb: fresh clicks, held/invalid input, RUN cursor, queued pops, step/world boundaries, counts/mass, inventory, retry, results and reset");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Balloon controls test timed out"); end
endmodule
