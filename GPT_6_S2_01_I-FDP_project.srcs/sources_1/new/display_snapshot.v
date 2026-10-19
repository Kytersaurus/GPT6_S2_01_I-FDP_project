// Owner: Role 4 - Marcus. Consistent state for both OLEDs.
`timescale 1ns / 1ps
// Hold the source bus during transfer; publish staged data only at frame start.
module display_snapshot #(parameter integer WIDTH = 123) (
    input wire game_clk, game_reset, display_clk, display_reset, frame_begin,
    input wire [WIDTH-1:0] game_data,
    output reg [WIDTH-1:0] display_data
);
    reg request_toggle, ack_toggle, request_pending, staged_valid;
    reg request_meta, request_sync, ack_meta, ack_sync;
    reg [WIDTH-1:0] held_data, staged_data;
    always @(posedge game_clk) begin
        if (game_reset) begin request_meta <= 0; request_sync <= 0; ack_toggle <= 0; held_data <= 0; end
        else begin
            request_meta <= request_toggle; request_sync <= request_meta;
            if (request_sync != ack_toggle) begin held_data <= game_data; ack_toggle <= request_sync; end
        end
    end
    always @(posedge display_clk) begin
        if (display_reset) begin
            ack_meta <= 0; ack_sync <= 0; request_toggle <= 0; request_pending <= 0;
            staged_valid <= 0; staged_data <= 0; display_data <= 0;
        end else begin
            ack_meta <= ack_toggle; ack_sync <= ack_meta;
            if (!request_pending && !staged_valid) begin request_toggle <= ~request_toggle; request_pending <= 1; end
            if (request_pending && ack_sync == request_toggle) begin
                staged_data <= held_data; staged_valid <= 1; request_pending <= 0;
            end
            if (frame_begin && staged_valid) begin display_data <= staged_data; staged_valid <= 0; end
        end
    end
endmodule
