// Owner: Role 4 - Marcus. Block-RAM terrain maps for the Cave Arch and Cave Flight levels.
`timescale 1ns / 1ps
`include "game_defs.vh"
// One 3-bit LP_MAP_* class per world pixel, traced from the reference screenshots
// (docs/maps). map_id selects Cave Arch (0) or Cave Flight (1). Both ports read with one
// clock of latency: draw map_id serves the renderer; query_map_id serves collision
// independently of the display snapshot. Outside pixels are sky above/beside the
// map and underground below it; collision masks them to preserve world bounds.
module level_map (
    input wire map_id,
    input wire draw_clk,
    input wire signed [10:0] draw_x, draw_y,
    output reg [2:0] draw_class,
    input wire query_clk,
    input wire query_map_id,
    input wire signed [10:0] query_x, query_y,
    output reg [2:0] query_class,
    output wire query_solid
);
    (* rom_style = "block" *) reg [2:0] arch_cells [0:512*`LP_MAP_HEIGHT-1];
    (* rom_style = "block" *) reg [2:0] flight_cells [0:1024*`LP_FLIGHT_HEIGHT-1];
    // Collision needs only solidity. Derive its one-bit ROMs from the same
    // class files at elaboration, avoiding a second colour ROM on the board.
    // query_class remains available to clients needing exact classes; unused
    // full-class query reads are optimized away in the hardware top.
    (* rom_style = "block" *) reg arch_solid [0:512*`LP_MAP_HEIGHT-1];
    (* rom_style = "block" *) reg flight_solid [0:1024*`LP_FLIGHT_HEIGHT-1];
    integer cell_index;
    initial begin
        $readmemh("cave_arch_map.mem", arch_cells);
        $readmemh("cave_flight_map.mem", flight_cells);
        for (cell_index=0; cell_index<512*`LP_MAP_HEIGHT; cell_index=cell_index+1)
            arch_solid[cell_index] = arch_cells[cell_index] >= `LP_MAP_ROCK && arch_cells[cell_index] <= `LP_MAP_DARK;
        for (cell_index=0; cell_index<1024*`LP_FLIGHT_HEIGHT; cell_index=cell_index+1)
            flight_solid[cell_index] = flight_cells[cell_index] >= `LP_MAP_ROCK && flight_cells[cell_index] <= `LP_MAP_DARK;
    end

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
    reg query_arch_solid, query_flight_solid;

    always @(posedge draw_clk) begin
        draw_arch <= arch_cells[{draw_y[8:0], draw_x[8:0]}];
        draw_flight <= flight_cells[{draw_y[7:0], draw_x[9:0]}];
        draw_map <= map_id;
        draw_was_inside <= in_map(map_id, draw_x, draw_y);
        draw_outside <= outside_class(map_id, draw_y);
    end
    always @* draw_class = !draw_was_inside ? draw_outside : draw_map ? draw_flight : draw_arch;

    always @(posedge query_clk) begin
        query_arch_solid <= arch_solid[{query_y[8:0], query_x[8:0]}];
        query_flight_solid <= flight_solid[{query_y[7:0], query_x[9:0]}];
        query_arch <= arch_cells[{query_y[8:0], query_x[8:0]}];
        query_flight <= flight_cells[{query_y[7:0], query_x[9:0]}];
        query_map <= query_map_id;
        query_was_inside <= in_map(query_map_id, query_x, query_y);
        query_outside <= outside_class(query_map_id, query_y);
    end
    assign query_solid = !query_was_inside ? (query_outside == `LP_MAP_DARK) :
                         query_map ? query_flight_solid : query_arch_solid;
    always @* query_class = !query_was_inside ? query_outside : query_map ? query_flight : query_arch;
endmodule
