// Owner: Shared display helpers - Role 1 and Role 4. Include inside a module.
    // Five pixels per row, seven rows from top to bottom. Only used letters are stored.
    function [34:0] letter_pixels;
        input [7:0] character;
        begin
            case (character)
                "A": letter_pixels = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B": letter_pixels = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C": letter_pixels = {5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D": letter_pixels = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": letter_pixels = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F": letter_pixels = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G": letter_pixels = {5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
                "H": letter_pixels = {5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I": letter_pixels = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
                "K": letter_pixels = {5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L": letter_pixels = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": letter_pixels = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N": letter_pixels = {5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
                "O": letter_pixels = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": letter_pixels = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R": letter_pixels = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": letter_pixels = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": letter_pixels = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": letter_pixels = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V": letter_pixels = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W": letter_pixels = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "X": letter_pixels = {5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "Y": letter_pixels = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                "Z": letter_pixels = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
                "J": letter_pixels = {5'b00111,5'b00010,5'b00010,5'b00010,5'b10010,5'b10010,5'b01100};
                "Q": letter_pixels = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
                "0": letter_pixels = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "3": letter_pixels = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4": letter_pixels = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5": letter_pixels = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6": letter_pixels = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7": letter_pixels = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8": letter_pixels = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9": letter_pixels = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "-": letter_pixels = {5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                "?": letter_pixels = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b00000,5'b00100};
                "!": letter_pixels = {5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00000,5'b00100};
                "/": letter_pixels = {5'b00001,5'b00010,5'b00010,5'b00100,5'b01000,5'b01000,5'b10000};
                "1": letter_pixels = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2": letter_pixels = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                default: letter_pixels = 0;
            endcase
        end
    endfunction

    // True where a left-aligned 16-character line starting at (left, top) has a lit pixel.
    function text_on;
        input [127:0] text;
        input integer left, top, pixel_x, pixel_y;
        reg [6:0] relative_x, relative_y;
        reg [4:0] column;
        reg [6:0] row;
        reg [7:0] character;
        reg [34:0] bits;
        begin
            text_on = 0;
            relative_x=pixel_x-left; relative_y=pixel_y-top;
            column = relative_x/6; row = relative_y;
            if (pixel_x >= left && pixel_y >= top && column < 16 && row < 7 && relative_x%6 < 5) begin
                character = text >> ((15-column)*8);
                bits = letter_pixels(character);
                text_on = bits[34-(row*5+relative_x%6)];
            end
        end
    endfunction

