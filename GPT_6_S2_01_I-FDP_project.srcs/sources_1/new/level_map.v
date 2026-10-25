// Owner: Role 4 - Marcus. Block-RAM terrain map for the Cave Arch level.
`timescale 1ns / 1ps
`include "game_defs.vh"
// One 3-bit LP_MAP_* class per world pixel, traced from the reference screenshots
// (docs/maps). Both ports read the same ROM with one clock of latency:
// the draw port serves the right renderer; the query port is free for collision.
// Coordinates outside the map return sky above/beside it and underground below it.
module level_map (
    input wire draw_clk,
    input wire signed [10:0] draw_x, draw_y,
    output reg [2:0] draw_class,
    input wire query_clk,
    input wire signed [10:0] query_x, query_y,
    output reg [2:0] query_class
);
    (* rom_style = "block" *) reg [2:0] cells [0:512*`LP_MAP_HEIGHT-1];
    initial $readmemh("cave_arch_map.mem", cells);

    function [2:0] outside_class;
        input signed [10:0] y;
        begin outside_class = (y >= `LP_MAP_HEIGHT) ? `LP_MAP_DARK : `LP_MAP_SKY; end
    endfunction

    wire draw_inside = draw_x >= 0 && draw_x < `LP_MAP_WIDTH && draw_y >= 0 && draw_y < `LP_MAP_HEIGHT;
    wire query_inside = query_x >= 0 && query_x < `LP_MAP_WIDTH && query_y >= 0 && query_y < `LP_MAP_HEIGHT;
    // Register the outside decision beside the read so the ROM itself stays a plain block-RAM read.
    reg draw_was_inside, query_was_inside;
    reg [2:0] draw_outside, query_outside;
    reg [2:0] draw_cell, query_cell;

    always @(posedge draw_clk) draw_cell <= cells[{draw_y[8:0], draw_x[8:0]}];
    always @(posedge draw_clk) begin
        draw_was_inside <= draw_inside;
        draw_outside <= outside_class(draw_y);
    end
    always @* draw_class = draw_was_inside ? draw_cell : draw_outside;

    always @(posedge query_clk) query_cell <= cells[{query_y[8:0], query_x[8:0]}];
    always @(posedge query_clk) begin
        query_was_inside <= query_inside;
        query_outside <= outside_class(query_y);
    end
    always @* query_class = query_was_inside ? query_cell : query_outside;
endmodule
