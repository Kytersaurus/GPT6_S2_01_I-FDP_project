`timescale 1ns / 1ps

// User-supplied rectangle drawing helper.
module square (
    input [6:0] width_x,
    input [6:0] length_y,
    input [6:0] x,
    input [6:0] y,
    input [6:0] pos_x,
    input [6:0] pos_y,
    output reg is_in_square = 0
);
    wire in_bounds = (x >= pos_x) && (y >= pos_y);
    wire [6:0] rel_x = x - pos_x;
    wire [6:0] rel_y = y - pos_y;
    wire x_val;
    wire y_val;

    assign x_val = in_bounds && rel_x < width_x;
    assign y_val = in_bounds && rel_y < length_y;

    always @ (*) begin
        is_in_square = x_val && y_val;
    end
endmodule
