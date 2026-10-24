// Owner: Role 1 - Kaushal. Pick one new sound, with important events first.
`timescale 1ns / 1ps
`include "game_defs.vh"
module sound_controller (
    input wire clk, reset, mute, cancel,
    input wire test_event, launch_event, pop_event, collision_event,
    input wire explosion_event, success_event, failure_event,
    input wire busy,
    input wire [2:0] active_sound,
    output wire sound_start,
    output reg [2:0] sound_id
);
    wire [6:0] events = {failure_event, success_event, explosion_event,
                         collision_event, pop_event, launch_event, test_event};
    reg [6:0] previous_events;
    wire [6:0] fresh_events = events & ~previous_events;

    // Remember held events even while muted, so unmuting cannot replay them.
    always @(posedge clk) begin
        if (reset) previous_events <= 0;
        else previous_events <= events;
    end

    always @* begin
        sound_id = `LP_SOUND_NONE;
        if (fresh_events[6]) sound_id = `LP_SOUND_FAILURE;
        else if (fresh_events[5]) sound_id = `LP_SOUND_SUCCESS;
        else if (fresh_events[4]) sound_id = `LP_SOUND_EXPLOSION;
        else if (fresh_events[3]) sound_id = `LP_SOUND_COLLISION;
        else if (fresh_events[2]) sound_id = `LP_SOUND_POP;
        else if (fresh_events[1]) sound_id = `LP_SOUND_LAUNCH;
        else if (fresh_events[0]) sound_id = `LP_SOUND_TEST;
    end
    // IDs are in priority order. Equal/lower priority requests are discarded.
    // This is combinational so the player sees the chosen ID on the same edge.
    assign sound_start = !reset && !mute && !cancel && sound_id != `LP_SOUND_NONE &&
                         (!busy || sound_id > active_sound);
endmodule
