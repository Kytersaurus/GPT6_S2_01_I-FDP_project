// Owner: Role 1 - Kaushal. Button actions plus the mute and reverse switches.
`timescale 1ns / 1ps
// Button actions and switches; mouse_adapter handles mouse clicks.
module input_controller #(
    parameter integer DEBOUNCE_CYCLES = 20000000,
    parameter integer RELEASE_CYCLES = 2000000
) (
    input wire clk, reset, btnC, btnU, mute_switch, reverse_switch,
    output wire start_press, edit_press, audio_muted, engine_reverse
);
    // The wheel engine is switched on and off only by clicking its cell on
    // the run diagram, and rockets only by clicking their own cells, so neither
    // needs a switch or button here.
    reg mute_meta, mute_sync;
    reg reverse_meta, reverse_sync;
    button_debouncer #(.RELEASE_CYCLES(RELEASE_CYCLES)) u_center (
        .CLOCK(clk), .reset(reset), .btn(btnC),
        .freq_count(DEBOUNCE_CYCLES-1), .btn_pressed(start_press)
    );
    button_debouncer #(.RELEASE_CYCLES(RELEASE_CYCLES)) u_up (
        .CLOCK(clk), .reset(reset), .btn(btnU),
        .freq_count(DEBOUNCE_CYCLES-1), .btn_pressed(edit_press)
    );
    always @(posedge clk) begin
        if (reset) begin
            reverse_meta <= 0; reverse_sync <= 0;
            // Keep the amplifier muted until the switch is sampled after reset.
            mute_meta <= 1; mute_sync <= 1;
        end else begin
            reverse_meta <= reverse_switch; reverse_sync <= reverse_meta;
            mute_meta <= mute_switch; mute_sync <= mute_meta;
        end
    end
    assign engine_reverse = reverse_sync;
    assign audio_muted = mute_sync;
endmodule
