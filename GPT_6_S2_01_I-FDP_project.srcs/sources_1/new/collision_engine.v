// Owner: Role 3 - Yap Ting; shared map collision integration.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Capture the route for the whole request/response transaction.
// All levels now use registered ROM reads (map collision).
module collision_engine #(parameter ROTATION_ONLY = 0) (
    input wire clk, reset, move_valid,
    output wire move_ready,
    input wire signed [`LP_COORD_BITS-1:0] previous_x, previous_y,
    input wire signed [`LP_COORD_BITS-1:0] proposed_x, proposed_y,
    input wire signed [15:0] proposed_vx, proposed_vy,
    input wire [2:0] terrain_count,
    input wire [127:0] terrain_rects,
    input wire map_level,
    input tri0 rotation_enabled,
    input wire signed [`LP_TILT_BITS-1:0] previous_tilt, proposed_tilt,
    input tri1 [8:0] collision_mask,
    input tri0 cg_enabled,
    input tri0 [26:0] build_grid,
    input tri0 [8:0] part_intact_mask, frame_intact_mask,
    output wire support_unstable,
    input wire [9:0] world_width, world_height,
    output wire signed [10:0] query_x, query_y,
    input wire [2:0] query_class,
    output wire response_valid,
    input wire response_ready,
    output wire signed [`LP_COORD_BITS-1:0] corrected_x, corrected_y,
    output wire signed [15:0] corrected_vx, corrected_vy,
    output wire grounded,
    output wire signed [7:0] ground_slope,
    output wire signed [`LP_TILT_BITS-1:0] corrected_tilt,
    output wire signed [1:0] tip_dir
);
    reg busy, active_rotation;
    wire rot_unstable;
    assign support_unstable=active_rotation && rot_unstable;
    wire use_rotation = ROTATION_ONLY || rotation_enabled;
    wire rot_ready, rot_valid, rot_ground;
    wire signed [`LP_COORD_BITS-1:0] rot_x, rot_y;
    wire signed [15:0] rot_vx, rot_vy;
    wire signed [7:0] rot_slope;
    wire signed [`LP_TILT_BITS-1:0] rot_tilt;
    wire signed [1:0] rot_tip;
    wire signed [10:0] upright_qx, upright_qy, rot_qx, rot_qy;
    assign query_x = active_rotation ? rot_qx : upright_qx;
    assign query_y = active_rotation ? rot_qy : upright_qy;
    assign corrected_tilt = active_rotation ? rot_tilt : 0;
    assign tip_dir = active_rotation ? rot_tip : 2'sd0;
    wire map_ready, map_valid, map_ground;
    wire signed [`LP_COORD_BITS-1:0] map_x, map_y;
    wire signed [15:0] map_vx, map_vy;
    wire signed [7:0] map_slope;
    assign move_ready = !busy && (use_rotation ? rot_ready : map_ready);
    assign response_valid = busy && (active_rotation ? rot_valid : map_valid);
    assign corrected_x = active_rotation ? rot_x : map_x;
    assign corrected_y = active_rotation ? rot_y : map_y;
    assign corrected_vx = active_rotation ? rot_vx : map_vx;
    assign corrected_vy = active_rotation ? rot_vy : map_vy;
    assign grounded = active_rotation ? rot_ground : map_ground;
    assign ground_slope = active_rotation ? rot_slope : map_slope;
    always @(posedge clk) begin
        if (reset) begin busy <= 0; active_rotation <= ROTATION_ONLY; end
        else begin
            if (move_valid && move_ready) begin busy <= 1; active_rotation <= use_rotation; end
            if (response_valid && response_ready) busy <= 0;
        end
    end
    generate if (!ROTATION_ONLY) begin : g_upright_reference
    map_collision_engine u_map (
        .clk(clk), .reset(reset), .move_valid(move_valid && !busy && !use_rotation), .move_ready(map_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .world_width(world_width), .world_height(world_height),
        .query_x(upright_qx), .query_y(upright_qy), .query_class(query_class),
        .response_valid(map_valid), .response_ready(response_ready && busy && !active_rotation),
        .corrected_x(map_x), .corrected_y(map_y), .corrected_vx(map_vx), .corrected_vy(map_vy), .grounded(map_ground),
        .ground_slope(map_slope)
    );
    end else begin : g_rotation_only
        assign map_ready=1'b0, map_valid=1'b0, map_ground=1'b0;
        assign map_x=0, map_y=0, map_vx=0, map_vy=0, map_slope=0;
        assign upright_qx=0, upright_qy=0;
    end endgenerate
    rotating_map_collision_engine u_rotated_map (
        .clk(clk), .reset(reset), .move_valid(move_valid && !busy && use_rotation), .move_ready(rot_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt),
        .collision_mask(collision_mask), .cg_enabled(cg_enabled), .build_grid(build_grid),
        .part_intact_mask(part_intact_mask), .frame_intact_mask(frame_intact_mask),
        .support_unstable(rot_unstable),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .world_width(world_width), .world_height(world_height),
        .query_x(rot_qx), .query_y(rot_qy), .query_class(query_class),
        .response_valid(rot_valid), .response_ready(response_ready && busy && active_rotation),
        .corrected_x(rot_x), .corrected_y(rot_y), .corrected_vx(rot_vx), .corrected_vy(rot_vy), .grounded(rot_ground),
        .ground_slope(rot_slope), .corrected_tilt(rot_tilt), .tip_dir(rot_tip)
    );
endmodule

// Upright 24x24 body against the pixel map. Each candidate body is checked
// completely, including fractional edge pixels. One-pixel axis substeps sweep
// thin obstacles. The ROM address is held for ISSUE then consumed in SAMPLE.
// At current speeds a request takes a few thousand 100 MHz clocks, well below
// the 60 Hz update interval. No unbounded combinational terrain search is used.
module map_collision_engine #(
    parameter integer STEP_PIXELS = 3,
    parameter integer SNAP_PIXELS = 3
) (
    input wire clk, reset, move_valid,
    output wire move_ready,
    input wire signed [`LP_COORD_BITS-1:0] previous_x, previous_y,
    input wire signed [`LP_COORD_BITS-1:0] proposed_x, proposed_y,
    input wire signed [15:0] proposed_vx, proposed_vy,
    input wire [9:0] world_width, world_height,
    output wire signed [10:0] query_x, query_y,
    input wire [2:0] query_class,
    output reg response_valid,
    input wire response_ready,
    output reg signed [`LP_COORD_BITS-1:0] corrected_x, corrected_y,
    output reg signed [15:0] corrected_vx, corrected_vy,
    output reg grounded,
    output reg signed [7:0] ground_slope
);
    localparam IDLE=0, BODY=1, BODY_RESULT=2, SUPPORT=3, SUPPORT_RESULT=4,
        H_NEXT=5, H_SCAN=6, H_RESULT=7, V_SETUP=8, V_NEXT=9,
        V_SCAN=10, V_RESULT=11, FINAL_SUPPORT=12, FINAL_RESULT=13,
        SNAP_SCAN=14, SNAP_RESULT=15, RESPOND=16, ISSUE=17, SAMPLE=18,
        SLOPE_LEFT=19, SLOPE_LEFT_RESULT=20, SLOPE_RIGHT=21, SLOPE_RIGHT_RESULT=22;
    localparam signed [`LP_COORD_BITS+1:0] PIXEL=256, BODY_FP=6144;
    reg [4:0] phase, scan_return;
    reg signed [`LP_COORD_BITS+1:0] work_x, work_y, target_x, target_y;
    reg signed [`LP_COORD_BITS+1:0] candidate_x, candidate_y, delta_y, wall_limit;
    reg signed [15:0] result_vx, result_vy;
    reg moving_up, allow_snap, result_ground;
    reg [3:0] lift_attempt, recovery_attempt;
    reg [9:0] saved_width, saved_height;
    // Wider than the map port so outside coordinates can never alias in-map
    // pixels after truncation (e.g. x=1024 must not query x=-1024).
    reg signed [12:0] scan_left, scan_right, scan_bottom, scan_x, scan_y;
    reg signed [12:0] hit_x, hit_y;
    reg scan_hit;
    reg signed [12:0] support_x, support_y, slope_left_y;
    reg signed [7:0] result_slope;
    wire signed [13:0] slope_rise = $signed(hit_y) - $signed(slope_left_y);
    wire signed [13:0] slope_mid_error = $signed(slope_left_y) + $signed(hit_y) -
                                               ($signed(support_y) <<< 1);
    wire scan_inside = scan_x >= 0 && scan_y >= 0 &&
                       scan_x < $signed({1'b0,saved_width}) &&
                       scan_y < $signed({1'b0,saved_height});
    // Outside pixels are open for collision, including below the map. The
    // committed-pose world check owns failure at the world boundary.
    assign query_x = scan_inside ? scan_x[10:0] : 11'sd0;
    assign query_y = scan_inside ? scan_y[10:0] : 11'sd0;
    wire solid = query_class == `LP_MAP_ROCK || query_class == `LP_MAP_GRASS ||
                 query_class == `LP_MAP_ROAD || query_class == `LP_MAP_DARK;
    wire signed [`LP_COORD_BITS+1:0] wall_contact = target_x > work_x ?
        $signed(hit_x)*PIXEL-BODY_FP : ($signed(hit_x)+1)*PIXEL;
    wire signed [`LP_COORD_BITS+1:0] floor_contact = $signed(hit_y)*PIXEL-BODY_FP;
    assign move_ready = phase == IDLE && !response_valid;

    task scan_region;
        input signed [12:0] left_pixel, right_pixel, top_pixel, bottom_pixel;
        input [4:0] return_phase;
        begin
            scan_left <= left_pixel; scan_right <= right_pixel;
            scan_x <= left_pixel; scan_y <= top_pixel; scan_bottom <= bottom_pixel;
            scan_hit <= 0; scan_return <= return_phase; phase <= ISSUE;
        end
    endtask
    task scan_body;
        input signed [`LP_COORD_BITS+1:0] x, y;
        input [4:0] return_phase;
        begin
            // Inclusive last occupied pixel, preserving subpixel contact.
            scan_region(x >>> 8, (x+BODY_FP-1) >>> 8,
                        y >>> 8, (y+BODY_FP-1) >>> 8, return_phase);
        end
    endtask
    always @(posedge clk) begin
        if (reset) begin
            phase <= IDLE; response_valid <= 0; grounded <= 0;
            ground_slope <= 0; result_slope <= 0;
            support_x <= 0; support_y <= 0; slope_left_y <= 0;
            corrected_x <= 0; corrected_y <= 0; corrected_vx <= 0; corrected_vy <= 0;
            work_x <= 0; work_y <= 0; target_x <= 0; target_y <= 0;
            candidate_x <= 0; candidate_y <= 0; delta_y <= 0; wall_limit <= 0;
            result_vx <= 0; result_vy <= 0; moving_up <= 0;
            allow_snap <= 0; result_ground <= 0; lift_attempt <= 0; recovery_attempt <= 0;
            saved_width <= 0; saved_height <= 0;
            scan_left <= 0; scan_right <= 0; scan_bottom <= 0; scan_x <= 0; scan_y <= 0;
            hit_x <= 0; hit_y <= 0; scan_hit <= 0; scan_return <= IDLE;
        end else begin
            if (response_valid && response_ready) response_valid <= 0;
            case (phase)
                IDLE: if (move_valid && move_ready) begin
                    work_x <= previous_x; work_y <= previous_y;
                    target_x <= proposed_x;
                    delta_y <= $signed(proposed_y)-$signed(previous_y);
                    result_vx <= proposed_vx; result_vy <= proposed_vy;
                    moving_up <= proposed_vy < 0 || proposed_y < previous_y;
                    saved_width <= world_width; saved_height <= world_height;
                    result_ground <= 0; result_slope <= 0; recovery_attempt <= 0; phase <= BODY;
                end
                BODY: scan_body(work_x, work_y, BODY_RESULT);
                BODY_RESULT: begin
                    if (!scan_hit) phase <= SUPPORT;
                    else if (recovery_attempt < STEP_PIXELS) begin
                        work_y <= work_y-PIXEL;
                        recovery_attempt <= recovery_attempt+1'b1; phase <= BODY;
                    end else begin
                        // A malformed/embedded spawn must not tunnel through
                        // terrain. Keep its original pose and stop motion.
                        work_y <= work_y + recovery_attempt*PIXEL;
                        result_vx <= 0; result_vy <= 0; phase <= RESPOND;
                    end
                end
                SUPPORT: scan_region(work_x >>> 8, (work_x+BODY_FP-1) >>> 8,
                    (work_y+BODY_FP) >>> 8, (work_y+BODY_FP) >>> 8, SUPPORT_RESULT);
                SUPPORT_RESULT: begin allow_snap <= scan_hit && !moving_up; phase <= H_NEXT; end
                H_NEXT: begin
                    if (work_x == target_x) phase <= V_SETUP;
                    else begin
                        if (target_x > work_x)
                            candidate_x <= target_x-work_x > PIXEL ? work_x+PIXEL : target_x;
                        else
                            candidate_x <= work_x-target_x > PIXEL ? work_x-PIXEL : target_x;
                        candidate_y <= work_y; lift_attempt <= 0; phase <= H_SCAN;
                    end
                end
                H_SCAN: scan_body(candidate_x, candidate_y, H_RESULT);
                H_RESULT: begin
                    if (!scan_hit) begin
                        work_x <= candidate_x; work_y <= candidate_y; phase <= H_NEXT;
                    end else begin
                        if (lift_attempt == 0) wall_limit <= wall_contact;
                        if (allow_snap && lift_attempt < STEP_PIXELS) begin
                            candidate_y <= candidate_y-PIXEL;
                            lift_attempt <= lift_attempt+1'b1; phase <= H_SCAN;
                        end else begin
                            // Preserve fractional travel up to the original
                            // wall, even if a later step-up trial hit a ceiling.
                            if (target_x > work_x) begin
                                if ((lift_attempt == 0 ? wall_contact : wall_limit) >= work_x &&
                                    (lift_attempt == 0 ? wall_contact : wall_limit) <= candidate_x)
                                    work_x <= lift_attempt == 0 ? wall_contact : wall_limit;
                            end else begin
                                if ((lift_attempt == 0 ? wall_contact : wall_limit) <= work_x &&
                                    (lift_attempt == 0 ? wall_contact : wall_limit) >= candidate_x)
                                    work_x <= lift_attempt == 0 ? wall_contact : wall_limit;
                            end
                            result_vx <= 0; phase <= V_SETUP;
                        end
                    end
                end
                V_SETUP: begin target_y <= work_y+delta_y; phase <= V_NEXT; end
                V_NEXT: begin
                    if (work_y == target_y) phase <= FINAL_SUPPORT;
                    else begin
                        candidate_x <= work_x;
                        if (target_y > work_y)
                            candidate_y <= target_y-work_y > PIXEL ? work_y+PIXEL : target_y;
                        else
                            candidate_y <= work_y-target_y > PIXEL ? work_y-PIXEL : target_y;
                        phase <= V_SCAN;
                    end
                end
                V_SCAN: scan_body(candidate_x, candidate_y, V_RESULT);
                V_RESULT: begin
                    if (!scan_hit) begin work_y <= candidate_y; phase <= V_NEXT; end
                    else begin
                        if (target_y > work_y) work_y <= floor_contact;
                        else work_y <= ($signed(hit_y)+1)*PIXEL;
                        result_vy <= 0; phase <= FINAL_SUPPORT;
                    end
                end
                FINAL_SUPPORT: begin
                    if (moving_up) phase <= RESPOND;
                    else if (allow_snap)
                        scan_region(work_x >>> 8, (work_x+BODY_FP-1) >>> 8,
                            (work_y+BODY_FP+255) >>> 8,
                            (work_y+BODY_FP+SNAP_PIXELS*PIXEL) >>> 8, FINAL_RESULT);
                    else if (work_y[7:0] == 0)
                        scan_region(work_x >>> 8, (work_x+BODY_FP-1) >>> 8,
                            (work_y+BODY_FP) >>> 8, (work_y+BODY_FP) >>> 8, FINAL_RESULT);
                    else phase <= RESPOND;
                end
                FINAL_RESULT: begin
                    if (scan_hit && floor_contact >= work_y &&
                        floor_contact-work_y <= SNAP_PIXELS*PIXEL) begin
                        support_x <= hit_x; support_y <= hit_y;
                        candidate_x <= work_x; candidate_y <= floor_contact; phase <= SNAP_SCAN;
                    end else phase <= RESPOND;
                end
                SNAP_SCAN: scan_body(candidate_x, candidate_y, SNAP_RESULT);
                SNAP_RESULT: begin
                    if (!scan_hit) begin
                        work_y <= candidate_y; result_ground <= 1; result_vy <= 0;
                        phase <= SLOPE_LEFT;
                    end else phase <= RESPOND;
                end
                // Estimate the exposed floor around the supporting contact,
                // even at rest. Eight pixels of baseline smooth pixel stairs.
                // Missing floors, cliffs and walls must not invent a gradient.
                SLOPE_LEFT: begin
                    if (support_x < 4 || support_x+4 >= $signed({1'b0,saved_width}) ||
                        support_y < 8 || support_y+8 >= $signed({1'b0,saved_height}))
                        phase <= RESPOND;
                    else scan_region(support_x-4, support_x-4,
                        support_y-8, support_y+8, SLOPE_LEFT_RESULT);
                end
                SLOPE_LEFT_RESULT: begin
                    if (scan_hit && hit_y > support_y-8) begin
                        slope_left_y <= hit_y; phase <= SLOPE_RIGHT;
                    end else phase <= RESPOND;
                end
                SLOPE_RIGHT: scan_region(support_x+4, support_x+4,
                    support_y-8, support_y+8, SLOPE_RIGHT_RESULT);
                SLOPE_RIGHT_RESULT: begin
                    // Q4.4 dy/dx: 16 * rise / 8. Steeper than 1:1 is
                    // outside the rolling model, and stays a blocking face.
                    // The measured line must also pass through the actual
                    // contact (one pixel of rounding tolerance). Otherwise an
                    // isolated bump above two lower floors looks like a ramp.
                    if (scan_hit && hit_y > support_y-8 && slope_rise >= -8 && slope_rise <= 8 &&
                        slope_mid_error >= -2 && slope_mid_error <= 2)
                        result_slope <= slope_rise * 2;
                    phase <= RESPOND;
                end
                RESPOND: begin
                    corrected_x <= work_x[`LP_COORD_BITS-1:0];
                    corrected_y <= work_y[`LP_COORD_BITS-1:0];
                    corrected_vx <= result_vx; corrected_vy <= result_vy;
                    grounded <= result_ground; ground_slope <= result_slope;
                    response_valid <= 1; phase <= IDLE;
                end
                ISSUE: phase <= SAMPLE;
                SAMPLE: begin
                    if (scan_inside && solid) begin
                        scan_hit <= 1; hit_x <= scan_x; hit_y <= scan_y; phase <= scan_return;
                    end else if (scan_x == scan_right && scan_y == scan_bottom)
                        phase <= scan_return;
                    else begin
                        if (scan_x == scan_right) begin scan_x <= scan_left; scan_y <= scan_y+1'b1; end
                        else scan_x <= scan_x+1'b1;
                        phase <= ISSUE;
                    end
                end
                default: phase <= IDLE;
            endcase
        end
    end
endmodule

