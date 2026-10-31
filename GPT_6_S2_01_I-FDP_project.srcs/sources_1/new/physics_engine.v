// Owner: Role 2 - Kyle. Vehicle movement and velocity.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Staged forces, serial mass divider, slope gravity, friction and spring impulse.
// ENGINE_FORCE is the ground thrust per engine. The arithmetic benches keep the
// original 96; the game sets its tuned value in My_Top_Module.
module physics_engine #(parameter integer ENGINE_FORCE = 96,
                        parameter integer ROCKET_FORCE_SHIFT = 9,
                        parameter integer WHEEL_TORQUE_SHIFT = 0) (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire run_init,
    output reg init_ready,
    input wire signed [`LP_COORD_BITS-1:0] spawn_x, spawn_y,
    input wire step_start, update_release,
    input wire [3:0] wheel_count, engine_count, balloon_count,
    // Wheels under (down) and on top of (up) the body. Left unconnected, both
    // are zero and the total wheel_count is used whichever way up the body is.
    input tri0 [3:0] wheels_down, wheels_up,
    input wire [7:0] mass_units,
    input wire engine_enabled,
    input wire engine_reverse,
    // Existing jump control is the spring trigger until a spring item is added.
    input wire jump_press,
    // Signed intact part counts: right-facing minus left-facing. Unconnected
    // ports preserve legacy benches with no airborne propulsion.
    input tri0 signed [4:0] fan_balance, rocket_balance,
    // Future placement logic supplies body-vertical rockets: down minus up.
    input tri0 signed [4:0] rocket_vertical_balance,
    input tri0 [3:0] rocket_count,
    input tri0 fan_enabled, rocket_req,
    output wire rocket_ready, rocket_active,
    // Read-only geometry for force application and the mass centre. Disabled
    // by default for legacy arithmetic benches; the game enables it explicitly.
    input tri0 moments_enabled,
    input tri0 [26:0] build_grid,
    input tri0 [8:0] build_frames, intact_mask, frame_intact_mask,
    input tri0 [8:0] build_facing_left, rocket_vertical_mask,
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
    input wire signed [`LP_TILT_BITS-1:0] corrected_tilt,
    // Collision's report that the body is balanced past a supporting edge.
    input tri0 signed [1:0] tip_dir,
    output reg signed [`LP_TILT_BITS-1:0] previous_tilt, proposed_tilt, vehicle_tilt,
    output reg movement_committed,
    output reg signed [`LP_COORD_BITS-1:0] vehicle_x, vehicle_y,
    // Drawing height: an alpha-beta filter of vehicle_y (a quarter of the error to the
    // position, a sixteenth to its speed), so the 2-pixel steps of a map shown at 2x glide
    // instead of jumping, without lagging on a steady slope. Collision and outcomes use
    // vehicle_y.
    output reg signed [`LP_COORD_BITS-1:0] display_y
);
    `include "rotation_geometry.vh"
    localparam IDLE = 0, MOMENTUM = 1, FREE_MOMENTUM = 2,
               FRICTION = 3, TOTAL_FORCE = 4, START_DIV = 5,
               WAIT_DIV = 6, CLAMP_VELOCITY = 7, POSITION = 8,
               MAKE_REQUEST = 9, SEND = 10, WAIT_RESPONSE = 11,
               WAIT_WORLD = 12, CALC_FORCE = 13, SLOPE_FORCE = 14, APPLY_SLOPE = 15, AIR_FORCE = 16, VERTICAL_START = 17, VERTICAL_WAIT = 18, VERTICAL_CLAMP = 19, MOMENT_WAIT = 20, ROTATE_FORCE = 21,
               PIVOT_START = 22, PIVOT_WAIT = 23, APPLY_PIVOT = 24,
               ROCKET_HORIZONTAL = 25, ROCKET_VERTICAL = 26, ROCKET_DONE = 27;
    localparam signed [15:0] wheel_drag = 16'sd10;
    // A wheeled body resting on its side without wheels scrapes instead of rolling.
    // Bodies with no wheel sides reported (no wheels, or legacy inputs) keep the
    // original zero-wheel behaviour.
    localparam signed [15:0] scrape_drag = 16'sd128;
    // Spin is in 1/16 tilt steps per update: 16 turns 11.25 degrees each update.
    // Tipping over an edge adds TIP_ACCEL per update, up to MAX_SPIN.
    localparam signed [5:0] TIP_ACCEL = 6'sd3, MAX_SPIN = 6'sd16;
    localparam signed [15:0] engine_force = ENGINE_FORCE;
    // Two available balloons must overcome gravity (32); one slows a fall.
    localparam signed [15:0] lift_per_balloon = 16'sd24;

    // Power-of-two per-part forces use wiring shifts, not multipliers.
    localparam FAN_FORCE_SHIFT = 6; // Fan force 64; rocket force is a power-of-two parameter.
    localparam [6:0] ROCKET_TICKS = 7'd90; // 1.5 s at the default 60 Hz
    localparam signed [15:0] SPRING_IMPULSE = 16'sd512;
    reg [4:0] phase;
    reg signed [15:0] velocity_x, velocity_y;
    reg was_grounded, spring_pending, spring_fired;
    reg [6:0] rocket_fuel;
    reg rocket_spent;
    reg signed [4:0] sampled_fans, sampled_rockets, sampled_vertical_rockets;
    reg signed [15:0] step_vertical_force;
    reg signed [9:0] sampled_rocket_cos, sampled_rocket_sin;
    reg [4:0] rocket_terms;
    reg signed [15:0] rocket_force_x, rocket_force_y;
    wire signed [15:0] rocket_unit_x=$signed({{6{sampled_rocket_cos[9]}},sampled_rocket_cos}) <<< (ROCKET_FORCE_SHIFT-8);
    wire signed [15:0] rocket_unit_y=$signed({{6{sampled_rocket_sin[9]}},sampled_rocket_sin}) <<< (ROCKET_FORCE_SHIFT-8);
    reg signed [15:0] remainder_y, pending_remainder_y;
    reg signed [16:0] step_vertical_base;
    reg signed [17:0] step_vy_sum;
    reg signed [15:0] step_air_force;
    reg step_moments_enabled, wheel_force_valid;
    reg signed [15:0] step_wheel_force;
    reg signed [13:0] angular_velocity_q8;
    reg signed [12:0] moment_angle_remainder;
    reg signed [17:0] step_angular_sum;
    reg signed [13:0] step_pivot_x, step_pivot_y;
    wire moment_valid, pivot_valid;
    wire signed [15:0] moment_accel;
    wire [15:0] support_negative_q8, support_positive_q8;
    reg signed [15:0] supported_moment_accel;
    wire signed [13:0] pivot_dx, pivot_dy;
    wire signed [13:0] clamped_angular_velocity=step_angular_sum>18'sd4096 ? 14'sd4096 :
        step_angular_sum< -18'sd4096 ? -14'sd4096 : step_angular_sum[13:0];
    wire signed [15:0] force_angle_sum=$signed(moment_angle_remainder)+$signed(clamped_angular_velocity);
    vehicle_moments #(.ROCKET_FORCE_SHIFT(ROCKET_FORCE_SHIFT), .WHEEL_TORQUE_SHIFT(WHEEL_TORQUE_SHIFT)) u_moments (
        .clk(clk),.reset(reset || run_init || game_state!=`LP_RUN),
        .start(phase==IDLE && step_start && moments_enabled && game_state==`LP_RUN && !run_init),
        .build_grid(build_grid),.build_frames(build_frames),.intact_mask(intact_mask),
        .frame_intact_mask(frame_intact_mask),.facing_left(build_facing_left),
        .rocket_vertical_mask(rocket_vertical_mask),.fan_on(fan_enabled),.rocket_on(rocket_active),
        .grounded(was_grounded),.tilt(vehicle_tilt),.wheel_force_valid(wheel_force_valid),
        .wheel_force(step_wheel_force),.result_valid(moment_valid),.result_ready(phase==MOMENT_WAIT),
        .angular_accel_q8(moment_accel),.support_negative_q8(support_negative_q8),.support_positive_q8(support_positive_q8),.com_x_q2(),.com_y_q2(),.body_mass(),.torque_q10(),
        .pivot_start(phase==PIVOT_START),.next_tilt(proposed_tilt),.pivot_valid(pivot_valid),
        .pivot_ready(phase==PIVOT_WAIT),.pivot_dx(pivot_dx),.pivot_dy(pivot_dy)
    );
    assign rocket_ready = game_state == `LP_RUN && !run_init &&
                          !rocket_spent && rocket_count != 0;
    assign rocket_active = game_state == `LP_RUN && !run_init &&
                           rocket_fuel != 0 && rocket_count != 0;
    // Requests are captured even between physics steps. A shared one-shot burn
    // is restored only by reset/retry, and only accepted updates consume fuel.
    always @(posedge clk) begin
        if (reset || run_init || game_state != `LP_RUN) begin
            rocket_fuel <= 0; rocket_spent <= 0;
        end else if (rocket_req && rocket_ready) begin
            rocket_fuel <= ROCKET_TICKS; rocket_spent <= 1;
        end else if (phase == IDLE && step_start && rocket_fuel != 0)
            rocket_fuel <= rocket_fuel - 1'b1;
    end
    // Accepted terrain gradient in Q4.4 dy/dx; positive descends to the right.
    reg signed [7:0] last_ground_slope, sampled_slope;
    // An upside-down body settles onto the slope with its top row down.
    wire signed [`LP_TILT_BITS-1:0] slope_tilt=slope_to_tilt(last_ground_slope);
    wire signed [`LP_TILT_BITS-1:0] desired_tilt=tilt_flipped(vehicle_tilt) ? slope_tilt+5'b10000 : slope_tilt;
    // Shortest way round: the 5-bit difference wraps to -16..15.
    wire signed [`LP_TILT_BITS-1:0] settle_error=desired_tilt-vehicle_tilt;
    // The body only settles toward a target held for three grounded updates in a row.
    // One-update slope readings at stair edges (or a failed probe reporting level)
    // would otherwise rock the body back and forth.
    reg signed [`LP_TILT_BITS-1:0] held_target;
    reg [1:0] held_count;
    wire target_steady=desired_tilt==held_target && held_count==2'd2;
    reg signed [15:0] display_vy;
    wire signed [`LP_COORD_BITS+1:0] display_guess=$signed(display_y)+$signed(display_vy);
    wire signed [`LP_COORD_BITS+1:0] display_error=$signed(corrected_y)-display_guess;
    reg signed [5:0] spin;
    reg signed [1:0] last_tip;
    reg [3:0] spin_frac;
    // A grounded body already three steps past the ground's angle in the tip direction rests
    // on its corner: it stops tipping and settles back (a tip reported on a steep slope's
    // stairs must not roll the body over while it sits on the slope).
    wire tip_overdone=(last_tip > 0 && settle_error <= -3) || (last_tip < 0 && settle_error >= 3);
    wire signed [1:0] active_tip=tip_overdone ? 2'sd0 : last_tip;
    wire signed [6:0] tip_spin=spin+(active_tip > 0 ? TIP_ACCEL : active_tip < 0 ? -TIP_ACCEL : 6'sd0);
    wire signed [5:0] next_tip_spin=tip_spin > MAX_SPIN ? MAX_SPIN : tip_spin < -MAX_SPIN ? -MAX_SPIN : tip_spin[5:0];
    wire signed [7:0] spin_sum=$signed({1'b0,spin_frac})+(was_grounded ? next_tip_spin : spin);
    // The wheels touching the ground decide grip and drive.
    wire [3:0] contact_wheels=(wheels_down|wheels_up)==0 ? wheel_count :
                              tilt_flipped(vehicle_tilt) ? wheels_up : wheels_down;
    reg [15:0] step_slope_product;
    reg signed [15:0] step_slope_force;
    reg [27:0] boost_timer; // 1.5 seconds at 100MHz is 150_000_000 cycles
    wire is_boosting = (boost_timer != 0);
    assign boost_active = is_boosting;
    reg sampled_boosting;
    reg [3:0] sampled_wheels, sampled_engines, sampled_balloons;
    reg sampled_sided;
    reg sampled_engine_enabled, sampled_engine_reverse, sampled_spring;
    wire spring_now;
    assign spring_now = (game_state == `LP_RUN) && was_grounded && !spring_fired &&
                      (spring_pending || jump_press);
    always @* begin
        supported_moment_accel=moment_accel;
        if(was_grounded && !sampled_spring && active_tip==0) begin
            if(moment_accel>0)
                supported_moment_accel=$signed({1'b0,moment_accel})>$signed({1'b0,support_positive_q8}) ?
                    moment_accel-$signed(support_positive_q8) : 16'sd0;
            else if(moment_accel<0)
                supported_moment_accel=-$signed({moment_accel[15],moment_accel})>$signed({1'b0,support_negative_q8}) ?
                    moment_accel+$signed(support_negative_q8) : 16'sd0;
        end
    end

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
    assign wheel_resistance = sampled_wheels != 0 ? sampled_wheels * wheel_drag : sampled_sided ? scrape_drag : 16'sd0;
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
            spring_pending <= 0;
        else if (phase == IDLE && step_start)
            spring_pending <= 0;
        else if (jump_press && was_grounded && !spring_fired)
            spring_pending <= 1;
    end

    always @(posedge clk) begin
        if (reset) begin
            sampled_rocket_cos<=0; sampled_rocket_sin<=0; rocket_terms<=0; rocket_force_x<=0; rocket_force_y<=0;
            step_moments_enabled<=0; wheel_force_valid<=0; step_wheel_force<=0;
            angular_velocity_q8<=0; moment_angle_remainder<=0; step_angular_sum<=0;
            step_pivot_x<=0; step_pivot_y<=0;
            phase <= IDLE; init_ready <= 0; was_grounded <= 0; boost_timer <= 0;
            spring_fired <= 0; sampled_vertical_rockets <= 0; step_vertical_force <= 0;
            remainder_y <= 0; pending_remainder_y <= 0; step_vertical_base <= 0; step_vy_sum <= 0;
            sampled_fans <= 0; sampled_rockets <= 0; step_air_force <= 0;
            last_ground_slope <= 0; sampled_slope <= 0;
            previous_tilt <= 0; proposed_tilt <= 0; vehicle_tilt <= 0;
            spin <= 0; spin_frac <= 0; last_tip <= 0; held_target <= 0; held_count <= 0;
            step_slope_product <= 0; step_slope_force <= 0;
            movement_committed <= 0;
            vehicle_x <= spawn_x; vehicle_y <= spawn_y; display_y <= spawn_y; display_vy <= 0;
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
            sampled_wheels <= 0; sampled_engines <= 0; sampled_balloons <= 0; sampled_sided <= 0;
            sampled_engine_enabled <= 0; sampled_engine_reverse <= 0; sampled_spring <= 0;
        end else begin
            movement_committed <= 0;
            divider_start <= 0;
            if (!run_init) init_ready <= 0;
            if (boost_timer != 0) boost_timer <= boost_timer - 1'b1;
            if (game_state == `LP_RUN && boost_req && engine_count != 0) boost_timer <= 28'd150000000;
            if (run_init && !init_ready) begin
                angular_velocity_q8<=0; moment_angle_remainder<=0; wheel_force_valid<=0;
                phase <= IDLE; init_ready <= 1; was_grounded <= 0; spring_fired <= 0;
                remainder_y <= 0; pending_remainder_y <= 0;
                last_ground_slope <= 0;
                previous_tilt <= 0; proposed_tilt <= 0; vehicle_tilt <= 0;
                spin <= 0; spin_frac <= 0; last_tip <= 0; held_target <= 0; held_count <= 0;
                vehicle_x <= spawn_x; vehicle_y <= spawn_y; display_y <= spawn_y; display_vy <= 0;
                previous_x <= spawn_x; previous_y <= spawn_y;
                proposed_x <= spawn_x; proposed_y <= spawn_y;
                proposed_vx <= 0; proposed_vy <= 0; velocity_x <= 0; velocity_y <= 0;
                            remainder_x <= 0; pending_remainder_x <= 0; remainder_mass <= 0;
                boost_timer <= 0;
            end else if (game_state != `LP_RUN) begin
                angular_velocity_q8<=0; moment_angle_remainder<=0; wheel_force_valid<=0;
                phase <= IDLE;
                last_ground_slope <= 0; was_grounded <= 0; spring_fired <= 0;
                spin <= 0; spin_frac <= 0; last_tip <= 0; held_target <= 0; held_count <= 0;
                display_y <= vehicle_y; display_vy <= 0;
            end else case (phase)
                IDLE: if (step_start) begin
                    // Capture all properties once. Later input changes cannot
                    // change this update while arithmetic or collision is busy.
                    previous_x <= vehicle_x; previous_y <= vehicle_y;
                    previous_tilt <= vehicle_tilt;
                    // A supported body tipping over an edge gains spin; otherwise it
                    // settles one angle step per update onto the ground under it.
                    // Airborne, the body keeps the spin it left the ground with.
                    step_moments_enabled<=moments_enabled; wheel_force_valid<=0;
                    step_pivot_x<=0; step_pivot_y<=0;
                    if (moments_enabled) begin
                        proposed_tilt<=vehicle_tilt;
                        if (was_grounded && !spring_now && active_tip==0) begin
                            if (desired_tilt!=held_target) begin held_target<=desired_tilt; held_count<=0; end
                            else if (held_count!=2'd2) held_count<=held_count+1'b1;
                        end else held_count<=0;
                    end else if (was_grounded && !spring_now && active_tip == 0) begin
                        spin <= 0; spin_frac <= 0;
                        if (desired_tilt != held_target) begin held_target <= desired_tilt; held_count <= 0; end
                        else if (held_count != 2'd2) held_count <= held_count+1'b1;
                        if (target_steady && settle_error > 0) proposed_tilt <= vehicle_tilt+1'b1;
                        else if (target_steady && settle_error < 0) proposed_tilt <= vehicle_tilt-1'b1;
                        else proposed_tilt <= vehicle_tilt;
                    end else begin
                        held_count <= 0;
                        if (was_grounded && !spring_now) spin <= next_tip_spin;
                        spin_frac <= spin_sum[3:0];
                        proposed_tilt <= vehicle_tilt+(spin_sum >>> 4);
                    end
                    step_x <= vehicle_x; step_y <= vehicle_y;
                    step_vx <= velocity_x; step_mass <= mass_units;
                    step_remainder <= remainder_x;
                    pending_remainder_x <= 0; pending_remainder_y <= 0;
                    sampled_wheels <= contact_wheels; sampled_engines <= engine_count;
                    sampled_sided <= (wheels_down|wheels_up)!=0;
                    sampled_balloons <= balloon_count;
                    sampled_engine_enabled <= engine_enabled; sampled_engine_reverse <= engine_reverse;
                    sampled_spring <= spring_now;
                    if (spring_now) spring_fired <= 1;
                    sampled_fans <= fan_enabled ? fan_balance : 5'sd0;
                    sampled_rockets <= rocket_active ? rocket_balance : 5'sd0;
                    sampled_vertical_rockets <= rocket_active ? rocket_vertical_balance : 5'sd0;
                    sampled_rocket_cos<=rotation_cos(vehicle_tilt);
                    sampled_rocket_sin<=rotation_sin(vehicle_tilt);
                    sampled_slope <= last_ground_slope;
                    sampled_boosting <= is_boosting;
                    phase <= CALC_FORCE;
                end
                CALC_FORCE: begin
                    // Part counting ends at the sampled registers above. Force
                    // multiplication/addition then has its own 100 MHz clock.
                    step_vertical_force <= 0;
                    rocket_force_x<=0; rocket_force_y<=0;
                    rocket_terms<=sampled_rockets<0 ? -sampled_rockets : sampled_rockets;
                    step_vertical_base <= sampled_spring ? -17'sd512 : vertical_sum;
                    // Reverse the legacy facing sign to match the fan thrust direction.
                    step_air_force <= -($signed({{11{sampled_fans[4]}},sampled_fans}) <<< FAN_FORCE_SHIFT);
                    step_thrust <= 0;
                    // With wheel sides reported, only wheels touching the ground drive.
                    if (sampled_engine_enabled && sampled_engines != 0 && (sampled_wheels != 0 || (!sampled_sided && !step_moments_enabled)) && was_grounded) begin
                        if (sampled_boosting)
                            step_thrust <= sampled_engine_reverse ? -(engine_magnitude <<< 1) : (engine_magnitude <<< 1);
                        else
                            step_thrust <= sampled_engine_reverse ? -engine_magnitude : engine_magnitude;
                    end
                    step_friction_limit <= was_grounded ? wheel_resistance : 16'd0;
                    if (sampled_spring)
                        step_vy <= -SPRING_IMPULSE;
                    else if (vertical_sum > 17'sd512)
                        step_vy <= 16'sd512;
                    else if (vertical_sum < -17'sd512)
                        step_vy <= -16'sd512;
                    else
                        step_vy <= vertical_sum[15:0];
                    // Lift reduces weight on the ramp. Spring launch or net upward
                    // lift detaches the body, so neither gets ground gravity.
                    if (was_grounded && !sampled_spring && net_gravity > 0)
                        step_slope_product <= net_gravity * slope_factor(slope_magnitude);
                    else step_slope_product <= 0;
                    phase <= (sampled_rockets!=0 || sampled_vertical_rockets!=0) ? ROCKET_HORIZONTAL : SLOPE_FORCE;
                end
                ROCKET_HORIZONTAL: begin
                    // The thrust vector rotates with the attached rocket. Sum
                    // bounded per-rocket vectors serially instead of multiplying.
                    if(rocket_terms==0) begin
                        rocket_terms<=sampled_vertical_rockets<0 ? -sampled_vertical_rockets : sampled_vertical_rockets;
                        phase<=ROCKET_VERTICAL;
                    end else begin
                        rocket_force_x<=rocket_force_x+(sampled_rockets<0 ? -rocket_unit_x : rocket_unit_x);
                        rocket_force_y<=rocket_force_y+(sampled_rockets<0 ? -rocket_unit_y : rocket_unit_y);
                        rocket_terms<=rocket_terms-1'b1;
                    end
                end
                ROCKET_VERTICAL: begin
                    if(rocket_terms==0) phase<=ROCKET_DONE;
                    else begin
                        rocket_force_x<=rocket_force_x+(sampled_vertical_rockets<0 ? rocket_unit_y : -rocket_unit_y);
                        rocket_force_y<=rocket_force_y+(sampled_vertical_rockets<0 ? -rocket_unit_x : rocket_unit_x);
                        rocket_terms<=rocket_terms-1'b1;
                    end
                end
                ROCKET_DONE: begin
                    step_air_force<=step_air_force+rocket_force_x;
                    step_vertical_force<=rocket_force_y;
                    phase<=SLOPE_FORCE;
                end
                SLOPE_FORCE: begin
                    step_wheel_force<=step_thrust;
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
                    phase <= AIR_FORCE;
                end
                AIR_FORCE: begin
                    step_thrust <= step_thrust + step_air_force;
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
                    step_wheel_force<=step_wheel_force+step_friction;
                    wheel_force_valid<=1;
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
                    phase <= VERTICAL_START;
                end
                VERTICAL_START: begin
                    // Time-share the horizontal serial divider: no second divider
                    // or multiplier is required for vertical rocket thrust.
                    if (step_vertical_force == 0 && remainder_y == 0)
                        phase <= MOMENT_WAIT;
                    else if (!divider_busy) begin
                        divider_input <= step_vertical_force +
                            (step_mass == remainder_mass ? remainder_y : 16'sd0);
                        divider_start <= 1;
                        phase <= VERTICAL_WAIT;
                    end
                end
                VERTICAL_WAIT: if (divider_done) begin
                    step_vy_sum <= $signed({step_vertical_base[16],step_vertical_base}) +
                                   $signed({{2{divider_quotient[15]}},divider_quotient});
                    pending_remainder_y <= divider_zero ? 16'sd0 : divider_remainder;
                    phase <= VERTICAL_CLAMP;
                end
                VERTICAL_CLAMP: begin
                    if (step_vy_sum > 18'sd512) begin
                        step_vy <= 16'sd512; pending_remainder_y <= 0;
                    end else if (step_vy_sum < -18'sd512) begin
                        step_vy <= -16'sd512; pending_remainder_y <= 0;
                    end else begin
                        step_vy <= step_vy_sum[15:0];
                        if ((step_vy_sum == 18'sd512 && pending_remainder_y > 0) ||
                            (step_vy_sum == -18'sd512 && pending_remainder_y < 0))
                            pending_remainder_y <= 0;
                    end
                    phase <= MOMENT_WAIT;
                end
                MOMENT_WAIT: begin
                    if (!step_moments_enabled) phase<=POSITION;
                    else if (moment_valid) begin
                        // Ground contact dissipates spin even while a motor is
                        // pushing. Airborne thruster spin remains undamped.
                        step_angular_sum<=
                            (was_grounded && !sampled_spring ?
                            $signed(angular_velocity_q8)-($signed(angular_velocity_q8) >>> 2) :
                            $signed(angular_velocity_q8))+$signed(supported_moment_accel)+
                            (was_grounded && !sampled_spring ?
                            (active_tip>0 ? 18'sd256 : active_tip<0 ? -18'sd256 : 18'sd0) : 18'sd0);
                        phase<=ROTATE_FORCE;
                    end
                end
                ROTATE_FORCE: begin
                    // Ground contact can settle a quiet body; otherwise integrate
                    // signed fractional angle symmetrically in both directions.
                    if (was_grounded && !sampled_spring && active_tip==0 && supported_moment_accel==0 &&
                        clamped_angular_velocity<14'sd256 && clamped_angular_velocity> -14'sd256) begin
                        angular_velocity_q8<=0; moment_angle_remainder<=0; spin<=0; spin_frac<=0;
                        if (target_steady && settle_error>0) proposed_tilt<=vehicle_tilt+1'b1;
                        else if (target_steady && settle_error<0) proposed_tilt<=vehicle_tilt-1'b1;
                        else proposed_tilt<=vehicle_tilt;
                    end else begin
                        angular_velocity_q8<=clamped_angular_velocity;
                        spin<=clamped_angular_velocity >>> 8;
                        spin_frac<=0;
                        if (force_angle_sum>=16'sd4096) begin
                            proposed_tilt<=vehicle_tilt+1'b1;
                            moment_angle_remainder<=force_angle_sum-16'sd4096;
                        end else if (force_angle_sum<= -16'sd4096) begin
                            proposed_tilt<=vehicle_tilt-1'b1;
                            moment_angle_remainder<=force_angle_sum+16'sd4096;
                        end else begin
                            proposed_tilt<=vehicle_tilt;
                            moment_angle_remainder<=force_angle_sum[12:0];
                        end
                    end
                    phase<=PIVOT_START;
                end
                PIVOT_START: phase<=PIVOT_WAIT;
                PIVOT_WAIT: if(pivot_valid) begin
                    step_pivot_x<=pivot_dx; step_pivot_y<=pivot_dy; phase<=POSITION;
                end
                POSITION: begin
                    step_x_sum <= $signed({step_x[`LP_COORD_BITS-1], step_x}) +
                                  $signed({{(`LP_COORD_BITS-15){step_result_vx[15]}}, step_result_vx});
                    step_y_sum <= $signed({step_y[`LP_COORD_BITS-1], step_y}) +
                                  $signed({{(`LP_COORD_BITS-15){step_vy[15]}}, step_vy});
                    phase <= step_moments_enabled ? APPLY_PIVOT : MAKE_REQUEST;
                end
                APPLY_PIVOT: begin
                    step_x_sum<=step_x_sum+$signed(step_pivot_x);
                    step_y_sum<=step_y_sum+$signed(step_pivot_y);
                    phase<=MAKE_REQUEST;
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
                    // An error of more than 12 pixels (none in normal motion) is not smoothed.
                    if (display_error > 22'sd3072 || display_error < -22'sd3072) begin
                        display_y <= corrected_y; display_vy <= 0;
                    end else begin
                        display_y <= display_guess + (display_error >>> 2);
                        display_vy <= display_vy + (display_error >>> 4);
                    end
                    vehicle_tilt <= sanitize_tilt(corrected_tilt);
                    last_tip <= grounded ? tip_dir : 2'sd0;
                    // A wall or roof that blocks an airborne turn stops the spin.
                    if ((step_moments_enabled || !grounded) && corrected_tilt != proposed_tilt) begin
                        spin<=0; spin_frac<=0; angular_velocity_q8<=0; moment_angle_remainder<=0;
                    end
                    velocity_x <= corrected_vx; velocity_y <= corrected_vy;
                    was_grounded <= grounded;
                    // A spring may fire once per continuous contact. Re-arm
                    // only when an accepted collision response releases it.
                    if (!grounded) spring_fired <= 0;
                    if (grounded && ground_slope >= -8'sd16 && ground_slope <= 8'sd16)
                        last_ground_slope <= ground_slope;
                    else last_ground_slope <= 0;
                    // A wall/contact correction must discard pre-contact carry.
                    if (corrected_vx == proposed_vx && corrected_x == proposed_x)
                        remainder_x <= pending_remainder_x;
                    else
                        remainder_x <= 0;
                    if (corrected_vy == proposed_vy && corrected_y == proposed_y)
                        remainder_y <= pending_remainder_y;
                    else remainder_y <= 0;
                    remainder_mass <= step_mass;
                    movement_committed <= 1; phase <= WAIT_WORLD;
                end
                WAIT_WORLD: if (update_release) phase <= IDLE;
                default: phase <= IDLE;
            endcase
        end
    end
endmodule

// Kept in this registered source file so existing open Vivado projects
// resolve the helper without a separate design-source registration.
`timescale 1ns / 1ps
`include "game_defs.vh"
// One rigid body. Coordinates are quarter pixels relative to grid centre.
// A single serial multiplier and divider are reused across all nine cells.
module vehicle_moments #(parameter integer ROCKET_FORCE_SHIFT = 9,
                         parameter integer WHEEL_TORQUE_SHIFT = 0) (
    input wire clk, reset, start,
    input wire [26:0] build_grid,
    input wire [8:0] build_frames, intact_mask, frame_intact_mask,
    input wire [8:0] facing_left, rocket_vertical_mask,
    input wire fan_on, rocket_on, grounded,
    input wire signed [`LP_TILT_BITS-1:0] tilt,
    input wire wheel_force_valid,
    input wire signed [15:0] wheel_force,
    output reg result_valid,
    input wire result_ready,
    output reg signed [15:0] angular_accel_q8,
    output reg [15:0] support_negative_q8, support_positive_q8,
    output reg signed [6:0] com_x_q2, com_y_q2,
    output reg [7:0] body_mass,
    input wire pivot_start,
    input wire signed [`LP_TILT_BITS-1:0] next_tilt,
    output reg pivot_valid,
    input wire pivot_ready,
    output reg signed [13:0] pivot_dx, pivot_dy,
    output wire signed [23:0] torque_q10
);
    `include "rotation_geometry.vh"
    localparam IDLE=0, SCAN=1, MASS_X_START=2, MASS_X_WAIT=3,
        MASS_Y_START=4, MASS_Y_WAIT=5, WAIT_FORCE=6, SHARE_START=7,
        SHARE_WAIT=8, CELL=9, ROT_FIRST=10, ROT_SECOND=11,
        ROT_COMBINE=12, TORQUE=13, WHEEL_MUL=14, ADD_TORQUE=15,
        ADVANCE=16, ACCEL_START=17, ACCEL_WAIT=18, DONE=19,
        MUL=20, MUL_SIGN=21, WAIT_PIVOT=22, PIVOT_OLD_X_SECOND=23,
        PIVOT_OLD_Y_FIRST=24, PIVOT_OLD_Y_SECOND=25, PIVOT_NEW_X_FIRST=26,
        PIVOT_NEW_X_SECOND=27, PIVOT_NEW_Y_FIRST=28, PIVOT_NEW_Y_SECOND=29,
        PIVOT_FINISH=30, PIVOT_DONE=31, SUPPORT_FIRST=32, SUPPORT_SECOND=33, SUPPORT_FINISH=34;
    reg [5:0] phase, mul_return;
    reg [3:0] index, wheel_contacts, balloons;
    reg signed [9:0] support_min, support_max;
    reg [26:0] grid;
    reg [8:0] frames, alive, frame_alive, direction, vertical, contact_mask;
    reg fans_active, rockets_active, on_ground, flipped;
    reg signed [9:0] cosine, sine, next_cosine, next_sine;
    reg signed [25:0] old_com_x, old_com_y;
    reg signed [11:0] mass_x, mass_y;
    reg signed [15:0] wheel_share, force_cell, saved_wheel_force;
    reg signed [4:0] wheel_remainder;
    reg is_wheel, axis_y;
    reg signed [8:0] arm_x, arm_y;
    reg signed [25:0] rot_first, rotation_sum;
    reg signed [23:0] cell_torque, torque_sum;
    assign torque_q10=torque_sum;
    wire [2:0] part=grid[index*3 +: 3];
    wire [8:0] support_down=frames << 3, support_up=frames >> 3;
    wire contact_wheel=alive[index] && part==`LP_PART_WHEEL &&
                       (flipped ? support_up[index] : support_down[index]);
    reg [2:0] cell_mass;
    reg signed [6:0] cell_x, cell_y;
    reg signed [15:0] cell_force;
    reg cell_axis_y, cell_is_wheel;
    always @* begin
        cell_mass=frame_alive[index] && frames[index] ? 3'd2 : 3'd0;
        if (alive[index]) case(part)
            `LP_PART_PIG, `LP_PART_BOOSTER, `LP_PART_FAN: cell_mass=cell_mass+3'd2;
            `LP_PART_ENGINE: cell_mass=cell_mass+3'd3;
            `LP_PART_WHEEL, `LP_PART_BALLOON: cell_mass=cell_mass+3'd1;
            default: begin end
        endcase
        case(index)
            0,3,6: cell_x=-7'sd32;
            2,5,8: cell_x=7'sd32;
            default: cell_x=0;
        endcase
        cell_y=index<3 ? -7'sd32 : index<6 ? 7'sd0 : 7'sd32;
        cell_force=0; cell_axis_y=0; cell_is_wheel=0;
        if (alive[index]) case(part)
            `LP_PART_FAN: if (fans_active)
                cell_force=direction[index] ? 16'sd64 : -16'sd64;
            `LP_PART_BOOSTER: if (rockets_active) begin
                cell_axis_y=vertical[index];
                if (vertical[index]) cell_force=direction[index] ? (16'sd1 <<< ROCKET_FORCE_SHIFT) : -(16'sd1 <<< ROCKET_FORCE_SHIFT);
                else cell_force=direction[index] ? -(16'sd1 <<< ROCKET_FORCE_SHIFT) : (16'sd1 <<< ROCKET_FORCE_SHIFT);
            end
            `LP_PART_WHEEL: if (on_ground && contact_mask[index]) begin
                cell_is_wheel=1;
                cell_force=wheel_share+(wheel_remainder>0 ? 16'sd1 : wheel_remainder<0 ? -16'sd1 : 16'sd0);
            end
            default: begin end
        endcase
    end

    reg divider_start;
    reg signed [15:0] dividend;
    reg [7:0] divisor;
    wire divider_busy, divider_done;
    wire signed [15:0] quotient, remainder;
    signed_divider16 u_divider(.clk(clk),.reset(reset),.start(divider_start),
        .dividend(dividend),.divisor(divisor),.busy(divider_busy),.done(divider_done),
        .divide_by_zero(),.quotient(quotient),.remainder(remainder));

    reg [9:0] mul_bits;
    reg [3:0] mul_count;
    reg mul_negative;
    reg signed [25:0] multiplicand, product;
    task multiply;
        input signed [15:0] a;
        input signed [9:0] b;
        input [5:0] return_phase;
        begin
            multiplicand <= {{10{a[15]}},a};
            mul_bits <= b<0 ? -b : b;
            mul_negative <= b<0;
            product <= 0; mul_count <= 0; mul_return <= return_phase;
            phase <= MUL;
        end
    endtask
    wire signed [23:0] accel_dividend=torque_sum >>> 3;
    wire signed [25:0] rotated_arm=rotation_sum >>> 8;
    wire signed [25:0] support_x=(rot_first-product) >>> 8;
    wire support_balanced=wheel_contacts!=0 && support_min<=0 && support_max>=0;
    always @(posedge clk) begin
        if (reset) begin
            phase<=IDLE; result_valid<=0; angular_accel_q8<=0;
            support_negative_q8<=0; support_positive_q8<=0; support_min<=0; support_max<=0; balloons<=0;
            pivot_valid<=0; pivot_dx<=0; pivot_dy<=0; next_cosine<=0; next_sine<=0; old_com_x<=0; old_com_y<=0;
            com_x_q2<=0; com_y_q2<=0; body_mass<=0;
            index<=0; wheel_contacts<=0; contact_mask<=0;
            grid<=0; frames<=0; alive<=0; frame_alive<=0; direction<=0; vertical<=0;
            fans_active<=0; rockets_active<=0; on_ground<=0; flipped<=0;
            cosine<=0; sine<=0; mass_x<=0; mass_y<=0;
            wheel_share<=0; wheel_remainder<=0; force_cell<=0; saved_wheel_force<=0;
            is_wheel<=0; axis_y<=0; arm_x<=0; arm_y<=0;
            rot_first<=0; rotation_sum<=0; cell_torque<=0; torque_sum<=0;
            divider_start<=0; dividend<=0; divisor<=0;
            mul_bits<=0; mul_count<=0; mul_negative<=0; multiplicand<=0; product<=0; mul_return<=0;
        end else begin
            divider_start<=0;
            case(phase)
                IDLE: if(start) begin
                    grid<=build_grid; frames<=build_frames; alive<=intact_mask;
                    frame_alive<=frame_intact_mask; direction<=facing_left; vertical<=rocket_vertical_mask;
                    fans_active<=fan_on; rockets_active<=rocket_on; on_ground<=grounded;
                    flipped<=tilt_flipped(tilt); cosine<=rotation_cos(tilt); sine<=rotation_sin(tilt);
                    index<=0; body_mass<=0; mass_x<=0; mass_y<=0;
                    contact_mask<=0; wheel_contacts<=0; torque_sum<=0;
                    balloons<=0; support_min<=10'sd511; support_max<=-10'sd512;
                    result_valid<=0; wheel_remainder<=0;
                    phase<=SCAN;
                end
                SCAN: begin
                    body_mass<=body_mass+cell_mass;
                    if(alive[index] && part==`LP_PART_BALLOON) balloons<=balloons+1'b1;
                    // Grid centres are -32, 0, +32 quarter pixels: shifts only.
                    if(cell_x<0) mass_x<=mass_x-($signed({1'b0,cell_mass}) <<< 5);
                    else if(cell_x>0) mass_x<=mass_x+($signed({1'b0,cell_mass}) <<< 5);
                    if(cell_y<0) mass_y<=mass_y-($signed({1'b0,cell_mass}) <<< 5);
                    else if(cell_y>0) mass_y<=mass_y+($signed({1'b0,cell_mass}) <<< 5);
                    contact_mask[index]<=contact_wheel;
                    if(contact_wheel) wheel_contacts<=wheel_contacts+1'b1;
                    if(index==8) phase<=MASS_X_START; else index<=index+1'b1;
                end
                MASS_X_START: if(!divider_busy) begin
                    dividend<={{4{mass_x[11]}},mass_x}; divisor<=body_mass;
                    divider_start<=1; phase<=MASS_X_WAIT;
                end
                MASS_X_WAIT: if(divider_done) begin com_x_q2<=quotient[6:0]; phase<=MASS_Y_START; end
                MASS_Y_START: if(!divider_busy) begin
                    dividend<={{4{mass_y[11]}},mass_y}; divisor<=body_mass;
                    divider_start<=1; phase<=MASS_Y_WAIT;
                end
                MASS_Y_WAIT: if(divider_done) begin com_y_q2<=quotient[6:0]; phase<=WAIT_FORCE; end
                WAIT_FORCE: if(wheel_force_valid) begin
                    saved_wheel_force<=wheel_force;
                    phase<=SHARE_START;
                end
                SHARE_START: begin
                    if(!on_ground || wheel_contacts==0) begin
                        wheel_share<=0; wheel_remainder<=0; index<=0; phase<=CELL;
                    end else if(!divider_busy) begin
                        dividend<=saved_wheel_force; divisor<={4'd0,wheel_contacts};
                        divider_start<=1; phase<=SHARE_WAIT;
                    end
                end
                SHARE_WAIT: if(divider_done) begin
                    wheel_share<=quotient; wheel_remainder<=remainder[4:0]; index<=0; phase<=CELL;
                end
                CELL: begin
                    force_cell<=cell_force; axis_y<=cell_axis_y; is_wheel<=cell_is_wheel;
                    arm_x<=$signed(cell_x)-$signed(com_x_q2);
                    // Wheel traction acts at the tyre's terrain-facing edge, four
                    // pixels beyond its cell centre; fans/rockets use cell centres.
                    arm_y<=$signed(cell_y)-$signed(com_y_q2)+
                           (cell_is_wheel ? (flipped ? -9'sd16 : 9'sd16) : 9'sd0);
                    if(cell_is_wheel) begin
                        if(wheel_remainder>0) wheel_remainder<=wheel_remainder-1'b1;
                        else if(wheel_remainder<0) wheel_remainder<=wheel_remainder+1'b1;
                    end
                    phase<=cell_force==0 && !cell_is_wheel ? ADVANCE : ROT_FIRST;
                end
                ROT_FIRST: begin
                    if(part==`LP_PART_BOOSTER) begin
                        // Rocket force and its arm rotate together. Their cross
                        // product is invariant, so use body coordinates directly.
                        rotation_sum<=axis_y ? ($signed(arm_x) <<< 8) : ($signed(arm_y) <<< 8);
                        phase<=TORQUE;
                    end else multiply({{7{arm_x[8]}},arm_x},axis_y ? cosine : sine,ROT_SECOND);
                end
                ROT_SECOND: begin
                    rot_first<=product;
                    multiply({{7{arm_y[8]}},arm_y},axis_y ? sine : cosine,ROT_COMBINE);
                end
                ROT_COMBINE: begin
                    rotation_sum<=axis_y ? rot_first-product : rot_first+product;
                    phase<=is_wheel ? SUPPORT_FIRST : TORQUE;
                end
                SUPPORT_FIRST: multiply({{7{arm_x[8]}},arm_x},cosine,SUPPORT_SECOND);
                SUPPORT_SECOND: begin
                    rot_first<=product;
                    multiply({{7{arm_y[8]}},arm_y},sine,SUPPORT_FINISH);
                end
                SUPPORT_FINISH: begin
                    // A small tyre contact patch supplies a bounded normal
                    // reaction moment about COM. Translation's normal response
                    // remains owned by the existing collision engine.
                    if(support_x-26'sd16<support_min) support_min<=support_x-26'sd16;
                    if(support_x+26'sd16>support_max) support_max<=support_x+26'sd16;
                    phase<=TORQUE;
                end
                TORQUE: begin
                    if(is_wheel && force_cell==0) phase<=ADVANCE;
                    else if(is_wheel) multiply(force_cell,rotated_arm[9:0],WHEEL_MUL);
                    else begin
                        // tau = rx*Fy - ry*Fx. Power-of-two actuator forces
                        // replace the final multiply with a constant shift.
                        if(part==`LP_PART_FAN)
                            cell_torque<=(axis_y ^ force_cell[15]) ? (rotated_arm <<< 6) : -(rotated_arm <<< 6);
                        else
                            cell_torque<=(axis_y ^ force_cell[15]) ? (rotated_arm <<< ROCKET_FORCE_SHIFT) : -(rotated_arm <<< ROCKET_FORCE_SHIFT);
                        phase<=ADD_TORQUE;
                    end
                end
                WHEEL_MUL: begin
                    // Optional game stability gain for unresolved wheel/terrain
                    // contact reactions; fan and rocket moments are unscaled.
                    cell_torque<=(-product) >>> WHEEL_TORQUE_SHIFT;
                    phase<=ADD_TORQUE;
                end
                ADD_TORQUE: begin torque_sum<=torque_sum+cell_torque; phase<=ADVANCE; end
                ADVANCE: if(index==8) phase<=ACCEL_START;
                         else begin index<=index+1'b1; phase<=CELL; end
                ACCEL_START: if(!divider_busy) begin
                    // Fixed mass-scaled rotational inertia, not a per-cell tensor.
                    // Q10 torque becomes Q8 angular acceleration with tau/(8*mass).
                    if(accel_dividend>24'sd32767) dividend<=16'sd32767;
                    else if(accel_dividend< -24'sd32768) dividend<=-16'sd32768;
                    else dividend<=accel_dividend[15:0];
                    divisor<=body_mass; divider_start<=1; phase<=ACCEL_WAIT;
                end
                ACCEL_WAIT: if(divider_done) begin
                    angular_accel_q8<=quotient;
                    // Weight is mass*(32-24*balloons). After the same inertia
                    // scaling, mass cancels: support arm times 4, 1, or 0.
                    if(on_ground && support_balanced && balloons<2) begin
                        support_negative_q8<=balloons==0 ? (-support_min <<< 2) : -support_min;
                        support_positive_q8<=balloons==0 ? (support_max <<< 2) : support_max;
                    end else begin support_negative_q8<=0; support_positive_q8<=0; end
                    result_valid<=1; phase<=DONE;
                end
                DONE: if(result_ready) begin result_valid<=0; phase<=WAIT_PIVOT; end
                // Keep COM world motion unchanged by the grid-centre rotation:
                // origin correction = R(old)*COM - R(new)*COM.
                WAIT_PIVOT: if(pivot_start) begin
                    next_cosine<=rotation_cos(next_tilt); next_sine<=rotation_sin(next_tilt);
                    multiply({{9{com_x_q2[6]}},com_x_q2},cosine,PIVOT_OLD_X_SECOND);
                end
                PIVOT_OLD_X_SECOND: begin
                    rot_first<=product;
                    multiply({{9{com_y_q2[6]}},com_y_q2},sine,PIVOT_OLD_Y_FIRST);
                end
                PIVOT_OLD_Y_FIRST: begin
                    old_com_x<=rot_first-product;
                    multiply({{9{com_x_q2[6]}},com_x_q2},sine,PIVOT_OLD_Y_SECOND);
                end
                PIVOT_OLD_Y_SECOND: begin
                    rot_first<=product;
                    multiply({{9{com_y_q2[6]}},com_y_q2},cosine,PIVOT_NEW_X_FIRST);
                end
                PIVOT_NEW_X_FIRST: begin
                    old_com_y<=rot_first+product;
                    multiply({{9{com_x_q2[6]}},com_x_q2},next_cosine,PIVOT_NEW_X_SECOND);
                end
                PIVOT_NEW_X_SECOND: begin
                    rot_first<=product;
                    multiply({{9{com_y_q2[6]}},com_y_q2},next_sine,PIVOT_NEW_Y_FIRST);
                end
                PIVOT_NEW_Y_FIRST: begin
                    pivot_dx<=(old_com_x-(rot_first-product)) >>> 2;
                    multiply({{9{com_x_q2[6]}},com_x_q2},next_sine,PIVOT_NEW_Y_SECOND);
                end
                PIVOT_NEW_Y_SECOND: begin
                    rot_first<=product;
                    multiply({{9{com_y_q2[6]}},com_y_q2},next_cosine,PIVOT_FINISH);
                end
                PIVOT_FINISH: begin
                    pivot_dy<=(old_com_y-(rot_first+product)) >>> 2;
                    pivot_valid<=1; phase<=PIVOT_DONE;
                end
                PIVOT_DONE: if(pivot_ready) begin pivot_valid<=0; phase<=IDLE; end
                MUL: begin
                    if(mul_bits[0]) product<=product+multiplicand;
                    multiplicand<=multiplicand <<< 1; mul_bits<=mul_bits >> 1;
                    if(mul_count==9) phase<=MUL_SIGN; else mul_count<=mul_count+1'b1;
                end
                MUL_SIGN: begin product<=mul_negative ? -product : product; phase<=mul_return; end
                default: phase<=IDLE;
            endcase
        end
    end
endmodule
