`timescale 1ns/1ps
`include "game_defs.vh"

// Owner: Role 4 - Marcus. With two rockets on the cart, clicking one must fire only
// that one, each burns for its own full time, and spent rockets stay spent until a
// retry. A clicked balloon must also play its pop on both OLEDs and then finish.
module individual_rockets_tb;
    reg clk = 1'b0, btnD = 1'b1;
    reg [11:0] mx = 12'd0, my = 12'd0;
    reg ml = 1'b0, me = 1'b0;
    tri1 PS2Clk, PS2Data;
    // Cells: balloon, rocket, rocket / engine, pig, frame-only / wheel, empty, wheel.
    localparam [26:0] GRID = {`LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL,
                              `LP_PART_EMPTY, `LP_PART_PIG, `LP_PART_ENGINE,
                              `LP_PART_BOOSTER, `LP_PART_BOOSTER, `LP_PART_BALLOON};
    always #5 clk = ~clk;

    My_Top_Module #(
        .ENABLE_START_SCREEN(0), .ENABLE_BGM(0), .PHYSICS_CYCLES(5000),
        .BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk), .btnD(btnD), .btnC(1'b0), .btnU(1'b0), .btnL(1'b0), .btnR(1'b0), .sw(16'd0),
        .PS2Clk(PS2Clk), .PS2Data(PS2Data), .JA(), .JB(), .JXADC(), .led(), .seg(), .an(), .dp()
    );

    initial begin
        force dut.mouse_x = mx; force dut.mouse_y = my;
        force dut.mouse_left = ml; force dut.mouse_right = 1'b0; force dut.mouse_event = me;
        force dut.left_frame = 1'b1;
    end

    task clocks; input integer n; begin repeat (n) @(negedge clk); end endtask
    task packet; input integer x, y; input l; begin mx = x; my = y; ml = l; me = 1; clocks(1); me = 0; clocks(4); end endtask
    task click; input integer x, y; begin packet(x, y, 0); packet(x, y, 1); packet(x, y, 0); end endtask
    task wait_steps; input integer n; begin clocks(n * 5000); end endtask

    integer first_fuel, waited;
    initial begin
        clocks(20); btnD = 1'b0; clocks(300);
        force dut.level_index = `LP_LEVEL_FLIGHT;
        force dut.u_builder.build_grid = GRID;
        force dut.u_builder.build_frames = 9'b000111000;
        force dut.u_builder.build_facing_down = 9'b000000110;
        force dut.u_builder.build_facing_left = 9'b000000000;
        clocks(4);
        if (!dut.build_valid) $fatal(1, "Two-rocket fixture is not a valid build");
        force dut.u_game.launch_req = 1'b1; clocks(1); force dut.u_game.launch_req = 1'b0; release dut.u_game.launch_req;
        clocks(20);
        if (dut.game_state !== `LP_RUN) $fatal(1, "Fixture did not launch");
        if (!dut.rocket_ready || dut.rocket_active) $fatal(1, "Rockets not ready at launch");
        if (dut.rocket_present_mask !== 9'b000000110) $fatal(1, "Rocket cells not recognised");

        // Fire the rocket in cell 1 only. Run grid cells are 16 px from (24, 2).
        click(46, 8);
        clocks(2);
        if (dut.rocket_burn_mask !== 9'b000000010) $fatal(1, "Clicking cell 1 lit rockets %b", dut.rocket_burn_mask);
        if (dut.rocket_spent_mask !== 9'b000000010) $fatal(1, "Clicking cell 1 spent rockets %b", dut.rocket_spent_mask);
        if (!dut.rocket_ready) $fatal(1, "The second rocket should still be ready");
        if (dut.rocket_vertical_balance !== -5'sd1) $fatal(1, "Only one rocket should push, balance %0d", dut.rocket_vertical_balance);
        // Clicking the same rocket again does nothing.
        wait_steps(4);
        first_fuel = dut.u_physics.rocket_fuel;
        click(46, 8);
        clocks(2);
        if (dut.u_physics.rocket_fuel > first_fuel) $fatal(1, "A spent rocket refilled its fuel");
        if (dut.rocket_burn_mask !== 9'b000000010) $fatal(1, "Re-clicking changed which rockets burn");

        // Now fire the second: both burn, each on its own timer.
        click(62, 8);
        clocks(2);
        if (dut.rocket_burn_mask !== 9'b000000110) $fatal(1, "Clicking cell 2 did not add its rocket: %b", dut.rocket_burn_mask);
        if (dut.rocket_vertical_balance !== -5'sd2) $fatal(1, "Two burning rockets should both push");
        if (dut.rocket_ready) $fatal(1, "No rocket should remain ready");
        if (dut.u_physics.second_rocket_fuel <= dut.u_physics.rocket_fuel)
            $fatal(1, "The second rocket must have more fuel left than the first");

        // Pop the balloon: the pop plays on both renderers for three phases, then stops.
        click(30, 8);
        // The pop waits for the idle slot between physics steps.
        waited = 0;
        while (dut.intact_mask[0] && waited < 400000) begin clocks(1); waited = waited + 1; end
        if (dut.intact_mask[0]) $fatal(1, "Balloon was not popped");
        clocks(300); // The pop reaches the renderers through the CDC snapshot.
        if (dut.balloon_pop_mask !== 9'b000000001 || dut.balloon_pop_phase !== 2'd1)
            $fatal(1, "Pop did not start: mask %b phase %0d", dut.balloon_pop_mask, dut.balloon_pop_phase);
        if (dut.draw_balloon_pop_mask !== 9'b000000001) $fatal(1, "Pop did not reach the renderers");
        wait_steps(10);
        if (dut.balloon_pop_phase !== 2'd2) $fatal(1, "Pop did not advance to its shards");
        wait_steps(8);
        if (dut.balloon_pop_phase !== 2'd3) $fatal(1, "Pop did not advance to its last phase");
        wait_steps(10);
        if (dut.balloon_pop_phase !== 2'd0 || dut.balloon_pop_mask !== 9'd0) $fatal(1, "Pop never finished");

        // Retry restores both rockets.
        click(12, 58);
        clocks(20);
        if (dut.rocket_spent_mask !== 9'd0 || dut.rocket_burn_mask !== 9'd0) $fatal(1, "Retry did not restore the rockets");

        $display("PASS individual_rockets_tb: each rocket fires alone on its own timer, spent rockets stay spent, retry restores them, and the balloon pop plays and ends");
        $finish;
    end
endmodule
