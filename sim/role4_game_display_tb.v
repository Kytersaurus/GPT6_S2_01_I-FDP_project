// Owner: Role 4 - Marcus. Levels, game control, level button and both renderers.
`timescale 1ns / 1ps
`include "game_defs.vh"
module role4_game_display_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;

    // Level table, checked through one instance.
    reg level=0;
    wire signed [15:0] spawn_x, spawn_y;
    wire [2:0] terrain_count, tnt_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire [`LP_TNT_BITS-1:0] tnt_positions;
    wire [1:0] hazard_count;
    wire [`LP_HAZARD_BITS-1:0] hazard_rects;
    level_data levels (
        .level_index(level),.spawn_x(spawn_x),.spawn_y(spawn_y),.terrain_count(terrain_count),
        .terrain_rects(terrain_rects),.goal_rect(goal_rect),.tnt_count(tnt_count),
        .tnt_positions(tnt_positions),.hazard_count(hazard_count),.hazard_rects(hazard_rects)
    );

    // Game controller with scripted neighbours.
    reg launch=0, retry=0, edit=0, level_next=0, live=1, tick=0, world_valid=0;
    reg goal=0, hazard=0, bounds=0;
    wire world_ready, run_init, step, release_step;
    wire [2:0] state;
    wire level_index;
    wire [1:0] fail_reason;
    game_controller control (
        .clk(clk),.reset(reset),.launch_req(launch),.retry_req(retry),.edit_req(edit),
        .guide_open_req(1'b0),.guide_close_req(1'b0),.level_next_req(level_next),
        .build_valid(1'b1),.pig_alive(live),.init_ready(3'b111),.physics_tick(tick),
        .world_valid(world_valid),.world_ready(world_ready),.gameplay_pending(1'b0),.gameplay_ready(),
        .goal_hit(goal),.hazard_hit(hazard),.out_of_bounds(bounds),.game_state(state),
        .level_index(level_index),.fail_reason(fail_reason),.run_init(run_init),.step_start(step),
        .update_release(release_step),.launch_event(),.success_event(),.failure_event()
    );

    // Level button with a scripted mouse.
    reg [2:0] button_state=`LP_BUILD;
    reg [11:0] mouse_x=0, mouse_y=0;
    reg mouse_left=0, mouse_event=0;
    wire button_req;
    integer button_pulses=0;
    level_button button (
        .clk(clk),.reset(reset),.game_state(button_state),.mouse_x(mouse_x),.mouse_y(mouse_y),
        .mouse_left(mouse_left),.mouse_event(mouse_event),.level_next_req(button_req)
    );
    always @(posedge clk) if (button_req) button_pulses = button_pulses + 1;

    // Renderers with the preset build: frames in cells 3-5, pig in cell 4.
    reg [12:0] pixel=0;
    reg [2:0] view_state=`LP_BUILD;
    reg [1:0] view_reason=`LP_FAIL_NONE;
    reg [`LP_MAX_TNT-1:0] tnt_intact={`LP_MAX_TNT{1'b1}};
    reg signed [15:0] vehicle_x=16'sd1024, vehicle_y=16'sd8192;
    wire [26:0] grid = {`LP_PART_WHEEL,`LP_PART_EMPTY,`LP_PART_WHEEL,
                        `LP_PART_ENGINE,`LP_PART_PIG,`LP_PART_EMPTY,
                        `LP_PART_EMPTY,`LP_PART_EMPTY,`LP_PART_EMPTY};
    wire [15:0] left_colour, right_colour;
    left_renderer left_view (
        .pixel_index(pixel),.game_state(view_state),.build_grid(grid),.intact_mask(9'b101110000),
        .frame_intact_mask(9'b000111000),.build_valid(1'b1),.build_error(4'd0),.engine_enabled(1'b1),
        .feedback_code(`LP_FEEDBACK_NONE),.feedback_cell(4'd0),
        .frames_left(4'd2),.pigs_left(4'd0),.wheels_left(4'd0),.engines_left(4'd0),.balloons_left(4'd2),
        .selected_part(`LP_PART_FRAME),.drag_active(1'b0),.cursor_x(7'd0),.cursor_y(7'd0),.cursor_visible(1'b0),
        .level_index(level),.fail_reason(view_reason),.pixel_data(left_colour)
    );
    right_renderer right_view (
        .pixel_index(pixel),.game_state(view_state),.build_grid(grid),.intact_mask(9'b101110000),
        .frame_intact_mask(9'b000111000),.vehicle_x(vehicle_x),.vehicle_y(vehicle_y),
        .spawn_x(spawn_x),.spawn_y(spawn_y),.terrain_count(terrain_count),.terrain_rects(terrain_rects),
        .goal_rect(goal_rect),.tnt_count(tnt_count),.tnt_positions(tnt_positions),.tnt_intact(tnt_intact),
        .hazard_count(hazard_count),.hazard_rects(hazard_rects),.pixel_data(right_colour)
    );

    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    // Task arguments are copied out only at the end, so pulse the named request directly.
    localparam LAUNCH=0, RETRY=1, EDIT=2, LEVEL=3, TICK=4;
    task pulse;
        input integer which;
        begin
            case (which)
                LAUNCH: launch=1; RETRY: retry=1; EDIT: edit=1; LEVEL: level_next=1; TICK: tick=1;
            endcase
            clocks(1);
            launch=0; retry=0; edit=0; level_next=0; tick=0;
            clocks(1);
        end
    endtask
    task expect_left;
        input integer x, y;
        input [15:0] colour;
        input [8*24-1:0] what;
        begin
            pixel=y*96+x; #1;
            if (left_colour !== colour) $fatal(1,"Left %0s: (%0d,%0d)=%h, expected %h",what,x,y,left_colour,colour);
        end
    endtask
    task expect_right;
        input integer x, y;
        input [15:0] colour;
        input [8*24-1:0] what;
        begin
            pixel=y*96+x; #1;
            if (right_colour !== colour) $fatal(1,"Right %0s: (%0d,%0d)=%h, expected %h",what,x,y,right_colour,colour);
        end
    endtask
    // Launch, then answer one movement step with the given outcome flags.
    task run_one_step;
        input g, h, b, alive;
        begin
            pulse(LAUNCH); clocks(2);
            if (state !== `LP_RUN) $fatal(1,"Launch did not reach RUN");
            pulse(TICK);
            if (!world_ready) $fatal(1,"No outstanding step after a physics tick");
            goal=g; hazard=h; bounds=b; live=alive; world_valid=1; clocks(1);
            world_valid=0; goal=0; hazard=0; bounds=0; live=1; clocks(1);
        end
    endtask
    initial begin
        // Level data: the spawn rests on ground; both levels keep within the packing limits.
        level=0; #1;
        if (spawn_x !== 16'sd1024 || spawn_y !== 16'sd8192) $fatal(1,"Level 1 spawn moved");
        if (terrain_count != 2 || tnt_count != 1 || hazard_count != 0) $fatal(1,"Level 1 counts wrong");
        if (terrain_rects[31:0] !== {8'd8,8'd96,8'd56,8'd0}) $fatal(1,"Level 1 ground is not the flat baseline");
        if (goal_rect !== {8'd24,8'd16,8'd32,8'd80}) $fatal(1,"Level 1 goal moved");
        if (tnt_positions[63:16] !== 0 || hazard_rects !== 0 || terrain_rects[127:64] !== 0)
            $fatal(1,"Level 1 unused entries are not zero");
        level=1; #1;
        if (terrain_count != 4 || tnt_count != 2 || hazard_count != 1) $fatal(1,"Level 2 counts wrong");
        if (tnt_positions[15:0] !== {8'd48,8'd60}) $fatal(1,"Level 2 path TNT not on the ground");
        if (hazard_rects[31:0] !== {8'd4,8'd16,8'd58,8'd36}) $fatal(1,"Level 2 spikes moved");
        // The pit must stay narrower than the 24 pixel vehicle so it can be crossed.
        if (hazard_rects[23:16] >= 24) $fatal(1,"Level 2 pit wider than the vehicle");

        clocks(3); reset=0; clocks(2);
        // Level select: only in BUILD, and launch on the same clock wins.
        if (state !== `LP_BUILD || level_index !== 0) $fatal(1,"Reset state wrong");
        pulse(LEVEL);
        if (level_index !== 1) $fatal(1,"Level request ignored in BUILD");
        launch=1; level_next=1; clocks(1); launch=0; level_next=0; clocks(1);
        if (level_index !== 1 || state === `LP_BUILD) $fatal(1,"Level changed while launching");
        clocks(2); pulse(LEVEL);
        if (level_index !== 1) $fatal(1,"Level changed outside BUILD");

        // Fail reasons in priority order: pig, hazard, then bounds.
        pulse(TICK); live=0; hazard=1; bounds=1; world_valid=1; clocks(1);
        world_valid=0; live=1; hazard=0; bounds=0; clocks(1);
        if (state !== `LP_FAIL || fail_reason !== `LP_FAIL_PIG) $fatal(1,"Pig loss not reported first");
        pulse(RETRY); clocks(2);
        if (fail_reason !== `LP_FAIL_NONE || level_index !== 1) $fatal(1,"Retry kept old reason or changed level");
        pulse(TICK); hazard=1; bounds=1; goal=1; world_valid=1; clocks(1);
        world_valid=0; hazard=0; bounds=0; goal=0; clocks(1);
        if (state !== `LP_FAIL || fail_reason !== `LP_FAIL_HAZARD) $fatal(1,"Hazard not reported before bounds/goal");
        pulse(EDIT);
        if (state !== `LP_BUILD || fail_reason !== `LP_FAIL_NONE) $fatal(1,"Edit did not clear the result");
        run_one_step(1'b0, 1'b0, 1'b1, 1'b1);
        if (state !== `LP_FAIL || fail_reason !== `LP_FAIL_BOUNDS) $fatal(1,"Out of bounds not reported");
        pulse(EDIT); run_one_step(1'b1, 1'b0, 1'b0, 1'b1);
        if (state !== `LP_SUCCESS || fail_reason !== `LP_FAIL_NONE) $fatal(1,"Goal did not succeed cleanly");

        // Level button: one pulse per fresh press inside the button, in BUILD only.
        mouse_x=88; mouse_y=59; mouse_left=1; mouse_event=1; clocks(1); mouse_event=0; clocks(2);
        if (button_pulses != 1) $fatal(1,"Button press not detected");
        mouse_event=1; clocks(1); mouse_event=0; clocks(2);
        if (button_pulses != 1) $fatal(1,"Held button repeated");
        mouse_left=0; mouse_event=1; clocks(1); mouse_event=0; clocks(1);
        mouse_x=81; mouse_left=1; mouse_event=1; clocks(1); mouse_event=0; mouse_left=0; clocks(2);
        if (button_pulses != 1) $fatal(1,"Press beside the button counted");
        mouse_event=1; clocks(1); mouse_event=0;
        button_state=`LP_RUN; mouse_x=88; mouse_left=1; mouse_event=1; clocks(1); mouse_event=0; clocks(2);
        if (button_pulses != 1) $fatal(1,"Button worked outside BUILD");

        // Left view: level button text, then result messages.
        level=0; view_state=`LP_BUILD;
        expect_left(82, 55, 16'h7bef, "button border");
        expect_left(83, 56, 16'hffff, "button L");
        expect_left(91, 56, 16'hffff, "button 1");
        expect_left(90, 56, 16'h0010, "button 1 gap");
        level=1;
        expect_left(90, 56, 16'hffff, "button 2");
        view_state=`LP_FAIL; view_reason=`LP_FAIL_PIG;
        expect_left(0, 56, 16'hf800, "PIG LOST text");
        expect_left(83, 56, 16'h0841, "no button after run");
        view_state=`LP_SUCCESS; view_reason=`LP_FAIL_NONE;
        expect_left(0, 56, 16'h07e0, "LEVEL CLEAR text");
        view_state=`LP_RUN;
        expect_left(5, 58, 16'h07e0, "runtime valid indicator");

        // Right view, level 1: TNT parts, then hiding an exploded block.
        level=0; view_state=`LP_BUILD;
        expect_right(48, 12, 16'hffe0, "TNT fuse");
        expect_right(44, 13, 16'hf800, "TNT body");
        expect_right(44, 15, 16'hffff, "TNT band");
        expect_right(40, 22, 16'h8320, "ledge");
        tnt_intact=0;
        expect_right(44, 13, 16'h0010, "exploded TNT");
        tnt_intact={`LP_MAX_TNT{1'b1}};
        // Before launch the vehicle sits at spawn even if physics holds an old position.
        vehicle_x=40*256;
        expect_right(16, 44, 16'h07e0, "pig at spawn in BUILD");
        view_state=`LP_RUN;
        expect_right(52, 44, 16'h07e0, "pig at vehicle in RUN");
        expect_right(16, 44, 16'h0010, "no pig left at spawn");
        // Level 2: spikes, pit gap and path TNT.
        level=1; view_state=`LP_BUILD;
        expect_right(37, 58, 16'hc618, "spike tip");
        expect_right(36, 58, 16'h0010, "gap between spikes");
        expect_right(36, 60, 16'hc618, "spike base");
        expect_right(40, 63, 16'h8320, "pit floor");
        expect_right(60, 49, 16'hf800, "path TNT");
        view_state=`LP_FAIL;
        expect_right(0, 0, 16'hf800, "fail border");

        $display("PASS role4_game_display_tb: two levels, level select, fail reasons, level button, result text, TNT, hazards, spawn preview");
        $finish;
    end
    initial begin #200000; $fatal(1,"Role 4 test timed out"); end
endmodule
