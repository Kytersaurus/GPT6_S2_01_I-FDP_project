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
    localparam IDLE=0, SEND=1, WAIT_RESPONSE=2, WAIT_WORLD=3;
    reg [1:0] phase;
    reg signed [15:0] velocity_x, velocity_y;
    reg was_grounded;
    integer next_vx, next_vy, next_x, next_y, acceleration, lift_per_balloon, drag;
    assign move_valid = (phase == SEND) && (game_state == `LP_RUN);
    assign response_ready = (phase == WAIT_RESPONSE) && (game_state == `LP_RUN);
    always @* begin
        acceleration = (mass_units <= 4) ? 24 : ((mass_units <= 8) ? 16 : 8);
        lift_per_balloon = (mass_units <= 4) ? 48 : ((mass_units <= 8) ? 32 : 16);
        drag = (wheel_count != 0) ? 4 : 16;
        next_vx = $signed(velocity_x);
        if (engine_enabled && engine_count != 0) next_vx = next_vx + acceleration * engine_count;
        else if (was_grounded) begin
            if (next_vx > drag) next_vx = next_vx - drag;
            else if (next_vx < -drag) next_vx = next_vx + drag;
            else next_vx = 0;
        end
        // Sign-extend velocity before mixing with unsigned part counts.
        next_vy = $signed(velocity_y);
        next_vy = next_vy + 32 - balloon_count * lift_per_balloon;
        if (next_vx > 256) next_vx = 256;
        if (next_vx < -256) next_vx = -256;
        if (next_vy > 512) next_vy = 512;
        if (next_vy < -512) next_vy = -512;
        next_x = $signed(vehicle_x) + next_vx;
        next_y = $signed(vehicle_y) + next_vy;
        if (next_x > 28672) next_x = 28672;
        if (next_x < -8192) next_x = -8192;
        if (next_y > 24576) next_y = 24576;
        if (next_y < -8192) next_y = -8192;
    end
    always @(posedge clk) begin
        if (reset) begin
            phase <= IDLE; init_ready <= 0; was_grounded <= 0; movement_committed <= 0;
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
                    previous_x <= vehicle_x; previous_y <= vehicle_y;
                    proposed_x <= next_x[15:0]; proposed_y <= next_y[15:0];
                    proposed_vx <= next_vx[15:0]; proposed_vy <= next_vy[15:0];
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
