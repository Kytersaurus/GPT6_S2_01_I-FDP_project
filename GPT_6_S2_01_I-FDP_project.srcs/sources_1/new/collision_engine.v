// Owner: Role 3 - Yap Ting. Terrain collision response.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Role 3 starter: downward platform crossing. Walls/ceilings/TNT are future work.
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
    // Capture -> check four platforms in parallel -> choose the highest hit.
    // Splitting the work avoids a chain of four full collision checks in one clock.
    localparam IDLE=0, CHECK=1, CHOOSE=2;
    reg [1:0] phase;
    reg signed [15:0] saved_x, saved_y, saved_vx, saved_vy;
    reg signed [17:0] old_bottom, new_bottom, new_right;
    reg [127:0] saved_terrain;
    reg [2:0] saved_count;
    reg [3:0] platform_hit;
    reg best_hit;
    reg [7:0] best_top;
    reg [8:0] rect_right_pixels;
    reg signed [17:0] rect_left, rect_right, rect_top;
    wire signed [17:0] new_left = {{2{saved_x[15]}},saved_x};
    wire signed [17:0] landing_y = $signed({2'b00,best_top,8'b0}) - 18'sd6144;
    integer select_index, check_index;
    assign move_ready = phase == IDLE && !response_valid;
    always @* begin
        best_hit = 0; best_top = 0;
        for (select_index = 0; select_index < 4; select_index = select_index + 1) begin
            if (platform_hit[select_index] && (!best_hit || saved_terrain[select_index*32+8 +: 8] < best_top)) begin
                best_hit = 1;
                best_top = saved_terrain[select_index*32+8 +: 8];
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            phase <= IDLE; response_valid <= 0; grounded <= 0;
            saved_x <= 0; saved_y <= 0; saved_vx <= 0; saved_vy <= 0;
            old_bottom <= 0; new_bottom <= 0; new_right <= 0;
            saved_terrain <= 0; saved_count <= 0; platform_hit <= 0;
            rect_right_pixels = 0; rect_left = 0; rect_right = 0; rect_top = 0;
            corrected_x <= 0; corrected_y <= 0; corrected_vx <= 0; corrected_vy <= 0;
        end else begin
            if (response_valid && response_ready) response_valid <= 0;
            case (phase)
                IDLE: if (move_valid && move_ready) begin
                    saved_x <= proposed_x; saved_y <= proposed_y;
                    saved_vx <= proposed_vx; saved_vy <= proposed_vy;
                    // 24 pixels * 256 fixed-point units; extend before addition.
                    old_bottom <= $signed({{2{previous_y[15]}},previous_y}) + 18'sd6144;
                    new_bottom <= $signed({{2{proposed_y[15]}},proposed_y}) + 18'sd6144;
                    new_right <= $signed({{2{proposed_x[15]}},proposed_x}) + 18'sd6144;
                    saved_terrain <= terrain_rects; saved_count <= terrain_count;
                    phase <= CHECK;
                end
                CHECK: begin
                    for (check_index = 0; check_index < 4; check_index = check_index + 1) begin
                        // Temporary blocking assignments describe each parallel check.
                        rect_left = $signed({2'b00,saved_terrain[check_index*32 +: 8],8'b0});
                        rect_top = $signed({2'b00,saved_terrain[check_index*32+8 +: 8],8'b0});
                        rect_right_pixels = {1'b0,saved_terrain[check_index*32 +: 8]} +
                                            {1'b0,saved_terrain[check_index*32+16 +: 8]};
                        rect_right = $signed({1'b0,rect_right_pixels,8'b0});
                        platform_hit[check_index] <= check_index < saved_count &&
                            saved_terrain[check_index*32+16 +: 8] != 0 && saved_terrain[check_index*32+24 +: 8] != 0 &&
                            !saved_vy[15] && old_bottom <= rect_top && new_bottom >= rect_top &&
                            new_right > rect_left && new_left < rect_right;
                    end
                    phase <= CHOOSE;
                end
                CHOOSE: begin
                    corrected_x <= saved_x; corrected_y <= best_hit ? landing_y[15:0] : saved_y;
                    corrected_vx <= saved_vx; corrected_vy <= best_hit ? 16'sd0 : saved_vy;
                    grounded <= best_hit; response_valid <= 1; phase <= IDLE;
                end
                default: phase <= IDLE;
            endcase
        end
    end
endmodule
