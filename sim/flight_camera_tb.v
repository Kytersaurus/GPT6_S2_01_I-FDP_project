// Regression for the 1.5x Cave Flight camera limits and scenery alignment.
`timescale 1ns / 1ps
`include "game_defs.vh"

module flight_camera_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [6:0] in_x = 0;
    reg [5:0] in_y = 0;
    reg signed [19:0] vehicle_x = 20'sd17408;
    reg signed [19:0] vehicle_y = 20'sd45568;
    wire signed [10:0] map_x, map_y;
    wire [15:0] pixel_data;

    right_renderer #(.USE_PIXEL_INDEX(0)) dut (
        .clk(clk), .pixel_index(13'd0), .in_x(in_x), .in_y(in_y),
        .zoomed_out(1'b0), .overview(1'b0), .free_look(1'b0),
        .cursor_x(7'd0), .cursor_y(7'd0), .game_state(`LP_RUN),
        .build_grid(27'd0), .build_facing_left(9'd0), .intact_mask(9'd0),
        .frame_intact_mask(9'd0), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y),
        .camera_x(vehicle_x), .camera_y(vehicle_y), .vehicle_tilt(5'sd0),
        .spawn_x(20'sd17408), .spawn_y(20'sd45568),
        .terrain_count(3'd0), .terrain_rects(128'd0), .goal_rect(32'd0),
        .tnt_count(3'd0), .tnt_positions(64'd0), .tnt_intact(4'd0),
        .hazard_count(2'd0), .hazard_rects(64'd0), .blast_phase(8'd0),
        .death_phase(2'd0), .death_x(20'sd0), .death_y(20'sd0),
        .launch_flash(1'b0), .anim_phase(1'b0), .map_level(1'b1), .map_id(1'b1),
        .world_width(10'd890), .world_height(10'd213), .flag_x(10'd769),
        .flag_y(10'd50), .star_box_x(10'd400), .star_box_y(10'd150),
        .star_box_collected(1'b0), .map_x(map_x), .map_y(map_y),
        .map_class(`LP_MAP_GRASS), .pixel_data(pixel_data)
    );

    initial begin
        #1;
        // The bottom-left spawn view must include the ground at y=202..204.
        if (map_x !== 11'sd58 || map_y !== 11'sd176)
            $fatal(1, "Spawn camera origin wrong: map=(%0d,%0d)", map_x, map_y);
        in_x = 7'd95; in_y = 6'd42;
        #1;
        if (map_x !== 11'sd121 || map_y !== 11'sd204)
            $fatal(1, "Spawn view clips ground: bottom map=(%0d,%0d)", map_x, map_y);

        // The finish ledge remains in the close-up view at its documented spot.
        vehicle_x = 20'sd196864;
        vehicle_y = 20'sd12800;
        in_x = 0; in_y = 0;
        #1;
        if (map_x !== 11'sd760 || map_y !== 11'sd48)
            $fatal(1, "Finish camera origin wrong: map=(%0d,%0d)", map_x, map_y);
        $display("PASS flight_camera_tb: close-up camera shows spawn ground and finish ledge at documented coordinates");
        $finish;
    end
endmodule
