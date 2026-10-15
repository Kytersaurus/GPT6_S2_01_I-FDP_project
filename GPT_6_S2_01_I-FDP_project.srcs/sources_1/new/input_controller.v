`timescale 1ns / 1ps
// Role 1 starter: button actions; a future mouse adapter can share these actions.
module input_controller #(
    parameter integer DEBOUNCE_CYCLES = 20000000,
    parameter integer RELEASE_CYCLES = 2000000
) (
    input wire clk, reset, btnC, btnU, engine_switch,
    output wire start_press, edit_press, engine_enabled
);
    reg engine_meta, engine_sync;
    button_debouncer #(.RELEASE_CYCLES(RELEASE_CYCLES)) u_center (
        .CLOCK(clk), .reset(reset), .btn(btnC),
        .freq_count(DEBOUNCE_CYCLES-1), .btn_pressed(start_press)
    );
    button_debouncer #(.RELEASE_CYCLES(RELEASE_CYCLES)) u_up (
        .CLOCK(clk), .reset(reset), .btn(btnU),
        .freq_count(DEBOUNCE_CYCLES-1), .btn_pressed(edit_press)
    );
    always @(posedge clk) begin
        if (reset) begin engine_meta <= 0; engine_sync <= 0; end
        else begin engine_meta <= engine_switch; engine_sync <= engine_meta; end
    end
    assign engine_enabled = engine_sync;
endmodule
