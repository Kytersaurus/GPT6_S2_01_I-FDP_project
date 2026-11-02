// Owner: Role 4 - Marcus. Block-RAM terrain maps for the Cave Arch and Cave Flight levels.
`timescale 1ns / 1ps
`include "game_defs.vh"
// One 3-bit LP_MAP_* class per world pixel, traced from the reference screenshots
// (docs/maps). map_id selects Cave Arch (0) or Cave Flight (1). Both ports read with one
// clock of latency: draw map_id serves the renderer; query_map_id serves collision
// independently of the display snapshot. Outside pixels are sky above/beside the
// map and underground below it; collision masks them to preserve world bounds.
// Cave Arch is traced at half the screenshot resolution, which left its passages too
// narrow for the 24-pixel vehicle. With ARCH_SCALED it is shown twice as large:
// world pixel w reads map pixel w/2 on both ports, so drawing and collision
// stay identical and no block RAM is added. The world is then
// LP_MAP_WORLD_WIDTH by LP_MAP_WORLD_HEIGHT. Asset checks use ARCH_SCALED=0.
// SMOOTH_DRAW smooths the drawn 2x Cave Arch: draw_clk must then run many times faster
// than draw_x/draw_y change, and all five reads must land inside one pixel. The top leaves
// it off: driven at 100 MHz from the untimed OLED clock domain it ran out of margin and
// map pixels flickered on the board. The
// draw port reads the centre map pixel and its four neighbours in turn, repeating while the
// coordinate is held, and each world pixel (a quarter of a map pixel) takes a neighbour's
// class by the Scale2x rule where two neighbours agree across its corner. Stair steps in
// grass and rock edges become diagonals one world pixel fine. Drawing only: collision and
// Cave Flight (one map pixel per world pixel) are unchanged.
module level_map #(parameter ARCH_SCALED = 1, parameter SMOOTH_DRAW = 0) (
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
    // Explicit one-bit files avoid synthesis-dependent initial-loop conversion
    // from the colour ROM. Both assets are generated from the same map classes.
    (* rom_style = "block" *) reg [0:0] arch_solid [0:512*`LP_MAP_HEIGHT-1];
    (* rom_style = "block" *) reg [0:0] flight_solid [0:1024*`LP_FLIGHT_HEIGHT-1];
    initial begin
        $readmemh("cave_arch_map.mem", arch_cells);
        $readmemh("cave_flight_map.mem", flight_cells);
        $readmemh("cave_arch_solid.mem", arch_solid);
        $readmemh("cave_flight_solid.mem", flight_solid);
    end

    // Halve non-negative coordinates; negative ones stay negative, so they remain
    // outside the map.
    function signed [10:0] arch_coord;
        input signed [10:0] c;
        begin
            arch_coord = (!ARCH_SCALED || c < 0) ? c : c >>> 1;
        end
    endfunction
    wire signed [10:0] draw_ax = arch_coord(draw_x), draw_ay = arch_coord(draw_y);
    wire signed [10:0] query_ax = arch_coord(query_x), query_ay = arch_coord(query_y);

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

    // Read step: 0 centre, 1 above, 2 below, 3 left, 4 right. Without SMOOTH_DRAW it stays 0.
    reg [2:0] draw_step = 3'd0, read_step = 3'd0;
    wire signed [10:0] step_dx = (draw_step == 3'd3) ? -11'sd1 : (draw_step == 3'd4) ? 11'sd1 : 11'sd0;
    wire signed [10:0] step_dy = (draw_step == 3'd1) ? -11'sd1 : (draw_step == 3'd2) ? 11'sd1 : 11'sd0;
    wire signed [10:0] read_ax = draw_ax + step_dx, read_ay = draw_ay + step_dy;
    wire signed [10:0] read_fx = draw_x + step_dx, read_fy = draw_y + step_dy;
    always @(posedge draw_clk) begin
        draw_step <= (!SMOOTH_DRAW || draw_step == 3'd4) ? 3'd0 : draw_step + 3'd1;
        read_step <= draw_step;
        draw_arch <= arch_cells[{read_ay[8:0], read_ax[8:0]}];
        draw_flight <= flight_cells[{read_fy[7:0], read_fx[9:0]}];
        draw_map <= map_id;
        draw_was_inside <= map_id ? in_map(1'b1, read_fx, read_fy) : in_map(1'b0, read_ax, read_ay);
        draw_outside <= map_id ? outside_class(1'b1, read_fy) : outside_class(1'b0, read_ay);
    end
    wire [2:0] read_class = !draw_was_inside ? draw_outside : draw_map ? draw_flight : draw_arch;

    reg [2:0] near_c, near_n, near_s, near_w, near_e;
    always @(posedge draw_clk) case (read_step)
        3'd0: near_c <= read_class;
        3'd1: near_n <= read_class;
        3'd2: near_s <= read_class;
        3'd3: near_w <= read_class;
        default: near_e <= read_class;
    endcase

    function [2:0] scale2x;
        input [2:0] c, n, s, w, e;
        input right, down;
        begin
            scale2x = c;
            if (!down && !right && w == n && n != e && w != s) scale2x = n;
            if (!down && right && n == e && n != w && e != s) scale2x = e;
            if (down && !right && w == s && w != n && s != e) scale2x = w;
            if (down && right && s == e && e != n && s != w) scale2x = e;
        end
    endfunction
    always @* begin
        if (!SMOOTH_DRAW) draw_class = read_class;
        else if (draw_map || !ARCH_SCALED || draw_x < 0 || draw_y < 0) draw_class = near_c;
        else draw_class = scale2x(near_c, near_n, near_s, near_w, near_e, draw_x[0], draw_y[0]);
    end

    always @(posedge query_clk) begin
        query_arch_solid <= arch_solid[{query_ay[8:0], query_ax[8:0]}];
        query_flight_solid <= flight_solid[{query_y[7:0], query_x[9:0]}];
        query_arch <= arch_cells[{query_ay[8:0], query_ax[8:0]}];
        query_flight <= flight_cells[{query_y[7:0], query_x[9:0]}];
        query_map <= query_map_id;
        query_was_inside <= query_map_id ? in_map(1'b1, query_x, query_y) : in_map(1'b0, query_ax, query_ay);
        query_outside <= query_map_id ? outside_class(1'b1, query_y) : outside_class(1'b0, query_ay);
    end
    assign query_solid = !query_was_inside ? (query_outside == `LP_MAP_DARK) :
                         query_map ? query_flight_solid : query_arch_solid;
    always @* query_class = !query_was_inside ? query_outside : query_map ? query_flight : query_arch;
endmodule
