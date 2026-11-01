// Temporary visualisation bench. It dumps real renderer pixels as PPM frames.
// This file is intentionally uncommitted and is useful when checking the two OLEDs.
`timescale 1ns / 1ps
`include "game_defs.vh"

module oled_frame_dump_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [12:0] pixel_index = 13'd0;
    reg [2:0] view_state = `LP_BUILD;
    reg [1:0] level_index = `LP_LEVEL_ARCH;
    reg [8:0] intact_mask = 9'b111111111;
    reg [8:0] frame_intact_mask = 9'b000111000;
    reg [8:0] build_frames = 9'b000111000;
    reg [8:0] build_facing_left = 9'b000000000;
    reg [26:0] build_grid = {
        `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
        `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
        `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
    };
    reg [1:0] inventory_page = 2'd0;
    reg [3:0] rockets_left = 4'd1, fans_left = 4'd1;
    reg [3:0] frames_left = 4'd2, pigs_left = 4'd0, wheels_left = 4'd0;
    reg [3:0] engines_left = 4'd0, balloons_left = 4'd2;
    reg [2:0] selected_part = `LP_PART_FRAME;
    reg selected_left = 1'b0, drag_active = 1'b0, drag_from_grid = 1'b0;
    reg [3:0] drag_source = 4'd9;
    reg [2:0] drag_contents = `LP_PART_EMPTY;
    reg [6:0] cursor_x = 7'd0, cursor_y = 7'd0;
    reg cursor_visible = 1'b0;
    reg [3:0] build_error = 4'd0;
    reg [2:0] feedback_code = `LP_FEEDBACK_NONE;
    reg [3:0] feedback_cell = 4'd0;
    reg engine_enabled = 1'b1, boost_active = 1'b0;
    reg [1:0] fail_reason = `LP_FAIL_NONE;
    reg [7:0] run_seconds = 8'd12;
    reg star_box_collected = 1'b0, anim_phase = 1'b0;

    reg signed [19:0] vehicle_x = 20'sd53248;
    reg signed [19:0] vehicle_y = 20'sd19456;
    reg signed [4:0] vehicle_tilt = 5'sd0;
    reg zoomed_out = 1'b1, overview = 1'b0, free_look = 1'b0;
    reg [6:0] look_x = 7'd0, look_y = 7'd0;
    reg [`LP_MAX_TNT-1:0] tnt_intact = {`LP_MAX_TNT{1'b1}};
    reg [2*`LP_MAX_TNT-1:0] blast_phase = {2*`LP_MAX_TNT{1'b0}};
    reg [2:0] visual_tnt_count = 3'd0;
    reg [`LP_TNT_BITS-1:0] visual_tnt_positions = {`LP_TNT_BITS{1'b0}};
    reg [1:0] death_phase = 2'd0;
    reg signed [19:0] death_x = 20'sd0, death_y = 20'sd0;
    reg launch_flash = 1'b0;

    wire signed [19:0] spawn_x, spawn_y;
    wire [2:0] terrain_count, tnt_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire [`LP_TNT_BITS-1:0] tnt_positions;
    wire [7:0] par_time;
    wire [1:0] hazard_count;
    wire [`LP_HAZARD_BITS-1:0] hazard_rects;
    wire map_level, map_id;
    wire [9:0] world_width, world_height, flag_x, flag_y;
    wire [9:0] star_box_x, star_box_y;

    level_data levels (
        .level_index(level_index), .spawn_x(spawn_x), .spawn_y(spawn_y),
        .terrain_count(terrain_count), .terrain_rects(terrain_rects), .goal_rect(goal_rect),
        .tnt_count(tnt_count), .tnt_positions(tnt_positions), .par_time(par_time),
        .hazard_count(hazard_count), .hazard_rects(hazard_rects), .map_level(map_level),
        .map_id(map_id), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .star_box_x(star_box_x), .star_box_y(star_box_y)
    );

    wire [15:0] left_colour, right_colour;
    wire signed [10:0] map_x, map_y;
    wire [2:0] map_class;

    left_renderer left_view (
        .pixel_index(pixel_index), .game_state(view_state), .build_grid(build_grid),
        .build_frames(build_frames), .build_facing_left(build_facing_left),
        .selected_left(selected_left), .inventory_page(inventory_page),
        .rockets_left(rockets_left), .fans_left(fans_left), .intact_mask(intact_mask),
        .frame_intact_mask(frame_intact_mask), .build_valid(1'b1), .build_error(build_error),
        .feedback_code(feedback_code), .feedback_cell(feedback_cell),
        .engine_enabled(engine_enabled), .boost_active(boost_active),
        .frames_left(frames_left), .pigs_left(pigs_left), .wheels_left(wheels_left),
        .engines_left(engines_left), .balloons_left(balloons_left),
        .selected_part(selected_part), .drag_active(drag_active),
        .drag_from_grid(drag_from_grid), .drag_source(drag_source),
        .drag_contents(drag_contents), .cursor_x(cursor_x), .cursor_y(cursor_y),
        .cursor_visible(cursor_visible), .level_index(level_index),
        .fail_reason(fail_reason), .run_seconds(run_seconds),
        .star_box_collected(star_box_collected), .anim_phase(anim_phase),
        .pixel_data(left_colour)
    );

    level_map #(.ARCH_SCALED(1)) map_rom (
        .map_id(map_id), .draw_clk(clk), .draw_x(map_x), .draw_y(map_y),
        .draw_class(map_class), .query_clk(clk), .query_map_id(map_id),
        .query_x(11'sd0), .query_y(11'sd0), .query_class(), .query_solid()
    );

    right_renderer right_view (
        .clk(clk), .pixel_index(pixel_index), .zoomed_out(zoomed_out),
        .overview(overview), .free_look(free_look), .cursor_x(look_x), .cursor_y(look_y),
        .game_state(view_state), .build_grid(build_grid),
        .build_facing_left(build_facing_left), .intact_mask(intact_mask),
        .frame_intact_mask(frame_intact_mask), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y),
        .vehicle_tilt(vehicle_tilt), .spawn_x(spawn_x), .spawn_y(spawn_y),
        .terrain_count(terrain_count), .terrain_rects(terrain_rects), .goal_rect(goal_rect),
        .tnt_count(visual_tnt_count), .tnt_positions(visual_tnt_positions), .tnt_intact(tnt_intact),
        .hazard_count(hazard_count), .hazard_rects(hazard_rects), .blast_phase(blast_phase),
        .death_phase(death_phase), .death_x(death_x), .death_y(death_y),
        .launch_flash(launch_flash), .anim_phase(anim_phase), .map_level(map_level),
        .map_id(map_id), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .star_box_x(star_box_x),
        .star_box_y(star_box_y), .star_box_collected(star_box_collected),
        .map_x(map_x), .map_y(map_y), .map_class(map_class), .pixel_data(right_colour)
    );

    integer x, y, fh, r8, g8, b8;

    task write_colour;
        input integer file_handle;
        input [15:0] colour;
        begin
            r8 = (colour[15:11] * 255) / 31;
            g8 = (colour[10:5] * 255) / 63;
            b8 = (colour[4:0] * 255) / 31;
            $fwrite(file_handle, "%0d %0d %0d ", r8, g8, b8);
        end
    endtask

    task dump_left;
        input [8*80-1:0] filename;
        begin
            fh = $fopen(filename, "w");
            $fwrite(fh, "P3\n96 64\n255\n");
            for (y = 0; y < 64; y = y + 1)
                for (x = 0; x < 96; x = x + 1) begin
                    pixel_index = y*96+x;
                    #1;
                    write_colour(fh, left_colour);
                end
            $fclose(fh);
        end
    endtask

    task dump_right;
        input [8*80-1:0] filename;
        begin
            fh = $fopen(filename, "w");
            $fwrite(fh, "P3\n96 64\n255\n");
            for (y = 0; y < 64; y = y + 1)
                for (x = 0; x < 96; x = x + 1) begin
                    pixel_index = y*96+x;
                    @(posedge clk);
                    #1;
                    write_colour(fh, right_colour);
                end
            $fclose(fh);
        end
    endtask

    initial begin
        // Build screen: the exact sample build used by the existing display test.
        view_state = `LP_BUILD;
        dump_left("oled_left_build.ppm");

        // Runtime screen at the Cave Arch spawn point.
        view_state = `LP_RUN;
        dump_left("oled_left_run.ppm");
        dump_right("oled_right_run.ppm");

        // Show the same runtime frame during a TNT blast for visual inspection.
        visual_tnt_count = 3'd1;
        visual_tnt_positions[7:0] = 8'd246;
        visual_tnt_positions[15:8] = 8'd76;
        blast_phase[1:0] = 2'd2;
        dump_right("oled_right_tnt.ppm");

        // Result screen: successful run with the collected star.
        view_state = `LP_SUCCESS;
        visual_tnt_count = 3'd0;
        blast_phase = {2*`LP_MAX_TNT{1'b0}};
        star_box_collected = 1'b1;
        run_seconds = 8'd22;
        dump_left("oled_left_success.ppm");
        dump_right("oled_right_success.ppm");

        $display("PASS oled_frame_dump_tb: wrote four 96x64 OLED frames");
        $finish;
    end
endmodule
