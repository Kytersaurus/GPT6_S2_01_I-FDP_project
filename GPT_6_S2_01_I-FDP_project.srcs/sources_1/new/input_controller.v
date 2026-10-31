// Owner: Role 1 - Kaushal. Button actions, engine switch and audio mute.
`timescale 1ns / 1ps
// Button actions and switches; mouse_adapter handles mouse clicks.
module input_controller #(
    parameter integer DEBOUNCE_CYCLES = 20000000,
    parameter integer RELEASE_CYCLES = 2000000
) (
    input wire clk, reset, btnC, btnU, btnL, btnR, engine_switch, mute_switch, reverse_switch,
    output wire start_press, edit_press, right_press, audio_muted, engine_reverse, jump_press,
    output reg engine_switch_changed
);
    reg engine_meta, engine_sync;
    reg engine_previous;
    reg [2:0] engine_startup;
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
    button_debouncer #(.RELEASE_CYCLES(RELEASE_CYCLES)) u_left (
        .CLOCK(clk), .reset(reset), .btn(btnL),
        .freq_count(DEBOUNCE_CYCLES-1), .btn_pressed(jump_press)
    );
    button_debouncer #(.RELEASE_CYCLES(RELEASE_CYCLES)) u_right (
        .CLOCK(clk), .reset(reset), .btn(btnR),
        .freq_count(DEBOUNCE_CYCLES-1), .btn_pressed(right_press)
    );
    always @(posedge clk) begin
        if (reset) begin
            engine_meta <= 0; engine_sync <= 0; engine_previous <= 0; engine_startup <= 0;
            engine_switch_changed <= 0;
            reverse_meta <= 0; reverse_sync <= 0;
            // Keep the amplifier muted until the switch is sampled after reset.
            mute_meta <= 1; mute_sync <= 1;
        end else begin
            engine_meta <= engine_switch; engine_sync <= engine_meta;
            engine_startup <= {engine_startup[1:0], 1'b1};
            if (engine_startup == 3'b111) begin
                engine_switch_changed <= engine_sync != engine_previous;
                engine_previous <= engine_sync;
            end else begin
                engine_switch_changed <= 0;
                engine_previous <= engine_sync;
            end
            reverse_meta <= reverse_switch; reverse_sync <= reverse_meta;
            mute_meta <= mute_switch; mute_sync <= mute_meta;
        end
    end
    assign engine_reverse = reverse_sync;
    assign audio_muted = mute_sync;
endmodule
