`timescale 1ns / 1ps
`include "game_defs.vh"

// Level 2/4 map background is open space.  In particular, the DARK display
// colour must not be converted into a collision floor for block-RAM maps.
module flight_background_tb;
    reg clk=0, reset=1, move_valid=0, response_ready=0;
    reg signed [19:0] previous_x=20'sd25600, previous_y=20'sd25600;
    reg signed [19:0] proposed_x=20'sd25856, proposed_y=20'sd26112;
    reg signed [15:0] proposed_vx=16'sd256, proposed_vy=16'sd256;
    reg signed [4:0] previous_tilt=0, proposed_tilt=0;
    reg [2:0] query_class=`LP_MAP_DARK;
    wire signed [10:0] query_x, query_y;
    wire move_ready, response_valid, grounded;
    wire signed [19:0] corrected_x, corrected_y;
    wire signed [15:0] corrected_vx, corrected_vy;
    wire signed [7:0] ground_slope;

    always #5 clk=~clk;

    collision_engine dut (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y),
        .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy),
        .terrain_count(3'd0), .terrain_rects(128'd0), .map_level(1'b1),
        .rotation_enabled(1'b0), .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt),
        .collision_mask(9'd0), .cg_enabled(1'b0), .build_grid(27'd0),
        .part_intact_mask(9'd0), .frame_intact_mask(9'd0),
        .world_width(10'd890), .world_height(10'd213),
        .query_x(query_x), .query_y(query_y), .query_class(query_class),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy),
        .grounded(grounded), .ground_slope(ground_slope),
        .corrected_tilt(), .tip_dir()
    );

    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask

    integer waited;
    initial begin
        clocks(3); reset=0; clocks(1);
        while (!move_ready) clocks(1);
        move_valid=1; clocks(1); move_valid=0;
        waited=0;
        while (!response_valid && waited<30000) begin clocks(1); waited=waited+1; end
        if (!response_valid) $fatal(1,"Background collision response timed out");
        if (corrected_x!==proposed_x || corrected_y!==proposed_y ||
            corrected_vx!==proposed_vx || corrected_vy!==proposed_vy || grounded)
            $fatal(1,"DARK background incorrectly blocked movement: x=%0d y=%0d vx=%0d vy=%0d grounded=%b",
                   corrected_x, corrected_y, corrected_vx, corrected_vy, grounded);
        response_ready=1; clocks(1); response_ready=0;
        $display("PASS flight_background_tb: DARK Level 2 background remains open");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Flight background test timed out"); end
endmodule
