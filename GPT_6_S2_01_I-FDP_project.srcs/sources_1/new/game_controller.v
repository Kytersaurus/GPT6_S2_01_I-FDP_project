// Owner: Role 4 - Marcus. Game states, level selection and update sequencing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// BUILD -> INIT_RUN -> RUN -> SUCCESS/FAIL -> retry (INIT_RUN) or edit (BUILD).
// Edit after SUCCESS moves to the next level; edit after FAIL keeps the level.
// The level only changes in BUILD, so geometry stays frozen for a whole run.
module game_controller #(parameter integer TICKS_PER_SECOND = 60) (
    input wire clk, reset, launch_req, retry_req, edit_req, guide_open_req, guide_close_req,
    input wire level_next_req,
    input wire build_valid, pig_alive,
    input wire [2:0] init_ready,
    input wire physics_tick, world_valid,
    output wire world_ready,
    input wire gameplay_pending,
    output wire gameplay_ready,
    input wire goal_hit, hazard_hit, out_of_bounds,
    output reg [2:0] game_state,
    output reg [2:0] guide_return_state,
    output reg [`LP_LEVEL_BITS-1:0] level_index,
    output reg [1:0] fail_reason,
    output reg [6:0] run_seconds,
    output wire run_init,
    output reg step_start, update_release, launch_event, success_event, failure_event
);
    reg step_busy;
    reg [6:0] second_ticks;
    wire [`LP_LEVEL_BITS-1:0] next_level = (level_index == `LP_LEVEL_COUNT-1) ? 0 : level_index + 1'b1;
    assign run_init = (game_state == `LP_INIT_RUN);
    assign world_ready = (game_state == `LP_RUN) && step_busy;
    assign gameplay_ready = (game_state == `LP_RUN) && !step_busy;
    always @(posedge clk) begin
        if (reset) begin
            game_state <= `LP_BUILD; guide_return_state <= `LP_BUILD; level_index <= 0; fail_reason <= `LP_FAIL_NONE;
            run_seconds <= 0; second_ticks <= 0;
            step_busy <= 0; step_start <= 0; update_release <= 0;
            launch_event <= 0; success_event <= 0; failure_event <= 0;
        end else begin
            step_start <= 0; update_release <= 0;
            launch_event <= 0; success_event <= 0; failure_event <= 0;
            case (game_state)
                `LP_BUILD: begin
                    step_busy <= 0;
                    if (guide_open_req) begin guide_return_state <= `LP_BUILD; game_state <= `LP_GUIDE; end
                    else if (launch_req && build_valid) game_state <= `LP_INIT_RUN;
                    else if (level_next_req) level_index <= next_level;
                end
                `LP_GUIDE: if (guide_close_req) game_state <= guide_return_state;
                `LP_INIT_RUN: begin
                    step_busy <= 0; fail_reason <= `LP_FAIL_NONE; run_seconds <= 0; second_ticks <= 0;
                    if (&init_ready) begin game_state <= `LP_RUN; launch_event <= 1; end
                end
                `LP_RUN: begin
                    // Whole seconds of RUN, held at 99; results freeze the final time.
                    if (physics_tick) begin
                        if (second_ticks == TICKS_PER_SECOND-1) begin
                            second_ticks <= 0;
                            if (run_seconds != 99) run_seconds <= run_seconds + 1;
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
endmodule
