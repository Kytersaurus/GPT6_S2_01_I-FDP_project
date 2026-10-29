// Owner: Role 1 - Kaushal. Build storage, damage state and part properties.
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
    parameter integer ROCKET_LIMIT = 1, FAN_LIMIT = 1,
    parameter integer FEEDBACK_CYCLES = 100000000
) (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire run_init,
    output reg init_ready,
    input wire edit_valid,
    input wire [1:0] edit_op,
    input wire [3:0] edit_cell, edit_source,
    input wire [2:0] edit_part,
    input wire edit_facing_left,
    input wire damage_valid,
    output wire damage_ready,
    input wire [8:0] damage_mask,
    input wire [8:0] damage_frame_mask,
    output reg [26:0] build_grid,
    output reg [8:0] build_frames,
    output reg [8:0] build_facing_left,
    output reg signed [4:0] engine_balance,
    output reg [3:0] rocket_count, fan_count, rockets_left, fans_left,
    output wire [8:0] intact_mask,
    output wire [8:0] frame_intact_mask,
    output reg build_valid,
    output reg [3:0] build_error,
    output reg [2:0] feedback_code,
    output reg [3:0] feedback_cell,
    output reg pig_alive,
    output reg [3:0] wheel_count, engine_count, balloon_count,
    // Intact wheels by the side they touch: a frame above hangs the wheel under
    // the body (down); a frame below sets it on top (up). A middle-row wheel
    // between two frames counts on both sides.
    output reg [3:0] wheels_down, wheels_up,
    output reg [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left,
    output reg [7:0] mass_units
);
    reg [8:0] content_mask;
    reg [8:0] runtime_intact, runtime_frames;
    integer mask_index;
    // BUILD always shows the saved construction. Only RUN needs stored damage.
    assign intact_mask = game_state == `LP_BUILD ? content_mask : runtime_intact;
    assign frame_intact_mask = game_state == `LP_BUILD ? build_frames : runtime_frames;
    always @* begin
        content_mask=0;
        for (mask_index=0; mask_index<9; mask_index=mask_index+1)
            content_mask[mask_index]=(build_grid[mask_index*3 +: 3] != `LP_PART_EMPTY);
    end
    reg placement_valid, stock_valid;
    integer index, saved_frames, saved_pigs, saved_wheels, saved_engines, saved_balloons, saved_rockets, saved_fans;
    reg [2:0] part;
    reg [2:0] edit_result;
    reg [2:0] source_part;
    reg [31:0] feedback_count;
    assign damage_ready = (game_state == `LP_RUN) && !run_init;

    // Shift the frame layer by one row in either direction; no edge wraps.
    wire [8:0] wheel_support = (build_frames << 3) | (build_frames >> 3);
    // Column masks prevent horizontal neighbours wrapping to the next row.
    wire [8:0] side_support = ((build_frames & 9'b011011011) << 1) |
                              ((build_frames & 9'b110110110) >> 1);

    // Decide once: this result controls both editing and the on-screen feedback.
    // Repeating the same placement or removing an empty cell is a quiet no-op.
    always @* begin
        edit_result = `LP_FEEDBACK_NONE;
        source_part = `LP_PART_EMPTY;
        if (edit_source < 9) source_part = build_grid[edit_source*3 +: 3];
        if (game_state == `LP_BUILD && !run_init && edit_valid && edit_cell < 9) begin
            case (edit_op)
                `LP_EDIT_PLACE: case (edit_part)
                    `LP_PART_FRAME: begin
                        if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_NONE;
                        else if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY)
                            edit_result = `LP_FEEDBACK_OCCUPIED;
                        else if (frames_left == 0) edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    `LP_PART_PIG, `LP_PART_ENGINE: begin
                        if (build_grid[edit_cell*3 +: 3] == edit_part)
                            edit_result = (edit_part==`LP_PART_ENGINE &&
                                           build_facing_left[edit_cell]!=edit_facing_left) ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NONE;
                        else if (!build_frames[edit_cell]) edit_result = `LP_FEEDBACK_NEED_FRAME;
                        else if ((edit_part == `LP_PART_PIG && pigs_left == 0) ||
                                 (edit_part == `LP_PART_ENGINE && engines_left == 0))
                            edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    `LP_PART_WHEEL: begin
                        if (build_grid[edit_cell*3 +: 3] == edit_part)
                            edit_result = `LP_FEEDBACK_NONE;
                        else if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                        else if (!wheel_support[edit_cell]) edit_result = `LP_FEEDBACK_FRAME_ABOVE;
                        else if (wheels_left == 0) edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    `LP_PART_BALLOON: begin
                        if (build_grid[edit_cell*3 +: 3] == edit_part)
                            edit_result = `LP_FEEDBACK_NONE;
                        else if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                        else if (edit_cell >= 6) edit_result = `LP_FEEDBACK_FRAME_BELOW;
                        else if (!build_frames[edit_cell+3]) edit_result = `LP_FEEDBACK_FRAME_BELOW;
                        else if (balloons_left == 0) edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    `LP_PART_BOOSTER, `LP_PART_FAN: begin
                        if (build_grid[edit_cell*3 +: 3] == edit_part)
                            edit_result = ((edit_part==`LP_PART_BOOSTER || edit_part==`LP_PART_FAN) &&
                                           build_facing_left[edit_cell]!=edit_facing_left) ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NONE;
                        else if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                        else if (!side_support[edit_cell]) edit_result = `LP_FEEDBACK_NEED_FRAME;
                        else if ((edit_part==`LP_PART_BOOSTER && rockets_left==0) ||
                                 (edit_part==`LP_PART_FAN && fans_left==0)) edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    default: begin end
                endcase
                `LP_EDIT_REMOVE:
                    if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY || build_frames[edit_cell])
                        edit_result = `LP_FEEDBACK_REMOVED;
                `LP_EDIT_MOVE: if (edit_source < 9 && edit_source != edit_cell) begin
                    if (edit_part == `LP_PART_FRAME && build_frames[edit_source] && source_part == `LP_PART_EMPTY) begin
                        if (build_frames[edit_cell] || build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY)
                            edit_result = `LP_FEEDBACK_OCCUPIED;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end else if (source_part == edit_part && source_part != `LP_PART_EMPTY) begin
                        if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) edit_result = `LP_FEEDBACK_OCCUPIED;
                        else case (edit_part)
                            `LP_PART_PIG, `LP_PART_ENGINE:
                                edit_result = build_frames[edit_cell] ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NEED_FRAME;
                            `LP_PART_WHEEL:
                                if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                                else edit_result = wheel_support[edit_cell] ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_FRAME_ABOVE;
                            `LP_PART_BALLOON:
                                if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                                else if (edit_cell >= 6) edit_result = `LP_FEEDBACK_FRAME_BELOW;
                                else edit_result = build_frames[edit_cell+3] ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_FRAME_BELOW;
                            `LP_PART_BOOSTER, `LP_PART_FAN:
                                if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                                else edit_result = side_support[edit_cell] ? `LP_FEEDBACK_PLACED : `LP_FEEDBACK_NEED_FRAME;
                            default: begin end
                        endcase
                    end
                end
                `LP_EDIT_RETURN: if (edit_source < 9 &&
                    ((edit_part == `LP_PART_FRAME && build_frames[edit_source] && source_part == `LP_PART_EMPTY) ||
                     (edit_part == source_part && source_part != `LP_PART_EMPTY)))
                    edit_result = `LP_FEEDBACK_REMOVED;
                default: begin end
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            // Start empty; retry still restores the player's saved construction.
            build_grid <= 0;
            build_frames <= 0;
            build_facing_left <= 0;
            runtime_intact <= 0;
            runtime_frames <= 0;
            init_ready <= 0;
            feedback_code <= `LP_FEEDBACK_NONE; feedback_cell <= 0; feedback_count <= 0;
        end
        else begin
            if (game_state != `LP_BUILD || run_init) begin
                feedback_code <= `LP_FEEDBACK_NONE; feedback_count <= 0;
            end else if (edit_result != `LP_FEEDBACK_NONE) begin
                feedback_code <= edit_result; feedback_cell <= edit_cell; feedback_count <= 0;
            end else if (feedback_code != `LP_FEEDBACK_NONE) begin
                if (feedback_count == FEEDBACK_CYCLES-1) begin
                    feedback_code <= `LP_FEEDBACK_NONE; feedback_count <= 0;
                end else feedback_count <= feedback_count + 1'b1;
            end
            if (!run_init) init_ready <= 0;
            if (run_init && !init_ready) begin
                // Retry restores both layers of the saved build.
                runtime_intact <= content_mask;
                runtime_frames <= build_frames;
                init_ready <= 1;
            end
            else if (game_state == `LP_BUILD) begin
                // The BUILD outputs follow the saved layers directly.
                // Keep a restored runtime copy ready for the next launch.
                runtime_intact <= content_mask;
                runtime_frames <= build_frames;
                if (edit_result == `LP_FEEDBACK_PLACED) begin
                    if (edit_op == `LP_EDIT_MOVE) begin
                        // Source and destination change on the same edge; stock is unchanged.
                        build_grid[edit_source*3 +: 3] <= `LP_PART_EMPTY;
                        build_grid[edit_cell*3 +: 3] <= source_part;
                        build_facing_left[edit_cell] <= build_facing_left[edit_source];
                        build_facing_left[edit_source] <= 0;
                        if (edit_part == `LP_PART_FRAME) begin
                            build_frames[edit_source] <= 0; build_frames[edit_cell] <= 1;
                        end
                    end else if (edit_part == `LP_PART_FRAME) begin
                        build_frames[edit_cell] <= 1'b1;
                    end else begin
                        // [start +: 3] selects one cell's three content bits.
                        build_grid[edit_cell*3 +: 3] <= edit_part;
                        build_facing_left[edit_cell] <= (edit_part==`LP_PART_ENGINE || edit_part==`LP_PART_BOOSTER ||
                                                         edit_part==`LP_PART_FAN) && edit_facing_left;
                    end
                end else if (edit_result == `LP_FEEDBACK_REMOVED) begin
                    if (edit_op == `LP_EDIT_RETURN) begin
                        build_grid[edit_source*3 +: 3] <= `LP_PART_EMPTY;
                        build_facing_left[edit_source] <= 0;
                        if (edit_part == `LP_PART_FRAME) begin
                            build_frames[edit_source] <= 0;
                        end
                    // Right click removes contents first, then the empty frame.
                    end else if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                        build_grid[edit_cell*3 +: 3] <= `LP_PART_EMPTY;
                        build_facing_left[edit_cell] <= 0;
                    end else begin
                        build_frames[edit_cell] <= 1'b0;
                    end
                end
            end
            else if (damage_valid && damage_ready) begin
                runtime_intact <= runtime_intact & ~damage_mask;
                runtime_frames <= runtime_frames & ~damage_frame_mask;
            end
        end
    end
    always @* begin
        wheel_count = 0; engine_count = 0; balloon_count = 0; wheels_down = 0; wheels_up = 0;
        rocket_count=0; fan_count=0; engine_balance=0;
        mass_units = 0; pig_alive = 0; part = 0;
        saved_frames = 0; saved_pigs = 0; saved_wheels = 0; saved_engines = 0; saved_balloons = 0; saved_rockets=0; saved_fans=0;
        placement_valid = 1;
        for (index = 0; index < 9; index = index + 1) begin
            part = build_grid[index*3 +: 3];
            if (part == `LP_PART_PIG) saved_pigs = saved_pigs + 1;
            if (build_frames[index]) saved_frames = saved_frames + 1;
            if (part == `LP_PART_WHEEL) saved_wheels = saved_wheels + 1;
            if (part == `LP_PART_ENGINE) saved_engines = saved_engines + 1;
            if (part == `LP_PART_BALLOON) saved_balloons = saved_balloons + 1;
            if (part == `LP_PART_BOOSTER) saved_rockets=saved_rockets+1;
            if (part == `LP_PART_FAN) saved_fans=saved_fans+1;
            // Construction validity uses the saved build, even after runtime damage.
            case (part)
                `LP_PART_EMPTY: begin end
                `LP_PART_PIG, `LP_PART_ENGINE:
                    if (!build_frames[index]) placement_valid = 0;
                `LP_PART_WHEEL: begin
                    if (build_frames[index] || !wheel_support[index]) placement_valid = 0;
                end
                `LP_PART_BALLOON: begin
                    if (build_frames[index] || index >= 6) placement_valid = 0;
                    else if (!build_frames[index+3]) placement_valid = 0;
                end
                `LP_PART_BOOSTER, `LP_PART_FAN:
                    if (build_frames[index] || !side_support[index]) placement_valid=0;
                default: placement_valid = 0;
            endcase
            // A frame and its contents both contribute to mass while intact.
            if (frame_intact_mask[index]) mass_units = mass_units + 2;
            if (intact_mask[index]) case (part)
                `LP_PART_PIG: begin pig_alive = 1; mass_units = mass_units + 2; end
                `LP_PART_WHEEL: begin
                    wheel_count = wheel_count + 1; mass_units = mass_units + 1;
                    if (index >= 3 && build_frames[index-3]) wheels_down = wheels_down + 1;
                    if (index < 6 && build_frames[index+3]) wheels_up = wheels_up + 1;
                end
                `LP_PART_ENGINE: begin
                    engine_count = engine_count + 1; mass_units = mass_units + 3;
                    engine_balance=engine_balance+(build_facing_left[index] ? -5'sd1 : 5'sd1);
                end
                `LP_PART_BOOSTER: begin rocket_count=rocket_count+1; mass_units=mass_units+2; end
                `LP_PART_FAN: begin fan_count=fan_count+1; mass_units=mass_units+2; end
                `LP_PART_BALLOON: begin balloon_count = balloon_count + 1; mass_units = mass_units + 1; end
                default: begin end
            endcase
        end
        frames_left = (saved_frames < FRAME_LIMIT) ? FRAME_LIMIT-saved_frames : 0;
        pigs_left = (saved_pigs < PIG_LIMIT) ? PIG_LIMIT-saved_pigs : 0;
        wheels_left = (saved_wheels < WHEEL_LIMIT) ? WHEEL_LIMIT-saved_wheels : 0;
        engines_left = (saved_engines < ENGINE_LIMIT) ? ENGINE_LIMIT-saved_engines : 0;
        balloons_left = (saved_balloons < BALLOON_LIMIT) ? BALLOON_LIMIT-saved_balloons : 0;
        rockets_left = saved_rockets < ROCKET_LIMIT ? ROCKET_LIMIT-saved_rockets : 0;
        fans_left = saved_fans < FAN_LIMIT ? FAN_LIMIT-saved_fans : 0;
        stock_valid = saved_rockets<=ROCKET_LIMIT && saved_fans<=FAN_LIMIT && saved_frames <= FRAME_LIMIT && saved_pigs <= PIG_LIMIT &&
                      saved_wheels <= WHEEL_LIMIT && saved_engines <= ENGINE_LIMIT &&
                      saved_balloons <= BALLOON_LIMIT;
        build_valid = (saved_pigs == 1) && placement_valid && stock_valid;
        if (saved_pigs != 1) build_error = `LP_BUILD_ERR_PIG;
        else if (!placement_valid) build_error = `LP_BUILD_ERR_ATTACHMENT;
        else if (!stock_valid) build_error = `LP_BUILD_ERR_INVENTORY;
        else build_error = `LP_BUILD_OK;
    end
endmodule
