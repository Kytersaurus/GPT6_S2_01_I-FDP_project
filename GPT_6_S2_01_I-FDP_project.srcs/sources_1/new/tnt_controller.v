// Owner: Role 3 - Yap Ting; standalone TNT trigger and damage generation.
`timescale 1ns / 1ps
`include "game_defs.vh"

// TNT controller for the run phase.
//
// TNT positions are stored as {y[7:0], x[7:0]} pixel coordinates.  Vehicle
// positions use the shared Q8.8 format and the vehicle footprint is 24 by
// 24 pixels.  A swept vehicle rectangle is used so a fast movement cannot
// pass through a TNT between two committed positions.
//
// The damage request is held until damage_ready is asserted.  This keeps the
// module independent from Role 1's eventual damage-application interface.
module tnt_controller (
    input wire clk,
    input wire reset,
    input wire run_init,
    input wire [2:0] game_state,
    output wire init_ready,

    input wire movement_committed,
    input wire signed [15:0] previous_x,
    input wire signed [15:0] previous_y,
    input wire signed [15:0] vehicle_x,
    input wire signed [15:0] vehicle_y,

    input wire [2:0] tnt_count,
    input wire [`LP_TNT_BITS-1:0] tnt_positions,
    input wire [`LP_GRID_BITS-1:0] build_grid,
    input wire [`LP_CELLS-1:0] build_frames,
    input wire [`LP_CELLS-1:0] intact_mask,
    input wire [`LP_CELLS-1:0] frame_intact_mask,

    output reg [`LP_MAX_TNT-1:0] tnt_intact,
    output reg damage_valid,
    input wire damage_ready,
    output reg [`LP_CELLS-1:0] damage_mask,
    output reg [`LP_CELLS-1:0] damage_frame_mask,
    output reg explosion_event,
    output reg damage_complete
);
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] WAIT_DAMAGE = 2'd1;
    localparam [1:0] COMPLETE = 2'd2;

    localparam integer VEHICLE_SIZE_PIXELS = 24;
    localparam integer TNT_SIZE_PIXELS = 8;
    localparam integer BLAST_RADIUS_PIXELS = 12;
    localparam integer BLAST_RADIUS_SQUARED =
        BLAST_RADIUS_PIXELS * BLAST_RADIUS_PIXELS;

    reg [1:0] state;
    reg [`LP_MAX_TNT-1:0] trigger_mask;
    reg trigger_found;
    reg [1:0] selected_tnt;
    reg signed [15:0] selected_tnt_x;
    reg signed [15:0] selected_tnt_y;
    reg [`LP_CELLS-1:0] calculated_damage_mask;
    reg [`LP_CELLS-1:0] calculated_frame_mask;

    integer previous_x_fp;
    integer previous_y_fp;
    integer current_x_fp;
    integer current_y_fp;
    integer sweep_left_fp;
    integer sweep_right_fp;
    integer sweep_top_fp;
    integer sweep_bottom_fp;
    integer tnt_x_pixels;
    integer tnt_y_pixels;
    integer selected_x_pixels;
    integer selected_y_pixels;
    integer cell_index;
    integer cell_x_pixels;
    integer cell_y_pixels;
    integer delta_x;
    integer delta_y;
    integer distance_squared;
    integer tnt_index;

    assign init_ready = run_init && (game_state == `LP_INIT_RUN);

    // Find the first intact TNT touched by the swept vehicle footprint.
    // Coordinates remain in Q8.8 here; TNT coordinates are shifted by eight
    // bits so comparisons use the same units.
    always @* begin
        previous_x_fp = $signed(previous_x);
        previous_y_fp = $signed(previous_y);
        current_x_fp = $signed(vehicle_x);
        current_y_fp = $signed(vehicle_y);

        if (previous_x_fp < current_x_fp)
            sweep_left_fp = previous_x_fp;
        else
            sweep_left_fp = current_x_fp;

        if (previous_x_fp + (VEHICLE_SIZE_PIXELS << 8) >
            current_x_fp + (VEHICLE_SIZE_PIXELS << 8))
            sweep_right_fp = previous_x_fp + (VEHICLE_SIZE_PIXELS << 8);
        else
            sweep_right_fp = current_x_fp + (VEHICLE_SIZE_PIXELS << 8);

        if (previous_y_fp < current_y_fp)
            sweep_top_fp = previous_y_fp;
        else
            sweep_top_fp = current_y_fp;

        if (previous_y_fp + (VEHICLE_SIZE_PIXELS << 8) >
            current_y_fp + (VEHICLE_SIZE_PIXELS << 8))
            sweep_bottom_fp = previous_y_fp + (VEHICLE_SIZE_PIXELS << 8);
        else
            sweep_bottom_fp = current_y_fp + (VEHICLE_SIZE_PIXELS << 8);

        trigger_mask = {`LP_MAX_TNT{1'b0}};
        trigger_found = 1'b0;
        selected_tnt = 2'd0;
        selected_tnt_x = 16'sd0;
        selected_tnt_y = 16'sd0;

        for (tnt_index = 0; tnt_index < `LP_MAX_TNT; tnt_index = tnt_index + 1) begin
            tnt_x_pixels = tnt_positions[tnt_index*16 +: 8];
            tnt_y_pixels = tnt_positions[tnt_index*16 + 8 +: 8];

            if ((tnt_index < tnt_count) && tnt_intact[tnt_index] &&
                (sweep_right_fp > (tnt_x_pixels << 8)) &&
                (sweep_left_fp < ((tnt_x_pixels + TNT_SIZE_PIXELS) << 8)) &&
                (sweep_bottom_fp > (tnt_y_pixels << 8)) &&
                (sweep_top_fp < ((tnt_y_pixels + TNT_SIZE_PIXELS) << 8))) begin
                trigger_mask[tnt_index] = 1'b1;
                if (!trigger_found) begin
                    trigger_found = 1'b1;
                    selected_tnt = tnt_index[1:0];
                    selected_tnt_x = tnt_x_pixels;
                    selected_tnt_y = tnt_y_pixels;
                end
            end
        end
    end

    // Calculate the content and frame cells inside the provisional blast
    // radius.  Cell centres are relative to the current 24 by 24 vehicle.
    always @* begin
        calculated_damage_mask = {`LP_CELLS{1'b0}};
        calculated_frame_mask = {`LP_CELLS{1'b0}};
        selected_x_pixels = selected_tnt_x;
        selected_y_pixels = selected_tnt_y;

        for (cell_index = 0; cell_index < `LP_CELLS; cell_index = cell_index + 1) begin
            cell_x_pixels = (current_x_fp >>> 8) +
                            ((cell_index % `LP_GRID_COLS) * `LP_CELL_PIXELS) +
                            (`LP_CELL_PIXELS / 2);
            cell_y_pixels = (current_y_fp >>> 8) +
                            ((cell_index / `LP_GRID_COLS) * `LP_CELL_PIXELS) +
                            (`LP_CELL_PIXELS / 2);
            delta_x = cell_x_pixels - (selected_x_pixels + TNT_SIZE_PIXELS / 2);
            delta_y = cell_y_pixels - (selected_y_pixels + TNT_SIZE_PIXELS / 2);
            distance_squared = (delta_x * delta_x) + (delta_y * delta_y);

            if ((distance_squared <= BLAST_RADIUS_SQUARED) &&
                intact_mask[cell_index] &&
                (build_grid[cell_index*`LP_PART_BITS +: `LP_PART_BITS] !=
                 `LP_PART_EMPTY))
                calculated_damage_mask[cell_index] = 1'b1;

            if ((distance_squared <= BLAST_RADIUS_SQUARED) &&
                build_frames[cell_index] && frame_intact_mask[cell_index])
                calculated_frame_mask[cell_index] = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            tnt_intact <= {`LP_MAX_TNT{1'b0}};
            damage_valid <= 1'b0;
            damage_mask <= {`LP_CELLS{1'b0}};
            damage_frame_mask <= {`LP_CELLS{1'b0}};
            explosion_event <= 1'b0;
            damage_complete <= 1'b0;
        end else begin
            explosion_event <= 1'b0;
            damage_complete <= 1'b0;

            if (run_init && (game_state == `LP_INIT_RUN)) begin
                state <= IDLE;
                tnt_intact <= {`LP_MAX_TNT{1'b1}};
                damage_valid <= 1'b0;
                damage_mask <= {`LP_CELLS{1'b0}};
                damage_frame_mask <= {`LP_CELLS{1'b0}};
            end else begin
                case (state)
                    IDLE: begin
                        if ((game_state == `LP_RUN) && movement_committed &&
                            trigger_found) begin
                            tnt_intact[selected_tnt] <= 1'b0;
                            damage_mask <= calculated_damage_mask;
                            damage_frame_mask <= calculated_frame_mask;
                            damage_valid <= 1'b1;
                            explosion_event <= 1'b1;
                            state <= WAIT_DAMAGE;
                        end
                    end

                    WAIT_DAMAGE: begin
                        if (damage_ready) begin
                            damage_valid <= 1'b0;
                            damage_complete <= 1'b1;
                            state <= COMPLETE;
                        end
                    end

                    COMPLETE: begin
                        state <= IDLE;
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
