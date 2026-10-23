// Owner: Role 4 - Marcus. Short TNT explosion animation for the right OLED.
`timescale 1ns / 1ps
`include "game_defs.vh"
// When a TNT's intact bit falls, its two-bit phase steps 1 -> 2 -> 3 -> 0,
// holding each phase for PHASE_TICKS physics ticks. Drawing only; no game effect.
module explosion_fx #(parameter integer PHASE_TICKS = 8) (
    input wire clk, reset, run_init, physics_tick,
    input wire [`LP_MAX_TNT-1:0] tnt_intact,
    output reg [2*`LP_MAX_TNT-1:0] blast_phase
);
    reg [`LP_MAX_TNT-1:0] previous_intact;
    reg [7:0] phase_ticks [0:`LP_MAX_TNT-1];
    integer index;
    always @(posedge clk) begin
        if (reset || run_init) begin
            // Retry restores the blocks; their rising bits never start an explosion.
            previous_intact <= tnt_intact; blast_phase <= 0;
            for (index = 0; index < `LP_MAX_TNT; index = index + 1) phase_ticks[index] <= 0;
        end else begin
            previous_intact <= tnt_intact;
            for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
                if (previous_intact[index] && !tnt_intact[index]) begin
                    blast_phase[index*2 +: 2] <= 2'd1; phase_ticks[index] <= 0;
                end else if (blast_phase[index*2 +: 2] != 0 && physics_tick) begin
                    if (phase_ticks[index] == PHASE_TICKS-1) begin
                        phase_ticks[index] <= 0;
                        blast_phase[index*2 +: 2] <= (blast_phase[index*2 +: 2] == 2'd3) ? 2'd0
                                                     : blast_phase[index*2 +: 2] + 2'd1;
                    end else phase_ticks[index] <= phase_ticks[index] + 1;
                end
            end
        end
    end
endmodule
