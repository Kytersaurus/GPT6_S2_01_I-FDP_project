// Owner: Shared clock/reset support - Role 1 (Kaushal) maintains this starter.
`timescale 1ns / 1ps
module clock_control #(parameter integer PHYSICS_CYCLES = 1666667) (
    input wire clk, reset_button,
    output wire reset, oled_clk, oled_reset,
    output reg physics_tick
);
    reg [7:0] power_on_count = 0;
    // Sample the reset button twice before using it in the game logic.
    reg reset_meta = 1, reset_sync = 1;
    // Count main-clock cycles, using a straightforward fixed-width counter.
    reg [31:0] tick_count;
    reg [1:0] display_reset_pipe = 2'b11;
    assign reset = (power_on_count != 8'hff) || reset_sync;
    custom_clk_divider u_oled_divider (
        .CLOCK(clk), .freq_count(32'd7), .CUSTOM_CLOCK(oled_clk)
    );
    always @(posedge clk) begin
        reset_meta <= reset_button; reset_sync <= reset_meta;
        if (power_on_count != 8'hff) power_on_count <= power_on_count + 1'b1;
        if (reset) begin tick_count <= 0; physics_tick <= 0; end
        else if (tick_count == PHYSICS_CYCLES-1) begin tick_count <= 0; physics_tick <= 1; end
        else begin tick_count <= tick_count + 1'b1; physics_tick <= 0; end
    end
    always @(posedge oled_clk or posedge reset) begin
        if (reset) display_reset_pipe <= 2'b11;
        else display_reset_pipe <= {display_reset_pipe[0], 1'b0};
    end
    assign oled_reset = display_reset_pipe[1];
endmodule
