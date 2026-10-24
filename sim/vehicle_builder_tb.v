// Owner: Role 1 - Kaushal. Frames, contents, attachment rules and retry.
`timescale 1ns / 1ps
`include "game_defs.vh"
module vehicle_builder_tb;
    reg clk = 0, reset = 1, run_init = 0;
    reg [2:0] game_state = `LP_BUILD;
    reg edit_valid = 0, damage_valid = 0;
    reg [1:0] edit_op = `LP_EDIT_PLACE;
    reg [3:0] edit_cell = 0;
    reg [2:0] edit_part = `LP_PART_FRAME;
    reg [8:0] damage_mask = 0, damage_frame_mask = 0;
    wire init_ready, damage_ready, build_valid, pig_alive;
    wire [26:0] build_grid;
    wire [8:0] build_frames, intact_mask, frame_intact_mask;
    wire [3:0] build_error, wheels, engines, balloons;
    wire [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left;
    wire [7:0] mass;
    reg [26:0] saved_grid;
    reg [8:0] saved_frames, saved_intact, saved_frame_intact;
    reg [12:0] pixel = 0;
    wire [15:0] colour;
    integer cell_number;
    always #5 clk = ~clk;

    // Larger test-only stocks exercise all cells and the two-digit display.
    vehicle_builder #(.FRAME_LIMIT(9), .PIG_LIMIT(2), .WHEEL_LIMIT(3), .ENGINE_LIMIT(9)) dut (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready),
        .edit_valid(edit_valid), .edit_op(edit_op), .edit_cell(edit_cell),.edit_source(4'd15), .edit_part(edit_part),
        .damage_valid(damage_valid), .damage_ready(damage_ready), .damage_mask(damage_mask),
        .damage_frame_mask(damage_frame_mask), .build_grid(build_grid), .build_frames(build_frames),
        .intact_mask(intact_mask), .frame_intact_mask(frame_intact_mask),
        .build_valid(build_valid), .build_error(build_error), .pig_alive(pig_alive),
        .wheel_count(wheels), .engine_count(engines), .balloon_count(balloons), .mass_units(mass),
        .frames_left(frames_left), .pigs_left(pigs_left), .wheels_left(wheels_left),
        .engines_left(engines_left), .balloons_left(balloons_left)
    );
    left_renderer view (
        .pixel_index(pixel), .game_state(game_state), .build_grid(build_grid),
        .intact_mask(intact_mask), .frame_intact_mask(frame_intact_mask),
        .build_valid(build_valid), .build_error(build_error), .engine_enabled(1'b1),
        .feedback_code(`LP_FEEDBACK_NONE), .feedback_cell(4'd0),
        .frames_left(frames_left), .pigs_left(pigs_left), .wheels_left(wheels_left),
        .engines_left(engines_left), .balloons_left(balloons_left), .selected_part(`LP_PART_FRAME),
        .drag_active(1'b0),.drag_from_grid(1'b0),.drag_source(4'd9),.drag_contents(3'd0),
        .cursor_x(7'd0), .cursor_y(7'd0), .cursor_visible(1'b0), .pixel_data(colour)
    );
    // Test-only gameplay fixture; the hardware builder starts empty.
    task build_test_vehicle;
        begin
            dut.build_grid = {
                `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
                `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
            };
            dut.build_frames = 9'b000111000;
            clocks(2);
        end
    endtask
    task clocks;
        input integer count;
        begin repeat (count) @(negedge clk); end
    endtask
    task edit;
        input [1:0] operation;
        input [3:0] cell_id;
        input [2:0] part_id;
        begin
            edit_op = operation; edit_cell = cell_id; edit_part = part_id;
            edit_valid = 1; clocks(1); edit_valid = 0; clocks(1);
        end
    endtask
    task save_build;
        begin
            saved_grid = build_grid; saved_frames = build_frames;
            saved_intact = intact_mask; saved_frame_intact = frame_intact_mask;
        end
    endtask
    task check_unchanged;
        begin
            if (build_grid !== saved_grid || build_frames !== saved_frames ||
                intact_mask !== saved_intact || frame_intact_mask !== saved_frame_intact)
                $fatal(1, "Rejected edit changed construction");
        end
    endtask
    initial begin
        clocks(3); reset = 0; clocks(2);
        if (build_grid!==0 || build_frames!==0 || intact_mask!==0 || frame_intact_mask!==0 ||
            build_valid || pig_alive || mass!=0 || frames_left!=9 || pigs_left!=2 ||
            wheels_left!=3 || engines_left!=9 || balloons_left!=2)
            $fatal(1,"Empty startup or configured inventory incorrect");
        build_test_vehicle();
        if (!build_valid || mass != 13 || intact_mask != 9'b101110000 || build_frames != 9'b000111000)
            $fatal(1, "Test frame/content build incorrect");
        save_build();
        edit(`LP_EDIT_PLACE, 0, `LP_PART_PIG); check_unchanged();
        edit(`LP_EDIT_PLACE, 0, `LP_PART_ENGINE); check_unchanged();
        edit(`LP_EDIT_PLACE, 0, `LP_PART_WHEEL); check_unchanged();
        edit(`LP_EDIT_PLACE, 8, `LP_PART_BALLOON); check_unchanged();
        edit(`LP_EDIT_PLACE, 7, `LP_PART_BALLOON); check_unchanged();
        edit(`LP_EDIT_PLACE, 4, `LP_PART_WHEEL); check_unchanged();
        edit(`LP_EDIT_PLACE, 4, `LP_PART_BALLOON); check_unchanged();
        edit(`LP_EDIT_PLACE, 0, `LP_PART_FRAME);
        edit(`LP_EDIT_PLACE, 0, `LP_PART_PIG);
        if (!build_frames[0] || build_grid[2:0] != `LP_PART_PIG || build_valid || mass != 17)
            $fatal(1, "Pig did not coexist with frame or two pigs accepted");
        edit(`LP_EDIT_PLACE, 0, `LP_PART_ENGINE);
        if (!build_frames[0] || engines != 2 || !build_valid || mass != 18)
            $fatal(1, "Replacing pig with engine damaged the frame");
        edit(`LP_EDIT_REMOVE, 0, `LP_PART_EMPTY);
        if (!build_frames[0] || build_grid[2:0] != `LP_PART_EMPTY || mass != 15)
            $fatal(1, "First removal did not preserve empty frame");
        edit(`LP_EDIT_REMOVE, 0, `LP_PART_EMPTY);
        if (build_frames[0] || frame_intact_mask[0] || mass != 13)
            $fatal(1, "Second removal did not remove frame");
        edit(`LP_EDIT_PLACE, 7, `LP_PART_WHEEL);
        if (wheels != 3 || mass != 14) $fatal(1, "Wheel below frame rejected");
        edit(`LP_EDIT_REMOVE, 7, `LP_PART_EMPTY);
        edit(`LP_EDIT_PLACE, 0, `LP_PART_BALLOON);
        if (balloons != 1 || mass != 14) $fatal(1, "Balloon above frame rejected");
        save_build();
        edit(`LP_EDIT_PLACE, 0, `LP_PART_FRAME); check_unchanged();
        edit(`LP_EDIT_REMOVE, 3, `LP_PART_EMPTY);
        if (build_valid || build_error != `LP_BUILD_ERR_ATTACHMENT)
            $fatal(1, "Removing support did not invalidate attached parts");
        edit(`LP_EDIT_PLACE, 3, `LP_PART_FRAME);
        if (!build_valid) $fatal(1, "Replacing support did not restore validity");
        edit(`LP_EDIT_REMOVE, 0, `LP_PART_EMPTY);
        // Exercise every packed cell, including the row boundaries.
        for (cell_number = 0; cell_number < 9; cell_number = cell_number + 1) begin
            edit(`LP_EDIT_REMOVE, cell_number, `LP_PART_EMPTY);
            edit(`LP_EDIT_REMOVE, cell_number, `LP_PART_EMPTY);
            edit(`LP_EDIT_PLACE, cell_number, `LP_PART_FRAME);
            edit(`LP_EDIT_PLACE, cell_number, `LP_PART_ENGINE);
            if (!build_frames[cell_number] || build_grid[cell_number*3 +: 3] != `LP_PART_ENGINE)
                $fatal(1, "Wrong cell edited");
        end
        if (engines != 9 || mass != 45 || build_valid) $fatal(1, "Layer counts or mass incorrect");
        game_state = `LP_RUN; clocks(1); pixel = 40*96+64; #1;
        if (colour != 16'hffff) $fatal(1, "18 surviving parts did not show tens digit");
        game_state = `LP_BUILD; clocks(1);
        edit(`LP_EDIT_PLACE, 0, `LP_PART_PIG);
        if (!build_valid || mass != 44 || engines != 8) $fatal(1, "Single pig not recognised");
        reset = 1; clocks(1); reset = 0; clocks(1); build_test_vehicle();
        save_build();
        for (cell_number = 9; cell_number < 16; cell_number = cell_number + 1) begin
            edit(`LP_EDIT_PLACE, cell_number, `LP_PART_FRAME); check_unchanged();
            edit(`LP_EDIT_REMOVE, cell_number, `LP_PART_EMPTY); check_unchanged();
        end
        edit(`LP_EDIT_PLACE, 0, `LP_PART_EMPTY); check_unchanged();
        edit(`LP_EDIT_PLACE, 0, `LP_PART_BOOSTER); check_unchanged();
        edit(`LP_EDIT_PLACE, 0, 3'd7); check_unchanged();
        edit(2'd2, 0, `LP_PART_FRAME); check_unchanged();
        edit(2'd3, 0, `LP_PART_FRAME); check_unchanged();
        // Move the pig to another frame; retry must restore this edited layout.
        edit(`LP_EDIT_REMOVE, 4, `LP_PART_EMPTY);
        if (build_valid || pig_alive || build_error != `LP_BUILD_ERR_PIG)
            $fatal(1, "Missing pig accepted");
        edit(`LP_EDIT_PLACE, 3, `LP_PART_PIG);
        if (!build_valid || !pig_alive || mass != 13) $fatal(1, "Moved pig not recognised");
        save_build(); game_state = `LP_RUN;
        edit(`LP_EDIT_REMOVE, 3, `LP_PART_EMPTY); check_unchanged();
        damage_frame_mask = 9'b000001000; damage_valid = 1; clocks(1); damage_valid = 0; clocks(1);
        if (frame_intact_mask[3] || !pig_alive || mass != 11 || build_frames !== saved_frames)
            $fatal(1, "Frame damage incorrectly destroyed pig or saved frame");
        pixel = 24*96+8; #1;
        if (colour != 16'h07e0) $fatal(1, "Surviving pig disappeared with its frame");
        pixel = 24*96+5; #1;
        if (colour != 16'h0841) $fatal(1, "Destroyed frame border still drawn");
        damage_frame_mask = 0; damage_mask = 9'b000101000;
        damage_valid = 1; clocks(1); damage_valid = 0; clocks(1);
        if (build_grid !== saved_grid || pig_alive || engines != 0 || mass != 6)
            $fatal(1, "Content damage changed saved build or wrong live properties");
        if (!frame_intact_mask[5]) $fatal(1, "Engine damage incorrectly destroyed frame");
        game_state = `LP_INIT_RUN; run_init = 1; clocks(2);
        if (!init_ready || intact_mask !== saved_intact || frame_intact_mask !== saved_frame_intact ||
            build_grid !== saved_grid || !pig_alive || engines != 1 || mass != 13)
            $fatal(1, "Retry did not restore both layers of the edited build");
        edit(`LP_EDIT_REMOVE, 3, `LP_PART_EMPTY); check_unchanged();
        clocks(3); if (!init_ready) $fatal(1, "Initialisation acknowledgement did not hold");
        run_init = 0; game_state = `LP_RUN; clocks(1);
        if (init_ready) $fatal(1, "Initialisation acknowledgement did not clear");
        damage_mask = 9'b000100000; damage_frame_mask = 9'b000100000;
        damage_valid = 1; clocks(1); damage_valid = 0;
        game_state = `LP_BUILD; clocks(2);
        if (intact_mask !== saved_intact || frame_intact_mask !== saved_frame_intact ||
            engines != 1 || build_grid !== saved_grid) $fatal(1, "Return to construction did not restore build");
        $display("PASS vehicle_builder_tb: frame contents, attachments, removal, validation, independent damage, drawing and retry");
        $finish;
    end
    initial begin #10000; $fatal(1, "Builder test timed out"); end
endmodule
