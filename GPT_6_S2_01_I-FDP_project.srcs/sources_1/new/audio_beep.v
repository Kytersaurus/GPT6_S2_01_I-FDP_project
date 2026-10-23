// Owner: Role 1 - Kaushal. First speaker test: a short, quiet PWM tone.
`timescale 1ns / 1ps
module audio_beep #(
    parameter integer TONE_HALF_CYCLES = 50000, // 100 MHz / (2 * 50000) = 1 kHz.
    parameter integer BEEP_CYCLES = 20000000   // 0.2 seconds at 100 MHz.
) (
    input wire clk, reset, start, mute,
    output reg busy,
    output wire audio_pwm
);
    reg [31:0] tone_count, duration_count;
    reg tone_high;
    reg [7:0] pwm_count;
    // A constant 50% duty is silence after the amplifier's input filter.
    // Small changes either side of 128 give a quieter first test than full scale.
    wire [7:0] pwm_level = (busy && !mute && !reset) ?
                           (tone_high ? 8'd136 : 8'd120) : 8'd128;
    assign audio_pwm = (pwm_count < pwm_level);

    // This is output data, not a new clock. All registers use the shared clk.
    always @(posedge clk) begin
        if (reset) pwm_count <= 0;
        else pwm_count <= pwm_count + 1'b1;
    end

    always @(posedge clk) begin
        if (reset || mute) begin
            busy <= 0; tone_count <= 0; duration_count <= 0; tone_high <= 0;
        end else if (!busy) begin
            tone_count <= 0; duration_count <= 0; tone_high <= 0;
            // start is a one-clock pulse from the existing button debouncer.
            if (start) busy <= 1;
        end else if (duration_count == BEEP_CYCLES-1) begin
            busy <= 0; tone_count <= 0; duration_count <= 0; tone_high <= 0;
        end else begin
            duration_count <= duration_count + 1'b1;
            if (tone_count == TONE_HALF_CYCLES-1) begin
                tone_count <= 0; tone_high <= !tone_high;
            end else tone_count <= tone_count + 1'b1;
            // Requests received while busy do not restart or queue the test beep.
        end
    end
endmodule
