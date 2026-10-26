// Owner: Role 1 - Kaushal; shared left-screen layout with Role 4 - Marcus.
`timescale 1ns / 1ps
`include "game_defs.vh"
module ui_renderer (
    input wire [12:0] pixel_index,
    input wire [15:0] base_pixel,
    input wire [2:0] game_state, feedback_code,
    input wire [1:0] diary_page, run_page,
    input wire [1:0] inventory_page,
    input wire selected_left, audio_muted,
    input wire [2:0] selected_part,
    input wire [2:0] master_volume,
    input wire [`LP_LEVEL_BITS-1:0] level_index,
    input wire build_valid, engine_enabled, boost_active,
    input wire fan_available, fan_on, rocket_available, rocket_ready,
    input wire [6:0] cursor_x, cursor_y,
    output reg [15:0] pixel_data
);
    `include "ui_font.vh"
    `include "part_sprites.vh"
    wire [6:0] x=pixel_index%96, y=pixel_index/96;
    reg [127:0] line;
    integer text_left, text_top, row, button_left, button_right;
    reg [1:0] tile;
    reg tile_hover;
    reg text_visible, button, enabled;
    reg [15:0] ink;
    always @* begin
        pixel_data=base_pixel; line="                ";
        text_left=0; text_top=0; row=0; button_left=0; button_right=0;
        text_visible=0; button=0; enabled=1; ink=16'hffff; tile=0; tile_hover=0;
        if (game_state==`LP_GUIDE) begin
            pixel_data=16'h0841;
            text_visible=1; text_left=2;
            if (y<9) begin row=0; text_top=1; ink=16'h07ff; end
            else if (y<18) begin row=1; text_top=10; end
            else if (y<27) begin row=2; text_top=19; end
            else if (y<36) begin row=3; text_top=28; end
            else if (y<45) begin row=4; text_top=37; end
            else begin row=5; text_top=46; end
            case (diary_page)
                0: case (row)
                    0: case (level_index)
                        0: line="DIARY L1 1/3    ";
                        1: line="DIARY L2 1/3    ";
                        2: line="DIARY L3 1/3    ";
                        default: line="DIARY L4 1/3    ";
                    endcase
                    1: line="GET PIG TO FLAG ";
                    2: line="DRAG PARTS IN   ";
                    3: line="CLICK SAME FLIPS";
                    4: line="DRIVE TAB POWERS";
                    5: line="U BACK C NEXT   ";
                endcase
                1: case (row)
                    0: line="PART RULES 2/3  ";
                    1: line="PIG/ENG FRAME   ";
                    2: line="WHEELS UP/DOWN  ";
                    3: line="BALLOONS ABOVE  ";
                    4: line="FAN/ROCKET SIDE ";
                    5: line="POP PAGE TO POP ";
                endcase
                2: case (row)
                    0: line="LEVEL HINT 3/3  ";
                    1: line=(level_index>=2) ? "MAP TEST ONLY   " : level_index ? "PROTECT ENGINE  " : "TRY MIDDLE ROW  ";
                    2: line=(level_index>=2) ? "PHYSICS PENDING " : level_index ? "TNT BREAKS PARTS" : "PIG IN CENTRE   ";
                    3: line=(level_index>=2) ? "WHEEL ZOOM      " : "ENGINE AT REAR  ";
                    4: line=(level_index>=2) ? "SW4 LOOK AROUND " : level_index ? "KEEP PIG SAFE   " : "WHEELS AT EDGES ";
                    5: line="RETRY RESTORES  ";
                endcase
                default: case (row)
                    0: line="AUDIO SETTINGS  ";
                    1: line="MASTER VOLUME   ";
                    2: case (master_volume)
                        0: line="     OFF        ";
                        1: line="     1/3        ";
                        2: line="     2/4        ";
                        3: line="     3/4        ";
                        default: line="     4/4        ";
                    endcase
                    3: line="                ";
                    4: line="                ";
                    5: line=audio_muted ? "MUTED BY SW1    " : "SW1 MUTES ALL   ";
                endcase
            endcase
        end
        // Compact BUILD toolbar keeps the full 48 by 48 construction grid.
        if (game_state==`LP_BUILD && y>=55) begin
            pixel_data=16'h0841; text_visible=1; text_top=56;
            if (x<18) begin
                button=1; button_left=0; button_right=17; text_left=2;
                line="GO              "; enabled=build_valid;
            end else if (x>=64 && x<80) begin
                button=1; button_left=64; button_right=79; text_left=69; line="?               ";
            end else if (x>=20 && x<62) begin
                button=1; button_left=x<34 ? 20 : x<48 ? 34 : 48;
                button_right=button_left+13; text_left=button_left+4;
                line=x<34 ? "1               " : x<48 ? "2               " : "3               ";
                if (inventory_page==(x<34 ? 0 : x<48 ? 1 : 2)) ink=16'hffe0;
            end else begin pixel_data=base_pixel; text_visible=0; end
        end
        if ((game_state==`LP_GUIDE || game_state==`LP_SUCCESS || game_state==`LP_FAIL) && y>=55) begin
            pixel_data=16'h0841; text_visible=0; text_top=56;
            if (x<28) begin
                button=1; button_left=0; button_right=27; text_left=2;
                line=game_state==`LP_GUIDE ? "BACK            " : "TRY             ";
            end else if (x>=32 && x<60) begin
                button=1; button_left=32; button_right=59; text_left=34;
                line=game_state==`LP_GUIDE ? "1               " : (game_state==`LP_SUCCESS ? "NEXT            " : "EDIT            ");
                enabled=game_state!=`LP_GUIDE || diary_page>0;
            end else if (x>=64) begin
                button=1; button_left=64; button_right=95; text_left=65;
                line=game_state==`LP_GUIDE ? "NEXT            " : "DIARY           ";
                enabled=game_state!=`LP_GUIDE || diary_page<3;
            end
        end
        if (game_state==`LP_GUIDE && y>=55 && x>=32) begin
            button=diary_page!=3; text_visible=0; pixel_data=16'h0841;
            if (diary_page!=3 && x<95) begin
                button_left=x<53 ? 32 : x<74 ? 53 : 74; button_right=button_left+20;
                text_left=button_left+8; text_top=56;
                line=x<53 ? "1               " : x<74 ? "2               " : "3               ";
                enabled=1; if (diary_page==(x<53 ? 0 : x<74 ? 1 : 2)) ink=16'hffe0;
            end
        end
        if (game_state==`LP_GUIDE && diary_page==3 && y>=28 && y<44) begin
            if ((x>=8 && x<36) || (x>=60 && x<88)) begin
                button=1; button_left=x<48 ? 8 : 60; button_right=button_left+27;
                text_left=button_left+11; text_top=32;
                line=x<48 ? "-               " : "+               ";
                enabled=x<48 ? master_volume>0 : master_volume<4;
            end
        end
        if (button) begin
            pixel_data=enabled ? 16'h18e5 : 16'h18c3;
            if (enabled && cursor_x>=button_left && cursor_x<=button_right &&
                cursor_y>=text_top-3 && cursor_y<text_top+11) pixel_data=16'h0351;
            if (x==button_left || x==button_right || (text_top==32 ? (y==28 || y==43) : (y==text_top-1 || y==text_top+7)))
                pixel_data=enabled ? 16'h04b4 : 16'h4208;
            if (!enabled) ink=16'h7bef;
            text_visible=1;
        end
        if (text_visible && text_on(line,text_left,text_top,x,y)) pixel_data=ink;
        // Book cover with a question mark, and a compact gear for settings.
        if (game_state==`LP_BUILD && y>=55 && x>=64) begin
            pixel_data=16'h18e5;
            if (x<80) begin
                if (x==65 || x==78 || y==55 || y==63 || x==67) pixel_data=16'h04b4;
                if (text_on("?               ",70,56,x,y)) pixel_data=16'hffff;
            end else begin
                if (((x>=85 && x<=90) && (y==55 || y==63)) ||
                    ((y>=57 && y<=61) && (x==83 || x==92)) ||
                    ((x==85 || x==90) && (y==57 || y==61)) ||
                    ((x==86 || x==89) && y>=58 && y<=60)) pixel_data=16'hffff;
            end
        end
        // Transient placement feedback temporarily uses the toolbar's full width.
        if (game_state==`LP_BUILD && feedback_code!=`LP_FEEDBACK_NONE && y>=55)
            pixel_data=base_pixel;
        if (game_state==`LP_SETTINGS) begin
            pixel_data=16'h0841;
            if (text_on("SETTINGS        ",24,2,x,y)) pixel_data=16'h07ff;
            if (x>=8 && x<88 && ((y>=12 && y<26) || (y>=30 && y<44))) begin
                pixel_data=16'h18e5;
                if (x==8 || x==87 || y==12 || y==25 || y==30 || y==43) pixel_data=16'h04b4;
                if (text_on(y<26 ? "AUDIO           " : "MAP SELECTION   ",10,y<26 ? 16 : 34,x,y)) pixel_data=16'hffff;
            end
            if (x<28 && y>=55) begin
                pixel_data=16'h18e5;
                if (text_on("BACK            ",2,56,x,y)) pixel_data=16'hffff;
            end
        end
        if (game_state==`LP_LEVEL_SELECT) begin
            pixel_data=16'h0841;
            if (text_on("SELECT LEVEL    ",12,2,x,y)) pixel_data=16'h07ff;
            // Two columns, two rows. The selected map has a green outline.
            if (((x>=2 && x<46) || (x>=50 && x<94)) &&
                ((y>=12 && y<32) || (y>=34 && y<54))) begin
                tile={y>=34,x>=50};
                button_left=tile[0] ? 50 : 2; button_right=button_left+43;
                text_top=tile[1] ? 34 : 12;
                tile_hover=cursor_x>=button_left && cursor_x<=button_right &&
                           cursor_y>=text_top && cursor_y<text_top+20;
                pixel_data=tile_hover ? 16'h0351 : 16'h18e5;
                if (x==button_left || x==button_right || y==text_top || y==text_top+19)
                    pixel_data=(tile==level_index) ? 16'h07e0 : (tile>=2 ? 16'hfd20 : 16'h04b4);
                case (tile)
                    0: line="TRACK           ";
                    1: line="TNT PIT         ";
                    2: line="ARCH            ";
                    3: line="FLIGHT          ";
                endcase
                if (text_on(line,button_left+1,text_top+2,x,y)) pixel_data=16'hffff;
                case (tile)
                    0: line="1               ";
                    1: line="2               ";
                    2: line="3 WIP           ";
                    3: line="4 WIP           ";
                endcase
                if (text_on(line,button_left+1,text_top+11,x,y)) pixel_data=tile>=2 ? 16'hfd20 : 16'h07ff;
            end
            if (y>=55) begin
                if (x<28) begin
                    pixel_data=16'h18e5;
                    if (x==0 || x==27 || y==55 || y==63) pixel_data=16'h04b4;
                    if (text_on("BACK            ",2,56,x,y)) pixel_data=16'hffff;
                end else if (text_on("PICK A MAP      ",32,56,x,y)) pixel_data=16'h7bef;
            end
        end
        // RUN uses three large menu pages; only POP retains the vehicle diagram.
        if (game_state==`LP_RUN) begin
            pixel_data=(run_page==1 && x<54 && y<55) ? base_pixel : 16'h0841;
            button=0; text_visible=0; enabled=1; ink=16'hffff; text_left=2; text_top=1;
            if (run_page==1) begin
                if (text_on("POP             ",2,1,x,y)) pixel_data=16'h07ff;
                if (x>=56 && x<84 && y>=14 && y<24) begin
                    button=1; button_left=56; button_right=83; text_top=15; text_left=58; line="EDIT            ";
                end
            end else begin
                if (text_on(run_page==0 ? "DRIVE           " : "SOUND           ",2,1,x,y)) pixel_data=16'h07ff;
                if (x>=40 && x<66 && y<10) begin
                    button=1; button_left=40; button_right=65; text_top=1; text_left=42; line="EDIT            ";
                end
            end
            if (run_page==0 && x>=4 && x<92 && y>=12 && y<54) begin
                button_left=4; button_right=91; text_left=8;
                if (y<22) begin button=1; text_top=13; line=engine_enabled ? "ENGINE ON       " : "ENGINE OFF      "; end
                else if (y>=23 && y<33) begin
                    button=1; text_top=24; enabled=fan_available;
                    line=fan_available ? (fan_on ? "FAN ON          " : "FAN OFF         ") : "FAN WAIT        ";
                end else if (y>=34 && y<44) begin
                    button=1; text_top=35; line=boost_active ? "BOOST ON        " : "BOOST           ";
                end else if (y>=45) begin
                    button=1; text_top=46; enabled=rocket_available && rocket_ready;
                    line=enabled ? "ROCKET FIRE     " : "ROCKET WAIT     ";
                end
            end
            if (run_page==2) begin
                if (text_on("MASTER VOLUME   ",2,10,x,y)) pixel_data=16'hffff;
                if (y>=19 && y<26) begin
                    case (master_volume)
                        0: line="     OFF        "; 1: line="     1/3        ";
                        2: line="     2/4        "; 3: line="     3/4        "; default: line="     4/4        ";
                    endcase
                    if (text_on(line,2,19,x,y)) pixel_data=16'hffff;
                end
                if (y>=46 && y<54) begin
                    button=1; button_left=4; button_right=91; text_top=47; text_left=34;
                    line=audio_muted ? "MUTED           " : "MUTE            ";
                end
                if (y>=28 && y<44 && ((x>=8 && x<36) || (x>=60 && x<88))) begin
                    button=1; button_left=x<48 ? 8 : 60; button_right=button_left+27;
                    text_top=32; text_left=button_left+11; line=x<48 ? "-               " : "+               ";
                    enabled=x<48 ? master_volume>0 : master_volume<4;
                end
            end
            if (y>=55) begin
                button=1; button_left=x<32 ? 0 : x<64 ? 32 : 64; button_right=button_left+31;
                text_top=56; text_visible=0;
            end
            if (button) begin
                pixel_data=enabled ? 16'h18e5 : 16'h18c3;
                if (enabled && cursor_x>=button_left && cursor_x<=button_right &&
                    cursor_y>=text_top-1 && cursor_y<text_top+8) pixel_data=16'h0351;
                if (x==button_left || x==button_right || (text_top==32 ? (y==28 || y==43) : (y==text_top-1 || y==text_top+7)))
                    pixel_data=enabled ? 16'h04b4 : 16'h4208;
                if (text_on(line,text_left,text_top,x,y)) pixel_data=enabled ? ink : 16'h7bef;
            end
            // A labelled retry button is visible on every RUN page.
            if (x>=66 && x<96 && y<10) begin
                pixel_data=16'h18e5;
                if (x==66 || x==95 || y==0 || y==9) pixel_data=16'h04b4;
                if (text_on("RETRY           ",68,1,x,y)) pixel_data=16'hffff;
            end
            // Icon-only page tabs: engine for DRIVE, balloon for POP and speaker for SOUND.
            if (y>=55) begin
                pixel_data=16'h18e5;
                if (x==0 || x==31 || x==32 || x==63 || x==64 || x==95 || y==55 || y==63) pixel_data=16'h04b4;
                if ((run_page==0 && x<32) || (run_page==1 && x>=32 && x<64) || (run_page==2 && x>=64)) begin
                    if (y==56 || y==62) pixel_data=16'hffe0;
                end
                // Engine: body, nose and small exhaust.
                if (x>=10 && x<=20 && y>=57 && y<=61 && (x<=18 || y==59)) pixel_data=(run_page==0) ? 16'hffe0 : 16'hffff;
                if (x==8 && y>=58 && y<=60) pixel_data=(run_page==0) ? 16'hffe0 : 16'hffff;
                // Balloon: round top with a string.
                if (x>=43 && x<=53 && y>=56 && y<=61 && ((x-48)*(x-48)+(y-58)*(y-58)<=16)) pixel_data=(run_page==1) ? 16'hffe0 : 16'hffff;
                if (x==48 && y==62) pixel_data=(run_page==1) ? 16'hffe0 : 16'hffff;
                // Speaker: cone and two sound marks.
                if ((x>=74 && x<=78 && y>=58 && y<=60) || (x==79 && y==57) || (x==79 && y==61) || (x==80 && y>=56 && y<=62) || (x==82 && (y==57 || y==61))) pixel_data=(run_page==2) ? 16'hffe0 : 16'hffff;
            end
        end
        // The pointer is also visible on diary/result controls.
        if ((x==cursor_x && y+2>=cursor_y && y<=cursor_y+2) ||
            (y==cursor_y && x+2>=cursor_x && x<=cursor_x+2)) pixel_data=16'hffff;
    end
endmodule
