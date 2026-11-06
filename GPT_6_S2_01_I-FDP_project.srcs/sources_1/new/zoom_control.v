// Owner: Role 4 - Marcus. Map zoom from the mouse wheel.
`timescale 1ns / 1ps
// The wheel steps through close (1.5x), normal (1.0x), and overview (0.5x) views,
// saturating at either end. Positive PS/2 deltas step out; negative deltas step in
// (board wheel orientation). The wheel turns the inventory page during BUILD, so the
// top level clears wheel_enabled there. preset_normal selects the middle view so the
// tutorial's zoom lesson always has room to step in and then back out.
module zoom_control (
    input wire clk, reset,
    input tri1 wheel_enabled,
    input tri0 preset_normal,
    input wire mouse_event,
    input wire [3:0] mouse_z,
    output reg zoomed_out,
    output reg overview
);
    always @(posedge clk) begin
        if (reset) begin
            zoomed_out <= 0; overview <= 0;
        end else if (preset_normal) begin
            zoomed_out <= 1; overview <= 0;
        end else if (wheel_enabled && mouse_event && mouse_z != 0) begin
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
endmodule
