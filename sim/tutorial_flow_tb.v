`timescale 1ns/1ps
`include "game_defs.vh"

// Owner: Role 4 - Marcus. Plays the whole tutorial through the real game, physics and
// collision logic, with mouse clicks and wheel steps at the top level. It checks each
// lesson's pause, its message state and its glowing control, then that the cart lands
// short of the flag, rolls right to it and never leaves the world. It also exports the
// real OLED pixels at each stage as *_left.hex and *_right.hex for visual review.
module tutorial_flow_tb;
    reg clk = 1'b0, btnD = 1'b1;
    reg [11:0] mx = 12'd0, my = 12'd0;
    reg ml = 1'b0, me = 1'b0;
    reg [3:0] mz = 4'd0;
    reg [12:0] pixel = 13'd0;
    tri1 PS2Clk, PS2Data;
    integer ticks, p, left_file, right_file;
    reg signed [19:0] landed_x;
    always #5 clk = ~clk;

    My_Top_Module #(
        .ENABLE_START_SCREEN(1), .ENABLE_BGM(0), .PHYSICS_CYCLES(4000),
        .BUTTON_DEBOUNCE_CYCLES(2), .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk), .btnD(btnD), .btnC(1'b0), .btnU(1'b0), .btnL(1'b0), .btnR(1'b0), .sw(16'd0),
        .PS2Clk(PS2Clk), .PS2Data(PS2Data), .JA(), .JB(), .JXADC(), .led(), .seg(), .an(), .dp()
    );

    initial begin
        force dut.mouse_x = mx; force dut.mouse_y = my;
        force dut.mouse_left = ml; force dut.mouse_right = 1'b0;
        force dut.mouse_event = me; force dut.mouse_z = mz;
        // Publish the snapshot every clock so frames can be exported without
        // simulating the OLEDs' full 60 Hz refresh, and read chosen pixels.
        force dut.left_frame = 1'b1;
        force dut.left_pixel_index = 13'd6143 - pixel;
        force dut.right_pixel_index = pixel;
    end

    task clocks; input integer n; begin repeat (n) @(negedge clk); end endtask
    task packet; input integer x, y; input l; begin mx = x; my = y; ml = l; me = 1; clocks(1); me = 0; clocks(4); end endtask
    task click; input integer x, y; begin packet(x, y, 0); packet(x, y, 1); packet(x, y, 0); end endtask
    task wheel; input [3:0] delta; begin mz = delta; me = 1; clocks(1); me = 0; mz = 0; clocks(4); end endtask

    task frame;
        input [255:0] name;
        begin
            left_file = $fopen({name, "_left.hex"}, "w");
            right_file = $fopen({name, "_right.hex"}, "w");
            for (p = 0; p < 6144; p = p + 1) begin
                pixel = p;
                @(posedge dut.oled_clk); @(posedge dut.oled_clk); #1;
                $fdisplay(left_file, "%h", dut.left_pixel_data);
                $fdisplay(right_file, "%h", dut.right_pixel_data);
            end
            $fclose(left_file); $fclose(right_file);
            // Return to the falling edge the mouse tasks are timed from.
            clocks(1);
        end
    endtask

    // Waits for a lesson; meanwhile the run must not have ended.
    task wait_for_lesson;
        input [`LP_LESSON_BITS-1:0] lesson;
        begin
            ticks = 0;
            while (dut.tutorial_lesson !== lesson && ticks < 60000000) begin
                clocks(1);
                ticks = ticks + 1;
                if (dut.game_state === `LP_FAIL) $fatal(1, "Run failed waiting for lesson %0d at x=%0d y=%0d", lesson, dut.vehicle_x >>> 8, dut.vehicle_y >>> 8);
                if (dut.game_state === `LP_SUCCESS) $fatal(1, "Run succeeded early waiting for lesson %0d", lesson);
            end
            if (dut.tutorial_lesson !== lesson) $fatal(1, "Timed out waiting for lesson %0d, stuck in %0d (state %0d, x=%0d y=%0d, engine %b, zoom %b%b, grounded %b tilt %0d vx %0d vy %0d grace %0d intact %b frames %b wheels %0d busy %b falling %b wasg %b)", lesson, dut.tutorial_lesson, dut.game_state, dut.vehicle_x >>> 8, dut.vehicle_y >>> 8, dut.ui_engine_on, dut.overview, dut.zoomed_out, dut.grounded, dut.vehicle_tilt, dut.corrected_vx, dut.corrected_vy, dut.tutorial_tnt_grace_frames, dut.intact_mask, dut.frame_intact_mask, dut.wheel_count, dut.u_game.step_busy, dut.falling, dut.audio_was_grounded);
            clocks(40);
        end
    endtask

    // For short-lived lessons: lesson numbers rise along the route.
    task wait_for_lesson_or_later;
        input [`LP_LESSON_BITS-1:0] lesson;
        begin
            ticks = 0;
            while (dut.tutorial_lesson < lesson && ticks < 60000) begin
                clocks(1);
                ticks = ticks + 1;
            end
            if (dut.tutorial_lesson < lesson) $fatal(1, "Lesson %0d never reached, stuck in %0d", lesson, dut.tutorial_lesson);
        end
    endtask

    task expect_glow;
        input [3:0] glow_cell;
        begin
            clocks(600); // The lesson reaches the renderers through the CDC snapshot.
            if (dut.u_left_renderer.tutorial_target_cell !== glow_cell)
                $fatal(1, "Lesson %0d glows cell %0d, expected %0d", dut.tutorial_lesson, dut.u_left_renderer.tutorial_target_cell, glow_cell);
            if (!dut.tutorial_pause_active) $fatal(1, "Lesson %0d did not hold the world still", dut.tutorial_lesson);
        end
    endtask

    initial begin
        clocks(20); btnD = 1'b0; clocks(300);
        click(48, 40); // Play
        if (dut.game_state !== `LP_BUILD || dut.level_index !== `LP_LEVEL_TUTORIAL)
            $fatal(1, "Play did not open the tutorial");
        clocks(200);
        frame("tutorial_welcome");
        // The starting screen keeps its bottom buttons: GO, the book and the gear.
        pixel = 55*96 + 0; clocks(40);
        if (dut.left_pixel_data === 16'h0841) $fatal(1, "GO button missing from the tutorial start screen");
        pixel = 55*96 + 64; clocks(40);
        if (dut.left_pixel_data === 16'h0841) $fatal(1, "Book button missing from the tutorial start screen");
        pixel = 55*96 + 80; clocks(40);
        if (dut.left_pixel_data === 16'h0841) $fatal(1, "Gear button missing from the tutorial start screen");
        // The wheel must leave the map alone during BUILD.
        wheel(4'd1);
        if (dut.zoomed_out || dut.overview) $fatal(1, "Wheel zoomed the map during BUILD");
        wheel(4'd15);

        click(8, 59); // GO
        wait_for_lesson(`LP_LESSON_ZOOM_IN);
        if (!dut.tutorial_pause_active) $fatal(1, "Zoom lesson did not hold the world still");
        if (!dut.zoomed_out) $fatal(1, "Zoom lesson did not start from the normal view");
        frame("tutorial_zoom_in");
        // The engine ignores clicks until the zoom exercise is finished.
        click(30, 24);
        if (dut.ui_engine_on) $fatal(1, "Engine worked during the zoom exercise");
        wheel(4'd15);
        wait_for_lesson(`LP_LESSON_ZOOM_OUT);
        if (dut.zoomed_out) $fatal(1, "Scrolling in did not zoom in");
        frame("tutorial_zoom_out");
        wheel(4'd1);
        wait_for_lesson(`LP_LESSON_ENGINE);
        if (!dut.zoomed_out) $fatal(1, "Scrolling out did not zoom out");
        expect_glow(4'd3);
        frame("tutorial_engine");

        click(30, 24); // Engine on: the first attempt deliberately meets the TNT.
        wait_for_lesson(`LP_LESSON_STAR);
        wait_for_lesson(`LP_LESSON_TNT);
        wait_for_lesson(`LP_LESSON_TNT_FALL);
        wait_for_lesson(`LP_LESSON_RETRY);
        if (!dut.tutorial_pause_active) $fatal(1, "Retry lesson did not hold the world still");
        force dut.tutorial_blink_frames = 4'd8; clocks(40);
        frame("tutorial_retry");
        pixel = 53*96 + 2; clocks(40);
        if (dut.left_pixel_data !== 16'hffe0) $fatal(1, "Retry button does not glow on the left OLED");
        release dut.tutorial_blink_frames;

        click(12, 58); // The retry icon on the left OLED.
        wait_for_lesson(`LP_LESSON_ENGINE); // The zoom exercise is not repeated.
        expect_glow(4'd3);
        click(30, 24);
        wait_for_lesson(`LP_LESSON_ROCKET);
        expect_glow(4'd1);
        if ($signed(dut.vehicle_x) >= 20'sd26624) $fatal(1, "Rocket stop ran past x=104, onto the TNT");
        frame("tutorial_rocket");

        click(46, 8); // Fire the rocket.
        wait_for_lesson_or_later(`LP_LESSON_HOP);
        wait_for_lesson(`LP_LESSON_FAN_ON);
        expect_glow(4'd7);
        if (!dut.tnt_intact[0]) $fatal(1, "Guided route set off the TNT");
        // The rocket hop is a hop: the cart is back near the ground by the fan stop.
        if ($signed(dut.vehicle_y) < 20'sd20480) $fatal(1, "Rocket threw the cart too high (y=%0d at the fan stop)", dut.vehicle_y >>> 8);
        frame("tutorial_fan_on");

        click(46, 40); // Fan on.
        wait_for_lesson_or_later(`LP_LESSON_FAN_FLY);
        wait_for_lesson(`LP_LESSON_FAN_OFF);
        expect_glow(4'd7);
        // It must really have risen, and still be well inside the world.
        if ($signed(dut.vehicle_y) >= 20'sd19456) $fatal(1, "Fan did not lift the cart (y=%0d)", dut.vehicle_y >>> 8);
        if ($signed(dut.vehicle_y) < 20'sd15360) $fatal(1, "Fan flew too high (y=%0d)", dut.vehicle_y >>> 8);
        frame("tutorial_fan_off");

        click(46, 40); // Fan off: the cart drops.
        wait_for_lesson_or_later(`LP_LESSON_DROP);
        ticks = 0;
        while (dut.tutorial_lesson !== `LP_LESSON_FLAG && ticks < 60000000) begin
            clocks(1);
            ticks = ticks + 1;
            if (dut.game_state === `LP_FAIL) $fatal(1, "Cart left the world while dropping");
            if (dut.game_state === `LP_SUCCESS) $fatal(1, "Cart reached the goal without landing first");
        end
        landed_x = dut.vehicle_x;
        // The pig (cart x+12) must land before the goal at x=216.
        if ($signed(landed_x) >= 20'sd52224) $fatal(1, "Cart landed past the start of the goal (x=%0d)", landed_x >>> 8);
        frame("tutorial_flag");

        // Engine still on from the lesson: the cart rolls right, to the flag, and clears.
        ticks = 0;
        while (dut.game_state !== `LP_SUCCESS && ticks < 60000000) begin
            clocks(1);
            ticks = ticks + 1;
            if (dut.game_state === `LP_FAIL) $fatal(1, "Cart left the world on the way to the flag");
        end
        if (dut.game_state !== `LP_SUCCESS) $fatal(1, "Cart never reached the flag (x=%0d)", dut.vehicle_x >>> 8);
        if ($signed(dut.vehicle_x) <= $signed(landed_x)) $fatal(1, "Cart did not move right after landing");

        $display("Tutorial cart landed at x=%0d and cleared at x=%0d", landed_x >>> 8, dut.vehicle_x >>> 8);
        $display("PASS tutorial_flow_tb: buttons, zoom exercise, glowing controls, retry icon, guided route, landing before the flag and clearing");
        $finish;
    end
endmodule
