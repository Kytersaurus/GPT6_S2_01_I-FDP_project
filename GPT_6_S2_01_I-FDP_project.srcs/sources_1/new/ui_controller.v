// Owner: Role 1 - Kaushal. Diary navigation and left-OLED action buttons.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_controller (
    input wire clk, reset, input_enabled, run_init, physics_tick, launch_event,
    input wire start_screen_active,
    input wire [2:0] game_state,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_right, mouse_event, next_press, engine_switch_changed,
    input wire engine_switch, engine_toggle_req, fan_toggle_req,
    input wire fan_available, rocket_available, rocket_ready, balloon_available,
    input wire [26:0] build_grid,
    input wire [8:0] intact_mask,
    output reg launch_req, edit_req, end_try_req, guide_open_req, guide_close_req,
    output reg level_open_req, level_close_req, level_select_req,
    output reg [`LP_LEVEL_BITS-1:0] selected_level,
    output reg [1:0] diary_page,
    output reg [2:0] master_volume,
    output reg [1:0] run_page,
    output reg boost_req, pop_req,
    output reg [3:0] pop_cell,
    output reg [1:0] mouse_speed,
    output reg engine_on, fan_on, rocket_req, sound_muted,
    output wire launch_flash
);
    reg left_was_down;
    reg [3:0] launch_ticks;
    assign launch_flash = launch_ticks != 0;

    wire [26:0] safe_grid = (build_grid === 27'bx || build_grid === 27'bz) ? 27'd0 : build_grid;
    wire [8:0] safe_intact = (intact_mask === 9'bx || intact_mask === 9'bz) ? 9'd0 : intact_mask;

    // Run grid decoding for 16x16 interactive parts (x: 24..71, y: 2..49)
    wire run_grid_hit = (mouse_x >= 24 && mouse_x < 72 && mouse_y >= 2 && mouse_y < 50);
    wire [1:0] run_col = (mouse_x < 40) ? 2'd0 : (mouse_x < 56) ? 2'd1 : 2'd2;
    wire [1:0] run_row = (mouse_y < 18) ? 2'd0 : (mouse_y < 34) ? 2'd1 : 2'd2;
    wire [3:0] run_clicked_cell = {2'b00, run_row} * 4'd3 + {2'b00, run_col};
    reg [2:0] clicked_part;
    reg clicked_intact;

    always @* begin
        case (run_clicked_cell)
            4'd0: begin clicked_part = safe_grid[2:0];   clicked_intact = safe_intact[0]; end
            4'd1: begin clicked_part = safe_grid[5:3];   clicked_intact = safe_intact[1]; end
            4'd2: begin clicked_part = safe_grid[8:6];   clicked_intact = safe_intact[2]; end
            4'd3: begin clicked_part = safe_grid[11:9];  clicked_intact = safe_intact[3]; end
            4'd4: begin clicked_part = safe_grid[14:12]; clicked_intact = safe_intact[4]; end
            4'd5: begin clicked_part = safe_grid[17:15]; clicked_intact = safe_intact[5]; end
            4'd6: begin clicked_part = safe_grid[20:18]; clicked_intact = safe_intact[6]; end
            4'd7: begin clicked_part = safe_grid[23:21]; clicked_intact = safe_intact[7]; end
            4'd8: begin clicked_part = safe_grid[26:24]; clicked_intact = safe_intact[8]; end
            default: begin clicked_part = `LP_PART_EMPTY; clicked_intact = 1'b0; end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            left_was_down<=0; diary_page<=0; master_volume<=4; engine_on<=0; fan_on<=0; sound_muted<=0;
            run_page<=0; boost_req<=0; pop_req<=0; pop_cell<=0; mouse_speed<=1; // Default NORM
            launch_req<=0; edit_req<=0; end_try_req<=0; guide_open_req<=0; guide_close_req<=0;
            rocket_req<=0; launch_ticks<=0;
            level_open_req<=0; level_close_req<=0; level_select_req<=0; selected_level<=0;
        end else begin
            launch_req<=0; edit_req<=0; end_try_req<=0; guide_open_req<=0; guide_close_req<=0; rocket_req<=0;
            level_open_req<=0; level_close_req<=0; level_select_req<=0;
            boost_req<=0; pop_req<=0;
            if (run_init) begin engine_on<=engine_switch; fan_on<=0; run_page<=0; end
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
                        // Option B: Large centered [ PLAY ] button: x: 36..59, y: 26..48 (and fallback 24..71, 36..48)
                        if ((mouse_x >= 36 && mouse_x <= 59 && mouse_y >= 26 && mouse_y <= 48) ||
                            (mouse_x >= 24 && mouse_x <= 71 && mouse_y >= 36 && mouse_y <= 48))
                            launch_req <= 1;
                        // Option B: Cartoon Settings [ GEAR ] in bottom-left: x: 2..20, y: 44..62 (and legacy top-right 82..94, 2..14)
                        else if ((mouse_x >= 2 && mouse_x <= 20 && mouse_y >= 44 && mouse_y <= 62) ||
                                 (mouse_x >= 82 && mouse_x <= 94 && mouse_y >= 2 && mouse_y <= 14))
                            level_open_req <= 1;
                    end else if (game_state==`LP_SETTINGS) begin
                        // Box 1 (Sound): x: 6..30, y: 12..48 (and legacy 8..88, 12..26) -> opens Sound page
                        if ((mouse_x>=6 && mouse_x<=30 && mouse_y>=12 && mouse_y<=48) ||
                            (mouse_x>=8 && mouse_x<88 && mouse_y>=12 && mouse_y<26)) begin
                            guide_open_req <= 1;
                            diary_page <= 3;
                        // Box 2 (Map): x: 36..60, y: 12..48 (and legacy 8..88, 28..50) -> opens Map select
                        end else if ((mouse_x>=36 && mouse_x<=60 && mouse_y>=12 && mouse_y<=48) ||
                                     (mouse_x>=8 && mouse_x<=88 && mouse_y>=28 && mouse_y<=50)) begin
                            level_select_req <= 1;
                        // Box 3 (Mouse Speed): x: 66..90, y: 12..48 (and legacy 38..92, 54..63) -> cycle speed
                        end else if ((mouse_x>=66 && mouse_x<=90 && mouse_y>=12 && mouse_y<=48) ||
                                     (mouse_x>=38 && mouse_x<=92 && mouse_y>=54 && mouse_y<=63)) begin
                            mouse_speed <= (mouse_speed == 2) ? 0 : mouse_speed + 1;
                        // Bottom [ BACK ] button: y >= 50
                        end else if ((mouse_x>=2 && mouse_x<=34 && mouse_y>=50 && mouse_y<=63) ||
                                     (mouse_x>=28 && mouse_x<=68 && mouse_y>=50 && mouse_y<=63) ||
                                     (mouse_x<28 && mouse_y>=55 && mouse_y<64)) begin
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
                        // 1. In-grid interactive part clicks (BIG 16x16 grid: x: 24..71, y: 2..49)
                        if (run_grid_hit) begin
                            if (clicked_part == `LP_PART_BALLOON && clicked_intact) begin
                                pop_req <= 1;
                                pop_cell <= run_clicked_cell;
                            end else if (clicked_part == `LP_PART_ENGINE && clicked_intact) begin
                                engine_on <= !engine_on;
                            end else if (clicked_part == `LP_PART_FAN && clicked_intact && fan_available) begin
                                fan_on <= !fan_on;
                            end else if (clicked_part == `LP_PART_BOOSTER && clicked_intact && rocket_available && rocket_ready) begin
                                rocket_req <= 1;
                                boost_req <= 1;
                            end
                        end

                        // 2. Bottom Navigation Bar (y >= 50): [RETRY] [END] [EDIT] [GEAR]
                        if (mouse_y >= 50 && mouse_y <= 63) begin
                            if (mouse_x >= 1 && mouse_x <= 24) launch_req <= 1;          // [RETRY]
                            else if (mouse_x >= 25 && mouse_x <= 48) end_try_req <= 1;   // [END]
                            else if (mouse_x >= 49 && mouse_x <= 72) edit_req <= 1;      // [EDIT]
                            else if (mouse_x >= 73 && mouse_x <= 95) level_open_req <= 1; // [GEAR]
                        end

                        // 3. Backward-compatible legacy checks:
                        // EDIT: top-bar (40..76, <10) or right-bar (70..94, 32..42) or pop page
                        if ((mouse_x>=40 && mouse_x<=76 && mouse_y<10) ||
                            (mouse_x>=70 && mouse_x<=94 && mouse_y>=32 && mouse_y<=42) ||
                            (run_page==1 && mouse_x>=56 && mouse_x<84 && mouse_y>=14 && mouse_y<24))
                            edit_req <= 1;
                        // RETRY: top-left (2..34, 1..10) or legacy (77..96, <10) or right-bar (70..94, 2..12)
                        else if ((mouse_x>=2 && mouse_x<=34 && mouse_y>=1 && mouse_y<=10) ||
                                 (mouse_x>=77 && mouse_x<96 && mouse_y<10) ||
                                 (mouse_x>=70 && mouse_x<=94 && mouse_y>=2 && mouse_y<=12))
                            launch_req <= 1;
                        // GEAR Settings: top (35..47, 1..10) or right-bar (74..90, 16..28)
                        else if ((mouse_x>=35 && mouse_x<=47 && mouse_y>=1 && mouse_y<=10) ||
                                 (mouse_x>=74 && mouse_x<=90 && mouse_y>=16 && mouse_y<=28))
                            level_open_req <= 1;
                        // Sound page controls when run_page==2:
                        else if (run_page==2 && mouse_y>=28 && mouse_y<44) begin
                            if (mouse_x>=8 && mouse_x<36 && master_volume>0)
                                master_volume <= master_volume - 1;
                            else if (mouse_x>=60 && mouse_x<88 && master_volume<4)
                                master_volume <= master_volume + 1;
                        end else if (run_page==2 && mouse_y>=46 && mouse_y<54) begin
                            sound_muted <= !sound_muted;
                        end
                        // Legacy bottom action icon slots:
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
                            if (mouse_x<32) run_page <= 0;
                            else if (mouse_x<64) run_page <= 1;
                            else run_page <= 2;
                        end
                    end
                end
            end
            if (game_state!=`LP_GUIDE && game_state!=`LP_SETTINGS && !guide_open_req) diary_page<=0;
        end
    end
endmodule
