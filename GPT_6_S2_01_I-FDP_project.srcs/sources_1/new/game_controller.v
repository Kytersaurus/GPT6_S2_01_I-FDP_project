// Owner: Role 4 - Marcus. Game states and update sequencing.
`timescale 1ns / 1ps
`include "game_defs.vh"
module game_controller (
    input wire clk, reset, launch_req, retry_req, edit_req, guide_open_req, guide_close_req,
    input wire build_valid, pig_alive,
    input wire [2:0] init_ready,
    input wire physics_tick, world_valid,
    output wire world_ready,
    input wire gameplay_pending,
    output wire gameplay_ready,
    input wire goal_hit, hazard_hit, out_of_bounds,
    output reg [2:0] game_state,
    output wire run_init,
    output reg step_start, update_release, launch_event, success_event, failure_event
);
    reg step_busy;
    assign run_init = (game_state == `LP_INIT_RUN);
    assign world_ready = (game_state == `LP_RUN) && step_busy;
    assign gameplay_ready = (game_state == `LP_RUN) && !step_busy;
    always @(posedge clk) begin
        if (reset) begin
            game_state <= `LP_BUILD; step_busy <= 0; step_start <= 0; update_release <= 0;
            launch_event <= 0; success_event <= 0; failure_event <= 0;
        end else begin
            step_start <= 0; update_release <= 0;
            launch_event <= 0; success_event <= 0; failure_event <= 0;
            case (game_state)
                `LP_BUILD: begin
                    step_busy <= 0;
                    if (guide_open_req) game_state <= `LP_GUIDE;
                    else if (launch_req && build_valid) game_state <= `LP_INIT_RUN;
                end
                `LP_GUIDE: if (guide_close_req) game_state <= `LP_BUILD;
                `LP_INIT_RUN: begin
                    step_busy <= 0;
                    if (&init_ready) begin game_state <= `LP_RUN; launch_event <= 1; end
                end
                `LP_RUN: begin
                    if (world_valid && world_ready) begin
                        step_busy <= 0; update_release <= 1;
                        if (!pig_alive || hazard_hit || out_of_bounds) begin
                            game_state <= `LP_FAIL; failure_event <= 1;
                        end else if (goal_hit) begin game_state <= `LP_SUCCESS; success_event <= 1; end
                    end else if (physics_tick && !step_busy && !gameplay_pending) begin
                        step_start <= 1; step_busy <= 1;
                    end
                end
                `LP_SUCCESS, `LP_FAIL: begin
                    step_busy <= 0;
                    if (edit_req) game_state <= `LP_BUILD;
                    else if (retry_req) game_state <= `LP_INIT_RUN;
                end
                default: begin game_state <= `LP_BUILD; step_busy <= 0; end
            endcase
        end
    end
endmodule
