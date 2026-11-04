`timescale 1ns / 1ps
`include "game_defs.vh"

module crash_impact_tb;
    reg clk;
    reg btnD;
    reg [15:0] sw;
    reg btnC, btnU, btnL, btnR;
    wire [15:0] led;
    wire [7:0] JA, JB;
    tri1 PS2Clk, PS2Data;

    My_Top_Module #(
        .PHYSICS_CYCLES(24),
        .BUTTON_DEBOUNCE_CYCLES(2),
        .BUTTON_RELEASE_CYCLES(2)
    ) dut (
        .clk(clk),
        .btnC(btnC),
        .btnU(btnU),
        .btnR(btnR),
        .btnL(btnL),
        .btnD(btnD),
        .sw(sw),
        .PS2Clk(PS2Clk),
        .PS2Data(PS2Data),
        .led(led),
        .JA(JA),
        .JB(JB)
    );

    always #5 clk = ~clk;

    task clocks(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    initial begin
        clk = 0;
        btnD = 1; // reset active
        sw = 16'h0000;
        btnC = 0; btnU = 0; btnL = 0; btnR = 0;
        clocks(10);
        btnD = 0; // reset deasserted
        // Wait for power_on_count (256 cycles) to expire
        clocks(300);

        // Put vehicle in LP_RUN
        force dut.game_state = `LP_RUN;
        force dut.run_init = 1'b0;

        // Populate a simple vehicle in builder:
        // cell 0 = WHEEL, cell 2 = WHEEL, cell 4 = PIG
        force dut.u_builder.build_grid = {`LP_PART_EMPTY, `LP_PART_EMPTY, `LP_PART_EMPTY,
                                          `LP_PART_EMPTY, `LP_PART_PIG,   `LP_PART_EMPTY,
                                          `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL};
        force dut.u_builder.build_frames = 9'b111_111_111;
        force dut.u_builder.runtime_intact = 9'b000_010_101;
        force dut.u_builder.runtime_frames = 9'b111_111_111;
        clocks(2);
        release dut.u_builder.runtime_intact;
        release dut.u_builder.runtime_frames;

        // Test 1: Gentle landing (vy = 16'sd100 < 768)
        force dut.airborne_ticks = 6'd15;
        force dut.audio_was_grounded = 1'b0;
        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.proposed_vy = 16'sd100;
        force dut.vehicle_tilt = 5'sd0;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b0)
            $fatal(1, "Gentle landing triggered impact damage!");
        release dut.airborne_ticks;
        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.proposed_vy;
        release dut.vehicle_tilt;
        clocks(1);

        if (dut.u_builder.runtime_intact !== 9'b000_010_000)
            if (dut.u_builder.runtime_intact !== 9'b000_010_101) $fatal(1, "Gentle landing changed intact mask! Got %b", dut.u_builder.runtime_intact);

        // Test 1b: Terrain bump jitter (vy = 800 >= 768, but airborne_ticks = 2 < 12)
        force dut.airborne_ticks = 6'd2;
        force dut.audio_was_grounded = 1'b0;
        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.proposed_vy = 16'sd800;
        force dut.vehicle_tilt = 5'sd0;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b0)
            $fatal(1, "Terrain bump (airborne_ticks < 12) falsely triggered impact damage!");
        release dut.airborne_ticks;
        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.proposed_vy;
        release dut.vehicle_tilt;
        clocks(1);

        // Test 1c: Intended first-map cave descent (384 pixels) remains safe.
        // The revised threshold is 448 pixels.
        force dut.falling = 1'b1;
        force dut.fall_start_y = 20'sd0;
        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.audio_was_grounded = 1'b0;
        force dut.proposed_vy = 16'sd800;
        force dut.corrected_y = 20'sd8192;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b0)
            $fatal(1, "Normal 32-pixel drop triggered impact damage!");
        release dut.falling;
        release dut.fall_start_y;
        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.audio_was_grounded;
        release dut.proposed_vy;
        release dut.corrected_y;
        clocks(1);

        // Test 2: High fall landing upright. The fall-distance reference is
        // forced to 0 and the landing is 448 pixels below it.
        // Upright landing reports the bottom row: cells 6, 7, 8
        // (mask 9'b111_000_000). The pig is protected, but impacted contents
        // are removed by the shared runtime damage handshake.
        force dut.u_builder.runtime_intact = 9'b111_010_101;
        clocks(1);
        release dut.u_builder.runtime_intact;

        force dut.airborne_ticks = 6'd15;
        force dut.audio_was_grounded = 1'b0;
        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.proposed_vy = 16'sd800;
        force dut.vehicle_tilt = 5'sd0;
        force dut.falling = 1'b1;
        force dut.fall_start_y = 20'sd0;
        force dut.corrected_y = 20'sd16384;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b1)
            $fatal(1, "Hard landing failed to trigger impact damage!");
        if (dut.impact_damage_mask !== 9'b111_111_111)
            $fatal(1, "Hard landing mask expected bottom row (9'b111_000_000), got %b", dut.impact_damage_mask);

        release dut.airborne_ticks;
        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.proposed_vy;
        release dut.vehicle_tilt;
        release dut.falling;
        release dut.fall_start_y;
        release dut.corrected_y;
        clocks(1);

        if (dut.u_builder.runtime_intact !== 9'b000_010_000)
            $fatal(1, "Hard landing did not remove the bottom contents: %b", dut.u_builder.runtime_intact);
        if (dut.u_builder.runtime_frames !== 9'b000_010_000)
            $fatal(1, "Hard landing should preserve wood frames!");
        if (dut.pig_alive !== 1'b1)
            $fatal(1, "Pig in cell 4 should survive bottom row impact!");

        // Test 3: High fall landing upside-down.
        force dut.u_builder.runtime_intact = 9'b111_111_111;
        force dut.u_builder.runtime_frames = 9'b111_111_111;
        clocks(1);
        release dut.u_builder.runtime_intact;
        release dut.u_builder.runtime_frames;

        force dut.airborne_ticks = 6'd15;
        force dut.audio_was_grounded = 1'b0;
        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.proposed_vy = 16'sd800;
        force dut.vehicle_tilt = -5'sd16;
        force dut.falling = 1'b1;
        force dut.fall_start_y = 20'sd0;
        force dut.corrected_y = 20'sd16384;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b1)
            $fatal(1, "Upside-down hard landing failed to trigger impact damage!");
        if (dut.impact_damage_mask !== 9'b111_111_111)
            $fatal(1, "Upside-down landing mask expected top row (9'b000_000_111), got %b", dut.impact_damage_mask);

        release dut.airborne_ticks;
        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.proposed_vy;
        release dut.vehicle_tilt;
        release dut.falling;
        release dut.fall_start_y;
        release dut.corrected_y;
        clocks(1);

        if (dut.u_builder.runtime_intact !== 9'b000_010_000)
            $fatal(1, "Upside-down landing did not remove the top contents: %b", dut.u_builder.runtime_intact);

        // Test 4: Fatal terminal-velocity high fall.
        force dut.u_builder.runtime_intact = 9'b111_111_111;
        force dut.u_builder.runtime_frames = 9'b111_111_111;
        clocks(1);
        release dut.u_builder.runtime_intact;
        release dut.u_builder.runtime_frames;

        force dut.airborne_ticks = 6'd15;
        force dut.audio_was_grounded = 1'b0;
        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.proposed_vy = 16'sd1300;
        force dut.vehicle_tilt = 5'sd0;
        force dut.falling = 1'b1;
        force dut.fall_start_y = 20'sd0;
        force dut.corrected_y = 20'sd114688;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b1)
            $fatal(1, "Fatal crash failed to trigger impact damage!");
        if (dut.impact_damage_mask !== 9'b111_111_111)
            $fatal(1, "Fatal crash mask expected all cells (9'b111_111_111), got %b", dut.impact_damage_mask);

        release dut.airborne_ticks;
        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.proposed_vy;
        release dut.vehicle_tilt;
        release dut.falling;
        release dut.fall_start_y;
        release dut.corrected_y;
        clocks(1);

        if (dut.u_builder.runtime_intact !== 9'b000_010_000)
            $fatal(1, "Fatal crash did not remove non-pig contents: %b", dut.u_builder.runtime_intact);
        if (dut.u_builder.runtime_frames !== 9'b000_010_000)
            $fatal(1, "Fatal crash did not remove non-pig frames: %b", dut.u_builder.runtime_frames);
        if (dut.pig_alive !== 1'b1)
            $fatal(1, "Pig should survive terrain impact!");

        // Test 5: Moderate horizontal right wall impact is harmless.
        force dut.u_builder.runtime_intact = 9'b111_111_111;
        force dut.u_builder.runtime_frames = 9'b111_111_111;
        clocks(1);
        release dut.u_builder.runtime_intact;
        release dut.u_builder.runtime_frames;

        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.audio_was_grounded = 1'b1; // already grounded rolling
        force dut.airborne_ticks = 6'd0;
        force dut.proposed_vy = 16'sd0;
        force dut.proposed_vx = 16'sd800;
        force dut.corrected_vx = 16'sd0;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b0)
            $fatal(1, "Right wall impact should not trigger part damage!");

        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.audio_was_grounded;
        release dut.airborne_ticks;
        release dut.proposed_vy;
        release dut.proposed_vx;
        release dut.corrected_vx;
        clocks(1);

        if (dut.u_builder.runtime_intact !== 9'b111_111_111)
            $fatal(1, "Right wall impact changed the intact contents: %b", dut.u_builder.runtime_intact);
        if (dut.u_builder.runtime_frames !== 9'b111_111_111)
            $fatal(1, "Right wall crash damaged frames unexpectedly!");
        if (dut.pig_alive !== 1'b1)
            $fatal(1, "Pig in cell 4 should survive right column wall impact!");

        // Test 6: Moderate horizontal left wall impact is harmless.
        force dut.u_builder.runtime_intact = 9'b111_111_111;
        force dut.u_builder.runtime_frames = 9'b111_111_111;
        clocks(1);
        release dut.u_builder.runtime_intact;
        release dut.u_builder.runtime_frames;

        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.audio_was_grounded = 1'b1;
        force dut.airborne_ticks = 6'd0;
        force dut.proposed_vy = 16'sd0;
        force dut.proposed_vx = -16'sd800;
        force dut.corrected_vx = 16'sd0;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b0)
            $fatal(1, "Left wall impact should not trigger part damage!");

        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.audio_was_grounded;
        release dut.airborne_ticks;
        release dut.proposed_vy;
        release dut.proposed_vx;
        release dut.corrected_vx;
        clocks(1);

        if (dut.u_builder.runtime_intact !== 9'b111_111_111)
            $fatal(1, "Left wall impact changed the intact contents: %b", dut.u_builder.runtime_intact);
        if (dut.u_builder.runtime_frames !== 9'b111_111_111)
            $fatal(1, "Left wall crash damaged frames unexpectedly!");
        if (dut.pig_alive !== 1'b1)
            $fatal(1, "Pig in cell 4 should survive left column wall impact!");

        // Test 7: Even a wall correction does not cause part damage; only a
        // high downward fall is allowed to use the impact damage path.
        force dut.u_builder.runtime_intact = 9'b111_111_111;
        force dut.u_builder.runtime_frames = 9'b111_111_111;
        clocks(1);
        release dut.u_builder.runtime_intact;
        release dut.u_builder.runtime_frames;

        force dut.response_valid = 1'b1;
        force dut.response_ready = 1'b1;
        force dut.grounded = 1'b1;
        force dut.audio_was_grounded = 1'b1;
        force dut.airborne_ticks = 6'd0;
        force dut.proposed_vy = 16'sd0;
        force dut.proposed_vx = 16'sd1300;
        force dut.corrected_vx = 16'sd0;
        clocks(1);

        if (dut.impact_damage_valid !== 1'b0)
            $fatal(1, "Fatal wall impact should not trigger part damage!");

        release dut.response_valid;
        release dut.response_ready;
        release dut.grounded;
        release dut.audio_was_grounded;
        release dut.airborne_ticks;
        release dut.proposed_vy;
        release dut.proposed_vx;
        release dut.corrected_vx;
        clocks(1);

        if (dut.u_builder.runtime_intact !== 9'b111_111_111)
            $fatal(1, "Fatal wall impact changed non-pig contents: %b", dut.u_builder.runtime_intact);
        if (dut.u_builder.runtime_frames !== 9'b111_111_111)
            $fatal(1, "Fatal wall impact changed frames: %b", dut.u_builder.runtime_frames);
        if (dut.pig_alive !== 1'b1)
            $fatal(1, "Pig should survive terrain impact!");

        $display("PASS crash_impact_tb: small falls and wall impacts survive; high falls damage non-pig contents");
        $finish;
    end
endmodule
