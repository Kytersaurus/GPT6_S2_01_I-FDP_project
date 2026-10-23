// Owner: Role 1 - Kaushal. Mouse configuration, construction and gameplay clicks.
`timescale 1ns / 1ps
`include "game_defs.vh"
module mouse_adapter (
    input wire clk, reset,
    input wire [2:0] game_state,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_right, mouse_event,
    output reg [11:0] mouse_value,
    output reg setx, sety, setmax_x, setmax_y,
    output reg [6:0] cursor_x, cursor_y,
    output reg [2:0] selected_part,
    output wire drag_active,
    output reg edit_valid,
    output reg [1:0] edit_op,
    output reg [3:0] edit_cell,
    output reg [2:0] edit_part,
    output reg pop_req,
    output reg [3:0] pop_cell
);
    reg [1:0] setup_step;
    reg left_was_down, right_was_down;
    reg place_pending;
    assign drag_active = place_pending && game_state == `LP_BUILD;
    wire in_grid = mouse_x >= 4 && mouse_x < 52 && mouse_y >= 4 && mouse_y < 52;
    wire in_inventory = mouse_x >= 56 && mouse_x < 92 && mouse_y >= 4 && mouse_y < 54;
    // Used only when in_grid is true, for placement, removal and balloon clicks.
    wire [3:0] hovered_cell = ((mouse_y-4)/16)*3 + (mouse_x-4)/16;

    // Configure the supplied driver for the left OLED, then place the cursor over the grid.
    always @* begin
        mouse_value = 0; setx = 0; sety = 0; setmax_x = 0; setmax_y = 0;
        case (setup_step)
            0: begin mouse_value = 95; setmax_x = 1; end
            1: begin mouse_value = 63; setmax_y = 1; end
            2: begin mouse_value = 24; setx = 1; sety = 1; end
            default: begin end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            setup_step <= 0; left_was_down <= 0; right_was_down <= 0;
            place_pending <= 0;
            cursor_x <= 24; cursor_y <= 24; selected_part <= `LP_PART_FRAME;
            edit_valid <= 0; edit_op <= `LP_EDIT_PLACE; edit_cell <= 0; edit_part <= `LP_PART_FRAME;
            pop_req <= 0; pop_cell <= 0;
        end else begin
            edit_valid <= 0; pop_req <= 0;
            // Leaving construction cancels a drag, even if no mouse packet arrives.
            if (game_state != `LP_BUILD) place_pending <= 0;
            if (setup_step != 3) setup_step <= setup_step + 1'b1;
            else if (mouse_event) begin
                // Read buttons only after a complete packet, when its position is ready.
                cursor_x <= (mouse_x > 95) ? 95 : mouse_x[6:0];
                cursor_y <= (mouse_y > 63) ? 63 : mouse_y[6:0];
                left_was_down <= mouse_left; right_was_down <= mouse_right;
                if (game_state == `LP_BUILD) begin
                    if (mouse_right) begin
                        // Right-click cancels placement and removes only once per press.
                        place_pending <= 0;
                        if (!right_was_down && in_grid) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_REMOVE;
                            edit_cell <= hovered_cell;
                            edit_part <= `LP_PART_EMPTY;
                        end
                    end else if (mouse_left && !left_was_down) begin
                        // Start a placement in the inventory or grid; wait for release.
                        place_pending <= in_inventory || in_grid;
                        // Select only on the initial press, not while dragging past rows.
                        if (in_inventory) begin
                            // Five fixed row boundaries avoid a hardware divide by ten.
                            if (mouse_y < 14) selected_part <= `LP_PART_FRAME;
                            else if (mouse_y < 24) selected_part <= `LP_PART_PIG;
                            else if (mouse_y < 34) selected_part <= `LP_PART_WHEEL;
                            else if (mouse_y < 44) selected_part <= `LP_PART_ENGINE;
                            else selected_part <= `LP_PART_BALLOON;
                        end
                    end else if (!mouse_left && left_was_down) begin
                        place_pending <= 0;
                        // One drop at the release position; outside the grid cancels it.
                        if (place_pending && in_grid) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_PLACE;
                            edit_cell <= hovered_cell;
                            edit_part <= selected_part;
                        end
                    end
                end else if (game_state == `LP_RUN && mouse_left && !left_was_down &&
                             !mouse_right && in_grid) begin
                    // Gameplay uses one fresh press, rather than construction's drop.
                    pop_req <= 1;
                    pop_cell <= hovered_cell;
                end
            end
        end
    end
endmodule
