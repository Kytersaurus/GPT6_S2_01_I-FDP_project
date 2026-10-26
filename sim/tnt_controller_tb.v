// Owner: Role 3 - Yap Ting; standalone TNT trigger and damage checks.
`timescale 1ns / 1ps
`include "game_defs.vh"

module tnt_controller_tb;
    reg clk=0, reset=1, run_init=0;
    reg [2:0] game_state=`LP_BUILD;
    wire init_ready;
    reg movement_committed=0;
    reg signed [`LP_COORD_BITS-1:0] previous_x=0, previous_y=0;
    reg signed [`LP_COORD_BITS-1:0] vehicle_x=0, vehicle_y=0;
    reg [2:0] tnt_count=0;
    reg [`LP_TNT_BITS-1:0] tnt_positions=0;
    reg [`LP_GRID_BITS-1:0] build_grid=0;
    reg [`LP_CELLS-1:0] build_frames=0;
    reg [`LP_CELLS-1:0] intact_mask=0;
    reg [`LP_CELLS-1:0] frame_intact_mask=0;
    wire [`LP_MAX_TNT-1:0] tnt_intact;
    reg damage_ready=0;
    wire damage_valid, explosion_event, damage_complete;
    wire [`LP_CELLS-1:0] damage_mask, damage_frame_mask;

    always #5 clk=~clk;

    tnt_controller dut(
        .clk(clk), .reset(reset), .run_init(run_init), .game_state(game_state),
        .init_ready(init_ready), .movement_committed(movement_committed),
        .previous_x(previous_x), .previous_y(previous_y),
        .vehicle_x(vehicle_x), .vehicle_y(vehicle_y),
        .tnt_count(tnt_count), .tnt_positions(tnt_positions),
        .build_grid(build_grid), .build_frames(build_frames),
        .intact_mask(intact_mask), .frame_intact_mask(frame_intact_mask),
        .tnt_intact(tnt_intact), .damage_valid(damage_valid),
        .damage_ready(damage_ready), .damage_mask(damage_mask),
        .damage_frame_mask(damage_frame_mask),
        .explosion_event(explosion_event), .damage_complete(damage_complete)
    );

    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask

    task start_run;
        begin
            game_state=`LP_INIT_RUN;
            run_init=1;
            clocks(2);
            if (!init_ready || tnt_intact !== {`LP_MAX_TNT{1'b1}})
                $fatal(1, "TNT module did not rearm during run initialisation");
            run_init=0;
            game_state=`LP_RUN;
            clocks(1);
        end
    endtask

    task wait_damage;
        integer waited;
        begin
            waited=0;
            while (!damage_valid && waited<64) begin clocks(1); waited=waited+1; end
            if (!damage_valid) $fatal(1,"TNT damage calculation stalled");
        end
    endtask

    initial begin
        // TNT 0 is at x=60,y=48. Cell 4 is close enough to be damaged.
        tnt_count=1;
        tnt_positions={48'd0,8'd48,8'd60};
        build_grid=0;
        build_grid[4*3 +: 3]=`LP_PART_PIG;
        build_frames=9'b000010000;
        intact_mask=9'b000010000;
        frame_intact_mask=9'b000010000;

        clocks(3);
        reset=0;
        clocks(1);
        if (tnt_intact!={`LP_MAX_TNT{1'b1}}) $fatal(1,"BUILD preview hides intact TNT");
        start_run();

        // The vehicle travels from x=0 to x=48 in one update. Its swept
        // footprint reaches the TNT even though the endpoint is before it.
        previous_x=0;
        previous_y=32*256;
        vehicle_x=48*256;
        vehicle_y=32*256;
        movement_committed=1;
        clocks(1);
        movement_committed=0;
        wait_damage();

        if (!explosion_event || tnt_intact[0] ||
            !damage_valid || !damage_mask[4] || !damage_frame_mask[4])
            $fatal(1, "TNT did not trigger or produce the expected damage masks");

        // The request must remain stable until Role 1 accepts it.
        clocks(2);
        if (!damage_valid || !damage_mask[4] || !damage_frame_mask[4])
            $fatal(1, "Damage request was not held under backpressure");

        damage_ready=1;
        clocks(1);
        damage_ready=0;
        if (damage_valid || damage_complete)
            $fatal(1, "Damage request did not complete");
        clocks(1);
        if (!damage_complete) $fatal(1,"Movement was not released after damage");

        // A triggered TNT cannot trigger repeatedly.
        clocks(2);
        movement_committed=1;
        clocks(1);
        movement_committed=0;
        if (explosion_event || damage_valid)
            $fatal(1, "Triggered TNT fired more than once");
        movement_committed=0;
        clocks(1);
        if (!damage_complete) $fatal(1,"No-explosion movement did not complete");

        // Both TNT in the same sweep must be processed before releasing world checks.
        start_run();
        tnt_count=2;
        tnt_positions={32'd0,8'd48,8'd61,8'd48,8'd60};
        movement_committed=1;
        clocks(1); movement_committed=0;
        wait_damage();
        if (!damage_valid || tnt_intact[0] || !tnt_intact[1])
            $fatal(1,"First of two TNT was not selected");
        damage_ready=1;
        clocks(1);
        damage_ready=0;
        if (damage_complete) $fatal(1,"World released before the second TNT");
        wait_damage();
        if (!damage_valid || !explosion_event || tnt_intact[1])
            $fatal(1,"Second touched TNT was lost");
        damage_ready=1; clocks(1); clocks(1);
        if (!damage_complete || damage_valid) $fatal(1,"Multiple TNT did not finish");
        damage_ready=0;

        // Initialisation represents both a fresh launch and retry, so TNT
        // becomes active again.
        start_run();
        if (!tnt_intact[0])
            $fatal(1, "Retry did not rearm TNT");

        // Leaving RUN cancels pending requests and restores the BUILD map preview.
        game_state=`LP_BUILD; clocks(1);
        if (damage_valid || tnt_intact!={`LP_MAX_TNT{1'b1}})
            $fatal(1,"BUILD did not cancel damage and restore TNT");

        $display("PASS tnt_controller_tb: swept trigger, one-shot state, damage masks, backpressure and retry");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "TNT test timed out");
    end
endmodule
