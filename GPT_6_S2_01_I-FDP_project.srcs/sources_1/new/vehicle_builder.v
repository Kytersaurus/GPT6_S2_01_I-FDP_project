// Owner: Role 1 - Kaushal. Build storage, damage state and part properties.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Role 1 starter: fixed build, derived properties, damage and retry.
// Editor/inventory inputs are reserved; placement is not implemented yet.
module vehicle_builder (
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
    output wire [26:0] build_grid,
    output reg [8:0] intact_mask,
    output reg build_valid,
    output reg [3:0] build_error,
    output reg pig_alive,
    output reg [3:0] wheel_count, engine_count, balloon_count,
    output reg [7:0] mass_units
);
    localparam [26:0] ORIGINAL_GRID = {
        `LP_PART_WHEEL, `LP_PART_FRAME, `LP_PART_WHEEL,
        `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_FRAME,
        `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
    };
    localparam [8:0] ORIGINAL_INTACT = 9'b111111000;
    integer index, original_pigs;
    reg [2:0] part;
    assign build_grid = ORIGINAL_GRID;
    assign damage_ready = (game_state == `LP_RUN) && !run_init;
    always @(posedge clk) begin
        if (reset) begin intact_mask <= ORIGINAL_INTACT; init_ready <= 0; end
        else begin
            if (!run_init) init_ready <= 0;
            if (run_init && !init_ready) begin intact_mask <= ORIGINAL_INTACT; init_ready <= 1; end
            else if (game_state == `LP_BUILD) intact_mask <= ORIGINAL_INTACT;
            else if (damage_valid && damage_ready) intact_mask <= intact_mask & ~damage_mask;
        end
    end
    always @* begin
        wheel_count = 0; engine_count = 0; balloon_count = 0;
        mass_units = 0; pig_alive = 0; original_pigs = 0; part = 0;
        for (index = 0; index < 9; index = index + 1) begin
            part = build_grid[index*3 +: 3];
            if (part == `LP_PART_PIG) original_pigs = original_pigs + 1;
            if (intact_mask[index]) case (part)
                `LP_PART_FRAME: mass_units = mass_units + 2;
                `LP_PART_PIG: begin pig_alive = 1; mass_units = mass_units + 2; end
                `LP_PART_WHEEL: begin wheel_count = wheel_count + 1; mass_units = mass_units + 1; end
                `LP_PART_ENGINE: begin engine_count = engine_count + 1; mass_units = mass_units + 3; end
                `LP_PART_BALLOON: begin balloon_count = balloon_count + 1; mass_units = mass_units + 1; end
                default: begin end
            endcase
        end
        build_valid = (original_pigs == 1);
        build_error = build_valid ? 4'd0 : 4'd1;
    end
endmodule
