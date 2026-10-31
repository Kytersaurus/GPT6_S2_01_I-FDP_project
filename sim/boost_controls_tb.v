// Owner: Role 1 - Kaushal. Test mouse boost and exclusion of ordinary sprite clicks.
`timescale 1ns / 1ps
`include "game_defs.vh"
module boost_controls_tb;
    reg clk = 0, btnD = 1;
    always #5 clk = ~clk;

    reg [11:0] mouse_x = 0, mouse_y = 0;
    reg mouse_left = 0, mouse_right = 0, mouse_event = 0;
    reg start = 0;
    tri1 PS2Clk, PS2Data;

    My_Top_Module #(
        .BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk), .btnC(1'b0), .btnU(1'b0), .btnR(1'b0), .btnL(1'b0), .btnD(btnD), .sw(16'h0001), // SW0 on
        .PS2Clk(PS2Clk), .PS2Data(PS2Data), .led(), .JA(), .JB(), .JXADC()
    );

    initial begin
        force dut.mouse_x = mouse_x;
        force dut.mouse_y = mouse_y;
        force dut.mouse_left = mouse_left;
        force dut.mouse_right = mouse_right;
        force dut.mouse_event = mouse_event;
        force dut.start_press = start;
    end

    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask

    task packet;
        input [11:0] x, y;
        input l, r;
        begin
            mouse_x = x; mouse_y = y; mouse_left = l; mouse_right = r;
            mouse_event = 1; clocks(1); mouse_event = 0; clocks(2);
        end
    endtask

    task left_click;
        input [11:0] x, y;
        begin
            packet(x, y, 0, 0);
            packet(x, y, 1, 0);
            packet(x, y, 0, 0);
        end
    endtask

    initial begin
        clocks(20);
        btnD = 0;
        clocks(280); // Wait for the shared startup reset before installing the build.

        // Put vehicle in builder
        dut.u_builder.build_grid = {
            `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
            `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
            `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY
        };
        dut.u_builder.build_frames = 9'b000111000;
        clocks(2);

        // Launch into RUN
        start = 1; clocks(2); start = 0;
        while (dut.game_state != `LP_RUN) clocks(1);
        clocks(5);

        if (dut.boost_active) $fatal(1, "Boost active before any click");

        // Click outside button
        left_click(12'd90, 12'd46);
        clocks(2);
        if (dut.boost_active) $fatal(1, "Boost triggered outside button");

        // Ordinary vehicle clicks must not trigger an invisible old boost row.
        left_click(12'd60, 12'd40);clocks(2);
        if(dut.boost_active) $fatal(1,"Wheel sprite triggered invisible boost control");
        // The compatible left-panel boost shortcut stays outside the vehicle.
        left_click(12'd20,12'd40);clocks(2);
        if (!dut.boost_active) $fatal(1, "Left-panel boost shortcut failed to activate");

        $display("PASS boost_controls_tb: left-panel boost activation and ordinary sprite-click exclusion");
        $finish;
    end
    initial begin #200000; $fatal(1,"Boost control test timed out"); end
endmodule
