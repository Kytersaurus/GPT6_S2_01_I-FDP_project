// Owner: Role 1 - Kaushal. Diary navigation and left-OLED action buttons.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_controller (
    input wire clk, reset, input_enabled, run_init, physics_tick, launch_event,
    input wire [2:0] game_state,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_right, mouse_event, next_press,
    // Kyle connects availability/readiness when fan and rocket physics is merged.
    input wire fan_available, rocket_available, rocket_ready,
    output reg launch_req, edit_req, guide_open_req, guide_close_req,
    output reg level_close_req, level_select_req,
    output reg [`LP_LEVEL_BITS-1:0] selected_level,
    output reg [1:0] diary_page,
    output reg [2:0] master_volume,
    output reg [1:0] run_page,
    output reg boost_req,
    output reg engine_on, fan_on, rocket_req, sound_muted,
    output wire launch_flash
);
    reg left_was_down;
    reg [3:0] launch_ticks;
    assign launch_flash = launch_ticks != 0;
    always @(posedge clk) begin
        if (reset) begin
            left_was_down<=0; diary_page<=0; master_volume<=4; engine_on<=1; fan_on<=0; sound_muted<=0;
            run_page<=0; boost_req<=0;
            launch_req<=0; edit_req<=0; guide_open_req<=0; guide_close_req<=0;
            rocket_req<=0; launch_ticks<=0;
            level_close_req<=0; level_select_req<=0; selected_level<=0;
        end else begin
            launch_req<=0; edit_req<=0; guide_open_req<=0; guide_close_req<=0; rocket_req<=0;
            level_close_req<=0; level_select_req<=0;
            boost_req<=0;
            if (run_init) begin engine_on<=1; fan_on<=0; run_page<=0; end
            if (!fan_available || game_state!=`LP_RUN) fan_on<=0;
            if (game_state!=`LP_RUN) launch_ticks<=0;
            else if (launch_event) launch_ticks<=8;
            else if (physics_tick && launch_ticks!=0) launch_ticks<=launch_ticks-1;
            if (game_state==`LP_GUIDE && next_press && diary_page<2) diary_page<=diary_page+1;
            if (mouse_event) begin
                // Track held presses even when the left view is hidden.
                left_was_down<=mouse_left;
                if (input_enabled && mouse_left && !left_was_down && !mouse_right) begin
                    if (((game_state==`LP_GUIDE && diary_page==3) ||
                         (game_state==`LP_RUN && run_page==2)) && mouse_y>=28 && mouse_y<44) begin
                        if (mouse_x>=8 && mouse_x<36 && master_volume>0) master_volume<=master_volume-1;
                        else if (mouse_x>=60 && mouse_x<88 && master_volume<4) master_volume<=master_volume+1;
                    end else if (game_state==`LP_RUN && run_page==2 && mouse_y>=46 && mouse_y<54) begin
                        sound_muted <= !sound_muted;
                    end else if (game_state==`LP_SETTINGS) begin
                        if (mouse_x<28 && mouse_y>=55 && mouse_y<64) level_close_req<=1;
                        else if (mouse_x>=8 && mouse_x<88 && mouse_y>=12 && mouse_y<26) begin
                            guide_open_req<=1; diary_page<=3;
                        end
                    end else if (game_state==`LP_LEVEL_SELECT) begin
                        if (mouse_x<28 && mouse_y>=55 && mouse_y<64) level_close_req<=1;
                        // Three level tiles; the bottom-right one is empty.
                        else if (((mouse_x>=2 && mouse_x<46) || (mouse_x>=50 && mouse_x<94)) &&
                                 ((mouse_y>=12 && mouse_y<32) || (mouse_y>=34 && mouse_y<54)) &&
                                 !(mouse_y>=34 && mouse_x>=50)) begin
                            selected_level <= {mouse_y>=34, mouse_x>=50};
                            level_select_req<=1;
                        end
                    end else if (game_state==`LP_BUILD && mouse_y>=55 && mouse_y<64) begin
                        if (mouse_x<18) launch_req<=1;
                        else if (mouse_x>=64 && mouse_x<80) begin guide_open_req<=1; diary_page<=0; end
                    end else if (game_state==`LP_GUIDE && mouse_y>=55 && mouse_y<64) begin
                        if (mouse_x<28) guide_close_req<=1;
                        else if (diary_page!=3 && mouse_x>=32 && mouse_x<95)
                            diary_page<=mouse_x<53 ? 0 : mouse_x<74 ? 1 : 2;
                    end else if ((game_state==`LP_SUCCESS || game_state==`LP_FAIL) && mouse_y>=55 && mouse_y<64) begin
                        if (mouse_x<28) launch_req<=1;
                        else if (mouse_x>=32 && mouse_x<60) edit_req<=1;
                        else if (mouse_x>=64 && mouse_x<96) begin guide_open_req<=1; diary_page<=0; end
                    end else if (game_state==`LP_RUN) begin
                        if (run_page==1 && mouse_x>=56 && mouse_x<84 && mouse_y>=14 && mouse_y<24) edit_req<=1;
                        else if (mouse_y>=55 && mouse_y<64) begin
                            if (mouse_x<32) run_page<=0;
                            else if (mouse_x<64) run_page<=1;
                            else if (mouse_x<96) run_page<=2;
                        end else if (mouse_y<10) begin
                            if (mouse_x>=66 && mouse_x<96) launch_req<=1;
                            else if (run_page!=1 && mouse_x>=40 && mouse_x<66) edit_req<=1;
                        end else if (run_page==0 && mouse_x>=4 && mouse_x<92) begin
                            if (mouse_y>=12 && mouse_y<22) engine_on<=!engine_on;
                            else if (mouse_y>=23 && mouse_y<33 && fan_available) fan_on<=!fan_on;
                            else if (mouse_y>=34 && mouse_y<44) boost_req<=1;
                            else if (mouse_y>=45 && mouse_y<54 && rocket_available && rocket_ready) rocket_req<=1;
                        end
                    end
                end
            end
            if (game_state!=`LP_GUIDE && game_state!=`LP_SETTINGS && !guide_open_req) diary_page<=0;
        end
    end
endmodule
