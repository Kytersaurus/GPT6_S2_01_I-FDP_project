// Owner: Role 1 - Kaushal; Role 4 draws this short cartoon effect in world coordinates.
`timescale 1ns / 1ps
`include "game_defs.vh"
module pig_death_effect #(parameter integer PHASE_TICKS=6) (
    input wire clk, reset, run_init, physics_tick, pig_alive,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire signed [`LP_COORD_BITS-1:0] vehicle_x, vehicle_y,
    input wire signed [`LP_TILT_BITS-1:0] vehicle_tilt,
    output reg [1:0] death_phase,
    output reg signed [`LP_COORD_BITS-1:0] death_x, death_y
);
    `include "rotation_geometry.vh"
    reg was_alive;
    reg [3:0] ticks;
    integer index;
    reg pig_found;
    reg signed [4:0] pig_local_x, pig_local_y;
    wire signed [9:0] tilt_cos = rotation_cos(sanitize_tilt(vehicle_tilt));
    wire signed [9:0] tilt_sin = rotation_sin(sanitize_tilt(vehicle_tilt));
    wire signed [15:0] pig_offset_x = pig_local_x*tilt_cos - pig_local_y*tilt_sin;
    wire signed [15:0] pig_offset_y = pig_local_x*tilt_sin + pig_local_y*tilt_cos;
    always @* begin
        pig_local_x=0; pig_local_y=0; pig_found=0;
        for (index=0; index<9; index=index+1)
            if (build_grid[index*3 +: 3]==`LP_PART_PIG) begin
                pig_found=1;
                pig_local_x=(index%3)*8-8;
                pig_local_y=(index/3)*8-8;
            end
    end
    always @(posedge clk) begin
        if (reset || run_init || game_state==`LP_BUILD) begin
            was_alive<=pig_alive; death_phase<=0; ticks<=0; death_x<=0; death_y<=0;
        end else begin
            was_alive<=pig_alive;
            if (game_state==`LP_RUN && was_alive && !pig_alive) begin
                if (pig_found) begin
                    death_x<=$signed(vehicle_x)+22'sd3072+pig_offset_x;
                    death_y<=$signed(vehicle_y)+22'sd3072+pig_offset_y;
                end
                death_phase<=1; ticks<=0;
            end else if (death_phase!=0 && physics_tick) begin
                if (ticks==PHASE_TICKS-1) begin
                    ticks<=0; death_phase<=death_phase==3 ? 0 : death_phase+1;
                end else ticks<=ticks+1;
            end
        end
    end
endmodule
