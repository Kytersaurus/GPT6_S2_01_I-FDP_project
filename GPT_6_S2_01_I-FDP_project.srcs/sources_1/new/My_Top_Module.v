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

// SW0 engine, BTNC launch/retry, BTNU return to BUILD after a result, BTND reset.
module My_Top_Module #(
    parameter integer PHYSICS_CYCLES = 1666667,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 20000000,
    parameter integer BUTTON_RELEASE_CYCLES = 2000000
) (
    input wire clk, btnC, btnU, btnD, btnR,
    input wire [1:0] sw,
    output wire [15:0] led,
    output wire [7:0] JA, JB
);
    wire reset, oled_clk, oled_reset, physics_tick, start_press, edit_press, engine_enabled, engine_reverse, jump_press;
    wire [2:0] game_state, init_ready;
    wire run_init, step_start, update_release;
    wire [26:0] build_grid;
    wire [8:0] intact_mask;
    wire build_valid, pig_alive, damage_ready;
    wire [3:0] build_error, wheel_count, engine_count, balloon_count;
    wire [7:0] mass_units;
    wire signed [15:0] spawn_x, spawn_y, vehicle_x, vehicle_y;
    wire [2:0] terrain_count;
    wire [127:0] terrain_rects;
    wire [31:0] goal_rect;
    wire move_valid, move_ready, response_valid, response_ready, grounded;
    wire signed [15:0] previous_x, previous_y, proposed_x, proposed_y, proposed_vx, proposed_vy;
    wire signed [15:0] corrected_x, corrected_y, corrected_vx, corrected_vy;
    wire movement_committed, world_valid, world_ready, goal_hit, hazard_hit, out_of_bounds;
    wire launch_event, success_event, failure_event;

    clock_control #(.PHYSICS_CYCLES(PHYSICS_CYCLES)) u_clocking (
        .clk(clk), .reset_button(btnD), .reset(reset), .oled_clk(oled_clk),
        .oled_reset(oled_reset), .physics_tick(physics_tick)
    );
    input_controller #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES), .RELEASE_CYCLES(BUTTON_RELEASE_CYCLES)
    ) u_input (
        .clk(clk), .reset(reset), .btnC(btnC), .btnU(btnU), .btnR(btnR), .engine_switch(sw[0]), .reverse_switch(sw[1]),
        .start_press(start_press), .edit_press(edit_press), .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(jump_press)
    );
    vehicle_builder u_builder (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready[0]),
        .edit_valid(1'b0), .edit_op(`LP_EDIT_PLACE), .edit_cell(4'd0), .edit_part(`LP_PART_EMPTY),
        .damage_valid(1'b0), .damage_ready(damage_ready), .damage_mask(9'd0),
        .build_grid(build_grid), .intact_mask(intact_mask), .build_valid(build_valid),
        .build_error(build_error), .pig_alive(pig_alive), .wheel_count(wheel_count),
        .engine_count(engine_count), .balloon_count(balloon_count), .mass_units(mass_units)
    );
    level_data u_level (
        .spawn_x(spawn_x), .spawn_y(spawn_y), .terrain_count(terrain_count),
        .terrain_rects(terrain_rects), .goal_rect(goal_rect)
    );
    game_controller u_game (
        .clk(clk), .reset(reset), .launch_req(start_press), .retry_req(start_press), .edit_req(edit_press),
        .guide_open_req(1'b0), .guide_close_req(1'b0), .build_valid(build_valid), .pig_alive(pig_alive),
        .init_ready(init_ready), .physics_tick(physics_tick), .world_valid(world_valid), .world_ready(world_ready),
        .goal_hit(goal_hit), .hazard_hit(hazard_hit), .out_of_bounds(out_of_bounds), .game_state(game_state),
        .run_init(run_init), .step_start(step_start), .update_release(update_release),
        .launch_event(launch_event), .success_event(success_event), .failure_event(failure_event)
    );
    physics_engine u_physics (
        .clk(clk), .reset(reset), .game_state(game_state), .run_init(run_init), .init_ready(init_ready[1]),
        .spawn_x(spawn_x), .spawn_y(spawn_y), .step_start(step_start), .update_release(update_release),
        .wheel_count(wheel_count), .engine_count(engine_count), .balloon_count(balloon_count),
        .mass_units(mass_units), .engine_enabled(engine_enabled), .engine_reverse(engine_reverse), .jump_press(jump_press), .move_valid(move_valid), .move_ready(move_ready),
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

    wire [76:0] snapshot_in = {game_state, build_grid, intact_mask, build_valid, build_error,
                              vehicle_x, vehicle_y, engine_enabled};
    wire [76:0] snapshot_out;
    wire [2:0] draw_state;
    wire [26:0] draw_grid;
    wire [8:0] draw_intact;
    wire draw_valid, draw_engine;
    wire [3:0] draw_error;
    wire signed [15:0] draw_x, draw_y;
    wire left_frame, right_frame;
    wire [12:0] left_pixel_index, right_pixel_index;
    wire [15:0] left_pixel_data, right_pixel_data;
    assign {draw_state, draw_grid, draw_intact, draw_valid, draw_error, draw_x, draw_y, draw_engine} = snapshot_out;
    display_snapshot u_snapshot (
        .game_clk(clk), .game_reset(reset), .display_clk(oled_clk), .display_reset(oled_reset),
        .frame_begin(left_frame), .game_data(snapshot_in), .display_data(snapshot_out)
    );
    left_renderer u_left_renderer (
        .pixel_index(left_pixel_index), .game_state(draw_state), .build_grid(draw_grid), .intact_mask(draw_intact),
        .build_valid(draw_valid), .build_error(draw_error), .engine_enabled(draw_engine), .pixel_data(left_pixel_data)
    );
    right_renderer u_right_renderer (
        .pixel_index(right_pixel_index), .game_state(draw_state), .build_grid(draw_grid), .intact_mask(draw_intact),
        .vehicle_x(draw_x), .vehicle_y(draw_y), .terrain_count(terrain_count), .terrain_rects(terrain_rects),
        .goal_rect(goal_rect), .pixel_data(right_pixel_data)
    );
    Oled_Display u_left_oled (
        .clk(oled_clk), .reset(oled_reset), .frame_begin(left_frame), .sending_pixels(), .sample_pixel(),
        .pixel_index(left_pixel_index), .pixel_data(left_pixel_data), .cs(JA[0]), .sdin(JA[1]), .sclk(JA[3]),
        .d_cn(JA[4]), .resn(JA[5]), .vccen(JA[6]), .pmoden(JA[7])
    );
    Oled_Display u_right_oled (
        .clk(oled_clk), .reset(oled_reset), .frame_begin(right_frame), .sending_pixels(), .sample_pixel(),
        .pixel_index(right_pixel_index), .pixel_data(right_pixel_data), .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]),
        .d_cn(JB[4]), .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
    assign JA[2] = 1'b0;
    assign JB[2] = 1'b0;
    assign led = {intact_mask, engine_enabled, build_valid, pig_alive, world_valid, game_state};
endmodule
