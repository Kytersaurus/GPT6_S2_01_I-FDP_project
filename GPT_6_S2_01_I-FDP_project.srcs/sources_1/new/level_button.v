// Owner: Role 4 - Marcus. Level button click on the left OLED.
`timescale 1ns / 1ps
`include "game_defs.vh"
// Reads the same mouse position as mouse_adapter, so the button needs no change there.
// The button lies outside the grid and inventory, so its clicks never edit the build.
module level_button (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_event,
    output reg level_next_req
);
    reg left_was_down;
    wire on_button = mouse_x >= `LP_LEVEL_BUTTON_X && mouse_x < `LP_LEVEL_BUTTON_X+`LP_LEVEL_BUTTON_W &&
                     mouse_y >= `LP_LEVEL_BUTTON_Y && mouse_y < `LP_LEVEL_BUTTON_Y+`LP_LEVEL_BUTTON_H;
    always @(posedge clk) begin
        if (reset) begin left_was_down <= 0; level_next_req <= 0; end
        else begin
            level_next_req <= 0;
            if (mouse_event) begin
                left_was_down <= mouse_left;
                // One request per fresh press; holding the button does not repeat.
                if (mouse_left && !left_was_down && on_button && game_state == `LP_BUILD) level_next_req <= 1;
            end
        end
    end
endmodule
