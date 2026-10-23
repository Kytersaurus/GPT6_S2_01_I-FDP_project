// Owner: Role 2 - Kyle. Clocked signed force/mass division.
`timescale 1ns / 1ps

// Pulse start only while busy is low. Inputs are captured on that edge.
// A nonzero divisor takes 16 calculation clocks; done pulses for one clock.
// Quotient truncates toward zero and remainder has the dividend's sign.
module signed_divider16 (
    input wire clk, reset, start,
    input wire signed [15:0] dividend,
    input wire [7:0] divisor,
    output reg busy, done, divide_by_zero,
    output reg signed [15:0] quotient, remainder
);
    reg [15:0] quotient_work;
    reg [7:0] remainder_work, divisor_work;
    reg result_negative;
    reg [4:0] bits_left;
    wire [8:0] trial_remainder, next_remainder;
    wire subtract_divisor;
    wire [15:0] next_quotient;

    // Bring down one dividend bit and subtract the divisor if it fits.
    assign trial_remainder = {remainder_work, quotient_work[15]};
    assign subtract_divisor = trial_remainder >= {1'b0, divisor_work};
    assign next_remainder = subtract_divisor
        ? trial_remainder - {1'b0, divisor_work} : trial_remainder;
    assign next_quotient = {quotient_work[14:0], subtract_divisor};

    always @(posedge clk) begin
        if (reset) begin
            busy <= 0; done <= 0; divide_by_zero <= 0;
            quotient <= 0; remainder <= 0;
            quotient_work <= 0; remainder_work <= 0; divisor_work <= 0;
            result_negative <= 0; bits_left <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                divide_by_zero <= (divisor == 0);
                if (divisor == 0) begin
                    quotient <= 0; remainder <= 0; busy <= 0; done <= 1;
                end else begin
                    quotient_work <= dividend[15]
                        ? (~dividend) + 16'd1 : dividend;
                    remainder_work <= 0;
                    divisor_work <= divisor;
                    result_negative <= dividend[15];
                    bits_left <= 5'd16;
                    busy <= 1;
                end
            end else if (busy) begin
                quotient_work <= next_quotient;
                remainder_work <= next_remainder[7:0];
                bits_left <= bits_left - 1'b1;
                if (bits_left == 1) begin
                    if (result_negative) begin
                        quotient <= (~next_quotient) + 16'd1;
                        remainder <= (~{8'd0, next_remainder[7:0]}) + 16'd1;
                    end else begin
                        quotient <= next_quotient;
                        remainder <= {8'd0, next_remainder[7:0]};
                    end
                    busy <= 0;
                    done <= 1;
                end
            end
        end
    end
endmodule
