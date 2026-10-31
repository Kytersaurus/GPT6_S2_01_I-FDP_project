// Owner: Role 1 - Kaushal. Basys3 active-low four-digit timer, shown as M.SS.
`timescale 1ns / 1ps
module seven_seg_timer #(
    parameter integer SCAN_CYCLES = 100000,
    parameter COUNTDOWN = 0,
    parameter integer TIME_LIMIT = 20
) (
    input wire clk, reset,
    input wire [7:0] seconds,
    output reg [6:0] seg,
    output reg [3:0] an,
    output reg dp
);
    reg [16:0] scan_count;
    reg [1:0] digit;
    reg [3:0] number;

    wire is_negative = COUNTDOWN ? (seconds > TIME_LIMIT) : 1'b0;
    wire [7:0] abs_seconds = COUNTDOWN ? (is_negative ? (seconds - TIME_LIMIT) : (TIME_LIMIT - seconds)) : seconds;

    reg [3:0] minutes;
    reg [3:0] sec_tens;
    reg [3:0] sec_ones;
    reg [8:0] temp_sec;
    
    always @* begin
        if (abs_seconds >= 240) begin minutes = 4; temp_sec = abs_seconds - 240; end
        else if (abs_seconds >= 180) begin minutes = 3; temp_sec = abs_seconds - 180; end
        else if (abs_seconds >= 120) begin minutes = 2; temp_sec = abs_seconds - 120; end
        else if (abs_seconds >= 60) begin minutes = 1; temp_sec = abs_seconds - 60; end
        else begin minutes = 0; temp_sec = abs_seconds; end
        
        if (temp_sec >= 50) begin sec_tens = 5; sec_ones = temp_sec - 50; end
        else if (temp_sec >= 40) begin sec_tens = 4; sec_ones = temp_sec - 40; end
        else if (temp_sec >= 30) begin sec_tens = 3; sec_ones = temp_sec - 30; end
        else if (temp_sec >= 20) begin sec_tens = 2; sec_ones = temp_sec - 20; end
        else if (temp_sec >= 10) begin sec_tens = 1; sec_ones = temp_sec - 10; end
        else begin sec_tens = 0; sec_ones = temp_sec[3:0]; end
    end

    always @(posedge clk) begin
        if (reset) begin scan_count <= 0; digit <= 0; end
        else if (scan_count == SCAN_CYCLES - 1) begin scan_count <= 0; digit <= digit + 1; end
        else scan_count <= scan_count + 1;
    end

    always @* begin
        an = 4'b1111; dp = 1; number = 0;
        case (digit)
            0: begin an = 4'b1110; number = sec_ones; end
            1: begin an = 4'b1101; number = sec_tens; end
            2: if (minutes!=0) begin an = 4'b1011; number = minutes; dp = 0; end
            3: if (is_negative) begin an = 4'b0111; number = 4'd10; end
        endcase
        case (number)
            0: seg = 7'b1000000; 1: seg = 7'b1111001;
            2: seg = 7'b0100100; 3: seg = 7'b0110000;
            4: seg = 7'b0011001; 5: seg = 7'b0010010;
            6: seg = 7'b0000010; 7: seg = 7'b1111000;
            8: seg = 7'b0000000; 9: seg = 7'b0010000;
            10: seg = 7'b0111111; default: seg = 7'b1111111;
        endcase
        if (reset) begin an = 4'b1111; seg = 7'b1111111; dp = 1; end
    end
endmodule
