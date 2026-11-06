// Owner: Role 4 - Marcus. Map zoom from SW14 and the mouse wheel.
`timescale 1ns / 1ps
// SW14 toggles between close (1.5x) and normal (1.0x) zoom. The wheel steps through close (1.5x),
// normal (1.0x), and overview (0.5x) views, saturating at either end.
// Positive PS/2 deltas step out; negative deltas step in (board wheel orientation).
module zoom_control (
    input wire clk, reset,
    input wire zoom_switch,
    input wire mouse_event,
    input wire [3:0] mouse_z,
    output reg zoomed_out,
    output reg overview
);
    reg switch_meta, switch_sync, switch_last;
    always @(posedge clk) begin
        if (reset) begin
            switch_meta <= 0; switch_sync <= 0; switch_last <= 0;
            zoomed_out <= 0; overview <= 0;
        end else begin
            switch_meta <= zoom_switch; switch_sync <= switch_meta; switch_last <= switch_sync;
            if (switch_sync != switch_last) begin
                zoomed_out <= switch_sync;
                overview <= 0;
            end else if (mouse_event && mouse_z != 0) begin
                if (!mouse_z[3]) begin
                    // Step out: 00 (close) -> 01 (normal) -> 10 (overview)
                    if (!overview && !zoomed_out) begin
                        zoomed_out <= 1;
                        overview <= 0;
                    end else if (!overview && zoomed_out) begin
                        zoomed_out <= 0;
                        overview <= 1;
                    end
                end else begin
                    // Step in: 10 (overview) -> 01 (normal) -> 00 (close)
                    if (overview) begin
                        zoomed_out <= 1;
                        overview <= 0;
                    end else if (zoomed_out) begin
                        zoomed_out <= 0;
                        overview <= 0;
                    end
                end
            end
        end
    end
endmodule
