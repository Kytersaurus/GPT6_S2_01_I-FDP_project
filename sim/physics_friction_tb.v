// Owner: Role 2 - Kyle. Force-based wheel friction and reverse checks.
`timescale 1ns / 1ps
`include "game_defs.vh"

module physics_friction_tb;
    reg clk = 0, reset = 1, run_init = 0;
    reg step_start = 0, update_release = 0;
    reg [2:0] game_state = `LP_BUILD;
    reg [3:0] wheels = 2, engines = 1;
    reg [7:0] mass = 11;
    reg engine_enabled = 0, engine_reverse = 0;
    reg move_ready = 0, response_valid = 0, grounded = 1;
    reg signed [`LP_COORD_BITS-1:0] cx = 0, cy = 0;
    reg signed [15:0] cvx = 0, cvy = 0;
    wire init_ready, move_valid, response_ready, committed;
    wire signed [`LP_COORD_BITS-1:0] px, py, nx, ny, x, y;
    wire signed [15:0] nvx, nvy;
    reg [4*`LP_COORD_BITS+31:0] held_request;
    integer steps, previous_velocity, wait_cycles;

    always #5 clk = ~clk;

    physics_engine dut (
        .clk(clk), .reset(reset), .game_state(game_state),
        .run_init(run_init), .init_ready(init_ready),
        .spawn_x(20'sd1024), .spawn_y(20'sd8192),
        .step_start(step_start), .update_release(update_release),
        .wheel_count(wheels), .engine_count(engines),
        .balloon_count(4'd0), .mass_units(mass),
        .engine_enabled(engine_enabled), .engine_reverse(engine_reverse),.jump_press(1'b0),
        .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(px), .previous_y(py),
        .proposed_x(nx), .proposed_y(ny), .proposed_vx(nvx), .proposed_vy(nvy),
        .response_valid(response_valid), .response_ready(response_ready),
        .corrected_x(cx), .corrected_y(cy),
        .corrected_vx(cvx), .corrected_vy(cvy), .grounded(grounded),
        .movement_committed(committed), .vehicle_x(x), .vehicle_y(y)
    );

    task clocks;
        input integer count;
        begin repeat (count) @(negedge clk); end
    endtask

    task begin_step;
        begin
            step_start = 1; clocks(1); step_start = 0;
            wait_cycles=0;
            while (!move_valid && wait_cycles<64) begin clocks(1); wait_cycles=wait_cycles+1; end
            if (!move_valid) $fatal(1, "Movement request missing");
        end
    endtask

    task finish_step;
        begin
            move_ready = 1; clocks(1); move_ready = 0;
            if (!response_ready) $fatal(1, "Collision response not accepted");
            response_valid = 1; clocks(1); response_valid = 0;
            if (!committed || x !== cx || y !== cy)
                $fatal(1, "Corrected movement did not commit");
            clocks(1);
            if (committed) $fatal(1, "Movement committed more than once");
            // A new tick must not bypass the pending world checks.
            step_start = 1; clocks(1); step_start = 0;
            if (move_valid) $fatal(1, "Movement bypassed world release");
            update_release = 1; clocks(1); update_release = 0;
        end
    endtask

    // Scripted collision responses establish starting velocity and contact.
    // No testbench writes or forces the engine's internal registers.
    task seed_state;
        input integer starting_velocity;
        input integer contact;
        begin
            reset = 1; game_state = `LP_BUILD; run_init = 0;
            step_start = 0; update_release = 0;
            move_ready = 0; response_valid = 0; grounded = contact;
            clocks(2); reset = 0;
            game_state = `LP_INIT_RUN; run_init = 1; clocks(2);
            if (!init_ready) $fatal(1, "Initialisation missing");
            run_init = 0; game_state = `LP_RUN;
            begin_step;
            cx = 1024; cy = 8192; cvx = starting_velocity; cvy = 0;
            finish_step;
        end
    endtask

    task expect_step;
        input integer expected_velocity;
        begin
            begin_step;
            if ($signed(nvx) !== expected_velocity)
                $fatal(1, "Expected vx=%0d, got %0d", expected_velocity, $signed(nvx));
            // Keep a flat-ground fixture while accepting horizontal proposals.
            cx = nx; cy = 8192; cvx = nvx; cvy = 0;
            finish_step;
        end
    endtask

    initial begin
        // Coasting loses speed gradually and stops without reversing.
        seed_state(7, 1); expect_step(6); expect_step(4); expect_step(2); expect_step(0); expect_step(0);
        seed_state(-7, 1); expect_step(-6); expect_step(-4); expect_step(-2); expect_step(0); expect_step(0);

        // Wheel count changes resistance: ten force units per wheel.
        wheels = 1; seed_state(100, 1); expect_step(100);
        wheels = 2; seed_state(100, 1); expect_step(99);
        wheels = 0; seed_state(100, 1); expect_step(100);

        // The same net force produces more acceleration after mass falls.
        wheels = 2; engine_enabled = 1;
        seed_state(0, 1); expect_step(6);
        mass = 8; expect_step(15);
        mass = 11; engine_reverse = 1;
        seed_state(0, 1); expect_step(-6);

        // Reverse thrust first brakes, then produces opposite movement.
        seed_state(20, 1); expect_step(10); expect_step(0); expect_step(-6);
        engine_reverse = 0;
        seed_state(-20, 1); expect_step(-10); expect_step(0); expect_step(6);

        // At rest, friction can balance an engine but cannot move the body.
        wheels = 10; seed_state(0, 1); expect_step(0);
        wheels = 15; seed_state(0, 1); expect_step(0);
        engine_enabled = 0; seed_state(0, 1); expect_step(0);

        // Airborne wheels produce no ground friction or ground-engine thrust.
        wheels = 9; engine_enabled = 1;
        seed_state(100, 0); expect_step(100);
        engine_reverse = 1;
        seed_state(-100, 0); expect_step(-100);

        // More engines increase thrust; horizontal speed remains capped.
        wheels = 2; engines = 2; engine_reverse = 0;
        seed_state(0, 1); expect_step(15);
        wheels = 0; engines = 1; mass = 1;
        seed_state(250, 1); expect_step(256);
        engine_reverse = 1;
        seed_state(-250, 1); expect_step(-256);

        // Zero mass is guarded instead of dividing by zero.
        mass = 0; seed_state(0, 1); expect_step(0);

        // A complete coast from maximum speed must stop monotonically.
        mass = 11; wheels = 2; engine_enabled = 0; engine_reverse = 0;
        seed_state(256, 1);
        steps = 0; previous_velocity = 256;
        while (previous_velocity != 0 && steps < 200) begin
            begin_step;
            if ($signed(nvx) < 0 || $signed(nvx) >= previous_velocity)
                $fatal(1, "Coasting failed to slow monotonically");
            previous_velocity = $signed(nvx);
            cx = nx; cy = 8192; cvx = nvx; cvy = 0;
            finish_step;
            steps = steps + 1;
        end
        if (previous_velocity != 0) $fatal(1, "Coasting never stopped");

        // Inputs may change while stalled, but published requests must not.
        seed_state(40, 1); begin_step;
        held_request = {px, py, nx, ny, nvx, nvy};
        engine_enabled = 1; engine_reverse = 1; wheels = 0; mass = 1;
        clocks(5);
        if (!move_valid || {px, py, nx, ny, nvx, nvy} !== held_request || x !== 16'sd1024)
            $fatal(1, "Stalled request changed or committed early");
        cx = nx; cy = 8192; cvx = nvx; cvy = 0;
        finish_step;

        // Retry clears motion, even after an active run.
        game_state = `LP_INIT_RUN; run_init = 1; clocks(2);
        if (!init_ready || x !== 16'sd1024 || y !== 16'sd8192)
            $fatal(1, "Retry did not restore spawn");
        engine_enabled = 0; wheels = 2; mass = 11;
        run_init = 0; game_state = `LP_RUN; expect_step(0);

        $display("PASS physics_friction_tb: wheel count, mass, coasting, reverse, airborne motion, speed limits, stable transactions, retry");
        $finish;
    end

    initial begin #1000000; $fatal(1, "Friction test timed out"); end
endmodule
