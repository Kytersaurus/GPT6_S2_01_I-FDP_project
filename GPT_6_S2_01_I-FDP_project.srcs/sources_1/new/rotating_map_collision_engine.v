// Owner: Role 2/3 integration. Terrain-following rotated vehicle collision.
`timescale 1ns / 1ps
`include "game_defs.vh"
module rotating_map_collision_engine (
    input wire clk, reset, move_valid,
    output wire move_ready,
    input wire signed [`LP_COORD_BITS-1:0] previous_x, previous_y, proposed_x, proposed_y,
    input wire signed [3:0] previous_tilt, proposed_tilt,
    input wire signed [15:0] proposed_vx, proposed_vy,
    input wire [9:0] world_width, world_height,
    output wire signed [10:0] query_x, query_y,
    input wire [2:0] query_class,
    output reg response_valid,
    input wire response_ready,
    output reg signed [`LP_COORD_BITS-1:0] corrected_x, corrected_y,
    output reg signed [15:0] corrected_vx, corrected_vy,
    output reg signed [3:0] corrected_tilt,
    output reg grounded,
    output reg signed [7:0] ground_slope
);
    `include "rotation_geometry.vh"
    localparam IDLE=0, OLD_BODY=1, OLD_RESULT=2, OLD_SUPPORT=3, OLD_SUPPORT_RESULT=4,
        TURN=5, TURN_SCAN=6, TURN_RESULT=7, H_NEXT=8, H_SCAN=9, H_RESULT=10,
        V_SETUP=11, V_NEXT=12, V_SCAN=13, V_RESULT=14,
        FINAL_SUPPORT=15, FINAL_SUPPORT_RESULT=16, SNAP=17, SNAP_RESULT=18,
        REFINE=19, REFINE_SCAN=20, REFINE_RESULT=21,
        SLOPE_LEFT=22, SLOPE_LEFT_RESULT=23, SLOPE_RIGHT=24, SLOPE_RIGHT_RESULT=25,
        RESPOND=26, ISSUE=27, SAMPLE=28, PROJECT=29, MASK=30;
    localparam signed [21:0] PIXEL=256, HALF=3072;
    reg [4:0] phase, scan_return, refine_return;
    reg signed [21:0] work_x, work_y, target_x, target_y, delta_y, turn_y;
    reg signed [21:0] candidate_x, candidate_y, safe_pos, blocked_pos, midpoint;
    reg signed [3:0] work_tilt, wanted_tilt, old_tilt;
    reg signed [15:0] result_vx, result_vy;
    reg signed [7:0] result_slope;
    reg moving_up, allow_snap, result_ground, refine_vertical;
    reg [2:0] attempts, snap_attempt;
    // Turning changes the support point as well as height. Compensate for
    // that bounded corner displacement in addition to ordinary 3px following.
    wire [2:0] snap_limit=work_tilt!=old_tilt ? 3'd6 : 3'd3;
    reg [9:0] saved_width, saved_height;

    // Query every pixel intersecting the rotated square. Separating-axis
    // tests include the pixel's area, rather than only its centre, so thin
    // walls cannot leak through tilted edges. ISSUE registers the mask next
    // to the synchronous terrain read; SAMPLE consumes both together.
    reg signed [12:0] scan_left, scan_right, scan_bottom, scan_x, scan_y, hit_x, hit_y;
    reg signed [21:0] scan_pose_x, scan_pose_y;
    reg scan_body_mode, scan_mask, scan_hit;
    wire signed [9:0] cosine=rotation_cos(work_tilt), sine=rotation_sin(work_tilt);
    wire signed [9:0] abs_sine=sine < 0 ? -sine : sine;
    wire signed [10:0] span=cosine+abs_sine;
    // Match the inverse-raster hull, including non-unit coefficient rounding.
    wire signed [21:0] extent=rotation_extent(work_tilt);
    wire signed [22:0] scan_dx=($signed(scan_x)*256)+128-$signed(scan_pose_x)-HALF;
    wire signed [22:0] scan_dy=($signed(scan_y)*256)+128-$signed(scan_pose_y)-HALF;
    // Inside a scan's bounded 35px box, relative positions fit signed 16 bits.
    // Register subtraction, projection and comparison separately at 100 MHz.
    reg signed [15:0] scan_dx_q, scan_dy_q;
    reg signed [27:0] local_u_q, local_v_q;
    wire signed [27:0] projection_limit=28'sd786432+span*128;
    wire occupied=local_u_q < projection_limit && local_u_q > -projection_limit &&
                  local_v_q < projection_limit && local_v_q > -projection_limit &&
                  scan_dx_q < extent+128 && scan_dx_q > -extent-128 &&
                  scan_dy_q < extent+128 && scan_dy_q > -extent-128;
    wire scan_inside=scan_x>=0 && scan_y>=0 && scan_x<$signed({1'b0,saved_width}) &&
                     scan_y<$signed({1'b0,saved_height});
    wire solid=query_class>=`LP_MAP_ROCK && query_class<=`LP_MAP_DARK;
    assign query_x=scan_inside ? scan_x[10:0] : 11'sd0;
    assign query_y=scan_inside ? scan_y[10:0] : 11'sd0;
    assign move_ready=phase==IDLE && !response_valid;

    reg signed [12:0] support_x, support_y, left_floor;
    wire signed [13:0] rise=$signed(hit_y)-$signed(left_floor);
    wire signed [13:0] midpoint_error=$signed(hit_y)+$signed(left_floor)-($signed(support_y)<<<1);

    task scan_region;
        input signed [12:0] left_edge, right_edge, top_edge, bottom_edge;
        input [4:0] return_to;
        begin
            scan_left<=left_edge; scan_right<=right_edge; scan_bottom<=bottom_edge;
            scan_x<=left_edge; scan_y<=top_edge; scan_hit<=0; scan_return<=return_to;
            scan_body_mode<=0; phase<=ISSUE;
        end
    endtask
    task scan_body;
        input signed [21:0] x, y;
        input [4:0] return_to;
        begin
            scan_region((x+HALF-extent)>>>8, (x+HALF+extent-1)>>>8,
                        (y+HALF-extent)>>>8, (y+HALF+extent-1)>>>8, return_to);
            scan_pose_x<=x; scan_pose_y<=y; scan_body_mode<=1;
        end
    endtask
    task refine_axis;
        input vertical;
        input signed [21:0] clear_position, hit_position;
        input [4:0] return_to;
        begin
            refine_vertical<=vertical; safe_pos<=clear_position; blocked_pos<=hit_position;
            refine_return<=return_to; phase<=REFINE;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            phase<=IDLE; response_valid<=0; grounded<=0; ground_slope<=0; corrected_tilt<=0;
            corrected_x<=0; corrected_y<=0; corrected_vx<=0; corrected_vy<=0;
            work_x<=0; work_y<=0; target_x<=0; target_y<=0; delta_y<=0; turn_y<=0;
            candidate_x<=0; candidate_y<=0; safe_pos<=0; blocked_pos<=0; midpoint<=0;
            work_tilt<=0; wanted_tilt<=0; old_tilt<=0; result_vx<=0; result_vy<=0; result_slope<=0;
            moving_up<=0; allow_snap<=0; result_ground<=0; refine_vertical<=0;
            attempts<=0; snap_attempt<=0; saved_width<=0; saved_height<=0;
            scan_left<=0; scan_right<=0; scan_bottom<=0; scan_x<=0; scan_y<=0;
            hit_x<=0; hit_y<=0; scan_pose_x<=0; scan_pose_y<=0;
            scan_body_mode<=0; scan_mask<=0; scan_hit<=0; scan_return<=IDLE; refine_return<=IDLE;
            scan_dx_q<=0; scan_dy_q<=0; local_u_q<=0; local_v_q<=0;
            support_x<=0; support_y<=0; left_floor<=0;
        end else begin
            if (response_valid && response_ready) response_valid<=0;
            case (phase)
                IDLE: if (move_valid && move_ready) begin
                    work_x<=previous_x; work_y<=previous_y; target_x<=proposed_x;
                    delta_y<=$signed(proposed_y)-$signed(previous_y);
                    work_tilt<=sanitize_tilt(previous_tilt); wanted_tilt<=sanitize_tilt(proposed_tilt);
                    old_tilt<=sanitize_tilt(previous_tilt);
                    result_vx<=proposed_vx; result_vy<=proposed_vy;
                    moving_up<=proposed_vy<0 || proposed_y<previous_y;
                    saved_width<=world_width; saved_height<=world_height;
                    result_ground<=0; result_slope<=0; attempts<=0; phase<=OLD_BODY;
                end
                OLD_BODY: scan_body(work_x,work_y,OLD_RESULT);
                OLD_RESULT: begin
                    if (!scan_hit) phase<=OLD_SUPPORT;
                    else if (attempts<3) begin work_y<=work_y-PIXEL; attempts<=attempts+1'b1; phase<=OLD_BODY; end
                    else begin
                        work_y<=work_y+attempts*PIXEL; result_vx<=0; result_vy<=0; phase<=RESPOND;
                    end
                end
                OLD_SUPPORT: scan_body(work_x,work_y+1,OLD_SUPPORT_RESULT);
                OLD_SUPPORT_RESULT: begin allow_snap<=scan_hit && !moving_up; phase<=TURN; end
                TURN: begin
                    if (wanted_tilt==work_tilt) phase<=H_NEXT;
                    else begin
                        turn_y<=work_y; work_tilt<=wanted_tilt; attempts<=0; phase<=TURN_SCAN;
                    end
                end
                TURN_SCAN: scan_body(work_x,work_y,TURN_RESULT);
                TURN_RESULT: begin
                    if (!scan_hit) phase<=H_NEXT;
                    else if (attempts<3) begin work_y<=work_y-PIXEL; attempts<=attempts+1'b1; phase<=TURN_SCAN; end
                    else begin
                        // A nearby wall/roof may block the turn. Retain the
                        // old safe orientation instead of rotating through it.
                        work_tilt<=old_tilt; work_y<=turn_y; phase<=H_NEXT;
                    end
                end
                H_NEXT: begin
                    if (work_x==target_x) phase<=V_SETUP;
                    else begin
                        candidate_x<=target_x>work_x ? (target_x-work_x>PIXEL ? work_x+PIXEL : target_x) :
                                                       (work_x-target_x>PIXEL ? work_x-PIXEL : target_x);
                        candidate_y<=work_y; attempts<=0; phase<=H_SCAN;
                    end
                end
                H_SCAN: scan_body(candidate_x,candidate_y,H_RESULT);
                H_RESULT: begin
                    if (!scan_hit) begin work_x<=candidate_x; work_y<=candidate_y; phase<=H_NEXT; end
                    else if (allow_snap && attempts<3) begin
                        candidate_y<=candidate_y-PIXEL; attempts<=attempts+1'b1; phase<=H_SCAN;
                    end else begin
                        result_vx<=0; refine_axis(0,work_x,candidate_x,V_SETUP);
                    end
                end
                V_SETUP: begin target_y<=work_y+delta_y; phase<=V_NEXT; end
                V_NEXT: begin
                    if (work_y==target_y) phase<=FINAL_SUPPORT;
                    else begin
                        candidate_y<=target_y>work_y ? (target_y-work_y>PIXEL ? work_y+PIXEL : target_y) :
                                                       (work_y-target_y>PIXEL ? work_y-PIXEL : target_y);
                        phase<=V_SCAN;
                    end
                end
                V_SCAN: scan_body(work_x,candidate_y,V_RESULT);
                V_RESULT: begin
                    if (!scan_hit) begin work_y<=candidate_y; phase<=V_NEXT; end
                    else begin result_vy<=0; refine_axis(1,work_y,candidate_y,FINAL_SUPPORT); end
                end
                REFINE: begin
                    // Q12.8 axis bisection ends within 1/256 world pixel.
                    // It replaces flat-edge corrections, which are incorrect
                    // for a tilted hull, and handles either movement sign.
                    if ((blocked_pos>=safe_pos && blocked_pos-safe_pos<=1) ||
                        (blocked_pos<safe_pos && safe_pos-blocked_pos<=1)) begin
                        if (refine_vertical) work_y<=safe_pos; else work_x<=safe_pos;
                        phase<=refine_return;
                    end else begin midpoint<=($signed(safe_pos)+$signed(blocked_pos))>>>1; phase<=REFINE_SCAN; end
                end
                REFINE_SCAN: scan_body(refine_vertical ? work_x : midpoint,
                                       refine_vertical ? midpoint : work_y,REFINE_RESULT);
                REFINE_RESULT: begin
                    if (scan_hit) blocked_pos<=midpoint; else safe_pos<=midpoint;
                    phase<=REFINE;
                end
                FINAL_SUPPORT: begin
                    if (moving_up) phase<=RESPOND;
                    else scan_body(work_x,work_y+1,FINAL_SUPPORT_RESULT);
                end
                FINAL_SUPPORT_RESULT: begin
                    if (scan_hit) begin
                        result_ground<=1; result_vy<=0; support_x<=hit_x; support_y<=hit_y; phase<=SLOPE_LEFT;
                    end else if (allow_snap) begin
                        snap_attempt<=1; safe_pos<=work_y; candidate_y<=work_y+PIXEL+1; phase<=SNAP;
                    end else phase<=RESPOND;
                end
                SNAP: scan_body(work_x,candidate_y,SNAP_RESULT);
                SNAP_RESULT: begin
                    if (scan_hit) begin
                        // Recheck exact support after committing the nearest
                        // clear pose; this also captures the contact to probe.
                        allow_snap<=0; refine_axis(1,safe_pos,candidate_y,FINAL_SUPPORT);
                    end else if (snap_attempt<snap_limit) begin
                        safe_pos<=candidate_y; candidate_y<=candidate_y+PIXEL;
                        snap_attempt<=snap_attempt+1'b1; phase<=SNAP;
                    end else phase<=RESPOND;
                end
                SLOPE_LEFT: begin
                    if (support_x<4 || support_x+4>=$signed({1'b0,saved_width}) || support_y<8 ||
                        support_y+8>=$signed({1'b0,saved_height})) phase<=RESPOND;
                    else scan_region(support_x-4,support_x-4,support_y-8,support_y+8,SLOPE_LEFT_RESULT);
                end
                SLOPE_LEFT_RESULT: begin
                    if (scan_hit && hit_y>support_y-8) begin left_floor<=hit_y; phase<=SLOPE_RIGHT; end
                    else phase<=RESPOND;
                end
                SLOPE_RIGHT: scan_region(support_x+4,support_x+4,support_y-8,support_y+8,SLOPE_RIGHT_RESULT);
                SLOPE_RIGHT_RESULT: begin
                    if (scan_hit && hit_y>support_y-8 && rise>=-8 && rise<=8 && midpoint_error>=-2 && midpoint_error<=2)
                        result_slope<=rise*2;
                    phase<=RESPOND;
                end
                RESPOND: begin
                    corrected_x<=work_x; corrected_y<=work_y; corrected_vx<=result_vx; corrected_vy<=result_vy;
                    corrected_tilt<=work_tilt; grounded<=result_ground; ground_slope<=result_slope;
                    response_valid<=1; phase<=IDLE;
                end
                ISSUE: begin
                    if (scan_body_mode) begin scan_dx_q<=scan_dx; scan_dy_q<=scan_dy; phase<=PROJECT; end
                    else begin scan_mask<=1; phase<=SAMPLE; end
                end
                PROJECT: begin
                    local_u_q<=scan_dx_q*cosine+scan_dy_q*sine;
                    local_v_q<=-scan_dx_q*sine+scan_dy_q*cosine;
                    phase<=MASK;
                end
                MASK: begin scan_mask<=occupied; phase<=SAMPLE; end
                SAMPLE: begin
                    if (scan_inside && scan_mask && solid) begin
                        scan_hit<=1; hit_x<=scan_x; hit_y<=scan_y; phase<=scan_return;
                    end else if (scan_x==scan_right && scan_y==scan_bottom) phase<=scan_return;
                    else begin
                        if (scan_x==scan_right) begin scan_x<=scan_left; scan_y<=scan_y+1'b1; end
                        else scan_x<=scan_x+1'b1;
                        phase<=ISSUE;
                    end
                end
                default: phase<=IDLE;
            endcase
        end
    end
endmodule
