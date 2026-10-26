// Owner: Role 1 - Kaushal. Mouse configuration, construction and gameplay clicks.
`timescale 1ns / 1ps
`include "game_defs.vh"
module mouse_adapter (
    input wire clk, reset, input_enabled,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] build_frames, build_facing_left,
    input wire [1:0] run_page,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_right, mouse_event,
    output reg [11:0] mouse_value,
    output reg setx, sety, setmax_x, setmax_y,
    output reg [6:0] cursor_x, cursor_y,
    output reg [2:0] selected_part,
    output reg selected_left,
    output reg [1:0] inventory_page,
    output reg edit_facing_left,
    output wire drag_active,
    output reg drag_from_grid,
    output reg [3:0] drag_source,
    output reg [2:0] drag_contents,
    output reg edit_valid,
    output reg [1:0] edit_op,
    output reg [3:0] edit_cell,
    output reg [3:0] edit_source,
    output reg [2:0] edit_part,
    output reg pop_req,
    output reg [3:0] pop_cell,
    output reg boost_req
);
    reg [1:0] setup_step;
    reg left_was_down, right_was_down;
    reg place_pending, inventory_armed;
    assign drag_active = place_pending && game_state == `LP_BUILD && input_enabled;
    wire build_grid_area = mouse_x >= 4 && mouse_x < 52 && mouse_y >= 4 && mouse_y < 52;
    wire pop_grid_area = mouse_x >= 4 && mouse_x < 40 && mouse_y >= 12 && mouse_y < 48;
    wire in_grid = (game_state == `LP_BUILD) ? build_grid_area : pop_grid_area;
    wire in_inventory = mouse_x >= 56 && mouse_x < 92 && mouse_y >= 4 && mouse_y < 54;
    // Used only when in_grid is true, for placement, removal and balloon clicks.
    wire [3:0] hovered_cell = (game_state == `LP_BUILD) ?
                              ((mouse_y-4)/16)*3 + (mouse_x-4)/16 :
                              ((mouse_y-12)/12)*3 + (mouse_x-4)/12;

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
            inventory_armed <= 0; drag_from_grid <= 0; drag_source <= 9; drag_contents <= 0;
            cursor_x <= 24; cursor_y <= 24; selected_part <= `LP_PART_FRAME;
            selected_left<=0; inventory_page<=0; edit_facing_left<=0;
            edit_valid <= 0; edit_op <= `LP_EDIT_PLACE; edit_cell <= 0; edit_source <= 9; edit_part <= `LP_PART_FRAME;
            pop_req <= 0; pop_cell <= 0; boost_req <= 0;
        end else begin
            edit_valid <= 0; pop_req <= 0; boost_req <= 0;
            // Leaving construction cancels a drag, even if no mouse packet arrives.
            if (game_state != `LP_BUILD || !input_enabled) begin
                place_pending <= 0; inventory_armed <= 0; drag_from_grid <= 0;
            end
            if (setup_step != 3) setup_step <= setup_step + 1'b1;
            else if (mouse_event) begin
                // Read buttons only after a complete packet, when its position is ready.
                cursor_x <= (mouse_x > 95) ? 95 : mouse_x[6:0];
                cursor_y <= (mouse_y > 63) ? 63 : mouse_y[6:0];
                left_was_down <= mouse_left; right_was_down <= mouse_right;
                if (game_state == `LP_BUILD && input_enabled) begin
                    if (mouse_right) begin
                        // Right-click cancels placement and removes only once per press.
                        place_pending <= 0; inventory_armed <= 0; drag_from_grid <= 0;
                        if (!right_was_down && in_grid && !place_pending) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_REMOVE;
                            edit_cell <= hovered_cell;
                            edit_part <= `LP_PART_EMPTY;
                        end
                    end else if (mouse_left && !left_was_down) begin
                        // Start a placement in the inventory or grid; wait for release.
                        place_pending <= in_inventory || in_grid;
                        drag_from_grid <= 0; drag_source <= 9; drag_contents <= 0;
                        // Select only on the initial press, not while dragging past rows.
                        if (mouse_y>=55 && mouse_y<64) begin
                            place_pending<=0;
                            if (mouse_x>=20 && mouse_x<62) begin
                                inventory_page <= mouse_x<34 ? 0 : mouse_x<48 ? 1 : 2;
                                inventory_armed<=0;
                            end
                        end else if (in_inventory) begin
                            inventory_armed <= 1;
                            // Five fixed row boundaries avoid a hardware divide by ten.
                            if (inventory_page!=0) begin
                                if (mouse_y<14) selected_part<=inventory_page==1 ? `LP_PART_BOOSTER : `LP_PART_FAN;
                                else begin place_pending<=0; inventory_armed<=0; end
                            end else if (mouse_y<14) selected_part<=`LP_PART_FRAME;
                            else if (mouse_y<24) selected_part<=`LP_PART_PIG;
                            else if (mouse_y<34) selected_part<=`LP_PART_WHEEL;
                            else if (mouse_y<44) selected_part<=`LP_PART_ENGINE;
                            else selected_part<=`LP_PART_BALLOON;
                        end else if (in_grid && !inventory_armed &&
                                     (build_frames[hovered_cell] || build_grid[hovered_cell*3 +: 3] != `LP_PART_EMPTY)) begin
                            // Existing parts are only transferred when a valid drop is accepted.
                            drag_from_grid <= 1; drag_source <= hovered_cell;
                            if (build_grid[hovered_cell*3 +: 3] != `LP_PART_EMPTY) begin
                                selected_part <= build_grid[hovered_cell*3 +: 3];
                                selected_left <= build_facing_left[hovered_cell];
                            end else selected_part <= `LP_PART_FRAME;
                        end
                    end else if (!mouse_left && left_was_down) begin
                        place_pending <= 0;
                        drag_from_grid <= 0;
                        if (place_pending) inventory_armed <= in_inventory && !drag_from_grid;
                        edit_facing_left<=selected_left;
                        // One drop at the release position; outside the grid cancels it.
                        if (place_pending && drag_from_grid && in_inventory) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_RETURN;
                            edit_source <= drag_source; edit_cell <= drag_source; edit_part <= selected_part;
                        end else if (place_pending && drag_from_grid && in_grid && hovered_cell==drag_source &&
                                     (selected_part==`LP_PART_ENGINE || selected_part==`LP_PART_BOOSTER)) begin
                            // A click released on the same cell flips the saved part in place.
                            edit_valid<=1; edit_op<=`LP_EDIT_PLACE; edit_cell<=drag_source;
                            edit_part<=selected_part; edit_facing_left<=!selected_left;
                            selected_left<=!selected_left;
                        end else if (place_pending && in_grid && (!drag_from_grid || hovered_cell != drag_source)) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_PLACE;
                            edit_cell <= hovered_cell;
                            edit_source <= drag_source;
                            if (drag_from_grid) edit_op <= `LP_EDIT_MOVE;
                            edit_part <= selected_part;
                        end
                    end
                end else if (input_enabled && game_state == `LP_RUN && mouse_left && !left_was_down &&
                             !mouse_right) begin
                    // Gameplay uses one fresh press, rather than construction's drop.
                    if (run_page==1 && in_grid) begin pop_req <= 1; pop_cell <= hovered_cell; end
                    // DRIVE boost comes from ui_controller.
                end
            end
        end
    end
endmodule
