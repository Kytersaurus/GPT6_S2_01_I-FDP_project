// Build storage, damage state and part properties.
`timescale 1ns / 1ps
`include "game_defs.vh"

// Frames and cell contents are stored separately: a frame can contain one pig or engine.
// Remaining stock is derived from the saved build, so damage never refunds it.
module vehicle_builder #(
    parameter integer FRAME_LIMIT = 5,
    parameter integer PIG_LIMIT = 1,
    parameter integer WHEEL_LIMIT = 2,
    parameter integer ENGINE_LIMIT = 1,
    parameter integer BALLOON_LIMIT = 2,
    parameter integer ROCKET_LIMIT = 1,
    parameter integer FAN_LIMIT = 1,
    parameter integer FEEDBACK_CYCLES = 100000000
) (
    input wire clk,
    input wire reset,
    input wire [2:0] game_state,
    input tri0 [1:0] level_index,
    input wire run_init,
    output reg init_ready,
    input wire edit_valid,
    input wire [1:0] edit_op,
    input wire [3:0] edit_cell,
    input wire [3:0] edit_source,
    input wire [2:0] edit_part,
    input wire edit_facing_left,
    tri0 edit_facing_down,
    input wire damage_valid,
    output wire damage_ready,
    input wire [8:0] damage_mask,
    input wire [8:0] damage_frame_mask,
    output reg [26:0] build_grid,
    output reg [8:0] build_frames,
    output reg [8:0] build_facing_left,
    output reg [8:0] build_facing_down,
    output reg signed [4:0] engine_balance,
    output reg signed [4:0] fan_balance,
    output reg signed [4:0] rocket_balance,
    output reg [3:0] rocket_count,
    output reg [3:0] fan_count,
    output reg [3:0] rockets_left,
    output reg [3:0] fans_left,
    output wire [8:0] intact_mask,
    output wire [8:0] frame_intact_mask,
    output reg build_valid,
    output reg [3:0] build_error,
    output reg [2:0] feedback_code,
    output reg [3:0] feedback_cell,
    output reg pig_alive,
    output reg [3:0] wheel_count,
    output reg [3:0] engine_count,
    output reg [3:0] balloon_count,
    // Intact wheels by the side they touch: a frame above hangs the wheel under
    // the body (down); a frame below sets it on top (up). A middle-row wheel
    // between two frames counts on both sides.
    output reg [3:0] wheels_down,
    output reg [3:0] wheels_up,
    output reg [3:0] frames_left,
    output reg [3:0] pigs_left,
    output reg [3:0] wheels_left,
    output reg [3:0] engines_left,
    output reg [3:0] balloons_left,
    output reg [7:0] mass_units
);
    reg [8:0] content_mask;
    reg [8:0] pig_cell_mask;
    reg [8:0] runtime_intact;
    reg [8:0] runtime_frames;
    integer mask_index;
    integer damage_index;
    reg [8:0] safe_damage_mask;
    reg [8:0] safe_damage_frame_mask;

    // BUILD always shows the saved construction. Only RUN needs stored damage.
    assign intact_mask = game_state == `LP_BUILD ? content_mask : runtime_intact;
    assign frame_intact_mask = game_state == `LP_BUILD ? build_frames : runtime_frames;

    always @ (*) begin
        content_mask = 0;
        pig_cell_mask = 0;
        for (mask_index = 0; mask_index < 9; mask_index = mask_index + 1) begin
            content_mask[mask_index] = (build_grid[mask_index*3 +: 3] != `LP_PART_EMPTY);
            pig_cell_mask[mask_index] = (build_grid[mask_index*3 +: 3] == `LP_PART_PIG);
        end
    end

    // If the pig's own wood frame breaks during a blast/fall, detach the rest
    // of the chassis so the bare pig pops out cleanly. Also auto-detach any
    // wheel, balloon, fan or rocket whose supporting frame was destroyed.
    wire pig_frame_broken = ((damage_frame_mask & pig_cell_mask) != 9'd0);
    wire [8:0] next_frames = pig_frame_broken ? 9'd0 : (runtime_frames & ~damage_frame_mask);
    wire [8:0] next_frame_left  = (next_frames & 9'b011011011) << 1;
    wire [8:0] next_frame_right = (next_frames & 9'b110110110) >> 1;
    wire [8:0] next_frame_above = (next_frames << 3) & 9'h1ff;
    wire [8:0] next_frame_below = next_frames >> 3;
    wire [8:0] next_wheel_support = next_frame_above | next_frame_below | next_frame_left | next_frame_right;

    // All runtime damage sources share this final safety gate. Protecting the
    // pig here prevents a future damage source from accidentally bypassing the
    // TNT rule, while allowing its wooden frame and any non-pig part in a
    // destroyed frame cell to break away.
    always @ (*) begin
        safe_damage_frame_mask = pig_frame_broken ? 9'h1ff : damage_frame_mask;
        safe_damage_mask = damage_mask | safe_damage_frame_mask;
        for (damage_index = 0; damage_index < 9; damage_index = damage_index + 1) begin
            case (build_grid[damage_index*`LP_PART_BITS +: `LP_PART_BITS])
                `LP_PART_PIG: begin
                    safe_damage_mask[damage_index] = 1'b0;
                end
                `LP_PART_BALLOON: begin
                    if (!next_frame_below[damage_index]) begin
                        safe_damage_mask[damage_index] = 1'b1;
                    end
                end
                `LP_PART_WHEEL, `LP_PART_BOOSTER, `LP_PART_FAN: begin
                    if (!next_wheel_support[damage_index]) begin
                        safe_damage_mask[damage_index] = 1'b1;
                    end
                end
                default: begin end
            endcase
        end
    end

    reg placement_valid;
    reg stock_valid;
    reg [3:0] cell_usable_directions;
    integer index;
    reg [3:0] saved_frames;
    reg [3:0] saved_pigs;
    reg [3:0] saved_wheels;
    reg [3:0] saved_engines;
    reg [3:0] saved_balloons;
    reg [3:0] saved_rockets;
    reg [3:0] saved_fans;
    reg [3:0] saved_tnts;
    reg [3:0] tnts_left;
    reg has_frame_stock;
    reg has_pig_stock;
    reg has_wheel_stock;
    reg has_engine_stock;
    reg has_balloon_stock;
    reg has_rocket_stock;
    reg has_fan_stock;
    reg has_tnt_stock;
    reg [2:0] part;
    reg [2:0] edit_result;
    reg [2:0] source_part;
    reg [31:0] feedback_count;

    assign damage_ready = (game_state == `LP_RUN) && !run_init;
    wire [3:0] active_fan_limit = (level_index == `LP_LEVEL_FLIGHT) ? (FAN_LIMIT[3:0] + 4'd1) : FAN_LIMIT[3:0];
    wire [3:0] active_rocket_limit = (level_index == `LP_LEVEL_FLIGHT) ? (ROCKET_LIMIT[3:0] + 4'd1) : ROCKET_LIMIT[3:0];

    // Shift the frame layer by one row or column in either direction; no edge wraps.
    wire [8:0] frame_left = (build_frames & 9'b011011011) << 1;
    wire [8:0] frame_right = (build_frames & 9'b110110110) >> 1;
    wire [8:0] frame_above = (build_frames << 3) & 9'h1ff;
    wire [8:0] frame_below = build_frames >> 3;
    wire [8:0] side_support = frame_left | frame_right;
    wire [8:0] wheel_support = frame_above | frame_below | side_support;

    // Rocket and fan directions depend on their supporting frames:
    // a direction {facing_down, facing_left} is usable when the cell touches at least
    // one supporting frame (wheel_support) and is not pointing directly into an adjacent
    // wood frame (~frame_right / ~frame_left / ~frame_above / ~frame_below).
    // Adjacent loose parts (wheels, balloons, second fans/rockets) never block placement.
    wire [8:0] can_point_right = wheel_support & ~frame_right;
    wire [8:0] can_point_left  = wheel_support & ~frame_left;
    wire [8:0] can_point_up    = wheel_support & ~frame_above;
    wire [8:0] can_point_down  = wheel_support & ~frame_below;
    // Each fan points away from the frame it mounts to: straight down under a frame,
    // straight up on top of a frame, or sideways when touching a side frame.
    wire [8:0] fan_hangs_under_frame = frame_above & ~frame_below & ~side_support;
    wire [8:0] fan_sits_on_frame     = frame_below & ~frame_above & ~side_support;
    wire [8:0] fan_can_point_right   = side_support & ~frame_right;
    wire [8:0] fan_can_point_left    = side_support & ~frame_left;

    // Usable directions of one cell, indexed by {facing_down, facing_left}.
    // Rockets: 0 right, 1 left, 2 up, 3 down. Fans: 0 right, 1 left, 2 down, 3 up.
    function [3:0] usable_directions;
        input [2:0] mounted_kind;
        input [3:0] part_cell;
        begin
            if (mounted_kind == `LP_PART_FAN) begin
                usable_directions[0] = fan_can_point_right[part_cell];
                usable_directions[1] = fan_can_point_left[part_cell];
                usable_directions[2] = fan_hangs_under_frame[part_cell];
                usable_directions[3] = fan_sits_on_frame[part_cell];
            end else begin
                usable_directions[0] = can_point_right[part_cell];
                usable_directions[1] = can_point_left[part_cell];
                usable_directions[2] = can_point_up[part_cell];
                usable_directions[3] = can_point_down[part_cell];
            end
        end
    endfunction

    // First usable direction at or after the requested one, in cycling order.
    // Returns the request unchanged when nothing is usable.
    function [1:0] resolve_direction;
        input [1:0] requested;
        input [3:0] usable;
        begin
            if (usable[requested]) begin
                resolve_direction = requested;
            end else if (usable[requested + 2'd1]) begin
                resolve_direction = requested + 2'd1;
            end else if (usable[requested + 2'd2]) begin
                resolve_direction = requested + 2'd2;
            end else if (usable[requested + 2'd3]) begin
                resolve_direction = requested + 2'd3;
            end else begin
                resolve_direction = requested;
            end
        end
    endfunction

    function is_mounted_part;
        input [2:0] candidate;
        begin
            is_mounted_part = (candidate == `LP_PART_BOOSTER || candidate == `LP_PART_FAN);
        end
    endfunction

    // An edit is resolved immediately. Otherwise one cell per clock is re-checked,
    // so a frame being added or removed turns the part to a usable direction.
    reg [3:0] mount_scan_cell;
    reg tutorial_seeded;
    wire resolving_edit = edit_valid && edit_cell < 9;
    wire [2:0] scan_part = build_grid[mount_scan_cell*3 +: 3];
    // The edit and the scan each have their own lookup: this is the design's tightest 100 MHz
    // path, and a shared lookup would add a mux level in front of both.
    wire [3:0] edit_usable = usable_directions(edit_part, edit_cell);
    wire [3:0] scan_usable = usable_directions(scan_part, mount_scan_cell);
    wire clean_facing_down = (edit_facing_down === 1'b1);
    wire clean_facing_left = (edit_facing_left === 1'b1);
    wire [1:0] edit_direction = resolve_direction({clean_facing_down, clean_facing_left}, edit_usable);
    wire [1:0] scan_direction = {build_facing_down[mount_scan_cell], build_facing_left[mount_scan_cell]};
    wire [1:0] scan_resolved = resolve_direction(scan_direction, scan_usable);
    wire edit_cell_changes_direction = edit_direction !=
        {build_facing_down[edit_cell], build_facing_left[edit_cell]};
    wire edit_cell_can_mount = |edit_usable;

    // Decide once: this result controls both editing and the on-screen feedback.
    // Repeating the same placement or removing an empty cell is a quiet no-op.
    always @ (*) begin
        edit_result = `LP_FEEDBACK_NONE;
        source_part = `LP_PART_EMPTY;
        if (edit_source < 9) begin
            source_part = build_grid[edit_source*3 +: 3];
        end
        if (game_state == `LP_BUILD && !run_init && edit_valid && edit_cell < 9 &&
            level_index != `LP_LEVEL_TUTORIAL) begin
            case (edit_op)
                `LP_EDIT_PLACE: begin
                    case (edit_part)
                        `LP_PART_FRAME: begin
                            if (clean_facing_down) begin
                                if (build_grid[edit_cell*3 +: 3] == `LP_PART_FRAME) begin
                                    edit_result = `LP_FEEDBACK_NONE;
                                end else if (!build_frames[edit_cell]) begin
                                    edit_result = `LP_FEEDBACK_NEED_FRAME;
                                end else if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                    edit_result = `LP_FEEDBACK_OCCUPIED;
                                end else if (!has_tnt_stock) begin
                                    edit_result = `LP_FEEDBACK_NO_STOCK;
                                end else begin
                                    edit_result = `LP_FEEDBACK_PLACED;
                                end
                            end else begin
                                if (build_frames[edit_cell]) begin
                                    edit_result = `LP_FEEDBACK_NONE;
                                end else if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                    edit_result = `LP_FEEDBACK_OCCUPIED;
                                end else if (!has_frame_stock) begin
                                    edit_result = `LP_FEEDBACK_NO_STOCK;
                                end else begin
                                    edit_result = `LP_FEEDBACK_PLACED;
                                end
                            end
                        end
                        `LP_PART_PIG, `LP_PART_ENGINE: begin
                            if (build_grid[edit_cell*3 +: 3] == edit_part) begin
                                edit_result = (edit_part == `LP_PART_ENGINE &&
                                               build_facing_left[edit_cell] != edit_facing_left) ?
                                              `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NONE;
                            end else if (!build_frames[edit_cell]) begin
                                edit_result = `LP_FEEDBACK_NEED_FRAME;
                            end else if ((edit_part == `LP_PART_PIG && !has_pig_stock) ||
                                         (edit_part == `LP_PART_ENGINE && !has_engine_stock)) begin
                                edit_result = `LP_FEEDBACK_NO_STOCK;
                            end else begin
                                edit_result = `LP_FEEDBACK_PLACED;
                            end
                        end
                        `LP_PART_WHEEL: begin
                            if (build_grid[edit_cell*3 +: 3] == edit_part) begin
                                edit_result = `LP_FEEDBACK_NONE;
                            end else if (build_frames[edit_cell] || build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                edit_result = `LP_FEEDBACK_OCCUPIED;
                            end else if (!wheel_support[edit_cell]) begin
                                edit_result = `LP_FEEDBACK_FRAME_ABOVE;
                            end else if (!has_wheel_stock) begin
                                edit_result = `LP_FEEDBACK_NO_STOCK;
                            end else begin
                                edit_result = `LP_FEEDBACK_PLACED;
                            end
                        end
                        `LP_PART_BALLOON: begin
                            if (build_grid[edit_cell*3 +: 3] == edit_part) begin
                                edit_result = `LP_FEEDBACK_NONE;
                            end else if (build_frames[edit_cell] || build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                edit_result = `LP_FEEDBACK_OCCUPIED;
                            end else if (edit_cell >= 6) begin
                                edit_result = `LP_FEEDBACK_FRAME_BELOW;
                            end else if (!build_frames[edit_cell+3]) begin
                                edit_result = `LP_FEEDBACK_FRAME_BELOW;
                            end else if (!has_balloon_stock) begin
                                edit_result = `LP_FEEDBACK_NO_STOCK;
                            end else begin
                                edit_result = `LP_FEEDBACK_PLACED;
                            end
                        end
                        `LP_PART_BOOSTER, `LP_PART_FAN: begin
                            // Re-placing onto itself is a rotation. When wheels or
                            // frames leave only one usable direction it stays quiet.
                            if (build_grid[edit_cell*3 +: 3] == edit_part) begin
                                edit_result = edit_cell_changes_direction ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NONE;
                            end else if (build_frames[edit_cell] || build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                edit_result = `LP_FEEDBACK_OCCUPIED;
                            end else if (!edit_cell_can_mount) begin
                                edit_result = `LP_FEEDBACK_NEED_FRAME;
                            end else if (!(edit_part == `LP_PART_BOOSTER ? has_rocket_stock : has_fan_stock)) begin
                                edit_result = `LP_FEEDBACK_NO_STOCK;
                            end else begin
                                edit_result = `LP_FEEDBACK_PLACED;
                            end
                        end
                        default: begin end
                    endcase
                end
                `LP_EDIT_REMOVE: begin
                    if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY || build_frames[edit_cell]) begin
                        edit_result = `LP_FEEDBACK_REMOVED;
                    end
                end
                `LP_EDIT_MOVE: begin
                    if (edit_source < 9 && edit_source != edit_cell) begin
                        if (edit_part == `LP_PART_FRAME && build_frames[edit_source] && source_part == `LP_PART_EMPTY) begin
                            if (build_frames[edit_cell] || build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                edit_result = `LP_FEEDBACK_OCCUPIED;
                            end else begin
                                edit_result = `LP_FEEDBACK_PLACED;
                            end
                        end else if (source_part == edit_part && source_part != `LP_PART_EMPTY) begin
                            if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                edit_result = `LP_FEEDBACK_OCCUPIED;
                            end else begin
                                case (edit_part)
                                    `LP_PART_FRAME, `LP_PART_PIG, `LP_PART_ENGINE: begin
                                        edit_result = build_frames[edit_cell] ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NEED_FRAME;
                                    end
                                    `LP_PART_WHEEL: begin
                                        if (build_frames[edit_cell]) begin
                                            edit_result = `LP_FEEDBACK_OCCUPIED;
                                        end else begin
                                            edit_result = wheel_support[edit_cell] ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_FRAME_ABOVE;
                                        end
                                    end
                                    `LP_PART_BALLOON: begin
                                        if (build_frames[edit_cell]) begin
                                            edit_result = `LP_FEEDBACK_OCCUPIED;
                                        end else if (edit_cell >= 6) begin
                                            edit_result = `LP_FEEDBACK_FRAME_BELOW;
                                        end else begin
                                            edit_result = build_frames[edit_cell+3] ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_FRAME_BELOW;
                                        end
                                    end
                                    `LP_PART_BOOSTER, `LP_PART_FAN: begin
                                        if (build_frames[edit_cell]) begin
                                            edit_result = `LP_FEEDBACK_OCCUPIED;
                                        end else begin
                                            edit_result = edit_cell_can_mount ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NEED_FRAME;
                                        end
                                    end
                                    default: begin end
                                endcase
                            end
                        end
                    end
                end
                `LP_EDIT_RETURN: begin
                    if (edit_source < 9 &&
                        ((edit_part == `LP_PART_FRAME && build_frames[edit_source] && source_part == `LP_PART_EMPTY) ||
                         (edit_part == source_part && source_part != `LP_PART_EMPTY))) begin
                        edit_result = `LP_FEEDBACK_REMOVED;
                    end
                end
                default: begin end
            endcase
        end
    end

    always @ (posedge clk) begin
        if (reset) begin
            // Start empty; retry still restores the player's saved construction.
            build_grid <= 0;
            build_frames <= 0;
            build_facing_left <= 0;
            build_facing_down <= 0;
            runtime_intact <= 0;
            runtime_frames <= 0;
            init_ready <= 0;
            mount_scan_cell <= 0;
            has_frame_stock   <= (FRAME_LIMIT > 0);
            has_pig_stock     <= (PIG_LIMIT > 0);
            has_wheel_stock   <= (WHEEL_LIMIT > 0);
            has_engine_stock  <= (ENGINE_LIMIT > 0);
            has_balloon_stock <= (BALLOON_LIMIT > 0);
            has_rocket_stock  <= (ROCKET_LIMIT > 0);
            has_fan_stock     <= (FAN_LIMIT > 0);
            has_tnt_stock     <= 1'b1;
            tutorial_seeded <= 0;
            feedback_code <= `LP_FEEDBACK_NONE;
            feedback_cell <= 0;
            feedback_count <= 0;
        end else begin
            has_frame_stock   <= (frames_left != 4'd0);
            has_pig_stock     <= (pigs_left != 4'd0);
            has_wheel_stock   <= (wheels_left != 4'd0);
            has_engine_stock  <= (engines_left != 4'd0);
            has_balloon_stock <= (balloons_left != 4'd0);
            has_rocket_stock  <= (rockets_left != 4'd0);
            has_fan_stock     <= (fans_left != 4'd0);
            has_tnt_stock     <= (tnts_left != 4'd0);

            if (game_state != `LP_BUILD || run_init) begin
                feedback_code <= `LP_FEEDBACK_NONE;
                feedback_count <= 0;
            end else if (edit_result != `LP_FEEDBACK_NONE) begin
                feedback_code <= edit_result;
                feedback_cell <= edit_cell;
                feedback_count <= 0;
            end else if (feedback_code != `LP_FEEDBACK_NONE) begin
                if (feedback_count == FEEDBACK_CYCLES-1) begin
                    feedback_code <= `LP_FEEDBACK_NONE;
                    feedback_count <= 0;
                end else begin
                    feedback_count <= feedback_count + 1'b1;
                end
            end

            if (!run_init) begin
                init_ready <= 0;
            end
            if (run_init && !init_ready) begin
                // Retry restores both layers of the saved build.
                runtime_intact <= content_mask;
                runtime_frames <= build_frames;
                init_ready <= 1;
            end else if (level_index != `LP_LEVEL_TUTORIAL && tutorial_seeded) begin
                // Reset the pre-built tutorial contraption when leaving the
                // tutorial for an actual map so the player starts fresh.
                build_grid <= 0;
                build_frames <= 0;
                build_facing_left <= 0;
                build_facing_down <= 0;
                runtime_intact <= 0;
                runtime_frames <= 0;
                tutorial_seeded <= 1'b0;
            end else if (game_state == `LP_BUILD && level_index == `LP_LEVEL_TUTORIAL &&
                         !tutorial_seeded) begin
                // Give Play a usable vehicle immediately. The normal builder
                // and run controls are still used, so the player can inspect
                // and edit it after learning each control.
                // Cells: balloon, rocket, empty / engine, pig, empty /
                //        wheel, fan, wheel. Frames support the middle row.
                // The rocket points up for the TNT-clearing lesson and the
                // fan points down. Physics gives this tutorial rocket a
                // short burn, so it hops over the crate instead of leaving
                // through the top bound.
                build_grid <= {
                    `LP_PART_WHEEL, `LP_PART_FAN, `LP_PART_WHEEL,
                    `LP_PART_EMPTY, `LP_PART_PIG, `LP_PART_ENGINE,
                    `LP_PART_EMPTY, `LP_PART_BOOSTER, `LP_PART_BALLOON
                };
                build_frames <= 9'b000111000;
                // Rocket is cell 1: facing_down=1, facing_left=0 means up.
                // Fan is cell 7: facing_down=1 means downward lift.
                build_facing_left <= 9'b000000000;
                // Bits 7 and 1 are the fan and upward rocket respectively.
                build_facing_down <= 9'b010000010;
                tutorial_seeded <= 1'b1;
            end else if (game_state == `LP_BUILD) begin
                // The BUILD outputs follow the saved layers directly.
                // Keep a restored runtime copy ready for the next launch.
                runtime_intact <= content_mask;
                runtime_frames <= build_frames;
                // Keep every rocket and fan pointing somewhere usable as its
                // neighbours change. With no usable direction the part stays put
                // and the build reports the usual attachment error.
                if (!resolving_edit) begin
                    mount_scan_cell <= (mount_scan_cell >= 4'd8) ? 4'd0 : mount_scan_cell + 4'd1;
                    if (is_mounted_part(scan_part) && scan_resolved != scan_direction) begin
                        build_facing_down[mount_scan_cell] <= scan_resolved[1];
                        build_facing_left[mount_scan_cell] <= scan_resolved[0];
                    end
                end
                if (edit_result == `LP_FEEDBACK_PLACED) begin
                    if (edit_op == `LP_EDIT_MOVE) begin
                        // Source and destination change on the same edge; stock is unchanged.
                        // Copy the source direction and point mount_scan_cell at edit_cell so
                        // any blocked direction is resolved on the next clock without adding a
                        // 9-to-1 source mux in front of resolve_direction.
                        build_grid[edit_source*3 +: 3] <= `LP_PART_EMPTY;
                        build_grid[edit_cell*3 +: 3] <= source_part;
                        build_facing_left[edit_source] <= 0;
                        build_facing_down[edit_source] <= 0;
                        build_facing_left[edit_cell] <= build_facing_left[edit_source];
                        build_facing_down[edit_cell] <= build_facing_down[edit_source];
                        mount_scan_cell <= edit_cell;
                        if (edit_part == `LP_PART_FRAME && source_part == `LP_PART_EMPTY) begin
                            build_frames[edit_source] <= 0;
                            build_frames[edit_cell] <= 1;
                        end
                    end else if (edit_part == `LP_PART_FRAME && !clean_facing_down) begin
                        build_frames[edit_cell] <= 1'b1;
                    end else begin
                        // [start +: 3] selects one cell's three content bits.
                        build_grid[edit_cell*3 +: 3] <= edit_part;
                        if (is_mounted_part(edit_part)) begin
                            build_facing_down[edit_cell] <= edit_direction[1];
                            build_facing_left[edit_cell] <= edit_direction[0];
                        end else begin
                            build_facing_down[edit_cell] <= 1'b0;
                            build_facing_left[edit_cell] <= (edit_part == `LP_PART_ENGINE) && edit_facing_left;
                        end
                    end
                end else if (edit_result == `LP_FEEDBACK_REMOVED) begin
                    if (edit_op == `LP_EDIT_RETURN) begin
                        build_grid[edit_source*3 +: 3] <= `LP_PART_EMPTY;
                        build_facing_left[edit_source] <= 0;
                        build_facing_down[edit_source] <= 0;
                        if (edit_part == `LP_PART_FRAME && source_part == `LP_PART_EMPTY) begin
                            build_frames[edit_source] <= 0;
                        end
                    // Right click removes contents first, then the empty frame.
                    end else if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                        build_grid[edit_cell*3 +: 3] <= `LP_PART_EMPTY;
                        build_facing_left[edit_cell] <= 0;
                        build_facing_down[edit_cell] <= 0;
                    end else begin
                        build_frames[edit_cell] <= 1'b0;
                    end
                end
            end else if (damage_valid && damage_ready) begin
                runtime_intact <= runtime_intact & ~safe_damage_mask;
                runtime_frames <= runtime_frames & ~safe_damage_frame_mask;
            end
        end
    end

    always @ (*) begin
        wheel_count = 0;
        engine_count = 0;
        balloon_count = 0;
        wheels_down = 0;
        wheels_up = 0;
        rocket_count = 0;
        fan_count = 0;
        engine_balance = 0;
        fan_balance = 0;
        rocket_balance = 0;
        mass_units = 0;
        pig_alive = 0;
        part = 0;
        saved_frames = 0;
        saved_pigs = 0;
        saved_wheels = 0;
        saved_engines = 0;
        saved_balloons = 0;
        saved_rockets = 0;
        saved_fans = 0;
        saved_tnts = 0;
        placement_valid = 1;
        for (index = 0; index < 9; index = index + 1) begin
            part = build_grid[index*3 +: 3];
            if (part == `LP_PART_PIG) begin
                saved_pigs = saved_pigs + 4'd1;
            end
            if (build_frames[index]) begin
                saved_frames = saved_frames + 4'd1;
            end
            if (part == `LP_PART_FRAME) begin
                saved_tnts = saved_tnts + 4'd1;
            end
            if (part == `LP_PART_WHEEL) begin
                saved_wheels = saved_wheels + 4'd1;
            end
            if (part == `LP_PART_ENGINE) begin
                saved_engines = saved_engines + 4'd1;
            end
            if (part == `LP_PART_BALLOON) begin
                saved_balloons = saved_balloons + 4'd1;
            end
            if (part == `LP_PART_BOOSTER) begin
                saved_rockets = saved_rockets + 4'd1;
            end
            if (part == `LP_PART_FAN) begin
                saved_fans = saved_fans + 4'd1;
            end

            // Construction validity uses the saved build, even after runtime damage.
            case (part)
                `LP_PART_EMPTY: begin end
                `LP_PART_FRAME, `LP_PART_PIG, `LP_PART_ENGINE: begin
                    if (!build_frames[index]) begin
                        placement_valid = 0;
                    end
                end
                `LP_PART_WHEEL: begin
                    if (build_frames[index] || !wheel_support[index]) begin
                        placement_valid = 0;
                    end
                end
                `LP_PART_BALLOON: begin
                    if (build_frames[index] || index >= 6) begin
                        placement_valid = 0;
                    end else if (!build_frames[index+3]) begin
                        placement_valid = 0;
                    end
                end
                `LP_PART_BOOSTER, `LP_PART_FAN: begin
                    cell_usable_directions = usable_directions(part, index[3:0]);
                    if (build_frames[index] ||
                        !cell_usable_directions[{build_facing_down[index], build_facing_left[index]}]) begin
                        placement_valid = 0;
                    end
                end
                default: begin
                    placement_valid = 0;
                end
            endcase

            // A frame and its contents both contribute to mass while intact.
            if (frame_intact_mask[index]) begin
                mass_units = mass_units + 2;
            end
            if (intact_mask[index]) begin
                case (part)
                    `LP_PART_PIG: begin
                        pig_alive = 1;
                        mass_units = mass_units + 2;
                    end
                    `LP_PART_WHEEL: begin
                        wheel_count = wheel_count + 1;
                        mass_units = mass_units + 1;
                        if (index >= 3 && frame_intact_mask[index-3]) begin
                            wheels_down = wheels_down + 1;
                        end
                        if (index < 6 && frame_intact_mask[index+3]) begin
                            wheels_up = wheels_up + 1;
                        end
                    end
                    `LP_PART_ENGINE: begin
                        engine_count = engine_count + 1;
                        mass_units = mass_units + 3;
                        engine_balance = engine_balance + (build_facing_left[index] ? -5'sd1 : 5'sd1);
                    end
                    `LP_PART_BOOSTER: begin
                        rocket_count = rocket_count + 1;
                        mass_units = mass_units + 2;
                        if (!build_facing_down[index]) begin
                            rocket_balance = rocket_balance + (build_facing_left[index] ? -5'sd1 : 5'sd1);
                        end
                    end
                    `LP_PART_FAN: begin
                        fan_count = fan_count + 1;
                        mass_units = mass_units + 2;
                        if (!build_facing_down[index]) begin
                            fan_balance = fan_balance + (build_facing_left[index] ? -5'sd1 : 5'sd1);
                        end
                    end
                    `LP_PART_FRAME: begin
                        mass_units = mass_units + 2;
                    end
                    `LP_PART_BALLOON: begin
                        balloon_count = balloon_count + 1;
                        mass_units = mass_units + 1;
                    end
                    default: begin end
                endcase
            end
        end
        frames_left = (saved_frames < FRAME_LIMIT[3:0]) ? (FRAME_LIMIT[3:0] - saved_frames) : 4'd0;
        pigs_left = (saved_pigs < PIG_LIMIT[3:0]) ? (PIG_LIMIT[3:0] - saved_pigs) : 4'd0;
        wheels_left = (saved_wheels < WHEEL_LIMIT[3:0]) ? (WHEEL_LIMIT[3:0] - saved_wheels) : 4'd0;
        engines_left = (saved_engines < ENGINE_LIMIT[3:0]) ? (ENGINE_LIMIT[3:0] - saved_engines) : 4'd0;
        balloons_left = (saved_balloons < BALLOON_LIMIT[3:0]) ? (BALLOON_LIMIT[3:0] - saved_balloons) : 4'd0;
        rockets_left = (saved_rockets < active_rocket_limit) ? (active_rocket_limit - saved_rockets) : 4'd0;
        fans_left = (saved_fans < active_fan_limit) ? (active_fan_limit - saved_fans) : 4'd0;
        tnts_left = (saved_tnts < 4'd1) ? 4'd1 : 4'd0;
        stock_valid = (saved_rockets <= active_rocket_limit) && (saved_fans <= active_fan_limit) &&
                      (saved_frames <= FRAME_LIMIT[3:0]) && (saved_pigs <= PIG_LIMIT[3:0]) &&
                      (saved_wheels <= WHEEL_LIMIT[3:0]) && (saved_engines <= ENGINE_LIMIT[3:0]) &&
                      (saved_balloons <= BALLOON_LIMIT[3:0]) && (saved_tnts <= 4'd1);
        build_valid = (saved_pigs == 4'd1) && placement_valid && stock_valid;
        if (saved_pigs != 4'd1) begin
            build_error = `LP_BUILD_ERR_PIG;
        end else if (!placement_valid) begin
            build_error = `LP_BUILD_ERR_ATTACHMENT;
        end else if (!stock_valid) begin
            build_error = `LP_BUILD_ERR_INVENTORY;
        end else begin
            build_error = `LP_BUILD_OK;
        end
    end
endmodule
