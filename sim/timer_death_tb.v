// Owner: Role 1 - Kaushal. Board digit scanning and independent pig-death effect.
`timescale 1ns / 1ps
`include "game_defs.vh"
module timer_death_tb;
    reg clk=0,reset=1,init=0,tick=0,alive=1;
    // Match the controller/timer's full 0..255-second interface. A narrower
    // driver leaves the high timer input floating in Vivado simulation.
    reg [7:0] seconds=99;
    reg [2:0] state=`LP_RUN;
    reg [26:0] grid=0;
    wire [6:0] seg;
    wire [3:0] an;
    wire dp;
    wire [1:0] phase;
    wire signed [`LP_COORD_BITS-1:0] x,y;
    reg [3:0] seen=0;
    integer i;
    always #5 clk=~clk;
    seven_seg_timer #(.SCAN_CYCLES(2)) timer(.clk(clk),.reset(reset),.seconds(seconds),.seg(seg),.an(an),.dp(dp));
    pig_death_effect #(.PHASE_TICKS(2)) death(.clk(clk),.reset(reset),.run_init(init),.physics_tick(tick),
        .pig_alive(alive),.game_state(state),.build_grid(grid),.vehicle_x(20'sd2560),.vehicle_y(20'sd5120),.vehicle_tilt(4'sd0),
        .death_phase(phase),.death_x(x),.death_y(y));
    task clocks; input integer n; begin repeat(n) @(negedge clk); end endtask
    // Basys3 segment truth table (active low, gfedcba), independent of the
    // timer's minute/second arithmetic. Callers provide explicit M.SS digits.
    function [6:0] digit_segments;
        input [3:0] value;
        begin
            case(value)
                0:digit_segments=7'b1000000; 1:digit_segments=7'b1111001;
                2:digit_segments=7'b0100100; 3:digit_segments=7'b0110000;
                4:digit_segments=7'b0011001; 5:digit_segments=7'b0010010;
                6:digit_segments=7'b0000010; 7:digit_segments=7'b1111000;
                8:digit_segments=7'b0000000; 9:digit_segments=7'b0010000;
                default:digit_segments=7'b1111111;
            endcase
        end
    endfunction
    task check_scan;
        input [7:0] value;
        input [15:0] expected_digits;
        integer active_digit;
        begin
            seconds=value; seen=0;
            for(i=0;i<8;i=i+1) begin
                clocks(1);
                case(an)
                    4'b1110:active_digit=0;
                    4'b1101:active_digit=1;
                    4'b1011:active_digit=2;
                    4'b0111:active_digit=3;
                    default:$fatal(1,"Timer scan did not enable exactly one digit");
                endcase
                if(seg!==digit_segments(expected_digits[active_digit*4 +: 4]) || dp!==(active_digit!=2))
                    $fatal(1,"Timer value%0d digit%0d: seg=%b dp=%b expected digit%0d",
                        value,active_digit,seg,dp,expected_digits[active_digit*4 +: 4]);
                seen[active_digit]=1;
            end
            if(seen!==4'b1111) $fatal(1,"Not all timer digits scanned at value%0d",value);
        end
    endtask
    initial begin
        grid[4*3 +: 3]=`LP_PART_PIG;
        clocks(2);if(an!=15 || seg!=127 || !dp) $fatal(1,"Timer reset did not blank display");
        reset=0;
        check_scan(8'd99,16'h0139);
        check_scan(8'd0,16'h0000);
        check_scan(8'd9,16'h0009);
        check_scan(8'd59,16'h0059);
        check_scan(8'd60,16'h0100);
        check_scan(8'd127,16'h0207);
        check_scan(8'd128,16'h0208);
        check_scan(8'd255,16'h0415);
        alive=0;clocks(1);
        if(phase!=1 || x!=22*256 || y!=32*256) $fatal(1,"Death position did not capture pig centre");
        state=`LP_FAIL; tick=1;clocks(2);
        if(phase!=2) $fatal(1,"Death animation stopped at result");
        clocks(2);if(phase!=3) $fatal(1,"Third death phase missing");
        clocks(2);tick=0;if(phase!=0) $fatal(1,"Death effect did not finish");
        init=1;alive=1;clocks(1);init=0;clocks(2);
        if(phase!=0) $fatal(1,"Retry replayed death");
        $display("PASS timer_death_tb: full 8-bit M.SS boundary scans/polarity, captured death position, result animation and retry");
        $finish;
    end
    initial begin #10000;$fatal(1,"Timer/death timed out");end
endmodule
