// Owner: Role 3 - Yap Ting; TNT trigger and damage generation; shared integration with Role 1.
`timescale 1ns / 1ps
`include "game_defs.vh"

// TNT controller for the run phase.
//
// TNT positions are stored as {y[7:0], x[7:0]} pixel coordinates.  Vehicle
// positions use the shared Q12.8 format and the vehicle footprint is 24 by
// 24 pixels.  A swept vehicle rectangle is used so a fast movement cannot
// pass through a TNT between two committed positions.
//
// Damage is held until accepted. damage_complete pulses after all TNT touched
// by one movement have been processed, including a movement with no explosion.
module tnt_controller (
    input wire clk,
    input wire reset,
    input wire run_init,
    input wire [2:0] game_state,
    output wire init_ready,

    input wire movement_committed,
    input wire signed [`LP_COORD_BITS-1:0] previous_x,
    input wire signed [`LP_COORD_BITS-1:0] previous_y,
    input wire signed [`LP_COORD_BITS-1:0] vehicle_x,
    input wire signed [`LP_COORD_BITS-1:0] vehicle_y,
    input wire signed [3:0] previous_tilt, vehicle_tilt,

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
    `include "rotation_geometry.vh"
    localparam IDLE=0, SELECT_TNT=1, CELL_DISTANCE=2, CHECK_CELL=3,
               SEND_DAMAGE=4, WAIT_DAMAGE=5, CAPTURE_TRIGGERS=6, CELL_POSITION=7;
    reg [2:0] state;
    reg [`LP_MAX_TNT-1:0] pending_triggers;
    reg signed [`LP_COORD_BITS-1:0] saved_x, saved_y;
    reg signed [3:0] saved_tilt;
    reg [1:0] active_tnt;
    reg [7:0] active_x, active_y;
    reg [3:0] cell_index;
    reg [`LP_MAX_TNT-1:0] trigger_mask;
    reg trigger_found;
    reg [1:0] selected_tnt;
    reg [12:0] distance_x, distance_y;
    wire [8:0] distance_squared = {1'b0,small_square(distance_x[3:0])} +
                                         {1'b0,small_square(distance_y[3:0])};
    reg signed [21:0] previous_x_fp, previous_y_fp, current_x_fp, current_y_fp;
    reg signed [21:0] next_sweep_left, next_sweep_right, next_sweep_top, next_sweep_bottom;
    reg signed [21:0] sweep_left_fp, sweep_right_fp, sweep_top_fp, sweep_bottom_fp;
    reg [`LP_TNT_BITS-1:0] saved_tnt_positions;
    reg [2:0] saved_tnt_count;
    reg signed [12:0] cell_x_position, cell_y_position;
    integer tnt_x_pixels, tnt_y_pixels, tnt_index;
    integer cell_x_pixels, cell_y_pixels;
    reg signed [12:0] delta_x, delta_y;
    wire signed [9:0] saved_cos = rotation_cos(saved_tilt);
    wire signed [9:0] saved_sin = rotation_sin(saved_tilt);
    wire signed [14:0] current_extent = rotation_extent(vehicle_tilt);
    wire signed [14:0] previous_extent = rotation_extent(previous_tilt);
    wire signed [14:0] sweep_extent = current_extent>previous_extent ? current_extent : previous_extent;
    reg signed [4:0] cell_local_x, cell_local_y;
    wire signed [15:0] cell_offset_x = cell_local_x*saved_cos - cell_local_y*saved_sin;
    wire signed [15:0] cell_offset_y = cell_local_x*saved_sin + cell_local_y*saved_cos;
    wire signed [`LP_COORD_BITS+1:0] cell_world_x = $signed(saved_x)+22'sd3072+cell_offset_x;
    wire signed [`LP_COORD_BITS+1:0] cell_world_y = $signed(saved_y)+22'sd3072+cell_offset_y;

    function [7:0] small_square;
        input [3:0] distance;
        begin
            case (distance)
                0: small_square=0;   1: small_square=1;
                2: small_square=4;   3: small_square=9;
                4: small_square=16;  5: small_square=25;
                6: small_square=36;  7: small_square=49;
                8: small_square=64;  9: small_square=81;
                10: small_square=100; 11: small_square=121;
                12: small_square=144;
                default: small_square=255;
            endcase
        end
    endfunction

    assign init_ready = run_init && (game_state == `LP_INIT_RUN);

    // Capture all TNT touched by the movement, not only the first one.
    always @* begin
        previous_x_fp=$signed(previous_x); previous_y_fp=$signed(previous_y);
        current_x_fp=$signed(vehicle_x); current_y_fp=$signed(vehicle_y);
        // A conservative swept hull includes both orientations and the path
        // between them; the blast itself still measures rotated cell centres.
        next_sweep_left = (previous_x_fp < current_x_fp ? previous_x_fp : current_x_fp)+22'sd3072-sweep_extent;
        next_sweep_right = (previous_x_fp > current_x_fp ? previous_x_fp : current_x_fp)+22'sd3072+sweep_extent;
        next_sweep_top = (previous_y_fp < current_y_fp ? previous_y_fp : current_y_fp)+22'sd3072-sweep_extent;
        next_sweep_bottom = (previous_y_fp > current_y_fp ? previous_y_fp : current_y_fp)+22'sd3072+sweep_extent;
        trigger_mask=0; trigger_found=0; selected_tnt=0;
        for (tnt_index=0; tnt_index<`LP_MAX_TNT; tnt_index=tnt_index+1) begin
            tnt_x_pixels=saved_tnt_positions[tnt_index*16 +: 8];
            tnt_y_pixels=saved_tnt_positions[tnt_index*16+8 +: 8];
            if (tnt_index<saved_tnt_count && tnt_intact[tnt_index] &&
                sweep_right_fp > tnt_x_pixels*256 && sweep_left_fp < (tnt_x_pixels+8)*256 &&
                sweep_bottom_fp > tnt_y_pixels*256 && sweep_top_fp < (tnt_y_pixels+8)*256)
                trigger_mask[tnt_index]=1;
            if (!trigger_found && pending_triggers[tnt_index]) begin
                trigger_found=1; selected_tnt=tnt_index[1:0];
            end
        end
    end

    // One cell at a time shares the distance hardware across all nine cells.
    // The cell centre is 4, 12 or 20 pixels from the vehicle's grid origin.
    always @* begin
        case (cell_index)
            0,3,6: cell_local_x=-5'sd8;
            1,4,7: cell_local_x=0;
            default: cell_local_x=5'sd8;
        endcase
        if (cell_index<3) cell_local_y=-5'sd8;
        else if (cell_index<6) cell_local_y=0;
        else cell_local_y=5'sd8;
        cell_x_pixels=$signed(cell_world_x) >>> 8;
        cell_y_pixels=$signed(cell_world_y) >>> 8;
        delta_x=cell_x_position-(active_x+4);
        delta_y=cell_y_position-(active_y+4);
    end

    always @(posedge clk) begin
        if (reset) begin
            state<=IDLE; pending_triggers<=0; tnt_intact<={`LP_MAX_TNT{1'b1}};
            saved_x<=0; saved_y<=0; active_tnt<=0; active_x<=0; active_y<=0; cell_index<=0;
            saved_tilt<=0;
            sweep_left_fp<=0; sweep_right_fp<=0; sweep_top_fp<=0; sweep_bottom_fp<=0;
            saved_tnt_positions<=0; saved_tnt_count<=0; cell_x_position<=0; cell_y_position<=0;
            distance_x<=0; distance_y<=0;
            damage_valid<=0; damage_mask<=0; damage_frame_mask<=0;
            explosion_event<=0; damage_complete<=0;
        end else begin
            explosion_event<=0; damage_complete<=0;
            if (run_init && game_state==`LP_INIT_RUN) begin
                state<=IDLE; pending_triggers<=0; tnt_intact<={`LP_MAX_TNT{1'b1}};
                damage_valid<=0; damage_mask<=0; damage_frame_mask<=0;
            end else if (game_state!=`LP_RUN) begin
                state<=IDLE; pending_triggers<=0; damage_valid<=0;
                if (game_state==`LP_BUILD) tnt_intact<={`LP_MAX_TNT{1'b1}};
            end else begin
                case (state)
                    IDLE: if (movement_committed) begin
                        saved_x<=vehicle_x; saved_y<=vehicle_y;
                        saved_tilt<=sanitize_tilt(vehicle_tilt);
                        // Lookup/max, hull arithmetic and trigger comparisons
                        // have separate clocks instead of one long path.
                        sweep_left_fp<=next_sweep_left; sweep_right_fp<=next_sweep_right;
                        sweep_top_fp<=next_sweep_top; sweep_bottom_fp<=next_sweep_bottom;
                        saved_tnt_positions<=tnt_positions; saved_tnt_count<=tnt_count;
                        state<=CAPTURE_TRIGGERS;
                    end
                    CAPTURE_TRIGGERS: begin
                        pending_triggers<=trigger_mask;
                        state<=SELECT_TNT;
                    end
                    SELECT_TNT: begin
                        if (trigger_found) begin
                            active_tnt<=selected_tnt;
                            active_x<=saved_tnt_positions[selected_tnt*16 +: 8];
                            active_y<=saved_tnt_positions[selected_tnt*16+8 +: 8];
                            pending_triggers[selected_tnt]<=0;
                            damage_mask<=0; damage_frame_mask<=0; cell_index<=0;
                            state<=CELL_POSITION;
                        end else begin
                            // This clock follows the final damage transfer, so
                            // the pig/count outputs have settled before world checks.
                            damage_complete<=1; state<=IDLE;
                        end
                    end
                    CELL_POSITION: begin
                        cell_x_position<=cell_x_pixels; cell_y_position<=cell_y_pixels;
                        state<=CELL_DISTANCE;
                    end
                    CELL_DISTANCE: begin
                        distance_x<=delta_x<0 ? -delta_x : delta_x;
                        distance_y<=delta_y<0 ? -delta_y : delta_y;
                        state<=CHECK_CELL;
                    end
                    CHECK_CELL: begin
                        // Exact circular radius of 12 pixels, measured at cell centres.
                        if (distance_x<=12 && distance_y<=12 && distance_squared<=144) begin
                            if (intact_mask[cell_index] &&
                                build_grid[cell_index*`LP_PART_BITS +: `LP_PART_BITS]!=`LP_PART_EMPTY)
                                damage_mask[cell_index]<=1;
                            if (build_frames[cell_index] && frame_intact_mask[cell_index])
                                damage_frame_mask[cell_index]<=1;
                        end
                        if (cell_index==8) state<=SEND_DAMAGE;
                        else begin cell_index<=cell_index+1; state<=CELL_POSITION; end
                    end
                    SEND_DAMAGE: begin
                        tnt_intact[active_tnt]<=0;
                        damage_valid<=1; explosion_event<=1; state<=WAIT_DAMAGE;
                    end
                    WAIT_DAMAGE: if (damage_ready) begin
                        damage_valid<=0; state<=SELECT_TNT;
                    end
                    default: state<=IDLE;
                endcase
            end
        end
    end
endmodule
