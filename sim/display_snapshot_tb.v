// Owner: Role 4 - Marcus.
`timescale 1ns / 1ps
module display_snapshot_tb;
    reg game_clk=0, display_clk=0, game_reset=1, display_reset=1, frame_begin=0;
    reg [31:0] game_data=32'h12345678;
    wire [31:0] display_data;
    always #5 game_clk=~game_clk;
    always #37 display_clk=~display_clk;
    display_snapshot #(.WIDTH(32)) dut (
        .game_clk(game_clk),.game_reset(game_reset),.display_clk(display_clk),.display_reset(display_reset),
        .frame_begin(frame_begin),.game_data(game_data),.display_data(display_data)
    );
    task display_clocks;
        input integer count;
        begin repeat(count) @(negedge display_clk); end
    endtask
    task publish;
        begin frame_begin=1; display_clocks(1); frame_begin=0; end
    endtask
    initial begin
        display_clocks(4); game_reset=0; display_reset=0;
        display_clocks(12);
        if (display_data!=0) $fatal(1,"Snapshot changed outside frame boundary");
        publish();
        if (display_data!=32'h12345678) $fatal(1,"First snapshot corrupted");
        game_data=32'hfedcba98; display_clocks(12);
        if (display_data!=32'h12345678) $fatal(1,"Visible state changed mid-frame");
        publish();
        if (display_data!=32'hfedcba98) $fatal(1,"Second snapshot corrupted");
        game_reset=1; display_reset=1; display_clocks(3);
        game_data=32'h55aa55aa; game_reset=0; display_reset=0; display_clocks(12); publish();
        if (display_data!=32'h55aa55aa) $fatal(1,"Snapshot did not recover from reset");
        $display("PASS display_snapshot_tb: coherent clock-domain transfer, frame-boundary publication, reset recovery");
        $finish;
    end
    initial begin #10000; $fatal(1,"Snapshot test timed out"); end
endmodule
