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
    parameter integer FEEDBACK_CYCLES = 100000000
) (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire run_init,
    output reg init_ready,
    input wire edit_valid,
    input wire [1:0] edit_op,
    input wire [3:0] edit_cell,
    input wire [2:0] edit_part,
    input wire damage_valid,
    output wire damage_ready,
    input wire [8:0] damage_mask,
    input wire [8:0] damage_frame_mask,
    output reg [26:0] build_grid,
    output reg [8:0] build_frames,
    output reg [8:0] intact_mask,
    output reg [8:0] frame_intact_mask,
    output reg build_valid,
    output reg [3:0] build_error,
    output reg [2:0] feedback_code,
    output reg [3:0] feedback_cell,
    output reg pig_alive,
    output reg [3:0] wheel_count, engine_count, balloon_count,
    output reg [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left,
    output reg [7:0] mass_units
);
    localparam [26:0] STARTER_GRID = {
        `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
        `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
        `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
    };
    localparam [8:0] STARTER_FRAMES = 9'b000111000;
    localparam [8:0] STARTER_INTACT = 9'b101110000;
    reg [8:0] content_mask;
    reg placement_valid, stock_valid;
    integer index, saved_frames, saved_pigs, saved_wheels, saved_engines, saved_balloons;
    reg [2:0] part;
    reg [2:0] edit_result;
    reg [31:0] feedback_count;
    assign damage_ready = (game_state == `LP_RUN) && !run_init;

    // Decide once: this result controls both editing and the on-screen feedback.
    // Repeating the same placement or removing an empty cell is a quiet no-op.
    always @* begin
        edit_result = `LP_FEEDBACK_NONE;
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
                        if (build_grid[edit_cell*3 +: 3] == edit_part) edit_result = `LP_FEEDBACK_NONE;
                        else if (!build_frames[edit_cell]) edit_result = `LP_FEEDBACK_NEED_FRAME;
                        else if ((edit_part == `LP_PART_PIG && pigs_left == 0) ||
                                 (edit_part == `LP_PART_ENGINE && engines_left == 0))
                            edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    `LP_PART_WHEEL: begin
                        if (build_grid[edit_cell*3 +: 3] == edit_part) edit_result = `LP_FEEDBACK_NONE;
                        else if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                        else if (edit_cell < 3) edit_result = `LP_FEEDBACK_FRAME_ABOVE;
                        else if (!build_frames[edit_cell-3]) edit_result = `LP_FEEDBACK_FRAME_ABOVE;
                        else if (wheels_left == 0) edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    `LP_PART_BALLOON: begin
                        if (build_grid[edit_cell*3 +: 3] == edit_part) edit_result = `LP_FEEDBACK_NONE;
                        else if (build_frames[edit_cell]) edit_result = `LP_FEEDBACK_OCCUPIED;
                        else if (edit_cell >= 6) edit_result = `LP_FEEDBACK_FRAME_BELOW;
                        else if (!build_frames[edit_cell+3]) edit_result = `LP_FEEDBACK_FRAME_BELOW;
                        else if (balloons_left == 0) edit_result = `LP_FEEDBACK_NO_STOCK;
                        else edit_result = `LP_FEEDBACK_PLACED;
                    end
                    default: begin end
                endcase
                `LP_EDIT_REMOVE:
                    if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY || build_frames[edit_cell])
                        edit_result = `LP_FEEDBACK_REMOVED;
                default: begin end
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            build_grid <= STARTER_GRID;
            build_frames <= STARTER_FRAMES;
            intact_mask <= STARTER_INTACT;
            frame_intact_mask <= STARTER_FRAMES;
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
                intact_mask <= content_mask;
                frame_intact_mask <= build_frames;
                init_ready <= 1;
            end
            else if (game_state == `LP_BUILD) begin
                // Returning to construction also restores damaged parts.
                intact_mask <= content_mask;
                frame_intact_mask <= build_frames;
                if (edit_result == `LP_FEEDBACK_PLACED) begin
                    if (edit_part == `LP_PART_FRAME) begin
                        build_frames[edit_cell] <= 1'b1;
                        frame_intact_mask[edit_cell] <= 1'b1;
                    end else begin
                        // [start +: 3] selects one cell's three content bits.
                        build_grid[edit_cell*3 +: 3] <= edit_part;
                        intact_mask[edit_cell] <= 1'b1;
                    end
                end else if (edit_result == `LP_FEEDBACK_REMOVED) begin
                    // First remove contents; a second click removes the empty frame.
                    if (build_grid[edit_cell*3 +: 3] != `LP_PART_EMPTY) begin
                        build_grid[edit_cell*3 +: 3] <= `LP_PART_EMPTY;
                        intact_mask[edit_cell] <= 1'b0;
                    end else begin
                        build_frames[edit_cell] <= 1'b0;
                        frame_intact_mask[edit_cell] <= 1'b0;
                    end
                end
            end
            else if (damage_valid && damage_ready) begin
                intact_mask <= intact_mask & ~damage_mask;
                frame_intact_mask <= frame_intact_mask & ~damage_frame_mask;
            end
        end
    end
    always @* begin
        wheel_count = 0; engine_count = 0; balloon_count = 0;
        mass_units = 0; pig_alive = 0; part = 0;
        saved_frames = 0; saved_pigs = 0; saved_wheels = 0; saved_engines = 0; saved_balloons = 0;
        content_mask = 0; placement_valid = 1;
        for (index = 0; index < 9; index = index + 1) begin
            part = build_grid[index*3 +: 3];
            content_mask[index] = (part != `LP_PART_EMPTY);
            if (part == `LP_PART_PIG) saved_pigs = saved_pigs + 1;
            if (build_frames[index]) saved_frames = saved_frames + 1;
            if (part == `LP_PART_WHEEL) saved_wheels = saved_wheels + 1;
            if (part == `LP_PART_ENGINE) saved_engines = saved_engines + 1;
            if (part == `LP_PART_BALLOON) saved_balloons = saved_balloons + 1;
            // Construction validity uses the saved build, even after runtime damage.
            case (part)
                `LP_PART_EMPTY: begin end
                `LP_PART_PIG, `LP_PART_ENGINE:
                    if (!build_frames[index]) placement_valid = 0;
                `LP_PART_WHEEL: begin
                    if (build_frames[index] || index < 3) placement_valid = 0;
                    else if (!build_frames[index-3]) placement_valid = 0;
                end
                `LP_PART_BALLOON: begin
                    if (build_frames[index] || index >= 6) placement_valid = 0;
                    else if (!build_frames[index+3]) placement_valid = 0;
                end
                default: placement_valid = 0;
            endcase
            // A frame and its contents both contribute to mass while intact.
            if (frame_intact_mask[index]) mass_units = mass_units + 2;
            if (intact_mask[index]) case (part)
                `LP_PART_PIG: begin pig_alive = 1; mass_units = mass_units + 2; end
                `LP_PART_WHEEL: begin wheel_count = wheel_count + 1; mass_units = mass_units + 1; end
                `LP_PART_ENGINE: begin engine_count = engine_count + 1; mass_units = mass_units + 3; end
                `LP_PART_BALLOON: begin balloon_count = balloon_count + 1; mass_units = mass_units + 1; end
                default: begin end
            endcase
        end
        frames_left = (saved_frames < FRAME_LIMIT) ? FRAME_LIMIT-saved_frames : 0;
        pigs_left = (saved_pigs < PIG_LIMIT) ? PIG_LIMIT-saved_pigs : 0;
        wheels_left = (saved_wheels < WHEEL_LIMIT) ? WHEEL_LIMIT-saved_wheels : 0;
        engines_left = (saved_engines < ENGINE_LIMIT) ? ENGINE_LIMIT-saved_engines : 0;
        balloons_left = (saved_balloons < BALLOON_LIMIT) ? BALLOON_LIMIT-saved_balloons : 0;
        stock_valid = saved_frames <= FRAME_LIMIT && saved_pigs <= PIG_LIMIT &&
                      saved_wheels <= WHEEL_LIMIT && saved_engines <= ENGINE_LIMIT &&
                      saved_balloons <= BALLOON_LIMIT;
        build_valid = (saved_pigs == 1) && placement_valid && stock_valid;
        if (saved_pigs != 1) build_error = `LP_BUILD_ERR_PIG;
        else if (!placement_valid) build_error = `LP_BUILD_ERR_ATTACHMENT;
        else if (!stock_valid) build_error = `LP_BUILD_ERR_INVENTORY;
        else build_error = `LP_BUILD_OK;
    end
endmodule
