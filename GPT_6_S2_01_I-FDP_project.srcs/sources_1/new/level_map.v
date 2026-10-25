// Owner: Role 4 - Marcus. Block-RAM terrain maps for the Cave Arch and Cave Flight levels.
`timescale 1ns / 1ps
`include "game_defs.vh"
// One 3-bit LP_MAP_* class per world pixel, traced from the reference screenshots
// (docs/maps). map_id selects Cave Arch (0) or Cave Flight (1). Both ports read with one
// clock of latency: the draw port serves the right renderer; the query port is free for
// collision. Coordinates outside a map return sky above/beside it and underground below it.
module level_map (
    input wire map_id,
    input wire draw_clk,
    input wire signed [10:0] draw_x, draw_y,
    output reg [2:0] draw_class,
    input wire query_clk,
    input wire signed [10:0] query_x, query_y,
    output reg [2:0] query_class
);
    (* rom_style = "block" *) reg [2:0] arch_cells [0:512*`LP_MAP_HEIGHT-1];
    (* rom_style = "block" *) reg [2:0] flight_cells [0:1024*`LP_FLIGHT_HEIGHT-1];
    initial $readmemh("cave_arch_map.mem", arch_cells);
    initial $readmemh("cave_flight_map.mem", flight_cells);

    function in_map;
        input map;
        input signed [10:0] x, y;
        begin
            in_map = map ? (x >= 0 && x < `LP_FLIGHT_WIDTH && y >= 0 && y < `LP_FLIGHT_HEIGHT)
                         : (x >= 0 && x < `LP_MAP_WIDTH && y >= 0 && y < `LP_MAP_HEIGHT);
        end
    endfunction

    function [2:0] outside_class;
        input map;
        input signed [10:0] y;
        begin
            outside_class = (y >= (map ? `LP_FLIGHT_HEIGHT : `LP_MAP_HEIGHT)) ? `LP_MAP_DARK : `LP_MAP_SKY;
        end
    endfunction

    // Register the map choice and outside decision beside each read so the ROMs stay plain block-RAM reads.
    reg [2:0] draw_arch, draw_flight, query_arch, query_flight, draw_outside, query_outside;
    reg draw_map, query_map, draw_was_inside, query_was_inside;

    always @(posedge draw_clk) begin
        draw_arch <= arch_cells[{draw_y[8:0], draw_x[8:0]}];
        draw_flight <= flight_cells[{draw_y[7:0], draw_x[9:0]}];
        draw_map <= map_id;
        draw_was_inside <= in_map(map_id, draw_x, draw_y);
        draw_outside <= outside_class(map_id, draw_y);
    end
    always @* draw_class = !draw_was_inside ? draw_outside : draw_map ? draw_flight : draw_arch;

    always @(posedge query_clk) begin
        query_arch <= arch_cells[{query_y[8:0], query_x[8:0]}];
        query_flight <= flight_cells[{query_y[7:0], query_x[9:0]}];
        query_map <= map_id;
        query_was_inside <= in_map(map_id, query_x, query_y);
        query_outside <= outside_class(map_id, query_y);
    end
    always @* query_class = !query_was_inside ? query_outside : query_map ? query_flight : query_arch;
endmodule
