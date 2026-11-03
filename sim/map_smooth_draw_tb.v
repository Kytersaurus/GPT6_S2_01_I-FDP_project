// Owner: Role 4 - Marcus. Checks level_map's smoothed draw port against a Scale2x reference.
`timescale 1ns / 1ps
`include "game_defs.vh"
// For every Cave Arch world pixel (and a margin outside the map), the SMOOTH_DRAW port,
// held for 12 clocks as the 16-clock OLED pixel holds it, must equal Scale2x of the plain
// port's centre and four neighbouring map pixels for that world pixel's quarter. Cave
// Flight pixels must be unchanged. The plain port keeps its one-clock latency.
module map_smooth_draw_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg map_id=0;
    reg signed [10:0] x=0, y=0, rx=0, ry=0;
    wire [2:0] smooth_class, raw_class;
    level_map #(.SMOOTH_DRAW(1)) smooth (.map_id(map_id), .draw_clk(clk), .draw_x(x), .draw_y(y), .draw_class(smooth_class),
        .query_clk(clk), .query_map_id(1'b0), .query_x(11'sd0), .query_y(11'sd0), .query_class(), .query_solid());
    level_map plain (.map_id(map_id), .draw_clk(clk), .draw_x(rx), .draw_y(ry), .draw_class(raw_class),
        .query_clk(clk), .query_map_id(1'b0), .query_x(11'sd0), .query_y(11'sd0), .query_class(), .query_solid());

    task read_raw(input signed [10:0] px, input signed [10:0] py, output [2:0] k);
        begin rx=px; ry=py; @(posedge clk); #1 k=raw_class; end
    endtask

    integer errors=0, changed=0, checked=0;
    reg [2:0] c, n, s, w, e, expected;
    initial begin
        for (y=-2; y<`LP_MAP_WORLD_HEIGHT+2; y=y+1) begin
            for (x=-2; x<`LP_MAP_WORLD_WIDTH+2; x=x+1) begin
                // World pixel x covers map pixel x/2 (floor); neighbours are one map pixel (two world pixels) away.
                read_raw(x, y, c); read_raw(x, y-2, n); read_raw(x, y+2, s); read_raw(x-2, y, w); read_raw(x+2, y, e);
                if (x<0 || y<0) expected=c;
                else begin
                    expected=c;
                    if (!y[0] && !x[0] && w==n && n!=e && w!=s) expected=n;
                    if (!y[0] && x[0] && n==e && n!=w && e!=s) expected=e;
                    if (y[0] && !x[0] && w==s && w!=n && s!=e) expected=w;
                    if (y[0] && x[0] && s==e && e!=n && s!=w) expected=e;
                end
                repeat (12) @(posedge clk);
                #1;
                if (smooth_class!==expected) begin
                    errors=errors+1;
                    if (errors<10) $display("ERROR arch (%0d,%0d): smooth %0d expected %0d", x, y, smooth_class, expected);
                end
                if (expected!=c) changed=changed+1;
                checked=checked+1;
            end
        end
        // Cave Flight is drawn unsmoothed.
        map_id=1;
        for (y=0; y<`LP_FLIGHT_HEIGHT; y=y+3) for (x=0; x<`LP_FLIGHT_WIDTH; x=x+3) begin
            read_raw(x, y, c);
            repeat (12) @(posedge clk);
            #1 if (smooth_class!==c) begin
                errors=errors+1;
                if (errors<10) $display("ERROR flight (%0d,%0d): smooth %0d raw %0d", x, y, smooth_class, c);
            end
        end
        $display("Checked %0d Cave Arch pixels, %0d smoothed", checked, changed);
        if (errors==0 && changed>0) $display("PASS map_smooth_draw_tb");
        else $display("FAIL map_smooth_draw_tb: %0d errors", errors);
        $finish;
    end
endmodule
