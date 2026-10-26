// Owner: Role 4 - Marcus. Map zoom from SW3 and the mouse wheel.
`timescale 1ns / 1ps
// SW3 is a debug shortcut for the normal zoom. The wheel steps through close,
// normal and overview views: towards the user zooms out, away zooms in.
// The PS/2 wheel delta is negative when the wheel turns away from the user.
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
                if (mouse_z[3]) begin
                    if (!zoomed_out) zoomed_out <= 1;
                    else overview <= 1;
                end else begin
                    if (overview) overview <= 0;
                    else zoomed_out <= 0;
                end
            end
        end
    end
endmodule
