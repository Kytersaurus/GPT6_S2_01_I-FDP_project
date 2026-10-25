// Owner: Role 4 - Marcus. Map zoom from SW3 and the mouse wheel.
`timescale 1ns / 1ps
// Flipping SW3 sets the zoom to match it (up = zoomed out). A wheel step then
// overrides it until the next flip: towards the user zooms out, away zooms in.
// The PS/2 wheel delta is negative when the wheel turns away from the user.
module zoom_control (
    input wire clk, reset,
    input wire zoom_switch,
    input wire mouse_event,
    input wire [3:0] mouse_z,
    output reg zoomed_out
);
    reg switch_meta, switch_sync, switch_last;
    always @(posedge clk) begin
        if (reset) begin
            switch_meta <= 0; switch_sync <= 0; switch_last <= 0; zoomed_out <= 0;
        end else begin
            switch_meta <= zoom_switch; switch_sync <= switch_meta; switch_last <= switch_sync;
            if (switch_sync != switch_last) zoomed_out <= switch_sync;
            else if (mouse_event && mouse_z != 0) zoomed_out <= !mouse_z[3];
        end
    end
endmodule
