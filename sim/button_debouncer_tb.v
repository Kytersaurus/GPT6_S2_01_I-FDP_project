// Owner: Role 1 - Kaushal.
`timescale 1ns / 1ps
module button_debouncer_tb;
    reg clk = 0, reset = 1, btn = 0;
    wire press;
    integer presses = 0;
    reg previous_press = 0;
    always #5 clk = ~clk;

    // Short intervals keep simulation quick; hardware defaults are unchanged.
    button_debouncer #(.RELEASE_CYCLES(8)) dut (
        .CLOCK(clk), .reset(reset), .btn(btn), .freq_count(32'd15), .btn_pressed(press)
    );

    task clocks;
        input integer count;
        begin repeat (count) @(negedge clk); end
    endtask

    always @(negedge clk) begin
        if (press) begin
            if (reset) $fatal(1, "Press during reset");
            if (previous_press) $fatal(1, "Press pulse lasted multiple cycles");
            presses = presses + 1;
        end
        previous_press = press;
    end

    initial begin
        clocks(4); reset = 0; clocks(4);
        btn = 1; clocks(6);
        if (presses != 1) $fatal(1, "First press missing");
        btn = 0; clocks(1); btn = 1; clocks(1);
        btn = 0; clocks(1); btn = 1; clocks(40);
        if (presses != 1) $fatal(1, "Press bounce or holding repeated");
        btn = 0; clocks(3); btn = 1; clocks(12);
        if (presses != 1) $fatal(1, "Brief release rearmed the button");
        btn = 0; clocks(14); btn = 1; clocks(6);
        if (presses != 2) $fatal(1, "Stable release did not allow next press");
        reset = 1; clocks(4);
        btn = 0; reset = 0; clocks(14); btn = 1; clocks(6);
        if (presses != 3) $fatal(1, "Button did not recover after reset");
        $display("PASS button_debouncer_tb: press bounce, held button, release bounce, rearm, reset, one-cycle pulses");
        $finish;
    end
    initial begin #10000; $fatal(1, "Debouncer test timed out"); end
endmodule
