// Owner: Role 4 - Marcus. Game states, level selection and update sequencing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// BUILD -> INIT_RUN -> RUN -> SUCCESS/FAIL -> retry (INIT_RUN) or edit (BUILD).
// Edit after SUCCESS moves to the next level; edit after FAIL keeps the level.
// Level selection is available before launch; geometry stays frozen for a whole run.
module game_controller #(
    parameter integer TICKS_PER_SECOND = 60,
    parameter integer ENABLE_START_SCREEN = 0
) (
    input wire clk, reset, launch_req, retry_req, edit_req, guide_open_req, guide_close_req,
    input wire level_next_req, level_open_req, level_close_req, level_select_req,
    input wire [`LP_LEVEL_BITS-1:0] selected_level,
    input wire build_valid, pig_alive,
    input wire [2:0] init_ready,
    input wire physics_tick, world_valid,
    output wire world_ready,
    input wire gameplay_pending,
    output wire gameplay_ready,
    input wire goal_hit, hazard_hit, out_of_bounds, star_box_hit,
    output reg star_box_collected,
    input wire enable_start_screen,
    output reg start_screen_active,
    input wire [7:0] par_time,
    output reg [2:0] game_state,
    output reg [2:0] guide_return_state,
    output reg [`LP_LEVEL_BITS-1:0] level_index,
    output reg [1:0] fail_reason,
    output reg [7:0] run_seconds,
    output wire run_init,
    output reg step_start, update_release, launch_event, success_event, failure_event
);
    reg step_busy;
    reg [6:0] second_ticks;
    reg settings_from_start;
    reg [2:0] settings_return_state;
    reg map_from_start;
    wire [`LP_LEVEL_BITS-1:0] next_level = (level_index == `LP_LEVEL_COUNT-1) ? 0 : level_index + 1'b1;
    assign run_init = (game_state == `LP_INIT_RUN);
    assign world_ready = (game_state == `LP_RUN) && step_busy;
    assign gameplay_ready = (game_state == `LP_RUN) && !step_busy;
    always @(posedge clk) begin
        if (reset) begin
            game_state <= `LP_BUILD; guide_return_state <= `LP_BUILD; settings_return_state <= `LP_BUILD; level_index <= 0; fail_reason <= `LP_FAIL_NONE;
            run_seconds <= 0; second_ticks <= 0; star_box_collected <= 0;
            step_busy <= 0; step_start <= 0; update_release <= 0;
            launch_event <= 0; success_event <= 0; failure_event <= 0;
            start_screen_active <= (enable_start_screen === 1'b1) || (ENABLE_START_SCREEN != 0);
            settings_from_start <= 1'b0;
            map_from_start <= 1'b0;
        end else begin
            step_start <= 0; update_release <= 0;
            if (star_box_hit && game_state == `LP_RUN) star_box_collected <= 1;
            launch_event <= 0; success_event <= 0; failure_event <= 0;
            if (start_screen_active) begin
                step_busy <= 0;
                if (launch_req) begin
                    start_screen_active <= 1'b0;
                    map_from_start <= 1'b1;
                    game_state <= `LP_LEVEL_SELECT;
                end else if (level_open_req) begin
                    start_screen_active <= 1'b0;
                    settings_from_start <= 1'b1;
                    settings_return_state <= `LP_BUILD;
                    game_state <= `LP_SETTINGS;
                end
            end else begin
                case (game_state)
                    `LP_BUILD: begin
                        step_busy <= 0;
                        if (guide_open_req) begin guide_return_state <= `LP_BUILD; game_state <= `LP_GUIDE; end
                        else if (launch_req && build_valid) game_state <= `LP_INIT_RUN;
                        else if (level_open_req) begin settings_from_start <= 1'b0; settings_return_state <= `LP_BUILD; game_state <= `LP_SETTINGS; end
                        else if (level_next_req) level_index <= next_level;
                    end
                    `LP_SETTINGS: begin
                        step_busy <= 0;
                        if (level_close_req || edit_req) begin
                            if (settings_from_start) begin
                                start_screen_active <= (enable_start_screen === 1'b1) || (ENABLE_START_SCREEN != 0);
                                settings_from_start <= 1'b0;
                                game_state <= `LP_BUILD;
                            end else begin
                                game_state <= settings_return_state;
                            end
                        end
                        else if (level_select_req || level_open_req) game_state <= `LP_LEVEL_SELECT;
                        else if (guide_open_req) begin guide_return_state <= `LP_SETTINGS; game_state <= `LP_GUIDE; end
                    end
                    `LP_LEVEL_SELECT: begin
                        step_busy <= 0;
                        if (level_close_req || edit_req) begin
                            if (map_from_start) begin
                                start_screen_active <= (enable_start_screen === 1'b1) || (ENABLE_START_SCREEN != 0);
                                game_state <= `LP_BUILD;
                            end else begin
                                game_state <= `LP_SETTINGS;
                            end
                        end else if (level_select_req && selected_level < `LP_LEVEL_COUNT) begin
                            level_index <= selected_level;
                            start_screen_active <= 1'b0;
                            game_state <= `LP_BUILD;
                        end
                    end
                    `LP_GUIDE: if (guide_close_req) game_state <= guide_return_state;
                    `LP_INIT_RUN: begin
                        step_busy <= 0; fail_reason <= `LP_FAIL_NONE; run_seconds <= 0; second_ticks <= 0; star_box_collected <= 0;
                        if (&init_ready) begin game_state <= `LP_RUN; launch_event <= 1; end
                    end
                    `LP_RUN: begin
                        if (edit_req) begin game_state <= `LP_BUILD; step_busy <= 0; fail_reason <= `LP_FAIL_NONE; end
                        else if (retry_req) begin game_state <= `LP_INIT_RUN; step_busy <= 0; end
                        else if (level_open_req) begin settings_from_start <= 1'b0; settings_return_state <= `LP_RUN; game_state <= `LP_SETTINGS; end
                        else begin
                    // Whole seconds of RUN, held at 4:15; results freeze the final time.
                    if (physics_tick) begin
                        if (second_ticks == TICKS_PER_SECOND-1) begin
                            second_ticks <= 0;
                            if (run_seconds != 8'hff) run_seconds <= run_seconds + 1'b1;
                        end else second_ticks <= second_ticks + 1;
                    end
                    if (world_valid && world_ready) begin
                        step_busy <= 0; update_release <= 1;
                        // Failure checks take priority over reaching the goal.
                        if (!pig_alive || hazard_hit || out_of_bounds) begin
                            game_state <= `LP_FAIL; failure_event <= 1;
                            if (!pig_alive) fail_reason <= `LP_FAIL_PIG;
                            else if (hazard_hit) fail_reason <= `LP_FAIL_HAZARD;
                            else fail_reason <= `LP_FAIL_BOUNDS;
                        end else if (goal_hit) begin game_state <= `LP_SUCCESS; success_event <= 1; end
                    end else if (physics_tick && !step_busy && !gameplay_pending) begin
                        step_start <= 1; step_busy <= 1;
                    end
                    end
                end
                `LP_SUCCESS, `LP_FAIL: begin
                    step_busy <= 0;
                    if (guide_open_req) begin guide_return_state <= game_state; game_state <= `LP_GUIDE; end
                    else if (edit_req) begin
                        game_state <= `LP_BUILD; fail_reason <= `LP_FAIL_NONE;
                        if (game_state == `LP_SUCCESS) level_index <= next_level;
                    end
                    else if (retry_req) game_state <= `LP_INIT_RUN;
                end
                default: begin game_state <= `LP_BUILD; step_busy <= 0; end
                endcase
            end
        end
    end
endmodule


