`timescale 1ns/1ps
`include "game_defs.vh"

// Verifies the special tutorial retry stop: after the TNT has been shown once,
// a retry waits while the TNT is visible. Clicking the rocket cell fires the
// short tutorial rocket and releases the vehicle so it can clear the crate.
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

        force dut.game_state = `LP_BUILD;
        clock_n(4);
        if (dut.build_grid[5:3] !== `LP_PART_BOOSTER ||
            dut.build_facing_down[1] !== 1'b1 || dut.build_facing_left[1] !== 1'b0)
            $fatal(1, "Tutorial rocket is not seeded as a centered upward rocket");

        // Model a completed TNT demonstration followed by a retry that has already
        // finished the wheel lesson: it restarts at the engine, not at the zoom.
        force dut.tutorial_tnt_seen = 1'b1;
        force dut.tutorial_zoom_done = 1'b1;
        force dut.run_init = 1'b1;
        clock_n(2);
        if (dut.tutorial_lesson !== `LP_LESSON_ENGINE)
            $fatal(1, "Retry did not restart from the engine lesson");
        release dut.run_init;
        force dut.game_state = `LP_RUN;
        clock_n(1);
        if (!dut.tutorial_pause_active)
            $fatal(1, "The engine lesson did not hold the world still");

        // Clicking the engine releases the world.
        force dut.ui_engine_on = 1'b1;
        clock_n(2);
        if (dut.tutorial_lesson !== `LP_LESSON_STAR || dut.tutorial_pause_active)
            $fatal(1, "Engine click did not release the world");

        // x=88 leaves the x=128 TNT inside the close-up view with a safety
        // margin. The retry must stop before the vehicle reaches the normal
        // contact boundary at about x=104.
        force dut.vehicle_x = 20'sd22528;
        clock_n(3);
        if (dut.tutorial_lesson !== `LP_LESSON_ROCKET || !dut.tutorial_pause_active)
            $fatal(1, "Tutorial did not pause before TNT");

        // It must remain stopped until the player performs the instructed
        // rocket action.
        clock_n(12);
        if (dut.tutorial_lesson !== `LP_LESSON_ROCKET || !dut.tutorial_pause_active)
            $fatal(1, "Tutorial pre-TNT pause ended before the clearing action");
        if (dut.btnR !== 1'b0) $fatal(1, "Bench must not need BTNR");

        // The physical right button no longer does anything at all.
        btnR = 1'b1;
        clock_n(4);
        btnR = 1'b0;
        clock_n(2);
        if (dut.tutorial_lesson !== `LP_LESSON_ROCKET || dut.u_physics.rocket_spent)
            $fatal(1, "BTNR still fired the rocket");

        // A click on the rocket's own cell fires it and continues the route.
        force dut.mouse_boost_cell = 4'd1;
        force dut.mouse_boost_req = 1'b1;
        clock_n(1);
        force dut.mouse_boost_req = 1'b0;
        clock_n(1);
        if (dut.tutorial_lesson !== `LP_LESSON_HOP || dut.tutorial_pause_active)
            $fatal(1, "Rocket click did not release the tutorial pause");
        if (!dut.tutorial_tnt_avoid_active || !dut.u_tnt.suppress_trigger)
            $fatal(1, "Guided rocket did not arm the tutorial TNT safety corridor");

        // The same click must also reach the physics one-shot. This bench uses a
        // slow physics tick, so the short tutorial fuel value is still visible.
        clock_n(2);
        if (dut.u_physics.rocket_spent_mask !== 9'b000000010 ||
            dut.u_physics.rocket_fuel != 7'd5)
            $fatal(1, "Rocket click released the pause without firing the tutorial rocket");

        $display("PASS tutorial_retry_tb: retry pauses before TNT, BTNR is dead, and clicking the rocket fires it");
        $finish;
    end
endmodule
