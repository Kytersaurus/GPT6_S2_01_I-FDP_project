`timescale 1ns / 1ps

// Based on the user's debouncer, including the optional stable-release check.
// At 100 MHz: freq_count = 19,999,999 gives a 200 ms lockout.
// RELEASE_CYCLES = 2,000,000 requires a 20 ms stable release.
module button_debouncer #(
    parameter integer RELEASE_CYCLES = 2000000
) (
    input CLOCK, reset,
    input btn,
    input [31:0] freq_count,
    output reg btn_pressed
);
    reg [31:0] count = 0;
    reg [1:0] state = 0;
    reg btn_sync_0 = 0;
    reg btn_sync_1 = 0;

    always @(posedge CLOCK) begin
        if (reset) begin
            btn_sync_0 <= 0;
            btn_sync_1 <= 0;
        end else begin
            btn_sync_0 <= btn;
            btn_sync_1 <= btn_sync_0;
        end
    end

    always @(posedge CLOCK) begin
        btn_pressed <= 0;
        if (reset) begin
            count <= 0;
            state <= 0;
        end else begin
            case (state)
                0: begin // IDLE: send one pulse when a press is detected.
                    if (btn_sync_1) begin
                        btn_pressed <= 1;
                        count <= 0;
                        state <= 1;
                    end
                end
                1: begin // LOCKOUT: ignore contact bounce after the press.
                    if (count < freq_count) begin
                        count <= count + 1;
                    end else begin
                        count <= 0;
                        state <= 2;
                    end
                end
                2: begin // WAIT FOR RELEASE: rearm only after a stable low.
                    if (!btn_sync_1) begin
                        if (count < RELEASE_CYCLES-1) begin
                            count <= count + 1;
                        end else begin
                            count <= 0;
                            state <= 0;
                        end
                    end else begin
                        count <= 0;
                    end
                end
                default: begin
                    count <= 0;
                    state <= 0;
                end
            endcase
        end
    end
endmodule
