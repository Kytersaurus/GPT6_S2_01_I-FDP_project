// Owner: Role 2 - Kyle. Vehicle movement and velocity.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Role 2 starter: upright body, provisional acceleration/lift/drag lookup.
module physics_engine (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire run_init,
    output reg init_ready,
    input wire signed [15:0] spawn_x, spawn_y,
    input wire step_start, update_release,
    input wire [3:0] wheel_count, engine_count, balloon_count,
    input wire [7:0] mass_units,
    input wire engine_enabled,
    output wire move_valid,
    input wire move_ready,
    output reg signed [15:0] previous_x, previous_y,
    output reg signed [15:0] proposed_x, proposed_y, proposed_vx, proposed_vy,
    input wire response_valid,
    output wire response_ready,
    input wire signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy,
    input wire grounded,
    output reg movement_committed,
    output reg signed [15:0] vehicle_x, vehicle_y
);
    localparam IDLE=0, CALC_FORCE=1, CALC_VELOCITY=2, CALC_POSITION=3, SEND=4, WAIT_RESPONSE=5, WAIT_WORLD=6;
    reg [2:0] phase;
    reg signed [15:0] velocity_x, velocity_y;
    reg was_grounded;
    reg [3:0] sampled_wheels, sampled_engines, sampled_balloons;
    reg [7:0] sampled_mass;
    reg sampled_engine_enabled;
    // One extra signed bit holds additions before the result is limited to 16 bits.
    reg signed [16:0] next_vx, next_vy, next_x, next_y;
    reg signed [11:0] engine_force, balloon_force;
    reg signed [5:0] drag_force;
    integer acceleration, lift_per_balloon, drag;
    assign move_valid = (phase == SEND) && (game_state == `LP_RUN);
    assign response_ready = (phase == WAIT_RESPONSE) && (game_state == `LP_RUN);
    always @* begin
        acceleration = (sampled_mass <= 4) ? 24 : ((sampled_mass <= 8) ? 16 : 8);
        lift_per_balloon = (sampled_mass <= 4) ? 48 : ((sampled_mass <= 8) ? 32 : 16);
        drag = (sampled_wheels != 0) ? 4 : 16;
        next_vx = $signed(velocity_x);
        if (engine_force != 0) next_vx = next_vx + engine_force;
        else if (was_grounded) begin
            if (next_vx > drag_force) next_vx = next_vx - drag_force;
            else if (next_vx < -drag_force) next_vx = next_vx + drag_force;
            else next_vx = 0;
        end
        // Sign-extend velocity before mixing with unsigned part counts.
        next_vy = $signed(velocity_y);
        next_vy = next_vy + 32 - balloon_force;
        if (next_vx > 256) next_vx = 256;
        if (next_vx < -256) next_vx = -256;
        if (next_vy > 512) next_vy = 512;
        if (next_vy < -512) next_vy = -512;
        // Position uses velocity saved on the preceding calculation clock.
        next_x = $signed(vehicle_x) + $signed(proposed_vx);
        next_y = $signed(vehicle_y) + $signed(proposed_vy);
        if (next_x > 28672) next_x = 28672;
        if (next_x < -8192) next_x = -8192;
        if (next_y > 24576) next_y = 24576;
        if (next_y < -8192) next_y = -8192;
    end
    always @(posedge clk) begin
        if (reset) begin
            phase <= IDLE; init_ready <= 0; was_grounded <= 0; movement_committed <= 0;
            sampled_wheels <= 0; sampled_engines <= 0; sampled_balloons <= 0;
            sampled_mass <= 0; sampled_engine_enabled <= 0;
            engine_force <= 0; balloon_force <= 0; drag_force <= 16;
            vehicle_x <= spawn_x; vehicle_y <= spawn_y;
            previous_x <= spawn_x; previous_y <= spawn_y;
            proposed_x <= spawn_x; proposed_y <= spawn_y;
            proposed_vx <= 0; proposed_vy <= 0; velocity_x <= 0; velocity_y <= 0;
        end else begin
            movement_committed <= 0;
            if (!run_init) init_ready <= 0;
            if (run_init && !init_ready) begin
                phase <= IDLE; init_ready <= 1; was_grounded <= 0;
                vehicle_x <= spawn_x; vehicle_y <= spawn_y;
                previous_x <= spawn_x; previous_y <= spawn_y;
                proposed_x <= spawn_x; proposed_y <= spawn_y;
                proposed_vx <= 0; proposed_vy <= 0; velocity_x <= 0; velocity_y <= 0;
            end else if (game_state != `LP_RUN) phase <= IDLE;
            else case (phase)
                IDLE: if (step_start) begin
                    // Save each calculation before starting the next one.
                    sampled_wheels <= wheel_count; sampled_engines <= engine_count;
                    sampled_balloons <= balloon_count; sampled_mass <= mass_units;
                    sampled_engine_enabled <= engine_enabled;
                    previous_x <= vehicle_x; previous_y <= vehicle_y;
                    phase <= CALC_FORCE;
                end
                CALC_FORCE: begin
                    engine_force <= sampled_engine_enabled ? acceleration * sampled_engines : 0;
                    balloon_force <= sampled_balloons * lift_per_balloon;
                    drag_force <= drag;
                    phase <= CALC_VELOCITY;
                end
                CALC_VELOCITY: begin
                    proposed_vx <= next_vx[15:0]; proposed_vy <= next_vy[15:0];
                    phase <= CALC_POSITION;
                end
                CALC_POSITION: begin
                    proposed_x <= next_x[15:0]; proposed_y <= next_y[15:0];
                    phase <= SEND;
                end
                SEND: if (move_ready) phase <= WAIT_RESPONSE;
                WAIT_RESPONSE: if (response_valid) begin
                    vehicle_x <= corrected_x; vehicle_y <= corrected_y;
                    velocity_x <= corrected_vx; velocity_y <= corrected_vy;
                    was_grounded <= grounded; movement_committed <= 1; phase <= WAIT_WORLD;
                end
                WAIT_WORLD: if (update_release) phase <= IDLE;
                default: phase <= IDLE;
            endcase
        end
    end
endmodule
