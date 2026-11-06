`timescale 1ns / 1ps
module zoom_controls_tb;
    reg clk=0, reset=1, event_in=0, wheel_enabled=1, preset=0;
    reg [3:0] delta=0;
    wire zoom, overview;
    zoom_control dut(.clk(clk),.reset(reset),.wheel_enabled(wheel_enabled),.preset_normal(preset),.mouse_event(event_in),
                     .mouse_z(delta),.zoomed_out(zoom),.overview(overview));
    always #5 clk=~clk;
    task wheel; input [3:0] value; begin
        @(negedge clk);delta=value;event_in=1;@(negedge clk);event_in=0;delta=0;@(negedge clk);
    end endtask
    task check; input integer expected; begin
        if ({overview,zoom}!==expected) $fatal(1,"Expected zoom %0d, got %b%b",expected,overview,zoom);
    end endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;@(negedge clk);check(0);
        wheel(1);check(1);wheel(1);check(2);wheel(1);check(2);
        wheel(15);check(1);wheel(15);check(0);wheel(15);check(0);
        // A zero delta (ordinary mouse movement) changes nothing.
        wheel(0);check(0);
        // BUILD uses the wheel for inventory pages, so the map must not zoom there.
        wheel_enabled=0;wheel(1);check(0);wheel(15);check(0);
        wheel_enabled=1;
        // The tutorial's zoom lesson starts from the normal view.
        @(negedge clk);preset=1;@(negedge clk);preset=0;check(1);
        wheel(1);wheel(1);wheel(1);reset=1;@(negedge clk);check(0);
        $display("PASS zoom_controls_tb: wheel polarity, three scales, saturation, zero delta, BUILD wheel disable, tutorial preset and reset");
        $finish;
    end
endmodule
