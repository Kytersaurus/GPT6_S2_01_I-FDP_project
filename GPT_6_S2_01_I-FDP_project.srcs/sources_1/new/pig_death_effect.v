// Owner: Role 1 - Kaushal; Role 4 draws this short cartoon effect in world coordinates.
`timescale 1ns / 1ps
`include "game_defs.vh"
module pig_death_effect #(parameter integer PHASE_TICKS=6) (
    input wire clk, reset, run_init, physics_tick, pig_alive,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire signed [15:0] vehicle_x, vehicle_y,
    output reg [1:0] death_phase,
    output reg signed [15:0] death_x, death_y
);
    reg was_alive;
    reg [3:0] ticks;
    integer index;
    always @(posedge clk) begin
        if (reset || run_init || game_state==`LP_BUILD) begin
            was_alive<=pig_alive; death_phase<=0; ticks<=0; death_x<=0; death_y<=0;
        end else begin
            was_alive<=pig_alive;
            if (game_state==`LP_RUN && was_alive && !pig_alive) begin
                for (index=0; index<9; index=index+1)
                    if (build_grid[index*3 +: 3]==`LP_PART_PIG) begin
                        death_x<=vehicle_x+((index%3)*8+4)*256;
                        death_y<=vehicle_y+((index/3)*8+4)*256;
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
