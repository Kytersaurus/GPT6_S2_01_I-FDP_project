`timescale 1ns / 1ps
module zoom_controls_tb;
    reg clk=0, reset=1, sw=0, event_in=0;
    reg [3:0] delta=0;
    wire zoom, overview;
    zoom_control dut(.clk(clk),.reset(reset),.zoom_switch(sw),.mouse_event(event_in),
                     .mouse_z(delta),.zoomed_out(zoom),.overview(overview));
    always #5 clk=~clk;
    task wheel; input [3:0] value; begin
        @(negedge clk);delta=value;event_in=1;
        @(negedge clk);event_in=0;delta=0;
    end endtask
    task check; input [1:0] expected; begin
        if({overview,zoom}!==expected) $fatal(1,"Wrong wheel scale: %b",{overview,zoom});
    end endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;check(0);
        wheel(1);check(1);wheel(1);check(3);wheel(1);check(2);
        wheel(1);check(2);wheel(0);check(2);
        wheel(15);check(3);wheel(15);check(1);wheel(15);check(0);wheel(15);check(0);
        sw=1;repeat(5) @(negedge clk);check(1);
        sw=0;repeat(5) @(negedge clk);check(0);
        wheel(1);wheel(1);wheel(1);reset=1;@(negedge clk);check(0);
        $display("PASS zoom_controls_tb: wheel polarity, four scales, saturation, zero delta, switch and reset");
        $finish;
    end
endmodule
