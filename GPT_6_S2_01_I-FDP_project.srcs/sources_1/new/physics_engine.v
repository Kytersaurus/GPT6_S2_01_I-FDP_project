// Owner: Role 2 - Kyle. Vehicle movement and velocity.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Staged force calculation, clocked division, slope gravity, friction and jumping.
module physics_engine (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire run_init,
    output reg init_ready,
    input wire signed [`LP_COORD_BITS-1:0] spawn_x, spawn_y,
    input wire step_start, update_release,
    input wire [3:0] wheel_count, engine_count, balloon_count,
    input wire [7:0] mass_units,
    input wire engine_enabled,
    input wire engine_reverse,
    input wire jump_press,
    input wire boost_req,
    output wire boost_active,
    output wire move_valid,
    input wire move_ready,
    output reg signed [`LP_COORD_BITS-1:0] previous_x, previous_y,
    output reg signed [`LP_COORD_BITS-1:0] proposed_x, proposed_y,
    output reg signed [15:0] proposed_vx, proposed_vy,
    input wire response_valid,
    output wire response_ready,
    input wire signed [`LP_COORD_BITS-1:0] corrected_x, corrected_y,
    input wire signed [15:0] corrected_vx, corrected_vy,
    input wire grounded,
    input wire signed [7:0] ground_slope,
    input wire signed [3:0] corrected_tilt,
    output reg signed [3:0] previous_tilt, proposed_tilt, vehicle_tilt,
    output reg movement_committed,
    output reg signed [`LP_COORD_BITS-1:0] vehicle_x, vehicle_y
);
    `include "rotation_geometry.vh"
    localparam IDLE = 0, MOMENTUM = 1, FREE_MOMENTUM = 2,
               FRICTION = 3, TOTAL_FORCE = 4, START_DIV = 5,
               WAIT_DIV = 6, CLAMP_VELOCITY = 7, POSITION = 8,
               MAKE_REQUEST = 9, SEND = 10, WAIT_RESPONSE = 11,
               WAIT_WORLD = 12, CALC_FORCE = 13, SLOPE_FORCE = 14, APPLY_SLOPE = 15;
    localparam signed [15:0] wheel_drag = 16'sd10;
    localparam signed [15:0] engine_force = 16'sd96;
    // Two available balloons must overcome gravity (32); one slows a fall.
    localparam signed [15:0] lift_per_balloon = 16'sd24;

    reg [3:0] phase;
    reg signed [15:0] velocity_x, velocity_y;
    reg was_grounded, jump_pending;
    // Accepted terrain gradient in Q4.4 dy/dx; positive descends to the right.
    reg signed [7:0] last_ground_slope, sampled_slope;
    wire signed [3:0] desired_tilt=slope_to_tilt(last_ground_slope);
    reg [15:0] step_slope_product;
    reg signed [15:0] step_slope_force;
    reg [27:0] boost_timer; // 1.5 seconds at 100MHz is 150_000_000 cycles
    wire is_boosting = (boost_timer != 0);
    assign boost_active = is_boosting;
    reg sampled_boosting;
    reg [3:0] sampled_wheels, sampled_engines, sampled_balloons;
    reg sampled_engine_enabled, sampled_engine_reverse, sampled_jump;
    wire jump_now;
    assign jump_now = (game_state == `LP_RUN) && was_grounded &&
                      (jump_pending || jump_press);

    // Keep the force-division fraction until a movement response commits.
    // Its mass tag prevents using a fraction from a different vehicle mass.
    reg signed [15:0] remainder_x, pending_remainder_x;
    reg [7:0] remainder_mass, step_mass;
    reg signed [15:0] step_remainder, step_thrust, step_drive;
    reg [15:0] step_friction_limit;
    reg signed [15:0] step_friction, total_force;
    reg signed [`LP_COORD_BITS-1:0] step_x, step_y;
    reg signed [15:0] step_vx, step_vy, step_result_vx;
    reg signed [24:0] step_momentum, step_free_momentum;
    reg signed [16:0] step_vx_sum;
    reg signed [`LP_COORD_BITS:0] step_x_sum, step_y_sum;
    localparam signed [`LP_COORD_BITS:0] POSITION_MAX = (1 << (`LP_COORD_BITS-1))-1;
    localparam signed [`LP_COORD_BITS:0] POSITION_MIN = -(1 << (`LP_COORD_BITS-1));

    wire signed [15:0] engine_magnitude, lift;
    wire [15:0] wheel_resistance;
    wire signed [16:0] vertical_sum;
    assign engine_magnitude = $signed({1'b0, sampled_engines}) * engine_force;
    assign wheel_resistance = sampled_wheels * wheel_drag;
    assign lift = $signed({1'b0, sampled_balloons}) * lift_per_balloon;
    assign vertical_sum = $signed({velocity_y[15], velocity_y}) +
                          17'sd32 - $signed({lift[15], lift});
    wire signed [16:0] net_gravity = 17'sd32 - $signed({lift[15], lift});
    wire [7:0] slope_magnitude = sampled_slope < 0 ? -sampled_slope : sampled_slope;

    // Horizontal gravity on y=s*x is g*s/(1+s*s). A small constant
    // table avoids a second divider and preserves symmetric left/right forces.
    // Coefficients are round(256*(q/16)/(1+(q/16)^2)), q in [0,16].
    function [7:0] slope_factor;
        input [7:0] q;
        begin
            case (q)
                0: slope_factor=0;   1: slope_factor=16;  2: slope_factor=32;
                3: slope_factor=46;  4: slope_factor=60;  5: slope_factor=73;
                6: slope_factor=84;  7: slope_factor=94;  8: slope_factor=102;
                9: slope_factor=109; 10: slope_factor=115; 11: slope_factor=120;
                12: slope_factor=123; 13: slope_factor=125; 14: slope_factor=127;
                15: slope_factor=128; 16: slope_factor=128;
                default: slope_factor=0;
            endcase
        end
    endfunction

    reg divider_start;
    reg signed [15:0] divider_input;
    wire divider_busy, divider_done, divider_zero;
    wire signed [15:0] divider_quotient, divider_remainder;
    wire divider_reset;
    assign divider_reset = reset || run_init || (game_state != `LP_RUN);
    signed_divider16 u_divider (
        .clk(clk), .reset(divider_reset), .start(divider_start),
        .dividend(divider_input), .divisor(step_mass),
        .busy(divider_busy), .done(divider_done),
        .divide_by_zero(divider_zero),
        .quotient(divider_quotient), .remainder(divider_remainder)
    );

    assign move_valid = (phase == SEND) && (game_state == `LP_RUN);
    assign response_ready = (phase == WAIT_RESPONSE) && (game_state == `LP_RUN);

    always @(posedge clk) begin
        if (reset || run_init || game_state != `LP_RUN)
            jump_pending <= 0;
        else if (phase == IDLE && step_start)
            jump_pending <= 0;
        else if (jump_press && was_grounded)
            jump_pending <= 1;
    end

    always @(posedge clk) begin
        if (reset) begin
            phase <= IDLE; init_ready <= 0; was_grounded <= 0; boost_timer <= 0;
            last_ground_slope <= 0; sampled_slope <= 0;
            previous_tilt <= 0; proposed_tilt <= 0; vehicle_tilt <= 0;
            step_slope_product <= 0; step_slope_force <= 0;
            movement_committed <= 0;
            vehicle_x <= spawn_x; vehicle_y <= spawn_y;
            previous_x <= spawn_x; previous_y <= spawn_y;
            proposed_x <= spawn_x; proposed_y <= spawn_y;
            proposed_vx <= 0; proposed_vy <= 0; velocity_x <= 0; velocity_y <= 0;
                        remainder_x <= 0; pending_remainder_x <= 0; remainder_mass <= 0;
                boost_timer <= 0;
            step_mass <= 0; step_remainder <= 0; step_thrust <= 0; step_drive <= 0;
            step_friction_limit <= 0; step_friction <= 0; total_force <= 0;
            step_x <= 0; step_y <= 0; step_vx <= 0; step_vy <= 0;
            step_result_vx <= 0; step_momentum <= 0; step_free_momentum <= 0;
            step_vx_sum <= 0; step_x_sum <= 0; step_y_sum <= 0;
            divider_start <= 0; divider_input <= 0;
            sampled_wheels <= 0; sampled_engines <= 0; sampled_balloons <= 0;
            sampled_engine_enabled <= 0; sampled_engine_reverse <= 0; sampled_jump <= 0;
        end else begin
            movement_committed <= 0;
            divider_start <= 0;
            if (!run_init) init_ready <= 0;
            if (boost_timer != 0) boost_timer <= boost_timer - 1'b1;
            if (game_state == `LP_RUN && boost_req && engine_count != 0) boost_timer <= 28'd150000000;
            if (run_init && !init_ready) begin
                phase <= IDLE; init_ready <= 1; was_grounded <= 0;
                last_ground_slope <= 0;
                previous_tilt <= 0; proposed_tilt <= 0; vehicle_tilt <= 0;
                vehicle_x <= spawn_x; vehicle_y <= spawn_y;
                previous_x <= spawn_x; previous_y <= spawn_y;
                proposed_x <= spawn_x; proposed_y <= spawn_y;
                proposed_vx <= 0; proposed_vy <= 0; velocity_x <= 0; velocity_y <= 0;
                            remainder_x <= 0; pending_remainder_x <= 0; remainder_mass <= 0;
                boost_timer <= 0;
            end else if (game_state != `LP_RUN) begin
                phase <= IDLE;
                last_ground_slope <= 0; was_grounded <= 0;
            end else case (phase)
                IDLE: if (step_start) begin
                    // Capture all properties once. Later input changes cannot
                    // change this update while arithmetic or collision is busy.
                    previous_x <= vehicle_x; previous_y <= vehicle_y;
                    previous_tilt <= vehicle_tilt;
                    // Settle one angle step per update. Airborne motion keeps
                    // its launch attitude; no artificial spin is introduced.
                    if (was_grounded && !jump_now) begin
                        if (desired_tilt > vehicle_tilt) proposed_tilt <= vehicle_tilt+1'b1;
                        else if (desired_tilt < vehicle_tilt) proposed_tilt <= vehicle_tilt-1'b1;
                        else proposed_tilt <= vehicle_tilt;
                    end else proposed_tilt <= vehicle_tilt;
                    step_x <= vehicle_x; step_y <= vehicle_y;
                    step_vx <= velocity_x; step_mass <= mass_units;
                    step_remainder <= remainder_x;
                    pending_remainder_x <= 0;
                    sampled_wheels <= wheel_count; sampled_engines <= engine_count;
                    sampled_balloons <= balloon_count;
                    sampled_engine_enabled <= engine_enabled; sampled_engine_reverse <= engine_reverse;
                    sampled_jump <= jump_now;
                    sampled_slope <= last_ground_slope;
                    sampled_boosting <= is_boosting;
                    phase <= CALC_FORCE;
                end
                CALC_FORCE: begin
                    // Part counting ends at the sampled registers above. Force
                    // multiplication/addition then has its own 100 MHz clock.
                    step_thrust <= 0;
                    if (sampled_engine_enabled && sampled_engines != 0 && was_grounded) begin
                        if (sampled_boosting)
                            step_thrust <= sampled_engine_reverse ? -(engine_magnitude <<< 1) : (engine_magnitude <<< 1);
                        else
                            step_thrust <= sampled_engine_reverse ? -engine_magnitude : engine_magnitude;
                    end
                    step_friction_limit <= was_grounded ? wheel_resistance : 16'd0;
                    if (sampled_jump)
                        step_vy <= -16'sd512;
                    else if (vertical_sum > 17'sd512)
                        step_vy <= 16'sd512;
                    else if (vertical_sum < -17'sd512)
                        step_vy <= -16'sd512;
                    else
                        step_vy <= vertical_sum[15:0];
                    // Lift reduces weight on the ramp. Jumping or net upward
                    // lift detaches the body, so neither gets ground gravity.
                    if (was_grounded && !sampled_jump && net_gravity > 0)
                        step_slope_product <= net_gravity * slope_factor(slope_magnitude);
                    else step_slope_product <= 0;
                    phase <= SLOPE_FORCE;
                end
                SLOPE_FORCE: begin
                    // Convert acceleration to force before the existing mass
                    // division. Wheel resistance can balance it at rest.
                    if (sampled_slope < 0)
                        step_slope_force <= -($signed({1'b0,step_mass}) *
                                              $signed({1'b0,step_slope_product[15:8]}));
                    else
                        step_slope_force <= $signed({1'b0,step_mass}) *
                                            $signed({1'b0,step_slope_product[15:8]});
                    phase <= APPLY_SLOPE;
                end
                APPLY_SLOPE: begin
                    step_thrust <= step_thrust + step_slope_force;
                    phase <= MOMENTUM;
                end
                MOMENTUM: begin
                    // An unsigned 8-bit mass needs a leading zero before it
                    // participates in signed multiplication.
                    step_momentum <= $signed({1'b0, step_mass}) * $signed(step_vx);
                    // Compare the captured mass here, after the builder's count
                    // calculation has ended at step_mass's register boundary.
                    if (step_mass == remainder_mass) step_drive <= step_thrust + step_remainder;
                    else begin step_remainder <= 0; step_drive <= step_thrust; end
                    phase <= FREE_MOMENTUM;
                end
                FREE_MOMENTUM: begin
                    step_free_momentum <= step_momentum +
                        $signed({{9{step_drive[15]}}, step_drive});
                    phase <= FRICTION;
                end
                FRICTION: begin
                    // Include the saved fraction in the stopping calculation.
                    // Friction can stop a body, but cannot make it reverse.
                    if (step_free_momentum > $signed({1'b0, step_friction_limit}))
                        step_friction <= -$signed(step_friction_limit);
                    else if (step_free_momentum < -$signed({1'b0, step_friction_limit}))
                        step_friction <= $signed(step_friction_limit);
                    else
                        step_friction <= -$signed(step_free_momentum[15:0]);
                    phase <= TOTAL_FORCE;
                end
                TOTAL_FORCE: begin
                    total_force <= step_thrust + step_friction;
                    phase <= START_DIV;
                end
                START_DIV: if (!divider_busy) begin
                    // All horizontal acceleration comes from force / mass.
                    // Carry the remainder so small forces are not rounded away.
                    divider_input <= total_force + step_remainder;
                    divider_start <= 1;
                    phase <= WAIT_DIV;
                end
                WAIT_DIV: if (divider_done) begin
                    step_vx_sum <= $signed({step_vx[15], step_vx}) +
                                   $signed({divider_quotient[15], divider_quotient});
                    pending_remainder_x <= divider_zero ? 16'sd0 : divider_remainder;
                    phase <= CLAMP_VELOCITY;
                end
                CLAMP_VELOCITY: begin
                    if (step_vx_sum > 17'sd256) begin
                        step_result_vx <= 16'sd256;
                        pending_remainder_x <= 0;
                    end else if (step_vx_sum < -17'sd256) begin
                        step_result_vx <= -16'sd256;
                        pending_remainder_x <= 0;
                    end else begin
                        step_result_vx <= step_vx_sum[15:0];
                        if ((step_vx_sum == 17'sd256 && pending_remainder_x > 0) ||
                            (step_vx_sum == -17'sd256 && pending_remainder_x < 0))
                            pending_remainder_x <= 0;
                    end
                    phase <= POSITION;
                end
                POSITION: begin
                    step_x_sum <= $signed({step_x[`LP_COORD_BITS-1], step_x}) +
                                  $signed({{(`LP_COORD_BITS-15){step_result_vx[15]}}, step_result_vx});
                    step_y_sum <= $signed({step_y[`LP_COORD_BITS-1], step_y}) +
                                  $signed({{(`LP_COORD_BITS-15){step_vy[15]}}, step_vy});
                    phase <= MAKE_REQUEST;
                end
                MAKE_REQUEST: begin
                    // Saturate only at the numeric limits. World bounds are checked
                    // after committing movement, using the selected level size.
                    if (step_x_sum > POSITION_MAX) begin
                        proposed_x <= POSITION_MAX[`LP_COORD_BITS-1:0];
                        pending_remainder_x <= 0;
                    end else if (step_x_sum < POSITION_MIN) begin
                        proposed_x <= POSITION_MIN[`LP_COORD_BITS-1:0];
                        pending_remainder_x <= 0;
                    end else proposed_x <= step_x_sum[`LP_COORD_BITS-1:0];
                    if (step_y_sum > POSITION_MAX)
                        proposed_y <= POSITION_MAX[`LP_COORD_BITS-1:0];
                    else if (step_y_sum < POSITION_MIN)
                        proposed_y <= POSITION_MIN[`LP_COORD_BITS-1:0];
                    else proposed_y <= step_y_sum[`LP_COORD_BITS-1:0];
                    proposed_vx <= step_result_vx; proposed_vy <= step_vy;
                    phase <= SEND;
                end
                SEND: if (move_ready) phase <= WAIT_RESPONSE;
                WAIT_RESPONSE: if (response_valid) begin
                    vehicle_x <= corrected_x; vehicle_y <= corrected_y;
                    vehicle_tilt <= sanitize_tilt(corrected_tilt);
                    velocity_x <= corrected_vx; velocity_y <= corrected_vy;
                    was_grounded <= grounded;
                    if (grounded && ground_slope >= -8'sd16 && ground_slope <= 8'sd16)
                        last_ground_slope <= ground_slope;
                    else last_ground_slope <= 0;
                    // A wall/contact correction must discard pre-contact carry.
                    if (corrected_vx == proposed_vx && corrected_x == proposed_x)
                        remainder_x <= pending_remainder_x;
                    else
                        remainder_x <= 0;
                    remainder_mass <= step_mass;
                    movement_committed <= 1; phase <= WAIT_WORLD;
                end
                WAIT_WORLD: if (update_release) phase <= IDLE;
                default: phase <= IDLE;
            endcase
        end
    end
endmodule
