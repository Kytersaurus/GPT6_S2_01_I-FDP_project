// Owner: Role 1 - Kaushal. User-supplied shared clock helper.
`timescale 1ns / 1ps
// User-supplied divider. Output frequency = CLOCK / (2 * (freq_count + 1)).
// Keep freq_count constant for the OLED clock; the divider runs through reset.
module custom_clk_divider(
    input CLOCK,
    input [31:0] freq_count,
    output reg CUSTOM_CLOCK
    );
    reg [31:0] COUNT = 0;
    initial begin
        CUSTOM_CLOCK = 0;
    end
    always @ (posedge CLOCK) begin
        COUNT <= (COUNT == freq_count) ? 0 : COUNT + 1;
        CUSTOM_CLOCK <= (COUNT == freq_count) ? ~CUSTOM_CLOCK : CUSTOM_CLOCK;
    end

endmodule
