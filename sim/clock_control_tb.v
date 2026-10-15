// Owner: Shared clock/reset support - Role 1 (Kaushal).
`timescale 1ns / 1ps
module clock_control_tb;
    reg clk=0, reset_button=0;
    wire div0, div1, div7, reset, oled_clk, oled_reset, physics_tick;
    time last0=0, last1=0, last7=0;
    integer cycles=0, last_tick=0, ticks=0;
    reg previous_tick=0;
    always #5 clk=~clk;
    custom_clk_divider d0 (.CLOCK(clk),.freq_count(32'd0),.CUSTOM_CLOCK(div0));
    custom_clk_divider d1 (.CLOCK(clk),.freq_count(32'd1),.CUSTOM_CLOCK(div1));
    custom_clk_divider d7 (.CLOCK(clk),.freq_count(32'd7),.CUSTOM_CLOCK(div7));
    clock_control #(.PHYSICS_CYCLES(5)) dut (
        .clk(clk),.reset_button(reset_button),.reset(reset),.oled_clk(oled_clk),
        .oled_reset(oled_reset),.physics_tick(physics_tick)
    );
    always @(posedge div0) begin
        if (last0!=0 && $time-last0!=20) $fatal(1,"freq_count=0 did not produce 50 MHz");
        last0=$time;
    end
    always @(posedge div1) begin
        if (last1!=0 && $time-last1!=40) $fatal(1,"freq_count=1 did not produce 25 MHz");
        last1=$time;
    end
    always @(posedge div7) begin
        if (last7!=0 && $time-last7!=160) $fatal(1,"freq_count=7 did not produce 6.25 MHz");
        last7=$time;
    end
    always @(negedge clk) begin
        cycles=cycles+1;
        if (oled_clk!==div7) $fatal(1,"OLED clock not connected to the custom divider");
        if (reset) begin last_tick=0; previous_tick=0; end
        else begin
            if (physics_tick) begin
                if (previous_tick || (last_tick!=0 && cycles-last_tick!=5)) $fatal(1,"Physics enable width/spacing incorrect");
                last_tick=cycles; ticks=ticks+1;
            end
            previous_tick=physics_tick;
        end
    end
    initial begin
        repeat(300) @(negedge clk);
        if (reset || oled_reset || ticks<3) $fatal(1,"Power-on reset did not release correctly");
        reset_button=1; repeat(20) @(negedge clk);
        if (!reset || !oled_reset) $fatal(1,"Button reset did not reach both domains");
        reset_button=0; repeat(40) @(negedge clk);
        if (reset || oled_reset) $fatal(1,"Reset release did not recover");
        $display("PASS clock_control_tb: supplied divider frequencies, OLED wiring, physics enables, startup and reset recovery");
        $finish;
    end
    initial begin #10000; $fatal(1,"Clock test timed out"); end
endmodule
