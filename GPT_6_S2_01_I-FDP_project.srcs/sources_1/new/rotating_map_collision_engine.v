// Owner: Role 2/3 integration. Terrain-following rotated vehicle collision.
`timescale 1ns / 1ps
`include "game_defs.vh"
module rotating_map_collision_engine (
    input wire clk, reset, move_valid,
    output wire move_ready,
    input wire signed [`LP_COORD_BITS-1:0] previous_x, previous_y, proposed_x, proposed_y,
    input wire signed [`LP_TILT_BITS-1:0] previous_tilt, proposed_tilt,
    input tri1 [8:0] collision_mask,
    input tri0 cg_enabled,
    input tri0 [26:0] build_grid,
    input tri0 [8:0] part_intact_mask, frame_intact_mask,
    output reg support_unstable,
    input wire signed [15:0] proposed_vx, proposed_vy,
    input wire [9:0] world_width, world_height,
    output wire signed [10:0] query_x, query_y,
    input wire [2:0] query_class,
    output reg response_valid,
    input wire response_ready,
    output reg signed [`LP_COORD_BITS-1:0] corrected_x, corrected_y,
    output reg signed [15:0] corrected_vx, corrected_vy,
    output reg signed [`LP_TILT_BITS-1:0] corrected_tilt,
    output reg grounded,
    output reg signed [7:0] ground_slope,
    // Ground contacts lie on one side of the vertical weight line. CG mode
    // uses surviving part masses; legacy callers use the grid centre.
    // Tip toward the unsupported side (+1 clockwise, -1 anticlockwise).
    output reg signed [1:0] tip_dir
);
    `include "rotation_geometry.vh"
    localparam IDLE=0, OLD_BODY=1, OLD_RESULT=2, OLD_SUPPORT=3, OLD_SUPPORT_RESULT=4,
        TURN=5, TURN_SCAN=6, TURN_RESULT=7, H_NEXT=8, H_SCAN=9, H_RESULT=10,
        V_SETUP=11, V_NEXT=12, V_SCAN=13, V_RESULT=14,
        FINAL_SUPPORT=15, FINAL_SUPPORT_RESULT=16, SNAP=17, SNAP_RESULT=18,
        REFINE=19, REFINE_SCAN=20, REFINE_RESULT=21,
        SLOPE_LEFT=22, SLOPE_LEFT_RESULT=23, SLOPE_RIGHT=24, SLOPE_RIGHT_RESULT=25,
        RESPOND=26, ISSUE=27, SAMPLE=28, PROJECT=29, MASK=30, SPAN=31, SPAN_RESULT=32, CG_CELL=33, CG_ACCUM=34, CG_RESULT=35;
    localparam signed [21:0] PIXEL=256, HALF=3072;
    reg [5:0] phase, scan_return, refine_return;
    reg signed [21:0] work_x, work_y, target_x, target_y, delta_y, turn_y;
    reg signed [21:0] candidate_x, candidate_y, safe_pos, blocked_pos, midpoint;
    reg signed [`LP_TILT_BITS-1:0] work_tilt, wanted_tilt, old_tilt;
    reg signed [15:0] result_vx, result_vy;
    reg signed [7:0] result_slope;
    reg moving_up, allow_snap, result_ground, refine_vertical;
    reg signed [1:0] result_tip;
    // Ground found on both sides of the contact: an even slope or floor, not an edge.
    reg slope_ok;
    reg [2:0] attempts, snap_attempt;
    // Turning changes the support point as well as height. Compensate for
    // that bounded corner displacement in addition to ordinary 3px following.
    wire [2:0] snap_limit=work_tilt!=old_tilt ? 3'd6 : 3'd3;
    reg [9:0] saved_width, saved_height;
    reg [8:0] saved_collision_mask;
    reg saved_cg_enabled;
    reg [26:0] saved_mass_grid;
    reg [8:0] saved_parts, saved_frames;
    reg [2:0] cg_units;
    reg signed [13:0] left_support_arm, right_support_arm;
    reg signed [20:0] cg_sum, left_support_sum, right_support_sum;
    reg [2:0] cell_mass;
    reg [3:0] mask_cell;
    wire [2:0] mass_part = saved_mass_grid >> (mask_cell*3);
    // Identical point masses to the builder. Add once per mass unit in the
    // CG_ACCUM state: sum(m*x) versus mass*support edge, with no division.
    always @* begin
        cell_mass = saved_frames[mask_cell] ? 3'd2 : 3'd0;
        if (saved_parts[mask_cell]) begin
            case (mass_part)
                `LP_PART_PIG, `LP_PART_FAN, `LP_PART_BOOSTER: cell_mass=cell_mass+3'd2;
                `LP_PART_ENGINE: cell_mass=cell_mass+3'd3;
                `LP_PART_WHEEL, `LP_PART_BALLOON: cell_mass=cell_mass+3'd1;
                default: begin end
            endcase
        end
    end


    // Query every pixel intersecting the occupied, rotated 8px cells. Separating-axis
    // tests include the pixel's area, rather than only its centre, so thin
    // walls cannot leak through tilted edges. Hold the terrain address through
    // projection/mask evaluation; SAMPLE consumes the matching terrain read.
    reg signed [12:0] scan_left, scan_right, scan_bottom, scan_x, scan_y, hit_x, hit_y;
    reg signed [21:0] scan_pose_x, scan_pose_y;
    reg scan_body_mode, scan_mask, scan_hit;
    // scan_all keeps scanning after a hit and records the hits' horizontal span.
    reg scan_all;
    reg signed [12:0] hit_min_x, hit_max_x;
    wire signed [9:0] cosine=rotation_cos(work_tilt), sine=rotation_sin(work_tilt);
    wire signed [9:0] abs_sine=sine < 0 ? -sine : sine;
    wire signed [9:0] abs_cosine=cosine < 0 ? -cosine : cosine;
    wire signed [10:0] span=abs_cosine+abs_sine;
    // Match the inverse-raster hull, including non-unit coefficient rounding.
    wire signed [21:0] extent=rotation_extent(work_tilt);
    wire signed [22:0] scan_dx=($signed(scan_x)*256)+128-$signed(scan_pose_x)-HALF;
    wire signed [22:0] scan_dy=($signed(scan_y)*256)+128-$signed(scan_pose_y)-HALF;
    // Inside a scan's bounded 35px box, relative positions fit signed 16 bits.
    // Register subtraction, projection and comparison separately at 100 MHz.
    reg signed [15:0] scan_dx_q, scan_dy_q;
    // Stage the sign inversion before the DSP input. Seventeen bits preserve
    // -(-32768) as well, although the bounded body scan uses far less range.
    reg signed [16:0] scan_neg_dx_q;
    reg signed [27:0] local_u_q, local_v_q;
    reg signed [34:0] pixel_x_numerator, pixel_y_numerator;
    reg signed [34:0] cell_dx_numerator, cell_dy_numerator;
    reg signed [34:0] cell_world_max_q, cell_world_min_q;
    reg signed [27:0] cell_u_min_q, cell_u_max_q, cell_v_min_q, cell_v_max_q;
    reg [1:0] mask_stage;
    wire signed [17:0] basis_norm=rotation_norm_squared(work_tilt);
    wire signed [34:0] cell_world_limit=($signed(span) <<< 18)+($signed(basis_norm) <<< 7);
    // Cell centres are -8,0,+8 local pixels. The common factor 8*65536
    // becomes a shift, so only two shared extra projection products are used.
    wire signed [10:0] centre_u_cos=mask_cell%3==0 ? -cosine : mask_cell%3==2 ? cosine : 11'sd0;
    wire signed [10:0] centre_u_sin=mask_cell%3==0 ? -sine : mask_cell%3==2 ? sine : 11'sd0;
    wire signed [10:0] centre_v_cos=mask_cell<3 ? -cosine : mask_cell>=6 ? cosine : 11'sd0;
    wire signed [10:0] centre_v_sin=mask_cell<3 ? -sine : mask_cell>=6 ? sine : 11'sd0;
    wire signed [11:0] cell_centre_x=centre_u_cos-centre_v_sin;
    wire signed [11:0] cell_centre_y=centre_u_sin+centre_v_cos;
    wire signed [14:0] cg_cell_x=$signed(cell_centre_x) <<< 3;
    wire signed [27:0] pixel_radius=$signed(span)*128;
    wire signed [27:0] cell_u_min=mask_cell%3==0 ? -28'sd786432 : mask_cell%3==1 ? -28'sd262144 : 28'sd262144;
    wire signed [27:0] cell_v_min=mask_cell<3 ? -28'sd786432 : mask_cell<6 ? -28'sd262144 : 28'sd262144;
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
        input [5:0] return_to;
        begin
            scan_left<=left_edge; scan_right<=right_edge; scan_bottom<=bottom_edge;
            scan_x<=left_edge; scan_y<=top_edge; scan_hit<=0; scan_return<=return_to;
            scan_body_mode<=0; scan_all<=0; phase<=ISSUE;
        end
    endtask
    task scan_body;
        input signed [21:0] x, y;
        input [5:0] return_to;
        begin
            scan_region((x+HALF-extent)>>>8, (x+HALF+extent-1)>>>8,
                        (y+HALF-extent)>>>8, (y+HALF+extent-1)>>>8, return_to);
            scan_pose_x<=x; scan_pose_y<=y; scan_body_mode<=1;
        end
    endtask
    task refine_axis;
        input vertical;
        input signed [21:0] clear_position, hit_position;
        input [5:0] return_to;
        begin
            refine_vertical<=vertical; safe_pos<=clear_position; blocked_pos<=hit_position;
            refine_return<=return_to; phase<=REFINE;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            phase<=IDLE; response_valid<=0; grounded<=0; ground_slope<=0; corrected_tilt<=0; tip_dir<=0;
            result_tip<=0; scan_all<=0; hit_min_x<=0; hit_max_x<=0; slope_ok<=0;
            corrected_x<=0; corrected_y<=0; corrected_vx<=0; corrected_vy<=0;
            work_x<=0; work_y<=0; target_x<=0; target_y<=0; delta_y<=0; turn_y<=0;
            candidate_x<=0; candidate_y<=0; safe_pos<=0; blocked_pos<=0; midpoint<=0;
            work_tilt<=0; wanted_tilt<=0; old_tilt<=0; result_vx<=0; result_vy<=0; result_slope<=0;
            moving_up<=0; allow_snap<=0; result_ground<=0; refine_vertical<=0;
            attempts<=0; snap_attempt<=0; saved_width<=0; saved_height<=0;
            scan_left<=0; scan_right<=0; scan_bottom<=0; scan_x<=0; scan_y<=0;
            hit_x<=0; hit_y<=0; scan_pose_x<=0; scan_pose_y<=0;
            scan_body_mode<=0; scan_mask<=0; scan_hit<=0; scan_return<=IDLE; refine_return<=IDLE;
            scan_dx_q<=0; scan_dy_q<=0; scan_neg_dx_q<=0; local_u_q<=0; local_v_q<=0;
            saved_collision_mask<=9'h1ff; pixel_x_numerator<=0; pixel_y_numerator<=0;
            cell_dx_numerator<=0; cell_dy_numerator<=0; mask_cell<=0; mask_stage<=0;
            cell_world_max_q<=0; cell_world_min_q<=0;
            cell_u_min_q<=0; cell_u_max_q<=0; cell_v_min_q<=0; cell_v_max_q<=0;
            support_x<=0; support_y<=0; left_floor<=0;
            saved_cg_enabled<=0; saved_mass_grid<=0; saved_parts<=0; saved_frames<=0;
            cg_units<=0; cg_sum<=0; left_support_sum<=0; right_support_sum<=0;
            left_support_arm<=0; right_support_arm<=0; support_unstable<=0;
        end else begin
            if (response_valid && response_ready) response_valid<=0;
            case (phase)
                IDLE: if (move_valid && move_ready) begin
                    work_x<=previous_x; work_y<=previous_y; target_x<=proposed_x;
                    delta_y<=$signed(proposed_y)-$signed(previous_y);
                    work_tilt<=sanitize_tilt(previous_tilt); wanted_tilt<=sanitize_tilt(proposed_tilt);
                    old_tilt<=sanitize_tilt(previous_tilt);
                    result_vx<=proposed_vx; result_vy<=proposed_vy;
                    // Turning moves the grid origin around its mass centre.
                    // That geometric y shift is not an upward launch. Use vy
                    // during a turn; retain position-only upward requests when
                    // the orientation is unchanged (legacy collision callers).
                    moving_up<=proposed_vy<0 ||
                        (sanitize_tilt(proposed_tilt)==sanitize_tilt(previous_tilt) &&
                         proposed_y<previous_y);
                    saved_width<=world_width; saved_height<=world_height;
                    saved_collision_mask<=collision_mask;
                    saved_cg_enabled<=cg_enabled; saved_mass_grid<=build_grid;
                    saved_parts<=part_intact_mask; saved_frames<=frame_intact_mask;
                    result_ground<=0; result_slope<=0; result_tip<=0; slope_ok<=0; attempts<=0; phase<=OLD_BODY;
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
                    // A grounded body steps up to 6 pixels: Cave Arch is shown at 2x,
                    // so this is the 3 map pixels the original allowance covered.
                    else if (allow_snap && attempts<6) begin
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
                        result_ground<=1; result_vy<=0; support_x<=hit_x; support_y<=hit_y; phase<=SPAN;
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
                SPAN: begin scan_body(work_x,work_y+1,SPAN_RESULT); scan_all<=1; end
                SPAN_RESULT: begin
                    if (saved_cg_enabled && scan_hit) begin
                        // Contact pixels occupy [min, max+1]. One extra pixel
                        // either side prevents quantized terrain from rocking.
                        left_support_arm<= (($signed(hit_min_x)-1) <<< 8)-work_x-HALF;
                        right_support_arm<=(($signed(hit_max_x)+2) <<< 8)-work_x-HALF;
                        cg_sum<=0; left_support_sum<=0; right_support_sum<=0;
                        mask_cell<=0; phase<=CG_CELL;
                    end else begin
                        if (!scan_hit) result_tip<=0;
                        else if (($signed(hit_max_x)+2)*256 <= work_x+HALF) result_tip<=1;
                        else if (($signed(hit_min_x)-1)*256 >= work_x+HALF) result_tip<=-1;
                        phase<=SLOPE_LEFT;
                    end
                end
                CG_CELL: begin cg_units<=cell_mass; phase<=CG_ACCUM; end
                CG_ACCUM: begin
                    if (cg_units!=0) begin
                        cg_sum<=cg_sum+cg_cell_x;
                        left_support_sum<=left_support_sum+left_support_arm;
                        right_support_sum<=right_support_sum+right_support_arm;
                        cg_units<=cg_units-1'b1;
                    end else if (mask_cell==8) phase<=CG_RESULT;
                    else begin mask_cell<=mask_cell+1'b1; phase<=CG_CELL; end
                end
                CG_RESULT: begin
                    // Compare the vertical weight line to the full support
                    // interval. Two separated contacts can safely bridge a gap.
                    if (cg_sum>right_support_sum) result_tip<=1;
                    else if (cg_sum<left_support_sum) result_tip<=-1;
                    else result_tip<=0;
                    phase<=SLOPE_LEFT;
                end
                // The probes look 12 pixels up and down, so a 45 degree slope drawn as the
                // 2-pixel stairs of a 2x map still reads as even ground (a rise of 9 or 10
                // over 8 pixels at some stair phases). Rises past 8 (45 degrees) report the
                // supported maximum gradient.
                SLOPE_LEFT: begin
                    if (support_x<4 || support_x+4>=$signed({1'b0,saved_width}) || support_y<12 ||
                        support_y+12>=$signed({1'b0,saved_height})) phase<=RESPOND;
                    else scan_region(support_x-4,support_x-4,support_y-12,support_y+12,SLOPE_LEFT_RESULT);
                end
                SLOPE_LEFT_RESULT: begin
                    if (scan_hit && hit_y>support_y-12) begin left_floor<=hit_y; phase<=SLOPE_RIGHT; end
                    else phase<=RESPOND;
                end
                SLOPE_RIGHT: scan_region(support_x+4,support_x+4,support_y-12,support_y+12,SLOPE_RIGHT_RESULT);
                SLOPE_RIGHT_RESULT: begin
                    if (scan_hit && hit_y>support_y-12 && rise>=-12 && rise<=12 && midpoint_error>=-2 && midpoint_error<=2) begin
                        result_slope<=rise>8 ? 8'sd16 : rise<-8 ? -8'sd16 : rise*2; slope_ok<=1;
                    end
                    phase<=RESPOND;
                end
                RESPOND: begin
                    corrected_x<=work_x; corrected_y<=work_y; corrected_vx<=result_vx; corrected_vy<=result_vy;
                    corrected_tilt<=work_tilt; grounded<=result_ground; ground_slope<=result_slope; tip_dir<=(saved_cg_enabled || !slope_ok) ? result_tip : 2'sd0;
                    support_unstable<=saved_cg_enabled && result_ground && result_tip!=0;
                    response_valid<=1; phase<=IDLE;
                end
                ISSUE: begin
                    if (scan_body_mode) begin
                        scan_dx_q<=scan_dx; scan_dy_q<=scan_dy;
                        scan_neg_dx_q<=-$signed(scan_dx[15:0]); phase<=PROJECT;
                    end
                    else begin scan_mask<=1; phase<=SAMPLE; end
                end
                PROJECT: begin
                    local_u_q<=scan_dx_q*cosine+scan_dy_q*sine;
                    local_v_q<=scan_neg_dx_q*sine+scan_dy_q*cosine;
                    pixel_x_numerator<=scan_dx_q*basis_norm;
                    pixel_y_numerator<=scan_dy_q*basis_norm;
                    cell_world_max_q<=cell_world_limit; cell_world_min_q<=-cell_world_limit;
                    mask_cell<=0; mask_stage<=0; scan_mask<=0;
                    phase<=MASK;
                end
                MASK: begin
                    if (mask_stage==0) begin
                        if (saved_collision_mask==9'h1ff) begin scan_mask<=occupied; phase<=SAMPLE; end
                        else if (!occupied || saved_collision_mask==0) phase<=SAMPLE;
                        else mask_stage<=1;
                    end else if (mask_stage==1) begin
                        if (saved_collision_mask[mask_cell]) begin
                            // Register cell bounds separately from comparisons:
                            // a long overlap test must not drive a DSP enable.
                            cell_u_min_q<=cell_u_min-pixel_radius;
                            cell_u_max_q<=cell_u_min+28'sd524288+pixel_radius;
                            cell_v_min_q<=cell_v_min-pixel_radius;
                            cell_v_max_q<=cell_v_min+28'sd524288+pixel_radius;
                            cell_dx_numerator<=pixel_x_numerator-($signed(cell_centre_x) <<< 19);
                            cell_dy_numerator<=pixel_y_numerator-($signed(cell_centre_y) <<< 19);
                            mask_stage<=2;
                        end else if (mask_cell==8) phase<=SAMPLE;
                        else mask_cell<=mask_cell+1'b1;
                    end else begin
                        // Four SAT axes for the actual occupied 8x8 cell.
                        // Empty grid cells never stop motion or create support.
                        if (local_u_q>cell_u_min_q && local_u_q<cell_u_max_q &&
                            local_v_q>cell_v_min_q && local_v_q<cell_v_max_q &&
                            cell_dx_numerator<cell_world_max_q && cell_dx_numerator>cell_world_min_q &&
                            cell_dy_numerator<cell_world_max_q && cell_dy_numerator>cell_world_min_q) begin
                            scan_mask<=1; phase<=SAMPLE;
                        end else begin
                            mask_stage<=1;
                            if (mask_cell==8) phase<=SAMPLE;
                            else mask_cell<=mask_cell+1'b1;
                        end
                    end
                end
                SAMPLE: begin
                    if (scan_inside && scan_mask && solid && !scan_all) begin
                        scan_hit<=1; hit_x<=scan_x; hit_y<=scan_y; phase<=scan_return;
                    end else if (scan_x==scan_right && scan_y==scan_bottom) begin
                        if (scan_inside && scan_mask && solid) begin
                            scan_hit<=1;
                            if (!scan_hit || scan_x<hit_min_x) hit_min_x<=scan_x;
                            if (!scan_hit || scan_x>hit_max_x) hit_max_x<=scan_x;
                        end
                        phase<=scan_return;
                    end
                    else begin
                        if (scan_inside && scan_mask && solid) begin
                            scan_hit<=1;
                            if (!scan_hit || scan_x<hit_min_x) hit_min_x<=scan_x;
                            if (!scan_hit || scan_x>hit_max_x) hit_max_x<=scan_x;
                        end
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
