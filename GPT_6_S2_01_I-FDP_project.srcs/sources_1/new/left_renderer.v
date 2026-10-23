// Owner: Role 4 - Marcus. Left OLED construction/status drawing.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Build view: grid, inventory icons/counts, selection, cursor and dragged part.
// Run view: grid, status bars and surviving-part count.
module left_renderer #(parameter EDITOR_CELL_PIXELS = 16) (
    input wire [12:0] pixel_index,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    input wire build_valid,
    input wire [3:0] build_error,
    input wire [2:0] feedback_code,
    input wire [3:0] feedback_cell,
    input wire engine_enabled,
    input wire [3:0] frames_left, pigs_left, wheels_left, engines_left, balloons_left,
    input wire [2:0] selected_part,
    input wire drag_active,
    input wire [6:0] cursor_x, cursor_y,
    input wire cursor_visible,
    output reg [15:0] pixel_data
);
    wire [6:0] x = pixel_index % 96;
    wire [6:0] y = pixel_index / 96;
    wire [6:0] grid_size = EDITOR_CELL_PIXELS * 3;
    wire grid_pixel, valid_pixel, engine_pixel, number_pixel, tens_pixel;
    wire inventory_number_pixel;
    reg [6:0] inventory_top;
    // Keep the 8 by 8 preview beside the cursor and fully on the OLED.
    wire [6:0] drag_left = (cursor_x > 84) ? 7'd88 : cursor_x + 7'd3;
    wire [6:0] drag_top = (cursor_y > 52) ? 7'd56 : cursor_y + 7'd3;
    reg [3:0] inventory_number;
    reg [2:0] inventory_part;
    reg [4:0] remaining_parts;
    wire [3:0] ones = remaining_parts % 10;
    wire [3:0] tens = remaining_parts / 10;
    integer index, cell_index, cell_x, cell_y;
    reg [2:0] part;
    reg [127:0] message;
    reg [15:0] message_colour;
    reg [7:0] letter;
    reg [34:0] letter_bits;
    integer text_column, text_row;

    // One icon definition for both inventory and dragging.
    // Transparent pixels keep the colour already drawn underneath.
    function [15:0] draw_part_icon;
        input [2:0] icon_part;
        input integer icon_x, icon_y;
        input [15:0] background;
        begin
            draw_part_icon = background;
            if (icon_x >= 0 && icon_x < 8 && icon_y >= 0 && icon_y < 8) begin
                case (icon_part)
                    `LP_PART_FRAME:
                        if (icon_x == 0 || icon_x == 7 || icon_y == 0 || icon_y == 7) draw_part_icon = 16'ha285;
                    `LP_PART_PIG: begin
                        draw_part_icon = 16'h07e0;
                        if (icon_y == 2 && (icon_x == 2 || icon_x == 5)) draw_part_icon = 16'h0000;
                    end
                    `LP_PART_WHEEL:
                        if (icon_x == 0 || icon_x == 7 || icon_y == 0 || icon_y == 7) draw_part_icon = 16'hffff;
                    `LP_PART_ENGINE: begin
                        draw_part_icon = 16'hf800;
                        if (icon_x >= 2 && icon_x < 6 && icon_y >= 3 && icon_y < 5) draw_part_icon = 16'hffe0;
                    end
                    `LP_PART_BALLOON: begin
                        if (icon_y < 6 && icon_x >= 1 && icon_x < 7) draw_part_icon = 16'hf81f;
                        if (icon_y >= 6 && icon_x == 3) draw_part_icon = 16'hffff;
                    end
                    default: begin end
                endcase
            end
        end
    endfunction

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
                "Y": letter_pixels = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                default: letter_pixels = 0;
            endcase
        end
    endfunction

    always @* begin
        message_colour = 16'hf800;
        case (feedback_code)
            `LP_FEEDBACK_PLACED: begin message = "PLACED          "; message_colour = 16'h07e0; end
            `LP_FEEDBACK_REMOVED: begin message = "REMOVED         "; message_colour = 16'h07e0; end
            `LP_FEEDBACK_NO_STOCK: message = "NO STOCK        ";
            `LP_FEEDBACK_NEED_FRAME: message = "NEED FRAME      ";
            `LP_FEEDBACK_FRAME_ABOVE: message = "FRAME ABOVE     ";
            `LP_FEEDBACK_FRAME_BELOW: message = "FRAME BELOW     ";
            `LP_FEEDBACK_OCCUPIED: message = "CELL OCCUPIED   ";
            default: begin
                if (build_valid) begin message = "READY           "; message_colour = 16'h07e0; end
                else case (build_error)
                    `LP_BUILD_ERR_PIG: message = "ADD PIG         ";
                    `LP_BUILD_ERR_INVENTORY: message = "CHECK STOCK     ";
                    default: message = "CHECK SUPPORT   ";
                endcase
            end
        endcase
        // Six pixels per character: five drawing columns, then a blank column.
        letter = message >> ((15-x/6)*8);
        letter_bits = letter_pixels(letter);
        text_column = x%6; text_row = y-56;
    end

    square u_grid_box (
        .x(x), .y(y), .pos_x(7'd4), .pos_y(7'd4),
        .width_x(grid_size), .length_y(grid_size), .is_in_square(grid_pixel)
    );
    square u_valid_box (
        .x(x), .y(y), .pos_x(7'd56), .pos_y(7'd6),
        .width_x(7'd36), .length_y(7'd8), .is_in_square(valid_pixel)
    );
    square u_engine_box (
        .x(x), .y(y), .pos_x(7'd56), .pos_y(7'd20),
        .width_x(7'd36), .length_y(7'd8), .is_in_square(engine_pixel)
    );
    seven_seg_oled u_part_count (
        .x(x), .y(y), .pos_x(7'd68), .pos_y(7'd36), .number(ones),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(number_pixel)
    );
    seven_seg_oled u_part_count_tens (
        .x(x), .y(y), .pos_x(7'd56), .pos_y(7'd36), .number(tens),
        .line_thickness(7'd2), .height(7'd20), .width(7'd10), .isDrawn(tens_pixel)
    );
    seven_seg_oled u_inventory_number (
        .x(x), .y(y), .pos_x(7'd82), .pos_y(inventory_top+7'd1), .number(inventory_number),
        .line_thickness(7'd1), .height(7'd8), .width(7'd5), .isDrawn(inventory_number_pixel)
    );
    always @* begin
        // Fixed row boundaries avoid dividing and multiplying the pixel position by ten.
        inventory_number = frames_left; inventory_part = `LP_PART_FRAME; inventory_top = 4;
        if (y >= 14 && y < 24) begin
            inventory_number = pigs_left; inventory_part = `LP_PART_PIG; inventory_top = 14;
        end else if (y >= 24 && y < 34) begin
            inventory_number = wheels_left; inventory_part = `LP_PART_WHEEL; inventory_top = 24;
        end else if (y >= 34 && y < 44) begin
            inventory_number = engines_left; inventory_part = `LP_PART_ENGINE; inventory_top = 34;
        end else if (y >= 44 && y < 54) begin
            inventory_number = balloons_left; inventory_part = `LP_PART_BALLOON; inventory_top = 44;
        end
    end

    always @* begin
        remaining_parts = 0;
        for (index = 0; index < 9; index = index + 1) begin
            if (intact_mask[index]) remaining_parts = remaining_parts + 1'b1;
            if (frame_intact_mask[index]) remaining_parts = remaining_parts + 1'b1;
        end
    end

    always @* begin
        cell_index = 0; cell_x = 0; cell_y = 0;
        part = 0;
        pixel_data = 16'h0841;
        if (grid_pixel) begin
            cell_index = ((y-4)/EDITOR_CELL_PIXELS)*3 + (x-4)/EDITOR_CELL_PIXELS;
            cell_x = (x-4)%EDITOR_CELL_PIXELS;
            cell_y = (y-4)%EDITOR_CELL_PIXELS;
            // Shift the selected cell's three bits into the bottom of the vector.
            part = build_grid >> (cell_index*3);
            if (cell_x == 0 || cell_y == 0 || x == 4+grid_size-1 || y == 4+grid_size-1) pixel_data = 16'h7bef;
            else begin
                // Draw the frame border, then its contents in the centre.
                if (frame_intact_mask[cell_index] &&
                    (cell_x < 3 || cell_x >= EDITOR_CELL_PIXELS-2 ||
                     cell_y < 3 || cell_y >= EDITOR_CELL_PIXELS-2)) pixel_data = 16'ha285;
                if (intact_mask[cell_index] && cell_x >= 3 && cell_x < EDITOR_CELL_PIXELS-2 &&
                    cell_y >= 3 && cell_y < EDITOR_CELL_PIXELS-2) case (part)
                    `LP_PART_PIG: pixel_data = 16'h07e0;
                    `LP_PART_WHEEL: pixel_data = 16'hffff;
                    `LP_PART_ENGINE: pixel_data = 16'hf800;
                    `LP_PART_BALLOON: pixel_data = 16'hf81f;
                    default: begin end
                endcase
            end
            if (feedback_code != `LP_FEEDBACK_NONE && feedback_cell < 9 &&
                cell_index == feedback_cell &&
                (cell_x == 0 || cell_y == 0 || cell_x == EDITOR_CELL_PIXELS-1 || cell_y == EDITOR_CELL_PIXELS-1) &&
                game_state == `LP_BUILD) pixel_data = message_colour;
        end
        if (game_state != `LP_BUILD) begin
            if (valid_pixel) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
            if (engine_pixel) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
            if (build_error != 0 && x >= 56 && x < 92 && y >= 30 && y < 34) pixel_data = 16'hf800;
            if (number_pixel || (remaining_parts >= 10 && tens_pixel)) pixel_data = 16'hffff;
        end else if (x >= 56 && x < 92 && y >= 4 && y < 54) begin
            pixel_data = 16'h18c3;
            if (selected_part == inventory_part &&
                (x == 56 || x == 91 || y == inventory_top || y == inventory_top+9)) pixel_data = 16'hffe0;
            pixel_data = draw_part_icon(inventory_part, x-60, y-inventory_top-1, pixel_data);
            if (inventory_number_pixel) pixel_data = (inventory_number == 0) ? 16'hf800 : 16'hffff;
        end
        if (game_state == `LP_BUILD) begin
            if (y >= 56 && y < 63) begin
                pixel_data = 16'h0841;
                if (text_column < 5 && letter_bits[34-(text_row*5+text_column)]) pixel_data = message_colour;
            end
        end else begin
            // Runtime indicators: build validity, engine switch, then game stage.
            if (y >= 57 && y < 63 && x >= 4 && x < 16) pixel_data = build_valid ? 16'h07e0 : 16'hf800;
            if (y >= 57 && y < 63 && x >= 20 && x < 32) pixel_data = engine_enabled ? 16'hffe0 : 16'h4208;
            if (y >= 58 && y < 62 && x >= 36 && x < 36+game_state*6) pixel_data = 16'h07ff;
        end
        // Draw a temporary copy above the interface; the builder changes only on release.
        if (game_state == `LP_BUILD && cursor_visible && drag_active)
            pixel_data = draw_part_icon(selected_part, x-drag_left, y-drag_top, pixel_data);
        if (cursor_visible && (game_state == `LP_BUILD || game_state == `LP_RUN) &&
            ((x == cursor_x && y+2 >= cursor_y && y <= cursor_y+2) ||
             (y == cursor_y && x+2 >= cursor_x && x <= cursor_x+2))) pixel_data = 16'hffff;
    end
endmodule
