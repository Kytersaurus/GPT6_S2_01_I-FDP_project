// Owner: Role 1 - Kaushal. Left-OLED UI hitboxes, diary/guide navigation, and runtime part toggles.
`timescale 1ns / 1ps
`include "game_defs.vh"

module ui_controller (
    input wire clk, reset, input_enabled, run_init, physics_tick, launch_event,
    input wire start_screen_active,
    input wire [2:0] game_state,
    input wire [11:0] mouse_x, mouse_y,
    input wire mouse_left, mouse_right, mouse_event,
    input wire next_press,
    // Tutorial mode hides the result screen's diary entry on the guided course.
    input tri0 tutorial_mode,
    input wire engine_toggle_req, fan_toggle_req,
    input tri0 [3:0] fan_toggle_cell,
    input tri0 rocket_toggle_req,
    input wire fan_available, rocket_available, rocket_ready, balloon_available,
    output reg home_req, launch_req, edit_req, end_try_req, guide_open_req, guide_close_req,
    output reg level_open_req, level_close_req, level_select_req,
    output reg [1:0] selected_level,
    output reg [1:0] run_page,
    output reg boost_req,
    output reg [1:0] diary_page,
    output reg [2:0] master_volume,
    output reg engine_on,
    output wire fan_on,
    output reg [8:0] active_fans,
    output reg rocket_req,
    output reg sound_muted,
    output wire launch_flash
);
    reg left_was_down;
    reg [4:0] launch_ticks;
    assign launch_flash = launch_ticks!=0;
    assign fan_on = |active_fans;
    wire [7:0] mx = (mouse_x[11:8] != 4'd0) ? 8'd255 : mouse_x[7:0];
    wire [6:0] my = (mouse_y[11:7] != 5'd0) ? 7'd127 : mouse_y[6:0];

    always @(posedge clk) begin
        if (reset) begin
            left_was_down<=0; diary_page<=0; master_volume<=2;
            engine_on<=0;
            active_fans<=9'd0; sound_muted<=0;
            run_page<=0; boost_req<=0;
            home_req<=0; launch_req<=0; edit_req<=0; end_try_req<=0; guide_open_req<=0; guide_close_req<=0;
            rocket_req<=0; launch_ticks<=0;
            level_open_req<=0; level_close_req<=0; level_select_req<=0; selected_level<=0;
        end else begin
            home_req<=0; launch_req<=0; edit_req<=0; end_try_req<=0; guide_open_req<=0; guide_close_req<=0; rocket_req<=0;
            level_open_req<=0; level_close_req<=0; level_select_req<=0;
            boost_req<=0;
            if (run_init) begin
                // Every run starts with the engine off.  Clicking the engine
                // cell on the run diagram is the only way to toggle it.
                engine_on<=1'b0;
                active_fans<=9'd0;
                run_page<=0;
            end else if (game_state==`LP_RUN) begin
                if (engine_toggle_req) engine_on<=!engine_on;
                if (fan_toggle_req && fan_available && fan_toggle_cell < 4'd9)
                    active_fans[fan_toggle_cell] <= !active_fans[fan_toggle_cell];
                if (rocket_toggle_req && rocket_available && rocket_ready) begin
                    rocket_req<=1;
                    boost_req<=1;
                end
            end
            if (!fan_available || (game_state!=`LP_RUN && game_state!=`LP_SETTINGS && game_state!=`LP_GUIDE))
                active_fans<=9'd0;
            if (game_state!=`LP_RUN && game_state!=`LP_INIT_RUN &&
                game_state!=`LP_SETTINGS && game_state!=`LP_GUIDE)
                engine_on<=0;
            if (game_state!=`LP_RUN) launch_ticks<=0;
            else if (launch_event) launch_ticks<=30;
            else if (physics_tick && launch_ticks!=0) launch_ticks<=launch_ticks-1;
            if (game_state==`LP_GUIDE && next_press && diary_page<2) diary_page<=diary_page+1;
            if (mouse_event) begin
                left_was_down<=mouse_left;
                if (input_enabled && mouse_left && !left_was_down && !mouse_right) begin
                    if (start_screen_active) begin
                        // Play button: centered at (48, 40), hover/click box (38..58, 30..50)
                        if (mx >= 38 && mx <= 58 && my >= 30 && my <= 50)
                            launch_req <= 1;
                        // Settings [ GEAR ]: bottom-left (4..20, 46..62)
                        else if (mx >= 4 && mx <= 20 && my >= 46 && my <= 62)
                            level_open_req <= 1;
                    end else if (game_state==`LP_SETTINGS) begin
                        // Box 1: Sound Settings / Volume (x: 8..44, y: 12..48) on main settings view
                        if (diary_page != 2'd1 && diary_page != 2'd2 && mx>=8 && mx<=44 && my>=12 && my<=48) begin
                            guide_open_req <= 1;
                            diary_page <= 3;
                        // Box 2: Map Select (x: 51..87, y: 12..48) on main settings view
                        end else if (diary_page != 2'd1 && diary_page != 2'd2 && mx>=51 && mx<=87 && my>=12 && my<=48) begin
                            level_select_req <= 1;
                        // Bottom-Left Controls Toggle [ ? ]: (x: 2..25, y: 52..62) cycles Settings (0) -> Mouse (1) -> Switches (2) -> Settings (0)
                        end else if (mx>=2 && mx<=25 && my>=52 && my<=62) begin
                            if (diary_page == 2'd1) diary_page <= 2'd2;
                            else if (diary_page == 2'd2) diary_page <= 2'd0;
                            else diary_page <= 2'd1;
                        // Home button: [ ⌂ ] in bottom right (x: 70..95, y: 52..62)
                        end else if (mx>=70 && mx<=95 && my>=52 && my<=62) begin
                            home_req <= 1;
                            diary_page <= 2'd0;
                        // Back button: [ ◀ ] in bottom center (x: 28..68, y: 52..62)
                        end else if (mx>=28 && mx<=68 && my>=52 && my<=62) begin
                            if (diary_page == 2'd1 || diary_page == 2'd2) diary_page <= 2'd0;
                            else level_close_req <= 1;
                        end
                    end else if (game_state==`LP_LEVEL_SELECT) begin
                        // Back button: (x: 0..27, y: 52..63)
                        if (mx<=27 && my>=52 && my<=63)
                            level_close_req <= 1;
                        // Map 1, Map 2, and the separate tutorial course.
                        // The compact rows leave the bottom toolbar clear.
                        else if (mx>=4 && mx<=91 &&
                                 ((my>=10 && my<=21) ||
                                  (my>=24 && my<=35) ||
                                  (my>=38 && my<=49))) begin
                            if (my>=38) selected_level <= `LP_LEVEL_TUTORIAL;
                            else if (my>=24) selected_level <= `LP_LEVEL_FLIGHT;
                            else selected_level <= `LP_LEVEL_ARCH;
                            level_select_req <= 1;
                        end
                    end else if (game_state==`LP_BUILD && my>=55 && my<=63) begin
                        if (mx<=17) launch_req <= 1;
                        else if (mx>=64 && mx<=79) begin guide_open_req <= 1; diary_page <= 0; end
                        else if (mx>=80 && mx<=95) level_open_req <= 1;
                    end else if (game_state==`LP_GUIDE) begin
                        // Volume [-] (x: 8..28, y: 24..37) and [+] (x: 64..84, y: 24..37)
                        if (diary_page==3 && my>=24 && my<=37) begin
                            if (mx>=8 && mx<=28 && master_volume>0)
                                master_volume <= master_volume - 1;
                            else if (mx>=64 && mx<=84 && master_volume<4)
                                master_volume <= master_volume + 1;
                        end
                        // Back button (x: 0..27, y: 52..63)
                        if (mx<=27 && my>=52 && my<=63) begin
                            guide_close_req <= 1;
                            diary_page <= 2'd0;
                        // Page buttons [1] (32..51), [2] (53..72), [3] (74..93) at y: 55..63
                        end else if (diary_page!=3 && my>=55 && my<=63) begin
                            if (mx>=32 && mx<=51) diary_page <= 2'd0;
                            else if (mx>=53 && mx<=72) diary_page <= 2'd1;
                            else if (mx>=74 && mx<=93) diary_page <= 2'd2;
                        end
                    end else if (game_state==`LP_SUCCESS || game_state==`LP_FAIL) begin
                        // Right Panel stacked big buttons (x: 56..92):
                        // Top button: [ NEXT / EDIT ] (y: 6..26)
                        if (mx >= 56 && mx <= 92 && my >= 6 && my <= 26) begin
                            edit_req <= 1;
                        // Bottom button: [ RETRY ] (y: 30..50)
                        end else if (mx >= 56 && mx <= 92 && my >= 30 && my <= 50) begin
                            launch_req <= 1;
                        // Bottom action bar (y: 53..63): [ HOME ] [ MAP SELECT ] [ GUIDE ] [ SETTINGS ]
                        end else if (my >= 53 && my <= 63) begin
                            if (mx >= 2 && mx <= 22) home_req <= 1;
                            else if (mx >= 26 && mx <= 46) level_select_req <= 1;
                            else if (mx >= 50 && mx <= 70 && !tutorial_mode) begin guide_open_req <= 1; diary_page <= 0; end
                            else if (mx >= 74 && mx <= 94) level_open_req <= 1;
                        end
                    end else if (game_state==`LP_RUN) begin
                        // Bottom Navigation Bar in run mode (y: 53..63): [TRY] [END] [EDIT] [GEAR]
                        if (my >= 53 && my <= 63) begin
                            if (mx >= 2 && mx <= 22) begin
                                launch_req <= 1;          // [RETRY]
                                run_page <= 0;
                            end else if (mx >= 26 && mx <= 46) begin
                                end_try_req <= 1;         // [END TRY]
                                run_page <= 0;
                            end else if (mx >= 50 && mx <= 70) begin
                                edit_req <= 1;            // [EDIT]
                                run_page <= 0;
                            end else if (mx >= 74 && mx <= 94) begin
                                level_open_req <= 1;      // [GEAR]
                            end
                        end
                    end
                end
            end
            if (game_state!=`LP_RUN || level_close_req || level_open_req) run_page<=0;
            if (game_state!=`LP_GUIDE && game_state!=`LP_SETTINGS && !guide_open_req) diary_page<=0;
        end
    end
endmodule
