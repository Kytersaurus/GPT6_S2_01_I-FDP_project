// Owner: Role 1 - Kaushal. Board digit scanning and independent pig-death effect.
`timescale 1ns / 1ps
`include "game_defs.vh"
module timer_death_tb;
    reg clk=0,reset=1,init=0,tick=0,alive=1;
    reg [6:0] seconds=99;
    reg [2:0] state=`LP_RUN;
    reg [26:0] grid=0;
    wire [6:0] seg;
    wire [3:0] an;
    wire dp;
    wire [1:0] phase;
    wire signed [15:0] x,y;
    reg [3:0] seen=0;
    integer i;
    always #5 clk=~clk;
    seven_seg_timer #(.SCAN_CYCLES(2)) timer(.clk(clk),.reset(reset),.seconds(seconds),.seg(seg),.an(an),.dp(dp));
    pig_death_effect #(.PHASE_TICKS(2)) death(.clk(clk),.reset(reset),.run_init(init),.physics_tick(tick),
        .pig_alive(alive),.game_state(state),.build_grid(grid),.vehicle_x(16'sd2560),.vehicle_y(16'sd5120),
        .death_phase(phase),.death_x(x),.death_y(y));
    task clocks; input integer n; begin repeat(n) @(negedge clk); end endtask
    initial begin
        grid[4*3 +: 3]=`LP_PART_PIG;
        clocks(2);if(an!=15 || seg!=127 || !dp) $fatal(1,"Timer reset did not blank display");
        reset=0;
        for(i=0;i<8;i=i+1) begin
            clocks(1);
            case(an)
                4'b1110: begin if(seg!=7'b0010000 || !dp) $fatal(1,"Seconds units wrong");seen[0]=1;end
                4'b1101: begin if(seg!=7'b0110000 || !dp) $fatal(1,"Seconds tens wrong");seen[1]=1;end
                4'b1011: begin if(seg!=7'b1111001 || dp) $fatal(1,"Minute/decimal wrong");seen[2]=1;end
                4'b0111: begin if(seg!=7'b1000000 || !dp) $fatal(1,"Minutes tens wrong");seen[3]=1;end
                default: $fatal(1,"More than one digit enabled");
            endcase
        end
        if(seen!=15) $fatal(1,"Not all timer digits scanned");
        alive=0;clocks(1);
        if(phase!=1 || x!=22*256 || y!=32*256) $fatal(1,"Death position did not capture pig centre");
        state=`LP_FAIL; tick=1;clocks(2);
        if(phase!=2) $fatal(1,"Death animation stopped at result");
        clocks(2);if(phase!=3) $fatal(1,"Third death phase missing");
        clocks(2);tick=0;if(phase!=0) $fatal(1,"Death effect did not finish");
        init=1;alive=1;clocks(1);init=0;clocks(2);
        if(phase!=0) $fatal(1,"Retry replayed death");
        $display("PASS timer_death_tb: MM.SS digit scan/polarity, captured death position, result animation and retry");
        $finish;
    end
    initial begin #10000;$fatal(1,"Timer/death timed out");end
endmodule
