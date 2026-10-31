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

// SW0 engine, SW1 mute, SW2 reverse, SW15 JA map view; BTNL jump, BTNC launch/retry,
// BTNU edit/next level after success, BTNR reserved and BTND reset.
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
    wire engine_reverse, reverse_switch_enabled, jump_press, boost_req, boost_active;
    wire [1:0] run_page, draw_run_page;
    wire selected_left, edit_facing_left, draw_selected_left;
    wire [1:0] inventory_page, draw_inventory_page;
    wire [8:0] build_facing_left, draw_facing_left;
    wire signed [4:0] engine_balance;
    wire [3:0] drive_engines = engine_balance<0 ? -engine_balance : engine_balance;
    wire [3:0] rocket_count, fan_count, rockets_left, fans_left, draw_rockets_left, draw_fans_left;
    wire ui_fan_on, ui_rocket_req, ui_sound_muted;
    assign engine_reverse = reverse_switch_enabled ^ (engine_balance<0);
    wire engine_switch_changed, ui_engine_on, ui_launch, ui_edit, ui_guide_open, ui_guide_close;
    wire [1:0] diary_page, death_phase, mouse_speed;
    wire [2:0] master_volume, draw_master_volume;
    wire [2:0] guide_return_state;
    wire signed [`LP_COORD_BITS-1:0] death_x, death_y;
    wire launch_flash;
    // SW0 changes the shared engine state; the on-screen DRIVE control can also toggle it.
    assign engine_enabled = ui_engine_on;
    wire [2:0] game_state, init_ready;
    wire run_init, step_start, update_release;
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
    // SW15 chooses the JA view; publish the change only between complete frames.
    always @(posedge clk) begin
        if (reset) begin
            view_meta_game <= 0; view_sync_game <= 0; view_ack_meta <= 0; view_ack_game <= 0;
        end else begin
            view_meta_game <= sw[15]; view_sync_game <= view_meta_game;
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
    wire signed [`LP_COORD_BITS-1:0] spawn_x, spawn_y, vehicle_x, vehicle_y, display_y;
    // Preserve the full Q12.8 spawn throughout movement and display.
    wire signed [19:0] level_spawn_x, level_spawn_y;
    assign spawn_x = level_spawn_x;
    assign spawn_y = level_spawn_y;
    wire [2:0] terrain_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire map_level, map_id;
    wire signed [10:0] collision_query_x, collision_query_y;
    wire collision_query_solid;
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
    // Ignore the first gentle contact at spawn and continuous rolling contact.
    wire collision_sound_event = game_state == `LP_RUN && response_valid && response_ready &&
                                 grounded && !audio_was_grounded && $signed(proposed_vy) >= 16'sd128;
    wire explosion_sound_event;
    always @(posedge clk) begin
        if (reset) begin audio_was_grounded <= 0; previous_game_state <= `LP_BUILD; end
        else begin
            previous_game_state <= game_state;
            if (run_init || game_state != `LP_RUN) audio_was_grounded <= 0;
            else if (response_valid && response_ready) audio_was_grounded <= grounded;
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
        .engine_switch(sw[0]), .mute_switch(sw[1]), .reverse_switch(sw[2]), .start_press(start_press), .edit_press(edit_press),
        .right_press(right_press),
        .engine_switch_changed(engine_switch_changed),
        .audio_muted(switch_audio_muted), .engine_reverse(reverse_switch_enabled), .jump_press(jump_press)
    );
    wire start_screen_active;
    wire ui_level_open_req, btn_level_open_req;
    wire ui_pop_req, mouse_pop_req;
    wire [3:0] mouse_pop_cell;
    wire ui_boost_req, mouse_boost_req, combined_boost_req;

    wire has_intact_engine = (intact_mask[0] && build_grid[2:0] == `LP_PART_ENGINE) ||
                             (intact_mask[1] && build_grid[5:3] == `LP_PART_ENGINE) ||
                             (intact_mask[2] && build_grid[8:6] == `LP_PART_ENGINE) ||
                             (intact_mask[3] && build_grid[11:9] == `LP_PART_ENGINE) ||
                             (intact_mask[4] && build_grid[14:12] == `LP_PART_ENGINE) ||
                             (intact_mask[5] && build_grid[17:15] == `LP_PART_ENGINE) ||
                             (intact_mask[6] && build_grid[20:18] == `LP_PART_ENGINE) ||
                             (intact_mask[7] && build_grid[23:21] == `LP_PART_ENGINE) ||
                             (intact_mask[8] && build_grid[26:24] == `LP_PART_ENGINE);

    wire has_intact_fan = (intact_mask[0] && build_grid[2:0] == `LP_PART_FAN) ||
                          (intact_mask[1] && build_grid[5:3] == `LP_PART_FAN) ||
                          (intact_mask[2] && build_grid[8:6] == `LP_PART_FAN) ||
                          (intact_mask[3] && build_grid[11:9] == `LP_PART_FAN) ||
                          (intact_mask[4] && build_grid[14:12] == `LP_PART_FAN) ||
                          (intact_mask[5] && build_grid[17:15] == `LP_PART_FAN) ||
                          (intact_mask[6] && build_grid[20:18] == `LP_PART_FAN) ||
                          (intact_mask[7] && build_grid[23:21] == `LP_PART_FAN) ||
                          (intact_mask[8] && build_grid[26:24] == `LP_PART_FAN);

    wire has_intact_rocket = (intact_mask[0] && build_grid[2:0] == `LP_PART_BOOSTER) ||
                            (intact_mask[1] && build_grid[5:3] == `LP_PART_BOOSTER) ||
                            (intact_mask[2] && build_grid[8:6] == `LP_PART_BOOSTER) ||
                            (intact_mask[3] && build_grid[11:9] == `LP_PART_BOOSTER) ||
                            (intact_mask[4] && build_grid[14:12] == `LP_PART_BOOSTER) ||
                            (intact_mask[5] && build_grid[17:15] == `LP_PART_BOOSTER) ||
                            (intact_mask[6] && build_grid[20:18] == `LP_PART_BOOSTER) ||
                            (intact_mask[7] && build_grid[23:21] == `LP_PART_BOOSTER) ||
                            (intact_mask[8] && build_grid[26:24] == `LP_PART_BOOSTER);

    wire has_intact_balloon = (intact_mask[0] && build_grid[2:0] == `LP_PART_BALLOON) ||
                              (intact_mask[1] && build_grid[5:3] == `LP_PART_BALLOON) ||
                              (intact_mask[2] && build_grid[8:6] == `LP_PART_BALLOON) ||
                              (intact_mask[3] && build_grid[11:9] == `LP_PART_BALLOON) ||
                              (intact_mask[4] && build_grid[14:12] == `LP_PART_BALLOON) ||
                              (intact_mask[5] && build_grid[17:15] == `LP_PART_BALLOON) ||
                              (intact_mask[6] && build_grid[20:18] == `LP_PART_BALLOON) ||
                              (intact_mask[7] && build_grid[23:21] == `LP_PART_BALLOON) ||
                              (intact_mask[8] && build_grid[26:24] == `LP_PART_BALLOON);

    wire [3:0] first_intact_balloon =
        (intact_mask[0] && build_grid[2:0] == `LP_PART_BALLOON) ? 4'd0 :
        (intact_mask[1] && build_grid[5:3] == `LP_PART_BALLOON) ? 4'd1 :
        (intact_mask[2] && build_grid[8:6] == `LP_PART_BALLOON) ? 4'd2 :
        (intact_mask[3] && build_grid[11:9] == `LP_PART_BALLOON) ? 4'd3 :
        (intact_mask[4] && build_grid[14:12] == `LP_PART_BALLOON) ? 4'd4 :
        (intact_mask[5] && build_grid[17:15] == `LP_PART_BALLOON) ? 4'd5 :
        (intact_mask[6] && build_grid[20:18] == `LP_PART_BALLOON) ? 4'd6 :
        (intact_mask[7] && build_grid[23:21] == `LP_PART_BALLOON) ? 4'd7 :
        (intact_mask[8] && build_grid[26:24] == `LP_PART_BALLOON) ? 4'd8 : 4'd15;

    assign pop_req = mouse_pop_req || ui_pop_req;
    assign pop_cell = mouse_pop_req ? mouse_pop_cell : first_intact_balloon;

    assign level_open_req = btn_level_open_req || ui_level_open_req;
    assign combined_boost_req = ui_boost_req || mouse_boost_req || (game_state == `LP_RUN && right_press);
    assign boost_req = combined_boost_req;

    ui_controller u_ui_control (
        .clk(clk), .reset(reset), .input_enabled(builder_input_enabled), .run_init(run_init),
        .physics_tick(physics_tick), .launch_event(launch_event),
        .start_screen_active(start_screen_active),
        .game_state(game_state),
        .mouse_x(mouse_x), .mouse_y(mouse_y), .mouse_left(mouse_left), .mouse_right(mouse_right),
        .mouse_event(mouse_event), .next_press(start_press), .engine_switch_changed(engine_switch_changed),
        .fan_available(has_intact_fan), .rocket_available(has_intact_rocket), .rocket_ready(has_intact_rocket && !boost_active), .balloon_available(has_intact_balloon),
        .build_grid(build_grid), .intact_mask(intact_mask),
        .launch_req(ui_launch), .edit_req(ui_edit), .guide_open_req(ui_guide_open), .guide_close_req(ui_guide_close),
        .level_open_req(ui_level_open_req), .level_close_req(level_close_req), .level_select_req(level_select_req), .selected_level(selected_level),
        .run_page(run_page), .boost_req(ui_boost_req), .pop_req(ui_pop_req), .pop_cell(mouse_pop_cell), .diary_page(diary_page), .master_volume(master_volume), .mouse_speed(mouse_speed), .engine_on(ui_engine_on), .fan_on(ui_fan_on), .rocket_req(ui_rocket_req), .sound_muted(ui_sound_muted), .launch_flash(launch_flash)
    );
    wire [7:0] par_time;
    seven_seg_timer #(.COUNTDOWN(1), .TIME_LIMIT(20)) u_board_timer (.clk(clk), .reset(reset), .seconds(run_seconds), .seg(seg), .an(an), .dp(dp));
    pig_death_effect u_pig_death (
        .clk(clk), .reset(reset), .run_init(run_init), .physics_tick(physics_tick), .pig_alive(pig_alive),
        .game_state(game_state), .build_grid(build_grid), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y), .vehicle_tilt(vehicle_tilt),
        .death_phase(death_phase), .death_x(death_x), .death_y(death_y)
    );
    sound_controller u_sound_control (
        .clk(clk), .reset(reset), .mute(audio_muted), .cancel(audio_cancel),
        .test_event(1'b0), .launch_event(launch_event), .pop_event(pop_sound_event),
        .collision_event(collision_sound_event), .explosion_event(explosion_sound_event),
        .success_event(success_event), .failure_event(failure_event),
        .busy(audio_busy), .active_sound(active_sound), .sound_start(sound_start), .sound_id(sound_id)
    );
    sound_generator #(
        .TONE_HALF_CYCLES(AUDIO_TONE_HALF_CYCLES), .BEEP_CYCLES(AUDIO_BEEP_CYCLES),
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
        .clk(clk), .reset(reset), .input_enabled(builder_input_enabled), .game_state(game_state),
        .build_grid(build_grid), .build_frames(build_frames), .build_facing_left(build_facing_left),
        .run_page(run_page), .selected_left(selected_left), .inventory_page(inventory_page), .edit_facing_left(edit_facing_left), .mouse_x(mouse_x), .mouse_y(mouse_y),
        .mouse_left(mouse_left), .mouse_right(mouse_right), .mouse_event(mouse_event),
        .mouse_value(mouse_value), .setx(setx), .sety(sety), .setmax_x(setmax_x), .setmax_y(setmax_y), .mouse_speed(mouse_speed),
        .cursor_x(cursor_x), .cursor_y(cursor_y), .selected_part(selected_part),
        .drag_active(drag_active), .drag_from_grid(drag_from_grid), .drag_source(drag_source), .drag_contents(drag_contents),
        .edit_valid(edit_valid), .edit_op(edit_op), .edit_cell(edit_cell), .edit_source(edit_source), .edit_part(edit_part),
        .pop_req(mouse_pop_req), .pop_cell(mouse_pop_cell), .boost_req(mouse_boost_req)
    );
    zoom_control u_zoom (
        .clk(clk), .reset(reset), .zoom_switch(sw[3]), .mouse_event(mouse_event), .mouse_z(mouse_z),
        .zoomed_out(zoomed_out), .overview(overview)
    );
    level_button u_level_button (
        .clk(clk), .reset(reset), .input_enabled(builder_input_enabled), .game_state(game_state), .mouse_x(mouse_x), .mouse_y(mouse_y),
        .mouse_left(mouse_left), .mouse_right(mouse_right), .mouse_event(mouse_event), .level_open_req(btn_level_open_req)
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
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready[0]),
        .edit_valid(edit_valid), .edit_op(edit_op), .edit_cell(edit_cell), .edit_source(edit_source), .edit_part(edit_part), .edit_facing_left(edit_facing_left),
        .build_facing_left(build_facing_left), .engine_balance(engine_balance),
        .rocket_count(rocket_count), .fan_count(fan_count), .rockets_left(rockets_left), .fans_left(fans_left),
        .damage_valid(pop_valid || tnt_damage_valid), .damage_ready(damage_ready),
        .damage_mask((pop_valid ? pop_mask : 9'd0) | (tnt_damage_valid ? tnt_damage_mask : 9'd0)),
        .damage_frame_mask(tnt_damage_valid ? tnt_frame_mask : 9'd0),
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
        .clk(clk), .reset(reset), .launch_req(start_press || ui_launch), .retry_req(start_press || ui_launch), .edit_req(edit_press || ui_edit),
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
    physics_engine #(.ENGINE_FORCE(ENGINE_FORCE)) u_physics (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready[1]),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(wheel_count), .wheels_down(wheels_down), .wheels_up(wheels_up), .tip_dir(tip_dir),
        .engine_count(drive_engines), .balloon_count(balloon_count),
        .mass_units(mass_units), .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(jump_press), .boost_req(boost_req), .boost_active(boost_active),
        .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .response_valid(response_valid),
        .response_ready(response_ready), .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded), .ground_slope(ground_slope),
        .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt), .corrected_tilt(corrected_tilt), .vehicle_tilt(vehicle_tilt),
        .movement_committed(movement_committed), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y), .display_y(display_y)
    );
    collision_engine #(.ROTATION_ONLY(1)) u_collision (
        .collision_mask(intact_mask | frame_intact_mask),
        .clk(clk), .reset(reset || run_init || game_state != `LP_RUN), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .terrain_count(terrain_count), .terrain_rects(terrain_rects),
        .map_level(map_level), .rotation_enabled(1'b1), .previous_tilt(previous_tilt), .proposed_tilt(proposed_tilt), .world_width(world_width), .world_height(world_height),
        .query_x(collision_query_x), .query_y(collision_query_y), .query_class(collision_query_class),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .ground_slope(ground_slope), .corrected_tilt(corrected_tilt), .tip_dir(tip_dir)
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

    localparam SNAPSHOT_WIDTH = 248 + 4*(`LP_COORD_BITS-16) + (`LP_TILT_BITS-4);
    wire [SNAPSHOT_WIDTH-1:0] snapshot_in = {start_screen_active, ui_fan_on, star_box_collected, vehicle_tilt, mouse_speed, audio_muted, run_page, selected_left, inventory_page, build_facing_left, rockets_left, fans_left, master_volume, diary_page, guide_return_state, death_phase, death_x, death_y, launch_flash, boost_active, drag_from_grid, drag_source, drag_contents,
                              game_state, build_grid, intact_mask, frame_intact_mask, build_valid, build_error,
                              vehicle_x, display_y, engine_enabled, frames_left, pigs_left, wheels_left,
                              engines_left, balloons_left, cursor_x, cursor_y, selected_part, drag_active,
                              feedback_code, feedback_cell, level_index, fail_reason, tnt_intact,
                              build_frames, run_seconds, blast_phase};
    wire [SNAPSHOT_WIDTH-1:0] snapshot_out;
    wire draw_start_screen_active, draw_fan_on;
    wire draw_audio_muted; wire [1:0] draw_mouse_speed;
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
    wire [6:0] left_x = 95 - (left_pixel_index % 96);
    wire [5:0] left_y = 63 - (left_pixel_index / 96);
    wire [6:0] right_x = right_pixel_index % 96;
    wire [5:0] right_y = right_pixel_index / 96;
    wire [6:0] map_x = show_map ? left_x : right_x;
    wire [5:0] map_y = show_map ? left_y : right_y;
    wire [15:0] left_pixel_data, right_pixel_data, base_left_pixel_data;
    assign {draw_start_screen_active, draw_fan_on, draw_star_box_collected, draw_tilt, draw_mouse_speed, draw_audio_muted, draw_run_page, draw_selected_left, draw_inventory_page, draw_facing_left, draw_rockets_left, draw_fans_left, draw_master_volume, draw_diary_page, draw_guide_return, draw_death_phase, draw_death_x, draw_death_y, draw_launch_flash, draw_boost_active, draw_drag_from_grid, draw_drag_source, draw_drag_contents,
            draw_state, draw_grid, draw_intact, draw_frames, draw_valid, draw_error, draw_x, draw_y, draw_engine,
            draw_frames_left, draw_pigs_left, draw_wheels_left, draw_engines_left, draw_balloons_left,
            draw_cursor_x, draw_cursor_y, draw_selected_part, draw_drag_active,
            draw_feedback_code, draw_feedback_cell, draw_level, draw_fail_reason, draw_tnt_intact,
            draw_saved_frames, draw_seconds, draw_blast} = snapshot_out;

    wire draw_has_engine = (draw_intact[0] && draw_grid[2:0] == `LP_PART_ENGINE) ||
                           (draw_intact[1] && draw_grid[5:3] == `LP_PART_ENGINE) ||
                           (draw_intact[2] && draw_grid[8:6] == `LP_PART_ENGINE) ||
                           (draw_intact[3] && draw_grid[11:9] == `LP_PART_ENGINE) ||
                           (draw_intact[4] && draw_grid[14:12] == `LP_PART_ENGINE) ||
                           (draw_intact[5] && draw_grid[17:15] == `LP_PART_ENGINE) ||
                           (draw_intact[6] && draw_grid[20:18] == `LP_PART_ENGINE) ||
                           (draw_intact[7] && draw_grid[23:21] == `LP_PART_ENGINE) ||
                           (draw_intact[8] && draw_grid[26:24] == `LP_PART_ENGINE);

    wire draw_has_fan = (draw_intact[0] && draw_grid[2:0] == `LP_PART_FAN) ||
                        (draw_intact[1] && draw_grid[5:3] == `LP_PART_FAN) ||
                        (draw_intact[2] && draw_grid[8:6] == `LP_PART_FAN) ||
                        (draw_intact[3] && draw_grid[11:9] == `LP_PART_FAN) ||
                        (draw_intact[4] && draw_grid[14:12] == `LP_PART_FAN) ||
                        (draw_intact[5] && draw_grid[17:15] == `LP_PART_FAN) ||
                        (draw_intact[6] && draw_grid[20:18] == `LP_PART_FAN) ||
                        (draw_intact[7] && draw_grid[23:21] == `LP_PART_FAN) ||
                        (draw_intact[8] && draw_grid[26:24] == `LP_PART_FAN);

    wire draw_has_rocket = (draw_intact[0] && draw_grid[2:0] == `LP_PART_BOOSTER) ||
                           (draw_intact[1] && draw_grid[5:3] == `LP_PART_BOOSTER) ||
                           (draw_intact[2] && draw_grid[8:6] == `LP_PART_BOOSTER) ||
                           (draw_intact[3] && draw_grid[11:9] == `LP_PART_BOOSTER) ||
                           (draw_intact[4] && draw_grid[14:12] == `LP_PART_BOOSTER) ||
                           (draw_intact[5] && draw_grid[17:15] == `LP_PART_BOOSTER) ||
                           (draw_intact[6] && draw_grid[20:18] == `LP_PART_BOOSTER) ||
                           (draw_intact[7] && draw_grid[23:21] == `LP_PART_BOOSTER) ||
                           (draw_intact[8] && draw_grid[26:24] == `LP_PART_BOOSTER);

    wire draw_has_balloon = (draw_intact[0] && draw_grid[2:0] == `LP_PART_BALLOON) ||
                            (draw_intact[1] && draw_grid[5:3] == `LP_PART_BALLOON) ||
                            (draw_intact[2] && draw_grid[8:6] == `LP_PART_BALLOON) ||
                            (draw_intact[3] && draw_grid[11:9] == `LP_PART_BALLOON) ||
                            (draw_intact[4] && draw_grid[14:12] == `LP_PART_BALLOON) ||
                            (draw_intact[5] && draw_grid[17:15] == `LP_PART_BALLOON) ||
                            (draw_intact[6] && draw_grid[20:18] == `LP_PART_BALLOON) ||
                            (draw_intact[7] && draw_grid[23:21] == `LP_PART_BALLOON) ||
                            (draw_intact[8] && draw_grid[26:24] == `LP_PART_BALLOON);
    display_snapshot #(.WIDTH(SNAPSHOT_WIDTH)) u_snapshot (
        .game_clk(clk), .game_reset(reset), .display_clk(oled_clk), .display_reset(oled_reset),
        .frame_begin(left_frame), .game_data(snapshot_in), .display_data(snapshot_out)
    );
    // Engine pistons step once every eight frames while running with SW0 on; boost doubles the rate.
    reg [3:0] engine_frames;
    always @(posedge oled_clk) begin
        if (oled_reset) engine_frames <= 0;
        else if (left_frame && draw_state == `LP_RUN && draw_engine)
            engine_frames <= engine_frames + (draw_boost_active ? 4'd2 : 4'd1);
    end
    wire anim_phase = engine_frames[3];
    // The map zoom and SW4 free look also change only between complete frames.
    reg zoom_meta_display, zoom_sync_display, draw_zoomed_out;
    reg overview_meta_display, overview_sync_display, draw_overview;
    reg look_meta_display, look_sync_display, draw_free_look;
    reg sw0_meta_display, sw0_sync_display, draw_sw0;
    always @(posedge oled_clk) begin
        if (oled_reset) begin
            zoom_meta_display <= 0; zoom_sync_display <= 0; draw_zoomed_out <= 0;
            overview_meta_display <= 0; overview_sync_display <= 0; draw_overview <= 0;
            look_meta_display <= 0; look_sync_display <= 0; draw_free_look <= 0;
            sw0_meta_display <= 0; sw0_sync_display <= 0; draw_sw0 <= 0;
        end else begin
            zoom_meta_display <= zoomed_out; zoom_sync_display <= zoom_meta_display;
            overview_meta_display <= overview; overview_sync_display <= overview_meta_display;
            look_meta_display <= sw[4]; look_sync_display <= look_meta_display;
            sw0_meta_display <= sw[0]; sw0_sync_display <= sw0_meta_display;
            if (left_frame) begin
                draw_zoomed_out <= zoom_sync_display;
                draw_overview <= overview_sync_display;
                draw_free_look <= look_sync_display;
                draw_sw0 <= sw0_sync_display;
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
    // Scrolling horizontal offset for Start Screen background
    reg [9:0] start_scroll_x;
    reg [1:0] scroll_div;
    always @(posedge oled_clk) begin
        if (oled_reset) begin
            start_scroll_x <= 0;
            scroll_div <= 0;
        end else if (left_frame && draw_start_screen_active) begin
            scroll_div <= scroll_div + 1'b1;
            if (scroll_div == 2'd1) begin
                scroll_div <= 0;
                start_scroll_x <= (start_scroll_x >= 10'd480) ? 10'd0 : start_scroll_x + 1'b1;
            end
        end
    end

    // Independent map selections keep collision on the live level while the
    // display may still hold the previous frame snapshot.
    // When Start Screen is active, Left OLED borrows the idle map port to draw the scrolling cave!
    wire signed [10:0] right_map_x, right_map_y;
    wire signed [10:0] map_draw_x = right_map_x;
    wire signed [10:0] map_draw_y = right_map_y;
    wire [2:0] map_draw_class;

    level_map u_level_map (
        .map_id(draw_map_id), .draw_clk(oled_clk), .draw_x(map_draw_x), .draw_y(map_draw_y), .draw_class(map_draw_class),
        .query_clk(clk), .query_map_id(map_id),
        .query_x(collision_query_x), .query_y(collision_query_y),
        .query_class(), .query_solid(collision_query_solid)
    );
    left_renderer u_left_renderer (
        .pixel_index(13'd0), .in_x(left_x), .in_y(left_y), .game_state(draw_state), .build_grid(draw_grid),
        .build_frames(draw_saved_frames), .build_facing_left(draw_facing_left),
        .selected_left(draw_selected_left), .inventory_page(draw_inventory_page),
        .rockets_left(draw_rockets_left), .fans_left(draw_fans_left), .intact_mask(draw_intact), .frame_intact_mask(draw_frames),
        .build_valid(draw_valid), .build_error(draw_error), .engine_enabled(draw_engine), .boost_active(draw_boost_active),
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
        .map_draw_class(map_draw_class),
        .diary_page(draw_diary_page), .run_page(draw_run_page),
        .inventory_page(draw_inventory_page),
        .selected_left(draw_selected_left), .audio_muted(draw_audio_muted),
        .selected_part(draw_selected_part),
        .master_volume(draw_master_volume), .mouse_speed(draw_mouse_speed),
        .level_index(draw_level),
        .build_valid(draw_valid), .engine_enabled(draw_engine), .boost_active(draw_boost_active),
        .engine_available(draw_has_engine),
        .fan_available(draw_has_fan), .fan_on(draw_fan_on),
        .rocket_available(draw_has_rocket), .rocket_ready(draw_has_rocket && !draw_boost_active),
        .balloon_available(draw_has_balloon),
        .anim_phase(anim_phase),
        .cursor_x(draw_cursor_x), .cursor_y(draw_cursor_y),
        .build_grid(draw_grid),
        .intact_mask(draw_intact),
        .frame_intact_mask(draw_frames),
        .build_facing_left(draw_facing_left),
        .sw0_engine(draw_sw0),
        .pixel_data(left_pixel_data)
    );
    right_renderer u_right_renderer (
        .clk(oled_clk), .zoomed_out(draw_zoomed_out), .overview(draw_overview),
        .free_look(draw_free_look), .cursor_x(draw_cursor_x), .cursor_y(draw_cursor_y),
        .pixel_index(13'd0), .in_x(map_x), .in_y(map_y), .game_state((draw_state==`LP_LEVEL_SELECT || draw_state==`LP_SETTINGS) ? `LP_BUILD : (draw_state==`LP_GUIDE ? draw_guide_return : draw_state)), .build_grid(draw_grid),
        .build_facing_left(draw_facing_left), .intact_mask(draw_intact), .frame_intact_mask(draw_frames),
        // Full world coordinates cross the display snapshot without truncation.
        .vehicle_x(draw_x), .vehicle_y(draw_y), .vehicle_tilt(draw_tilt),
        .spawn_x(draw_spawn_x), .spawn_y(draw_spawn_y),
        .terrain_count(draw_terrain_count), .terrain_rects(draw_terrain_rects), .goal_rect(draw_goal_rect),
        .tnt_count(draw_tnt_count), .tnt_positions(draw_tnt_positions), .tnt_intact(draw_tnt_intact),
        .hazard_count(draw_hazard_count), .hazard_rects(draw_hazard_rects), .blast_phase(draw_blast),
        .death_phase(draw_death_phase), .death_x(draw_death_x), .death_y(draw_death_y), .launch_flash(draw_launch_flash),
        .anim_phase(anim_phase), .map_level(draw_map_level), .map_id(draw_map_id), .world_width(draw_world_width),
        .world_height(draw_world_height), .flag_x(draw_flag_x), .flag_y(draw_flag_y), .star_box_x(draw_star_box_x), .star_box_y(draw_star_box_y), .star_box_collected(draw_star_box_collected),
        .map_x(right_map_x), .map_y(right_map_y), .map_class(map_draw_class),
        .pixel_data(right_pixel_data)
    );
    wire right_oled_on = (draw_state != `LP_LEVEL_SELECT);
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
    assign led = sw;
endmodule









