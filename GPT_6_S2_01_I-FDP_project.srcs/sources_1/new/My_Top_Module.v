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
// BTNU edit/next level after success, BTNR test beep and BTND reset.
module My_Top_Module #(
    parameter integer PHYSICS_CYCLES = 1666667,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 20000000,
    parameter integer BUTTON_RELEASE_CYCLES = 2000000,
    parameter integer AUDIO_TONE_HALF_CYCLES = 50000,
    parameter integer AUDIO_BEEP_CYCLES = 20000000,
    parameter integer AUDIO_NOTE_CYCLES = 8000000,
    parameter integer AUDIO_FADE_CYCLES = 50000,
    parameter integer ENABLE_BGM = 1,
    parameter integer BGM_UNIT_CYCLES = 15625000,
    parameter integer FRAME_LIMIT = 5,
    parameter integer PIG_LIMIT = 1,
    parameter integer WHEEL_LIMIT = 2,
    parameter integer ENGINE_LIMIT = 1,
    parameter integer BALLOON_LIMIT = 2,
    parameter integer FEEDBACK_CYCLES = 100000000
) (
    input wire clk, btnC, btnU, btnR, btnL, btnD,
    input wire [15:0] sw,
    inout wire PS2Clk, PS2Data,
    output wire [15:0] led,
    output wire [7:0] JA, JB,
    output wire [3:0] JXADC
);
    wire reset, oled_clk, oled_reset, physics_tick, start_press, edit_press, engine_enabled;
    wire engine_reverse, jump_press, boost_req, boost_active;
    wire [2:0] game_state, init_ready;
    wire run_init, step_start, update_release;
    wire [26:0] build_grid;
    wire [8:0] build_frames, intact_mask, frame_intact_mask;
    wire build_valid, pig_alive, damage_ready;
    wire [3:0] build_error, wheel_count, engine_count, balloon_count;
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
    wire signed [15:0] spawn_x, spawn_y, vehicle_x, vehicle_y;
    wire [2:0] terrain_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire level_next_req, level_index;
    wire [1:0] fail_reason;
    wire [6:0] run_seconds;
    wire [2*`LP_MAX_TNT-1:0] blast_phase;
    // Accepted launch and result pulses for Role 1 audio; Role 4 does not schedule sounds.
    wire [2:0] tnt_count;
    wire [`LP_TNT_BITS-1:0] tnt_positions;
    wire [1:0] hazard_count;
    wire [`LP_HAZARD_BITS-1:0] hazard_rects;
    // Placeholder until Role 3's TNT logic reports which blocks have exploded.
    wire [`LP_MAX_TNT-1:0] tnt_intact = {`LP_MAX_TNT{1'b1}};
    wire move_valid, move_ready, response_valid, response_ready, grounded;
    wire signed [15:0] previous_x, previous_y, proposed_x, proposed_y, proposed_vx, proposed_vy;
    wire signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy;
    wire movement_committed, world_valid, world_ready, goal_hit, hazard_hit, out_of_bounds;
    wire launch_event, success_event, failure_event;
    wire beep_press, audio_muted, audio_busy, audio_pwm;
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
    // Role 3 will connect a one-clock pulse when TNT actually explodes.
    wire explosion_sound_event = 1'b0;
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
    input_controller #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES), .RELEASE_CYCLES(BUTTON_RELEASE_CYCLES)
    ) u_input (
        .clk(clk), .reset(reset), .btnC(btnC), .btnU(btnU), .btnR(btnR), .btnL(btnL),
        .engine_switch(sw[0]), .mute_switch(sw[1]), .reverse_switch(sw[2]), .start_press(start_press), .edit_press(edit_press),
        .beep_press(beep_press), .engine_enabled(engine_enabled), .audio_muted(audio_muted), .engine_reverse(engine_reverse), .jump_press(jump_press)
    );
    sound_controller u_sound_control (
        .clk(clk), .reset(reset), .mute(audio_muted), .cancel(audio_cancel),
        .test_event(beep_press), .launch_event(launch_event), .pop_event(pop_sound_event),
        .collision_event(collision_sound_event), .explosion_event(explosion_sound_event),
        .success_event(success_event), .failure_event(failure_event),
        .busy(audio_busy), .active_sound(active_sound), .sound_start(sound_start), .sound_id(sound_id)
    );
    sound_generator #(
        .TONE_HALF_CYCLES(AUDIO_TONE_HALF_CYCLES), .BEEP_CYCLES(AUDIO_BEEP_CYCLES),
        .NOTE_CYCLES(AUDIO_NOTE_CYCLES), .FADE_CYCLES(AUDIO_FADE_CYCLES)
    ) u_audio (
        .clk(clk), .reset(reset), .start(sound_start), .sound_id(sound_id),
        .mute(audio_muted), .cancel(audio_cancel), .busy(audio_busy),
        .active_sound(active_sound), .audio_pwm(audio_pwm), .bgm_sample(bgm_sample)
    );
    bgm_player #(.UNIT_CYCLES(BGM_UNIT_CYCLES), .FADE_CYCLES(AUDIO_FADE_CYCLES)) u_bgm (
        .clk(clk), .reset(reset),
        .enabled(ENABLE_BGM && !audio_muted && (game_state == `LP_BUILD || game_state == `LP_RUN)),
        .pause(audio_busy || sound_start), .fast(game_state == `LP_RUN), .audio_sample(bgm_sample)
    );
    MouseCtl u_mouse (
        .clk(clk), .rst(reset), .xpos(mouse_x), .ypos(mouse_y), .zpos(),
        .left(mouse_left), .middle(), .right(mouse_right), .new_event(mouse_event),
        .value(mouse_value), .setx(setx), .sety(sety), .setmax_x(setmax_x), .setmax_y(setmax_y),
        .ps2_clk(PS2Clk), .ps2_data(PS2Data)
    );
    mouse_adapter u_mouse_adapter (
        .clk(clk), .reset(reset), .input_enabled(builder_input_enabled), .game_state(game_state),
        .build_grid(build_grid), .build_frames(build_frames), .mouse_x(mouse_x), .mouse_y(mouse_y),
        .mouse_left(mouse_left), .mouse_right(mouse_right), .mouse_event(mouse_event),
        .mouse_value(mouse_value), .setx(setx), .sety(sety), .setmax_x(setmax_x), .setmax_y(setmax_y),
        .cursor_x(cursor_x), .cursor_y(cursor_y), .selected_part(selected_part),
        .drag_active(drag_active), .drag_from_grid(drag_from_grid), .drag_source(drag_source), .drag_contents(drag_contents),
        .edit_valid(edit_valid), .edit_op(edit_op), .edit_cell(edit_cell), .edit_source(edit_source), .edit_part(edit_part),
        .pop_req(pop_req), .pop_cell(pop_cell), .boost_req(boost_req)
    );
    level_button u_level_button (
        .clk(clk), .reset(reset), .input_enabled(builder_input_enabled), .game_state(game_state), .mouse_x(mouse_x), .mouse_y(mouse_y),
        .mouse_left(mouse_left), .mouse_right(mouse_right), .mouse_event(mouse_event), .level_next_req(level_next_req)
    );
    balloon_control u_balloons (
        .clk(clk), .reset(reset), .game_state(game_state), .pop_req(pop_req), .pop_cell(pop_cell),
        .build_grid(build_grid), .intact_mask(intact_mask), .gameplay_ready(gameplay_ready),
        .pop_pending(pop_pending), .pop_valid(pop_valid), .pop_mask(pop_mask)
    );
    vehicle_builder #(
        .FRAME_LIMIT(FRAME_LIMIT), .PIG_LIMIT(PIG_LIMIT), .WHEEL_LIMIT(WHEEL_LIMIT),
        .ENGINE_LIMIT(ENGINE_LIMIT), .BALLOON_LIMIT(BALLOON_LIMIT), .FEEDBACK_CYCLES(FEEDBACK_CYCLES)
    ) u_builder (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready[0]),
        .edit_valid(edit_valid), .edit_op(edit_op), .edit_cell(edit_cell), .edit_source(edit_source), .edit_part(edit_part),
        .damage_valid(pop_valid), .damage_ready(damage_ready), .damage_mask(pop_mask), .damage_frame_mask(9'd0),
        .build_grid(build_grid), .build_frames(build_frames),
        .intact_mask(intact_mask), .frame_intact_mask(frame_intact_mask), .build_valid(build_valid),
        .build_error(build_error), .pig_alive(pig_alive), .wheel_count(wheel_count),
        .feedback_code(feedback_code), .feedback_cell(feedback_cell),
        .engine_count(engine_count), .balloon_count(balloon_count), .mass_units(mass_units),
        .frames_left(frames_left), .pigs_left(pigs_left), .wheels_left(wheels_left),
        .engines_left(engines_left), .balloons_left(balloons_left)
    );
    // TNT positions and hazards are ready for Role 3's checks; world_outcomes does not read them yet.
    level_data u_level (
        .level_index(level_index), .spawn_x(spawn_x), .spawn_y(spawn_y), .terrain_count(terrain_count),
        .terrain_rects(terrain_rects), .goal_rect(goal_rect), .tnt_count(tnt_count),
        .tnt_positions(tnt_positions), .hazard_count(hazard_count), .hazard_rects(hazard_rects)
    );
    game_controller u_game (
        .clk(clk), .reset(reset), .launch_req(start_press), .retry_req(start_press), .edit_req(edit_press),
        .guide_open_req(1'b0), .guide_close_req(1'b0), .level_next_req(level_next_req),
        .level_index(level_index), .fail_reason(fail_reason), .run_seconds(run_seconds),
        .build_valid(build_valid && !edit_valid), .pig_alive(pig_alive),
        .init_ready(init_ready), .physics_tick(physics_tick), .world_valid(world_valid), .world_ready(world_ready),
        .gameplay_pending(pop_pending), .gameplay_ready(gameplay_ready),
        .goal_hit(goal_hit), .hazard_hit(hazard_hit), .out_of_bounds(out_of_bounds), .game_state(game_state),
        .run_init(run_init), .step_start(step_start), .update_release(update_release),
        .launch_event(launch_event), .success_event(success_event), .failure_event(failure_event)
    );
    explosion_fx u_explosions (
        .clk(clk), .reset(reset), .run_init(run_init), .physics_tick(physics_tick),
        .tnt_intact(tnt_intact), .blast_phase(blast_phase)
    );
    physics_engine u_physics (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready[1]),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(wheel_count), .engine_count(engine_count), .balloon_count(balloon_count),
        .mass_units(mass_units), .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(jump_press), .boost_req(boost_req), .boost_active(boost_active),
        .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .response_valid(response_valid),
        .response_ready(response_ready), .corrected_x(corrected_x), .corrected_y(corrected_y),
        .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded),
        .movement_committed(movement_committed), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y)
    );
    collision_engine u_collision (
        .clk(clk), .reset(reset), .move_valid(move_valid), .move_ready(move_ready),
        .previous_x(previous_x), .previous_y(previous_y), .proposed_x(proposed_x), .proposed_y(proposed_y),
        .proposed_vx(proposed_vx), .proposed_vy(proposed_vy), .terrain_count(terrain_count), .terrain_rects(terrain_rects),
        .response_valid(response_valid), .response_ready(response_ready), .corrected_x(corrected_x),
        .corrected_y(corrected_y), .corrected_vx(corrected_vx), .corrected_vy(corrected_vy), .grounded(grounded)
    );
    world_outcomes u_world (
        .clk(clk), .reset(reset), .run_init(run_init), .game_state(game_state), .init_ready(init_ready[2]),
        .movement_committed(movement_committed), .vehicle_x(vehicle_x), .vehicle_y(vehicle_y),
        .build_grid(build_grid), .intact_mask(intact_mask), .goal_rect(goal_rect), .world_valid(world_valid),
        .world_ready(world_ready), .goal_hit(goal_hit), .hazard_hit(hazard_hit), .out_of_bounds(out_of_bounds)
    );

    wire [170:0] snapshot_in = {boost_active, drag_from_grid, drag_source, drag_contents,
                              game_state, build_grid, intact_mask, frame_intact_mask, build_valid, build_error,
                              vehicle_x, vehicle_y, engine_enabled, frames_left, pigs_left, wheels_left,
                              engines_left, balloons_left, cursor_x, cursor_y, selected_part, drag_active,
                              feedback_code, feedback_cell, level_index, fail_reason, tnt_intact,
                              build_frames, run_seconds, blast_phase};
    wire [170:0] snapshot_out;
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
    wire signed [15:0] draw_x, draw_y;
    wire draw_level;
    wire [8:0] draw_saved_frames;
    wire [6:0] draw_seconds;
    wire [2*`LP_MAX_TNT-1:0] draw_blast;
    wire [1:0] draw_fail_reason;
    wire [`LP_MAX_TNT-1:0] draw_tnt_intact;
    wire signed [15:0] draw_spawn_x, draw_spawn_y;
    wire [2:0] draw_terrain_count, draw_tnt_count;
    wire [127:0] draw_terrain_rects;
    wire [31:0] draw_goal_rect;
    wire [`LP_TNT_BITS-1:0] draw_tnt_positions;
    wire [1:0] draw_hazard_count;
    wire [`LP_HAZARD_BITS-1:0] draw_hazard_rects;
    wire [12:0] left_pixel_index, right_pixel_index;
    // JA is mounted upside down: reverse all 96 x 64 pixels to rotate it 180 degrees.
    wire [12:0] left_render_index = 13'd6143 - left_pixel_index;
    // Reuse the map renderer for one-OLED play; JB is blank while JA shows the map.
    wire [12:0] map_pixel_index = show_map ? left_render_index : right_pixel_index;
    wire [15:0] left_pixel_data, right_pixel_data;
    assign {draw_boost_active, draw_drag_from_grid, draw_drag_source, draw_drag_contents,
            draw_state, draw_grid, draw_intact, draw_frames, draw_valid, draw_error, draw_x, draw_y, draw_engine,
            draw_frames_left, draw_pigs_left, draw_wheels_left, draw_engines_left, draw_balloons_left,
            draw_cursor_x, draw_cursor_y, draw_selected_part, draw_drag_active,
            draw_feedback_code, draw_feedback_cell, draw_level, draw_fail_reason, draw_tnt_intact,
            draw_saved_frames, draw_seconds, draw_blast} = snapshot_out;
    display_snapshot #(.WIDTH(171)) u_snapshot (
        .game_clk(clk), .game_reset(reset), .display_clk(oled_clk), .display_reset(oled_reset),
        .frame_begin(left_frame), .game_data(snapshot_in), .display_data(snapshot_out)
    );
    // A second copy of the level table, indexed by the snapshot, keeps the map in step with the drawn state.
    level_data u_draw_level (
        .level_index(draw_level), .spawn_x(draw_spawn_x), .spawn_y(draw_spawn_y),
        .terrain_count(draw_terrain_count), .terrain_rects(draw_terrain_rects), .goal_rect(draw_goal_rect),
        .tnt_count(draw_tnt_count), .tnt_positions(draw_tnt_positions),
        .hazard_count(draw_hazard_count), .hazard_rects(draw_hazard_rects)
    );
    left_renderer u_left_renderer (
        .pixel_index(left_render_index), .game_state(draw_state), .build_grid(draw_grid),
        .build_frames(draw_saved_frames), .intact_mask(draw_intact), .frame_intact_mask(draw_frames),
        .build_valid(draw_valid), .build_error(draw_error), .engine_enabled(draw_engine), .boost_active(draw_boost_active),
        .feedback_code(draw_feedback_code), .feedback_cell(draw_feedback_cell),
        .frames_left(draw_frames_left), .pigs_left(draw_pigs_left), .wheels_left(draw_wheels_left),
        .engines_left(draw_engines_left), .balloons_left(draw_balloons_left), .selected_part(draw_selected_part),
        .drag_active(draw_drag_active),
        .drag_from_grid(draw_drag_from_grid), .drag_source(draw_drag_source), .drag_contents(draw_drag_contents),
        .cursor_x(draw_cursor_x), .cursor_y(draw_cursor_y), .cursor_visible(1'b1),
        .level_index(draw_level), .fail_reason(draw_fail_reason), .run_seconds(draw_seconds),
        .pixel_data(left_pixel_data)
    );
    right_renderer u_right_renderer (
        .pixel_index(map_pixel_index), .game_state(draw_state), .build_grid(draw_grid),
        .intact_mask(draw_intact), .frame_intact_mask(draw_frames),
        .vehicle_x(draw_x), .vehicle_y(draw_y), .spawn_x(draw_spawn_x), .spawn_y(draw_spawn_y),
        .terrain_count(draw_terrain_count), .terrain_rects(draw_terrain_rects), .goal_rect(draw_goal_rect),
        .tnt_count(draw_tnt_count), .tnt_positions(draw_tnt_positions), .tnt_intact(draw_tnt_intact),
        .hazard_count(draw_hazard_count), .hazard_rects(draw_hazard_rects), .blast_phase(draw_blast),
        .pixel_data(right_pixel_data)
    );
    Oled_Display u_left_oled (
        .clk(oled_clk), .reset(oled_reset), .frame_begin(left_frame), .sending_pixels(), .sample_pixel(),
        .pixel_index(left_pixel_index), .pixel_data(show_map ? right_pixel_data : left_pixel_data), .cs(JA[0]), .sdin(JA[1]), .sclk(JA[3]),
        .d_cn(JA[4]), .resn(JA[5]), .vccen(JA[6]), .pmoden(JA[7])
    );
    Oled_Display u_right_oled (
        .clk(oled_clk), .reset(oled_reset), .frame_begin(), .sending_pixels(), .sample_pixel(),
        .pixel_index(right_pixel_index), .pixel_data(show_map ? 16'd0 : right_pixel_data), .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]),
        .d_cn(JB[4]), .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
    assign JA[2] = 1'b0;
    assign JB[2] = 1'b0;
    // Pmod AMP2 on JXADC pins 1-6: AIN, GAIN, NC, shutdown_n, GND, 3.3V.
    assign JXADC[0] = audio_pwm;
    assign JXADC[1] = 1'b1; // High selects the lower, 6 dB gain.
    assign JXADC[2] = 1'b0; // AMP2 pin 3 is not connected.
    assign JXADC[3] = !reset && !audio_muted;
    assign led = {intact_mask, engine_enabled, build_valid, pig_alive, world_valid, game_state};
endmodule
