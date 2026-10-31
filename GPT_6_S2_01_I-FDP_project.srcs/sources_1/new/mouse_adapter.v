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
    input wire [1:0] mouse_speed,
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
    output reg boost_req,
    output reg engine_toggle_req,
    output reg fan_toggle_req
);
    reg [1:0] setup_step;

    reg left_was_down, right_was_down;
    reg place_pending, inventory_armed;
    assign drag_active = place_pending && game_state == `LP_BUILD && input_enabled;
    wire build_grid_area = mouse_x >= 4 && mouse_x < 52 && mouse_y >= 4 && mouse_y < 52;
    wire pop_grid_area = mouse_x >= 4 && mouse_x < 40 && mouse_y >= 12 && mouse_y < 48;
    wire run_grid_big = mouse_x >= 24 && mouse_x < 72 && mouse_y >= 2 && mouse_y < 50;

    wire in_grid = (game_state == `LP_BUILD) ? build_grid_area :
                   (run_page == 2'd1) ? pop_grid_area : run_grid_big;
    wire in_inventory = mouse_x >= 56 && mouse_x < 92 && mouse_y >= 4 && mouse_y < 54;
    // Find grid rows and columns with fixed range checks instead of division.
    wire building = game_state == `LP_BUILD;
    wire [1:0] build_col = mouse_x < 20 ? 2'd0 : mouse_x < 36 ? 2'd1 : 2'd2;
    wire [1:0] build_row = mouse_y < 20 ? 2'd0 : mouse_y < 36 ? 2'd1 : 2'd2;
    wire [1:0] pop_col = mouse_x < 16 ? 2'd0 : mouse_x < 28 ? 2'd1 : 2'd2;
    wire [1:0] pop_row = mouse_y < 24 ? 2'd0 : mouse_y < 36 ? 2'd1 : 2'd2;
    wire [1:0] run_col_big = mouse_x < 40 ? 2'd0 : mouse_x < 56 ? 2'd1 : 2'd2;
    wire [1:0] run_row_big = mouse_y < 18 ? 2'd0 : mouse_y < 34 ? 2'd1 : 2'd2;

    wire [1:0] hovered_col = building ? build_col : (run_page == 2'd1 ? pop_col : run_col_big);
    wire [1:0] hovered_row = building ? build_row : (run_page == 2'd1 ? pop_row : run_row_big);
    reg [3:0] hovered_cell;
    reg [2:0] hovered_part;
    reg hovered_frame, hovered_facing_left;

    // Explicit cases keep cell decoding and part lookup short and predictable.
    always @* begin
        case ({hovered_row, hovered_col})
            4'b0000: hovered_cell = 0;
            4'b0001: hovered_cell = 1;
            4'b0010: hovered_cell = 2;
            4'b0100: hovered_cell = 3;
            4'b0101: hovered_cell = 4;
            4'b0110: hovered_cell = 5;
            4'b1000: hovered_cell = 6;
            4'b1001: hovered_cell = 7;
            4'b1010: hovered_cell = 8;
            default: hovered_cell = 9;
        endcase

        hovered_part = `LP_PART_EMPTY;
        hovered_frame = 0;
        hovered_facing_left = 0;
        case (hovered_cell)
            0: begin hovered_part=build_grid[2:0];   hovered_frame=build_frames[0]; hovered_facing_left=build_facing_left[0]; end
            1: begin hovered_part=build_grid[5:3];   hovered_frame=build_frames[1]; hovered_facing_left=build_facing_left[1]; end
            2: begin hovered_part=build_grid[8:6];   hovered_frame=build_frames[2]; hovered_facing_left=build_facing_left[2]; end
            3: begin hovered_part=build_grid[11:9];  hovered_frame=build_frames[3]; hovered_facing_left=build_facing_left[3]; end
            4: begin hovered_part=build_grid[14:12]; hovered_frame=build_frames[4]; hovered_facing_left=build_facing_left[4]; end
            5: begin hovered_part=build_grid[17:15]; hovered_frame=build_frames[5]; hovered_facing_left=build_facing_left[5]; end
            6: begin hovered_part=build_grid[20:18]; hovered_frame=build_frames[6]; hovered_facing_left=build_facing_left[6]; end
            7: begin hovered_part=build_grid[23:21]; hovered_frame=build_frames[7]; hovered_facing_left=build_facing_left[7]; end
            8: begin hovered_part=build_grid[26:24]; hovered_frame=build_frames[8]; hovered_facing_left=build_facing_left[8]; end
            default: begin end
        endcase
    end

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

    reg [11:0] prev_mouse_x, prev_mouse_y;
    reg signed [12:0] internal_x, internal_y;
    wire signed [12:0] raw_dx = $signed({1'b0, mouse_x}) - $signed({1'b0, prev_mouse_x});
    wire signed [12:0] raw_dy = $signed({1'b0, mouse_y}) - $signed({1'b0, prev_mouse_y});
    wire is_teleport = (raw_dx > 15 || raw_dx < -15 || raw_dy > 15 || raw_dy < -15);
    wire [1:0] safe_speed = (mouse_speed === 2'bzz || mouse_speed === 2'bxx) ? 2'd1 : mouse_speed;

    reg signed [12:0] scaled_dx, scaled_dy;
    reg signed [12:0] nxt_x, nxt_y;

    always @(posedge clk) begin
        if (reset) begin
            setup_step <= 0; left_was_down <= 0; right_was_down <= 0;
            place_pending <= 0;
            inventory_armed <= 0; drag_from_grid <= 0; drag_source <= 9; drag_contents <= 0;
            cursor_x <= 24; cursor_y <= 24; selected_part <= `LP_PART_FRAME;
            prev_mouse_x <= 24; prev_mouse_y <= 24; internal_x <= 24; internal_y <= 24;
            selected_left<=0; inventory_page<=0; edit_facing_left<=0;
            edit_valid <= 0; edit_op <= `LP_EDIT_PLACE; edit_cell <= 0; edit_source <= 9; edit_part <= `LP_PART_FRAME;
            pop_req <= 0; pop_cell <= 0; boost_req <= 0;
            engine_toggle_req <= 0; fan_toggle_req <= 0;
        end else begin
            edit_valid <= 0; pop_req <= 0; boost_req <= 0;
            engine_toggle_req <= 0; fan_toggle_req <= 0;
            // Leaving construction cancels a drag, even if no mouse packet arrives.
            if (game_state != `LP_BUILD || !input_enabled) begin
                place_pending <= 0; inventory_armed <= 0; drag_from_grid <= 0;
            end
            if (setup_step != 3) begin
                setup_step <= setup_step + 1'b1;
                prev_mouse_x <= 24; prev_mouse_y <= 24;
                internal_x <= 24; internal_y <= 24;
            end else if (mouse_event) begin
                prev_mouse_x <= mouse_x;
                prev_mouse_y <= mouse_y;
                if (is_teleport || safe_speed == 2'd1) begin
                    internal_x <= (mouse_x > 95) ? 13'sd95 : $signed({1'b0, mouse_x});
                    internal_y <= (mouse_y > 63) ? 13'sd63 : $signed({1'b0, mouse_y});
                    cursor_x <= (mouse_x > 95) ? 7'd95 : mouse_x[6:0];
                    cursor_y <= (mouse_y > 63) ? 7'd63 : mouse_y[6:0];
                end else begin
                    if (safe_speed == 2'd0) begin
                        scaled_dx = raw_dx >>> 1;
                        scaled_dy = raw_dy >>> 1;
                    end else begin
                        scaled_dx = (raw_dx <<< 1) + (raw_dx >>> 1);
                        scaled_dy = (raw_dy <<< 1) + (raw_dy >>> 1);
                    end
                    nxt_x = internal_x + scaled_dx;
                    nxt_y = internal_y + scaled_dy;
                    if (nxt_x < 0) nxt_x = 0; else if (nxt_x > 95) nxt_x = 95;
                    if (nxt_y < 0) nxt_y = 0; else if (nxt_y > 63) nxt_y = 63;
                    internal_x <= nxt_x;
                    internal_y <= nxt_y;
                    cursor_x <= nxt_x[6:0];
                    cursor_y <= nxt_y[5:0];
                end

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
                                inventory_page <= mouse_x<41 ? 0 : 1;
                                inventory_armed<=0;
                            end
                        end else if (in_inventory) begin
                            inventory_armed <= 1;
                            // Basic parts use five rows; page two splits the panel between two parts.
                            if (inventory_page!=0) begin
                                if (mouse_y<28) selected_part<=`LP_PART_BOOSTER;
                                else if (mouse_y>28) selected_part<=`LP_PART_FAN;
                                else begin place_pending<=0; inventory_armed<=0; end
                            end else if (mouse_y<14) selected_part<=`LP_PART_FRAME;
                            else if (mouse_y<24) selected_part<=`LP_PART_PIG;
                            else if (mouse_y<34) selected_part<=`LP_PART_WHEEL;
                            else if (mouse_y<44) selected_part<=`LP_PART_ENGINE;
                            else selected_part<=`LP_PART_BALLOON;
                        end else if (in_grid && !inventory_armed &&
                                     (hovered_frame || hovered_part != `LP_PART_EMPTY)) begin
                            // Existing parts are only transferred when a valid drop is accepted.
                            drag_from_grid <= 1; drag_source <= hovered_cell;
                            if (hovered_part != `LP_PART_EMPTY) begin
                                selected_part <= hovered_part;
                                selected_left <= hovered_facing_left;
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
                                     (selected_part==`LP_PART_ENGINE || selected_part==`LP_PART_BOOSTER ||
                                      selected_part==`LP_PART_FAN)) begin
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
                    if (in_grid) begin
                        if (hovered_part == `LP_PART_BALLOON) begin
                            pop_req <= 1; pop_cell <= hovered_cell;
                        end else if (run_page == 2'd0) begin
                            if (hovered_part == `LP_PART_ENGINE) begin
                                engine_toggle_req <= 1;
                            end else if (hovered_part == `LP_PART_FAN) begin
                                fan_toggle_req <= 1;
                            end else if (hovered_part == `LP_PART_BOOSTER) begin
                                boost_req <= 1;
                            end
                        end
                    end
                    // DRIVE boost comes from ui_controller.
                end
            end
        end
    end
endmodule
