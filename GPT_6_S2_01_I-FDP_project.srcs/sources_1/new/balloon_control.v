// Owner: Role 1 - Kaushal. Queue balloon clicks until movement/world checks finish.
`timescale 1ns / 1ps
`include "game_defs.vh"
module balloon_control (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire pop_req,
    input wire [3:0] pop_cell,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire gameplay_ready,
    output wire pop_pending, pop_valid,
    output wire [8:0] pop_mask
);
    reg [8:0] pending_mask;
    integer index;

    assign pop_pending = |pending_mask;
    // The builder always accepts damage in RUN. The controller reserves this
    // idle clock for the pop, so no movement step starts on the same edge.
    assign pop_valid = (game_state == `LP_RUN) && gameplay_ready && pop_pending;
    assign pop_mask = pending_mask & intact_mask;

    always @(posedge clk) begin
        if (reset || game_state != `LP_RUN) pending_mask <= 0;
        else begin
            for (index = 0; index < 9; index = index + 1) begin
                if (pop_valid) pending_mask[index] <= 0;
                if (pop_req && pop_cell == index && intact_mask[index] &&
                    build_grid[index*3 +: 3] == `LP_PART_BALLOON &&
                    !(pop_valid && pending_mask[index])) begin
                    // Repeated clicks on a queued balloon use the same bit.
                    // A different click arriving during application is kept.
                    pending_mask[index] <= 1;
                end
            end
        end
    end
endmodule
