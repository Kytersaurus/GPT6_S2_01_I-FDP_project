// Pick one new sound, with important events first.
`timescale 1ns / 1ps
`include "game_defs.vh"

module sound_controller (
    input wire clk,
    input wire reset,
    input wire mute,
    input wire cancel,
    input wire launch_event,
    input wire pop_event,
    input wire collision_event,
    input wire explosion_event,
    input wire success_event,
    input wire failure_event,
    input wire busy,
    input wire [2:0] active_sound,
    output wire sound_start,
    output reg [2:0] sound_id
);
    wire [5:0] events = {
        failure_event,
        success_event,
        explosion_event,
        collision_event,
        pop_event,
        launch_event
    };
    reg [5:0] previous_events;
    wire [5:0] fresh_events = events & ~previous_events;

    // Remember held events even while muted, so unmuting cannot replay them.
    always @ (posedge clk) begin
        if (reset) begin
            previous_events <= 0;
        end else begin
            previous_events <= events;
        end
    end

    always @ (*) begin
        sound_id = `LP_SOUND_NONE;
        if (fresh_events[5]) begin
            sound_id = `LP_SOUND_FAILURE;
        end else if (fresh_events[4]) begin
            sound_id = `LP_SOUND_SUCCESS;
        end else if (fresh_events[3]) begin
            sound_id = `LP_SOUND_EXPLOSION;
        end else if (fresh_events[2]) begin
            sound_id = `LP_SOUND_COLLISION;
        end else if (fresh_events[1]) begin
            sound_id = `LP_SOUND_POP;
        end else if (fresh_events[0]) begin
            sound_id = `LP_SOUND_LAUNCH;
        end
    end

    // IDs are in priority order. Equal/lower priority requests are discarded.
    // This is combinational so the player sees the chosen ID on the same edge.
    assign sound_start = !reset && !mute && !cancel && sound_id != `LP_SOUND_NONE &&
                         (!busy || sound_id > active_sound);
endmodule
