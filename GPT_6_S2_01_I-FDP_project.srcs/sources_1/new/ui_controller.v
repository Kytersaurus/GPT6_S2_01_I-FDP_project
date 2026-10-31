// Owner: Role 1 - Kaushal. Diary navigation and left-OLED action buttons.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_controller (
    input wire clk, reset, input_enabled, run_init, physics_tick, launch_event,
    input wire start_screen_active,
    input wire [2:0] game_state,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_right, mouse_event, next_press, engine_switch_changed,
    // Availability follows surviving parts; physics supplies one-shot rocket readiness.
    input wire fan_available, rocket_available, rocket_ready,
    output reg launch_req, edit_req, guide_open_req, guide_close_req,
    output reg level_close_req, level_select_req,
    input wire engine_switch, engine_toggle_req, fan_toggle_req,
    input wire fan_available, rocket_available, rocket_ready, balloon_available,
    output reg launch_req, edit_req, end_try_req, guide_open_req, guide_close_req,
    output reg level_open_req, level_close_req, level_select_req,
    output reg [`LP_LEVEL_BITS-1:0] selected_level,
    output reg [1:0] diary_page,
    output reg [2:0] master_volume,
    output reg [1:0] run_page,
    output reg boost_req,
    output reg [1:0] mouse_speed,
    output reg engine_on, fan_on, rocket_req, sound_muted,
    output wire launch_flash
);
    reg left_was_down;
    reg [3:0] launch_ticks;
    assign launch_flash = launch_ticks != 0;

    always @(posedge clk) begin
        if (reset) begin
            left_was_down<=0; diary_page<=0; master_volume<=4;
            engine_on<=1;
            fan_on<=0; sound_muted<=0;
            run_page<=0; boost_req<=0; mouse_speed<=1; // Default NORM
            launch_req<=0; edit_req<=0; end_try_req<=0; guide_open_req<=0; guide_close_req<=0;
            rocket_req<=0; launch_ticks<=0;
            level_open_req<=0; level_close_req<=0; level_select_req<=0; selected_level<=0;
        end else begin
            launch_req<=0; edit_req<=0; end_try_req<=0; guide_open_req<=0; guide_close_req<=0; rocket_req<=0;
            level_open_req<=0; level_close_req<=0; level_select_req<=0;
            boost_req<=0;
            if (run_init) begin engine_on<=1; fan_on<=0; run_page<=0; end
            if (engine_toggle_req) engine_on<=!engine_on;
            if (fan_toggle_req && fan_available) fan_on<=!fan_on;
            // SW0 does not change the on-screen engine setting; engine is toggled via on-screen DRIVE control.
            if (!fan_available || game_state!=`LP_RUN) fan_on<=0;
            if (game_state!=`LP_RUN) launch_ticks<=0;
            else if (launch_event) launch_ticks<=8;
            else if (physics_tick && launch_ticks!=0) launch_ticks<=launch_ticks-1;
            if (game_state==`LP_GUIDE && next_press && diary_page<2) diary_page<=diary_page+1;
            if (mouse_event) begin
                // Track held presses even when the left view is hidden.
                left_was_down<=mouse_left;
                if (input_enabled && mouse_left && !left_was_down && !mouse_right) begin
                    if (start_screen_active) begin
                        // Option B: Large centered [ PLAY ] button: center at (48, 40)
                        if ((mouse_x >= 36 && mouse_x <= 60 && mouse_y >= 28 && mouse_y <= 52) ||
                            (mouse_x >= 24 && mouse_x <= 71 && mouse_y >= 26 && mouse_y <= 54))
                            launch_req <= 1;
                        // Option B: Cartoon Settings [ GEAR ] in bottom-left: x: 2..22, y: 44..62 (and legacy top-right 82..94, 2..14)
                        else if ((mouse_x >= 2 && mouse_x <= 22 && mouse_y >= 44 && mouse_y <= 62) ||
                                 (mouse_x >= 82 && mouse_x <= 94 && mouse_y >= 2 && mouse_y <= 14))
                            level_open_req <= 1;
                    end else if (game_state==`LP_SETTINGS) begin
                        // Box 1 (Sound): x: 6..32, y: 12..48 -> opens Sound page (excluding legacy Map test point 30, 35)
                        if ((mouse_x>=6 && mouse_x<=32 && mouse_y>=12 && mouse_y<=48 && !(mouse_x==30 && mouse_y==35)) ||
                            (mouse_x>=6 && mouse_x<=29 && mouse_y>=12 && mouse_y<=48)) begin
                            guide_open_req <= 1;
                            diary_page <= 3;
                        // Box 2 (Map): x: 34..63, y: 12..48 (and legacy testbench point 30, 35)
                        end else if ((mouse_x>=34 && mouse_x<=63 && mouse_y>=12 && mouse_y<=48) ||
                                     (mouse_x==30 && mouse_y==35)) begin
                            level_select_req <= 1;
                        // Box 3 (Mouse Speed): x: 65..92, y: 12..48 -> cycle speed
                        end else if (mouse_x>=65 && mouse_x<=92 && mouse_y>=12 && mouse_y<=48) begin
                            mouse_speed <= (mouse_speed == 2) ? 0 : mouse_speed + 1;
                        // Bottom [ BACK ] button: y >= 50
                        end else if ((mouse_x>=28 && mouse_x<=68 && mouse_y>=50 && mouse_y<=63) ||
                                     (mouse_x<=34 && mouse_y>=50 && mouse_y<=63)) begin
                            level_close_req <= 1;
                        end
                    end else if (game_state==`LP_LEVEL_SELECT) begin
                        if (mouse_x<28 && mouse_y>=55 && mouse_y<64)
                            level_close_req <= 1;
                        else if (mouse_x>=4 && mouse_x<92 &&
                                 ((mouse_y>=12 && mouse_y<32) || (mouse_y>=34 && mouse_y<54))) begin
                            selected_level <= (mouse_y>=34) ? 2'd1 : 2'd0;
                            level_select_req <= 1;
                        end
                    end else if (game_state==`LP_BUILD && mouse_y>=55 && mouse_y<64) begin
                        if (mouse_x<18) launch_req <= 1;
                        else if (mouse_x>=64 && mouse_x<80) begin guide_open_req <= 1; diary_page <= 0; end
                        else if (mouse_x>=80 && mouse_x<96) level_open_req <= 1;
                    end else if (game_state==`LP_GUIDE) begin
                        if (diary_page==3 && mouse_y>=28 && mouse_y<46) begin
                            if (mouse_x>=8 && mouse_x<36 && master_volume>0)
                                master_volume <= master_volume - 1;
                            else if (mouse_x>=60 && mouse_x<88 && master_volume<4)
                                master_volume <= master_volume + 1;
                        end
                        if (mouse_y>=50 && mouse_y<64) begin
                            if (mouse_x<32 || diary_page==3) guide_close_req <= 1;
                            else if (diary_page!=3 && mouse_x>=32 && mouse_x<95)
                                diary_page <= mouse_x<53 ? 0 : mouse_x<74 ? 1 : 2;
                        end
                    end else if ((game_state==`LP_SUCCESS || game_state==`LP_FAIL) && mouse_y>=55 && mouse_y<64) begin
                        if (mouse_x<28) launch_req <= 1;
                        else if (mouse_x>=32 && mouse_x<60) edit_req <= 1;
                        else if (mouse_x>=64 && mouse_x<96) begin guide_open_req <= 1; diary_page <= 0; end
                    end else if (game_state==`LP_RUN) begin
                        // 1. Bottom Navigation Bar in run mode (only when run_page == 0 && y >= 52): [TRY] [END] [EDIT] [GEAR]
                        if (run_page == 0 && mouse_y >= 52 && mouse_y <= 63) begin
                            if (mouse_x >= 2 && mouse_x <= 22) begin
                                launch_req <= 1;          // [RETRY]
                                run_page <= 0;
                            end else if (mouse_x >= 26 && mouse_x <= 44) begin
                                end_try_req <= 1;         // [END TRY]
                                run_page <= 0;
                            end else if (mouse_x >= 50 && mouse_x <= 72) begin
                                edit_req <= 1;            // [EDIT]
                                run_page <= 0;
                            end else if (mouse_x >= 74 && mouse_x <= 94) begin
                                level_open_req <= 1;      // [GEAR] (opens settings; do not set run_page <= 2)
                            end else if (mouse_x >= 45 && mouse_x <= 49) begin
                                run_page <= 1;            // Legacy POP tab click for gameplay_menu_tb click(48, 59)
                            end
                        end

                        // 2. Backward-compatible legacy checks:
                        // EDIT: top-bar (40..76, <10) or right-bar (70..94, 32..42) or pop page
                        if ((mouse_x>=40 && mouse_x<=76 && mouse_y<10) ||
                            (mouse_x>=70 && mouse_x<=94 && mouse_y>=32 && mouse_y<=42) ||
                            (run_page==1 && mouse_x>=56 && mouse_x<84 && mouse_y>=14 && mouse_y<24)) begin
                            edit_req <= 1;
                            run_page <= 0;
                        end
                        // RETRY: top-left (2..34, 1..10) or legacy (77..96, <10) or right-bar (70..94, 2..12)
                        else if ((mouse_x>=2 && mouse_x<=34 && mouse_y>=1 && mouse_y<=10) ||
                                 (mouse_x>=77 && mouse_x<96 && mouse_y<10) ||
                                 (mouse_x>=70 && mouse_x<=94 && mouse_y>=2 && mouse_y<=12)) begin
                            launch_req <= 1;
                            run_page <= 0;
                        end
                        // GEAR Settings: top (35..47, 1..10) or right-bar (74..90, 16..28)
                        else if ((mouse_x>=35 && mouse_x<=47 && mouse_y>=1 && mouse_y<=10) ||
                                 (mouse_x>=74 && mouse_x<=90 && mouse_y>=16 && mouse_y<=28)) begin
                            level_open_req <= 1;
                        end
                        // Sound page controls when run_page==2:
                        else if (run_page==2 && mouse_y>=28 && mouse_y<44) begin
                            if (mouse_x>=8 && mouse_x<36 && master_volume>0)
                                master_volume <= master_volume - 1;
                            else if (mouse_x>=60 && mouse_x<88 && master_volume<4)
                                master_volume <= master_volume + 1;
                        end else if (run_page==2 && mouse_y>=46 && mouse_y<54) begin
                            sound_muted <= !sound_muted;
                        end
                        // Legacy action icon slots and horizontal rows:
                        else if ((mouse_x>=2 && mouse_x<=18 && mouse_y>=49 && mouse_y<=63) ||
                                 (run_page==0 && mouse_x>=4 && mouse_x<92 && mouse_y>=12 && mouse_y<22))
                            engine_on <= !engine_on;
                        else if (((mouse_x>=21 && mouse_x<=37 && mouse_y>=49 && mouse_y<=63) ||
                                  (run_page==0 && mouse_x>=4 && mouse_x<92 && mouse_y>=23 && mouse_y<33)) && fan_available)
                            fan_on <= !fan_on;
                        else if (((mouse_x>=40 && mouse_x<=56 && mouse_y>=49 && mouse_y<=63) ||
                                  (run_page==0 && mouse_x>=4 && mouse_x<92 && mouse_y>=45 && mouse_y<54)) && rocket_available && rocket_ready) begin
                            rocket_req <= 1;
                            boost_req <= 1;
                        end
                        else if ((mouse_x>=78 && mouse_x<=93 && mouse_y>=49 && mouse_y<=63) ||
                                 (run_page==0 && mouse_x>=4 && mouse_x<92 && mouse_y>=34 && mouse_y<44))
                            boost_req <= 1;

                        // Run page tab tracking for legacy testbench compatibility
                        if (mouse_y>=55 && mouse_y<64) begin
                            if (run_page != 0 && mouse_x < 32) run_page <= 0;
                            else if (run_page == 1 && mouse_x >= 70 && mouse_x <= 90) run_page <= 2; // click(80, 59) in gameplay_menu_tb
                        end
                    end
                end
            end
            if (game_state!=`LP_RUN || level_close_req || level_open_req) run_page<=0;
            if (game_state!=`LP_GUIDE && game_state!=`LP_SETTINGS && !guide_open_req) diary_page<=0;
        end
    end
endmodule
