// Owner: Role 4 - Marcus. Right OLED map and vehicle drawing with a following camera.
`timescale 1ns / 1ps
`include "game_defs.vh"
// The camera centres on the vehicle and stops at the world edges. The map view (the default)
// shows the 96 by 64 screen at 1.5x (64 by 43 world pixels) with 12 by 12 sprites;
// normal zoom-out shows 96 by 64 world pixels at 1.0x with 8 by 8 sprites, and overview shows
// 192 by 128 world pixels at 0.5x. In free look (SW14) the
// cursor position picks the camera instead, so the whole map can be explored without driving.
// Drawing order: background (map, or sky and terrain), hazards, goal, flag, TNT, vehicle,
// explosions, then the result border. Before launch the vehicle is drawn at the spawn point.
// Three coordinate sets per pixel: world pixels (terrain, map ROM), screen-scale pixels
// (sprites; a world position p is at 3p/2 at 1.5x, with an even camera so this is exact) and
// half-world texture units (stone, flag and explosions). Output has one clock of latency:
// map_x/map_y go to the level_map draw port and the class returns with the registered pixel.
module right_renderer #(
    parameter USE_PIXEL_INDEX = 1
) (
    input wire clk,
    input wire [12:0] pixel_index,
    input wire [6:0] in_x,
    input wire [5:0] in_y,
    input wire zoomed_out,
    input wire overview,
    // Free look: the camera follows the mouse cursor (0..95, 0..63) across the whole world.
    input wire free_look,
    input wire [6:0] cursor_x, cursor_y,
    input wire [2:0] game_state,
    input wire [26:0] build_grid,
    input wire [8:0] build_facing_left,
    input tri0 [8:0] build_facing_down,
    input tri0 engine_enabled,
    input tri0 boost_active,
    input tri0 [8:0] active_fans,
    // Rockets fire one at a time, so each cell has its own exhaust flame.
    input tri0 [8:0] rocket_burn_mask,
    // Cells whose balloon has just burst, and how far through the burst they are.
    input tri0 [8:0] balloon_pop_mask,
    input tri0 [1:0] balloon_pop_phase,
    input wire [8:0] intact_mask,
    input wire [8:0] frame_intact_mask,
    // 20-bit Q12.8 positions, ready for wider physics; today's 16-bit values are sign-extended.
    // vehicle_x/y are the rendered sprite position. camera_x/y are separate so
    // callers can choose whether the camera follows raw or filtered motion.
    input wire signed [19:0] vehicle_x, vehicle_y,
    input wire signed [19:0] camera_x, camera_y,
    input wire signed [`LP_TILT_BITS-1:0] vehicle_tilt,
    input wire signed [19:0] spawn_x, spawn_y,
    input wire [2:0] terrain_count,
    input wire [127:0] terrain_rects,
    input wire [31:0] goal_rect,
    input wire [2:0] tnt_count,
    input wire [`LP_TNT_BITS-1:0] tnt_positions,
    input wire [`LP_MAX_TNT-1:0] tnt_intact,
    input tri0 [`LP_LESSON_BITS-1:0] tutorial_lesson,
    input wire [1:0] hazard_count,
    input wire [`LP_HAZARD_BITS-1:0] hazard_rects,
    input wire [2*`LP_MAX_TNT-1:0] blast_phase,
    input tri0 [1:0] death_phase,
    input wire signed [`LP_COORD_BITS-1:0] death_x, death_y,
    // Visual-only debris from a high-fall impact. The cells are animated
    // deterministically in this renderer; they are not separate physics bodies.
    input tri0 [8:0] scatter_mask,
    input tri0 signed [`LP_COORD_BITS-1:0] scatter_x, scatter_y,
    input tri0 [5:0] scatter_phase,
    input wire launch_flash,
    input wire anim_phase,
    input wire map_level,
    input wire map_id,  // 0 Cave Arch (has the moon), 1 Cave Flight
    input tri0 [`LP_LEVEL_BITS-1:0] level_index,
    input wire [9:0] world_width, world_height,
    input wire [9:0] flag_x, flag_y,
    input wire [9:0] star_box_x, star_box_y,
    input wire star_box_collected,
    input tri0 [7:0] run_seconds,
    // Level par time in whole seconds, the same value the 7-segment
    // countdown starts from, so the time star matches what the board shows.
    input tri0 [7:0] par_time,
    output reg signed [10:0] map_x, map_y,
    input wire [2:0] map_class,
    output reg [15:0] pixel_data
);
    `include "part_sprites.vh"
    `include "ui_font.vh"
    `include "rotation_geometry.vh"

    // Small procedural drawing of the Basys3 centre button (BTNC) for the tutorial
    // welcome card: a white-edged silver key with a dark C, 20 by 10 at (left, top).
    function [15:0] board_button_pixel;
        input [6:0] pixel_x, left;
        input [5:0] pixel_y, top;
        reg [6:0] bx;
        reg [5:0] by;
        reg label_pixel;
        begin
            bx = pixel_x - left;
            by = pixel_y - top;
            // A 5 by 6 C centred on the key face.
            label_pixel = (bx == 7'd8 && by >= 6'd3 && by <= 6'd6) ||
                          ((by == 6'd2 || by == 6'd7) && bx >= 7'd9 && bx <= 7'd12);
            if (by == 6'd9) board_button_pixel = 16'h4208;                // Lower shadow
            else if (bx == 7'd0 || bx == 7'd19 || by == 6'd0) board_button_pixel = 16'hffff; // Raised edge
            else if (label_pixel) board_button_pixel = 16'h0000;
            else board_button_pixel = 16'hbdf7;                           // Silver key face
        end
    endfunction

    // Tutorial sky, drawn from comparators alone so it needs no image memory and looks
    // the same at every zoom: a dithered gradient from deep to pale blue, a sun, soft
    // clouds, and two rows of hills. Dithering uses screen bits, which stay one pixel
    // fine even when the overview samples every second world pixel.
    function [15:0] tutorial_sky_pixel;
        input signed [11:0] world_x, world_y;
        input dither;
        reg [2:0] band;
        reg [6:0] cloud_x;
        reg [6:0] far_hill_x, near_hill_x;
        reg [4:0] far_hill_height;
        reg [5:0] near_hill_height;
        reg [11:0] sun_dx, sun_dy;
        begin
            band = world_y[6:4];
            if (world_y[3] && dither && band != 3'd7) band = band + 3'd1;
            case (band)
                3'd0: tutorial_sky_pixel = 16'h3bd9;
                3'd1: tutorial_sky_pixel = 16'h445a;
                3'd2: tutorial_sky_pixel = 16'h54db;
                3'd3: tutorial_sky_pixel = 16'h655c;
                3'd4: tutorial_sky_pixel = 16'h7dbc;
                3'd5: tutorial_sky_pixel = 16'h95fd;
                default: tutorial_sky_pixel = 16'hae5d;
            endcase

            // Sun high on the right, over the finish: a soft glow around a warm rounded disc.
            sun_dx = (world_x >= 12'sd196) ? world_x - 12'sd196 : 12'sd196 - world_x;
            sun_dy = (world_y >= 12'sd24) ? world_y - 12'sd24 : 12'sd24 - world_y;
            if (sun_dx < 12'd11 && sun_dy < 12'd11) begin
                if (sun_dx < 12'd7 && sun_dy < 12'd7 && sun_dx + sun_dy <= 12'd9) tutorial_sky_pixel = 16'hffb4;
                else if (sun_dx + sun_dy <= 12'd13 && dither) tutorial_sky_pixel = 16'hdf5b;
            end

            // One rounded cloud repeats every 128 world pixels, a second every 128 in between.
            cloud_x = world_x[6:0];
            if ((world_y >= 12'sd18 && world_y < 12'sd20 && cloud_x >= 7'd16 && cloud_x < 7'd30) ||
                (world_y >= 12'sd20 && world_y < 12'sd25 && cloud_x >= 7'd10 && cloud_x < 7'd38) ||
                (world_y >= 12'sd25 && world_y < 12'sd27 && cloud_x >= 7'd14 && cloud_x < 7'd34) ||
                (world_y >= 12'sd40 && world_y < 12'sd42 && cloud_x >= 7'd80 && cloud_x < 7'd90) ||
                (world_y >= 12'sd42 && world_y < 12'sd46 && cloud_x >= 7'd74 && cloud_x < 7'd98))
                tutorial_sky_pixel = 16'hf79e;

            // Hills are triangle waves. The far row repeats every 64 pixels, the near one every 128.
            far_hill_x = world_x[5] ? ~world_x[6:0] : world_x[6:0];
            far_hill_height = far_hill_x[4:0];
            near_hill_x = world_x[6:0] + 7'd20;
            near_hill_height = near_hill_x[6] ? ~near_hill_x[5:0] : near_hill_x[5:0];
            if (world_y >= 12'sd104 - $signed({7'd0, far_hill_height}))
                tutorial_sky_pixel = 16'h6d90;
            if (world_y >= 12'sd116 - $signed({7'd0, near_hill_height[5:2]}) - $signed({7'd0, near_hill_height[5:3]}))
                tutorial_sky_pixel = 16'h3d0a;
        end
    endfunction

    wire [5:0] raw_pi_y = ({12'd0, pixel_index} * 25'd2731) >> 18;
    wire [6:0] raw_pi_x = pixel_index - (raw_pi_y << 6) - (raw_pi_y << 5);
    wire [6:0] x = USE_PIXEL_INDEX ? raw_pi_x : in_x;
    wire [5:0] y = USE_PIXEL_INDEX ? raw_pi_y : in_y;

    wire before_launch = (game_state == `LP_BUILD || game_state == `LP_GUIDE);
    // Vehicle (or spawn) top-left in whole world pixels plus Q12.1 half-pixel bit.
    wire signed [19:0] origin_x = before_launch ? spawn_x : vehicle_x;
    wire signed [19:0] origin_y = before_launch ? spawn_y : vehicle_y;
    wire signed [19:0] camera_origin_x = before_launch ? spawn_x : camera_x;
    wire signed [19:0] camera_origin_y = before_launch ? spawn_y : camera_y;
    wire signed [11:0] vx = camera_origin_x[19:8];
    wire signed [11:0] vy = camera_origin_y[19:8];
    wire signed [11:0] veh_x = origin_x[19:8];
    wire signed [11:0] veh_y = origin_y[19:8];
    wire veh_hx = (game_state == `LP_RUN) && origin_x[7];
    wire veh_hy = (game_state == `LP_RUN) && origin_y[7];
    wire cam_hx = (game_state == `LP_RUN && !free_look) && camera_origin_x[7];
    wire cam_hy = (game_state == `LP_RUN && !free_look) && camera_origin_y[7];

    // Stage 0: camera and the world position under this pixel.
    wire [6:0] sx = x;
    wire [6:0] sy = {1'b0, y};
    reg [7:0] world_view_w, world_view_h;
    always @* begin
        // Camera limits are in world pixels. At the default 1.5x scale each
        // screen pixel covers 2/3 of a world pixel, so using the raw screen
        // dimensions here would leave the start ground and map edges clipped.
        if (overview) begin
            world_view_w = 8'd192; world_view_h = 8'd128;
        end else if (zoomed_out) begin
            world_view_w = 8'd96; world_view_h = 8'd64;
        end else begin
            world_view_w = 8'd64; world_view_h = 8'd43;
        end
    end
    // Signed limits: a camera left of or above the world must clamp to zero, not wrap.
    wire signed [11:0] max_x = $signed({2'b00, world_width}) - $signed({4'b0000, world_view_w});
    wire signed [11:0] max_y = $signed({2'b00, world_height}) - $signed({4'b0000, world_view_h});
    // Scale the cursor to the camera range: 86/8192 ~ 1/95 and 130/8192 ~ 1/63.
    wire [24:0] free_look_x = cursor_x * max_x[10:0] * 7'd86;
    wire [25:0] free_look_y = cursor_y * max_y[10:0] * 8'd130;
    // 171/256 and 342/256 give exactly 2x/3 and 4x/3 for the screen range 0..95 without a divider.
    wire [15:0] sx_times_171 = sx * 8'd171;
    wire [15:0] sy_times_171 = sy * 8'd171;
    wire [15:0] sx_times_342 = sx * 9'd342;
    wire [15:0] sy_times_342 = sy * 9'd342;
    wire signed [12:0] screen_two_thirds_x = {5'd0, sx_times_171[15:8]};
    wire signed [12:0] screen_two_thirds_y = {5'd0, sy_times_171[15:8]};
    wire signed [12:0] screen_four_thirds_x = {5'd0, sx_times_342[15:8]};
    wire signed [12:0] screen_four_thirds_y = {5'd0, sy_times_342[15:8]};
    wire signed [12:0] sx_signed = {6'd0, sx};
    wire signed [12:0] sy_signed = {6'd0, sy};
    reg signed [12:0] cam_x, cam_y;
    reg cam_hx_eff, cam_hy_eff;
    reg signed [12:0] next_fx, next_fy, next_wx, next_wy, next_tx, next_ty;
    always @* begin
        cam_hx_eff = cam_hx;
        cam_hy_eff = cam_hy;
        if (free_look) begin
            cam_x = free_look_x >> 13;
            cam_y = free_look_y >> 13;
        end else begin
            cam_x = vx + 13'sd12 - $signed({6'd0, world_view_w[7:1]});
            cam_y = vy + 13'sd12 - $signed({6'd0, world_view_h[7:1]});
        end
        if (cam_x >= max_x) begin cam_x = max_x; cam_hx_eff = 1'b0; end
        if (cam_y >= max_y) begin cam_y = max_y; cam_hy_eff = 1'b0; end
        if (cam_x <= 0) begin cam_x = 0; cam_hx_eff = 1'b0; end
        if (cam_y <= 0) begin cam_y = 0; cam_hy_eff = 1'b0; end
        if (overview) begin
            // Half scale uses shifts and the existing sprite data, with no new image ROM.
            cam_x[0] = 1'b0; cam_y[0] = 1'b0;
            next_wx = cam_x + 2*sx_signed;         next_wy = cam_y + 2*sy_signed;
            next_fx = (cam_x >>> 1) + sx_signed;   next_fy = (cam_y >>> 1) + sy_signed;
            next_tx = 2*next_wx;                   next_ty = 2*next_wy;
        end else if (zoomed_out) begin
            next_wx = cam_x + sx_signed;           next_wy = cam_y + sy_signed;
            next_fx = next_wx;                     next_fy = next_wy;
            next_tx = {next_wx[11:0], cam_hx_eff}; next_ty = {next_wy[11:0], cam_hy_eff};
        end else begin
            // Eliminate 1.5x even-camera judder in RUN mode and interpolate half-pixels (Q12.1).
            if (game_state != `LP_RUN) begin
                cam_x[0] = 1'b0; cam_y[0] = 1'b0;
            end
            next_wx = cam_x + screen_two_thirds_x + $signed({12'd0, cam_hx_eff & sx_times_171[7]});
            next_wy = cam_y + screen_two_thirds_y + $signed({12'd0, cam_hy_eff & sy_times_171[7]});
            next_fx = cam_x + (cam_x >>> 1) + $signed({12'd0, cam_hx_eff}) + sx_signed;
            next_fy = cam_y + ((cam_y + 13'sd1) >>> 1) + $signed({12'd0, cam_hy_eff}) + sy_signed;
            next_tx = {cam_x[11:0], cam_hx_eff} + screen_four_thirds_x;
            next_ty = {cam_y[11:0], cam_hy_eff} + screen_four_thirds_y;
        end
        map_x = next_wx;
        map_y = next_wy;
    end

    // Stage 1: registered beside the map read.
    wire signed [`LP_TILT_BITS-1:0] next_tilt = before_launch ? 0 : sanitize_tilt(vehicle_tilt);
    reg [6:0] px, py;
    reg signed [11:0] fx, fy, wx, wy, tex_x, tex_y;
    reg zoomed_out_q, overview_q;
    reg signed [`LP_TILT_BITS-1:0] tilt_q;
    reg signed [9:0] rotation_c_q, rotation_s_q;
    always @(posedge clk) begin
        px <= sx; py <= sy; zoomed_out_q <= zoomed_out; overview_q <= overview;
        fx <= next_fx; fy <= next_fy; wx <= next_wx; wy <= next_wy; tex_x <= next_tx; tex_y <= next_ty;
        tilt_q <= next_tilt;
        rotation_c_q <= rotation_cos(next_tilt);
        rotation_s_q <= rotation_sin(next_tilt);
    end

    // One text line is shared by the launch "GO!" and the ending card titles:
    // they are never on screen together, and each text_on call costs real logic.
    wire in_result_state = (game_state == `LP_SUCCESS || game_state == `LP_FAIL);
    reg [127:0] banner_text;
    reg [6:0] banner_left, banner_top;
    wire tutorial_active = (level_index == `LP_LEVEL_TUTORIAL);
    wire tutorial_welcome = tutorial_active && (game_state == `LP_BUILD);
    wire tutorial_coaching = tutorial_active && (game_state == `LP_RUN);
    wire tutorial_avoid_tnt = tutorial_coaching &&
                              (tutorial_lesson == `LP_LESSON_TNT || tutorial_lesson == `LP_LESSON_TNT_FALL);
    wire tutorial_retry_prompt = tutorial_coaching && (tutorial_lesson == `LP_LESSON_RETRY);
    // Welcome card: the board's BTNC key sits beside "PRESS".
    localparam [6:0] WELCOME_KEY_LEFT = 7'd54;
    localparam [5:0] WELCOME_KEY_TOP = 6'd36;
    wire welcome_key_area = tutorial_welcome &&
                            px >= WELCOME_KEY_LEFT && px < WELCOME_KEY_LEFT + 7'd20 &&
                            py >= WELCOME_KEY_TOP && py < WELCOME_KEY_TOP + 6'd10;
    // Retry lesson: a copy of the left OLED's retry button sits between the words,
    // so the player knows exactly which icon to look for on the other screen.
    wire retry_key_area = tutorial_retry_prompt && px >= 7'd36 && px < 7'd47 && py < 7'd9;
    // 9 by 9 clockwise arrow, the same artwork as the retry button on the left OLED.
    function retry_arrow_lit;
        input signed [7:0] lx, ly;
        reg [8:0] row;
        begin
            row = 9'd0;
            retry_arrow_lit = 1'b0;
            if (lx >= -4 && lx <= 4 && ly >= -4 && ly <= 4) begin
                case (ly)
                    -8'sd4: row = 9'b001111001;
                    -8'sd3: row = 9'b011111111;
                    -8'sd2: row = 9'b110000111;
                    -8'sd1: row = 9'b110001111;
                     8'sd0,  8'sd1: row = 9'b110000000;
                     8'sd2: row = 9'b111000110;
                     8'sd3: row = 9'b011111110;
                     8'sd4: row = 9'b001111100;
                    default: row = 9'd0;
                endcase
                retry_arrow_lit = row[4 - lx];
            end
        end
    endfunction
    // True when the cart needs its engine turned back on to carry on with this lesson.
    wire tutorial_engine_needed = !engine_enabled &&
                                  (tutorial_lesson == `LP_LESSON_STAR || tutorial_lesson == `LP_LESSON_TNT ||
                                   tutorial_lesson == `LP_LESSON_HOP || tutorial_lesson == `LP_LESSON_FLAG);
    always @* begin
        if (game_state == `LP_SUCCESS) begin
            banner_text = "LEVEL CLEAR!    "; banner_left = 7'd12; banner_top = 7'd11;
        end else if (game_state == `LP_FAIL) begin
            banner_text = "GAME OVER       "; banner_left = 7'd21; banner_top = 7'd14;
        end else if (tutorial_welcome) begin
            // All four lines of the welcome card share this one text lookup.
            if (py < 7'd20) begin
                banner_text = "    TUTORIAL    "; banner_left = 7'd0; banner_top = 7'd10;
            end else if (py < 7'd34) begin
                banner_text = "  LEARN BASICS  "; banner_left = 7'd0; banner_top = 7'd22;
            end else if (py < 7'd47) begin
                banner_text = "PRESS           "; banner_left = 7'd20; banner_top = 7'd38;
            end else begin
                banner_text = "TO START        "; banner_left = 7'd24; banner_top = 7'd49;
            end
        end else if (tutorial_coaching) begin
            banner_left = 7'd0; banner_top = 7'd1;
            if (tutorial_engine_needed) banner_text = "CLICK ENGINE ON ";
            else case (tutorial_lesson)
                `LP_LESSON_ZOOM_IN:  banner_text = "SCROLL^ ZOOM IN ";
                `LP_LESSON_ZOOM_OUT: banner_text = "SCROLLv ZOOM OUT";
                `LP_LESSON_ENGINE:   banner_text = "CLICK ENGINE ON ";
                `LP_LESSON_STAR:     banner_text = "STAR DRIVE OVER ";
                `LP_LESSON_TNT,
                `LP_LESSON_TNT_FALL: banner_text = "AVOID TNT       ";
                `LP_LESSON_RETRY:    banner_text = "CLICK    ON LEFT";
                `LP_LESSON_ROCKET:   banner_text = "CLICK ROCKET NOW";
                `LP_LESSON_HOP:      banner_text = "ROCKET USED     ";
                `LP_LESSON_FAN_ON:   banner_text = "CLICK FAN ON    ";
                `LP_LESSON_FAN_FLY:  banner_text = "FAN LIFTS CART  ";
                `LP_LESSON_FAN_OFF:  banner_text = "CLICK FAN OFF   ";
                `LP_LESSON_DROP:     banner_text = "CART DROPS      ";
                default:             banner_text = "DRIVE TO FLAG   ";
            endcase
        end else begin
            banner_text = "GO!             "; banner_left = 7'd39; banner_top = 7'd1;
        end
    end
    wire banner_lit = text_on(banner_text, banner_left, banner_top, px, py);
    // Ending card layout: the clear card keeps its pig below the row of stars.
    wire [6:0] card_pig_top = (game_state == `LP_SUCCESS) ? 7'd36 : 7'd28;
    // Stars: one for clearing, one for the star box, one for beating par.
    // Beating par means finishing before the 7-segment countdown reaches 0.
    wire beat_par_time = (run_seconds < par_time);
    wire [1:0] stars_earned = 2'd1 + (star_box_collected ? 2'd1 : 2'd0) + (beat_par_time ? 2'd1 : 2'd0);
    reg [6:0] card_star_x;
    reg card_star_earned;

    // World position to screen-scale position for sprites: p, or floor(3p/2) at 1.5x.
    function signed [14:0] scaled;
        input signed [11:0] world;
        input zoomed_out_now;
        reg signed [13:0] tripled;
        begin
            tripled = 3 * world;
            scaled = zoomed_out_now ? world : (tripled >>> 1);
        end
    endfunction

    // Absolute value of a coordinate difference.
    function [13:0] magnitude;
        input signed [13:0] value;
        begin magnitude = (value < 0) ? -value : value; end
    endfunction

    // Staggered stones with mortar and a lit top-left edge in three shades. Only the low bits of
    // the texture position matter, so the sums stay narrow. Returns which stone tone this pixel is.
    localparam [2:0] STONE_MORTAR = 3'd0;
    localparam [2:0] STONE_LIGHT = 3'd1;
    localparam [2:0] STONE_TONE_A = 3'd2;
    localparam [2:0] STONE_TONE_B = 3'd3;
    localparam [2:0] STONE_TONE_C = 3'd4;
    function [2:0] stone_tone;
        input [11:0] fine_x, fine_y;
        reg [3:0] row, stagger, lx;
        reg [2:0] ly;
        reg [7:0] shifted;
        reg [1:0] shade;
        begin
            row = fine_y[6:3];
            stagger = row * 4'd5;
            shifted = fine_x[7:0] + stagger;
            lx = shifted[3:0];
            ly = fine_y[2:0];
            shade = shifted[5:4] ^ {row[0], 1'b0} ^ shifted[7:6] ^ row[1:0];
            if (lx == 0 || ly == 0 || (lx == 1 && ly == 1)) stone_tone = STONE_MORTAR;
            else if (lx == 1 || ly == 1) stone_tone = STONE_LIGHT;
            else if (shade == 0) stone_tone = STONE_TONE_A;
            else if (shade == 2) stone_tone = STONE_TONE_C;
            else stone_tone = STONE_TONE_B;
        end
    endfunction

    function [15:0] map_colour;
        input [2:0] map_cell;
        input signed [11:0] fine_x, fine_y;
        reg [2:0] tone, road_x, road_y;
        reg [1:0] grass_x, grass_y;
        reg signed [13:0] moon_dx, moon_dy, shadow_dy;
        reg [13:0] moon_abs_x, moon_abs_y, shadow_abs_y;
        reg [9:0] moon_distance_sq;
        reg [5:0] shadow_distance_sq;
        begin
            tone = stone_tone(fine_x, fine_y);
            case (map_cell)
                `LP_MAP_CAVE: case (tone)
                    STONE_MORTAR: map_colour = 16'h08a2;
                    STONE_LIGHT:  map_colour = 16'h2a88;
                    STONE_TONE_A: map_colour = 16'h1985;
                    STONE_TONE_C: map_colour = 16'h2227;
                    default:       map_colour = 16'h21c6;
                endcase
                `LP_MAP_ROCK: case (tone)
                    STONE_MORTAR: map_colour = 16'h1988;
                    STONE_LIGHT:  map_colour = 16'h6c97;
                    STONE_TONE_A: map_colour = 16'h3af0;
                    STONE_TONE_C: map_colour = 16'h4bd4;
                    default:       map_colour = 16'h4352;
                endcase
                // 3-tone turf shading on 2-world-pixel cells (exact 3x3 screen blocks at 1.5x zoom).
                `LP_MAP_GRASS: begin
                    grass_x = fine_x[3:2] * 2'd3;
                    grass_y = fine_y[3:2];
                    case (grass_x ^ grass_y)
                        2'd0, 2'd1: map_colour = fine_y[1] ? 16'h4d86 : 16'h5e27;
                        2'd2:       map_colour = 16'h3504;
                        default:    map_colour = 16'h4d86;
                    endcase
                end
                `LP_MAP_ROAD: begin
                    road_x = fine_x[2:0] * 3'd3;
                    road_y = fine_y[2:0] * 3'd5;
                    map_colour = (road_x == road_y) ? 16'h4a89 : 16'h3a28;
                end
                `LP_MAP_DARK: map_colour = 16'h1082;
                default: begin
                    // Night sky lightening towards the horizon, with the moon seen through the arch.
                    if (fine_y < 0) map_colour = 16'ha5fd;
                    else case (fine_y[10:6])
                        5'd0: map_colour = 16'h322d;
                        5'd1: map_colour = 16'h3a8f;
                        5'd2: map_colour = 16'h4af1;
                        5'd3: map_colour = 16'h5b94;
                        5'd4: map_colour = 16'h6c57;
                        5'd5: map_colour = 16'h8d1a;
                        default: map_colour = 16'ha5fd;
                    endcase
                    // Centre in half-world units: Cave Arch world pixel (280, 78) in the night sky above the start hill.
                    // Radius 18: only pixels within 18 on each axis need the small squares below.
                    moon_dx = fine_x - 14'sd560;
                    moon_dy = fine_y - 14'sd156;
                    shadow_dy = moon_dy + 14'sd6;
                    moon_abs_x = magnitude(moon_dx);
                    moon_abs_y = magnitude(moon_dy);
                    shadow_abs_y = magnitude(shadow_dy);
                    moon_distance_sq = moon_abs_x[4:0] * moon_abs_x[4:0] + moon_abs_y[4:0] * moon_abs_y[4:0];
                    shadow_distance_sq = moon_abs_x[2:0] * moon_abs_x[2:0] + shadow_abs_y[2:0] * shadow_abs_y[2:0];
                    if (!map_id && moon_abs_x <= 14'd18 && moon_abs_y <= 14'd18 && moon_distance_sq <= 10'd324) begin
                        if (moon_abs_x <= 14'd4 && shadow_abs_y <= 14'd4 && shadow_distance_sq <= 6'd16) map_colour = 16'hc65a;
                        else map_colour = 16'he75e;
                    end
                end
            endcase
        end
    endfunction

    wire goal_pixel;
    integer index, rx, ry, rw, rh;
    reg [31:0] rectangle;

    // Sprites sample world pixels at 1x and 0.5x, and screen-scale pixels at 1.5x.
    wire small_tiles = zoomed_out_q || overview_q;
    wire signed [13:0] tile_sample_x = small_tiles ? wx : fx;
    wire signed [13:0] tile_sample_y = small_tiles ? wy : fy;
    wire [3:0] tile_size = small_tiles ? 4'd8 : 4'd12;
    // A tile's top-left in the sampled coordinates; floor(3p/2) = p + p/2 for positive p.
    function signed [13:0] tile_position;
        input [9:0] world;
        input small_tile;
        begin tile_position = small_tile ? {4'd0, world} : ({4'd0, world} + {5'd0, world[9:1]}); end
    endfunction
    function tile_contains;
        input signed [13:0] local_value;
        input [3:0] size;
        begin tile_contains = (local_value >= 0) && (local_value < $signed({10'd0, size})); end
    endfunction

    reg signed [13:0] star_local_x, star_local_y, tnt_local_x, tnt_local_y;
    reg [3:0] drawn_tnt_x, drawn_tnt_y;
    reg tnt_tile_hit;
    reg signed [13:0] flag_dx, flag_dy;

    // Half-pixel centred coordinates keep opposite corners symmetric. Only
    // nearby pixels enter these small products, preventing outside-world
    // positions from aliasing into the sprite after narrowing.
    reg signed [14:0] rel_x, rel_y;
    reg signed [6:0] cell_px;
    reg signed [14:0] vehicle_screen_x, vehicle_screen_y;
    reg signed [8:0] rotation_dx2, rotation_dy2;
    reg signed [9:0] rotation_c, rotation_s;
    reg signed [19:0] rotation_x_sum, rotation_y_sum;
    reg signed [20:0] rotated_x, rotated_y;
    reg signed [14:0] rotation_centre;
    reg [1:0] cell_col, cell_row;
    reg [3:0] cell_index, cell_x, cell_y;
    reg [2:0] part;
    reg part_anim;

    // Debris and the pig burst are compared against one shared offset from the moving origin.
    wire signed [13:0] scatter_offset_x = wx - $signed(scatter_x[19:8]);
    wire signed [13:0] scatter_offset_y = wy - $signed(scatter_y[19:8]);
    wire scatter_near = (scatter_offset_x >= -14'sd64) && (scatter_offset_x < 14'sd96) &&
                        (scatter_offset_y >= -14'sd64) && (scatter_offset_y < 14'sd96);
    reg signed [8:0] scatter_local_x, scatter_local_y;
    wire [5:0] scatter_half = scatter_phase >> 1;
    wire [5:0] scatter_quarter = scatter_phase >> 2;

    reg signed [13:0] blast_dx, blast_dy;
    reg [13:0] blast_abs_x, blast_abs_y;
    reg [4:0] drawn_blast_x, drawn_blast_y;
    reg [1:0] drawn_blast_phase;
    reg [9:0] blast_distance_sq;
    reg [1:0] blast_now;

    wire signed [13:0] death_dx = wx - $signed(death_x[19:8]);
    wire signed [13:0] death_dy = wy - $signed(death_y[19:8]);
    wire [13:0] death_abs_x = magnitude(death_dx);
    wire [13:0] death_abs_y = magnitude(death_dy);
    // Every burst shape stays within 9 world pixels of the pig.
    wire death_near = (death_abs_x <= 14'd9) && (death_abs_y <= 14'd9);
    wire [4:0] death_distance = death_abs_x[3:0] + death_abs_y[3:0];

    square u_goal_box (
        .x(wx[6:0]), .y(wy[6:0]), .pos_x(goal_rect[6:0]), .pos_y(goal_rect[14:8]),
        .width_x(goal_rect[22:16]), .length_y(goal_rect[30:24]), .is_in_square(goal_pixel)
    );

    // square is retained for the ROM maps, whose coordinates fit in 7 bits.
    // The tutorial uses the rectangle path and can place its finish beyond
    // that range, so calculate its goal pixel with the full 8-bit fields.
    wire rectangle_goal_pixel = !map_level &&
        wx >= $signed({1'b0, goal_rect[7:0]}) &&
        wx <  $signed({1'b0, goal_rect[7:0]}) + $signed({1'b0, goal_rect[23:16]}) &&
        wy >= $signed({1'b0, goal_rect[15:8]}) &&
        wy <  $signed({1'b0, goal_rect[15:8]}) + $signed({1'b0, goal_rect[31:24]});
    wire goal_draw_pixel = map_level ? goal_pixel : rectangle_goal_pixel;
    // The tutorial is intentionally styled procedurally.  It reuses the
    // existing rectangle renderer instead of adding another bitmap/BRAM.
    wire tutorial_render = !map_level && (level_index == `LP_LEVEL_TUTORIAL);
    wire signed [11:0] sky_world_x = wx;
    wire signed [11:0] sky_world_y = wy;
    wire [15:0] tutorial_sky = tutorial_sky_pixel(sky_world_x, sky_world_y, px[0] ^ py[0]);
    // Cave Arch has decorative grass painted beside and beyond its finish flag. The map
    // files stay untouched, so those pixels are redrawn here as what lies around them:
    // open cave up to world x=666, then the rock mound. Collision does not read this class.
    wire arch_finish_grass = map_level && !map_id && (map_class == `LP_MAP_GRASS) &&
                             wx >= 12'sd606 && wx < 12'sd740 && wy >= 12'sd450 && wy < 12'sd500;
    reg [2:0] drawn_map_class;
    always @* begin
        drawn_map_class = map_class;
        if (arch_finish_grass) drawn_map_class = (wx < 12'sd666) ? `LP_MAP_CAVE : `LP_MAP_ROCK;
    end
    // The welcome card stays up for the whole BUILD state. It therefore
    // disappears only when the normal start/launch action moves the game into
    // RUN; there is no timer that can dismiss it while the player is reading.
    always @* begin
        rx = 0; ry = 0; rw = 0; rh = 0; part = 0; part_anim = 0; rectangle = 0;
        cell_col = 0; cell_row = 0; cell_index = 0; cell_x = 0; cell_y = 0;
        rotation_dx2=0; rotation_dy2=0; rotation_c=0; rotation_s=0;
        rotation_x_sum=0; rotation_y_sum=0; rotated_x=0; rotated_y=0;
        star_local_x = 0; star_local_y = 0; flag_dx = 0; flag_dy = 0;
        card_star_x = 7'd0; card_star_earned = 1'b0;
        if (map_level) pixel_data = map_colour(drawn_map_class, tex_x, tex_y);
        else begin
            pixel_data = tutorial_render ? tutorial_sky : 16'h0010;
            for (index = 0; index < 4; index = index + 1) begin
                rectangle = terrain_rects >> (index*32);
                rx = rectangle[7:0]; ry = rectangle[15:8];
                rw = rectangle[23:16]; rh = rectangle[31:24];
                if (index < terrain_count && wx >= rx && wx < rx+rw && wy >= ry && wy < ry+rh) begin
                    if (tutorial_render) begin
                        // Bright grass on top, a dark seam below it, and a
                        // two-tone soil pattern make steps readable at every
                        // zoom without adding a texture table.
                        if (wy == ry || wy == ry+1) pixel_data = 16'h5ecb;
                        else if (wy == ry+2) pixel_data = 16'h2d61;
                        else if (((((wx-rx) >>> 2) ^ ((wy-ry) >>> 2)) & 1) != 0)
                            pixel_data = 16'h7a40;
                        else pixel_data = 16'h8a60;
                    end else pixel_data = 16'h8320;
                end
            end
        end
        // Spikes: four-pixel teeth, pointed in their outer columns.
        for (index = 0; index < `LP_MAX_HAZARDS; index = index + 1) begin
            rectangle = hazard_rects >> (index*32);
            rx = rectangle[7:0]; ry = rectangle[15:8];
            rw = rectangle[23:16]; rh = rectangle[31:24];
            if (index < hazard_count && wx >= rx && wx < rx+rw && wy >= ry && wy < ry+rh &&
                (((wx-rx) & 3) == 1 || ((wx-rx) & 3) == 2 || wy-ry >= (rh >>> 1))) pixel_data = 16'hc618;
        end
        if (goal_draw_pixel && !tutorial_render) begin
            pixel_data = 16'h0320;
        end else if (tutorial_render &&
                     wx >= $signed({1'b0, goal_rect[7:0]}) &&
                     wx <  $signed({1'b0, goal_rect[7:0]}) + $signed({1'b0, goal_rect[23:16]}) &&
                     wy >= 14'sd120 && wy < 14'sd126) begin
            // On-land checkered finish strip embedded into the ground surface (y=120..125).
            pixel_data = (((((wx - $signed({1'b0, goal_rect[7:0]})) >>> 2) ^
                            ((wy - 14'sd120) >>> 1)) & 1) != 0)
                          ? 16'hffff : 16'h07e0;
        end
        // Finish flag on map levels and tutorial, in half-world units from its top-left: a 3-wide orange
        // wooden pole 28 tall (lit left edge, dark right edge) and a 20 by 16 checkered cloth
        // with a dark border and 4-unit (2 world pixel) squares.
        if (map_level || tutorial_render) begin
            flag_dx = tex_x - $signed({3'd0, flag_x, 1'b0});
            flag_dy = tex_y - $signed({3'd0, flag_y, 1'b0});
            if (flag_dx >= 0 && flag_dx < 3 && flag_dy >= 0 && flag_dy < 28) begin
                if (flag_dx == 0) pixel_data = 16'hfd8c;
                else if (flag_dx == 1) pixel_data = 16'hec05;
                else pixel_data = 16'haa82;
            end else if (flag_dx >= 3 && flag_dx < 23 && flag_dy >= 1 && flag_dy < 17) begin
                if (flag_dx == 3 || flag_dx == 22 || flag_dy == 1 || flag_dy == 16) pixel_data = 16'h3186;
                else pixel_data = ((((flag_dx-3) >>> 2) ^ ((flag_dy-1) >>> 2)) & 1) ? 16'h0000 : 16'hffff;
            end
        end
        // Star box: draw on both ROM maps and rectangle courses. This keeps
        // the tutorial objects visible without adding another map memory.
        star_local_x = tile_sample_x - tile_position(star_box_x, small_tiles);
        star_local_y = tile_sample_y - tile_position(star_box_y, small_tiles);
        if (`LP_STAR_BOX_ENABLED && !star_box_collected &&
            tile_contains(star_local_x, tile_size) && tile_contains(star_local_y, tile_size)) begin
            if (small_tiles) pixel_data = star_sprite(star_local_x[3:0], star_local_y[3:0], pixel_data);
            else pixel_data = star_sprite12(star_local_x[3:0], star_local_y[3:0], pixel_data);
        end
        // TNT: 12 by 12 close, 8 by 8 normal/overview (overview naturally samples it smaller).
        // TNT tiles are opaque, so the last crate covering this pixel is the only one to draw;
        // this keeps one sprite lookup however many crates a level has.
        tnt_tile_hit = 1'b0; drawn_tnt_x = 4'd0; drawn_tnt_y = 4'd0;
        tnt_local_x = 0; tnt_local_y = 0;
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            tnt_local_x = tile_sample_x - tile_position(tnt_positions[index*`LP_TNT_ENTRY_BITS +: `LP_TNT_COORD_BITS], small_tiles);
            tnt_local_y = tile_sample_y - tile_position(tnt_positions[index*`LP_TNT_ENTRY_BITS+`LP_TNT_COORD_BITS +: `LP_TNT_COORD_BITS], small_tiles);
            if (index < tnt_count && tnt_intact[index] &&
                tile_contains(tnt_local_x, tile_size) && tile_contains(tnt_local_y, tile_size)) begin
                tnt_tile_hit = 1'b1;
                drawn_tnt_x = tnt_local_x[3:0];
                drawn_tnt_y = tnt_local_y[3:0];
            end
        end
        if (tnt_tile_hit) begin
            if (small_tiles) pixel_data = tnt_sprite(drawn_tnt_x, drawn_tnt_y, pixel_data);
            else pixel_data = tnt_sprite12(drawn_tnt_x, drawn_tnt_y, pixel_data);
        end
        // Vehicle: three cells of 12, 8, or 4 screen pixels, using existing sprites.
        if (overview_q) begin
            cell_px = 7'sd4;
            vehicle_screen_x = veh_x >>> 1;
            vehicle_screen_y = veh_y >>> 1;
        end else begin
            cell_px = zoomed_out_q ? 7'sd8 : 7'sd12;
            vehicle_screen_x = scaled(veh_x, zoomed_out_q) + (zoomed_out_q ? 15'sd0 : $signed({14'd0, veh_hx}));
            vehicle_screen_y = scaled(veh_y, zoomed_out_q) + (zoomed_out_q ? 15'sd0 : $signed({14'd0, veh_hy}));
        end
        rel_x = fx - vehicle_screen_x;
        rel_y = fy - vehicle_screen_y;
        // Inverse-map every destination pixel through the body's rotation.
        // Zero tilt retains the original sprite lookup exactly at every zoom.
        if (tilt_q != 0) begin
            if (rel_x >= -cell_px && rel_x < 4*cell_px &&
                rel_y >= -cell_px && rel_y < 4*cell_px) begin
                rotation_dx2=2*rel_x+1-3*cell_px;
                rotation_dy2=2*rel_y+1-3*cell_px;
                rotation_c=rotation_c_q; rotation_s=rotation_s_q;
                rotation_x_sum=rotation_c*rotation_dx2+rotation_s*rotation_dy2;
                rotation_y_sum=-rotation_s*rotation_dx2+rotation_c*rotation_dy2;
                // Half the three-cell span in Q9: 3 * cell_px * 256.
                rotation_centre = 768 * cell_px;
                rotated_x = rotation_x_sum + rotation_centre;
                rotated_y = rotation_y_sum + rotation_centre;
                rel_x = rotated_x >>> 9;
                rel_y = rotated_y >>> 9;
            end else begin rel_x=-1; rel_y=-1; end
        end
        if (rel_x >= 0 && rel_x < 3*cell_px && rel_y >= 0 && rel_y < 3*cell_px) begin
            cell_col = (rel_x >= 2*cell_px) ? 2'd2 : ((rel_x >= cell_px) ? 2'd1 : 2'd0);
            cell_row = (rel_y >= 2*cell_px) ? 2'd2 : ((rel_y >= cell_px) ? 2'd1 : 2'd0);
            cell_x = rel_x - cell_col*cell_px;
            cell_y = rel_y - cell_row*cell_px;
            cell_index = {cell_row, 1'b0} + cell_row + cell_col;
            part = build_grid >> (cell_index*3);
            // Overview cells are 4 pixels wide: sample the 8 by 8 sprites at every second pixel.
            if (overview_q) begin
                cell_x = cell_x << 1;
                cell_y = cell_y << 1;
            end
            part_anim = anim_phase;
            if (!USE_PIXEL_INDEX && game_state == `LP_RUN) begin
                if (part == `LP_PART_FAN)         part_anim = active_fans[cell_index] ? anim_phase : 1'b0;
                else if (part == `LP_PART_ENGINE) part_anim = engine_enabled ? anim_phase : 1'b0;
            end
            if (small_tiles) begin
                if (frame_intact_mask[cell_index]) pixel_data = part_sprite(`LP_PART_FRAME, cell_x, cell_y, 1'b0, pixel_data);
                if (intact_mask[cell_index]) begin
                    if (part == `LP_PART_FRAME)
                        pixel_data = tnt_sprite(cell_x, cell_y, pixel_data);
                    else
                        pixel_data = part_sprite_mounted(part, cell_x, cell_y, 8, build_facing_left[cell_index], build_facing_down[cell_index], frame_intact_mask, cell_index, part_anim, pixel_data);
                end
            end else begin
                if (frame_intact_mask[cell_index]) pixel_data = part_sprite12(`LP_PART_FRAME, cell_x, cell_y, 1'b0, pixel_data);
                if (intact_mask[cell_index]) begin
                    if (part == `LP_PART_FRAME)
                        pixel_data = tnt_sprite12(cell_x, cell_y, pixel_data);
                    else
                        pixel_data = part_sprite_mounted(part, cell_x, cell_y, 12, build_facing_left[cell_index], build_facing_down[cell_index], frame_intact_mask, cell_index, part_anim, pixel_data);
                end
            end
            // The burst plays over the cell after the balloon has gone.
            if (balloon_pop_mask[cell_index])
                pixel_data = balloon_pop_sprite(balloon_pop_phase, cell_x, cell_y, small_tiles ? 5'd8 : 5'd12, pixel_data);
            // Rocket exhaust flame and Fan wind streak particles during live RUN mode.
            if (!USE_PIXEL_INDEX && game_state == `LP_RUN && intact_mask[cell_index]) begin
                if (part == `LP_PART_BOOSTER && rocket_burn_mask[cell_index]) begin
                    if ((!build_facing_down[cell_index] && ((!build_facing_left[cell_index] && cell_x < 4'd3) || (build_facing_left[cell_index] && cell_x >= (small_tiles ? 4'd5 : 4'd9))) && cell_y >= 4'd2 && cell_y < (small_tiles ? 4'd6 : 4'd10)) ||
                        (build_facing_down[cell_index] && ((!build_facing_left[cell_index] && cell_y >= (small_tiles ? 4'd5 : 4'd9)) || (build_facing_left[cell_index] && cell_y < 4'd3)) && cell_x >= 4'd2 && cell_x < (small_tiles ? 4'd6 : 4'd10)))
                        pixel_data = (anim_phase ^ cell_x[0] ^ cell_y[0]) ? 16'hffe0 : 16'hfd20;
                end else if (part == `LP_PART_FAN && active_fans[cell_index]) begin
                    if (((cell_x + cell_y + {3'd0, anim_phase}) & 4'd3) == 4'd0 &&
                        (cell_x < 4'd2 || cell_x >= (small_tiles ? 4'd6 : 4'd10) || cell_y >= (small_tiles ? 4'd6 : 4'd10)))
                        pixel_data = 16'h9fff;
                end
            end
        end
        // High-fall debris: show a compact three-piece scatter burst while the
        // damaged cells leave the vehicle. This is deliberately a small sprite
        // overlay, not nine independent moving bodies. Compare in world pixels:
        // the existing wx/wy pipeline already accounts for 0.5x, 1x and 1.5x display sampling.
        scatter_local_x = 0; scatter_local_y = 0;
        if (scatter_phase != 0 && (|scatter_mask) && scatter_near) begin
            for (index = 0; index < 3; index = index + 1) begin
                case (index)
                    0: begin
                        scatter_local_x = scatter_offset_x[8:0] + $signed({3'd0, scatter_half});
                        scatter_local_y = scatter_offset_y[8:0] + $signed({3'd0, scatter_quarter});
                    end
                    1: begin
                        scatter_local_x = scatter_offset_x[8:0] - $signed({3'd0, scatter_half});
                        scatter_local_y = scatter_offset_y[8:0] - $signed({3'd0, scatter_quarter});
                    end
                    default: begin
                        scatter_local_x = scatter_offset_x[8:0];
                        scatter_local_y = scatter_offset_y[8:0] - $signed({3'd0, scatter_phase});
                    end
                endcase
                if (scatter_local_x >= 0 && scatter_local_x < 6 && scatter_local_y >= 0 && scatter_local_y < 6) begin
                    if (scatter_local_x == 0 || scatter_local_y == 0 || scatter_local_x == 5 || scatter_local_y == 5)
                        pixel_data = 16'h630c;
                    else if (index != 1)
                        pixel_data = 16'hfd20;
                    else
                        pixel_data = 16'hc618;
                end
            end
        end
        // Explosions grow over three phases: yellow flash, orange fireball, grey smoke.
        // The largest radius is 22 half-world units, so only pixels that close use the squares.
        blast_dx = 0; blast_dy = 0; blast_abs_x = 0; blast_abs_y = 0; blast_distance_sq = 0; blast_now = 0;
        drawn_blast_x = 5'd0; drawn_blast_y = 5'd0; drawn_blast_phase = 2'd0;
        for (index = 0; index < `LP_MAX_TNT; index = index + 1) begin
            blast_dx = tex_x - $signed({3'd0, tnt_positions[index*`LP_TNT_ENTRY_BITS +: `LP_TNT_COORD_BITS], 1'b0}) - 14'sd`LP_TNT_PIXELS;
            blast_dy = tex_y - $signed({3'd0, tnt_positions[index*`LP_TNT_ENTRY_BITS+`LP_TNT_COORD_BITS +: `LP_TNT_COORD_BITS], 1'b0}) - 14'sd`LP_TNT_PIXELS;
            blast_abs_x = magnitude(blast_dx);
            blast_abs_y = magnitude(blast_dy);
            blast_now = blast_phase[index*2 +: 2];
            if (index < tnt_count && blast_now != 2'd0 && blast_abs_x <= 14'd22 && blast_abs_y <= 14'd22) begin
                drawn_blast_x = blast_abs_x[4:0];
                drawn_blast_y = blast_abs_y[4:0];
                drawn_blast_phase = blast_now;
            end
        end
        blast_distance_sq = drawn_blast_x * drawn_blast_x + drawn_blast_y * drawn_blast_y;
        case (drawn_blast_phase)
            2'd1: if (blast_distance_sq <= 10'd100) pixel_data = 16'hffe0;
            2'd2: if (blast_distance_sq <= 10'd256) pixel_data = (blast_distance_sq <= 10'd36) ? 16'hffe0 : 16'hfd20;
            2'd3: if (blast_distance_sq <= 10'd484) pixel_data = 16'h8410;
            default: ;
        endcase
        if (launch_flash && game_state==`LP_RUN && !tutorial_active && px>=34 && px<62 && py<10) begin
            pixel_data=16'h04b4;
            if (banner_lit) pixel_data=16'hffff;
        end
        // Ending card: a midnight navy panel over the map, 80 by 48 and centred.
        // Clear shows the title, three stars and a pig; crash shows a dizzy pig.
        // The chip is nearly full, so each drawing helper is used only once and
        // its position is chosen first. Each call is its own copy of the logic.
        if (in_result_state && px >= 8 && px < 88 && py >= 8 && py < 56) begin
            if (px == 8 || px == 87 || py == 8 || py == 55) pixel_data = 16'h4a69; // Card edge
            else pixel_data = 16'h0869; // Midnight navy
            if (banner_lit) pixel_data = (game_state == `LP_SUCCESS) ? 16'hffe0 : 16'hf800;
            if (game_state == `LP_SUCCESS) begin
                // Three stars share one lookup: pick the star this column falls in.
                if (px >= 66) begin
                    card_star_x = px - 7'd66;
                    card_star_earned = (stars_earned == 2'd3);
                end else if (px >= 42) begin
                    card_star_x = px - 7'd42;
                    card_star_earned = (stars_earned >= 2'd2);
                end else begin
                    card_star_x = px - 7'd18;
                    card_star_earned = 1'b1;
                end
                if (px >= 18) pixel_data = gold_star12(card_star_earned ? 16'hfee0 : 16'h39e7, card_star_x, py - 20, pixel_data);
            end
            pixel_data = part_sprite16(`LP_PART_PIG, px - 40, py - card_pig_top, 1'b0, pixel_data);
            // Dizzy eyes: a small black and white check over each 2 by 2 eye.
            if (game_state == `LP_FAIL && (py == 34 || py == 35) &&
                (px == 44 || px == 45 || px == 50 || px == 51))
                pixel_data = ((px + py) & 1) ? 16'h0000 : 16'hffff;
        end
        // World-space pig burst stays visible after the pig's intact bit clears.
        if (death_phase != 0 && death_near) begin
            if (death_phase == 1 && death_distance <= 5'd4) pixel_data = 16'hffe0;
            else if (death_phase == 2 && death_distance <= 5'd7 &&
                     (death_abs_x == 0 || death_abs_y == 0 || death_abs_x == death_abs_y)) pixel_data = 16'hf800;
            else if (death_phase == 3 && death_distance >= 5'd7 && death_distance <= 5'd9 &&
                     (death_abs_x == 14'd6 || death_abs_y == 14'd6)) pixel_data = 16'hb800;
        end
        // The tutorial is an in-map coach: one compact hint at the top of the
        // world OLED changes as the vehicle reaches each short checkpoint.
        // It reuses the existing 5x7 font and does not add map storage.
        if (tutorial_coaching && py < 9) begin
            pixel_data = 16'h0869;
            if (banner_lit) pixel_data = tutorial_avoid_tnt ? 16'hf800 : 16'h07ff;
            if (retry_key_area) begin
                if (px == 7'd36 || px == 7'd46) pixel_data = 16'hffe0;
                else if (retry_arrow_lit($signed({1'b0, px}) - 8'sd41, $signed({1'b0, py}) - 8'sd4)) pixel_data = 16'hffff;
                else pixel_data = 16'h18e5;
            end
        end
        // Full-screen tutorial welcome. It intentionally sits after all map
        // drawing, so the player sees a clear welcome card rather than a
        // small banner over the construction map. The card is held by the
        // BUILD state and disappears when the existing start action launches
        // the run; it does not time out.
        if (tutorial_welcome) begin
            if (px == 0 || px == 95 || py == 0 || py == 63) pixel_data = 16'h07e0;
            else pixel_data = 16'h0869;
            if (banner_lit) begin
                if (py < 7'd20) pixel_data = 16'hffe0;
                else if (py < 7'd34) pixel_data = 16'h07ff;
                else pixel_data = 16'hffff;
            end
            if (welcome_key_area) pixel_data = board_button_pixel(px, WELCOME_KEY_LEFT, py[5:0], WELCOME_KEY_TOP);
        end
        if (px == 0 || px == 95 || py == 0 || py == 63) begin
            if (game_state == `LP_SUCCESS) pixel_data = 16'h07e0;
            else if (game_state == `LP_FAIL) pixel_data = 16'hf800;
        end
    end
endmodule
