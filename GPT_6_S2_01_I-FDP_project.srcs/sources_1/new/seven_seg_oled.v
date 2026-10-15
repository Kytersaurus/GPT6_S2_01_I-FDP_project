// Owner: Role 1 - Kaushal. User-supplied drawing helper used by Role 4.
`timescale 1ns / 1ps

// User-supplied seven-segment number drawing helper.
module seven_seg_oled(
    input [6:0] x, y, pos_x, pos_y,
    input [3:0] number,
    input [6:0] line_thickness,
    input [6:0] height,
    input [6:0] width,
    output reg isDrawn = 0
    );

    wire in_bounds = (x >= pos_x) && (y >= pos_y);
    wire [6:0] rel_x = x - pos_x;
    wire [6:0] rel_y = y - pos_y;
    wire [6:0] half_height = height >> 1;
    wire [6:0] half_thick = line_thickness >> 1;
    wire seg_A, seg_B, seg_C, seg_D, seg_E, seg_F, seg_G;

    assign seg_A = in_bounds && (rel_x >= 0 && rel_x < width) && (rel_y >= 0 && rel_y < line_thickness);
    assign seg_B = in_bounds && (rel_x >= (width-line_thickness) && rel_x < width) && (rel_y >= 0 && rel_y <= half_height);
    assign seg_C = in_bounds && (rel_x >= (width-line_thickness) && rel_x < width) && (rel_y >= half_height && rel_y < height);
    assign seg_D = in_bounds && (rel_x >= 0 && rel_x < width) && (rel_y >= (height-line_thickness) && rel_y < height);
    assign seg_E = in_bounds && (rel_x >= 0 && rel_x < line_thickness) && (rel_y >= half_height && rel_y < height);
    assign seg_F = in_bounds && (rel_x >= 0 && rel_x < line_thickness) && (rel_y >= 0 && rel_y <= half_height);
    assign seg_G = in_bounds && (rel_x >= 0 && rel_x < width) && (half_height >= half_thick) &&
                   (rel_y >= (half_height-half_thick) && rel_y <= (half_height+half_thick));

    always @(*) begin
        case(number)
            0: isDrawn = seg_A | seg_B | seg_C | seg_D | seg_E | seg_F;
            1: isDrawn = seg_B | seg_C;
            2: isDrawn = seg_A | seg_B | seg_D | seg_E | seg_G;
            3: isDrawn = seg_A | seg_B | seg_C | seg_D | seg_G;
            4: isDrawn = seg_B | seg_C | seg_F | seg_G;
            5: isDrawn = seg_A | seg_C | seg_D | seg_F | seg_G;
            6: isDrawn = seg_A | seg_C | seg_D | seg_E | seg_F | seg_G;
            7: isDrawn = seg_A | seg_B | seg_C;
            8: isDrawn = seg_A | seg_B | seg_C | seg_D | seg_E | seg_F | seg_G;
            9: isDrawn = seg_A | seg_B | seg_C | seg_D | seg_F | seg_G;
            default: isDrawn = 1'b0;
        endcase
    end
endmodule
