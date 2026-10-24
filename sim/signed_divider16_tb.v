// Owner: Role 2 - Kyle; shared integration checks for the force/mass divider.
`timescale 1ns / 1ps
module signed_divider16_tb;
    reg clk=0,reset=1,start=0;
    reg signed [15:0] dividend=0;
    reg [7:0] divisor=0;
    wire busy,done,zero;
    wire signed [15:0] quotient,remainder;
    integer a,b,i,j,k,expected_q,expected_r;
    always #5 clk=~clk;
    signed_divider16 dut(.clk(clk),.reset(reset),.start(start),.dividend(dividend),.divisor(divisor),
        .busy(busy),.done(done),.divide_by_zero(zero),.quotient(quotient),.remainder(remainder));
    task clocks;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task divide;
        input signed [15:0] number;
        input integer denominator;
        begin
            dividend=number;divisor=denominator;start=1;clocks(1);start=0;
            if (!busy || done) $fatal(1,"Divider did not accept nonzero request");
            // Change inputs and try another start while busy: the accepted operands must stay fixed.
            dividend=123;divisor=0;start=1;
            for (k=1;k<=16;k=k+1) begin
                clocks(1);
                if (k<16 && (!busy || done)) $fatal(1,"Division completed too early");
            end
            start=0;
            expected_q=number/denominator;expected_r=number%denominator;
            if (busy || !done || zero || $signed(quotient)!=expected_q || $signed(remainder)!=expected_r)
                $fatal(1,"%0d / %0d returned q=%0d r=%0d",number,denominator,quotient,remainder);
            clocks(1);if (done || busy) $fatal(1,"Done repeated or busy request replayed");
        end
    endtask
    initial begin
        clocks(3);reset=0;clocks(1);
        for (i=0;i<8;i=i+1) begin
            case(i)
                0:a=-32768;1:a=-32767;2:a=-255;3:a=-1;
                4:a=0;5:a=1;6:a=255;default:a=32767;
            endcase
            for (j=0;j<6;j=j+1) begin
                case(j) 0:b=1;1:b=2;2:b=3;3:b=7;4:b=13;default:b=255;endcase
                divide(a,b);
            end
        end
        for(i=0;i<128;i=i+1) divide($signed($random),1+($urandom%255));
        dividend=-12;divisor=0;start=1;clocks(1);start=0;
        if(busy || !done || !zero || quotient!=0 || remainder!=0) $fatal(1,"Zero-mass guard failed");
        clocks(1);divisor=13;start=1;clocks(1);start=0;clocks(5);reset=1;clocks(1);reset=0;clocks(20);
        if(busy || done) $fatal(1,"Reset did not cancel in-flight division");
        $display("PASS signed_divider16_tb: signed extremes/random operands, quotient/remainder, 16-cycle latency, captured inputs, busy suppression, zero divisor and reset");
        $finish;
    end
    initial begin #200000; $fatal(1,"Divider test timed out"); end
endmodule
