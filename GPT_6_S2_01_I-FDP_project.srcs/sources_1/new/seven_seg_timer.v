// Owner: Role 1 - Kaushal. Basys3 active-low four-digit timer, shown as MM.SS.
`timescale 1ns / 1ps
module seven_seg_timer #(parameter integer SCAN_CYCLES=100000) (
    input wire clk, reset,
    input wire [6:0] seconds,
    output reg [6:0] seg,
    output reg [3:0] an,
    output reg dp
);
    reg [16:0] scan_count;
    reg [1:0] digit;
    reg [3:0] number;
    wire [6:0] remaining_seconds = seconds>=60 ? seconds-7'd60 : seconds;
    always @(posedge clk) begin
        if (reset) begin scan_count<=0; digit<=0; end
        else if (scan_count==SCAN_CYCLES-1) begin scan_count<=0; digit<=digit+1; end
        else scan_count<=scan_count+1;
    end
    always @* begin
        an=4'b1111; dp=1; number=0;
        case (digit)
            0: begin an=4'b1110; number=remaining_seconds%10; end
            1: begin an=4'b1101; number=remaining_seconds/10; end
            2: begin an=4'b1011; number=seconds>=60 ? 1 : 0; dp=0; end
            3: begin an=4'b0111; number=0; end
        endcase
        case (number)
            0: seg=7'b1000000; 1: seg=7'b1111001;
            2: seg=7'b0100100; 3: seg=7'b0110000;
            4: seg=7'b0011001; 5: seg=7'b0010010;
            6: seg=7'b0000010; 7: seg=7'b1111000;
            8: seg=7'b0000000; 9: seg=7'b0010000;
            default: seg=7'b1111111;
        endcase
        if (reset) begin an=4'b1111; seg=7'b1111111; dp=1; end
    end
endmodule
