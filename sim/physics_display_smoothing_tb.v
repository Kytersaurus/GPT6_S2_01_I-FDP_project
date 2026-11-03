// Owner: Shared - verifies the visual-only horizontal interpolation.
`timescale 1ns / 1ps
`include "game_defs.vh"

module physics_display_smoothing_tb;
    reg clk = 0, reset = 1, run_init = 0, step_start = 0, update_release = 0;
    reg [2:0] game_state = `LP_BUILD;
    reg move_ready = 0, response_valid = 0;
    reg signed [19:0] corrected_x = 20'sd1024, corrected_y = 20'sd8192;
    reg signed [15:0] corrected_vx = 0, corrected_vy = 0;
    wire init_ready, move_valid, response_ready, committed;
    wire signed [19:0] previous_x, previous_y, proposed_x, proposed_y;
    wire signed [15:0] proposed_vx, proposed_vy;
    wire signed [19:0] vehicle_x, vehicle_y, display_x, display_y;
    integer waited, i;
    reg signed [19:0] previous_display;

    always #5 clk = ~clk;

    physics_engine dut (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init),
        .init_ready(init_ready), .spawn_x(20'sd1024), .spawn_y(20'sd8192),
        .step_start(step_start), .update_release(update_release),
        .wheel_count(4'd0), .engine_count(4'd0), .balloon_count(4'd0),
        .mass_units(8'd11), .engine_enabled(1'b0), .engine_reverse(1'b0),
        .jump_press(1'b0), .boost_req(1'b0), .moments_enabled(1'b0),
        .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y),
        .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy),
        .grounded(1'b1), .ground_slope(8'sd0), .ground_slope_valid(1'b1),
        .corrected_tilt(5'sd0), .tip_dir(2'sd0), .support_unstable(1'b0),
        .movement_committed(committed), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y),
        .display_x(display_x), .display_y(display_y)
    );

    task clocks;
        input integer count;
        begin repeat (count) @(negedge clk); end
    endtask

    task begin_step;
        begin
            step_start = 1'b1;
            clocks(1);
            step_start = 1'b0;
            waited = 0;
            while (!move_valid && waited < 200) begin
                clocks(1);
                waited = waited + 1;
            end
            if (!move_valid) $fatal(1, "Display smoothing movement request timed out");
        end
    endtask

    task finish_step;
        input integer target_x;
        input integer target_vx;
        begin
            corrected_x = target_x;
            corrected_y = 20'sd8192;
            corrected_vx = target_vx;
            corrected_vy = 16'sd0;
            move_ready = 1'b1;
            clocks(1);
            move_ready = 1'b0;
            if (!response_ready) $fatal(1, "Display smoothing response was not ready");
            response_valid = 1'b1;
            clocks(1);
            response_valid = 1'b0;
            if (!committed || vehicle_x !== corrected_x)
                $fatal(1, "Physics pose did not commit for display smoothing");
            if (display_y !== corrected_y)
                $fatal(1, "Grounded display y was filtered away from the accepted contact");
            clocks(1);
            update_release = 1'b1;
            clocks(1);
            update_release = 1'b0;
        end
    endtask

    initial begin
        clocks(3);
        reset = 1'b0;
        game_state = `LP_INIT_RUN;
        run_init = 1'b1;
        clocks(3);
        if (!init_ready) $fatal(1, "Display smoothing physics did not initialise");
        run_init = 1'b0;
        game_state = `LP_RUN;

        // Seed a steady two-pixel-per-update ground motion through the public
        // collision response. The raw physics pose must still commit exactly.
        begin_step;
        finish_step(1024, 512);
        previous_display = display_x;

        // The rendered x position should move monotonically, remain behind the
        // raw pose while coasting, and therefore interpolate rather than jump.
        for (i = 0; i < 6; i = i + 1) begin
            begin_step;
            if (proposed_x <= previous_x)
                $fatal(1, "Ground motion did not advance: previous=%0d proposed=%0d", previous_x, proposed_x);
            finish_step(proposed_x, proposed_vx);
            if (display_x <= previous_display)
                $fatal(1, "Display x did not move smoothly: previous=%0d current=%0d", previous_display, display_x);
            if (display_x >= vehicle_x)
                $fatal(1, "Display x overshot the committed pose: display=%0d raw=%0d", display_x, vehicle_x);
            previous_display = display_x;
        end

        // Large corrections still snap immediately, preventing visible lag on
        // retry, teleport-like fixtures or a substantial collision correction.
        begin_step;
        finish_step(vehicle_x + 20*256, 0);
        if (display_x !== vehicle_x)
            $fatal(1, "Large correction was smoothed instead of snapped");

        $display("PASS physics_display_smoothing_tb: ground x interpolation is monotonic, grounded y is exact and large corrections snap");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Display smoothing test timed out");
    end
endmodule
