// Owner: Role 4 - Marcus. Verify both ROM ports against the original map files.
`timescale 1ns / 1ps
`include "game_defs.vh"
module level_map_tb;
    reg draw_clk = 0, query_clk = 0, map_id = 0;
    reg signed [10:0] draw_x = 0, draw_y = 0, query_x = 0, query_y = 0;
    wire [2:0] draw_class, query_class;
    reg [2:0] arch [0:512*`LP_MAP_HEIGHT-1];
    reg [2:0] flight [0:1024*`LP_FLIGHT_HEIGHT-1];
    integer x, y, m;
    always #5 draw_clk = ~draw_clk;
    always #7 query_clk = ~query_clk;
    level_map #(.ARCH_SCALED(0)) dut (.map_id(map_id), .draw_clk(draw_clk), .draw_x(draw_x), .draw_y(draw_y),
        .draw_class(draw_class), .query_clk(query_clk), .query_x(query_x),
        .query_y(query_y), .query_class(query_class));

    function [2:0] expected;
        input map;
        input integer px, py;
        begin
            if (py >= (map ? `LP_FLIGHT_HEIGHT : `LP_MAP_HEIGHT)) expected = `LP_MAP_DARK;
            else if (px < 0 || py < 0 || px >= (map ? `LP_FLIGHT_WIDTH : `LP_MAP_WIDTH)) expected = `LP_MAP_SKY;
            else expected = map ? flight[py*1024+px] : arch[py*512+px];
        end
    endfunction

    initial begin
        $readmemh("cave_arch_map.mem", arch);
        $readmemh("cave_flight_map.mem", flight);
        for (m=0; m<2; m=m+1) begin
            // Check every valid pixel and all four outside edges on both ports.
            for (y=-1; y<=(m ? `LP_FLIGHT_HEIGHT : `LP_MAP_HEIGHT); y=y+1)
                for (x=-1; x<=(m ? `LP_FLIGHT_WIDTH : `LP_MAP_WIDTH); x=x+1) begin
                    @(negedge draw_clk);
                    map_id=m; draw_x=x; draw_y=y;
                    @(posedge draw_clk); #1;
                    if (draw_class !== expected(m,x,y)) $fatal(1,"Draw map %0d at %0d,%0d",m,x,y);
                    @(negedge query_clk);
                    query_x=x; query_y=y;
                    @(posedge query_clk); #1;
                    if (query_class !== expected(m,x,y)) $fatal(1,"Query map %0d at %0d,%0d",m,x,y);
                end
        end
        $display("PASS level_map_tb");
        $finish;
    end
endmodule
