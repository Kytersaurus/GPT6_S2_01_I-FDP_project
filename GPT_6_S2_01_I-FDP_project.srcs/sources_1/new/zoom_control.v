// Owner: Role 4 - Marcus. Map zoom from SW3 and the mouse wheel.
`timescale 1ns / 1ps
// SW3 is a debug shortcut for the normal zoom. The wheel steps through close,
// normal, overview and wide overview views, saturating at either end.
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
                    if (!overview) begin
                        if (!zoomed_out) zoomed_out<=1;
                        else overview<=1;
                    end else zoomed_out<=0; // Fourth view: 192 x 128, four-pixel cells.
                end else begin
                    if (overview) begin
                        if (!zoomed_out) zoomed_out<=1;
                        else overview<=0;
                    end else zoomed_out<=0;
                end
            end
        end
    end
endmodule
