// Owner: Role 1 - Kaushal. Mouse configuration, construction and gameplay clicks.
`timescale 1ns / 1ps
`include "game_defs.vh"
module mouse_adapter (
    input wire clk, reset, input_enabled,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] build_frames, build_facing_left,
    input wire [8:0] build_facing_down,
    input wire [1:0] run_page,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_right, mouse_event,
    input tri0 [3:0] mouse_z,
    output reg [11:0] mouse_value,
    output reg setx, sety, setmax_x, setmax_y,
    output wire [6:0] cursor_x, cursor_y,
    output reg [2:0] selected_part,
    output reg selected_left,
    output reg selected_down,
    output reg [1:0] inventory_page,
    output reg engine_facing_left,
    output reg fan_facing_left,
    output reg fan_facing_down,
    output reg rocket_facing_left,
    output reg rocket_facing_down,
    output reg edit_facing_left,
    output reg edit_facing_down,
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
    output reg fan_toggle_req,
    output reg [3:0] fan_toggle_cell
);
    localparam SETUP_SETMAX_X = 2'd0;
    localparam SETUP_SETMAX_Y = 2'd1;
    localparam SETUP_SET_XY   = 2'd2;
    localparam SETUP_IDLE     = 2'd3;

    reg [1:0] setup_state;
    reg left_was_down, right_was_down;
    reg place_pending, inventory_armed, inv_cycle_pending, sync_edit_dir;
    assign drag_active = place_pending && game_state == `LP_BUILD && input_enabled;

    wire [6:0] clamped_x = (mouse_x >= 12'd95) ? 7'd95 : mouse_x[6:0];
    wire [6:0] clamped_y = (mouse_y >= 12'd63) ? 7'd63 : mouse_y[5:0];

    reg has_moved;
    assign cursor_x = (has_moved || mouse_event) ? clamped_x : 7'd24;
    assign cursor_y = (has_moved || mouse_event) ? clamped_y : 7'd24;

    wire [11:0] cur_x = {5'd0, cursor_x};
    wire [11:0] cur_y = {5'd0, cursor_y};

    wire build_grid_area = cur_x >= 4 && cur_x < 52 && cur_y >= 4 && cur_y < 52;
    wire run_grid_big = cur_x >= 24 && cur_x < 72 && cur_y >= 2 && cur_y < 50;

    wire in_grid = (game_state == `LP_BUILD) ? build_grid_area :
                   (game_state == `LP_RUN)   ? run_grid_big : 1'b0;
    wire in_inventory = cur_x >= 56 && cur_x < 92 && cur_y >= 4 && cur_y < 54;
    // Find grid rows and columns with fixed range checks instead of division.
    wire building = game_state == `LP_BUILD;
    wire [1:0] build_col = cur_x < 20 ? 2'd0 : cur_x < 36 ? 2'd1 : 2'd2;
    wire [1:0] build_row = cur_y < 20 ? 2'd0 : cur_y < 36 ? 2'd1 : 2'd2;
    wire [1:0] run_col_big = cur_x < 40 ? 2'd0 : cur_x < 56 ? 2'd1 : 2'd2;
    wire [1:0] run_row_big = cur_y < 18 ? 2'd0 : cur_y < 34 ? 2'd1 : 2'd2;

    wire [1:0] hovered_col = building ? build_col : run_col_big;
    wire [1:0] hovered_row = building ? build_row : run_row_big;
    reg [3:0] hovered_cell;
    reg [2:0] hovered_part;
    reg hovered_frame, hovered_facing_left, hovered_facing_down;

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
        hovered_facing_down = 0;
        case (hovered_cell)
            0: begin hovered_part=build_grid[2:0];   hovered_frame=build_frames[0]; hovered_facing_left=build_facing_left[0]; hovered_facing_down=build_facing_down[0]; end
            1: begin hovered_part=build_grid[5:3];   hovered_frame=build_frames[1]; hovered_facing_left=build_facing_left[1]; hovered_facing_down=build_facing_down[1]; end
            2: begin hovered_part=build_grid[8:6];   hovered_frame=build_frames[2]; hovered_facing_left=build_facing_left[2]; hovered_facing_down=build_facing_down[2]; end
            3: begin hovered_part=build_grid[11:9];  hovered_frame=build_frames[3]; hovered_facing_left=build_facing_left[3]; hovered_facing_down=build_facing_down[3]; end
            4: begin hovered_part=build_grid[14:12]; hovered_frame=build_frames[4]; hovered_facing_left=build_facing_left[4]; hovered_facing_down=build_facing_down[4]; end
            5: begin hovered_part=build_grid[17:15]; hovered_frame=build_frames[5]; hovered_facing_left=build_facing_left[5]; hovered_facing_down=build_facing_down[5]; end
            6: begin hovered_part=build_grid[20:18]; hovered_frame=build_frames[6]; hovered_facing_left=build_facing_left[6]; hovered_facing_down=build_facing_down[6]; end
            7: begin hovered_part=build_grid[23:21]; hovered_frame=build_frames[7]; hovered_facing_left=build_facing_left[7]; hovered_facing_down=build_facing_down[7]; end
            8: begin hovered_part=build_grid[26:24]; hovered_frame=build_frames[8]; hovered_facing_left=build_facing_left[8]; hovered_facing_down=build_facing_down[8]; end
            default: begin end
        endcase
    end

    // Direction codes are {facing_down, facing_left}. Rockets cycle right, left,
    // up, down; fans cycle right, left, down (code 2). vehicle_builder skips any
    // direction blocked by what touches the part, so this only asks for the next.
    wire [1:0] selected_direction = {selected_down, selected_left};
    wire [1:0] next_rocket_direction = selected_direction + 2'd1;
    wire [1:0] next_fan_direction = (selected_direction >= 2'd2) ? 2'd0 : selected_direction + 2'd1;
    wire [1:0] next_inventory_rocket = {rocket_facing_down, rocket_facing_left} + 2'd1;
    wire [1:0] next_inventory_fan = fan_facing_down ? 2'd0 : {fan_facing_down, fan_facing_left} + 2'd1;

    always @* begin
        mouse_value = 12'd0;
        setx = 1'b0;
        sety = 1'b0;
        setmax_x = 1'b0;
        setmax_y = 1'b0;
        case (setup_state)
            SETUP_SETMAX_X: begin mouse_value = 12'd95; setmax_x = 1'b1; end
            SETUP_SETMAX_Y: begin mouse_value = 12'd63; setmax_y = 1'b1; end
            SETUP_SET_XY:   begin mouse_value = 12'd24; setx = 1'b1; sety = 1'b1; end
            default: begin end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            has_moved <= 1'b0;
            setup_state <= SETUP_SETMAX_X;
            left_was_down <= 0;
            right_was_down <= 0;
            place_pending <= 0;
            inventory_armed <= 0;
            inv_cycle_pending <= 0;
            sync_edit_dir <= 0;
            drag_from_grid <= 0;
            drag_source <= 9;
            drag_contents <= 0;
            selected_part <= `LP_PART_FRAME;
            selected_left <= 0;
            engine_facing_left <= 0;
            fan_facing_left <= 0;
            fan_facing_down <= 0;
            rocket_facing_left <= 0;
            rocket_facing_down <= 0;
            inventory_page <= 0;
            selected_down <= 0;
            edit_facing_left <= 0;
            edit_facing_down <= 0;
            edit_valid <= 0;
            edit_op <= `LP_EDIT_PLACE;
            edit_cell <= 0;
            edit_source <= 9;
            edit_part <= `LP_PART_FRAME;
            pop_req <= 0;
            pop_cell <= 0;
            boost_req <= 0;
            engine_toggle_req <= 0;
            fan_toggle_req <= 0;
            fan_toggle_cell <= 0;
        end else begin
            edit_valid <= 0;
            pop_req <= 0;
            boost_req <= 0;
            engine_toggle_req <= 0;
            fan_toggle_req <= 0;
            sync_edit_dir <= edit_valid && (edit_op == `LP_EDIT_PLACE || edit_op == `LP_EDIT_MOVE) && (edit_cell < 4'd9);

            if (sync_edit_dir && (build_grid[edit_cell*3 +: 3] == edit_part)) begin
                selected_left <= build_facing_left[edit_cell];
                selected_down <= (edit_part == `LP_PART_FRAME) ? 1'b1 : build_facing_down[edit_cell];
                case (edit_part)
                    `LP_PART_ENGINE:  begin engine_facing_left <= build_facing_left[edit_cell]; end
                    `LP_PART_BOOSTER: begin rocket_facing_left <= build_facing_left[edit_cell]; rocket_facing_down <= build_facing_down[edit_cell]; end
                    `LP_PART_FAN:     begin fan_facing_left    <= build_facing_left[edit_cell]; fan_facing_down    <= build_facing_down[edit_cell]; end
                    default: begin end
                endcase
            end

            if (input_enabled && game_state == `LP_BUILD && mouse_event && mouse_z != 0) begin
                if (!mouse_z[3]) begin
                    inventory_page <= 2'd1;
                end else begin
                    inventory_page <= 2'd0;
                end
            end

            case (setup_state)
                SETUP_SETMAX_X: setup_state <= SETUP_SETMAX_Y;
                SETUP_SETMAX_Y: setup_state <= SETUP_SET_XY;
                SETUP_SET_XY:   setup_state <= SETUP_IDLE;
                default:        setup_state <= SETUP_IDLE;
            endcase

            // Leaving construction cancels a drag, even if no mouse packet arrives.
            if (game_state != `LP_BUILD || !input_enabled) begin
                place_pending <= 0; inventory_armed <= 0; inv_cycle_pending <= 0; drag_from_grid <= 0;
            end

            if (mouse_event) begin
                has_moved <= 1'b1;
                left_was_down <= mouse_left; right_was_down <= mouse_right;
                if (game_state == `LP_BUILD && input_enabled) begin
                    if (mouse_right) begin
                        // Right-click cancels placement and removes only once per press.
                        place_pending <= 0; inventory_armed <= 0; inv_cycle_pending <= 0; drag_from_grid <= 0;
                        if (!right_was_down && in_grid && !place_pending) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_REMOVE;
                            edit_cell <= hovered_cell;
                            edit_part <= `LP_PART_EMPTY;
                        end
                    end else if (mouse_left && !left_was_down) begin
                        // Start a placement in the inventory or grid; wait for release.
                        place_pending <= in_inventory || in_grid;
                        drag_from_grid <= 0; drag_source <= 9; drag_contents <= 0;
                        inv_cycle_pending <= 0;
                        // Select only on the initial press, not while dragging past rows.
                        // Do not cycle direction on press so dragging from inventory never glitches.
                        if (in_inventory) begin
                            inventory_armed <= 1;
                            // Both pages use uniform 10-pixel rows (Row 0: y=4..13, Row 1: y=14..23, etc.).
                            if (inventory_page!=0) begin
                                if (cur_y<14) begin
                                    inv_cycle_pending <= (selected_part == `LP_PART_BOOSTER);
                                    selected_part <= `LP_PART_BOOSTER;
                                    selected_left <= rocket_facing_left;
                                    selected_down <= rocket_facing_down;
                                end else if (cur_y<24) begin
                                    inv_cycle_pending <= (selected_part == `LP_PART_FAN);
                                    selected_part <= `LP_PART_FAN;
                                    selected_left <= fan_facing_left;
                                    selected_down <= fan_facing_down;
                                end else if (cur_y<34) begin
                                    selected_part <= `LP_PART_FRAME;
                                    selected_left <= 0;
                                    selected_down <= 1'b1;
                                end else begin place_pending<=0; inventory_armed<=0; end
                            end else if (cur_y<14) begin
                                selected_part <= `LP_PART_FRAME;
                                selected_left <= 0;
                                selected_down <= 0;
                            end else if (cur_y<24) begin
                                selected_part <= `LP_PART_PIG;
                                selected_left <= 0;
                                selected_down <= 0;
                            end else if (cur_y<34) begin
                                selected_part <= `LP_PART_WHEEL;
                                selected_left <= 0;
                                selected_down <= 0;
                            end else if (cur_y<44) begin
                                inv_cycle_pending <= (selected_part == `LP_PART_ENGINE);
                                selected_part <= `LP_PART_ENGINE;
                                selected_left <= engine_facing_left;
                                selected_down <= 0;
                            end else begin
                                selected_part <= `LP_PART_BALLOON;
                                selected_left <= 0;
                                selected_down <= 0;
                            end
                        end else if (in_grid && !inventory_armed &&
                                     (hovered_frame || hovered_part != `LP_PART_EMPTY)) begin
                            // Existing parts are only transferred when a valid drop is accepted.
                            drag_from_grid <= 1; drag_source <= hovered_cell;
                            if (hovered_part != `LP_PART_EMPTY) begin
                                selected_part <= hovered_part;
                                selected_left <= hovered_facing_left;
                                selected_down <= (hovered_part == `LP_PART_FRAME) ? 1'b1 : hovered_facing_down;
                                case (hovered_part)
                                    `LP_PART_ENGINE:  begin engine_facing_left <= hovered_facing_left; end
                                    `LP_PART_BOOSTER: begin rocket_facing_left <= hovered_facing_left; rocket_facing_down <= hovered_facing_down; end
                                    `LP_PART_FAN:     begin fan_facing_left    <= hovered_facing_left; fan_facing_down <= hovered_facing_down; end
                                    default: begin end
                                endcase
                            end else begin
                                selected_part <= `LP_PART_FRAME;
                                selected_left <= 0;
                                selected_down <= 0;
                            end
                        end
                    end else if (!mouse_left && left_was_down) begin
                        place_pending <= 0;
                        drag_from_grid <= 0;
                        inv_cycle_pending <= 0;
                        if (place_pending) inventory_armed <= in_inventory && !drag_from_grid;
                        edit_facing_left <= selected_left;
                        edit_facing_down <= selected_down;
                        // Cycle inventory facing only on release inside the inventory (click without drag).
                        if (place_pending && !drag_from_grid && in_inventory && inv_cycle_pending) begin
                            if (selected_part == `LP_PART_BOOSTER && inventory_page != 0 && cur_y < 14) begin
                                {rocket_facing_down, rocket_facing_left} <= next_inventory_rocket;
                                {selected_down, selected_left} <= next_inventory_rocket;
                            end else if (selected_part == `LP_PART_FAN && inventory_page != 0 && cur_y >= 14 && cur_y < 24) begin
                                {fan_facing_down, fan_facing_left} <= next_inventory_fan;
                                {selected_down, selected_left} <= next_inventory_fan;
                            end else if (selected_part == `LP_PART_ENGINE && inventory_page == 0 && cur_y >= 34 && cur_y < 44) begin
                                engine_facing_left <= !engine_facing_left;
                                selected_left <= !engine_facing_left;
                            end
                        end else if (place_pending && drag_from_grid && in_inventory) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_RETURN;
                            edit_source <= drag_source; edit_cell <= drag_source; edit_part <= selected_part;
                        end else if (place_pending && drag_from_grid && in_grid && hovered_cell==drag_source &&
                                     (selected_part==`LP_PART_ENGINE || selected_part==`LP_PART_BOOSTER ||
                                      selected_part==`LP_PART_FAN)) begin
                            edit_valid <= 1; edit_op <= `LP_EDIT_PLACE; edit_cell <= drag_source;
                            edit_part <= selected_part;
                            if (selected_part == `LP_PART_ENGINE) begin
                                edit_facing_left <= !selected_left; edit_facing_down <= 0;
                                selected_left <= !selected_left;    selected_down <= 0;
                                engine_facing_left <= !selected_left;
                            end else if (selected_part == `LP_PART_BOOSTER) begin
                                {edit_facing_down, edit_facing_left} <= next_rocket_direction;
                                {selected_down, selected_left} <= next_rocket_direction;
                                {rocket_facing_down, rocket_facing_left} <= next_rocket_direction;
                            end else if (selected_part == `LP_PART_FAN) begin
                                {edit_facing_down, edit_facing_left} <= next_fan_direction;
                                {selected_down, selected_left} <= next_fan_direction;
                                {fan_facing_down, fan_facing_left} <= next_fan_direction;
                            end
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
                        if (hovered_part == `LP_PART_BALLOON || hovered_part == `LP_PART_FRAME) begin
                            pop_req <= 1; pop_cell <= hovered_cell;
                        end else if (run_page == 2'd0) begin
                            if (hovered_part == `LP_PART_ENGINE) begin
                                engine_toggle_req <= 1;
                            end else if (hovered_part == `LP_PART_FAN) begin
                                fan_toggle_req <= 1;
                                fan_toggle_cell <= hovered_cell;
                            end else if (hovered_part == `LP_PART_BOOSTER) begin
                                boost_req <= 1;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
