`timescale 1ns/1ps
`include "game_defs.vh"

// Verifies the special tutorial retry stop: after the TNT has been shown once,
// a retry waits while the TNT is visible. BTNR fires the short tutorial rocket
// and releases the vehicle so it can clear the crate.
module tutorial_retry_tb;
    reg clk = 1'b0;
    reg btnD = 1'b0, btnC = 1'b0, btnU = 1'b0, btnL = 1'b0, btnR = 1'b0;
    reg [15:0] sw = 16'd0;
    tri PS2Clk, PS2Data;
    wire [15:0] led;
    wire [7:0] JA, JB;
    wire [6:0] seg;
    wire [3:0] an;
    wire dp;
    wire [3:0] JXADC;

    always #5 clk = ~clk;

    My_Top_Module #(
        .ENABLE_START_SCREEN(0), .ENABLE_BGM(0),
        .PHYSICS_CYCLES(1000000), .BUTTON_DEBOUNCE_CYCLES(1),
        .BUTTON_RELEASE_CYCLES(1)
    ) dut (
        .clk(clk), .btnD(btnD), .btnC(btnC), .btnU(btnU),
        .btnL(btnL), .btnR(btnR), .sw(sw),
        .PS2Clk(PS2Clk), .PS2Data(PS2Data), .JA(JA), .JB(JB),
        .JXADC(JXADC), .led(led), .seg(seg), .an(an), .dp(dp)
    );

    task clock_n;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) @(posedge clk);
        end
    endtask

    initial begin
        btnD = 1'b1;
        clock_n(8);
        btnD = 1'b0;
        // clock_control also has a power-on reset counter of 255 cycles.
        clock_n(270);

        // The engine is mouse-only, so every tutorial retry starts with it off.
        force dut.level_index = `LP_LEVEL_TUTORIAL;
        force dut.game_state = `LP_INIT_RUN;
        force dut.run_init = 1'b1;
        clock_n(2);
        if (dut.ui_engine_on)
            $fatal(1, "Tutorial retry did not start with the engine off");
        release dut.run_init;

        // Model a completed TNT demonstration followed by the retry/build state.
        force dut.game_state = `LP_BUILD;
        clock_n(4);
        if (dut.build_grid[5:3] !== `LP_PART_BOOSTER ||
            dut.build_facing_down[1] !== 1'b1 || dut.build_facing_left[1] !== 1'b0)
            $fatal(1, "Tutorial rocket is not seeded as a centered upward rocket");
        // The real retry may enter INIT_RUN while the TNT is still spent,
        // before tnt_controller restores its intact mask.  That condition
        // must arm the guided retry even if the display flag was delayed.
        force dut.tnt_intact = {`LP_MAX_TNT{1'b0}};
        force dut.tutorial_tnt_seen = 1'b0;
        clock_n(2);
        if (!dut.tutorial_retry_pending)
            $fatal(1, "Spent TNT did not arm the tutorial retry prompt");

        force dut.tnt_intact = {`LP_MAX_TNT{1'b1}};
        force dut.tutorial_tnt_seen = 1'b1;
        force dut.right_press = 1'b0;
        clock_n(2);
        if (!dut.tutorial_retry_pending)
            $fatal(1, "Tutorial retry did not arm the pre-TNT prompt");

        // x=88 leaves the x=128 TNT inside the close-up view with a safety
        // margin. The retry must stop before the vehicle reaches the normal
        // contact boundary at about x=104.
        force dut.game_state = `LP_RUN;
        force dut.vehicle_x = 20'sd22528;
        clock_n(1);
        if (!dut.tutorial_pause_active || !dut.tutorial_retry_waiting)
            $fatal(1, "Tutorial did not pause before TNT");

        // It must remain stopped until the player performs the instructed
        // rocket action.
        clock_n(12);
        if (!dut.tutorial_pause_active || !dut.tutorial_retry_waiting)
            $fatal(1, "Tutorial pre-TNT pause ended before the clearing action");

        force dut.right_press = 1'b1;
        clock_n(1);
        if (dut.tutorial_pause_active || dut.tutorial_retry_waiting)
            $fatal(1, "BTNR did not fire the rocket and release the tutorial pause");
        if (dut.tutorial_next_prompt != 3'd4)
            $fatal(1, "Tutorial did not continue to the fan lesson after the rocket");
        if (!dut.tutorial_tnt_avoid_active || !dut.u_tnt.suppress_trigger)
            $fatal(1, "Guided rocket did not arm the tutorial TNT safety corridor");

        // The same BTNR press must also reach the physics one-shot.  This
        // bench uses a slow physics tick, so the short tutorial fuel value is
        // still visible after the request is accepted.
        force dut.right_press = 1'b0;
        clock_n(2);
        if (!dut.u_physics.rocket_spent ||
            dut.u_physics.rocket_fuel != 7'd16)
            $fatal(1, "BTNR released the pause without firing the tutorial rocket");

        // Verify initial lesson engine-tile click immediately releases tutorial_pause_active,
        // and left_renderer highlights the expected target cells (Engine=3, Rocket=1, Fan=7).
        force dut.game_state = `LP_BUILD;
        force dut.tnt_intact = {`LP_MAX_TNT{1'b1}};
        force dut.tutorial_tnt_seen = 1'b0;
        force dut.vehicle_x = 20'sd4096; // start pose (< 40 px) -> prompt 0
        clock_n(2);
        release dut.tutorial_tnt_seen;
        force dut.game_state = `LP_RUN;
        clock_n(2);
        if (dut.tutorial_pause_active !== 1'b1 || dut.tutorial_prompt_index !== 3'd0)
            $fatal(1, "Tutorial start did not enter initial prompt 0 pause");

        force dut.draw_state = `LP_RUN;
        force dut.draw_level = `LP_LEVEL_TUTORIAL;
        force dut.draw_engine = 1'b0;
        force dut.draw_x = 20'sd4096;
        clock_n(1);
        if (dut.u_left_renderer.tutorial_target_cell !== 4'd3)
            $fatal(1, "Tutorial start did not highlight Engine cell 3 (got %0d)", dut.u_left_renderer.tutorial_target_cell);

        force dut.mouse_engine_toggle_req = 1'b1;
        clock_n(1);
        force dut.mouse_engine_toggle_req = 1'b0;
        clock_n(1);
        if (dut.tutorial_pause_active !== 1'b0)
            $fatal(1, "Clicking the Engine tile did not immediately unpause the initial tutorial lesson");

        // Check Rocket cell 1 target highlight before TNT on guided retry, and Fan cell 7 highlight at x=168..191 px.
        force dut.draw_engine = 1'b1;
        force dut.draw_tutorial_tnt_seen = 1'b1;
        force dut.draw_x = 20'sd22528; // x=88 px
        clock_n(1);
        if (dut.u_left_renderer.tutorial_target_cell !== 4'd1)
            $fatal(1, "Tutorial retry before TNT did not highlight Rocket cell 1 (got %0d)", dut.u_left_renderer.tutorial_target_cell);

        force dut.draw_x = 20'sd45056; // x=176 px (fan lesson)
        force dut.draw_tutorial_fan_tested = 1'b0;
        clock_n(1);
        if (dut.u_left_renderer.tutorial_target_cell !== 4'd7)
            $fatal(1, "Tutorial fan lesson did not highlight Fan cell 7 (got %0d)", dut.u_left_renderer.tutorial_target_cell);

        $display("PASS tutorial_retry_tb: retry pauses before TNT, BTNR fires rocket, and target tiles blink/unpause");
        $finish;
    end
endmodule
