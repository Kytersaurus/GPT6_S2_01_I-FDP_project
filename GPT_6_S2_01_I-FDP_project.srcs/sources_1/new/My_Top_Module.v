// Owner: Shared integration - all roles; Role 4 (Marcus) coordinates edits.
`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: 
//  STUDENT B NAME:
//  STUDENT C NAME: 
//  STUDENT D NAME:  
//////////////////////////////////////////////////////////////////////////////////

`include "game_defs.vh"

// SW0 1-OLED JA map view, SW1 engine debug, SW2 reverse, SW13 free-look pan, SW14 zoom, SW15 mute;
// BTNL reserved, BTNC launch/retry, BTNU edit/next level after success, BTNR reserved and BTND reset.
module My_Top_Module #(
    parameter integer PHYSICS_CYCLES = 1666667,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 20000000,
    parameter integer BUTTON_RELEASE_CYCLES = 2000000,
    parameter integer AUDIO_TONE_HALF_CYCLES = 50000,
    parameter integer AUDIO_BEEP_CYCLES = 20000000,
    parameter integer AUDIO_NOTE_CYCLES = 8000000,
    parameter integer AUDIO_FADE_CYCLES = 50000,
    parameter integer ENABLE_BGM = 1,
`ifdef SYNTHESIS
    parameter integer ENABLE_START_SCREEN = 1,
`else
    parameter integer ENABLE_START_SCREEN = 0,
`endif
    parameter integer BGM_UNIT_CYCLES = 15625000,
    parameter integer FRAME_LIMIT = 5,
    parameter integer PIG_LIMIT = 1,
    parameter integer WHEEL_LIMIT = 4,
    parameter integer ENGINE_LIMIT = 1,
    // Ground thrust per engine. 320 lets one engine pull a 15-unit cart (three
    // frames, pig, engine, four wheels) up about 40 degrees, as a motor cart in
    // Bad Piggies climbs a hill; 96 managed only about 12 degrees.
    parameter integer ENGINE_FORCE = 320,
    parameter integer ENABLE_MOMENTS = 1,
    parameter integer WHEEL_TORQUE_SHIFT = 2, // compatibility only; wheel drive adds no torque
    // Rocket must overcome gravity on a loaded cart when pointing upward.
    parameter integer ROCKET_FORCE_SHIFT = 10, // 1024; set 9 for the older 512
    parameter integer BALLOON_LIMIT = 2,
    parameter integer ROCKET_LIMIT = 1, FAN_LIMIT = 1,
    parameter integer FEEDBACK_CYCLES = 100000000
) (
    input wire clk, btnC, btnU, btnR, btnL, btnD,
    input wire [15:0] sw,
    inout wire PS2Clk, PS2Data,
    output wire [15:0] led,
    output wire [7:0] JA, JB,
    output wire [6:0] seg,
    output wire [3:0] an,
    output wire dp,
    output wire [3:0] JXADC
);
`ifdef SYNTHESIS
    wire enable_start_screen = 1'b1;
`else
    wire enable_start_screen = (ENABLE_START_SCREEN != 0);
`endif
    wire reset, oled_clk, oled_reset, physics_tick, start_press, edit_press, engine_enabled;
    wire support_unstable;
    wire support_span_valid, ground_slope_valid;
    wire [3:0] support_wheel_count;
    wire signed [9:0] support_left_q2, support_right_q2, support_y_q2;
    wire signed [9:0] support_left_y_q2, support_right_y_q2;
    wire signed [13:0] pivot_dx_q8, pivot_dy_q8;
    wire engine_reverse, reverse_switch_enabled, jump_press, boost_req, boost_active;
    wire [1:0] run_page, draw_run_page;
    wire selected_left, edit_facing_left, draw_selected_left;
    wire selected_down, edit_facing_down;
    wire [1:0] inventory_page, draw_inventory_page;
    wire [8:0] build_facing_left, draw_facing_left;
    wire [8:0] build_facing_down;
    wire engine_facing_left, fan_facing_left, fan_facing_down, rocket_facing_left, rocket_facing_down;
    wire signed [4:0] engine_balance, fan_balance, rocket_balance;
    wire rocket_ready, rocket_active;
    wire [3:0] drive_engines = engine_balance<0 ? -engine_balance : engine_balance;
    wire [3:0] rocket_count, fan_count, rockets_left, fans_left, draw_rockets_left, draw_fans_left;
    // Every production build uses the same COM-aware body. Wheel drive stays
    // translational; adding an inactive fan must not change the physics model.
    wire body_moments_enabled = (ENABLE_MOMENTS != 0);
    wire fan_available = fan_count != 0;
    wire rocket_available = rocket_count != 0;
    wire ui_fan_on, ui_rocket_req, ui_sound_muted; wire [8:0] ui_active_fans; wire [3:0] mouse_fan_toggle_cell;
    assign engine_reverse = reverse_switch_enabled ^ (engine_balance<0);
    wire engine_switch_changed, ui_engine_on, ui_launch, ui_edit, ui_guide_open, ui_guide_close;
    wire [1:0] diary_page, death_phase;
    wire [2:0] master_volume, draw_master_volume;
    wire [2:0] guide_return_state;
    wire signed [`LP_COORD_BITS-1:0] death_x, death_y;
    wire launch_flash; wire [2:0] game_state, init_ready; wire run_init, step_start, update_release;
    // SW1 changes the shared engine state; in hardware SW1 enables directly during RUN.
`ifdef SYNTHESIS
    assign engine_enabled = (game_state == `LP_RUN && !run_init) ? (ui_engine_on || sw[1]) : 1'b0;
`else
    assign engine_enabled = (game_state == `LP_RUN && !run_init) ? ui_engine_on : 1'b0;
`endif


    wire [26:0] build_grid;
    wire [8:0] build_frames, intact_mask, frame_intact_mask;
    wire build_valid, pig_alive, damage_ready;
    wire [3:0] build_error, wheel_count, engine_count, balloon_count, wheels_down, wheels_up;
    wire signed [1:0] tip_dir;
    wire [2:0] feedback_code;
    wire [3:0] feedback_cell;
    wire [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left;
    wire [11:0] mouse_x, mouse_y, mouse_value;
    wire mouse_left, mouse_right, mouse_event, setx, sety, setmax_x, setmax_y;
    wire [6:0] cursor_x, cursor_y;
    wire [2:0] selected_part, edit_part;
    wire edit_valid, drag_active, drag_from_grid;
    wire [2:0] drag_contents;
    wire [1:0] edit_op;
    wire [3:0] edit_cell, edit_source, drag_source;
    wire left_frame;
    reg view_meta_game, view_sync_game, view_ack_meta, view_ack_game;
    reg view_meta_display, view_sync_display, show_map;
    wire builder_input_enabled = !view_sync_game && !view_ack_game;
    // SW0 chooses the 1-OLED JA map view; publish the change only between complete frames.
    always @(posedge clk) begin
        if (reset) begin
            view_meta_game <= 0; view_sync_game <= 0; view_ack_meta <= 0; view_ack_game <= 0;
        end else begin
            view_meta_game <= sw[0]; view_sync_game <= view_meta_game;
            view_ack_meta <= show_map; view_ack_game <= view_ack_meta;
        end
    end
    always @(posedge oled_clk) begin
        if (oled_reset) begin view_meta_display <= 0; view_sync_display <= 0; show_map <= 0; end
        else begin
            view_meta_display <= view_sync_game; view_sync_display <= view_meta_display;
            if (left_frame) show_map <= view_sync_display;
        end
    end
    wire pop_req, pop_pending, pop_valid, gameplay_ready;
    wire [3:0] pop_cell;
    wire [8:0] pop_mask;
    wire [7:0] mass_units;
    wire signed [`LP_COORD_BITS-1:0] spawn_x, spawn_y, vehicle_x, vehicle_y, display_x, display_y;
    // Preserve the full Q12.8 spawn throughout movement and display.
    wire signed [19:0] level_spawn_x, level_spawn_y;
    assign spawn_x = level_spawn_x;
    assign spawn_y = level_spawn_y;
    wire [2:0] terrain_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire map_level, map_id;
    wire signed [10:0] collision_query_x, collision_query_y;
    // The live collision path only needs the registered solid/open result.
    // Map colour classes remain available on level_map's draw and simulation
    // interfaces, while this one-bit path avoids a second query colour ROM.
    wire collision_query_solid;
    // Collision only needs the solid/open result. Keeping this one-bit path
    // separate lets Vivado discard the query-side colour ROM copy.
    wire [2:0] collision_query_class = collision_query_solid ? `LP_MAP_ROCK : `LP_MAP_SKY;
    wire [9:0] world_width, world_height, flag_x, flag_y;
    wire level_open_req, level_close_req, level_select_req;
    wire [`LP_LEVEL_BITS-1:0] selected_level;
    wire [`LP_LEVEL_BITS-1:0] level_index;
    wire [3:0] mouse_z;
    wire zoomed_out, overview;
    wire [1:0] fail_reason;
    wire [7:0] run_seconds;
    wire [2*`LP_MAX_TNT-1:0] blast_phase;
    // Accepted launch and result pulses for Role 1 audio; Role 4 does not schedule sounds.
    wire [2:0] tnt_count;
    wire [`LP_TNT_BITS-1:0] tnt_positions;
    wire [1:0] hazard_count;
    wire [`LP_HAZARD_BITS-1:0] hazard_rects;
    wire [`LP_MAX_TNT-1:0] tnt_intact;
    wire tnt_damage_valid, tnt_complete;
    wire [8:0] tnt_damage_mask, tnt_frame_mask;
    wire tnt_knockback_valid;
    wire signed [15:0] tnt_knockback_x, tnt_knockback_y;
    wire collision_impact_valid;
    wire [3:0] collision_impact_flags;
    wire move_valid, move_ready, response_valid, response_ready, grounded;
    wire signed [7:0] ground_slope;
    wire signed [`LP_TILT_BITS-1:0] previous_tilt, proposed_tilt, corrected_tilt, vehicle_tilt;
    wire signed [`LP_COORD_BITS-1:0] previous_x, previous_y, proposed_x, proposed_y;
    wire signed [15:0] proposed_vx, proposed_vy;
    wire signed [`LP_COORD_BITS-1:0] corrected_x, corrected_y;
    wire signed [15:0] corrected_vx, corrected_vy;
    wire movement_committed, world_valid, world_ready, goal_hit, hazard_hit, out_of_bounds, star_box_hit, star_box_collected;
    wire [9:0] star_box_x, star_box_y;
    wire [9:0] draw_star_box_x, draw_star_box_y;
    wire launch_event, success_event, failure_event;
    wire switch_audio_muted, audio_muted, audio_busy, audio_pwm;
    assign audio_muted = switch_audio_muted || ui_sound_muted;
    wire sound_start;
    wire signed [3:0] bgm_sample;
    wire [2:0] sound_id, active_sound;
    reg audio_was_grounded;
    reg [2:0] previous_game_state;
    wire audio_cancel = run_init || (game_state == `LP_BUILD && previous_game_state != `LP_BUILD);
    wire pop_sound_event = pop_valid && damage_ready && (|pop_mask);
    // Crash damage is based on fall distance, not ordinary rolling speed.
    // Coordinates are Q12.8. The normal 24-pixel spawn drop stays harmless. A
    // 48-pixel ledge or balloon drop damages the contact row; a 96-pixel fall
    // tears off everything except the protected pig and its frame.
    localparam signed [19:0] ARCH_FALL_DISTANCE_Q8   = 20'sd16384; // 64 px (Map 1, 2x scale)
    localparam signed [19:0] FLIGHT_FALL_DISTANCE_Q8 = 20'sd13312; // 52 px (Map 2, 1x scale)

    wire wall_crash_right = ($signed(proposed_vx) >= 16'sd448 && $signed(corrected_vx) <= 0);
    wire wall_crash_left  = ($signed(proposed_vx) <= -16'sd448 && $signed(corrected_vx) >= 0);
    wire wall_crash_event = (wall_crash_right || wall_crash_left);

    // Ignore the first gentle contact at spawn and continuous rolling contact.
    // Trigger on hard landings or high-speed wall collisions.
    wire collision_sound_event = game_state == `LP_RUN && response_valid && response_ready &&
                                 ((grounded && !audio_was_grounded && $signed(proposed_vy) >= 16'sd128) ||
                                  wall_crash_event);
    wire explosion_sound_event;
    reg [5:0] airborne_ticks;
    reg falling;
    reg signed [`LP_COORD_BITS-1:0] fall_start_y;
    wire signed [`LP_COORD_BITS-1:0] fall_distance_q8 = $signed(corrected_y) - $signed(fall_start_y);
    wire high_fall_landing = response_valid && response_ready && grounded && !audio_was_grounded &&
                              falling && (airborne_ticks >= (map_id ? 6'd14 : 6'd12)) &&
                              ($signed(proposed_vy) >= 16'sd512) &&
                              (fall_distance_q8 >= (map_id ? FLIGHT_FALL_DISTANCE_Q8 : ARCH_FALL_DISTANCE_Q8));
    always @(posedge clk) begin
        if (reset) begin
            audio_was_grounded <= 0;
            previous_game_state <= `LP_BUILD;
            airborne_ticks <= 6'd0;
            falling <= 1'b0;
            fall_start_y <= 0;
        end
        else begin
            previous_game_state <= game_state;
            if (run_init || game_state != `LP_RUN) begin
                audio_was_grounded <= 0;
                airborne_ticks <= 6'd0;
                falling <= 1'b0;
                fall_start_y <= 0;
            end
            else if (response_valid && response_ready) begin
                audio_was_grounded <= grounded;
                if (!grounded) begin
                    if (airborne_ticks < 6'd63) airborne_ticks <= airborne_ticks + 1'b1;
                    // Record the last grounded pose when leaving it. If the
                    // vehicle starts in the air, use its first airborne pose.
                    if (audio_was_grounded || !falling || ($signed(previous_y) < $signed(fall_start_y)) || ($signed(proposed_vy) <= 16'sd160)) fall_start_y <= previous_y;
                    falling <= 1'b1;
                end else begin
                    airborne_ticks <= 6'd0;
                    falling <= 1'b0;
                end
            end
        end
    end

    // Only a high fall landing can remove non-pig parts. Collision correction
    // still handles walls and ceilings, but those contacts are harmless here.
    wire vert_crash_event = high_fall_landing;

    reg [8:0] next_impact_mask;
    reg [8:0] next_frame_mask;

    always @* begin
        next_impact_mask = 9'd0;
        next_frame_mask = 9'd0;
        if (vert_crash_event) begin
            // A terminal high fall requests all cells/frames. vehicle_builder
            // still protects the pig through its final safety gate.
            next_impact_mask = 9'b111_111_111;
            next_frame_mask  = 9'b111_111_111;
        end
    end

    // Only scatter cells that are actually intact and are not the protected pig.
    wire [8:0] pig_mask = {
        (build_grid[26:24] == `LP_PART_PIG), (build_grid[23:21] == `LP_PART_PIG), (build_grid[20:18] == `LP_PART_PIG),
        (build_grid[17:15] == `LP_PART_PIG), (build_grid[14:12] == `LP_PART_PIG), (build_grid[11:9]  == `LP_PART_PIG),
        (build_grid[8:6]   == `LP_PART_PIG), (build_grid[5:3]   == `LP_PART_PIG), (build_grid[2:0]   == `LP_PART_PIG)
    };
    wire [8:0] scatter_damage_mask =
        (((next_impact_mask & intact_mask) | (next_frame_mask & frame_intact_mask)) & ~pig_mask);

    reg impact_damage_valid;
    reg [8:0] impact_damage_mask;
    reg [8:0] impact_damage_frame_mask;
    // Compact visual-only debris state. The renderer uses a fixed offset table
    // instead of instantiating independent physics for nine debris bodies.
    reg [8:0] scatter_mask;
    reg signed [`LP_COORD_BITS-1:0] scatter_x, scatter_y;
    reg [5:0] scatter_phase;

    always @(posedge clk) begin
        if (reset || run_init || game_state != `LP_RUN) begin
            impact_damage_valid <= 1'b0;
            impact_damage_mask <= 9'd0;
            impact_damage_frame_mask <= 9'd0;
            scatter_mask <= 9'd0;
            scatter_x <= 0;
            scatter_y <= 0;
            scatter_phase <= 6'd0;
        end else begin
            impact_damage_valid <= 1'b0;
            if (scatter_phase != 0 && physics_tick) begin
                if (scatter_phase >= 6'd24) scatter_phase <= 6'd0;
                else scatter_phase <= scatter_phase + 1'b1;
            end
            if (response_valid && response_ready && damage_ready && vert_crash_event) begin
                impact_damage_valid <= 1'b1;
                impact_damage_mask <= next_impact_mask;
                impact_damage_frame_mask <= next_frame_mask;
                if (scatter_damage_mask != 0) begin
                    scatter_mask <= scatter_damage_mask;
                    scatter_x <= corrected_x;
                    scatter_y <= corrected_y;
                    scatter_phase <= 6'd1;
                end else begin
                    scatter_mask <= 9'd0;
                    scatter_phase <= 6'd0;
                end
            end
        end
    end

    clock_control #(.PHYSICS_CYCLES(PHYSICS_CYCLES)) u_clocking (
        .clk(clk), .reset_button(btnD), .reset(reset), .oled_clk(oled_clk),
        .oled_reset(oled_reset), .physics_tick(physics_tick)
    );


    wire right_press;
    input_controller #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES), .RELEASE_CYCLES(BUTTON_RELEASE_CYCLES)
    ) u_input (
        .clk(clk), .reset(reset), .btnC(btnC), .btnU(btnU), .btnL(btnL), .btnR(btnR),
        .engine_switch(sw[1]), .mute_switch(sw[15]), .reverse_switch(sw[2]), .start_press(start_press), .edit_press(edit_press),
        .right_press(right_press),
        .engine_switch_changed(engine_switch_changed),
        .audio_muted(switch_audio_muted), .engine_reverse(reverse_switch_enabled), .jump_press(jump_press)
    );
    wire start_screen_active;
    wire ui_home_req;
    wire ui_level_open_req;
    wire mouse_pop_req;
    wire [3:0] mouse_pop_cell;
    wire ui_boost_req, mouse_boost_req, combined_boost_req;
    wire mouse_engine_toggle_req, mouse_fan_toggle_req, ui_end_try;

    assign pop_req = mouse_pop_req;
    assign pop_cell = mouse_pop_cell;

    assign level_open_req = ui_level_open_req;
    assign combined_boost_req = rocket_ready && (ui_boost_req || mouse_boost_req || (game_state == `LP_RUN && right_press));
    assign boost_req = combined_boost_req;

    wire [11:0] effective_mouse_x = {5'd0, cursor_x};
    wire [11:0] effective_mouse_y = {6'd0, cursor_y};

    ui_controller u_ui_control (
        .clk(clk), .reset(reset), .input_enabled(builder_input_enabled), .run_init(run_init),
        .physics_tick(physics_tick), .launch_event(launch_event),
        .start_screen_active(start_screen_active), .game_state(game_state),
        .mouse_x(effective_mouse_x), .mouse_y(effective_mouse_y),
        .mouse_left(mouse_left), .mouse_right(mouse_right), .mouse_event(mouse_event),
        .next_press(start_press), .engine_switch_changed(engine_switch_changed),
        .engine_switch(sw[1]), .engine_toggle_req(mouse_engine_toggle_req),
        .fan_toggle_req(mouse_fan_toggle_req), .fan_toggle_cell(mouse_fan_toggle_cell), .rocket_toggle_req(mouse_boost_req || (game_state == `LP_RUN && right_press)),
        .fan_available(fan_available), .rocket_available(rocket_available),
        .rocket_ready(rocket_ready), .balloon_available(balloon_count != 4'd0),
        .home_req(ui_home_req), .launch_req(ui_launch), .edit_req(ui_edit), .end_try_req(ui_end_try),
        .guide_open_req(ui_guide_open), .guide_close_req(ui_guide_close),
        .level_open_req(ui_level_open_req), .level_close_req(level_close_req),
        .level_select_req(level_select_req), .selected_level(selected_level),
        .run_page(run_page), .boost_req(ui_boost_req), .diary_page(diary_page),
        .master_volume(master_volume), .engine_on(ui_engine_on),
        .fan_on(ui_fan_on), .active_fans(ui_active_fans), .rocket_req(ui_rocket_req), .sound_muted(ui_sound_muted),
        .launch_flash(launch_flash)
    );
    wire [7:0] par_time;
    seven_seg_timer #(.COUNTDOWN(1), .TIME_LIMIT(20)) u_board_timer (.clk(clk), .reset(reset || (game_state!=`LP_RUN && game_state!=`LP_SUCCESS && game_state!=`LP_FAIL)), .seconds(run_seconds), .time_limit(par_time), .seg(seg), .an(an), .dp(dp));
    pig_death_effect u_pig_death (
        .clk(clk), .reset(reset), .run_init(run_init), .physics_tick(physics_tick), .pig_alive(pig_alive),
        .game_state(game_state), .build_grid(build_grid), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y), .vehicle_tilt(vehicle_tilt),
        .death_phase(death_phase), .death_x(death_x), .death_y(death_y)
    );
    sound_controller u_sound_control (
        .clk(clk), .reset(reset), .mute(audio_muted), .cancel(audio_cancel),
        .launch_event(launch_event), .pop_event(pop_sound_event),
        .collision_event(collision_sound_event), .explosion_event(explosion_sound_event),
        .success_event(success_event), .failure_event(failure_event),
        .busy(audio_busy), .active_sound(active_sound), .sound_start(sound_start), .sound_id(sound_id)
    );
    sound_generator #(
        .NOTE_CYCLES(AUDIO_NOTE_CYCLES), .FADE_CYCLES(AUDIO_FADE_CYCLES),
        .GAIN_SHIFT(2)
    ) u_audio (
        .clk(clk), .reset(reset), .start(sound_start), .sound_id(sound_id),
        .mute(audio_muted), .cancel(audio_cancel), .busy(audio_busy),
        .master_volume(master_volume), .active_sound(active_sound), .audio_pwm(audio_pwm), .bgm_sample(bgm_sample)
    );
    wire [1:0] bgm_mode = start_screen_active ? 2'd2 : (game_state == `LP_RUN ? 2'd1 : 2'd0);
    bgm_player #(.UNIT_CYCLES(BGM_UNIT_CYCLES), .FADE_CYCLES(AUDIO_FADE_CYCLES)) u_bgm (
        .clk(clk), .reset(reset),
        .enabled(ENABLE_BGM && !audio_muted && (start_screen_active || game_state == `LP_BUILD || game_state == `LP_LEVEL_SELECT || game_state == `LP_SETTINGS || game_state == `LP_GUIDE || game_state == `LP_RUN)),
        .fast(game_state == `LP_RUN),
        .bgm_mode(bgm_mode),
        .master_volume(master_volume), .pause(audio_busy || sound_start), .audio_sample(bgm_sample)
    );
    MouseCtl u_mouse (
        .clk(clk), .rst(reset), .xpos(mouse_x), .ypos(mouse_y), .zpos(mouse_z),
        .left(mouse_left), .middle(), .right(mouse_right), .new_event(mouse_event),
        .value(mouse_value), .setx(setx), .sety(sety), .setmax_x(setmax_x), .setmax_y(setmax_y),
        .ps2_clk(PS2Clk), .ps2_data(PS2Data)
    );
    mouse_adapter u_mouse_adapter (
        .clk(clk), .reset(reset), .input_enabled(builder_input_enabled && !start_screen_active), .game_state(game_state),
        .build_grid(build_grid), .build_frames(build_frames), .build_facing_left(build_facing_left), .build_facing_down(build_facing_down),
        .run_page(run_page), .selected_left(selected_left), .selected_down(selected_down), .inventory_page(inventory_page),
        .engine_facing_left(engine_facing_left), .fan_facing_left(fan_facing_left), .fan_facing_down(fan_facing_down), .rocket_facing_left(rocket_facing_left), .rocket_facing_down(rocket_facing_down),
        .edit_facing_left(edit_facing_left), .edit_facing_down(edit_facing_down), .mouse_x(mouse_x), .mouse_y(mouse_y),
        .mouse_left(mouse_left), .mouse_right(mouse_right), .mouse_event(mouse_event), .mouse_z(mouse_z),
        .mouse_value(mouse_value), .setx(setx), .sety(sety), .setmax_x(setmax_x), .setmax_y(setmax_y),
        .cursor_x(cursor_x), .cursor_y(cursor_y), .selected_part(selected_part),
        .drag_active(drag_active), .drag_from_grid(drag_from_grid), .drag_source(drag_source), .drag_contents(drag_contents),
        .edit_valid(edit_valid), .edit_op(edit_op), .edit_cell(edit_cell), .edit_source(edit_source), .edit_part(edit_part),
        .pop_req(mouse_pop_req), .pop_cell(mouse_pop_cell), .boost_req(mouse_boost_req),
        .engine_toggle_req(mouse_engine_toggle_req), .fan_toggle_req(mouse_fan_toggle_req), .fan_toggle_cell(mouse_fan_toggle_cell)
    );
    zoom_control u_zoom (
        .clk(clk), .reset(reset), .zoom_switch(sw[14]), .mouse_event(mouse_event), .mouse_z(mouse_z),
        .zoomed_out(zoomed_out), .overview(overview)
    );
    balloon_control u_balloons (
        .clk(clk), .reset(reset), .game_state(game_state), .pop_req(pop_req), .pop_cell(pop_cell),
        .build_grid(build_grid), .intact_mask(intact_mask), .gameplay_ready(gameplay_ready),
        .pop_pending(pop_pending), .pop_valid(pop_valid), .pop_mask(pop_mask)
    );
    vehicle_builder #(
        .FRAME_LIMIT(FRAME_LIMIT), .PIG_LIMIT(PIG_LIMIT), .WHEEL_LIMIT(WHEEL_LIMIT),
        .ENGINE_LIMIT(ENGINE_LIMIT), .BALLOON_LIMIT(BALLOON_LIMIT),
        .ROCKET_LIMIT(ROCKET_LIMIT), .FAN_LIMIT(FAN_LIMIT), .FEEDBACK_CYCLES(FEEDBACK_CYCLES)
    ) u_builder (
        .clk(clk), .reset(reset), .game_state(game_state), .level_index(level_index), .run_init(run_init), .init_ready(init_ready[0]),
        .edit_valid(edit_valid), .edit_op(edit_op), .edit_cell(edit_cell), .edit_source(edit_source), .edit_part(edit_part), .edit_facing_left(edit_facing_left),
        .edit_facing_down(edit_facing_down),
        .build_facing_left(build_facing_left), .build_facing_down(build_facing_down), .engine_balance(engine_balance),
        .fan_balance(fan_balance), .rocket_balance(rocket_balance),
        .rocket_count(rocket_count), .fan_count(fan_count), .rockets_left(rockets_left), .fans_left(fans_left),
        // Balloon pops, TNT and hard terrain impacts share the one damage
        // handshake. vehicle_builder protects the pig cell and its frame.
        .damage_valid(pop_valid || tnt_damage_valid || impact_damage_valid), .damage_ready(damage_ready),
        .damage_mask((pop_valid ? pop_mask : 9'd0) |
                     (tnt_damage_valid ? tnt_damage_mask : 9'd0) |
                     (impact_damage_valid ? impact_damage_mask : 9'd0)),
        .damage_frame_mask((tnt_damage_valid ? tnt_frame_mask : 9'd0) |
                           (impact_damage_valid ? impact_damage_frame_mask : 9'd0)),
        .build_grid(build_grid), .build_frames(build_frames),
        .intact_mask(intact_mask), .frame_intact_mask(frame_intact_mask), .build_valid(build_valid),
        .build_error(build_error), .pig_alive(pig_alive), .wheel_count(wheel_count), .wheels_down(wheels_down), .wheels_up(wheels_up),
        .feedback_code(feedback_code), .feedback_cell(feedback_cell),
        .engine_count(engine_count), .balloon_count(balloon_count), .mass_units(mass_units),
        .frames_left(frames_left), .pigs_left(pigs_left), .wheels_left(wheels_left),
        .engines_left(engines_left), .balloons_left(balloons_left)
    );
    // Geometry stays fixed throughout a run.
    level_data u_level (
        .level_index(level_index), .par_time(par_time), .spawn_x(level_spawn_x), .spawn_y(level_spawn_y), .terrain_count(terrain_count),
        .terrain_rects(terrain_rects), .goal_rect(goal_rect), .tnt_count(tnt_count),
        .tnt_positions(tnt_positions), .hazard_count(hazard_count), .hazard_rects(hazard_rects),
        .map_level(map_level), .map_id(map_id), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .star_box_x(star_box_x), .star_box_y(star_box_y)
    );
    game_controller #(.ENABLE_START_SCREEN(ENABLE_START_SCREEN)) u_game (
        .home_req(ui_home_req), .clk(clk), .reset(reset), .launch_req(start_press || ui_launch), .retry_req(start_press || ui_launch), .edit_req(edit_press || ui_edit),
        .end_try_req(ui_end_try),
        .guide_open_req(ui_guide_open || (game_state==`LP_BUILD && edit_press)), .guide_close_req(ui_guide_close || edit_press),
        .guide_return_state(guide_return_state), .level_next_req(1'b0), .level_open_req(level_open_req),
        .level_close_req(level_close_req), .level_select_req(level_select_req), .selected_level(selected_level),
        .level_index(level_index), .fail_reason(fail_reason), .run_seconds(run_seconds),
        .build_valid(build_valid && !edit_valid), .pig_alive(pig_alive),
        .init_ready(init_ready), .physics_tick(physics_tick), .world_valid(world_valid), .world_ready(world_ready),
        .gameplay_pending(pop_pending), .gameplay_ready(gameplay_ready),
        .goal_hit(goal_hit), .hazard_hit(hazard_hit), .out_of_bounds(out_of_bounds), .star_box_hit(star_box_hit), .star_box_collected(star_box_collected),
        .enable_start_screen(enable_start_screen),
        .start_screen_active(start_screen_active),
        .par_time(par_time), .game_state(game_state),
        .run_init(run_init), .step_start(step_start), .update_release(update_release),
        .launch_event(launch_event), .success_event(success_event), .failure_event(failure_event)
    );
    explosion_fx u_explosions (
        .clk(clk), .reset(reset), .run_init(run_init), .physics_tick(physics_tick),
        .tnt_intact(tnt_intact), .blast_phase(blast_phase)
    );
    wire [3:0] active_down_fans =
        (intact_mask[0] && build_grid[2:0]   == `LP_PART_FAN && build_facing_down[0] && ui_active_fans[0]) +
        (intact_mask[1] && build_grid[5:3]   == `LP_PART_FAN && build_facing_down[1] && ui_active_fans[1]) +
        (intact_mask[2] && build_grid[8:6]   == `LP_PART_FAN && build_facing_down[2] && ui_active_fans[2]) +
        (intact_mask[3] && build_grid[11:9]  == `LP_PART_FAN && build_facing_down[3] && ui_active_fans[3]) +
        (intact_mask[4] && build_grid[14:12] == `LP_PART_FAN && build_facing_down[4] && ui_active_fans[4]) +
        (intact_mask[5] && build_grid[17:15] == `LP_PART_FAN && build_facing_down[5] && ui_active_fans[5]) +
        (intact_mask[6] && build_grid[20:18] == `LP_PART_FAN && build_facing_down[6] && ui_active_fans[6]) +
        (intact_mask[7] && build_grid[23:21] == `LP_PART_FAN && build_facing_down[7] && ui_active_fans[7]) +
        (intact_mask[8] && build_grid[26:24] == `LP_PART_FAN && build_facing_down[8] && ui_active_fans[8]);

    wire [8:0] fan_lift_mask = {
        intact_mask[8] && build_grid[26:24] == `LP_PART_FAN && build_facing_down[8],
        intact_mask[7] && build_grid[23:21] == `LP_PART_FAN && build_facing_down[7],
        intact_mask[6] && build_grid[20:18] == `LP_PART_FAN && build_facing_down[6],
        intact_mask[5] && build_grid[17:15] == `LP_PART_FAN && build_facing_down[5],
        intact_mask[4] && build_grid[14:12] == `LP_PART_FAN && build_facing_down[4],
        intact_mask[3] && build_grid[11:9]  == `LP_PART_FAN && build_facing_down[3],
        intact_mask[2] && build_grid[8:6]   == `LP_PART_FAN && build_facing_down[2],
        intact_mask[1] && build_grid[5:3]   == `LP_PART_FAN && build_facing_down[1],
        intact_mask[0] && build_grid[2:0]   == `LP_PART_FAN && build_facing_down[0]
    };
    wire [8:0] fan_horiz_mask = {
        build_grid[26:24] == `LP_PART_FAN && !build_facing_down[8],
        build_grid[23:21] == `LP_PART_FAN && !build_facing_down[7],
        build_grid[20:18] == `LP_PART_FAN && !build_facing_down[6],
        build_grid[17:15] == `LP_PART_FAN && !build_facing_down[5],
        build_grid[14:12] == `LP_PART_FAN && !build_facing_down[4],
        build_grid[11:9]  == `LP_PART_FAN && !build_facing_down[3],
        build_grid[8:6]   == `LP_PART_FAN && !build_facing_down[2],
        build_grid[5:3]   == `LP_PART_FAN && !build_facing_down[1],
        build_grid[2:0]   == `LP_PART_FAN && !build_facing_down[0]
    };
    wire [8:0] rocket_vertical_mask = {
        intact_mask[8] && build_grid[26:24] == `LP_PART_BOOSTER && build_facing_down[8],
        intact_mask[7] && build_grid[23:21] == `LP_PART_BOOSTER && build_facing_down[7],
        intact_mask[6] && build_grid[20:18] == `LP_PART_BOOSTER && build_facing_down[6],
        intact_mask[5] && build_grid[17:15] == `LP_PART_BOOSTER && build_facing_down[5],
        intact_mask[4] && build_grid[14:12] == `LP_PART_BOOSTER && build_facing_down[4],
        intact_mask[3] && build_grid[11:9]  == `LP_PART_BOOSTER && build_facing_down[3],
        intact_mask[2] && build_grid[8:6]   == `LP_PART_BOOSTER && build_facing_down[2],
        intact_mask[1] && build_grid[5:3]   == `LP_PART_BOOSTER && build_facing_down[1],
        intact_mask[0] && build_grid[2:0]   == `LP_PART_BOOSTER && build_facing_down[0]
    };
    // Vertical rockets point up (facing_left=0) or down (facing_left=1).
    // The balance is signed: negative pushes up, positive pushes down.
    wire [8:0] rocket_down_mask = rocket_vertical_mask & build_facing_left;
    wire [8:0] rocket_up_mask = rocket_vertical_mask & ~build_facing_left;
    wire [3:0] active_up_rockets =
        rocket_up_mask[0] + rocket_up_mask[1] + rocket_up_mask[2] +
        rocket_up_mask[3] + rocket_up_mask[4] + rocket_up_mask[5] +
        rocket_up_mask[6] + rocket_up_mask[7] + rocket_up_mask[8];
    wire [3:0] active_down_rockets =
        rocket_down_mask[0] + rocket_down_mask[1] + rocket_down_mask[2] +
        rocket_down_mask[3] + rocket_down_mask[4] + rocket_down_mask[5] +
        rocket_down_mask[6] + rocket_down_mask[7] + rocket_down_mask[8];
    wire signed [4:0] rocket_vertical_balance =
        $signed({1'b0, active_down_rockets}) - $signed({1'b0, active_up_rockets}); wire [8:0] active_horiz_fans = intact_mask & fan_horiz_mask & ui_active_fans; wire [8:0] active_right_fans = active_horiz_fans & ~build_facing_left; wire [8:0] active_left_fans = active_horiz_fans & build_facing_left; wire [3:0] active_right_fan_count = active_right_fans[0]+active_right_fans[1]+active_right_fans[2]+active_right_fans[3]+active_right_fans[4]+active_right_fans[5]+active_right_fans[6]+active_right_fans[7]+active_right_fans[8]; wire [3:0] active_left_fan_count = active_left_fans[0]+active_left_fans[1]+active_left_fans[2]+active_left_fans[3]+active_left_fans[4]+active_left_fans[5]+active_left_fans[6]+active_left_fans[7]+active_left_fans[8]; wire signed [4:0] active_fan_balance = $signed({1'b0, active_right_fan_count}) - $signed({1'b0, active_left_fan_count});
    physics_engine #(.ENGINE_FORCE(ENGINE_FORCE), .ROCKET_FORCE_SHIFT(ROCKET_FORCE_SHIFT), .WHEEL_TORQUE_SHIFT(WHEEL_TORQUE_SHIFT)) u_physics (
        .support_endpoint_y_valid(support_span_valid),
        .support_left_y_q2(support_left_y_q2),.support_right_y_q2(support_right_y_q2),
        .support_wheel_count(support_wheel_count),
        .proposed_pivot_dx_q8(pivot_dx_q8),.proposed_pivot_dy_q8(pivot_dy_q8),
        .ground_slope_valid(ground_slope_valid),.support_span_valid(support_span_valid),
        .support_left_q2(support_left_q2),.support_right_q2(support_right_q2),.support_y_q2(support_y_q2),
        .moments_enabled(body_moments_enabled),.build_grid(build_grid),.build_frames(build_frames),
        .intact_mask(intact_mask),.frame_intact_mask(frame_intact_mask),
        .build_facing_left(build_facing_left),.rocket_vertical_mask(rocket_vertical_mask),
        .fan_balance(active_fan_balance), .rocket_balance(rocket_balance), .rocket_vertical_balance(rocket_vertical_balance), .rocket_count(rocket_count),

        .fan_enabled(ui_fan_on), .rocket_req(ui_rocket_req), .rocket_ready(rocket_ready), .rocket_active(rocket_active),
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready[1]),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(wheel_count), .wheels_down(wheels_down), .wheels_up(wheels_up), .tip_dir(tip_dir), .support_unstable(support_unstable),
        .engine_count(drive_engines), .balloon_count(balloon_count),
        .mass_units(mass_units), .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(1'b0), .boost_req(boost_req), .boost_active(boost_active),
        .tnt_knockback_valid(tnt_knockback_valid), .tnt_knockback_x(tnt_knockback_x), .tnt_knockback_y(tnt_knockback_y),
        // Future lift-fan placement supplies these; no item/sprite exists yet.
        .live_lift_fan_count(active_down_fans), .fan_lift_mask(fan_lift_mask), .fan_active_mask(ui_active_fans),
        .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .response_valid(response_valid),
        .response_ready(response_ready), .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded), .ground_slope(ground_slope),
        .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt), .corrected_tilt(corrected_tilt), .vehicle_tilt(vehicle_tilt),
        .movement_committed(movement_committed), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y),
        .display_x(display_x), .display_y(display_y)
    );
    collision_engine #(.ROTATION_ONLY(1)) u_collision (
        .support_left_y_q2(support_left_y_q2),.support_right_y_q2(support_right_y_q2),
        .support_wheel_count(support_wheel_count),
        .pivot_dx_q8(pivot_dx_q8),.pivot_dy_q8(pivot_dy_q8),
        .ground_slope_valid(ground_slope_valid),.support_span_valid(support_span_valid),
        .support_left_q2(support_left_q2),.support_right_q2(support_right_q2),.support_y_q2(support_y_q2),
        .collision_mask(intact_mask | frame_intact_mask),
        .cg_enabled(1'b1), .build_grid(build_grid), .part_intact_mask(intact_mask),
        .frame_intact_mask(frame_intact_mask), .support_unstable(support_unstable),
        .clk(clk), .reset(reset || run_init || game_state != `LP_RUN), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .terrain_count(terrain_count), .terrain_rects(terrain_rects),
        .map_level(map_level), .rotation_enabled(1'b1), .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt), .world_width(world_width), .world_height(world_height),
        .query_x(collision_query_x), .query_y(collision_query_y), .query_class(collision_query_class),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .ground_slope(ground_slope), .corrected_tilt(corrected_tilt), .tip_dir(tip_dir),
         .impact_valid(collision_impact_valid), .impact_flags(collision_impact_flags)
    );
    // Finish TNT damage before checking the pig and goal for this movement.
    // Physics holds its committed pose until the world result is accepted.
    tnt_controller u_tnt (
        .clk(clk), .reset(reset), .run_init(run_init), .game_state(game_state), .init_ready(),
        .movement_committed(movement_committed), .previous_x(previous_x), .previous_y(previous_y), .previous_tilt(previous_tilt),
        .vehicle_x(vehicle_x), .vehicle_y(vehicle_y), .vehicle_tilt(vehicle_tilt), .tnt_count(tnt_count), .tnt_positions(tnt_positions),
        .build_grid(build_grid), .build_frames(build_frames), .intact_mask(intact_mask),
        .frame_intact_mask(frame_intact_mask), .tnt_intact(tnt_intact),
        .damage_valid(tnt_damage_valid), .damage_ready(damage_ready),
        .damage_mask(tnt_damage_mask), .damage_frame_mask(tnt_frame_mask),
        .knockback_valid(tnt_knockback_valid), .knockback_x(tnt_knockback_x), .knockback_y(tnt_knockback_y),
        .explosion_event(explosion_sound_event), .damage_complete(tnt_complete)
    );
    world_outcomes u_world (
        .clk(clk), .reset(reset), .run_init(run_init), .game_state(game_state), .init_ready(init_ready[2]),
        .movement_committed(tnt_complete), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y), .vehicle_tilt(vehicle_tilt),
        .build_grid(build_grid), .intact_mask(intact_mask), .goal_rect(goal_rect),
        .map_level(map_level), .world_width(world_width), .world_height(world_height),
        .flag_x(flag_x), .flag_y(flag_y), .star_box_x(star_box_x), .star_box_y(star_box_y),
        .hazard_count(hazard_count), .hazard_rects(hazard_rects), .world_valid(world_valid),
        .world_ready(world_ready), .goal_hit(goal_hit), .hazard_hit(hazard_hit), .out_of_bounds(out_of_bounds), .star_box_hit(star_box_hit)
    );

    // Base snapshot width is adjusted for the current three TNT slots and
    // carries the filtered display pose for both the vehicle and follow-camera.
    localparam SNAPSHOT_WIDTH = 249 + 3*(`LP_MAX_TNT-4) +
                                4*(`LP_COORD_BITS-16) + (`LP_TILT_BITS-4) +
                                2*`LP_COORD_BITS + 9 + 6;
    wire [SNAPSHOT_WIDTH-1:0] snapshot_in = {start_screen_active, fan_available, ui_fan_on, star_box_collected, rocket_available, rocket_ready, vehicle_tilt, audio_muted, run_page, selected_left, inventory_page, build_facing_left, rockets_left, fans_left, master_volume, diary_page, guide_return_state, death_phase, death_x, death_y, launch_flash, (boost_active || rocket_active), drag_from_grid, drag_source, drag_contents,
                              game_state, build_grid, intact_mask, frame_intact_mask, build_valid, build_error,
                              display_x, display_y, engine_enabled, frames_left, pigs_left, wheels_left,
                              engines_left, balloons_left, cursor_x, cursor_y, selected_part, drag_active,
                              feedback_code, feedback_cell, level_index, fail_reason, tnt_intact,
                              build_frames, run_seconds, blast_phase, scatter_mask, scatter_x, scatter_y, scatter_phase};
    wire [SNAPSHOT_WIDTH-1:0] snapshot_out;
    wire draw_audio_muted;
    wire draw_start_screen_active;
    wire draw_fan_available, draw_fan_on, draw_rocket_available, draw_rocket_ready;

    wire signed [`LP_TILT_BITS-1:0] draw_tilt;
    wire [1:0] draw_diary_page, draw_death_phase;
    wire [2:0] draw_guide_return;
    wire signed [`LP_COORD_BITS-1:0] draw_death_x, draw_death_y;
    wire draw_launch_flash;
    wire draw_star_box_collected;
    wire draw_boost_active;
    wire draw_drag_from_grid;
    wire [3:0] draw_drag_source;
    wire [2:0] draw_drag_contents;
    wire [2:0] draw_state;
    wire [26:0] draw_grid;
    wire [8:0] draw_intact, draw_frames;
    wire draw_valid, draw_engine, draw_drag_active;
    wire [3:0] draw_error;
    wire [2:0] draw_feedback_code;
    wire [3:0] draw_feedback_cell;
    wire [3:0] draw_frames_left, draw_pigs_left, draw_wheels_left, draw_engines_left, draw_balloons_left;
    wire [6:0] draw_cursor_x, draw_cursor_y;
    wire [2:0] draw_selected_part;
    wire signed [`LP_COORD_BITS-1:0] draw_x, draw_y;
    wire [`LP_LEVEL_BITS-1:0] draw_level;
    wire [8:0] draw_saved_frames;
    wire [7:0] draw_seconds;
    wire [2*`LP_MAX_TNT-1:0] draw_blast;
    wire [8:0] draw_scatter_mask;
    wire signed [`LP_COORD_BITS-1:0] draw_scatter_x, draw_scatter_y;
    wire [5:0] draw_scatter_phase;
    wire [1:0] draw_fail_reason;
    wire [`LP_MAX_TNT-1:0] draw_tnt_intact;
    wire signed [19:0] draw_spawn_x, draw_spawn_y;
    wire [2:0] draw_terrain_count, draw_tnt_count;
    wire [127:0] draw_terrain_rects;
    wire [31:0] draw_goal_rect;
    wire [`LP_TNT_BITS-1:0] draw_tnt_positions;
    wire [1:0] draw_hazard_count;
    wire [`LP_HAZARD_BITS-1:0] draw_hazard_rects;
    wire [12:0] left_pixel_index, right_pixel_index;
    // JA is mounted upside down: reverse all 96 x 64 pixels to rotate it 180 degrees.
    // Reciprocal multiplication eliminates combinational / 96 and % 96 divider trees:
    // ({12'd0, pixel_index} * 25'd2731) >> 18 == pixel_index / 96 for all 0 <= pixel_index < 6144.
    wire [5:0] raw_left_y = ({12'd0, left_pixel_index} * 25'd2731) >> 18;
    wire [6:0] raw_left_x = left_pixel_index - (raw_left_y << 6) - (raw_left_y << 5);
    wire [6:0] left_x = 7'd95 - raw_left_x;
    wire [5:0] left_y = 6'd63 - raw_left_y;

    wire [5:0] raw_right_y = ({12'd0, right_pixel_index} * 25'd2731) >> 18;
    wire [6:0] raw_right_x = right_pixel_index - (raw_right_y << 6) - (raw_right_y << 5);
    wire [6:0] right_x = raw_right_x;
    wire [5:0] right_y = raw_right_y;
    wire [6:0] map_x = show_map ? left_x : right_x;
    wire [5:0] map_y = show_map ? left_y : right_y;
    wire [15:0] left_pixel_data, right_pixel_data, base_left_pixel_data;
    assign {draw_start_screen_active, draw_fan_available, draw_fan_on, draw_star_box_collected, draw_rocket_available, draw_rocket_ready, draw_tilt, draw_audio_muted, draw_run_page, draw_selected_left, draw_inventory_page, draw_facing_left, draw_rockets_left, draw_fans_left, draw_master_volume, draw_diary_page, draw_guide_return, draw_death_phase, draw_death_x, draw_death_y, draw_launch_flash, draw_boost_active, draw_drag_from_grid, draw_drag_source, draw_drag_contents,
            draw_state, draw_grid, draw_intact, draw_frames, draw_valid, draw_error, draw_x, draw_y, draw_engine,
            draw_frames_left, draw_pigs_left, draw_wheels_left, draw_engines_left, draw_balloons_left,
            draw_cursor_x, draw_cursor_y, draw_selected_part, draw_drag_active,
            draw_feedback_code, draw_feedback_cell, draw_level, draw_fail_reason, draw_tnt_intact,
            draw_saved_frames, draw_seconds, draw_blast, draw_scatter_mask, draw_scatter_x, draw_scatter_y, draw_scatter_phase} = snapshot_out;

    display_snapshot #(.WIDTH(SNAPSHOT_WIDTH)) u_snapshot (
        .game_clk(clk), .game_reset(reset), .display_clk(oled_clk), .display_reset(oled_reset),
        .frame_begin(left_frame), .game_data(snapshot_in), .display_data(snapshot_out)
    );
    wire in_diary_walkthrough = (draw_state == `LP_GUIDE) && (draw_diary_page != 2'd3);
    // Engine pistons step once every eight frames while running with SW0 on; boost doubles the rate.
    reg [3:0] engine_frames;
    // Wheels use a faster independent phase so their spokes do not appear to
    // freeze while the vehicle is travelling between physics updates.
    reg [2:0] wheel_frames;
    wire vehicle_moving = (corrected_x[19:8] != previous_x[19:8]) || (!grounded && (corrected_y[19:8] != previous_y[19:8]));
    reg moving_meta, moving_sync;
    always @(posedge oled_clk) begin
        if (oled_reset) begin
            engine_frames <= 0;
            wheel_frames <= 0;
            moving_meta <= 0;
            moving_sync <= 0;
        end else begin
            moving_meta <= vehicle_moving;
            moving_sync <= moving_meta;
            if (left_frame && (draw_state == `LP_RUN || in_diary_walkthrough)) begin
                if (draw_engine || draw_fan_on || draw_boost_active || in_diary_walkthrough)
                    engine_frames <= engine_frames + (draw_boost_active ? 4'd2 : 4'd1);
                if (moving_sync || in_diary_walkthrough)
                    wheel_frames <= wheel_frames + 1'b1;
            end
        end
    end
    wire anim_phase = engine_frames[3];
    wire wheel_anim_phase = wheel_frames[1];
    // The map zoom and SW12 free look also change only between complete frames.
    reg zoom_meta_display, zoom_sync_display, draw_zoomed_out;
    reg overview_meta_display, overview_sync_display, draw_overview;
    reg look_meta_display, look_sync_display, draw_free_look;
    reg [8:0] facing_down_meta, facing_down_sync, draw_facing_down; reg [8:0] active_fans_meta, active_fans_sync, draw_ui_active_fans;
    reg selected_down_meta, selected_down_sync, draw_selected_down;
    reg inv_eng_meta, inv_eng_sync, draw_inv_engine_left;
    reg inv_fan_l_meta, inv_fan_l_sync, draw_inv_fan_left;
    reg inv_fan_d_meta, inv_fan_d_sync, draw_inv_fan_down;
    reg inv_rkt_meta, inv_rkt_sync, draw_inv_rocket_left;
    reg inv_rkt_d_meta, inv_rkt_d_sync, draw_inv_rocket_down;

    always @(posedge oled_clk) begin
        if (oled_reset) begin
            zoom_meta_display <= 0; zoom_sync_display <= 0; draw_zoomed_out <= 0;
            overview_meta_display <= 0; overview_sync_display <= 0; draw_overview <= 0;
            look_meta_display <= 0; look_sync_display <= 0; draw_free_look <= 0;
            facing_down_meta <= 0; facing_down_sync <= 0; draw_facing_down <= 0; active_fans_meta <= 0; active_fans_sync <= 0; draw_ui_active_fans <= 0;
            selected_down_meta <= 0; selected_down_sync <= 0; draw_selected_down <= 0;
            inv_eng_meta <= 0; inv_eng_sync <= 0; draw_inv_engine_left <= 0;
            inv_fan_l_meta <= 0; inv_fan_l_sync <= 0; draw_inv_fan_left <= 0;
            inv_fan_d_meta <= 0; inv_fan_d_sync <= 0; draw_inv_fan_down <= 0;
            inv_rkt_meta <= 0; inv_rkt_sync <= 0; draw_inv_rocket_left <= 0;
            inv_rkt_d_meta <= 0; inv_rkt_d_sync <= 0; draw_inv_rocket_down <= 0;
        end else begin
            zoom_meta_display <= zoomed_out; zoom_sync_display <= zoom_meta_display;
            overview_meta_display <= overview; overview_sync_display <= overview_meta_display;
            look_meta_display <= sw[13]; look_sync_display <= look_meta_display;
            facing_down_meta <= build_facing_down; facing_down_sync <= facing_down_meta; active_fans_meta <= ui_active_fans; active_fans_sync <= active_fans_meta;
            selected_down_meta <= selected_down; selected_down_sync <= selected_down_meta;
            inv_eng_meta <= engine_facing_left; inv_eng_sync <= inv_eng_meta;
            inv_fan_l_meta <= fan_facing_left; inv_fan_l_sync <= inv_fan_l_meta;
            inv_fan_d_meta <= fan_facing_down; inv_fan_d_sync <= inv_fan_d_meta;
            inv_rkt_meta <= rocket_facing_left; inv_rkt_sync <= inv_rkt_meta;
            inv_rkt_d_meta <= rocket_facing_down; inv_rkt_d_sync <= inv_rkt_d_meta;
            if (left_frame) begin
                draw_zoomed_out <= zoom_sync_display;
                draw_overview <= overview_sync_display;
                draw_free_look <= look_sync_display;
                draw_facing_down <= facing_down_sync; draw_ui_active_fans <= active_fans_sync;
                draw_selected_down <= selected_down_sync;
                draw_inv_engine_left <= inv_eng_sync;
                draw_inv_fan_left <= inv_fan_l_sync;
                draw_inv_fan_down <= inv_fan_d_sync;
                draw_inv_rocket_left <= inv_rkt_sync;
                draw_inv_rocket_down <= inv_rkt_d_sync;
            end
        end
    end
    // A second copy of the level table, indexed by the snapshot, keeps the map in step with the drawn state.
    wire draw_map_level, draw_map_id;
    wire [9:0] draw_world_width, draw_world_height, draw_flag_x, draw_flag_y;
    level_data u_draw_level (
        .level_index(draw_level), .spawn_x(draw_spawn_x), .spawn_y(draw_spawn_y),
        .terrain_count(draw_terrain_count), .terrain_rects(draw_terrain_rects), .goal_rect(draw_goal_rect),
        .tnt_count(draw_tnt_count), .tnt_positions(draw_tnt_positions),
        .hazard_count(draw_hazard_count), .hazard_rects(draw_hazard_rects),
        .map_level(draw_map_level), .map_id(draw_map_id), .world_width(draw_world_width), .world_height(draw_world_height),
        .flag_x(draw_flag_x), .flag_y(draw_flag_y), .star_box_x(draw_star_box_x), .star_box_y(draw_star_box_y)
    );
    // Scrolling horizontal offset for Start Screen clouds
    reg [6:0] cloud_scroll_fg;
    reg [6:0] cloud_scroll_bg;
    reg [1:0] cloud_div;
    always @(posedge oled_clk) begin
        if (oled_reset) begin
            cloud_scroll_fg <= 7'd0;
            cloud_scroll_bg <= 7'd0;
            cloud_div <= 2'd0;
        end else if (left_frame && draw_start_screen_active) begin
            cloud_div <= cloud_div + 1'b1;
            // Foreground clouds drift lively: 1 pixel every 2 frames (~30 px/s)
            if (cloud_div[0]) begin
                cloud_scroll_fg <= (cloud_scroll_fg >= 7'd95) ? 7'd0 : (cloud_scroll_fg + 7'd1);
            end
            // Background clouds drift distant/slow: 1 pixel every 4 frames (~15 px/s)
            if (cloud_div == 2'd3) begin
                cloud_scroll_bg <= (cloud_scroll_bg >= 7'd95) ? 7'd0 : (cloud_scroll_bg + 7'd1);
            end
        end
    end

    // Independent map selections keep collision on the live level while the
    // display may still hold the previous frame snapshot.
    wire signed [10:0] right_map_x, right_map_y;
    wire signed [10:0] map_draw_x = right_map_x;
    wire signed [10:0] map_draw_y = right_map_y;
    wire [2:0] map_draw_class;
    // The draw port reads on the OLED clock, beside the renderer's own register. level_map's
    // SMOOTH_DRAW (100 MHz neighbour reads) is off: its reads had to finish inside one OLED
    // pixel across the untimed OLED clock boundary, and on the board map pixels flickered.
    level_map u_level_map (
        .map_id(draw_map_id), .draw_clk(oled_clk), .draw_x(map_draw_x), .draw_y(map_draw_y), .draw_class(map_draw_class),
        .query_clk(clk), .query_map_id(map_id),
        .query_x(collision_query_x), .query_y(collision_query_y),
        .query_class(), .query_solid(collision_query_solid)
    );
    wire [8:0] draw_active_fans = {
        draw_intact[8] && draw_grid[26:24] == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[8] : draw_fan_on),
        draw_intact[7] && draw_grid[23:21] == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[7] : draw_fan_on),
        draw_intact[6] && draw_grid[20:18] == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[6] : draw_fan_on),
        draw_intact[5] && draw_grid[17:15] == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[5] : draw_fan_on),
        draw_intact[4] && draw_grid[14:12] == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[4] : draw_fan_on),
        draw_intact[3] && draw_grid[11:9]  == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[3] : draw_fan_on),
        draw_intact[2] && draw_grid[8:6]   == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[2] : draw_fan_on),
        draw_intact[1] && draw_grid[5:3]   == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[1] : draw_fan_on),
        draw_intact[0] && draw_grid[2:0]   == `LP_PART_FAN && (draw_ui_active_fans != 0 ? draw_ui_active_fans[0] : draw_fan_on)
    };
    left_renderer #(
        .USE_PIXEL_INDEX(0),
        .ENABLE_COMPACT_RUN_SPRITES(0)
    ) u_left_renderer (
        .pixel_index(13'd0), .in_x(left_x), .in_y(left_y), .game_state(draw_state), .build_grid(draw_grid),
        .build_frames(draw_saved_frames), .build_facing_left(draw_facing_left),
        .build_facing_down(draw_facing_down),
        .selected_left(draw_selected_left), .selected_down(draw_selected_down),
        .inv_engine_left(draw_inv_engine_left), .inv_fan_left(draw_inv_fan_left),
        .inv_fan_down(draw_inv_fan_down), .inv_rocket_left(draw_inv_rocket_left), .inv_rocket_down(draw_inv_rocket_down),
        .inventory_page(draw_inventory_page),
        .rockets_left(draw_rockets_left), .fans_left(draw_fans_left), .intact_mask(draw_intact), .frame_intact_mask(draw_frames),
        .build_valid(draw_valid), .build_error(draw_error), .engine_enabled(draw_engine), .wheel_moving(moving_sync), .boost_active(draw_boost_active),
        .active_fans(draw_active_fans), .rocket_ready(draw_rocket_ready),
        .feedback_code(draw_feedback_code), .feedback_cell(draw_feedback_cell),
        .frames_left(draw_frames_left), .pigs_left(draw_pigs_left), .wheels_left(draw_wheels_left),
        .engines_left(draw_engines_left), .balloons_left(draw_balloons_left), .selected_part(draw_selected_part),
        .drag_active(draw_drag_active),
        .drag_from_grid(draw_drag_from_grid), .drag_source(draw_drag_source), .drag_contents(draw_drag_contents),
        .cursor_x(draw_cursor_x), .cursor_y(draw_cursor_y), .cursor_visible(1'b1),
        .level_index(draw_level), .fail_reason(draw_fail_reason), .run_seconds(draw_seconds), .star_box_collected(draw_star_box_collected),
        .anim_phase(anim_phase), .pixel_data(base_left_pixel_data)
    );
    ui_renderer u_ui_renderer (
        .x(left_x), .y(left_y), .base_pixel(base_left_pixel_data), .game_state(draw_state),
        .feedback_code(draw_feedback_code),
        .start_screen_active(draw_start_screen_active),
        .diary_page(draw_diary_page),
        .audio_muted(draw_audio_muted),
        .master_volume(draw_master_volume),
        .level_index(draw_level),
        .build_valid(draw_valid),
        .cursor_x(draw_cursor_x), .cursor_y(draw_cursor_y),
        .cloud_scroll_fg(cloud_scroll_fg),
        .cloud_scroll_bg(cloud_scroll_bg),
        .pixel_data(left_pixel_data)
    );
    // Dual-OLED Diary Walkthrough: pan the Right OLED camera to the selected checkpoint
    // and pose the recommended demo vehicle on the live cave terrain.
    wire signed [19:0] diary_pose_x = (draw_map_id == 1'b0) ?
        ((draw_diary_page == 2'd0) ? {12'd240, 8'd0} : (draw_diary_page == 2'd1) ? {12'd196, 8'd0} : {12'd564, 8'd0}) :
        ((draw_diary_page == 2'd0) ? {12'd100, 8'd0} : (draw_diary_page == 2'd1) ? {12'd512, 8'd0} : {12'd732, 8'd0});
    wire signed [19:0] diary_pose_y = (draw_map_id == 1'b0) ?
        ((draw_diary_page == 2'd0) ? {12'd72,  8'd0} : (draw_diary_page == 2'd1) ? {12'd366, 8'd0} : {12'd462, 8'd0}) :
        ((draw_diary_page == 2'd0) ? {12'd162, 8'd0} : (draw_diary_page == 2'd1) ? {12'd87,  8'd0} : {12'd40,  8'd0});
    wire [26:0] diary_grid = (draw_map_id == 1'b0) ?
        {`LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_PIG, `LP_PART_ENGINE, `LP_PART_EMPTY,   `LP_PART_BOOSTER, `LP_PART_EMPTY} :
        {`LP_PART_WHEEL, `LP_PART_EMPTY, `LP_PART_WHEEL, `LP_PART_FAN,   `LP_PART_PIG, `LP_PART_ENGINE, `LP_PART_BALLOON, `LP_PART_BOOSTER, `LP_PART_BALLOON};
    wire [8:0] diary_frames = (draw_map_id == 1'b0) ? 9'b000_111_000 : 9'b000_011_000;
    wire [8:0] diary_intact = (draw_map_id == 1'b0) ? 9'b101_011_010 :
                              ((draw_diary_page == 2'd0) ? 9'b101_111_111 : 9'b101_111_110);
    wire [8:0] diary_active_fans = (draw_map_id == 1'b1) ? 9'b000_100_000 : 9'd0;

    right_renderer #(
        .USE_PIXEL_INDEX(0)
    ) u_right_renderer (
        .clk(oled_clk), .zoomed_out(draw_zoomed_out), .overview(draw_overview),
        .free_look(draw_free_look), .cursor_x(draw_cursor_x), .cursor_y(draw_cursor_y),
        .pixel_index(13'd0), .in_x(map_x), .in_y(map_y),
        .game_state(in_diary_walkthrough ? `LP_RUN : ((draw_state==`LP_LEVEL_SELECT || draw_state==`LP_SETTINGS) ? `LP_BUILD : (draw_state==`LP_GUIDE ? draw_guide_return : draw_state))),
        .build_grid(in_diary_walkthrough ? diary_grid : draw_grid),
        .build_facing_left(in_diary_walkthrough ? 9'd0 : draw_facing_left),
        .build_facing_down(in_diary_walkthrough ? ((draw_map_id == 1'b0) ? 9'b000_000_010 : 9'd0) : draw_facing_down),
        .engine_enabled(in_diary_walkthrough ? 1'b1 : draw_engine),
        .active_fans(in_diary_walkthrough ? diary_active_fans : draw_active_fans),
        .intact_mask(in_diary_walkthrough ? diary_intact : draw_intact),
        .frame_intact_mask(in_diary_walkthrough ? diary_frames : draw_frames),
        // Follow the filtered pose for both the vehicle and camera. This keeps
        // the wheels attached to the moving ground instead of making the map
        // jump on every raw physics-pixel update.
        .vehicle_x(in_diary_walkthrough ? diary_pose_x : draw_x),
        .vehicle_y(in_diary_walkthrough ? diary_pose_y : draw_y),
        .camera_x(in_diary_walkthrough ? diary_pose_x : draw_x),
        .camera_y(in_diary_walkthrough ? diary_pose_y : draw_y),
        .vehicle_tilt(in_diary_walkthrough ? 6'sd0 : draw_tilt),
        .spawn_x(draw_spawn_x), .spawn_y(draw_spawn_y),
        .terrain_count(draw_terrain_count), .terrain_rects(draw_terrain_rects), .goal_rect(draw_goal_rect),
        .tnt_count(draw_tnt_count), .tnt_positions(draw_tnt_positions), .tnt_intact(draw_tnt_intact),
        .hazard_count(draw_hazard_count), .hazard_rects(draw_hazard_rects), .blast_phase(draw_blast),
        .death_phase(in_diary_walkthrough ? 2'd0 : draw_death_phase), .death_x(draw_death_x), .death_y(draw_death_y),
        .launch_flash(in_diary_walkthrough ? 1'b0 : draw_launch_flash),
        .scatter_mask(in_diary_walkthrough ? 9'd0 : draw_scatter_mask), .scatter_x(draw_scatter_x), .scatter_y(draw_scatter_y), .scatter_phase(draw_scatter_phase),
        .anim_phase(wheel_anim_phase), .map_level(draw_map_level), .map_id(draw_map_id), .world_width(draw_world_width),
        .world_height(draw_world_height), .flag_x(draw_flag_x), .flag_y(draw_flag_y), .star_box_x(draw_star_box_x), .star_box_y(draw_star_box_y),
        .star_box_collected(in_diary_walkthrough ? 1'b0 : draw_star_box_collected), .run_seconds(draw_seconds),
        .map_x(right_map_x), .map_y(right_map_y), .map_class(map_draw_class),
        .pixel_data(right_pixel_data)
    );
    wire right_oled_on = !draw_start_screen_active && (draw_state != `LP_LEVEL_SELECT);
    Oled_Display u_left_oled (
        .clk(oled_clk), .reset(oled_reset), .frame_begin(left_frame), .sending_pixels(), .sample_pixel(left_sample),
        .pixel_index(left_pixel_index), .pixel_data(show_map ? right_pixel_data : left_pixel_data), .cs(JA[0]), .sdin(JA[1]), .sclk(JA[3]),
        .d_cn(JA[4]), .resn(JA[5]), .vccen(JA[6]), .pmoden(JA[7])
    );
    Oled_Display u_right_oled (
        .clk(oled_clk), .reset(oled_reset), .frame_begin(right_frame), .sending_pixels(), .sample_pixel(right_sample),
        .pixel_index(right_pixel_index), .pixel_data(show_map ? 16'd0 : (right_oled_on ? right_pixel_data : 16'h0000)), .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]),
        .d_cn(JB[4]), .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
    assign JA[2] = 1'b0;
    assign JB[2] = 1'b0;
    // Pmod AMP2 on JXADC pins 1-6: AIN, GAIN, NC, shutdown_n, GND, 3.3V.
    assign JXADC[0] = audio_pwm;
    assign JXADC[1] = 1'b1; // High selects the lower, 6 dB gain.
    assign JXADC[2] = 1'b0; // AMP2 pin 3 is not connected.
    assign JXADC[3] = !reset && !audio_muted;

    // Flash unused middle LEDs (led[12:3]) when GO is called (launch_flash)
    // and when the game ends (LP_SUCCESS alternating marquee, LP_FAIL alert blink).
    // Unused switches sw[12:3] are intentionally disconnected.
    reg [3:0] led_anim_tick;
    wire led_anim_active = launch_flash || (game_state == `LP_SUCCESS) || (game_state == `LP_FAIL);
    always @(posedge clk) begin
        if (reset || !led_anim_active)
            led_anim_tick <= 4'd0;
        else if (physics_tick)
            led_anim_tick <= led_anim_tick + 4'd1;
    end

    wire [9:0] unused_leds_flash =
        launch_flash               ? {10{led_anim_tick[1]}} :
        (game_state == `LP_SUCCESS) ? (led_anim_tick[3] ? 10'b1010101010 : 10'b0101010101) :
        (game_state == `LP_FAIL)    ? {10{led_anim_tick[3]}} :
                                     10'd0;

    assign led = {sw[15:13], unused_leds_flash, sw[2:0]};
endmodule









