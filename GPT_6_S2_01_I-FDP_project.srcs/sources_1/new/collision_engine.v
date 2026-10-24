// Owner: Role 3 - Yap Ting. Terrain collision response.
`timescale 1ns / 1ps
`include "game_defs.vh"

// Collision response for the fixed 24 by 24 pixel vehicle footprint.
// The module owns no vehicle position registers. It captures one proposed
// movement, checks the four active terrain rectangles, and returns one stable
// response through the existing valid/ready handshake.
module collision_engine (
    input wire clk, reset, move_valid,
    output wire move_ready,
    input wire signed [15:0] previous_x, previous_y,
    input wire signed [15:0] proposed_x, proposed_y, proposed_vx, proposed_vy,
    input wire [2:0] terrain_count,
    input wire [127:0] terrain_rects,
    output reg response_valid,
    input wire response_ready,
    output reg signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy,
    output reg grounded
);
    localparam IDLE = 0, CHECK = 1, CHOOSE = 2;
    localparam signed [17:0] VEHICLE_WIDTH_FP  = 18'sd6144; // 24 * 256
    localparam signed [17:0] VEHICLE_HEIGHT_FP = 18'sd6144; // 24 * 256

    reg [1:0] phase;
    reg signed [15:0] saved_x, saved_y, saved_vx, saved_vy;
    reg signed [17:0] old_left, old_right, old_top, old_bottom;
    reg signed [17:0] new_left, new_right, new_top, new_bottom;
    reg [127:0] saved_terrain;
    reg [2:0] saved_count;

    reg [3:0] landing_hit;
    reg [3:0] ceiling_hit;
    reg [3:0] left_wall_hit;
    reg [3:0] right_wall_hit;

    reg best_landing_hit, best_ceiling_hit;
    reg best_left_wall_hit, best_right_wall_hit;
    reg [7:0] best_landing_top;
    reg [8:0] best_ceiling_bottom;
    reg [7:0] best_left_wall_x;
    reg [8:0] best_right_wall_x;

    reg [8:0] rect_right_pixels, rect_bottom_pixels;
    reg signed [17:0] rect_left, rect_right, rect_top, rect_bottom;
    reg signed [15:0] next_x, next_y, next_vx, next_vy;

    integer select_index, check_index;

    assign move_ready = (phase == IDLE) && !response_valid;

    // Choose independently on the vertical and horizontal axes. This allows
    // a diagonal corner hit to correct both coordinates in one response.
    // For multiple landing surfaces, the highest crossed surface wins.
    always @* begin
        best_landing_hit = 1'b0;
        best_ceiling_hit = 1'b0;
        best_left_wall_hit = 1'b0;
        best_right_wall_hit = 1'b0;
        best_landing_top = 8'd0;
        best_ceiling_bottom = 9'd0;
        best_left_wall_x = 8'd0;
        best_right_wall_x = 9'd0;

        for (select_index = 0; select_index < 4; select_index = select_index + 1) begin
            if (landing_hit[select_index] &&
                (!best_landing_hit ||
                 saved_terrain[select_index*32+8 +: 8] < best_landing_top)) begin
                best_landing_hit = 1'b1;
                best_landing_top = saved_terrain[select_index*32+8 +: 8];
            end

            if (ceiling_hit[select_index] &&
                (!best_ceiling_hit ||
                 ({1'b0,saved_terrain[select_index*32+8 +: 8]} +
                  {1'b0,saved_terrain[select_index*32+24 +: 8]}) > best_ceiling_bottom)) begin
                best_ceiling_hit = 1'b1;
                best_ceiling_bottom = {1'b0,saved_terrain[select_index*32+8 +: 8]} +
                                      {1'b0,saved_terrain[select_index*32+24 +: 8]};
            end

            if (left_wall_hit[select_index] &&
                (!best_left_wall_hit ||
                 saved_terrain[select_index*32 +: 8] < best_left_wall_x)) begin
                best_left_wall_hit = 1'b1;
                best_left_wall_x = saved_terrain[select_index*32 +: 8];
            end

            if (right_wall_hit[select_index] &&
                (!best_right_wall_hit ||
                 ({1'b0,saved_terrain[select_index*32 +: 8]} +
                  {1'b0,saved_terrain[select_index*32+16 +: 8]}) > best_right_wall_x)) begin
                best_right_wall_hit = 1'b1;
                best_right_wall_x = {1'b0,saved_terrain[select_index*32 +: 8]} +
                                    {1'b0,saved_terrain[select_index*32+16 +: 8]};
            end
        end
    end

    // Calculate the response from the selected surfaces. The current
    // coordinate convention is positive x to the right and positive y down.
    always @* begin
        next_x = saved_x;
        next_y = saved_y;
        next_vx = saved_vx;
        next_vy = saved_vy;

        if (best_landing_hit) begin
            next_y = $signed({2'b00,best_landing_top,8'b0}) - VEHICLE_HEIGHT_FP;
            next_vy = 16'sd0;
        end else if (best_ceiling_hit) begin
            next_y = $signed({1'b0,best_ceiling_bottom,8'b0});
            next_vy = 16'sd0;
        end

        if (best_left_wall_hit) begin
            next_x = $signed({2'b00,best_left_wall_x,8'b0}) - VEHICLE_WIDTH_FP;
            next_vx = 16'sd0;
        end else if (best_right_wall_hit) begin
            next_x = $signed({1'b0,best_right_wall_x,8'b0});
            next_vx = 16'sd0;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            phase <= IDLE;
            response_valid <= 1'b0;
            grounded <= 1'b0;
            saved_x <= 0;
            saved_y <= 0;
            saved_vx <= 0;
            saved_vy <= 0;
            old_left <= 0;
            old_right <= 0;
            old_top <= 0;
            old_bottom <= 0;
            new_left <= 0;
            new_right <= 0;
            new_top <= 0;
            new_bottom <= 0;
            saved_terrain <= 0;
            saved_count <= 0;
            landing_hit <= 0;
            ceiling_hit <= 0;
            left_wall_hit <= 0;
            right_wall_hit <= 0;
            corrected_x <= 0;
            corrected_y <= 0;
            corrected_vx <= 0;
            corrected_vy <= 0;
        end else begin
            if (response_valid && response_ready)
                response_valid <= 1'b0;

            case (phase)
                IDLE: begin
                    if (move_valid && move_ready) begin
                        saved_x <= proposed_x;
                        saved_y <= proposed_y;
                        saved_vx <= proposed_vx;
                        saved_vy <= proposed_vy;
                        old_left <= $signed({{2{previous_x[15]}},previous_x});
                        old_right <= $signed({{2{previous_x[15]}},previous_x}) +
                                     VEHICLE_WIDTH_FP;
                        old_top <= $signed({{2{previous_y[15]}},previous_y});
                        old_bottom <= $signed({{2{previous_y[15]}},previous_y}) +
                                      VEHICLE_HEIGHT_FP;
                        new_left <= $signed({{2{proposed_x[15]}},proposed_x});
                        new_right <= $signed({{2{proposed_x[15]}},proposed_x}) +
                                     VEHICLE_WIDTH_FP;
                        new_top <= $signed({{2{proposed_y[15]}},proposed_y});
                        new_bottom <= $signed({{2{proposed_y[15]}},proposed_y}) +
                                      VEHICLE_HEIGHT_FP;
                        saved_terrain <= terrain_rects;
                        saved_count <= terrain_count;
                        landing_hit <= 0;
                        ceiling_hit <= 0;
                        left_wall_hit <= 0;
                        right_wall_hit <= 0;
                        phase <= CHECK;
                    end
                end

                CHECK: begin
                    for (check_index = 0; check_index < 4; check_index = check_index + 1) begin
                        rect_left = $signed({2'b00,saved_terrain[check_index*32 +: 8],8'b0});
                        rect_top = $signed({2'b00,saved_terrain[check_index*32+8 +: 8],8'b0});
                        rect_right_pixels = {1'b0,saved_terrain[check_index*32 +: 8]} +
                                            {1'b0,saved_terrain[check_index*32+16 +: 8]};
                        rect_bottom_pixels = {1'b0,saved_terrain[check_index*32+8 +: 8]} +
                                             {1'b0,saved_terrain[check_index*32+24 +: 8]};
                        rect_right = $signed({1'b0,rect_right_pixels,8'b0});
                        rect_bottom = $signed({1'b0,rect_bottom_pixels,8'b0});

                        landing_hit[check_index] <=
                            check_index < saved_count &&
                            saved_terrain[check_index*32+16 +: 8] != 0 &&
                            saved_terrain[check_index*32+24 +: 8] != 0 &&
                            !saved_vy[15] &&
                            old_bottom <= rect_top &&
                            new_bottom >= rect_top &&
                            new_right > rect_left &&
                            new_left < rect_right;

                        ceiling_hit[check_index] <=
                            check_index < saved_count &&
                            saved_terrain[check_index*32+16 +: 8] != 0 &&
                            saved_terrain[check_index*32+24 +: 8] != 0 &&
                            saved_vy[15] &&
                            old_top >= rect_bottom &&
                            new_top <= rect_bottom &&
                            new_right > rect_left &&
                            new_left < rect_right;

                        // Test sideways motion at the previous height. Gravity
                        // must not turn a floor edge into a wall while landing.
                        left_wall_hit[check_index] <=
                            check_index < saved_count &&
                            saved_terrain[check_index*32+16 +: 8] != 0 &&
                            saved_terrain[check_index*32+24 +: 8] != 0 &&
                            !saved_vx[15] &&
                            old_right <= rect_left &&
                            new_right > rect_left &&
                            old_bottom > rect_top &&
                            old_top < rect_bottom;

                        right_wall_hit[check_index] <=
                            check_index < saved_count &&
                            saved_terrain[check_index*32+16 +: 8] != 0 &&
                            saved_terrain[check_index*32+24 +: 8] != 0 &&
                            saved_vx[15] &&
                            old_left >= rect_right &&
                            new_left < rect_right &&
                            old_bottom > rect_top &&
                            old_top < rect_bottom;
                    end
                    phase <= CHOOSE;
                end

                CHOOSE: begin
                    corrected_x <= next_x;
                    corrected_y <= next_y;
                    corrected_vx <= next_vx;
                    corrected_vy <= next_vy;
                    grounded <= best_landing_hit;
                    response_valid <= 1'b1;
                    phase <= IDLE;
                end

                default: phase <= IDLE;
            endcase
        end
    end
endmodule
