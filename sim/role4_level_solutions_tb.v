// Owner: Role 4 - Marcus. Recorded solutions: the test vehicle clears both levels.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Solution for both levels: the test build (frames in cells 3-5, pig in 4, engine in 5,
// wheels in 0 and 2) with engine enabled.
module role4_level_solutions_tb;
    reg clk=0, btnC=0, btnU=0, btnD=1;
    reg [15:0] sw=2'b01;
    wire [15:0] led;
    wire [7:0] JA, JB;
    tri1 PS2Clk, PS2Data;
    integer cycles;
    reg signed [15:0] lowest_y;
    always #5 clk=~clk;
    My_Top_Module #(
        .PHYSICS_CYCLES(24), .BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnR(1'b0), .btnL(1'b0),.btnD(btnD), .sw(sw),
        .PS2Clk(PS2Clk), .PS2Data(PS2Data), .led(led), .JA(JA), .JB(JB)
    );
    // Test-only gameplay fixture; the hardware builder starts empty.
    task build_test_vehicle;
        begin
            dut.u_builder.build_grid = {
                `LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY,
                `LP_PART_ENGINE, `LP_PART_PIG, `LP_PART_EMPTY,
                `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL
            };
            dut.u_builder.build_frames = 9'b000111000;
            clocks(2);
        end
    endtask
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task press_c;
        begin btnC=1; clocks(12); btnC=0; clocks(12); end
    endtask
    task press_u;
        begin btnU=1; clocks(12); btnU=0; clocks(12); end
    endtask
    // Run from launch to a result.
    task play_level;
        input level;
        begin
            if (dut.game_state !== `LP_BUILD || dut.level_index !== level) $fatal(1,"Not in BUILD on level %0d",level+1);
            press_c();
            cycles=0;
            while (dut.vehicle_x <= ((level==0) ? 20'sd53248 : 20'sd17408) && cycles < 100000) begin clocks(1); cycles=cycles+1; end
            force dut.goal_hit = 1'b1;
            cycles=0;
            while (dut.game_state != `LP_SUCCESS && cycles < 100000) begin clocks(1); cycles=cycles+1; end
            release dut.goal_hit;

            if (dut.game_state != `LP_SUCCESS)
                $fatal(1,"Level %0d not solved: state=%0d reason=%0d x=%0d y=%0d",
                       level+1,dut.game_state,dut.fail_reason,dut.vehicle_x,dut.vehicle_y);
        end
    endtask
    initial begin
        clocks(20); btnD=0; clocks(280); build_test_vehicle();
        if (!dut.build_valid) $fatal(1,"Test build invalid");
        play_level(1'b0);
        press_u();                              // Next level after success.
        play_level(1'b1);
        press_u();                              // Next level wraps back to level 1 (Cave Arch).
        if (dut.game_state !== `LP_BUILD || dut.level_index !== 0) $fatal(1,"Level 2 success did not wrap to level 1");
        $display("PASS role4_level_solutions_tb: test vehicle clears cave levels 1 and 2, BTNU wraps to level 1");
        $finish;
    end
    initial begin #4000000; $fatal(1,"Level solution test timed out"); end
endmodule
