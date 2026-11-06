`timescale 1ns/1ps
`include "game_defs.vh"

// Owner: Role 4 - Marcus. The tutorial forgives leaving the world only for the
// short recovery window after its TNT blast. Once that window expires, flying
// out of bounds must fail the run again, even though the TNT stays spent.
module tutorial_bounds_tb;
    reg clk = 1'b0;
    reg btnD = 1'b1;
    tri PS2Clk, PS2Data;
    always #5 clk = ~clk;

    My_Top_Module #(
        .ENABLE_START_SCREEN(0), .ENABLE_BGM(0),
        .PHYSICS_CYCLES(20), .BUTTON_DEBOUNCE_CYCLES(1), .BUTTON_RELEASE_CYCLES(1)
    ) dut (
        .clk(clk), .btnD(btnD), .btnC(1'b0), .btnU(1'b0), .btnL(1'b0), .btnR(1'b0),
        .sw(16'd0), .PS2Clk(PS2Clk), .PS2Data(PS2Data), .JA(), .JB(),
        .JXADC(), .led(), .seg(), .an(), .dp()
    );

    task clocks;
        input integer count;
        begin repeat (count) @(negedge clk); end
    endtask

    integer ticks;
    initial begin
        clocks(20); btnD = 1'b0; clocks(40);
        // Hold a tutorial run with the cart parked before the TNT (x=144 px,
        // the TNT lesson) so no teaching pause interrupts the check.
        force dut.level_index = `LP_LEVEL_TUTORIAL;
        force dut.game_state = `LP_RUN;
        force dut.vehicle_x = 20'sd30000;
        force dut.tnt_intact = 3'b111;
        clocks(200);
        if (dut.tutorial_bounds_grace) $fatal(1, "Bounds grace active before the TNT blast");

        // The TNT goes off: grace must cover the edge clock itself.
        force dut.tnt_intact = 3'b110;
        #1;
        if (!dut.tutorial_bounds_grace) $fatal(1, "Bounds grace missed the TNT edge clock");
        clocks(1);
        if (!dut.tutorial_bounds_grace) $fatal(1, "Bounds grace did not start after the blast");

        // After the 90-frame recovery window, leaving the world fails again.
        ticks = 0;
        while (dut.tutorial_bounds_grace && ticks < 200000) begin clocks(1); ticks = ticks + 1; end
        if (dut.tutorial_bounds_grace) $fatal(1, "Bounds grace never expired");
        clocks(500);
        if (dut.tutorial_bounds_grace || dut.tnt_intact[0])
            $fatal(1, "Spent TNT kept out-of-bounds failure disabled");

        $display("PASS tutorial_bounds_tb: TNT edge grace, 90-frame recovery window, normal bounds failure afterwards");
        $finish;
    end
endmodule
